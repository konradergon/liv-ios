//! Renaming ONE VALUE everywhere it is carried.
//!
//! The contract is `core/`'s (`services/src/content.rs::rename_value`),
//! because this is a user-facing verb the shell already has a door for and
//! two of them behaving differently is a defect.
//!
//! **Why it cannot be N writes from the shell.** A rename onto a name that
//! is already taken is a MERGE, and only the store can see every carrier
//! at once. One grouped transaction, one undo step.
//!
//! The shape of the answer differs by what the property holds, and that is
//! the whole design:
//!
//! * a **select or status** keeps its values as option ENTITIES, so a
//!   plain rename is ONE write to that option's name and every carrier
//!   re-renders for free — the reason references exist;
//! * a **text** property carries the words in each cell, so every carrier
//!   is rewritten.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_787_391_635_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

/// A select property with two options, and three tasks carrying them.
fn board(e: &mut Engine) -> (EntityId, EntityId, EntityId, Vec<EntityId>) {
    let field = e.declare_field("stage", "select", false, T0).unwrap();
    let doing = e.declare(kind::OPTION, "Doing", T0 + 1).unwrap();
    let done = e.declare(kind::OPTION, "Done", T0 + 2).unwrap();
    e.add(field, prop::OPTIONS, Value::Ref(doing), T0 + 3).unwrap();
    e.add(field, prop::OPTIONS, Value::Ref(done), T0 + 4).unwrap();

    let mut tasks = Vec::new();
    for i in 0..3 {
        let t = e.create(kind::TASK, Some(&format!("task {i}")), T0 + 10 + i).unwrap();
        e.set(t, field, Value::Ref(doing), T0 + 10 + i).unwrap();
        tasks.push(t);
    }
    (field, doing, done, tasks)
}

// ---- a select: one write, because references ---------------------------

#[test]
fn renaming_an_option_is_one_write_and_every_carrier_follows() {
    let mut e = engine();
    let (field, doing, _, tasks) = board(&mut e);
    let before = e.group_count().unwrap();

    let n = e.rename_value(field, "Doing", "In progress", T0 + 20).unwrap();

    assert_eq!(n, 3, "three carriers changed");
    assert_eq!(e.name(doing).unwrap().as_deref(), Some("In progress"));
    assert_eq!(e.group_count().unwrap(), before + 1, "ONE group");
    // The carriers were not touched at all — they point at the option,
    // and the option is what has a name.
    for t in tasks {
        assert_eq!(e.one(t, field).unwrap(), Some(Value::Ref(doing)));
    }
}

#[test]
fn renaming_onto_a_taken_name_merges() {
    let mut e = engine();
    let (field, doing, done, tasks) = board(&mut e);

    let n = e.rename_value(field, "Doing", "Done", T0 + 20).unwrap();

    assert_eq!(n, 3);
    for t in tasks {
        assert_eq!(e.one(t, field).unwrap(), Some(Value::Ref(done)), "repointed");
    }
    assert!(e.is_trashed(doing).unwrap(), "the loser is trashed");
    // And detached, so it stops being offered in the picker.
    let options = e.cell(field, prop::OPTIONS).unwrap();
    assert!(!options.iter().any(|(_, v)| *v == Value::Ref(doing)), "and detached");
    assert!(options.iter().any(|(_, v)| *v == Value::Ref(done)));
}

#[test]
fn a_merge_is_one_undo() {
    let mut e = engine();
    let (field, doing, done, tasks) = board(&mut e);
    e.rename_value(field, "Doing", "Done", T0 + 20).unwrap();

    e.undo(T0 + 21).unwrap();

    assert!(!e.is_trashed(doing).unwrap(), "the loser is back");
    for t in tasks {
        assert_eq!(e.one(t, field).unwrap(), Some(Value::Ref(doing)), "and so are the carriers");
    }
    let options = e.cell(field, prop::OPTIONS).unwrap();
    assert!(options.iter().any(|(_, v)| *v == Value::Ref(doing)), "and it is offered again");
    assert!(options.iter().any(|(_, v)| *v == Value::Ref(done)));
}

#[test]
fn case_does_not_hide_an_option() {
    let mut e = engine();
    let (field, doing, _, _) = board(&mut e);
    // What the user types is what they see, give or take the shift key.
    assert_eq!(e.rename_value(field, "doing", "Started", T0 + 20).unwrap(), 3);
    assert_eq!(e.name(doing).unwrap().as_deref(), Some("Started"));
}

// ---- text: the words are in the cells ---------------------------------

#[test]
fn renaming_a_text_value_rewrites_its_carriers() {
    let mut e = engine();
    let field = e.declare_field("client", "text", false, T0).unwrap();
    let mut carriers = Vec::new();
    for i in 0..3 {
        let t = e.create(kind::TASK, Some(&format!("task {i}")), T0 + 1 + i).unwrap();
        e.set(t, field, Value::Text("Acme".into()), T0 + 1 + i).unwrap();
        carriers.push(t);
    }
    let other = e.create(kind::TASK, Some("elsewhere"), T0 + 9).unwrap();
    e.set(other, field, Value::Text("Beta".into()), T0 + 9).unwrap();

    let n = e.rename_value(field, "Acme", "Acme Ltd", T0 + 20).unwrap();

    assert_eq!(n, 3);
    for t in carriers {
        assert_eq!(e.one(t, field).unwrap(), Some(Value::Text("Acme Ltd".into())));
    }
    assert_eq!(
        e.one(other, field).unwrap(),
        Some(Value::Text("Beta".into())),
        "and nothing else moved"
    );
}

/// **Backstage plumbing is not a carrier.**
///
/// Options, declared fields and the rest are name-keyed working entities.
/// `rename_value(prop::NAME, …)` over all of them would rewrite the
/// lookups themselves — which is the P19 review's finding in `core/`, and
/// the reason its text branch walks user entities only.
#[test]
fn a_rename_does_not_touch_the_furniture() {
    let mut e = engine();
    let field = e.declare_field("client", "text", false, T0).unwrap();
    let option = e.declare(kind::OPTION, "Acme", T0 + 1).unwrap();
    let task = e.create(kind::TASK, Some("Acme"), T0 + 2).unwrap();

    let n = e.rename_value(prop::NAME, "Acme", "Acme Ltd", T0 + 20).unwrap();

    assert_eq!(n, 1, "the task, not the option");
    assert_eq!(e.name(task).unwrap().as_deref(), Some("Acme Ltd"));
    assert_eq!(e.name(option).unwrap().as_deref(), Some("Acme"), "the option is untouched");
    let _ = field;
}

// ---- refusals ---------------------------------------------------------

#[test]
fn the_refusals_are_the_ones_core_makes() {
    let mut e = engine();
    let (field, _, _, _) = board(&mut e);

    assert!(matches!(
        e.rename_value(field, "Doing", "   ", T0 + 20),
        Err(RenameError::Refused(_))
    ));
    assert!(matches!(
        e.rename_value(field, "Doing", "Doing", T0 + 20),
        Err(RenameError::Refused(_))
    ));
    assert!(
        matches!(e.rename_value(field, "Nothing", "Something", T0 + 20), Err(RenameError::Refused(_))),
        "no such value"
    );

    // A date does not rename. Vocabulary only.
    let due = e.declare_field("shipped", "datetime", false, T0 + 30).unwrap();
    assert!(matches!(
        e.rename_value(due, "x", "y", T0 + 31),
        Err(RenameError::Refused(_))
    ));
}

/// **An ambiguous rename refuses; it never guesses.**
///
/// Two kinds sharing an option name is the DESIGNED state of `status` —
/// the options are scoped by `for-type`, with no cross-kind dedup — so a
/// rename keyed by name alone cannot pick one. `core/` refuses for exactly
/// this reason (the P19 review) and so does this.
#[test]
fn two_options_sharing_a_name_refuse_rather_than_guess() {
    let mut e = engine();
    let field = e.declare_field("stage", "select", false, T0).unwrap();
    let one = e.declare(kind::OPTION, "Done", T0 + 1).unwrap();
    let two = e.declare(kind::OPTION, "Done", T0 + 2).unwrap();
    e.add(field, prop::OPTIONS, Value::Ref(one), T0 + 3).unwrap();
    e.add(field, prop::OPTIONS, Value::Ref(two), T0 + 4).unwrap();

    assert!(matches!(
        e.rename_value(field, "Done", "Shipped", T0 + 20),
        Err(RenameError::Ambiguous(_))
    ));
    // And the same for the name it would merge INTO.
    let doing = e.declare(kind::OPTION, "Doing", T0 + 5).unwrap();
    e.add(field, prop::OPTIONS, Value::Ref(doing), T0 + 6).unwrap();
    assert!(matches!(
        e.rename_value(field, "Doing", "Done", T0 + 21),
        Err(RenameError::Ambiguous(_))
    ));
}

#[test]
fn renaming_an_option_nothing_carries_still_renames_it() {
    // Zero carriers is not a refusal: the option is in the picker and the
    // user is fixing its name.
    let mut e = engine();
    let field = e.declare_field("stage", "select", false, T0).unwrap();
    let option = e.declare(kind::OPTION, "Dong", T0 + 1).unwrap();
    e.add(field, prop::OPTIONS, Value::Ref(option), T0 + 2).unwrap();

    assert_eq!(e.rename_value(field, "Dong", "Doing", T0 + 20).unwrap(), 0);
    assert_eq!(e.name(option).unwrap().as_deref(), Some("Doing"));
}

#[test]
fn a_renamed_box_replays_identically() {
    let mut e = engine();
    let (field, _, _, _) = board(&mut e);
    e.rename_value(field, "Doing", "Done", T0 + 20).unwrap();

    let before = e.digest().unwrap();
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), before);
}
