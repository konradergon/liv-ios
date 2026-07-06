//! Worked example 2, tested: one series, few exceptions, no duplication —
//! and the horizon decision, which is the window, capped at a year.

use lotus_core::*;
use lotus_services::recurrence::occurrences;
use lotus_services::today_sections;

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("lotus_recur_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn clean(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
}

/// A series: one entity with a name, a due anchor, and a rule.
fn series(session: &mut Session, name: &str, due: DateTime, rule: &str) -> Id {
    let id = session.allocate_id();
    let due_prop = lotus_services::property_id(session.store(), "due").unwrap();
    let recur_prop = lotus_services::property_id(session.store(), "recurrence").unwrap();
    session
        .commit(
            vec![
                Command::Create { entity: id },
                Command::AddCell {
                    entity: id,
                    cell: Cell { property: props::NAME, value: Value::text(name) },
                },
                Command::AddCell {
                    entity: id,
                    cell: Cell { property: due_prop, value: Value::DateTime(due) },
                },
                Command::AddCell {
                    entity: id,
                    cell: Cell { property: recur_prop, value: Value::text(rule) },
                },
            ],
            "series",
            Author::User,
        )
        .unwrap();
    id
}

#[test]
fn weekly_expands_on_the_anchors_weekday() {
    let (mut session, path) = boxed("weekly");
    // 2026-07-07 is a Tuesday.
    let standup = series(&mut session, "standup", DateTime::date(2026, 7, 7), "every week");

    let july = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    let dates: Vec<i64> = july.iter().map(|o| o.date.civil / 10_000).collect();
    assert_eq!(dates, vec![20260707, 20260714, 20260721, 20260728]);
    assert!(july.iter().all(|o| o.series == standup));

    // The series is stored once; the occurrences are virtual. Nothing new
    // landed in the log for four Tuesdays.
    let stored = session.store().history().len();
    let _ = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    assert_eq!(session.store().history().len(), stored);

    clean(&path);
}

#[test]
fn daily_starts_at_the_anchor_never_before() {
    let (mut session, path) = boxed("daily");
    series(&mut session, "meds", DateTime::date(2026, 7, 15), "every day");

    let month = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    assert_eq!(month.len(), 17); // the 15th through the 31st
    assert_eq!(month[0].date.civil / 10_000, 20260715);

    clean(&path);
}

#[test]
fn monthly_clamps_to_short_months() {
    let (mut session, path) = boxed("monthly");
    series(&mut session, "rent", DateTime::date(2026, 1, 31), "every month");

    let feb = occurrences(
        session.store(),
        DateTime::date(2026, 2, 1),
        DateTime::date(2026, 2, 28),
    );
    // 2026 is not a leap year: the 31st clamps to the 28th.
    assert_eq!(feb.len(), 1);
    assert_eq!(feb[0].date.civil / 10_000, 20260228);

    clean(&path);
}

#[test]
fn an_exception_suppresses_exactly_one_date() {
    let (mut session, path) = boxed("exception");
    let standup = series(&mut session, "standup", DateTime::date(2026, 7, 7), "every week");

    // Worked example 2: editing one occurrence materializes an exception
    // entity referencing the series, carrying that date as its own due.
    let exception = session.allocate_id();
    let due_prop = lotus_services::property_id(session.store(), "due").unwrap();
    let exc_prop = lotus_services::property_id(session.store(), "exception-of").unwrap();
    session
        .commit(
            vec![
                Command::Create { entity: exception },
                Command::AddCell {
                    entity: exception,
                    cell: Cell {
                        property: exc_prop,
                        value: Value::Reference(standup),
                    },
                },
                Command::AddCell {
                    entity: exception,
                    cell: Cell {
                        property: due_prop,
                        value: Value::DateTime(DateTime::date(2026, 7, 14)),
                    },
                },
                Command::AddCell {
                    entity: exception,
                    cell: Cell {
                        property: props::NAME,
                        value: Value::text("standup (moved)"),
                    },
                },
            ],
            "move one standup",
            Author::User,
        )
        .unwrap();

    let july = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    let dates: Vec<i64> = july.iter().map(|o| o.date.civil / 10_000).collect();
    // The 14th belongs to the exception entity now, not the expansion.
    assert_eq!(dates, vec![20260707, 20260721, 20260728]);

    clean(&path);
}

#[test]
fn the_window_is_the_horizon_capped_at_a_year() {
    let (mut session, path) = boxed("horizon");
    series(&mut session, "meds", DateTime::date(2026, 1, 1), "every day");

    // Ask for three years; the cap answers one.
    let expanded = occurrences(
        session.store(),
        DateTime::date(2026, 1, 1),
        DateTime::date(2029, 1, 1),
    );
    assert!(expanded.len() <= 367, "got {}", expanded.len());

    clean(&path);
}

#[test]
fn a_series_occurring_today_joins_today() {
    let (mut session, path) = boxed("today");
    // Anchor Monday 2026-07-06, weekly; asking on the anchor's day.
    let standup = series(&mut session, "standup", DateTime::date(2026, 7, 6), "every week");

    let sections = today_sections(session.store(), DateTime::date(2026, 7, 6));
    assert!(sections.due.contains(&standup));

    // A week later it recurs again — but on an off day it is absent, and
    // its past occurrences have not piled up as debt.
    let tuesday = today_sections(session.store(), DateTime::date(2026, 7, 14));
    assert!(!tuesday.due.contains(&standup));
    let next_monday = today_sections(session.store(), DateTime::date(2026, 7, 13));
    assert!(next_monday.due.contains(&standup));

    clean(&path);
}

#[test]
fn nonsense_rules_recur_never() {
    let (mut session, path) = boxed("nonsense");
    series(&mut session, "junk", DateTime::date(2026, 7, 6), "every blorptime");
    series(&mut session, "junk2", DateTime::date(2026, 7, 6), "on tuesdays maybe");

    let july = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    assert!(july.is_empty());

    clean(&path);
}
