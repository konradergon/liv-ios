//! The library: every row the app looks things up in, the Notes list, the
//! Unsorted list and the count beside each view in the library panel —
//! one pass over the box.
//!
//! Each rule here was in Swift until 2026-09-30: Notes in
//! `Everything.swift`, Unsorted in `Kit.swift` (`livIsUnfiled`), the counts
//! in `Panel.swift` (`ViewCounts`). The panel's count and the list it opens
//! disagreed twice in September, because they were two copies.

use liv_engine::*;
use liv_surface::library::{library, Library};
use liv_surface::tasks::tasks;
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

/// The library as it reads at nine on DAY, on a clock at UTC.
fn read(e: &Engine, lens: &Lens) -> Library {
    library(e, at(DAY, 9, 0), 0, lens).unwrap()
}

fn titles<'a>(lib: &'a Library, ids: &[EntityId]) -> Vec<&'a str> {
    ids.iter()
        .map(|id| lib.all.iter().find(|r| r.id == *id).expect("a listed id is in `all`").title.as_str())
        .collect()
}

#[test]
fn all_is_every_front_of_house_row_newest_first() {
    let mut e = engine();
    let note = e.create(kind::NOTE, Some("A note"), 1_000).unwrap();
    let t = e.create(kind::TASK, Some("A task"), 1_001).unwrap();
    let gone = e.create(kind::NOTE, Some("Thrown away"), 1_002).unwrap();
    let filed = e.create(kind::NOTE, Some("Archived"), 1_003).unwrap();
    e.declare(kind::AREA, "Home", 1_004).unwrap();
    e.trash(gone, 2_000).unwrap();
    e.set(filed, prop::ARCHIVED, Value::Bool(true), 2_001).unwrap();

    let lib = read(&e, &Lens::Everything);
    let ids: Vec<EntityId> = lib.all.iter().map(|r| r.id).collect();
    assert_eq!(ids, vec![t, note], "newest first; no trash, archive or furniture");
}

#[test]
fn notes_is_what_opens_as_a_page_in_the_lens_last_touched_first() {
    // "NOTES, and only notes: a task is a record and opens as a card, so a
    // list of things that open as a PAGE is the honest content of the
    // word. Files count; a file is a document you work on."
    let mut e = engine();
    let old = e.create(kind::NOTE, Some("Old note"), 1_000).unwrap();
    let new = e.create(kind::NOTE, Some("New note"), 1_001).unwrap();
    let scrap = e.capture("a scrap", 1_002).unwrap();
    e.create(kind::TASK, Some("A task"), 1_003).unwrap();
    e.create(kind::EVENT, Some("An event"), 1_004).unwrap();
    // Touching the old note brings it to the top.
    e.set(old, prop::NAME, Value::Text("Old note, edited".into()), 5_000).unwrap();

    let lib = read(&e, &Lens::Everything);
    assert_eq!(titles(&lib, &lib.notes), vec!["Old note, edited", "a scrap", "New note"]);

    // It wears the workspace lens.
    let lens: Lens = [new, scrap].into_iter().collect();
    let lib = read(&e, &lens);
    assert_eq!(titles(&lib, &lib.notes), vec!["a scrap", "New note"]);
}

#[test]
fn unsorted_is_what_a_person_files_with_no_area_whatever_the_lens() {
    let mut e = engine();
    let home = e.declare(kind::AREA, "Home", 1_000).unwrap();
    let loose_note = e.create(kind::NOTE, Some("Loose note"), 1_001).unwrap();
    let loose_task = e.create(kind::TASK, Some("Loose task"), 1_002).unwrap();
    let filed = e.create(kind::NOTE, Some("Filed note"), 1_003).unwrap();
    e.set(filed, prop::AREA, Value::Ref(home), 1_004).unwrap();
    let empty = e.create(kind::NOTE, None, 1_005).unwrap();
    let scrap = e.capture("caught in the share sheet", 1_006).unwrap();
    // Furniture the areas are FOR, not things waiting to be put in one.
    e.create(kind::PROJECT, Some("Roof"), 1_007).unwrap();
    e.create(kind::PERSON, Some("Sam"), 1_008).unwrap();
    // AN AREA WITH NO NAME IS NO AREA: one of the six built-in areas the
    // app stopped shipping on 2026-09-21. The reference is still there and
    // nothing can show it.
    let old_area = EntityId([0, 0, 0, 0, 0, 0, 0x83, 0, 0x80, b'L', b'I', b'V', b'F', b'U', b'R', b'N']);
    let stranded = e.create(kind::NOTE, Some("Filed under an old area"), 1_009).unwrap();
    e.set(stranded, prop::AREA, Value::Ref(old_area), 1_010).unwrap();

    // A lens that admits none of them: Unsorted ignores it (design/ios.md
    // M4) — a thing made under the wrong workspace must not vanish.
    let lens: Lens = [filed].into_iter().collect();
    let lib = read(&e, &lens);
    let expected = vec![stranded, scrap, empty, loose_task, loose_note];
    assert_eq!(lib.unsorted, expected, "newest first, and never lensed");
    assert!(is_unsorted(&row(&e, loose_note).unwrap()));
    assert!(!is_unsorted(&row(&e, filed).unwrap()));
}

#[test]
fn the_panel_counts_the_lists_it_opens() {
    // "A count beside a row is a promise about the list that row opens."
    let mut e = engine();
    let late = e.create(kind::TASK, Some("Late"), 1_000).unwrap();
    e.set(late, prop::DUE, Value::Date(DateSpec::Day(DAY - 1)), 1_001).unwrap();
    let due_today = e.create(kind::TASK, Some("Due today"), 1_002).unwrap();
    e.set(due_today, prop::DUE, Value::Date(DateSpec::Day(DAY)), 1_003).unwrap();
    let done_today = e.create(kind::TASK, Some("Done today"), 1_004).unwrap();
    e.set(done_today, prop::DUE, Value::Date(DateSpec::Day(DAY)), 1_005).unwrap();
    e.set(done_today, prop::STATUS, Value::Ref(status::DONE), 1_006).unwrap();
    let tomorrow = e.create(kind::TASK, Some("Tomorrow"), 1_007).unwrap();
    e.set(tomorrow, prop::DUE, Value::Date(DateSpec::Day(DAY + 1)), 1_008).unwrap();
    let meeting = e.create(kind::EVENT, Some("Meeting"), 1_009).unwrap();
    e.set(meeting, prop::DUE, Value::Date(DateSpec::Day(DAY)), 1_010).unwrap();
    e.create(kind::NOTE, Some("A note"), 1_011).unwrap();

    let lib = read(&e, &Lens::Everything);
    let c = &lib.counts;
    assert_eq!(c.notes, lib.notes.len());
    assert_eq!(c.unsorted, lib.unsorted.len());
    let task_rows: usize = tasks(&e, None, &Lens::Everything, DAY)
        .unwrap()
        .groups
        .iter()
        .map(|g| g.rows.len())
        .sum();
    assert_eq!(c.tasks, task_rows, "the Tasks screen lists every task, done ones folded");
    assert_eq!(c.events, 1);
    // Today: what is due today or earlier and still open — not the one
    // already done, not tomorrow's, not the meeting (it cannot be ticked).
    assert_eq!(c.today, 2);

    // The lens applies to every count but Unsorted's.
    let lens: Lens = [late].into_iter().collect();
    let lib = read(&e, &lens);
    assert_eq!((lib.counts.today, lib.counts.tasks, lib.counts.events, lib.counts.notes), (1, 1, 0, 0));
    assert_eq!(lib.counts.unsorted, lib.unsorted.len());
}

#[test]
fn every_row_in_the_library_says_whether_it_is_late() {
    // The properties card reads a row out of the library and turns its due
    // red when it is late. It used to work that out itself — a third copy
    // of the rule — so the answer that knows the day says so.
    let mut e = engine();
    let t = e.create(kind::TASK, Some("Late"), 1_000).unwrap();
    e.set(t, prop::DUE, Value::Date(DateSpec::Day(DAY - 1)), 1_001).unwrap();
    let meeting = e.create(kind::EVENT, Some("Yesterday's meeting"), 1_002).unwrap();
    e.set(meeting, prop::DUE, Value::Date(DateSpec::Day(DAY - 1)), 1_003).unwrap();
    let lib = read(&e, &Lens::Everything);
    let late = |id: EntityId| lib.all.iter().find(|r| r.id == id).unwrap().late;
    assert!(late(t));
    assert!(!late(meeting), "an event is never late");
}

#[test]
fn a_thing_carrying_a_file_opens_as_a_file_whatever_its_kind_says() {
    // A FILE is checked first, because having a file crosscuts the kinds —
    // a scanned contract is a file and can also be a task, and what you
    // want to see is the contract. Before this it fell through to
    // `.document` and opened as an empty markdown editor over a real file
    // (shipped bug, found 2026-08-08).
    let mut e = engine();
    let scan = e.create(kind::TASK, Some("Signed contract"), 1_000).unwrap();
    e.set(scan, prop::FILE, Value::Blob([7u8; 32]), 1_001).unwrap();
    let plain = e.create(kind::TASK, Some("Ordinary task"), 1_002).unwrap();
    let note = e.create(kind::NOTE, Some("A note"), 1_003).unwrap();
    let capture = e.mint(1_004);
    e.commit(vec![Op::CreateEntity { entity: capture }], action::CREATE, Author::User, 1_004)
        .unwrap();

    let lib = read(&e, &Lens::Everything);
    let of = |id: EntityId| shape_of(lib.all.iter().find(|r| r.id == id).unwrap());
    assert_eq!(of(scan), Shape::File, "a task carrying a file is a file");
    assert_eq!(of(plain), Shape::Record);
    assert_eq!(of(note), Shape::Document);
    assert_eq!(of(capture), Shape::Document, "an untyped capture is a document");

    // And Notes, being what opens as a page, holds the file and not the task.
    assert!(lib.notes.contains(&scan) && lib.notes.contains(&note) && lib.notes.contains(&capture));
    assert!(!lib.notes.contains(&plain));
}

#[test]
fn backstage_furniture_is_on_no_list() {
    // FOUND BY A FAILING TEST, not by reading. A minted area IS an entity
    // with no area, so it turned up among the unfiled notes. The engine
    // stores backstage things like anything else, so the rule has to be
    // stated — and it is stated once, in `visible`.
    let mut e = engine();
    let note = e.create(kind::NOTE, Some("A real note"), 1_000).unwrap();
    let my_area = e.declare(kind::AREA, "Woodworking", 1_001).unwrap();
    let my_status = e.declare(kind::STATUS, "Blocked", 1_002).unwrap();
    let workspace = e.declare(kind::WORKSPACE, "Deep work", 1_003).unwrap();
    let field = e.declare_field("mileage", "number", false, 1_004).unwrap();

    let lib = read(&e, &Lens::Everything);
    let all: Vec<EntityId> = lib.all.iter().map(|r| r.id).collect();
    for (list, ids) in [("all", &all), ("notes", &lib.notes), ("unsorted", &lib.unsorted)] {
        assert!(ids.contains(&note), "{list} shows the note");
        for (what, id) in
            [("area", my_area), ("status", my_status), ("workspace", workspace), ("field", field)]
        {
            assert!(!ids.contains(&id), "{list} must not show the {what}");
        }
    }
    // And it is not a display trick: they really are marked, and the mark
    // is what `visible` reads.
    assert!(row(&e, my_area).unwrap().working);
    assert!(!row(&e, note).unwrap().working);
}

#[test]
fn any_area_files_a_thing_just_as_well_as_another() {
    // Every area is one a person made, and filing reads the cell, not which
    // area it points at.
    let mut e = engine();
    let loose = e.create(kind::TASK, Some("Hesitated-over task"), 1_000).unwrap();
    assert_eq!(read(&e, &Lens::Everything).unsorted, vec![loose]);
    let mine = e.declare(kind::AREA, "Woodworking", 2_000).unwrap();
    e.set(loose, prop::AREA, Value::Ref(mine), 2_001).unwrap();
    assert!(read(&e, &Lens::Everything).unsorted.is_empty());
}
