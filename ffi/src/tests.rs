//! The C ABI's own tests — every verb exercised through the same
//! boundary the shells use. Split out of lib.rs (T6, owner 2026-08-09):
//! the one file had reached 5,785 lines, and 2,700 of them were this
//! module. `use super::*` keeps the seam identical.

use super::*;
use liv_core::{Cell, Command};
use std::ffi::CString;

#[test]
fn the_seam_roundtrips() {
    let path = std::env::temp_dir().join("liv_ffi_roundtrip.log");
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let c_path = CString::new(path.to_str().unwrap()).unwrap();

    let text = CString::new("Call Anna Friday").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    assert_ne!(id, 0);

    // Whitespace is not a thought.
    let blank = CString::new("   ").unwrap();
    assert_eq!(unsafe { liv_capture_at(c_path.as_ptr(), blank.as_ptr()) }, 0);

    // The session closed behind the capture: the box is free again,
    // and what the shell wrote, the rest of the system reads.
    let session = Session::open(&path).unwrap();
    let entity = session.store().get(id).unwrap();
    assert!(entity.get(liv_core::props::CONTENT).is_some());
    assert!(entity.get(liv_core::props::CREATED).is_some());
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn snapshot_and_triage_roundtrip() {
    let path = std::env::temp_dir().join("liv_ffi_snapshot.log");
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let c_path = CString::new(path.to_str().unwrap()).unwrap();

    let text = CString::new("kickoff friday").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    assert_ne!(id, 0);

    // The snapshot shows the scrap unstructured and the clerk's proposal.
    let raw = unsafe { liv_snapshot(c_path.as_ptr()) };
    assert!(!raw.is_null());
    let json = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_string();
    unsafe { liv_string_free(raw) };
    let snap: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(snap["unstructured"][0], id);
    assert_eq!(snap["inbox"][0]["entity"], id);
    assert_eq!(snap["inbox"][0]["author"], "dates");
    let print = snap["inbox"][0]["fingerprint"].as_u64().unwrap();

    // A stale or wrong fingerprint is refused: consent is to a
    // proposal, never to a position.
    assert_eq!(unsafe { liv_accept_at(c_path.as_ptr(), id, 1, print ^ 1) }, 0);

    // Accepting through the seam lands the due cell...
    assert_eq!(unsafe { liv_accept_at(c_path.as_ptr(), id, 1, print) }, 1);
    let raw = unsafe { liv_snapshot(c_path.as_ptr()) };
    let json = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_string();
    unsafe { liv_string_free(raw) };
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
    let dir = std::env::temp_dir().join(format!("liv_box_{name}"));
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
    liv_string_free(raw);
    serde_json::from_str(&json).unwrap()
}

// ---- the store cache (design/perf-incremental-open.md, slice B) ----

#[test]
fn a_cache_hit_matches_a_full_open() {
    let (path, c_path) = fresh_box("liv_ffi_cache_equiv.log");
    unsafe { liv_capture_at(c_path.as_ptr(), CString::new("kickoff friday").unwrap().as_ptr()) };

    // First snapshot: a full open (miss) that populates the cache.
    let first = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    // Second snapshot: served from the cache (a hit) — the SAME answer.
    let hit = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(first, hit, "a cache hit must not change the answer");
    // Clear the cache: a forced full replay agrees too — the cache never
    // diverges from the log's own consequence.
    clear_cache_for_tests();
    let full = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(first, full, "the cache never diverges from a full replay");
    cleanup(&path);
}

#[test]
fn an_external_append_is_picked_up() {
    let (path, c_path) = fresh_box("liv_ffi_external.log");
    // Seed + cache via an FFI snapshot.
    unsafe { read_json(liv_snapshot(c_path.as_ptr())) };

    // A second writer (the CLI stand-in) appends a note directly, then drops
    // — releasing the lock. The FFI cache still holds the pre-append store.
    let external_id = {
        let mut session = Session::open(&path).unwrap();
        liv_services::content::create_note(&mut session, DateTime::at(2026, 7, 8, 9, 0)).unwrap()
    };
    // The next FFI snapshot must SEE the external note — the grown log length
    // forces a full re-open, not a stale cache hit.
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let seen = snap["entities"].as_array().unwrap().iter().any(|e| e["id"] == external_id);
    assert!(seen, "an external append must invalidate the cache");
    cleanup(&path);
}

#[test]
fn two_creates_do_not_reuse_an_id() {
    let (path, c_path) = fresh_box("liv_ffi_ids.log");
    // The second create is a cache HIT (the first's commit grew the log, and
    // check-in cached that length); next_id must ride the cached store.
    let a = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let b = unsafe { liv_create_note_at(c_path.as_ptr()) };
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
    let (path, c_path) = fresh_box("liv_ffi_locked.log");
    // Warm the cache.
    unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    // Hold the box open elsewhere (grabs the exclusive lock).
    let guard = Session::open(&path).unwrap();
    // Even with a warm cache, a snapshot must refuse (null), never serve a
    // stale cached answer while another writer holds the box (Guard 5).
    let raw = unsafe { liv_snapshot(c_path.as_ptr()) };
    assert!(raw.is_null(), "a locked box yields null, never a cached snapshot");
    drop(guard);
    // Lock released: the next snapshot succeeds again.
    let raw = unsafe { liv_snapshot(c_path.as_ptr()) };
    assert!(!raw.is_null());
    unsafe { liv_string_free(raw) };
    cleanup(&path);
}

#[test]
fn a_sidecar_change_without_a_log_change_invalidates() {
    let (path, c_path) = fresh_box("liv_ffi_sidecar.log");
    unsafe { liv_capture_at(c_path.as_ptr(), CString::new("kickoff friday").unwrap().as_ptr()) };
    // Snapshot proposes friday and caches (inbox has one).
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(snap["inbox"].as_array().unwrap().len(), 1);

    // Externally decline it: rewrites .declined + .pending WITHOUT touching
    // the main log (its length is unchanged).
    {
        let mut session = Session::open(&path).unwrap();
        session.reject(0).unwrap();
    }
    // The next FFI snapshot must reflect the decline — the sidecar length
    // changed even though the log length did not (Guard 2).
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
    liv_services::seed_if_fresh(&mut session).unwrap();
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
    // liv_snapshot byte-identical — it is exactly the current civil
    // month's window.
    let (path, c_path) = fresh_box("liv_ffi_win_default.log");
    unsafe { liv_capture_at(c_path.as_ptr(), CString::new("hello").unwrap().as_ptr()) };
    let full = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let now = Local::now();
    let from = DateTime::date(now.year(), now.month(), 1).civil;
    let to = DateTime::date(
        now.year(),
        now.month(),
        last_day_of_month(now.year(), now.month()),
    )
    .civil;
    let windowed = unsafe { read_json(liv_snapshot_window_at(c_path.as_ptr(), from, to)) };
    assert_eq!(full, windowed, "the default snapshot IS the current-month window");
    cleanup(&path);
}

#[test]
fn a_future_window_steers_the_occurrence_engine() {
    let (path, c_path) = fresh_box("liv_ffi_win_future.log");
    // A weekly series anchored 2026-07-07 (a Tuesday); the window decides
    // which of its Tuesdays the snapshot expands.
    seed_series(&path, DateTime::date(2026, 7, 7), "every week");
    let snap = unsafe {
        read_json(liv_snapshot_window_at(
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
    let (path, c_path) = fresh_box("liv_ffi_win_straddle.log");
    seed_series(&path, DateTime::date(2026, 7, 7), "every week");
    let snap = unsafe {
        read_json(liv_snapshot_window_at(
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
    let (path, c_path) = fresh_box("liv_ffi_win_cap.log");
    seed_series(&path, DateTime::date(2026, 1, 1), "every day");
    // Ask for three years; the engine caps at 366 days from `from`.
    let snap = unsafe {
        read_json(liv_snapshot_window_at(
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
    let (path, c_path) = fresh_box("liv_ffi_event.log");
    let due_civil = DateTime::at(2026, 7, 9, 9, 0).civil;
    let id = unsafe { liv_create_event_at(c_path.as_ptr(), due_civil, 0) };
    assert_ne!(id, 0);
    let snap = unsafe {
        read_json(liv_snapshot_window_at(
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

#[test]
fn a_cell_ref_target_resolves_through_redirects() {
    // The read-time-resolution law at the wire (the P11.5 review's
    // finding): after a merge, a cell still storing the LOSER id must
    // serialize its ref_target as the SURVIVOR — the shell's backlink
    // index and pickers key on it.
    let (path, c_path) = fresh_box("liv_ffi_redirect.log");
    let (survivor, loser, event) = {
        let mut session = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut session).unwrap();
        let survivor =
            liv_services::content::create_note(&mut session, DateTime::date(2026, 7, 10))
                .unwrap();
        let loser =
            liv_services::content::create_note(&mut session, DateTime::date(2026, 7, 10))
                .unwrap();
        let event = liv_services::content::create_event(
            &mut session,
            DateTime::date(2026, 7, 12),
            DateTime::date(2026, 7, 10),
        )
        .unwrap();
        liv_services::content::set_property(
            &mut session,
            event,
            "attendees",
            &format!("#{loser}"),
        )
        .unwrap();
        session.merge(survivor, loser, Vec::new(), Author::User).unwrap();
        (survivor, loser, event)
    };
    let _ = loser;
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let cell = snap["entities"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["id"] == event)
        .unwrap()["cells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["property"] == "attendees")
        .unwrap()
        .clone();
    assert_eq!(
        cell["ref_target"].as_u64(),
        Some(survivor),
        "the wire resolves the redirect"
    );
    cleanup(&path);
}

#[test]
fn add_property_births_one_definition_vault_wide() {
    // Entry 670's promise ("exists vault-wide the moment one object
    // uses it") is NOT what the core does — set on an unknown name
    // refuses (content.rs: "no property named ..."). This test ran
    // FIRST (the design's contingent-exception clause): the seam
    // births the definition; everything after is the ordinary set.
    let (path, c_path) = fresh_box("liv_ffi_add_property.log");
    let note = {
        let mut session = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut session).unwrap();
        liv_services::content::create_note(&mut session, DateTime::date(2026, 7, 10))
            .unwrap()
    };
    let c_grade = CString::new("grade").unwrap();
    let c_number = CString::new("number").unwrap();
    let c_value = CString::new("12").unwrap();
    // The refusal the seam compensates for, pinned:
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), note, c_grade.as_ptr(), c_value.as_ptr()) },
        0,
        "set on an unknown property name refuses"
    );
    // Birth: one definition, vault-wide; the id comes back for the
    // shell to reveal the row.
    let born = unsafe {
        liv_add_property_at(c_path.as_ptr(), c_grade.as_ptr(), c_number.as_ptr())
    };
    assert_ne!(born, 0);
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), note, c_grade.as_ptr(), c_value.as_ptr()) },
        1,
        "the born property accepts its first value"
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let prop = snap["properties"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["name"] == "grade")
        .expect("the catalog carries the born definition");
    assert_eq!(prop["kind"], "number");
    assert_eq!(prop["id"].as_u64(), Some(born));
    let cell_value = snap["entities"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["id"] == note)
        .unwrap()["cells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["property"] == "grade")
        .expect("the first value landed")["value"]
        .as_str()
        .unwrap()
        .to_string();
    assert!(cell_value.starts_with("12"), "got {cell_value}");
    // One name, one definition — a re-add refuses, other kind or not.
    let c_text = CString::new("text").unwrap();
    assert_eq!(
        unsafe { liv_add_property_at(c_path.as_ptr(), c_grade.as_ptr(), c_text.as_ptr()) },
        0
    );
    // Garbage refused: empty name, unknown kind, an existing/reserved name.
    let c_empty = CString::new("  ").unwrap();
    let c_widget = CString::new("widget").unwrap();
    let c_name = CString::new("name").unwrap();
    assert_eq!(
        unsafe { liv_add_property_at(c_path.as_ptr(), c_empty.as_ptr(), c_text.as_ptr()) },
        0
    );
    assert_eq!(
        unsafe { liv_add_property_at(c_path.as_ptr(), c_grade.as_ptr(), c_widget.as_ptr()) },
        0
    );
    assert_eq!(
        unsafe { liv_add_property_at(c_path.as_ptr(), c_name.as_ptr(), c_text.as_ptr()) },
        0
    );
    cleanup(&path);
}

#[test]
fn open_daily_note_is_get_or_create_per_date_and_workspace() {
    // P12 12a (failing-test-first, memory: test-drive-core-changes): the
    // one new P12 seam. It must be idempotent per (date, workspace) — the
    // find and the conditional create run in ONE session so two entry
    // points can never double-create — and per-workspace (D3): the same
    // date in two workspaces is two notes.
    let (path, c_path) = fresh_box("liv_ffi_daily.log");
    // Two stand-in workspace targets (any entity id serves as a reference).
    let (ws_a, ws_b) = {
        let mut session = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut session).unwrap();
        let a = liv_services::content::create_note(&mut session, DateTime::date(2026, 7, 1))
            .unwrap();
        let b = liv_services::content::create_note(&mut session, DateTime::date(2026, 7, 1))
            .unwrap();
        (a, b)
    };
    let jul11 = DateTime::date(2026, 7, 11).civil;
    let jul12 = DateTime::date(2026, 7, 12).civil;

    // Idempotent: twice on one (date, workspace) is ONE note.
    let first = unsafe { liv_open_daily_note_at(c_path.as_ptr(), jul11, ws_a) };
    assert_ne!(first, 0);
    let again = unsafe { liv_open_daily_note_at(c_path.as_ptr(), jul11, ws_a) };
    assert_eq!(first, again, "the same day+workspace resolves to one note");

    // A different date is a different note.
    let other_day = unsafe { liv_open_daily_note_at(c_path.as_ptr(), jul12, ws_a) };
    assert_ne!(other_day, first);

    // Per-workspace (D3): the same date in another workspace is another note.
    let other_ws = unsafe { liv_open_daily_note_at(c_path.as_ptr(), jul11, ws_b) };
    assert_ne!(other_ws, first, "each workspace has its own today");

    // Time in the civil is normalized away — an afternoon call finds the
    // morning's note.
    let afternoon = DateTime::at(2026, 7, 11, 15, 30).civil;
    let same = unsafe { liv_open_daily_note_at(c_path.as_ptr(), afternoon, ws_a) };
    assert_eq!(same, first, "the seam keys on the day, not the minute");

    // The global (workspace 0 = None) bucket is SELF-CONSISTENT and
    // ISOLATED from workspace buckets (the review's high): two None opens
    // on one day are one note, and that note is neither `first` nor
    // `other_ws` (which are workspace-scoped).
    let global1 = unsafe { liv_open_daily_note_at(c_path.as_ptr(), jul11, 0) };
    let global2 = unsafe { liv_open_daily_note_at(c_path.as_ptr(), jul11, 0) };
    assert_ne!(global1, 0);
    assert_eq!(global1, global2, "None is self-consistent, not double-created");
    assert_ne!(global1, first, "None never adopts a workspace-scoped note");
    assert_ne!(global1, other_ws, "None never adopts a workspace-scoped note");

    // Exactly two daily notes on Jul 11 (one per workspace), one on Jul 12.
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let entities = snap["entities"].as_array().unwrap();
    let dailies: Vec<_> = entities
        .iter()
        .filter(|e| {
            e["kinds"]
                .as_array()
                .map(|ks| ks.iter().any(|k| k == "daily-note"))
                .unwrap_or(false)
        })
        .collect();
    assert_eq!(dailies.len(), 4, "ws_a/ws_b/global on Jul 11 + ws_a on Jul 12");

    // The born note carries type + date + workspace + a non-empty template body.
    let born = entities.iter().find(|e| e["id"] == first).unwrap();
    let cells = born["cells"].as_array().unwrap();
    assert!(cells.iter().any(|c| c["property"] == "date"), "has a date cell");
    assert!(
        cells.iter().any(|c| c["property"] == "workspace"
            && c["ref_target"].as_u64() == Some(ws_a)),
        "carries the workspace reference"
    );
    assert_ne!(
        born["content_print"].as_u64(),
        Some(0),
        "born with the default template body"
    );
    assert_eq!(born["title"], "2026-07-11", "named the ISO date");
    cleanup(&path);
}

#[test]
fn set_type_stamps_a_named_type_onto_an_orphan_scrap() {
    // P12 12d (failing-test-first): the Inbox Route commit stamps a
    // TYPE cell by NAME so a bare capture leaves the content∧¬type
    // orphan set. set_property can't (reference needs #id) and types are
    // working plumbing off the snapshot, so this is the seam that closes
    // the gap (the design's "stamp type" assumption verified false).
    let (path, c_path) = fresh_box("liv_ffi_set_type.log");
    let scrap = unsafe {
        let c_text = CString::new("Steven owes me 300 kr").unwrap();
        liv_capture_at(c_path.as_ptr(), c_text.as_ptr())
    };
    assert_ne!(scrap, 0);

    // Before: the scrap is a content-only orphan (no kinds).
    let before = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let scrap_before = before["entities"].as_array().unwrap()
        .iter().find(|e| e["id"] == scrap).unwrap();
    assert!(scrap_before["kinds"].as_array().unwrap().is_empty(), "starts typeless");
    assert_ne!(scrap_before["content_print"].as_u64(), Some(0), "has content");

    // Stamp type = note.
    let c_note = CString::new("note").unwrap();
    assert_eq!(unsafe { liv_set_type_at(c_path.as_ptr(), scrap, c_note.as_ptr()) }, 1);

    // After: it is a note; it left the orphan set.
    let after = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let scrap_after = after["entities"].as_array().unwrap()
        .iter().find(|e| e["id"] == scrap).unwrap();
    assert!(
        scrap_after["kinds"].as_array().unwrap().iter().any(|k| k == "note"),
        "now typed as note"
    );

    // Re-stamping a different type REPLACES (one type, not two).
    let c_task = CString::new("task").unwrap();
    assert_eq!(unsafe { liv_set_type_at(c_path.as_ptr(), scrap, c_task.as_ptr()) }, 1);
    let retyped = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let kinds = retyped["entities"].as_array().unwrap()
        .iter().find(|e| e["id"] == scrap).unwrap()["kinds"].as_array().unwrap().clone();
    assert_eq!(kinds.len(), 1, "one type, replaced not appended");
    assert!(kinds.iter().any(|k| k == "task"));

    // An unknown type name is refused; nothing changes.
    let c_bogus = CString::new("nonesuch").unwrap();
    assert_eq!(unsafe { liv_set_type_at(c_path.as_ptr(), scrap, c_bogus.as_ptr()) }, 0);
    cleanup(&path);
}

#[test]
fn contact_profile_fields_are_seeded_additively() {
    // P14-CT (failing-test-first): a fresh box seeds the contact profile
    // fields role/org/email/phone (all text), and an older box gains them
    // on open — the seed_event_fields additive pattern.
    let (path, c_path) = fresh_box("liv_ffi_contacts.log");
    {
        let mut session = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut session).unwrap();
    }
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let props: std::collections::HashMap<String, String> = snap["properties"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| {
            (
                p["name"].as_str().unwrap().to_string(),
                p["kind"].as_str().unwrap_or("").to_string(),
            )
        })
        .collect();
    for field in ["role", "org", "email", "phone"] {
        assert_eq!(
            props.get(field).map(String::as_str),
            Some("text"),
            "contact field {field} seeded as text"
        );
    }
    cleanup(&path);
}

// ---- the snapshot re-base (P11/11f — the phase's visible effect) ----

/// A recurring series anchored on an arbitrary date property, written
/// directly as the CLI would.
fn seed_series_on(path: &std::path::Path, prop: &str, anchor: DateTime, rule: &str) {
    let mut session = Session::open(path).unwrap();
    liv_services::seed_if_fresh(&mut session).unwrap();
    let id = session.allocate_id();
    let anchor_prop = property_id(session.store(), prop).unwrap();
    let recur = property_id(session.store(), "recurrence").unwrap();
    session
        .commit(
            vec![
                Command::Create { entity: id },
                Command::AddCell {
                    entity: id,
                    cell: Cell { property: anchor_prop, value: Value::DateTime(anchor) },
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
fn a_due_only_box_positions_by_due() {
    // The compat pin: on a box with no calendar-role cells, every dated
    // row positions by `due` with no span end — the shipped world,
    // byte-identical modulo the additive fields.
    let (path, c_path) = fresh_box("liv_ffi_rebase_compat.log");
    let id = unsafe {
        liv_create_event_at(c_path.as_ptr(), DateTime::at(2026, 7, 11, 9, 0).civil, 0)
    };
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let row = snap["entities"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["id"] == id)
        .unwrap();
    assert_eq!(row["positioned_by"], "due");
    assert!(row.get("due_end").is_none(), "a plain date carries no end");
    assert!(snap["dated"].as_array().unwrap().iter().any(|d| d.as_u64() == Some(id)));
    cleanup(&path);
}

#[test]
fn a_calendar_role_date_enters_dated_and_fills_due() {
    // The re-base itself: an entity carrying only a calendar-role `date`
    // fills the very field the shipped CalendarView already buckets by.
    let (path, c_path) = fresh_box("liv_ffi_rebase_date.log");
    let id = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let date = CString::new("date").unwrap();
    let when = CString::new("2026-07-12").unwrap();
    assert_eq!(unsafe { liv_set_at(c_path.as_ptr(), id, date.as_ptr(), when.as_ptr()) }, 1);

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let row = snap["entities"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["id"] == id)
        .unwrap();
    assert_eq!(row["due"].as_i64(), Some(DateTime::date(2026, 7, 12).civil));
    assert_eq!(row["due_date_only"], true);
    assert_eq!(row["positioned_by"], "date");
    assert!(snap["dated"].as_array().unwrap().iter().any(|d| d.as_u64() == Some(id)));
    cleanup(&path);
}

#[test]
fn an_entity_with_both_date_and_due_positions_once_by_set_precedence() {
    // ONE order rules both the recurrence anchor and the rendered row
    // (design §2.2: date before due) — and the union never doubles a row.
    let (path, c_path) = fresh_box("liv_ffi_rebase_both.log");
    let id = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let due = CString::new("due").unwrap();
    let date = CString::new("date").unwrap();
    let friday = CString::new("2026-07-10").unwrap();
    let tuesday = CString::new("2026-07-07").unwrap();
    unsafe {
        assert_eq!(liv_set_at(c_path.as_ptr(), id, due.as_ptr(), friday.as_ptr()), 1);
        assert_eq!(liv_set_at(c_path.as_ptr(), id, date.as_ptr(), tuesday.as_ptr()), 1);
    }
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let appearances = snap["dated"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|d| d.as_u64() == Some(id))
        .count();
    assert_eq!(appearances, 1, "the union dedupes");
    let row = snap["entities"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["id"] == id)
        .unwrap();
    assert_eq!(row["positioned_by"], "date", "the set precedence");
    assert_eq!(row["due"].as_i64(), Some(DateTime::date(2026, 7, 7).civil));
    cleanup(&path);
}

#[test]
fn a_span_fills_due_end_and_a_plain_date_leaves_it_absent() {
    let (path, c_path) = fresh_box("liv_ffi_rebase_span.log");
    let spanned = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let plain = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let due = CString::new("due").unwrap();
    let start = DateTime::date(2026, 7, 11).civil;
    let end = DateTime::date(2026, 7, 13).civil;
    unsafe {
        assert_eq!(liv_set_span_at(c_path.as_ptr(), spanned, due.as_ptr(), start, end, 1), 1);
        assert_eq!(liv_set_span_at(c_path.as_ptr(), plain, due.as_ptr(), start, 0, 1), 1);
    }
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let rows = snap["entities"].as_array().unwrap();
    let spanned_row = rows.iter().find(|e| e["id"] == spanned).unwrap();
    let plain_row = rows.iter().find(|e| e["id"] == plain).unwrap();
    assert_eq!(spanned_row["due_end"].as_i64(), Some(end), "the span bar's feed");
    assert!(plain_row.get("due_end").is_none());
    cleanup(&path);
}

#[test]
fn a_date_anchored_series_reaches_the_windowed_snapshot() {
    // P10's window-steer test, re-run for the generalized anchor: a
    // weekly series on `date` (not due) fills a FUTURE month's window.
    let (path, c_path) = fresh_box("liv_ffi_rebase_series.log");
    seed_series_on(&path, "date", DateTime::date(2026, 7, 7), "every week");
    let snap = unsafe {
        read_json(liv_snapshot_window_at(
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
    assert_eq!(civils, vec![20260804, 20260811, 20260818, 20260825], "August's Tuesdays");
    cleanup(&path);
}

#[test]
fn an_external_append_of_a_dated_entity_is_seen_by_the_union() {
    // The cache battery's representative: an external writer adds a
    // date-role entity; the grown log forces a full re-open and the NEW
    // union path serves it — never a stale dated list.
    let (path, c_path) = fresh_box("liv_ffi_rebase_external.log");
    unsafe { liv_string_free(liv_snapshot(c_path.as_ptr())) }; // warm
    let external = {
        let mut session = Session::open(&path).unwrap();
        let id = liv_services::content::create_note(&mut session, DateTime::date(2026, 7, 10))
            .unwrap();
        liv_services::content::set_property(&mut session, id, "date", "2026-07-12").unwrap();
        id
    };
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(
        snap["dated"].as_array().unwrap().iter().any(|d| d.as_u64() == Some(external)),
        "the external date-role entity is positioned"
    );
    cleanup(&path);
}

// ---- display attributes + the value pool (P11/11e) ----

#[test]
fn distinct_values_is_a_read() {
    let (path, c_path) = fresh_box("liv_ffi_distinct.log");
    let a = unsafe { liv_create_task_at(c_path.as_ptr()) };
    let _b = unsafe { liv_create_task_at(c_path.as_ptr()) };
    let _c = unsafe { liv_create_task_at(c_path.as_ptr()) };
    let status = CString::new("status").unwrap();
    let done = CString::new("done").unwrap();
    assert_eq!(unsafe { liv_set_at(c_path.as_ptr(), a, status.as_ptr(), done.as_ptr()) }, 1);
    let before = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };

    let raw = unsafe { liv_distinct_values_at(c_path.as_ptr(), status.as_ptr()) };
    assert!(!raw.is_null());
    let pool: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    let rows = pool.as_array().unwrap();
    assert_eq!(rows.len(), 2, "todo and done");
    assert_eq!(rows[0]["value"], "todo", "count desc: two todos outrank one done");
    assert_eq!(rows[0]["count"], 2);
    assert_eq!(rows[1]["value"], "done");

    let after = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(before, after, "a read leaves the cached snapshot verbatim");
    cleanup(&path);
}

#[test]
fn the_catalog_carries_usage_and_attributes() {
    let (path, c_path) = fresh_box("liv_ffi_attrs.log");
    let a = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let due = CString::new("due").unwrap();
    let when = CString::new("2026-07-11").unwrap();
    assert_eq!(unsafe { liv_set_at(c_path.as_ptr(), a, due.as_ptr(), when.as_ptr()) }, 1);

    // Set an icon ON the due definition through the ordinary seam.
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let due_row = snap["properties"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["name"] == "due")
        .unwrap();
    let due_id = due_row["id"].as_u64().unwrap();
    assert_eq!(due_row["usage"].as_u64(), Some(1), "one live carrier");
    assert!(due_row.get("icon").is_none(), "unset attributes stay absent");

    let icon = CString::new("icon").unwrap();
    let glyph = CString::new("i-flag").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), due_id, icon.as_ptr(), glyph.as_ptr()) },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let due_row = snap["properties"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["name"] == "due")
        .unwrap();
    assert_eq!(due_row["icon"], "i-flag", "the attribute rides the catalog");
    cleanup(&path);
}

// ---- universal status through the seam (P11/11d) ----

#[test]
fn the_option_offer_seam_is_a_read() {
    let (path, c_path) = fresh_box("liv_ffi_offer.log");
    let before = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };

    let task = CString::new("task").unwrap();
    let raw = unsafe { liv_status_options_at(c_path.as_ptr(), task.as_ptr()) };
    assert!(!raw.is_null());
    let offer: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    let names: Vec<&str> =
        offer.as_array().unwrap().iter().map(|o| o["name"].as_str().unwrap()).collect();
    assert_eq!(names, vec!["todo", "doing", "done"], "board order");
    assert_eq!(offer[2]["completes"], true, "done completes");

    // A read leaves the cached snapshot verbatim.
    let after = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(before, after);
    cleanup(&path);
}

#[test]
fn add_status_option_is_tagged_wrote() {
    let (path, c_path) = fresh_box("liv_ffi_addopt.log");
    unsafe { liv_string_free(liv_snapshot(c_path.as_ptr())) }; // warm
    let project = CString::new("project").unwrap();
    let name = CString::new("active").unwrap();
    let id = unsafe {
        liv_add_status_option_at(c_path.as_ptr(), project.as_ptr(), name.as_ptr(), -1.0)
    };
    assert_ne!(id, 0);

    // The Wrote contract: the very next offer (a cache hit) carries it…
    let raw = unsafe { liv_status_options_at(c_path.as_ptr(), project.as_ptr()) };
    let offer: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert!(offer.as_array().unwrap().iter().any(|o| o["name"] == "active"));

    // …and the task offer is untouched (per-kind scoping).
    let task = CString::new("task").unwrap();
    let raw = unsafe { liv_status_options_at(c_path.as_ptr(), task.as_ptr()) };
    let task_offer: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert_eq!(task_offer.as_array().unwrap().len(), 3);
    cleanup(&path);
}

#[test]
fn assist_off_silences_the_persisted_queue_and_prop_follows_a_rename() {
    // P19 review: (1) the .pending sidecar outlives the sweep — the
    // snapshot's inbox must go quiet the moment the switch is off;
    // (2) assist.prop carries the switch property's CURRENT name so the
    // toggle keeps a write target after an ordinary definition rename.
    let (path, c_path) = fresh_box("liv_ffi_assist_gate");
    let text = CString::new("kickoff friday").unwrap();
    assert_ne!(unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) }, 0);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(
        !snap["inbox"].as_array().unwrap().is_empty(),
        "the frozen-string-shaped capture should propose"
    );
    let assist = snap["assist"]["id"].as_u64().unwrap();
    assert_eq!(snap["assist"]["prop"], "automation");

    // OFF: the queue reads empty even though .pending persists.
    let prop = CString::new("automation").unwrap();
    let off = CString::new("false").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), assist, prop.as_ptr(), off.as_ptr()) },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(snap["inbox"].as_array().unwrap().is_empty(), "off means SILENCE");
    assert_eq!(snap["assist"]["on"], false);

    // Rename the automation DEFINITION through the ordinary door: the
    // gate holds and the row advertises the new write target.
    let def = snap["properties"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["name"] == "automation")
        .and_then(|p| p["id"].as_u64())
        .expect("the automation definition rides the catalog");
    let name_prop = CString::new("name").unwrap();
    let new_name = CString::new("autopilot").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), def, name_prop.as_ptr(), new_name.as_ptr()) },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(snap["inbox"].as_array().unwrap().is_empty(), "the rename must not re-enable");
    assert_eq!(snap["assist"]["on"], false);
    assert_eq!(snap["assist"]["prop"], "autopilot");
    cleanup(&path);
}

fn fresh_vault(name: &str) -> (std::path::PathBuf, std::path::PathBuf, CString) {
    // A VAULT-shaped box: <root>/.liv/box/box.log (design §6).
    let root = std::env::temp_dir().join(format!("liv_vault_{name}"));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join(".liv/box")).unwrap();
    let path = root.join(".liv/box/box.log");
    let c_path = CString::new(path.to_str().unwrap()).unwrap();
    (root, path, c_path)
}

#[test]
fn every_wrote_commit_materializes_in_a_vault_box() {
    let (root, _path, c_path) = fresh_vault("continuous");
    let text = CString::new("projected thought").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    assert_ne!(id, 0);
    // Route it so it projects (scraps are box-only until typed).
    let note = CString::new("note").unwrap();
    assert_eq!(unsafe { liv_set_type_at(c_path.as_ptr(), id, note.as_ptr()) }, 1);
    let name_prop = CString::new("name").unwrap();
    let name = CString::new("Projected thought").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), id, name_prop.as_ptr(), name.as_ptr()) },
        1
    );
    assert!(
        root.join("library/notes/projected-thought.md").exists(),
        "the commit hook materialized the file"
    );
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn vault_sync_ingests_an_external_edit_once() {
    let (root, _path, c_path) = fresh_vault("sync");
    let text = CString::new("sync target").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    let note = CString::new("note").unwrap();
    unsafe { liv_set_type_at(c_path.as_ptr(), id, note.as_ptr()) };
    let name_prop = CString::new("name").unwrap();
    let name = CString::new("Sync target").unwrap();
    unsafe { liv_set_at(c_path.as_ptr(), id, name_prop.as_ptr(), name.as_ptr()) };
    let file = root.join("library/notes/sync-target.md");
    assert!(file.exists());

    // The user edits the file outside Liv.
    let mut bytes = std::fs::read(&file).unwrap();
    bytes.extend_from_slice(b"an outside line");
    std::fs::write(&file, bytes).unwrap();

    let raw = unsafe { liv_vault_sync_at(c_path.as_ptr()) };
    let sync: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert_eq!(sync["edited"], 1, "{sync}");

    // Echo-proof: a second sync is silent.
    let raw = unsafe { liv_vault_sync_at(c_path.as_ptr()) };
    let again: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert_eq!(again["edited"], 0, "{again}");
    assert_eq!(again["created"], 0);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn vault_findings_and_resolve_settle_a_conflict() {
    let (root, _path, c_path) = fresh_vault("diverge");
    let id = unsafe {
        liv_capture_at(c_path.as_ptr(), CString::new("target").unwrap().as_ptr())
    };
    let note = CString::new("note").unwrap();
    unsafe { liv_set_type_at(c_path.as_ptr(), id, note.as_ptr()) };
    let name_prop = CString::new("name").unwrap();
    let name = CString::new("Contested").unwrap();
    unsafe { liv_set_at(c_path.as_ptr(), id, name_prop.as_ptr(), name.as_ptr()) };
    let file = root.join("library/notes/contested.md");
    assert!(file.exists());

    // A GENUINE conflict = the box moved since the manifest's sync
    // point AND the disk moved too. The continuous hook keeps the
    // manifest current, so we simulate an OFFLINE box change by staling
    // the manifest's stored digest (as if a CLI committed while this
    // reader was down), then move the disk independently.
    let manifest_path = root.join(".liv/index.json");
    let mut manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&manifest_path).unwrap()).unwrap();
    for row in manifest["rows"].as_array_mut().unwrap() {
        if row["id"].as_u64() == Some(id) {
            row["digest"] = serde_json::json!("staleaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        }
    }
    std::fs::write(&manifest_path, serde_json::to_vec(&manifest).unwrap()).unwrap();
    std::fs::write(&file, b"# Contested\n\ndisk moved independently\n").unwrap();

    let raw = unsafe { liv_vault_findings_at(c_path.as_ptr(), 0) };
    let findings: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert_eq!(findings[0]["kind"], "conflict", "{findings}");

    // Resolve: take the disk version.
    let rel = CString::new("library/notes/contested.md").unwrap();
    let verdict = CString::new("take-disk").unwrap();
    assert_eq!(
        unsafe { liv_vault_resolve_at(c_path.as_ptr(), id, rel.as_ptr(), verdict.as_ptr()) },
        1
    );
    // Settled: a fresh findings scan is empty.
    let raw = unsafe { liv_vault_findings_at(c_path.as_ptr(), 0) };
    let after: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert_eq!(after.as_array().unwrap().len(), 0, "resolved: {after}");
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn the_snapshot_carries_the_projected_path() {
    // P20j.6: the fidelity flip's wire contract — a routed note's real
    // vault path rides the snapshot; a box-only scrap carries none.
    let (path, c_path) = fresh_box("liv_ffi_vaultpath");
    let scrap = unsafe {
        liv_capture_at(c_path.as_ptr(), CString::new("loose").unwrap().as_ptr())
    };
    let note = CString::new("note").unwrap();
    unsafe { liv_set_type_at(c_path.as_ptr(), scrap, note.as_ptr()) };
    let name_prop = CString::new("name").unwrap();
    let name = CString::new("Steven Åkesson").unwrap();
    unsafe { liv_set_at(c_path.as_ptr(), scrap, name_prop.as_ptr(), name.as_ptr()) };

    // A second, still-unrouted scrap.
    let orphan = unsafe {
        liv_capture_at(c_path.as_ptr(), CString::new("still loose").unwrap().as_ptr())
    };

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let rows = snap["entities"].as_array().unwrap();
    let routed = rows.iter().find(|r| r["id"].as_u64() == Some(scrap)).unwrap();
    assert_eq!(
        routed["vault_path"].as_str(),
        Some("library/notes/steven-akesson.md"),
        "the diacritic-folded projected path rides the wire"
    );
    let loose = rows.iter().find(|r| r["id"].as_u64() == Some(orphan)).unwrap();
    assert!(loose.get("vault_path").is_none(), "a box-only scrap carries no path");
    cleanup(&path);
}

#[test]
fn vault_status_and_rebuild() {
    let (root, _path, c_path) = fresh_vault("rebuild");
    let text = CString::new("rebuild me").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    let note = CString::new("note").unwrap();
    unsafe { liv_set_type_at(c_path.as_ptr(), id, note.as_ptr()) };
    let name_prop = CString::new("name").unwrap();
    let name = CString::new("Rebuild me").unwrap();
    unsafe { liv_set_at(c_path.as_ptr(), id, name_prop.as_ptr(), name.as_ptr()) };

    let raw = unsafe { liv_vault_status_at(c_path.as_ptr()) };
    let status: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert_eq!(status["mode"], "vault", "{status}");
    assert!(status["files"].as_u64().unwrap() >= 1);

    // Torch the projection; rebuild returns it.
    std::fs::remove_dir_all(root.join("library")).unwrap();
    assert!(unsafe { liv_vault_rebuild_at(c_path.as_ptr()) } >= 1);
    assert!(root.join("library/notes/rebuild-me.md").exists());

    // A LEGACY box reports legacy and never projects.
    let (lp, lc) = fresh_box("liv_ffi_legacy_status");
    let raw = unsafe { liv_vault_status_at(lc.as_ptr()) };
    let status: serde_json::Value =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert_eq!(status["mode"], "legacy");
    cleanup(&lp);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_shrunken_log_raises_an_alert_and_replays_honestly() {
    // P20j.4: sync-down of an OLDER log copy = length regression. The
    // fast path refuses (miss), the shorter log replays honestly, and
    // the notice is drained exactly once.
    let (path, c_path) = fresh_box("liv_ffi_regress");
    let text = CString::new("first thought").unwrap();
    assert_ne!(unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) }, 0);
    let older = std::fs::read(&path).unwrap();
    let text2 = CString::new("second thought").unwrap();
    assert_ne!(unsafe { liv_capture_at(c_path.as_ptr(), text2.as_ptr()) }, 0);
    let newer = std::fs::read(&path).unwrap();

    // The guard's proof is the CACHE entry; parallel tests may call
    // clear_cache_for_tests between our warm and the shrink, so the
    // scenario retries — the mechanism itself is deterministic.
    let mut surfaced = false;
    for _attempt in 0..10 {
        std::fs::write(&path, &newer).unwrap();
        unsafe { liv_string_free(liv_snapshot(c_path.as_ptr())) }; // warm
        // The "sync client" replaces the log with the older copy.
        std::fs::write(&path, &older).unwrap();
        unsafe { liv_string_free(liv_snapshot(c_path.as_ptr())) };
        let raw = unsafe { liv_vault_alerts_at(c_path.as_ptr()) };
        let alerts: Vec<String> =
            serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() })
                .unwrap();
        unsafe { liv_string_free(raw) };
        if alerts.iter().any(|a| a.contains("SHRANK")) {
            surfaced = true;
            break;
        }
    }
    assert!(surfaced, "the regression was surfaced within the retries");
    // Drained: a second read is quiet.
    let raw = unsafe { liv_vault_alerts_at(c_path.as_ptr()) };
    let again: Vec<String> =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert!(again.is_empty());
    cleanup(&path);
}

#[test]
fn a_conflicted_copy_sibling_raises_an_alert() {
    let (path, c_path) = fresh_box("liv_ffi_confl");
    unsafe { liv_string_free(liv_snapshot(c_path.as_ptr())) };
    let sibling = path.with_file_name("box (conflicted copy 2026-07-19).log");
    std::fs::write(&sibling, b"whatever a sync client left").unwrap();
    unsafe { liv_string_free(liv_snapshot(c_path.as_ptr())) };

    let raw = unsafe { liv_vault_alerts_at(c_path.as_ptr()) };
    let alerts: Vec<String> =
        serde_json::from_str(unsafe { CStr::from_ptr(raw).to_str().unwrap() }).unwrap();
    unsafe { liv_string_free(raw) };
    assert!(
        alerts.iter().any(|a| a.contains("conflicted copy")),
        "the sibling was surfaced: {alerts:?}"
    );
    let _ = std::fs::remove_file(&sibling);
    cleanup(&path);
}

#[test]
fn message_import_upserts_and_reimport_reads() {
    let (path, c_path) = fresh_box("liv_ffi_comms");
    let batch = CString::new(
        r#"[{"external_id":"slack:1","from":"Elin","source":"Slack · #liv-dev","sent":"2026-07-14 09:02","body":"day 1 pairings are up"}]"#,
    )
    .unwrap();
    assert_eq!(unsafe { liv_import_messages_at(c_path.as_ptr(), batch.as_ptr()) }, 1);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let rows = snap["entities"].as_array().unwrap();
    assert!(
        rows.iter().any(|r| r["kinds"]
            .as_array()
            .map(|k| k.iter().any(|x| x == "message"))
            .unwrap_or(false)),
        "the message rides the row store"
    );
    // Byte-identical re-import: 0 changed, and the cache survives
    // verbatim (Read, never a phantom Wrote).
    let before = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(unsafe { liv_import_messages_at(c_path.as_ptr(), batch.as_ptr()) }, 0);
    let after = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(before, after);
    cleanup(&path);
}

#[test]
fn a_refused_add_option_leaves_the_cache_verbatim() {
    // The review's over-eviction finding: an empty name is a pure
    // refusal — the store is untouched, so the cached snapshot must
    // survive (Read), never be evicted into a full replay (Failed).
    let (path, c_path) = fresh_box("liv_ffi_addopt_refused.log");
    let before = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let task = CString::new("task").unwrap();
    let blank = CString::new("   ").unwrap();
    assert_eq!(
        unsafe {
            liv_add_status_option_at(c_path.as_ptr(), task.as_ptr(), blank.as_ptr(), -1.0)
        },
        0
    );
    let after = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(before, after);
    cleanup(&path);
}

#[test]
fn build_properties_option_offer_stays_backward_compatible() {
    // The flat catalog list: no drops, no duplicates, additive fields only.
    let (path, c_path) = fresh_box("liv_ffi_catalog.log");
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let status = snap["properties"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["name"] == "status")
        .expect("the status property is in the catalog");
    let options = status["options"].as_array().unwrap();
    let names: Vec<&str> = options.iter().map(|o| o["name"].as_str().unwrap()).collect();
    assert_eq!(names.len(), 3, "no drops, no duplicates");
    for name in ["todo", "doing", "done"] {
        assert_eq!(names.iter().filter(|n| **n == name).count(), 1);
    }
    assert_eq!(options[0]["order"].as_f64(), Some(1.0), "additive order field");
    assert!(
        options[0]["for_types"].as_array().unwrap().iter().any(|t| t == "task"),
        "additive for_types field names the kind"
    );
    cleanup(&path);
}

#[test]
fn a_locked_box_refuses_every_new_p11_seam() {
    // Guard 5 across the phase's seams: a held lock means busy — never a
    // stale answer, never a write.
    let (path, c_path) = fresh_box("liv_ffi_p11_locked.log");
    let id = unsafe { liv_create_note_at(c_path.as_ptr()) };
    unsafe { liv_string_free(liv_snapshot(c_path.as_ptr())) }; // warm the cache
    let guard = Session::open(&path).unwrap();

    let due = CString::new("due").unwrap();
    let task = CString::new("task").unwrap();
    let name = CString::new("x").unwrap();
    unsafe {
        assert!(liv_cycle_date_role_at(c_path.as_ptr(), id, due.as_ptr()).is_null());
        assert_eq!(
            liv_set_span_at(c_path.as_ptr(), id, due.as_ptr(), 202607110000, 202607130000, 1),
            0
        );
        assert!(liv_status_options_at(c_path.as_ptr(), task.as_ptr()).is_null());
        assert_eq!(
            liv_add_status_option_at(c_path.as_ptr(), task.as_ptr(), name.as_ptr(), -1.0),
            0
        );
    }
    drop(guard);
    cleanup(&path);
}

// ---- spans through the seam (P11/11b) ----

#[test]
fn a_span_write_is_tagged_wrote_and_a_bad_span_is_refused() {
    let (path, c_path) = fresh_box("liv_ffi_span.log");
    let id = unsafe { liv_create_note_at(c_path.as_ptr()) };
    assert_ne!(id, 0);
    unsafe { liv_string_free(liv_snapshot(c_path.as_ptr())) }; // warm the cache
    let due = CString::new("due").unwrap();

    // A real span writes (the Wrote contract: the very next snapshot —
    // a cache hit — carries the new due start).
    let start = DateTime::date(2026, 7, 11).civil;
    let end = DateTime::date(2026, 7, 13).civil;
    assert_eq!(
        unsafe { liv_set_span_at(c_path.as_ptr(), id, due.as_ptr(), start, end, 1) },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
    let before = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(
        unsafe { liv_set_span_at(c_path.as_ptr(), id, due.as_ptr(), end, start, 1) },
        0
    );
    let after = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(before, after);
    cleanup(&path);
}

#[test]
fn a_span_displays_as_its_own_parseable_text() {
    // The mirror contract's read side (the review's finding: display
    // never learned spans, so a text write-back silently destroyed the
    // end). The snapshot's cell text IS the parseable span form — writing
    // it back through the ordinary set seam is a lossless no-op.
    let (path, c_path) = fresh_box("liv_ffi_span_display.log");
    let id = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let due = CString::new("due").unwrap();
    let start = DateTime::date(2026, 7, 11).civil;
    let end = DateTime::date(2026, 7, 13).civil;
    assert_eq!(
        unsafe { liv_set_span_at(c_path.as_ptr(), id, due.as_ptr(), start, end, 1) },
        1
    );

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
    assert_eq!(unsafe { liv_set_at(c_path.as_ptr(), id, due.as_ptr(), raw.as_ptr()) }, 1);
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
    let (path, c_path) = fresh_box("liv_ffi_lookup.log");
    let id = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let occurred = CString::new("occurred").unwrap();
    let when = CString::new("2026-07-09").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), id, occurred.as_ptr(), when.as_ptr()) },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
    let (path, c_path) = fresh_box("liv_ffi_span_ver.log");
    let a = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let b = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let due = CString::new("due").unwrap();
    let date = CString::new("date").unwrap();
    let s1 = DateTime::date(2026, 7, 11).civil;
    let e1 = DateTime::date(2026, 7, 13).civil;
    assert_eq!(unsafe { liv_set_span_at(c_path.as_ptr(), a, due.as_ptr(), s1, e1, 1) }, 1);
    assert_eq!(unsafe { liv_set_span_at(c_path.as_ptr(), b, date.as_ptr(), s1, e1, 1) }, 1);

    let header = std::fs::read_to_string(&path)
        .unwrap()
        .lines()
        .next()
        .unwrap()
        .to_string();
    assert_eq!(header, r#"{"liv_log":2}"#);
    clear_cache_for_tests();
    let raw = unsafe { liv_snapshot(c_path.as_ptr()) };
    assert!(!raw.is_null(), "the bumped box reopens from scratch");
    unsafe { liv_string_free(raw) };
    cleanup(&path);
}

// ---- role cycling through the cache (P11/11a) ----

#[test]
fn role_cycle_round_trips_through_the_cache() {
    let (path, c_path) = fresh_box("liv_ffi_cycle.log");
    let id = unsafe {
        liv_create_event_at(c_path.as_ptr(), DateTime::at(2026, 7, 11, 9, 0).civil, 0)
    };
    assert_ne!(id, 0);
    // Warm the cache, then cycle due -> date on the HIT path.
    unsafe { liv_string_free(liv_snapshot(c_path.as_ptr())) };
    let due = CString::new("due").unwrap();
    let raw = unsafe { liv_cycle_date_role_at(c_path.as_ptr(), id, due.as_ptr()) };
    assert!(!raw.is_null(), "the cycle succeeds");
    let next = unsafe { CStr::from_ptr(raw).to_str().unwrap().to_string() };
    unsafe { liv_string_free(raw) };
    assert_eq!(next, "date", "due cycles to date");

    // The Wrote contract: the very next snapshot (a cache hit) sees it.
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
    let full = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(snap, full);
    cleanup(&path);
}

#[test]
fn a_refused_cycle_is_tagged_read_and_leaves_the_cache_verbatim() {
    let (path, c_path) = fresh_box("liv_ffi_cycle_refused.log");
    let id = unsafe { liv_create_note_at(c_path.as_ptr()) };
    assert_ne!(id, 0);
    let before = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };

    // No due cell on the note: the cycle is refused, nothing written.
    let due = CString::new("due").unwrap();
    let raw = unsafe { liv_cycle_date_role_at(c_path.as_ptr(), id, due.as_ptr()) };
    assert!(raw.is_null(), "the cycle is refused");

    // The refusal never touched the store: the next snapshot — still the
    // cached one — is identical.
    let after = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(before, after);
    cleanup(&path);
}

#[test]
fn setting_location_on_an_event_round_trips() {
    // 10b: `location` is seeded (offered, not expected); set it on an event
    // through the ordinary set seam and it shows in the snapshot's cells.
    let (path, c_path) = fresh_box("liv_ffi_location.log");
    let id = unsafe {
        liv_create_event_at(c_path.as_ptr(), DateTime::at(2026, 7, 9, 9, 0).civil, 0)
    };
    assert_ne!(id, 0);
    let loc = CString::new("location").unwrap();
    let val = CString::new("Room 4").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), id, loc.as_ptr(), val.as_ptr()) },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
    let (path, c_path) = fresh_box("liv_ffi_torn.log");
    unsafe { liv_capture_at(c_path.as_ptr(), CString::new("real note").unwrap().as_ptr()) };
    // Append a torn (newline-less) trailing record straight to the file.
    {
        use std::io::Write as _;
        let mut f = std::fs::OpenOptions::new().append(true).open(&path).unwrap();
        f.write_all(b"{\"seq\":999,\"garbage\":").unwrap();
    }
    // First FFI open repairs (drops the torn record, lowering the length) and
    // caches the REPAIRED length; the second hits cleanly and agrees — the
    // torn record never leaks into either answer (Guard 1).
    let first = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let second = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(first, second);
    assert_eq!(first["entities"].as_array().unwrap().len(), 1);
    cleanup(&path);
}

#[test]
fn content_seam_roundtrips() {
    let (path, c_path) = fresh_box("liv_ffi_content.log");

    let text = CString::new("plain thought").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    assert_ne!(id, 0);

    // The read: capture's RichText comes back verbatim, name null.
    let doc = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) };
    assert_eq!(doc["id"], id);
    assert_eq!(doc["name"], serde_json::Value::Null);
    assert_eq!(doc["trashed"], false);
    assert_eq!(doc["spans"], serde_json::json!([{"Text": "plain thought"}]));
    let base = doc["fingerprint"].as_u64().unwrap();
    assert_ne!(base, 0);

    // The snapshot's content_print is the same identity, for free.
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
        liv_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), base, &mut fresh)
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
        liv_set_content_at(c_path.as_ptr(), id, drifted.as_ptr(), base, &mut fresh)
    };
    assert_eq!(stale, -1);
    // Unchanged spans against the fresh base: success, no transaction.
    let unchanged = unsafe {
        liv_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), fresh, std::ptr::null_mut())
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
            liv_set_content_at(c_path.as_ptr(), id, bad.as_ptr(), fresh, std::ptr::null_mut())
        },
        0
    );

    // Empty spans remove content; fingerprint returns to 0.
    let empty = CString::new("[]").unwrap();
    let mut cleared: u64 = 1;
    assert_eq!(
        unsafe {
            liv_set_content_at(c_path.as_ptr(), id, empty.as_ptr(), fresh, &mut cleared)
        },
        1
    );
    assert_eq!(cleared, 0);

    // Undo restores the prior content in one step.
    assert_eq!(unsafe { liv_undo_at(c_path.as_ptr()) }, 1);
    let doc = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) };
    assert_eq!(doc["spans"], serde_json::json!([{"Text": "rewritten"}]));

    // No such entity: the box answers "missing", never null — null is
    // reserved for a box that would not open at all.
    let gone = unsafe { read_json(liv_content_at(c_path.as_ptr(), 999_999)) };
    assert_eq!(gone["missing"], true);
    assert_eq!(gone["fingerprint"], 0);

    cleanup(&path);
}

#[test]
fn editing_content_retracts_stale_proposals() {
    let (path, c_path) = fresh_box("liv_ffi_retract.log");

    // The clerk proposes due=friday from the captured words.
    let text = CString::new("kickoff friday").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
            liv_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), base, std::ptr::null_mut())
        },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
fn accept_group_commits_a_group_as_one_transaction() {
    let (path, c_path) = fresh_box("liv_ffi_group.log");
    let a = CString::new("kickoff friday").unwrap();
    let b = CString::new("review monday").unwrap();
    let ida = unsafe { liv_capture_at(c_path.as_ptr(), a.as_ptr()) };
    let idb = unsafe { liv_capture_at(c_path.as_ptr(), b.as_ptr()) };

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let inbox = snap["inbox"].as_array().unwrap();
    assert_eq!(inbox.len(), 2);
    // P16c: each proposal carries structured commands for the diff card.
    assert_eq!(inbox[0]["commands"][0]["kind"], "add");
    assert_eq!(inbox[0]["commands"][0]["property"], "due");

    let fps: Vec<u64> = inbox.iter().map(|p| p["fingerprint"].as_u64().unwrap()).collect();
    let fps_json = CString::new(serde_json::to_string(&fps).unwrap()).unwrap();
    assert_eq!(
        unsafe { liv_accept_group_at(c_path.as_ptr(), fps_json.as_ptr()) },
        1
    );

    // Both scraps got a due; the queue drained.
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(snap["inbox"].as_array().unwrap().is_empty());
    let has_due = |snap: &serde_json::Value, id: u64| {
        snap["entities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|e| e["id"] == id)
            .unwrap()["cells"]
            .as_array()
            .unwrap()
            .iter()
            .any(|c| c["property"] == "due")
    };
    assert!(has_due(&snap, ida) && has_due(&snap, idb));

    // ONE undo reverts BOTH — the group committed as one transaction.
    assert_eq!(unsafe { liv_undo_at(c_path.as_ptr()) }, 1);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(!has_due(&snap, ida) && !has_due(&snap, idb), "one undo reverted the whole group");

    // A stale fingerprint refuses the whole group, untouched.
    let stale = CString::new("[123456789]").unwrap();
    assert_eq!(
        unsafe { liv_accept_group_at(c_path.as_ptr(), stale.as_ptr()) },
        0
    );

    cleanup(&path);
}

#[test]
fn legacy_text_content_reads_as_one_span() {
    let (path, c_path) = fresh_box("liv_ffi_legacy.log");

    let mut session = Session::open(&path).unwrap();
    let id = session.allocate_id();
    session
        .commit(
            vec![
                liv_core::Command::Create { entity: id },
                liv_core::Command::AddCell {
                    entity: id,
                    cell: liv_core::Cell {
                        property: liv_core::props::CONTENT,
                        value: Value::text("old plain text"),
                    },
                },
            ],
            "legacy",
            Author::User,
        )
        .unwrap();
    drop(session);

    let doc = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) };
    assert_eq!(doc["spans"], serde_json::json!([{"Text": "old plain text"}]));
    let base = doc["fingerprint"].as_u64().unwrap();
    assert_ne!(base, 0);

    // Saving over legacy content replaces it honestly, guarded by the
    // fingerprint of the stored Text value.
    let spans = CString::new(r#"[{"Text":"upgraded"}]"#).unwrap();
    assert_eq!(
        unsafe {
            liv_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), base, std::ptr::null_mut())
        },
        1
    );

    cleanup(&path);
}

#[test]
fn workspace_tree_roundtrips() {
    let (path, c_path) = fresh_box("liv_ffi_workspace.log");

    // The seed ships Home; a snapshot shows it, favourite by shell
    // convention (builtin), top-level.
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let spaces = snap["workspaces"].as_array().unwrap();
    assert_eq!(spaces.len(), 1);
    assert_eq!(spaces[0]["name"], "Home");
    assert_eq!(spaces[0]["builtin"], "home");
    assert_eq!(spaces[0]["parent"], 0);

    // A new area, then a child project under it.
    let name = CString::new("Work").unwrap();
    let area = unsafe { liv_create_workspace_at(c_path.as_ptr(), name.as_ptr(), 0) };
    assert_ne!(area, 0);
    let child_name = CString::new("Liv port").unwrap();
    let child =
        unsafe { liv_create_workspace_at(c_path.as_ptr(), child_name.as_ptr(), area) };
    assert_ne!(child, 0);

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let spaces = snap["workspaces"].as_array().unwrap();
    assert_eq!(spaces.len(), 3);
    let child_row = spaces.iter().find(|w| w["id"] == child).unwrap();
    assert_eq!(child_row["parent"], area);

    // Workspaces are navigation chrome: never in Everything.
    assert!(
        !snap["everything"].as_array().unwrap().iter().any(|id| *id == area || *id == child)
    );

    // The lens (design/ios.md M4): a workspace's `query` cell is what
    // makes it a saved view that also stamps. It rides the ordinary set
    // door and must reach the wire, or a shell has to keep its own copy
    // — a second source of truth the constitution refuses.
    let query_prop = CString::new("query").unwrap();
    let lens = CString::new("area:Work").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), area, query_prop.as_ptr(), lens.as_ptr()) },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let row = snap["workspaces"]
        .as_array()
        .unwrap()
        .iter()
        .find(|w| w["id"] == area)
        .unwrap()
        .clone();
    assert_eq!(row["query"], "area:Work");
    // A workspace without one carries no key at all (skip-serialized),
    // which every decoder already treats as absent.
    let home = snap["workspaces"]
        .as_array()
        .unwrap()
        .iter()
        .find(|w| w["builtin"] == "home")
        .unwrap()
        .clone();
    assert!(home["query"].is_null());

    // favorite/archived ride the ordinary set door; unset removes.
    let favorite = CString::new("favorite").unwrap();
    let yes = CString::new("true").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), area, favorite.as_ptr(), yes.as_ptr()) },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
        unsafe { liv_unset_at(c_path.as_ptr(), child, parent_prop.as_ptr()) },
        1
    );

    // Deletion never cascades: trashing the parent trashes only the
    // parent. The child survives with a now-dangling parent — the
    // shell re-roots it. One undo restores the parent.
    let up = CString::new("parent").unwrap();
    let area_arg = CString::new(format!("{area}")).unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), child, up.as_ptr(), area_arg.as_ptr()) },
        1
    );
    assert_eq!(unsafe { liv_trash_workspace_at(c_path.as_ptr(), area) }, 1);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let after = snap["workspaces"].as_array().unwrap();
    assert_eq!(after.len(), 2); // Home + the surviving child
    assert!(after.iter().any(|w| w["id"] == child));
    assert!(!after.iter().any(|w| w["id"] == area));
    assert_eq!(unsafe { liv_undo_at(c_path.as_ptr()) }, 1);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(snap["workspaces"].as_array().unwrap().len(), 3);

    cleanup(&path);
}

#[test]
fn set_at_and_create_note() {
    let (path, c_path) = fresh_box("liv_ffi_set.log");

    // Birth: one transaction, typed note, created — then rename.
    let note = unsafe { liv_create_note_at(c_path.as_ptr()) };
    assert_ne!(note, 0);
    let prop = CString::new("name").unwrap();
    let value = CString::new("meeting notes").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), note, prop.as_ptr(), value.as_ptr()) },
        1
    );
    let doc = unsafe { read_json(liv_content_at(c_path.as_ptr(), note)) };
    assert_eq!(doc["name"], "meeting notes");

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
        unsafe { liv_set_at(c_path.as_ptr(), note, status.as_ptr(), done.as_ptr()) },
        1
    );
    // A date, parsed by the declared kind.
    let due = CString::new("due").unwrap();
    let day = CString::new("2026-07-08").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), note, due.as_ptr(), day.as_ptr()) },
        1
    );
    // Unknown property, unknown entity: refused.
    let nope = CString::new("frobnicate").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), note, nope.as_ptr(), done.as_ptr()) },
        0
    );
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), 999_999, status.as_ptr(), done.as_ptr()) },
        0
    );

    cleanup(&path);
}

#[test]
fn content_history_is_the_log() {
    let (path, c_path) = fresh_box("liv_ffi_history.log");

    let text = CString::new("first").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    let base = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) }["fingerprint"]
        .as_u64()
        .unwrap();

    // A second version.
    let v2 = CString::new(r#"[{"Text":"second"}]"#).unwrap();
    let mut fresh: u64 = 0;
    assert_eq!(
        unsafe { liv_set_content_at(c_path.as_ptr(), id, v2.as_ptr(), base, &mut fresh) },
        1
    );

    // History has both, newest first, each a whole content value.
    let hist = unsafe { read_json(liv_content_history_at(c_path.as_ptr(), id)) };
    let versions = hist.as_array().unwrap();
    assert_eq!(versions.len(), 2);
    assert_eq!(versions[0]["spans"], serde_json::json!([{"Text": "second"}]));
    assert_eq!(versions[1]["spans"], serde_json::json!([{"Text": "first"}]));
    assert_eq!(versions[1]["author"], "user");

    // Restore = an ordinary set_content of the old spans (re-read the
    // fresh base first, the way the shell does).
    let re = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) };
    let now = re["fingerprint"].as_u64().unwrap();
    let restore = CString::new(r#"[{"Text":"first"}]"#).unwrap();
    assert_eq!(
        unsafe {
            liv_set_content_at(c_path.as_ptr(), id, restore.as_ptr(), now, std::ptr::null_mut())
        },
        1
    );
    let back = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) };
    assert_eq!(back["spans"], serde_json::json!([{"Text": "first"}]));
    // The restore is a NEW version, appended — the log is never rewritten.
    let hist = unsafe { read_json(liv_content_history_at(c_path.as_ptr(), id)) };
    assert_eq!(hist.as_array().unwrap().len(), 3);

    cleanup(&path);
}

#[test]
fn undo_does_not_mint_a_phantom_history_version() {
    let (path, c_path) = fresh_box("liv_ffi_hist_undo.log");

    let text = CString::new("first").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    let base = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) }["fingerprint"]
        .as_u64()
        .unwrap();
    let v2 = CString::new(r#"[{"Text":"second"}]"#).unwrap();
    let mut fresh: u64 = 0;
    assert_eq!(
        unsafe { liv_set_content_at(c_path.as_ptr(), id, v2.as_ptr(), base, &mut fresh) },
        1
    );

    // Undo the edit — the content reverts to "first" via an appended
    // inverse transaction. History must still show only the two
    // forward edits, not a third phantom "first".
    assert_eq!(unsafe { liv_undo_at(c_path.as_ptr()) }, 1);
    let back = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) };
    assert_eq!(back["spans"], serde_json::json!([{"Text": "first"}]));
    let hist = unsafe { read_json(liv_content_history_at(c_path.as_ptr(), id)) };
    assert_eq!(hist.as_array().unwrap().len(), 2);

    cleanup(&path);
}

#[test]
fn marks_and_blocks_round_trip_through_the_seam() {
    let (path, c_path) = fresh_box("liv_ffi_p4.log");

    let text = CString::new("start").unwrap();
    let id = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    let base = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) }["fingerprint"]
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
            liv_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), base, &mut fresh)
        },
        1
    );
    assert_ne!(fresh, base);

    // The read comes back with the marks and blocks intact.
    let got = unsafe { read_json(liv_content_at(c_path.as_ptr(), id)) };
    assert_eq!(got["spans"][0], serde_json::json!({"Break": {"Heading": 1}}));
    assert_eq!(got["spans"][4], serde_json::json!({"Text": {"text": "this", "marks": 5}}));
    assert_eq!(got["spans"][5], serde_json::json!({"Break": {"Task": {"depth": 0, "done": false}}}));
    assert_eq!(got["fingerprint"].as_u64().unwrap(), fresh);

    // Saving the identical doc against the fresh base is a no-op, not
    // a conflict — the marks-and-blocks encoding is canonical.
    assert_eq!(
        unsafe {
            liv_set_content_at(c_path.as_ptr(), id, spans.as_ptr(), fresh, std::ptr::null_mut())
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
    let (path, c_path) = fresh_box("liv_ffi_catalog.log");
    let text = CString::new("a note").unwrap();
    assert_ne!(unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) }, 0);

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
    let (path, c_path) = fresh_box("liv_ffi_search.log");
    let a = unsafe {
        liv_capture_at(c_path.as_ptr(), CString::new("call anna about the report").unwrap().as_ptr())
    };
    let b = unsafe {
        liv_capture_at(c_path.as_ptr(), CString::new("buy groceries").unwrap().as_ptr())
    };
    assert_ne!(a, 0);
    assert_ne!(b, 0);

    let raw = CString::new("report").unwrap();
    let json = unsafe { read_json(liv_search_at(c_path.as_ptr(), raw.as_ptr())) };

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
    let all = unsafe { read_json(liv_search_at(c_path.as_ptr(), blank.as_ptr())) };
    let all_ids: Vec<u64> = all["hits"].as_array().unwrap().iter()
        .map(|h| h["id"].as_u64().unwrap()).collect();
    assert!(all_ids.contains(&a) && all_ids.contains(&b));

    cleanup(&path);
}

#[test]
fn add_file_by_reference_through_the_seam() {
    let (path, c_path) = fresh_box("liv_ffi_addfile.log");
    let doc = std::env::temp_dir().join("liv_ffi_sample.txt");
    std::fs::write(&doc, b"hello from a referenced file").unwrap();
    let doc_c = CString::new(doc.to_str().unwrap()).unwrap();

    let id = unsafe { liv_add_file_at(c_path.as_ptr(), doc_c.as_ptr()) };
    assert_ne!(id, 0);

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let entity = snap["entities"].as_array().unwrap().iter()
        .find(|e| e["id"].as_u64() == Some(id)).unwrap();
    // name = filename, a file-kind cell rendering the path, format = txt
    assert_eq!(entity["title"], "liv_ffi_sample.txt");
    let cells = entity["cells"].as_array().unwrap();
    let file_cell = cells.iter().find(|c| c["kind"] == "file").unwrap();
    assert_eq!(file_cell["value"], doc.to_str().unwrap());
    assert!(cells.iter().any(|c| c["property"] == "format" && c["value"] == "txt"));

    // A bad path adds nothing and returns 0.
    let bad = CString::new("/no/such/file.pdf").unwrap();
    assert_eq!(unsafe { liv_add_file_at(c_path.as_ptr(), bad.as_ptr()) }, 0);

    let _ = std::fs::remove_file(&doc);
    cleanup(&path);
}

#[test]
fn import_batch_through_the_seam() {
    let (path, c_path) = fresh_box("liv_ffi_import.log");
    let items = r#"[
        {"kind":"link","url":"https://a.example","title":"Alpha"},
        {"kind":"link","url":"https://b.example","title":null},
        {"kind":"scrap","text":"a loose thought"}
    ]"#;
    let items_c = CString::new(items).unwrap();
    let stamps_c = CString::new("[]").unwrap();
    let n = unsafe {
        liv_import_batch_at(c_path.as_ptr(), items_c.as_ptr(), stamps_c.as_ptr())
    };
    assert_eq!(n, 3);

    // The titled link shows its title; the batch really landed.
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let entities = snap["entities"].as_array().unwrap();
    assert!(entities.iter().any(|e| e["title"] == "Alpha"), "titled link not found");

    // Re-import the same urls → 0 new (external-id dedupe).
    let items2 = r#"[
        {"kind":"link","url":"https://a.example","title":"Alpha"},
        {"kind":"link","url":"https://b.example","title":null}
    ]"#;
    let items2_c = CString::new(items2).unwrap();
    let n2 = unsafe {
        liv_import_batch_at(c_path.as_ptr(), items2_c.as_ptr(), stamps_c.as_ptr())
    };
    assert_eq!(n2, 0, "re-import should be a no-op");

    // A malformed items json returns -1, writes nothing.
    let bad = CString::new("not json").unwrap();
    assert_eq!(
        unsafe { liv_import_batch_at(c_path.as_ptr(), bad.as_ptr(), stamps_c.as_ptr()) },
        -1
    );

    cleanup(&path);
}

#[test]
fn export_through_the_seam() {
    let (path, c_path) = fresh_box("liv_ffi_export.log");
    // Import two notes, then read their ids from the snapshot.
    let items = r#"[
        {"kind":"note","frontmatter":[["title","One"]],"body":"first","source_id":"/1"},
        {"kind":"note","frontmatter":[["title","Two"]],"body":"second","source_id":"/2"}
    ]"#;
    let items_c = CString::new(items).unwrap();
    let stamps_c = CString::new("[]").unwrap();
    assert_eq!(
        unsafe { liv_import_batch_at(c_path.as_ptr(), items_c.as_ptr(), stamps_c.as_ptr()) },
        2
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let ids: Vec<u64> = snap["entities"].as_array().unwrap().iter()
        .filter(|e| e["title"] == "One" || e["title"] == "Two")
        .map(|e| e["id"].as_u64().unwrap())
        .collect();
    assert_eq!(ids.len(), 2);

    let out = std::env::temp_dir().join("liv_ffi_export_out");
    let _ = std::fs::remove_dir_all(&out);
    let ids_c = CString::new(serde_json::to_string(&ids).unwrap()).unwrap();
    let groups_c = CString::new("[]").unwrap();
    let dest_c = CString::new(out.to_str().unwrap()).unwrap();
    let n = unsafe {
        liv_export_at(c_path.as_ptr(), ids_c.as_ptr(), groups_c.as_ptr(), dest_c.as_ptr())
    };
    assert_eq!(n, 2);
    assert!(out.join("One.md").exists());
    assert!(out.join("Two.md").exists());

    // Bad ids json → -1.
    let bad = CString::new("nope").unwrap();
    assert_eq!(
        unsafe { liv_export_at(c_path.as_ptr(), bad.as_ptr(), groups_c.as_ptr(), dest_c.as_ptr()) },
        -1
    );

    let _ = std::fs::remove_dir_all(&out);
    cleanup(&path);
}

#[test]
fn create_task_through_the_seam() {
    let (path, c_path) = fresh_box("liv_ffi_task.log");
    let id = unsafe { liv_create_task_at(c_path.as_ptr()) };
    assert_ne!(id, 0);

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
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
    let (path, c_path) = fresh_box("liv_ffi_list.log");
    let name = CString::new("Reading queue").unwrap();
    let list = unsafe { liv_create_list_at(c_path.as_ptr(), name.as_ptr()) };
    assert_ne!(list, 0);
    let a = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let b = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let related = CString::new("related").unwrap();
    let a_ref = CString::new(format!("#{a}")).unwrap();
    let b_ref = CString::new(format!("#{b}")).unwrap();

    // Add a, then b; a duplicate add is a no-op that still returns 1.
    assert_eq!(unsafe { liv_add_cell_at(c_path.as_ptr(), list, related.as_ptr(), a_ref.as_ptr()) }, 1);
    assert_eq!(unsafe { liv_add_cell_at(c_path.as_ptr(), list, related.as_ptr(), b_ref.as_ptr()) }, 1);
    assert_eq!(unsafe { liv_add_cell_at(c_path.as_ptr(), list, related.as_ptr(), a_ref.as_ptr()) }, 1);

    let members = |snap: &serde_json::Value| -> Vec<u64> {
        snap["entities"].as_array().unwrap().iter()
            .find(|e| e["id"].as_u64() == Some(list)).unwrap()["cells"].as_array().unwrap()
            .iter().filter(|c| c["property"] == "related")
            .filter_map(|c| c["ref_target"].as_u64()).collect()
    };
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(members(&snap), vec![a, b], "insertion order, not doubled");

    // Remove a — b remains, and a (the note) survives.
    assert_eq!(unsafe { liv_remove_cell_at(c_path.as_ptr(), list, related.as_ptr(), a_ref.as_ptr()) }, 1);
    let snap2 = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert_eq!(members(&snap2), vec![b]);
    assert!(
        snap2["entities"].as_array().unwrap().iter().any(|e| e["id"].as_u64() == Some(a)),
        "un-tagging never deletes the member");

    cleanup(&path);
}

#[test]
fn links_cross_the_seam_in_both_directions() {
    let (path, c_path) = fresh_box("liv_ffi_links.log");
    let hub = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let picked = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let typed = unsafe { liv_create_note_at(c_path.as_ptr()) };
    let name = CString::new("name").unwrap();
    for (id, text) in [(hub, "Hub"), (picked, "Picked"), (typed, "Typed")] {
        let value = CString::new(text).unwrap();
        assert_eq!(
            unsafe { liv_set_at(c_path.as_ptr(), id, name.as_ptr(), value.as_ptr()) }, 1);
    }

    // Door one: a link picked in properties.
    let related = CString::new("related").unwrap();
    let picked_ref = CString::new(format!("#{picked}")).unwrap();
    assert_eq!(
        unsafe { liv_add_cell_at(c_path.as_ptr(), hub, related.as_ptr(), picked_ref.as_ptr()) },
        1);
    // Door two: a [[ ]] typed in the body — a Ref span, nothing else.
    let spans = CString::new(format!(r#"[{{"Text":{{"text":"see ","marks":0}}}},{{"Ref":{typed}}}]"#))
        .unwrap();
    assert_eq!(
        unsafe { liv_set_content_at(c_path.as_ptr(), hub, spans.as_ptr(), 0, std::ptr::null_mut()) },
        1);

    let links = unsafe { read_json(liv_links_at(c_path.as_ptr(), hub)) };
    let out = links["out"].as_array().unwrap();
    assert_eq!(out.len(), 2, "one list, both doors: {links}");
    assert_eq!(out[0]["id"].as_u64(), Some(picked));
    assert_eq!(out[0]["name"], "Picked");
    assert_eq!(out[0]["from_body"], false);
    assert_eq!(out[1]["id"].as_u64(), Some(typed));
    assert_eq!(out[1]["from_body"], true);
    assert!(links["in"].as_array().unwrap().is_empty());

    // …and the other end sees it coming back, through either door.
    for target in [picked, typed] {
        let back = unsafe { read_json(liv_links_at(c_path.as_ptr(), target)) };
        let inbound = back["in"].as_array().unwrap();
        assert_eq!(inbound.len(), 1, "#{target} is linked from the hub: {back}");
        assert_eq!(inbound[0]["id"].as_u64(), Some(hub));
        assert_eq!(inbound[0]["name"], "Hub");
    }

    // Unlinking is a removal of the cell — never a delete of the target.
    assert_eq!(
        unsafe { liv_remove_cell_at(c_path.as_ptr(), hub, related.as_ptr(), picked_ref.as_ptr()) },
        1);
    let after = unsafe { read_json(liv_links_at(c_path.as_ptr(), hub)) };
    assert_eq!(after["out"].as_array().unwrap().len(), 1);
    let orphan = unsafe { read_json(liv_links_at(c_path.as_ptr(), picked)) };
    assert!(orphan["in"].as_array().unwrap().is_empty(), "the backlink went with it");

    // An unknown id answers empty, never null.
    let none = unsafe { read_json(liv_links_at(c_path.as_ptr(), 999_999)) };
    assert!(none["out"].as_array().unwrap().is_empty());

    cleanup(&path);
}

#[test]
fn a_nul_byte_in_extracted_text_survives_the_seam() {
    let (path, c_path) = fresh_box("liv_ffi_nul.log");
    // A text-format file with an embedded NUL (a null-padded log).
    let doc = std::env::temp_dir().join("liv_ffi_nul.log");
    std::fs::write(&doc, b"before\0after the null").unwrap();
    let doc_c = CString::new(doc.to_str().unwrap()).unwrap();
    let id = unsafe { liv_add_file_at(c_path.as_ptr(), doc_c.as_ptr()) };
    assert_ne!(id, 0);

    // The preview must not silently vanish — the NUL is scrubbed at the
    // seam, so a non-null string comes back with the words intact.
    let raw = unsafe { liv_extracted_text_at(c_path.as_ptr(), id) };
    assert!(!raw.is_null(), "the NUL must not blank the preview");
    let text = unsafe { CStr::from_ptr(raw).to_str().unwrap().to_string() };
    unsafe { liv_string_free(raw) };
    assert!(text.contains("before") && text.contains("after the null"));

    let _ = std::fs::remove_file(&doc);
    let _ = std::fs::remove_dir_all(files::cache_dir(path.to_str().unwrap()));
    cleanup(&path);
}
#[test]
fn pins_roundtrip_backstage_and_tolerate_dangling_targets() {
    let (path, c_path) = fresh_box("liv_ffi_pins.log");

    let text = CString::new("pin me").unwrap();
    let note = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };
    assert_ne!(note, 0);
    let other_text = CString::new("me too").unwrap();
    let other = unsafe { liv_capture_at(c_path.as_ptr(), other_text.as_ptr()) };

    // Pin both; pinning is idempotent.
    let pin = unsafe { liv_pin_at(c_path.as_ptr(), note) };
    assert_ne!(pin, 0);
    assert_eq!(unsafe { liv_pin_at(c_path.as_ptr(), note) }, pin);
    let pin_other = unsafe { liv_pin_at(c_path.as_ptr(), other) };
    assert_ne!(pin_other, 0);

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let pins = snap["pins"].as_array().unwrap();
    assert_eq!(pins.len(), 2);
    // Ordered by the float key: first pinned first.
    assert_eq!(pins[0]["target"], note);
    assert_eq!(pins[1]["target"], other);
    assert!(pins[0]["order"].as_f64().unwrap() < pins[1]["order"].as_f64().unwrap());
    // Backstage: the pin entity itself never pollutes Everything.
    assert!(!snap["everything"].as_array().unwrap().iter().any(|id| *id == pin));

    // A dangling target (trashed under the pin) drops the ROW, never
    // the snapshot.
    assert_eq!(unsafe { liv_trash_at(c_path.as_ptr(), other) }, 1);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let pins = snap["pins"].as_array().unwrap();
    assert_eq!(pins.len(), 1);
    assert_eq!(pins[0]["target"], note);

    // Unpin by target; a second unpin is a quiet no-op.
    assert_eq!(unsafe { liv_unpin_at(c_path.as_ptr(), note) }, 1);
    assert_eq!(unsafe { liv_unpin_at(c_path.as_ptr(), note) }, 0);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(snap["pins"].as_array().unwrap().is_empty());

    cleanup(&path);
}
#[test]
fn layers_roundtrip_and_drop_dangling_members() {
    let (path, c_path) = fresh_box("liv_ffi_layers.log");

    let a_text = CString::new("alpha").unwrap();
    let a = unsafe { liv_capture_at(c_path.as_ptr(), a_text.as_ptr()) };
    let b_text = CString::new("beta").unwrap();
    let b = unsafe { liv_capture_at(c_path.as_ptr(), b_text.as_ptr()) };

    let name = CString::new("Writing set").unwrap();
    let members = CString::new(format!("[{b},{a}]")).unwrap();
    let layer =
        unsafe { liv_layer_save_at(c_path.as_ptr(), name.as_ptr(), 0, members.as_ptr()) };
    assert_ne!(layer, 0);

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let layers = snap["layers"].as_array().unwrap();
    assert_eq!(layers.len(), 1);
    assert_eq!(layers[0]["id"], layer);
    assert_eq!(layers[0]["name"], "Writing set");
    // Members in SAVED order: b before a.
    let members: Vec<u64> = layers[0]["members"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_u64().unwrap())
        .collect();
    assert_eq!(members, vec![b, a]);
    // Backstage: the layer never pollutes Everything.
    assert!(!snap["everything"].as_array().unwrap().iter().any(|id| *id == layer));

    // A dangling member (trashed under the layer) drops from the ROW,
    // not the snapshot; the layer survives with the live remainder.
    assert_eq!(unsafe { liv_trash_at(c_path.as_ptr(), b) }, 1);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let layers = snap["layers"].as_array().unwrap();
    assert_eq!(layers.len(), 1);
    let members: Vec<u64> = layers[0]["members"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_u64().unwrap())
        .collect();
    assert_eq!(members, vec![a]);

    // Delete rides the ordinary trash door.
    assert_eq!(unsafe { liv_trash_at(c_path.as_ptr(), layer) }, 1);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(snap["layers"].as_array().unwrap().is_empty());

    cleanup(&path);
}
#[test]
fn habits_roundtrip_through_the_snapshot() {
    let (path, c_path) = fresh_box("liv_ffi_habits.log");

    let name = CString::new("Climb").unwrap();
    let cadence = CString::new("3\u{d7}/wk").unwrap();
    let habit =
        unsafe { liv_create_habit_at(c_path.as_ptr(), name.as_ptr(), 2.0, cadence.as_ptr()) };
    assert_ne!(habit, 0);
    let other_name = CString::new("Mobility").unwrap();
    let other = unsafe {
        liv_create_habit_at(c_path.as_ptr(), other_name.as_ptr(), 0.0, std::ptr::null())
    };
    assert_ne!(other, 0);

    // Check in TODAY (0 = today, the shell's path) — idempotent.
    let row = unsafe { liv_check_in_at(c_path.as_ptr(), habit, 0) };
    assert_ne!(row, 0);
    assert_eq!(unsafe { liv_check_in_at(c_path.as_ptr(), habit, 0) }, row);

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let section = &snap["habits"];
    let lines = section["habits"].as_array().unwrap();
    assert_eq!(lines.len(), 2);
    let climb = lines.iter().find(|h| h["id"] == habit).unwrap();
    assert_eq!(climb["points"], 2.0);
    assert_eq!(climb["today_check_in"], row);
    let mobility = lines.iter().find(|h| h["id"] == other).unwrap();
    assert_eq!(mobility["points"], 1.0);
    assert!(mobility["today_check_in"].is_null());
    assert_eq!(section["streak"], 1);
    assert_eq!(section["heat"].as_array().unwrap().len(), 84);
    assert_eq!(section["heat"][83], 1);

    // The habit is front of house; the check-in record is backstage.
    assert!(snap["everything"].as_array().unwrap().iter().any(|id| *id == habit));
    assert!(!snap["everything"].as_array().unwrap().iter().any(|id| *id == row));

    // Uncheck rides the ordinary trash door.
    assert_eq!(unsafe { liv_trash_at(c_path.as_ptr(), row) }, 1);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(snap["habits"]["habits"][0]["today_check_in"].is_null());
    assert_eq!(snap["habits"]["streak"], 0);

    cleanup(&path);
}
#[test]
fn time_views_widgets_roundtrip_the_snapshot() {
    let (path, c_path) = fresh_box("liv_ffi_timeviews.log");

    let text = CString::new("thesis work").unwrap();
    let project = unsafe { liv_capture_at(c_path.as_ptr(), text.as_ptr()) };

    // A closed interval: full civil stamps (YYYYMMDDHHMM), anchored to
    // today so the entry always sits inside the rolling 7-day window
    // (a fixed date rots out of the window as the calendar advances).
    let day = civil_today().civil / 10_000;
    let entry =
        unsafe { liv_log_time_at(c_path.as_ptr(), project, day * 10_000 + 900, day * 10_000 + 1030) };
    assert_ne!(entry, 0);

    let view_name = CString::new("Open tasks").unwrap();
    let query = CString::new("is:task status!=done").unwrap();
    let view = unsafe {
        liv_create_view_at(c_path.as_ptr(), view_name.as_ptr(), query.as_ptr())
    };
    assert_ne!(view, 0);

    let kind = CString::new("habits").unwrap();
    let widget = unsafe { liv_widget_add_at(c_path.as_ptr(), kind.as_ptr(), 0, 3.0) };
    assert_ne!(widget, 0);

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    // Time: totals + entries in the 7-day window.
    let time = &snap["time_entries"];
    assert_eq!(time["totals"][0]["target"], project);
    assert_eq!(time["totals"][0]["minutes"], 90);
    assert_eq!(time["entries"].as_array().unwrap().len(), 1);
    // Views.
    let views = snap["views"].as_array().unwrap();
    assert_eq!(views.len(), 1);
    assert_eq!(views[0]["name"], "Open tasks");
    assert_eq!(views[0]["query"], "is:task status!=done");
    // Widgets, ordered.
    let widgets = snap["widgets"].as_array().unwrap();
    assert_eq!(widgets.len(), 1);
    assert_eq!(widgets[0]["kind"], "habits");
    assert_eq!(widgets[0]["span"], 3.0);
    // All backstage: none of the records pollute Everything.
    let everything = snap["everything"].as_array().unwrap();
    assert!(!everything.iter().any(|id| *id == entry || *id == view || *id == widget));
    // But the WIDGET joins the row store, so the Inspector can resolve a
    // selected card (P18e) — rows only, never the id lists.
    assert!(snap["entities"].as_array().unwrap().iter().any(|e| e["id"] == widget));

    // Removal rides the ordinary trash door.
    assert_eq!(unsafe { liv_trash_at(c_path.as_ptr(), widget) }, 1);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    assert!(snap["widgets"].as_array().unwrap().is_empty());

    cleanup(&path);
}
#[test]
fn rename_value_roundtrips_and_refuses_wrong_kinds() {
    let (path, c_path) = fresh_box("liv_ffi_rename.log");

    let a_text = CString::new("carrier one").unwrap();
    let a = unsafe { liv_capture_at(c_path.as_ptr(), a_text.as_ptr()) };
    let b_text = CString::new("carrier two").unwrap();
    let b = unsafe { liv_capture_at(c_path.as_ptr(), b_text.as_ptr()) };

    // Birth a text property through the existing add-property door, set
    // both carriers, rename across them.
    let tag = CString::new("tag").unwrap();
    let kind = CString::new("text").unwrap();
    let prop = unsafe { liv_add_property_at(c_path.as_ptr(), tag.as_ptr(), kind.as_ptr()) };
    assert_ne!(prop, 0);
    let old = CString::new("draft").unwrap();
    for id in [a, b] {
        assert_eq!(
            unsafe { liv_set_at(c_path.as_ptr(), id, tag.as_ptr(), old.as_ptr()) },
            1
        );
    }
    let new = CString::new("sketch").unwrap();
    assert_eq!(
        unsafe {
            liv_rename_value_at(c_path.as_ptr(), tag.as_ptr(), old.as_ptr(), new.as_ptr())
        },
        2
    );
    // One undo restores both.
    assert_eq!(unsafe { liv_undo_at(c_path.as_ptr()) }, 1);

    // Kind discipline: a datetime property refuses.
    let due = CString::new("due").unwrap();
    let x = CString::new("x").unwrap();
    let y = CString::new("y").unwrap();
    assert_eq!(
        unsafe {
            liv_rename_value_at(c_path.as_ptr(), due.as_ptr(), x.as_ptr(), y.as_ptr())
        },
        -1
    );

    cleanup(&path);
}
#[test]
fn seed_layer_and_kind_ids_ride_the_wire() {
    let (path, c_path) = fresh_box("liv_ffi_seedlayer.log");

    // The kind-id seam (19c): type entities exposed as an optional key so
    // hide-on-kind / core-on-kinds writers can pass #<id> references.
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let kinds = snap["kinds"].as_array().unwrap();
    let task_kind = kinds.iter().find(|k| k["name"] == "task").expect("task kind on the wire");
    assert!(task_kind["id"].as_u64().unwrap() > 0);
    assert!(kinds.iter().any(|k| k["name"] == "habit"));

    // The seed layer: a SEEDED, unused status option reads seeded=true,
    // count=0, hidden=false.
    let props_arr = snap["properties"].as_array().unwrap();
    let status = props_arr.iter().find(|p| p["name"] == "status").unwrap();
    assert_eq!(status["seeded"], true, "the status definition is seed-born");
    let todo = status["options"].as_array().unwrap().iter()
        .find(|o| o["name"] == "todo").unwrap().clone();
    assert_eq!(todo["seeded"], true);
    assert_eq!(todo["count"], 0);
    assert_eq!(todo["hidden"], false);

    // Using the seed flips it to the vault shelf: count>0 → seeded=false.
    let task = unsafe { liv_create_task_at(c_path.as_ptr()) };
    assert_ne!(task, 0);
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let status = snap["properties"].as_array().unwrap().iter()
        .find(|p| p["name"] == "status").unwrap().clone();
    let todo = status["options"].as_array().unwrap().iter()
        .find(|o| o["name"] == "todo").unwrap().clone();
    assert!(todo["count"].as_u64().unwrap() >= 1);
    assert_eq!(todo["seeded"], false, "a used seed migrates shelves");

    // The hidden convention: a `hidden` bool cell on the option entity.
    let hidden_name = CString::new("hidden").unwrap();
    let bool_kind = CString::new("bool").unwrap();
    assert_ne!(
        unsafe {
            liv_add_property_at(c_path.as_ptr(), hidden_name.as_ptr(), bool_kind.as_ptr())
        },
        0
    );
    let option_id = todo["id"].as_u64().unwrap();
    let yes = CString::new("true").unwrap();
    assert_eq!(
        unsafe { liv_set_at(c_path.as_ptr(), option_id, hidden_name.as_ptr(), yes.as_ptr()) },
        1
    );
    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let status = snap["properties"].as_array().unwrap().iter()
        .find(|p| p["name"] == "status").unwrap().clone();
    let todo = status["options"].as_array().unwrap().iter()
        .find(|o| o["name"] == "todo").unwrap().clone();
    assert_eq!(todo["hidden"], true);

    // A user-born property is NOT seeded.
    let hidden_def = snap["properties"].as_array().unwrap().iter()
        .find(|p| p["name"] == "hidden").unwrap().clone();
    assert_eq!(hidden_def["seeded"], false);

    cleanup(&path);
}

/// Phase 3: open checkbox lines inside notes ride the wire as a
/// projection — derived on read, stored nowhere, created never.
#[test]
fn note_task_lines_ride_the_wire() {
    let (path, c_path) = fresh_box("liv_ffi_notetasks.log");
    let note = unsafe { liv_create_note_at(c_path.as_ptr()) };
    assert_ne!(note, 0);

    // The iOS editor's shape: literal markers, Body breaks.
    let spans = r#"[
        {"Text":"Roof project"},
        {"Break":"Body"},
        {"Text":"- [ ] call the surveyor"},
        {"Break":"Body"},
        {"Text":"- [x] paid deposit"}
    ]"#;
    let json = CString::new(spans).unwrap();
    let mut fresh: u64 = 0;
    let ok = unsafe {
        liv_set_content_at(c_path.as_ptr(), note, json.as_ptr(), 0, &mut fresh)
    };
    assert_eq!(ok, 1, "content saved");

    let snap = unsafe { read_json(liv_snapshot(c_path.as_ptr())) };
    let rows = snap["note_tasks"].as_array().expect("note_tasks on the wire");
    assert_eq!(rows.len(), 1, "the OPEN line only: {rows:?}");
    assert_eq!(rows[0]["entity"].as_u64().unwrap(), note);
    assert_eq!(rows[0]["line"], 1, "second line of the buffer");
    assert_eq!(rows[0]["text"], "call the surveyor", "marker stripped");
    assert_eq!(rows[0]["source"], "Roof project", "the note's own first line, not a summary");
    assert_eq!(rows[0]["indent"], 0);

    // Nothing was created or written by the projection itself: the
    // note is still the only front-of-house entity.
    assert_eq!(snap["everything"].as_array().unwrap().len(), 1);

    cleanup(&path);
}
