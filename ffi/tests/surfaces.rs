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
        // The user's own area, minted like any other piece of vocabulary.
        let health = e.declare(kind::AREA, "Health", 1_000).unwrap();
        let a = e.create(kind::TASK, Some("Dentist"), 1_000).unwrap();
        e.set(a, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, 14, 0), tz: 0 }), 1_001)
            .unwrap();
        e.set(a, prop::AREA, Value::Ref(health), 1_002).unwrap();
        let late = e.create(kind::TASK, Some("Overdue"), 1_003).unwrap();
        e.set(late, prop::DUE, Value::Date(DateSpec::Day(DAY - 2)), 1_004).unwrap();
        (a, health)
    };
    unsafe { liv_view_close_all() };

    let c = CString::new(path.to_str().unwrap()).unwrap();
    let v = call(|out| unsafe {
        liv_view_today(c.as_ptr(), at(DAY, 9, 0), 0, std::ptr::null(), out)
    })
    .unwrap();

    let day = &v["days"][0];
    assert_eq!(day["day"], DAY);
    assert_eq!(v["days"].as_array().unwrap().len(), 7, "the whole strip");
    assert_eq!(titles(&day["ahead"]), vec!["Dentist"]);
    assert_eq!(titles(&v["late"]), vec!["Overdue"]);
    assert_eq!(v["late"][0]["late"], true);
    assert!(day["passed"].as_array().unwrap().is_empty());
    assert_eq!(day["areas"][0]["name"], "Health");
    assert_eq!(day["areas"][0]["count"], 1);
    assert_eq!(day["unfiled"], 1, "the late one has no area");

    // AN ID SURVIVES THE ROUND TRIP as 32 hex characters — 16 bytes, which
    // a JSON number is not. The whole retrofit cost core-decisions.md
    // prices is avoided by the ABI being built for them from the start.
    let id = day["ahead"][0]["id"].as_str().unwrap();
    assert_eq!(id.len(), 32);
    assert_eq!(id, task_id.hex());
    assert_eq!(day["ahead"][0]["area"].as_str().unwrap(), area_id.hex());
    assert!(v["what_next"].as_array().unwrap().is_empty(), "both tasks have dates");

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
        call(|out| unsafe { liv_view_today(std::ptr::null(), 0, 0, std::ptr::null(), out) }),
        Err(LIV_ERR_PATH)
    );

    let nowhere = CString::new("/does/not/exist/at/all/liv.db").unwrap();
    assert_eq!(
        call(|out| unsafe { liv_view_today(nowhere.as_ptr(), 0, 0, std::ptr::null(), out) }),
        Err(LIV_ERR_OPEN)
    );

    let bad_id = CString::new("not-hex").unwrap();
    assert_eq!(
        call(|out| unsafe {
            liv_view_tasks(c.as_ptr(), bad_id.as_ptr(), DAY, std::ptr::null(), out)
        }),
        Err(LIV_ERR_ARG),
        "a project that is not an id is an argument error, not an unfiltered list"
    );
    let bad_lens = CString::new("{\"not\":\"an array\"}").unwrap();
    assert_eq!(
        call(|out| unsafe {
            liv_view_today(c.as_ptr(), 0, 0, bad_lens.as_ptr(), out)
        }),
        Err(LIV_ERR_ARG)
    );

    // And a null out-pointer is refused rather than written through.
    assert_eq!(
        unsafe { liv_view_today(c.as_ptr(), 0, 0, std::ptr::null(), std::ptr::null_mut()) },
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
        liv_view_library(c.as_ptr(), at(DAY, 9, 0), 0, std::ptr::null(), out)
    })
    .unwrap();
    assert!(v["all"].as_array().unwrap().is_empty());
    assert!(v["notes"].as_array().unwrap().is_empty());
    assert_eq!(v["counts"]["unsorted"], 0);
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

    // Every task the Tasks screen would list, whatever group it is in.
    let listed = |lens: *const std::ffi::c_char| -> Vec<String> {
        let v = call(|out| unsafe { liv_view_tasks(c.as_ptr(), std::ptr::null(), DAY, lens, out) })
            .unwrap();
        v["groups"].as_array().unwrap().iter().flat_map(|g| titles(&g["rows"])).collect()
    };
    assert_eq!(listed(std::ptr::null()).len(), 2);

    let none = CString::new("[]").unwrap();
    assert!(listed(none.as_ptr()).is_empty(), "an empty lens admits nothing");

    let one = CString::new(format!("[\"{}\"]", keep.hex())).unwrap();
    assert_eq!(listed(one.as_ptr()), vec!["Mine"]);
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
        liv_view_tasks(c.as_ptr(), std::ptr::null(), DAY, std::ptr::null(), out)
    })
    .unwrap();
    let groups = v["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 2, "To do and Done; the empty ones are not groups");
    assert_eq!(groups[0]["name"], "To do");
    assert_eq!(groups[0]["late"], 1, "the lateness is the group's fact, said once");
    assert_eq!(groups[0]["completes"], false);
    assert_eq!(groups[1]["name"], "Done");
    assert_eq!(groups[1]["completes"], true);
    assert_eq!(groups[1]["late"], 0);
    assert_eq!(titles(&groups[0]["rows"]), vec!["Order slates", "Call the roofer"]);

    // The screen's counts, and what the Project menu offers.
    assert_eq!(v["open"], 2);
    assert_eq!(v["late"], 1);
    assert_eq!(v["in_notes"].as_array().unwrap().len(), 0);
    assert_eq!(v["projects"][0]["id"], roof.hex());
    assert_eq!(v["projects"][0]["name"], "Roof");
    let late: Vec<bool> = groups[0]["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["late"].as_bool().unwrap())
        .collect();
    assert_eq!(late.iter().filter(|l| **l).count(), 1, "each row says whether it is late");

    // Filtering by project, by id.
    let id = CString::new(roof.hex()).unwrap();
    let v = call(|out| unsafe {
        liv_view_tasks(c.as_ptr(), id.as_ptr(), DAY, std::ptr::null(), out)
    })
    .unwrap();
    assert_eq!(v["groups"].as_array().unwrap().len(), 2);
    unsafe { liv_view_close_all() };
}

#[test]
fn the_calendar_comes_back_by_day() {
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

    let v = call(|out| unsafe { liv_view_day(c.as_ptr(), DAY - 3, DAY + 3, std::ptr::null(), out) })
        .unwrap();
    let days = v.as_array().unwrap();
    assert_eq!(days.len(), 1, "only a day with something on it");
    assert_eq!(days[0]["day"], DAY);
    assert_eq!(titles(&days[0]["all_day"]), vec!["Renew the passport"]);
    assert_eq!(titles(&days[0]["timed"]), vec!["clash 0", "clash 1"], "in time order");
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

    let all = || {
        let v = call(|out| unsafe {
            liv_view_library(c.as_ptr(), at(DAY, 9, 0), 0, std::ptr::null(), out)
        })
        .unwrap();
        titles(&v["all"])
    };
    assert_eq!(all(), vec!["First"]);

    // A write through a second handle on the same file, then the same
    // held connection is asked again.
    {
        let mut e = Engine::open_local(&path).unwrap();
        e.create(kind::NOTE, Some("Second"), 2_000).unwrap();
    }
    assert_eq!(all(), vec!["Second", "First"], "a held connection is not a stale one");
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
    assert_eq!(unsafe { liv_view_day(c.as_ptr(), DAY, DAY, std::ptr::null(), &mut out) }, LIV_OK);
    let day_bytes = unsafe { CStr::from_ptr(out) }.to_bytes().len();
    unsafe { liv_ffi::liv_string_free(out) };

    let mut out: *mut std::ffi::c_char = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_view_library(c.as_ptr(), at(DAY, 9, 0), 0, std::ptr::null(), &mut out) },
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
        let v = call(|out| unsafe { liv_view_day(cc.as_ptr(), DAY, DAY, std::ptr::null(), out) })
            .unwrap();
        assert_eq!(v[0]["timed"].as_array().unwrap().len(), 10);
    }
    unsafe { liv_view_close_all() };

    let once = |c: &CString| {
        let start = Instant::now();
        let mut out: *mut std::ffi::c_char = std::ptr::null_mut();
        assert_eq!(unsafe { liv_view_day(c.as_ptr(), DAY, DAY, std::ptr::null(), &mut out) }, LIV_OK);
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

/// **A capture has no name, and its title is its first line** — on a box
/// the engine made itself (2026-09-29).
///
/// Prompted by the first device run, which showed `First row: Untitled`.
/// It carries on the core-era converted-box test that went with `convert/`
/// in stage 5 (2026-09-29): a scrap caught as words lists as those words,
/// and a thing with neither a name nor a body reads as its kind and when —
/// never an empty string, never an id.
#[test]
fn a_scrap_made_on_the_engine_keeps_its_first_line_as_its_title() {
    let path = box_path("scrap_title");
    let day = days_from_civil(2026, 9, 13);
    {
        let mut e = Engine::open_local(&path).unwrap();
        let scrap = e.capture("call the roofer about the slates", at(day, 10, 0) as u64).unwrap();
        let bare = e.create(kind::TASK, None, at(day, 10, 30) as u64).unwrap();
        for (thing, hour) in [(scrap, 9), (bare, 10)] {
            let due = Value::Date(DateSpec::Instant { ms: at(day, hour, 0), tz: 0 });
            e.set(thing, prop::DUE, due, at(day, 11, 0) as u64).unwrap();
        }
    }
    unsafe { liv_view_close_all() };
    let c = CString::new(path.to_str().unwrap()).unwrap();

    let v = call(|out| unsafe { liv_view_day(c.as_ptr(), day, day, std::ptr::null(), out) })
        .unwrap();
    let timed = v[0]["timed"].as_array().unwrap();
    assert_eq!(timed.len(), 2, "both are on the day");

    assert_eq!(timed[0]["title"], "call the roofer about the slates");
    assert_eq!(timed[0]["untitled"], false);
    assert_eq!(timed[1]["untitled"], true, "still flagged, so it can draw quietly");
    assert_eq!(timed[1]["title"], "Task · 13 Sep 10:30");

    unsafe { liv_view_close_all() };
}

#[test]
fn the_library_answers_the_panel_and_its_two_lists() {
    let path = box_path("library");
    let (note, scrap, t) = {
        let mut e = Engine::open_local(&path).unwrap();
        let note = e.create(kind::NOTE, Some("A note"), 1_000).unwrap();
        let scrap = e.capture("a scrap", 1_001).unwrap();
        let t = e.create(kind::TASK, Some("A task"), 1_002).unwrap();
        e.set(t, prop::DUE, Value::Date(DateSpec::Day(DAY)), 1_003).unwrap();
        (note, scrap, t)
    };
    unsafe { liv_view_close_all() };
    let c = CString::new(path.to_str().unwrap()).unwrap();

    let v = call(|out| unsafe { liv_view_library(c.as_ptr(), at(DAY, 9, 0), 0, std::ptr::null(), out) })
        .unwrap();
    assert_eq!(titles(&v["all"]), vec!["A task", "a scrap", "A note"], "newest first");
    let ids = |key: &str| -> Vec<String> {
        v[key].as_array().unwrap().iter().map(|x| x.as_str().unwrap().to_owned()).collect()
    };
    assert_eq!(ids("notes"), vec![scrap.hex(), note.hex()], "pages only, last touched first");
    assert_eq!(ids("unsorted"), vec![t.hex(), scrap.hex(), note.hex()]);
    assert_eq!(v["counts"]["today"], 1);
    assert_eq!(v["counts"]["tasks"], 1);
    assert_eq!(v["counts"]["notes"], 2);
    assert_eq!(v["counts"]["unsorted"], 3);

    // A lens narrows Notes and the counts, never `all` or Unsorted.
    let lens = CString::new(format!("[\"{}\"]", note.hex())).unwrap();
    let v = call(|out| unsafe { liv_view_library(c.as_ptr(), at(DAY, 9, 0), 0, lens.as_ptr(), out) })
        .unwrap();
    assert_eq!(v["all"].as_array().unwrap().len(), 3);
    assert_eq!(v["notes"].as_array().unwrap().len(), 1);
    assert_eq!(v["unsorted"].as_array().unwrap().len(), 3);
    assert_eq!(v["counts"]["tasks"], 0);
    unsafe { liv_view_close_all() };
}

#[test]
fn the_reminders_come_back_soonest_first_with_a_count() {
    let path = box_path("reminders");
    {
        let mut e = Engine::open_local(&path).unwrap();
        for h in [15i64, 11, 13] {
            let t = e.create(kind::TASK, Some(&format!("{h}:00")), 1_000).unwrap();
            e.set(t, prop::DUE, Value::Date(DateSpec::Instant { ms: at(DAY, h, 0), tz: 0 }), 1_001)
                .unwrap();
        }
        let bare = e.create(kind::TASK, Some("A bare date"), 1_002).unwrap();
        e.set(bare, prop::DUE, Value::Date(DateSpec::Day(DAY + 1)), 1_003).unwrap();
    }
    unsafe { liv_view_close_all() };
    let c = CString::new(path.to_str().unwrap()).unwrap();
    let v = call(|out| unsafe { liv_view_reminders(c.as_ptr(), at(DAY, 9, 0), 0, 2, out) })
        .unwrap();
    assert_eq!(titles(&v["soonest"]), vec!["11:00", "13:00"], "soonest first, cut to the limit");
    assert_eq!(v["total"], 3, "and every one counted; the bare date does not ring");
    unsafe { liv_view_close_all() };
}

#[test]
fn the_search_screen_comes_back_as_rows_inside_the_lens() {
    use liv_ffi::finding::liv_view_search;
    let path = box_path("search_screen");
    let mine = {
        let mut e = Engine::open_local(&path).unwrap();
        let mine = e.create(kind::NOTE, Some("Roof"), 1_000).unwrap();
        e.create(kind::NOTE, Some("Roof tiles"), 1_001).unwrap();
        mine
    };
    unsafe { liv_view_close_all() };
    let c = CString::new(path.to_str().unwrap()).unwrap();
    let q = CString::new("roof").unwrap();

    let v = call(|out| unsafe { liv_view_search(c.as_ptr(), q.as_ptr(), 0, std::ptr::null(), out) })
        .unwrap();
    assert_eq!(titles(&v["hits"]), vec!["Roof", "Roof tiles"]);
    assert_eq!(v["total"], 2);
    assert_eq!(v["exact"], true, "one is called exactly that");

    let lens = CString::new(format!("[\"{}\"]", mine.hex())).unwrap();
    let v = call(|out| unsafe { liv_view_search(c.as_ptr(), q.as_ptr(), 0, lens.as_ptr(), out) })
        .unwrap();
    assert_eq!(titles(&v["hits"]), vec!["Roof"]);
    assert_eq!(v["total"], 1);

    let bad = CString::new("not a list").unwrap();
    assert_eq!(
        call(|out| unsafe { liv_view_search(c.as_ptr(), q.as_ptr(), 0, bad.as_ptr(), out) }),
        Err(LIV_ERR_ARG)
    );
    unsafe { liv_view_close_all() };
}

/// **ONE REFRESH STAYS LINEAR IN THE BOX** (standing rule 2; 2026-09-29).
///
/// What the app pays after every action is not one read but several — the
/// ones `BoxModel.loadEverything` makes once every screen has been opened:
/// the library (every row, Notes, Unsorted and the panel's counts), the
/// reminders, the trash, the clerk's sweep, the workspaces, the assist
/// switch, the property list, the kinds, and the screens that ask for
/// themselves — Tasks (which carries the checkbox lines in notes), Today,
/// and the Calendar's three months. It replaces `ffi/src/tests.rs
/// the_snapshot_stays_linear_in_box_size`, which timed the core
/// `liv_snapshot` those eight replaced, and goes with `core/` in stage 5.
///
/// Notes carry DISTINCT names and bodies the clerk reads — a date word and
/// a name it can mention — so a proposer that turned quadratic would show.
#[test]
fn one_refresh_stays_linear_in_the_box() {
    use liv_ffi::basics::{liv_kinds, liv_properties};
    use liv_ffi::finding::{liv_assist, liv_view_trash, liv_workspaces};
    use liv_ffi::writes::liv_sweep;

    fn boxed(name: &str, notes: u64) -> std::path::PathBuf {
        let path = box_path(name);
        let mut e = Engine::open_local(&path).unwrap();
        e.create(kind::PERSON, Some("Anna"), 1_000).unwrap();
        let roof = e.create(kind::PROJECT, Some("Roof"), 1_001).unwrap();
        for i in 0..notes {
            let id = e.create(kind::NOTE, Some(&format!("note number {i}")), 2_000 + i).unwrap();
            let words = format!("Call Anna about part {i} of the rebuild, due friday.");
            e.set_content(id, vec![Span::Text(TextSpan::plain(words))], 0, 2_000 + i).unwrap();
            // And a task beside every other note, dated and filed, so
            // the Tasks screen has groups, lateness and projects to count.
            if i % 2 == 0 {
                let t = e.create(kind::TASK, Some(&format!("task {i}")), 3_000 + i).unwrap();
                let due = DAY - 5 + (i % 10) as i32;
                e.set(t, prop::DUE, Value::Date(DateSpec::Day(due)), 3_000 + i).unwrap();
                e.set(t, prop::PROJECT, Value::Ref(roof), 3_000 + i).unwrap();
            }
        }
        path
    }
    let small = boxed("refresh_small", 200);
    let large = boxed("refresh_large", 400);
    unsafe { liv_view_close_all() };

    let refresh = |path: &std::path::Path| {
        let p = CString::new(path.to_str().unwrap()).unwrap();
        let start = std::time::Instant::now();
        call(|out| unsafe { liv_view_library(p.as_ptr(), at(DAY, 9, 0), 0, std::ptr::null(), out) })
            .unwrap();
        call(|out| unsafe { liv_view_reminders(p.as_ptr(), at(DAY, 9, 0), 0, 64, out) })
            .unwrap();
        call(|out| unsafe { liv_view_trash(p.as_ptr(), out) }).unwrap();
        call(|out| unsafe { liv_sweep(p.as_ptr(), out) }).unwrap();
        call(|out| unsafe { liv_workspaces(p.as_ptr(), out) }).unwrap();
        call(|out| unsafe {
            liv_view_tasks(p.as_ptr(), std::ptr::null(), DAY, std::ptr::null(), out)
        })
        .unwrap();
        call(|out| unsafe { liv_view_today(p.as_ptr(), at(DAY, 9, 0), 0, std::ptr::null(), out) })
            .unwrap();
        call(|out| unsafe { liv_view_day(p.as_ptr(), DAY - 40, DAY + 60, std::ptr::null(), out) })
            .unwrap();
        call(|out| unsafe { liv_assist(p.as_ptr(), out) }).unwrap();
        call(|out| unsafe { liv_properties(p.as_ptr(), out) }).unwrap();
        call(|out| unsafe { liv_kinds(p.as_ptr(), out) }).unwrap();
        start.elapsed()
    };
    // Warm both, then interleaved rounds, best ratio — reads repeat.
    refresh(&small);
    refresh(&large);
    let ratio = (0..5)
        .map(|_| {
            let s = refresh(&small);
            let l = refresh(&large);
            l.as_secs_f64() / s.as_secs_f64().max(1e-9)
        })
        .fold(f64::INFINITY, f64::min);
    unsafe { liv_view_close_all() };
    let _ = std::fs::remove_dir_all(small.parent().unwrap());
    let _ = std::fs::remove_dir_all(large.parent().unwrap());
    assert!(ratio < 2.8, "doubling the box multiplied one refresh by {ratio:.2}x");
}
