//! Civil dates — the day arithmetic every date the engine shows or parses
//! rides on (`inspect.rs`, `value.rs`, surface's search and clerk).
//!
//! Moved here from `convert/tests/convert.rs` (2026-09-29) when stage 5 of
//! `design/rust-owns-the-mechanisms.md` set `convert/` for deletion: the
//! functions are the engine's, and `engine/src/civil.rs` had no test of
//! its own.

use liv_engine::{civil_from_days, days_from_civil};

#[test]
fn the_civil_arithmetic_is_exact_across_the_awkward_dates() {
    // Hinnant's algorithm, checked at the places a hand-rolled one breaks.
    for (y, m, d, days) in [
        (1970, 1, 1, 0),
        (1970, 1, 2, 1),
        (1969, 12, 31, -1),
        (2000, 2, 29, 11_016), // a leap year that IS one, being /400
        (1900, 3, 1, -25_508), // the year after one that is NOT, being /100
        (2026, 9, 13, 20_709),
        (2100, 3, 1, 47_541), // the next /100 non-leap
    ] {
        assert_eq!(days_from_civil(y, m, d), days, "{y}-{m}-{d}");
        assert_eq!(civil_from_days(days), (y, m as u32, d as u32));
    }
    // Every day for eight years round-trips, which is the only honest way
    // to believe a date function.
    for day in 20_000..23_000 {
        let (y, m, d) = civil_from_days(day);
        assert_eq!(days_from_civil(y, m, d), day);
    }
    // A malformed date reads as the epoch rather than as a wild one.
    assert_eq!(days_from_civil(0, 0, 0), 0);
    assert_eq!(days_from_civil(2026, 13, 1), 0);
}
