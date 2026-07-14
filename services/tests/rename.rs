//! The rename engine (P19b): one vault-wide value rename = ONE grouped
//! transaction, one undo, merge-on-collision, kind discipline, and a torn
//! tail replays to the pre-rename state. The phase's one required verb.

use lotus_core::*;
use lotus_services::{content, property_id};

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("lotus_rename_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn cleanup(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

fn capture(session: &mut Session, text: &str) -> Id {
    lotus_services::capture(session, text, DateTime::at(2026, 7, 15, 9, 0)).unwrap()
}

fn text_value(store: &Store, id: Id, prop: Id) -> Option<String> {
    match store.get(id)?.get(prop) {
        Some(Value::Text(t)) => Some(t.clone()),
        _ => None,
    }
}

#[test]
fn text_rename_rewrites_every_carrier_in_one_transaction() {
    let (mut session, path) = boxed("text");
    let tag = content::birth_property(&mut session, "tag", "text").unwrap();
    let carriers: Vec<Id> = (0..21).map(|i| capture(&mut session, &format!("note {i}"))).collect();
    for id in &carriers {
        content::set_property(&mut session, *id, "tag", "draft").unwrap();
    }
    // A decoy that must NOT change.
    let decoy = capture(&mut session, "decoy");
    content::set_property(&mut session, decoy, "tag", "final").unwrap();

    let count = content::rename_value(&mut session, "tag", "draft", "sketch").unwrap();
    assert_eq!(count, 21);
    let store = session.store();
    for id in &carriers {
        assert_eq!(text_value(store, *id, tag).as_deref(), Some("sketch"));
    }
    assert_eq!(text_value(store, decoy, tag).as_deref(), Some("final"));

    // ONE undo restores every carrier byte-identically.
    session.undo(Author::User).unwrap();
    let store = session.store();
    for id in &carriers {
        assert_eq!(text_value(store, *id, tag).as_deref(), Some("draft"));
    }

    cleanup(&path);
}

#[test]
fn select_rename_renames_the_option_and_merge_repoints_carriers() {
    let (mut session, path) = boxed("select");
    let flavor = content::birth_property(&mut session, "flavor", "select").unwrap();
    let vanilla = content::add_option(&mut session, flavor, "vanilla").unwrap();
    let chocolate = content::add_option(&mut session, flavor, "chocolate").unwrap();

    let a = capture(&mut session, "a");
    let b = capture(&mut session, "b");
    let c = capture(&mut session, "c");
    content::set_property(&mut session, a, "flavor", "vanilla").unwrap();
    content::set_property(&mut session, b, "flavor", "vanilla").unwrap();
    content::set_property(&mut session, c, "flavor", "chocolate").unwrap();

    // Plain rename: the OPTION renames; carriers keep their references.
    let count = content::rename_value(&mut session, "flavor", "vanilla", "hazelnut").unwrap();
    assert_eq!(count, 2, "reports the carriers");
    let store = session.store();
    assert!(matches!(store.get(vanilla).unwrap().get(props::NAME),
        Some(Value::Text(n)) if n == "hazelnut"));
    assert!(store.get(a).unwrap().has(flavor, &Value::Select(vanilla)));

    // MERGE on collision: carriers repoint to the existing option; the loser
    // option is trashed; one commit.
    let count = content::rename_value(&mut session, "flavor", "hazelnut", "chocolate").unwrap();
    assert_eq!(count, 2);
    let store = session.store();
    assert!(store.get(a).unwrap().has(flavor, &Value::Select(chocolate)));
    assert!(store.get(b).unwrap().has(flavor, &Value::Select(chocolate)));
    assert!(store.get(vanilla).unwrap().trashed, "the merged-away option is trashed");

    // ONE undo un-merges wholesale: carriers back on the old option, alive.
    session.undo(Author::User).unwrap();
    let store = session.store();
    assert!(store.get(a).unwrap().has(flavor, &Value::Select(vanilla)));
    assert!(!store.get(vanilla).unwrap().trashed);

    cleanup(&path);
}

#[test]
fn kind_discipline_refuses_dates_and_references() {
    let (mut session, path) = boxed("discipline");
    assert!(content::rename_value(&mut session, "due", "20260715", "20260716").is_err());
    assert!(content::rename_value(&mut session, "related", "#12", "#13").is_err());
    assert!(content::rename_value(&mut session, "no-such-prop", "a", "b").is_err());
    // Old == new and empty new are refusals, not no-ops.
    let _ = content::birth_property(&mut session, "tag", "text").unwrap();
    assert!(content::rename_value(&mut session, "tag", "same", "same").is_err());
    assert!(content::rename_value(&mut session, "tag", "x", "  ").is_err());
    cleanup(&path);
}

#[test]
fn a_torn_tail_replays_to_the_pre_rename_state() {
    let (mut session, path) = boxed("torn");
    let tag = content::birth_property(&mut session, "tag", "text").unwrap();
    let a = capture(&mut session, "a");
    content::set_property(&mut session, a, "tag", "old").unwrap();
    drop(session);
    let before = std::fs::metadata(&path).unwrap().len();

    let mut session = Session::open(&path).unwrap();
    content::rename_value(&mut session, "tag", "old", "new").unwrap();
    drop(session);

    // Crash injection: the rename's record is torn mid-write. The loader
    // drops the torn tail — the box replays to exactly the pre-rename state.
    let file = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
    file.set_len(before + 7).unwrap();
    drop(file);
    let session = Session::open(&path).unwrap();
    assert_eq!(text_value(session.store(), a, tag).as_deref(), Some("old"));

    cleanup(&path);
}
