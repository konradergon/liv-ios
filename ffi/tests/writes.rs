//! The write verbs across the C ABI, and the span JSON that crosses with
//! them.
//!
//! **The span shapes here are the shell's, verbatim.** They are copied
//! from what `Editor.swift`'s `SpanJSON` encoder produces — which is
//! itself pinned against the JSON in `core/src/value.rs`'s own tests — so
//! if this file and that encoder ever disagree, the editor stops being
//! able to save. That is the whole reason these are literal strings
//! rather than something generated from the Rust types.

use std::ffi::{CStr, CString};

use liv_engine::{kind, Engine};
use liv_ffi::surfaces::{liv_view_close_all, LIV_ERR_ARG, LIV_OK};
use liv_ffi::writes::*;
use serde_json::Value as J;

const T0: u64 = 1_789_257_600_000;

fn dir(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("liv_ffi_writes_{name}"));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn c(s: &str) -> CString {
    CString::new(s).unwrap()
}

/// Read an out-pointer and free it, the way a caller must.
fn took(out: *mut std::ffi::c_char) -> J {
    assert!(!out.is_null(), "LIV_OK with no payload");
    let json = unsafe { CStr::from_ptr(out) }.to_str().unwrap().to_owned();
    unsafe { liv_ffi::liv_string_free(out) };
    serde_json::from_str(&json).unwrap()
}

/// A box with one note in it, and the paths to reach it.
fn box_with_a_note(name: &str) -> (std::path::PathBuf, CString, String) {
    let d = dir(name);
    let path = d.join("liv.db");
    let id = {
        let mut e = Engine::open_local(&path).unwrap();
        e.create(kind::NOTE, Some("Roof"), T0).unwrap().hex()
    };
    // The verbs hold their own connection; the one above must be closed
    // or the two writers race for the same file.
    unsafe { liv_view_close_all() };
    let cpath = c(path.to_str().unwrap());
    (d, cpath, id)
}

// ---- the editor's round trip -------------------------------------------

#[test]
fn a_body_goes_out_and_comes_back_in_the_shells_own_json() {
    let (d, path, id) = box_with_a_note("body");
    let id = c(&id);

    // Exactly what `SpanJSON.encode` writes: an unmarked run is a BARE
    // STRING, a unit block is a bare string, a payload block is a one-key
    // object, and marks ride alongside the text.
    let spans = r#"[
        {"Break":{"Heading":2}},
        {"Text":"Roof"},
        {"Break":"Body"},
        {"Text":{"text":"call the surveyor","marks":1}},
        {"Break":{"Task":{"depth":0,"done":false}}},
        {"Text":"book the ferry"},
        {"Break":{"Code":{"lang":"rust"}}},
        {"Break":{"Callout":{"kind":"warning"}}},
        {"Break":"Rule"}
    ]"#;

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_write_body(path.as_ptr(), id.as_ptr(), c(spans).as_ptr(), 0, T0, &mut out) },
        LIV_OK
    );
    let print = took(out)["print"].as_u64().unwrap();
    assert_ne!(print, 0);

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_read_body(path.as_ptr(), id.as_ptr(), &mut out) }, LIV_OK);
    let back = took(out);
    assert_eq!(back["print"].as_u64().unwrap(), print);

    // The same document, span for span, in the same spellings.
    let want: J = serde_json::from_str(spans).unwrap();
    assert_eq!(back["spans"], want);

    let _ = std::fs::remove_dir_all(&d);
}

/// **A `Ref` crosses as HEX, and the shell already reads that.** `LivID`'s
/// decoder was built in slice 4 to accept a JSON number or 32 hex
/// characters, and its encoder writes hex — so the editor round-trips
/// through these verbs with no Swift change.
#[test]
fn a_link_in_a_body_crosses_as_hex() {
    let (d, path, id) = box_with_a_note("ref");
    let target = {
        let mut e = Engine::open_local(&std::path::Path::new(&d).join("liv.db")).unwrap();
        e.create(kind::NOTE, Some("Ferry times"), T0 + 1).unwrap().hex()
    };
    unsafe { liv_view_close_all() };
    let id = c(&id);

    let spans = format!(r#"[{{"Text":"see "}},{{"Ref":"{target}"}}]"#);
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_write_body(path.as_ptr(), id.as_ptr(), c(&spans).as_ptr(), 0, T0 + 2, &mut out) },
        LIV_OK
    );
    took(out);

    let mut out = std::ptr::null_mut();
    unsafe { liv_read_body(path.as_ptr(), id.as_ptr(), &mut out) };
    assert_eq!(took(out)["spans"][1]["Ref"].as_str().unwrap(), target);

    // And it is a real link, both ways.
    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_links(path.as_ptr(), id.as_ptr(), &mut out) }, LIV_OK);
    let links = took(out);
    assert_eq!(links["out"][0].as_str().unwrap(), target);

    let mut out = std::ptr::null_mut();
    unsafe { liv_links(path.as_ptr(), c(&target).as_ptr(), &mut out) };
    assert_eq!(took(out)["in"][0].as_str().unwrap(), id.to_str().unwrap());

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_save_against_a_moved_body_is_told_apart_from_a_refusal() {
    let (d, path, id) = box_with_a_note("stale");
    let id = c(&id);
    let one = c(r#"[{"Text":"one"}]"#);
    let two = c(r#"[{"Text":"two"}]"#);

    let mut out = std::ptr::null_mut();
    unsafe { liv_write_body(path.as_ptr(), id.as_ptr(), one.as_ptr(), 0, T0, &mut out) };
    let first = took(out)["print"].as_u64().unwrap();

    let mut out = std::ptr::null_mut();
    unsafe { liv_write_body(path.as_ptr(), id.as_ptr(), two.as_ptr(), first, T0 + 1, &mut out) };
    took(out);

    // Our editor still holds `first`.
    let mut out = std::ptr::null_mut();
    let code =
        unsafe { liv_write_body(path.as_ptr(), id.as_ptr(), one.as_ptr(), first, T0 + 2, &mut out) };
    assert_eq!(code, LIV_ERR_STALE, "re-read, never overwrite");

    // A link to nothing is a different failure, and says so.
    let ghost = "99999999999999999999999999999999";
    let bad = c(&format!(r#"[{{"Ref":"{ghost}"}}]"#));
    let mut out = std::ptr::null_mut();
    let fresh = {
        let mut o = std::ptr::null_mut();
        unsafe { liv_read_body(path.as_ptr(), id.as_ptr(), &mut o) };
        took(o)["print"].as_u64().unwrap()
    };
    assert_eq!(
        unsafe { liv_write_body(path.as_ptr(), id.as_ptr(), bad.as_ptr(), fresh, T0 + 3, &mut out) },
        LIV_ERR_REFUSED
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// **A span this build does not understand is refused, not dropped.** The
/// old codec kept an unknown block as `.other` and flattened it on save,
/// which is a decision about someone's writing that a wire decoder should
/// not make. Here the save fails and the editor still holds the text.
#[test]
fn nonsense_span_json_is_an_argument_error_and_writes_nothing() {
    let (d, path, id) = box_with_a_note("nonsense");
    let id = c(&id);

    for bad in [
        r#"{"Text":"not an array"}"#,
        r#"[{"Wat":"a span kind from the future"}]"#,
        r#"[{"Break":"Interlude"}]"#,
        r#"[{"Break":{"Heading":9}}]"#,
        r#"[{"Text":{"text":"x","marks":16}}]"#,
        "not json at all",
    ] {
        let mut out = std::ptr::null_mut();
        let code =
            unsafe { liv_write_body(path.as_ptr(), id.as_ptr(), c(bad).as_ptr(), 0, T0, &mut out) };
        assert_eq!(code, LIV_ERR_ARG, "{bad}");
    }

    let mut out = std::ptr::null_mut();
    unsafe { liv_read_body(path.as_ptr(), id.as_ptr(), &mut out) };
    let back = took(out);
    assert_eq!(back["print"].as_u64().unwrap(), 0, "and the body is still empty");

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn history_comes_back_newest_first_with_its_spans() {
    let (d, path, id) = box_with_a_note("history");
    let id = c(&id);

    let mut print = 0u64;
    for (n, text) in ["one", "two", "three"].iter().enumerate() {
        let spans = c(&format!(r#"[{{"Text":"{text}"}}]"#));
        let mut out = std::ptr::null_mut();
        unsafe {
            liv_write_body(path.as_ptr(), id.as_ptr(), spans.as_ptr(), print, T0 + n as u64, &mut out)
        };
        print = took(out)["print"].as_u64().unwrap();
    }

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_body_history(path.as_ptr(), id.as_ptr(), &mut out) }, LIV_OK);
    let h = took(out);
    let words: Vec<&str> =
        h.as_array().unwrap().iter().map(|v| v["spans"][0]["Text"].as_str().unwrap()).collect();
    assert_eq!(words, vec!["three", "two", "one"]);
    assert_eq!(h[0]["author"].as_str().unwrap(), "user");
    assert_eq!(h[0]["seq"].as_u64().unwrap() > 0, true);

    let _ = std::fs::remove_dir_all(&d);
}

// ---- undo --------------------------------------------------------------

#[test]
fn undo_and_redo_over_the_abi() {
    let (d, path, id) = box_with_a_note("undo");
    let id = c(&id);
    let one = c(r#"[{"Text":"one"}]"#);
    let two = c(r#"[{"Text":"two"}]"#);

    let mut out = std::ptr::null_mut();
    unsafe { liv_write_body(path.as_ptr(), id.as_ptr(), one.as_ptr(), 0, T0, &mut out) };
    let first = took(out)["print"].as_u64().unwrap();
    let mut out = std::ptr::null_mut();
    unsafe { liv_write_body(path.as_ptr(), id.as_ptr(), two.as_ptr(), first, T0 + 1, &mut out) };
    took(out);

    let mut out = std::ptr::null_mut();
    unsafe { liv_undo_state(path.as_ptr(), &mut out) };
    let state = took(out);
    assert!(state["undo"].as_bool().unwrap() && !state["redo"].as_bool().unwrap());

    assert_eq!(unsafe { liv_undo(path.as_ptr(), T0 + 2) }, LIV_OK);
    let mut out = std::ptr::null_mut();
    unsafe { liv_read_body(path.as_ptr(), id.as_ptr(), &mut out) };
    assert_eq!(took(out)["spans"][0]["Text"].as_str().unwrap(), "one");

    let mut out = std::ptr::null_mut();
    unsafe { liv_undo_state(path.as_ptr(), &mut out) };
    assert!(took(out)["redo"].as_bool().unwrap(), "and redo is live now");

    assert_eq!(unsafe { liv_redo(path.as_ptr(), T0 + 3) }, LIV_OK);
    let mut out = std::ptr::null_mut();
    unsafe { liv_read_body(path.as_ptr(), id.as_ptr(), &mut out) };
    assert_eq!(took(out)["spans"][0]["Text"].as_str().unwrap(), "two");

    let _ = std::fs::remove_dir_all(&d);
}

/// **Nothing to undo is an answer, not a failure.** A shell asking on a
/// fresh box is not a shell doing anything wrong, and the old ABI's one
/// zero could not tell the two apart.
#[test]
fn nothing_to_undo_has_its_own_code() {
    let d = dir("empty");
    let path = d.join("liv.db");
    { Engine::open_local(&path).unwrap(); }
    unsafe { liv_view_close_all() };
    let path = c(path.to_str().unwrap());

    assert_eq!(unsafe { liv_undo(path.as_ptr(), T0) }, LIV_ERR_NOTHING);
    assert_eq!(unsafe { liv_redo(path.as_ptr(), T0) }, LIV_ERR_NOTHING);

    let _ = std::fs::remove_dir_all(&d);
}

// ---- the clerk ---------------------------------------------------------

/// A proposal is named by its FINGERPRINT, not its position: the sweep is
/// recomputed in every process, so an index would mean something else by
/// the time the user tapped it.
#[test]
fn a_suggestion_is_accepted_by_fingerprint() {
    let d = dir("clerk");
    let path = d.join("liv.db");
    let scrap = {
        let mut e = Engine::open_local(&path).unwrap();
        e.create(kind::PERSON, Some("Anna"), T0).unwrap();
        let scrap = e.create(kind::NOTE, None, T0 + 1).unwrap();
        e.set_content(scrap, vec![liv_engine::Span::text("call anna tomorrow")], 0, T0 + 2)
            .unwrap();
        scrap.hex()
    };
    unsafe { liv_view_close_all() };
    let path = c(path.to_str().unwrap());

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_sweep(path.as_ptr(), &mut out) }, LIV_OK);
    let found = took(out);
    let rows = found.as_array().unwrap();
    assert!(rows.len() >= 2, "a date and a mention: {rows:?}");
    assert!(rows.iter().all(|r| r["entity"].as_str() == Some(scrap.as_str())));

    let dated = rows.iter().find(|r| r["proposer"] == "dates").unwrap();
    let print = dated["print"].as_u64().unwrap();
    assert!(dated["reason"].as_str().unwrap().contains("tomorrow"));

    assert_eq!(unsafe { liv_accept(path.as_ptr(), print, T0 + 3) }, LIV_OK);

    // Taken, so no longer suggested.
    let mut out = std::ptr::null_mut();
    unsafe { liv_sweep(path.as_ptr(), &mut out) };
    let after = took(out);
    assert!(after.as_array().unwrap().iter().all(|r| r["proposer"] != "dates"));

    // And accepting it again has nothing to accept.
    assert_eq!(unsafe { liv_accept(path.as_ptr(), print, T0 + 4) }, LIV_ERR_NOTHING);

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn declining_is_not_forgetting() {
    let d = dir("decline");
    let path = d.join("liv.db");
    {
        let mut e = Engine::open_local(&path).unwrap();
        e.create(kind::PERSON, Some("Anna"), T0).unwrap();
        let scrap = e.create(kind::NOTE, None, T0 + 1).unwrap();
        e.set_content(scrap, vec![liv_engine::Span::text("call anna tomorrow")], 0, T0 + 2)
            .unwrap();
    }
    unsafe { liv_view_close_all() };
    let path = c(path.to_str().unwrap());

    let mut out = std::ptr::null_mut();
    unsafe { liv_sweep(path.as_ptr(), &mut out) };
    let rows = took(out);
    let before = rows.as_array().unwrap().len();
    let print = rows[0]["print"].as_u64().unwrap();

    assert_eq!(unsafe { liv_decline(path.as_ptr(), print) }, LIV_OK);

    let mut out = std::ptr::null_mut();
    unsafe { liv_sweep(path.as_ptr(), &mut out) };
    assert_eq!(took(out).as_array().unwrap().len(), before - 1, "and nothing asks twice");

    let _ = std::fs::remove_dir_all(&d);
}

// ---- vocabulary and files ----------------------------------------------

#[test]
fn renaming_a_value_reports_its_carriers() {
    let d = dir("rename");
    let path = d.join("liv.db");
    let field = {
        let mut e = Engine::open_local(&path).unwrap();
        let field = e.declare_field("client", "text", false, T0).unwrap();
        for i in 0..3 {
            let t = e.create(kind::TASK, Some(&format!("task {i}")), T0 + 1 + i).unwrap();
            e.set(t, field, liv_engine::Value::Text("Acme".into()), T0 + 1 + i).unwrap();
        }
        field.hex()
    };
    unsafe { liv_view_close_all() };
    let path = c(path.to_str().unwrap());
    let field = c(&field);

    let mut out = std::ptr::null_mut();
    let code = unsafe {
        liv_rename_value(
            path.as_ptr(),
            field.as_ptr(),
            c("Acme").as_ptr(),
            c("Acme Ltd").as_ptr(),
            T0 + 10,
            &mut out,
        )
    };
    assert_eq!(code, LIV_OK);
    assert_eq!(took(out)["carriers"].as_u64().unwrap(), 3);

    // An unchanged name is a refusal a person reads, not a crash.
    let mut out = std::ptr::null_mut();
    let code = unsafe {
        liv_rename_value(
            path.as_ptr(),
            field.as_ptr(),
            c("Acme Ltd").as_ptr(),
            c("Acme Ltd").as_ptr(),
            T0 + 11,
            &mut out,
        )
    };
    assert_eq!(code, LIV_ERR_REFUSED);

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_file_is_added_by_reference_and_resyncs() {
    let d = dir("file");
    let path = d.join("liv.db");
    { Engine::open_local(&path).unwrap(); }
    unsafe { liv_view_close_all() };
    let doc = d.join("invoice.pdf");
    std::fs::write(&doc, "first bytes").unwrap();
    let path = c(path.to_str().unwrap());
    let doc_s = doc.to_string_lossy().into_owned();

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_add_file(path.as_ptr(), c(&doc_s).as_ptr(), T0, &mut out) },
        LIV_OK
    );
    let id = took(out)["id"].as_str().unwrap().to_owned();
    let id = c(&id);
    assert_eq!(std::fs::read_to_string(&doc).unwrap(), "first bytes", "never moved");

    let mut out = std::ptr::null_mut();
    unsafe { liv_resync_file(path.as_ptr(), id.as_ptr(), T0 + 1, &mut out) };
    let r = took(out);
    assert_eq!(r["state"].as_str().unwrap(), "unchanged");
    assert_eq!(r["path"].as_str().unwrap(), doc_s);

    std::fs::write(&doc, "second bytes").unwrap();
    let mut out = std::ptr::null_mut();
    unsafe { liv_resync_file(path.as_ptr(), id.as_ptr(), T0 + 2, &mut out) };
    assert_eq!(took(out)["state"].as_str().unwrap(), "changed");

    std::fs::remove_file(&doc).unwrap();
    let mut out = std::ptr::null_mut();
    unsafe { liv_resync_file(path.as_ptr(), id.as_ptr(), T0 + 3, &mut out) };
    assert_eq!(took(out)["state"].as_str().unwrap(), "broken");

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_add_file(path.as_ptr(), c("/no/such/file").as_ptr(), T0 + 4, &mut out) },
        LIV_ERR_REFUSED,
        "an unreadable path is never a phantom entity"
    );

    let _ = std::fs::remove_dir_all(&d);
}

// ---- the error channel -------------------------------------------------

#[test]
fn a_bad_id_is_an_argument_error_and_never_a_panic() {
    let (d, path, _) = box_with_a_note("badid");
    for bad in ["", "abc", "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"] {
        let mut out = std::ptr::null_mut();
        assert_eq!(
            unsafe { liv_read_body(path.as_ptr(), c(bad).as_ptr(), &mut out) },
            LIV_ERR_ARG,
            "{bad}"
        );
        assert!(out.is_null(), "a refused call delivers nothing to free");
    }
    let _ = std::fs::remove_dir_all(&d);
}

// ---- what a write costs -------------------------------------------------

/// A box of `n` quiet notes, plus one scrap the clerk has something to say
/// about. Returns the box path.
fn box_of(name: &str, n: u64) -> (std::path::PathBuf, CString) {
    let d = dir(name);
    let path = d.join("liv.db");
    {
        let mut e = Engine::open_local(&path).unwrap();
        e.create(kind::PERSON, Some("Anna"), T0).unwrap();
        for i in 0..n {
            let id = e.create(kind::NOTE, Some(&format!("note {i}")), T0 + i).unwrap();
            e.set_content(
                id,
                vec![liv_engine::Span::text("a few words about the roof and nothing else")],
                0,
                T0 + i,
            )
            .unwrap();
        }
        let scrap = e.create(kind::NOTE, None, T0 + n + 1).unwrap();
        e.set_content(scrap, vec![liv_engine::Span::text("call anna tomorrow")], 0, T0 + n + 2)
            .unwrap();
    }
    unsafe { liv_view_close_all() };
    let c = c(path.to_str().unwrap());
    (d, c)
}

fn one_date_print(path: &CString) -> u64 {
    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_sweep(path.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    rows.as_array()
        .unwrap()
        .iter()
        .find(|r| r["proposer"] == "dates")
        .expect("the clerk should still see the date")["print"]
        .as_u64()
        .unwrap()
}

/// **Accepting one suggestion costs one sweep, and a sweep costs the box.**
///
/// This is the design, not an accident: a proposal is named by its
/// fingerprint, so `accept` re-runs the sweep to find it, and a proposal
/// the box no longer makes is one the user already acted on. The price is
/// that every tap in the inbox re-reads the box.
///
/// What that price IS, measured here on 2026-09-13 in a debug build: a
/// 50-note box accepts in 14 ms, a 500-note box in 120 ms. Ten times the
/// box, ten times the work — linear, which is the shape a sweep has to
/// have, and nothing worse. **But twenty taps through the inbox of a
/// 500-note box is two and a half seconds of sweeping**, and that is a
/// product question (batch the accepts, or cache a sweep per box
/// generation) rather than a defect in these verbs. This test exists to
/// keep the shape linear until that question is answered.
///
/// A ratio, never a millisecond budget — a ratio survives a slow machine.
#[test]
fn accepting_costs_one_sweep_and_does_not_go_quadratic() {
    use std::time::Instant;
    let (ds, small) = box_of("cost_small", 50);
    let (dl, large) = box_of("cost_large", 500);

    // The sweep-and-find is all `accept` does before its one write, and it
    // is the part that touches the box, so it is the part to pin.
    let sweep_once = |p: &CString| {
        let t = Instant::now();
        let mut out = std::ptr::null_mut();
        assert_eq!(unsafe { liv_sweep(p.as_ptr(), &mut out) }, LIV_OK);
        took(out);
        t.elapsed().as_secs_f64()
    };
    let best = (0..6)
        .map(|_| sweep_once(&large) / sweep_once(&small).max(1e-9))
        .fold(f64::INFINITY, f64::min);

    // Measured 9.5x for a ten-times box. The ceiling matches
    // surface/tests/sweep_cost.rs, which measured the same shape from the
    // other side and found 9.3x with the word index and 18.5x without —
    // so 14 sits between them, and a threshold nobody measured is a
    // threshold that passes.
    assert!(best < 14.0, "accept's sweep went superlinear in the box: {best:.1}x");

    // And the accept itself lands, in both sizes.
    for p in [&small, &large] {
        let print = one_date_print(p);
        assert_eq!(unsafe { liv_accept(p.as_ptr(), print, T0 + 9_000) }, LIV_OK);
        assert_eq!(
            unsafe { liv_accept(p.as_ptr(), print, T0 + 9_001) },
            LIV_ERR_NOTHING,
            "and a proposal the box no longer makes is not written twice"
        );
    }

    let _ = std::fs::remove_dir_all(&ds);
    let _ = std::fs::remove_dir_all(&dl);
}
