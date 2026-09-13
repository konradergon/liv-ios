//! The one piece of date arithmetic the conversion needs.
//!
//! `core/` packs a civil stamp as `YYYYMMDD * 10_000 + HHMM` — zone-free,
//! totally ordered, and readable in a hex dump. The engine counts days
//! from the epoch. Neither is wrong and the two do not meet without this.
//!
//! **Hinnant's algorithm, not a library.** It is exact for every
//! proleptic-Gregorian date, it is fifteen lines, and it has no zone in
//! it — which matters, because the value being converted is deliberately
//! zoneless and a library that "helpfully" localises it would put a
//! floating day on the wrong side of midnight. `chrono` is already in the
//! tree for the FFI's clock; this is not that job.

/// Unpack `YYYYMMDDHHMM` into its parts.
pub fn split_civil(civil: i64) -> (i32, u32, u32, u32, u32) {
    let day_part = civil / 10_000;
    let time = (civil % 10_000).max(0);
    (
        (day_part / 10_000) as i32,
        ((day_part / 100) % 100) as u32,
        (day_part % 100) as u32,
        (time / 100) as u32,
        (time % 100) as u32,
    )
}

/// Days since 1970-01-01, for any proleptic-Gregorian date.
///
/// Negative for dates before the epoch, which is why the caller must floor
/// rather than truncate when it goes back the other way.
pub fn days_from_civil(y: i32, m: u32, d: u32) -> i32 {
    // Guard the stamps a box can actually hold: a zero or malformed one
    // reads as the epoch rather than as some wild date.
    if y == 0 || m == 0 || m > 12 || d == 0 || d > 31 {
        return 0;
    }
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = (y - era * 400) as u32; // [0, 399]
    let mp = (m + 9) % 12; // March = 0
    let doy = (153 * mp + 2) / 5 + d - 1; // [0, 365]
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy; // [0, 146096]
    era * 146_097 + doe as i32 - 719_468
}

/// The inverse, for tests and for anything that has to show a day back.
pub fn civil_from_days(days: i32) -> (i32, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u32; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe as i32 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = doy - (153 * mp + 2) / 5 + 1; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 }; // [1, 12]
    (if m <= 2 { y + 1 } else { y }, m, d)
}
