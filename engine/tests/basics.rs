//! Making a thing, emptying a cell — the two verbs the six screens are
//! built out of, and the parts of them a correctness test cannot see.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_789_257_600_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

/// **A capture is UNTYPED, and the promotion proposer depends on it.**
///
/// `create` always writes a `kind`, and `promotion` returns early the
/// moment one exists — so before `capture` there was no way to make a
/// thing the clerk could offer to promote. The test for that proposer had
/// to hand-write a `RemoveFromSet` to take the kind back off, which is a
/// test building something the app cannot build.
#[test]
fn a_capture_has_no_kind_and_the_clerk_can_reach_it() {
    let mut e = engine();
    let id = e.capture("- [ ] book the ferry", T0).unwrap();

    assert_eq!(e.one(id, prop::KIND).unwrap(), None, "a capture decides nothing");
    assert!(matches!(e.one(id, prop::BODY).unwrap(), Some(Value::Rich(_))));

    // `create` is the contrast, and the reason this verb exists.
    let made = e.create(kind::NOTE, None, T0 + 1).unwrap();
    assert_eq!(e.one(made, prop::KIND).unwrap(), Some(Value::Ref(kind::NOTE)));
}

/// One group, so one undo takes the whole capture back rather than
/// leaving half of it.
///
/// Undoing it TRASHES it rather than erasing it, which is the rule for
/// anything a group created: `create`'s inverse is trash, so the thing
/// stays findable — and readable — in the Trash, which is where a person
/// has to go to get it back. This test asserted erasure at first, and
/// erasure is what would make an undone capture unrecoverable.
#[test]
fn a_capture_is_one_action_and_undoing_it_puts_it_in_the_trash() {
    let mut e = engine();
    let before = e.groups().unwrap().len();
    let id = e.capture("call the surveyor", T0).unwrap();
    assert_eq!(e.groups().unwrap().len(), before + 1, "one group, not two");

    e.undo(T0 + 1).unwrap();
    assert!(e.is_trashed(id).unwrap(), "undone, not erased");
    assert!(
        matches!(e.one(id, prop::BODY).unwrap(), Some(Value::Rich(_))),
        "and still says what it was, or the Trash is a list of blanks"
    );

    e.restore(id, T0 + 2).unwrap();
    assert!(!e.is_trashed(id).unwrap());
}

/// **Emptying an already-empty cell must write NOTHING.**
///
/// A correctness test cannot see this. Undo already looks right without
/// the guard: its backward walk stops at the last group still in effect,
/// and a `RemoveFromSet` naming no dots has no effect, so it is skipped
/// and the real write is undone either way. What the guard actually stops
/// is the LOG GROWING — a picker set to "None" twice, or a shell that
/// clears a field on every keystroke, appending a group forever.
///
/// So this counts groups, which is the only place the difference shows.
#[test]
fn emptying_an_empty_cell_appends_nothing_to_the_log() {
    let mut e = engine();
    let id = e.create(kind::TASK, Some("roof"), T0).unwrap();
    e.set(id, prop::DUE, Value::Date(DateSpec::Day(20_000)), T0 + 1).unwrap();

    assert!(e.unset(id, prop::DUE, T0 + 2).unwrap().is_some(), "the first one does something");
    let after = e.groups().unwrap().len();

    for n in 0..5 {
        assert!(e.unset(id, prop::DUE, T0 + 3 + n).unwrap().is_none(), "and the rest do not");
    }
    assert_eq!(e.groups().unwrap().len(), after, "five more taps, no more log");
}

#[test]
fn emptying_a_cell_leaves_no_value_rather_than_a_blank_one() {
    let mut e = engine();
    let id = e.create(kind::TASK, Some("roof"), T0).unwrap();
    e.set(id, prop::DUE, Value::Date(DateSpec::Day(20_000)), T0 + 1).unwrap();

    e.unset(id, prop::DUE, T0 + 2).unwrap();
    assert_eq!(e.one(id, prop::DUE).unwrap(), None);
    assert!(e.cell(id, prop::DUE).unwrap().is_empty(), "no live row at all");

    e.undo(T0 + 3).unwrap();
    assert_eq!(e.one(id, prop::DUE).unwrap(), Some(Value::Date(DateSpec::Day(20_000))));
}
