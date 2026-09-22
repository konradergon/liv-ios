//! Cost, not just correctness — standing rule 2.
//!
//! Anything on the write path ships with a test that asserts the SHAPE:
//! doubling the box must not much more than double the work. A ratio
//! survives a slow machine and a debug build where a millisecond budget
//! does not.
//!
//! This rule exists because the tree it was written for has produced the
//! same defect four times: the file projection scanned per entity, the
//! clerk sweep walked the box per write, `find_type` ran a full query per
//! creation, and search rebuilt its corpus per keystroke. All four are
//! *rebuild on read instead of maintain on write*, and none were caught by
//! a correctness test.
//!
//! Both boxes are built once and then measured in interleaved rounds, and
//! the reported ratio is the best round — so one scheduler hiccup has to
//! land in the same place every round to be seen.

use liv_engine::*;
use std::time::{Duration, Instant};

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const NAME: EntityId = EntityId([0xf1; 16]);

fn time(mut work: impl FnMut()) -> Duration {
    let start = Instant::now();
    work();
    start.elapsed()
}

fn best_ratio(
    rounds: usize,
    mut small: impl FnMut() -> Duration,
    mut large: impl FnMut() -> Duration,
) -> f64 {
    (0..rounds)
        .map(|_| {
            let s = time(|| {
                small();
            });
            let l = time(|| {
                large();
            });
            l.as_secs_f64() / s.as_secs_f64().max(1e-9)
        })
        .fold(f64::INFINITY, f64::min)
}

/// A box holding `n` entities, each with a name.
fn box_of(n: u64) -> Engine {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    for i in 0..n {
        let id = e.mint(1_787_391_635_000 + i);
        e.commit(
            vec![
                Op::CreateEntity { entity: id },
                Op::SetCell {
                    entity: id,
                    prop: NAME,
                    value: Value::Text(format!("note {i} about invoices")),
                    replaces: vec![],
                },
            ],
            1,
            Author::User,
            1_787_391_635_000 + i,
        )
        .unwrap();
    }
    e
}

#[test]
fn one_write_stays_flat_as_the_box_grows() {
    let mut small = box_of(500);
    let mut large = box_of(5_000);

    let write = |e: &mut Engine, at: u64| {
        let id = e.mint(at);
        e.commit(
            vec![
                Op::CreateEntity { entity: id },
                Op::SetCell {
                    entity: id,
                    prop: NAME,
                    value: Value::Text("one more".into()),
                    replaces: vec![],
                },
            ],
            1,
            Author::User,
            at,
        )
        .unwrap();
    };

    // Not `best_ratio`: a write mutates, so the two sides cannot be
    // re-run against the same state. Fifty writes each, timed in one go.
    let mut at = 2_000_000_000_000u64;
    let s = time(|| {
        for _ in 0..50 {
            write(&mut small, at);
            at += 1;
        }
    });
    let l = time(|| {
        for _ in 0..50 {
            write(&mut large, at);
            at += 1;
        }
    });
    let ratio = l.as_secs_f64() / s.as_secs_f64().max(1e-9);

    // Ten times the box. A write that scans is ~10x; a write that does
    // not is ~1x. 3.0 leaves room for B-tree depth and page cache without
    // letting a scan back in.
    assert!(
        ratio < 3.0,
        "ten times the box multiplied one write by {ratio:.2}x; \
         something on the write path is looking at the whole box"
    );
}

#[test]
fn replay_stays_linear_in_the_log() {
    // Replay is O(history) by definition — that is the point of it. What
    // must NOT happen is O(history x box): a fold that re-reads the view
    // per op would make the rebuild button unusable exactly when it is
    // needed, on the largest box.
    let mut small = box_of(500);
    let mut large = box_of(5_000);

    let ratio = best_ratio(
        3,
        || time(|| small.replay().unwrap()),
        || time(|| large.replay().unwrap()),
    );

    assert!(
        ratio < 22.0,
        "ten times the log multiplied replay by {ratio:.2}x; \
         the fold is doing more than linear work per op"
    );
}

#[test]
fn reading_one_cell_does_not_scan_the_box() {
    let small = box_of(500);
    let large = box_of(5_000);

    // The same question of each: one property on one entity.
    let first = |e: &Engine| e.groups().unwrap()[0].ops[0].entity();
    let (a, b) = (first(&small), first(&large));

    let ratio = best_ratio(
        5,
        || time(|| {
            small.cell(a, NAME).unwrap();
        }),
        || time(|| {
            large.cell(b, NAME).unwrap();
        }),
    );

    assert!(
        ratio < 2.5,
        "ten times the box multiplied a single-cell read by {ratio:.2}x; \
         the index is not being used"
    );
}

// ---- the reads a surface makes ----------------------------------------
//
// **The claim these exist to hold down.** The core answers every question
// by handing the shell the whole box: 3.5 MB and 39 ms at 6,400 notes on
// every refresh, whatever is on screen. The engine's promise is that a
// question costs what its ANSWER costs. That is a SHAPE claim, so it is
// tested as one — and it is exactly the shape a missing index destroys
// without any answer being wrong.

/// A box of `n` tasks, a tenth of them due inside one week.
///
/// The week is a fixed slice of the calendar, so it holds a tenth of the
/// small box and a tenth of the large one — which is the point: the
/// ANSWER grows with the box here, and the next test is the one where it
/// does not.
fn dated_box(n: u64) -> Engine {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    for i in 0..n {
        let id = e.create(kind::TASK, Some(&format!("task {i}")), 1_787_391_635_000 + i).unwrap();
        // Spread over ten days; day 20_000 + (i % 10).
        e.set(id, prop::DUE, Value::Date(DateSpec::Day(20_000 + (i % 10) as i32)), 1_787_391_635_000 + i)
            .unwrap();
    }
    e
}

#[test]
fn a_window_query_costs_its_answer_not_the_box() {
    // ONE DAY out of ten, in a box and in a box ten times bigger. The
    // answer is ten times bigger too, so the honest expectation is
    // roughly ten — what this refuses is the shape where the query scans
    // every dated cell and the ratio tracks the BOX instead.
    let small = dated_box(500);
    let large = dated_box(5_000);
    let day = 20_003i64 * 86_400_000;

    let ratio = best_ratio(
        7,
        || time(|| {
            std::hint::black_box(small.in_window(prop::DUE, day, day).unwrap().len());
        }),
        || time(|| {
            std::hint::black_box(large.in_window(prop::DUE, day, day).unwrap().len());
        }),
    );

    // Sanity: the answers really are 50 and 500.
    assert_eq!(small.in_window(prop::DUE, day, day).unwrap().len(), 50);
    assert_eq!(large.in_window(prop::DUE, day, day).unwrap().len(), 500);
    assert!(ratio < 25.0, "ten times the answer should not cost much more than ten times: {ratio:.1}x");
}

#[test]
fn an_empty_window_is_flat_however_big_the_box_is() {
    // THE TEST THAT ACTUALLY CATCHES A MISSING INDEX. Above, the answer
    // grows with the box, so a scan and a seek both look linear. Here the
    // answer is EMPTY in both boxes — a seek is flat and a scan is not,
    // and nothing about correctness can tell them apart.
    let small = dated_box(500);
    let large = dated_box(5_000);
    let nowhere = 30_000i64 * 86_400_000;

    let ratio = best_ratio(
        7,
        || time(|| {
            std::hint::black_box(small.in_window(prop::DUE, nowhere, nowhere).unwrap().len());
        }),
        || time(|| {
            std::hint::black_box(large.in_window(prop::DUE, nowhere, nowhere).unwrap().len());
        }),
    );

    assert!(small.in_window(prop::DUE, nowhere, nowhere).unwrap().is_empty());
    assert!(large.in_window(prop::DUE, nowhere, nowhere).unwrap().is_empty());
    assert!(ratio < 4.0, "an empty answer must not cost more in a bigger box: {ratio:.1}x");
}

#[test]
fn one_entitys_cells_cost_the_same_in_any_size_of_box() {
    // The N+1 shape that made the core's file projection quadratic was a
    // loop over entities each asking for one cell. `cells_of` is the
    // answer, and it is only an answer if it is flat.
    let small = dated_box(500);
    let large = dated_box(5_000);
    let one_small = small.all_entities().unwrap()[10];
    let one_large = large.all_entities().unwrap()[10];

    let ratio = best_ratio(
        7,
        || time(|| {
            std::hint::black_box(small.cells_of(one_small).unwrap().len());
        }),
        || time(|| {
            std::hint::black_box(large.cells_of(one_large).unwrap().len());
        }),
    );
    assert_eq!(small.cells_of(one_small).unwrap().len(), 3, "kind, name, due");
    assert!(ratio < 4.0, "reading one entity must not notice the box: {ratio:.1}x");
}

#[test]
fn a_write_still_stays_flat_now_that_the_fold_maintains_at_ms() {
    // `at_ms` is maintained ON WRITE (standing rule 2's whole point), so
    // the write path is the one that could have paid for it. Dated boxes
    // rather than the plain ones above, because an undated write would
    // never touch the new column and would prove nothing.
    let mut small = dated_box(500);
    let mut large = dated_box(5_000);

    let write = |e: &mut Engine, at: u64| {
        let id = e.create(kind::TASK, Some("one more"), at).unwrap();
        e.set(id, prop::DUE, Value::Date(DateSpec::Day(20_005)), at).unwrap();
    };

    // Separate counters: each closure needs its own, or they would both
    // borrow one and neither could run.
    let mut ns = 0u64;
    let mut nl = 0u64;
    let ratio = best_ratio(
        7,
        || {
            ns += 1;
            time(|| write(&mut small, 1_800_000_000_000 + ns))
        },
        || {
            nl += 1;
            time(|| write(&mut large, 1_900_000_000_000 + nl))
        },
    );
    assert!(ratio < 4.0, "one dated write must not notice the box: {ratio:.1}x");
}

// ---- undo ------------------------------------------------------------
//
// `undo.rs` claims its cost is the depth the user has undone to, never the
// size of the box — which is the whole reason there is no undo stack held
// beside the log. That is a claim about SHAPE, so it is asserted here
// rather than believed.

/// **The question "can I undo?" must not read the history.**
///
/// This is the one that would rot quietly: `undoable()` is what decides
/// whether a button is live, so a shell asks it on every refresh. `core/`
/// answers it from a `Vec` in memory it built by scanning the whole log at
/// open. Here it walks backward and stops at the first group still in
/// effect — which, in a box nobody has undone in, is the first row read.
#[test]
fn asking_what_undo_would_take_does_not_read_the_box() {
    let small = box_of(500);
    let large = box_of(5_000);

    let ratio = best_ratio(
        12,
        || time(|| assert!(small.undoable().unwrap().is_some())),
        || time(|| assert!(large.undoable().unwrap().is_some())),
    );
    assert!(ratio < 4.0, "the undo question must not notice the box: {ratio:.1}x");
}

/// And taking it costs one group's inverse, not the log's.
#[test]
fn one_undo_stays_flat_as_the_box_grows() {
    let mut small = box_of(500);
    let mut large = box_of(5_000);

    let ratio = best_ratio(
        12,
        || time(|| { small.undo(1_787_400_000_000).unwrap(); }),
        || time(|| { large.undo(1_787_400_000_000).unwrap(); }),
    );
    assert!(ratio < 4.0, "one undo must not notice the box: {ratio:.1}x");
}

/// **Undoing ten deep costs the ten, and still not the box.**
///
/// The backward walk is bounded by the run of reversals at the tail, so a
/// box with ten undos already standing pays for those ten wherever it is.
/// If the walk ever started loading history to find its place, this is
/// where it would show.
#[test]
fn undoing_deep_costs_the_depth_not_the_box() {
    let mut small = box_of(500);
    let mut large = box_of(5_000);
    for i in 0..10 {
        small.undo(1_787_400_000_000 + i).unwrap();
        large.undo(1_787_400_000_000 + i).unwrap();
    }

    let ratio = best_ratio(
        12,
        || time(|| assert!(small.undoable().unwrap().is_some())),
        || time(|| assert!(large.undoable().unwrap().is_some())),
    );
    assert!(ratio < 4.0, "ten deep is ten deep in either box: {ratio:.1}x");
}

// ---- content ----------------------------------------------------------

/// **Saving a body must not notice the box**, and the compare-and-swap is
/// the part that could make it: reading the current value to fingerprint
/// it is a read on the write path, which is exactly the shape standing
/// rule 2 exists to catch. `core/` re-serialised the whole value on every
/// save AND walked the store to validate each link.
#[test]
fn one_save_stays_flat_as_the_box_grows() {
    let mut small = box_of(500);
    let mut large = box_of(5_000);
    let one_small = small.all_entities().unwrap()[0];
    let one_large = large.all_entities().unwrap()[0];

    // A different body each round: the no-op rule would otherwise make
    // every save after the first commit nothing, and this would time the
    // early return instead of a write.
    let n = std::cell::Cell::new(0u64);
    let ratio = best_ratio(
        12,
        || {
            n.set(n.get() + 1);
            let base = small.content(one_small).unwrap().1;
            let spans = vec![Span::text(format!("draft {}", n.get()))];
            time(|| {
                small.set_content(one_small, spans.clone(), base, 1_787_400_000_000).unwrap();
            })
        },
        || {
            let base = large.content(one_large).unwrap().1;
            let spans = vec![Span::text(format!("draft {}", n.get()))];
            time(|| {
                large.set_content(one_large, spans.clone(), base, 1_787_400_000_000).unwrap();
            })
        },
    );
    assert!(ratio < 4.0, "one save must not notice the box: {ratio:.1}x");
}

/// And a body full of links costs its links, not the box.
///
/// Every `[[…]]` is checked against the box before the save lands — a
/// reference to nothing is not content — so this is the loop that would
/// quietly become "per link, scan everything".
#[test]
fn checking_a_bodys_links_costs_the_links_not_the_box() {
    let mut small = box_of(500);
    let mut large = box_of(5_000);
    let linky = |e: &Engine| -> Vec<Span> {
        e.all_entities().unwrap().into_iter().take(20).map(Span::Ref).collect()
    };
    let small_spans = linky(&small);
    let large_spans = linky(&large);
    let one_small = small.all_entities().unwrap()[0];
    let one_large = large.all_entities().unwrap()[0];

    // **A DIFFERENT body every round**, and the first version of this
    // test did not do that. The no-op rule returns before the link check
    // — `set_content` reads the current value, compares, and leaves — so
    // saving the same twenty links twelve times measured the early
    // return eleven times out of twelve. `best_ratio` takes the best
    // round, so it measured nothing at all, and stayed green with the
    // check replaced by a full scan of the box.
    let n = std::cell::Cell::new(0u64);
    let t = 1_787_400_000_000u64;
    let with = |links: &[Span], n: u64| {
        let mut v = vec![Span::text(format!("draft {n}"))];
        v.extend_from_slice(links);
        v
    };
    let ratio = best_ratio(
        12,
        || {
            n.set(n.get() + 1);
            let base = small.content(one_small).unwrap().1;
            let spans = with(&small_spans, n.get());
            time(|| {
                small.set_content(one_small, spans.clone(), base, t).unwrap();
            })
        },
        || {
            let base = large.content(one_large).unwrap().1;
            let spans = with(&large_spans, n.get());
            time(|| {
                large.set_content(one_large, spans.clone(), base, t).unwrap();
            })
        },
    );
    assert!(ratio < 4.0, "twenty links is twenty links in either box: {ratio:.1}x");
}

// ---- history and links ------------------------------------------------
//
// Both of these are questions `core/` answers by scanning — history walks
// every transaction in the box, backlinks decode every content cell. They
// are the fifth and sixth instance of the defect in this file's header,
// and the fold maintains a table for each so they are seeks.

fn box_of_notes_with_bodies(n: u64) -> (Engine, EntityId, EntityId) {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let hub = e.create(kind::NOTE, Some("Hub"), 1_787_391_635_000).unwrap();
    let mut first = None;
    for i in 0..n {
        let t = 1_787_391_635_000 + i;
        let id = e.create(kind::NOTE, Some(&format!("note {i}")), t).unwrap();
        // Every note points at the hub, so `links_to(hub)` has an answer
        // proportional to the box while `links_to(a leaf)` has none —
        // which is the pair that tells a seek from a scan.
        e.set_content(id, vec![Span::text("see "), Span::Ref(hub)], 0, t).unwrap();
        first.get_or_insert(id);
    }
    let one = first.unwrap();
    (e, hub, one)
}

/// **What points HERE, when the answer is nothing.**
///
/// The honest shape: a note nobody links to costs the same in a box of 500
/// and a box of 5,000. A scan would cost the box, and a correctness test
/// cannot tell the two apart — both answer "nothing".
#[test]
fn asking_what_links_here_is_flat_when_nothing_does() {
    let (small, _, leaf_small) = box_of_notes_with_bodies(500);
    let (large, _, leaf_large) = box_of_notes_with_bodies(5_000);

    let ratio = best_ratio(
        12,
        || time(|| assert!(small.links_to(leaf_small).unwrap().is_empty())),
        || time(|| assert!(large.links_to(leaf_large).unwrap().is_empty())),
    );
    assert!(ratio < 4.0, "an empty backlink answer must not cost the box: {ratio:.1}x");
}

/// And one note's history costs its own edits, not the box's.
#[test]
fn one_notes_history_costs_its_edits_not_the_box() {
    let (mut small, _, one_small) = box_of_notes_with_bodies(500);
    let (mut large, _, one_large) = box_of_notes_with_bodies(5_000);
    // Ten versions each, so both answers are the same size.
    for i in 0..10u64 {
        let b = small.content(one_small).unwrap().1;
        small.set_content(one_small, vec![Span::text(format!("v{i}"))], b, 1_787_400_000_000 + i).unwrap();
        let b = large.content(one_large).unwrap().1;
        large.set_content(one_large, vec![Span::text(format!("v{i}"))], b, 1_787_400_000_000 + i).unwrap();
    }

    let ratio = best_ratio(
        12,
        || time(|| assert_eq!(small.content_history(one_small).unwrap().len(), 11)),
        || time(|| assert_eq!(large.content_history(one_large).unwrap().len(), 11)),
    );
    assert!(ratio < 4.0, "eleven versions is eleven versions in either box: {ratio:.1}x");
}

// ---- rename -----------------------------------------------------------

/// **Renaming a value costs its carriers, not the box.**
///
/// `core/`'s text branch walks every user entity to find them. Here the
/// carriers come off `cells_by_value`, which is the index that exists so
/// that "everything with Anna" is a join rather than a search.
#[test]
fn renaming_a_text_value_costs_its_carriers_not_the_box() {
    let mut small = box_of(500);
    let mut large = box_of(5_000);

    // A DECLARED field, because `rename_value` asks what the property
    // holds and refuses rather than guessing for one the box has never
    // heard of. Three carriers each, whatever else is in the box.
    let carriers = |e: &mut Engine, t: u64| -> EntityId {
        let field = e.declare_field("client", "text", false, t).unwrap();
        for (i, id) in e.all_entities().unwrap().into_iter().take(3).enumerate() {
            e.set(id, field, Value::Text("Acme".into()), t + i as u64).unwrap();
        }
        field
    };
    let small_field = carriers(&mut small, 2_000);
    let large_field = carriers(&mut large, 3_000);

    let n = std::cell::Cell::new(0u64);
    let ratio = best_ratio(
        12,
        || {
            n.set(n.get() + 1);
            let (from, to) = (names(n.get() - 1), names(n.get()));
            time(|| {
                small.rename_value(small_field, &from, &to, 1_787_400_000_000).unwrap();
            })
        },
        || {
            let (from, to) = (names(n.get() - 1), names(n.get()));
            time(|| {
                large.rename_value(large_field, &from, &to, 1_787_400_000_000).unwrap();
            })
        },
    );
    assert!(ratio < 4.0, "three carriers is three carriers in either box: {ratio:.1}x");
}

/// The rename chain's nth name. Round 0 is what the carriers start as.
fn names(n: u64) -> String {
    if n == 0 {
        "Acme".to_owned()
    } else {
        format!("Acme {n}")
    }
}

// ---- running a query --------------------------------------------------

/// **`core/`'s `run` says it in a comment**: *"A linear scan — the simplest
/// thing; an index earns its place when a measurement demands it."* The
/// measurement demanded it. That scan is what made a snapshot cost the box
/// rather than the screen, and this is the test that keeps it paid for.
#[test]
fn a_query_with_an_equals_costs_its_answer_not_the_box() {
    let mut small = box_of(500);
    let mut large = box_of(5_000);
    // Ten matches in each box, so both answers are the same size.
    //
    // The area is MINTED, not compiled in — so each box gets its own
    // "Work" with its own id, and each side of the ratio is asked about
    // the id its own box holds. The carriers are chosen BEFORE the mint
    // so that "the first ten entities" still means ten notes, not nine
    // and an area. `declare` (never `create`) keeps the area `working`,
    // which is what stops `run` from counting it as an eleventh match.
    let mut works: Vec<EntityId> = Vec::new();
    for (e, t) in [(&mut small, 2_000u64), (&mut large, 3_000u64)] {
        let carriers: Vec<EntityId> = e.all_entities().unwrap().into_iter().take(10).collect();
        let work = e.declare(kind::AREA, "Work", t).unwrap();
        for (i, id) in carriers.into_iter().enumerate() {
            e.set(id, prop::AREA, Value::Ref(work), t + i as u64).unwrap();
        }
        works.push(work);
    }
    let asking_for = |work: EntityId| Query {
        constraints: vec![Constraint {
            property: prop::AREA,
            op: QueryOp::Equals(Value::Ref(work)),
        }],
        ..Default::default()
    };
    let (small_work, large_work) = (asking_for(works[0]), asking_for(works[1]));

    let ratio = best_ratio(
        12,
        || time(|| assert_eq!(small.run(&small_work).unwrap().len(), 10)),
        || time(|| assert_eq!(large.run(&large_work).unwrap().len(), 10)),
    );
    assert!(ratio < 4.0, "ten matches is ten matches in either box: {ratio:.1}x");
}

/// And a query with NO equality is honestly linear — the one case that
/// still reads everything, stated rather than hidden.
#[test]
fn a_query_with_nothing_to_seek_on_is_linear_and_says_so() {
    let small = box_of(500);
    let large = box_of(5_000);
    let anything = Query {
        constraints: vec![Constraint { property: prop::AREA, op: QueryOp::Missing }],
        ..Default::default()
    };

    let ratio = best_ratio(
        6,
        || time(|| { small.run(&anything).unwrap(); }),
        || time(|| { large.run(&anything).unwrap(); }),
    );
    // Ten times the box, about ten times the work. Asserted as a CEILING
    // so that a future change making it quadratic is caught, and as a
    // FLOOR so that an index quietly added here is noticed and this
    // comment stops being true.
    assert!(ratio > 4.0, "this one really is linear; if it is not, say so: {ratio:.1}x");
    assert!(ratio < 25.0, "linear, not quadratic: {ratio:.1}x");
}
