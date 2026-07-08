//! P10/10a — an event is a `create_task` twin that writes a `due` at birth, so
//! it lands on the calendar by property-based positioning (it appears because
//! it has a `due`, not because of its type). Birth is minimal: no
//! location/attendees/notes, no status — those are set after birth.

use lotus_core::*;
use lotus_services::{content, property_id, seed_if_fresh};

fn fresh(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("lotus_ev_{name}"));
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

fn named(store: &Store, id: Id) -> Option<String> {
    match store.get(id)?.get(props::NAME) {
        Some(Value::Text(n)) => Some(n.clone()),
        _ => None,
    }
}

#[test]
fn create_event_is_typed_dued_and_minimal() {
    let (path, mut session) = fresh("create");
    let due = DateTime::at(2026, 7, 9, 9, 0);
    let id = content::create_event(&mut session, due, DateTime::date(2026, 7, 8)).unwrap();
    let store = session.store();
    let e = store.get(id).unwrap();

    // Typed `event`, so property-based positioning draws it on the calendar.
    match e.get(props::TYPE) {
        Some(Value::Reference(t)) => assert_eq!(named(store, *t).as_deref(), Some("event")),
        other => panic!("expected type=event, got {other:?}"),
    }
    // The clicked time rides the due, timed (not all-day).
    let due_prop = property_id(store, "due").unwrap();
    match e.get(due_prop) {
        Some(Value::DateTime(d)) => {
            assert_eq!(d.civil, due.civil);
            assert!(!d.date_only, "a timed event keeps date_only=false");
        }
        other => panic!("expected a due datetime, got {other:?}"),
    }
    // Born minimal: created present, but no name and no status.
    assert!(e.get(props::CREATED).is_some());
    assert!(named(store, id).is_none(), "born nameless — the caller renames");
    if let Some(status) = property_id(store, "status") {
        assert!(e.get(status).is_none(), "an event is not a task; no status at birth");
    }
    cleanup(&path);
}

#[test]
fn an_all_day_event_keeps_the_date_only_bit() {
    let (path, mut session) = fresh("allday");
    let id = content::create_event(&mut session, DateTime::date(2026, 7, 9), DateTime::date(2026, 7, 8))
        .unwrap();
    let store = session.store();
    let due_prop = property_id(store, "due").unwrap();
    match store.get(id).unwrap().get(due_prop) {
        Some(Value::DateTime(d)) => assert!(d.date_only, "an all-day event's due is date_only"),
        other => panic!("expected a due datetime, got {other:?}"),
    }
    cleanup(&path);
}

#[test]
fn event_fields_seed_alongside_due_and_are_idempotent() {
    let (path, mut session) = fresh("fields");
    // They land even though `due` already exists — a SEPARATE additive guard,
    // not the starter-library due-guard that short-circuits on every box.
    assert!(property_id(session.store(), "due").is_some());
    assert!(property_id(session.store(), "location").is_some());
    assert!(property_id(session.store(), "attendees").is_some());

    // Idempotent across reopens: exactly one property of each name.
    seed_if_fresh(&mut session).unwrap();
    let count = |name: &str| {
        session
            .store()
            .entities()
            .filter(|e| {
                matches!(e.get(props::NAME), Some(Value::Text(n)) if n == name)
                    && matches!(e.get(props::VALUE_KIND), Some(Value::Text(_)))
            })
            .count()
    };
    assert_eq!(count("location"), 1, "one location property");
    assert_eq!(count("attendees"), 1, "one attendees property");
    cleanup(&path);
}

#[test]
fn the_event_type_still_expects_only_due() {
    // create_event must not touch the event type's expectations: location and
    // attendees (10b) are offered by the calendar, never expected.
    let (path, mut session) = fresh("expect");
    content::create_event(&mut session, DateTime::at(2026, 7, 9, 9, 0), DateTime::date(2026, 7, 8))
        .unwrap();
    let store = session.store();
    let event_type = content::find_type(store, "event").expect("event type is seeded");
    let due_prop = property_id(store, "due").unwrap();
    let expected: Vec<Id> = store
        .get(event_type)
        .unwrap()
        .all(props::EXPECTED)
        .filter_map(|v| match v {
            Value::Reference(p) => Some(*p),
            _ => None,
        })
        .collect();
    assert_eq!(expected, vec![due_prop], "the event type expects exactly [due]");
    cleanup(&path);
}
