//! Civil date arithmetic, dependency-free — shared by the clerk (parsing
//! "friday") and the recurrence engine (expanding "every friday").
//! Fifty lines of calendar beat a clock dependency in a layer that must
//! stay pure: nothing here reads the time.

use lotus_core::DateTime;

pub(crate) const WEEKDAYS: [&str; 7] = [
    "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
];

pub(crate) fn parts(date: DateTime) -> (i32, u32, u32) {
    let ymd = date.civil / 10_000;
    ((ymd / 10_000) as i32, ((ymd / 100) % 100) as u32, (ymd % 100) as u32)
}

pub(crate) fn leap(year: i32) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

pub(crate) fn days_in_month(year: i32, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if leap(year) {
                29
            } else {
                28
            }
        }
        _ => 30,
    }
}

pub(crate) fn add_days(date: DateTime, days: u32) -> DateTime {
    let (mut y, mut m, mut d) = parts(date);
    for _ in 0..days {
        d += 1;
        if d > days_in_month(y, m) {
            d = 1;
            m += 1;
            if m > 12 {
                m = 1;
                y += 1;
            }
        }
    }
    DateTime::date(y, m, d)
}

/// Sakamoto's method; 0 = Sunday.
pub(crate) fn weekday(date: DateTime) -> u32 {
    let (mut y, m, d) = parts(date);
    const T: [i32; 12] = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
    if m < 3 {
        y -= 1;
    }
    ((y + y / 4 - y / 100 + y / 400 + T[(m - 1) as usize] + d as i32).rem_euclid(7)) as u32
}

pub(crate) fn show_date(date: DateTime) -> String {
    let (y, m, d) = parts(date);
    format!("{y:04}-{m:02}-{d:02}")
}

/// The date with its clock stripped: recurrence and comparison work in
/// whole civil days.
pub(crate) fn day_of(date: DateTime) -> DateTime {
    let (y, m, d) = parts(date);
    DateTime::date(y, m, d)
}
