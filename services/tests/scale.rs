//! Cost, not just correctness.
//!
//! Every one of the other 315 tests checks that an answer is right; none
//! checked that getting it stays affordable. The snapshot's file
//! projection was quadratic — it resolved a property by scanning the
//! whole store, once per entity — and nothing caught it, because nothing
//! looks. Measured before the fix: 12 ms at 500 entities, 195 ms at
//! 4,000, on every snapshot, on a machine much faster than a phone.
//!
//! These tests assert the SHAPE, not a wall-clock number: doubling the
//! box must not much more than double the work. A ratio survives slow
//! CI machines and a debug build; a millisecond budget does not.
//!
//! **How the ratio is measured** (2026-08-17). Timing the small box, then
//! the large one, and dividing was fragile: the two numbers came from
//! different moments, so one scheduler hiccup — including the other tests
//! in this file, which run at the same time — moved the ratio without
//! anything being slower. Both boxes are now built ONCE and then measured
//! in interleaved rounds, and the reported ratio is the best round. A
//! hiccup now has to land in the same place in every round to be seen.

use liv_core::*;
use liv_services::{content, seed_if_fresh};
use std::time::{Duration, Instant};

fn boxed(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("liv_scale_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.log");
    let mut session = Session::open(&path).unwrap();
    seed_if_fresh(&mut session).unwrap();
    (path, session)
}

fn time(work: impl Fn()) -> Duration {
    let start = Instant::now();
    work();
    start.elapsed()
}

/// The best of `rounds` interleaved measurements of the same two reads.
/// Both closures must already have their boxes built — building inside a
/// round would time the build.
fn best_ratio(rounds: usize, small: impl Fn() -> Duration, large: impl Fn() -> Duration) -> f64 {
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

/// Build `n` notes, each with a line of content.
fn notes(name: &str, n: usize) -> (std::path::PathBuf, Session) {
    let (path, mut session) = boxed(name);
    let now = DateTime::date(2026, 8, 8);
    for _ in 0..n {
        let id = content::create_note(&mut session, now).unwrap();
        content::set_content(
            &mut session,
            id,
            vec![Span::Text(TextSpan::plain("a line of words"))],
            0,
        )
        .unwrap();
    }
    (path, session)
}

#[test]
fn the_file_projection_stays_linear_in_box_size() {
    let (small_path, small_box) = notes("n400", 400);
    let (large_path, large_box) = notes("n800", 800);
    let project = |session: &Session, n: usize| {
        time(|| {
            let files = liv_services::vault::expected_files(session.store());
            assert_eq!(files.len(), n, "every note projects one file");
        })
    };
    // Linear would be ~2x. Quadratic was ~3.3x here and worse as the box
    // grows. 2.6x leaves room for constant per-run overhead at these
    // small sizes without letting a scan back in.
    let ratio = best_ratio(
        5,
        || project(&small_box, 400),
        || project(&large_box, 800),
    );
    let _ = std::fs::remove_dir_all(small_path.parent().unwrap());
    let _ = std::fs::remove_dir_all(large_path.parent().unwrap());
    assert!(
        ratio < 2.6,
        "doubling the box multiplied the work by {ratio:.2}x; \
         something is scanning the store per entity"
    );
}

/// T1 (owner, 2026-08-09): looking up a property by name must not scan
/// the store. ~197 call sites resolve names; before the index, each
/// call was O(box), so N lookups over a box of N cost N² — the exact
/// shape that made the snapshot take 195 ms at 4,000 entities.
#[test]
fn name_lookup_stays_flat_as_the_box_grows() {
    // The SAME number of lookups over boxes of different sizes: the
    // cost must not follow the box. With the old scan, 4x the entities
    // made the same thousand lookups ~4x slower; with the index the
    // box's size is irrelevant.
    fn plain(name: &str, box_size: usize) -> (std::path::PathBuf, Session) {
        let (path, mut session) = boxed(name);
        let now = DateTime::date(2026, 8, 9);
        for _ in 0..box_size {
            content::create_note(&mut session, now).unwrap();
        }
        (path, session)
    }
    let (small_path, small_box) = plain("lookup400", 400);
    let (large_path, large_box) = plain("lookup1600", 1600);
    let lookups = |session: &Session| {
        time(|| {
            for _ in 0..1_000 {
                assert!(liv_services::property_id(session.store(), "due").is_some());
            }
        })
    };
    let ratio = best_ratio(5, || lookups(&small_box), || lookups(&large_box));
    let _ = std::fs::remove_dir_all(small_path.parent().unwrap());
    let _ = std::fs::remove_dir_all(large_path.parent().unwrap());
    assert!(
        ratio < 2.5,
        "a 4x larger box multiplied the same lookups by {ratio:.2}x; \
         property_id is scanning the store again"
    );
}

/// Links, both directions (2026-08-17). "What points at me" is the read
/// that tempts a scan: every body in the box holds `[[ ]]` tokens, and
/// the honest-looking way to answer is to walk them all. The core keeps
/// a backlink index instead, so reading ONE entity's links must cost
/// what that entity's links cost — never what the box costs.
#[test]
fn reading_links_stays_flat_as_the_box_grows() {
    // The hub keeps the SAME five links in both boxes; everything else
    // in the box links elsewhere, so the index is large either way. A
    // scan of every body would make the 4x box ~4x slower.
    fn chain(name: &str, box_size: usize) -> (std::path::PathBuf, Session, Id) {
        let (path, mut session) = boxed(name);
        let now = DateTime::date(2026, 8, 17);
        let hub = content::create_note(&mut session, now).unwrap();
        let mut previous = hub;
        for i in 0..box_size {
            let id = content::create_note(&mut session, now).unwrap();
            // A chain: each note points at the one before it. Only the
            // first five reach the hub.
            content::set_content(
                &mut session,
                id,
                vec![Span::Text(TextSpan::plain("see ")), Span::Ref(previous)],
                0,
            )
            .unwrap();
            if i >= 4 {
                previous = id;
            }
        }
        (path, session, hub)
    }
    let (small_path, small_box, small_hub) = chain("links200", 200);
    let (large_path, large_box, large_hub) = chain("links800", 800);
    let reads = |session: &Session, hub: Id| {
        time(|| {
            for _ in 0..500 {
                assert_eq!(liv_services::links::links(session.store(), hub).inbound.len(), 5);
            }
        })
    };
    let ratio = best_ratio(
        5,
        || reads(&small_box, small_hub),
        || reads(&large_box, large_hub),
    );
    let _ = std::fs::remove_dir_all(small_path.parent().unwrap());
    let _ = std::fs::remove_dir_all(large_path.parent().unwrap());
    // The shape this guards against — walking every body — is ~4x per 4x
    // box, and was measured at 7x when the hub's own link count grew with
    // the box.
    assert!(
        ratio < 2.5,
        "a 4x larger box multiplied the same link reads by {ratio:.2}x; \
         links() is following the box, not the entity"
    );
}
