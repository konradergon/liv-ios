//! What rings, and when.
//!
//! Until 2026-10-01 this was `Notify.swift`'s own walk of the whole box,
//! with its own copy of "is this a task" and "is this done". The shell
//! still owns the platform half — turning a wall-clock time into an alarm,
//! and how many pending alarms its phone allows.

use liv_engine::{kind, prop, Engine, LogError};

use crate::{can_tick, row, visible, Lens, Row};

/// The reminders still to come, soonest first.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Reminders {
    /// The soonest, at most the `limit` the shell asked for.
    pub soonest: Vec<Row>,
    /// How many ring in all — so a shell can say how many did not fit.
    pub total: usize,
}

/// **Does this ring?** An event, or a task still open — a status is what
/// makes a thing a task, with or without the word — at its clock time. A
/// due with no clock time never rings (owner, 2026-08-06: "a date reminder
/// shouldn't be a thing"), and there is no lead time: it rings when due.
pub fn rings(r: &Row) -> bool {
    let event = r.kind == Some(kind::EVENT);
    let open_task = !event && can_tick(r) && !r.done;
    (event || open_task) && r.due_ms.is_some() && !r.all_day
}

/// Every reminder still to come on the phone's clock, soonest first, the
/// first `limit` of them. `now_ms` and `offset_min` as `today`: a due is a
/// wall-clock time, so "still to come" is read on that clock. Every
/// workspace: a reminder does not care which one you are in.
pub fn reminders(
    e: &Engine,
    now_ms: i64,
    offset_min: i32,
    limit: usize,
) -> Result<Reminders, LogError> {
    let now = now_ms + offset_min as i64 * 60_000;
    let mut due = Vec::new();
    // ONE INDEX SEEK over what is due after now — the past never rings.
    for (id, _) in e.in_window(prop::DUE, now + 1, i64::MAX / 2)? {
        let r = row(e, id, offset_min)?;
        if visible(&r, &Lens::Everything) && rings(&r) {
            due.push(r);
        }
    }
    due.sort_by(|a, b| (a.due_ms, a.id).cmp(&(b.due_ms, b.id)));
    let total = due.len();
    due.truncate(limit);
    Ok(Reminders { soonest: due, total })
}
