//! P6/6a — search as navigation: the DSL splits qualifiers from free text,
//! ranking scores name over cell over content, and the gates keep plumbing
//! (working, trashed, archived) out of the results.

use lotus_core::*;
use lotus_services::search::{self, MatchField};
use lotus_services::{run, Constraint, Op};

fn c(property: Id, value: Value) -> Cell {
    Cell { property, value }
}

/// A property definition: name + value-kind, backstage (working).
fn def(cmds: &mut Vec<Command>, id: Id, name: &str, kind: &str) {
    cmds.push(Command::Create { entity: id });
    cmds.push(Command::AddCell { entity: id, cell: c(props::NAME, Value::text(name)) });
    cmds.push(Command::AddCell { entity: id, cell: c(props::VALUE_KIND, Value::text(kind)) });
    cmds.push(Command::AddCell { entity: id, cell: c(props::WORKING, Value::Bool(true)) });
}

/// A backstage named entity — a select option or a type.
fn work(cmds: &mut Vec<Command>, id: Id, name: &str) {
    cmds.push(Command::Create { entity: id });
    cmds.push(Command::AddCell { entity: id, cell: c(props::NAME, Value::text(name)) });
    cmds.push(Command::AddCell { entity: id, cell: c(props::WORKING, Value::Bool(true)) });
}

/// A live user entity with a name.
fn live(cmds: &mut Vec<Command>, id: Id, name: &str) {
    cmds.push(Command::Create { entity: id });
    cmds.push(Command::AddCell { entity: id, cell: c(props::NAME, Value::text(name)) });
}

fn add(cmds: &mut Vec<Command>, id: Id, property: Id, value: Value) {
    cmds.push(Command::AddCell { entity: id, cell: c(property, value) });
}

struct Fx {
    store: Store,
    // ranking ladder for the term "report"
    r_exact: Id,   // "report"        — whole name
    r_prefix: Id,  // "report card"   — leading prefix
    r_word: Id,    // "annual report" — word-boundary inside
    r_cell: Id,    // cell "quarterly report"
    r_body: Id,    // content "…report…"
    anna: Id,
    meeting: Id,   // content [see [[Anna]]]
    oldreport: Id, // archived
    laundry: Id,   // type:task
    grocery: Id,   // type:note
    finish: Id,    // status:done
    early: Id,     // due 2026-07-08
    late: Id,      // due 2026-07-12
    status: Id,
    due: Id,
    archived: Id,
    task_type: Id,
    done_opt: Id,
}

fn fixture() -> Fx {
    let mut store = Store::new();

    let status = store.allocate_id();
    let due = store.allocate_id();
    let archived = store.allocate_id();
    let summary = store.allocate_id();
    let todo_opt = store.allocate_id();
    let done_opt = store.allocate_id();
    let task_type = store.allocate_id();
    let note_type = store.allocate_id();

    let r_exact = store.allocate_id();
    let r_prefix = store.allocate_id();
    let r_word = store.allocate_id();
    let r_cell = store.allocate_id();
    let r_body = store.allocate_id();
    let anna = store.allocate_id();
    let meeting = store.allocate_id();
    let secret = store.allocate_id();
    let trashme = store.allocate_id();
    let oldreport = store.allocate_id();
    let laundry = store.allocate_id();
    let grocery = store.allocate_id();
    let finish = store.allocate_id();
    let early = store.allocate_id();
    let late = store.allocate_id();

    let mut cmds = Vec::new();

    // Property definitions. TYPE is the reserved built-in; the rest are
    // ordinary user properties with a declared value-kind.
    def(&mut cmds, props::TYPE, "type", "reference");
    def(&mut cmds, status, "status", "select");
    def(&mut cmds, due, "due", "datetime");
    def(&mut cmds, archived, "archived", "bool");
    def(&mut cmds, summary, "summary", "text");

    // Select options and types (backstage named entities).
    work(&mut cmds, todo_opt, "todo");
    work(&mut cmds, done_opt, "done");
    work(&mut cmds, task_type, "task");
    work(&mut cmds, note_type, "note");
    add(&mut cmds, status, props::OPTIONS, Value::Reference(todo_opt));
    add(&mut cmds, status, props::OPTIONS, Value::Reference(done_opt));

    // The ranking ladder for "report".
    live(&mut cmds, r_exact, "report");
    live(&mut cmds, r_prefix, "report card");
    live(&mut cmds, r_word, "annual report");
    live(&mut cmds, r_cell, "memo");
    add(&mut cmds, r_cell, summary, Value::text("quarterly report"));
    live(&mut cmds, r_body, "draft");
    add(
        &mut cmds,
        r_body,
        props::CONTENT,
        Value::RichText(RichText { spans: vec![Span::text("the report ships monday")] }),
    );

    // Wiki-link: content resolves a Ref to the target's name through display.
    live(&mut cmds, anna, "Anna");
    live(&mut cmds, meeting, "kickoff");
    add(
        &mut cmds,
        meeting,
        props::CONTENT,
        Value::RichText(RichText { spans: vec![Span::text("see "), Span::Ref(anna)] }),
    );

    // Gate fodder.
    work(&mut cmds, secret, "secret"); // working
    live(&mut cmds, trashme, "trashme");
    cmds.push(Command::Trash { entity: trashme });
    live(&mut cmds, oldreport, "oldreport");
    add(&mut cmds, oldreport, archived, Value::Bool(true));

    // Qualifier fodder.
    live(&mut cmds, laundry, "do laundry");
    add(&mut cmds, laundry, props::TYPE, Value::Reference(task_type));
    // A user note whose title collides with the type name "task" (a later,
    // higher id) — type:task must still resolve to the low-id type.
    let task_dupe = store.allocate_id();
    live(&mut cmds, task_dupe, "task");
    live(&mut cmds, grocery, "buy milk");
    add(&mut cmds, grocery, props::TYPE, Value::Reference(note_type));
    live(&mut cmds, finish, "wrap up");
    add(&mut cmds, finish, status, Value::Select(done_opt));
    live(&mut cmds, early, "ship early");
    add(&mut cmds, early, due, Value::DateTime(DateTime::date(2026, 7, 8)));
    live(&mut cmds, late, "ship late");
    add(&mut cmds, late, due, Value::DateTime(DateTime::date(2026, 7, 12)));

    store.commit(cmds, "search fixture", Author::User).unwrap();

    Fx {
        store, r_exact, r_prefix, r_word, r_cell, r_body, anna, meeting,
        oldreport, laundry, grocery, finish, early, late, status, due,
        archived, task_type, done_opt,
    }
}

fn ids(fx: &Fx, raw: &str) -> Vec<Id> {
    let sq = search::parse(&fx.store, raw);
    search::search(&fx.store, &sq, 50).into_iter().map(|h| h.id).collect()
}

#[test]
fn ranking_name_beats_cell_beats_content() {
    let fx = fixture();
    let sq = search::parse(&fx.store, "report");
    let hits = search::search(&fx.store, &sq, 50);
    let order: Vec<Id> = hits.iter().map(|h| h.id).collect();

    // whole name > leading prefix > word-boundary > another cell > body.
    assert_eq!(order, vec![fx.r_exact, fx.r_prefix, fx.r_word, fx.r_cell, fx.r_body]);
    assert_eq!(hits[0].field, MatchField::Name);
    assert_eq!(hits[3].field, MatchField::Cell);
    assert_eq!(hits[4].field, MatchField::Content);
    // and the scores strictly descend.
    assert!(hits.windows(2).all(|w| w[0].score > w[1].score));
}

#[test]
fn free_text_terms_are_anded() {
    let fx = fixture();
    // Only "annual report" carries both words.
    assert_eq!(ids(&fx, "annual report"), vec![fx.r_word]);
}

#[test]
fn a_wiki_link_is_found_by_the_target_name() {
    let fx = fixture();
    let order = ids(&fx, "anna");
    // The person (exact name) ranks first; the note that links her follows
    // because display resolves its Ref span to "Anna".
    assert_eq!(order.first(), Some(&fx.anna));
    assert!(order.contains(&fx.meeting));
}

#[test]
fn gates_exclude_working_trashed_and_archived() {
    let fx = fixture();
    assert!(ids(&fx, "secret").is_empty(), "a working entity must not surface");
    assert!(ids(&fx, "trashme").is_empty(), "a trashed entity must not surface");
    // A Select value ("done") is not incidental free text, and the option
    // entity named "done" is backstage — so a bare "done" finds nothing.
    assert!(ids(&fx, "done").is_empty());
    // Archived is backstage by default; is:archived opts it back in.
    assert!(ids(&fx, "oldreport").is_empty());
    assert_eq!(ids(&fx, "oldreport is:archived"), vec![fx.oldreport]);
}

#[test]
fn type_qualifier_resolves_a_reference_by_name() {
    let fx = fixture();
    let sq = search::parse(&fx.store, "type:task");
    assert!(sq.terms.is_empty());
    assert!(
        sq.query.constraints.iter().any(|con| con.property == props::TYPE
            && con.op == Op::Equals(Value::Reference(fx.task_type))),
        "type:task must resolve to the type entity id",
    );
    let order = ids(&fx, "type:task");
    assert!(order.contains(&fx.laundry));
    assert!(!order.contains(&fx.grocery));
}

#[test]
fn reference_resolution_is_deterministic_on_a_name_collision() {
    // "task" names both the low-id type and a later user note. Resolution
    // must always pick the type (lowest id) — never flip with HashMap order.
    let fx = fixture();
    for _ in 0..8 {
        let sq = search::parse(&fx.store, "type:task");
        assert!(
            sq.query.constraints.iter().any(|con| con.property == props::TYPE
                && con.op == Op::Equals(Value::Reference(fx.task_type))),
            "type:task must resolve to the low-id type, not the same-named note",
        );
    }
}

#[test]
fn status_qualifier_resolves_a_select_option() {
    let fx = fixture();
    let sq = search::parse(&fx.store, "status:done");
    assert!(
        sq.query.constraints.iter().any(|con| con.property == fx.status
            && con.op == Op::Equals(Value::Select(fx.done_opt))),
    );
    assert!(ids(&fx, "status:done").contains(&fx.finish));
}

#[test]
fn date_less_than_is_at_most() {
    let fx = fixture();
    let sq = search::parse(&fx.store, "due<2026-07-10");
    assert!(
        sq.query.constraints.iter().any(|con| con.property == fx.due
            && matches!(con.op, Op::AtMost(_))),
    );
    let order = ids(&fx, "due<2026-07-10");
    assert!(order.contains(&fx.early)); // 07-08 ≤ 07-10
    assert!(!order.contains(&fx.late)); // 07-12 is after
}

#[test]
fn a_typo_qualifier_demotes_to_free_text() {
    let fx = fixture();
    let sq = search::parse(&fx.store, "statuz:done");
    assert_eq!(sq.terms, vec!["statuz:done".to_string()]);
    // The only constraint is the default archived exclusion — no phantom
    // constraint on a property that does not exist.
    assert_eq!(sq.query.constraints.len(), 1);
    assert_eq!(sq.query.constraints[0].property, fx.archived);
}

#[test]
fn a_facet_count_is_the_hypothetical_result_size() {
    let fx = fixture();
    let sq = search::parse(&fx.store, "");
    let f = search::facet(&fx.store, &sq, props::TYPE);
    let base_size = run(&fx.store, &sq.query).len();

    assert!(!f.values.is_empty());
    for fv in &f.values {
        // The count is literally run(base + Equals(value)).len().
        let mut probe = sq.query.clone();
        probe.constraints.retain(|c| c.property != props::TYPE);
        probe.constraints.push(Constraint {
            property: props::TYPE,
            op: Op::Equals(fv.value.clone()),
        });
        assert_eq!(fv.count, run(&fx.store, &probe).len());
        assert!(fv.count > 0, "zero-count values are dropped");
        // Adding a constraint never grows the result.
        assert!(fv.count <= base_size);
    }
    // Sorted count-descending.
    assert!(f.values.windows(2).all(|w| w[0].count >= w[1].count));
}

#[test]
fn a_facet_shows_siblings_and_marks_the_active_value() {
    let fx = fixture();
    // With type:task active, the type facet still lists note (counts
    // exclude self) and marks task active — so the chip can pivot.
    let sq = search::parse(&fx.store, "type:task");
    let f = search::facet(&fx.store, &sq, props::TYPE);
    let task = f.values.iter().find(|v| v.label == "task").expect("task value");
    let note = f.values.iter().find(|v| v.label == "note").expect("note sibling");
    assert!(task.active);
    assert!(!note.active);
}

#[test]
fn facet_properties_finds_type_and_select_props() {
    let fx = fixture();
    let sq = search::parse(&fx.store, "");
    let facetable = search::facet_properties(&fx.store, &sq);
    assert!(facetable.contains(&props::TYPE), "TYPE is faceted");
    assert!(facetable.contains(&fx.status), "a present select prop is faceted");
    // due is a datetime, never a facet.
    assert!(!facetable.contains(&fx.due));
}
