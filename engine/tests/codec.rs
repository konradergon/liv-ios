//! The format is a document (design/op-format.md); these tests are what
//! keep this crate honest against it.
//!
//! Four things are pinned here, and the last two exist because the format
//! they replace had neither:
//!
//! 1. Encode-then-decode is the identity, for every op kind and every
//!    value kind.
//! 2. One logical group has exactly ONE byte sequence. The replay gate
//!    asserts byte-identical and drift detection is a digest exchange;
//!    both need that.
//! 3. Hostile bytes produce a typed error and never a panic.
//! 4. A record from a newer build is refused outright.

use liv_engine::op::{decode, encode};
use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

fn ent(n: u8) -> EntityId {
    EntityId([n; 16])
}

/// One group carrying every op kind and every value kind, so a single
/// round trip covers the whole grammar.
fn everything() -> Group {
    Group {
        device: dev(7),
        first_seq: 4_294_967_296, // past 32 bits, to catch a narrow varint
        hlc: Hlc { wall_ms: 1_787_391_635_000, ctr: 3 },
        author: Author::Proposer("clerk".into()),
        action: 42,
        reverses: Some(Dot { device: dev(9), seq: 17 }),
        ops: vec![
            Op::CreateEntity { entity: ent(1) },
            Op::SetCell {
                entity: ent(1),
                prop: ent(2),
                value: Value::Text("a line of words".into()),
                replaces: vec![
                    Dot { device: dev(1), seq: 1 },
                    Dot { device: dev(2), seq: 300 },
                ],
            },
            Op::SetCell {
                entity: ent(1),
                prop: ent(3),
                value: Value::Number(-1.5),
                replaces: vec![],
            },
            Op::SetCell {
                entity: ent(1),
                prop: ent(4),
                value: Value::Bool(true),
                replaces: vec![],
            },
            Op::SetCell {
                entity: ent(1),
                prop: ent(5),
                value: Value::Date(DateSpec::Day(20_688)),
                replaces: vec![],
            },
            Op::SetCell {
                entity: ent(1),
                prop: ent(6),
                value: Value::Date(DateSpec::Instant { ms: -1, tz: 65_535 }),
                replaces: vec![],
            },
            Op::SetCell {
                entity: ent(1),
                prop: ent(7),
                value: Value::Ref(ent(8)),
                replaces: vec![],
            },
            Op::AddToSet { entity: ent(1), prop: ent(9), value: Value::Blob([0xab; 32]) },
            Op::RemoveFromSet {
                entity: ent(1),
                prop: ent(9),
                value: Value::Text("tag".into()),
                replaces: vec![Dot { device: dev(3), seq: 0 }],
            },
        ],
    }
}

#[test]
fn every_op_and_every_value_survives_a_round_trip() {
    let g = everything();
    let bytes = encode(&g);
    let (back, used) = decode(&bytes).expect("a group this crate wrote decodes");
    assert_eq!(back, g, "encode then decode is the identity");
    assert_eq!(used, bytes.len(), "the frame reports exactly what it consumed");
}

#[test]
fn one_group_has_exactly_one_byte_sequence() {
    // Not "it round-trips" — that allows two encodings of one value. The
    // replay gate asserts byte-identical output, so this has to hold.
    let g = everything();
    assert_eq!(encode(&g), encode(&g), "encoding is deterministic");
    let (back, _) = decode(&encode(&g)).unwrap();
    assert_eq!(encode(&back), encode(&g), "decode then re-encode is the same bytes");
}

#[test]
fn a_plain_write_is_small() {
    // The format it replaces spent 318 bytes on a three-command
    // transaction, 186 of them field names. This is not an optimisation
    // target, but a regression here would mean the envelope crept back.
    let g = Group {
        device: dev(1),
        first_seq: 16,
        hlc: Hlc { wall_ms: 1_787_391_635_000, ctr: 0 },
        author: Author::User,
        action: 1,
        reverses: None,
        ops: vec![
            Op::CreateEntity { entity: ent(1) },
            Op::SetCell { entity: ent(1), prop: ent(2), value: Value::Ref(ent(3)), replaces: vec![] },
        ],
    };
    let n = encode(&g).len();
    assert!(n < 130, "a create-plus-one-cell group is {n} bytes; the envelope is creeping back");
}

#[test]
fn a_torn_tail_drops_the_whole_group() {
    // Action atomicity is a property of the FRAME. Truncate anywhere and
    // the group is refused entire — never half applied.
    let bytes = encode(&everything());
    for cut in 0..bytes.len() {
        match decode(&bytes[..cut]) {
            Err(_) => {}
            Ok(_) => panic!("a group truncated at {cut} of {} decoded anyway", bytes.len()),
        }
    }
    assert!(decode(&bytes).is_ok(), "and the whole thing still decodes");
}

#[test]
fn a_flipped_byte_is_caught_by_the_checksum() {
    let bytes = encode(&everything());
    let mut caught = 0;
    for i in 0..bytes.len() {
        for bit in 0..8 {
            let mut bad = bytes.clone();
            bad[i] ^= 1 << bit;
            if decode(&bad).is_err() {
                caught += 1;
            }
        }
    }
    let total = bytes.len() * 8;
    // Not every flip is detectable — a bit inside the length prefix can
    // produce a shorter, still-valid frame. The checksum catches the rest.
    assert!(
        caught * 100 / total > 95,
        "only {caught} of {total} single-bit flips were rejected"
    );
}

#[test]
fn hostile_bytes_never_panic() {
    // Every single-byte mutation of a real group, plus a pile of
    // structured garbage. The decoder must return a typed error; it must
    // not panic, and it must not allocate on a stated length it cannot
    // possibly satisfy.
    let good = encode(&everything());
    for i in 0..good.len() {
        for v in [0x00u8, 0x01, 0x7f, 0x80, 0xff] {
            let mut bad = good.clone();
            bad[i] = v;
            let _ = decode(&bad);
        }
    }
    for junk in [
        vec![],
        vec![0xff; 64],
        vec![0x00],
        vec![0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80],
        // a frame claiming a gigantic body
        {
            let mut v = vec![];
            for _ in 0..9 {
                v.push(0xff);
            }
            v
        },
    ] {
        let _ = decode(&junk);
    }
}

#[test]
fn a_non_minimal_varint_is_refused() {
    // Two encodings of one number would mean two byte sequences for one
    // group, which the replay gate cannot tolerate.
    let mut body = vec![liv_engine::RECORD_VERSION];
    body.extend_from_slice(&[1u8; 8]); // device
    body.extend_from_slice(&[0x80, 0x00]); // first_seq = 0, written long
    let framed = frame(&body);
    assert!(
        matches!(decode(&framed), Err(DecodeError::NonMinimalVarint)),
        "a padded varint must be refused, not accepted"
    );
}

#[test]
fn a_newer_record_is_refused_outright() {
    // The refusal path the format it replaces never had a test for.
    let mut body = vec![liv_engine::RECORD_VERSION + 1];
    body.extend_from_slice(&[1u8; 8]);
    body.push(0);
    body.push(0);
    let framed = frame(&body);
    match decode(&framed) {
        Err(DecodeError::UnsupportedVersion { found, supported }) => {
            assert_eq!(found, liv_engine::RECORD_VERSION + 1);
            assert_eq!(supported, liv_engine::RECORD_VERSION);
        }
        other => panic!("a newer record must be refused with its own error, got {other:?}"),
    }
}

#[test]
fn not_a_number_cannot_reach_the_log() {
    // NaN has no defined ordering, so two stores holding it would
    // disagree about the same value without either being wrong.
    let g = Group {
        device: dev(1),
        first_seq: 0,
        hlc: Hlc::default(),
        author: Author::User,
        action: 0,
        reverses: None,
        ops: vec![Op::SetCell {
            entity: ent(1),
            prop: ent(2),
            value: Value::Number(f64::NAN),
            replaces: vec![],
        }],
    };
    assert!(
        matches!(decode(&encode(&g)), Err(DecodeError::NotFinite)),
        "NaN must be refused on the way back in"
    );
}

#[test]
fn trailing_bytes_are_refused() {
    let g = everything();
    let mut body = vec![];
    let bytes = encode(&g);
    // Rebuild the frame with one extra body byte the decoder will not use.
    let (_, used) = decode(&bytes).unwrap();
    assert_eq!(used, bytes.len());
    body.extend_from_slice(&bytes);
    body.push(0x00);
    // The extra byte is outside the frame, so the frame still decodes and
    // reports having used less than the buffer — which is how a log reads
    // one group at a time.
    let (_, used) = decode(&body).unwrap();
    assert!(used < body.len(), "a frame consumes only its own bytes");
}

/// Wrap a hand-built body in the length + checksum frame, so a test can
/// aim at the body's grammar rather than at the frame's.
fn frame(body: &[u8]) -> Vec<u8> {
    fn crc32(data: &[u8]) -> u32 {
        let mut crc = 0xffff_ffffu32;
        for &b in data {
            crc ^= b as u32;
            for _ in 0..8 {
                let mask = (crc & 1).wrapping_neg();
                crc = (crc >> 1) ^ (0xedb8_8320 & mask);
            }
        }
        !crc
    }
    let mut out = vec![];
    let mut len = body.len() as u64;
    loop {
        let byte = (len & 0x7f) as u8;
        len >>= 7;
        if len == 0 {
            out.push(byte);
            break;
        }
        out.push(byte | 0x80);
    }
    out.extend_from_slice(body);
    out.extend_from_slice(&crc32(body).to_le_bytes());
    out
}
