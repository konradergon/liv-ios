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
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, area::WORK);

    e.accept(&p, T0 + 1).unwrap();

    assert_eq!(e.one(scrap, prop::AREA).unwrap(), Some(Value::Ref(area::WORK)));
    // **The proposer is preserved**, not laundered into the user. The box
    // can say afterwards which suggestions were taken, and a clerk that
    // proposes badly is answerable for it.
    let last = e.groups().unwrap().pop().unwrap();
    assert_eq!(last.author, Author::Proposer("area".into()));
}

#[test]
fn an_accepted_proposal_is_one_undo() {
    let mut e = engine();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    e.accept(&filing(scrap, area::WORK), T0 + 1).unwrap();

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
    let a = e.create(kind::NOTE, Some("one"), T0).unwrap();
    let b = e.create(kind::NOTE, Some("two"), T0 + 1).unwrap();
    let before = e.group_count().unwrap();

    e.accept_all(&[filing(a, area::WORK), filing(b, area::WORK)], T0 + 2).unwrap();

    assert_eq!(e.group_count().unwrap(), before + 1, "ONE group");
    assert_eq!(e.one(a, prop::AREA).unwrap(), Some(Value::Ref(area::WORK)));
    assert_eq!(e.one(b, prop::AREA).unwrap(), Some(Value::Ref(area::WORK)));

    e.undo(T0 + 3).unwrap();
    assert_eq!(e.one(a, prop::AREA).unwrap(), None, "and one undo takes the lot");
    assert_eq!(e.one(b, prop::AREA).unwrap(), None);
}

#[test]
fn one_bad_member_refuses_the_whole_group() {
    // All-or-nothing. Half a consent is worse than none: the user said
    // yes to a set, and a set that half-landed is not what they agreed to.
    let mut e = engine();
    let a = e.create(kind::NOTE, Some("one"), T0).unwrap();
    let good = filing(a, area::WORK);
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
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, area::WORK);

    assert!(!e.is_declined(&p).unwrap(), "not yet");
    e.decline(&p).unwrap();
    assert!(e.is_declined(&p).unwrap(), "and now it is");

    // The sweep re-derives the same draft in every process, so it is the
    // identical proposal that must be recognised — not a remembered
    // object, a recomputed one.
    assert!(e.is_declined(&filing(scrap, area::WORK)).unwrap());
}

#[test]
fn declining_one_does_not_decline_its_neighbours() {
    let mut e = engine();
    let a = e.create(kind::NOTE, Some("one"), T0).unwrap();
    let b = e.create(kind::NOTE, Some("two"), T0 + 1).unwrap();

    e.decline(&filing(a, area::WORK)).unwrap();

    assert!(!e.is_declined(&filing(b, area::WORK)).unwrap(), "a different subject");
    assert!(!e.is_declined(&filing(a, area::HOME)).unwrap(), "a different suggestion");
}

#[test]
fn the_reason_is_part_of_what_was_declined() {
    // Refusing "because it mentions Alpha" is not refusing "because it is
    // due Tuesday". A proposer that finds the same write for a better
    // reason is entitled to ask.
    let mut e = engine();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let one = filing(scrap, area::WORK);
    let mut two = filing(scrap, area::WORK);
    two.reason = "you file every kickoff under Work".into();

    e.decline(&one).unwrap();
    assert!(e.is_declined(&one).unwrap());
    assert!(!e.is_declined(&two).unwrap());
}

#[test]
fn a_refusal_survives_a_reopen_and_a_replay() {
    let dir = std::env::temp_dir().join("liv_engine_clerk");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("liv.db");

    let (scrap, p) = {
        let mut e = Engine::open_local(&path).unwrap();
        let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
        let p = filing(scrap, area::WORK);
        e.decline(&p).unwrap();
        (scrap, p)
    };
    let _ = scrap;

    let mut e = Engine::open_local(&path).unwrap();
    assert!(e.is_declined(&p).unwrap(), "a refusal outlives the process");
    // And a replay must not take it: nothing in the log could put it
    // back, which is the same rule `places` follows.
    e.replay().unwrap();
    assert!(e.is_declined(&p).unwrap(), "or the repair button");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn accepting_a_proposal_that_was_declined_still_works() {
    // The refusal stops the CLERK asking again. It is not a ban: if the
    // user later does the same thing themselves, or changes their mind
    // from a list of past suggestions, nothing should stand in the way.
    let mut e = engine();
    let scrap = e.create(kind::NOTE, Some("kickoff notes"), T0).unwrap();
    let p = filing(scrap, area::WORK);
    e.decline(&p).unwrap();

    e.accept(&p, T0 + 1).unwrap();
    assert_eq!(e.one(scrap, prop::AREA).unwrap(), Some(Value::Ref(area::WORK)));
}
