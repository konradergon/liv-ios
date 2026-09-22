//! The quarantine queue: nothing lands unconfirmed.
//!
//! `Author::Proposer` has been in the op format since Phase 2 with the
//! comment that explains it — *"a proposal is an operation that has not
//! been applied, carrying the proposer's name here instead of the user's,
//! which is what makes 'nothing lands unconfirmed' a property of the
//! type"*. This is the queue that uses it.
//!
//! **The proposals themselves are not stored, and that is `core/`'s
//! design, not a shortcut.** The sweep is a pure function of the box
//! (`services/src/clerk.rs`: *"every date the clerk proposes derives from
//! the store alone, so the sweep is identical in every process"*), so a
//! pending draft is recomputed rather than kept. What must persist is the
//! REFUSAL — declining is not forgetting, and nothing asks twice.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_787_391_635_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

/// "This scrap mentions the Alpha kickoff — file it under Work."
///
/// **The area is minted, not compiled in** (owner, 2026-09-21: *"Areas
/// are all created by the user"*). Every test below declares the areas it
/// needs on its own engine and threads the id in here — which is also
/// closer to the real thing, since a box has no area until someone makes
/// one.
fn filing(entity: EntityId, area: EntityId) -> Proposal {
    Proposal {
        ops: vec![Op::SetCell {
            entity,
            prop: prop::AREA,
            value: Value::Ref(area),
            replaces: vec![],
        }],
        proposer: "area".into(),
        reason: "mentions the Alpha kickoff".into(),
    }
}

// ---- accepting --------------------------------------------------------

#[test]
fn accepting_a_proposal_writes_it_under_the_proposers_name() {
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, work);

    e.accept(&p, T0 + 1).unwrap();

    assert_eq!(e.one(scrap, prop::AREA).unwrap(), Some(Value::Ref(work)));
    // **The proposer is preserved**, not laundered into the user. The box
    // can say afterwards which suggestions were taken, and a clerk that
    // proposes badly is answerable for it.
    let last = e.groups().unwrap().pop().unwrap();
    assert_eq!(last.author, Author::Proposer("area".into()));
}

#[test]
fn an_accepted_proposal_is_one_undo() {
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    e.accept(&filing(scrap, work), T0 + 1).unwrap();

    e.undo(T0 + 2).unwrap();
    assert_eq!(e.one(scrap, prop::AREA).unwrap(), None, "taking a suggestion is undoable");
}

#[test]
fn a_proposal_that_would_be_refused_as_a_write_is_refused_as_a_proposal() {
    // Consent is not a bypass. A suggestion goes through the same gate
    // every write does — the clerk is a proposer, not an author.
    let mut e = engine();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let nonsense = Proposal {
        ops: vec![Op::SetCell {
            entity: scrap,
            prop: prop::AREA,
            // An area cell holding a note.
            value: Value::Ref(scrap),
            replaces: vec![],
        }],
        proposer: "area".into(),
        reason: "nothing sensible".into(),
    };
    assert!(e.accept(&nonsense, T0 + 1).is_err());
    assert_eq!(e.one(scrap, prop::AREA).unwrap(), None);
}

// ---- a whole group, all or nothing ------------------------------------

#[test]
fn a_group_of_proposals_lands_as_one_action() {
    let mut e = engine();
    // Minted before `before` is read, so the area's own group is not
    // mistaken for the one the acceptance writes.
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let a = e.create(kind::NOTE, Some("one"), T0).unwrap();
    let b = e.create(kind::NOTE, Some("two"), T0 + 1).unwrap();
    let before = e.group_count().unwrap();

    e.accept_all(&[filing(a, work), filing(b, work)], T0 + 2).unwrap();

    assert_eq!(e.group_count().unwrap(), before + 1, "ONE group");
    assert_eq!(e.one(a, prop::AREA).unwrap(), Some(Value::Ref(work)));
    assert_eq!(e.one(b, prop::AREA).unwrap(), Some(Value::Ref(work)));

    e.undo(T0 + 3).unwrap();
    assert_eq!(e.one(a, prop::AREA).unwrap(), None, "and one undo takes the lot");
    assert_eq!(e.one(b, prop::AREA).unwrap(), None);
}

#[test]
fn one_bad_member_refuses_the_whole_group() {
    // All-or-nothing. Half a consent is worse than none: the user said
    // yes to a set, and a set that half-landed is not what they agreed to.
    let mut e = engine();
    // Again before `before`: the mint is setup, not part of what is
    // being counted.
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let a = e.create(kind::NOTE, Some("one"), T0).unwrap();
    let good = filing(a, work);
    let bad = Proposal {
        ops: vec![Op::SetCell {
            entity: a,
            prop: prop::AREA,
            value: Value::Ref(a),
            replaces: vec![],
        }],
        proposer: "area".into(),
        reason: "nothing sensible".into(),
    };
    let before = e.group_count().unwrap();

    assert!(e.accept_all(&[good, bad], T0 + 2).is_err());
    assert_eq!(e.group_count().unwrap(), before, "nothing was written");
    assert_eq!(e.one(a, prop::AREA).unwrap(), None);
}

#[test]
fn accepting_nothing_writes_nothing() {
    let mut e = engine();
    let before = e.group_count().unwrap();
    assert!(e.accept_all(&[], T0).is_err());
    assert_eq!(e.group_count().unwrap(), before);
}

// ---- declining is not forgetting --------------------------------------

#[test]
fn a_declined_proposal_is_never_offered_again() {
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, work);

    assert!(!e.is_declined(&p).unwrap(), "not yet");
    e.decline(&p, T0 + 1).unwrap();
    assert!(e.is_declined(&p).unwrap(), "and now it is");

    // The sweep re-derives the same draft in every process, so it is the
    // identical proposal that must be recognised — not a remembered
    // object, a recomputed one.
    assert!(e.is_declined(&filing(scrap, work)).unwrap());
}

#[test]
fn declining_one_does_not_decline_its_neighbours() {
    let mut e = engine();
    // Two areas, minted once each: two `declare`s of one name would be
    // two different areas and the second assertion would stop meaning
    // "a different suggestion".
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let home = e.declare(kind::AREA, "Home", T0).unwrap();
    let a = e.create(kind::NOTE, Some("one"), T0).unwrap();
    let b = e.create(kind::NOTE, Some("two"), T0 + 1).unwrap();

    e.decline(&filing(a, work), T0 + 2).unwrap();

    assert!(!e.is_declined(&filing(b, work)).unwrap(), "a different subject");
    assert!(!e.is_declined(&filing(a, home)).unwrap(), "a different suggestion");
}

#[test]
fn the_reason_is_part_of_what_was_declined() {
    // Refusing "because it mentions Alpha" is not refusing "because it is
    // due Tuesday". A proposer that finds the same write for a better
    // reason is entitled to ask.
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let one = filing(scrap, work);
    let mut two = filing(scrap, work);
    two.reason = "you file every kickoff under Work".into();

    e.decline(&one, T0 + 2).unwrap();
    assert!(e.is_declined(&one).unwrap());
    assert!(!e.is_declined(&two).unwrap());
}

#[test]
fn accepting_a_proposal_that_was_declined_still_works() {
    // The refusal stops the CLERK asking again. It is not a ban: if the
    // user later does the same thing themselves, or changes their mind
    // from a list of past suggestions, nothing should stand in the way.
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, work);
    e.decline(&p, T0 + 1).unwrap();

    e.accept(&p, T0 + 2).unwrap();
    assert_eq!(e.one(scrap, prop::AREA).unwrap(), Some(Value::Ref(work)));
}

// ---- a refusal travels -------------------------------------------------

/// **Refusing on the phone refuses everywhere** (owner, 2026-09-13):
/// *"if you refuse on the phone, then it should refuse on all synced
/// devices also, otherwise it isn't a good sync."*
///
/// This reverses what `core/` did and what this crate did until now — a
/// refusal beside the log rather than in it, so declining on the laptop
/// left the phone still asking. It is the whole test: the refusal is an
/// op, so it travels like every other fact.
#[test]
fn a_refusal_made_on_one_device_is_honoured_on_the_other() {
    let mut laptop = Engine::open_in_memory(dev(1)).unwrap();
    // The laptop mints the area; the phone learns it from the same
    // groups it learns the note from, so both ends mean the same area.
    let work = laptop.declare(kind::AREA, "Work", T0).unwrap();
    let scrap = laptop.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, work);

    let mut phone = Engine::open_in_memory(dev(2)).unwrap();
    for g in laptop.groups().unwrap() {
        phone.receive(g).unwrap();
    }
    assert!(!phone.is_declined(&p).unwrap(), "nothing said no yet");

    laptop.decline(&p, T0 + 1).unwrap();
    assert!(laptop.is_declined(&p).unwrap());

    for g in laptop.groups().unwrap() {
        let _ = phone.receive(g);
    }
    assert!(phone.is_declined(&p).unwrap(), "the refusal has to travel");
}

/// And it is a fact like any other: replay puts it back, because it is
/// IN the log now rather than beside it.
///
/// This is the exact reversal of what this crate asserted before. The old
/// rule was `places`'s — nothing in the log could put a device-local row
/// back, so replay had to leave it alone. A refusal is no longer that
/// kind of thing.
#[test]
fn a_refusal_survives_a_replay_because_it_is_in_the_log() {
    let dir = std::env::temp_dir().join("liv_engine_refusal_replay");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("liv.db");

    let p = {
        let mut e = Engine::open_local(&path).unwrap();
        let work = e.declare(kind::AREA, "Work", T0).unwrap();
        let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
        let p = filing(scrap, work);
        e.decline(&p, T0 + 1).unwrap();
        p
    };

    let mut e = Engine::open_local(&path).unwrap();
    assert!(e.is_declined(&p).unwrap(), "a refusal outlives the process");
    e.replay().unwrap();
    assert!(e.is_declined(&p).unwrap(), "and the repair button rebuilds it");

    let _ = std::fs::remove_dir_all(&dir);
}

/// **A fingerprint is 64 bits and a number cell is not.**
///
/// The refusal rides as the fingerprint's hex spelling, not as
/// `Value::Number`, which is an f64 with 53 bits of mantissa: storing a
/// fingerprint in one would round it, and two proposals whose prints
/// differ only in the low bits would start refusing each other.
///
/// This asserts the STORED FORM, not a round trip. A round trip proves
/// nothing here — a lossy spelling used on both sides still matches
/// itself, which is exactly how this test would have passed while being
/// worthless.
#[test]
fn a_refusal_stores_every_bit_of_its_fingerprint() {
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, work);
    let print = p.fingerprint();
    assert!(print > (1u64 << 53), "the fixture must exceed an f64's mantissa: {print}");

    e.decline(&p, T0 + 1).unwrap();

    let stored: Vec<Value> =
        e.cell(scrap, prop::DECLINED).unwrap().into_iter().map(|(_, v)| v).collect();
    assert_eq!(
        stored,
        vec![Value::Text(format!("{print:016x}"))],
        "the cell must hold all 64 bits, spelled out"
    );
    // And the spelling parses back to the exact same u64.
    let Value::Text(hex) = &stored[0] else { panic!("not text") };
    assert_eq!(u64::from_str_radix(hex, 16).unwrap(), print);
}

/// **Refusing twice is refusing once**, and the verb is what makes it so.
///
/// A set here is an observed-remove set: every `AddToSet` is its own
/// element with its own dot, which is what lets a tag added on the phone
/// survive a removal on the laptop. `Engine::add` behaves the same way,
/// deliberately. So nothing in the set layer stops a repeated tap growing
/// the box, and `decline` checks first.
///
/// The first version of this test asserted the SET did it, and the set
/// does not.
#[test]
fn refusing_twice_is_refusing_once() {
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, work);

    e.decline(&p, T0 + 1).unwrap();
    e.decline(&p, T0 + 2).unwrap();
    e.decline(&p, T0 + 3).unwrap();

    assert_eq!(e.cell(scrap, prop::DECLINED).unwrap().len(), 1, "one no, however often tapped");
    assert!(e.is_declined(&p).unwrap());

    // And one undo is enough to take it back, which is the other half of
    // why the repeat writes nothing.
    e.undo(T0 + 4).unwrap();
    assert!(!e.is_declined(&p).unwrap(), "one undo, not three");
}

/// And a refusal can be taken back, because it is an ordinary action in
/// this device's history. A mis-tap in the inbox is recoverable rather
/// than permanent — which the device-local table could not offer.
#[test]
fn a_refusal_can_be_undone() {
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, work);

    e.decline(&p, T0 + 1).unwrap();
    assert!(e.is_declined(&p).unwrap());

    e.undo(T0 + 2).unwrap();
    assert!(!e.is_declined(&p).unwrap(), "the clerk may ask again");
}
