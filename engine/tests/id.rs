//! Identity, and the one property twenty-one call sites depend on.
//!
//! `design/core-decisions.md` chose UUIDv7 over v4 for one reason: id
//! order must remain creation order, because fourteen Rust sites and
//! seven desktop `ORDER BY id` tiebreaks already assume it. That decision
//! is only worth anything if the generator is actually monotonic, and the
//! decision record says so explicitly — *verify before committing*. This
//! is that verification.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

#[test]
fn ids_minted_in_one_millisecond_still_sort_in_order() {
    // The hard case: far more ids in a single millisecond than the 12
    // bits v7 reserves beside the timestamp. A bulk import does this.
    let mut g = IdGen::new(dev(1));
    let mut last = EntityId::NONE;
    for i in 0..10_000 {
        let id = g.mint(1_787_391_635_000);
        assert!(
            id > last,
            "id {i} minted in the same millisecond did not sort after the one before it"
        );
        last = id;
    }
}

#[test]
fn ids_sort_in_order_across_milliseconds() {
    let mut g = IdGen::new(dev(1));
    let mut last = EntityId::NONE;
    for ms in 0..2_000u64 {
        for _ in 0..3 {
            let id = g.mint(1_787_391_635_000 + ms);
            assert!(id > last, "ids stopped sorting at ms {ms}");
            last = id;
        }
    }
}

#[test]
fn a_clock_that_jumps_backwards_cannot_reorder_the_past() {
    // Phones do this — a time-zone change, an NTP correction. An id
    // minted after another must never sort before it, whatever the clock
    // says.
    let mut g = IdGen::new(dev(1));
    let first = g.mint(1_787_391_635_000);
    let after_jump = g.mint(1_000_000_000_000);
    assert!(
        after_jump > first,
        "a backwards clock produced an id that sorts before one minted earlier"
    );
}

#[test]
fn two_devices_never_mint_the_same_id() {
    // The generator is seeded from the device rather than from the
    // operating system — that is what keeps this crate free of a
    // randomness dependency — so this is the property that has to hold.
    use std::collections::HashSet;
    let mut seen: HashSet<EntityId> = HashSet::new();
    for d in 0..8u8 {
        let mut g = IdGen::new(dev(d));
        for i in 0..5_000 {
            let id = g.mint(1_787_391_635_000 + (i % 7));
            assert!(seen.insert(id), "device {d} minted an id another device already had");
        }
    }
}

#[test]
fn the_timestamp_reads_back_out_of_the_id() {
    // v7's whole point: created-at without a lookup.
    let mut g = IdGen::new(dev(1));
    let ms = 1_787_391_635_123;
    assert_eq!(g.mint(ms).millis(), ms);
}

#[test]
fn the_layout_is_a_real_uuid_v7() {
    // Version 7 in the high nibble of byte 6, RFC 4122 variant in the top
    // two bits of byte 8. Anything reading these as UUIDs has to agree.
    let mut g = IdGen::new(dev(3));
    for _ in 0..1_000 {
        let id = g.mint(1_787_391_635_000);
        assert_eq!(id.0[6] >> 4, 0x7, "version nibble");
        assert_eq!(id.0[8] >> 6, 0b10, "variant bits");
    }
}

#[test]
fn hex_round_trips() {
    let mut g = IdGen::new(dev(5));
    let id = g.mint(1_787_391_635_000);
    assert_eq!(EntityId::from_hex(&id.hex()), Some(id));
    assert_eq!(id.hex().len(), 32);
    assert_eq!(EntityId::from_hex("nope"), None);
    assert_eq!(EntityId::from_hex(&"z".repeat(32)), None);
}

#[test]
fn the_clock_stamp_never_goes_backwards() {
    let mut g = IdGen::new(dev(1));
    let a = g.stamp(1_787_391_635_000);
    let b = g.stamp(1_000_000_000_000);
    assert!(b >= a, "a hybrid clock reading went backwards when the wall clock did");
}
