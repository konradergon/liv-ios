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

/// THE WRITE PATH (2026-08-19). Standing rule 2 says anything on the
/// snapshot path ships with a cost test. Three read paths had one; the
/// WRITE path had none — and that is where the app was quadratic.
///
/// Measured before this test existed: one `liv_set_at` on a box of notes
/// WITH BODIES cost 39.7 ms at 500 notes, 152.5 ms at 1,000, and did not
/// finish inside ten minutes at 2,000. The same edit on notes with no
/// body was flat, 4.9 ms at 500 to 8.6 ms at 8,000 — because the clerk
/// only reads entities that have content, and the FFI runs the clerk
/// over the WHOLE BOX on every write (`ffi/src/lib.rs`, `checkin`).
///
/// The sweep is the thing being timed, not the commit: `Session::commit`
/// underneath is a flat fsync. Bodies and names are BOTH required to
/// reproduce it — the names are what the gazetteer walks, the bodies are
/// what it walks them against.
#[test]
fn the_clerk_sweep_stays_flat_as_the_box_grows() {
    fn written(name: &str, n: usize) -> (std::path::PathBuf, Session) {
        let (path, mut session) = boxed(name);
        let now = DateTime::date(2026, 8, 19);
        for i in 0..n {
            let id = content::create_note(&mut session, now).unwrap();
            // A DISTINCT name per note: identical names would land every
            // note in one dedupe bucket and measure a different defect.
            content::set_property(&mut session, id, "name", &format!("note number {i}")).unwrap();
            // A real body. Without one the clerk skips the entity and
            // this test measures nothing.
            content::set_content(
                &mut session,
                id,
                vec![Span::Text(TextSpan::plain(
                    "Meeting with Anna about the kitchen rebuild, due friday.",
                ))],
                0,
            )
            .unwrap();
        }
        (path, session)
    }

    let (small_path, small_box) = written("sweep500", 500);
    let (large_path, large_box) = written("sweep1000", 1000);
    let sweep = |session: &Session| {
        time(|| {
            let _ = liv_services::clerk::sweep(session.store(), DateTime::date(2026, 8, 19));
        })
    };
    let ratio = best_ratio(3, || sweep(&small_box), || sweep(&large_box));
    let _ = std::fs::remove_dir_all(small_path.parent().unwrap());
    let _ = std::fs::remove_dir_all(large_path.parent().unwrap());
    // Linear would be ~2x. Measured before the fix: 3.8x — every entity
    // with content is walked against every named entity, so doubling the
    // box quadruples one write. 2.6x is the same headroom the file
    // projection gets, and it is nowhere near 3.8.
    // Linear would be 2.0x. MEASURED 2.47x on 2026-08-19 — the sweep
    // itself is mildly superlinear (every entity with content is walked
    // against the gazetteer of every named entity), but it is NOT the
    // quadratic that made a write take 152 ms. That was the FFI
    // re-persisting the whole proposal queue once per proposal; see
    // ffi/src/tests.rs `one_write_stays_flat_as_the_box_grows`. This
    // guards the sweep's own shape so the second-order cost cannot grow
    // into a first-order one unnoticed.
    assert!(
        ratio < 2.6,
        "doubling the box multiplied the clerk sweep by {ratio:.2}x; \
         the sweep is walking the box per entity, and it runs on EVERY write"
    );
}

/// THE SWEEP WITH A FULL QUEUE (2026-08-20). `the_clerk_sweep_stays_flat`
/// above builds its boxes with an EMPTY pending queue, so it never
/// exercises the sweep's closing filter — and that filter is the last
/// quadratic on the write path.
///
/// Every freshly derived proposal is compared, by full command-vector
/// equality, against every proposal already pending AND every one ever
/// declined. A real box always has a full queue: the clerk proposes on
/// every open and every write. Measured before the fix: 16.79 ms at
/// 4,000 notes, 62% of the whole sweep.
#[test]
fn the_sweep_stays_flat_when_the_queue_is_full() {
    fn primed(name: &str, n: usize) -> (std::path::PathBuf, Session) {
        let (path, mut session) = boxed(name);
        let now = DateTime::date(2026, 8, 20);
        for i in 0..n {
            let id = content::create_note(&mut session, now).unwrap();
            content::set_property(&mut session, id, "name", &format!("note number {i}")).unwrap();
            content::set_content(
                &mut session,
                id,
                vec![Span::Text(TextSpan::plain(
                    "Meeting with Anna about the kitchen rebuild, due friday.",
                ))],
                0,
            )
            .unwrap();
        }
        // Fill the queue, which is the state every real box is in.
        let first = liv_services::clerk::sweep(session.store(), now);
        session.propose_all(first).unwrap();
        (path, session)
    }

    // 1,000 vs 2,000: the quadratic is invisible below this. Measured at
    // 250/500 the ratio is 0.95x; it only shows from 1,000 upward.
    let (small_path, small_box) = primed("full1000", 1000);
    let (large_path, large_box) = primed("full2000", 2000);
    let sweep = |session: &Session| {
        time(|| {
            let _ = liv_services::clerk::sweep(session.store(), DateTime::date(2026, 8, 20));
        })
    };
    let ratio = best_ratio(3, || sweep(&small_box), || sweep(&large_box));
    let _ = std::fs::remove_dir_all(small_path.parent().unwrap());
    let _ = std::fs::remove_dir_all(large_path.parent().unwrap());
    assert!(
    // MEASURED 2.27x on 2026-08-20 — superlinear, and the cause is real:
    // the closing filter compares each fresh proposal by full command
    // equality against everything pending and everything ever declined.
    // It is not yet worth fixing (16.79 ms at 4,000 notes), but it is on
    // a path that only grows, and `declined` is append-only and never
    // pruned. This guards it from becoming first-order unnoticed.
        ratio < 2.6,
        "with a full queue, doubling the box multiplied the sweep by {ratio:.2}x; \
         the closing filter is comparing every new proposal against every old one"
    );
}

/// T2 (owner, 2026-08-22): `find_type` must not scan the box.
///
/// Measured before the fix: creating notes collapsed from 6,557/s at 10,000
/// entities to 1,354/s at 40,000 — because `create_note` calls `find_type`,
/// which built a Query and ran a full-store scan for the "note" type on every
/// single creation. A profile of a 500,000-entity build put 98% of samples in
/// that one call. Building a box was O(n²).
///
/// `store.named()` is an O(1) index over exactly this — the one T1 added — and
/// the store's own comment says trash and plumbing are read-time concerns,
/// which is what the filter below is for.
#[test]
fn finding_a_type_does_not_scan_the_box() {
    let (small_path, small_box) = notes("ft400", 400);
    let (large_path, large_box) = notes("ft4000", 4000);
    let look = |session: &Session| {
        time(|| {
            assert!(
                liv_services::content::find_type(session.store(), "note").is_some(),
                "the seeded note type is findable"
            );
        })
    };
    let ratio = best_ratio(5, || look(&small_box), || look(&large_box));
    let _ = std::fs::remove_dir_all(small_path.parent().unwrap());
    let _ = std::fs::remove_dir_all(large_path.parent().unwrap());
    // Ten times the box. A scan is ~10x; an index is ~1x. 2.5 leaves room
    // for constant overhead without letting the scan back in.
    assert!(
        ratio < 2.5,
        "ten times the box multiplied a type lookup by {ratio:.2}x; \
         find_type is scanning the store instead of using the name index"
    );
}

/// T3 (owner, 2026-08-22): `recency` must not be rebuilt per read.
///
/// Measured before the fix: 99 ms per call at 500,000 entities, on every
/// search, identical every time — it walked the whole transaction history and
/// allocated a fresh map of every entity. Search calls it once per query, so
/// it was ~34% of a search that already reads the whole box.
#[test]
fn recency_is_not_rebuilt_on_every_read() {
    let (small_path, small_box) = notes("rc400", 400);
    let (large_path, large_box) = notes("rc4000", 4000);
    let ask = |session: &Session| {
        time(|| {
            assert!(!session.store().recency().is_empty(), "the box has history");
        })
    };
    let ratio = best_ratio(5, || ask(&small_box), || ask(&large_box));
    let _ = std::fs::remove_dir_all(small_path.parent().unwrap());
    let _ = std::fs::remove_dir_all(large_path.parent().unwrap());
    assert!(
        ratio < 2.5,
        "ten times the history multiplied a recency read by {ratio:.2}x; \
         it is being rebuilt from history instead of maintained on append"
    );
}
