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

use liv_engine::{
    civil_from_days, kind, model, prop, status, DateSpec, Engine, EntityId, LogError, Value,
};

/// The sweep — what the clerk would suggest, read off the box. The
/// queue that accepts or declines one is in the engine; the heuristics
/// are here, because English is product and the box has no opinion.
pub mod clerk;

/// Search: resolving a typed query against the box, ranking what it
/// admits, and the facets beside it. The GRAMMAR is the engine's.
pub mod search;

/// Where a word starts and stops — one boundary matcher, which the clerk
/// and search both call (standing rule 4).
pub mod words;


pub mod day;
pub mod everything;
pub mod tasks;
pub mod today;

/// The workspace lens — what this screen is allowed to show.
///
/// **Evaluating the query is not this crate's job** and never was: the box
/// already answers it (`liv_query` today, and the query grammar moves down
/// with search). What the shell was doing was CACHING the answer and then
/// testing membership on every row of every surface, which put the lens in
/// twenty-two places. It is a parameter here, applied once per surface, in
/// one line each.
#[derive(Debug, Clone, Default, PartialEq)]
pub enum Lens {
    /// No workspace, or the All workspace: everything is admitted.
    #[default]
    Everything,
    /// Exactly these, and nothing else.
    Only(std::collections::HashSet<EntityId>),
}

impl Lens {
    pub fn admits(&self, id: EntityId) -> bool {
        match self {
            Lens::Everything => true,
            Lens::Only(ids) => ids.contains(&id),
        }
    }

    /// True when some lens is on — the surfaces show the chip only then.
    pub fn on(&self) -> bool {
        matches!(self, Lens::Only(_))
    }
}

impl FromIterator<EntityId> for Lens {
    fn from_iter<I: IntoIterator<Item = EntityId>>(iter: I) -> Lens {
        Lens::Only(iter.into_iter().collect())
    }
}

/// **Is this row on a surface at all?** Trashed, archived and backstage
/// things are on none of them, and the lens decides the rest. One place,
/// because it was a repeated three-clause `filter` in every view file and
/// the calendar's occurrence loop had a fourth copy.
///
/// The `working` clause is the one the shell never had to write: `core/`
/// curated the snapshot's `everything` list inside the builder, so
/// backstage entities never reached Swift at all. The engine stores them
/// like anything else — a minted area IS an entity with no area — so
/// without this a user's seventh area turns up in Unfiled. It did, and a
/// test caught it.
pub fn visible(r: &Row, lens: &Lens) -> bool {
    !r.trashed && !r.archived && !r.working && lens.admits(r.id)
}

/// The day's dated things, in time order, lens applied.
///
/// ONE INDEX SEEK, where the shell filtered every dated row in the box.
/// `in_window` is inclusive at both ends and `day_end` is the last
/// millisecond, so a thing due at 23:59 is on the day and midnight
/// tomorrow is not.
pub fn agenda(e: &Engine, day: i32, lens: &Lens) -> Result<Vec<Row>, LogError> {
    let mut rows = Vec::new();
    for (id, _) in e.in_window(prop::DUE, day_start(day), day_end(day))? {
        let r = row(e, id)?;
        if visible(&r, lens) {
            rows.push(r);
        }
    }
    // Time order, then id — the day as it actually runs, events and tasks
    // interleaved rather than in separate blocks.
    rows.sort_by(|a, b| (a.due_ms, a.id).cmp(&(b.due_ms, b.id)));
    Ok(rows)
}

/// Every status there is, in the order a screen groups by: the three Liv
/// ships with, then whatever the box has minted, oldest first.
pub fn statuses(e: &Engine) -> Result<Vec<EntityId>, LogError> {
    let mut out: Vec<EntityId> = liv_engine::STATUSES.to_vec();
    let mut minted = e.of_kind(kind::STATUS)?;
    minted.sort();
    out.extend(minted.into_iter().filter(|s| !model::is_furniture(*s)));
    Ok(out)
}

/// What a thing opens as. A FILE is checked first, because having a file
/// crosscuts the kinds — a scanned contract is a file and can also be a
/// task, and what you want to see is the contract. Then a note and an
/// untyped capture are documents; everything else with a kind is a record.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Shape {
    Document,
    Record,
    File,
}

pub fn shape_of(r: &Row) -> Shape {
    if r.has_file {
        return Shape::File;
    }
    match r.kind {
        None => Shape::Document,
        Some(k) if k == kind::NOTE => Shape::Document,
        Some(_) => Shape::Record,
    }
}

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
    /// From the id, not a stored cell: a v7 id carries its own
    /// millisecond, so `created` needs no value and cannot disagree
    /// with one.
    pub created_ms: i64,
    /// When it was last WRITTEN — never when it was read. No op records a
    /// visit, and a device-side one would disagree with every other
    /// surface.
    pub touched_ms: i64,
    /// Carries file bytes, which crosscuts kind and decides how it opens.
    pub has_file: bool,
    /// **Plumbing on the shelf.** Real, addressable, and on no
    /// front-of-house list: workspaces, saved views, declared fields,
    /// minted areas and status options. `core/` excluded these inside the
    /// snapshot builder, so no shell ever had to know; the engine stores
    /// them like anything else, so the rule has to live somewhere, and
    /// this is it.
    pub working: bool,
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
        // The body is a span list, so its first line is the plain text
        // up to the first `Break` — a `Ref` contributes nothing, because
        // a link's words live on its target, not in this note.
        Some(Value::Rich(spans)) => first_line(&liv_engine::rich::plain(spans)),
        _ => None,
    };
    // **NEVER EMPTY, AND NEVER AN ID** (owner, 2026-09-13: *"LivID
    // shouldn't be read by the user"* and *"Unnamed task/event/note
    // should get a sensible name"*). A screen that has to invent a word
    // for a nameless thing will invent a different one on each surface —
    // the shell had four ("Untitled", "untitled", the kind's word, and a
    // hash-number) before this was one function.
    let (title, untitled) = match name.or(body_line) {
        Some(t) => (t, false),
        None => (made_name(e, id)?, true),
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
        created_ms: id.millis() as i64,
        touched_ms: e.touched(id)?,
        has_file: cells.iter().any(|(p, _, _)| *p == prop::FILE),
        working: matches!(one(prop::WORKING), Some(Value::Bool(true))),
    })
}

/// What to call a thing nobody has named: the kind's word, and when.
///
/// **This amends the 2026-09-06 ruling** that a nameless row says what it
/// IS — "Task", "Note" — rather than "Untitled", the word Obsidian, Apple
/// Notes and Notion all use for a failure to name. That was right and it
/// was not enough: fourteen rows reading "Task" distinguish each other no
/// better than fourteen reading "Untitled", and the harness had already
/// tripped over exactly that, unable to aim at one of three notes sharing
/// a label.
///
/// The word comes from the model, which is the only place the app's
/// vocabulary lives — a shell carrying its own copy is the mistake
/// `one-core.md` §4 records. `untitled` stays true, so a surface can
/// still draw a made name more quietly than a given one.
fn made_name(e: &Engine, id: EntityId) -> Result<String, LogError> {
    let kind = match e.kind_of(id)? {
        Some(k) => model::label(k).unwrap_or("Capture").to_string(),
        // An untyped capture. "Note" would be a claim about its kind that
        // nothing in the box makes.
        None => "Capture".to_string(),
    };
    let made = id.millis() as i64;
    if made <= 0 {
        return Ok(kind);
    }
    Ok(format!("{kind} · {}", stamp_words(made)))
}

/// `13 Sep 14:32` from a millisecond.
///
/// **English, like every other word the model owns.** A locale-formatted
/// date belongs in the shell (`rust-owns-the-mechanisms.md` §4) — but a
/// NAME is vocabulary, and vocabulary is Rust's, or a second shell grows
/// its own copy of it.
fn stamp_words(ms: i64) -> String {
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    let day = day_of(ms);
    let (_, m, d) = civil_from_days(day);
    let in_day = ms - day_start(day);
    let minutes = (in_day / 60_000).clamp(0, 24 * 60 - 1);
    let month = MONTHS.get((m as usize).saturating_sub(1)).copied().unwrap_or("");
    format!("{d} {month} {:02}:{:02}", minutes / 60, minutes % 60)
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
