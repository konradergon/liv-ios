//! P6/6a — search as navigation: the DSL splits qualifiers from free text,
//! ranking scores name over cell over content, and the gates keep plumbing
//! (working, trashed, archived) out of the results.

use liv_core::*;
use liv_services::search::{self, MatchField};
use liv_services::{run, Constraint, Op};

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
    note_type: Id,
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
        archived, task_type, note_type, done_opt,
    }
}

fn ids(fx: &Fx, raw: &str) -> Vec<Id> {
    let sq = search::parse(&fx.store, raw);
    search::search(&fx.store, &sq, 50, |_| String::new()).into_iter().map(|h| h.id).collect()
}

#[test]
fn ranking_name_beats_cell_beats_content() {
    let fx = fixture();
    let sq = search::parse(&fx.store, "report");
    let hits = search::search(&fx.store, &sq, 50, |_| String::new());
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

// ---- P11.5 review fix: quoted qualifier values ----

#[test]
fn a_quoted_qualifier_value_keeps_its_spaces() {
    // The chip-click contract: clicking the "Anna Karlsson" chip filters on
    // exactly that person. Without quoting the DSL split her in half — the
    // review's live-reproduced high.
    let dir = std::env::temp_dir().join("liv_search_quoted");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.log");
    let mut session = Session::open(&path).unwrap();
    liv_services::seed_if_fresh(&mut session).unwrap();

    let anna = liv_services::content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    liv_services::content::set_property(&mut session, anna, "name", "Anna Karlsson").unwrap();
    let event = liv_services::content::create_event(
        &mut session, DateTime::date(2026, 7, 12), DateTime::date(2026, 7, 10)).unwrap();
    liv_services::content::set_property(&mut session, event, "attendees", &format!("#{anna}")).unwrap();
    let other = liv_services::content::create_event(
        &mut session, DateTime::date(2026, 7, 13), DateTime::date(2026, 7, 10)).unwrap();

    let store = session.store();
    let sq = search::parse(store, "attendees:\"Anna Karlsson\"");
    let hits = search::search(store, &sq, 200, |_| String::new());
    assert!(hits.iter().any(|h| h.id == event), "the quoted reference resolves whole");
    assert!(!hits.iter().any(|h| h.id == other), "and it filters, not free-texts");

    // A quoted TEXT value works through the same door.
    liv_services::content::set_property(&mut session, event, "location", "Room 4 East").unwrap();
    let store = session.store();
    let sq = search::parse(store, "location:\"Room 4 East\"");
    let hits = search::search(store, &sq, 200, |_| String::new());
    assert!(hits.iter().any(|h| h.id == event));

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_spaced_property_name_needs_the_whole_term_quoted() {
    // TWO spellings reach the same term, and the shell writes both:
    // `people:"Anna Karlsson"` when the VALUE has a space, and
    // `"valid until:friday"` when the NAME does. There is nowhere else to
    // put the quotes in the second case — `valid until:"friday"` leaves
    // `valid` as a bare word and `until:friday` as a term for a property
    // that does not exist.
    //
    // Pinned on 2026-08-27, when the shell's three separate spellers were
    // folded into one that follows `spell`. Nothing covered this form, so
    // nothing would have caught the shell being routed onto a spelling the
    // core cannot read.
    let dir = std::env::temp_dir().join("liv_search_spaced_name");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.log");
    let mut session = Session::open(&path).unwrap();
    liv_services::seed_if_fresh(&mut session).unwrap();

    // A property whose NAME carries a space. Nothing stops a user making
    // one — the schema is data — which is exactly why the grammar has a
    // spelling for it.
    liv_services::content::birth_property(&mut session, "valid until", "text").unwrap();
    let note = liv_services::content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();
    liv_services::content::set_property(&mut session, note, "valid until", "friday").unwrap();
    let other = liv_services::content::create_note(&mut session, DateTime::date(2026, 7, 11)).unwrap();

    let store = session.store();
    let sq = search::parse(store, "\"valid until:friday\"");
    let hits = search::search(store, &sq, 200, |_| String::new());
    assert!(hits.iter().any(|h| h.id == note), "the whole-quoted term resolves");
    assert!(!hits.iter().any(|h| h.id == other), "and it filters, not free-texts");

    // The minus rides INSIDE the quotes, which is what the shell writes.
    let sq = search::parse(store, "\"-valid until:friday\"");
    let hits = search::search(store, &sq, 200, |_| String::new());
    assert!(!hits.iter().any(|h| h.id == note), "excluded");
    assert!(hits.iter().any(|h| h.id == other), "and the rest survive");

    let _ = std::fs::remove_dir_all(&dir);
}

// ---- P13 13a: facet exclusion (include→exclude→off) + recency + true count ----

#[test]
fn a_leading_minus_excludes_a_qualifier() {
    // bp3 a17/a18: `-key:value` renders an exclude pill. parse() must emit
    // Op::NotEquals (which already exists and is already evaluated — the
    // archived gate proves it), and run() drops the matching value while
    // KEEPING cell-absent entities (NotEquals is vacuously true where absent).
    let fx = fixture();
    let sq = search::parse(&fx.store, "-type:task");
    assert!(
        sq.query.constraints.iter().any(|con| con.property == props::TYPE
            && con.op == Op::NotEquals(Value::Reference(fx.task_type))),
        "-type:task must build a NotEquals constraint on the type property",
    );
    let order = ids(&fx, "-type:task");
    assert!(!order.contains(&fx.laundry), "type:task is excluded");
    assert!(order.contains(&fx.grocery), "type:note survives");
    assert!(order.contains(&fx.anna), "a type-absent entity survives (vacuous NotEquals)");
}

#[test]
fn include_and_exclude_coexist() {
    // Two constraints ANDed by run(): include note, exclude the done status.
    let fx = fixture();
    let sq = search::parse(&fx.store, "type:note -status:done");
    assert!(sq.query.constraints.iter().any(|con| con.property == props::TYPE
        && con.op == Op::Equals(Value::Reference(fx.note_type))));
    assert!(sq.query.constraints.iter().any(|con| con.property == fx.status
        && con.op == Op::NotEquals(Value::Select(fx.done_opt))));
    let order = ids(&fx, "type:note -status:done");
    assert!(order.contains(&fx.grocery), "a note without a done status survives");
    assert!(!order.contains(&fx.finish), "finish is status:done — excluded (and not a note)");
}

#[test]
fn a_facet_marks_an_excluded_value() {
    // The FacetValue tri-state: with -type:task active, the task value is
    // marked excluded (renders red), note is neither active nor excluded.
    let fx = fixture();
    let sq = search::parse(&fx.store, "-type:task");
    let f = search::facet(&fx.store, &sq, props::TYPE);
    let task = f.values.iter().find(|v| v.label == "task").expect("task value");
    let note = f.values.iter().find(|v| v.label == "note").expect("note sibling");
    assert!(task.excluded, "the excluded value is flagged");
    assert!(!task.active, "excluded is not active(include)");
    assert!(!note.excluded && !note.active, "an untouched sibling is off");
}

#[test]
fn empty_query_sorts_by_recency() {
    // bp3 a10: the empty-query recents jump list is MODIFIED-desc (most
    // recently edited first), not CREATED-desc.
    let mut store = Store::new();
    let name = props::NAME;
    let older = store.allocate_id();
    let newer = store.allocate_id();
    // `older` is CREATED last (higher created), `newer` first — so a
    // created-desc sort would put `older` first. But `newer` is EDITED last.
    store.commit(
        vec![
            Command::Create { entity: newer },
            Command::AddCell { entity: newer, cell: c(name, Value::text("newer")) },
        ],
        "a", Author::User,
    ).unwrap();
    store.commit(
        vec![
            Command::Create { entity: older },
            Command::AddCell { entity: older, cell: c(name, Value::text("older")) },
        ],
        "b", Author::User,
    ).unwrap();
    // A later edit to `newer` — now its modified time is the latest.
    store.commit(
        vec![Command::AddCell { entity: newer, cell: c(name, Value::text("newer edited")) }],
        "c", Author::User,
    ).unwrap();

    let sq = search::parse(&store, "");
    let order: Vec<Id> = search::search(&store, &sq, 50, |_| String::new())
        .into_iter().map(|h| h.id).collect();
    let pos = |id: Id| order.iter().position(|x| *x == id).unwrap();
    assert!(pos(newer) < pos(older), "most-recently-edited sorts first (modified-desc)");
}

// ---- 2026-08-27: one grammar, one parser ----
//
// The shell carried a second parser for this DSL and the two disagreed
// sixteen ways. Retiring the Swift one makes THIS the only answer, so the
// four places the core was the worse of the two are fixed here first.
// Owner's rulings, 2026-08-27: "lens means only, search means include;
// case-insensitive values; typo shows nothing".

/// A small store carrying the four property definitions these tests need —
/// area, tags, bookmarked, archived. Entities come from `thing`.
fn bench() -> (Store, Id, Id, Id) {
    let mut store = Store::new();
    let mut cmds = Vec::new();
    let area = store.allocate_id();
    def(&mut cmds, area, "area", "text");
    let tags = store.allocate_id();
    def(&mut cmds, tags, "tags", "text");
    let bookmarked = store.allocate_id();
    def(&mut cmds, bookmarked, "bookmarked", "bool");
    let archived = store.allocate_id();
    def(&mut cmds, archived, "archived", "bool");
    store.commit(cmds, "fields", Author::User).unwrap();
    (store, area, tags, bookmarked)
}

fn thing(store: &mut Store, name: &str, cells: &[(Id, Value)]) -> Id {
    let id = store.allocate_id();
    let mut cmds = Vec::new();
    live(&mut cmds, id, name);
    for (p, v) in cells {
        add(&mut cmds, id, *p, v.clone());
    }
    store.commit(cmds, "thing", Author::User).unwrap();
    id
}

fn archived_id(store: &Store) -> Id {
    store.named("archived").iter().copied().min().unwrap()
}

#[test]
fn a_lens_restricts_where_a_search_widens() {
    // The same token, two jobs. `is:archived` in a WORKSPACE means "show me
    // my archived things"; in SEARCH it means "look in the archive too".
    // One grammar can serve both only if the caller says which it is.
    let (mut store, _, _, _) = bench();
    let arch = archived_id(&store);
    let live_one = thing(&mut store, "live one", &[]);
    let old = thing(&mut store, "old one", &[(arch, Value::Bool(true))]);

    let lens = search::parse_mode(&store, "is:archived", search::Mode::Lens);
    assert_eq!(run(&store, &lens.query), vec![old], "a lens shows ONLY the archived");

    let found = search::parse_mode(&store, "is:archived", search::Mode::Search);
    let mut both = run(&store, &found.query);
    both.sort();
    let mut want = vec![live_one, old];
    want.sort();
    assert_eq!(both, want, "a search shows archived AS WELL");
}

#[test]
fn bookmarked_is_a_flag_the_core_knows() {
    // It shipped in the shell's parser and not in this one, so a bookmarks
    // workspace worked until it went through the core and then emptied.
    let (mut store, _, _, bookmarked) = bench();
    let plain = thing(&mut store, "plain", &[]);
    let kept = thing(&mut store, "kept", &[(bookmarked, Value::Bool(true))]);

    let q = search::parse_mode(&store, "is:bookmarked", search::Mode::Lens);
    let hits = run(&store, &q.query);
    assert_eq!(hits, vec![kept]);
    assert!(!hits.contains(&plain));
}

#[test]
fn a_property_name_resolves_whatever_its_case() {
    // `Area:Work` silently found nothing: the name index is an exact map,
    // so the token demoted to free text and the screen went empty with no
    // error anywhere.
    let (mut store, area, _, _) = bench();
    let n = thing(&mut store, "roof", &[(area, Value::text("Work"))]);

    for raw in ["area:Work", "Area:Work", "AREA:Work"] {
        let q = search::parse_mode(&store, raw, search::Mode::Lens);
        assert_eq!(run(&store, &q.query), vec![n], "{raw} should resolve");
    }
}

#[test]
fn a_text_value_matches_whatever_its_case() {
    // Values stay VERBATIM on the way in — "errands" must not become
    // "Errands" — but matching is a different question, and a lens that
    // misses its own value because someone capitalised it is a trap.
    let (mut store, _, tags, _) = bench();
    let n = thing(&mut store, "article", &[(tags, Value::text("Reading"))]);

    for raw in ["tags:Reading", "tags:reading", "tags:READING"] {
        let q = search::parse_mode(&store, raw, search::Mode::Lens);
        assert_eq!(run(&store, &q.query), vec![n], "{raw} should match");
    }
    // And the cell itself is untouched by any of it.
    let cell = store.get(n).unwrap();
    assert_eq!(cell.all(tags).next(), Some(&Value::text("Reading")));
}

#[test]
fn a_typo_shows_nothing_rather_than_everything() {
    // The shell's parser ignored what it could not read, so a workspace
    // query with one letter wrong quietly filtered nothing. The core's
    // rule — an unreadable token is a required word — is the honest one
    // (owner, 2026-08-27).
    let (mut store, area, _, _) = bench();
    thing(&mut store, "roof", &[(area, Value::text("Work"))]);

    let q = search::parse_mode(&store, "wibble", search::Mode::Lens);
    assert_eq!(q.terms, vec!["wibble".to_string()]);

    let slip = search::parse_mode(&store, "no:projct", search::Mode::Lens);
    assert_eq!(
        slip.terms,
        vec!["no:projct".to_string()],
        "a misspelled property is a word, not a filter that matches everything"
    );
}
