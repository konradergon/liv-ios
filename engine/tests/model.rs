//! The furniture, and the promise that it cannot drift.
//!
//! `what-liv-is-for.md`: *"Areas, fields and kinds are ours, and they
//! don't grow."* That is enforced here by there being nowhere to write
//! them — they are constants in the binary, not rows in a box.

use liv_engine::model::{is_furniture, label};
use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

#[test]
fn two_fresh_boxes_agree_on_the_furniture_without_exchanging_anything() {
    // THE POINT OF COMPILING IT IN. The current tree seeds this per
    // device, which is how two devices end up with two "Work" areas —
    // `one-core.md` §4 records that as the mistake. Neither box below
    // has written a single op, and both already know all of it.
    let a = Engine::open_in_memory(dev(1)).unwrap();
    let b = Engine::open_in_memory(dev(2)).unwrap();

    assert_eq!(a.group_count().unwrap(), 0, "no ops were needed");
    assert_eq!(b.group_count().unwrap(), 0);
    assert_eq!(a.entity_count().unwrap(), 0, "and no entities");

    // The furniture is identical because it is the same constants.
    assert_eq!(AREAS.len(), 6);
    assert_eq!(KINDS.len(), 6);
    assert_eq!(PROPS.iter().filter(|p| p.shown).count(), 6, "six fields the user picks from");
    assert_eq!(label(area::WORK), Some("Work"));
    assert_eq!(label(kind::NOTE), Some("Note"));
}

#[test]
fn furniture_is_told_apart_by_a_real_discriminator() {
    // `core-decisions.md` flagged that `id < FIRST_USER_ID` dies with
    // UUIDv7, because v7 sorts by time rather than by namespace, and that
    // a real discriminator was needed. This is it.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let minted = e.mint(1_787_391_635_000);

    assert!(is_furniture(area::WORK));
    assert!(is_furniture(kind::TASK));
    assert!(is_furniture(prop::DUE));
    assert!(is_furniture(status::DONE));
    assert!(!is_furniture(minted), "a minted id is not furniture");

    // And it does not depend on ordering, which is the whole point.
    assert!(area::WORK < minted, "furniture still sorts first, but nothing relies on it");
}

#[test]
fn every_piece_of_furniture_is_distinct_and_named() {
    use std::collections::HashSet;
    let mut seen = HashSet::new();
    let all: Vec<EntityId> = PROPS
        .iter()
        .map(|p| p.id)
        .chain(KINDS.iter().copied())
        .chain(AREAS.iter().copied())
        .chain(STATUSES.iter().copied())
        .collect();
    for id in &all {
        assert!(seen.insert(*id), "two pieces of furniture share an id: {}", id.hex());
        assert!(label(*id).is_some(), "unnamed furniture: {}", id.hex());
    }
    assert_eq!(all.len(), 10 + 6 + 6 + 3);
}

#[test]
fn the_area_names_live_in_exactly_one_place() {
    // The current shell keeps these as a Swift constant, which
    // `one-core.md` §4 calls shell-side furnishing and a mistake. A shell
    // asks; it does not carry its own copy.
    let names: Vec<&str> = AREAS.iter().map(|a| label(*a).unwrap()).collect();
    assert_eq!(
        names,
        vec!["Work", "Health", "Money", "Home", "Family & Friends", "Learning"],
        "the six researched rather than invented (what-liv-is-for.md)"
    );
}

#[test]
fn a_value_of_the_wrong_kind_is_refused_at_the_door() {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let note = e.create(kind::NOTE, Some("Roof"), 1_000).unwrap();

    // Due holds a date, not a sentence.
    let bad = e.set(note, prop::DUE, Value::Text("friday".into()), 1_001);
    assert!(matches!(bad, Err(WriteError::Refused(Refused::WrongKind))), "got {bad:?}");

    // And the right shape of value can still be the wrong kind of thing:
    // an area is not a status.
    let wrong = e.set(note, prop::STATUS, Value::Ref(area::WORK), 1_002);
    assert!(matches!(wrong, Err(WriteError::Refused(Refused::WrongClass))), "got {wrong:?}");

    // The right one lands.
    e.set(note, prop::STATUS, Value::Ref(status::DOING), 1_003).unwrap();
    assert_eq!(e.one(note, prop::STATUS).unwrap(), Some(Value::Ref(status::DOING)));
}

#[test]
fn a_user_created_field_is_data_and_the_engine_has_no_opinion() {
    // The product allows a seventh kind of field "behind a door in
    // Settings", so a property the model does not know is not an error.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let field = e.create(kind::NOTE, Some("Reading time"), 1_000).unwrap();
    let note = e.create(kind::NOTE, Some("An article"), 1_001).unwrap();

    e.set(note, field, Value::Text("20 minutes".into()), 1_002).unwrap();
    assert_eq!(e.one(note, field).unwrap(), Some(Value::Text("20 minutes".into())));
}

#[test]
fn asking_for_the_wrong_shape_of_write_is_refused() {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let note = e.create(kind::NOTE, None, 1_000).unwrap();
    let anna = e.create(kind::PERSON, Some("Anna"), 1_001).unwrap();

    // People is a set; setting it is the wrong verb.
    assert!(matches!(
        e.set(note, prop::PEOPLE, Value::Ref(anna), 1_002),
        Err(WriteError::WrongCardinality { many: true, .. })
    ));
    // Due is a register; adding to it is the wrong verb.
    assert!(matches!(
        e.add(note, prop::DUE, Value::Date(DateSpec::Day(1)), 1_003),
        Err(WriteError::WrongCardinality { many: false, .. })
    ));
}

#[test]
fn setting_a_register_twice_leaves_one_value() {
    // `set` names what it saw, so the second write replaces the first —
    // the caller never has to think about `replaces`.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let task = e.create(kind::TASK, Some("Call the dentist"), 1_000).unwrap();

    e.set(task, prop::AREA, Value::Ref(area::HEALTH), 1_001).unwrap();
    e.set(task, prop::AREA, Value::Ref(area::HOME), 1_002).unwrap();

    assert_eq!(e.cell(task, prop::AREA).unwrap().len(), 1);
    assert_eq!(e.one(task, prop::AREA).unwrap(), Some(Value::Ref(area::HOME)));
    assert!(!e.contended(task, prop::AREA).unwrap());
}

#[test]
fn a_person_is_referenced_by_id_which_is_why_renaming_is_one_write() {
    // The claim in core.md §2, made real: forty notes mentioning Anna
    // hold her id, not her name, so renaming her touches one cell.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let anna = e.create(kind::PERSON, Some("Anna"), 1_000).unwrap();
    let mut notes = Vec::new();
    for i in 0..40u64 {
        let n = e.create(kind::NOTE, Some(&format!("note {i}")), 1_001 + i).unwrap();
        e.add(n, prop::PEOPLE, Value::Ref(anna), 1_100 + i).unwrap();
        notes.push(n);
    }

    let before = e.group_count().unwrap();
    e.set(anna, prop::NAME, Value::Text("Anna Karlsson".into()), 2_000).unwrap();
    assert_eq!(e.group_count().unwrap(), before + 1, "renaming is ONE write");

    // And every note followed, because none of them held the name.
    for n in &notes {
        let people = e.cell(*n, prop::PEOPLE).unwrap();
        assert_eq!(people[0].1, Value::Ref(anna));
    }
    assert_eq!(e.name(anna).unwrap(), Some("Anna Karlsson".into()));
}

#[test]
fn a_set_is_add_wins_so_a_concurrent_add_survives_a_removal() {
    // `remove` names only the adds it can see. A tag added on another
    // device that this one never saw is not swept away with them.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let note = e.create(kind::NOTE, None, 1_000).unwrap();
    let invoice = e.create(kind::NOTE, Some("invoice"), 1_001).unwrap();

    e.add(note, prop::TAGS, Value::Ref(invoice), 1_002).unwrap();
    let seen: Vec<Dot> = e.cell(note, prop::TAGS).unwrap().into_iter().map(|(d, _)| d).collect();

    // Another device adds the same tag, without having seen ours.
    e.receive(Group {
        device: dev(2),
        first_seq: 0,
        hlc: Hlc { wall_ms: 1_003, ctr: 0 },
        author: Author::User,
        action: liv_engine::action::ADD,
        reverses: None,
        ops: vec![Op::AddToSet { entity: note, prop: prop::TAGS, value: Value::Ref(invoice) }],
    })
    .unwrap();
    assert_eq!(e.cell(note, prop::TAGS).unwrap().len(), 2, "two adds, one tag");

    // We remove, naming only what we had seen.
    e.commit(
        vec![Op::RemoveFromSet {
            entity: note,
            prop: prop::TAGS,
            value: Value::Ref(invoice),
            replaces: seen,
        }],
        liv_engine::action::REMOVE,
        Author::User,
        1_004,
    )
    .unwrap();

    assert_eq!(
        e.cell(note, prop::TAGS).unwrap().len(),
        1,
        "the concurrent add survives — a set is add-wins"
    );
}

#[test]
fn trash_is_soft_and_comes_back() {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let note = e.create(kind::NOTE, Some("Draft"), 1_000).unwrap();
    assert!(!e.is_trashed(note).unwrap());

    e.trash(note, 1_001).unwrap();
    assert!(e.is_trashed(note).unwrap());
    assert_eq!(e.name(note).unwrap(), Some("Draft".into()), "still there, still named");

    e.restore(note, 1_002).unwrap();
    assert!(!e.is_trashed(note).unwrap());
}

#[test]
fn the_model_survives_the_replay_gate() {
    // Everything above, then rebuilt from the log.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let anna = e.create(kind::PERSON, Some("Anna"), 1_000).unwrap();
    let task = e.create(kind::TASK, Some("Call the dentist"), 1_001).unwrap();
    e.set(task, prop::AREA, Value::Ref(area::HEALTH), 1_002).unwrap();
    e.set(task, prop::STATUS, Value::Ref(status::DOING), 1_003).unwrap();
    e.set(task, prop::DUE, Value::Date(DateSpec::Day(20_688)), 1_004).unwrap();
    e.add(task, prop::PEOPLE, Value::Ref(anna), 1_005).unwrap();
    e.trash(task, 1_006).unwrap();
    e.restore(task, 1_007).unwrap();

    let before = e.digest().unwrap();
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), before);
    assert_eq!(e.kind_of(task).unwrap(), Some(kind::TASK));
}
