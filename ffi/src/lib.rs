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
    let bytes = serde_json::to_vec(&proposal.commands).unwrap_or_default();
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
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
}
