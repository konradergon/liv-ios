//! The new seam: one verb per screen.
//!
//! **What this replaced.** The core-era `liv_snapshot` handed a shell the
//! whole box as one JSON document — 3.5 MB and 39 ms at 6,400 notes,
//! rebuilt on every refresh, linear in the box and independent of what is
//! on screen — and the shell then searched it to work out what Today is. Here a screen
//! asks for itself and gets itself: the payload is proportional to the
//! answer, and the deciding happens in `liv-surface`, where `cargo test`
//! can reach it (`rust-owns-the-mechanisms.md` §3).
//!
//! ## Why these verbs do not mirror `with_box`
//!
//! `CLAUDE.md` asks ABI additions to mirror `with_box` + `Committed`. That
//! pattern exists for `core/`: open the file, replay the log, take the
//! process-wide lock, and hand back a `Session` — plus a five-field cache
//! to avoid re-reading a log that has not changed. None of it applies. The
//! engine is a database: opening is 0.3 ms and flat in the size of the
//! box, SQLite does its own locking in WAL mode, and there is no replay to
//! skip. So a connection is kept per box and reused, and that is the whole
//! of it.
//!
//! ## The shape of a call
//!
//! Every verb returns `int32_t`: `LIV_OK`, or a negative code saying what
//! went wrong. The answer comes back through an out-pointer, which the
//! caller frees with `liv_string_free`. **Zero never means failure here** —
//! the old ABI's `0` is both "no id" and "it broke", which is why a shell
//! could not tell an empty box from an unreadable one.
//!
//! Ids cross as 32 lowercase hex characters, because an `EntityId` is 16
//! bytes and a JSON number is not (`core-decisions.md`: the ABI is
//! designed for 16-byte ids from the start, so none of the 39-of-57
//! retrofit cost applies).

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use liv_engine::{Engine, EntityId};
use liv_surface::calendar::calendar;
use liv_surface::library::library;
use liv_surface::reminders::reminders;
use liv_surface::tasks::tasks;
use liv_surface::today::today;
use liv_surface::{Lens, Row};
use serde::Serialize;

// ---- the error channel -------------------------------------------------

pub const LIV_OK: i32 = 0;
/// The path was not valid UTF-8, or was null.
pub const LIV_ERR_PATH: i32 = -1;
/// The box would not open — missing directory, permissions, or a box
/// written by a newer build.
pub const LIV_ERR_OPEN: i32 = -2;
/// A parameter did not parse: a malformed id, a lens
/// that was not a JSON array of hex ids.
pub const LIV_ERR_ARG: i32 = -3;
/// The box opened and then refused the read.
pub const LIV_ERR_READ: i32 = -4;
/// The answer would not encode — a bug here, never the caller's fault.
pub const LIV_ERR_ENCODE: i32 = -5;

// ---- the open boxes ----------------------------------------------------

static BOXES: OnceLock<Mutex<HashMap<PathBuf, Engine>>> = OnceLock::new();

fn boxes() -> &'static Mutex<HashMap<PathBuf, Engine>> {
    BOXES.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Run `work` against the box at `path`, opening it once and keeping it.
///
/// The connection is held rather than reopened because a shell asks
/// several of these per screen, and SQLite's own locking makes holding one
/// safe — WAL is why the share extension can read while the app writes,
/// which is the reason SQLite was chosen (`core-decisions.md` §5).
pub(crate) fn with_engine<T>(
    path: *const c_char,
    work: impl FnOnce(&mut Engine) -> Result<T, i32>,
) -> Result<T, i32> {
    if path.is_null() {
        return Err(LIV_ERR_PATH);
    }
    let path = unsafe { CStr::from_ptr(path) }.to_str().map_err(|_| LIV_ERR_PATH)?;
    let path = PathBuf::from(path);

    let mut open = boxes().lock().map_err(|_| LIV_ERR_OPEN)?;
    if !open.contains_key(&path) {
        let engine = Engine::open_local(&path).map_err(|_| LIV_ERR_OPEN)?;
        open.insert(path.clone(), engine);
    }
    work(open.get_mut(&path).expect("just inserted"))
}

/// Hand a JSON answer back through the out-pointer.
pub(crate) fn deliver<T: Serialize>(out: *mut *mut c_char, value: &T) -> i32 {
    if out.is_null() {
        return LIV_ERR_ARG;
    }
    let Ok(json) = serde_json::to_string(value) else { return LIV_ERR_ENCODE };
    let Ok(c) = CString::new(json) else { return LIV_ERR_ENCODE };
    unsafe { *out = c.into_raw() };
    LIV_OK
}

/// Forget every open box. A test seam, and the thing a shell calls when it
/// is about to move or replace a box file.
///
/// # Safety
/// No other thread may be inside a `liv_view_*` call on this process.
#[no_mangle]
pub unsafe extern "C" fn liv_view_close_all() {
    if let Ok(mut open) = boxes().lock() {
        open.clear();
    }
}

// ---- arguments ---------------------------------------------------------

pub(crate) fn parse_id(hex: &str) -> Option<EntityId> {
    if hex.len() != 32 {
        return None;
    }
    let mut out = [0u8; 16];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(hex.get(i * 2..i * 2 + 2)?, 16).ok()?;
    }
    Some(EntityId(out))
}

/// The lens, as a JSON array of hex ids — or null for "everything".
///
/// **Null is not the empty array.** A workspace whose query matches
/// nothing admits nothing, and that is a real, showable state; passing
/// null to mean it would silently turn a filtered-to-empty screen into an
/// unfiltered one, which is the more alarming of the two failures.
pub(crate) fn parse_lens(lens: *const c_char) -> Result<Lens, i32> {
    if lens.is_null() {
        return Ok(Lens::Everything);
    }
    let raw = unsafe { CStr::from_ptr(lens) }.to_str().map_err(|_| LIV_ERR_ARG)?;
    Ok(Lens::Only(id_list(raw)?.into_iter().collect()))
}

/// A JSON array of hex ids — the one way a list of things crosses in. Any
/// entry that is not an id refuses the whole list: acting on the part
/// that parsed would be acting on something nobody asked for.
pub(crate) fn id_list(raw: &str) -> Result<Vec<EntityId>, i32> {
    let ids: Vec<String> = serde_json::from_str(raw).map_err(|_| LIV_ERR_ARG)?;
    ids.iter().map(|hex| parse_id(hex).ok_or(LIV_ERR_ARG)).collect()
}

// ---- the wire shapes ---------------------------------------------------
//
// **A wire type, not the surface type.** `liv-surface` stays free of
// serde and of any opinion about JSON, so that a desktop can link it and
// hand its rows to something else entirely. The one thing this layer adds
// is the encoding of an id as hex, and that belongs exactly here.

fn hex(id: EntityId) -> String {
    id.hex()
}

#[derive(Serialize)]
struct WireRow {
    id: String,
    title: String,
    untitled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    due_ms: Option<i64>,
    all_day: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    status: Option<String>,
    done: bool,
    /// Open, a task, and its day has passed. Only the surfaces told the
    /// day set it — Today, Tasks and the library — and it is false on the
    /// rest.
    late: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    area: Option<String>,
    created_ms: i64,
    touched_ms: i64,
    has_file: bool,
    /// **Does it hold any words?** Four shell surfaces ask it and none
    /// of them could get an answer: on `core/` it was the body's
    /// compare-and-swap print being non-zero, and the engine hands that
    /// print back per body rather than per row. So the Inbox listed
    /// nothing to route while the panel counted eight captures (owner,
    /// 2026-09-15). Free — `surface::row` already reads the body cell.
    has_body: bool,
    /// **The word for the kind, not its id**, and lowercase: `note`,
    /// `task`, `event`. It is the same spelling the query grammar uses
    /// (`type:task`), so one word means one thing everywhere.
    ///
    /// §3 says a surface verb hands back the strings the row will draw.
    /// Sending only the id would make every shell keep its own map from
    /// id to word — which is the shell-side furnishing `one-core.md` §4
    /// records as a mistake, rebuilt one layer up.
    #[serde(skip_serializing_if = "Option::is_none")]
    kind_word: Option<String>,
    /// The status as a person reads it. A DISPLAY name, not a stable
    /// word: a status is an option someone can rename, and the rename is
    /// supposed to show.
    #[serde(skip_serializing_if = "Option::is_none")]
    status_word: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    area_word: Option<String>,
    /// Filed away, which is NOT thrown away. Every surface but the
    /// archive hides these, and the shell needs to know which it is
    /// looking at.
    archived: bool,
    /// In the trash. Always false on every surface except `liv_view_trash`
    /// — they filter it — but the shell indexes rows from both and must
    /// not have to remember which list a row came from.
    trashed: bool,
}

impl From<&Row> for WireRow {
    fn from(r: &Row) -> WireRow {
        WireRow {
            id: hex(r.id),
            title: r.title.clone(),
            untitled: r.untitled,
            kind: r.kind.map(hex),
            due_ms: r.due_ms,
            all_day: r.all_day,
            status: r.status.map(hex),
            done: r.done,
            late: r.late,
            area: r.area.map(hex),
            created_ms: r.created_ms,
            touched_ms: r.touched_ms,
            has_file: r.has_file,
            has_body: r.has_body,
            archived: r.archived,
            trashed: r.trashed,
            kind_word: r.kind_word.clone(),
            status_word: r.status_word.clone(),
            area_word: r.area_word.clone(),
        }
    }
}

/// The same rows, as JSON, for a verb outside this module.
pub(crate) fn rows_json(rows: &[Row]) -> serde_json::Value {
    serde_json::to_value(wire(rows)).unwrap_or(serde_json::Value::Null)
}

fn wire(rows: &[Row]) -> Vec<WireRow> {
    rows.iter().map(WireRow::from).collect()
}

#[derive(Serialize)]
struct WireToday {
    days: Vec<WireTodayDay>,
    late: Vec<WireRow>,
    what_next: Vec<WireRow>,
    captured: usize,
}

#[derive(Serialize)]
struct WireTodayDay {
    day: i32,
    all_day: Vec<WireRow>,
    passed: Vec<WireRow>,
    ahead: Vec<WireRow>,
    done: Vec<WireRow>,
    areas: Vec<WireCount>,
    unfiled: usize,
}

#[derive(Serialize)]
struct WireCount {
    name: String,
    count: usize,
}

#[derive(Serialize)]
struct WireGroup {
    #[serde(skip_serializing_if = "Option::is_none")]
    status: Option<String>,
    name: String,
    completes: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    hue: Option<i64>,
    late: usize,
    rows: Vec<WireRow>,
}

#[derive(Serialize)]
struct WireNoteLine {
    note: String,
    source: String,
    line: usize,
    text: String,
    depth: u8,
}

#[derive(Serialize)]
struct WireNamed {
    id: String,
    name: String,
}

#[derive(Serialize)]
struct WireTasks {
    groups: Vec<WireGroup>,
    open: usize,
    late: usize,
    in_notes: Vec<WireNoteLine>,
    projects: Vec<WireNamed>,
}

#[derive(Serialize)]
struct WireLibrary {
    all: Vec<WireRow>,
    notes: Vec<String>,
    unsorted: Vec<String>,
    counts: WireCounts,
}

#[derive(Serialize)]
struct WireCounts {
    today: usize,
    unsorted: usize,
    notes: usize,
    tasks: usize,
    events: usize,
}

#[derive(Serialize)]
struct WireReminders {
    soonest: Vec<WireRow>,
    total: usize,
}

#[derive(Serialize)]
struct WireCalendarDay {
    day: i32,
    all_day: Vec<WireRow>,
    timed: Vec<WireRow>,
}

// ---- the verbs ---------------------------------------------------------

/// The Today screen: the seven days of the strip, each split into its
/// piles and counted by area, plus what is late, what is next and what was
/// caught today.
///
/// `now_ms` is the real instant and `offset_min` the phone's distance from
/// UTC in minutes; "today" is the day on the phone's clock.
///
/// # Safety
/// `path` and `lens` must be null or valid C strings; `out` must be a
/// valid pointer to a `char *` the caller will free with
/// `liv_string_free`.
#[no_mangle]
pub unsafe extern "C" fn liv_view_today(
    path: *const c_char,
    now_ms: i64,
    offset_min: i32,
    lens: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let lens = match parse_lens(lens) {
        Ok(l) => l,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let t = today(e, now_ms, offset_min, &lens).map_err(|_| LIV_ERR_READ)?;
        Ok(WireToday {
            days: t
                .days
                .iter()
                .map(|d| WireTodayDay {
                    day: d.day,
                    all_day: wire(&d.all_day),
                    passed: wire(&d.passed),
                    ahead: wire(&d.ahead),
                    done: wire(&d.done),
                    areas: d
                        .areas
                        .iter()
                        .map(|(name, count)| WireCount { name: name.clone(), count: *count })
                        .collect(),
                    unfiled: d.unfiled,
                })
                .collect(),
            late: wire(&t.late),
            what_next: wire(&t.what_next),
            captured: t.captured,
        })
    }) {
        Ok(t) => deliver(out, &t),
        Err(e) => e,
    }
}

/// The Tasks screen: every task grouped by status, the screen's counts,
/// the open lines in notes, and the projects its menu offers. `project`
/// is a hex id or null; it narrows the groups and nothing else.
///
/// # Safety
/// As `liv_view_today`.
#[no_mangle]
pub unsafe extern "C" fn liv_view_tasks(
    path: *const c_char,
    project: *const c_char,
    today_day: i32,
    lens: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let lens = match parse_lens(lens) {
        Ok(l) => l,
        Err(e) => return e,
    };
    let project = if project.is_null() {
        None
    } else {
        match unsafe { CStr::from_ptr(project) }.to_str().ok().and_then(parse_id) {
            Some(id) => Some(id),
            None => return LIV_ERR_ARG,
        }
    };
    match with_engine(path, |e| {
        let t = tasks(e, project, &lens, today_day).map_err(|_| LIV_ERR_READ)?;
        Ok(WireTasks {
            groups: t
                .groups
                .iter()
                .map(|g| WireGroup {
                    status: g.status.map(hex),
                    name: g.name.clone(),
                    completes: g.completes,
                    hue: g.hue,
                    late: g.late,
                    rows: wire(&g.rows),
                })
                .collect(),
            open: t.open,
            late: t.late,
            in_notes: t
                .in_notes
                .into_iter()
                .map(|l| WireNoteLine {
                    note: hex(l.note),
                    source: l.source,
                    line: l.line,
                    text: l.text,
                    depth: l.depth,
                })
                .collect(),
            projects: t
                .projects
                .into_iter()
                .map(|(id, name)| WireNamed { id: hex(id), name })
                .collect(),
        })
    }) {
        Ok(t) => deliver(out, &t),
        Err(e) => e,
    }
}

/// The library: every live row (what a shell looks a thing up in), the
/// Notes and Unsorted lists as ids into it, and the count beside each view
/// in the library panel — one pass over the box.
///
/// `now_ms` and `offset_min` as `liv_view_today`. The lens narrows Notes
/// and the counts; it never narrows `all` or Unsorted.
///
/// # Safety
/// As `liv_view_today`.
#[no_mangle]
pub unsafe extern "C" fn liv_view_library(
    path: *const c_char,
    now_ms: i64,
    offset_min: i32,
    lens: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let lens = match parse_lens(lens) {
        Ok(l) => l,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let l = library(e, now_ms, offset_min, &lens).map_err(|_| LIV_ERR_READ)?;
        Ok(WireLibrary {
            all: wire(&l.all),
            notes: l.notes.into_iter().map(hex).collect(),
            unsorted: l.unsorted.into_iter().map(hex).collect(),
            counts: WireCounts {
                today: l.counts.today,
                unsorted: l.counts.unsorted,
                notes: l.counts.notes,
                tasks: l.counts.tasks,
                events: l.counts.events,
            },
        })
    }) {
        Ok(l) => deliver(out, &l),
        Err(e) => e,
    }
}

/// The reminders still to come on the phone's clock, soonest first: the
/// first `limit`, and how many in all. `now_ms` and `offset_min` as
/// `liv_view_today`. Which things ring is Rust's; turning a wall-clock due
/// into an alarm, and the phone's own cap on pending alarms, are the
/// shell's.
///
/// # Safety
/// `path` must be a valid C string; `out` as `liv_view_today`.
#[no_mangle]
pub unsafe extern "C" fn liv_view_reminders(
    path: *const c_char,
    now_ms: i64,
    offset_min: i32,
    limit: u32,
    out: *mut *mut c_char,
) -> i32 {
    match with_engine(path, |e| {
        let r = reminders(e, now_ms, offset_min, limit as usize).map_err(|_| LIV_ERR_READ)?;
        Ok(WireReminders { soonest: wire(&r.soonest), total: r.total })
    }) {
        Ok(r) => deliver(out, &r),
        Err(e) => e,
    }
}

/// The calendar: every day from `from_day` to `to_day` (days since the
/// epoch, both included) that has anything on it, its all-day things apart
/// from its timed ones, each in time order.
///
/// # Safety
/// As `liv_view_today`.
#[no_mangle]
pub unsafe extern "C" fn liv_view_day(
    path: *const c_char,
    from_day: i32,
    to_day: i32,
    lens: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let lens = match parse_lens(lens) {
        Ok(l) => l,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let days = calendar(e, from_day, to_day, &lens).map_err(|_| LIV_ERR_READ)?;
        Ok(days
            .iter()
            .map(|d| WireCalendarDay {
                day: d.day,
                all_day: wire(&d.all_day),
                timed: wire(&d.timed),
            })
            .collect::<Vec<_>>())
    }) {
        Ok(d) => deliver(out, &d),
        Err(e) => e,
    }
}

// ---- the one-way door --------------------------------------------------
