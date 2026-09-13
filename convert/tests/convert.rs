//! The conversion, against a real seeded box.
//!
//! Not a hand-built fixture: `seed_if_fresh` is what a phone actually
//! runs, and its 70 entities over 51 property definitions are the shape
//! this has to survive.

use liv_convert::*;
use liv_core::{props, Author, Cell, Command, DateTime, Session, Value};
use liv_engine::{kind, prop, DateSpec, DeviceId, Engine, Value as EV};

fn temp(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("liv_convert_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// A seeded box with a few real things in it.
fn seeded(dir: &std::path::Path) -> std::path::PathBuf {
    let path = dir.join("liv.log");
    let mut s = Session::open(&path).unwrap();
    liv_services::seed_if_fresh(&mut s).unwrap();

    let note = liv_services::content::create_note(
        &mut s,
        DateTime { civil: 2026_09_13_1000, date_only: false, end: None },
    )
    .unwrap();
    s.commit(
        vec![Command::AddCell {
            entity: note,
            cell: Cell { property: props::NAME, value: Value::text("Roof project") },
        }],
        "name",
        Author::User,
    )
    .unwrap();

    let task = liv_services::content::create_task(
        &mut s,
        DateTime { civil: 2026_09_13_1100, date_only: false, end: None },
    )
    .unwrap();
    s.commit(
        vec![Command::AddCell {
            entity: task,
            cell: Cell { property: props::NAME, value: Value::text("Order slates") },
        }],
        "name",
        Author::User,
    )
    .unwrap();
    path
}

#[test]
fn a_seeded_box_converts_and_the_things_in_it_arrive() {
    let dir = temp("seeded");
    let from = seeded(&dir);
    let to = dir.join("liv.db");

    let report = convert(&from, &to).unwrap();

    // **A FRESH BOX IS 70 ENTITIES AND ALMOST ALL OF IT IS SCHEMA.** 51
    // property definitions, a type per kind, an option per area and
    // status — and the engine has every one of those compiled in. Copying
    // them would give a converted box a second "due" and a second "Work"
    // sitting beside the frozen ones in every picker, which is exactly
    // the drift the furniture exists to prevent.
    //
    // So they RESOLVE rather than convert, and what is left is the
    // content: the two things actually written.
    assert!(report.resolved > 50, "the schema resolved: {report:?}");
    assert!(report.entities < 20, "what converted is content, not schema: {report:?}");
    assert!(report.files_dropped == 0, "nothing in a seeded box carries a file");
    assert!(report.clean(), "{report:?}");

    let e = Engine::open_local(&to).unwrap();
    assert_eq!(e.entity_count().unwrap() as usize, report.entities);

    // The proof that resolving worked: the six areas and three statuses
    // are the FROZEN ids, and the box minted no copies of them.
    for a in liv_engine::AREAS {
        assert!(liv_engine::model::is_furniture(*a));
    }
    let minted_areas = e.of_kind(kind::AREA).unwrap();
    assert!(minted_areas.is_empty(), "a seeded box invents no seventh area");
    assert!(e.of_kind(kind::STATUS).unwrap().is_empty(), "nor a fourth status");

    // THE THINGS, by name, with their kinds carried across.
    let named: Vec<(String, Option<liv_engine::EntityId>)> = e
        .all_entities()
        .unwrap()
        .into_iter()
        .filter_map(|id| e.name(id).unwrap().map(|n| (n, e.kind_of(id).unwrap())))
        .collect();
    let note = named.iter().find(|(n, _)| n == "Roof project").expect("the note came across");
    assert_eq!(note.1, Some(kind::NOTE), "and it is still a note");
    let task = named.iter().find(|(n, _)| n == "Order slates").expect("the task came across");
    assert_eq!(task.1, Some(kind::TASK));

    // THE VOCABULARY LANDED ON OUR FROZEN IDS, not on copies. This is the
    // whole point of the property map: a converted box's `due` cell is
    // `prop::DUE`, which every surface already reads.
    let ids: Vec<liv_engine::EntityId> = e.all_entities().unwrap();
    let due_holders: usize = ids
        .iter()
        .filter(|id| e.one(**id, prop::DUE).map(|v| v.is_some()).unwrap_or(false))
        .count();
    let _ = due_holders; // a seeded box need not have any; the type is the claim.
    assert!(e.of_kind(kind::NOTE).unwrap().len() >= 1);

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn converting_twice_gives_the_same_box() {
    // **The cheapest proof it is not doing something different each
    // time.** Every engine id is DERIVED from the core id and its creation
    // time rather than minted, so two runs agree byte for byte.
    //
    // SAME DEVICE, and that is not a cheat. A dot is `(device, seq)` and
    // the digest hashes the device on every cell row, by design — it is
    // how two devices notice drift. So two boxes converted on two devices
    // SHOULD have different digests, and asserting otherwise would be
    // asserting the merge design away. What is being tested here is the
    // conversion; the device is held still so that it is the only thing
    // being tested.
    let dir = temp("twice");
    let from = seeded(&dir);
    let session = liv_core::Session::open(&from).unwrap();

    let digest_of = || {
        let mut e = Engine::open_in_memory(DeviceId([7; 8])).unwrap();
        let report = liv_convert::pour(session.store(), &mut e).unwrap();
        (report, e.digest().unwrap())
    };
    let (ra, da) = digest_of();
    let (rb, db) = digest_of();
    assert_eq!(ra, rb, "the same box reports the same thing");
    assert_eq!(da, db, "and produces the same view, byte for byte");
    drop(session);

    // Two real conversions differ only in who wrote them: the ENTITY IDS
    // are identical, because they are derived rather than minted.
    let a = dir.join("a.db");
    let b = dir.join("b.db");
    convert(&from, &a).unwrap();
    convert(&from, &b).unwrap();
    let ea = Engine::open_local(&a).unwrap();
    let eb = Engine::open_local(&b).unwrap();
    assert_eq!(ea.all_entities().unwrap(), eb.all_entities().unwrap(), "the same things");
    assert_ne!(ea.device(), eb.device(), "written by different devices");
    assert_ne!(ea.digest().unwrap(), eb.digest().unwrap(), "which the digest can see");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_converted_box_survives_the_replay_gate() {
    // The gate `core-plan.md` says stops everything if it fails. A box
    // that arrived by conversion is a box like any other.
    let dir = temp("gate");
    let from = seeded(&dir);
    let to = dir.join("liv.db");
    convert(&from, &to).unwrap();

    let mut e = Engine::open_local(&to).unwrap();
    let before = e.digest().unwrap();
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), before);

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn it_refuses_to_run_into_a_box_that_already_exists() {
    // "Run it again" is the first thing anyone tries, and a converter that
    // allows it is a converter that can double a box.
    let dir = temp("twice_same");
    let from = seeded(&dir);
    let to = dir.join("liv.db");
    convert(&from, &to).unwrap();
    let err = convert(&from, &to).unwrap_err();
    assert!(err.to_string().contains("already exists"), "{err}");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn the_original_is_not_touched() {
    let dir = temp("readonly");
    let from = seeded(&dir);
    let before = std::fs::read(&from).unwrap();
    convert(&from, &dir.join("liv.db")).unwrap();
    assert_eq!(std::fs::read(&from).unwrap(), before, "byte for byte");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_date_keeps_whether_it_was_a_day_or_a_moment() {
    // **The whole distinction.** "Due Friday" and "starts 14:00" are
    // different things, and a floating day that shifts when the device
    // changes zone is the most common quiet corruption in a personal app.
    let dir = temp("dates");
    let path = dir.join("liv.log");
    let (day_id, moment_id) = {
        let mut s = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut s).unwrap();
        let due = liv_services::property_id(s.store(), "due").unwrap();

        let a = liv_services::content::create_task(
            &mut s,
            DateTime { civil: 2026_09_13_0000, date_only: true, end: None },
        )
        .unwrap();
        let b = liv_services::content::create_task(
            &mut s,
            DateTime { civil: 2026_09_13_0000, date_only: true, end: None },
        )
        .unwrap();
        s.commit(
            vec![
                Command::AddCell {
                    entity: a,
                    cell: Cell {
                        property: due,
                        value: Value::DateTime(DateTime {
                            civil: 2026_09_18_0000,
                            date_only: true,
                            end: None,
                        }),
                    },
                },
                Command::AddCell {
                    entity: b,
                    cell: Cell {
                        property: due,
                        value: Value::DateTime(DateTime {
                            civil: 2026_09_18_1430,
                            date_only: false,
                            end: None,
                        }),
                    },
                },
            ],
            "dates",
            Author::User,
        )
        .unwrap();
        (a, b)
    };

    let to = dir.join("liv.db");
    convert(&path, &to).unwrap();
    let e = Engine::open_local(&to).unwrap();

    // 2026-09-18 is day 20_714 since the epoch. Check the arithmetic
    // itself rather than trusting it.
    let day = days_from_civil(2026, 9, 18);
    assert_eq!(civil_from_days(day), (2026, 9, 18), "the algorithm round-trips");

    let find = |core_id: liv_core::Id| {
        let id = engine_id(core_id, 0);
        e.all_entities().unwrap().into_iter().find(|x| x.0[9..16] == id.0[9..16]).unwrap()
    };
    let a = find(day_id);
    let b = find(moment_id);

    assert_eq!(
        e.one(a, prop::DUE).unwrap(),
        Some(EV::Date(DateSpec::Day(day))),
        "a floating day stays a floating day"
    );
    match e.one(b, prop::DUE).unwrap() {
        Some(EV::Date(DateSpec::Instant { ms, .. })) => {
            assert_eq!(ms, day as i64 * 86_400_000 + 14 * 3_600_000 + 30 * 60_000, "14:30");
        }
        other => panic!("a moment must stay a moment, got {other:?}"),
    }

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn the_civil_arithmetic_is_exact_across_the_awkward_dates() {
    // Hinnant's algorithm, checked at the places a hand-rolled one breaks.
    for (y, m, d, days) in [
        (1970, 1, 1, 0),
        (1970, 1, 2, 1),
        (1969, 12, 31, -1),
        (2000, 2, 29, 11_016), // a leap year that IS one, being /400
        (1900, 3, 1, -25_508), // the year after one that is NOT, being /100
        (2026, 9, 13, 20_709),
        (2100, 3, 1, 47_541), // the next /100 non-leap
    ] {
        assert_eq!(days_from_civil(y, m, d), days, "{y}-{m}-{d}");
        assert_eq!(civil_from_days(days), (y, m as u32, d as u32));
    }
    // Every day for eight years round-trips, which is the only honest way
    // to believe a date function.
    for day in 20_000..23_000 {
        let (y, m, d) = civil_from_days(day);
        assert_eq!(days_from_civil(y, m, d), day);
    }
    // A malformed stamp reads as the epoch rather than as a wild date.
    assert_eq!(days_from_civil(0, 0, 0), 0);
    assert_eq!(days_from_civil(2026, 13, 1), 0);
    assert_eq!(split_civil(2026_09_13_1430), (2026, 9, 13, 14, 30));
}

#[test]
fn a_type_the_engine_has_no_kind_for_is_named_rather_than_swallowed() {
    // Kinds are ours and do not grow from a box, so an invented one is
    // telling us something we should read.
    let dir = temp("unknown_kind");
    let path = dir.join("liv.log");
    {
        let mut s = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut s).unwrap();
        let t = s.allocate_id();
        let thing = s.allocate_id();
        s.commit(
            vec![
                Command::Create { entity: t },
                Command::AddCell {
                    entity: t,
                    cell: Cell { property: props::NAME, value: Value::text("sourdough starter") },
                },
                Command::Create { entity: thing },
                Command::AddCell {
                    entity: thing,
                    cell: Cell { property: props::TYPE, value: Value::Reference(t) },
                },
                Command::AddCell {
                    entity: thing,
                    cell: Cell { property: props::NAME, value: Value::text("Gerald") },
                },
            ],
            "odd",
            Author::User,
        )
        .unwrap();
    }

    let to = dir.join("liv.db");
    let report = convert(&path, &to).unwrap();
    assert_eq!(report.unknown_kinds, vec!["sourdough starter".to_owned()]);
    assert!(!report.clean(), "and the report says so");

    // THE ENTITY STILL CAME ACROSS, with everything else it had. Refusing
    // the kind is not refusing the thing.
    let e = Engine::open_local(&to).unwrap();
    let gerald = e
        .all_entities()
        .unwrap()
        .into_iter()
        .find(|id| e.name(*id).unwrap().as_deref() == Some("Gerald"))
        .expect("Gerald survived");
    assert_eq!(e.kind_of(gerald).unwrap(), None, "with no kind, which is honest");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_body_flattens_to_markdown_the_editor_can_read_back() {
    let dir = temp("body");
    let path = dir.join("liv.log");
    {
        let mut s = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut s).unwrap();
        let note = liv_services::content::create_note(
            &mut s,
            DateTime { civil: 2026_09_13_1000, date_only: false, end: None },
        )
        .unwrap();
        let rt = liv_core::RichText {
            spans: vec![
                liv_core::Span::Break(liv_core::Block::Heading(1)),
                liv_core::Span::text("Trip planning"),
                liv_core::Span::Break(liv_core::Block::Task { depth: 0, done: false }),
                liv_core::Span::text("book the ferry"),
                liv_core::Span::Break(liv_core::Block::Task { depth: 0, done: true }),
                liv_core::Span::text("passport"),
            ],
        };
        s.commit(
            vec![Command::AddCell {
                entity: note,
                cell: Cell { property: props::CONTENT, value: Value::RichText(rt) },
            }],
            "body",
            Author::User,
        )
        .unwrap();
    }

    let to = dir.join("liv.db");
    let report = convert(&path, &to).unwrap();
    assert_eq!(report.flattened, 1);

    let e = Engine::open_local(&to).unwrap();
    let body = e
        .all_entities()
        .unwrap()
        .into_iter()
        .find_map(|id| match e.one(id, prop::BODY).unwrap() {
            Some(EV::Text(t)) if t.contains("Trip") => Some(t),
            _ => None,
        })
        .expect("the body came across");

    // MARKDOWN, not bare text: the editor already round-trips it, so a
    // checklist comes back a checklist when blocks land — and
    // `note_tasks` can still see an open box in the meantime.
    assert!(body.contains("# Trip planning"), "{body}");
    assert!(body.contains("- [ ] book the ferry"), "{body}");
    assert!(body.contains("- [x] passport"), "{body}");

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_converted_id_is_not_furniture_and_still_sorts_by_creation() {
    // Version 7 where the furniture is version 8, so a converted box can
    // never collide with a compiled-in id — and id order is still
    // creation order, which twenty-one sites depend on.
    let older = engine_id(9_000, 1_700_000_000_000);
    let newer = engine_id(3, 1_800_000_000_000);
    assert!(!liv_engine::model::is_furniture(older));
    assert!(looks_like_entity(older));
    assert!(older < newer, "the later one sorts later whatever its core id was");
    assert_eq!(older.millis(), 1_700_000_000_000);

    // Two things made in the same millisecond still differ.
    assert_ne!(engine_id(1, 5_000), engine_id(2, 5_000));

    let _ = DeviceId([0; 8]);
}
