//! The grammar, and asking the box with it.
//!
//! The lexer moved here from `services/src/search.rs` unchanged, so these
//! pin the spellings that were already shipping — a shell reads them back
//! over the ABI rather than carrying a second parser, and a respelled term
//! has to round-trip or a saved workspace changes meaning when it is
//! edited.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_787_391_635_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

fn one(raw: &str) -> Term {
    let mut terms = lex(raw);
    assert_eq!(terms.len(), 1, "{raw} is one token: {terms:?}");
    terms.pop().unwrap()
}

// ---- the grammar ------------------------------------------------------

#[test]
fn the_shapes_of_a_token() {
    assert_eq!(one("area:work").op, TermOp::Equals);
    assert_eq!(one("-area:work").op, TermOp::NotEquals);
    assert_eq!(one("is:archived").op, TermOp::Is);
    assert_eq!(one("has:due").op, TermOp::Has);
    assert_eq!(one("no:area").op, TermOp::No);
    assert_eq!(one("due<friday").op, TermOp::AtMost);
    assert_eq!(one("roof").op, TermOp::Text);

    let t = one("-area:work");
    assert_eq!(t.key, "area", "the minus is the operator, not the name");
    assert_eq!(t.value, "work");
}

#[test]
fn a_half_qualifier_is_just_words() {
    // A key the user is still typing is not a qualifier yet.
    for raw in ["area:", ":work", "<friday", "due<"] {
        assert_eq!(one(raw).op, TermOp::Text, "{raw}");
        assert_eq!(one(raw).value, raw);
    }
}

/// **A bare URL lexes as a qualifier, and that is not a bug here.**
///
/// The comment this lexer arrived with claimed `http://x` degraded to
/// free text. It does not: both halves of the split are non-empty, so it
/// reads as `http` = `//example.com`. Nothing is wrong with that — the
/// lexer has no box and cannot know whether a property called `http`
/// exists, and a lexer that guessed at URL schemes would be a lexer with
/// an opinion about the box. The rescue is one layer up, where an
/// unresolvable key falls back to the whole token as free text.
#[test]
fn a_url_is_a_qualifier_to_the_lexer_and_words_to_the_resolver() {
    let t = one("http://example.com");
    assert_eq!(t.op, TermOp::Equals);
    assert_eq!(t.key, "http");
    assert_eq!(t.value, "//example.com");
}

#[test]
fn a_term_respells_to_something_that_reads_back_the_same() {
    // The raw form is what a saved workspace stores, so joining a term
    // list has to reproduce a query the lexer reads identically —
    // otherwise editing a filter changes what it means.
    for raw in [
        "area:work",
        "-area:work",
        "is:archived",
        "due<friday",
        "people:\"Anna Karlsson\"",
        "\"valid until:friday\"",
        "roof",
    ] {
        let first = lex(raw);
        let rejoined: Vec<String> = first.iter().map(|t| t.raw.clone()).collect();
        assert_eq!(lex(&rejoined.join(" ")), first, "{raw} did not survive its own spelling");
    }
}

#[test]
fn quotes_hold_a_phrase_together() {
    let t = one("people:\"Anna Karlsson\"");
    assert_eq!(t.key, "people");
    assert_eq!(t.value, "Anna Karlsson");
    // A key with a space is the odd case, and there the WHOLE term is
    // quoted instead.
    let t = one("\"valid until:friday\"");
    assert_eq!(t.key, "valid until");
    assert_eq!(t.value, "friday");
}

#[test]
fn the_lexer_touches_no_box() {
    // It is called per keystroke by a picker editing a draft. Nothing
    // here consults anything, and that is the point — there is no box in
    // the signature at all.
    assert_eq!(lex("").len(), 0);
    assert_eq!(lex("   ").len(), 0);
    assert_eq!(lex("a b c").len(), 3);
}

// ---- running one ------------------------------------------------------

/// What `tasks` files, and the areas it filed them under.
///
/// There are no compiled-in areas: an area is ordinary minted vocabulary,
/// so the fixture declares the two it needs and hands back their ids for
/// the tests to query with.
struct Filed {
    a: EntityId,
    b: EntityId,
    c: EntityId,
    work: EntityId,
    home: EntityId,
}

/// Three tasks: two in Work, one at Home; one of the Work ones is done.
fn tasks(e: &mut Engine) -> Filed {
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let home = e.declare(kind::AREA, "Home", T0).unwrap();
    let a = e.create(kind::TASK, Some("roof"), T0).unwrap();
    let b = e.create(kind::TASK, Some("invoice"), T0 + 1).unwrap();
    let c = e.create(kind::TASK, Some("laundry"), T0 + 2).unwrap();
    e.set(a, prop::AREA, Value::Ref(work), T0 + 3).unwrap();
    e.set(b, prop::AREA, Value::Ref(work), T0 + 4).unwrap();
    e.set(c, prop::AREA, Value::Ref(home), T0 + 5).unwrap();
    e.set(b, prop::STATUS, Value::Ref(status::DONE), T0 + 6).unwrap();
    Filed { a, b, c, work, home }
}

fn q(constraints: Vec<Constraint>) -> Query {
    Query { constraints, ..Default::default() }
}

fn eq(property: EntityId, value: Value) -> Constraint {
    Constraint { property, op: QueryOp::Equals(value) }
}

#[test]
fn a_conjunction_of_constraints() {
    let mut e = engine();
    let Filed { a, b, c, work, home } = tasks(&mut e);

    assert_eq!(e.run(&q(vec![eq(prop::AREA, Value::Ref(work))])).unwrap(), vec![a, b]);
    assert_eq!(e.run(&q(vec![eq(prop::AREA, Value::Ref(home))])).unwrap(), vec![c]);
    assert_eq!(
        e.run(&q(vec![
            eq(prop::AREA, Value::Ref(work)),
            Constraint {
                property: prop::STATUS,
                op: QueryOp::NotEquals(Value::Ref(status::DONE))
            },
        ]))
        .unwrap(),
        vec![a],
        "and the done one drops out"
    );
}

#[test]
fn not_equals_is_vacuously_true_when_the_property_is_absent() {
    // A task with no status satisfies `status != done`. The opposite
    // reading hides every unstarted task from every negative filter.
    let mut e = engine();
    let Filed { a, c, .. } = tasks(&mut e);
    let out = e
        .run(&q(vec![Constraint {
            property: prop::STATUS,
            op: QueryOp::NotEquals(Value::Ref(status::DONE)),
        }]))
        .unwrap();
    assert!(out.contains(&a) && out.contains(&c));
}

#[test]
fn missing_is_stronger_than_not_equals() {
    let mut e = engine();
    let Filed { a, .. } = tasks(&mut e);
    let missing = e
        .run(&q(vec![Constraint { property: prop::STATUS, op: QueryOp::Missing }]))
        .unwrap();
    assert!(missing.contains(&a), "no status at all");

    let exists = e
        .run(&q(vec![Constraint { property: prop::AREA, op: QueryOp::Exists }]))
        .unwrap();
    assert_eq!(exists.len(), 3, "all three are filed somewhere");
}

#[test]
fn backstage_and_trashed_stay_out_unless_asked_for() {
    let mut e = engine();
    let Filed { a, b, c, .. } = tasks(&mut e);
    e.trash(c, T0 + 10).unwrap();
    // A declared field is working plumbing, and it has a name like
    // anything else.
    e.declare_field("client", "text", false, T0 + 11).unwrap();

    let all = e.run(&Query::default()).unwrap();
    assert_eq!(all, vec![a, b], "live, and not plumbing");

    let with_trash = e.run(&Query { include_trashed: true, ..Default::default() }).unwrap();
    assert!(with_trash.contains(&c));

    let with_working = e.run(&Query { include_working: true, ..Default::default() }).unwrap();
    assert!(with_working.len() > all.len());
}

#[test]
fn at_most_is_everything_due_by_then() {
    let mut e = engine();
    let a = e.create(kind::TASK, Some("soon"), T0).unwrap();
    let b = e.create(kind::TASK, Some("later"), T0 + 1).unwrap();
    e.set(a, prop::DUE, Value::Date(DateSpec::Day(20_000)), T0 + 2).unwrap();
    e.set(b, prop::DUE, Value::Date(DateSpec::Day(20_100)), T0 + 3).unwrap();

    let out = e
        .run(&q(vec![Constraint {
            property: prop::DUE,
            op: QueryOp::AtMost(Value::Date(DateSpec::Day(20_050))),
        }]))
        .unwrap();
    assert_eq!(out, vec![a]);
}

#[test]
fn sorting_puts_things_without_the_property_last_in_either_direction() {
    let mut e = engine();
    let a = e.create(kind::TASK, Some("soon"), T0).unwrap();
    let b = e.create(kind::TASK, Some("later"), T0 + 1).unwrap();
    let none = e.create(kind::TASK, Some("someday"), T0 + 2).unwrap();
    e.set(a, prop::DUE, Value::Date(DateSpec::Day(20_000)), T0 + 3).unwrap();
    e.set(b, prop::DUE, Value::Date(DateSpec::Day(20_100)), T0 + 4).unwrap();

    let up = Query {
        sort: Some(Sort { property: prop::DUE, descending: false }),
        ..Default::default()
    };
    assert_eq!(e.run(&up).unwrap(), vec![a, b, none]);

    let down = Query {
        sort: Some(Sort { property: prop::DUE, descending: true }),
        ..Default::default()
    };
    // **`none` stays last.** Only the values reverse — "no due date" is
    // not "the furthest future", and a descending sort that floats every
    // undated thing to the top is a list nobody asked for.
    assert_eq!(e.run(&down).unwrap(), vec![b, a, none]);
}

#[test]
fn results_are_stable_without_a_sort() {
    let mut e = engine();
    let Filed { a, b, work, .. } = tasks(&mut e);
    let out = e.run(&q(vec![eq(prop::AREA, Value::Ref(work))])).unwrap();
    assert_eq!(out, vec![a, b], "by id, which for a v7 id is creation order");
    assert_eq!(e.run(&q(vec![eq(prop::AREA, Value::Ref(work))])).unwrap(), out);
}
