//! Today: the day, and what is late.
//!
//! **Every rule here came out of `Today.swift`**, where it sat as a
//! comment above a `filter` — 21 collection operations in one view file,
//! reachable by no test. The comments came with them.

use liv_engine::{prop, Engine, EntityId, LogError};

use crate::{agenda, day_of, day_start, is_task, row, visible, Lens, Row};

/// What the Today screen is.
///
/// **The split is the screen.** The shell was computing all six of these
/// from a snapshot of the whole box; it now receives them.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Today {
    /// Incomplete tasks whose day has passed, most recent first.
    pub late: Vec<Row>,
    /// Timed and already gone — the timeline dims these.
    pub passed: Vec<Row>,
    /// Timed and still coming.
    pub ahead: Vec<Row>,
    /// A day with no clock time: it belongs to the day, not to an hour.
    pub all_day: Vec<Row>,
    /// Finished, and out of the way.
    pub done: Vec<Row>,
    /// The next thing up, when the day being shown is today. The shell
    /// lights this row; it does not work out which one it is.
    pub next: Option<EntityId>,
    /// How many things were caught today, whatever day is being shown.
    pub captured: usize,
}

/// Build it.
///
/// `day` is the day being shown and `today` is the real one — they differ
/// whenever the date strip has been moved, and several rules below turn on
/// whether they are the same. `now_ms` is the clock.
pub fn today(
    e: &Engine,
    day: i32,
    today_day: i32,
    now_ms: i64,
    lens: &Lens,
) -> Result<Today, LogError> {
    let mut out = Today::default();

    // ---- the four piles ------------------------------------------------
    let on_today = day == today_day;
    for r in agenda(e, day, lens)? {
        if r.all_day {
            out.all_day.push(r);
        } else if r.done {
            out.done.push(r);
        } else if on_today && r.due_ms.unwrap_or(0) < now_ms {
            // The timeline knows the time, but only for today: yesterday
            // is not "all passed" and tomorrow is not "all ahead".
            out.passed.push(r);
        } else {
            out.ahead.push(r);
        }
    }
    out.next = if on_today { out.ahead.first().map(|r| r.id) } else { None };

    // ---- late ----------------------------------------------------------
    //
    // LATE = incomplete TASKS whose day has passed (owner ruling). Not
    // events, not notes — a thing is late only if it can still be done.
    //
    // The window starts at the epoch rather than at some horizon: a task
    // due three years ago is still late, and a horizon would be a rule
    // nobody stated.
    for (id, _) in e.in_window(prop::DUE, i64::MIN / 2, day_start(today_day) - 1)? {
        let r = row(e, id)?;
        if !visible(&r, lens) || r.done || !is_task(&r) {
            continue;
        }
        out.late.push(r);
    }
    // Most recent first: yesterday's is more actionable than last year's.
    out.late.sort_by(|a, b| (b.due_ms, b.id).cmp(&(a.due_ms, a.id)));

    // ---- captured ------------------------------------------------------
    //
    // Counted from the ID, not from a `created` cell. A v7 id carries its
    // own millisecond (`id.rs`), so "made today" needs no stored value and
    // cannot disagree with one.
    // The lens applies here too — a filtered surface counts what it can
    // show, or the number disagrees with the list under it.
    let mut captured = 0;
    for id in e.all_entities()? {
        if day_of(id.millis() as i64) != today_day {
            continue;
        }
        if visible(&row(e, id)?, lens) {
            captured += 1;
        }
    }
    out.captured = captured;

    Ok(out)
}
