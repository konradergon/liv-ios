//! Today's rules, under test for the first time.
//!
//! Every assertion below corresponds to a line of `Today.swift` that no
//! test in the workspace could reach. Where the Swift carried a comment
//! stating the rule — usually with the owner's ruling attached — the
//! comment is quoted, because that comment WAS the specification.

use liv_engine::*;
use liv_surface::today::today;
use liv_surface::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const DAY: i32 = 20_700;
/// 09:15 on DAY.
fn at(day: i32, hour: i64, minute: i64) -> i64 {
    day as i64 * 86_400_000 + hour * 3_600_000 + minute * 60_000
}

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

/// A task due at a clock time.
fn timed_task(e: &mut Engine, name: &str, day: i32, hour: i64, minute: i64) -> EntityId {
    let id = e.create(kind::TASK, Some(name), 1_000).unwrap();
    e.set(
        id,
        prop::DUE,
        Value::Date(DateSpec::Instant { ms: at(day, hour, minute), tz: 0 }),
        1_001,
    )
    .unwrap();
    id
}

/// A task due on a day, with no clock time.
fn all_day_task(e: &mut Engine, name: &str, day: i32) -> EntityId {
    let id = e.create(kind::TASK, Some(name), 1_000).unwrap();
    e.set(id, prop::DUE, Value::Date(DateSpec::Day(day)), 1_001).unwrap();
    id
}

fn titles(rows: &[Row]) -> Vec<&str> {
    rows.iter().map(|r| r.title.as_str()).collect()
}

#[test]
fn the_day_runs_in_time_order_with_tasks_and_events_interleaved() {
    // The old view kept events and tasks in separate blocks; one
    // time-ordered timeline is the day as it actually runs.
    let mut e = engine();
    timed_task(&mut e, "Dentist", DAY, 14, 0);
    let ev = e.create(kind::EVENT, Some("Standup"), 1_000).unwrap();
    e.set(ev, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, 9, 30), tz: 0 }), 1_001)
        .unwrap();
    timed_task(&mut e, "Invoice", DAY, 11, 0);

    // Shown on a day that is not today, so nothing is "passed".
    let t = today(&e, DAY, DAY + 1, at(DAY + 1, 8, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.ahead), vec!["Standup", "Invoice", "Dentist"]);
    assert!(t.passed.is_empty(), "only today has a passed/ahead split");
    assert_eq!(t.next, None, "and only today lights the next row");
}

#[test]
fn today_knows_the_time_and_other_days_do_not() {
    // "The timeline knows the time (today only): what passed dims, the
    // next thing up is lit."
    let mut e = engine();
    timed_task(&mut e, "Morning", DAY, 9, 0);
    timed_task(&mut e, "Noon", DAY, 12, 0);
    timed_task(&mut e, "Evening", DAY, 18, 0);

    let now = at(DAY, 13, 0);
    let t = today(&e, DAY, DAY, now, &Lens::Everything).unwrap();
    assert_eq!(titles(&t.passed), vec!["Morning", "Noon"]);
    assert_eq!(titles(&t.ahead), vec!["Evening"]);
    assert_eq!(t.next, t.ahead.first().map(|r| r.id), "the next thing up is lit");

    // The same box, shown on a day that is not today.
    let elsewhere = today(&e, DAY, DAY + 3, at(DAY + 3, 13, 0), &Lens::Everything).unwrap();
    assert!(elsewhere.passed.is_empty());
    assert_eq!(titles(&elsewhere.ahead), vec!["Morning", "Noon", "Evening"]);
}

#[test]
fn an_all_day_thing_belongs_to_the_day_and_not_to_an_hour() {
    // A day is not an instant (op.rs): "due Friday" and "starts 14:00"
    // are different things, and they go in different places.
    let mut e = engine();
    all_day_task(&mut e, "Renew the passport", DAY);
    timed_task(&mut e, "Dentist", DAY, 14, 0);

    let t = today(&e, DAY, DAY, at(DAY, 8, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.all_day), vec!["Renew the passport"]);
    assert_eq!(titles(&t.ahead), vec!["Dentist"]);
    assert!(t.all_day[0].all_day);
    assert!(!t.ahead[0].all_day);
}

#[test]
fn late_is_incomplete_tasks_whose_day_has_passed_and_nothing_else() {
    // THE OWNER'S RULING, quoted from Today.swift: "LATE = incomplete
    // TASKS whose day has passed. Not events, not notes — a thing is
    // late only if it can still be done."
    let mut e = engine();
    let overdue = timed_task(&mut e, "Overdue task", DAY - 2, 10, 0);
    timed_task(&mut e, "Older overdue task", DAY - 9, 10, 0);

    let past_event = e.create(kind::EVENT, Some("Last week's standup"), 1_000).unwrap();
    e.set(past_event, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY - 2, 9, 0), tz: 0 }), 1_001)
        .unwrap();
    let past_note = e.create(kind::NOTE, Some("A dated note"), 1_000).unwrap();
    e.set(past_note, prop::DUE, Value::Date(DateSpec::Day(DAY - 2)), 1_001).unwrap();

    let t = today(&e, DAY, DAY, at(DAY, 8, 0), &Lens::Everything).unwrap();
    // Most recent first: yesterday's is more actionable than last year's.
    assert_eq!(titles(&t.late), vec!["Overdue task", "Older overdue task"]);

    // Finishing it takes it out of Late, and nothing else changes.
    e.set(overdue, prop::STATUS, Value::Ref(status::DONE), 2_000).unwrap();
    let t = today(&e, DAY, DAY, at(DAY, 8, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.late), vec!["Older overdue task"]);
}

#[test]
fn a_minted_status_that_completes_finishes_a_thing_just_like_done() {
    // The shell answered this by collecting the NAMES of completing
    // options into a Set<String> and testing membership by string, which
    // makes "Done" and "done" two different answers. It is a cell now.
    let mut e = engine();
    // kind::STATUS, not kind::OPTION — the status cell is
    // `Holds::RefTo(kind::STATUS)`, so a select's generic option is
    // refused there and a minted STATUS is not. That refusal is the model
    // doing its job: "Shipped" is a status, "Urgent" is a priority, and
    // they do not go in each other's cells.
    let shipped = e.declare(kind::STATUS, "Shipped", 1_000).unwrap();
    e.set(shipped, prop::COMPLETES, Value::Bool(true), 1_001).unwrap();
    let parked = e.declare(kind::STATUS, "Parked", 1_002).unwrap();

    let a = timed_task(&mut e, "Ship it", DAY - 1, 10, 0);
    let b = timed_task(&mut e, "Think about it", DAY - 1, 11, 0);
    e.set(a, prop::STATUS, Value::Ref(shipped), 2_000).unwrap();
    e.set(b, prop::STATUS, Value::Ref(parked), 2_001).unwrap();

    // And a generic option really is refused there.
    let urgent = e.declare(kind::OPTION, "Urgent", 1_003).unwrap();
    assert!(matches!(
        e.set(a, prop::STATUS, Value::Ref(urgent), 2_002),
        Err(WriteError::Refused(Refused::WrongClass))
    ));

    assert!(completes(&e, shipped).unwrap());
    assert!(!completes(&e, parked).unwrap());
    assert!(!completes(&e, status::TODO).unwrap());
    assert!(completes(&e, status::DONE).unwrap());

    let t = today(&e, DAY, DAY, at(DAY, 8, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.late), vec!["Think about it"], "a completing status is done");
}

#[test]
fn a_finished_thing_on_the_day_goes_to_done_rather_than_the_timeline() {
    let mut e = engine();
    let a = timed_task(&mut e, "Already done", DAY, 9, 0);
    timed_task(&mut e, "Still to do", DAY, 10, 0);
    e.set(a, prop::STATUS, Value::Ref(status::DONE), 2_000).unwrap();

    let t = today(&e, DAY, DAY, at(DAY, 8, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.done), vec!["Already done"]);
    assert_eq!(titles(&t.ahead), vec!["Still to do"]);
    assert!(t.passed.is_empty(), "done never lands in passed, whatever the clock says");
}

#[test]
fn trashed_and_archived_things_are_on_no_surface() {
    let mut e = engine();
    let gone = timed_task(&mut e, "Trashed", DAY, 9, 0);
    let filed = timed_task(&mut e, "Archived", DAY, 10, 0);
    timed_task(&mut e, "Here", DAY, 11, 0);
    let late_gone = timed_task(&mut e, "Trashed and late", DAY - 1, 9, 0);

    e.trash(gone, 2_000).unwrap();
    e.trash(late_gone, 2_001).unwrap();
    e.set(filed, prop::ARCHIVED, Value::Bool(true), 2_002).unwrap();

    let t = today(&e, DAY, DAY, at(DAY, 8, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.ahead), vec!["Here"]);
    assert!(t.late.is_empty(), "and the late block filters the same way");

    // Restoring brings it back — trash is soft.
    e.restore(gone, 2_003).unwrap();
    let t = today(&e, DAY, DAY, at(DAY, 8, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.ahead), vec!["Trashed", "Here"]);
}

#[test]
fn a_scrap_is_titled_by_its_first_line_with_the_markers_off() {
    // The desk and the outbox ledger use the same rule, so it is one
    // function (standing rule 4) rather than three that can disagree.
    let mut e = engine();
    let scrap = e.create(kind::NOTE, None, 1_000).unwrap();
    e.set(scrap, prop::BODY, Value::Text("# Trip planning\n\nferries".into()), 1_001).unwrap();
    e.set(scrap, prop::DUE, Value::Date(DateSpec::Day(DAY)), 1_002).unwrap();

    let t = today(&e, DAY, DAY, at(DAY, 8, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.all_day), vec!["Trip planning"], "never '# Trip planning'");
    assert!(!t.all_day[0].untitled);

    // A thing with neither says so, rather than the surface inventing
    // words the shell would then have to style around.
    let bare = e.create(kind::NOTE, None, 1_003).unwrap();
    e.set(bare, prop::DUE, Value::Date(DateSpec::Day(DAY)), 1_004).unwrap();
    let t = today(&e, DAY, DAY, at(DAY, 8, 0), &Lens::Everything).unwrap();
    let empty = t.all_day.iter().find(|r| r.id == bare).unwrap();
    assert!(empty.untitled && empty.title.is_empty());
}

#[test]
fn captured_counts_what_was_made_today_from_the_id_itself() {
    // A v7 id carries its own millisecond, so "made today" needs no
    // stored value and cannot disagree with one.
    // IN ORDER, and that is not fussiness: the id generator is
    // MONOTONIC (id.rs, and a test in engine/tests/id.rs holds it down),
    // so a mint asked for an earlier millisecond than the last one gets
    // the last one instead. Real use never asks — you cannot make
    // something yesterday — but a test that does would silently be
    // measuring the clamp rather than the rule.
    let mut e = engine();
    let today_ms = at(DAY, 10, 0) as u64;
    e.create(kind::NOTE, Some("yesterday"), at(DAY - 1, 10, 0) as u64).unwrap();
    e.create(kind::NOTE, Some("one"), today_ms).unwrap();
    e.create(kind::NOTE, Some("two"), today_ms + 1_000).unwrap();

    let t = today(&e, DAY, DAY, at(DAY, 23, 0), &Lens::Everything).unwrap();
    assert_eq!(t.captured, 2);
}

#[test]
fn midnight_and_the_last_minute_of_the_day_land_on_the_right_days() {
    // `in_window` is inclusive at both ends and `day_end` is the last
    // millisecond, so this is the edge the off-by-one would live on.
    let mut e = engine();
    timed_task(&mut e, "One minute past midnight", DAY, 0, 1);
    timed_task(&mut e, "Last minute", DAY, 23, 59);
    timed_task(&mut e, "Tomorrow, just", DAY + 1, 0, 0);

    let t = today(&e, DAY, DAY, at(DAY, 0, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.ahead), vec!["One minute past midnight", "Last minute"]);

    let t = today(&e, DAY + 1, DAY, at(DAY, 0, 0), &Lens::Everything).unwrap();
    assert_eq!(titles(&t.ahead), vec!["Tomorrow, just"]);
}

#[test]
fn a_day_before_the_epoch_still_lands_on_its_own_day() {
    // `day_of` floors rather than truncating, so a negative millisecond
    // does not round toward zero and put a 1969 stamp on 1970-01-01.
    assert_eq!(day_of(-1), -1);
    assert_eq!(day_of(0), 0);
    assert_eq!(day_of(86_400_000), 1);
    assert_eq!(day_start(-1), -86_400_000);
    assert_eq!(day_end(-1), -1);
}
