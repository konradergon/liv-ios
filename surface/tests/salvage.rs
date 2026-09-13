//! The two surfaces the swap would otherwise take away.

use liv_engine::*;
use liv_surface::salvage::{note_tasks, trash};
use liv_surface::Lens;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_789_257_600_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

fn body(e: &mut Engine, id: EntityId, spans: Vec<Span>, at: u64) {
    e.set_content(id, spans, 0, at).unwrap();
}

#[test]
fn the_trash_is_the_one_surface_that_wants_what_the_rest_throw_away() {
    let mut e = engine();
    let live = e.create(kind::NOTE, Some("Still here"), T0).unwrap();
    let gone = e.create(kind::NOTE, Some("Thrown out"), T0 + 1).unwrap();
    let filed = e.create(kind::NOTE, Some("Archived"), T0 + 2).unwrap();
    e.set(filed, prop::ARCHIVED, Value::Bool(true), T0 + 3).unwrap();
    e.trash(gone, T0 + 4).unwrap();

    let rows = trash(&e).unwrap();
    let ids: Vec<EntityId> = rows.iter().map(|r| r.id).collect();
    assert_eq!(ids, vec![gone], "only the trashed one");
    assert!(!ids.contains(&live));

    // **Archived is not trashed.** Archiving files something away;
    // trashing throws it out, and they are different screens.
    assert!(!ids.contains(&filed), "archived is not trashed");

    // And restoring takes it back off the list.
    e.restore(gone, T0 + 5).unwrap();
    assert!(trash(&e).unwrap().is_empty());
}

/// Newest first: the thing you just deleted is the thing you are most
/// likely to be looking for.
#[test]
fn the_trash_is_newest_first() {
    let mut e = engine();
    let mut ids = Vec::new();
    for i in 0..3u64 {
        let id = e.create(kind::NOTE, Some(&format!("note {i}")), T0 + i).unwrap();
        e.trash(id, T0 + 10 + i).unwrap();
        ids.push(id);
    }
    let rows: Vec<EntityId> = trash(&e).unwrap().iter().map(|r| r.id).collect();
    ids.reverse();
    assert_eq!(rows, ids);
}

/// **A projection: nothing is stored.** No entity is created and no cell
/// is written — a line in a note is a thought, not a task someone has to
/// file.
#[test]
fn an_open_checkbox_inside_a_note_is_listed_without_becoming_a_thing() {
    let mut e = engine();
    let note = e.create(kind::NOTE, Some("Saturday"), T0).unwrap();
    let before = e.all_entities().unwrap().len();
    body(
        &mut e,
        note,
        vec![
            Span::text("plans"),
            Span::Break(rich::Block::Task { depth: 0, done: false }),
            Span::text("book the ferry"),
            Span::Break(rich::Block::Task { depth: 1, done: true }),
            Span::text("already done this"),
            Span::Break(rich::Block::Task { depth: 0, done: false }),
            Span::text("call the surveyor"),
        ],
        T0 + 1,
    );

    let found = note_tasks(&e, &Lens::Everything).unwrap();
    let words: Vec<&str> = found.iter().map(|t| t.text.as_str()).collect();
    assert_eq!(words, vec!["book the ferry", "call the surveyor"], "and never the done one");
    assert_eq!(found[0].note, note);
    assert_eq!(found[0].source, "Saturday", "titled where the body is");
    assert_eq!(found[1].depth, 0);
    assert_ne!(found[0].line, found[1].line, "each line has its own address");

    assert_eq!(e.all_entities().unwrap().len(), before, "nothing was created");
}

/// Something already typed as a task or an event is listed as ITSELF.
/// Its body lines would be the same work counted twice.
#[test]
fn a_task_does_not_contribute_its_own_body_lines() {
    let mut e = engine();
    let task = e.create(kind::TASK, Some("Fix the roof"), T0).unwrap();
    body(
        &mut e,
        task,
        vec![
            Span::Break(rich::Block::Task { depth: 0, done: false }),
            Span::text("get a quote"),
        ],
        T0 + 1,
    );
    assert!(note_tasks(&e, &Lens::Everything).unwrap().is_empty());
}

#[test]
fn a_trashed_note_contributes_no_lines() {
    let mut e = engine();
    let note = e.create(kind::NOTE, Some("Old"), T0).unwrap();
    body(
        &mut e,
        note,
        vec![
            Span::Break(rich::Block::Task { depth: 0, done: false }),
            Span::text("book the ferry"),
        ],
        T0 + 1,
    );
    assert_eq!(note_tasks(&e, &Lens::Everything).unwrap().len(), 1);
    e.trash(note, T0 + 2).unwrap();
    assert!(note_tasks(&e, &Lens::Everything).unwrap().is_empty());
}

/// An empty checkbox is someone mid-sentence, not a task.
#[test]
fn an_empty_checkbox_is_not_a_task() {
    let mut e = engine();
    let note = e.create(kind::NOTE, Some("Saturday"), T0).unwrap();
    body(
        &mut e,
        note,
        vec![
            Span::Break(rich::Block::Task { depth: 0, done: false }),
            Span::Break(rich::Block::Task { depth: 0, done: false }),
            Span::text("   "),
        ],
        T0 + 1,
    );
    assert!(note_tasks(&e, &Lens::Everything).unwrap().is_empty());
}

/// **A trash state two devices disagree about is not a trash state.**
///
/// `with_value` finds anything with a live `trashed: true` row, and a
/// concurrent trash-and-restore leaves one standing beside a `false`.
/// `row` reads that cell with `one`, which answers nothing when a
/// register is contended — so the row says it is not trashed, and the
/// trash must agree with it rather than list a thing every other surface
/// is still showing. Nothing silently wins, here included.
///
/// This is what the `r.trashed` re-check is for. Deleting it changed no
/// test until this one existed, because the query alone cannot see it.
#[test]
fn a_contended_trash_state_is_not_the_trash() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("Argued over"), T0).unwrap();

    for (n, (d, gone)) in [(dev(2), true), (dev(3), false)].into_iter().enumerate() {
        e.receive(Group {
            device: d,
            first_seq: 0,
            hlc: Hlc { wall_ms: 2_000 + n as u64, ctr: 0 },
            author: Author::User,
            action: 1,
            reverses: None,
            ops: vec![Op::SetCell {
                entity: id,
                prop: prop::TRASHED,
                value: Value::Bool(gone),
                replaces: vec![],
            }],
        })
        .unwrap();
    }
    assert!(e.contended(id, prop::TRASHED).unwrap(), "the setup must actually contend");
    assert!(!e.is_trashed(id).unwrap(), "and `one` refuses to pick");

    assert!(
        trash(&e).unwrap().is_empty(),
        "a thing every other surface still shows must not also be in the trash"
    );
}
