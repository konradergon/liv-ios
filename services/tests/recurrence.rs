//! Worked example 2, tested: one series, few exceptions, no duplication —
//! and the horizon decision, which is the window, capped at a year.

use lotus_core::*;
use lotus_services::recurrence::occurrences;
use lotus_services::today_sections;

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("lotus_recur_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn clean(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
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

// ---- P11/11c — recurrence generalized to the positioning set ----

/// A series anchored on an arbitrary date property — the generalized twin
/// of `series` (which stays due-anchored, pinning the pre-P11 world).
fn series_on(session: &mut Session, name: &str, prop: &str, anchor: DateTime, rule: &str) -> Id {
    let id = session.allocate_id();
    let anchor_prop = lotus_services::property_id(session.store(), prop).unwrap();
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
                    cell: Cell { property: anchor_prop, value: Value::DateTime(anchor) },
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
fn recurrence_expands_on_a_non_event_dated_entity() {
    // Repeat is available on ANY dated object (bp1 e23): a plain note with a
    // calendar-role `date` and a rule expands like any series — nothing in
    // the engine reads a type.
    let (mut session, path) = boxed("gen_note");
    // 2026-07-07 is a Tuesday.
    let note = series_on(&mut session, "water plants", "date", DateTime::date(2026, 7, 7), "every week");

    let july = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    let dates: Vec<i64> = july.iter().map(|o| o.date.civil / 10_000).collect();
    assert_eq!(dates, vec![20260707, 20260714, 20260721, 20260728]);
    assert!(july.iter().all(|o| o.series == note));
    clean(&path);
}

#[test]
fn a_date_anchored_series_uses_the_date_not_due() {
    // An entity carrying BOTH: `date` (a Tuesday) wins over `due` (a Friday)
    // — the calendar role is the anchor precedence (calendar_set order).
    let (mut session, path) = boxed("gen_precedence");
    let id = series_on(&mut session, "both", "date", DateTime::date(2026, 7, 7), "every week");
    let due_prop = lotus_services::property_id(session.store(), "due").unwrap();
    session
        .commit(
            vec![Command::AddCell {
                entity: id,
                cell: Cell {
                    property: due_prop,
                    value: Value::DateTime(DateTime::date(2026, 7, 10)),
                },
            }],
            "add a due too",
            Author::User,
        )
        .unwrap();

    let july = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    let dates: Vec<i64> = july.iter().filter(|o| o.series == id).map(|o| o.date.civil / 10_000).collect();
    assert_eq!(dates, vec![20260707, 20260714, 20260721, 20260728], "Tuesdays, not Fridays");
    clean(&path);
}

#[test]
fn a_rule_on_a_lookup_only_entity_is_inert() {
    // A rule beside only lookup-role dates expands NOWHERE by default — the
    // positioning set is the anchor set. The parameterized engine is the
    // sanctioned escape hatch, not a behavior flag.
    let (mut session, path) = boxed("gen_inert");
    let id = series_on(&mut session, "archived ritual", "occurred", DateTime::date(2026, 7, 7), "every week");

    let july = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    assert!(july.iter().all(|o| o.series != id), "inert on the default expansion");

    let occurred = lotus_services::property_id(session.store(), "occurred").unwrap();
    let asked = lotus_services::recurrence::occurrences_anchored(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
        &[occurred],
    );
    assert_eq!(
        asked.iter().filter(|o| o.series == id).count(),
        4,
        "explicitly asked, it expands"
    );
    clean(&path);
}

#[test]
fn an_exception_on_a_date_anchored_series_suppresses_exactly_one_date() {
    // The exception stays an ordinary entity; it covers the date of its own
    // cell on the SERIES' anchor property (bp9 OQ-B, adopted).
    let (mut session, path) = boxed("gen_exception");
    let ritual = series_on(&mut session, "ritual", "date", DateTime::date(2026, 7, 7), "every week");
    let exception = session.allocate_id();
    let date_prop = lotus_services::property_id(session.store(), "date").unwrap();
    let exc_prop = lotus_services::property_id(session.store(), "exception-of").unwrap();
    session
        .commit(
            vec![
                Command::Create { entity: exception },
                Command::AddCell {
                    entity: exception,
                    cell: Cell { property: exc_prop, value: Value::Reference(ritual) },
                },
                Command::AddCell {
                    entity: exception,
                    cell: Cell {
                        property: date_prop,
                        value: Value::DateTime(DateTime::date(2026, 7, 14)),
                    },
                },
            ],
            "move one",
            Author::User,
        )
        .unwrap();

    let july = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    let dates: Vec<i64> =
        july.iter().filter(|o| o.series == ritual).map(|o| o.date.civil / 10_000).collect();
    assert_eq!(dates, vec![20260707, 20260721, 20260728]);
    clean(&path);
}

#[test]
fn occurrences_stay_virtual_for_any_anchor() {
    let (mut session, path) = boxed("gen_virtual");
    series_on(&mut session, "virtual", "date", DateTime::date(2026, 7, 7), "every week");
    let stored = session.store().history().len();
    let _ = occurrences(
        session.store(),
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
    );
    assert_eq!(session.store().history().len(), stored, "nothing lands in the log");
    clean(&path);
}

#[test]
fn the_year_horizon_cap_holds_regardless_of_anchor() {
    let (mut session, path) = boxed("gen_horizon");
    series_on(&mut session, "daily", "date", DateTime::date(2026, 1, 1), "every day");
    let expanded = occurrences(
        session.store(),
        DateTime::date(2026, 1, 1),
        DateTime::date(2029, 1, 1),
    );
    assert!(expanded.len() <= 367, "got {}", expanded.len());
    clean(&path);
}

#[test]
fn a_due_anchored_series_is_unchanged_by_generalization() {
    // The explicit same-output pin: the default expansion IS the anchored
    // expansion over the positioning set, and pre-P11 (due-only) series come
    // out bit-identical.
    let (mut session, path) = boxed("gen_pin");
    series(&mut session, "standup", DateTime::date(2026, 7, 7), "every week");
    let store = session.store();
    let default = occurrences(store, DateTime::date(2026, 7, 1), DateTime::date(2026, 7, 31));
    let anchored = lotus_services::recurrence::occurrences_anchored(
        store,
        DateTime::date(2026, 7, 1),
        DateTime::date(2026, 7, 31),
        &lotus_services::calendar_set(store),
    );
    assert_eq!(default, anchored);
    assert_eq!(default.len(), 4);
    clean(&path);
}

#[test]
fn a_date_anchored_series_occurring_today_joins_today() {
    // §4.3, pinned as deliberate: a birthday (a date-anchored series)
    // appears in Today on its day — the calendar-lens behavior bp1 e21
    // describes. No pre-P11 data changes appearance (no `date` cells exist).
    let (mut session, path) = boxed("gen_today");
    let birthday = series_on(&mut session, "birthday", "date", DateTime::date(2026, 7, 7), "every week");
    let sections = today_sections(session.store(), DateTime::date(2026, 7, 14));
    assert!(sections.due.contains(&birthday), "the occurrence day joins Today");
    let off = today_sections(session.store(), DateTime::date(2026, 7, 15));
    assert!(!off.due.contains(&birthday), "an off day does not");
    clean(&path);
}
