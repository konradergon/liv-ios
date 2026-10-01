//! What rings. Until 2026-10-01 this was `Notify.swift`'s own walk of the
//! whole box, with its own copy of "is this a task" and "is this done".

use liv_engine::*;
use liv_surface::reminders::{reminders, rings};
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

fn timed(e: &mut Engine, k: EntityId, name: &str, day: i32, hour: i64, minute: i64) -> EntityId {
    let id = e.create(k, Some(name), 1_000).unwrap();
    e.set(id, prop::DUE, Value::Date(DateSpec::Instant { ms: at(day, hour, minute), tz: 0 }), 1_001)
        .unwrap();
    id
}

fn titles(rows: &[Row]) -> Vec<&str> {
    rows.iter().map(|r| r.title.as_str()).collect()
}

/// Nine in the morning on DAY, on a clock at UTC.
fn ringing(e: &Engine, limit: usize) -> liv_surface::reminders::Reminders {
    reminders(e, at(DAY, 9, 0), 0, limit).unwrap()
}

#[test]
fn an_open_task_and_an_event_ring_and_a_note_does_not() {
    let mut e = engine();
    timed(&mut e, kind::TASK, "Call the roofer", DAY, 14, 0);
    timed(&mut e, kind::EVENT, "Standup", DAY, 10, 0);
    timed(&mut e, kind::NOTE, "A dated note", DAY, 11, 0);
    // A status is what makes a thing a task, with or without the word.
    let scrap = e.capture("bring the ladder", 1_002).unwrap();
    e.set(scrap, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, 12, 0), tz: 0 }), 1_003)
        .unwrap();
    e.set(scrap, prop::STATUS, Value::Ref(status::TODO), 1_004).unwrap();

    let r = ringing(&e, 64);
    assert_eq!(titles(&r.soonest), vec!["Standup", "bring the ladder", "Call the roofer"]);
}

#[test]
fn a_finished_task_does_not_ring() {
    let mut e = engine();
    let done = timed(&mut e, kind::TASK, "Already done", DAY, 14, 0);
    e.set(done, prop::STATUS, Value::Ref(status::DONE), 2_000).unwrap();
    timed(&mut e, kind::TASK, "Still to do", DAY, 15, 0);
    assert_eq!(titles(&ringing(&e, 64).soonest), vec!["Still to do"]);
}

#[test]
fn a_bare_date_never_rings() {
    // "A date reminder shouldn't be a thing" (owner, 2026-08-06): a due
    // with no clock time does not ring at all — not at midnight, not at a
    // hidden 09:00.
    let mut e = engine();
    let t = e.create(kind::TASK, Some("Some day this week"), 1_000).unwrap();
    e.set(t, prop::DUE, Value::Date(DateSpec::Day(DAY + 1)), 1_001).unwrap();
    assert!(ringing(&e, 64).soonest.is_empty());
}

#[test]
fn only_what_is_still_to_come_rings_on_the_phones_clock() {
    // Half past midnight in Stockholm is 22:30 UTC the day before. A due
    // is a wall-clock time, so "still to come" is read on the phone's
    // clock: 00:15 has passed there, 01:00 has not.
    let mut e = engine();
    timed(&mut e, kind::TASK, "Just after midnight", DAY + 1, 0, 15);
    timed(&mut e, kind::TASK, "One o'clock", DAY + 1, 1, 0);
    let r = reminders(&e, at(DAY, 22, 30), 120, 64).unwrap();
    assert_eq!(titles(&r.soonest), vec!["One o'clock"]);
}

#[test]
fn the_trash_and_the_archive_stay_quiet() {
    let mut e = engine();
    let gone = timed(&mut e, kind::TASK, "Thrown away", DAY, 14, 0);
    let filed = timed(&mut e, kind::EVENT, "Archived", DAY, 15, 0);
    e.trash(gone, 2_000).unwrap();
    e.set(filed, prop::ARCHIVED, Value::Bool(true), 2_001).unwrap();
    assert!(ringing(&e, 64).soonest.is_empty());
}

#[test]
fn the_soonest_come_first_and_the_limit_cuts_but_still_counts() {
    // The phone keeps only so many pending notifications (iOS: 64); the
    // shell says how many, and the rest are counted so Settings can say
    // how many did not fit.
    let mut e = engine();
    for h in [16, 11, 13, 10, 15] {
        timed(&mut e, kind::TASK, &format!("{h}:00"), DAY, h, 0);
    }
    let r = ringing(&e, 3);
    assert_eq!(titles(&r.soonest), vec!["10:00", "11:00", "13:00"]);
    assert_eq!(r.total, 5);
}

#[test]
fn rings_is_one_rule_for_every_row() {
    let mut e = engine();
    let t = timed(&mut e, kind::TASK, "Task", DAY, 14, 0);
    let ev = timed(&mut e, kind::EVENT, "Event", DAY, 14, 0);
    let n = timed(&mut e, kind::NOTE, "Note", DAY, 14, 0);
    assert!(rings(&row(&e, t).unwrap()));
    assert!(rings(&row(&e, ev).unwrap()));
    assert!(!rings(&row(&e, n).unwrap()));
}
