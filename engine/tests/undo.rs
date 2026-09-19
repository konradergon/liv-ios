//! Undo, and the one thing it cannot promise.
//!
//! `Group.reverses` has been in the op format since Phase 2 and nothing
//! wrote it. This is what writes it.
//!
//! The semantics are `core/`'s, deliberately — two undo buttons that
//! behave differently is a defect even while only one of them ships. From
//! `core/src/store.rs`: an undo appends the inverse ops in REVERSE order,
//! carrying `reverses` to its target; the undo and redo stacks are not
//! state but a READING of the log, rebuilt on open, so nothing about undo
//! can drift from what the log says.
//!
//! **One thing is new here, because the log is not one device's any more.**
//! Undo is what *you* did on *this* device. Another device's action is
//! never on your stack — it is not yours to take back, and a box that let
//! either end undo the other's last write would race.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_787_391_635_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

fn text(s: &str) -> Value {
    Value::Text(s.into())
}

/// The live values of one cell, in no particular order.
fn values(e: &Engine, id: EntityId, prop: EntityId) -> Vec<Value> {
    let mut v: Vec<Value> = e.cell(id, prop).unwrap().into_iter().map(|(_, v)| v).collect();
    v.sort_by_key(|x| format!("{x:?}"));
    v
}

// ---- the four ops, each undone ----------------------------------------

#[test]
fn undoing_a_create_trashes_it() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("Roof"), T0).unwrap();
    assert!(!e.is_trashed(id).unwrap());

    e.undo(T0 + 1).unwrap();

    // NOT deleted. `op.rs` has no Delete: Create's inverse is Trash, and
    // a trashed thing still exists — so an undone create is recoverable
    // the same way anything else in the trash is.
    assert!(e.is_trashed(id).unwrap(), "an undone create is trashed, not erased");
    assert_eq!(e.entity_count().unwrap(), 1);
}

#[test]
fn undoing_a_set_puts_the_old_value_back() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("first"), T0).unwrap();
    e.set(id, prop::NAME, text("second"), T0 + 1).unwrap();
    assert_eq!(values(&e, id, prop::NAME), vec![text("second")]);

    e.undo(T0 + 2).unwrap();
    assert_eq!(values(&e, id, prop::NAME), vec![text("first")]);
}

#[test]
fn undoing_the_first_set_leaves_no_value() {
    let mut e = engine();
    let id = e.create(kind::NOTE, None, T0).unwrap();
    e.set(id, prop::NAME, text("named at last"), T0 + 1).unwrap();

    e.undo(T0 + 2).unwrap();

    // Not "" and not the old value — there was no old value. A register
    // with nothing in it is a register with nothing in it.
    assert!(values(&e, id, prop::NAME).is_empty(), "the cell is gone, not blank");
}

#[test]
fn undoing_an_add_removes_the_member() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("Roof"), T0).unwrap();
    let one = e.create(kind::PERSON, Some("Ada"), T0 + 1).unwrap();
    let two = e.create(kind::PERSON, Some("Bo"), T0 + 2).unwrap();
    e.add(id, prop::PEOPLE, Value::Ref(one), T0 + 3).unwrap();
    e.add(id, prop::PEOPLE, Value::Ref(two), T0 + 4).unwrap();

    e.undo(T0 + 5).unwrap();

    assert_eq!(values(&e, id, prop::PEOPLE), vec![Value::Ref(one)], "only the last add went");
}

#[test]
fn undoing_a_remove_puts_the_member_back() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("Roof"), T0).unwrap();
    let who = e.create(kind::PERSON, Some("Ada"), T0 + 1).unwrap();
    e.add(id, prop::PEOPLE, Value::Ref(who), T0 + 2).unwrap();
    e.remove(id, prop::PEOPLE, &Value::Ref(who), T0 + 3).unwrap();
    assert!(values(&e, id, prop::PEOPLE).is_empty());

    e.undo(T0 + 4).unwrap();

    // ONE member, not two. A set holds a value or it does not; the
    // removal retired however many dots carried it, and membership is
    // what is being restored, not the row count.
    assert_eq!(values(&e, id, prop::PEOPLE), vec![Value::Ref(who)]);
}

// ---- the stack --------------------------------------------------------

#[test]
fn undo_walks_back_one_action_at_a_time() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("one"), T0).unwrap();
    e.set(id, prop::NAME, text("two"), T0 + 1).unwrap();
    e.set(id, prop::NAME, text("three"), T0 + 2).unwrap();

    e.undo(T0 + 3).unwrap();
    assert_eq!(values(&e, id, prop::NAME), vec![text("two")]);
    e.undo(T0 + 4).unwrap();
    assert_eq!(values(&e, id, prop::NAME), vec![text("one")]);
    e.undo(T0 + 5).unwrap();
    assert!(e.is_trashed(id).unwrap(), "and the create itself");
}

#[test]
fn a_create_is_one_action_even_though_it_is_three_ops() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("Roof"), T0).unwrap();

    // One undo, not two: creating a note and giving it its kind is not
    // two things the user did (`write.rs`, `create`).
    e.undo(T0 + 1).unwrap();
    assert!(e.is_trashed(id).unwrap());
    assert!(e.undoable().unwrap().is_none(), "nothing left behind it");
}

#[test]
fn nothing_to_undo_says_so() {
    let mut e = engine();
    assert!(e.undoable().unwrap().is_none());
    assert!(matches!(e.undo(T0), Err(WriteError::NothingToUndo)));
}

#[test]
fn an_undo_is_not_itself_undone_by_the_next_undo() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("one"), T0).unwrap();
    e.set(id, prop::NAME, text("two"), T0 + 1).unwrap();

    e.undo(T0 + 2).unwrap();
    // If the undo landed on its own stack, this would put "two" back and
    // undo would be a toggle rather than a walk.
    e.undo(T0 + 3).unwrap();
    assert!(e.is_trashed(id).unwrap(), "the second undo took the create");
}

#[test]
fn redo_puts_it_back_and_undo_takes_it_again() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("one"), T0).unwrap();
    e.set(id, prop::NAME, text("two"), T0 + 1).unwrap();

    e.undo(T0 + 2).unwrap();
    assert_eq!(values(&e, id, prop::NAME), vec![text("one")]);
    e.redo(T0 + 3).unwrap();
    assert_eq!(values(&e, id, prop::NAME), vec![text("two")]);
    e.undo(T0 + 4).unwrap();
    assert_eq!(values(&e, id, prop::NAME), vec![text("one")]);
}

#[test]
fn a_fresh_write_clears_the_redo_stack() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("one"), T0).unwrap();
    e.set(id, prop::NAME, text("two"), T0 + 1).unwrap();
    e.undo(T0 + 2).unwrap();
    assert!(e.redoable().unwrap().is_some());

    e.set(id, prop::NAME, text("three"), T0 + 3).unwrap();

    // The branch you did not take is gone. Redoing into it would be
    // rewriting history that has been written over.
    assert!(e.redoable().unwrap().is_none());
    assert!(matches!(e.redo(T0 + 4), Err(WriteError::NothingToRedo)));
}

/// **The stacks are a reading of the log, not state.**
///
/// `core/` rebuilds them on load for the same reason, and it is what
/// makes undo survive a relaunch. Nothing about undo is persisted beyond
/// the ops themselves.
#[test]
fn the_stacks_survive_a_reopen() {
    let dir = std::env::temp_dir().join("liv_engine_undo_reopen");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("liv.db");

    let id = {
        let mut e = Engine::open_local(&path).unwrap();
        let id = e.create(kind::NOTE, Some("one"), T0).unwrap();
        e.set(id, prop::NAME, text("two"), T0 + 1).unwrap();
        id
    };

    let mut e = Engine::open_local(&path).unwrap();
    assert!(e.undoable().unwrap().is_some(), "a reopened box knows what it just did");
    e.undo(T0 + 2).unwrap();
    assert_eq!(values(&e, id, prop::NAME), vec![text("one")]);
    e.redo(T0 + 3).unwrap();
    assert_eq!(values(&e, id, prop::NAME), vec![text("two")]);
}

// ---- the multi-device rule --------------------------------------------

/// **Another device's action is never on your stack.**
///
/// `core/` never had to say this — it has one device and one history. Here
/// a box holds both ends of a sync, and undo means "take back what I just
/// did", not "take back the last thing that happened".
#[test]
fn undo_never_reaches_another_devices_action() {
    let mut mine = engine();
    let id = mine.create(kind::NOTE, Some("mine"), T0).unwrap();

    // A group from somewhere else, arriving the way sync delivers one.
    let theirs = Group {
        device: dev(2),
        first_seq: 0,
        hlc: Hlc { wall_ms: T0 + 1, ctr: 0 },
        author: Author::User,
        action: action::SET,
        reverses: None,
        ops: vec![Op::SetCell {
            entity: id,
            prop: prop::NAME,
            value: text("theirs"),
            replaces: vec![],
        }],
    };
    mine.receive(theirs).unwrap();

    // The newest action in the box is theirs. Mine is what undo takes.
    let next = mine.undoable().unwrap().expect("my create is still undoable");
    assert_eq!(next.device, dev(1));
    mine.undo(T0 + 2).unwrap();
    assert!(mine.is_trashed(id).unwrap());
}

// ---- the gate ---------------------------------------------------------

/// An undo is ordinary history: it replays like anything else.
#[test]
fn an_undone_box_replays_identically() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("one"), T0).unwrap();
    e.set(id, prop::NAME, text("two"), T0 + 1).unwrap();
    e.undo(T0 + 2).unwrap();
    e.redo(T0 + 3).unwrap();
    e.undo(T0 + 4).unwrap();

    let before = e.digest().unwrap();
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), before, "the replay gate holds over undo");
}

