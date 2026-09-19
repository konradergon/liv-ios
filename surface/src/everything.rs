//! Everything: the flat list of what is in the box.
//!
//! From `Everything.swift`, which held ten collection operations. Its two
//! standing rules come with it:
//!
//! 1. **It wears the workspace lens** like every other surface (owner, rev
//!    6). "Workspaces define context consistently via property filtering"
//!    outranks the old "Everything never hides" rule, and the
//!    always-complete surface is the All workspace, one switch away.
//! 2. **Unfiled means NO AREA** — not "no type". The Inbox's rule keys on
//!    type, which is why a task you hesitated over was missing from every
//!    area AND from the Inbox.

use liv_engine::{prop, Engine, LogError};

use crate::{day_of, row, shape_of, visible, Lens, Row, Shape};

/// Which slice — the chips at the head of the list.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Slice {
    #[default]
    All,
    Notes,
    Upcoming,
    Unfiled,
}

impl Slice {
    /// What an empty one says.
    pub fn empty_word(self) -> &'static str {
        match self {
            Slice::All => "Empty",
            Slice::Notes => "Nothing written",
            Slice::Upcoming => "Nothing due",
            Slice::Unfiled => "All filed",
        }
    }
}

/// How many days ahead Upcoming looks.
pub const HORIZON_DAYS: i32 = 7;

pub fn everything(
    e: &Engine,
    slice: Slice,
    lens: &Lens,
    today_day: i32,
) -> Result<Vec<Row>, LogError> {
    // UPCOMING IS A WINDOW, so it is an index seek rather than a scan of
    // everything dated. The other three need the whole box, and say so.
    if slice == Slice::Upcoming {
        let mut rows = Vec::new();
        for (id, _) in e.in_window(
            prop::DUE,
            crate::day_start(today_day),
            crate::day_end(today_day + HORIZON_DAYS),
        )? {
            let r = row(e, id)?;
            if visible(&r, lens) {
                rows.push(r);
            }
        }
        // The one slice sorted FORWARD, because "what is coming" reads in
        // the order it will arrive. Today included: a thing due in an
        // hour is upcoming.
        rows.sort_by(|a, b| (a.due_ms, a.id).cmp(&(b.due_ms, b.id)));
        return Ok(rows);
    }

    let mut rows = Vec::new();
    for id in e.all_entities()? {
        let r = row(e, id)?;
        if !visible(&r, lens) {
            continue;
        }
        let keep = match slice {
            Slice::All => true,
            // WHAT WAS THE NOTES VIEW, unchanged: documents only. A task
            // is a record and opens as a card, so a list of things that
            // open as a page is the honest content. Files count — a file
            // is a document you work on.
            Slice::Notes => shape_of(&r) != Shape::Record,
            Slice::Unfiled => r.area.is_none(),
            Slice::Upcoming => unreachable!("handled above"),
        };
        if keep {
            rows.push(r);
        }
    }

    match slice {
        // ORDERED BY WHAT YOU TOUCHED LAST, not by when you made it. That
        // ordering is why this can beat the tab switcher: the note you
        // were editing ten minutes ago is the first row, and unlike the
        // switcher it also reaches the note you did NOT leave open.
        Slice::Notes => rows.sort_by(|a, b| (b.touched_ms, b.id).cmp(&(a.touched_ms, a.id))),
        _ => rows.sort_by(|a, b| (b.created_ms, b.id).cmp(&(a.created_ms, a.id))),
    }
    Ok(rows)
}

/// **Unfiled is structurally impossible inside a workspace whose query
/// stamps an area**, so the chip hides there rather than promising an
/// always-empty list (audit, 2026-08-04).
///
/// `stamps_area` is whether the active workspace writes an `area` cell
/// onto everything it makes — the shell knows it from the workspace's own
/// stamp cells, and it stays a parameter until workspaces move down.
pub fn slices(stamps_area: bool) -> Vec<Slice> {
    let all = [Slice::All, Slice::Notes, Slice::Upcoming, Slice::Unfiled];
    all.into_iter().filter(|s| *s != Slice::Unfiled || !stamps_area).collect()
}

/// What the row's trailing fact says. Upcoming answers "when is it due";
/// the other slices answer "when did I catch it". A column of identical
/// dates tells you nothing, so the shell shows it only when it changes —
/// but WHICH stamp it is, is this crate's answer.
pub fn trailing_ms(r: &Row, slice: Slice) -> Option<i64> {
    let ms = if slice == Slice::Upcoming { r.due_ms? } else { r.created_ms };
    if ms > 0 {
        Some(ms)
    } else {
        None
    }
}

/// The day a trailing fact falls on, for the shell to compare against
/// today before it formats anything.
pub fn trailing_day(r: &Row, slice: Slice) -> Option<i32> {
    trailing_ms(r, slice).map(day_of)
}
