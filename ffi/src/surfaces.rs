//! The new seam: one verb per screen.
//!
//! **What this replaces.** `liv_snapshot` hands a shell the whole box as
//! one JSON document — 3.5 MB and 39 ms at 6,400 notes, rebuilt on every
//! refresh, linear in the box and independent of what is on screen — and
//! the shell then searches it to work out what Today is. Here a screen
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
use liv_surface::day::Block;
use liv_surface::everything::{everything, Slice};
use liv_surface::tasks::{tasks, Filter};
use liv_surface::today::today;
use liv_surface::{day as day_surface, Lens, Row};
use serde::Serialize;

// ---- the error channel -------------------------------------------------

pub const LIV_OK: i32 = 0;
/// The path was not valid UTF-8, or was null.
pub const LIV_ERR_PATH: i32 = -1;
/// The box would not open — missing directory, permissions, or a box
/// written by a newer build.
pub const LIV_ERR_OPEN: i32 = -2;
/// A parameter did not parse: an unknown slice, a malformed id, a lens
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
fn with_engine<T>(
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
fn deliver<T: Serialize>(out: *mut *mut c_char, value: &T) -> i32 {
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

fn parse_id(hex: &str) -> Option<EntityId> {
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
fn parse_lens(lens: *const c_char) -> Result<Lens, i32> {
    if lens.is_null() {
        return Ok(Lens::Everything);
    }
    let raw = unsafe { CStr::from_ptr(lens) }.to_str().map_err(|_| LIV_ERR_ARG)?;
    let ids: Vec<String> = serde_json::from_str(raw).map_err(|_| LIV_ERR_ARG)?;
    let mut out = std::collections::HashSet::with_capacity(ids.len());
    for hex in ids {
        out.insert(parse_id(&hex).ok_or(LIV_ERR_ARG)?);
    }
    Ok(Lens::Only(out))
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
    #[serde(skip_serializing_if = "Option::is_none")]
    area: Option<String>,
    created_ms: i64,
    touched_ms: i64,
    has_file: bool,
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
            area: r.area.map(hex),
            created_ms: r.created_ms,
            touched_ms: r.touched_ms,
            has_file: r.has_file,
        }
    }
}

fn wire(rows: &[Row]) -> Vec<WireRow> {
    rows.iter().map(WireRow::from).collect()
}

#[derive(Serialize)]
struct WireToday {
    late: Vec<WireRow>,
    passed: Vec<WireRow>,
    ahead: Vec<WireRow>,
    all_day: Vec<WireRow>,
    done: Vec<WireRow>,
    #[serde(skip_serializing_if = "Option::is_none")]
    next: Option<String>,
    captured: usize,
}

#[derive(Serialize)]
struct WireGroup {
    #[serde(skip_serializing_if = "Option::is_none")]
    status: Option<String>,
    name: String,
    completes: bool,
    late: usize,
    rows: Vec<WireRow>,
}

#[derive(Serialize)]
struct WireBlock {
    row: WireRow,
    start_min: i32,
    minutes: i32,
    column: usize,
    columns: usize,
}

impl From<&Block> for WireBlock {
    fn from(b: &Block) -> WireBlock {
        WireBlock {
            row: WireRow::from(&b.row),
            start_min: b.start_min,
            minutes: b.minutes,
            column: b.column,
            columns: b.columns,
        }
    }
}

#[derive(Serialize)]
struct WireDay {
    all_day: Vec<WireRow>,
    blocks: Vec<WireBlock>,
}

// ---- the verbs ---------------------------------------------------------

/// Today: the agenda for `day`, split into its five piles, plus what is
/// late and what was caught.
///
/// `day` and `today` are days since the epoch and differ whenever the date
/// strip has been moved — several rules turn on whether they are the same.
///
/// # Safety
/// `path` and `lens` must be null or valid C strings; `out` must be a
/// valid pointer to a `char *` the caller will free with
/// `liv_string_free`.
#[no_mangle]
pub unsafe extern "C" fn liv_view_today(
    path: *const c_char,
    day: i32,
    today_day: i32,
    now_ms: i64,
    lens: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let lens = match parse_lens(lens) {
        Ok(l) => l,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let t = today(e, day, today_day, now_ms, &lens).map_err(|_| LIV_ERR_READ)?;
        Ok(WireToday {
            late: wire(&t.late),
            passed: wire(&t.passed),
            ahead: wire(&t.ahead),
            all_day: wire(&t.all_day),
            done: wire(&t.done),
            next: t.next.map(hex),
            captured: t.captured,
        })
    }) {
        Ok(t) => deliver(out, &t),
        Err(e) => e,
    }
}

/// Tasks, grouped by status. `filter` is 0 all, 1 status, 2 project;
/// `filter_id` is the hex id it names and is ignored when `filter` is 0.
///
/// # Safety
/// As `liv_view_today`.
#[no_mangle]
pub unsafe extern "C" fn liv_view_tasks(
    path: *const c_char,
    filter: i32,
    filter_id: *const c_char,
    today_day: i32,
    lens: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let lens = match parse_lens(lens) {
        Ok(l) => l,
        Err(e) => return e,
    };
    let named = || -> Option<EntityId> {
        if filter_id.is_null() {
            return None;
        }
        parse_id(unsafe { CStr::from_ptr(filter_id) }.to_str().ok()?)
    };
    let filter = match filter {
        0 => Filter::All,
        1 => match named() {
            Some(id) => Filter::Status(id),
            None => return LIV_ERR_ARG,
        },
        2 => match named() {
            Some(id) => Filter::Project(id),
            None => return LIV_ERR_ARG,
        },
        _ => return LIV_ERR_ARG,
    };
    match with_engine(path, |e| {
        let groups = tasks(e, filter, &lens, today_day).map_err(|_| LIV_ERR_READ)?;
        Ok(groups
            .iter()
            .map(|g| WireGroup {
                status: g.status.map(hex),
                name: g.name.clone(),
                completes: g.completes,
                late: g.late,
                rows: wire(&g.rows),
            })
            .collect::<Vec<_>>())
    }) {
        Ok(g) => deliver(out, &g),
        Err(e) => e,
    }
}

/// Everything, in one slice: 0 all, 1 notes, 2 upcoming, 3 unfiled.
///
/// # Safety
/// As `liv_view_today`.
#[no_mangle]
pub unsafe extern "C" fn liv_view_everything(
    path: *const c_char,
    slice: i32,
    today_day: i32,
    lens: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let lens = match parse_lens(lens) {
        Ok(l) => l,
        Err(e) => return e,
    };
    let slice = match slice {
        0 => Slice::All,
        1 => Slice::Notes,
        2 => Slice::Upcoming,
        3 => Slice::Unfiled,
        _ => return LIV_ERR_ARG,
    };
    match with_engine(path, |e| {
        let rows = everything(e, slice, &lens, today_day).map_err(|_| LIV_ERR_READ)?;
        Ok(wire(&rows))
    }) {
        Ok(r) => deliver(out, &r),
        Err(e) => e,
    }
}

/// The calendar's day: the all-day strip, and the timeline's blocks with
/// their columns already worked out.
///
/// # Safety
/// As `liv_view_today`.
#[no_mangle]
pub unsafe extern "C" fn liv_view_day(
    path: *const c_char,
    day: i32,
    lens: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let lens = match parse_lens(lens) {
        Ok(l) => l,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let d = day_surface::day(e, day, &lens).map_err(|_| LIV_ERR_READ)?;
        Ok(WireDay {
            all_day: wire(&d.all_day),
            blocks: d.blocks.iter().map(WireBlock::from).collect(),
        })
    }) {
        Ok(d) => deliver(out, &d),
        Err(e) => e,
    }
}

// ---- the one-way door --------------------------------------------------

/// Build an engine box from a `core/` box.
///
/// **Refuses if the target exists**, because "run it again" is the first
/// thing anyone tries and a converter that allows it can double a box. To
/// rebuild, delete the file first — which is also how a shell says "throw
/// the conversion away and take the core box as truth again".
///
/// The answer is the report as JSON:
/// `{"entities","cells","resolved","minted_vocabulary",
///   "files_dropped","undeclared","unknown_kinds":[…],"clean"}`
///
/// # Safety
/// `from` and `to` must be valid C strings; `out` a valid `char *` slot.
#[no_mangle]
pub unsafe extern "C" fn liv_view_convert(
    from: *const c_char,
    to: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    if from.is_null() || to.is_null() {
        return LIV_ERR_PATH;
    }
    let Ok(from) = unsafe { CStr::from_ptr(from) }.to_str() else { return LIV_ERR_PATH };
    let Ok(to) = unsafe { CStr::from_ptr(to) }.to_str() else { return LIV_ERR_PATH };
    let to_path = PathBuf::from(to);

    // A held connection to the target would keep the file open while it is
    // being replaced or deleted; drop everything first.
    unsafe { liv_view_close_all() };

    match liv_convert::convert(std::path::Path::new(from), &to_path) {
        Ok(r) => {
            let report = WireReport {
                entities: r.entities,
                cells: r.cells,
                resolved: r.resolved,
                minted_vocabulary: r.minted_vocabulary,
                files_dropped: r.files_dropped,
                undeclared: r.undeclared,
                clean: r.clean(),
                unknown_kinds: r.unknown_kinds,
            };
            deliver(out, &report)
        }
        // The box is there and would not convert, which is neither a bad
        // path nor a bad argument: the source refused to be read.
        Err(_) => LIV_ERR_READ,
    }
}

#[derive(Serialize)]
struct WireReport {
    entities: usize,
    cells: usize,
    resolved: usize,
    minted_vocabulary: usize,
    files_dropped: usize,
    undeclared: usize,
    clean: bool,
    unknown_kinds: Vec<String>,
}
