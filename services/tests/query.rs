//! The v0 query: a plain conjunction of (property, operator, value),
//! interpreted the same way for every view that will ever exist.

use liv_core::*;
use liv_services::{run, Constraint, Op, Query, Sort};

const STATUS: Id = 4300;
const DUE: Id = 4301;

fn cell(property: Id, value: Value) -> Cell {
    Cell { property, value }
}

/// A store with a mix: two tasks (one done), a note, a working placement,
/// and a trashed scrap.
fn fixture() -> (Store, [Id; 5]) {
    let mut store = Store::new();
    let task = store.allocate_id();
    let done_task = store.allocate_id();
    let note = store.allocate_id();
    let placement = store.allocate_id();
    let trashed = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: task },
                Command::AddCell {
                    entity: task,
                    cell: cell(STATUS, Value::text("todo")),
                },
                Command::AddCell {
                    entity: task,
                    cell: cell(DUE, Value::DateTime(DateTime::date(2026, 7, 10))),
                },
                Command::Create { entity: done_task },
                Command::AddCell {
                    entity: done_task,
                    cell: cell(STATUS, Value::text("done")),
                },
                Command::AddCell {
                    entity: done_task,
                    cell: cell(DUE, Value::DateTime(DateTime::at(2026, 7, 8, 9, 0))),
                },
                Command::Create { entity: note },
                Command::Create { entity: placement },
                Command::AddCell {
                    entity: placement,
                    cell: cell(props::WORKING, Value::Bool(true)),
                },
                Command::Create { entity: trashed },
                Command::Trash { entity: trashed },
            ],
            "fixture",
            Author::User,
        )
        .unwrap();
    (store, [task, done_task, note, placement, trashed])
}

#[test]
fn equals_matches_and_conjunction_narrows() {
    let (store, [task, done_task, ..]) = fixture();
    let todo = run(
        &store,
        &Query {
            constraints: vec![Constraint {
                property: STATUS,
                op: Op::Equals(Value::text("todo")),
            }],
            ..Query::default()
        },
    );
    assert_eq!(todo, vec![task]);

    // status? AND status != todo — the conjunction narrows to the done task.
    let done = run(
        &store,
        &Query {
            constraints: vec![
                Constraint {
                    property: STATUS,
                    op: Op::Exists,
                },
                Constraint {
                    property: STATUS,
                    op: Op::NotEquals(Value::text("todo")),
                },
            ],
            ..Query::default()
        },
    );
    assert_eq!(done, vec![done_task]);
}

#[test]
fn not_equals_is_vacuously_true_when_absent() {
    let (store, [task, _, note, ..]) = fixture();
    // "status != done": the todo task AND the statusless note both satisfy.
    let not_done = run(
        &store,
        &Query {
            constraints: vec![Constraint {
                property: STATUS,
                op: Op::NotEquals(Value::text("done")),
            }],
            ..Query::default()
        },
    );
    assert_eq!(not_done, vec![task, note]);
}

#[test]
fn backstage_and_trash_stay_out_by_default() {
    let (store, [task, done_task, note, placement, trashed]) = fixture();
    let everyone = run(&store, &Query::default());
    assert_eq!(everyone, vec![task, done_task, note]);

    let backstage = run(
        &store,
        &Query {
            include_working: true,
            include_trashed: true,
            ..Query::default()
        },
    );
    assert!(backstage.contains(&placement));
    assert!(backstage.contains(&trashed));
}

#[test]
fn sort_by_date_missing_last() {
    let (store, [task, done_task, note, ..]) = fixture();
    let by_due = run(
        &store,
        &Query {
            sort: Some(Sort {
                property: DUE,
                descending: false,
            }),
            ..Query::default()
        },
    );
    // Tuesday 9:00 before date-only Friday; the dateless note last.
    assert_eq!(by_due, vec![done_task, task, note]);

    let by_due_desc = run(
        &store,
        &Query {
            sort: Some(Sort {
                property: DUE,
                descending: true,
            }),
            ..Query::default()
        },
    );
    assert_eq!(by_due_desc, vec![task, done_task, note]);
}

#[test]
fn multi_valued_matches_on_any_cell() {
    let mut store = Store::new();
    let tagged = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: tagged },
                Command::AddCell {
                    entity: tagged,
                    cell: cell(4400, Value::text("work")),
                },
                Command::AddCell {
                    entity: tagged,
                    cell: cell(4400, Value::text("urgent")),
                },
            ],
            "tags",
            Author::User,
        )
        .unwrap();
    let hits = run(
        &store,
        &Query {
            constraints: vec![Constraint {
                property: 4400,
                op: Op::Equals(Value::text("urgent")),
            }],
            ..Query::default()
        },
    );
    assert_eq!(hits, vec![tagged]);
}

#[test]
fn a_query_is_data_it_serializes() {
    // The reason the query is a struct and not a closure: a saved query is
    // an entity, and this string is what its query cell will hold.
    let query = Query {
        constraints: vec![Constraint {
            property: STATUS,
            op: Op::NotEquals(Value::text("done")),
        }],
        sort: Some(Sort {
            property: DUE,
            descending: false,
        }),
        ..Query::default()
    };
    let text = serde_json::to_string(&query).unwrap();
    let back: Query = serde_json::from_str(&text).unwrap();
    assert_eq!(back, query);
}
