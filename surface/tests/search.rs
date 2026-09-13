//! Search's rules, which were prose in `services/src/search.rs`.
//!
//! Three of them are owner rulings with dates, and each is the kind of
//! thing a port loses silently: the mode flip on `is:archived`, the
//! required-word rule, and the prefix tier for filings.

use liv_engine::*;
use liv_surface::search::{facet, facet_properties, parse, parse_mode, search, Field, Mode};

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_789_257_600_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

fn hits(e: &Engine, raw: &str) -> Vec<EntityId> {
    let s = parse(e, raw).unwrap();
    search(e, &s, usize::MAX).unwrap().into_iter().map(|h| h.id).collect()
}

// ---- is:archived cannot mean one thing ---------------------------------

/// **"Lens means only, search means include"** (owner, 2026-08-27).
///
/// The same token, opposite filters. A workspace called Archive that
/// showed everything plus the archive would be the bug this prevents.
#[test]
fn a_lens_restricts_to_the_archive_and_a_search_merely_looks_in_it() {
    let mut e = engine();
    let live = e.create(kind::NOTE, Some("live one"), T0).unwrap();
    let filed = e.create(kind::NOTE, Some("filed away"), T0 + 1).unwrap();
    e.set(filed, prop::ARCHIVED, Value::Bool(true), T0 + 2).unwrap();

    let lens = parse_mode(&e, "is:archived", Mode::Lens).unwrap();
    assert_eq!(e.run(&lens.query).unwrap(), vec![filed], "a lens shows the archive");

    let box_ = parse_mode(&e, "is:archived", Mode::Search).unwrap();
    let found = e.run(&box_.query).unwrap();
    assert!(found.contains(&live) && found.contains(&filed), "a search looks in it too");
}

#[test]
fn the_archive_is_backstage_until_asked_for() {
    let mut e = engine();
    let live = e.create(kind::NOTE, Some("live one"), T0).unwrap();
    let filed = e.create(kind::NOTE, Some("filed away"), T0 + 1).unwrap();
    e.set(filed, prop::ARCHIVED, Value::Bool(true), T0 + 2).unwrap();

    assert_eq!(hits(&e, "one"), vec![live]);
    // Vacuously true where the cell is absent — everything that never
    // took a position is still here.
    assert_eq!(hits(&e, ""), vec![live]);
}

/// `bookmarked` hides nothing, so it is an ordinary equality in both
/// modes — not every `is:` is a gate.
#[test]
fn a_flag_that_hides_nothing_is_the_same_in_both_modes() {
    let mut e = engine();
    let a = e.create(kind::NOTE, Some("kept"), T0).unwrap();
    e.create(kind::NOTE, Some("ordinary"), T0 + 1).unwrap();
    e.set(a, prop::BOOKMARKED, Value::Bool(true), T0 + 2).unwrap();

    for mode in [Mode::Search, Mode::Lens] {
        let s = parse_mode(&e, "is:bookmarked", mode).unwrap();
        assert_eq!(e.run(&s.query).unwrap(), vec![a], "{mode:?}");
    }
}

// ---- a typo shows nothing ----------------------------------------------

/// **Every free-text word is REQUIRED** (owner, 2026-08-27). A search that
/// quietly drops the word you misspelled shows a confident list of the
/// wrong things.
#[test]
fn a_word_that_matches_nothing_drops_the_row() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("roof survey"), T0).unwrap();
    assert_eq!(hits(&e, "roof"), vec![id]);
    assert_eq!(hits(&e, "roof survey"), vec![id]);
    assert!(hits(&e, "roof zzzz").is_empty(), "both words, or nothing");
}

/// And an unresolvable qualifier becomes one of those required words,
/// rather than being dropped.
#[test]
fn an_unresolvable_qualifier_is_words() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("the link"), T0).unwrap();
    e.set_content(id, vec![Span::text("see http://example.com for it")], 0, T0 + 1).unwrap();

    // No property is called `http`, so the whole token is a term.
    let s = parse(&e, "http://example.com").unwrap();
    assert!(s.query.constraints.iter().all(|c| c.property == prop::ARCHIVED));
    assert_eq!(s.terms, vec!["http://example.com"]);
    assert_eq!(hits(&e, "http://example.com"), vec![id]);
}

// ---- the weight ladder -------------------------------------------------

#[test]
fn a_whole_name_beats_a_prefix_beats_a_word_inside_it() {
    let mut e = engine();
    let exact = e.create(kind::NOTE, Some("roof"), T0).unwrap();
    let prefix = e.create(kind::NOTE, Some("roofing quote"), T0 + 1).unwrap();
    let inside = e.create(kind::NOTE, Some("the roof survey"), T0 + 2).unwrap();
    let body = e.create(kind::NOTE, Some("unrelated"), T0 + 3).unwrap();
    e.set_content(body, vec![Span::text("about the roof")], 0, T0 + 4).unwrap();

    assert_eq!(hits(&e, "roof"), vec![exact, prefix, inside, body]);
}

#[test]
fn where_a_term_matched_is_reported() {
    let mut e = engine();
    let named = e.create(kind::NOTE, Some("roof"), T0).unwrap();
    let bodied = e.create(kind::NOTE, Some("quote"), T0 + 1).unwrap();
    e.set_content(bodied, vec![Span::text("about the roof")], 0, T0 + 2).unwrap();

    let s = parse(&e, "roof").unwrap();
    let found = search(&e, &s, usize::MAX).unwrap();
    assert_eq!(found[0].id, named);
    assert_eq!(found[0].field, Field::Name);
    assert_eq!(found[1].id, bodied);
    assert_eq!(found[1].field, Field::Content);
}

/// **The filing tier takes a PREFIX and the body tier does not.**
///
/// The owner's report: a note filed under "Testjunk" could not be found by
/// typing "test", and standing rule 5 says nobody types `area:Testjunk` to
/// fix it. A filing is a short label reached by incremental typing; a body
/// is long enough that a whole word is the honest unit.
#[test]
fn typing_the_start_of_a_filing_reaches_what_is_filed_there() {
    let mut e = engine();
    // An AREA, not a bare option — `area` is `RefTo(kind::AREA)`. And it
    // goes in no `options` list: a select's choices are registered there,
    // but an area is its own KIND, so a seventh one is found by being an
    // area rather than by being listed.
    let junk = e.declare(kind::AREA, "Testjunk", T0).unwrap();
    let filed = e.create(kind::NOTE, Some("a note"), T0 + 2).unwrap();
    e.set(filed, prop::AREA, Value::Ref(junk), T0 + 3).unwrap();

    assert_eq!(hits(&e, "test"), vec![filed], "the start of the filing reaches it");
    assert_eq!(hits(&e, "testjunk"), vec![filed]);
}

#[test]
fn a_prefix_of_a_body_word_does_not_reach_it() {
    let mut e = engine();
    let id = e.create(kind::NOTE, Some("a note"), T0).unwrap();
    e.set_content(id, vec![Span::text("about the surveyor")], 0, T0 + 1).unwrap();

    assert_eq!(hits(&e, "surveyor"), vec![id]);
    assert!(hits(&e, "survey").is_empty(), "a body wants a whole word");
}

/// A number is not searchable text, and that is what stops "2026"
/// surfacing everything with a due date.
#[test]
fn a_date_is_not_words() {
    let mut e = engine();
    let id = e.create(kind::TASK, Some("ship it"), T0).unwrap();
    e.set(id, prop::DUE, Value::Date(DateSpec::Day(days_from_civil(2026, 9, 13))), T0 + 1)
        .unwrap();
    assert!(hits(&e, "2026").is_empty());
}

/// The score is the SUM of each term's best field — and the ladder's top
/// rung is steep enough to win on its own.
///
/// I expected the note named "roof survey" to beat the one named "roof"
/// with "survey" in its body. It does not, and the arithmetic is the
/// point: an exact whole-name match is 100, so "roof" scores 100 + 10 for
/// the body word, while "roof survey" scores 60 for a name prefix + 40
/// for a word inside the name = 100. **An exact name wins**, which is the
/// ladder saying that what a thing is CALLED outranks what it contains.
#[test]
fn the_score_is_the_sum_over_terms_and_an_exact_name_dominates() {
    let mut e = engine();
    let two_words = e.create(kind::NOTE, Some("roof survey"), T0).unwrap();
    let exact = e.create(kind::NOTE, Some("roof"), T0 + 1).unwrap();
    e.set_content(exact, vec![Span::text("and a survey later")], 0, T0 + 2).unwrap();

    let s = parse(&e, "roof survey").unwrap();
    let found = search(&e, &s, usize::MAX).unwrap();
    assert_eq!(found.len(), 2, "both hold both words");
    assert_eq!(found[0].id, exact);
    assert_eq!(found[0].score, 110.0);
    assert_eq!(found[1].id, two_words);
    assert_eq!(found[1].score, 100.0);
}

/// Equal scores break by most-recently-TOUCHED, then id — a total order,
/// so the same box searches to the same list.
#[test]
fn equal_scores_break_by_what_was_edited_last() {
    let mut e = engine();
    let older = e.create(kind::NOTE, Some("roof one"), T0).unwrap();
    let newer = e.create(kind::NOTE, Some("roof two"), T0 + 1).unwrap();
    assert_eq!(hits(&e, "roof"), vec![newer, older]);

    e.set_content(older, vec![Span::text("edited")], 0, T0 + 10).unwrap();
    assert_eq!(hits(&e, "roof"), vec![older, newer], "editing moves it up");
    assert_eq!(hits(&e, "roof"), vec![older, newer], "and stays put");
}

#[test]
fn a_query_of_only_qualifiers_is_still_a_search() {
    let mut e = engine();
    let task = e.create(kind::TASK, Some("ship it"), T0).unwrap();
    e.create(kind::NOTE, Some("a note"), T0 + 1).unwrap();

    let s = parse(&e, "kind:task").unwrap();
    let found = search(&e, &s, usize::MAX).unwrap();
    assert_eq!(found.iter().map(|h| h.id).collect::<Vec<_>>(), vec![task]);
    assert_eq!(found[0].field, Field::Structured, "nothing matched a field, because nothing had to");
}

#[test]
fn a_reference_qualifier_resolves_by_name() {
    let mut e = engine();
    let task = e.create(kind::TASK, Some("ship it"), T0).unwrap();
    e.create(kind::NOTE, Some("a note"), T0 + 1).unwrap();
    e.set(task, prop::AREA, Value::Ref(area::WORK), T0 + 2).unwrap();

    assert_eq!(hits(&e, "kind:task"), vec![task], "a compiled-in kind, by its word");
    assert_eq!(hits(&e, "area:work"), vec![task]);
    assert!(hits(&e, "area:nowhere").is_empty(), "an unknown name finds nothing");
}

// ---- facets ------------------------------------------------------------

fn board(e: &mut Engine) -> (EntityId, EntityId, EntityId) {
    let a = e.create(kind::TASK, Some("roof"), T0).unwrap();
    let b = e.create(kind::TASK, Some("invoice"), T0 + 1).unwrap();
    let c = e.create(kind::TASK, Some("laundry"), T0 + 2).unwrap();
    e.set(a, prop::AREA, Value::Ref(area::WORK), T0 + 3).unwrap();
    e.set(b, prop::AREA, Value::Ref(area::WORK), T0 + 4).unwrap();
    e.set(c, prop::AREA, Value::Ref(area::HOME), T0 + 5).unwrap();
    (a, b, c)
}

#[test]
fn a_facet_counts_what_each_value_would_yield() {
    let mut e = engine();
    board(&mut e);
    let s = parse(&e, "").unwrap();
    let f = facet(&e, &s, prop::AREA).unwrap();

    assert_eq!(f.label, "area");
    let counts: Vec<(String, usize)> =
        f.values.iter().map(|v| (v.label.clone(), v.count)).collect();
    assert_eq!(counts, vec![("Work".into(), 2), ("Home".into(), 1)], "count-descending");
    assert!(f.values.iter().all(|v| !v.active && !v.excluded));
}

/// **The count excludes this property's own constraints**, so a facet you
/// have already picked still shows its siblings and you can pivot. Without
/// that, choosing one value collapses the row to itself and there is no
/// way back out.
#[test]
fn a_chosen_facet_still_shows_its_siblings() {
    let mut e = engine();
    board(&mut e);
    let s = parse(&e, "area:work").unwrap();
    let f = facet(&e, &s, prop::AREA).unwrap();

    let counts: Vec<(String, usize, bool)> =
        f.values.iter().map(|v| (v.label.clone(), v.count, v.active)).collect();
    assert_eq!(
        counts,
        vec![("Work".into(), 2, true), ("Home".into(), 1, false)],
        "Home is still offered, and still counts 1"
    );
}

#[test]
fn an_excluded_value_says_so() {
    let mut e = engine();
    board(&mut e);
    let s = parse(&e, "-area:work").unwrap();
    let f = facet(&e, &s, prop::AREA).unwrap();
    let work = f.values.iter().find(|v| v.label == "Work").expect("still offered");
    assert!(work.excluded && !work.active);
}

#[test]
fn a_value_nothing_would_yield_is_not_a_choice() {
    let mut e = engine();
    let (a, b, _) = board(&mut e);
    // Narrow to something no Home task satisfies.
    e.set(a, prop::STATUS, Value::Ref(status::DONE), T0 + 10).unwrap();
    e.set(b, prop::STATUS, Value::Ref(status::DONE), T0 + 11).unwrap();

    let s = parse(&e, "status:done").unwrap();
    let f = facet(&e, &s, prop::AREA).unwrap();
    assert_eq!(f.values.iter().map(|v| v.label.clone()).collect::<Vec<_>>(), vec!["Work"]);
}

#[test]
fn only_properties_the_result_actually_carries_get_a_chip_row() {
    let mut e = engine();
    board(&mut e);
    let props = facet_properties(&e, &parse(&e, "").unwrap()).unwrap();
    assert!(props.contains(&prop::KIND), "everything has a kind");
    assert!(props.contains(&prop::AREA));
    assert!(!props.contains(&prop::PROJECT), "nothing is in a project, so do not offer one");
}
