//! Layers (P17i): a workspace layout snapshot as a small backstage entity —
//! a NAME + ordered `related` members (the tabs to reopen) + a workspace
//! scope. Restore is pure shell (mutates nothing in the log); the only log
//! writes are create/rename/delete of the layer itself.

use liv_core::*;
use liv_services::{content, property_id};

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("liv_layers_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    liv_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn cleanup(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

fn capture(session: &mut Session, text: &str) -> Id {
    liv_services::capture(session, text, DateTime::at(2026, 7, 14, 10, 0)).unwrap()
}

#[test]
fn layer_births_backstage_with_ordered_members_in_one_commit() {
    let (mut session, path) = boxed("birth");
    let a = capture(&mut session, "alpha");
    let b = capture(&mut session, "beta");

    let layer = content::create_layer(
        &mut session,
        "Writing set",
        None,
        &[b, a],
        DateTime::at(2026, 7, 14, 10, 0),
    )
    .unwrap();
    assert_ne!(layer, 0);

    let store = session.store();
    let entity = store.get(layer).expect("layer exists");
    assert!(entity.has(props::WORKING, &Value::Bool(true)), "backstage — never in Everything");
    assert!(matches!(entity.get(props::NAME), Some(Value::Text(n)) if n == "Writing set"));
    let layer_type = content::find_type(store, "layer").expect("layer type seeded");
    assert!(entity.has(props::TYPE, &Value::Reference(layer_type)));

    // Members are ordered `related` cells — b first, then a, as saved.
    let related = property_id(store, "related").unwrap();
    let members: Vec<Id> = entity
        .cells
        .iter()
        .filter(|c| c.property == related)
        .filter_map(|c| match &c.value {
            Value::Reference(id) => Some(*id),
            _ => None,
        })
        .collect();
    assert_eq!(members, vec![b, a]);

    // ONE transaction: a single undo unwinds the whole save.
    session.undo(Author::User).unwrap();
    let gone = session.store().get(layer).map(|e| e.trashed) != Some(false);
    assert!(gone, "one undo removes the layer entirely");

    cleanup(&path);
}

#[test]
fn layer_scopes_to_a_workspace() {
    let (mut session, path) = boxed("scope");
    let note = capture(&mut session, "scoped");
    let workspace =
        content::create_workspace(&mut session, "Studies", None, DateTime::at(2026, 7, 14, 10, 0))
            .unwrap();

    let layer = content::create_layer(
        &mut session,
        "Desk",
        Some(workspace),
        &[note],
        DateTime::at(2026, 7, 14, 10, 1),
    )
    .unwrap();

    let store = session.store();
    let ws_prop = property_id(store, "workspace").expect("workspace property");
    assert!(store.get(layer).unwrap().has(ws_prop, &Value::Reference(workspace)));

    cleanup(&path);
}
