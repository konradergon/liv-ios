//! Saving a body, and the compare-and-swap that makes it safe.
//!
//! **There is no force flag, by design.** The editor saves against the
//! fingerprint it last read; if the stored body moved underneath it, the
//! save is refused and the editor re-reads. `core/` has exactly this
//! contract (`services/src/content.rs`) and the shell already speaks it —
//! `liv_set_content_at` returns -1 for stale, and `Editor.swift` holds a
//! `base` for the round trip. Two save buttons that behave differently is
//! a defect even while only one of them ships.
//!
//! The one rule here that surprises people: **the no-op wins before the
//! guard.** Saving what is already stored is never stale, whatever base
//! the writer believed — its intent is the log's state already, and
//! refusing it would make a harmless keystroke look like a conflict.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_787_391_635_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

fn note(e: &mut Engine, name: &str) -> EntityId {
    e.create(kind::NOTE, Some(name), T0).unwrap()
}

fn body(e: &Engine, id: EntityId) -> Vec<Span> {
    e.content(id).unwrap().0
}

fn print(e: &Engine, id: EntityId) -> u64 {
    e.content(id).unwrap().1
}

// ---- the round trip ---------------------------------------------------

#[test]
fn a_body_saves_and_reads_back() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    assert!(body(&e, id).is_empty(), "a fresh note has no body");
    assert_eq!(print(&e, id), 0, "and no fingerprint — zero is never a real one");

    let spans = vec![
        Span::Break(Block::Heading(2)),
        Span::text("Roof"),
        Span::Break(Block::Body),
        Span::text("call the surveyor"),
    ];
    let fresh = e.set_content(id, spans.clone(), 0, T0 + 1).unwrap();

    assert_eq!(body(&e, id), spans);
    assert_eq!(print(&e, id), fresh, "the fingerprint it returned is the one stored");
    assert_ne!(fresh, 0);
}

#[test]
fn the_fingerprint_follows_the_value_and_nothing_else() {
    let mut e = engine();
    let a = note(&mut e, "A");
    let b = note(&mut e, "B");
    let spans = vec![Span::text("same words")];

    let one = e.set_content(a, spans.clone(), 0, T0 + 1).unwrap();
    let two = e.set_content(b, spans, 0, T0 + 2).unwrap();
    assert_eq!(one, two, "the same body has the same fingerprint in two entities");

    // And a mark is a difference. A fingerprint over the TEXT rather than
    // the value would call these two the same document and let a save
    // that dropped every bold through the compare-and-swap.
    let marked = e
        .set_content(
            b,
            vec![Span::Text(TextSpan { text: "same words".into(), marks: Marks(Marks::BOLD) })],
            two,
            T0 + 3,
        )
        .unwrap();
    assert_ne!(marked, two, "bolding it is a different document");
}

// ---- the compare-and-swap --------------------------------------------

#[test]
fn a_save_against_a_moved_body_is_refused() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let first = e.set_content(id, vec![Span::text("one")], 0, T0 + 1).unwrap();

    // Someone else saves. Our editor still holds `first`.
    e.set_content(id, vec![Span::text("two")], first, T0 + 2).unwrap();

    let refused = e.set_content(id, vec![Span::text("one, edited")], first, T0 + 3);
    assert!(matches!(refused, Err(ContentError::Stale)), "{refused:?}");
    assert_eq!(body(&e, id), vec![Span::text("two")], "and nothing was written");
}

#[test]
fn saving_what_is_already_there_is_never_stale() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let spans = vec![Span::text("one")];
    let fp = e.set_content(id, spans.clone(), 0, T0 + 1).unwrap();

    // A deliberately wrong base. The no-op wins before the guard: this
    // writer's intent is the log's state already, so refusing it would
    // turn a harmless keystroke into a conflict the user has to resolve.
    let again = e.set_content(id, spans, 12_345, T0 + 2).unwrap();
    assert_eq!(again, fp);
    assert_eq!(e.group_count().unwrap(), 2, "and it committed nothing");
}

#[test]
fn the_first_save_is_against_a_base_of_zero() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    // Not a special case in the API, just what "no cell" fingerprints to.
    assert!(matches!(
        e.set_content(id, vec![Span::text("x")], 999, T0 + 1),
        Err(ContentError::Stale)
    ));
    assert!(e.set_content(id, vec![Span::text("x")], 0, T0 + 2).is_ok());
}

// ---- clearing ---------------------------------------------------------

#[test]
fn an_empty_body_removes_the_cell() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let fp = e.set_content(id, vec![Span::text("one")], 0, T0 + 1).unwrap();

    let cleared = e.set_content(id, vec![], fp, T0 + 2).unwrap();
    assert_eq!(cleared, 0, "back to no fingerprint");
    assert!(e.one(id, prop::BODY).unwrap().is_none(), "the cell is gone, not empty");
    // And the note is still a note.
    assert_eq!(e.kind_of(id).unwrap(), Some(kind::NOTE));
    assert_eq!(e.name(id).unwrap().as_deref(), Some("Roof"));
}

// ---- what is not content ----------------------------------------------

#[test]
fn a_reference_to_nothing_is_not_content() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let ghost = EntityId([0x99; 16]);

    let refused = e.set_content(id, vec![Span::text("see "), Span::Ref(ghost)], 0, T0 + 1);
    assert!(matches!(refused, Err(ContentError::Invalid)), "{refused:?}");
    assert!(body(&e, id).is_empty(), "and nothing was written");

    // The same body with a real target saves.
    let real = note(&mut e, "Ferry times");
    e.set_content(id, vec![Span::text("see "), Span::Ref(real)], 0, T0 + 2).unwrap();
    assert_eq!(body(&e, id).len(), 2);
}

#[test]
fn a_reference_to_a_trashed_thing_is_still_content() {
    // Trash is reversible and a link to something in the trash is a link
    // to something that still exists. Refusing it would make emptying a
    // note's neighbour a reason its own save fails.
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let other = note(&mut e, "Ferry times");
    e.trash(other, T0 + 1).unwrap();

    e.set_content(id, vec![Span::Ref(other)], 0, T0 + 2).unwrap();
    assert_eq!(body(&e, id), vec![Span::Ref(other)]);
}

#[test]
fn a_body_on_a_thing_that_does_not_exist_is_refused() {
    let mut e = engine();
    let refused = e.set_content(EntityId([0x77; 16]), vec![Span::text("x")], 0, T0);
    assert!(matches!(refused, Err(ContentError::Invalid)), "{refused:?}");
}

// ---- it is an ordinary write -----------------------------------------

#[test]
fn a_save_is_one_action_and_undoes_as_one() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let one = e.set_content(id, vec![Span::text("one")], 0, T0 + 1).unwrap();
    e.set_content(id, vec![Span::text("two")], one, T0 + 2).unwrap();

    e.undo(T0 + 3).unwrap();
    assert_eq!(body(&e, id), vec![Span::text("one")], "one undo, one save");
    e.undo(T0 + 4).unwrap();
    assert!(body(&e, id).is_empty(), "and the first save took the cell with it");
}

#[test]
fn a_box_with_bodies_replays_identically() {
    let mut e = engine();
    let a = note(&mut e, "A");
    let b = note(&mut e, "B");
    let fp = e
        .set_content(
            a,
            vec![
                Span::Break(Block::Code { lang: Some("rust".into()) }),
                Span::text("fn main() {}"),
                Span::Ref(b),
            ],
            0,
            T0 + 1,
        )
        .unwrap();
    e.set_content(a, vec![Span::text("simpler")], fp, T0 + 2).unwrap();

    let before = e.digest().unwrap();
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), before, "the replay gate holds over content");
    assert_eq!(body(&e, a), vec![Span::text("simpler")]);
}
