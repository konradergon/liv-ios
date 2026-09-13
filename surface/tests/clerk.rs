//! The sweep's product rules, each of which lived only in a comment.
//!
//! `services/src/clerk.rs` has one test file's worth of coverage for six
//! proposers and a page of prose explaining why each behaves as it does.
//! This is that prose, as assertions — the port is the moment those rules
//! are either written down or lost.

use liv_engine::*;
use liv_surface::clerk::{assist_enabled, permitted, sweep, sweep_one};

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

/// 2026-09-13, a Sunday. Every id minted at this millisecond anchors here.
const T0: u64 = 1_789_257_600_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

/// A scrap: no kind, a body, nothing filed.
fn scrap(e: &mut Engine, text: &str) -> EntityId {
    let id = e.create(kind::NOTE, None, T0).unwrap();
    // `create` gives it a kind; a real capture has none, and the
    // promotion proposer turns on exactly that.
    e.set_content(id, vec![Span::text(text)], 0, T0).unwrap();
    id
}

fn reasons(e: &Engine) -> Vec<String> {
    sweep(e).unwrap().into_iter().map(|p| p.reason).collect()
}

fn proposers(e: &Engine) -> Vec<String> {
    sweep(e).unwrap().into_iter().map(|p| p.proposer).collect()
}

// ---- the gate ----------------------------------------------------------

#[test]
fn absent_or_true_is_on_and_only_an_explicit_false_silences_it() {
    let mut e = engine();
    scrap(&mut e, "call anna tomorrow");
    assert!(assist_enabled(&e).unwrap(), "an older box never said no");
    assert!(!sweep(&e).unwrap().is_empty());

    let settings = e.create(kind::NOTE, Some("settings"), T0).unwrap();
    e.set(settings, prop::AUTOMATION, Value::Bool(true), T0 + 1).unwrap();
    assert!(assist_enabled(&e).unwrap(), "and true is still on");

    e.set(settings, prop::AUTOMATION, Value::Bool(false), T0 + 2).unwrap();
    assert!(!assist_enabled(&e).unwrap());
    assert!(sweep(&e).unwrap().is_empty(), "off means SILENCE, not fewer");
}

// ---- dates -------------------------------------------------------------

#[test]
fn the_first_date_word_wins() {
    let mut e = engine();
    let id = scrap(&mut e, "post it tomorrow, or 2026-12-25 at the latest");
    let p = sweep(&e).unwrap();
    let dated = p.iter().find(|p| p.proposer == "dates").expect("a date");
    assert!(dated.reason.contains("tomorrow"), "{}", dated.reason);
    assert_eq!(
        dated.ops,
        vec![Op::SetCell {
            entity: id,
            prop: prop::DUE,
            value: Value::Date(DateSpec::Day(days_from_civil(2026, 9, 14))),
            replaces: vec![],
        }]
    );
}

/// **"Tomorrow" means the day after the THOUGHT, not the day after the
/// sweep.** A proposal that drifts with the clock is a lie waiting for
/// midnight, and it would also mean the inbox showed one thing and
/// accepting committed another.
#[test]
fn a_relative_date_anchors_on_when_it_was_written() {
    let mut e = engine();
    // Two scraps a week apart, with the same words.
    let older = e.create(kind::NOTE, None, T0).unwrap();
    e.set_content(older, vec![Span::text("ring them tomorrow")], 0, T0).unwrap();
    let newer = e.create(kind::NOTE, None, T0 + 7 * 86_400_000).unwrap();
    e.set_content(newer, vec![Span::text("ring them tomorrow")], 0, T0 + 7 * 86_400_000)
        .unwrap();

    let p = sweep(&e).unwrap();
    let day = |id: EntityId| {
        p.iter()
            .find(|p| p.proposer == "dates" && p.ops[0].entity() == id)
            .and_then(|p| match &p.ops[0] {
                Op::SetCell { value: Value::Date(DateSpec::Day(d)), .. } => Some(*d),
                _ => None,
            })
            .expect("a date for each")
    };
    assert_eq!(day(newer) - day(older), 7, "each anchored on its own day");
}

#[test]
fn a_weekday_is_the_next_one_and_today_counts() {
    let mut e = engine();
    // T0 is a Sunday.
    let sunday = scrap(&mut e, "due sunday");
    let monday = scrap(&mut e, "due monday");
    let saturday = scrap(&mut e, "due saturday");

    let p = sweep(&e).unwrap();
    let day = |id: EntityId| {
        p.iter()
            .find(|p| p.proposer == "dates" && p.ops[0].entity() == id)
            .and_then(|p| match &p.ops[0] {
                Op::SetCell { value: Value::Date(DateSpec::Day(d)), .. } => Some(*d),
                _ => None,
            })
            .expect("a date")
    };
    let anchor = days_from_civil(2026, 9, 13);
    assert_eq!(day(sunday), anchor, "the anchor's own weekday is today, not a week away");
    assert_eq!(day(monday), anchor + 1);
    assert_eq!(day(saturday), anchor + 6);
}

#[test]
fn an_iso_date_is_validated_enough_not_to_be_a_lie() {
    let mut e = engine();
    scrap(&mut e, "not 2026-13-01 nor 2026-02-30 nor -234-01-01");
    assert!(
        !proposers(&e).contains(&"dates".to_owned()),
        "a month of 13, a February 30th and a negative year are not dates"
    );

    let mut e = engine();
    scrap(&mut e, "leap day 2028-02-29 exists");
    assert!(proposers(&e).contains(&"dates".to_owned()));
}

#[test]
fn the_clerk_suggests_and_never_competes() {
    let mut e = engine();
    let id = scrap(&mut e, "call anna tomorrow");
    assert!(proposers(&e).contains(&"dates".to_owned()));

    e.set(id, prop::DUE, Value::Date(DateSpec::Day(20_000)), T0 + 1).unwrap();
    assert!(
        !proposers(&e).contains(&"dates".to_owned()),
        "something already due gets no date proposal"
    );
}

// ---- mentions ----------------------------------------------------------

#[test]
fn a_known_name_in_the_text_is_a_proposed_relation() {
    let mut e = engine();
    let anna = e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    let id = scrap(&mut e, "call anna about the roof");

    let p = sweep(&e).unwrap();
    let m = p.iter().find(|p| p.proposer == "mentions").expect("a mention");
    assert_eq!(m.ops, vec![Op::AddToSet { entity: id, prop: prop::RELATED, value: Value::Ref(anna) }]);
    assert!(m.reason.contains("Anna"), "named as written: {}", m.reason);
}

/// **Whole words.** "anna" is in "call anna friday" and not in "susanna".
///
/// This one is held by the gazetteer's first-word PREFILTER — "susanna"
/// tokenises to one word and never reaches the boundary check at all.
/// Worth keeping as itself, and not to be mistaken for a test of
/// `contains_word`, which is the one below.
#[test]
fn a_name_inside_another_word_is_not_a_mention() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    scrap(&mut e, "susanna wrote back");
    assert!(!proposers(&e).contains(&"mentions".to_owned()));
}

/// And THIS is the boundary check, because only a multi-word name can get
/// past the prefilter and still not be there: "Anna Karlsson" against
/// "anna karlssonx" hits the prefilter on "anna" and must then be refused
/// on the trailing letter.
#[test]
fn a_multi_word_name_still_needs_a_boundary_at_both_ends() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna Karlsson"), T0).unwrap();
    scrap(&mut e, "anna karlssonx wrote back");
    assert!(!proposers(&e).contains(&"mentions".to_owned()));

    let mut e = engine();
    e.create(kind::PERSON, Some("Anna Karlsson"), T0).unwrap();
    scrap(&mut e, "anna karlsson wrote back");
    assert!(proposers(&e).contains(&"mentions".to_owned()), "and the real one still lands");
}

#[test]
fn a_thing_does_not_mention_itself() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("Roof project"), T0).unwrap();
    e.set_content(id, vec![Span::text("the roof project needs a surveyor")], 0, T0).unwrap();
    assert!(!proposers(&e).contains(&"mentions".to_owned()));
}

#[test]
fn a_name_already_related_is_not_proposed_again() {
    let mut e = engine();
    let anna = e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    let id = scrap(&mut e, "call anna about the roof");
    e.add(id, prop::RELATED, Value::Ref(anna), T0 + 1).unwrap();
    assert!(!proposers(&e).contains(&"mentions".to_owned()));
}

/// Two characters would match half the box.
#[test]
fn a_name_under_three_characters_is_not_a_name() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Jo"), T0).unwrap();
    scrap(&mut e, "ask jo about it");
    assert!(!proposers(&e).contains(&"mentions".to_owned()));
}

/// **A paragraph boundary is a boundary**, and this is a deliberate
/// correction. `core/` flattened a body by joining its text runs with a
/// SPACE and dropping the breaks, so "Anna" ending one paragraph and
/// "Karlsson" opening the next read as the full name and matched. Here a
/// break is a newline, so it does not.
#[test]
fn a_name_split_across_a_paragraph_is_not_a_mention() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna Karlsson"), T0).unwrap();
    let id = e.create(kind::NOTE, None, T0).unwrap();
    e.set_content(
        id,
        vec![Span::text("ask Anna"), Span::Break(Block::Body), Span::text("Karlsson replied")],
        0,
        T0,
    )
    .unwrap();
    assert!(!proposers(&e).contains(&"mentions".to_owned()));
}

// ---- area --------------------------------------------------------------

#[test]
fn where_it_goes_is_read_off_what_it_mentions() {
    let mut e = engine();
    let anna = e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    e.set(anna, prop::AREA, Value::Ref(area::WORK), T0 + 1).unwrap();
    let id = scrap(&mut e, "call anna about the roof");

    let p = sweep(&e).unwrap();
    let a = p.iter().find(|p| p.proposer == "area").expect("an area");
    assert_eq!(
        a.ops,
        vec![Op::SetCell {
            entity: id,
            prop: prop::AREA,
            value: Value::Ref(area::WORK),
            replaces: vec![]
        }]
    );
    assert!(a.reason.contains("Work"), "the area named, not numbered: {}", a.reason);
}

/// **Two areas is a coin flip, and the clerk does not flip coins.**
#[test]
fn two_mentions_filed_differently_say_nothing() {
    let mut e = engine();
    let anna = e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    let bruno = e.create(kind::PERSON, Some("Bruno"), T0).unwrap();
    e.set(anna, prop::AREA, Value::Ref(area::WORK), T0 + 1).unwrap();
    e.set(bruno, prop::AREA, Value::Ref(area::HOME), T0 + 2).unwrap();
    scrap(&mut e, "anna and bruno both replied");

    assert!(!proposers(&e).contains(&"area".to_owned()));
}

#[test]
fn a_mention_filed_nowhere_says_nothing_and_does_not_veto() {
    let mut e = engine();
    let anna = e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    e.create(kind::PERSON, Some("Bruno"), T0).unwrap();
    e.set(anna, prop::AREA, Value::Ref(area::WORK), T0 + 1).unwrap();
    scrap(&mut e, "anna and bruno both replied");

    // Bruno is filed nowhere; he neither names an area nor blocks Anna's.
    assert!(proposers(&e).contains(&"area".to_owned()));
}

// ---- priority ----------------------------------------------------------

#[test]
fn a_priority_word_proposes_only_a_real_option() {
    let mut e = engine();
    scrap(&mut e, "this one is URGENT");
    assert!(
        !proposers(&e).contains(&"priority".to_owned()),
        "no such option in the box — stay quiet, never invent"
    );

    let high = e.declare(kind::OPTION, "High", T0 + 1).unwrap();
    e.add(prop::PRIORITY, prop::OPTIONS, Value::Ref(high), T0 + 2).unwrap();
    let p = sweep(&e).unwrap();
    let pr = p.iter().find(|p| p.proposer == "priority").expect("a priority");
    assert!(matches!(&pr.ops[0], Op::SetCell { prop, value: Value::Ref(o), .. }
        if *prop == prop::PRIORITY && *o == high));
}

#[test]
fn the_lexicon_is_closed() {
    let mut e = engine();
    let high = e.declare(kind::OPTION, "High", T0).unwrap();
    let low = e.declare(kind::OPTION, "Low", T0).unwrap();
    e.add(prop::PRIORITY, prop::OPTIONS, Value::Ref(high), T0 + 1).unwrap();
    e.add(prop::PRIORITY, prop::OPTIONS, Value::Ref(low), T0 + 2).unwrap();

    for (text, want) in [
        ("this is urgent", Some(high)),
        ("do it asap", Some(high)),
        ("fix the roof!!!", Some(high)),
        ("low priority, this one", Some(low)),
        ("do it whenever", Some(low)),
        ("quite important really", None),
        ("pressing matter", None),
    ] {
        let mut e2 = Engine::open_in_memory(dev(2)).unwrap();
        let h = e2.declare(kind::OPTION, "High", T0).unwrap();
        let l = e2.declare(kind::OPTION, "Low", T0).unwrap();
        e2.add(prop::PRIORITY, prop::OPTIONS, Value::Ref(h), T0 + 1).unwrap();
        e2.add(prop::PRIORITY, prop::OPTIONS, Value::Ref(l), T0 + 2).unwrap();
        let id = e2.create(kind::NOTE, None, T0).unwrap();
        e2.set_content(id, vec![Span::text(text)], 0, T0).unwrap();
        let got = sweep(&e2)
            .unwrap()
            .into_iter()
            .find(|p| p.proposer == "priority")
            .map(|p| match &p.ops[0] {
                Op::SetCell { value: Value::Ref(o), .. } => *o,
                _ => panic!(),
            });
        let want = want.map(|w| if w == high { h } else { l });
        assert_eq!(got, want, "{text}");
    }
    let _ = (high, low);
}

// ---- promotion ---------------------------------------------------------

#[test]
fn a_capture_that_opens_with_a_checkbox_is_a_task_waiting_for_its_kind() {
    let mut e = engine();
    let id = e.create(kind::NOTE, None, T0).unwrap();
    // A capture has no kind. `create` gives one, so take it back.
    e.commit(
        vec![Op::RemoveFromSet {
            entity: id,
            prop: prop::KIND,
            value: Value::Ref(kind::NOTE),
            replaces: e.cell(id, prop::KIND).unwrap().into_iter().map(|(d, _)| d).collect(),
        }],
        action::SET,
        Author::User,
        T0 + 1,
    )
    .unwrap();
    e.set_content(
        id,
        vec![Span::Break(Block::Task { depth: 0, done: false }), Span::text("book the ferry")],
        0,
        T0 + 2,
    )
    .unwrap();

    let p = sweep(&e).unwrap();
    let promo = p.iter().find(|p| p.proposer == "promotion").expect("a promotion");
    // Both cells, so accepting leaves a task with a status rather than a
    // task the board cannot place.
    assert_eq!(promo.ops.len(), 2);
    assert!(matches!(&promo.ops[0], Op::SetCell { prop, value: Value::Ref(k), .. }
        if *prop == prop::KIND && *k == kind::TASK));
    assert!(matches!(&promo.ops[1], Op::SetCell { prop, value: Value::Ref(s), .. }
        if *prop == prop::STATUS && *s == status::TODO));
}

#[test]
fn something_already_typed_is_not_promoted() {
    let mut e = engine();
    let id = e.create(kind::NOTE, None, T0).unwrap();
    e.set_content(
        id,
        vec![Span::Break(Block::Task { depth: 0, done: false }), Span::text("book the ferry")],
        0,
        T0 + 1,
    )
    .unwrap();
    assert!(!proposers(&e).contains(&"promotion".to_owned()));
}

// ---- the frame ---------------------------------------------------------

#[test]
fn the_sweep_is_a_pure_function_of_the_box() {
    let mut e = engine();
    let anna = e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    e.set(anna, prop::AREA, Value::Ref(area::WORK), T0 + 1).unwrap();
    scrap(&mut e, "call anna tomorrow about the roof");
    scrap(&mut e, "email anna friday");

    let once = reasons(&e);
    assert!(once.len() >= 4);
    assert_eq!(reasons(&e), once, "the same box sweeps to the same list");
    assert_eq!(reasons(&e), once, "every time");
}

#[test]
fn backstage_and_trashed_are_not_swept() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    let gone = scrap(&mut e, "call anna tomorrow");
    e.trash(gone, T0 + 1).unwrap();
    assert!(sweep(&e).unwrap().is_empty(), "the trash is not a queue of chores");

    let plumbing = e.declare_field("client", "text", false, T0 + 2).unwrap();
    e.set_content(plumbing, vec![Span::text("call anna tomorrow")], 0, T0 + 3).unwrap();
    assert!(sweep(&e).unwrap().is_empty(), "nor is backstage furniture");
}

/// **The clerk never touches a value judgment**, and this tests the GUARD
/// rather than the current proposers.
///
/// The first version iterated over real proposals asserting none set
/// `private` — which passed with the guard deleted, because none of the
/// five ever does. An invariant about proposers nobody has written yet
/// cannot be tested through the proposers that exist; it has to be tested
/// where it lives.
#[test]
fn a_proposal_that_would_set_private_is_not_permitted() {
    let hostile = Proposal {
        ops: vec![Op::SetCell {
            entity: EntityId([0x11; 16]),
            prop: prop::PRIVATE,
            value: Value::Bool(true),
            replaces: vec![],
        }],
        proposer: "some future proposer".into(),
        reason: "it looks personal".into(),
    };
    assert!(!permitted(&hostile));

    let fine = Proposal {
        ops: vec![Op::SetCell {
            entity: EntityId([0x11; 16]),
            prop: prop::AREA,
            value: Value::Ref(area::WORK),
            replaces: vec![],
        }],
        proposer: "area".into(),
        reason: "mentions Anna".into(),
    };
    assert!(permitted(&fine));

    // And the sweep applies it.
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    scrap(&mut e, "call anna tomorrow");
    assert!(sweep(&e).unwrap().iter().all(permitted));
}

#[test]
fn a_declined_proposal_does_not_come_back() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    scrap(&mut e, "call anna tomorrow");

    let before = sweep(&e).unwrap();
    let mention = before.iter().find(|p| p.proposer == "mentions").unwrap().clone();
    e.decline(&mention).unwrap();

    let after = sweep(&e).unwrap();
    assert_eq!(after.len(), before.len() - 1);
    assert!(!after.iter().any(|p| p.proposer == "mentions"));
    // And the rest still stand — a refusal is about one suggestion.
    assert!(after.iter().any(|p| p.proposer == "dates"));
}

#[test]
fn accepting_a_proposal_stops_it_being_proposed() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    scrap(&mut e, "call anna tomorrow");

    let dated = sweep(&e).unwrap().into_iter().find(|p| p.proposer == "dates").unwrap();
    e.accept(&dated, T0 + 10).unwrap();

    assert!(
        !proposers(&e).contains(&"dates".to_owned()),
        "it is due now, so there is nothing left to suggest"
    );
}

#[test]
fn a_body_of_nothing_is_not_swept() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    let id = e.create(kind::NOTE, Some("Empty"), T0).unwrap();
    e.set_content(id, vec![Span::Break(Block::Body)], 0, T0 + 1).unwrap();
    assert!(sweep(&e).unwrap().is_empty());
}

// ---- one entity at a time ----------------------------------------------

/// **`sweep_one` must be `sweep`, narrowed — never a second opinion.**
///
/// This is the whole contract. Accepting a suggestion re-derives it from
/// the box to check the box still makes it, and it now re-derives one
/// entity rather than all of them. If the two ever disagreed, a proposal
/// the inbox showed could be unacceptable, or one it never showed could be
/// accepted — so this compares them entity by entity over a box holding
/// every proposer's trigger at once, rather than testing one case.
#[test]
fn sweeping_one_thing_says_exactly_what_sweeping_everything_said_about_it() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna Karin"), T0).unwrap();
    let sam = e.create(kind::PERSON, Some("Sam Reed"), T0 + 1).unwrap();
    let area = e.create(kind::AREA, Some("Boatyard"), T0 + 2).unwrap();
    e.set(sam, prop::AREA, Value::Ref(area), T0 + 3).unwrap();

    // One trigger per proposer, plus things that trigger nothing.
    scrap(&mut e, "call anna karin tomorrow, urgent");
    scrap(&mut e, "sam reed has the keys");
    scrap(&mut e, "nothing in here at all");
    scrap(&mut e, "ask sam reed on friday, low priority");
    let promoted = e.create(kind::NOTE, None, T0 + 20).unwrap();
    e.set_content(
        promoted,
        vec![Span::Break(rich::Block::Task { depth: 0, done: false }), Span::text("book the ferry")],
        0,
        T0 + 21,
    )
    .unwrap();

    let all = sweep(&e).unwrap();
    assert!(all.len() >= 6, "the box must actually be interesting: {}", all.len());

    for id in e.all_entities().unwrap() {
        let from_whole: Vec<u64> = all
            .iter()
            .filter(|p| p.ops.first().map(liv_engine::Op::entity) == Some(id))
            .map(|p| p.fingerprint())
            .collect();
        let from_one: Vec<u64> = sweep_one(&e, id).unwrap().iter().map(|p| p.fingerprint()).collect();
        assert_eq!(from_one, from_whole, "the two sweeps disagree about {}", id.hex());
    }
}

/// And the filters still apply when only one thing is swept: a refusal
/// silences it there too, or declining in the inbox would not stop the
/// accept path from re-offering it.
#[test]
fn sweeping_one_thing_still_honours_a_refusal_and_the_consent_gate() {
    let mut e = engine();
    e.create(kind::PERSON, Some("Anna"), T0).unwrap();
    let id = scrap(&mut e, "call anna tomorrow");

    let mine = sweep_one(&e, id).unwrap();
    assert!(mine.len() >= 2, "a date and a mention");
    e.decline(&mine[0]).unwrap();
    assert_eq!(sweep_one(&e, id).unwrap().len(), mine.len() - 1, "a refusal is remembered");

    let s = e.create(kind::NOTE, Some("settings"), T0 + 50).unwrap();
    e.set(s, prop::AUTOMATION, Value::Bool(false), T0 + 51).unwrap();
    assert!(sweep_one(&e, id).unwrap().is_empty(), "off means silent here too");
}
