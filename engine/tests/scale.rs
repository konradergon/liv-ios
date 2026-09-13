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
