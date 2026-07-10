//! P11/11e — display attributes (the V3 inspector's substrate: five
//! definitions, values are P11.5's call) and the usage-count / value-pool
//! service. Definitions are entities, so an attribute is ordinary data on a
//! property-definition entity — no core change anywhere here.

use lotus_core::*;
use lotus_services::content;
use lotus_services::{property_id, search, seed_if_fresh};

fn fresh(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("lotus_at_{name}"));
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

#[test]
fn display_attributes_seed_idempotent_and_land_on_an_old_box() {
    let (path, mut session) = fresh("seed");
    assert!(property_id(session.store(), "due").is_some(), "an old box has due");
    for (name, kind) in [
        ("icon", "text"),
        ("digit-key", "text"),
        ("hide-on-kind", "reference"),
        ("hide-when-empty", "bool"),
        ("core-on-kind", "reference"),
    ] {
        let id = property_id(session.store(), name).unwrap_or_else(|| panic!("{name} seeded"));
        match session.store().get(id).unwrap().get(props::VALUE_KIND) {
            Some(Value::Text(k)) => assert_eq!(k, kind, "{name} kind"),
            other => panic!("{name} has no kind, got {other:?}"),
        }
    }
    seed_if_fresh(&mut session).unwrap();
    let count = session
        .store()
        .entities()
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "icon")
                && matches!(e.get(props::VALUE_KIND), Some(Value::Text(_)))
        })
        .count();
    assert_eq!(count, 1);
    cleanup(&path);
}

#[test]
fn a_property_definition_carries_display_attributes_across_reopen() {
    // The attributes are cells ON the definition entity — set through the
    // ordinary seam, durable like any cell.
    let (path, mut session) = fresh("carry");
    let due = property_id(session.store(), "due").unwrap();
    content::set_property(&mut session, due, "icon", "i-flag").unwrap();
    content::set_property(&mut session, due, "digit-key", "d").unwrap();
    content::set_property(&mut session, due, "hide-when-empty", "true").unwrap();
    drop(session);

    let session = Session::open(&path).unwrap();
    let store = session.store();
    let def = store.get(due).unwrap();
    let icon = property_id(store, "icon").unwrap();
    let digit = property_id(store, "digit-key").unwrap();
    let hide = property_id(store, "hide-when-empty").unwrap();
    assert_eq!(def.get(icon), Some(&Value::text("i-flag")));
    assert_eq!(def.get(digit), Some(&Value::text("d")));
    assert_eq!(def.get(hide), Some(&Value::Bool(true)));
    cleanup(&path);
}

#[test]
fn hide_on_kind_is_per_kind() {
    // "name/type edits apply vault-wide; hide applies per kind" — the scope
    // rule is exactly definition cells vs hide-on-kind reference targets.
    let (path, mut session) = fresh("hidekind");
    let store = session.store();
    let due = property_id(store, "due").unwrap();
    let task = content::find_type(store, "task").unwrap();
    content::add_cell(&mut session, due, "hide-on-kind", &format!("#{task}")).unwrap();

    let store = session.store();
    let hide_on = property_id(store, "hide-on-kind").unwrap();
    let note = content::find_type(store, "note").unwrap();
    let def = store.get(due).unwrap();
    assert!(def.has(hide_on, &Value::Reference(task)), "hidden on task");
    assert!(!def.has(hide_on, &Value::Reference(note)), "not on note");
    cleanup(&path);
}

#[test]
fn usage_count_counts_live_entities_carrying_a_property() {
    let (path, mut session) = fresh("usage");
    let a = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    let b = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    let _bare = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, a, "due", "2026-07-11").unwrap();
    content::set_property(&mut session, b, "due", "2026-07-12").unwrap();

    let store = session.store();
    let due = property_id(store, "due").unwrap();
    let count = |store: &Store| {
        search::usage_counts(store)
            .into_iter()
            .find(|(id, _)| *id == due)
            .map(|(_, c)| c)
            .unwrap_or(0)
    };
    assert_eq!(count(store), 2, "two live carriers");

    // Trash one: the count follows the live set.
    content::trash_workspace(&mut session, a).unwrap();
    assert_eq!(count(session.store()), 1, "trash leaves the live set");
    cleanup(&path);
}

#[test]
fn usage_count_of_an_unused_property_is_zero() {
    let (path, session) = fresh("zero");
    let store = session.store();
    let location = property_id(store, "location").unwrap();
    let usage = search::usage_counts(store);
    assert_eq!(
        usage.iter().find(|(id, _)| *id == location).map(|(_, c)| *c),
        Some(0),
        "an unused property appears with zero — the picker still offers it"
    );
    cleanup(&path);
}

#[test]
fn distinct_values_lists_each_value_once_with_counts_deterministically() {
    let (path, mut session) = fresh("distinct");
    let mut tasks = Vec::new();
    for _ in 0..4 {
        tasks.push(content::create_task(&mut session, DateTime::date(2026, 7, 10)).unwrap());
    }
    for id in &tasks[..3] {
        content::set_property(&mut session, *id, "priority", "high").unwrap();
    }
    content::set_property(&mut session, tasks[3], "priority", "low").unwrap();

    let store = session.store();
    let priority = property_id(store, "priority").unwrap();
    let first = search::distinct_values(store, priority);
    assert_eq!(first.len(), 2, "each value once");
    assert_eq!(first[0].1, 3, "count desc: high first");
    assert_eq!(first[1].1, 1);
    let again = search::distinct_values(store, priority);
    assert_eq!(first, again, "deterministic order");
    cleanup(&path);
}

#[test]
fn a_status_options_usage_count_drives_the_picker() {
    let (path, mut session) = fresh("picker");
    let mut tasks = Vec::new();
    for _ in 0..3 {
        tasks.push(content::create_task(&mut session, DateTime::date(2026, 7, 10)).unwrap());
    }
    content::set_property(&mut session, tasks[2], "status", "done").unwrap();

    let store = session.store();
    let status = property_id(store, "status").unwrap();
    let todo = content::find_option(store, status, "todo").unwrap();
    let done = content::find_option(store, status, "done").unwrap();
    let pool = search::distinct_values(store, status);
    assert_eq!(pool[0], (Value::Select(todo), 2), "todo carries two");
    assert_eq!(pool[1], (Value::Select(done), 1), "done carries one");
    cleanup(&path);
}
