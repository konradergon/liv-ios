//! The surfaces: what each screen is, answered in Rust.
//!
//! **This is where the shell's logic went** (owner, 2026-09-13: *"The rust
//! side should handle all the app mechanisms […] The swift side should just
//! implement an interface for the rust side. no logic."*). A surface takes
//! the engine and a few parameters and returns exactly the rows one screen
//! draws — filtered, sorted, and carrying the facts the row needs. The
//! shell lays them out and does not decide what is in them.
//!
//! **Why a crate and not a module in `engine/`.** The engine is a store: it
//! knows entities, cells, ops and merge rules, and it must stay linkable by
//! a desktop that arranges its screens differently. "What is Today" is a
//! product answer, not a storage one.
//!
//! **Why not `services/`.** That is 9,000 lines over `core/`, and it moves
//! here when its turn comes (`rust-owns-the-mechanisms.md` §5, stage 5).
//! Nothing is ported twice: a surface is written against the engine once.
//!
//! ## The rules live here now, and they are tested
//!
//! Every product rule in this crate was, until today, a comment above a
//! filter in a SwiftUI view file — reachable by no test in the workspace
//! and checkable only by looking at a simulator. They arrive here with the
//! comment intact and a test under it.

use liv_engine::{kind, model, prop, status, DateSpec, Engine, EntityId, LogError, Value};

pub mod today;

/// One row, as a screen needs it.
///
/// **Flat on purpose.** This crosses the ABI next, and a row the shell can
/// draw without asking a second question is the whole point of the move —
/// `rust-owns-the-mechanisms.md` §3.
#[derive(Debug, Clone, PartialEq)]
pub struct Row {
    pub id: EntityId,
    /// Already resolved: the name cell, or the body's first line for a
    /// scrap that never got one. Never empty — an untitled thing says so
    /// with `untitled`, and the shell styles that rather than inventing
    /// the words.
    pub title: String,
    pub untitled: bool,
    pub kind: Option<EntityId>,
    /// When, in milliseconds — `view::at_ms`'s reading.
    pub due_ms: Option<i64>,
    /// A day with no clock time. "Due Friday" and "starts 14:00" are
    /// different things (op.rs), and the timeline puts them in different
    /// places.
    pub all_day: bool,
    pub status: Option<EntityId>,
    /// Whether that status finishes the thing — resolved here, because
    /// "which statuses complete" is a question about the box and the
    /// shell was answering it by collecting names into a `Set<String>`.
    pub done: bool,
    pub area: Option<EntityId>,
    pub trashed: bool,
    pub archived: bool,
}

/// Everything a row needs, built from one `cells_of` rather than one query
/// per property.
pub fn row(e: &Engine, id: EntityId) -> Result<Row, LogError> {
    let cells = e.cells_of(id)?;
    let one = |want: EntityId| -> Option<&Value> {
        let mut it = cells.iter().filter(|(p, _, _)| *p == want);
        let first = it.next()?;
        // A contended register has two rows and has no one value; the
        // caller sees None rather than a coin flip (core.md §5).
        if it.next().is_some() {
            None
        } else {
            Some(&first.2)
        }
    };

    let name = match one(prop::NAME) {
        Some(Value::Text(s)) if !s.trim().is_empty() => Some(s.trim().to_owned()),
        _ => None,
    };
    let body_line = match one(prop::BODY) {
        Some(Value::Text(s)) => first_line(s),
        _ => None,
    };
    let (title, untitled) = match name.or(body_line) {
        Some(t) => (t, false),
        None => (String::new(), true),
    };

    let due = one(prop::DUE).and_then(|v| match v {
        Value::Date(d) => Some(*d),
        _ => None,
    });
    let st = match one(prop::STATUS) {
        Some(Value::Ref(s)) => Some(*s),
        _ => None,
    };

    Ok(Row {
        id,
        title,
        untitled,
        kind: match one(prop::KIND) {
            Some(Value::Ref(k)) => Some(*k),
            _ => None,
        },
        due_ms: due.as_ref().map(|d| match d {
            DateSpec::Day(day) => *day as i64 * 86_400_000,
            DateSpec::Instant { ms, .. } => *ms,
        }),
        all_day: matches!(due, Some(DateSpec::Day(_))),
        status: st,
        done: match st {
            Some(s) => completes(e, s)?,
            None => false,
        },
        area: match one(prop::AREA) {
            Some(Value::Ref(a)) => Some(*a),
            _ => None,
        },
        trashed: matches!(one(prop::TRASHED), Some(Value::Bool(true))),
        archived: matches!(one(prop::ARCHIVED), Some(Value::Bool(true))),
    })
}

/// A scrap carries no name cell — its display name is its first content
/// line, the same rule the desk and the outbox ledger use. Markdown markers
/// come off, so a note that starts `# Trip planning` is titled
/// "Trip planning" and never `# Trip planning`.
fn first_line(body: &str) -> Option<String> {
    let line = body.lines().find(|l| !l.trim().is_empty())?;
    let t = line.trim_start_matches(['#', '>', '-', '*', ' ']).trim();
    if t.is_empty() {
        None
    } else {
        Some(t.to_owned())
    }
}

/// **Does reaching this status finish the thing?**
///
/// The frozen Done does; a minted status option says so in its
/// `prop::COMPLETES` cell. The shell was answering this by gathering the
/// NAMES of completing options into a `Set<String>` and testing membership
/// by string — which is the shape that makes "Done" and "done" two
/// different answers, and which the desktop's own query code carries a
/// note about.
pub fn completes(e: &Engine, st: EntityId) -> Result<bool, LogError> {
    if st == status::DONE {
        return Ok(true);
    }
    if model::is_furniture(st) {
        return Ok(false);
    }
    Ok(matches!(e.one(st, prop::COMPLETES)?, Some(Value::Bool(true))))
}

/// Is this a thing that can still be DONE, rather than something that
/// merely happens? Only a task is late; an event is not.
pub fn is_task(row: &Row) -> bool {
    row.kind == Some(kind::TASK)
}

/// Days since the epoch, from a millisecond reading. Floors, so a negative
/// millisecond does not round toward zero and put a pre-1970 stamp on the
/// wrong day.
pub fn day_of(ms: i64) -> i32 {
    ms.div_euclid(86_400_000) as i32
}

/// The first millisecond of a day.
pub fn day_start(day: i32) -> i64 {
    day as i64 * 86_400_000
}

/// The last millisecond of a day.
pub fn day_end(day: i32) -> i64 {
    day_start(day) + 86_400_000 - 1
}
