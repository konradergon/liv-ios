//! Finding things across the C ABI: search, the grammar, the furniture.
//!
//! `surface/src/search.rs` and `engine/src/query.rs` were both built and
//! tested and neither had a door. These are the doors, and the cases
//! here are the ones where a door can be wrong in a way the layer below
//! it cannot see.

use std::ffi::{CStr, CString};

use liv_engine::{area, kind, prop, status, Engine, Span, Value};
use liv_ffi::finding::*;
use liv_ffi::surfaces::{liv_view_close_all, LIV_ERR_ARG, LIV_OK};
use serde_json::Value as J;

const T0: u64 = 1_789_257_600_000;

fn dir(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("liv_ffi_finding_{name}"));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn c(s: &str) -> CString {
    CString::new(s).unwrap()
}

fn took(out: *mut std::ffi::c_char) -> J {
    assert!(!out.is_null(), "LIV_OK with no payload");
    let json = unsafe { CStr::from_ptr(out) }.to_str().unwrap().to_owned();
    unsafe { liv_ffi::liv_string_free(out) };
    serde_json::from_str(&json).unwrap()
}

/// A box with a few things worth finding.
fn stocked(name: &str) -> (std::path::PathBuf, CString) {
    let d = dir(name);
    let path = d.join("liv.db");
    {
        let mut e = Engine::open_local(&path).unwrap();
        let roof = e.create(kind::TASK, Some("Fix the roof"), T0).unwrap();
        e.set(roof, prop::AREA, Value::Ref(area::HOME), T0).unwrap();
        e.set(roof, prop::STATUS, Value::Ref(status::TODO), T0).unwrap();

        let ferry = e.create(kind::TASK, Some("Book the ferry"), T0 + 1).unwrap();
        e.set(ferry, prop::AREA, Value::Ref(area::HOME), T0 + 1).unwrap();
        e.set(ferry, prop::STATUS, Value::Ref(status::DONE), T0 + 1).unwrap();

        let invoice = e.create(kind::TASK, Some("Send the invoice"), T0 + 2).unwrap();
        e.set(invoice, prop::AREA, Value::Ref(area::WORK), T0 + 2).unwrap();

        // Something whose only match is in its body.
        let note = e.create(kind::NOTE, Some("Saturday"), T0 + 3).unwrap();
        e.set_content(note, vec![Span::text("the roof needs a surveyor")], 0, T0 + 3).unwrap();

        // And something archived, which is what tells the two modes apart.
        let old = e.create(kind::TASK, Some("Old roof job"), T0 + 4).unwrap();
        e.set(old, prop::ARCHIVED, Value::Bool(true), T0 + 4).unwrap();
    }
    unsafe { liv_view_close_all() };
    let p = c(path.to_str().unwrap());
    (d, p)
}

fn hits(v: &J) -> Vec<String> {
    v["hits"].as_array().unwrap().iter().map(|h| h["id"].as_str().unwrap().to_owned()).collect()
}

fn search(path: &CString, q: &str, limit: u32) -> J {
    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_search(path.as_ptr(), c(q).as_ptr(), limit, &mut out) }, LIV_OK, "{q}");
    took(out)
}

// ---- search ------------------------------------------------------------

#[test]
fn a_search_ranks_its_hits_and_says_where_each_matched() {
    let (d, path) = stocked("rank");
    let found = search(&path, "roof", 0);

    let rows = found["hits"].as_array().unwrap();
    assert!(rows.len() >= 2, "the name and the body: {found}");

    // A name match outranks a body match, and each says which it was, so
    // a row can hint why it is in the list.
    assert_eq!(rows[0]["field"].as_str().unwrap(), "name");
    assert!(rows.iter().any(|h| h["field"] == "content"), "the body hit is there too");
    let scores: Vec<f64> = rows.iter().map(|h| h["score"].as_f64().unwrap()).collect();
    let mut sorted = scores.clone();
    sorted.sort_by(|a, b| b.partial_cmp(a).unwrap());
    assert_eq!(scores, sorted, "hits come back ranked");

    let _ = std::fs::remove_dir_all(&d);
}

/// **`limit` bounds the hits and never the facets.**
///
/// A facet count is over everything the query matches. A row saying
/// "Home 2" while the list shows one is telling the truth about the box;
/// a count that changed with how far the user had scrolled would be
/// useless for pivoting, which is the one thing a facet row is for.
#[test]
fn a_limit_cuts_the_list_and_leaves_the_counts_honest() {
    let (d, path) = stocked("limit");

    let all = search(&path, "the", 0);
    let capped = search(&path, "the", 1);
    assert!(all["hits"].as_array().unwrap().len() > 1);
    assert_eq!(capped["hits"].as_array().unwrap().len(), 1);

    let count_of = |v: &J, label: &str| -> Option<u64> {
        v["facets"].as_array()?.iter().find_map(|f| {
            f["values"].as_array()?.iter().find(|x| x["label"] == label)?["count"].as_u64()
        })
    };
    assert_eq!(
        count_of(&capped, "Home"),
        count_of(&all, "Home"),
        "the count is over the box, not over the page"
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// **A search box WIDENS and a lens RESTRICTS**, on the same text.
///
/// `is:archived` means "look in the archive too" when someone is hunting
/// for a thing, and "only archived things" when it is a filter. One
/// grammar, told which job it is doing — and the easiest thing in this
/// file to get backwards, because both readings return rows.
#[test]
fn the_same_words_widen_a_search_and_restrict_a_lens() {
    let (d, path) = stocked("modes");

    // Searching: the archived one joins the live ones.
    let widened = search(&path, "roof is:archived", 0);
    let names = hits(&widened);
    assert!(names.len() >= 2, "the archive is added, not swapped in: {widened}");

    // Lensing: only the archived one.
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_lens(path.as_ptr(), c("roof is:archived").as_ptr(), &mut out) },
        LIV_OK
    );
    let lens = took(out);
    let ids = lens["ids"].as_array().unwrap();
    assert_eq!(ids.len(), 1, "a lens is a boundary: {lens}");
    assert!(names.contains(&ids[0].as_str().unwrap().to_owned()), "and it is one of the same");

    // A lens hands back its terms so the shell draws chips without
    // parsing the text itself.
    let terms = lens["terms"].as_array().unwrap();
    assert!(terms.iter().any(|t| t["op"] == "is" && t["value"] == "archived"));

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_qualifier_narrows_and_a_facet_says_what_else_it_could_be() {
    let (d, path) = stocked("facets");
    let found = search(&path, "area:home", 0);
    assert_eq!(found["hits"].as_array().unwrap().len(), 2, "{found}");

    let areas = found["facets"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["label"] == "area")
        .unwrap_or_else(|| panic!("no area facet in {found}"));
    let home = areas["values"].as_array().unwrap().iter().find(|v| v["label"] == "Home").unwrap();
    assert_eq!(home["active"], true, "the chip reads as chosen");

    // **The count excludes this property's own constraints**, or a facet
    // you have already picked shows its own count and nothing else, and
    // there is no way to pivot to a sibling.
    let work = areas["values"].as_array().unwrap().iter().find(|v| v["label"] == "Work");
    assert!(work.is_some(), "the sibling is still offered: {areas}");
    assert_eq!(work.unwrap()["count"].as_u64().unwrap(), 1);
    assert_eq!(work.unwrap()["active"], false);

    let _ = std::fs::remove_dir_all(&d);
}

/// A typo shows nothing (owner, 2026-08-27). A bare word is REQUIRED,
/// never quietly dropped to salvage some results.
#[test]
fn a_word_that_matches_nothing_finds_nothing() {
    let (d, path) = stocked("typo");
    assert!(search(&path, "rooof", 0)["hits"].as_array().unwrap().is_empty());
    assert!(search(&path, "roof zzzz", 0)["hits"].as_array().unwrap().is_empty(), "ANDed");
    let _ = std::fs::remove_dir_all(&d);
}

// ---- the grammar as chips ----------------------------------------------

/// **Standing rule 5: a user never types a query language.** This is how
/// a stored filter becomes chips a person edits by tapping, and how the
/// chips become text again.
#[test]
fn a_filter_lexes_into_chips_and_the_chips_spell_it_back() {
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_terms(c("area:home -status:done roof").as_ptr(), &mut out) },
        LIV_OK
    );
    let terms = took(out);
    let rows = terms.as_array().unwrap();
    assert_eq!(rows.len(), 3, "{terms}");
    assert_eq!(rows[0]["op"], "equals");
    assert_eq!(rows[0]["key"], "area");
    assert_eq!(rows[0]["value"], "home");
    assert_eq!(rows[1]["op"], "not-equals");
    assert_eq!(rows[2]["op"], "text");

    // Joining the canonical spellings reproduces a query that lexes the
    // same way — which is what lets a shell write edited chips back.
    let respelled: Vec<&str> = rows.iter().map(|t| t["raw"].as_str().unwrap()).collect();
    let joined = respelled.join(" ");
    let mut out = std::ptr::null_mut();
    unsafe { liv_terms(c(&joined).as_ptr(), &mut out) };
    assert_eq!(took(out), terms, "a round trip through the chips changes nothing");
}

#[test]
fn lexing_needs_no_box_and_refuses_nothing() {
    // No path argument at all: it takes no lock and has no opinion about
    // whether a property exists, which is what makes it safe to call on
    // every keystroke.
    for raw in ["", "   ", "area:", ":home", "-", "🙂"] {
        let mut out = std::ptr::null_mut();
        assert_eq!(unsafe { liv_terms(c(raw).as_ptr(), &mut out) }, LIV_OK, "{raw:?}");
        assert!(took(out).is_array());
    }
}

// ---- what a picker offers ----------------------------------------------

/// **A different question from `liv_options`.** That asks what a cell MAY
/// hold; this asks what it does.
#[test]
fn values_in_use_are_what_the_box_carries_not_what_it_allows() {
    let (d, path) = stocked("inuse");
    let area = c(&prop::AREA.hex());

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_values_in_use(path.as_ptr(), area.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    let labels: Vec<&str> =
        rows.as_array().unwrap().iter().map(|r| r["label"].as_str().unwrap()).collect();

    // Two areas are in use out of six that exist, commonest first.
    assert_eq!(labels, vec!["Home", "Work"], "{rows}");
    assert_eq!(rows[0]["count"].as_u64().unwrap(), 2);
    assert_eq!(rows[0]["ref"].as_str().unwrap(), area::HOME.hex(), "and the chip is tappable");

    // **The trash is not "in use".** Offering what the trash holds is
    // offering someone their own deletions back — and the only thing
    // filed under Money here is thrown away, so it must not appear.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_ffi::basics::liv_make(
            path.as_ptr(),
            c(&kind::TASK.hex()).as_ptr(),
            c("Old receipt").as_ptr(),
            T0 + 20,
            &mut out,
        )
    };
    let junk = c(took(out)["id"].as_str().unwrap());
    unsafe {
        liv_ffi::basics::liv_set(
            path.as_ptr(),
            junk.as_ptr(),
            area.as_ptr(),
            c("Money").as_ptr(),
            T0 + 21,
        )
    };
    let mut out = std::ptr::null_mut();
    unsafe { liv_values_in_use(path.as_ptr(), area.as_ptr(), &mut out) };
    assert!(
        took(out).as_array().unwrap().iter().any(|r| r["label"] == "Money"),
        "in use while it is live"
    );

    assert_eq!(unsafe { liv_ffi::basics::liv_trash(path.as_ptr(), junk.as_ptr(), T0 + 22) }, LIV_OK);
    let mut out = std::ptr::null_mut();
    unsafe { liv_values_in_use(path.as_ptr(), area.as_ptr(), &mut out) };
    let after = took(out);
    assert!(
        !after.as_array().unwrap().iter().any(|r| r["label"] == "Money"),
        "and gone once it is in the trash: {after}"
    );

    let _ = std::fs::remove_dir_all(&d);
}

// ---- files -------------------------------------------------------------

/// **A hash travels and a path does not**, so `absent` and `gone` are
/// different answers. A file added on the laptop reaches the phone as a
/// valid reference with no local copy; that is "find it for me", not
/// "this is broken".
#[test]
fn a_missing_file_is_told_apart_from_one_that_never_arrived() {
    let d = dir("files");
    let path = d.join("liv.db");
    let doc = d.join("invoice.pdf");
    std::fs::write(&doc, "some bytes").unwrap();
    let gone_id;
    let absent_id;
    {
        let mut e = Engine::open_local(&path).unwrap();
        gone_id = e.add_file(doc.to_str().unwrap(), T0).unwrap();
        // A file that arrived by sync: the hash is here, the path is not.
        absent_id = e.create(kind::FILE, Some("From the laptop"), T0 + 1).unwrap();
        e.set(absent_id, prop::FILE, Value::Blob([7u8; 32]), T0 + 1).unwrap();
    }
    unsafe { liv_view_close_all() };
    let p = c(path.to_str().unwrap());

    // Nothing wrong yet with the local one.
    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_file_alerts(p.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    let only: Vec<&str> =
        rows.as_array().unwrap().iter().map(|r| r["id"].as_str().unwrap()).collect();
    assert_eq!(only, vec![absent_id.hex()], "a synced file with no copy here: {rows}");
    assert_eq!(rows[0]["why"], "absent");
    assert!(rows[0]["path"].is_null(), "and null is the honest answer for where");

    // Now take the local one away.
    std::fs::remove_file(&doc).unwrap();
    let mut out = std::ptr::null_mut();
    unsafe { liv_file_alerts(p.as_ptr(), &mut out) };
    let rows = took(out);
    let gone = rows
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["id"].as_str().unwrap() == gone_id.hex())
        .unwrap_or_else(|| panic!("the vanished file is not reported: {rows}"));
    assert_eq!(gone["why"], "gone");
    assert!(gone["path"].as_str().unwrap().ends_with("invoice.pdf"), "it says WHERE it looked");

    let _ = std::fs::remove_dir_all(&d);
}

// ---- workspaces and filters --------------------------------------------

/// **A workspace is an ordinary entity**, so the primitives already make
/// one and there is no verb here that does. This only reads.
#[test]
fn a_workspace_is_made_with_the_ordinary_verbs_and_read_back_here() {
    let (d, path) = stocked("workspaces");

    let mut out = std::ptr::null_mut();
    unsafe {
        liv_ffi::basics::liv_make(
            path.as_ptr(),
            c(&kind::WORKSPACE.hex()).as_ptr(),
            c("House").as_ptr(),
            T0 + 10,
            &mut out,
        )
    };
    let ws = c(took(out)["id"].as_str().unwrap());
    let query = c(&prop::QUERY.hex());
    assert_eq!(
        unsafe {
            liv_ffi::basics::liv_set(
                path.as_ptr(),
                ws.as_ptr(),
                query.as_ptr(),
                c("area:home").as_ptr(),
                T0 + 11,
            )
        },
        LIV_OK
    );

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_workspaces(path.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    let row = rows.as_array().unwrap().iter().find(|r| r["name"] == "House").unwrap();
    assert_eq!(row["query"], "area:home");
    assert_eq!(row["favorite"], false);
    assert_eq!(row["archived"], false);
    assert!(row["parent"].is_null());

    // And its query, run as a lens, is what the workspace admits.
    let mut out = std::ptr::null_mut();
    unsafe { liv_lens(path.as_ptr(), c("area:home").as_ptr(), &mut out) };
    assert_eq!(took(out)["ids"].as_array().unwrap().len(), 2);

    let _ = std::fs::remove_dir_all(&d);
}

/// An archived workspace is INCLUDED with its flag — the switcher shows
/// them behind a disclosure, and filtering them out here would take that
/// choice away from the shell.
#[test]
fn an_archived_workspace_is_reported_not_hidden() {
    let (d, path) = stocked("archived_ws");
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_ffi::basics::liv_make(
            path.as_ptr(),
            c(&kind::WORKSPACE.hex()).as_ptr(),
            c("Last year").as_ptr(),
            T0 + 10,
            &mut out,
        )
    };
    let ws = c(took(out)["id"].as_str().unwrap());
    let archived = c(&prop::ARCHIVED.hex());
    unsafe {
        liv_ffi::basics::liv_set(
            path.as_ptr(),
            ws.as_ptr(),
            archived.as_ptr(),
            c("yes").as_ptr(),
            T0 + 11,
        )
    };

    let mut out = std::ptr::null_mut();
    unsafe { liv_workspaces(path.as_ptr(), &mut out) };
    let rows = took(out);
    let row = rows.as_array().unwrap().iter().find(|r| r["name"] == "Last year").unwrap();
    assert_eq!(row["archived"], true, "reported, with the flag: {rows}");

    // A TRASHED one is gone, which is a different thing from archived.
    assert_eq!(unsafe { liv_ffi::basics::liv_trash(path.as_ptr(), ws.as_ptr(), T0 + 12) }, LIV_OK);
    let mut out = std::ptr::null_mut();
    unsafe { liv_workspaces(path.as_ptr(), &mut out) };
    assert!(!took(out).as_array().unwrap().iter().any(|r| r["name"] == "Last year"));

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_saved_filter_reads_back_with_its_query() {
    let (d, path) = stocked("views");
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_ffi::basics::liv_make(
            path.as_ptr(),
            c(&kind::VIEW.hex()).as_ptr(),
            c("Overdue at home").as_ptr(),
            T0 + 10,
            &mut out,
        )
    };
    let v = c(took(out)["id"].as_str().unwrap());
    unsafe {
        liv_ffi::basics::liv_set(
            path.as_ptr(),
            v.as_ptr(),
            c(&prop::QUERY.hex()).as_ptr(),
            c("area:home -status:done").as_ptr(),
            T0 + 11,
        )
    };

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_views(path.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    assert_eq!(rows[0]["name"], "Overdue at home");
    assert_eq!(rows[0]["query"], "area:home -status:done");

    let _ = std::fs::remove_dir_all(&d);
}

/// **Absent or true is ON; only an explicit `false` silences the clerk.**
/// An older box that never set it is not a box that said no.
#[test]
fn the_assist_switch_is_on_until_it_is_explicitly_off() {
    let (d, path) = stocked("assist");

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_assist(path.as_ptr(), &mut out) }, LIV_OK);
    let a = took(out);
    assert_eq!(a["on"], true, "a box that never said anything");
    let switch = c(a["property"].as_str().unwrap());

    // Turning it off is an ordinary set, which is why there is no writer
    // in this file.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_ffi::basics::liv_make(
            path.as_ptr(),
            c(&kind::NOTE.hex()).as_ptr(),
            c("settings").as_ptr(),
            T0 + 10,
            &mut out,
        )
    };
    let s = c(took(out)["id"].as_str().unwrap());
    assert_eq!(
        unsafe {
            liv_ffi::basics::liv_set(path.as_ptr(), s.as_ptr(), switch.as_ptr(), c("no").as_ptr(), T0 + 11)
        },
        LIV_OK
    );

    let mut out = std::ptr::null_mut();
    unsafe { liv_assist(path.as_ptr(), &mut out) };
    assert_eq!(took(out)["on"], false);

    let _ = std::fs::remove_dir_all(&d);
}

// ---- the error channel -------------------------------------------------

#[test]
fn a_bad_id_is_an_argument_error_and_never_a_panic() {
    let (d, path) = stocked("badid");
    for bad in ["", "abc", "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"] {
        let mut out = std::ptr::null_mut();
        assert_eq!(
            unsafe { liv_values_in_use(path.as_ptr(), c(bad).as_ptr(), &mut out) },
            LIV_ERR_ARG,
            "{bad}"
        );
        assert!(out.is_null(), "a refused call delivers nothing to free");
    }
    let _ = std::fs::remove_dir_all(&d);
}

// ---- the two the swap would otherwise take away ------------------------

#[test]
fn the_trash_has_its_own_verb_because_every_other_surface_hides_it() {
    let (d, path) = stocked("trash");

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_view_trash(path.as_ptr(), &mut out) }, LIV_OK);
    assert!(took(out).as_array().unwrap().is_empty(), "nothing thrown out yet");

    // Throw one out through the ordinary verb.
    let all = search(&path, "roof", 0);
    let victim = c(all["hits"][0]["id"].as_str().unwrap());
    assert_eq!(
        unsafe { liv_ffi::basics::liv_trash(path.as_ptr(), victim.as_ptr(), T0 + 20) },
        LIV_OK
    );

    let mut out = std::ptr::null_mut();
    unsafe { liv_view_trash(path.as_ptr(), &mut out) };
    let rows = took(out);
    assert_eq!(rows.as_array().unwrap().len(), 1, "{rows}");
    assert_eq!(rows[0]["id"].as_str().unwrap(), victim.to_str().unwrap());
    // The same row shape every other surface returns, so the Trash screen
    // draws with the code every list already has.
    assert!(rows[0]["title"].as_str().is_some_and(|t| !t.is_empty()));

    // And it is gone from the surfaces that hide it.
    let after = search(&path, "roof", 0);
    assert!(!hits(&after).contains(&victim.to_str().unwrap().to_owned()));

    let _ = std::fs::remove_dir_all(&d);
}

/// **A projection: nothing is stored.** A line in a note is a thought,
/// not a task someone has to file.
#[test]
fn open_lines_inside_notes_are_listed_without_becoming_things() {
    let d = dir("notetasks");
    let path = d.join("liv.db");
    let note;
    let before;
    {
        let mut e = Engine::open_local(&path).unwrap();
        note = e.create(kind::NOTE, Some("Saturday"), T0).unwrap();
        e.set_content(
            note,
            vec![
                Span::Break(liv_engine::rich::Block::Task { depth: 0, done: false }),
                Span::text("book the ferry"),
                Span::Break(liv_engine::rich::Block::Task { depth: 0, done: true }),
                Span::text("already done"),
            ],
            0,
            T0 + 1,
        )
        .unwrap();
        before = e.all_entities().unwrap().len();
    }
    unsafe { liv_view_close_all() };
    let p = c(path.to_str().unwrap());

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_note_tasks(p.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    assert_eq!(rows.as_array().unwrap().len(), 1, "the open one only: {rows}");
    assert_eq!(rows[0]["text"], "book the ferry");
    assert_eq!(rows[0]["note"].as_str().unwrap(), note.hex());
    assert_eq!(rows[0]["source"], "Saturday", "titled where the body is");
    assert!(rows[0]["line"].as_u64().is_some(), "and carries the toggle's address");

    // Nothing was created by asking.
    let e = Engine::open_local(&path).unwrap();
    assert_eq!(e.all_entities().unwrap().len(), before);
    drop(e);

    let _ = std::fs::remove_dir_all(&d);
}
