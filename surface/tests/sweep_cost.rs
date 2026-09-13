//! What the sweep costs — standing rule 2, and the one measurement
//! `core/` actually took.
//!
//! The mentions proposer is the whole risk. Without a word index, every
//! thing with a body walks EVERY name in the box, and `core/` measured
//! exactly that on 2026-08-19: **8.9 ms at 250 notes, 35.4 at 500, 141.7
//! at 1,000** — four times the work for twice the box. That is the shape
//! this file exists to keep out.
//!
//! A ratio, never a millisecond budget: a ratio survives a slow machine
//! and a debug build.

use liv_engine::*;
use liv_surface::clerk::sweep;
use std::time::{Duration, Instant};

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_789_257_600_000;

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
            let s = small();
            let l = large();
            l.as_secs_f64() / s.as_secs_f64().max(1e-9)
        })
        .fold(f64::INFINITY, f64::min)
}

/// `n` named people, and `n` notes whose bodies name nobody.
///
/// Nobody is mentioned, so the ANSWER is the same size in both boxes and
/// only the searching differs — which is what tells a prefilter from a
/// walk. A correctness test cannot see the difference: both answer
/// "no mentions".
fn box_of(n: u64) -> Engine {
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    for i in 0..n {
        e.create(kind::PERSON, Some(&format!("Person Number {i}")), T0 + i).unwrap();
    }
    for i in 0..n {
        let id = e.create(kind::NOTE, Some(&format!("note {i}")), T0 + n + i).unwrap();
        e.set_content(
            id,
            vec![Span::text("a few words about the roof and the ferry and nothing else")],
            0,
            T0 + n + i,
        )
        .unwrap();
    }
    e
}

/// **Twice the box must not be four times the work.**
///
/// Ten times the entities here. A walk over every name would be ~100×
/// (ten times the notes, each against ten times the names); the prefilter
/// makes it linear in the box, which is honest — every note still has to
/// be read — and nothing worse.
#[test]
fn the_sweep_does_not_go_quadratic_in_the_number_of_names() {
    let small = box_of(50);
    let large = box_of(500);

    let ratio = best_ratio(
        6,
        || time(|| assert!(sweep(&small).unwrap().is_empty())),
        || time(|| assert!(sweep(&large).unwrap().is_empty())),
    );
    // **The ceiling is MEASURED, not guessed.** Ten times the box costs
    // 9.3x with the word index and 18.5x without it, on this machine —
    // so 14 sits between them with room either side.
    //
    // The first version of this said 25, which was a guess, and 25 does
    // not catch the walk: at these sizes the per-entity SQLite reads
    // swamp the string matching, so removing the index only doubles the
    // ratio rather than squaring it. A threshold nobody measured is a
    // threshold that passes.
    assert!(ratio < 14.0, "the sweep went superlinear in the box: {ratio:.1}x");
}

/// And a box the clerk is switched off in costs nothing at all.
#[test]
fn a_silenced_clerk_does_not_read_the_box() {
    let small = {
        let mut e = box_of(50);
        let s = e.create(kind::NOTE, Some("settings"), T0).unwrap();
        e.set(s, prop::AUTOMATION, Value::Bool(false), T0 + 1).unwrap();
        e
    };
    let large = {
        let mut e = box_of(500);
        let s = e.create(kind::NOTE, Some("settings"), T0).unwrap();
        e.set(s, prop::AUTOMATION, Value::Bool(false), T0 + 1).unwrap();
        e
    };

    let ratio = best_ratio(
        8,
        || time(|| assert!(sweep(&small).unwrap().is_empty())),
        || time(|| assert!(sweep(&large).unwrap().is_empty())),
    );
    // Off means SILENCE, and silence is free: the gate is an index seek
    // on one property, so it must not notice the box at all.
    assert!(ratio < 4.0, "a silenced clerk still read the box: {ratio:.1}x");
}
