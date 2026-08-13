//! P8/8a — the task surface's substrate: a seeded `priority` select that
//! lands even on a box that already has `due`, and `create_task` — a typed,
//! already-`todo` birth distinct from an untyped capture.

use liv_core::*;
use liv_services::{content, property_id, seed_if_fresh};

fn fresh(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("liv_t_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.log");
    let mut session = Session::open(&path).unwrap();
    seed_if_fresh(&mut session).unwrap();
    (path, session)
}

fn cleanup(path: &std::path::Path) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::remove_dir_all(dir);
    }
}

fn named(store: &Store, id: Id) -> Option<String> {
    match store.get(id)?.get(props::NAME) {
        Some(Value::Text(n)) => Some(n.clone()),
        _ => None,
    }
}

/// The type entity for a kind (a working entity named `name`, not a property).
fn type_of(store: &Store, name: &str) -> Id {
    store
        .entities()
        .find(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == name)
                && e.get(props::VALUE_KIND).is_none()
        })
        .map(|e| e.id)
        .unwrap_or_else(|| panic!("no {name} type"))
}

#[test]
fn priority_is_seeded_alongside_due_and_is_idempotent() {
    let (path, mut session) = fresh("tasks_priority");
    // `due` (starter library) and `priority` (its own separately-guarded
    // pass) both land — the pass is NOT gated behind the starter library's
    // `due` short-circuit.
    assert!(property_id(session.store(), "due").is_some());
    let priority = property_id(session.store(), "priority").expect("priority is seeded");

    let options: Vec<String> = session
        .store()
        .get(priority)
        .unwrap()
        .all(props::OPTIONS)
        .filter_map(|v| match v {
            Value::Reference(t) => named(session.store(), *t),
            _ => None,
        })
        .collect();
    assert_eq!(options.len(), 3);
    assert!(options.iter().any(|o| o == "high"));

    // Re-opening (which re-runs the seed) must not duplicate it.
    seed_if_fresh(&mut session).unwrap();
    assert_eq!(property_id(session.store(), "priority"), Some(priority));
    let defs = session
        .store()
        .entities()
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "priority")
                && e.get(props::VALUE_KIND).is_some()
        })
        .count();
    assert_eq!(defs, 1);
    cleanup(&path);
}

#[test]
fn create_task_is_a_typed_todo_with_no_priority_or_due() {
    let (path, mut session) = fresh("tasks_create");
    let id = content::create_task(&mut session, DateTime::date(2026, 7, 7)).unwrap();
    let store = session.store();
    let e = store.get(id).unwrap();

    // type = the task type
    match e.get(props::TYPE) {
        Some(Value::Reference(t)) => assert_eq!(named(store, *t).as_deref(), Some("task")),
        other => panic!("expected type=task, got {other:?}"),
    }
    // status = a Select of the "todo" option (not a bare Reference)
    let status = property_id(store, "status").unwrap();
    match e.get(status) {
        Some(Value::Select(opt)) => assert_eq!(named(store, *opt).as_deref(), Some("todo")),
        other => panic!("expected status=Select(todo), got {other:?}"),
    }
    // no priority, no due at birth
    assert!(e.get(property_id(store, "priority").unwrap()).is_none());
    assert!(e.get(property_id(store, "due").unwrap()).is_none());
    assert!(e.get(props::CREATED).is_some());
    cleanup(&path);
}

#[test]
fn priority_is_offered_not_expected_by_the_task_type() {
    let (path, session) = fresh("tasks_expect");
    let store = session.store();
    let priority = property_id(store, "priority").unwrap();
    let expects: Vec<Id> = store
        .get(type_of(store, "task"))
        .unwrap()
        .all(props::EXPECTED)
        .filter_map(|v| match v {
            Value::Reference(p) => Some(*p),
            _ => None,
        })
        .collect();
    // The task type expects status + due; priority is offered, never expected.
    assert!(!expects.contains(&priority), "priority must not be an expectation");
    cleanup(&path);
}

// ── note task lines: the PROJECTION (roadmap phase 3, owner 2026-08-05) ──
//
// Checkbox lines written inside a note appear in the Tasks view. Nothing
// is stored, nothing is created: `note_tasks` derives a view of the lines
// that are already there. Two authored forms must both be seen — the
// core's structural `Block::Task` (D19's own shape, what the desktop
// writes) and the iOS editor's literal `- [ ] ` text (its recorded
// deviation until it converts to marks-and-blocks).

fn body(text: &str) -> Vec<Span> {
    // The iOS editor's shape: every newline is a Body break, markers stay
    // literal text (shell/ios/Sources/Editor.swift textToSpans).
    let mut spans = Vec::new();
    for (i, line) in text.split('\n').enumerate() {
        if i > 0 {
            spans.push(Span::Break(Block::Body));
        }
        if !line.is_empty() {
            spans.push(Span::Text(TextSpan::plain(line)));
        }
    }
    spans
}

#[test]
fn note_task_lines_project_from_both_authored_forms() {
    let (path, mut session) = fresh("note_tasks_forms");
    let now = DateTime::date(2026, 8, 5);

    // (a) the iOS form: literal markers in Body paragraphs.
    let ios = content::create_note(&mut session, now).unwrap();
    content::set_content(
        &mut session,
        ios,
        body("Roof project\n- [ ] call the surveyor\n  - [ ] send photos\n- [x] paid deposit\nnot a task"),
        0,
    )
    .unwrap();

    // (b) the core's own form: structural task blocks, no markers.
    let desk = content::create_note(&mut session, now).unwrap();
    content::set_content(
        &mut session,
        desk,
        vec![
            Span::Break(Block::Task { depth: 0, done: false }),
            Span::Text(TextSpan::plain("pack rain gear")),
            Span::Break(Block::Task { depth: 0, done: true }),
            Span::Text(TextSpan::plain("book the ferry")),
        ],
        0,
    )
    .unwrap();

    let rows = liv_services::tasks::note_tasks(session.store());

    // OPEN lines only, in document order, per note.
    let mine: Vec<(Id, u32, &str, u32)> =
        rows.iter().map(|r| (r.entity, r.line, r.text.as_str(), r.indent)).collect();
    // The SOURCE name is the note's first line, never a body summary —
    // the flattened-title trap that has bitten three surfaces already.
    assert!(
        rows.iter().filter(|r| r.entity == ios).all(|r| r.source == "Roof project"),
        "the source names the note: {:?}",
        rows.iter().map(|r| r.source.as_str()).collect::<Vec<_>>()
    );
    assert_eq!(
        mine,
        vec![
            (ios, 1, "call the surveyor", 0),
            (ios, 2, "send photos", 2),
            (desk, 0, "pack rain gear", 0),
        ],
        "open lines from both forms, markers stripped, indent kept, \
         and a DETERMINISTIC order (entities() has none of its own)"
    );
    cleanup(&path);
}

#[test]
fn note_task_projection_skips_what_is_not_a_note_of_yours() {
    let (path, mut session) = fresh("note_tasks_skips");
    let now = DateTime::date(2026, 8, 5);
    let template_prop = content::birth_property(&mut session, "template", "text").unwrap();

    // A template's body is scaffolding, not work.
    let template = content::create_note(&mut session, now).unwrap();
    content::set_content(&mut session, template, body("- [ ] {{cursor}}"), 0).unwrap();
    session
        .commit(
            vec![Command::AddCell {
                entity: template,
                cell: Cell { property: template_prop, value: Value::text("1") },
            }],
            "mark template",
            Author::User,
        )
        .unwrap();

    // A trashed note is gone.
    let trashed = content::create_note(&mut session, now).unwrap();
    content::set_content(&mut session, trashed, body("- [ ] forget me"), 0).unwrap();
    session
        .commit(vec![Command::Trash { entity: trashed }], "trash", Author::User)
        .unwrap();

    // An EMPTY checkbox is a line not yet written, not work — the
    // editor's return-key continuation mints them by the handful.
    let blank = content::create_note(&mut session, now).unwrap();
    content::set_content(&mut session, blank, body("shopping\n- [ ] \n- [ ] milk"), 0).unwrap();

    // A TASK's own body would double-count against itself in that view.
    let task = content::create_task(&mut session, now).unwrap();
    content::set_content(&mut session, task, body("- [ ] sub-step"), 0).unwrap();

    let rows = liv_services::tasks::note_tasks(session.store());
    assert_eq!(
        rows.iter().map(|r| (r.entity, r.line, r.text.as_str())).collect::<Vec<_>>(),
        vec![(blank, 2, "milk")],
        "templates, trashed notes, typed tasks and EMPTY boxes never project"
    );
    cleanup(&path);
}

/// The name a LIST should show for a note. Until 2026-08-07 the snapshot
/// answered this with `liv_views::summary`, which returns the whole body
/// flattened into one line — so a daily note appeared in every list as
/// "Thu 6 Aug ## Today - [ ] milk ## Notes". The owner asked for it
/// three times; this pins the answer.
#[test]
fn display_name_is_the_first_line_not_the_whole_body() {
    let (path, mut session) = fresh("display_name");
    let now = DateTime::date(2026, 8, 7);

    // A multi-line note with no name of its own.
    let note = content::create_note(&mut session, now).unwrap();
    content::set_content(
        &mut session,
        note,
        body("Trip planning\nAsk Steven about the rack.\n## Gear\n- Boots"),
        0,
    )
    .unwrap();

    let got = content::display_name(session.store(), session.store().get(note).unwrap());
    assert_eq!(
        got, "Trip planning",
        "a list shows the note's FIRST line, never its whole body"
    );

    // A leading marker is display, not part of the name.
    let heading = content::create_note(&mut session, now).unwrap();
    content::set_content(&mut session, heading, body("## Weekly review\nnotes below"), 0).unwrap();
    assert_eq!(
        content::display_name(session.store(), session.store().get(heading).unwrap()),
        "Weekly review"
    );

    // A blank first line is skipped; a rule line has no words at all.
    let spaced = content::create_note(&mut session, now).unwrap();
    content::set_content(&mut session, spaced, body("\n---\nReal first line"), 0).unwrap();
    assert_eq!(
        content::display_name(session.store(), session.store().get(spaced).unwrap()),
        "Real first line"
    );

    // A name cell always wins.
    let named_note = content::create_note(&mut session, now).unwrap();
    content::set_content(&mut session, named_note, body("body text"), 0).unwrap();
    session
        .commit(
            vec![Command::AddCell {
                entity: named_note,
                cell: Cell { property: props::NAME, value: Value::text("Chosen name") },
            }],
            "name",
            Author::User,
        )
        .unwrap();
    assert_eq!(
        content::display_name(session.store(), session.store().get(named_note).unwrap()),
        "Chosen name"
    );

    // Nothing at all falls back to the id, never to an empty string.
    let empty = content::create_note(&mut session, now).unwrap();
    assert_eq!(
        content::display_name(session.store(), session.store().get(empty).unwrap()),
        format!("#{empty}")
    );

    cleanup(&path);
}

/// Syntax must NEVER appear in a title (owner, 2026-08-07). The block
/// stripper alone left inline markers — "**Pack** the van" arrived with
/// its asterisks, and a greedy leading-character trim mangled a line
/// STARTING with bold into "Bold start** rest". The rules here mirror
/// the iOS editor's scanner exactly (EditorStyle.swift MarkScan), so
/// the saved title and the live editor preview never disagree.
#[test]
fn display_name_never_shows_syntax() {
    let (path, mut session) = fresh("display_name_syntax");
    let now = DateTime::date(2026, 8, 7);
    let mut check = |first_line: &str, want: &str| {
        let note = content::create_note(&mut session, now).unwrap();
        content::set_content(&mut session, note, body(first_line), 0).unwrap();
        let got =
            content::display_name(session.store(), session.store().get(note).unwrap());
        assert_eq!(got, want, "first line {first_line:?}");
    };

    // Inline marks come off; the words stay.
    check("**Pack** the `van` for [[4155|Kitchen rebuild]]", "Pack the van for Kitchen rebuild");
    check("**Bold start** rest", "Bold start rest");
    check("*Milan* trip", "Milan trip");
    check("~~old~~ new plan", "old new plan");
    // Unclosed markers are literal text, exactly as the editor renders them.
    check("**Pack", "**Pack");
    // A reference with no name has nothing better to show; it stays as typed.
    check("[[99999]] follow-up", "[[99999]] follow-up");
    // Block markers, precisely — not a greedy character trim.
    check("## Weekly **review**", "Weekly review");
    check("- [x] paid deposit\nrest", "paid deposit");
    check("1. First step", "First step");
    check("> quoted words", "quoted words");
    // A hash with no space is the user's own text, not a heading.
    check("#errands today", "#errands today");

    cleanup(&path);
}
