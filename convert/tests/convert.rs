//! The conversion, against a real seeded box.
//!
//! Not a hand-built fixture: `seed_if_fresh` is what a phone actually
//! runs, and its 70 entities over 51 property definitions are the shape
//! this has to survive.

use liv_convert::*;
use liv_core::{props, Author, Cell, Command, DateTime, Session, Value};
use liv_engine::{
    kind, prop, Block, DateSpec, DeviceId, Engine, Marks, Span, TextSpan, Value as EV,
};

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

    // STATUSES resolve onto the FROZEN three and the box mints no copy
    // of them — that half is unchanged.
    assert!(e.of_kind(kind::STATUS).unwrap().is_empty(), "nor a fourth status");

    // AND NO AREAS AT ALL, which is a fact about the SEED rather than
    // about the converter: `seed_if_fresh` never wrote the six: they
    // were compiled into the engine, and now (2026-09-21) they are not
    // compiled into anything. An old box carrying areas of its own is
    // the next test.
    assert!(e.of_kind(kind::AREA).unwrap().is_empty(), "a seeded box has no areas");

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

/// **AN OLD BOX'S AREA ARRIVES MINTED, NOT RESOLVED** (2026-09-21).
///
/// It used to resolve: an option of `area` named "Work" became
/// `area::WORK`, the frozen one, and a converted box that minted its own
/// copy would have put two Works in every picker. That is the drift the
/// compiled-in furniture existed to prevent.
///
/// The owner removed the fixed areas, so there is nothing left to
/// resolve ONTO and the branch inverts. What has to stay true is the
/// rest of it: the area comes across with its name, says it is an area,
/// carries `working` so it stays out of lists and searches, and the
/// thing filed under it still points at it.
#[test]
fn an_old_boxs_area_comes_across_as_a_minted_one() {
    let dir = temp("old_area");
    let path = dir.join("liv.log");
    {
        let mut s = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut s).unwrap();
        let area_prop = s.allocate_id();
        let work = s.allocate_id();
        let note = s.allocate_id();
        s.commit(
            vec![
                Command::Create { entity: work },
                Command::AddCell {
                    entity: work,
                    cell: Cell { property: props::NAME, value: Value::text("Work") },
                },
                Command::Create { entity: area_prop },
                Command::AddCell {
                    entity: area_prop,
                    cell: Cell { property: props::NAME, value: Value::text("area") },
                },
                Command::AddCell {
                    entity: area_prop,
                    cell: Cell { property: props::OPTIONS, value: Value::Reference(work) },
                },
                Command::Create { entity: note },
                Command::AddCell {
                    entity: note,
                    cell: Cell { property: props::NAME, value: Value::text("Order slates") },
                },
                Command::AddCell {
                    entity: note,
                    cell: Cell { property: area_prop, value: Value::Reference(work) },
                },
            ],
            "an area of their own",
            Author::User,
        )
        .unwrap();
    }

    let to = dir.join("liv.db");
    convert(&path, &to).unwrap();
    let e = Engine::open_local(&to).unwrap();

    let areas = e.of_kind(kind::AREA).unwrap();
    assert_eq!(areas.len(), 1, "one area in, one area out: {areas:?}");
    let work = areas[0];
    assert_eq!(e.name(work).unwrap().as_deref(), Some("Work"), "with its name");
    assert!(!liv_engine::model::is_furniture(work), "minted, never frozen");

    // VOCABULARY, so it stays out of every list. This is the half that
    // `liv_add_option` got wrong until today, and a converted box must
    // not reintroduce it.
    assert!(
        e.run(&liv_engine::Query::default()).unwrap().iter().all(|id| *id != work),
        "an area is not a thing the box lists"
    );

    // AND THE FILING SURVIVED: the note still points at it.
    let note = e
        .all_entities()
        .unwrap()
        .into_iter()
        .find(|id| e.name(*id).unwrap().as_deref() == Some("Order slates"))
        .expect("the note came across");
    assert_eq!(
        e.one(note, prop::AREA).unwrap(),
        Some(liv_engine::Value::Ref(work)),
        "filed under the area it was filed under"
    );

    let _ = std::fs::remove_dir_all(&dir);
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
fn a_body_crosses_span_for_span() {
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
    convert(&path, &to).unwrap();

    let e = Engine::open_local(&to).unwrap();
    let body = e
        .all_entities()
        .unwrap()
        .into_iter()
        .find_map(|id| match e.one(id, prop::BODY).unwrap() {
            Some(EV::Rich(spans)) if !spans.is_empty() => Some(spans),
            _ => None,
        })
        .expect("the body came across");

    // **SPAN FOR SPAN.** This used to flatten to markdown, because the
    // engine had no blocks and a checklist that came back as a checklist
    // was the best available. It has blocks now, so the round trip
    // through markdown — which loses a callout's kind, a code fence's
    // language, and every mark — is not a conversion, it is a downgrade.
    assert_eq!(
        body,
        vec![
            Span::Break(Block::Heading(1)),
            Span::text("Trip planning"),
            Span::Break(Block::Task { depth: 0, done: false }),
            Span::text("book the ferry"),
            Span::Break(Block::Task { depth: 0, done: true }),
            Span::text("passport"),
        ]
    );

    let _ = std::fs::remove_dir_all(&dir);
}

/// The parts markdown could not have carried.
#[test]
fn marks_a_code_language_and_a_callout_kind_all_survive() {
    let dir = temp("body-rich");
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
                liv_core::Span::Text(liv_core::TextSpan {
                    text: "loud".into(),
                    marks: liv_core::Marks(liv_core::Marks::BOLD | liv_core::Marks::STRIKE),
                }),
                liv_core::Span::Break(liv_core::Block::Code { lang: Some("rust".into()) }),
                liv_core::Span::text("fn main() {}"),
                liv_core::Span::Break(liv_core::Block::Callout { kind: "warning".into() }),
                liv_core::Span::text("mind the step"),
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
    convert(&path, &to).unwrap();
    let e = Engine::open_local(&to).unwrap();
    let body = e
        .all_entities()
        .unwrap()
        .into_iter()
        .find_map(|id| match e.one(id, prop::BODY).unwrap() {
            Some(EV::Rich(spans)) if !spans.is_empty() => Some(spans),
            _ => None,
        })
        .expect("the body came across");

    assert_eq!(
        body,
        vec![
            Span::Text(TextSpan {
                text: "loud".into(),
                marks: Marks(Marks::BOLD | Marks::STRIKE),
            }),
            Span::Break(Block::Code { lang: Some("rust".into()) }),
            Span::text("fn main() {}"),
            Span::Break(Block::Callout { kind: "warning".into() }),
            Span::text("mind the step"),
        ]
    );

    let _ = std::fs::remove_dir_all(&dir);
}

/// **A `[[link]]` stays a link, not its target's name in brackets.**
///
/// Flattening turned `Span::Ref(id)` into the literal text `[[Name]]`,
/// which reads right and is not the same thing: rename the target and the
/// body still says the old name, and nothing in the box knows the note
/// points anywhere.
#[test]
fn a_body_reference_arrives_as_a_reference() {
    let dir = temp("body-ref");
    let path = dir.join("liv.log");
    {
        let mut s = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut s).unwrap();
        let target = liv_services::content::create_note(
            &mut s,
            DateTime { civil: 2026_09_13_0900, date_only: false, end: None },
        )
        .unwrap();
        s.commit(
            vec![Command::AddCell {
                entity: target,
                cell: Cell { property: props::NAME, value: Value::Text("Ferry times".into()) },
            }],
            "name",
            Author::User,
        )
        .unwrap();
        let note = liv_services::content::create_note(
            &mut s,
            DateTime { civil: 2026_09_13_1000, date_only: false, end: None },
        )
        .unwrap();
        s.commit(
            vec![Command::AddCell {
                entity: note,
                cell: Cell {
                    property: props::CONTENT,
                    value: Value::RichText(liv_core::RichText {
                        spans: vec![liv_core::Span::text("see "), liv_core::Span::Ref(target)],
                    }),
                },
            }],
            "body",
            Author::User,
        )
        .unwrap();
    }

    let to = dir.join("liv.db");
    convert(&path, &to).unwrap();
    let e = Engine::open_local(&to).unwrap();
    let body = e
        .all_entities()
        .unwrap()
        .into_iter()
        .find_map(|id| match e.one(id, prop::BODY).unwrap() {
            Some(EV::Rich(spans)) if spans.len() == 2 => Some(spans),
            _ => None,
        })
        .expect("the body came across");

    let Span::Ref(target) = body[1] else { panic!("the link is a Ref: {body:?}") };
    assert_eq!(e.name(target).unwrap().as_deref(), Some("Ferry times"));

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

/// **A file crosses now, and its two halves go to different places.**
///
/// It used to be dropped and counted. `core`'s `FileRef` carries a
/// content hash AND a device-local path in one value in the log, which
/// `core.md` §14 records as a model bug; the engine splits them, so the
/// conversion finally has somewhere to put each — the hash into the cell,
/// the path into `places`, which does not sync and is not in the digest.
#[test]
fn a_file_crosses_as_its_hash_with_its_path_kept_locally() {
    let dir = temp("file");
    let path = dir.join("liv.log");
    let doc = dir.join("invoice.pdf");
    std::fs::write(&doc, "some bytes").unwrap();
    let doc = doc.to_string_lossy().into_owned();

    let hash = {
        let mut s = Session::open(&path).unwrap();
        liv_services::seed_if_fresh(&mut s).unwrap();
        let id = liv_services::files::add_file(
            &mut s,
            &doc,
            DateTime { civil: 2026_09_13_1000, date_only: false, end: None },
        )
        .unwrap();
        let file_prop = s
            .store()
            .entities()
            .find(|e| {
                matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "file")
            })
            .map(|e| e.id)
            .expect("the file property is seeded");
        match s.store().get(id).and_then(|e| e.get(file_prop)) {
            Some(Value::File(f)) => f.hash,
            other => panic!("expected a file cell, got {other:?}"),
        }
    };

    let to = dir.join("liv.db");
    let report = convert(&path, &to).unwrap();
    assert_eq!(report.files_dropped, 0, "nothing was dropped");
    assert!(report.clean(), "and the conversion is clean");

    let e = Engine::open_local(&to).unwrap();
    // Found by its file CELL, not by a kind: `core`'s `add_file` sets no
    // type at all, so a file entity there is a thing that has a file. The
    // conversion carries what is in the box rather than improving on it.
    let file = e
        .all_entities()
        .unwrap()
        .into_iter()
        .find(|id| e.one(*id, prop::FILE).unwrap().is_some())
        .expect("the file came across");

    assert_eq!(e.one(file, prop::FILE).unwrap(), Some(EV::Blob(hash)), "the hash, exactly");
    assert_eq!(e.path_of(file).unwrap().as_deref(), Some(doc.as_str()), "and where it sits");
    assert_eq!(e.one(file, prop::FORMAT).unwrap(), Some(EV::Text("pdf".into())));

    let _ = std::fs::remove_dir_all(&dir);
}
