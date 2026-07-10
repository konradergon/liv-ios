//! P11/11a — role-typed dates (the amended spine, R1). A role is a seeded
//! PROPERTY, not a value attribute: `date` positions on the calendar beside
//! `due`; `valid-until` / `occurred` / `purchased-on` are lookup roles —
//! filterable facts that never render as appointments. Space-cycling a role
//! is one lossless transaction moving the value between properties.

use lotus_core::*;
use lotus_services::content::{self, WriteError};
use lotus_services::{calendar_set, property_id, search, seed_if_fresh, today_sections};

fn fresh(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("lotus_dr_{name}"));
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

fn datetime_of(store: &Store, id: Id, prop: Id) -> Option<DateTime> {
    match store.get(id)?.get(prop) {
        Some(Value::DateTime(d)) => Some(*d),
        _ => None,
    }
}

#[test]
fn the_four_date_roles_seed_beside_due_and_are_idempotent() {
    let (path, mut session) = fresh("seed");
    // All four land even though `due` already exists — a SEPARATE additive
    // guard, never an edit inside the starter library's due-guard.
    assert!(property_id(session.store(), "due").is_some());
    for role in ["date", "valid-until", "occurred", "purchased-on"] {
        let id = property_id(session.store(), role)
            .unwrap_or_else(|| panic!("{role} is seeded"));
        match session.store().get(id).unwrap().get(props::VALUE_KIND) {
            Some(Value::Text(kind)) => assert_eq!(kind, "datetime", "{role} is a datetime"),
            other => panic!("{role} has no kind, got {other:?}"),
        }
    }

    // Idempotent: a second open seeds nothing again.
    seed_if_fresh(&mut session).unwrap();
    for role in ["date", "valid-until", "occurred", "purchased-on"] {
        let count = session
            .store()
            .entities()
            .filter(|e| {
                matches!(e.get(props::NAME), Some(Value::Text(n)) if n == role)
                    && matches!(e.get(props::VALUE_KIND), Some(Value::Text(_)))
            })
            .count();
        assert_eq!(count, 1, "exactly one {role} definition");
    }
    cleanup(&path);
}

#[test]
fn the_calendar_positioning_set_is_date_and_due_only() {
    let (path, session) = fresh("posset");
    let store = session.store();
    let date = property_id(store, "date").unwrap();
    let due = property_id(store, "due").unwrap();
    // `date` before `due` — the anchor and display precedence. Lookup roles
    // are absent by exact equality, and that absence IS the off-calendar rule.
    assert_eq!(calendar_set(store), vec![date, due]);
    cleanup(&path);
}

#[test]
fn a_lookup_role_date_is_filter_only_never_positioned() {
    let (path, mut session) = fresh("lookup");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, id, "occurred", "2026-07-09").unwrap();

    // Not in Today's due section on its own date. (Today reads `due` by
    // construction, so alone this would be vacuous — the real positioning
    // pin, absence from the snapshot's `dated`, lives at the FFI:
    // a_lookup_role_only_entity_stays_off_dated.)
    let sections = today_sections(session.store(), DateTime::date(2026, 7, 9));
    assert!(!sections.due.contains(&id), "occurred never positions an entity");

    // …but found as a filterable fact through the ordinary qualifier seam.
    let q = search::parse(session.store(), "occurred<2027-01-01");
    let hits = search::search(session.store(), &q, 200, |_| String::new());
    assert!(hits.iter().any(|h| h.id == id), "occurred<… finds it");
    cleanup(&path);
}

#[test]
fn an_entity_may_carry_several_date_rows_at_once() {
    // bp9 #28: `last seen` (occurred) and a calendar date coexist — the
    // roles are independent rows, never one slot.
    let (path, mut session) = fresh("multi");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, id, "due", "2026-07-11 09:00").unwrap();
    content::set_property(&mut session, id, "valid-until", "2027-01-01").unwrap();
    content::set_property(&mut session, id, "occurred", "2026-07-01").unwrap();
    let store = session.store();
    for role in ["due", "valid-until", "occurred"] {
        let prop = property_id(store, role).unwrap();
        assert!(datetime_of(store, id, prop).is_some(), "{role} is present");
    }
    cleanup(&path);
}

#[test]
fn space_cycles_the_role_as_one_transaction_moving_the_value() {
    let (path, mut session) = fresh("cycle");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, id, "due", "2026-07-11 09:00").unwrap();
    let store = session.store();
    let due = property_id(store, "due").unwrap();
    let date = property_id(store, "date").unwrap();
    let original = datetime_of(store, id, due).unwrap();
    let before = store.history().len();

    let next = content::cycle_date_role(&mut session, id, due).unwrap();
    assert_eq!(next, date, "due cycles to date");

    let store = session.store();
    assert_eq!(store.history().len(), before + 1, "one transaction");
    assert!(datetime_of(store, id, due).is_none(), "the due cell is gone");
    assert_eq!(datetime_of(store, id, date), Some(original), "the value moved intact");
    cleanup(&path);
}

#[test]
fn role_cycling_is_lossless_round_trip() {
    // The full ring back to origin: due → date → valid-until → occurred →
    // purchased-on → due, with civil AND the date_only bit identical.
    let (path, mut session) = fresh("ring");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, id, "due", "2026-07-11 09:00").unwrap();
    let due = property_id(session.store(), "due").unwrap();
    let original = datetime_of(session.store(), id, due).unwrap();
    assert!(!original.date_only, "a timed date exercises the whole value");

    let mut from = due;
    for _ in 0..5 {
        from = content::cycle_date_role(&mut session, id, from).unwrap();
    }
    assert_eq!(from, due, "five cycles close the ring");
    assert_eq!(datetime_of(session.store(), id, due), Some(original), "lossless");
    cleanup(&path);
}

#[test]
fn cycling_refuses_when_the_target_role_is_occupied() {
    // Cycling never merges or clobbers a sibling date row (bp9 #28).
    let (path, mut session) = fresh("occupied");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, id, "due", "2026-07-11").unwrap();
    content::set_property(&mut session, id, "date", "2026-07-12").unwrap();
    let store = session.store();
    let due = property_id(store, "due").unwrap();
    let date = property_id(store, "date").unwrap();
    let before = store.history().len();

    match content::cycle_date_role(&mut session, id, due) {
        Err(WriteError::Refused(_)) => {}
        other => panic!("expected a refusal, got {other:?}"),
    }
    let store = session.store();
    assert_eq!(store.history().len(), before, "the store is untouched");
    assert!(datetime_of(store, id, due).is_some(), "due survives");
    assert!(datetime_of(store, id, date).is_some(), "date survives");

    // And a cycle with no date cell at all is refused the same way.
    let bare = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    assert!(matches!(
        content::cycle_date_role(&mut session, bare, due),
        Err(WriteError::Refused(_))
    ));
    cleanup(&path);
}

#[test]
fn cycling_refuses_on_a_multi_valued_date_row() {
    // A merge can leave two cells on one date property. The FFI addresses a
    // cycle by (entity, property) only, so "which of the two moves" would be
    // ambiguous — refuse, never guess (the review's finding).
    let (path, mut session) = fresh("multicell");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::add_cell(&mut session, id, "due", "2026-07-11").unwrap();
    content::add_cell(&mut session, id, "due", "2026-07-12").unwrap();
    let store = session.store();
    let due = property_id(store, "due").unwrap();
    assert_eq!(store.get(id).unwrap().all(due).count(), 2, "two due cells");
    let before = store.history().len();

    match content::cycle_date_role(&mut session, id, due) {
        Err(WriteError::Refused(_)) => {}
        other => panic!("expected a refusal, got {other:?}"),
    }
    let store = session.store();
    assert_eq!(store.history().len(), before, "the store is untouched");
    assert_eq!(store.get(id).unwrap().all(due).count(), 2, "both cells survive");
    cleanup(&path);
}
