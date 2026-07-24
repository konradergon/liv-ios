//! P9/9a — a list is an entity of type=list whose ordered `related` cells
//! ARE its members; membership is tagging (add-one / remove-one), never a
//! delete of the member.

use liv_core::*;
use liv_services::{content, property_id, seed_if_fresh};

fn fresh(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("liv_t_{name}"));
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

fn type_of(store: &Store, name: &str) -> Option<Id> {
    store
        .entities()
        .find(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == name)
                && e.get(props::VALUE_KIND).is_none()
        })
        .map(|e| e.id)
}

fn members(store: &Store, list: Id) -> Vec<Id> {
    let related = property_id(store, "related").unwrap();
    store
        .get(list)
        .unwrap()
        .all(related)
        .filter_map(|v| match v {
            Value::Reference(m) => Some(*m),
            _ => None,
        })
        .collect()
}

#[test]
fn the_list_type_is_seeded_alongside_due_and_is_idempotent() {
    let (path, mut session) = fresh("lists_seed");
    // Lands even though `due` already exists (the separate additive guard).
    assert!(property_id(session.store(), "due").is_some());
    let list_type = type_of(session.store(), "list").expect("list type seeded");

    seed_if_fresh(&mut session).unwrap();
    assert_eq!(type_of(session.store(), "list"), Some(list_type));
    let count = session
        .store()
        .entities()
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "list")
                && e.get(props::VALUE_KIND).is_none()
        })
        .count();
    assert_eq!(count, 1);
    cleanup(&path);
}

#[test]
fn create_list_is_named_typed_and_empty() {
    let (path, mut session) = fresh("lists_create");
    let id = content::create_list(&mut session, "Reading queue", DateTime::date(2026, 7, 8)).unwrap();
    let store = session.store();
    let e = store.get(id).unwrap();
    assert_eq!(e.get(props::NAME), Some(&Value::text("Reading queue")));
    match e.get(props::TYPE) {
        Some(Value::Reference(t)) => assert_eq!(named(store, *t).as_deref(), Some("list")),
        other => panic!("expected type=list, got {other:?}"),
    }
    assert!(members(store, id).is_empty(), "a fresh list has no members");
    cleanup(&path);
}

#[test]
fn membership_is_tagging_ordered_deduped_and_never_deletes() {
    let (path, mut session) = fresh("lists_member");
    let list = content::create_list(&mut session, "L", DateTime::date(2026, 7, 8)).unwrap();
    let a = content::create_note(&mut session, DateTime::date(2026, 7, 8)).unwrap();
    let b = content::create_note(&mut session, DateTime::date(2026, 7, 8)).unwrap();

    // Add a then b — members follow insertion (log) order.
    content::add_cell(&mut session, list, "related", &format!("#{a}")).unwrap();
    content::add_cell(&mut session, list, "related", &format!("#{b}")).unwrap();
    assert_eq!(members(session.store(), list), vec![a, b]);

    // Adding a again is a silent no-op — the member set never doubles.
    content::add_cell(&mut session, list, "related", &format!("#{a}")).unwrap();
    assert_eq!(members(session.store(), list), vec![a, b]);

    // Removing a member removes exactly that cell; b stays, and a — the
    // object — survives (removing membership never deletes).
    content::remove_cell(&mut session, list, "related", &format!("#{a}")).unwrap();
    assert_eq!(members(session.store(), list), vec![b]);
    assert!(session.store().get(a).is_some(), "un-tagging never deletes the member");

    // Removing a non-member is a no-op, not an error.
    content::remove_cell(&mut session, list, "related", &format!("#{a}")).unwrap();
    assert_eq!(members(session.store(), list), vec![b]);

    // A membership to a nonexistent entity is refused (reference validation).
    assert!(content::add_cell(&mut session, list, "related", "#999999").is_err());
    cleanup(&path);
}

#[test]
fn a_list_cannot_be_its_own_member() {
    let (path, mut session) = fresh("lists_selfref");
    let l = content::create_list(&mut session, "L", DateTime::date(2026, 7, 8)).unwrap();
    // A self-reference is refused — a list may not be its own member (the same
    // guard the clerk's `related` proposer applies).
    assert!(content::add_cell(&mut session, l, "related", &format!("#{l}")).is_err());
    assert!(members(session.store(), l).is_empty(), "nothing was tagged");
    // remove stays open, so a pre-existing self-ref could still be cleared
    // (a no-op here, since none was added) — and it must not error.
    assert!(content::remove_cell(&mut session, l, "related", &format!("#{l}")).is_ok());
    cleanup(&path);
}
