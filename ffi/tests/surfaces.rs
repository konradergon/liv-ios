//! The new seam, exercised through the C ABI rather than around it.
//!
//! Every call below goes through the same `extern "C"` entry point a Swift
//! shell will use, with C strings in and a `char *` out — because the
//! things that break at a seam (a null, a bad parse, a leaked string, an
//! id that does not survive the round trip) are invisible from the Rust
//! side of it.

use std::ffi::{CStr, CString};

use liv_engine::*;
use liv_ffi::surfaces::*;

fn box_path(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("liv_ffi_surface_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.join("liv.db")
}

const DAY: i32 = 20_700;

fn at(day: i32, hour: i64, minute: i64) -> i64 {
    day as i64 * 86_400_000 + hour * 3_600_000 + minute * 60_000
}

/// Call a verb and get its JSON back, having freed the C string.
fn call(f: impl FnOnce(*mut *mut std::ffi::c_char) -> i32) -> Result<serde_json::Value, i32> {
    let mut out: *mut std::ffi::c_char = std::ptr::null_mut();
    let code = f(&mut out);
    if code != LIV_OK {
        assert!(out.is_null(), "a failing call must not also hand back a string to leak");
        return Err(code);
    }
    assert!(!out.is_null(), "LIV_OK means there is an answer");
    let json = unsafe { CStr::from_ptr(out) }.to_str().unwrap().to_owned();
    unsafe { liv_ffi::liv_string_free(out) };
    Ok(serde_json::from_str(&json).expect("the answer is JSON"))
}

fn titles(v: &serde_json::Value) -> Vec<String> {
    v.as_array()
        .unwrap()
        .iter()
        .map(|r| r["title"].as_str().unwrap_or_default().to_owned())
        .collect()
}

#[test]
fn a_screen_asks_for_itself_and_gets_itself() {
    let path = box_path("today");
    let (task_id, area_id) = {
        let mut e = Engine::open_local(&path).unwrap();
        let a = e.create(kind::TASK, Some("Dentist"), 1_000).unwrap();
        e.set(a, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, 14, 0), tz: 0 }), 1_001)
            .unwrap();
        e.set(a, prop::AREA, Value::Ref(area::HEALTH), 1_002).unwrap();
        let late = e.create(kind::TASK, Some("Overdue"), 1_003).unwrap();
        e.set(late, prop::DUE, Value::Date(DateSpec::Day(DAY - 2)), 1_004).unwrap();
        (a, area::HEALTH)
    };
    unsafe { liv_view_close_all() };

    let c = CString::new(path.to_str().unwrap()).unwrap();
    let v = call(|out| unsafe {
        liv_view_today(c.as_ptr(), DAY, DAY, at(DAY, 9, 0), std::ptr::null(), out)
    })
    .unwrap();

    assert_eq!(titles(&v["ahead"]), vec!["Dentist"]);
    assert_eq!(titles(&v["late"]), vec!["Overdue"]);
    assert!(v["passed"].as_array().unwrap().is_empty());

    // AN ID SURVIVES THE ROUND TRIP as 32 hex characters — 16 bytes, which
    // a JSON number is not. The whole retrofit cost core-decisions.md
    // prices is avoided by the ABI being built for them from the start.
    let id = v["ahead"][0]["id"].as_str().unwrap();
    assert_eq!(id.len(), 32);
    assert_eq!(id, task_id.hex());
    assert_eq!(v["ahead"][0]["area"].as_str().unwrap(), area_id.hex());
    assert_eq!(v["next"].as_str().unwrap(), task_id.hex(), "the next thing up is named");

    // The payload is the SCREEN, not the box: nothing about the late task
    // appears twice, and no entity the day does not show is in it.
    assert_eq!(v["captured"].as_u64(), Some(0), "nothing was made on DAY itself");
}

#[test]
fn the_error_channel_says_which_thing_went_wrong() {
    // THE POINT OF THE CHANGE. The old ABI returns 0 for both "no id" and
    // "it broke", which is why a shell could not tell an empty box from an
    // unreadable one. Every one of these is a distinct code.
    let path = box_path("errors");
    let c = CString::new(path.to_str().unwrap()).unwrap();

    assert_eq!(
        call(|out| unsafe { liv_view_today(std::ptr::null(), DAY, DAY, 0, std::ptr::null(), out) }),
        Err(LIV_ERR_PATH)
    );

    let nowhere = CString::new("/does/not/exist/at/all/liv.db").unwrap();
    assert_eq!(
        call(|out| unsafe { liv_view_today(nowhere.as_ptr(), DAY, DAY, 0, std::ptr::null(), out) }),
        Err(LIV_ERR_OPEN)
    );

    assert_eq!(
        call(|out| unsafe { liv_view_everything(c.as_ptr(), 9, DAY, std::ptr::null(), out) }),
        Err(LIV_ERR_ARG),
        "an unknown slice is an argument error, not an empty list"
    );
    assert_eq!(
        call(|out| unsafe {
            liv_view_tasks(c.as_ptr(), 1, std::ptr::null(), DAY, std::ptr::null(), out)
        }),
        Err(LIV_ERR_ARG),
        "filtering by status without saying which"
    );
    let bad_id = CString::new("not-hex").unwrap();
    assert_eq!(
        call(|out| unsafe {
            liv_view_tasks(c.as_ptr(), 2, bad_id.as_ptr(), DAY, std::ptr::null(), out)
        }),
        Err(LIV_ERR_ARG)
    );
    let bad_lens = CString::new("{\"not\":\"an array\"}").unwrap();
    assert_eq!(
        call(|out| unsafe {
            liv_view_today(c.as_ptr(), DAY, DAY, 0, bad_lens.as_ptr(), out)
        }),
        Err(LIV_ERR_ARG)
    );

    // And a null out-pointer is refused rather than written through.
    assert_eq!(
        unsafe { liv_view_today(c.as_ptr(), DAY, DAY, 0, std::ptr::null(), std::ptr::null_mut()) },
        LIV_ERR_ARG
    );
    unsafe { liv_view_close_all() };
}

#[test]
fn an_empty_box_is_an_empty_answer_and_not_an_error() {
    // The other half of the same point: empty is a success.
    let path = box_path("empty");
    let c = CString::new(path.to_str().unwrap()).unwrap();
    let v = call(|out| unsafe {
        liv_view_everything(c.as_ptr(), 0, DAY, std::ptr::null(), out)
    })
    .unwrap();
    assert!(v.as_array().unwrap().is_empty());
    unsafe { liv_view_close_all() };
}

#[test]
fn a_null_lens_means_everything_and_an_empty_one_means_nothing() {
    // **Null is not the empty array.** A workspace whose query matches
    // nothing admits nothing, and that is a real, showable state. Passing
    // null to mean it would turn a filtered-to-empty screen into an
    // unfiltered one — the more alarming of the two failures.
    let path = box_path("lens");
    let keep = {
        let mut e = Engine::open_local(&path).unwrap();
        let a = e.create(kind::TASK, Some("Mine"), 1_000).unwrap();
        e.create(kind::TASK, Some("Theirs"), 1_001).unwrap();
        a
    };
    unsafe { liv_view_close_all() };
    let c = CString::new(path.to_str().unwrap()).unwrap();

    let all = call(|out| unsafe {
        liv_view_everything(c.as_ptr(), 0, DAY, std::ptr::null(), out)
    })
    .unwrap();
    assert_eq!(titles(&all).len(), 2);

    let none = CString::new("[]").unwrap();
    let v = call(|out| unsafe {
        liv_view_everything(c.as_ptr(), 0, DAY, none.as_ptr(), out)
    })
    .unwrap();
    assert!(v.as_array().unwrap().is_empty(), "an empty lens admits nothing");

    let one = CString::new(format!("[\"{}\"]", keep.hex())).unwrap();
    let v = call(|out| unsafe {
        liv_view_everything(c.as_ptr(), 0, DAY, one.as_ptr(), out)
    })
    .unwrap();
    assert_eq!(titles(&v), vec!["Mine"]);
    unsafe { liv_view_close_all() };
}

#[test]
fn tasks_come_back_grouped_with_the_groups_own_facts() {
    let path = box_path("tasks");
    let roof = {
        let mut e = Engine::open_local(&path).unwrap();
        let roof = e.create(kind::PROJECT, Some("Roof"), 1_000).unwrap();
        for (n, (name, st, due)) in [
            ("Order slates", status::TODO, DAY - 2),
            ("Call the roofer", status::TODO, DAY + 1),
            ("Pay deposit", status::DONE, DAY - 9),
        ]
        .into_iter()
        .enumerate()
        {
            let t = e.create(kind::TASK, Some(name), 1_010 + n as u64).unwrap();
            e.set(t, prop::STATUS, Value::Ref(st), 1_020 + n as u64).unwrap();
            e.set(t, prop::DUE, Value::Date(DateSpec::Day(due)), 1_030 + n as u64).unwrap();
            e.set(t, prop::PROJECT, Value::Ref(roof), 1_040 + n as u64).unwrap();
        }
        roof
    };
    unsafe { liv_view_close_all() };
    let c = CString::new(path.to_str().unwrap()).unwrap();

    let v = call(|out| unsafe {
        liv_view_tasks(c.as_ptr(), 0, std::ptr::null(), DAY, std::ptr::null(), out)
    })
    .unwrap();
    let groups = v.as_array().unwrap();
    assert_eq!(groups.len(), 2, "To do and Done; the empty ones are not groups");
    assert_eq!(groups[0]["name"], "To do");
    assert_eq!(groups[0]["late"], 1, "the lateness is the group's fact, said once");
    assert_eq!(groups[0]["completes"], false);
    assert_eq!(groups[1]["name"], "Done");
    assert_eq!(groups[1]["completes"], true);
    assert_eq!(groups[1]["late"], 0);
    assert_eq!(titles(&groups[0]["rows"]), vec!["Order slates", "Call the roofer"]);

    // Filtering by project, by id.
    let id = CString::new(roof.hex()).unwrap();
    let v = call(|out| unsafe {
        liv_view_tasks(c.as_ptr(), 2, id.as_ptr(), DAY, std::ptr::null(), out)
    })
    .unwrap();
    assert_eq!(v.as_array().unwrap().len(), 2);
    unsafe { liv_view_close_all() };
}

#[test]
fn the_day_comes_back_laid_out() {
    let path = box_path("day");
    {
        let mut e = Engine::open_local(&path).unwrap();
        for (n, m) in [(0i64, 0i64), (1, 20)] {
            let t = e.create(kind::EVENT, Some(&format!("clash {n}")), 1_000 + n as u64).unwrap();
            e.set(
                t,
                prop::DUE,
                Value::Date(DateSpec::Instant { ms: at(DAY, 9, m), tz: 0 }),
                1_010 + n as u64,
            )
            .unwrap();
        }
        let allday = e.create(kind::TASK, Some("Renew the passport"), 2_000).unwrap();
        e.set(allday, prop::DUE, Value::Date(DateSpec::Day(DAY)), 2_001).unwrap();
    }
    unsafe { liv_view_close_all() };
    let c = CString::new(path.to_str().unwrap()).unwrap();

    let v = call(|out| unsafe { liv_view_day(c.as_ptr(), DAY, std::ptr::null(), out) }).unwrap();
    assert_eq!(titles(&v["all_day"]), vec!["Renew the passport"]);
    let blocks = v["blocks"].as_array().unwrap();
    assert_eq!(blocks.len(), 2);
    assert_eq!(blocks[0]["start_min"], 9 * 60);
    assert_eq!(blocks[1]["start_min"], 9 * 60 + 20);
    // THE SHELL IS TOLD THE COLUMNS, not left to work out the overlap.
    assert_eq!(blocks[0]["columns"], 2);
    assert_eq!(blocks[0]["column"], 0);
    assert_eq!(blocks[1]["column"], 1);
    assert!(blocks[0]["minutes"].as_i64().unwrap() > 0, "never zero — it stays tappable");
    unsafe { liv_view_close_all() };
}

#[test]
fn the_box_stays_open_between_calls_and_sees_writes_made_since() {
    // The connection is HELD rather than reopened per call, which is the
    // whole of the cache here — no five-field invalidation, because there
    // is no log to re-read and SQLite does its own locking.
    let path = box_path("reuse");
    {
        let mut e = Engine::open_local(&path).unwrap();
        e.create(kind::NOTE, Some("First"), 1_000).unwrap();
    }
    let c = CString::new(path.to_str().unwrap()).unwrap();

    let v = call(|out| unsafe {
        liv_view_everything(c.as_ptr(), 0, DAY, std::ptr::null(), out)
    })
    .unwrap();
    assert_eq!(titles(&v), vec!["First"]);

    // A write through a second handle on the same file, then the same
    // held connection is asked again.
    {
        let mut e = Engine::open_local(&path).unwrap();
        e.create(kind::NOTE, Some("Second"), 2_000).unwrap();
    }
    let v = call(|out| unsafe {
        liv_view_everything(c.as_ptr(), 0, DAY, std::ptr::null(), out)
    })
    .unwrap();
    assert_eq!(titles(&v), vec!["Second", "First"], "a held connection is not a stale one");
    unsafe { liv_view_close_all() };
}

#[test]
fn the_payload_is_the_screen_rather_than_the_box() {
    // The claim the whole change rests on, as a number. `liv_snapshot` is
    // 3.5 MB at 6,400 notes whatever is on screen; one day of it is one
    // day of it.
    let path = box_path("size");
    {
        let mut e = Engine::open_local(&path).unwrap();
        for i in 0..2_000u64 {
            let t = e.create(kind::TASK, Some(&format!("task {i}")), 1_000 + i).unwrap();
            // Spread over 200 days, so one day holds ten.
            e.set(
                t,
                prop::DUE,
                Value::Date(DateSpec::Day(DAY + (i % 200) as i32)),
                2_000 + i,
            )
            .unwrap();
        }
    }
    unsafe { liv_view_close_all() };
    let c = CString::new(path.to_str().unwrap()).unwrap();

    let mut out: *mut std::ffi::c_char = std::ptr::null_mut();
    assert_eq!(unsafe { liv_view_day(c.as_ptr(), DAY, std::ptr::null(), &mut out) }, LIV_OK);
    let day_bytes = unsafe { CStr::from_ptr(out) }.to_bytes().len();
    unsafe { liv_ffi::liv_string_free(out) };

    let mut out: *mut std::ffi::c_char = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_view_everything(c.as_ptr(), 0, DAY, std::ptr::null(), &mut out) },
        LIV_OK
    );
    let all_bytes = unsafe { CStr::from_ptr(out) }.to_bytes().len();
    unsafe { liv_ffi::liv_string_free(out) };

    // Ten rows against two thousand. The ratio is the point, not the
    // bytes: one day does not pay for the other 199.
    println!("one day: {day_bytes} B    the whole box: {all_bytes} B");
    assert!(
        day_bytes * 20 < all_bytes,
        "one day was {day_bytes} B against the whole box's {all_bytes} B"
    );
    unsafe { liv_view_close_all() };
}

/// **Standing rule 2, on the new read path.** Anything on the snapshot
/// path ships with a COST test, not just a correctness one — and this
/// path exists precisely because the old one was linear in the box.
///
/// A correctness test cannot see the difference: one day's rows are the
/// same rows either way. The SHAPE is the claim.
#[test]
fn one_days_view_stays_flat_as_the_box_grows() {
    use std::time::Instant;

    /// `n` tasks on OTHER days, plus exactly ten on DAY.
    ///
    /// The ten are the point. A first version spread everything evenly
    /// over 500 days, which put one row on DAY in the small box and ten
    /// in the large one — so the answer grew with the box and the test
    /// was measuring proportionality while claiming flatness. It failed
    /// at 5.0x and it was the test that was wrong.
    fn box_of(name: &str, n: u64) -> std::path::PathBuf {
        let path = box_path(name);
        let mut e = Engine::open_local(&path).unwrap();
        for i in 0..n {
            let t = e.create(kind::TASK, Some(&format!("filler {i}")), 1_000 + i).unwrap();
            e.set(
                t,
                prop::DUE,
                Value::Date(DateSpec::Day(DAY + 1 + (i % 499) as i32)),
                2_000 + i,
            )
            .unwrap();
        }
        for i in 0..10u64 {
            let t = e.create(kind::TASK, Some(&format!("on the day {i}")), 900_000 + i).unwrap();
            e.set(
                t,
                prop::DUE,
                Value::Date(DateSpec::Instant { ms: at(DAY, 9, i as i64), tz: 0 }),
                900_100 + i,
            )
            .unwrap();
        }
        path
    }

    let small = box_of("flat_small", 500);
    let large = box_of("flat_large", 5_000);
    unsafe { liv_view_close_all() };
    let cs = CString::new(small.to_str().unwrap()).unwrap();
    let cl = CString::new(large.to_str().unwrap()).unwrap();

    // Same answer in both, which is what makes the ratio mean anything.
    for c in [&small, &large] {
        let cc = CString::new(c.to_str().unwrap()).unwrap();
        let v = call(|out| unsafe { liv_view_day(cc.as_ptr(), DAY, std::ptr::null(), out) })
            .unwrap();
        assert_eq!(v["blocks"].as_array().unwrap().len(), 10);
    }
    unsafe { liv_view_close_all() };

    let once = |c: &CString| {
        let start = Instant::now();
        let mut out: *mut std::ffi::c_char = std::ptr::null_mut();
        assert_eq!(unsafe { liv_view_day(c.as_ptr(), DAY, std::ptr::null(), &mut out) }, LIV_OK);
        unsafe { liv_ffi::liv_string_free(out) };
        start.elapsed().as_secs_f64()
    };

    // Warm both, then interleave — the same discipline as the engine's
    // scale tests, so one scheduler hiccup has to land in the same place
    // every round to be seen.
    once(&cs);
    once(&cl);
    let ratio = (0..7)
        .map(|_| {
            let s = once(&cs);
            let l = once(&cl);
            l / s.max(1e-9)
        })
        .fold(f64::INFINITY, f64::min);

    assert!(ratio < 3.0, "ten times the box for the SAME ten rows cost {ratio:.1}x");
    unsafe { liv_view_close_all() };
}

/// **The end of the chain, and the thing stage 4 rests on.**
///
/// A real `core/` box — seeded the way a phone seeds it — is converted,
/// and then read through the same C entry points the shell will call.
/// Every earlier test in this file built its box with the engine's own
/// API, which proves the seam but not that anything already in the world
/// can reach it.
#[test]
fn a_converted_box_reads_through_the_new_seam() {
    let dir = std::env::temp_dir().join("liv_ffi_converted");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let log = dir.join("liv.log");
    let db = dir.join("liv.db");

    // A box the old way: seeded, then two things caught and one of them
    // given a date and a status.
    {
        use liv_core::{props, Author, Cell, Command, DateTime, Session, Value as CV};
        let mut s = Session::open(&log).unwrap();
        liv_services::seed_if_fresh(&mut s).unwrap();
        let due = liv_services::property_id(s.store(), "due").unwrap();
        let task = liv_services::content::create_task(
            &mut s,
            DateTime { civil: 2026_09_13_1000, date_only: false, end: None },
        )
        .unwrap();
        s.commit(
            vec![
                Command::AddCell {
                    entity: task,
                    cell: Cell { property: props::NAME, value: CV::text("Order slates") },
                },
                Command::AddCell {
                    entity: task,
                    cell: Cell {
                        property: due,
                        // Day 20_714 is 2026-09-18.
                        value: CV::DateTime(DateTime {
                            civil: 2026_09_18_0900,
                            date_only: false,
                            end: None,
                        }),
                    },
                },
            ],
            "task",
            Author::User,
        )
        .unwrap();
        liv_services::content::create_note(
            &mut s,
            DateTime { civil: 2026_09_13_1100, date_only: false, end: None },
        )
        .unwrap();
    }

    let report = liv_convert::convert(&log, &db).unwrap();
    assert!(report.clean(), "{report:?}");
    assert!(report.resolved > 50, "the box's schema resolved onto the furniture, not into it");

    unsafe { liv_view_close_all() };
    let c = CString::new(db.to_str().unwrap()).unwrap();
    let the_day = liv_convert::days_from_civil(2026, 9, 18);

    // THE DAY. The task's `due` landed on `prop::DUE` — the frozen id
    // every surface reads — which is the whole point of resolving the
    // box's schema rather than copying it.
    let v = call(|out| unsafe { liv_view_day(c.as_ptr(), the_day, std::ptr::null(), out) })
        .unwrap();
    let blocks = v["blocks"].as_array().unwrap();
    assert_eq!(blocks.len(), 1, "one thing is due that day");
    assert_eq!(blocks[0]["row"]["title"], "Order slates");
    assert_eq!(blocks[0]["start_min"], 9 * 60, "at 09:00");

    // TASKS. The task arrived with its kind, so `of_kind` finds it.
    let v = call(|out| unsafe {
        liv_view_tasks(c.as_ptr(), 0, std::ptr::null(), the_day, std::ptr::null(), out)
    })
    .unwrap();
    let found: Vec<String> =
        v.as_array().unwrap().iter().flat_map(|g| titles(&g["rows"])).collect();
    assert_eq!(found, vec!["Order slates"]);

    // EVERYTHING. Two things, and NOT the sixty pieces of schema — those
    // resolved onto the compiled-in furniture, and backstage things are
    // on no front-of-house surface anyway.
    let v = call(|out| unsafe {
        liv_view_everything(c.as_ptr(), 0, the_day, std::ptr::null(), out)
    })
    .unwrap();
    let names = titles(&v);
    assert!(names.contains(&"Order slates".to_owned()), "{names:?}");
    assert!(
        names.len() < 5,
        "a converted box's front of house is its content, not its schema: {names:?}"
    );

    unsafe { liv_view_close_all() };
    let _ = std::fs::remove_dir_all(&dir);
}

/// **A capture has no name, and its title is its first line.**
///
/// Prompted by the first device run, which showed `First row: Untitled`.
/// That is the right answer for a thing with neither a name nor a body,
/// and the wrong one for a scrap — so the question is which, and the way
/// to settle it is a test rather than a squint at a screenshot.
///
/// The chain has three places it could be lost: `capture` writes
/// `props::CONTENT` as RichText; the converter flattens that to markdown
/// in `prop::BODY`; and `surface::row` falls back to the body's first
/// line when there is no name.
#[test]
fn a_captured_scrap_keeps_its_first_line_as_its_title() {
    let dir = std::env::temp_dir().join("liv_ffi_capture_title");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let log = dir.join("liv.log");
    let db = dir.join("liv.db");

    let the_day = liv_convert::days_from_civil(2026, 9, 13);
    {
        use liv_core::{Author, Cell, Command, DateTime, Session, Value as CV};
        let mut s = Session::open(&log).unwrap();
        liv_services::seed_if_fresh(&mut s).unwrap();
        let due = liv_services::property_id(s.store(), "due").unwrap();

        // A scrap, the way the app catches one: content, no name.
        let scrap = liv_services::capture(
            &mut s,
            "call the roofer about the slates",
            DateTime { civil: 2026_09_13_1000, date_only: false, end: None },
        )
        .unwrap();
        // A thing with neither, so both answers appear on one screen.
        let bare = liv_services::content::create_task(
            &mut s,
            DateTime { civil: 2026_09_13_1030, date_only: false, end: None },
        )
        .unwrap();
        for (e, hhmm) in [(scrap, 0900i64), (bare, 1000)] {
            s.commit(
                vec![Command::AddCell {
                    entity: e,
                    cell: Cell {
                        property: due,
                        value: CV::DateTime(DateTime {
                            civil: 2026_09_13_0000 + hhmm,
                            date_only: false,
                            end: None,
                        }),
                    },
                }],
                "due",
                Author::User,
            )
            .unwrap();
        }
    }

    liv_convert::convert(&log, &db).unwrap();
    unsafe { liv_view_close_all() };
    let c = CString::new(db.to_str().unwrap()).unwrap();

    let v = call(|out| unsafe { liv_view_day(c.as_ptr(), the_day, std::ptr::null(), out) })
        .unwrap();
    let blocks = v["blocks"].as_array().unwrap();
    assert_eq!(blocks.len(), 2, "both are on the day");

    // THE SCRAP CARRIES ITS WORDS ACROSS.
    assert_eq!(blocks[0]["row"]["title"], "call the roofer about the slates");
    assert_eq!(blocks[0]["row"]["untitled"], false);

    // AND A THING WITH NOTHING SAYS SO, rather than the surface inventing
    // words for it — which is what the shell drew, correctly.
    assert_eq!(blocks[1]["row"]["untitled"], true);
    assert_eq!(blocks[1]["row"]["title"], "");

    unsafe { liv_view_close_all() };
    let _ = std::fs::remove_dir_all(&dir);
}
