//! The log, and the two properties it exists to guarantee.
//!
//! 1. **An op is never applied before the one it follows.** That is the
//!    hold buffer, and `core-decisions.md` says build it whatever the
//!    transport turns out to be — because it is fifty lines, and it stops
//!    the transport choice from being load-bearing.
//! 2. **A torn tail is expected, not exceptional.** A sync file being
//!    appended to by another device, or copied mid-write, ends in a
//!    partial group. Everything before it stands.

use liv_engine::log::{decode_stream, encode_stream};
use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

fn ent(n: u8) -> EntityId {
    EntityId([n; 16])
}

/// A group of `ops` ops, starting at `first_seq`.
fn group(device: u8, first_seq: u64, ops: usize) -> Group {
    Group {
        device: dev(device),
        first_seq,
        hlc: Hlc { wall_ms: 1_787_391_635_000 + first_seq, ctr: 0 },
        author: Author::User,
        action: 1,
        reverses: None,
        ops: (0..ops).map(|i| Op::CreateEntity { entity: ent(i as u8 + 1) }).collect(),
    }
}

#[test]
fn a_fresh_box_knows_it_holds_nothing() {
    let log = Engine::open_in_memory(dev(1)).unwrap();
    assert_eq!(log.next_seq(dev(1)).unwrap(), 0);
    assert!(log.version_vector().unwrap().is_empty());
    assert_eq!(log.group_count().unwrap(), 0);
}

#[test]
fn appending_advances_the_version_vector() {
    let mut log = Engine::open_in_memory(dev(1)).unwrap();
    log.receive(group(1, 0, 3)).unwrap();
    log.receive(group(1, 3, 2)).unwrap();
    log.receive(group(2, 0, 1)).unwrap();

    assert_eq!(log.next_seq(dev(1)).unwrap(), 5, "three ops then two");
    assert_eq!(log.next_seq(dev(2)).unwrap(), 1);
    let vv = log.version_vector().unwrap();
    assert_eq!(vv.len(), 2, "one entry per device that has written");
    assert_eq!(vv[&dev(1)], 5);
    assert_eq!(vv[&dev(2)], 1);
}

#[test]
fn a_group_survives_the_round_trip_through_storage() {
    let mut log = Engine::open_in_memory(dev(1)).unwrap();
    let g = group(1, 0, 4);
    log.receive(g.clone()).unwrap();
    let back = log.range(dev(1), 0).unwrap();
    assert_eq!(back, vec![g], "what came out is what went in");
}

#[test]
fn out_of_order_arrivals_wait_for_the_gap_to_fill() {
    // The whole point of the hold buffer. Ops 3 and 5 arrive before op 0,
    // and nothing may be applied until the run is contiguous.
    let mut log = Engine::open_in_memory(dev(1)).unwrap();

    let landed = log.receive(group(1, 3, 2)).unwrap();
    assert!(landed.is_empty(), "a group past the gap must not land");
    assert_eq!(log.held(), 1);

    let landed = log.receive(group(1, 5, 1)).unwrap();
    assert!(landed.is_empty(), "nor the one after it");
    assert_eq!(log.held(), 2);
    assert_eq!(log.group_count().unwrap(), 0, "nothing has been written yet");

    // The arrival that fills the gap releases everything behind it.
    let landed = log.receive(group(1, 0, 3)).unwrap();
    assert_eq!(landed.len(), 3, "the filling group plus both held ones");
    assert_eq!(landed[0].first_seq, 0);
    assert_eq!(landed[1].first_seq, 3);
    assert_eq!(landed[2].first_seq, 5);
    assert_eq!(log.held(), 0, "the buffer is empty again");
    assert_eq!(log.next_seq(dev(1)).unwrap(), 6);
}

#[test]
fn one_device_waiting_does_not_hold_up_another() {
    let mut log = Engine::open_in_memory(dev(1)).unwrap();
    log.receive(group(1, 9, 1)).unwrap(); // held, waiting for a gap
    let landed = log.receive(group(2, 0, 1)).unwrap();
    assert_eq!(landed.len(), 1, "device 2 is not behind device 1's gap");
    assert_eq!(log.held(), 1);
}

#[test]
fn receiving_the_same_group_twice_is_a_no_op() {
    // Sync re-sending a range it already sent is normal, not an error.
    let mut log = Engine::open_in_memory(dev(1)).unwrap();
    assert_eq!(log.receive(group(1, 0, 2)).unwrap().len(), 1);
    assert_eq!(log.receive(group(1, 0, 2)).unwrap().len(), 0, "already held");
    assert_eq!(log.group_count().unwrap(), 1, "and it was not written twice");
    assert_eq!(log.next_seq(dev(1)).unwrap(), 2);
}

#[test]
fn the_log_reads_back_in_causal_order_not_arrival_order() {
    // A note written on a train and synced a week later belongs where it
    // was WRITTEN, or two devices disagree about the user's own past.
    let mut log = Engine::open_in_memory(dev(1)).unwrap();
    let mut early = group(2, 0, 1);
    early.hlc = Hlc { wall_ms: 1_000, ctr: 0 };
    let mut late = group(1, 0, 1);
    late.hlc = Hlc { wall_ms: 9_000, ctr: 0 };

    log.receive(late.clone()).unwrap(); // arrives first
    log.receive(early.clone()).unwrap(); // written first

    let all = log.groups().unwrap();
    assert_eq!(all[0].hlc.wall_ms, 1_000, "the earlier write comes first");
    assert_eq!(all[1].hlc.wall_ms, 9_000);
}

#[test]
fn a_box_from_a_newer_build_is_refused_whole() {
    let dir = std::env::temp_dir().join("liv_engine_newer_box");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.db");

    {
        let log = Engine::open(&path, dev(1)).unwrap();
        drop(log);
    }
    // Forge a box written by a build from the future.
    let c = rusqlite::Connection::open(&path).unwrap();
    c.execute("UPDATE meta SET value = ?1 WHERE key = 'box_format'", [(BOX_FORMAT + 1).to_string()])
        .unwrap();
    drop(c);

    match Engine::open(&path, dev(1)) {
        Err(LogError::UnsupportedBox { found, supported }) => {
            assert_eq!(found, BOX_FORMAT + 1);
            assert_eq!(supported, BOX_FORMAT);
        }
        Err(e) => panic!("wrong error for a newer box: {e}"),
        Ok(_) => panic!("a box from a newer build must be refused, not opened"),
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_stream_with_a_torn_tail_yields_everything_whole() {
    // What a sync file looks like while another device is appending to it.
    let groups = vec![group(1, 0, 2), group(1, 2, 1), group(1, 3, 3)];
    let bytes = encode_stream(&groups);

    let (back, used) = decode_stream(&bytes);
    assert_eq!(back, groups, "a whole file reads back whole");
    assert_eq!(used, bytes.len());

    // Now cut it anywhere at all. Whatever survives must be a prefix of
    // the original, and the byte count must land on a group boundary so
    // the caller can resume there.
    for cut in 0..bytes.len() {
        let (part, used) = decode_stream(&bytes[..cut]);
        assert!(part.len() <= groups.len());
        assert_eq!(part[..], groups[..part.len()], "a torn file yields a prefix, never a mangle");
        assert_eq!(encode_stream(&part).len(), used, "the used count is a group boundary");
    }
}

#[test]
fn a_corrupted_group_stops_the_stream_where_it_starts() {
    let groups = vec![group(1, 0, 1), group(1, 1, 1), group(1, 2, 1)];
    let mut bytes = encode_stream(&groups);
    let first = liv_engine::op::encode(&groups[0]).len();
    let second = liv_engine::op::encode(&groups[1]).len();
    // Flip a bit inside the second group's body.
    bytes[first + second / 2] ^= 0x40;

    let (back, used) = decode_stream(&bytes);
    assert_eq!(back, groups[..1], "everything before the damage stands");
    assert_eq!(used, first, "and the caller is told exactly where it stopped");
}

#[test]
fn a_box_reopens_with_what_it_held() {
    let dir = std::env::temp_dir().join("liv_engine_reopen");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.db");

    {
        let mut log = Engine::open(&path, dev(1)).unwrap();
        log.receive(group(1, 0, 2)).unwrap();
        log.receive(group(1, 2, 1)).unwrap();
    }
    let log = Engine::open(&path, dev(1)).unwrap();
    assert_eq!(log.next_seq(dev(1)).unwrap(), 3);
    assert_eq!(log.groups().unwrap().len(), 2);
    let _ = std::fs::remove_dir_all(&dir);
}
