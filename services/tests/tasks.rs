//! P8/8a — the task surface's substrate: a seeded `priority` select that
//! lands even on a box that already has `due`, and `create_task` — a typed,
//! already-`todo` birth distinct from an untyped capture.

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

/// The type entity for a kind (a working entity named `name`, not a property).
fn type_of(store: &Store, name: &str) -> Id {
    store
        .entities()
        .find(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == name)
                && e.get(props::VALUE_KIND).is_none()
        })
        .map(|e| e.id)
        .unwrap_or_else(|| panic!("no {name} type"))
}

#[test]
fn priority_is_seeded_alongside_due_and_is_idempotent() {
    let (path, mut session) = fresh("tasks_priority");
    // `due` (starter library) and `priority` (its own separately-guarded
    // pass) both land — the pass is NOT gated behind the starter library's
    // `due` short-circuit.
    assert!(property_id(session.store(), "due").is_some());
    let priority = property_id(session.store(), "priority").expect("priority is seeded");

    let options: Vec<String> = session
        .store()
        .get(priority)
        .unwrap()
        .all(props::OPTIONS)
        .filter_map(|v| match v {
            Value::Reference(t) => named(session.store(), *t),
            _ => None,
        })
        .collect();
    assert_eq!(options.len(), 3);
    assert!(options.iter().any(|o| o == "high"));

    // Re-opening (which re-runs the seed) must not duplicate it.
    seed_if_fresh(&mut session).unwrap();
    assert_eq!(property_id(session.store(), "priority"), Some(priority));
    let defs = session
        .store()
        .entities()
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "priority")
                && e.get(props::VALUE_KIND).is_some()
        })
        .count();
    assert_eq!(defs, 1);
    cleanup(&path);
}

#[test]
fn create_task_is_a_typed_todo_with_no_priority_or_due() {
    let (path, mut session) = fresh("tasks_create");
    let id = content::create_task(&mut session, DateTime::date(2026, 7, 7)).unwrap();
    let store = session.store();
    let e = store.get(id).unwrap();

    // type = the task type
    match e.get(props::TYPE) {
        Some(Value::Reference(t)) => assert_eq!(named(store, *t).as_deref(), Some("task")),
        other => panic!("expected type=task, got {other:?}"),
    }
    // status = a Select of the "todo" option (not a bare Reference)
    let status = property_id(store, "status").unwrap();
    match e.get(status) {
        Some(Value::Select(opt)) => assert_eq!(named(store, *opt).as_deref(), Some("todo")),
        other => panic!("expected status=Select(todo), got {other:?}"),
    }
    // no priority, no due at birth
    assert!(e.get(property_id(store, "priority").unwrap()).is_none());
    assert!(e.get(property_id(store, "due").unwrap()).is_none());
    assert!(e.get(props::CREATED).is_some());
    cleanup(&path);
}

#[test]
fn priority_is_offered_not_expected_by_the_task_type() {
    let (path, session) = fresh("tasks_expect");
    let store = session.store();
    let priority = property_id(store, "priority").unwrap();
    let expects: Vec<Id> = store
        .get(type_of(store, "task"))
        .unwrap()
        .all(props::EXPECTED)
        .filter_map(|v| match v {
            Value::Reference(p) => Some(*p),
            _ => None,
        })
        .collect();
    // The task type expects status + due; priority is offered, never expected.
    assert!(!expects.contains(&priority), "priority must not be an expectation");
    cleanup(&path);
}
