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

use lotus_core::{props, Author, DateTime, Id, Session, Store, Value};
use lotus_services::{clerk, property_id, run, Constraint, Op, Query, Sort};

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
    property: String,
    value: String,
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
struct Snapshot {
    today: Vec<Id>,
    unstructured: Vec<Id>,
    everything: Vec<Id>,
    dated: Vec<Id>,
    /// Virtual: this month's expansion of every recurring series,
    /// computed in services — never stored, same answer for every view.
    occurrences: Vec<OccurrenceRow>,
    inbox: Vec<ProposalRow>,
    entities: Vec<EntityRow>,
}

/// Open the box, seed if fresh, and fill the queue with the clerk's sweep —
/// the same ritual every shell performs.
unsafe fn open_swept(path: *const c_char) -> Option<Session> {
    if path.is_null() {
        return None;
    }
    let path = CStr::from_ptr(path).to_str().ok()?;
    if let Some(dir) = std::path::Path::new(path).parent() {
        std::fs::create_dir_all(dir).ok()?;
    }
    let mut session = Session::open(path).ok()?;
    lotus_services::seed_if_fresh(&mut session).ok()?;
    let today = civil_today();
    for proposal in clerk::sweep(session.store(), today) {
        if session.propose(proposal).is_err() {
            return None;
        }
    }
    Some(session)
}

fn civil_today() -> DateTime {
    let now = Local::now();
    DateTime::date(now.year(), now.month(), now.day())
}

fn build_snapshot(store: &Store) -> Snapshot {
    let due_prop = property_id(store, "due");
    let status_prop = property_id(store, "status");

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

    // This month's window is the horizon the calendar asks for.
    let now = Local::now();
    let month_first = DateTime::date(now.year(), now.month(), 1);
    let month_last = DateTime::date(
        now.year(),
        now.month(),
        last_day_of_month(now.year(), now.month()),
    );
    let occurrences = lotus_services::recurrence::occurrences(store, month_first, month_last)
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
                content_print: lotus_services::content::content_fingerprint(
                    entity.get(props::CONTENT),
                ),
                cells: entity
                    .cells
                    .iter()
                    .map(|cell| CellRow {
                        property: reference_name(store, cell.property),
                        value: lotus_views::display(store, &cell.value),
                    })
                    .collect(),
            }
        })
        .collect();

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

    Snapshot { today, unstructured, everything, dated, occurrences, inbox, entities }
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
    let Some(session) = open_swept(path) else {
        return std::ptr::null_mut();
    };
    let snapshot = build_snapshot(session.store());
    drop(session); // release the box before handing the JSON over
    match serde_json::to_string(&snapshot).ok().and_then(|s| CString::new(s).ok()) {
        Some(s) => s.into_raw(),
        None => std::ptr::null_mut(),
    }
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
    let Some(mut session) = open_swept(path) else {
        return 0;
    };
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
        _ => return 0,
    };
    // A consent is to a proposal, not a position: if the queue shifted
    // since the snapshot, refuse — the shell refreshes and the user sees
    // the truth before clicking again.
    if fingerprint(&session.store().pending()[index]) != expected {
        return 0;
    }
    let outcome = if accept {
        session.accept(index).is_ok()
    } else {
        session.reject(index).is_ok()
    };
    outcome as i32
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
    let Some(mut session) = open_swept(path) else {
        return 0;
    };
    session.undo(Author::User).is_ok() as i32
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
    /// Identity of the stored content value; a save must present it back.
    fingerprint: u64,
    /// The log's own serde encoding of Span, verbatim.
    spans: Vec<lotus_core::Span>,
}

/// One entity's content, fresh from the box. Legacy plain-text content
/// reads as one Text span (the fingerprint still covers the stored
/// value). Redirects resolve before reading. Null when the box is
/// unavailable or the entity does not exist. Free with `lotus_string_free`.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_content_at(path: *const c_char, id: u64) -> *mut c_char {
    let Some(session) = open_swept(path) else {
        return std::ptr::null_mut();
    };
    let store = session.store();
    let id = store.resolve(id);
    let Some(entity) = store.get(id) else {
        return std::ptr::null_mut();
    };
    let doc = ContentDoc {
        id,
        name: match entity.get(props::NAME) {
            Some(Value::Text(name)) => Some(name.clone()),
            _ => None,
        },
        trashed: entity.trashed,
        fingerprint: lotus_services::content::content_fingerprint(entity.get(props::CONTENT)),
        spans: lotus_services::content::content_spans(entity),
    };
    drop(session);
    match serde_json::to_string(&doc).ok().and_then(|s| CString::new(s).ok()) {
        Some(s) => s.into_raw(),
        None => std::ptr::null_mut(),
    }
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
    let Some(mut session) = open_swept(path) else {
        return 0;
    };
    match lotus_services::content::set_content(&mut session, id, spans, base_fingerprint) {
        Ok(fresh) => {
            if !fresh_fingerprint.is_null() {
                *fresh_fingerprint = fresh;
            }
            1
        }
        Err(lotus_services::content::ContentError::Stale) => -1,
        Err(_) => 0,
    }
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
    let Some(mut session) = open_swept(path) else {
        return 0;
    };
    lotus_services::content::set_property(&mut session, id, property, value).is_ok() as i32
}

/// Birth of a note: Create + type + created, one transaction. Returns
/// the id, 0 on failure. The caller drops straight into renaming.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_create_note_at(path: *const c_char) -> u64 {
    let Some(mut session) = open_swept(path) else {
        return 0;
    };
    let now = Local::now();
    let created = DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute());
    lotus_services::content::create_note(&mut session, created).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
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
        let path = std::env::temp_dir().join(name);
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{}.declined", path.display()));
        let _ = std::fs::remove_file(format!("{}.pending", path.display()));
        let c_path = CString::new(path.to_str().unwrap()).unwrap();
        (path, c_path)
    }

    fn cleanup(path: &std::path::Path) {
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}.declined", path.display()));
        let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    }

    unsafe fn read_json(raw: *mut c_char) -> serde_json::Value {
        assert!(!raw.is_null());
        let json = CStr::from_ptr(raw).to_str().unwrap().to_string();
        lotus_string_free(raw);
        serde_json::from_str(&json).unwrap()
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

        // The stale base now refuses — and the log did not move.
        let session = Session::open(&path).unwrap();
        let history_len = session.store().history().len();
        drop(session);
        let stale = unsafe {
            lotus_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), base, &mut fresh)
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

        // No such entity: null.
        assert!(unsafe { lotus_content_at(c_path.as_ptr(), 999_999) }.is_null());

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
}
