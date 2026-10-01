//! The furniture, and the promise that it cannot drift.
//!
//! **The floor is compiled in.** Everything Liv ships with — every
//! property, every kind, the three statuses — is a constant in the binary,
//! written by no op and present in no box. Two fresh boxes therefore agree
//! about all of it having exchanged nothing, which is the answer to the
//! drift `one-core.md` §4 records.
//!
//! **The box may build on it.** `what-liv-is-for.md` said "areas, fields
//! and kinds are ours, and they don't grow", then amended itself on
//! 2026-08-29: areas grow, fields grow behind a door, kinds stay ours. On
//! 2026-09-21 the owner took the amendment the rest of the way — *"areas
//! are all created by the user, so whatever fixed areas are in code should
//! be removed"* — so **no area is compiled in at all**. Every area in this
//! file is minted, alongside the declared field and the backstage
//! furniture the app draws with.
//!
//! What keeps the promise across both halves is that the distinction is
//! **seeded vs minted**, not compiled-in vs declared. A seeded thing is
//! made again on every device and the copies disagree; a minted thing is
//! made once and syncs as itself. An area now sits squarely on the minted
//! side: made once, on one device, and synced as itself.

use liv_engine::model::{furniture_of, is_furniture, label};
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
    assert_eq!(KINDS.len(), 6);
    assert_eq!(STATUSES.len(), 3);
    assert_eq!(PROPS.iter().filter(|p| p.shown).count(), 6, "six fields the user picks from");
    assert_eq!(label(status::DONE), Some("Done"));
    assert_eq!(label(kind::NOTE), Some("Note"));

    // And the other half of the same promise, since 2026-09-21: an area is
    // NOT compiled in, so neither box arrives with one to disagree about.
    // The six constants asserted here until today were the seeding bug
    // moved into the binary rather than answered.
    assert!(furniture_of(kind::AREA).is_empty(), "no area ships with the app");
    assert!(a.of_kind(kind::AREA).unwrap().is_empty(), "and a fresh box holds none");
}

#[test]
fn furniture_is_told_apart_by_a_real_discriminator() {
    // `core-decisions.md` flagged that `id < FIRST_USER_ID` dies with
    // UUIDv7, because v7 sorts by time rather than by namespace, and that
    // a real discriminator was needed. This is it.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let minted = e.mint(1_787_391_635_000);
    let work = e.declare(kind::AREA, "Work", 1_787_391_635_000).unwrap();

    assert!(is_furniture(kind::TASK));
    assert!(is_furniture(prop::DUE));
    assert!(is_furniture(status::DONE));
    assert!(!is_furniture(minted), "a minted id is not furniture");
    assert!(!is_furniture(work), "and an area is minted now — every one of them");

    // And it does not depend on ordering, which is the whole point.
    assert!(kind::TASK < minted, "furniture still sorts first, but nothing relies on it");
}

#[test]
fn every_piece_of_furniture_is_distinct_and_named() {
    use std::collections::HashSet;
    let mut seen = HashSet::new();
    let all: Vec<EntityId> = PROPS
        .iter()
        .map(|p| p.id)
        // ALL_KINDS, not KINDS: the backstage kinds are furniture too, and
        // an unnamed or colliding one would be just as wrong.
        .chain(ALL_KINDS.iter().copied())
        .chain(STATUSES.iter().copied())
        .collect();
    for id in &all {
        assert!(seen.insert(*id), "two pieces of furniture share an id: {}", id.hex());
        assert!(label(*id).is_some(), "unnamed furniture: {}", id.hex());
    }

    // The counts that are PRODUCT statements, named rather than summed —
    // a total was a number to keep up to date, and these are claims.
    assert_eq!(PROPS.iter().filter(|p| p.shown).count(), 6, "six fields the user picks from");
    assert_eq!(KINDS.len(), 6, "six kinds a create menu offers");
    assert!(furniture_of(kind::AREA).is_empty(), "and no area — the user makes every one");
    assert_eq!(STATUSES.len(), 3);

    // And the one that is an ENGINEERING statement: the app's whole
    // schema is compiled in, not seeded. A fresh `core/` box carries 51
    // property definitions; anything much below that means the engine
    // cannot hold the app.
    assert!(PROPS.len() >= 51, "the app's schema is compiled in: {} properties", PROPS.len());
}

#[test]
fn the_area_names_live_in_exactly_one_place() {
    // The current shell keeps these as a Swift constant, which
    // `one-core.md` §4 calls shell-side furnishing and a mistake. A shell
    // asks; it does not carry its own copy. Since 2026-09-21 there is no
    // copy in Rust either — the app ships no area, so the one place any of
    // these words exists is the box someone made them in, and the engine
    // is what a shell asks for them.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let names = ["Work", "Health", "Money", "Home", "Family & Friends", "Learning"];
    let minted: Vec<EntityId> =
        names.iter().map(|n| e.declare(kind::AREA, n, 1_000).unwrap()).collect();

    let read_back: Vec<String> =
        minted.iter().map(|a| e.name(*a).unwrap().expect("a minted area is named")).collect();
    let expected: Vec<String> = names.iter().map(|n| n.to_string()).collect();
    assert_eq!(read_back, expected, "the six researched rather than invented (what-liv-is-for.md)");

    // Six entities, not six constants — and no seventh copy anywhere.
    assert_eq!(e.of_kind(kind::AREA).unwrap().len(), 6);
    assert!(furniture_of(kind::AREA).is_empty(), "none of them is compiled in");
}

#[test]
fn a_value_of_the_wrong_kind_is_refused_at_the_door() {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let work = e.declare(kind::AREA, "Work", 1_000).unwrap();
    let note = e.create(kind::NOTE, Some("Roof"), 1_000).unwrap();

    // Due holds a date, not a sentence.
    let bad = e.set(note, prop::DUE, Value::Text("friday".into()), 1_001);
    assert!(matches!(bad, Err(WriteError::Refused(Refused::WrongKind))), "got {bad:?}");

    // And the right shape of value can still be the wrong kind of thing:
    // an area is not a status.
    let wrong = e.set(note, prop::STATUS, Value::Ref(work), 1_002);
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
    let health = e.declare(kind::AREA, "Health", 1_000).unwrap();
    let home = e.declare(kind::AREA, "Home", 1_000).unwrap();
    let task = e.create(kind::TASK, Some("Call the dentist"), 1_000).unwrap();

    e.set(task, prop::AREA, Value::Ref(health), 1_001).unwrap();
    e.set(task, prop::AREA, Value::Ref(home), 1_002).unwrap();

    assert_eq!(e.cell(task, prop::AREA).unwrap().len(), 1);
    assert_eq!(e.one(task, prop::AREA).unwrap(), Some(Value::Ref(home)));
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
    let health = e.declare(kind::AREA, "Health", 1_000).unwrap();
    let anna = e.create(kind::PERSON, Some("Anna"), 1_000).unwrap();
    let task = e.create(kind::TASK, Some("Call the dentist"), 1_001).unwrap();
    e.set(task, prop::AREA, Value::Ref(health), 1_002).unwrap();
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

/// **The model is closed; the store underneath it is not.** This is the
/// fact Phase 6 turns on, so it is a test rather than a paragraph.
///
/// A kind is not something a box may invent: the product says kinds do not
/// grow in daily use, so `prop::KIND` is `Holds::RefTo(kind::KIND)` and the
/// only things of that kind are frozen. But `commit` takes ops directly and
/// does not consult the model, so the log and the view carry an entity of
/// an unnamed shape perfectly well, and it survives the replay gate.
///
/// **Resolved 2026-09-13** (`rust-owns-the-mechanisms.md` §2): the model
/// learned to name what the box holds. Kinds stay ours — this test still
/// passes, and should — but areas, fields, options and the backstage
/// furniture are minted entities now, and the tests below cover them.
#[test]
fn the_model_refuses_a_seventh_kind_but_the_store_would_have_held_it() {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let workspace_kind = e.mint(2_000);
    let subject = e.mint(2_001);

    // The front door is shut, and says why.
    let refused = e.set(subject, prop::KIND, Value::Ref(workspace_kind), 2_002);
    assert!(
        matches!(refused, Err(WriteError::Refused(model::Refused::WrongClass))),
        "a minted id is not furniture, so it cannot be a kind: {refused:?}"
    );

    // The store behind it is a general property→value log, so the same
    // shape lands when the caller writes the ops itself.
    let named = e.mint(2_003);
    e.commit(
        vec![
            Op::CreateEntity { entity: subject },
            Op::SetCell {
                entity: subject,
                prop: named,
                value: Value::Text("Deep work".into()),
                replaces: vec![],
            },
        ],
        action::CREATE,
        Author::User,
        2_004,
    )
    .unwrap();

    assert_eq!(e.cell(subject, named).unwrap().len(), 1, "stored");
    assert_eq!(e.kind_of(subject).unwrap(), None, "and still has no kind");

    let before = e.digest().unwrap();
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), before, "an unnamed entity replays like any other");
}

// ---- the floor, and what the box builds on it -------------------------
//
// `rust-owns-the-mechanisms.md` §2: what Liv ships with is compiled in and
// never written; what the box adds is an entity, minted once. These are
// the tests that say the second half works, because until 2026-09-13 it
// did not — the engine could not express thirteen of the nineteen things
// the app's snapshot carries.

/// **Areas grow** (`what-liv-is-for.md`, amended 2026-08-29), and since
/// 2026-09-21 growing is all they do: *"areas are all created by the user,
/// so whatever fixed areas are in code should be removed"*. There is no
/// frozen area left for a seventh to sit beside, so this is the whole
/// story — an area is an ordinary entity, and the area cell takes it by
/// the same rule that guards every other reference.
#[test]
fn an_area_is_minted_and_the_cell_takes_it_like_any_other_reference() {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let home = e.declare(kind::AREA, "Home", 1_000).unwrap();
    let task = e.create(kind::TASK, Some("Plane the door"), 1_000).unwrap();

    // One the user made.
    e.set(task, prop::AREA, Value::Ref(home), 1_001).unwrap();
    assert_eq!(e.one(task, prop::AREA).unwrap(), Some(Value::Ref(home)));

    // And another, in the same cell, by the same verb.
    let woodworking = e.declare(kind::AREA, "Woodworking", 1_002).unwrap();
    e.set(task, prop::AREA, Value::Ref(woodworking), 1_003).unwrap();
    assert_eq!(e.one(task, prop::AREA).unwrap(), Some(Value::Ref(woodworking)));
    assert_eq!(e.name(woodworking).unwrap().as_deref(), Some("Woodworking"));

    // Neither shipped with the app. The difference "Home" used to make
    // here — frozen against minted — is what the ruling removed.
    assert!(!model::is_furniture(home), "minted, not frozen");
    assert!(!model::is_furniture(woodworking), "minted, not frozen");
    // And both answer the same question the same way, which is what makes
    // the cell check work for both.
    assert_eq!(e.kind_of_any(home).unwrap(), Some(kind::AREA));
    assert_eq!(e.kind_of_any(woodworking).unwrap(), Some(kind::AREA));

    // The constraint is still real: a person is not an area.
    let anna = e.create(kind::PERSON, Some("Anna"), 1_004).unwrap();
    assert!(
        matches!(
            e.set(task, prop::AREA, Value::Ref(anna), 1_005),
            Err(WriteError::Refused(model::Refused::WrongClass))
        ),
        "a minted entity of the wrong kind is still refused"
    );
}

/// The product's *"new kind of field, behind a door in Settings"*. It
/// describes itself in cells, and the engine reads its shape back out and
/// enforces it — which is the whole difference between a declared field
/// and a property the engine merely tolerates.
#[test]
fn a_declared_field_describes_itself_and_is_then_enforced() {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let mileage = e.declare_field("mileage", "number", false, 2_000).unwrap();
    let trip = e.create(kind::EVENT, Some("Drive to the coast"), 2_001).unwrap();

    let shape = e.prop_shape(mileage).unwrap().expect("declared");
    assert_eq!(shape, PropShape { holds: Holds::Number, many: false });

    e.set(trip, mileage, Value::Number(412.0), 2_002).unwrap();
    assert_eq!(e.one(trip, mileage).unwrap(), Some(Value::Number(412.0)));

    // Declared means CHECKED. A sentence in a number field is refused at
    // the door, exactly as it would be for one of ours.
    assert!(matches!(
        e.set(trip, mileage, Value::Text("a lot".into()), 2_003),
        Err(WriteError::Refused(model::Refused::WrongKind))
    ));
    // And the cardinality it declared is enforced too.
    assert!(matches!(
        e.add(trip, mileage, Value::Number(1.0), 2_004),
        Err(WriteError::WrongCardinality { .. })
    ));

    // It survives the gate like anything else — including its own shape,
    // which is read back from the replayed view.
    let before = e.digest().unwrap();
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), before);
    assert_eq!(e.prop_shape(mileage).unwrap(), Some(shape), "its shape replays with it");
}

/// A property nobody declared is still stored and still has no opinion
/// attached — the promise the engine made before any of this, kept.
#[test]
fn an_undeclared_property_is_stored_without_an_opinion() {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let note = e.create(kind::NOTE, Some("Scratch"), 3_000).unwrap();
    let nothing = e.mint(3_001);

    e.set(note, nothing, Value::Text("anything".into()), 3_002).unwrap();
    e.set(note, nothing, Value::Number(7.0), 3_003).unwrap();
    assert_eq!(e.prop_shape(nothing).unwrap(), None, "no shape to enforce");
    assert_eq!(e.one(note, nothing).unwrap(), Some(Value::Number(7.0)));
}

/// **The thirteen the engine could not hold.** Workspaces, saved views,
/// layers, widgets, habits and pins are entities in a `core/` box and had
/// no word in the engine at all. They are kinds now, so the chrome the app
/// draws is expressible — which is what unblocks the snapshot work.
#[test]
fn the_backstage_furniture_the_app_draws_is_expressible() {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();

    let all = e.declare(kind::WORKSPACE, "All", 4_000).unwrap();
    let deep = e.declare(kind::WORKSPACE, "Deep work", 4_001).unwrap();
    e.set(deep, prop::PARENT, Value::Ref(all), 4_002).unwrap();
    e.set(deep, prop::QUERY, Value::Text("area:Work".into()), 4_003).unwrap();
    e.set(deep, prop::ORDER, Value::Number(1.5), 4_004).unwrap();
    e.set(deep, prop::EMOJI, Value::Text("🌲".into()), 4_005).unwrap();
    e.set(deep, prop::FAVORITE, Value::Bool(true), 4_006).unwrap();

    let view = e.declare(kind::VIEW, "Due this week", 4_007).unwrap();
    e.set(view, prop::WORKSPACE, Value::Ref(deep), 4_008).unwrap();

    let habit = e.declare(kind::HABIT, "Run", 4_009).unwrap();
    e.set(habit, prop::CADENCE, Value::Text("daily".into()), 4_010).unwrap();
    let checkin = e.create(kind::CHECKIN, None, 4_011).unwrap();
    e.set(checkin, prop::HABIT, Value::Ref(habit), 4_012).unwrap();

    let widget = e.declare(kind::WIDGET, "Today", 4_013).unwrap();
    e.set(widget, prop::ORDER, Value::Number(0.5), 4_014).unwrap();
    let layer = e.declare(kind::LAYER, "Morning", 4_015).unwrap();
    let pin = e.create(kind::PIN, None, 4_016).unwrap();
    e.set(pin, prop::PARENT, Value::Ref(deep), 4_017).unwrap();

    // Every reference above was constrained to a kind and every one held.
    assert_eq!(e.kind_of(deep).unwrap(), Some(kind::WORKSPACE));
    assert_eq!(e.one(view, prop::WORKSPACE).unwrap(), Some(Value::Ref(deep)));
    assert_eq!(e.one(checkin, prop::HABIT).unwrap(), Some(Value::Ref(habit)));
    assert_eq!(e.entity_count().unwrap(), 8);
    let _ = (widget, layer, pin);

    let before = e.digest().unwrap();
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), before, "the chrome replays like content");
}
