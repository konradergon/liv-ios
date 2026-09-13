//! Tasks, Everything and the day timeline — the rules, under test.
//!
//! Same standard as `today.rs`: every assertion here corresponds to a line
//! of a SwiftUI view file that no test in the workspace could reach, and
//! where the Swift carried the rule as a comment, the comment came too.

use liv_engine::*;
use liv_surface::day::{day, MIN_MINUTES};
use liv_surface::everything::{everything, slices, Slice};
use liv_surface::tasks::{tasks, Filter};
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

    let g = tasks(&e, Filter::All, &Lens::Everything, DAY).unwrap();
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

    let g = tasks(&e, Filter::All, &Lens::Everything, DAY).unwrap();
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

    let g = tasks(&e, Filter::All, &Lens::Everything, DAY).unwrap();
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

    let g = tasks(&e, Filter::All, &Lens::Everything, DAY).unwrap();
    let todo = g.iter().find(|x| x.name == "To do").unwrap();
    assert_eq!(todo.late, 2, "two of the three are overdue");
    let done = g.iter().find(|x| x.name == "Done").unwrap();
    assert_eq!(done.late, 0, "a finished band has nothing late in it by definition");
}

#[test]
fn the_chips_narrow_inside_the_lens_rather_than_replacing_it() {
    // "The lens (M4) runs BEFORE the chip filter: the workspace scopes the
    // surface, the chips narrow inside it."
    let mut e = engine();
    let seen = task(&mut e, "In the workspace", 1_000);
    let hidden = task(&mut e, "Outside it", 1_001);
    e.set(seen, prop::STATUS, Value::Ref(status::TODO), 1_010).unwrap();
    e.set(hidden, prop::STATUS, Value::Ref(status::TODO), 1_011).unwrap();

    let lens: Lens = [seen].into_iter().collect();
    let g = tasks(&e, Filter::Status(status::TODO), &lens, DAY).unwrap();
    let found: Vec<&str> = g.iter().flat_map(|x| titles(&x.rows)).collect();
    assert_eq!(found, vec!["In the workspace"]);
    assert!(lens.on());
    assert!(!Lens::Everything.on());
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

    let g = tasks(&e, Filter::Project(roof), &Lens::Everything, DAY).unwrap();
    let found: Vec<&str> = g.iter().flat_map(|x| titles(&x.rows)).collect();
    assert_eq!(found, vec!["Order slates"]);

    // Renaming the project does not move a task, because the cell holds
    // the id — the claim core.md §2 makes, on this surface.
    e.set(roof, prop::NAME, Value::Text("The roof".into()), 2_000).unwrap();
    let g = tasks(&e, Filter::Project(roof), &Lens::Everything, DAY).unwrap();
    assert_eq!(g.iter().flat_map(|x| titles(&x.rows)).count(), 1);
}

// ---- Everything --------------------------------------------------------

#[test]
fn everything_is_newest_first_and_notes_is_most_recently_touched() {
    let mut e = engine();
    let first = e.create(kind::NOTE, Some("First"), 1_000).unwrap();
    let second = e.create(kind::NOTE, Some("Second"), 2_000).unwrap();
    let t = task(&mut e, "A task", 3_000);

    let all = everything(&e, Slice::All, &Lens::Everything, DAY).unwrap();
    assert_eq!(titles(&all), vec!["A task", "Second", "First"], "newest first");

    // NOTES IS DOCUMENTS ONLY: a task is a record and opens as a card.
    let notes = everything(&e, Slice::Notes, &Lens::Everything, DAY).unwrap();
    assert_eq!(titles(&notes), vec!["Second", "First"]);
    let _ = t;

    // ORDERED BY WHAT YOU TOUCHED LAST. Editing the older one moves it to
    // the top, which is why this beats the tab switcher.
    e.set(first, prop::BODY, Value::Text("edited".into()), 4_000).unwrap();
    let notes = everything(&e, Slice::Notes, &Lens::Everything, DAY).unwrap();
    assert_eq!(titles(&notes), vec!["First", "Second"]);
    let _ = second;
}

#[test]
fn unfiled_means_no_area_and_not_no_type() {
    // The Inbox's rule keys on TYPE, which is why a task you hesitated
    // over was missing from every area AND from the Inbox. This one keys
    // on area, so it catches exactly that task.
    let mut e = engine();
    let filed = task(&mut e, "Filed task", 1_000);
    let loose = task(&mut e, "Hesitated-over task", 1_001);
    let note = e.create(kind::NOTE, Some("Loose note"), 1_002).unwrap();
    e.set(filed, prop::AREA, Value::Ref(area::WORK), 1_010).unwrap();

    let unfiled = everything(&e, Slice::Unfiled, &Lens::Everything, DAY).unwrap();
    assert_eq!(titles(&unfiled), vec!["Loose note", "Hesitated-over task"]);
    let _ = (loose, note);

    // A minted area files a thing just as well as one of ours.
    let mine = e.declare(kind::AREA, "Woodworking", 2_000).unwrap();
    e.set(loose, prop::AREA, Value::Ref(mine), 2_001).unwrap();
    let unfiled = everything(&e, Slice::Unfiled, &Lens::Everything, DAY).unwrap();
    assert_eq!(titles(&unfiled), vec!["Loose note"]);
}

#[test]
fn upcoming_is_the_next_seven_days_forward_with_today_included() {
    // "The one slice sorted FORWARD, because what is coming reads in the
    // order it will arrive. Today included: a thing due in an hour is
    // upcoming."
    let mut e = engine();
    for (n, d) in [(0, DAY - 1), (1, DAY), (2, DAY + 3), (3, DAY + 7), (4, DAY + 8)] {
        let t = task(&mut e, &format!("day {d}"), 1_000 + n);
        e.set(t, prop::DUE, Value::Date(DateSpec::Day(d)), 1_010 + n).unwrap();
    }
    let up = everything(&e, Slice::Upcoming, &Lens::Everything, DAY).unwrap();
    assert_eq!(
        titles(&up),
        vec![
            format!("day {}", DAY),
            format!("day {}", DAY + 3),
            format!("day {}", DAY + 7)
        ],
        "yesterday is not upcoming, and the horizon is inclusive at seven days"
    );
}

#[test]
fn unfiled_hides_inside_a_workspace_that_stamps_an_area() {
    // Structurally impossible there, so the chip goes rather than
    // promising an always-empty list (audit, 2026-08-04).
    assert_eq!(slices(false).len(), 4);
    assert_eq!(slices(true), vec![Slice::All, Slice::Notes, Slice::Upcoming]);
    assert_eq!(Slice::Unfiled.empty_word(), "All filed");
}

#[test]
fn a_thing_carrying_a_file_opens_as_a_file_whatever_its_kind_says() {
    // A FILE is checked first, because having a file crosscuts the six
    // kinds — a scanned contract is a file and can also be a task, and
    // what you want to see is the contract. Before this it fell through
    // to `.document` and opened as an empty markdown editor over a real
    // file (shipped bug, found 2026-08-08).
    let mut e = engine();
    let scan = task(&mut e, "Signed contract", 1_000);
    e.set(scan, prop::FILE, Value::Blob([7u8; 32]), 1_001).unwrap();
    let plain = task(&mut e, "Ordinary task", 1_002);
    let note = e.create(kind::NOTE, Some("A note"), 1_003).unwrap();
    let capture = e.mint(1_004);
    e.commit(vec![Op::CreateEntity { entity: capture }], action::CREATE, Author::User, 1_004)
        .unwrap();

    let all = everything(&e, Slice::All, &Lens::Everything, DAY).unwrap();
    let of = |id: EntityId| shape_of(all.iter().find(|r| r.id == id).unwrap());
    assert_eq!(of(scan), Shape::File, "a task carrying a file is a file");
    assert_eq!(of(plain), Shape::Record);
    assert_eq!(of(note), Shape::Document);
    assert_eq!(of(capture), Shape::Document, "an untyped capture is a document");

    // And Notes, being documents only, holds the file and not the task.
    let notes = everything(&e, Slice::Notes, &Lens::Everything, DAY).unwrap();
    let ids: Vec<EntityId> = notes.iter().map(|r| r.id).collect();
    assert!(ids.contains(&scan) && ids.contains(&note) && ids.contains(&capture));
    assert!(!ids.contains(&plain));
}

// ---- the day timeline ---------------------------------------------------

#[test]
fn the_timeline_puts_a_block_where_its_clock_time_is() {
    let mut e = engine();
    let a = e.create(kind::EVENT, Some("Standup"), 1_000).unwrap();
    e.set(a, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, 9, 30), tz: 0 }), 1_001)
        .unwrap();
    let b = task(&mut e, "All day thing", 1_002);
    e.set(b, prop::DUE, Value::Date(DateSpec::Day(DAY)), 1_003).unwrap();

    let d = day(&e, DAY, &Lens::Everything).unwrap();
    assert_eq!(titles(&d.all_day), vec!["All day thing"]);
    assert_eq!(d.blocks.len(), 1);
    assert_eq!(d.blocks[0].start_min, 9 * 60 + 30);
    assert_eq!(d.blocks[0].minutes, MIN_MINUTES, "never zero — it has to stay tappable");
    assert_eq!((d.blocks[0].column, d.blocks[0].columns), (0, 1));
}

#[test]
fn overlapping_blocks_share_the_width_as_a_cluster_not_as_pairs() {
    // Two blocks that do not touch each other can still both touch a
    // third, and all three have to share the width or the middle one is
    // drawn over.
    let mut e = engine();
    // 09:00, 09:20, 09:40 — the first and the third do not overlap (30
    // minutes each), but both overlap the second.
    for (n, m) in [(0i64, 0i64), (1, 20), (2, 40)] {
        let t = task(&mut e, &format!("t{n}"), 1_000 + n as u64);
        e.set(
            t,
            prop::DUE,
            Value::Date(DateSpec::Instant { ms: at(DAY, 9, m), tz: 0 }),
            1_010 + n as u64,
        )
        .unwrap();
    }
    let d = day(&e, DAY, &Lens::Everything).unwrap();
    assert_eq!(d.blocks.len(), 3);
    assert!(d.blocks.iter().all(|b| b.columns == 3), "one cluster of three");
    assert_eq!(
        d.blocks.iter().map(|b| b.column).collect::<Vec<_>>(),
        vec![0, 1, 2],
        "each gets its own column"
    );

    // A block well clear of them is its own cluster at full width.
    let far = task(&mut e, "afternoon", 2_000);
    e.set(far, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, 15, 0), tz: 0 }), 2_001)
        .unwrap();
    let d = day(&e, DAY, &Lens::Everything).unwrap();
    let last = d.blocks.last().unwrap();
    assert_eq!((last.column, last.columns), (0, 1));
}

#[test]
fn the_timeline_wears_the_lens_like_every_other_surface() {
    let mut e = engine();
    let seen = task(&mut e, "Mine", 1_000);
    let hidden = task(&mut e, "Theirs", 1_001);
    for t in [seen, hidden] {
        e.set(t, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, 10, 0), tz: 0 }), 1_010)
            .unwrap();
    }
    let lens: Lens = [seen].into_iter().collect();
    let d = day(&e, DAY, &lens).unwrap();
    assert_eq!(titles(&d.blocks.iter().map(|b| b.row.clone()).collect::<Vec<_>>()), vec!["Mine"]);
    assert_eq!(d.blocks[0].columns, 1, "and the hidden one does not crowd it");
}

#[test]
fn backstage_furniture_is_on_no_front_of_house_surface() {
    // FOUND BY A FAILING TEST, not by reading. A minted area IS an entity
    // with no area, so it turned up in Unfiled next to the notes.
    //
    // `core/` never exposed this: it curated the snapshot's `everything`
    // list inside the builder, so no shell ever had to know the rule. The
    // engine stores backstage things like anything else, so the rule has
    // to be stated — and it is stated once, in `visible`.
    let mut e = engine();
    let note = e.create(kind::NOTE, Some("A real note"), 1_000).unwrap();
    let my_area = e.declare(kind::AREA, "Woodworking", 1_001).unwrap();
    let my_status = e.declare(kind::STATUS, "Blocked", 1_002).unwrap();
    let workspace = e.declare(kind::WORKSPACE, "Deep work", 1_003).unwrap();
    let field = e.declare_field("mileage", "number", false, 1_004).unwrap();

    for slice in [Slice::All, Slice::Notes, Slice::Unfiled] {
        let rows = everything(&e, slice, &Lens::Everything, DAY).unwrap();
        let ids: Vec<EntityId> = rows.iter().map(|r| r.id).collect();
        assert!(ids.contains(&note), "{slice:?} shows the note");
        for (what, id) in
            [("area", my_area), ("status", my_status), ("workspace", workspace), ("field", field)]
        {
            assert!(!ids.contains(&id), "{slice:?} must not show the {what}");
        }
    }

    // And it is not a display trick: they really are marked, and the mark
    // is what `visible` reads.
    assert!(row(&e, my_area).unwrap().working);
    assert!(!row(&e, note).unwrap().working);
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

    let d = day(&e, DAY, &Lens::Everything).unwrap();
    assert_eq!(d.blocks.len(), 1);
    assert_eq!(d.blocks[0].row.id, real);

    let t = liv_surface::today::today(&e, DAY, DAY + 1, at(DAY + 1, 9, 0), &Lens::Everything)
        .unwrap();
    assert_eq!(titles(&t.late), vec!["A real task"], "and it is not late either");
}
