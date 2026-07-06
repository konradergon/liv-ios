//! The entity model is only as good as its worst case.
//! These tests are the constitution's worked examples, executable.

use lotus_core::*;

fn cell(property: Id, value: Value) -> Cell {
    Cell { property, value }
}

fn reference(property: Id, target: Id) -> Cell {
    cell(property, Value::Reference(target))
}

/// Worked example 1: a thought, captured.
/// An untyped entity with content and a creation date. Nothing else.
#[test]
fn capture_creates_a_scrap() {
    let mut store = Store::new();
    let scrap = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: scrap },
                Command::AddCell {
                    entity: scrap,
                    cell: cell(props::CONTENT, Value::text("Call Anna Friday")),
                },
                Command::AddCell {
                    entity: scrap,
                    cell: cell(props::CREATED, Value::DateTime(DateTime::at(2026, 7, 6, 9, 30))),
                },
            ],
            "capture",
            Author::User,
        )
        .unwrap();

    let entity = store.get(scrap).unwrap();
    assert_eq!(entity.cells.len(), 2);
    assert!(entity.get(props::TYPE).is_none(), "no type at capture");

    // The clerk proposes; nothing lands unconfirmed.
    store.propose(Proposal {
        commands: vec![Command::AddCell {
            entity: scrap,
            cell: cell(4200, Value::DateTime(DateTime::date(2026, 7, 10))),
        }],
        label: "add due date".into(),
        author: Author::Proposer("dates".into()),
        reason: "contains Friday -> due date Friday?".into(),
    });
    assert!(store.get(scrap).unwrap().get(4200).is_none(), "drafts never pollute");

    store.accept(0).unwrap();
    assert!(store.get(scrap).unwrap().get(4200).is_some());
    assert_eq!(
        store.history().last().unwrap().author,
        Author::Proposer("dates".into())
    );
}

/// Worked example 3: a task inside a note.
/// The note does not contain the task; it displays it.
#[test]
fn a_note_displays_a_task_it_does_not_own() {
    let mut store = Store::new();
    let status = store.allocate_id(); // a select option entity
    let task = store.allocate_id();
    let note = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: status },
                Command::Create { entity: task },
                Command::AddCell {
                    entity: task,
                    cell: cell(props::NAME, Value::text("buy milk")),
                },
                Command::Create { entity: note },
                Command::AddCell {
                    entity: note,
                    cell: cell(
                        props::CONTENT,
                        Value::RichText(RichText {
                            spans: vec![
                                Span::Text("Groceries: ".into()),
                                Span::Ref(task),
                            ],
                        }),
                    ),
                },
            ],
            "write note",
            Author::User,
        )
        .unwrap();

    // The embedded reference is indexed like any other.
    let links = store.backlinks(task);
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].source, note);
    assert_eq!(links[0].property, props::CONTENT);

    // Checking the checkbox edits the task; the note is untouched.
    let note_before = store.get(note).unwrap().clone();
    store
        .commit(
            vec![Command::AddCell {
                entity: task,
                cell: cell(4300, Value::Select(status)),
            }],
            "check off",
            Author::User,
        )
        .unwrap();
    assert_eq!(*store.get(note).unwrap(), note_before);

    // Deleting the note does not delete the task.
    store
        .commit(vec![Command::Trash { entity: note }], "trash note", Author::User)
        .unwrap();
    assert!(!store.get(task).unwrap().trashed);
}

/// Worked example 6: two entities for the same person.
/// Three hundred references, zero writes to any of them.
#[test]
fn merge_rewrites_nothing() {
    let mut store = Store::new();
    let anna = store.allocate_id();
    let anna_dupe = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: anna },
                Command::AddCell {
                    entity: anna,
                    cell: cell(props::NAME, Value::text("Anna")),
                },
                Command::Create { entity: anna_dupe },
                Command::AddCell {
                    entity: anna_dupe,
                    cell: cell(props::NAME, Value::text("Anna")),
                },
                Command::AddCell {
                    entity: anna_dupe,
                    cell: cell(4400, Value::text("anna@example.com")),
                },
            ],
            "two annas",
            Author::User,
        )
        .unwrap();

    let mut meetings = Vec::new();
    for _ in 0..300 {
        let meeting = store.allocate_id();
        meetings.push(meeting);
        store
            .commit(
                vec![
                    Command::Create { entity: meeting },
                    Command::AddCell {
                        entity: meeting,
                        cell: reference(4401, anna_dupe),
                    },
                ],
                "meeting",
                Author::User,
            )
            .unwrap();
    }
    let meeting_before = store.get(meetings[17]).unwrap().clone();

    store.merge(anna, anna_dupe, vec![], Author::User).unwrap();

    // No meeting was edited; every reference resolves to the survivor.
    assert_eq!(*store.get(meetings[17]).unwrap(), meeting_before);
    assert_eq!(store.resolve(anna_dupe), anna);
    assert_eq!(store.get(anna_dupe).unwrap().id, anna);
    assert_eq!(store.backlinks(anna).len(), 300);

    // The distinct email came along; the duplicate name did not.
    let survivor = store.get(anna).unwrap();
    assert!(survivor.get(4400).is_some());
    assert_eq!(survivor.all(props::NAME).count(), 1);

    // One undo step, like everything else.
    store.undo(Author::User).unwrap();
    assert_eq!(store.resolve(anna_dupe), anna_dupe);
    assert!(!store.get(anna_dupe).unwrap().trashed);
    assert!(store.get(anna).unwrap().get(4400).is_none());
}

/// Worked example 7: a date with no time.
#[test]
fn civil_dates_sort_beside_datetimes() {
    let friday = DateTime::date(2026, 7, 10);
    let friday_ten = DateTime::at(2026, 7, 10, 10, 0);
    let thursday_late = DateTime::at(2026, 7, 9, 23, 59);

    assert_ne!(
        Value::DateTime(friday),
        Value::DateTime(DateTime::at(2026, 7, 10, 0, 0)),
        "friday and friday 00:00 are different values"
    );
    assert!(thursday_late < friday);
    assert!(friday < friday_ten);
}

/// Worked example 8: a card dragged to the top of a board.
/// Manual order is data about (entity, view), promoted to a Placement.
#[test]
fn placement_is_backstage_plumbing() {
    let mut store = Store::new();
    let task = store.allocate_id();
    let view = store.allocate_id();
    let placement = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: task },
                Command::Create { entity: view },
                Command::Create { entity: placement },
                Command::AddCell {
                    entity: placement,
                    cell: reference(4500, task),
                },
                Command::AddCell {
                    entity: placement,
                    cell: reference(4501, view),
                },
                Command::AddCell {
                    entity: placement,
                    cell: cell(4502, Value::text("h")),
                },
                Command::AddCell {
                    entity: placement,
                    cell: cell(props::WORKING, Value::Bool(true)),
                },
            ],
            "drag to top",
            Author::User,
        )
        .unwrap();

    // Reordering is one small command pair on one small entity.
    store
        .commit(
            vec![
                Command::RemoveCell {
                    entity: placement,
                    cell: cell(4502, Value::text("h")),
                },
                Command::AddCell {
                    entity: placement,
                    cell: cell(4502, Value::text("d")),
                },
            ],
            "reorder",
            Author::User,
        )
        .unwrap();
    assert_eq!(store.get(placement).unwrap().get(4502), Some(&Value::text("d")));

    store.undo(Author::User).unwrap();
    assert_eq!(store.get(placement).unwrap().get(4502), Some(&Value::text("h")));
    assert_eq!(
        store.get(placement).unwrap().get(props::WORKING),
        Some(&Value::Bool(true))
    );
}

/// Worked example 10: an agent plans the offsite.
/// One key accepts all of it. One undo removes all of it.
#[test]
fn an_agent_batch_is_one_step() {
    let mut store = Store::new();
    let project = store.allocate_id();
    store
        .commit(vec![Command::Create { entity: project }], "project", Author::User)
        .unwrap();

    let mut commands = Vec::new();
    let mut drafted = Vec::new();
    for _ in 0..6 {
        let id = store.allocate_id();
        drafted.push(id);
        commands.push(Command::Create { entity: id });
        commands.push(Command::AddCell {
            entity: id,
            cell: reference(4600, project),
        });
    }
    store.propose(Proposal {
        commands,
        label: "plan the offsite".into(),
        author: Author::Proposer("offsite-agent".into()),
        reason: "goal: plan the offsite".into(),
    });

    assert!(store.get(drafted[0]).is_none(), "quarantined");
    store.accept(0).unwrap();
    assert!(drafted.iter().all(|id| store.get(*id).is_some()));
    assert_eq!(
        store.history().last().unwrap().author,
        Author::Proposer("offsite-agent".into())
    );

    store.undo(Author::User).unwrap();
    assert!(drafted.iter().all(|id| store.get(*id).unwrap().trashed));
}

// ---- invariants ----

#[test]
fn identifiers_are_never_reused() {
    let mut store = Store::new();
    let a = store.allocate_id();
    store
        .commit(vec![Command::Create { entity: a }], "create", Author::User)
        .unwrap();
    store
        .commit(vec![Command::Trash { entity: a }], "trash", Author::User)
        .unwrap();
    let b = store.allocate_id();
    assert!(b > a);
}

#[test]
fn undo_appends_and_never_erases() {
    let mut store = Store::new();
    let a = store.allocate_id();
    let seq = store
        .commit(vec![Command::Create { entity: a }], "create", Author::User)
        .unwrap();

    let undo_seq = store.undo(Author::User).unwrap();
    assert_eq!(store.history().len(), 2, "the mistake and its correction are both facts");
    let undo_tx = &store.history()[undo_seq as usize];
    assert_eq!(undo_tx.reverses, Some(seq));
    assert_eq!(undo_tx.author, Author::User);

    let redo_seq = store.redo(Author::User).unwrap();
    assert_eq!(store.history().len(), 3);
    assert_eq!(store.history()[redo_seq as usize].reverses, Some(undo_seq));
    assert!(!store.get(a).unwrap().trashed);
}

#[test]
fn a_transaction_lands_whole_or_not_at_all() {
    let mut store = Store::new();
    let a = store.allocate_id();
    let missing = store.allocate_id();
    let result = store.commit(
        vec![
            Command::Create { entity: a },
            Command::AddCell {
                entity: missing, // never created
                cell: cell(props::NAME, Value::text("x")),
            },
        ],
        "broken",
        Author::User,
    );
    assert!(matches!(result, Err(StoreError::NoSuchEntity(_))));
    assert!(store.get(a).is_none(), "the applied prefix was reversed");
    assert!(store.history().is_empty());
}

#[test]
fn value_equality_is_per_kind() {
    // Files by hash: the path is where, not what.
    let here = Value::File(FileRef { path: "/a/contract.docx".into(), hash: [7; 32] });
    let there = Value::File(FileRef { path: "/b/contract.docx".into(), hash: [7; 32] });
    let changed = Value::File(FileRef { path: "/a/contract.docx".into(), hash: [8; 32] });
    assert_eq!(here, there);
    assert_ne!(here, changed);

    // Rich text by spans.
    assert_eq!(
        Value::RichText(RichText { spans: vec![Span::Ref(9)] }),
        Value::RichText(RichText { spans: vec![Span::Ref(9)] })
    );
}

#[test]
fn multi_valued_properties_are_repeated_cells() {
    let mut store = Store::new();
    let note_type = store.allocate_id();
    let task_type = store.allocate_id();
    let email = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: note_type },
                Command::Create { entity: task_type },
                Command::Create { entity: email },
                Command::AddCell { entity: email, cell: reference(props::TYPE, note_type) },
                // An email can also be a task: same entity, one more cell.
                Command::AddCell { entity: email, cell: reference(props::TYPE, task_type) },
            ],
            "type twice",
            Author::User,
        )
        .unwrap();
    assert_eq!(store.get(email).unwrap().all(props::TYPE).count(), 2);

    // Removal picks the equal cell, not its sibling.
    store
        .commit(
            vec![Command::RemoveCell { entity: email, cell: reference(props::TYPE, note_type) }],
            "not a note",
            Author::User,
        )
        .unwrap();
    let remaining = store.get(email).unwrap();
    assert!(remaining.has(props::TYPE, &Value::Reference(task_type)));
    assert!(!remaining.has(props::TYPE, &Value::Reference(note_type)));
    assert!(store.backlinks(note_type).is_empty());
    assert_eq!(store.backlinks(task_type).len(), 1);
}

#[test]
fn redirects_chase_transitively() {
    let mut store = Store::new();
    let a = store.allocate_id();
    let b = store.allocate_id();
    let c = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: a },
                Command::Create { entity: b },
                Command::Create { entity: c },
            ],
            "three",
            Author::User,
        )
        .unwrap();
    store.merge(b, a, vec![], Author::User).unwrap();
    store.merge(c, b, vec![], Author::User).unwrap();
    assert_eq!(store.resolve(a), c);
    assert_eq!(store.get(a).unwrap().id, c);
}

#[test]
fn modification_time_is_derived_not_stored() {
    let mut store = Store::new();
    let a = store.allocate_id();
    store
        .commit(vec![Command::Create { entity: a }], "create", Author::User)
        .unwrap();
    let entity = store.get(a).unwrap();
    assert!(entity.cells.is_empty(), "no modified cell, ever");
    assert!(store.modified(a).is_some());
}
