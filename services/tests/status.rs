//! P11/11d — universal status (R2, R6 as recorded in the design §5): ONE
//! `status` definition; the option entities it already references gain
//! `for-type` scoping (union namespace, per-kind offer), board `order`, a
//! `hue`, and a `completes` done-marker. The entry default is a cell on the
//! type. No kind is forced a status — absence stays always-valid.

use liv_core::*;
use liv_services::content::{self, find_type};
use liv_services::{property_id, search, seed_if_fresh, status_options_for};

fn fresh(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("liv_st_{name}"));
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
fn status_scoping_seeds_idempotent_and_lands_on_a_box_that_already_has_due() {
    let (path, mut session) = fresh("seed");
    // Lands beside the existing vocabulary — a SEPARATE additive guard.
    assert!(property_id(session.store(), "due").is_some());
    for prop in ["for-type", "hue", "completes", "default-status"] {
        assert!(property_id(session.store(), prop).is_some(), "{prop} is seeded");
    }
    seed_if_fresh(&mut session).unwrap();
    let count = session
        .store()
        .entities()
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "for-type")
                && matches!(e.get(props::VALUE_KIND), Some(Value::Text(_)))
        })
        .count();
    assert_eq!(count, 1, "exactly one for-type definition");
    cleanup(&path);
}

#[test]
fn the_existing_todo_doing_done_become_task_scoped() {
    let (path, session) = fresh("scoped");
    let store = session.store();
    let task = find_type(store, "task").unwrap();
    let offer = status_options_for(store, task);
    let names: Vec<&str> = offer.iter().map(|o| o.name.as_str()).collect();
    assert_eq!(names, vec!["todo", "doing", "done"], "the legacy three, in board order");
    assert_eq!(offer[0].order, 1.0);
    assert_eq!(offer[1].order, 2.0);
    assert_eq!(offer[2].order, 3.0);
    cleanup(&path);
}

#[test]
fn an_option_carries_board_order_and_hue_and_they_round_trip() {
    // Existence + round-trip only — never a specific color (R3 owns values).
    let (path, mut session) = fresh("hue");
    let store = session.store();
    let task = find_type(store, "task").unwrap();
    let todo = status_options_for(store, task)[0].clone();
    assert!(todo.hue.is_some(), "a seeded option carries some hue");

    // Re-hue = an ordinary set on the option entity; the offer reflects it.
    content::set_property(&mut session, todo.id, "hue", "200").unwrap();
    let again = status_options_for(session.store(), task);
    assert_eq!(again[0].hue, Some(200.0));
    cleanup(&path);
}

#[test]
fn done_is_marked_completes() {
    let (path, session) = fresh("completes");
    let store = session.store();
    let task = find_type(store, "task").unwrap();
    let offer = status_options_for(store, task);
    assert!(!offer[0].completes, "todo is open");
    assert!(!offer[1].completes, "doing is open");
    assert!(offer[2].completes, "done is the terminal state the checkbox writes");
    cleanup(&path);
}

#[test]
fn status_options_are_scoped_per_kind_by_for_type() {
    let (path, mut session) = fresh("perkind");
    let project = find_type(session.store(), "project").unwrap();
    let task = find_type(session.store(), "task").unwrap();

    let active = content::add_status_option(&mut session, project, "active", None).unwrap();
    let store = session.store();
    let project_offer = status_options_for(store, project);
    assert!(project_offer.iter().any(|o| o.id == active), "project offers active");
    assert!(!project_offer.iter().any(|o| o.name == "todo"), "todo is task-scoped");
    let task_offer = status_options_for(store, task);
    assert_eq!(task_offer.len(), 3, "the task offer is unchanged");
    cleanup(&path);
}

#[test]
fn a_kind_with_no_status_options_offers_none() {
    // Vocabularies are per-kind, never inherited from task (bp6 #33 inverse).
    let (path, session) = fresh("none");
    let store = session.store();
    let note = find_type(store, "note").unwrap();
    assert!(status_options_for(store, note).is_empty());
    cleanup(&path);
}

#[test]
fn an_unscoped_option_is_offered_everywhere() {
    // The backward-safe degenerate case: an option with no for-type at all
    // (an old app version's fresh option) is never stranded.
    let (path, mut session) = fresh("unscoped");
    let store = session.store();
    let status = property_id(store, "status").unwrap();
    let id = session.allocate_id();
    session
        .commit(
            vec![
                Command::Create { entity: id },
                Command::AddCell {
                    entity: id,
                    cell: Cell { property: props::NAME, value: Value::text("someday") },
                },
                Command::AddCell {
                    entity: id,
                    cell: Cell { property: props::WORKING, value: Value::Bool(true) },
                },
                Command::AddCell {
                    entity: status,
                    cell: Cell { property: props::OPTIONS, value: Value::Reference(id) },
                },
            ],
            "legacy option",
            Author::User,
        )
        .unwrap();
    let store = session.store();
    let task = find_type(store, "task").unwrap();
    let note = find_type(store, "note").unwrap();
    assert!(status_options_for(store, task).iter().any(|o| o.id == id));
    assert!(status_options_for(store, note).iter().any(|o| o.id == id));
    cleanup(&path);
}

#[test]
fn the_entry_default_is_a_cell_on_the_type_and_user_editable() {
    let (path, mut session) = fresh("default");
    let store = session.store();
    let task = find_type(store, "task").unwrap();
    let status = property_id(store, "status").unwrap();
    let doing = content::find_option(store, status, "doing").unwrap();

    // Re-point the entry column: an ordinary reference set on the TYPE.
    content::set_property(&mut session, task, "default-status", &format!("#{doing}")).unwrap();
    let born = content::create_task(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    let store = session.store();
    assert_eq!(
        store.get(born).unwrap().get(status),
        Some(&Value::Select(doing)),
        "a new task births the edited default"
    );
    cleanup(&path);
}

#[test]
fn create_task_still_births_status_select_todo() {
    // Compat: births are byte-identical on every existing box — the cell is
    // a Select of the todo OPTION entity, never a Reference.
    let (path, mut session) = fresh("compat");
    let born = content::create_task(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    let store = session.store();
    let status = property_id(store, "status").unwrap();
    let todo = content::find_option(store, status, "todo").unwrap();
    assert_eq!(store.get(born).unwrap().get(status), Some(&Value::Select(todo)));
    cleanup(&path);
}

#[test]
fn no_status_is_always_valid() {
    let (path, mut session) = fresh("nostatus");
    let note = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    let store = session.store();
    let status = property_id(store, "status").unwrap();
    assert!(store.get(note).unwrap().get(status).is_none(), "nothing forces a status");
    let q = search::parse(store, "status:done");
    let hits = search::search(store, &q, 200, |_| String::new());
    assert!(!hits.iter().any(|h| h.id == note), "a status query never drags it in");
    cleanup(&path);
}

#[test]
fn pre_existing_status_select_cells_survive_the_scoping() {
    let (path, mut session) = fresh("survive");
    let born = content::create_task(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    content::set_property(&mut session, born, "status", "done").unwrap();
    let store = session.store();
    let q = search::parse(store, "status:done");
    let hits = search::search(store, &q, 200, |_| String::new());
    assert!(hits.iter().any(|h| h.id == born), "status:done still matches vault-wide");
    cleanup(&path);
}
