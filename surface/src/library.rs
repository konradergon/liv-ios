//! The library: everything the app looks things up in, the two lists that
//! need the whole box, and the count beside each view — in one pass.
//!
//! **One pass, on purpose.** Notes, Unsorted and the library panel's
//! counts all need every row in the box, and the app already reads every
//! row after each write (it looks things up by id). Answering them as
//! separate questions would read the whole box three more times per write;
//! at 5,000 things one such read is about 120 ms (measured 2026-09-30).

use liv_engine::{kind, Engine, EntityId, LogError};

use crate::{
    can_tick, dated, day_of, is_unsorted, row, shape_of, visible, Lens, Row, Shape,
};

/// What `library` answers.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Library {
    /// Every live, front-of-house thing, newest first — what the app looks
    /// a thing up in by id. Never lensed: a link to something outside the
    /// workspace still has to resolve.
    pub all: Vec<Row>,
    /// The Notes list: what opens as a page, in the lens, last touched
    /// first. Ids of rows in `all`.
    pub notes: Vec<EntityId>,
    /// The Unsorted list: what a person files, with no area, newest first.
    /// **Never lensed** (design/ios.md M4): a thing made under the wrong
    /// workspace must not vanish. Ids of rows in `all`.
    pub unsorted: Vec<EntityId>,
    pub counts: Counts,
}

/// The number beside each view in the library panel — the number of rows
/// that view will show, so the two can never disagree.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Counts {
    /// Open things that can be ticked, due today or earlier.
    pub today: usize,
    pub unsorted: usize,
    pub notes: usize,
    /// Every task, done ones included — the Tasks screen folds them, it
    /// does not drop them.
    pub tasks: usize,
    pub events: usize,
}

/// Build it. `now_ms` and `offset_min` are read as in `today`: "today" is
/// the day on the phone's clock.
pub fn library(e: &Engine, now_ms: i64, offset_min: i32, lens: &Lens) -> Result<Library, LogError> {
    let today_day = day_of(now_ms + offset_min as i64 * 60_000);
    let mut out = Library::default();

    for id in e.all_entities()? {
        let r = dated(row(e, id, offset_min)?, today_day);
        if visible(&r, &Lens::Everything) {
            out.all.push(r);
        }
    }
    out.all.sort_by(|a, b| (b.created_ms, b.id).cmp(&(a.created_ms, a.id)));

    let mut notes: Vec<&Row> = Vec::new();
    for r in &out.all {
        if is_unsorted(r) {
            out.unsorted.push(r.id);
        }
        if !lens.admits(r.id) {
            continue;
        }
        if shape_of(r) != Shape::Record {
            notes.push(r);
        }
        match r.kind {
            Some(k) if k == kind::TASK => out.counts.tasks += 1,
            Some(k) if k == kind::EVENT => out.counts.events += 1,
            _ => {}
        }
        let due_by_today = r.due_ms.is_some_and(|ms| day_of(ms) <= today_day);
        if can_tick(r) && due_by_today && !r.done {
            out.counts.today += 1;
        }
    }
    // ORDERED BY WHAT YOU TOUCHED LAST, not by when you made it: the note
    // you were editing ten minutes ago is the first row.
    notes.sort_by(|a, b| (b.touched_ms, b.id).cmp(&(a.touched_ms, a.id)));
    out.notes = notes.iter().map(|r| r.id).collect();

    out.counts.notes = out.notes.len();
    out.counts.unsorted = out.unsorted.len();
    Ok(out)
}
