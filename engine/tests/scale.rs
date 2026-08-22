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
