//! The calendar: which things fall on which day.
//!
//! **Only which, never where.** Where a block sits on the hour grid and how
//! wide it is when things clash stays with the shell, because it has to be
//! worked out again on every frame of a drag, and a question to the core
//! per frame is not a thing a finger can wait for (owner, 2026-09-30).

use liv_engine::{prop, Engine, LogError};

use crate::{day_end, day_of, day_start, row, visible, Lens, Row};

/// One day that has anything on it.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct CalendarDay {
    /// Days since the epoch.
    pub day: i32,
    /// Things that belong to the day rather than to an hour.
    pub all_day: Vec<Row>,
    /// Things at a clock time, in time order.
    pub timed: Vec<Row>,
}

/// Every day from `from` to `to`, both included, that has anything on it,
/// in order. One index seek for the whole range, however many days.
pub fn calendar(e: &Engine, from: i32, to: i32, lens: &Lens) -> Result<Vec<CalendarDay>, LogError> {
    let mut rows = Vec::new();
    for (id, _) in e.in_window(prop::DUE, day_start(from), day_end(to))? {
        let r = row(e, id)?;
        if visible(&r, lens) {
            rows.push(r);
        }
    }
    // Time order, then id — the day as it actually runs.
    rows.sort_by(|a, b| (a.due_ms, a.id).cmp(&(b.due_ms, b.id)));

    let mut days: Vec<CalendarDay> = Vec::new();
    for r in rows {
        let day = day_of(r.due_ms.unwrap_or(0));
        if days.last().map(|d| d.day) != Some(day) {
            days.push(CalendarDay { day, ..CalendarDay::default() });
        }
        let d = days.last_mut().expect("just pushed");
        if r.all_day {
            d.all_day.push(r);
        } else {
            d.timed.push(r);
        }
    }
    Ok(days)
}
