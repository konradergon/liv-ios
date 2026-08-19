//! The one C seam the macOS shell crosses — milestone 4, reshaped by the
//! single-writer lock of the review: the agent holds no session. Capture
//! opens the box, writes, and closes — the lock lives for milliseconds,
//! so the CLI stays usable while the agent sits in the menu bar.
//!
//! The clerk is not run here: pending proposals are re-derived by the
//! sweep at every open, so the next `liv inbox` sees exactly what this
//! capture deserved.

use std::ffi::{c_char, CStr, CString};

// The snapshot types + builder (T6, 2026-08-09 — lib.rs had reached
// 5,785 lines; rule 9 called for the seam).
mod snapshot;
use snapshot::{build_snapshot, build_snapshot_windowed, fingerprint};


use chrono::{Datelike, Local, Timelike};
use serde::Serialize;

use std::collections::HashMap;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use liv_core::{props, Author, DateTime, Entity, Id, Session, Store, Value};
use liv_services::{clerk, files, property_id, run, search, Constraint, Op, Query};

/// Capture one scrap into the box at `path`, creating and seeding the box
/// if it is fresh. Returns the new entity's id, or 0 on failure — 0 is
/// never a valid id. Whitespace-only text is a failure, not a scrap.
/// Fails (rather than waits) if another process holds the box open.
///
/// # Safety
/// `path` and `text` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_capture_at(path: *const c_char, text: *const c_char) -> u64 {
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
    if liv_services::seed_if_fresh(&mut session).is_err() {
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
    liv_services::capture(&mut session, text, created).unwrap_or(0)
}

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

/// P20j.4 — the log's self-defense notices (design §4): length
/// regression / same-length replacement / a conflicted-copy sibling.
/// Deduped by message; drained by `liv_vault_alerts_at`.
static VAULT_ALERTS: OnceLock<Mutex<Vec<String>>> = OnceLock::new();

fn vault_alert(message: String) {
    let alerts = VAULT_ALERTS.get_or_init(|| Mutex::new(Vec::new()));
    let mut alerts = alerts.lock().unwrap();
    if !alerts.contains(&message) {
        alerts.push(message);
    }
}

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

    // P20j.4 — the log defends itself (design §4): a SHORTER log than the
    // cache last proved, or a same-length different-inode file, means
    // something replaced the append-only source (a sync client, usually).
    // Never a silent adoption: the fast path refuses (the miss below does
    // a full honest replay of what is there) and a notice is surfaced.
    {
        let map = cache().lock().unwrap();
        if let Some(cached) = map.get(&key) {
            if cur_len < cached.log_len {
                vault_alert(format!(
                    "the log at {} SHRANK ({} → {} bytes) — a sync client may have replaced it with an older copy; opened by full replay, nothing adopted silently",
                    key.display(), cached.log_len, cur_len));
            } else if cur_inode != cached.inode && cur_len == cached.log_len {
                vault_alert(format!(
                    "the log at {} was REPLACED in place (same length, new file) — opened by full replay",
                    key.display()));
            }
        }
    }
    // A conflicted-copy sibling (cloud sync's fork fingerprint) raises a
    // notice every open until the user resolves it.
    if let (Some(dir), Some(stem)) = (path.parent(), path.file_stem()) {
        let stem = stem.to_string_lossy().to_lowercase();
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_lowercase();
                if name.contains(&stem) && name.contains("conflict") {
                    vault_alert(format!(
                        "a conflicted copy of the log at {} exists beside it ({}) — resolve it before trusting sync",
                        key.display(),
                        entry.file_name().to_string_lossy()));
                }
            }
        }
    }

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
    liv_services::seed_if_fresh(&mut session).ok()?;
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
            // ONE durable write for the whole sweep. This was a loop
            // calling `propose` per proposal, and each of those rewrote
            // the entire pending-queue file and fsynced it — N fsyncs and
            // O(N^2) bytes for one property edit (measured 2026-08-19:
            // 152 ms at 1,000 notes, unfinished at 2,000). Guarded by
            // `one_write_stays_flat_as_the_box_grows`.
            if session.propose_all(proposals).is_err() {
                cache().lock().unwrap().remove(&key);
                return;
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
    // P20j.5 — the continuous projection: every Wrote commit in a VAULT
    // box materializes. The PLAN computes here (pure CPU + one small
    // manifest read) while the store is still in hand; the file IO runs
    // AFTER checkin under the projector lock — never the box lock — and
    // a projection failure never fails the commit (surfaced by sync).
    let planned = if matches!(committed, Committed::Wrote) {
        liv_services::projection::vault_root_of(&key).map(|root| {
            let io = liv_services::projection::RealVaultIo::new(&root);
            let manifest = liv_services::projection::load_manifest(&io);
            let (ops, next) =
                liv_services::projection::plan_projection(session.store(), &manifest);
            (root, ops, next)
        })
    } else {
        None
    };
    checkin(key, session, committed);
    if let Some((root, ops, next)) = planned {
        let _ = liv_services::projection::apply_locked(&root, &ops, &next);
    }
    value
}

fn civil_today() -> DateTime {
    let now = Local::now();
    DateTime::date(now.year(), now.month(), now.day())
}

/// The value-kind a property declares, if any.
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
/// Returns a malloc'd string — free it with `liv_string_free`.
/// Null on failure (including the box being open elsewhere).
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_snapshot(path: *const c_char) -> *mut c_char {
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
/// `liv_snapshot`. Null on failure; free with `liv_string_free`.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_snapshot_window_at(
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
    /// The TRUE match count (bp3 a12): results are never silently capped —
    /// `hits` is the first page, `total` is the whole matching set.
    total: usize,
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
    // The full ranked set decides `total` (never capped); the wire carries
    // the first page. The shell can raise the page size later.
    let mut all = search::search(store, &sq, usize::MAX, extracted);
    let total = all.len();
    all.truncate(200);
    let facets = search::facet_properties(store, &sq)
        .into_iter()
        .map(|property| search::facet(store, &sq, property))
        .filter(|facet| !facet.values.is_empty())
        .collect();
    SearchResult { hits: all, facets, total }
}

/// Search the box: parse the raw DSL, rank the hits, count the facets.
/// Returns a malloc'd JSON string — free it with `liv_string_free`.
/// Null on failure (including the box being open elsewhere).
///
/// # Safety
/// `path` and `raw_query` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_search_at(
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
pub unsafe extern "C" fn liv_resync_file_at(path: *const c_char, id: u64) -> i32 {
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
/// `liv_string_free`; NULL only when the box is unavailable.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_extracted_text_at(path: *const c_char, id: u64) -> *mut c_char {
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
/// `s` must be a pointer returned by `liv_snapshot`, freed at most once.
#[no_mangle]
pub unsafe extern "C" fn liv_string_free(s: *mut c_char) {
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
                Some(liv_core::Command::AddCell { entity: e, .. }) => *e == entity,
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
pub unsafe extern "C" fn liv_accept_at(
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
pub unsafe extern "C" fn liv_reject_at(
    path: *const c_char,
    entity: u64,
    ordinal: u32,
    fingerprint: u64,
) -> i32 {
    triage(path, entity, ordinal, fingerprint, false)
}

/// Accept a GROUP of pending proposals as ONE transaction, one undo (P16b,
/// constitution 1.3). `fingerprints_json` is `[u64,…]` — the group's members by
/// their displayed fingerprints (the true identity; unique in the queue).
/// All-or-nothing: if ANY fingerprint no longer matches a pending proposal, the
/// whole group is refused untouched (the shell refreshes and re-reads). Returns
/// 1 on success, 0 on busy / a stale group / a bad payload.
///
/// # Safety
/// `path` and `fingerprints_json` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_accept_group_at(
    path: *const c_char,
    fingerprints_json: *const c_char,
) -> i32 {
    if fingerprints_json.is_null() {
        return 0;
    }
    let Ok(json) = CStr::from_ptr(fingerprints_json).to_str() else {
        return 0;
    };
    let Ok(wanted) = serde_json::from_str::<Vec<u64>>(json) else {
        return 0;
    };
    if wanted.is_empty() {
        return 0;
    }
    with_box(path, 0, move |session| {
        // Resolve every member to its pending index by fingerprint; a single
        // miss refuses the whole group without touching the store.
        let indices: Option<Vec<usize>> = wanted
            .iter()
            .map(|&fp| session.store().pending().iter().position(|p| fingerprint(p) == fp))
            .collect();
        let Some(indices) = indices else {
            return (0, Committed::Read);
        };
        match liv_services::clerk::accept_group(session, &indices) {
            Ok(_) => (1, Committed::Wrote),
            Err(_) => (0, Committed::Failed),
        }
    })
}

/// Undo the last committed transaction — capture, accept, set, anything
/// that landed in the log. (A decline is not a transaction; restoring a
/// refusal is a separate, deliberate act.) Returns 1 on success.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_undo_at(path: *const c_char) -> i32 {
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
pub unsafe extern "C" fn liv_probe(path: *const c_char) -> *mut c_char {
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
        liv_core::PersistError::Locked => "locked",
        liv_core::PersistError::Corrupt(_) => "corrupt",
        liv_core::PersistError::UnsupportedVersion(_) => "version",
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
    spans: Vec<liv_core::Span>,
}

/// One entity's content, fresh from the box. Legacy plain-text content
/// reads as one Text span (the fingerprint still covers the stored
/// value). Redirects resolve before reading. A box that opened fine but
/// holds no such entity answers `{"missing":true,…}`; null means only
/// that the box itself is unavailable (probe to learn why).
/// Free with `liv_string_free`.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_content_at(path: *const c_char, id: u64) -> *mut c_char {
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
                fingerprint: liv_services::content::content_fingerprint(
                    entity.get(props::CONTENT),
                ),
                spans: liv_services::content::content_spans(entity),
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
pub unsafe extern "C" fn liv_set_content_at(
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
    let Ok(spans) = serde_json::from_str::<Vec<liv_core::Span>>(json) else {
        return 0;
    };
    with_box(path, 0, move |session| {
        match liv_services::content::set_content(session, id, spans, base_fingerprint) {
            Ok(fresh) => {
                if !fresh_fingerprint.is_null() {
                    unsafe { *fresh_fingerprint = fresh };
                }
                (1, Committed::Wrote)
            }
            // A stale save refused before it touched the store — cache stays valid.
            Err(liv_services::content::ContentError::Stale) => (-1, Committed::Read),
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
pub unsafe extern "C" fn liv_set_at(
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
        let ok = liv_services::content::set_property(session, id, property, value).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Add ONE cell to a (multi-valued) property — list membership adds a
/// member as ("related", "#<member-id>"). Unlike liv_set_at (replace all
/// cells of the property) and liv_unset_at (remove all), this touches
/// exactly one cell; adding a value already present is a no-op that still
/// returns 1. Value parsed by the property's kind. 1 ok, 0 on
/// busy/parse/no-entity.
///
/// # Safety
/// `path`, `property`, `value` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_add_cell_at(
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
        let ok = liv_services::content::add_cell(session, id, property, value).is_ok();
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
pub unsafe extern "C" fn liv_remove_cell_at(
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
        let ok = liv_services::content::remove_cell(session, id, property, value).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

#[derive(Serialize)]
struct ContentVersionRow {
    seq: u64,
    time: i64,
    author: String,
    label: String,
    spans: Vec<liv_core::Span>,
}

/// Every past version of an entity's content, NEWEST first, as one JSON
/// array: [{"seq","time","author","label","spans"}]. The log is the
/// history — no reconstruction; each entry is a whole content value, and
/// restoring one is an ordinary `liv_set_content_at` of its spans.
/// Null when the box is unavailable. Free with `liv_string_free`.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_content_history_at(path: *const c_char, id: u64) -> *mut c_char {
    with_box(path, std::ptr::null_mut(), |session| {
        let mut versions: Vec<ContentVersionRow> =
            liv_services::content::content_history(session.store(), id)
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

/// Both directions of an entity's LINKS, as one JSON object:
/// `{"out":[Link…],"in":[Link…]}` with
/// `Link = {"id","name","kinds":[..],"property","from_body"}`.
///
/// One mechanism, two doors (feature-map §6): a `[[ ]]` typed in a body
/// is a `Ref` span, a link picked in properties is a `related` cell, and
/// both are the same edge — `from_body` says only WHERE it lives, which
/// is what decides whether the shell may remove it in place. `in` is the
/// core's backlink index, so it costs what the entity's links cost, not
/// what the box costs (services/tests/scale.rs).
///
/// Filing (`area`, `project`, `people`, `type`) is not a link, and
/// backstage furniture (layers, pins, anything `working`) never appears.
/// An unknown id answers with two empty lists. Null only when the box is
/// unavailable. Free with `liv_string_free`.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_links_at(path: *const c_char, id: u64) -> *mut c_char {
    with_box(path, std::ptr::null_mut(), |session| {
        let links = liv_services::links::links(session.store(), id);
        let out = match serde_json::to_string(&links).ok().and_then(|s| CString::new(s).ok()) {
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
pub unsafe extern "C" fn liv_create_note_at(path: *const c_char) -> u64 {
    with_box(path, 0, |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let id = liv_services::content::create_note(session, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Get-or-create the daily note for a day + workspace (P12 12a) and return
/// its id — the one place a query-then-create runs in ONE session so two
/// entry points can never double-create. `date_civil` is any packed civil in
/// the day (the minute is normalized away); `workspace` 0 = none (global).
/// Read on the found path (store untouched), Wrote on birth (forces re-sweep).
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_open_daily_note_at(
    path: *const c_char,
    date_civil: i64,
    workspace: u64,
) -> u64 {
    // Normalize to the DAY: zero the packed time, date_only.
    let day = DateTime { civil: (date_civil / 10_000) * 10_000, date_only: true, end: None };
    let ws = (workspace != 0).then_some(workspace);
    with_box(path, 0, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        match liv_services::content::get_or_create_daily_note(session, day, ws, created) {
            Ok((id, created)) => (id, if created { Committed::Wrote } else { Committed::Read }),
            Err(_) => (0, Committed::Failed),
        }
    })
}

/// Stamp an entity's TYPE by name (P12 12d — the Inbox Route commit). 1 on
/// success, 0 on refusal (unknown type name / no entity). A refusal never
/// touched the store, so the cache stays valid.
///
/// # Safety
/// `path` and `type_name` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_set_type_at(
    path: *const c_char,
    id: u64,
    type_name: *const c_char,
) -> i32 {
    if type_name.is_null() {
        return 0;
    }
    let Ok(type_name) = CStr::from_ptr(type_name).to_str() else {
        return 0;
    };
    with_box(path, 0, |session| {
        match liv_services::content::set_type(session, id, type_name) {
            Ok(()) => (1, Committed::Wrote),
            Err(liv_services::content::WriteError::Refused(_)) => (0, Committed::Read),
            Err(liv_services::content::WriteError::Persist(_)) => (0, Committed::Failed),
        }
    })
}

/// Create a task by hand (the Tasks quick-add): one transaction — type=task
/// + status=todo + created. Returns the new id, 0 on failure. Distinct from
/// capture, which makes an untyped scrap the clerk quarantines.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_create_task_at(path: *const c_char) -> u64 {
    with_box(path, 0, |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let id = liv_services::content::create_task(session, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Layer ① of the value pool (P11/11e): a property's distinct live values
/// with usage counts, JSON [{value, count}] in deterministic order (count
/// desc, then display). Values render through views::display, so a span
/// reads "start -> end" and a select reads its option's name. Null on
/// busy/unknown property. Free with `liv_string_free`.
///
/// # Safety
/// `path` and `property` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_distinct_values_at(
    path: *const c_char,
    property: *const c_char,
) -> *mut c_char {
    if property.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(prop_name) = CStr::from_ptr(property).to_str() else {
        return std::ptr::null_mut();
    };
    with_box(path, std::ptr::null_mut(), |session| {
        let store = session.store();
        let Some(prop) = property_id(store, prop_name) else {
            return (std::ptr::null_mut(), Committed::Read);
        };
        let rows: Vec<serde_json::Value> = liv_services::search::distinct_values(store, prop)
            .into_iter()
            .map(|(value, count)| {
                serde_json::json!({
                    "value": liv_views::display(store, &value),
                    "count": count,
                })
            })
            .collect();
        let out = match serde_json::to_string(&rows).ok().and_then(|s| CString::new(s).ok()) {
            Some(s) => s.into_raw(),
            None => std::ptr::null_mut(),
        };
        (out, Committed::Read)
    })
}

/// The status vocabulary OFFERED to a kind (P11/11d), sorted by board
/// order: JSON [{id,name,order,hue,completes}]. Options with no carriers
/// are included — an empty board column keeps its header. Null on
/// busy/unknown kind. Free with `liv_string_free`.
///
/// # Safety
/// `path` and `kind` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_status_options_at(
    path: *const c_char,
    kind: *const c_char,
) -> *mut c_char {
    if kind.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(kind_name) = CStr::from_ptr(kind).to_str() else {
        return std::ptr::null_mut();
    };
    with_box(path, std::ptr::null_mut(), |session| {
        let Some(kind_id) = liv_services::content::find_type(session.store(), kind_name)
        else {
            return (std::ptr::null_mut(), Committed::Read);
        };
        let options = liv_services::status_options_for(session.store(), kind_id);
        let out = match serde_json::to_string(&options).ok().and_then(|s| CString::new(s).ok()) {
            Some(s) => s.into_raw(),
            None => std::ptr::null_mut(),
        };
        (out, Committed::Read)
    })
}

/// A new status option for a kind (column-add / "Edit vocabulary…"): one
/// commit, ordered last for that kind. `hue` < 0 means none. Returns the
/// option id, or 0 on busy/refusal/failure.
///
/// # Safety
/// `path`, `kind`, and `name` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_add_status_option_at(
    path: *const c_char,
    kind: *const c_char,
    name: *const c_char,
    hue: f64,
) -> u64 {
    if kind.is_null() || name.is_null() {
        return 0;
    }
    let (Ok(kind_name), Ok(option_name)) =
        (CStr::from_ptr(kind).to_str(), CStr::from_ptr(name).to_str())
    else {
        return 0;
    };
    with_box(path, 0, |session| {
        let Some(kind_id) = liv_services::content::find_type(session.store(), kind_name)
        else {
            // No such kind: nothing touched, the cached store stays valid.
            return (0, Committed::Read);
        };
        let hue = (hue >= 0.0).then_some(hue);
        match liv_services::content::add_status_option(session, kind_id, option_name, hue) {
            Ok(id) => (id, Committed::Wrote),
            // A refusal never touched the store — the cache stays valid;
            // only a real persist failure evicts (the review's finding).
            Err(liv_services::content::WriteError::Refused(_)) => (0, Committed::Read),
            Err(liv_services::content::WriteError::Persist(_)) => (0, Committed::Failed),
        }
    })
}

/// Birth a property definition by name + value kind — the add-property
/// popover's create leg (P11.5g; the single Rust exception, carved after
/// the failing test showed set refuses unknown names). Returns the new
/// definition id, or 0 on busy/refusal (empty name, duplicate, unknown
/// kind).
///
/// # Safety
/// `path`, `name`, and `kind` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_add_property_at(
    path: *const c_char,
    name: *const c_char,
    kind: *const c_char,
) -> u64 {
    if name.is_null() || kind.is_null() {
        return 0;
    }
    let (Ok(name), Ok(kind)) = (CStr::from_ptr(name).to_str(), CStr::from_ptr(kind).to_str())
    else {
        return 0;
    };
    with_box(path, 0, |session| {
        match liv_services::content::birth_property(session, name, kind) {
            Ok(id) => (id, Committed::Wrote),
            // A refusal never touched the store — the cache stays valid.
            Err(liv_services::content::WriteError::Refused(_)) => (0, Committed::Read),
            Err(liv_services::content::WriteError::Persist(_)) => (0, Committed::Failed),
        }
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
pub unsafe extern "C" fn liv_set_span_at(
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
        let ok = liv_services::content::set_property(session, id, prop_name, &raw).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Space-cycles a date row's role (P11/11a): one transaction moving the
/// value — civil + date_only intact — from `property` to the next role in
/// the ring due → date → valid-until → occurred → purchased-on → due.
/// Returns the NEW property name (malloc'd — free with `liv_string_free`),
/// or NULL on busy/refusal. A refusal never touched the store, so the cached
/// snapshot stays valid (`Read`); only a real write re-sweeps (`Wrote`).
///
/// # Safety
/// `path` and `property` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_cycle_date_role_at(
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
        match liv_services::content::cycle_date_role(session, id, prop) {
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
            Err(liv_services::content::WriteError::Refused(_)) => {
                (std::ptr::null_mut(), Committed::Read)
            }
            Err(liv_services::content::WriteError::Persist(_)) => {
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
pub unsafe extern "C" fn liv_create_event_at(
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
        let id = liv_services::content::create_event(session, due, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Birth of a list: Create + type=list + name + created, one transaction.
/// Named at birth (unlike a note). Returns the id, 0 on failure.
///
/// # Safety
/// `path` and `name` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_create_list_at(
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
        let id = liv_services::content::create_list(session, name, created).unwrap_or(0);
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
pub unsafe extern "C" fn liv_add_file_at(
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
        let id = liv_services::files::add_file(session, file_path, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Import a batch (P15a): `items_json` is a JSON array of tagged import items
/// (`{"kind":"link","url":…}` / `"file"` / `"note"` / `"scrap"`); `stamps_json`
/// is `[[property,target],…]` reference cells stamped on every committed entity
/// (the funnel's inherited project/area). One transaction, one undo. Returns the
/// count committed (deduped items are skipped), -1 on a parse/box error.
///
/// # Safety
/// `path`, `items_json`, `stamps_json` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_import_batch_at(
    path: *const c_char,
    items_json: *const c_char,
    stamps_json: *const c_char,
) -> i64 {
    if items_json.is_null() {
        return -1;
    }
    let Ok(items_str) = CStr::from_ptr(items_json).to_str() else {
        return -1;
    };
    let Ok(items) = serde_json::from_str::<Vec<liv_services::import::ImportItem>>(items_str) else {
        return -1;
    };
    // A non-null but malformed stamps_json is an error, not silently empty —
    // else the funnel's inherited project/area would vanish and the import
    // would still report success (the P15a review's finding).
    let stamps: Vec<(u64, u64)> = if stamps_json.is_null() {
        Vec::new()
    } else {
        let Ok(s) = CStr::from_ptr(stamps_json).to_str() else {
            return -1;
        };
        match serde_json::from_str(s) {
            Ok(v) => v,
            Err(_) => return -1,
        }
    };
    let defaults = liv_services::import::ImportDefaults { stamps };

    with_box(path, -1, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        match liv_services::import::commit_batch(session, &items, created, &defaults) {
            Ok(ids) => {
                let n = ids.len() as i64;
                (n, if ids.is_empty() { Committed::Read } else { Committed::Wrote })
            }
            Err(_) => (-1, Committed::Failed),
        }
    })
}

/// Export (P15c): `ids_json` is `[u64,…]` (the shell-resolved matched-minus-
/// unchecked set), `group_props_json` is `[u64,…]` group-by properties (≤2
/// used), `dest` a folder OUTSIDE the box. Copy-only, a projection — the log is
/// untouched (Committed::Read). Returns the count written, -1 on parse/IO error.
///
/// # Safety
/// `path`, `ids_json`, `group_props_json`, `dest` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_export_at(
    path: *const c_char,
    ids_json: *const c_char,
    group_props_json: *const c_char,
    dest: *const c_char,
) -> i64 {
    if ids_json.is_null() || dest.is_null() {
        return -1;
    }
    let (Ok(ids_str), Ok(dest_str)) =
        (CStr::from_ptr(ids_json).to_str(), CStr::from_ptr(dest).to_str())
    else {
        return -1;
    };
    let Ok(ids) = serde_json::from_str::<Vec<u64>>(ids_str) else {
        return -1;
    };
    let groups: Vec<u64> = if group_props_json.is_null() {
        Vec::new()
    } else {
        let Ok(g) = CStr::from_ptr(group_props_json).to_str() else {
            return -1;
        };
        match serde_json::from_str(g) {
            Ok(v) => v,
            Err(_) => return -1,
        }
    };

    // Compute the plan under the box lock (a store read), then RELEASE the lock
    // before the outbound copy — never hold the single-writer lock across a
    // multi-GB byte copy (the P15c review's finding).
    let plan = with_box(path, None, move |session| {
        (
            Some(liv_services::export::export_plan(session.store(), &ids, &groups)),
            Committed::Read,
        )
    });
    let Some(plan) = plan else {
        return -1; // box busy
    };
    match liv_services::export::export_write(&plan, std::path::Path::new(dest_str)) {
        Ok(n) => n as i64,
        Err(_) => -1,
    }
}

/// Birth of a workspace: Create + type + name (+ parent, trailing
/// order), one transaction. parent 0 = top level. Returns the id, 0 on
/// failure.
///
/// # Safety
/// `path` and `name` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_create_workspace_at(
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
        let id = liv_services::content::create_workspace(session, name, parent, created).unwrap_or(0);
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
pub unsafe extern "C" fn liv_trash_workspace_at(path: *const c_char, id: u64) -> i32 {
    with_box(path, 0, |session| {
        let ok = liv_services::content::trash_workspace(session, id).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Pin an object to the Favourites shelf (P17g): one transaction that
/// births the pin (and, first time, the `pin` type + `target` property),
/// landing after the last pin. Idempotent — re-pinning returns the
/// existing pin's id. Returns the pin id, 0 on failure.
///
/// Additive verb (boundary rule): with_box + Committed, shipped with a
/// round-trip test, flagged in the PR.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_pin_at(path: *const c_char, target: u64) -> u64 {
    with_box(path, 0, |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let id = liv_services::content::create_pin(session, target, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Unpin a target: trash its live pin (soft, reversible). Returns 1 when a
/// pin was removed, 0 when the target had none (a quiet no-op).
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_unpin_at(path: *const c_char, target: u64) -> i32 {
    with_box(path, 0, |session| {
        match liv_services::content::remove_pin(session, target) {
            Ok(true) => (1, Committed::Wrote),
            Ok(false) => (0, Committed::Read),
            Err(_) => (0, Committed::Failed),
        }
    })
}

/// Create a habit (P18b): an ordinary front-of-house entity. `points` <= 0
/// means "no points cell" (reads as 1); `cadence` may be null. Returns the
/// habit id, 0 on failure.
///
/// Additive verb (boundary rule): with_box + Committed, shipped with a
/// round-trip test, flagged in the PR.
///
/// # Safety
/// `path` and `name` must be valid NUL-terminated UTF-8; `cadence` may be
/// null or valid UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_create_habit_at(
    path: *const c_char,
    name: *const c_char,
    points: f64,
    cadence: *const c_char,
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
    let cadence = if cadence.is_null() {
        None
    } else {
        match CStr::from_ptr(cadence).to_str() {
            Ok(c) if !c.trim().is_empty() => Some(c.trim().to_string()),
            _ => None,
        }
    };
    with_box(path, 0, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let points = (points > 0.0).then_some(points);
        let id = liv_services::content::create_habit(
            session,
            name,
            points,
            cadence.as_deref(),
            created,
        )
        .unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Check a habit in on a civil day (YYYYMMDD; 0 = today). One backstage
/// record, one commit, one undo; idempotent per (habit, day) so the checkbox
/// toggle is safe. Uncheck = liv_trash_at on the returned row. Returns the
/// check-in id, 0 on failure.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_check_in_at(path: *const c_char, habit: u64, day: i64) -> u64 {
    with_box(path, 0, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let day = if day > 0 {
            day
        } else {
            (now.year() as i64) * 10_000 + (now.month() as i64) * 100 + now.day() as i64
        };
        let id = liv_services::content::check_in(session, habit, day, created).unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Rename one VALUE everywhere it is carried (P19b): ONE grouped
/// transaction, one undo — text cells rewrite; select/status renames the
/// option or MERGES into an existing one. Returns the carrier count, or -1
/// on refusal (unknown property, wrong kind, empty/unchanged name).
///
/// Additive verb (boundary rule): with_box + Committed, crash-tested (the
/// torn-tail test), flagged in the PR.
///
/// # Safety
/// `path`, `property`, `old`, and `new` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_rename_value_at(
    path: *const c_char,
    property: *const c_char,
    old: *const c_char,
    new: *const c_char,
) -> i64 {
    if property.is_null() || old.is_null() || new.is_null() {
        return -1;
    }
    let (Ok(property), Ok(old), Ok(new)) = (
        CStr::from_ptr(property).to_str(),
        CStr::from_ptr(old).to_str(),
        CStr::from_ptr(new).to_str(),
    ) else {
        return -1;
    };
    with_box(path, -1, move |session| {
        use liv_services::content::WriteError;
        match liv_services::content::rename_value(session, property, old, new) {
            Ok(count) => (count as i64, Committed::Wrote),
            // A refusal never touched the store: the cache survives (Read).
            // A persist failure leaves the MEMORY store one committed txn
            // ahead of the disk — caching that serves a phantom rename and
            // commits later writes onto a torn tail (the P19 review's high):
            // Failed evicts.
            Err(WriteError::Refused(_)) => (-1, Committed::Read),
            Err(_) => (-1, Committed::Failed),
        }
    })
}

/// Mint an option for a select/status property (P19b) — idempotent (an
/// existing option of that name is returned). Returns the option id, 0 on
/// failure. Additive verb, tested, flagged.
///
/// # Safety
/// `path` and `name` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_add_option_at(
    path: *const c_char,
    property: u64,
    name: *const c_char,
) -> u64 {
    if name.is_null() {
        return 0;
    }
    let Ok(name) = CStr::from_ptr(name).to_str() else {
        return 0;
    };
    with_box(path, 0, move |session| {
        use liv_services::content::WriteError;
        match liv_services::content::add_option(session, property, name) {
            // The idempotent hit committed nothing — Read, or every re-add
            // triggers a needless re-sweep (the create-or-return pattern).
            Ok((id, created)) => (id, if created { Committed::Wrote } else { Committed::Read }),
            Err(WriteError::Refused(_)) => (0, Committed::Read),
            Err(_) => (0, Committed::Failed),
        }
    })
}

/// Toggle one kind's reference cell on a definition's display-attribute
/// property ("hide-on-kind" / "core-on-kind") — additive PER KIND (P19
/// review: `set` replaces every cell, un-hiding the other kinds). Returns
/// 1 changed, 0 no-op, -1 refused.
///
/// Additive verb (boundary rule): with_box + Committed, tested, flagged.
///
/// # Safety
/// `path` and `property` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_kind_flag_at(
    path: *const c_char,
    def: u64,
    property: *const c_char,
    kind: u64,
    on: i32,
) -> i32 {
    if property.is_null() {
        return -1;
    }
    let Ok(property) = CStr::from_ptr(property).to_str() else {
        return -1;
    };
    with_box(path, -1, move |session| {
        use liv_services::content::WriteError;
        match liv_services::content::toggle_kind_ref(session, def, property, kind, on != 0) {
            Ok(true) => (1, Committed::Wrote),
            Ok(false) => (0, Committed::Read),
            Err(WriteError::Refused(_)) => (-1, Committed::Read),
            Err(_) => (-1, Committed::Failed),
        }
    })
}

/// The vault's status (P20j.5): {"mode":"vault"|"legacy","root":…,
/// "files":N}. Cheap — no scan. Additive verb, flagged.
///
/// # Safety
/// Free the returned string with `liv_string_free`.
#[no_mangle]
pub unsafe extern "C" fn liv_vault_status_at(path: *const c_char) -> *mut c_char {
    if path.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(p) = CStr::from_ptr(path).to_str() else {
        return std::ptr::null_mut();
    };
    let box_path = std::path::Path::new(p);
    let json = match liv_services::projection::vault_root_of(box_path) {
        None => serde_json::json!({ "mode": "legacy" }),
        Some(root) => {
            let io = liv_services::projection::RealVaultIo::new(&root);
            let manifest = liv_services::projection::load_manifest(&io);
            serde_json::json!({
                "mode": "vault",
                "root": root.display().to_string(),
                "files": manifest.rows.len(),
            })
        }
    };
    CString::new(json.to_string()).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

/// One vault sync (P20j.5): scan → tier-A ingest as ONE "vault-edit"
/// transaction → adopt → re-project. Returns
/// {"edited":N,"created":N,"surfaced":N} or null on busy/legacy.
/// The scan's file reads run inside the box hold v0 (recorded — the
/// store cannot yet be snapshotted out); sync is launch/user-triggered.
///
/// # Safety
/// Free the returned string with `liv_string_free`.
#[no_mangle]
pub unsafe extern "C" fn liv_vault_sync_at(path: *const c_char) -> *mut c_char {
    let Some((mut session, key)) = open_box(path) else {
        return std::ptr::null_mut();
    };
    let Some(root) = liv_services::projection::vault_root_of(&key) else {
        checkin(key, session, Committed::Read);
        return CString::new(r#"{"mode":"legacy"}"#)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut());
    };
    let io = liv_services::projection::RealVaultIo::new(&root);
    let mut manifest = liv_services::projection::load_manifest(&io);
    let findings =
        liv_services::projection::scan(&io, session.store(), &manifest);
    let outcome = match liv_services::projection::ingest(
        &mut session,
        &io,
        &manifest,
        &findings,
    ) {
        Ok(outcome) => outcome,
        Err(_) => {
            checkin(key, session, Committed::Failed);
            return std::ptr::null_mut();
        }
    };
    // Adopted hand-born paths fold in BEFORE planning, so the projector
    // renames them to canonical instead of duplicating (20j.3's pin).
    liv_services::projection::adopt_into(&mut manifest, &outcome.adopted);
    let (ops, next) =
        liv_services::projection::plan_projection(session.store(), &manifest);
    let changed = outcome.edited + outcome.created > 0;
    checkin(key, session, if changed { Committed::Wrote } else { Committed::Read });
    let _ = liv_services::projection::apply_locked(&root, &ops, &next);
    let json = serde_json::json!({
        "edited": outcome.edited,
        "created": outcome.created,
        "surfaced": outcome.surfaced,
    });
    CString::new(json.to_string()).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

/// Full re-materialization (P20j.5): plan from an EMPTY manifest so every
/// file rewrites even if the manifest lies. Returns the file count, -1 on
/// busy/legacy/failure.
#[no_mangle]
pub unsafe extern "C" fn liv_vault_rebuild_at(path: *const c_char) -> i64 {
    let Some((session, key)) = open_box(path) else {
        return -1;
    };
    let Some(root) = liv_services::projection::vault_root_of(&key) else {
        checkin(key, session, Committed::Read);
        return -1;
    };
    let (ops, next) = liv_services::projection::plan_projection(
        session.store(),
        &liv_services::projection::Manifest::default(),
    );
    checkin(key, session, Committed::Read);
    match liv_services::projection::apply_locked(&root, &ops, &next) {
        Ok(()) => next.rows.len() as i64,
        Err(_) => -1,
    }
}

/// The vault's current divergence findings (P20j.7): a read-only scan,
/// JSON `[{kind, id?, path?, count?}]` — kind ∈ conflict|missing|newfile|
/// masschange|orphan|edited. `all=1` expands a mass burst. No ingest, no
/// write. Additive verb, flagged.
///
/// # Safety
/// Free the returned string with `liv_string_free`.
#[no_mangle]
pub unsafe extern "C" fn liv_vault_findings_at(
    path: *const c_char,
    all: i32,
) -> *mut c_char {
    let Some((session, key)) = open_box(path) else {
        return CString::new("[]").map(CString::into_raw).unwrap_or(std::ptr::null_mut());
    };
    let Some(root) = liv_services::projection::vault_root_of(&key) else {
        checkin(key, session, Committed::Read);
        return CString::new("[]").map(CString::into_raw).unwrap_or(std::ptr::null_mut());
    };
    let io = liv_services::projection::RealVaultIo::new(&root);
    let manifest = liv_services::projection::load_manifest(&io);
    let findings = if all != 0 {
        liv_services::projection::scan_all(&io, session.store(), &manifest)
    } else {
        liv_services::projection::scan(&io, session.store(), &manifest)
    };
    checkin(key, session, Committed::Read);

    use liv_services::projection::ReconcileFinding as F;
    let arr: Vec<serde_json::Value> = findings
        .iter()
        .map(|f| match f {
            F::Edited { id, path } => serde_json::json!({ "kind": "edited", "id": id, "path": path }),
            F::NewFile { path } => serde_json::json!({ "kind": "newfile", "path": path }),
            F::Conflict { id, path } => serde_json::json!({ "kind": "conflict", "id": id, "path": path }),
            F::Missing { id, path } => serde_json::json!({ "kind": "missing", "id": id, "path": path }),
            F::OrphanCopy { path } => serde_json::json!({ "kind": "orphan", "path": path }),
            F::MassChange { count } => serde_json::json!({ "kind": "masschange", "count": count }),
        })
        .collect();
    let json = serde_json::to_string(&arr).unwrap_or_else(|_| "[]".into());
    CString::new(json).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

/// Resolve one divergence (P20j.7): `verdict` ∈ "take-disk" | "keep-app" |
/// "trash". take-disk/trash commit ONE undoable txn; keep-app rewrites the
/// file from the store (no box write). All re-project under the lock.
/// Returns 1 on success, 0 on failure/busy. Additive verb, flagged.
///
/// # Safety
/// `path`, `rel_path`, and `verdict` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_vault_resolve_at(
    path: *const c_char,
    id: u64,
    rel_path: *const c_char,
    verdict: *const c_char,
) -> i32 {
    if rel_path.is_null() || verdict.is_null() {
        return 0;
    }
    let (Ok(rel), Ok(verdict)) =
        (CStr::from_ptr(rel_path).to_str(), CStr::from_ptr(verdict).to_str())
    else {
        return 0;
    };
    let Some((mut session, key)) = open_box(path) else {
        return 0;
    };
    let Some(root) = liv_services::projection::vault_root_of(&key) else {
        checkin(key, session, Committed::Read);
        return 0;
    };
    use liv_services::projection as proj;
    let (ok, committed): (bool, Committed) = match verdict {
        "take-disk" => {
            let io = proj::RealVaultIo::new(&root);
            match proj::resolve_take_disk(&mut session, &io, id, rel) {
                Ok(()) => (true, Committed::Wrote),
                Err(_) => (false, Committed::Failed),
            }
        }
        "trash" => match proj::resolve_trash(&mut session, id) {
            Ok(()) => (true, Committed::Wrote),
            Err(_) => (false, Committed::Failed),
        },
        "keep-app" => {
            // No box write: do the file IO under the projector lock, tag
            // Read so the cache stays.
            let mut io = proj::RealVaultIo::new(&root);
            (proj::resolve_keep_app(&mut io, session.store(), id).is_ok(), Committed::Read)
        }
        _ => (false, Committed::Read),
    };
    // Re-project the box's current truth (parks trashed files, canonicalizes
    // an ingested take-disk). keep-app already wrote its one file.
    let planned = if matches!(committed, Committed::Wrote) {
        let io = proj::RealVaultIo::new(&root);
        let manifest = proj::load_manifest(&io);
        Some(proj::plan_projection(session.store(), &manifest))
    } else {
        None
    };
    checkin(key, session, committed);
    if let Some((ops, next)) = planned {
        let _ = proj::apply_locked(&root, &ops, &next);
    }
    if ok { 1 } else { 0 }
}

/// Drain the vault's self-defense notices (P20j.4): a JSON array of
/// strings — length regression, in-place replacement, conflicted-copy
/// siblings. Read-and-clear; empty array when quiet. Additive verb
/// (boundary rule), flagged.
///
/// # Safety
/// The returned string must be freed with `liv_string_free`.
#[no_mangle]
pub unsafe extern "C" fn liv_vault_alerts_at(path: *const c_char) -> *mut c_char {
    // Path-scoped drain: every alert message embeds its box path, so one
    // box's reader never swallows another's notices (also what keeps the
    // parallel test processes honest).
    let wanted = if path.is_null() {
        None
    } else {
        CStr::from_ptr(path)
            .to_str()
            .ok()
            .map(|p| {
                std::fs::canonicalize(p)
                    .map(|c| c.display().to_string())
                    .unwrap_or_else(|_| p.to_string())
            })
    };
    let drained: Vec<String> = {
        let alerts = VAULT_ALERTS.get_or_init(|| Mutex::new(Vec::new()));
        let mut alerts = alerts.lock().unwrap();
        match &wanted {
            None => std::mem::take(&mut *alerts),
            Some(needle) => {
                let (mine, rest): (Vec<String>, Vec<String>) =
                    alerts.drain(..).partition(|a| a.contains(needle.as_str()));
                *alerts = rest;
                mine
            }
        }
    };
    let json = serde_json::to_string(&drained).unwrap_or_else(|_| "[]".into());
    CString::new(json).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

/// Import a batch of messages (P20g, BP-15): JSON array of
/// {external_id, from, source, sent?, body}. ONE transaction; external-id
/// upserts — feed-owned cells refresh, user cells never. Returns
/// created+updated, -1 on refusal/parse/persist failure.
///
/// Additive verb (boundary rule): with_box + Committed, tested, flagged.
///
/// # Safety
/// `path` and `json` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_import_messages_at(
    path: *const c_char,
    json: *const c_char,
) -> i64 {
    if json.is_null() {
        return -1;
    }
    let Ok(json) = CStr::from_ptr(json).to_str() else {
        return -1;
    };
    #[derive(serde::Deserialize)]
    struct DropJSON {
        external_id: String,
        from: String,
        source: String,
        #[serde(default)]
        sent: Option<String>,
        body: String,
    }
    let Ok(drops) = serde_json::from_str::<Vec<DropJSON>>(json) else {
        return -1;
    };
    let drops: Vec<liv_services::comms::MessageDrop> = drops
        .into_iter()
        .map(|d| liv_services::comms::MessageDrop {
            external_id: d.external_id,
            from: d.from,
            source: d.source,
            sent: d.sent,
            body: d.body,
        })
        .collect();
    with_box(path, -1, move |session| {
        use liv_services::content::WriteError;
        match liv_services::comms::import_messages(session, &drops) {
            Ok(outcome) => {
                let changed = outcome.created + outcome.updated;
                (
                    changed as i64,
                    if changed > 0 { Committed::Wrote } else { Committed::Read },
                )
            }
            Err(WriteError::Refused(_)) => (-1, Committed::Read),
            Err(_) => (-1, Committed::Failed),
        }
    })
}

/// Log ONE closed time interval (P18d): full civil stamps YYYYMMDDHHMM,
/// written whole at stop — the running timer is shell state and start
/// writes nothing. One commit, one undo. Returns the entry id, 0 on failure.
///
/// Additive verb (boundary rule): with_box + Committed, tested, flagged.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_log_time_at(
    path: *const c_char,
    target: u64,
    start_civil: i64,
    end_civil: i64,
) -> u64 {
    if start_civil <= 0 || end_civil <= 0 {
        return 0;
    }
    let to_dt = |civil: i64| {
        DateTime::at(
            (civil / 100_000_000) as i32,
            ((civil / 1_000_000) % 100) as u32,
            ((civil / 10_000) % 100) as u32,
            ((civil / 100) % 100) as u32,
            (civil % 100) as u32,
        )
    };
    with_box(path, 0, move |session| {
        let id = liv_services::content::log_time(session, target, to_dt(start_civil), to_dt(end_civil))
            .unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Save a view (P18d): the one filter engine's bookmark — a named query.
/// Returns the view id, 0 on failure. Additive verb, tested, flagged.
///
/// # Safety
/// `path`, `name`, and `query` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_create_view_at(
    path: *const c_char,
    name: *const c_char,
    query: *const c_char,
) -> u64 {
    if name.is_null() || query.is_null() {
        return 0;
    }
    let (Ok(name), Ok(query)) = (CStr::from_ptr(name).to_str(), CStr::from_ptr(query).to_str())
    else {
        return 0;
    };
    let name = name.trim();
    if name.is_empty() {
        return 0;
    }
    with_box(path, 0, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let id = liv_services::content::create_view(session, name, query.trim(), created)
            .unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Add a board widget (P18d): kind + workspace scope (0 = Home) + span
/// (columns; <= 0 for the default). One commit — on a fresh box the widget
/// types are born in the SAME transaction, so one undo removes everything.
/// Config edits ride liv_set_at; removal rides liv_trash_at. Returns
/// the widget id, 0 on failure. Additive verb, tested, flagged.
///
/// # Safety
/// `path` and `kind` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_widget_add_at(
    path: *const c_char,
    kind: *const c_char,
    workspace: u64,
    span: f64,
) -> u64 {
    if kind.is_null() {
        return 0;
    }
    let Ok(kind) = CStr::from_ptr(kind).to_str() else {
        return 0;
    };
    let kind = kind.trim();
    if kind.is_empty() {
        return 0;
    }
    with_box(path, 0, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let workspace = (workspace != 0).then_some(workspace);
        let span = (span > 0.0).then_some(span);
        let id = liv_services::content::add_widget(session, kind, workspace, span, created)
            .unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Save a layout layer (P17i): one transaction — name + workspace scope
/// (0 = Home) + the ordered member ids (`members_json` = `[u64,…]`, the
/// open tabs). Returns the layer id, 0 on failure. Restore has NO verb
/// (pure shell); rename/delete ride liv_set_at / liv_trash_at.
///
/// Additive verb (boundary rule): with_box + Committed, shipped with a
/// round-trip test, flagged in the PR.
///
/// # Safety
/// `path`, `name`, and `members_json` must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn liv_layer_save_at(
    path: *const c_char,
    name: *const c_char,
    workspace: u64,
    members_json: *const c_char,
) -> u64 {
    if name.is_null() || members_json.is_null() {
        return 0;
    }
    let Ok(name) = CStr::from_ptr(name).to_str() else {
        return 0;
    };
    let name = name.trim();
    if name.is_empty() {
        return 0;
    }
    let Ok(json) = CStr::from_ptr(members_json).to_str() else {
        return 0;
    };
    let Ok(members) = serde_json::from_str::<Vec<u64>>(json) else {
        return 0;
    };
    with_box(path, 0, move |session| {
        let now = Local::now();
        let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
        let workspace = (workspace != 0).then_some(workspace);
        let id =
            liv_services::content::create_layer(session, name, workspace, &members, created)
                .unwrap_or(0);
        (id, if id != 0 { Committed::Wrote } else { Committed::Failed })
    })
}

/// Trash one entity — the inspector's Trash action. Soft, reversible
/// (⌘⌥Z), never cascades. 1 on success, 0 on failure.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn liv_trash_at(path: *const c_char, id: u64) -> i32 {
    with_box(path, 0, |session| {
        let ok = liv_services::content::trash_workspace(session, id).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

/// Remove every cell of one property — the inverse of liv_set_at's
/// replace. A property the entity does not carry is success, not an
/// error. Returns 1 on success, 0 on busy/no entity/no property.
///
/// # Safety
/// `path` and `property` must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn liv_unset_at(
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
        let ok = liv_services::content::unset_property(session, id, property).is_ok();
        (ok as i32, if ok { Committed::Wrote } else { Committed::Failed })
    })
}

#[cfg(test)]
mod tests;
