//! The one C seam the macOS shell crosses — milestone 4, reshaped by the
//! single-writer lock of the review: the agent holds no session. Capture
//! opens the box, writes, and closes — the lock lives for milliseconds,
//! so the CLI stays usable while the agent sits in the menu bar.
//!
//! The clerk is not run here: pending proposals are re-derived by the
//! sweep at every open, so the next `lotus inbox` sees exactly what this
//! capture deserved.

use std::ffi::{c_char, CStr, CString};

use chrono::{Datelike, Local, Timelike};
use serde::Serialize;

use std::collections::HashMap;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use lotus_core::{props, Author, DateTime, Entity, Id, Session, Store, Value};
use lotus_services::{clerk, files, property_id, run, search, Constraint, Op, Query, Sort};

/// Capture one scrap into the box at `path`, creating and seeding the box
/// if it is fresh. Returns the new entity's id, or 0 on failure — 0 is
/// never a valid id. Whitespace-only text is a failure, not a scrap.
/// Fails (rather than waits) if another process holds the box open.
///
/// # Safety
/// `path` and `text` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_capture_at(path: *const c_char, text: *const c_char) -> u64 {
    if path.is_null() || text.is_null() {
        return 0;
    }
    let (Ok(path), Ok(text)) = (CStr::from_ptr(path).to_str(), CStr::from_ptr(text).to_str())
    else {
        return 0;
    };
    let text = text.trim();
    if text.is_empty() {
        return 0;
    }

    if let Some(dir) = std::path::Path::new(path).parent() {
        if std::fs::create_dir_all(dir).is_err() {
            return 0;
        }
    }
    let Ok(mut session) = Session::open(path) else {
        return 0;
    };
    if lotus_services::seed_if_fresh(&mut session).is_err() {
        return 0;
    }

    let now = Local::now();
    let created = DateTime::at(
        now.year(),
        now.month(),
        now.day(),
        now.hour(),
        now.minute(),
    );
    lotus_services::capture(&mut session, text, created).unwrap_or(0)
}

// ---- the window's read: one JSON snapshot ----
// The shell renders from a snapshot and never holds the box: every call
// opens, reads (or writes), closes. The lock lives for milliseconds.

#[derive(Serialize)]
struct CellRow {
    /// The property definition's id — the inspector keys the catalog off
    /// it to render the right control and pick options.
    property_id: Id,
    property: String,
    /// The value-kind of the property: text/number/bool/datetime/select/
    /// reference/richtext/file — empty when the property has no kind.
    kind: String,
    value: String,
    /// For select/reference cells, the referenced entity's id — so the
    /// picker pre-selects and edits by id.
    ref_target: Option<Id>,
}

#[derive(Serialize)]
struct OptionRow {
    id: Id,
    name: String,
}

/// One property definition — the inspector's catalog: its kind, and for
/// a select, its option entities.
#[derive(Serialize)]
struct PropertyRow {
    id: Id,
    name: String,
    kind: String,
    options: Vec<OptionRow>,
}

#[derive(Serialize)]
struct EntityRow {
    id: Id,
    title: String,
    kinds: Vec<String>,
    due: Option<i64>,
    due_date_only: bool,
    status: Option<String>,
    created: Option<i64>,
    trashed: bool,
    bookmarked: bool,
    archived: bool,
    /// Fingerprint of the stored content value, 0 when none — the editor
    /// learns from every snapshot whether its base moved, for free.
    content_print: u64,
    cells: Vec<CellRow>,
}

#[derive(Serialize)]
struct OccurrenceRow {
    series: Id,
    civil: i64,
}

#[derive(Serialize)]
struct ProposalRow {
    entity: Id,
    /// 1-based position among this entity's proposals, in sweep order —
    /// the same addressing the CLI uses, stable across processes.
    ordinal: u32,
    /// Deterministic hash of the proposal's commands. Triage must present
    /// it back and it must still match: a consent is to a proposal, never
    /// to a position that may have shifted since the snapshot.
    fingerprint: u64,
    reason: String,
    author: String,
}

/// FNV-1a over the serialized commands — deterministic across processes,
/// because the sweep is deterministic.
fn fingerprint(proposal: &lotus_core::Proposal) -> u64 {
    lotus_services::content::fnv(&serde_json::to_vec(&proposal.commands).unwrap_or_default())
}

#[derive(Serialize)]
struct WorkspaceRow {
    id: Id,
    name: String,
    emoji: Option<String>,
    favorite: bool,
    archived: bool,
    /// "home" for the protected built-in; empty otherwise.
    builtin: String,
    /// 0 = top level; the tree is parent references, nothing else.
    parent: Id,
    order: f64,
}

#[derive(Serialize)]
struct Snapshot {
    today: Vec<Id>,
    unstructured: Vec<Id>,
    everything: Vec<Id>,
    dated: Vec<Id>,
    /// Virtual: this month's expansion of every recurring series,
    /// computed in services — never stored, same answer for every view.
    occurrences: Vec<OccurrenceRow>,
    inbox: Vec<ProposalRow>,
    /// Navigation chrome: working entities of type workspace, whole
    /// tree, archived included (the shell draws the Archive group).
    workspaces: Vec<WorkspaceRow>,
    /// Every property definition — the inspector's catalog.
    properties: Vec<PropertyRow>,
    entities: Vec<EntityRow>,
}

/// Open the box, seed if fresh, and fill the queue with the clerk's sweep —
/// the same ritual every shell performs.
// ---- the per-box store cache: skip re-reading an unchanged append-only log ----
//
// design/perf-incremental-open.md. Every FFI call used to `Session::open` —
// read_to_end + parse + replay the WHOLE log — on every tab switch, snapshot,
// and save: O(history) per interaction, the tab-lag root cause. The log is
// append-only, so an unchanged byte length is proof no committed record
// changed; on that fast path we serve the cached `Store` and never touch the
// bytes. We still open + `try_lock` every call, so single-writer coexistence
// is untouched — only the redundant re-read is gone.

struct Cached {
    store: Store,
    /// The log's byte length when we cached — append-only ⇒ equal length on the
    /// next open proves nothing was appended (the whole fast-path validator).
    log_len: u64,
    /// The two sidecars' lengths, tracked SEPARATELY (not summed). A decline
    /// moves a proposal from .pending to .declined — the same bytes — so the
    /// combined length is unchanged and would miss it; the individual lengths
    /// both move. Sidecars are rewritten off the main log, so its length alone
    /// can't witness a sidecar change (Guard 2).
    declined_len: u64,
    pending_len: u64,
    /// The log's inode — a same-length file REPLACEMENT at the same path is
    /// caught here (Guard 3).
    inode: u64,
    /// The header version the log carries — a cached session must know
    /// whether the span fence (v2) is already raised, or a second span write
    /// would try to raise it again.
    header_version: u32,
}

static CACHE: OnceLock<Mutex<HashMap<PathBuf, Cached>>> = OnceLock::new();

fn cache() -> &'static Mutex<HashMap<PathBuf, Cached>> {
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Forget every cached store — a test seam to force the next open down the full
/// replay path, so a cache hit can be checked against a from-scratch replay.
#[cfg(test)]
fn clear_cache_for_tests() {
    if let Some(map) = CACHE.get() {
        map.lock().unwrap().clear();
    }
}

/// Byte lengths of the two sidecars (.declined, .pending), counting an absent
/// one as 0. Returned separately so a decline — which moves the same bytes from
/// .pending to .declined — is witnessed (the combined length would not move).
fn sidecar_lens(key: &Path) -> (u64, u64) {
    let of = |suffix: &str| {
        let mut name = key.as_os_str().to_owned();
        name.push(suffix);
        std::fs::metadata(PathBuf::from(name)).map(|m| m.len()).unwrap_or(0)
    };
    (of(".declined"), of(".pending"))
}

/// Open the box, serving the cached store when the append-only log (its length,
/// its sidecars, and its inode) is unchanged. Returns the session and its
/// canonical cache key, or None when the box can't be opened or is held
/// elsewhere. On a MISS it seeds + sweeps exactly as the old `open_swept` did;
/// on a HIT it does neither — both are pure functions of the store and already
/// reflected in the cached one (perf design §1.4).
///
/// Guard 5: the file is `try_lock`ed on EVERY path before the cache is
/// consulted, so a CLI holding the box yields busy, never a stale hit.
unsafe fn open_box(raw_path: *const c_char) -> Option<(Session, PathBuf)> {
    if raw_path.is_null() {
        return None;
    }
    let path_str = CStr::from_ptr(raw_path).to_str().ok()?;
    let path = Path::new(path_str);
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).ok()?;
    }

    let file = std::fs::OpenOptions::new()
        .create(true)
        .read(true)
        .append(true)
        .open(path)
        .ok()?;
    if file.try_lock().is_err() {
        return None; // Locked (or io) -> the caller's busy value, never a hit
    }

    let meta = file.metadata().ok()?;
    let cur_len = meta.len();
    let cur_inode = meta.ino();
    let key = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let (cur_decl, cur_pend) = sidecar_lens(&key);

    // Fast path: the cached store is still the log's whole consequence.
    {
        let mut map = cache().lock().unwrap();
        let fresh = map.get(&key).is_some_and(|c| {
            c.log_len == cur_len
                && c.declined_len == cur_decl
                && c.pending_len == cur_pend
                && c.inode == cur_inode
        });
        if fresh {
            let hit = map.remove(&key).unwrap();
            return Some((
                Session::from_cached(hit.store, file, path, hit.header_version),
                key,
            ));
        }
    }

    // Slow path: replay the log on the handle we already locked, then the
    // idempotent seed and the deterministic sweep (only ever here, §1.4).
    let mut session = Session::open_on(file, path).ok()?;
    lotus_services::seed_if_fresh(&mut session).ok()?;
    let today = civil_today();
    for proposal in clerk::sweep(session.store(), today) {
        if session.propose(proposal).is_err() {
            return None;
        }
    }
    Some((session, key))
}

/// Reconcile the cache on the way out: cache the store on a read, re-sweep then
/// cache on a write, or evict on a failed / poisoned write so a phantom write is
/// never served (Guards 4/6). Length + inode are read from the still-locked
/// handle before the session drops, so no external append can race in.
fn checkin(key: PathBuf, mut session: Session, committed: Committed) {
    match committed {
        // Unchanged and already swept — cache verbatim.
        Committed::Read => cache_store(key, session),
        // A write changed the store's content, and the next open is a cache HIT
        // that will NOT sweep — so re-derive proposals now (any retraction of a
        // now-stale proposal already happened inside the mutation) and cache the
        // swept store. A propose failure poisons: evict instead of caching.
        Committed::Wrote => {
            let today = civil_today();
            let proposals = clerk::sweep(session.store(), today);
            for proposal in proposals {
                if session.propose(proposal).is_err() {
                    cache().lock().unwrap().remove(&key);
                    return;
                }
            }
            cache_store(key, session);
        }
        Committed::Failed => {
            cache().lock().unwrap().remove(&key);
        }
    }
}

/// Snapshot the session's store into the cache with the log's post-op length +
/// inode, read from the still-locked handle before the session (its lock)
/// drops — so no external append can race between the stat and the write.
fn cache_store(key: PathBuf, session: Session) {
    let Ok(meta) = session.log_file_meta() else {
        cache().lock().unwrap().remove(&key);
        return;
    };
    let (declined_len, pending_len) = sidecar_lens(&key);
    let entry = Cached {
        log_len: meta.len(),
        inode: meta.ino(),
        declined_len,
        pending_len,
        header_version: session.header_version(),
        store: session.into_store(), // consumes the session -> drops the lock
    };
    cache().lock().unwrap().insert(key, entry);
}

/// What a `with_box` closure did, so check-in knows how to reconcile the cache.
/// The subtlety the perf design missed: after a write the NEXT open is a cache
/// HIT that skips the sweep, so a write must re-derive proposals itself.
enum Committed {
    /// A read, or a mutation the guard refused without touching the store: the
    /// store is unchanged and already swept — cache it verbatim.
    Read,
    /// A mutation that changed the store: re-sweep before caching (proposals are
    /// a function of content, and the next open won't sweep).
    Wrote,
    /// A mutation that failed to persist, or a create whose id was burned before
    /// a failed commit: evict, so a phantom / poisoned write is never served,
    /// and the next open replays only what reached disk (Guards 4/6).
    Failed,
}

/// The ONE choke point every box-opening FFI entry routes through. Opens the
/// box (cache-fast when the log is unchanged), runs `f` against the live
/// session, checks the result back into the cache, and returns f's value — or
/// `busy` when the box can't be opened or is held elsewhere.
unsafe fn with_box<T>(
    path: *const c_char,
    busy: T,
    f: impl FnOnce(&mut Session) -> (T, Committed),
) -> T {
    let Some((mut session, key)) = open_box(path) else {
        return busy;
    };
    let (value, committed) = f(&mut session);
    checkin(key, session, committed);
    value
}

fn civil_today() -> DateTime {
    let now = Local::now();
    DateTime::date(now.year(), now.month(), now.day())
}

/// The value-kind a property declares, if any.
fn property_kind(store: &Store, property: Id) -> Option<String> {
    match store.get(property).and_then(|p| p.get(props::VALUE_KIND)) {
        Some(Value::Text(kind)) => Some(kind.clone()),
        _ => None,
    }
}

/// The id a select/reference cell points at, for the picker.
fn cell_target(value: &Value) -> Option<Id> {
    match value {
        Value::Select(id) | Value::Reference(id) => Some(*id),
        _ => None,
    }
}

/// The user-facing property definitions, with each select's options —
/// the catalog the inspector renders controls from. The core's own
/// schema vocabulary (name, type, working, private, value-kind, options,
/// expected, …) lives at the reserved ids below FIRST_USER_ID and is
/// plumbing, never something a hand sets on a note, so it is excluded:
/// offering `working` would let an edit silently hide the entity from
/// every view.
fn build_properties(store: &Store) -> Vec<PropertyRow> {
    let mut rows: Vec<PropertyRow> = store
        .entities()
        .filter(|e| !e.trashed && e.id >= props::FIRST_USER_ID)
        .filter_map(|e| {
            let kind = property_kind(store, e.id)?;
            let name = match e.get(props::NAME) {
                Some(Value::Text(n)) => n.clone(),
                _ => return None,
            };
            let options = if kind == "select" {
                e.all(props::OPTIONS)
                    .filter_map(|v| match v {
                        Value::Reference(id) => Some(OptionRow {
                            id: *id,
                            name: reference_name(store, *id),
                        }),
                        _ => None,
                    })
                    .collect()
            } else {
                Vec::new()
            };
            Some(PropertyRow { id: e.id, name, kind, options })
        })
        .collect();
    rows.sort_by(|a, b| a.name.cmp(&b.name));
    rows
}

/// The default snapshot: the current civil month's occurrence window. A thin
/// wrapper so `lotus_snapshot_at` is byte-identical to before — every existing
/// caller keeps working. The calendar asks for other windows through
/// `build_snapshot_windowed`.
fn build_snapshot(store: &Store) -> Snapshot {
    let now = Local::now();
    let from = DateTime::date(now.year(), now.month(), 1);
    let to = DateTime::date(
        now.year(),
        now.month(),
        last_day_of_month(now.year(), now.month()),
    );
    build_snapshot_windowed(store, from, to)
}

/// The snapshot over a caller-chosen occurrence window. `dated` is the full
/// sorted set regardless (the shell buckets it by day); only `occurrences` —
/// the recurrence engine's expansion — follows `[from, to]`, which the engine
/// caps at a year. Same `Snapshot` shape, a caller-chosen horizon.
fn build_snapshot_windowed(store: &Store, from: DateTime, to: DateTime) -> Snapshot {
    let due_prop = property_id(store, "due");
    let status_prop = property_id(store, "status");
    let bookmarked_prop = property_id(store, "bookmarked");
    let archived_prop = property_id(store, "archived");

    let everything = run(store, &Query::default());

    let sections = lotus_services::today_sections(store, civil_today());
    let (today, unstructured) = (sections.due, sections.unstructured);

    // The calendar's plain dates: everything with a due that is not a
    // recurring series — those arrive as occurrences instead.
    let dated = match due_prop {
        None => Vec::new(),
        Some(due) => {
            let mut constraints = vec![Constraint { property: due, op: Op::Exists }];
            if let Some(recurrence) = property_id(store, "recurrence") {
                constraints.push(Constraint { property: recurrence, op: Op::Missing });
            }
            run(
                store,
                &Query {
                    constraints,
                    sort: Some(Sort { property: due, descending: false }),
                    ..Query::default()
                },
            )
        }
    };

    // The caller's window is the horizon the calendar asks for.
    let occurrences = lotus_services::recurrence::occurrences(store, from, to)
        .into_iter()
        .map(|o| OccurrenceRow { series: o.series, civil: o.date.civil })
        .collect();

    let entities = everything
        .iter()
        .filter_map(|id| store.get(*id))
        .map(|entity| {
            let (due, due_date_only) = due_prop
                .and_then(|p| match entity.get(p) {
                    Some(Value::DateTime(d)) => Some((Some(d.civil), d.date_only)),
                    _ => None,
                })
                .unwrap_or((None, false));
            EntityRow {
                id: entity.id,
                title: lotus_views::summary(store, entity),
                kinds: entity
                    .all(props::TYPE)
                    .filter_map(|v| match v {
                        Value::Reference(t) => Some(reference_name(store, *t)),
                        _ => None,
                    })
                    .collect(),
                due,
                due_date_only,
                status: status_prop.and_then(|p| {
                    entity.get(p).map(|v| lotus_views::display(store, v))
                }),
                created: match entity.get(props::CREATED) {
                    Some(Value::DateTime(d)) => Some(d.civil),
                    _ => None,
                },
                trashed: entity.trashed,
                bookmarked: bookmarked_prop
                    .map(|p| entity.has(p, &Value::Bool(true)))
                    .unwrap_or(false),
                archived: archived_prop
                    .map(|p| entity.has(p, &Value::Bool(true)))
                    .unwrap_or(false),
                content_print: lotus_services::content::content_fingerprint(
                    entity.get(props::CONTENT),
                ),
                cells: entity
                    .cells
                    .iter()
                    .map(|cell| CellRow {
                        property_id: cell.property,
                        property: reference_name(store, cell.property),
                        kind: property_kind(store, cell.property).unwrap_or_default(),
                        value: lotus_views::display(store, &cell.value),
                        ref_target: cell_target(&cell.value),
                    })
                    .collect(),
            }
        })
        .collect();

    // The workspace tree: type by name, then every untrashed carrier.
    let workspaces = match lotus_services::content::find_type(store, "workspace") {
        None => Vec::new(),
        Some(workspace_type) => {
            let text = |entity: &lotus_core::Entity, prop: Option<Id>| -> Option<String> {
                match prop.and_then(|p| entity.get(p)) {
                    Some(Value::Text(t)) => Some(t.clone()),
                    _ => None,
                }
            };
            let flag = |entity: &lotus_core::Entity, prop: Option<Id>| -> bool {
                matches!(prop.and_then(|p| entity.get(p)), Some(Value::Bool(true)))
            };
            let emoji_prop = property_id(store, "emoji");
            let favorite_prop = property_id(store, "favorite");
            let archived_prop = property_id(store, "archived");
            let builtin_prop = property_id(store, "builtin");
            let parent_prop = property_id(store, "parent");
            let order_prop = property_id(store, "order");
            let mut rows: Vec<WorkspaceRow> = store
                .entities()
                .filter(|e| {
                    !e.trashed && e.has(props::TYPE, &Value::Reference(workspace_type))
                })
                .map(|e| WorkspaceRow {
                    id: e.id,
                    name: match e.get(props::NAME) {
                        Some(Value::Text(name)) => name.clone(),
                        _ => format!("#{}", e.id),
                    },
                    emoji: text(e, emoji_prop),
                    favorite: flag(e, favorite_prop),
                    archived: flag(e, archived_prop),
                    builtin: text(e, builtin_prop).unwrap_or_default(),
                    parent: match parent_prop.and_then(|p| e.get(p)) {
                        Some(Value::Reference(target)) => *target,
                        _ => 0,
                    },
                    order: match order_prop.and_then(|p| e.get(p)) {
                        Some(Value::Number(n)) => *n,
                        _ => 0.0,
                    },
                })
                .collect();
            rows.sort_by(|a, b| {
                a.order.partial_cmp(&b.order).unwrap_or(std::cmp::Ordering::Equal)
            });
            rows
        }
    };

    let mut seen: Vec<Id> = Vec::new();
    let inbox = store
        .pending()
        .iter()
        .filter_map(|p| {
            let entity = match p.commands.first() {
                Some(lotus_core::Command::AddCell { entity, .. })
                | Some(lotus_core::Command::Create { entity })
                | Some(lotus_core::Command::Trash { entity })
                | Some(lotus_core::Command::Restore { entity })
                | Some(lotus_core::Command::RemoveCell { entity, .. })
                | Some(lotus_core::Command::Redirect { entity, .. }) => *entity,
                None => return None,
            };
            seen.push(entity);
            let ordinal = seen.iter().filter(|e| **e == entity).count() as u32;
            Some(ProposalRow {
                entity,
                ordinal,
                fingerprint: fingerprint(p),
                reason: p.reason.clone(),
                author: match &p.author {
                    Author::Proposer(name) => name.clone(),
                    Author::User => "user".into(),
                    Author::System => "system".into(),
                },
            })
        })
        .collect();

    let properties = build_properties(store);

    Snapshot {
        today,
        unstructured,
        everything,
        dated,
        occurrences,
        inbox,
        workspaces,
        properties,
        entities,
    }
}

fn last_day_of_month(year: i32, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 => 29,
        _ => 28,
    }
}

fn reference_name(store: &Store, id: Id) -> String {
    match store.get(id).and_then(|e| e.get(props::NAME)) {
        Some(Value::Text(name)) => name.clone(),
        _ => format!("#{id}"),
    }
}

/// Everything the window renders, as one JSON document.
/// Returns a malloc'd string — free it with `lotus_string_free`.
/// Null on failure (including the box being open elsewhere).
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_snapshot(path: *const c_char) -> *mut c_char {
    with_box(path, std::ptr::null_mut(), |session| {
        let snapshot = build_snapshot(session.store());
        let out = match serde_json::to_string(&snapshot).ok().and_then(|s| CString::new(s).ok()) {
            Some(s) => s.into_raw(),
            None => std::ptr::null_mut(),
        };
        (out, Committed::Read)
    })
}

/// The same snapshot over a caller-chosen occurrence window: `dated` is
/// unchanged (the full sorted set; the shell buckets it by day), but the
/// recurrence `occurrences` are expanded over `[from_civil, to_civil]`
/// (civil `YYYYMMDDHHMM`) instead of the current month — so a calendar
/// navigated to another month, or a week crossing a month edge, sees its
/// occurrences. The engine caps the window at a year. Same JSON shape as
/// `lotus_snapshot`. Null on failure; free with `lotus_string_free`.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_snapshot_window_at(
    path: *const c_char,
    from_civil: i64,
    to_civil: i64,
) -> *mut c_char {
    with_box(path, std::ptr::null_mut(), |session| {
        let from = DateTime { civil: from_civil, date_only: true, end: None };
        let to = DateTime { civil: to_civil, date_only: true, end: None };
        let snapshot = build_snapshot_windowed(session.store(), from, to);
        let out = match serde_json::to_string(&snapshot).ok().and_then(|s| CString::new(s).ok()) {
            Some(s) => s.into_raw(),
            None => std::ptr::null_mut(),
        };
        (out, Committed::Read)
    })
}

/// Ranked hits + facet counts for one raw DSL query. Its own seam, not part
/// of the cached snapshot: search is query-driven and debounced, and carries
/// a rank order the snapshot's section arrays cannot. `hits` are bare ids
/// (score + why-matched); the shell already holds each entity's title and
/// cells from the snapshot, so results render as the list lens in place.
#[derive(Serialize)]
struct SearchResult {
    hits: Vec<search::Hit>,
    facets: Vec<search::Facet>,
}

fn build_search(store: &Store, raw: &str, cache_dir: &Path) -> SearchResult {
    let sq = search::parse(store, raw);
    // A file entity's cached extracted text extends the corpus — read the
    // sidecar cache (off the log) and hand it to the ranker. A non-file
    // entity contributes nothing.
    let file_prop = property_id(store, "file");
    let format_prop = property_id(store, "format");
    let extracted = |entity: &Entity| -> String {
        let Some(fp) = file_prop else { return String::new() };
        let Some(Value::File(file)) = entity.get(fp) else { return String::new() };
        let format = format_prop
            .and_then(|p| entity.get(p))
            .and_then(|v| match v {
                Value::Text(t) => Some(t.as_str()),
                _ => None,
            })
            .unwrap_or("");
        files::extracted_text(cache_dir, file, format)
    };
    let hits = search::search(store, &sq, 200, extracted);
    let facets = search::facet_properties(store, &sq)
        .into_iter()
        .map(|property| search::facet(store, &sq, property))
        .filter(|facet| !facet.values.is_empty())
        .collect();
    SearchResult { hits, facets }
}

/// Search the box: parse the raw DSL, rank the hits, count the facets.
/// Returns a malloc'd JSON string — free it with `lotus_string_free`.
/// Null on failure (including the box being open elsewhere).
///
/// # Safety
/// `path` and `raw_query` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_search_at(
    path: *const c_char,
    raw_query: *const c_char,
) -> *mut c_char {
    if path.is_null() || raw_query.is_null() {
        return std::ptr::null_mut();
    }
    let (Ok(raw), Ok(path_str)) = (CStr::from_ptr(raw_query).to_str(), CStr::from_ptr(path).to_str())
    else {
        return std::ptr::null_mut();
    };
    let cache = files::cache_dir(path_str);
    with_box(path, std::ptr::null_mut(), |session| {
        let result = build_search(session.store(), raw, &cache);
        let out = match serde_json::to_string(&result).ok().and_then(|s| CString::new(s).ok()) {
            Some(s) => s.into_raw(),
            None => std::ptr::null_mut(),
        };
        (out, Committed::Read)
    })
}

/// Re-hash a file entity's referenced path; if the bytes changed, replace
/// the File cell (one transaction — the hash change IS the integration).
/// Returns 1 if changed & rewritten, 0 if unchanged, -1 if the path no
/// longer resolves (a broken reference). Called when a file is opened, never
/// on a timer.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_resync_file_at(path: *const c_char, id: u64) -> i32 {
    with_box(path, 0, |session| match files::resync_file(session, id) {
        Ok(files::Resync::Changed(_)) => (1, Committed::Wrote),
        Ok(files::Resync::Unchanged) => (0, Committed::Read),
        Ok(files::Resync::Broken) => (-1, Committed::Read),
        Err(_) => (0, Committed::Failed),
    })
}

/// A file entity's extracted plain text (rung 2), from the hash-keyed cache
/// (extracting on a miss). Empty when the file has no extractable text, is a
/// broken reference, or is not a file entity. A malloc'd string — free with
/// `lotus_string_free`; NULL only when the box is unavailable.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_extracted_text_at(path: *const c_char, id: u64) -> *mut c_char {
    let Ok(path_str) = CStr::from_ptr(path).to_str() else {
        return std::ptr::null_mut();
    };
    let cache = files::cache_dir(path_str);
    with_box(path, std::ptr::null_mut(), |session| {
        // A NUL byte is valid UTF-8 (a null-padded log, a UTF-16 export) and
        // survives from_utf8_lossy, but it would make CString::new fail and
        // blank the preview of a file search still matched. Scrub it at the C
        // boundary so the preview degrades to visible-but-cleaned text.
        let text = file_text(session.store(), &cache, id).replace('\0', "\u{FFFD}");
        let out = match CString::new(text) {
            Ok(s) => s.into_raw(),
            Err(_) => std::ptr::null_mut(),
        };
        (out, Committed::Read)
    })
}

/// The extracted text for one file entity, or empty when it carries no file
/// cell — the shared body of the read seam and (later) any reader.
fn file_text(store: &Store, cache_dir: &Path, id: u64) -> String {
    let id = store.resolve(id);
    let Some(file_prop) = property_id(store, "file") else {
        return String::new();
    };
    let Some(entity) = store.get(id) else {
        return String::new();
    };
    let Some(Value::File(file)) = entity.get(file_prop) else {
        return String::new();
    };
    let format = property_id(store, "format")
        .and_then(|p| entity.get(p))
        .and_then(|v| match v {
            Value::Text(t) => Some(t.as_str()),
            _ => None,
        })
        .unwrap_or("");
    files::extracted_text(cache_dir, file, format)
}

/// # Safety
/// `s` must be a pointer returned by `lotus_snapshot`, freed at most once.
#[no_mangle]
pub unsafe extern "C" fn lotus_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

unsafe fn triage(
    path: *const c_char,
    entity: Id,
    ordinal: u32,
    expected: u64,
    accept: bool,
) -> i32 {
    with_box(path, 0, |session| {
        let matching: Vec<usize> = session
            .store()
            .pending()
            .iter()
            .enumerate()
            .filter(|(_, p)| match p.commands.first() {
                Some(lotus_core::Command::AddCell { entity: e, .. }) => *e == entity,
                _ => false,
            })
            .map(|(i, _)| i)
            .collect();
        let index = match (matching.len(), ordinal as usize) {
            (n, k) if k >= 1 && k <= n => matching[k - 1],
            // No such proposal: nothing touched, the store is safe to cache.
            _ => return (0, Committed::Read),
        };
        // A consent is to a proposal, not a position: if the queue shifted
        // since the snapshot, refuse — the shell refreshes and the user sees
        // the truth before clicking again. (No mutation, so cache stays valid.)
        if fingerprint(&session.store().pending()[index]) != expected {
            return (0, Committed::Read);
        }
        let outcome = if accept {
            session.accept(index).is_ok()
        } else {
            session.reject(index).is_ok()
        };
        (outcome as i32, if outcome { Committed::Wrote } else { Committed::Failed })
    })
}

/// Accept the proposal addressed by (entity, ordinal) — verified against
/// the fingerprint the snapshot reported. Returns 1 on success, 0 when
/// the box is busy or the queue no longer matches what was displayed.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_accept_at(
    path: *const c_char,
    entity: u64,
    ordinal: u32,
    fingerprint: u64,
) -> i32 {
    triage(path, entity, ordinal, fingerprint, true)
}

/// Decline the proposal addressed by (entity, ordinal) — verified like
/// accept; the refusal is remembered forever, so a stale click must
/// never land here. Returns 1 on success.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_reject_at(
    path: *const c_char,
    entity: u64,
    ordinal: u32,
    fingerprint: u64,
) -> i32 {
    triage(path, entity, ordinal, fingerprint, false)
}

/// Undo the last committed transaction — capture, accept, set, anything
/// that landed in the log. (A decline is not a transaction; restoring a
/// refusal is a separate, deliberate act.) Returns 1 on success.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_undo_at(path: *const c_char) -> i32 {
    with_box(path, 0, |session| {
        let ok = session.undo(Author::User).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Why the box would not open, as one JSON object: {"code","message"}.
/// Null when the box opens fine. Codes: "locked", "corrupt", "version",
/// "io" — the shell retries "locked" and surfaces the rest.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_probe(path: *const c_char) -> *mut c_char {
    if path.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(path) = CStr::from_ptr(path).to_str() else {
        return std::ptr::null_mut();
    };
    let error = match Session::open(path) {
        Ok(_) => return std::ptr::null_mut(),
        Err(e) => e,
    };
    let code = match &error {
        lotus_core::PersistError::Locked => "locked",
        lotus_core::PersistError::Corrupt(_) => "corrupt",
        lotus_core::PersistError::UnsupportedVersion(_) => "version",
        _ => "io",
    };
    let json = serde_json::json!({ "code": code, "message": error.to_string() });
    match CString::new(json.to_string()) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

// ---- the editor's seam: content in, content out, guarded ----

#[derive(Serialize)]
struct ContentDoc {
    id: Id,
    name: Option<String>,
    trashed: bool,
    /// True when the box opened fine but no such entity exists — never
    /// conflated with a locked box, which is a null return instead.
    missing: bool,
    /// Identity of the stored content value; a save must present it back.
    fingerprint: u64,
    /// The log's own serde encoding of Span, verbatim.
    spans: Vec<lotus_core::Span>,
}

/// One entity's content, fresh from the box. Legacy plain-text content
/// reads as one Text span (the fingerprint still covers the stored
/// value). Redirects resolve before reading. A box that opened fine but
/// holds no such entity answers `{"missing":true,…}`; null means only
/// that the box itself is unavailable (probe to learn why).
/// Free with `lotus_string_free`.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_content_at(path: *const c_char, id: u64) -> *mut c_char {
    with_box(path, std::ptr::null_mut(), |session| {
        let store = session.store();
        let resolved = store.resolve(id);
        let doc = match store.get(resolved) {
            Some(entity) => ContentDoc {
                id: resolved,
                name: match entity.get(props::NAME) {
                    Some(Value::Text(name)) => Some(name.clone()),
                    _ => None,
                },
                trashed: entity.trashed,
                missing: false,
                fingerprint: lotus_services::content::content_fingerprint(
                    entity.get(props::CONTENT),
                ),
                spans: lotus_services::content::content_spans(entity),
            },
            None => ContentDoc {
                id: resolved,
                name: None,
                trashed: false,
                missing: true,
                fingerprint: 0,
                spans: Vec::new(),
            },
        };
        let out = match serde_json::to_string(&doc).ok().and_then(|s| CString::new(s).ok()) {
            Some(s) => s.into_raw(),
            None => std::ptr::null_mut(),
        };
        (out, Committed::Read)
    })
}

/// Replace the entity's whole content in one transaction — the editor's
/// save. `base_fingerprint` must still match the stored content: a save
/// is to a value, never a moment. There is no force flag; overwrite is
/// re-read then save. On success `*fresh_fingerprint` receives the new
/// content's fingerprint. Returns 1 saved, -1 stale, 0 busy or invalid.
///
/// # Safety
/// `path` and `spans_json` must be valid NUL-terminated UTF-8 strings;
/// `fresh_fingerprint` must be null or valid for one u64 write.
#[no_mangle]
pub unsafe extern "C" fn lotus_set_content_at(
    path: *const c_char,
    id: u64,
    spans_json: *const c_char,
    base_fingerprint: u64,
    fresh_fingerprint: *mut u64,
) -> i32 {
    if spans_json.is_null() {
        return 0;
    }
    let Ok(json) = CStr::from_ptr(spans_json).to_str() else {
        return 0;
    };
    let Ok(spans) = serde_json::from_str::<Vec<lotus_core::Span>>(json) else {
        return 0;
    };
    with_box(path, 0, move |session| {
        match lotus_services::content::set_content(session, id, spans, base_fingerprint) {
            Ok(fresh) => {
                if !fresh_fingerprint.is_null() {
                    unsafe { *fresh_fingerprint = fresh };
                }
                (1, Committed::Wrote)
            }
            // A stale save refused before it touched the store — cache stays valid.
            Err(lotus_services::content::ContentError::Stale) => (-1, Committed::Read),
            Err(_) => (0, Committed::Failed),
        }
    })
}

/// Set one property by name: the CLI's `set` through the seam — value
/// parsed by the property's declared kind, replace-the-cell, one
/// transaction. Serves the checkbox ("status","done"), rename ("name",…)
/// and the inspector to come. Returns 1, or 0 on busy/parse/no-entity.
///
/// # Safety
/// `path`, `property` and `value` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_set_at(
    path: *const c_char,
    id: u64,
    property: *const c_char,
    value: *const c_char,
) -> i32 {
    if property.is_null() || value.is_null() {
        return 0;
    }
    let (Ok(property), Ok(value)) = (
        CStr::from_ptr(property).to_str(),
        CStr::from_ptr(value).to_str(),
    ) else {
        return 0;
    };
    with_box(path, 0, |session| {
        let ok = lotus_services::content::set_property(session, id, property, value).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Add ONE cell to a (multi-valued) property — list membership adds a
/// member as ("related", "#<member-id>"). Unlike lotus_set_at (replace all
/// cells of the property) and lotus_unset_at (remove all), this touches
/// exactly one cell; adding a value already present is a no-op that still
/// returns 1. Value parsed by the property's kind. 1 ok, 0 on
/// busy/parse/no-entity.
///
/// # Safety
/// `path`, `property`, `value` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_add_cell_at(
    path: *const c_char,
    id: u64,
    property: *const c_char,
    value: *const c_char,
) -> i32 {
    if property.is_null() || value.is_null() {
        return 0;
    }
    let (Ok(property), Ok(value)) =
        (CStr::from_ptr(property).to_str(), CStr::from_ptr(value).to_str())
    else {
        return 0;
    };
    with_box(path, 0, |session| {
        let ok = lotus_services::content::add_cell(session, id, property, value).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Remove ONE cell of a (multi-valued) property — un-tag a list member.
/// NEVER deletes the referenced entity. Removing a value that isn't present
/// is a no-op that still returns 1. 1 ok, 0 on busy/failure.
///
/// # Safety
/// `path`, `property`, `value` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_remove_cell_at(
    path: *const c_char,
    id: u64,
    property: *const c_char,
    value: *const c_char,
) -> i32 {
    if property.is_null() || value.is_null() {
        return 0;
    }
    let (Ok(property), Ok(value)) =
        (CStr::from_ptr(property).to_str(), CStr::from_ptr(value).to_str())
    else {
        return 0;
    };
    with_box(path, 0, |session| {
        let ok = lotus_services::content::remove_cell(session, id, property, value).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

#[derive(Serialize)]
struct ContentVersionRow {
    seq: u64,
    time: i64,
    author: String,
    label: String,
    spans: Vec<lotus_core::Span>,
}

/// Every past version of an entity's content, NEWEST first, as one JSON
/// array: [{"seq","time","author","label","spans"}]. The log is the
/// history — no reconstruction; each entry is a whole content value, and
/// restoring one is an ordinary `lotus_set_content_at` of its spans.
/// Null when the box is unavailable. Free with `lotus_string_free`.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_content_history_at(path: *const c_char, id: u64) -> *mut c_char {
    with_box(path, std::ptr::null_mut(), |session| {
        let mut versions: Vec<ContentVersionRow> =
            lotus_services::content::content_history(session.store(), id)
                .into_iter()
                .map(|v| ContentVersionRow {
                    seq: v.seq,
                    time: v.time,
                    author: match v.author {
                        Author::Proposer(name) => name,
                        Author::User => "user".into(),
                        Author::System => "system".into(),
                    },
                    label: v.label,
                    spans: v.spans,
                })
                .collect();
        versions.reverse(); // newest first for the pane
        let out = match serde_json::to_string(&versions).ok().and_then(|s| CString::new(s).ok()) {
            Some(s) => s.into_raw(),
            None => std::ptr::null_mut(),
        };
        (out, Committed::Read)
    })
}

/// Birth of a note: Create + type + created, one transaction. Returns
/// the id, 0 on failure. The caller drops straight into renaming.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_create_note_at(path: *const c_char) -> u64 {
    with_box(path, 0, |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let id = lotus_services::content::create_note(session, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Create a task by hand (the Tasks quick-add): one transaction — type=task
/// + status=todo + created. Returns the new id, 0 on failure. Distinct from
/// capture, which makes an untyped scrap the clerk quarantines.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_create_task_at(path: *const c_char) -> u64 {
    with_box(path, 0, |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let id = lotus_services::content::create_task(session, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// The packed civil as the seam's date text — "yyyy-mm-dd", with " hh:mm"
/// when timed. The FFI's span writer formats through this and re-parses via
/// parse_value, so the drag gestures and the inspector row are provably the
/// SAME write (the mirror contract).
fn civil_text(civil: i64, date_only: bool) -> String {
    let (ymd, hhmm) = (civil / 10_000, civil % 10_000);
    let mut s = format!("{:04}-{:02}-{:02}", ymd / 10_000, (ymd / 100) % 100, ymd % 100);
    if !date_only {
        s.push_str(&format!(" {:02}:{:02}", hhmm / 100, hhmm % 100));
    }
    s
}

/// Writes a date/span cell as ONE command (P11/11b — the mirror contract:
/// the inspector row, a calendar drag, and a span-grip drag are all this
/// write). `end_civil` = 0 means no end (a plain date); an end not strictly
/// after the start is refused before the box is even opened. `date_only`
/// applies to both ends. Returns 1, or 0 on busy/refusal.
///
/// # Safety
/// `path` and `property` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_set_span_at(
    path: *const c_char,
    id: u64,
    property: *const c_char,
    start_civil: i64,
    end_civil: i64,
    date_only: i32,
) -> i32 {
    if property.is_null() {
        return 0;
    }
    let Ok(prop_name) = CStr::from_ptr(property).to_str() else {
        return 0;
    };
    let date_only = date_only != 0;
    // A date-only civil carries no time; zero the HH:mm like create_event.
    let normalize = |c: i64| if date_only { (c / 10_000) * 10_000 } else { c };
    let start = normalize(start_civil);
    let end = normalize(end_civil);
    if end_civil != 0 && end <= start {
        return 0; // refused before the box is opened — nothing to tag
    }
    let raw = if end_civil == 0 {
        civil_text(start, date_only)
    } else {
        format!("{} -> {}", civil_text(start, date_only), civil_text(end, date_only))
    };
    with_box(path, 0, move |session| {
        let ok = lotus_services::content::set_property(session, id, prop_name, &raw).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Space-cycles a date row's role (P11/11a): one transaction moving the
/// value — civil + date_only intact — from `property` to the next role in
/// the ring due → date → valid-until → occurred → purchased-on → due.
/// Returns the NEW property name (malloc'd — free with `lotus_string_free`),
/// or NULL on busy/refusal. A refusal never touched the store, so the cached
/// snapshot stays valid (`Read`); only a real write re-sweeps (`Wrote`).
///
/// # Safety
/// `path` and `property` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_cycle_date_role_at(
    path: *const c_char,
    id: u64,
    property: *const c_char,
) -> *mut c_char {
    if property.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(prop_name) = CStr::from_ptr(property).to_str() else {
        return std::ptr::null_mut();
    };
    with_box(path, std::ptr::null_mut(), |session| {
        let Some(prop) = property_id(session.store(), prop_name) else {
            return (std::ptr::null_mut(), Committed::Read);
        };
        match lotus_services::content::cycle_date_role(session, id, prop) {
            Ok(next) => {
                let name = match session.store().get(next).and_then(|p| p.get(props::NAME)) {
                    Some(Value::Text(n)) => n.clone(),
                    _ => String::new(),
                };
                match CString::new(name) {
                    Ok(s) => (s.into_raw(), Committed::Wrote),
                    // The write landed even if the name can't cross the C
                    // boundary — the cache must still see it.
                    Err(_) => (std::ptr::null_mut(), Committed::Wrote),
                }
            }
            Err(lotus_services::content::CycleError::Refused(_)) => {
                (std::ptr::null_mut(), Committed::Read)
            }
            Err(lotus_services::content::CycleError::Persist(_)) => {
                (std::ptr::null_mut(), Committed::Failed)
            }
        }
    })
}

/// Create an event by hand (the "+ Event" button, or double-click a day/hour).
/// One transaction: type=event + due (from `due_civil`, all-day when
/// `date_only` != 0) + created. Returns the new id, or 0 (busy box / failure).
/// Distinct from capture, which makes an untyped scrap the clerk quarantines.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_create_event_at(
    path: *const c_char,
    due_civil: i64,
    date_only: i32,
) -> u64 {
    with_box(path, 0, |session| {
        // A date-only due carries no time; zero the HH:mm so it matches
        // DateTime::date's packing exactly (the shell should pass 0 anyway).
        let due = DateTime {
            civil: if date_only != 0 { (due_civil / 10_000) * 10_000 } else { due_civil },
            date_only: date_only != 0,
            end: None,
        };
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let id = lotus_services::content::create_event(session, due, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Birth of a list: Create + type=list + name + created, one transaction.
/// Named at birth (unlike a note). Returns the id, 0 on failure.
///
/// # Safety
/// `path` and `name` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_create_list_at(
    path: *const c_char,
    name: *const c_char,
) -> u64 {
    if name.is_null() {
        return 0;
    }
    let Ok(name) = CStr::from_ptr(name).to_str() else {
        return 0;
    };
    with_box(path, 0, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let id = lotus_services::content::create_list(session, name, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Add a file by reference: hash its bytes, create the entity with a `file`
/// cell (path + hash) + `format` + `name`, one transaction. NEVER copies,
/// moves, or renames the file — only reads it to hash. Returns the new id,
/// or 0 (unreadable path, busy box, or failure).
///
/// # Safety
/// `path` and `file_path` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_add_file_at(
    path: *const c_char,
    file_path: *const c_char,
) -> u64 {
    if file_path.is_null() {
        return 0;
    }
    let Ok(file_path) = CStr::from_ptr(file_path).to_str() else {
        return 0;
    };
    with_box(path, 0, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let id = lotus_services::files::add_file(session, file_path, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Birth of a workspace: Create + type + name (+ parent, trailing
/// order), one transaction. parent 0 = top level. Returns the id, 0 on
/// failure.
///
/// # Safety
/// `path` and `name` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_create_workspace_at(
    path: *const c_char,
    name: *const c_char,
    parent: u64,
) -> u64 {
    if name.is_null() {
        return 0;
    }
    let Ok(name) = CStr::from_ptr(name).to_str() else {
        return 0;
    };
    let name = name.trim();
    if name.is_empty() {
        return 0;
    }
    with_box(path, 0, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let parent = (parent != 0).then_some(parent);
        let id = lotus_services::content::create_workspace(session, name, parent, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Trash one workspace — and only that one. Deletion never cascades:
/// its children keep their dangling `parent` and the shell re-roots
/// them. Returns 1 on success, 0 on failure.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_trash_workspace_at(path: *const c_char, id: u64) -> i32 {
    with_box(path, 0, |session| {
        let ok = lotus_services::content::trash_workspace(session, id).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Trash one entity — the inspector's Trash action. Soft, reversible
/// (⌘⌥Z), never cascades. 1 on success, 0 on failure.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_trash_at(path: *const c_char, id: u64) -> i32 {
    with_box(path, 0, |session| {
        let ok = lotus_services::content::trash_workspace(session, id).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Remove every cell of one property — the inverse of lotus_set_at's
/// replace. A property the entity does not carry is success, not an
/// error. Returns 1 on success, 0 on busy/no entity/no property.
///
/// # Safety
/// `path` and `property` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn lotus_unset_at(
    path: *const c_char,
    id: u64,
    property: *const c_char,
) -> i32 {
    if property.is_null() {
        return 0;
    }
    let Ok(property) = CStr::from_ptr(property).to_str() else {
        return 0;
    };
    with_box(path, 0, |session| {
        let ok = lotus_services::content::unset_property(session, id, property).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use lotus_core::{Cell, Command};
    use std::ffi::CString;

    #[test]
    fn the_seam_roundtrips() {
        let path = std::env::temp_dir().join("lotus_ffi_roundtrip.log");
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.declined", path.display()));
        let _ = std::fs::remove_file(format!("{}.pending", path.display()));
        let c_path = CString::new(path.to_str().unwrap()).unwrap();

        let text = CString::new("Call Anna Friday").unwrap();
        let id = unsafe { lotus_capture_at(c_path.as_ptr(), text.as_ptr()) };
        assert_ne!(id, 0);

        // Whitespace is not a thought.
        let blank = CString::new("   ").unwrap();
        assert_eq!(unsafe { lotus_capture_at(c_path.as_ptr(), blank.as_ptr()) }, 0);

        // The session closed behind the capture: the box is free again,
        // and what the shell wrote, the rest of the system reads.
        let session = Session::open(&path).unwrap();
        let entity = session.store().get(id).unwrap();
        assert!(entity.get(lotus_core::props::CONTENT).is_some());
        assert!(entity.get(lotus_core::props::CREATED).is_some());
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.declined", path.display()));
        let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    }

    #[test]
    fn snapshot_and_triage_roundtrip() {
        let path = std::env::temp_dir().join("lotus_ffi_snapshot.log");
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.declined", path.display()));
        let _ = std::fs::remove_file(format!("{}.pending", path.display()));
        let c_path = CString::new(path.to_str().unwrap()).unwrap();

        let text = CString::new("kickoff friday").unwrap();
        let id = unsafe { lotus_capture_at(c_path.as_ptr(), text.as_ptr()) };
        assert_ne!(id, 0);

        // The snapshot shows the scrap unstructured and the clerk's proposal.
        let raw = unsafe { lotus_snapshot(c_path.as_ptr()) };
        assert!(!raw.is_null());
        let json = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_string();
        unsafe { lotus_string_free(raw) };
        let snap: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(snap["unstructured"][0], id);
        assert_eq!(snap["inbox"][0]["entity"], id);
        assert_eq!(snap["inbox"][0]["author"], "dates");
        let print = snap["inbox"][0]["fingerprint"].as_u64().unwrap();

        // A stale or wrong fingerprint is refused: consent is to a
        // proposal, never to a position.
        assert_eq!(unsafe { lotus_accept_at(c_path.as_ptr(), id, 1, print ^ 1) }, 0);

        // Accepting through the seam lands the due cell...
        assert_eq!(unsafe { lotus_accept_at(c_path.as_ptr(), id, 1, print) }, 1);
        let raw = unsafe { lotus_snapshot(c_path.as_ptr()) };
        let json = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_string();
        unsafe { lotus_string_free(raw) };
        let snap: serde_json::Value = serde_json::from_str(&json).unwrap();
        // ...so the scrap moves from unstructured to today/dated...
        assert_eq!(snap["dated"][0], id);
        assert!(snap["inbox"].as_array().unwrap().is_empty());

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.declined", path.display()));
        let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    }

    /// A fresh box path with sidecars cleared; returns (PathBuf, CString).
    fn fresh_box(name: &str) -> (std::path::PathBuf, CString) {
        // A per-box directory so the extraction cache (a sibling of the box)
        // is isolated per test — parallel tests must not share one cache.
        let dir = std::env::temp_dir().join(format!("lotus_box_{name}"));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("box.log");
        let c_path = CString::new(path.to_str().unwrap()).unwrap();
        (path, c_path)
    }

    fn cleanup(path: &std::path::Path) {
        // The box lives in its own dir now — remove the lot (box, sidecars,
        // cache).
        if let Some(dir) = path.parent() {
            let _ = std::fs::remove_dir_all(dir);
        }
    }

    unsafe fn read_json(raw: *mut c_char) -> serde_json::Value {
        assert!(!raw.is_null());
        let json = CStr::from_ptr(raw).to_str().unwrap().to_string();
        lotus_string_free(raw);
        serde_json::from_str(&json).unwrap()
    }

    // ---- the store cache (design/perf-incremental-open.md, slice B) ----

    #[test]
    fn a_cache_hit_matches_a_full_open() {
        let (path, c_path) = fresh_box("lotus_ffi_cache_equiv.log");
        unsafe { lotus_capture_at(c_path.as_ptr(), CString::new("kickoff friday").unwrap().as_ptr()) };

        // First snapshot: a full open (miss) that populates the cache.
        let first = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        // Second snapshot: served from the cache (a hit) — the SAME answer.
        let hit = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(first, hit, "a cache hit must not change the answer");
        // Clear the cache: a forced full replay agrees too — the cache never
        // diverges from the log's own consequence.
        clear_cache_for_tests();
        let full = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(first, full, "the cache never diverges from a full replay");
        cleanup(&path);
    }

    #[test]
    fn an_external_append_is_picked_up() {
        let (path, c_path) = fresh_box("lotus_ffi_external.log");
        // Seed + cache via an FFI snapshot.
        unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };

        // A second writer (the CLI stand-in) appends a note directly, then drops
        // — releasing the lock. The FFI cache still holds the pre-append store.
        let external_id = {
            let mut session = Session::open(&path).unwrap();
            lotus_services::content::create_note(&mut session, DateTime::at(2026, 7, 8, 9, 0)).unwrap()
        };
        // The next FFI snapshot must SEE the external note — the grown log length
        // forces a full re-open, not a stale cache hit.
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let seen = snap["entities"].as_array().unwrap().iter().any(|e| e["id"] == external_id);
        assert!(seen, "an external append must invalidate the cache");
        cleanup(&path);
    }

    #[test]
    fn two_creates_do_not_reuse_an_id() {
        let (path, c_path) = fresh_box("lotus_ffi_ids.log");
        // The second create is a cache HIT (the first's commit grew the log, and
        // check-in cached that length); next_id must ride the cached store.
        let a = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        let b = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        assert_ne!(a, 0);
        assert_ne!(b, 0);
        assert_ne!(a, b, "consecutive creates through the cache must mint distinct ids");
        // Both survive a full replay from disk (cache cleared) — the ids are real.
        clear_cache_for_tests();
        let session = Session::open(&path).unwrap();
        assert!(session.store().get(a).is_some() && session.store().get(b).is_some());
        cleanup(&path);
    }

    #[test]
    fn a_locked_box_is_not_served_from_cache() {
        let (path, c_path) = fresh_box("lotus_ffi_locked.log");
        // Warm the cache.
        unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        // Hold the box open elsewhere (grabs the exclusive lock).
        let guard = Session::open(&path).unwrap();
        // Even with a warm cache, a snapshot must refuse (null), never serve a
        // stale cached answer while another writer holds the box (Guard 5).
        let raw = unsafe { lotus_snapshot(c_path.as_ptr()) };
        assert!(raw.is_null(), "a locked box yields null, never a cached snapshot");
        drop(guard);
        // Lock released: the next snapshot succeeds again.
        let raw = unsafe { lotus_snapshot(c_path.as_ptr()) };
        assert!(!raw.is_null());
        unsafe { lotus_string_free(raw) };
        cleanup(&path);
    }

    #[test]
    fn a_sidecar_change_without_a_log_change_invalidates() {
        let (path, c_path) = fresh_box("lotus_ffi_sidecar.log");
        unsafe { lotus_capture_at(c_path.as_ptr(), CString::new("kickoff friday").unwrap().as_ptr()) };
        // Snapshot proposes friday and caches (inbox has one).
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(snap["inbox"].as_array().unwrap().len(), 1);

        // Externally decline it: rewrites .declined + .pending WITHOUT touching
        // the main log (its length is unchanged).
        {
            let mut session = Session::open(&path).unwrap();
            session.reject(0).unwrap();
        }
        // The next FFI snapshot must reflect the decline — the sidecar length
        // changed even though the log length did not (Guard 2).
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(
            snap["inbox"].as_array().unwrap().len(),
            0,
            "a sidecar change must invalidate the cache"
        );
        cleanup(&path);
    }

    // ---- the calendar's steerable window + create_event (P10/10a) ----

    /// A weekly/daily/… series set up directly, as the CLI would.
    fn seed_series(path: &std::path::Path, due: DateTime, rule: &str) {
        let mut session = Session::open(path).unwrap();
        lotus_services::seed_if_fresh(&mut session).unwrap();
        let id = session.allocate_id();
        let due_prop = property_id(session.store(), "due").unwrap();
        let recur = property_id(session.store(), "recurrence").unwrap();
        session
            .commit(
                vec![
                    Command::Create { entity: id },
                    Command::AddCell {
                        entity: id,
                        cell: Cell { property: due_prop, value: Value::DateTime(due) },
                    },
                    Command::AddCell {
                        entity: id,
                        cell: Cell { property: recur, value: Value::text(rule) },
                    },
                ],
                "series",
                Author::User,
            )
            .unwrap();
    }

    #[test]
    fn the_default_snapshot_is_the_current_month_window() {
        // The load-bearing regression guard: the windowed refactor must leave
        // lotus_snapshot byte-identical — it is exactly the current civil
        // month's window.
        let (path, c_path) = fresh_box("lotus_ffi_win_default.log");
        unsafe { lotus_capture_at(c_path.as_ptr(), CString::new("hello").unwrap().as_ptr()) };
        let full = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let now = Local::now();
        let from = DateTime::date(now.year(), now.month(), 1).civil;
        let to = DateTime::date(
            now.year(),
            now.month(),
            last_day_of_month(now.year(), now.month()),
        )
        .civil;
        let windowed = unsafe { read_json(lotus_snapshot_window_at(c_path.as_ptr(), from, to)) };
        assert_eq!(full, windowed, "the default snapshot IS the current-month window");
        cleanup(&path);
    }

    #[test]
    fn a_future_window_steers_the_occurrence_engine() {
        let (path, c_path) = fresh_box("lotus_ffi_win_future.log");
        // A weekly series anchored 2026-07-07 (a Tuesday); the window decides
        // which of its Tuesdays the snapshot expands.
        seed_series(&path, DateTime::date(2026, 7, 7), "every week");
        let snap = unsafe {
            read_json(lotus_snapshot_window_at(
                c_path.as_ptr(),
                DateTime::date(2026, 8, 1).civil,
                DateTime::date(2026, 8, 31).civil,
            ))
        };
        let civils: Vec<i64> = snap["occurrences"]
            .as_array()
            .unwrap()
            .iter()
            .map(|o| o["civil"].as_i64().unwrap() / 10_000)
            .collect();
        // August 2026's Tuesdays — a month the default (current) window never covers.
        assert_eq!(civils, vec![20260804, 20260811, 20260818, 20260825]);
        cleanup(&path);
    }

    #[test]
    fn a_week_window_straddling_a_month_boundary_spans_both_sides() {
        // The week grid's window is [Mon, Sun], which can cross a month edge —
        // it must expand occurrences on BOTH sides (proving the window, not a
        // fixed month, feeds it). A weekly Tuesday series over Jul 28 .. Aug 4.
        let (path, c_path) = fresh_box("lotus_ffi_win_straddle.log");
        seed_series(&path, DateTime::date(2026, 7, 7), "every week");
        let snap = unsafe {
            read_json(lotus_snapshot_window_at(
                c_path.as_ptr(),
                DateTime::date(2026, 7, 28).civil,
                DateTime::date(2026, 8, 4).civil,
            ))
        };
        let civils: Vec<i64> = snap["occurrences"]
            .as_array()
            .unwrap()
            .iter()
            .map(|o| o["civil"].as_i64().unwrap() / 10_000)
            .collect();
        assert!(civils.contains(&20260728), "the July Tuesday");
        assert!(civils.contains(&20260804), "the August Tuesday");
        cleanup(&path);
    }

    #[test]
    fn the_occurrence_window_is_capped_at_a_year() {
        let (path, c_path) = fresh_box("lotus_ffi_win_cap.log");
        seed_series(&path, DateTime::date(2026, 1, 1), "every day");
        // Ask for three years; the engine caps at 366 days from `from`.
        let snap = unsafe {
            read_json(lotus_snapshot_window_at(
                c_path.as_ptr(),
                DateTime::date(2026, 1, 1).civil,
                DateTime::date(2029, 1, 1).civil,
            ))
        };
        let count = snap["occurrences"].as_array().unwrap().len();
        assert!((366..=367).contains(&count), "a 3-year ask caps at ~a year, got {count}");
        cleanup(&path);
    }

    #[test]
    fn create_event_lands_typed_and_dued_on_the_asked_day() {
        let (path, c_path) = fresh_box("lotus_ffi_event.log");
        let due_civil = DateTime::at(2026, 7, 9, 9, 0).civil;
        let id = unsafe { lotus_create_event_at(c_path.as_ptr(), due_civil, 0) };
        assert_ne!(id, 0);
        let snap = unsafe {
            read_json(lotus_snapshot_window_at(
                c_path.as_ptr(),
                DateTime::date(2026, 7, 1).civil,
                DateTime::date(2026, 7, 31).civil,
            ))
        };
        let e = snap["entities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["id"] == id)
            .expect("the new event is in the snapshot");
        assert!(e["kinds"].as_array().unwrap().iter().any(|k| k == "event"));
        assert_eq!(e["due"].as_i64().unwrap(), due_civil);
        assert_eq!(e["due_date_only"], false);
        // A non-recurring dated entity, so it rides `dated` (bucketed by day).
        assert!(snap["dated"].as_array().unwrap().iter().any(|d| d.as_u64() == Some(id)));
        cleanup(&path);
    }

    // ---- spans through the seam (P11/11b) ----

    #[test]
    fn a_span_write_is_tagged_wrote_and_a_bad_span_is_refused() {
        let (path, c_path) = fresh_box("lotus_ffi_span.log");
        let id = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        assert_ne!(id, 0);
        unsafe { lotus_string_free(lotus_snapshot(c_path.as_ptr())) }; // warm the cache
        let due = CString::new("due").unwrap();

        // A real span writes (the Wrote contract: the very next snapshot —
        // a cache hit — carries the new due start).
        let start = DateTime::date(2026, 7, 11).civil;
        let end = DateTime::date(2026, 7, 13).civil;
        assert_eq!(
            unsafe { lotus_set_span_at(c_path.as_ptr(), id, due.as_ptr(), start, end, 1) },
            1
        );
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let row = snap["entities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["id"] == id)
            .unwrap();
        assert_eq!(row["due"].as_i64(), Some(start), "the span's start positions the row");

        // The full value — end included — survives a from-scratch replay.
        clear_cache_for_tests();
        let session = Session::open(&path).unwrap();
        let due_prop = property_id(session.store(), "due").unwrap();
        match session.store().get(id).unwrap().get(due_prop) {
            Some(Value::DateTime(d)) => {
                assert_eq!(d.civil, start);
                assert_eq!(d.end, Some(end));
                assert!(d.date_only);
            }
            other => panic!("expected the span, got {other:?}"),
        }
        drop(session);

        // A backwards span is refused before the box is opened: no write,
        // and the cached snapshot stays exactly what it was.
        let before = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(
            unsafe { lotus_set_span_at(c_path.as_ptr(), id, due.as_ptr(), end, start, 1) },
            0
        );
        let after = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(before, after);
        cleanup(&path);
    }

    #[test]
    fn a_span_displays_as_its_own_parseable_text() {
        // The mirror contract's read side (the review's finding: display
        // never learned spans, so a text write-back silently destroyed the
        // end). The snapshot's cell text IS the parseable span form — writing
        // it back through the ordinary set seam is a lossless no-op.
        let (path, c_path) = fresh_box("lotus_ffi_span_display.log");
        let id = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        let due = CString::new("due").unwrap();
        let start = DateTime::date(2026, 7, 11).civil;
        let end = DateTime::date(2026, 7, 13).civil;
        assert_eq!(
            unsafe { lotus_set_span_at(c_path.as_ptr(), id, due.as_ptr(), start, end, 1) },
            1
        );

        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let text = snap["entities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["id"] == id)
            .unwrap()["cells"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["property"] == "due")
            .unwrap()["value"]
            .as_str()
            .unwrap()
            .to_string();
        assert_eq!(text, "2026-07-11 -> 2026-07-13", "the span names its end");

        // Round-trip: the displayed text re-parses to the identical value.
        let raw = CString::new(text).unwrap();
        assert_eq!(unsafe { lotus_set_at(c_path.as_ptr(), id, due.as_ptr(), raw.as_ptr()) }, 1);
        clear_cache_for_tests();
        let session = Session::open(&path).unwrap();
        let due_prop = property_id(session.store(), "due").unwrap();
        match session.store().get(id).unwrap().get(due_prop) {
            Some(Value::DateTime(d)) => {
                assert_eq!(d.civil, start);
                assert_eq!(d.end, Some(end), "the write-back kept the end");
            }
            other => panic!("expected the span, got {other:?}"),
        }
        cleanup(&path);
    }

    #[test]
    fn a_lookup_role_only_entity_stays_off_dated() {
        // The design's real positioning assertion (the review flagged the
        // services-level version as vacuous): an entity whose only date is a
        // lookup role carries the cell, yet never enters the snapshot's
        // `dated` — the calendar surface.
        let (path, c_path) = fresh_box("lotus_ffi_lookup.log");
        let id = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        let occurred = CString::new("occurred").unwrap();
        let when = CString::new("2026-07-09").unwrap();
        assert_eq!(
            unsafe { lotus_set_at(c_path.as_ptr(), id, occurred.as_ptr(), when.as_ptr()) },
            1
        );
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let row = snap["entities"].as_array().unwrap().iter().find(|e| e["id"] == id).unwrap();
        assert!(
            row["cells"].as_array().unwrap().iter().any(|c| c["property"] == "occurred"),
            "the occurred cell is really there (not a vacuous pass)"
        );
        assert!(
            !snap["dated"].as_array().unwrap().iter().any(|d| d.as_u64() == Some(id)),
            "a lookup-only entity never positions on the calendar"
        );
        cleanup(&path);
    }

    #[test]
    fn a_second_span_write_rides_the_bumped_header() {
        // The version fence through the CACHE: the first span bumps the
        // header to 2; the cached session must carry that fact, so the
        // second span write doesn't try to bump again (and the box reopens).
        let (path, c_path) = fresh_box("lotus_ffi_span_ver.log");
        let a = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        let b = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        let due = CString::new("due").unwrap();
        let date = CString::new("date").unwrap();
        let s1 = DateTime::date(2026, 7, 11).civil;
        let e1 = DateTime::date(2026, 7, 13).civil;
        assert_eq!(unsafe { lotus_set_span_at(c_path.as_ptr(), a, due.as_ptr(), s1, e1, 1) }, 1);
        assert_eq!(unsafe { lotus_set_span_at(c_path.as_ptr(), b, date.as_ptr(), s1, e1, 1) }, 1);

        let header = std::fs::read_to_string(&path)
            .unwrap()
            .lines()
            .next()
            .unwrap()
            .to_string();
        assert_eq!(header, r#"{"lotus_log":2}"#);
        clear_cache_for_tests();
        let raw = unsafe { lotus_snapshot(c_path.as_ptr()) };
        assert!(!raw.is_null(), "the bumped box reopens from scratch");
        unsafe { lotus_string_free(raw) };
        cleanup(&path);
    }

    // ---- role cycling through the cache (P11/11a) ----

    #[test]
    fn role_cycle_round_trips_through_the_cache() {
        let (path, c_path) = fresh_box("lotus_ffi_cycle.log");
        let id = unsafe {
            lotus_create_event_at(c_path.as_ptr(), DateTime::at(2026, 7, 11, 9, 0).civil, 0)
        };
        assert_ne!(id, 0);
        // Warm the cache, then cycle due -> date on the HIT path.
        unsafe { lotus_string_free(lotus_snapshot(c_path.as_ptr())) };
        let due = CString::new("due").unwrap();
        let raw = unsafe { lotus_cycle_date_role_at(c_path.as_ptr(), id, due.as_ptr()) };
        assert!(!raw.is_null(), "the cycle succeeds");
        let next = unsafe { CStr::from_ptr(raw).to_str().unwrap().to_string() };
        unsafe { lotus_string_free(raw) };
        assert_eq!(next, "date", "due cycles to date");

        // The Wrote contract: the very next snapshot (a cache hit) sees it.
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let cells = snap["entities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["id"] == id)
            .unwrap()["cells"]
            .as_array()
            .unwrap()
            .clone();
        assert!(cells.iter().any(|c| c["property"] == "date"), "the date cell is there");
        assert!(!cells.iter().any(|c| c["property"] == "due"), "the due cell is gone");

        // And a from-scratch replay agrees — the cache never diverges.
        clear_cache_for_tests();
        let full = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(snap, full);
        cleanup(&path);
    }

    #[test]
    fn a_refused_cycle_is_tagged_read_and_leaves_the_cache_verbatim() {
        let (path, c_path) = fresh_box("lotus_ffi_cycle_refused.log");
        let id = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        assert_ne!(id, 0);
        let before = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };

        // No due cell on the note: the cycle is refused, nothing written.
        let due = CString::new("due").unwrap();
        let raw = unsafe { lotus_cycle_date_role_at(c_path.as_ptr(), id, due.as_ptr()) };
        assert!(raw.is_null(), "the cycle is refused");

        // The refusal never touched the store: the next snapshot — still the
        // cached one — is identical.
        let after = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(before, after);
        cleanup(&path);
    }

    #[test]
    fn setting_location_on_an_event_round_trips() {
        // 10b: `location` is seeded (offered, not expected); set it on an event
        // through the ordinary set seam and it shows in the snapshot's cells.
        let (path, c_path) = fresh_box("lotus_ffi_location.log");
        let id = unsafe {
            lotus_create_event_at(c_path.as_ptr(), DateTime::at(2026, 7, 9, 9, 0).civil, 0)
        };
        assert_ne!(id, 0);
        let loc = CString::new("location").unwrap();
        let val = CString::new("Room 4").unwrap();
        assert_eq!(
            unsafe { lotus_set_at(c_path.as_ptr(), id, loc.as_ptr(), val.as_ptr()) },
            1
        );
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let e = snap["entities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["id"] == id)
            .unwrap();
        let has_location = e["cells"]
            .as_array()
            .unwrap()
            .iter()
            .any(|c| c["property"] == "location" && c["value"] == "Room 4");
        assert!(has_location, "location set on an event shows in the snapshot");
        cleanup(&path);
    }

    #[test]
    fn a_torn_tail_is_repaired_then_cached() {
        let (path, c_path) = fresh_box("lotus_ffi_torn.log");
        unsafe { lotus_capture_at(c_path.as_ptr(), CString::new("real note").unwrap().as_ptr()) };
        // Append a torn (newline-less) trailing record straight to the file.
        {
            use std::io::Write as _;
            let mut f = std::fs::OpenOptions::new().append(true).open(&path).unwrap();
            f.write_all(b"{\"seq\":999,\"garbage\":").unwrap();
        }
        // First FFI open repairs (drops the torn record, lowering the length) and
        // caches the REPAIRED length; the second hits cleanly and agrees — the
        // torn record never leaks into either answer (Guard 1).
        let first = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let second = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(first, second);
        assert_eq!(first["entities"].as_array().unwrap().len(), 1);
        cleanup(&path);
    }

    #[test]
    fn content_seam_roundtrips() {
        let (path, c_path) = fresh_box("lotus_ffi_content.log");

        let text = CString::new("plain thought").unwrap();
        let id = unsafe { lotus_capture_at(c_path.as_ptr(), text.as_ptr()) };
        assert_ne!(id, 0);

        // The read: capture's RichText comes back verbatim, name null.
        let doc = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) };
        assert_eq!(doc["id"], id);
        assert_eq!(doc["name"], serde_json::Value::Null);
        assert_eq!(doc["trashed"], false);
        assert_eq!(doc["spans"], serde_json::json!([{"Text": "plain thought"}]));
        let base = doc["fingerprint"].as_u64().unwrap();
        assert_ne!(base, 0);

        // The snapshot's content_print is the same identity, for free.
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let row = snap["entities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["id"] == id)
            .unwrap();
        assert_eq!(row["content_print"].as_u64().unwrap(), base);

        // A save against the right base lands and reports the fresh print.
        let spans = CString::new(r#"[{"Text":"rewritten"}]"#).unwrap();
        let mut fresh: u64 = 0;
        let saved = unsafe {
            lotus_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), base, &mut fresh)
        };
        assert_eq!(saved, 1);
        assert_ne!(fresh, base);

        // A *different* rewrite against the stale base refuses — and the
        // log does not move. (The same spans against a stale base are a
        // no-op, not a conflict: writing what is already there is never
        // stale.)
        let session = Session::open(&path).unwrap();
        let history_len = session.store().history().len();
        drop(session);
        let drifted = CString::new(r#"[{"Text":"drifted"}]"#).unwrap();
        let stale = unsafe {
            lotus_set_content_at(c_path.as_ptr(), id, drifted.as_ptr(), base, &mut fresh)
        };
        assert_eq!(stale, -1);
        // Unchanged spans against the fresh base: success, no transaction.
        let unchanged = unsafe {
            lotus_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), fresh, std::ptr::null_mut())
        };
        assert_eq!(unchanged, 1);
        let session = Session::open(&path).unwrap();
        assert_eq!(session.store().history().len(), history_len);
        // The save was one transaction: RemoveCell + AddCell.
        let edit = session
            .store()
            .history()
            .iter()
            .find(|tx| tx.label == "edit")
            .unwrap();
        assert_eq!(edit.commands.len(), 2);
        drop(session);

        // A reference to nothing is not content.
        let bad = CString::new(r#"[{"Ref":999999}]"#).unwrap();
        assert_eq!(
            unsafe {
                lotus_set_content_at(c_path.as_ptr(), id, bad.as_ptr(), fresh, std::ptr::null_mut())
            },
            0
        );

        // Empty spans remove content; fingerprint returns to 0.
        let empty = CString::new("[]").unwrap();
        let mut cleared: u64 = 1;
        assert_eq!(
            unsafe {
                lotus_set_content_at(c_path.as_ptr(), id, empty.as_ptr(), fresh, &mut cleared)
            },
            1
        );
        assert_eq!(cleared, 0);

        // Undo restores the prior content in one step.
        assert_eq!(unsafe { lotus_undo_at(c_path.as_ptr()) }, 1);
        let doc = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) };
        assert_eq!(doc["spans"], serde_json::json!([{"Text": "rewritten"}]));

        // No such entity: the box answers "missing", never null — null is
        // reserved for a box that would not open at all.
        let gone = unsafe { read_json(lotus_content_at(c_path.as_ptr(), 999_999)) };
        assert_eq!(gone["missing"], true);
        assert_eq!(gone["fingerprint"], 0);

        cleanup(&path);
    }

    #[test]
    fn editing_content_retracts_stale_proposals() {
        let (path, c_path) = fresh_box("lotus_ffi_retract.log");

        // The clerk proposes due=friday from the captured words.
        let text = CString::new("kickoff friday").unwrap();
        let id = unsafe { lotus_capture_at(c_path.as_ptr(), text.as_ptr()) };
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let inbox = snap["inbox"].as_array().unwrap();
        assert_eq!(inbox.len(), 1);
        assert!(inbox[0]["reason"].as_str().unwrap().contains("friday"));
        let base = snap["entities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["id"] == id)
            .unwrap()["content_print"]
            .as_u64()
            .unwrap();

        // Rewriting the words retracts the stale proposal; the next sweep
        // derives from what is actually there. One proposal, the new one —
        // never friday and thursday side by side.
        let spans = CString::new(r#"[{"Text":"kickoff thursday"}]"#).unwrap();
        assert_eq!(
            unsafe {
                lotus_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), base, std::ptr::null_mut())
            },
            1
        );
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let inbox = snap["inbox"].as_array().unwrap();
        assert_eq!(inbox.len(), 1);
        assert!(inbox[0]["reason"].as_str().unwrap().contains("thursday"));

        // Retraction is not refusal: nothing landed in the declined
        // sidecar, so the clerk was free to re-derive.
        let session = Session::open(&path).unwrap();
        assert!(session.store().declined().is_empty());

        cleanup(&path);
    }

    #[test]
    fn legacy_text_content_reads_as_one_span() {
        let (path, c_path) = fresh_box("lotus_ffi_legacy.log");

        let mut session = Session::open(&path).unwrap();
        let id = session.allocate_id();
        session
            .commit(
                vec![
                    lotus_core::Command::Create { entity: id },
                    lotus_core::Command::AddCell {
                        entity: id,
                        cell: lotus_core::Cell {
                            property: lotus_core::props::CONTENT,
                            value: Value::text("old plain text"),
                        },
                    },
                ],
                "legacy",
                Author::User,
            )
            .unwrap();
        drop(session);

        let doc = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) };
        assert_eq!(doc["spans"], serde_json::json!([{"Text": "old plain text"}]));
        let base = doc["fingerprint"].as_u64().unwrap();
        assert_ne!(base, 0);

        // Saving over legacy content replaces it honestly, guarded by the
        // fingerprint of the stored Text value.
        let spans = CString::new(r#"[{"Text":"upgraded"}]"#).unwrap();
        assert_eq!(
            unsafe {
                lotus_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), base, std::ptr::null_mut())
            },
            1
        );

        cleanup(&path);
    }

    #[test]
    fn workspace_tree_roundtrips() {
        let (path, c_path) = fresh_box("lotus_ffi_workspace.log");

        // The seed ships Home; a snapshot shows it, favourite by shell
        // convention (builtin), top-level.
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let spaces = snap["workspaces"].as_array().unwrap();
        assert_eq!(spaces.len(), 1);
        assert_eq!(spaces[0]["name"], "Home");
        assert_eq!(spaces[0]["builtin"], "home");
        assert_eq!(spaces[0]["parent"], 0);

        // A new area, then a child project under it.
        let name = CString::new("Work").unwrap();
        let area = unsafe { lotus_create_workspace_at(c_path.as_ptr(), name.as_ptr(), 0) };
        assert_ne!(area, 0);
        let child_name = CString::new("Lotus port").unwrap();
        let child =
            unsafe { lotus_create_workspace_at(c_path.as_ptr(), child_name.as_ptr(), area) };
        assert_ne!(child, 0);

        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let spaces = snap["workspaces"].as_array().unwrap();
        assert_eq!(spaces.len(), 3);
        let child_row = spaces.iter().find(|w| w["id"] == child).unwrap();
        assert_eq!(child_row["parent"], area);

        // Workspaces are navigation chrome: never in Everything.
        assert!(
            !snap["everything"].as_array().unwrap().iter().any(|id| *id == area || *id == child)
        );

        // favorite/archived ride the ordinary set door; unset removes.
        let favorite = CString::new("favorite").unwrap();
        let yes = CString::new("true").unwrap();
        assert_eq!(
            unsafe { lotus_set_at(c_path.as_ptr(), area, favorite.as_ptr(), yes.as_ptr()) },
            1
        );
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let row = snap["workspaces"]
            .as_array()
            .unwrap()
            .iter()
            .find(|w| w["id"] == area)
            .unwrap()
            .clone();
        assert_eq!(row["favorite"], true);
        let parent_prop = CString::new("parent").unwrap();
        assert_eq!(
            unsafe { lotus_unset_at(c_path.as_ptr(), child, parent_prop.as_ptr()) },
            1
        );

        // Deletion never cascades: trashing the parent trashes only the
        // parent. The child survives with a now-dangling parent — the
        // shell re-roots it. One undo restores the parent.
        let up = CString::new("parent").unwrap();
        let area_arg = CString::new(format!("{area}")).unwrap();
        assert_eq!(
            unsafe { lotus_set_at(c_path.as_ptr(), child, up.as_ptr(), area_arg.as_ptr()) },
            1
        );
        assert_eq!(unsafe { lotus_trash_workspace_at(c_path.as_ptr(), area) }, 1);
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let after = snap["workspaces"].as_array().unwrap();
        assert_eq!(after.len(), 2); // Home + the surviving child
        assert!(after.iter().any(|w| w["id"] == child));
        assert!(!after.iter().any(|w| w["id"] == area));
        assert_eq!(unsafe { lotus_undo_at(c_path.as_ptr()) }, 1);
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(snap["workspaces"].as_array().unwrap().len(), 3);

        cleanup(&path);
    }

    #[test]
    fn set_at_and_create_note() {
        let (path, c_path) = fresh_box("lotus_ffi_set.log");

        // Birth: one transaction, typed note, created — then rename.
        let note = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        assert_ne!(note, 0);
        let prop = CString::new("name").unwrap();
        let value = CString::new("meeting notes").unwrap();
        assert_eq!(
            unsafe { lotus_set_at(c_path.as_ptr(), note, prop.as_ptr(), value.as_ptr()) },
            1
        );
        let doc = unsafe { read_json(lotus_content_at(c_path.as_ptr(), note)) };
        assert_eq!(doc["name"], "meeting notes");

        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let row = snap["entities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["id"] == note)
            .unwrap();
        assert_eq!(row["kinds"], serde_json::json!(["note"]));

        // The checkbox's door: set status by option name.
        let status = CString::new("status").unwrap();
        let done = CString::new("done").unwrap();
        assert_eq!(
            unsafe { lotus_set_at(c_path.as_ptr(), note, status.as_ptr(), done.as_ptr()) },
            1
        );
        // A date, parsed by the declared kind.
        let due = CString::new("due").unwrap();
        let day = CString::new("2026-07-08").unwrap();
        assert_eq!(
            unsafe { lotus_set_at(c_path.as_ptr(), note, due.as_ptr(), day.as_ptr()) },
            1
        );
        // Unknown property, unknown entity: refused.
        let nope = CString::new("frobnicate").unwrap();
        assert_eq!(
            unsafe { lotus_set_at(c_path.as_ptr(), note, nope.as_ptr(), done.as_ptr()) },
            0
        );
        assert_eq!(
            unsafe { lotus_set_at(c_path.as_ptr(), 999_999, status.as_ptr(), done.as_ptr()) },
            0
        );

        cleanup(&path);
    }

    #[test]
    fn content_history_is_the_log() {
        let (path, c_path) = fresh_box("lotus_ffi_history.log");

        let text = CString::new("first").unwrap();
        let id = unsafe { lotus_capture_at(c_path.as_ptr(), text.as_ptr()) };
        let base = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) }["fingerprint"]
            .as_u64()
            .unwrap();

        // A second version.
        let v2 = CString::new(r#"[{"Text":"second"}]"#).unwrap();
        let mut fresh: u64 = 0;
        assert_eq!(
            unsafe { lotus_set_content_at(c_path.as_ptr(), id, v2.as_ptr(), base, &mut fresh) },
            1
        );

        // History has both, newest first, each a whole content value.
        let hist = unsafe { read_json(lotus_content_history_at(c_path.as_ptr(), id)) };
        let versions = hist.as_array().unwrap();
        assert_eq!(versions.len(), 2);
        assert_eq!(versions[0]["spans"], serde_json::json!([{"Text": "second"}]));
        assert_eq!(versions[1]["spans"], serde_json::json!([{"Text": "first"}]));
        assert_eq!(versions[1]["author"], "user");

        // Restore = an ordinary set_content of the old spans (re-read the
        // fresh base first, the way the shell does).
        let re = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) };
        let now = re["fingerprint"].as_u64().unwrap();
        let restore = CString::new(r#"[{"Text":"first"}]"#).unwrap();
        assert_eq!(
            unsafe {
                lotus_set_content_at(c_path.as_ptr(), id, restore.as_ptr(), now, std::ptr::null_mut())
            },
            1
        );
        let back = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) };
        assert_eq!(back["spans"], serde_json::json!([{"Text": "first"}]));
        // The restore is a NEW version, appended — the log is never rewritten.
        let hist = unsafe { read_json(lotus_content_history_at(c_path.as_ptr(), id)) };
        assert_eq!(hist.as_array().unwrap().len(), 3);

        cleanup(&path);
    }

    #[test]
    fn undo_does_not_mint_a_phantom_history_version() {
        let (path, c_path) = fresh_box("lotus_ffi_hist_undo.log");

        let text = CString::new("first").unwrap();
        let id = unsafe { lotus_capture_at(c_path.as_ptr(), text.as_ptr()) };
        let base = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) }["fingerprint"]
            .as_u64()
            .unwrap();
        let v2 = CString::new(r#"[{"Text":"second"}]"#).unwrap();
        let mut fresh: u64 = 0;
        assert_eq!(
            unsafe { lotus_set_content_at(c_path.as_ptr(), id, v2.as_ptr(), base, &mut fresh) },
            1
        );

        // Undo the edit — the content reverts to "first" via an appended
        // inverse transaction. History must still show only the two
        // forward edits, not a third phantom "first".
        assert_eq!(unsafe { lotus_undo_at(c_path.as_ptr()) }, 1);
        let back = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) };
        assert_eq!(back["spans"], serde_json::json!([{"Text": "first"}]));
        let hist = unsafe { read_json(lotus_content_history_at(c_path.as_ptr(), id)) };
        assert_eq!(hist.as_array().unwrap().len(), 2);

        cleanup(&path);
    }

    #[test]
    fn marks_and_blocks_round_trip_through_the_seam() {
        let (path, c_path) = fresh_box("lotus_ffi_p4.log");

        let text = CString::new("start").unwrap();
        let id = unsafe { lotus_capture_at(c_path.as_ptr(), text.as_ptr()) };
        let base = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) }["fingerprint"]
            .as_u64()
            .unwrap();

        // A formatted doc: a heading, body with a bold+code run, a task
        // block, and a reference (a wiki-link is a Ref, so it backlinks).
        let doc = r#"[
            {"Break":{"Heading":1}},
            {"Text":"Title"},
            {"Break":"Body"},
            {"Text":"see "},
            {"Text":{"text":"this","marks":5}},
            {"Break":{"Task":{"depth":0,"done":false}}},
            {"Text":"ship 4a"}
        ]"#;
        let spans = CString::new(doc).unwrap();
        let mut fresh: u64 = 0;
        assert_eq!(
            unsafe {
                lotus_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), base, &mut fresh)
            },
            1
        );
        assert_ne!(fresh, base);

        // The read comes back with the marks and blocks intact.
        let got = unsafe { read_json(lotus_content_at(c_path.as_ptr(), id)) };
        assert_eq!(got["spans"][0], serde_json::json!({"Break": {"Heading": 1}}));
        assert_eq!(got["spans"][4], serde_json::json!({"Text": {"text": "this", "marks": 5}}));
        assert_eq!(got["spans"][5], serde_json::json!({"Break": {"Task": {"depth": 0, "done": false}}}));
        assert_eq!(got["fingerprint"].as_u64().unwrap(), fresh);

        // Saving the identical doc against the fresh base is a no-op, not
        // a conflict — the marks-and-blocks encoding is canonical.
        assert_eq!(
            unsafe {
                lotus_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), fresh, std::ptr::null_mut())
            },
            1
        );
        let session = Session::open(&path).unwrap();
        assert_eq!(session.store().history().iter().filter(|t| t.label == "edit").count(), 1);
        drop(session);

        cleanup(&path);
    }

    #[test]
    fn the_catalog_offers_user_properties_not_schema_plumbing() {
        let (path, c_path) = fresh_box("lotus_ffi_catalog.log");
        let text = CString::new("a note").unwrap();
        assert_ne!(unsafe { lotus_capture_at(c_path.as_ptr(), text.as_ptr()) }, 0);

        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let names: Vec<String> = snap["properties"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p["name"].as_str().unwrap().to_string())
            .collect();

        // The library properties a hand legitimately sets are offered.
        assert!(names.contains(&"due".to_string()));
        assert!(names.contains(&"status".to_string()));

        // The core's own schema vocabulary (ids below FIRST_USER_ID) is
        // plumbing, never addable: setting `working` would hide the note
        // from every view. None of it reaches the catalog.
        for plumbing in [
            "working", "private", "value-kind", "options", "expected",
            "default-view", "query", "renderer", "config", "external-id",
            "name", "type",
        ] {
            assert!(
                !names.contains(&plumbing.to_string()),
                "schema property {plumbing} leaked into the inspector catalog"
            );
        }

        cleanup(&path);
    }

    #[test]
    fn search_ranks_hits_and_facets_through_the_seam() {
        let (path, c_path) = fresh_box("lotus_ffi_search.log");
        let a = unsafe {
            lotus_capture_at(c_path.as_ptr(), CString::new("call anna about the report").unwrap().as_ptr())
        };
        let b = unsafe {
            lotus_capture_at(c_path.as_ptr(), CString::new("buy groceries").unwrap().as_ptr())
        };
        assert_ne!(a, 0);
        assert_ne!(b, 0);

        let raw = CString::new("report").unwrap();
        let json = unsafe { read_json(lotus_search_at(c_path.as_ptr(), raw.as_ptr())) };

        let hits = json["hits"].as_array().unwrap();
        let ids: Vec<u64> = hits.iter().map(|h| h["id"].as_u64().unwrap()).collect();
        assert!(ids.contains(&a), "the scrap mentioning the report is a hit");
        assert!(!ids.contains(&b), "an unrelated scrap is not");
        // Each hit carries a positive score and a why-matched field.
        assert!(hits[0]["score"].as_f64().unwrap() > 0.0);
        assert_eq!(hits[0]["field"], "content");
        // Facets is always an array (empty for bare captures with no type).
        assert!(json["facets"].is_array());

        // A blank query with no free text is a valid search (recent order).
        let blank = CString::new("").unwrap();
        let all = unsafe { read_json(lotus_search_at(c_path.as_ptr(), blank.as_ptr())) };
        let all_ids: Vec<u64> = all["hits"].as_array().unwrap().iter()
            .map(|h| h["id"].as_u64().unwrap()).collect();
        assert!(all_ids.contains(&a) && all_ids.contains(&b));

        cleanup(&path);
    }

    #[test]
    fn add_file_by_reference_through_the_seam() {
        let (path, c_path) = fresh_box("lotus_ffi_addfile.log");
        let doc = std::env::temp_dir().join("lotus_ffi_sample.txt");
        std::fs::write(&doc, b"hello from a referenced file").unwrap();
        let doc_c = CString::new(doc.to_str().unwrap()).unwrap();

        let id = unsafe { lotus_add_file_at(c_path.as_ptr(), doc_c.as_ptr()) };
        assert_ne!(id, 0);

        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let entity = snap["entities"].as_array().unwrap().iter()
            .find(|e| e["id"].as_u64() == Some(id)).unwrap();
        // name = filename, a file-kind cell rendering the path, format = txt
        assert_eq!(entity["title"], "lotus_ffi_sample.txt");
        let cells = entity["cells"].as_array().unwrap();
        let file_cell = cells.iter().find(|c| c["kind"] == "file").unwrap();
        assert_eq!(file_cell["value"], doc.to_str().unwrap());
        assert!(cells.iter().any(|c| c["property"] == "format" && c["value"] == "txt"));

        // A bad path adds nothing and returns 0.
        let bad = CString::new("/no/such/file.pdf").unwrap();
        assert_eq!(unsafe { lotus_add_file_at(c_path.as_ptr(), bad.as_ptr()) }, 0);

        let _ = std::fs::remove_file(&doc);
        cleanup(&path);
    }

    #[test]
    fn create_task_through_the_seam() {
        let (path, c_path) = fresh_box("lotus_ffi_task.log");
        let id = unsafe { lotus_create_task_at(c_path.as_ptr()) };
        assert_ne!(id, 0);

        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        let e = snap["entities"].as_array().unwrap().iter()
            .find(|e| e["id"].as_u64() == Some(id)).unwrap();
        // A typed, todo task: kinds carries "task", status renders "todo".
        let kinds: Vec<&str> =
            e["kinds"].as_array().unwrap().iter().filter_map(|k| k.as_str()).collect();
        assert!(kinds.contains(&"task"), "a created task is typed task");
        assert_eq!(e["status"], "todo");

        cleanup(&path);
    }

    #[test]
    fn list_membership_through_the_seam() {
        let (path, c_path) = fresh_box("lotus_ffi_list.log");
        let name = CString::new("Reading queue").unwrap();
        let list = unsafe { lotus_create_list_at(c_path.as_ptr(), name.as_ptr()) };
        assert_ne!(list, 0);
        let a = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        let b = unsafe { lotus_create_note_at(c_path.as_ptr()) };
        let related = CString::new("related").unwrap();
        let a_ref = CString::new(format!("#{a}")).unwrap();
        let b_ref = CString::new(format!("#{b}")).unwrap();

        // Add a, then b; a duplicate add is a no-op that still returns 1.
        assert_eq!(unsafe { lotus_add_cell_at(c_path.as_ptr(), list, related.as_ptr(), a_ref.as_ptr()) }, 1);
        assert_eq!(unsafe { lotus_add_cell_at(c_path.as_ptr(), list, related.as_ptr(), b_ref.as_ptr()) }, 1);
        assert_eq!(unsafe { lotus_add_cell_at(c_path.as_ptr(), list, related.as_ptr(), a_ref.as_ptr()) }, 1);

        let members = |snap: &serde_json::Value| -> Vec<u64> {
            snap["entities"].as_array().unwrap().iter()
                .find(|e| e["id"].as_u64() == Some(list)).unwrap()["cells"].as_array().unwrap()
                .iter().filter(|c| c["property"] == "related")
                .filter_map(|c| c["ref_target"].as_u64()).collect()
        };
        let snap = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(members(&snap), vec![a, b], "insertion order, not doubled");

        // Remove a — b remains, and a (the note) survives.
        assert_eq!(unsafe { lotus_remove_cell_at(c_path.as_ptr(), list, related.as_ptr(), a_ref.as_ptr()) }, 1);
        let snap2 = unsafe { read_json(lotus_snapshot(c_path.as_ptr())) };
        assert_eq!(members(&snap2), vec![b]);
        assert!(
            snap2["entities"].as_array().unwrap().iter().any(|e| e["id"].as_u64() == Some(a)),
            "un-tagging never deletes the member");

        cleanup(&path);
    }

    #[test]
    fn a_nul_byte_in_extracted_text_survives_the_seam() {
        let (path, c_path) = fresh_box("lotus_ffi_nul.log");
        // A text-format file with an embedded NUL (a null-padded log).
        let doc = std::env::temp_dir().join("lotus_ffi_nul.log");
        std::fs::write(&doc, b"before\0after the null").unwrap();
        let doc_c = CString::new(doc.to_str().unwrap()).unwrap();
        let id = unsafe { lotus_add_file_at(c_path.as_ptr(), doc_c.as_ptr()) };
        assert_ne!(id, 0);

        // The preview must not silently vanish — the NUL is scrubbed at the
        // seam, so a non-null string comes back with the words intact.
        let raw = unsafe { lotus_extracted_text_at(c_path.as_ptr(), id) };
        assert!(!raw.is_null(), "the NUL must not blank the preview");
        let text = unsafe { CStr::from_ptr(raw).to_str().unwrap().to_string() };
        unsafe { lotus_string_free(raw) };
        assert!(text.contains("before") && text.contains("after the null"));

        let _ = std::fs::remove_file(&doc);
        let _ = std::fs::remove_dir_all(files::cache_dir(path.to_str().unwrap()));
        cleanup(&path);
    }
}
