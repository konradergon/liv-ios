//! Cost, not just correctness.
//!
//! Every one of the other 315 tests checks that an answer is right; none
//! checked that getting it stays affordable. The snapshot's file
//! projection was quadratic — it resolved a property by scanning the
//! whole store, once per entity — and nothing caught it, because nothing
//! looks. Measured before the fix: 12 ms at 500 entities, 195 ms at
//! 4,000, on every snapshot, on a machine much faster than a phone.
//!
//! This test asserts the SHAPE, not a wall-clock number: doubling the
//! box must not much more than double the work. A ratio survives slow
//! CI machines and a debug build; a millisecond budget does not.

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

/// Build `n` notes and time one file projection over them.
fn cost(n: usize) -> Duration {
    let (path, mut session) = boxed(&format!("n{n}"));
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
    // Best of three: a cold cache or a scheduler hiccup must not fail a
    // build. The quadratic shape this guards against is a 3-4x jump per
    // doubling, far outside that noise.
    let store = session.store();
    let best = (0..3)
        .map(|_| {
            let start = Instant::now();
            let files = liv_services::vault::expected_files(store);
            assert_eq!(files.len(), n, "every note projects one file");
            start.elapsed()
        })
        .min()
        .unwrap();
    let _ = std::fs::remove_dir_all(path.parent().unwrap());
    best
}

#[test]
fn the_file_projection_stays_linear_in_box_size() {
    let small = cost(400);
    let large = cost(800);
    // Linear would be ~2x. Quadratic was ~3.3x here and worse as the box
    // grows. 2.6x leaves room for constant per-run overhead at these
    // small sizes without letting a scan back in.
    let ratio = large.as_secs_f64() / small.as_secs_f64().max(1e-9);
    assert!(
        ratio < 2.6,
        "doubling the box multiplied the work by {ratio:.2}x \
         ({small:?} -> {large:?}); something is scanning the store per entity"
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
    fn lookups(box_size: usize) -> Duration {
        let (path, mut session) = boxed(&format!("lookup{box_size}"));
        let now = DateTime::date(2026, 8, 9);
        for _ in 0..box_size {
            content::create_note(&mut session, now).unwrap();
        }
        let store = session.store();
        let best = (0..3)
            .map(|_| {
                let start = Instant::now();
                for _ in 0..1_000 {
                    assert!(liv_services::property_id(store, "due").is_some());
                }
                start.elapsed()
            })
            .min()
            .unwrap();
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
        best
    }
    let small = lookups(400);
    let large = lookups(1600);
    let ratio = large.as_secs_f64() / small.as_secs_f64().max(1e-9);
    assert!(
        ratio < 2.5,
        "a 4x larger box multiplied the same lookups by {ratio:.2}x \
         ({small:?} -> {large:?}); property_id is scanning the store again"
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
    fn reads(box_size: usize) -> Duration {
        let (path, mut session) = boxed(&format!("links{box_size}"));
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
        let store = session.store();
        // Best of FIVE: this test shares a machine with the two above,
        // and a scheduler hiccup in the middle of a 500-read run is the
        // only thing that has ever moved the ratio.
        let best = (0..5)
            .map(|_| {
                let start = Instant::now();
                for _ in 0..500 {
                    assert_eq!(liv_services::links::links(store, hub).inbound.len(), 5);
                }
                start.elapsed()
            })
            .min()
            .unwrap();
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
        best
    }
    let small = reads(200);
    let large = reads(800);
    let ratio = large.as_secs_f64() / small.as_secs_f64().max(1e-9);
    // The shape this guards against — walking every body — is ~4x per 4x
    // box, and was measured at 7x when the hub's own link count grew with
    // the box. 3x leaves room for a loaded machine without letting it in.
    assert!(
        ratio < 3.0,
        "a 4x larger box multiplied the same link reads by {ratio:.2}x \
         ({small:?} -> {large:?}); links() is following the box, not the entity"
    );
}
