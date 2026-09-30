//! Today: the week ahead on the strip, what is late, what is next.
//!
//! **Every rule here came out of `Today.swift`**, where it sat as a
//! comment above a `filter` — 21 collection operations in one view file,
//! reachable by no test. The comments came with them.

use std::collections::{BTreeMap, BTreeSet};

use liv_engine::{kind, prop, Engine, EntityId, LogError};

use crate::{agenda, dated, day_of, is_late, row, visible, Lens, Row};

/// How many days the date strip shows: today and the six after it.
pub const STRIP_DAYS: i32 = 7;

/// How many undated tasks "What next" lists: a nudge under the day, not a
/// second Tasks screen.
pub const WHAT_NEXT: usize = 5;

/// What the Today screen is.
///
/// **Everything the strip can pick is already in here**, so moving the
/// day redraws in one frame without asking again.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Today {
    /// Today and the six days after it, in order.
    pub days: Vec<TodayDay>,
    /// Open tasks whose day has passed, most recent first. The same on
    /// every day of the strip.
    pub late: Vec<Row>,
    /// Open tasks with no date, last touched first, at most `WHAT_NEXT`.
    pub what_next: Vec<Row>,
    /// Scraps caught today — things with no kind yet, which is what
    /// "Route them" takes you to.
    pub captured: usize,
}

/// One day of the strip.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct TodayDay {
    /// Days since the epoch.
    pub day: i32,
    /// A day with no clock time: it belongs to the day, not to an hour.
    pub all_day: Vec<Row>,
    /// Timed and already gone — the schedule dims these. Only today has
    /// any: yesterday is not "all passed" and tomorrow is not "all ahead".
    pub passed: Vec<Row>,
    /// Timed and still coming.
    pub ahead: Vec<Row>,
    /// Timed and finished, out of the way.
    pub done: Vec<Row>,
    /// The line under the title: what is late, open or all-day, counted by
    /// area and named alphabetically.
    pub areas: Vec<(String, usize)>,
    /// The same count for the things with no area.
    pub unfiled: usize,
}

/// Build it.
///
/// `now_ms` is the real instant and `offset_min` the phone's distance from
/// UTC. A due is a wall-clock time stored as if at UTC, so "now" on that
/// clock is `now_ms + offset`; and "made today" reads an id's instant in
/// the same zone.
pub fn today(e: &Engine, now_ms: i64, offset_min: i32, lens: &Lens) -> Result<Today, LogError> {
    let offset_ms = offset_min as i64 * 60_000;
    let now = now_ms + offset_ms;
    let today_day = day_of(now);
    let mut out = Today::default();

    // ---- late ----------------------------------------------------------
    //
    // LATE = incomplete TASKS whose day has passed (owner ruling). Not
    // events, not notes — a thing is late only if it can still be done.
    //
    // The window starts at the epoch rather than at some horizon: a task
    // due three years ago is still late, and a horizon would be a rule
    // nobody stated.
    for (id, _) in e.in_window(prop::DUE, i64::MIN / 2, crate::day_start(today_day) - 1)? {
        let r = dated(row(e, id)?, today_day);
        if visible(&r, lens) && is_late(&r, today_day) {
            out.late.push(r);
        }
    }
    // Most recent first: yesterday's is more actionable than last year's.
    out.late.sort_by(|a, b| (b.due_ms, b.id).cmp(&(a.due_ms, a.id)));

    // ---- the strip -----------------------------------------------------
    for day in today_day..today_day + STRIP_DAYS {
        let mut d = TodayDay { day, ..TodayDay::default() };
        for r in agenda(e, day, lens)? {
            let r = dated(r, today_day);
            if r.all_day {
                d.all_day.push(r);
            } else if r.done {
                d.done.push(r);
            } else if day == today_day && r.due_ms.unwrap_or(0) < now {
                d.passed.push(r);
            } else {
                d.ahead.push(r);
            }
        }
        let counted = out.late.iter().chain(&d.passed).chain(&d.ahead).chain(&d.all_day);
        (d.areas, d.unfiled) = by_area(counted);
        out.days.push(d);
    }

    // ---- what next -----------------------------------------------------
    //
    // Open tasks with NO date. The schedule answers "when"; this answers
    // "what" — without it an undated commitment is invisible until you go
    // looking for it in Tasks. Anything with a status can be ticked, so
    // it counts as a task here.
    let mut candidates: BTreeSet<EntityId> = e.of_kind(kind::TASK)?.into_iter().collect();
    for (id, _) in liv_engine::view::with_prop(e.conn(), prop::STATUS)? {
        candidates.insert(id);
    }
    let mut next = Vec::new();
    for id in candidates {
        let r = row(e, id)?;
        if visible(&r, lens) && crate::can_tick(&r) && r.due_ms.is_none() && !r.done {
            next.push(r);
        }
    }
    next.sort_by(|a, b| (b.touched_ms, b.id).cmp(&(a.touched_ms, a.id)));
    next.truncate(WHAT_NEXT);
    out.what_next = next;

    // ---- captured ------------------------------------------------------
    //
    // Counted from the ID, not from a `created` cell. A v7 id carries its
    // own millisecond (`id.rs`), so "made today" needs no stored value and
    // cannot disagree with one. The lens applies here too — a filtered
    // surface counts what it can show.
    let mut captured = 0;
    for id in e.all_entities()? {
        if day_of(id.millis() as i64 + offset_ms) != today_day {
            continue;
        }
        let r = row(e, id)?;
        if r.kind.is_none() && visible(&r, lens) {
            captured += 1;
        }
    }
    out.captured = captured;

    Ok(out)
}

/// Count rows by area name, alphabetically, and the ones with none.
fn by_area<'a>(rows: impl Iterator<Item = &'a Row>) -> (Vec<(String, usize)>, usize) {
    let mut named: BTreeMap<String, usize> = BTreeMap::new();
    let mut unfiled = 0;
    for r in rows {
        match r.area_word.as_deref() {
            Some(a) if !a.is_empty() => *named.entry(a.to_owned()).or_default() += 1,
            _ => unfiled += 1,
        }
    }
    (named.into_iter().collect(), unfiled)
}
