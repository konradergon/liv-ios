//! Tasks, Everything and the day timeline — the rules, under test.
//!
//! Same standard as `today.rs`: every assertion here corresponds to a line
//! of a SwiftUI view file that no test in the workspace could reach, and
//! where the Swift carried the rule as a comment, the comment came too.

use liv_engine::*;
use liv_surface::calendar::calendar;
use liv_surface::tasks::{tasks, PROJECTS_OFFERED};
use liv_surface::salvage::note_tasks;
use liv_surface::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const DAY: i32 = 20_700;

fn at(day: i32, hour: i64, minute: i64) -> i64 {
    day as i64 * 86_400_000 + hour * 3_600_000 + minute * 60_000
}

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

fn titles(rows: &[Row]) -> Vec<&str> {
    rows.iter().map(|r| r.title.as_str()).collect()
}

fn task(e: &mut Engine, name: &str, now: u64) -> EntityId {
    e.create(kind::TASK, Some(name), now).unwrap()
}

// ---- Tasks -------------------------------------------------------------

#[test]
fn tasks_are_grouped_by_status_with_ours_first_and_no_status_last() {
    let mut e = engine();
    let a = task(&mut e, "Todo one", 1_000);
    let b = task(&mut e, "Doing one", 1_001);
    let c = task(&mut e, "Loose", 1_002);
    e.set(a, prop::STATUS, Value::Ref(status::TODO), 1_010).unwrap();
    e.set(b, prop::STATUS, Value::Ref(status::DOING), 1_011).unwrap();

    let g = tasks(&e, None, &Lens::Everything, DAY, 0).unwrap().groups;
    let names: Vec<&str> = g.iter().map(|x| x.name.as_str()).collect();
    assert_eq!(names, vec!["To do", "Doing", "No status"]);
    assert_eq!(titles(&g[2].rows), vec!["Loose"]);
    assert_eq!(g[2].status, None, "No status is not a status");
    let _ = c;

    // AN EMPTY GROUP IS NOT A GROUP — Done exists in the vocabulary and
    // does not appear, because nothing is in it.
    assert!(!names.contains(&"Done"));
}

#[test]
fn a_task_whose_status_was_retired_still_shows() {
    // "(also holds statuses no longer in the vocabulary — every task
    // shows)". A task must never fall off the screen because the option
    // it points at went away.
    let mut e = engine();
    let ghost = e.declare(kind::STATUS, "Blocked", 1_000).unwrap();
    let t = task(&mut e, "Waiting on legal", 1_001);
    e.set(t, prop::STATUS, Value::Ref(ghost), 1_002).unwrap();
    e.trash(ghost, 1_003).unwrap();

    let g = tasks(&e, None, &Lens::Everything, DAY, 0).unwrap().groups;
    let found: Vec<&str> = g.iter().flat_map(|x| titles(&x.rows)).collect();
    assert_eq!(found, vec!["Waiting on legal"], "it is on the screen somewhere");
}

#[test]
fn tasks_sort_by_due_then_title_then_id_with_undated_last() {
    let mut e = engine();
    let far = task(&mut e, "Zebra", 1_000);
    let near = task(&mut e, "Apple", 1_001);
    task(&mut e, "Undated banana", 1_002);
    task(&mut e, "Undated apple", 1_003);
    e.set(far, prop::DUE, Value::Date(DateSpec::Day(DAY + 5)), 1_010).unwrap();
    e.set(near, prop::DUE, Value::Date(DateSpec::Day(DAY + 1)), 1_011).unwrap();

    let g = tasks(&e, None, &Lens::Everything, DAY, 0).unwrap().groups;
    assert_eq!(
        titles(&g[0].rows),
        vec!["Apple", "Zebra", "Undated apple", "Undated banana"],
        "due first, undated last, then title — and the title tiebreak is case-insensitive"
    );
}

#[test]
fn lateness_is_the_groups_fact_and_a_finished_band_has_none() {
    // Measured 2026-08-30: this screen was 1.85% saturated pixels against
    // Todoist's 0.58%, and 21,000 of those were a column of red dates —
    // one per row, because in a real box every task is overdue. Todoist
    // says it once, in the heading.
    let mut e = engine();
    for (n, d) in [(0, DAY - 3), (1, DAY - 1), (2, DAY + 1)] {
        let t = task(&mut e, &format!("task {n}"), 1_000 + n);
        e.set(t, prop::DUE, Value::Date(DateSpec::Day(d)), 1_010 + n).unwrap();
        e.set(t, prop::STATUS, Value::Ref(status::TODO), 1_020 + n).unwrap();
    }
    let old = task(&mut e, "long done", 2_000);
    e.set(old, prop::DUE, Value::Date(DateSpec::Day(DAY - 30)), 2_001).unwrap();
    e.set(old, prop::STATUS, Value::Ref(status::DONE), 2_002).unwrap();

    let g = tasks(&e, None, &Lens::Everything, DAY, 0).unwrap().groups;
    let todo = g.iter().find(|x| x.name == "To do").unwrap();
    assert_eq!(todo.late, 2, "two of the three are overdue");
    let done = g.iter().find(|x| x.name == "Done").unwrap();
    assert_eq!(done.late, 0, "a finished band has nothing late in it by definition");
}

#[test]
fn the_project_filter_narrows_inside_the_lens_rather_than_replacing_it() {
    // "The lens (M4) runs BEFORE the chip filter: the workspace scopes the
    // surface, the chips narrow inside it."
    let mut e = engine();
    let roof = e.create(kind::PROJECT, Some("Roof"), 1_000).unwrap();
    let seen = task(&mut e, "In the workspace", 1_001);
    let hidden = task(&mut e, "Outside it", 1_002);
    e.set(seen, prop::PROJECT, Value::Ref(roof), 1_010).unwrap();
    e.set(hidden, prop::PROJECT, Value::Ref(roof), 1_011).unwrap();

    let lens: Lens = [seen].into_iter().collect();
    let g = tasks(&e, Some(roof), &lens, DAY, 0).unwrap().groups;
    let found: Vec<&str> = g.iter().flat_map(|x| titles(&x.rows)).collect();
    assert_eq!(found, vec!["In the workspace"]);
    assert!(lens.on());
    assert!(!Lens::Everything.on());
}

#[test]
fn the_groups_come_in_the_order_the_status_picker_offers() {
    // The segments above the list are the picker's options, and the
    // groups under them must come in the same order, or the screen
    // disagrees with itself. One list, `options_for`, feeds both.
    let mut e = engine();
    let blocked = e.declare(kind::STATUS, "Blocked", 1_000).unwrap();
    e.set(blocked, prop::HUE, Value::Number(5.0), 1_001).unwrap();
    for (n, st) in [status::DONE, blocked, status::TODO, status::DOING].into_iter().enumerate() {
        let t = task(&mut e, &format!("t{n}"), 1_010 + n as u64);
        e.set(t, prop::STATUS, Value::Ref(st), 1_020 + n as u64).unwrap();
    }

    let offered: Vec<EntityId> =
        e.options_for(prop::STATUS).unwrap().into_iter().map(|(id, _)| id).collect();
    let g = tasks(&e, None, &Lens::Everything, DAY, 0).unwrap().groups;
    let shown: Vec<EntityId> = g.iter().filter_map(|x| x.status).collect();
    assert_eq!(shown, offered);

    // The group carries its option's hue, which is what colours its box.
    let b = g.iter().find(|x| x.status == Some(blocked)).unwrap();
    assert_eq!(b.hue, Some(5));
    assert_eq!(g.iter().find(|x| x.status == Some(status::TODO)).unwrap().hue, None);
}

#[test]
fn a_row_is_late_only_while_it_can_still_be_done() {
    // "Late is strictly past: due today is not overdue." And a finished
    // task is not late, however old its date.
    let mut e = engine();
    let overdue = task(&mut e, "Overdue", 1_000);
    let today = task(&mut e, "Due today", 1_001);
    let finished = task(&mut e, "Finished", 1_002);
    e.set(overdue, prop::DUE, Value::Date(DateSpec::Day(DAY - 1)), 1_010).unwrap();
    e.set(today, prop::DUE, Value::Date(DateSpec::Day(DAY)), 1_011).unwrap();
    e.set(finished, prop::DUE, Value::Date(DateSpec::Day(DAY - 9)), 1_012).unwrap();
    e.set(finished, prop::STATUS, Value::Ref(status::DONE), 1_013).unwrap();

    let rows: Vec<Row> = tasks(&e, None, &Lens::Everything, DAY, 0)
        .unwrap()
        .groups
        .into_iter()
        .flat_map(|g| g.rows)
        .collect();
    let late = |id: EntityId| rows.iter().find(|r| r.id == id).unwrap().late;
    assert!(late(overdue));
    assert!(!late(today));
    assert!(!late(finished));

    // An event is never late: it happened. The rule is one function.
    let meeting = e.create(kind::EVENT, Some("Meeting"), 1_020).unwrap();
    e.set(meeting, prop::DUE, Value::Date(DateSpec::Day(DAY - 1)), 1_021).unwrap();
    assert!(!is_late(&row(&e, meeting, 0).unwrap(), DAY));
    assert!(is_late(&row(&e, overdue, 0).unwrap(), DAY));
}

#[test]
fn the_screens_counts_ignore_the_project_filter() {
    // "6 open · 2 late" is the size of the SCREEN, not of the slice you
    // are looking at: every open task the lens admits, plus the open
    // lines inside its notes.
    let mut e = engine();
    let roof = e.create(kind::PROJECT, Some("Roof"), 1_000).unwrap();
    let a = task(&mut e, "Order slates", 1_001);
    let b = task(&mut e, "Prune", 1_002);
    let c = task(&mut e, "Already done", 1_003);
    e.set(a, prop::PROJECT, Value::Ref(roof), 1_010).unwrap();
    e.set(b, prop::DUE, Value::Date(DateSpec::Day(DAY - 2)), 1_011).unwrap();
    e.set(c, prop::STATUS, Value::Ref(status::DONE), 1_012).unwrap();
    let note = e.create(kind::NOTE, Some("Weekend"), 1_020).unwrap();
    e.set_content(
        note,
        vec![Span::Break(rich::Block::Task { depth: 0, done: false }), Span::text("buy rope")],
        0,
        1_021,
    )
    .unwrap();

    for project in [None, Some(roof)] {
        let t = tasks(&e, project, &Lens::Everything, DAY, 0).unwrap();
        assert_eq!(t.open, 3, "two open tasks and one open line, whatever the filter");
        assert_eq!(t.late, 1);
    }
    let narrowed = tasks(&e, Some(roof), &Lens::Everything, DAY, 0).unwrap();
    let found: Vec<&str> = narrowed.groups.iter().flat_map(|x| titles(&x.rows)).collect();
    assert_eq!(found, vec!["Order slates"], "while the list itself narrows");
}

#[test]
fn the_lines_in_notes_come_with_the_answer_and_wear_the_lens() {
    let mut e = engine();
    let mine = e.create(kind::NOTE, Some("Mine"), 1_000).unwrap();
    let theirs = e.create(kind::NOTE, Some("Theirs"), 1_001).unwrap();
    for (n, note) in [mine, theirs].into_iter().enumerate() {
        e.set_content(
            note,
            vec![Span::Break(rich::Block::Task { depth: 0, done: false }), Span::text("a line")],
            0,
            1_010 + n as u64,
        )
        .unwrap();
    }
    let lens: Lens = [mine].into_iter().collect();
    let t = tasks(&e, None, &lens, DAY, 0).unwrap();
    let from: Vec<EntityId> = t.in_notes.iter().map(|l| l.note).collect();
    assert_eq!(from, vec![mine]);
    assert_eq!(t.in_notes.len(), note_tasks(&e, &lens, 0).unwrap().len(), "the same projection");
    assert_eq!(t.open, 1);
}

#[test]
fn the_project_segment_offers_the_most_used_projects() {
    // A menu, not a directory: the few you actually file under, the
    // commonest first, so it does not reshuffle between two equals.
    let mut e = engine();
    let mut projects = Vec::new();
    for n in 0..(PROJECTS_OFFERED + 2) {
        projects.push(e.create(kind::PROJECT, Some(&format!("P{n}")), 1_000 + n as u64).unwrap());
    }
    // P0 is used three times, P1 twice, the rest once each.
    let mut at = 2_000;
    for (n, p) in projects.iter().enumerate() {
        let uses = match n {
            0 => 3,
            1 => 2,
            _ => 1,
        };
        for _ in 0..uses {
            let t = task(&mut e, "t", at);
            e.set(t, prop::PROJECT, Value::Ref(*p), at + 1).unwrap();
            at += 2;
        }
    }
    let offered = tasks(&e, None, &Lens::Everything, DAY, 0).unwrap().projects;
    assert_eq!(offered.len(), PROJECTS_OFFERED);
    let names: Vec<&str> = offered.iter().map(|(_, n)| n.as_str()).collect();
    assert_eq!(&names[..3], &["P0", "P1", "P2"], "commonest first, then by name");
    assert_eq!(offered[0].0, projects[0], "and each carries its id, which is what filters");
}

#[test]
fn filtering_by_project_reads_the_cell_not_a_name() {
    let mut e = engine();
    let roof = e.create(kind::PROJECT, Some("Roof"), 1_000).unwrap();
    let other = e.create(kind::PROJECT, Some("Garden"), 1_001).unwrap();
    let a = task(&mut e, "Order slates", 1_002);
    let b = task(&mut e, "Prune", 1_003);
    e.set(a, prop::PROJECT, Value::Ref(roof), 1_010).unwrap();
    e.set(b, prop::PROJECT, Value::Ref(other), 1_011).unwrap();

    let g = tasks(&e, Some(roof), &Lens::Everything, DAY, 0).unwrap().groups;
    let found: Vec<&str> = g.iter().flat_map(|x| titles(&x.rows)).collect();
    assert_eq!(found, vec!["Order slates"]);

    // Renaming the project does not move a task, because the cell holds
    // the id — the claim core.md §2 makes, on this surface.
    e.set(roof, prop::NAME, Value::Text("The roof".into()), 2_000).unwrap();
    let g = tasks(&e, Some(roof), &Lens::Everything, DAY, 0).unwrap().groups;
    assert_eq!(g.iter().flat_map(|x| titles(&x.rows)).count(), 1);
}

// ---- the calendar -------------------------------------------------------
//
// Rust answers WHICH things are on WHICH day. Where a block sits and how
// wide it is stays with the shell, because it has to move every frame of
// a drag (owner, 2026-09-30).

fn event_at(e: &mut Engine, name: &str, day: i32, hour: i64, minute: i64) -> EntityId {
    let id = e.create(kind::EVENT, Some(name), 1_000).unwrap();
    e.set(id, prop::DUE, Value::Date(DateSpec::Instant { ms: at(day, hour, minute), tz: 0 }), 1_001)
        .unwrap();
    id
}

#[test]
fn the_calendar_puts_each_thing_on_its_day_with_all_day_apart() {
    let mut e = engine();
    event_at(&mut e, "Standup", DAY, 9, 30);
    let b = task(&mut e, "All day thing", 1_002);
    e.set(b, prop::DUE, Value::Date(DateSpec::Day(DAY)), 1_003).unwrap();
    event_at(&mut e, "Dentist", DAY + 2, 14, 0);
    let filed = event_at(&mut e, "Archived", DAY, 11, 0);
    e.set(filed, prop::ARCHIVED, Value::Bool(true), 1_004).unwrap();

    let days = calendar(&e, DAY, DAY + 3, &Lens::Everything, 0).unwrap();
    let which: Vec<i32> = days.iter().map(|d| d.day).collect();
    assert_eq!(which, vec![DAY, DAY + 2], "a day with nothing on it is not sent");
    assert_eq!(titles(&days[0].all_day), vec!["All day thing"]);
    assert_eq!(titles(&days[0].timed), vec!["Standup"], "and archived is on no surface");
    assert_eq!(titles(&days[1].timed), vec!["Dentist"]);
}

#[test]
fn the_calendar_runs_in_time_order_and_stops_at_its_edges() {
    let mut e = engine();
    event_at(&mut e, "Just before", DAY - 1, 23, 59);
    event_at(&mut e, "Late", DAY, 22, 0);
    event_at(&mut e, "Midnight", DAY, 0, 0);
    event_at(&mut e, "Last minute", DAY + 1, 23, 59);
    event_at(&mut e, "Just after", DAY + 2, 0, 0);

    let days = calendar(&e, DAY, DAY + 1, &Lens::Everything, 0).unwrap();
    assert_eq!(titles(&days[0].timed), vec!["Midnight", "Late"]);
    assert_eq!(titles(&days[1].timed), vec!["Last minute"]);
    assert_eq!(days.len(), 2);
}

#[test]
fn the_calendar_wears_the_lens_like_every_other_surface() {
    let mut e = engine();
    let seen = event_at(&mut e, "Mine", DAY, 10, 0);
    event_at(&mut e, "Theirs", DAY, 10, 0);
    let lens: Lens = [seen].into_iter().collect();
    let days = calendar(&e, DAY, DAY, &lens, 0).unwrap();
    assert_eq!(titles(&days[0].timed), vec!["Mine"]);
}

#[test]
fn a_dated_backstage_thing_stays_off_the_day_and_out_of_late() {
    // The same rule on the time surfaces. Nothing should ever give a
    // workspace a due date, but "should never" is not a mechanism.
    let mut e = engine();
    let ws = e.declare(kind::WORKSPACE, "Deep work", 1_000).unwrap();
    e.set(ws, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, 10, 0), tz: 0 }), 1_001)
        .unwrap();
    let real = task(&mut e, "A real task", 1_002);
    e.set(real, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, 11, 0), tz: 0 }), 1_003)
        .unwrap();

    let days = calendar(&e, DAY, DAY, &Lens::Everything, 0).unwrap();
    let ids: Vec<EntityId> = days[0].timed.iter().map(|r| r.id).collect();
    assert_eq!(ids, vec![real]);

    let t = liv_surface::today::today(&e, at(DAY + 1, 9, 0), 0, &Lens::Everything).unwrap();
    assert_eq!(titles(&t.late), vec!["A real task"], "and it is not late either");
}

// ---- an id is never a name ---------------------------------------------

/// **Owner, 2026-09-13: *"LivID shouldn't be read by the user."*** And:
/// *"Unnamed task/event/note should get a sensible name."*
///
/// The two are one rule. The old fallback was `#4142`, which is both — an
/// id on screen AND a name that tells a person nothing. It reached four
/// surfaces, and the shell mapped it away on only one.
/// **A made name is in the phone's time** (owner, 2026-10-01: a task made
/// at 06:07 in Stockholm read "Task · 1 Oct 04:07" — UTC). An id knows the
/// instant it was made; the phone's offset says what its clock read then.
#[test]
fn a_made_name_reads_the_phones_clock() {
    let mut e = engine();
    let day = days_from_civil(2026, 10, 1);
    let made = day as u64 * 86_400_000 + (4 * 60 + 7) * 60_000; // 04:07 UTC
    let task = e.create(kind::TASK, None, made).unwrap();
    assert_eq!(row(&e, task, 120).unwrap().title, "Task · 1 Oct 06:07", "two hours ahead");
    assert_eq!(row(&e, task, 0).unwrap().title, "Task · 1 Oct 04:07", "on UTC");
    assert_eq!(row(&e, task, -300).unwrap().title, "Task · 30 Sep 23:07", "and the day moves");
}

#[test]
fn a_nameless_thing_gets_a_sensible_name_and_never_an_id() {
    let mut e = engine();
    // 1_789_000_000_000 ms is 2026-09-06 09:46 UTC.
    let when = 1_789_033_560_000u64;
    let task = e.create(kind::TASK, None, when).unwrap();
    let note = e.create(kind::NOTE, None, when + 60_000).unwrap();
    let event = e.create(kind::EVENT, None, when + 120_000).unwrap();
    // A capture with no kind at all.
    let loose = e.mint(when + 180_000);
    e.commit(vec![Op::CreateEntity { entity: loose }], action::CREATE, Author::User, when + 180_000)
        .unwrap();

    for id in [task, note, event, loose] {
        let r = row(&e, id, 0).unwrap();
        assert!(r.untitled, "still flagged so a surface can draw it quietly");
        assert!(!r.title.is_empty(), "never empty");
        // THE POINT. Not the id, not any part of it.
        assert!(!r.title.contains(&id.hex()), "an id is never a name: {:?}", r.title);
        assert!(!r.title.contains('#'), "nor a hash-number: {:?}", r.title);
        assert_ne!(r.title, "Untitled", "nor the vault's word for a failure to name");
    }

    // IT SAYS WHAT THE THING IS, from the model's own word — not a copy
    // of that word kept in a shell (`one-core.md` §4).
    assert!(row(&e, task, 0).unwrap().title.starts_with("Task · "));
    assert!(row(&e, note, 0).unwrap().title.starts_with("Note · "));
    assert!(row(&e, event, 0).unwrap().title.starts_with("Event · "));
    // An untyped capture is not claimed to be a note.
    assert!(row(&e, loose, 0).unwrap().title.starts_with("Capture · "));

    // AND IT SAYS WHEN, which is what distinguishes fourteen nameless
    // rows from each other where "Task" fourteen times does not. The
    // harness had already tripped over exactly that, unable to aim at one
    // of three notes sharing a label.
    let a = row(&e, task, 0).unwrap().title;
    let b = row(&e, note, 0).unwrap().title;
    assert_ne!(a, b);
    assert!(a.contains("Sep"), "the month reads as a word: {a:?}");
    assert!(a.contains(':'), "and the time is there to break a tie: {a:?}");

    // A NAME STILL WINS, and so does a body's first line — a made name is
    // the last resort, not the first.
    let named = e.create(kind::TASK, Some("Order slates"), when).unwrap();
    assert_eq!(row(&e, named, 0).unwrap().title, "Order slates");
    assert!(!row(&e, named, 0).unwrap().untitled);

    let scrap = e.create(kind::NOTE, None, when).unwrap();
    e.set(
        scrap,
        prop::BODY,
        Value::Rich(vec![
            Span::Break(Block::Heading(1)),
            Span::text("Trip planning"),
            Span::Break(Block::Body),
            Span::text("ferries"),
        ]),
        when,
    )
    .unwrap();
    assert_eq!(row(&e, scrap, 0).unwrap().title, "Trip planning");
}

/// **DOES THIS THING HAVE WORDS IN IT?** — one boolean, four callers.
///
/// The iOS shell asks it in four places: whether a scrap is an unrouted
/// capture (the Inbox's list), whether a record card opens with its
/// notes showing, whether a tab card says "Content lives on this
/// entity", and whether the links list should reload. On `core/` it was
/// answered by the body's compare-and-swap fingerprint being non-zero.
/// The engine hands that print back per body from `liv_read_body`
/// rather than shipping it for every row, so the shell's accessor
/// returned nil — and all four questions quietly answered "no".
///
/// The Inbox was the one a person could see: the panel counted eight
/// captures while the screen itself said "Nothing to route" (owner,
/// 2026-09-15).
///
/// A boolean is the right answer here and a fingerprint was never
/// needed: three of the four want "is there anything in it", and the
/// fourth wants "did MY base move", which is a different question.
/// `row` already reads `prop::BODY` out of the same `cells_of` it reads
/// everything else from, so this costs nothing.
#[test]
fn a_row_says_whether_it_holds_any_words() {
    let mut e = engine();
    let when = at(DAY, 9, 0) as u64;

    let empty = e.create(kind::NOTE, Some("Nothing in it"), when).unwrap();
    assert!(!row(&e, empty, 0).unwrap().has_body, "a name is not a body");

    let written = e.create(kind::NOTE, Some("Slates"), when).unwrap();
    e.set(written, prop::BODY, Value::Rich(vec![Span::text("call the roofer")]), when).unwrap();
    assert!(row(&e, written, 0).unwrap().has_body);

    // THE INBOX'S OWN CASE: an untyped capture. It has no name and no
    // kind, and the words it was caught with are the whole of it.
    let caught = e.capture("ferry times", when).unwrap();
    let r = row(&e, caught, 0).unwrap();
    assert!(r.has_body, "a capture is nothing BUT its body");
    assert_eq!(r.kind_word, None, "and it is still untyped");

    // A capture of nothing is not a capture of something. `clerk.rs`
    // already makes one of these, so it is a shape that occurs.
    let blank = e.capture("", when).unwrap();
    assert!(!row(&e, blank, 0).unwrap().has_body, "an empty body is not a body");

    // A body EMPTIED again says no, rather than staying true because it
    // once said yes.
    e.set(written, prop::BODY, Value::Rich(vec![]), when + 1).unwrap();
    assert!(!row(&e, written, 0).unwrap().has_body);

    // Whitespace is not words. A shell drawing "Content lives on this
    // entity" for a note holding one space would be lying to the person
    // who is looking for the content.
    let spaces = e.create(kind::NOTE, None, when).unwrap();
    e.set(spaces, prop::BODY, Value::Rich(vec![Span::text("   \n  ")]), when).unwrap();
    assert!(!row(&e, spaces, 0).unwrap().has_body);
}
