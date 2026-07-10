//! P11/11b — writing spans through the ordinary seams: the datetime grammar
//! gains "start -> end" (both sides the existing yyyy-mm-dd [hh:mm] form,
//! same date_only reading, end strictly after start), so the inspector's
//! set seam and the search DSL are span-capable with no new entry point.

use lotus_core::*;
use lotus_services::content;
use lotus_services::{property_id, seed_if_fresh};

fn fresh(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("lotus_sp_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.log");
    let mut session = Session::open(&path).unwrap();
    seed_if_fresh(&mut session).unwrap();
    (path, session)
}

fn cleanup(path: &std::path::Path) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::remove_dir_all(dir);
    }
}

fn due_of(store: &Store, id: Id) -> Option<DateTime> {
    let due = property_id(store, "due")?;
    match store.get(id)?.get(due) {
        Some(Value::DateTime(d)) => Some(*d),
        _ => None,
    }
}

#[test]
fn a_span_parses_start_and_optional_end() {
    let (path, mut session) = fresh("parse");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();

    // A span: both sides date-only, end after start.
    content::set_property(&mut session, id, "due", "2026-07-11 -> 2026-07-13").unwrap();
    let d = due_of(session.store(), id).unwrap();
    assert!(d.date_only);
    assert_eq!(d.civil, DateTime::date(2026, 7, 11).civil);
    assert_eq!(d.end, Some(DateTime::date(2026, 7, 13).civil));

    // A plain date stays end-less.
    content::set_property(&mut session, id, "due", "2026-07-11").unwrap();
    assert_eq!(due_of(session.store(), id).unwrap().end, None);

    // Mixed date-only/timed sides are refused; so is a backwards span.
    assert!(content::set_property(&mut session, id, "due", "2026-07-11 -> 2026-07-13 10:00").is_err());
    assert!(content::set_property(&mut session, id, "due", "2026-07-13 -> 2026-07-11").is_err());
    cleanup(&path);
}

#[test]
fn a_span_edit_round_trips_start_and_end_across_reopen() {
    let (path, mut session) = fresh("reopen");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, id, "due", "2026-07-11 09:00 -> 2026-07-12 17:30").unwrap();
    let written = due_of(session.store(), id).unwrap();
    drop(session);

    // A fresh open replays the log from disk: civil ×2 + date_only survive.
    let session = Session::open(&path).unwrap();
    let read = due_of(session.store(), id).unwrap();
    assert_eq!(read, written);
    assert!(!read.date_only);
    assert_eq!(read.end, Some(DateTime::at(2026, 7, 12, 17, 30).civil));
    cleanup(&path);
}

#[test]
fn span_editing_is_one_command_one_undo() {
    let (path, mut session) = fresh("undo");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, id, "due", "2026-07-11").unwrap();
    let plain = due_of(session.store(), id).unwrap();
    let before = session.store().history().len();

    // Adding an end to the date is ONE transaction…
    content::set_property(&mut session, id, "due", "2026-07-11 -> 2026-07-14").unwrap();
    assert_eq!(session.store().history().len(), before + 1);
    assert!(due_of(session.store(), id).unwrap().end.is_some());

    // …so one undo restores the plain date.
    session.undo(Author::User).unwrap();
    assert_eq!(due_of(session.store(), id), Some(plain));
    cleanup(&path);
}

#[test]
fn cycling_a_span_keeps_its_end() {
    // §2.3 meets §3: the role moves, the whole value — end included — rides.
    let (path, mut session) = fresh("cycle");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, id, "due", "2026-07-11 -> 2026-07-13").unwrap();
    let store = session.store();
    let due = property_id(store, "due").unwrap();
    let date = property_id(store, "date").unwrap();
    let original = due_of(store, id).unwrap();

    let next = content::cycle_date_role(&mut session, id, due).unwrap();
    assert_eq!(next, date);
    match session.store().get(id).unwrap().get(date) {
        Some(Value::DateTime(d)) => assert_eq!(*d, original, "the end rode along"),
        other => panic!("expected the span on date, got {other:?}"),
    }
    cleanup(&path);
}
