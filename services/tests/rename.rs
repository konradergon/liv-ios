//! The rename engine (P19b): one vault-wide value rename = ONE grouped
//! transaction, one undo, merge-on-collision, kind discipline, and a torn
//! tail replays to the pre-rename state. The phase's one required verb.

use liv_core::*;
use liv_services::content;

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("liv_rename_{name}.log"));
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
    liv_services::capture(session, text, DateTime::at(2026, 7, 15, 9, 0)).unwrap()
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
    let (vanilla, created) = content::add_option(&mut session, flavor, "vanilla").unwrap();
    assert!(created);
    let (chocolate, _) = content::add_option(&mut session, flavor, "chocolate").unwrap();

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
    let (mut session, path) = boxed("optguard");
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

#[test]
fn ambiguous_same_named_options_refuse_to_rename() {
    // Per-kind same-named options are the DESIGNED state of `status`
    // (add_status_option scopes by for-type, no cross-kind dedup) — a rename
    // keyed only by name cannot pick one, so it must refuse, never guess.
    let (mut session, path) = boxed("ambiguous");
    let flavor = content::birth_property(&mut session, "flavor", "select").unwrap();
    let (first, _) = content::add_option(&mut session, flavor, "done").unwrap();
    // A second option of the SAME name, minted through the raw door the way
    // add_status_option does for another kind.
    let second = session.allocate_id();
    session
        .commit(
            vec![
                Command::Create { entity: second },
                Command::AddCell {
                    entity: second,
                    cell: Cell { property: props::NAME, value: Value::text("done") },
                },
                Command::AddCell {
                    entity: second,
                    cell: Cell { property: props::WORKING, value: Value::Bool(true) },
                },
                Command::AddCell {
                    entity: flavor,
                    cell: Cell { property: props::OPTIONS, value: Value::Reference(second) },
                },
            ],
            "second done",
            Author::User,
        )
        .unwrap();

    assert!(
        content::rename_value(&mut session, "flavor", "done", "archived").is_err(),
        "an ambiguous old name must refuse"
    );
    // Ambiguous MERGE TARGET refuses too.
    let _ = content::add_option(&mut session, flavor, "solo").unwrap().0;
    assert!(
        content::rename_value(&mut session, "flavor", "solo", "done").is_err(),
        "an ambiguous merge target must refuse"
    );
    // Neither option was touched.
    let store = session.store();
    let named: Vec<&str> = [first, second]
        .iter()
        .filter_map(|id| match store.get(*id)?.get(props::NAME) {
            Some(Value::Text(n)) => Some(n.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(named, ["done", "done"]);
    cleanup(&path);
}

#[test]
fn text_rename_skips_backstage_plumbing() {
    // rename_value("name", …) must never rewrite WORKING entities: options,
    // types, and definitions are name-keyed plumbing, not carriers.
    let (mut session, path) = boxed("plumbing");
    let ws = content::create_workspace(&mut session, "todo", None, DateTime::at(2026, 7, 15, 9, 0))
        .unwrap();
    let count = content::rename_value(&mut session, "name", "todo", "someday-maybe").unwrap();
    let store = session.store();
    // The seeded `todo` STATUS OPTION kept its name — status resolution
    // (todo_option, default-status) survives.
    let status = liv_services::property_id(store, "status").unwrap();
    assert!(
        liv_services::content::find_option(store, status, "todo").is_some(),
        "the rename rewrote the seeded todo option's name"
    );
    // The workspace is WORKING plumbing too (excluded from Everything) and
    // has its own rename door — the vocabulary rename leaves it alone. No
    // front-of-house `name` carriers exist here, so the count is zero.
    // (Real carriers still rewrite: see text_rename_rewrites_every_carrier.)
    assert_eq!(count, 0);
    assert!(matches!(
        store.get(ws).unwrap().get(props::NAME),
        Some(Value::Text(n)) if n == "todo"
    ));
    cleanup(&path);
}

#[test]
fn add_option_enforces_kind_discipline() {
    let (mut session, path) = boxed("discipline");
    // Not a select: refuse.
    let notes = content::birth_property(&mut session, "notes", "text").unwrap();
    assert!(content::add_option(&mut session, notes, "x").is_err());
    // A trashed definition: refuse (store.get returns Some for trashed —
    // the standing gotcha).
    let flavor = content::birth_property(&mut session, "flavor", "select").unwrap();
    session
        .commit(vec![Command::Trash { entity: flavor }], "trash def", Author::User)
        .unwrap();
    assert!(content::add_option(&mut session, flavor, "x").is_err());
    cleanup(&path);
}

#[test]
fn kind_flags_accumulate_per_kind() {
    // P19 review: `set_property` replaces every cell of a property, so
    // hiding a definition on a SECOND kind silently un-hid the first. The
    // kind-flag door toggles ONE kind's reference cell, leaving the rest.
    let (mut session, path) = boxed("kindflag");
    let tag = content::birth_property(&mut session, "tag", "text").unwrap();
    let store = session.store();
    let task = store
        .entities()
        .find(|e| {
            e.has(props::WORKING, &Value::Bool(true))
                && matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "task")
                && e.get(props::EXPECTED).is_some()
        })
        .map(|e| e.id)
        .unwrap();
    let note = store
        .entities()
        .find(|e| {
            e.has(props::WORKING, &Value::Bool(true))
                && matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "note")
                && e.get(props::EXPECTED).is_some()
        })
        .map(|e| e.id)
        .unwrap();

    let hide_prop = liv_services::property_id(session.store(), "hide-on-kind").unwrap();
    let refs = |session: &Session| -> usize {
        session
            .store()
            .get(tag)
            .map(|e| e.all(hide_prop).count())
            .unwrap_or(0)
    };

    assert!(content::toggle_kind_ref(&mut session, tag, "hide-on-kind", task, true).unwrap());
    assert!(content::toggle_kind_ref(&mut session, tag, "hide-on-kind", note, true).unwrap());
    assert_eq!(refs(&session), 2, "the second kind must not evict the first");
    // Idempotent on, then a real off — one cell leaves, one stays.
    assert!(!content::toggle_kind_ref(&mut session, tag, "hide-on-kind", task, true).unwrap());
    assert_eq!(refs(&session), 2);
    assert!(content::toggle_kind_ref(&mut session, tag, "hide-on-kind", task, false).unwrap());
    assert_eq!(refs(&session), 1);
    // Kind discipline: only reference-kind plumbing takes kind flags.
    assert!(content::toggle_kind_ref(&mut session, tag, "tag", task, true).is_err());
    cleanup(&path);
}
