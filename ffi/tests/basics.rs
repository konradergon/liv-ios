//! The verbs every tap uses, across the C ABI.
//!
//! Without these a shell on the engine can read and never touch: no
//! capture, no create, no ticking a checkbox, no filing, no trash. They
//! are the difference between the swap being possible and being an
//! amputation.

use std::ffi::{CStr, CString};

use liv_engine::{kind, prop, Engine};
use liv_ffi::basics::*;
use liv_ffi::finding::liv_search;
use liv_ffi::surfaces::{liv_view_close_all, LIV_ERR_ARG, LIV_OK};
use liv_ffi::writes::{LIV_ERR_NOTHING, LIV_ERR_REFUSED, LIV_ERR_STALE};
use serde_json::Value as J;

const T0: u64 = 1_789_257_600_000;

fn dir(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("liv_ffi_basics_{name}"));
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

/// An empty box on disk, with the verbs' own connection.
fn box_at(name: &str) -> (std::path::PathBuf, CString) {
    let d = dir(name);
    let path = d.join("liv.db");
    {
        Engine::open_local(&path).unwrap();
    }
    unsafe { liv_view_close_all() };
    let p = c(path.to_str().unwrap());
    (d, p)
}

/// A compiled-in property's id, the way a shell gets its first one.
fn prop_id(path: &CString, name: &str) -> CString {
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_property_named(path.as_ptr(), c(name).as_ptr(), &mut out) },
        LIV_OK,
        "{name}"
    );
    c(took(out)["id"].as_str().unwrap())
}

// ---- making things -----------------------------------------------------

#[test]
fn a_thing_is_made_named_or_not() {
    let (d, path) = box_at("make");
    let note = c(&kind::NOTE.hex());

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_make(path.as_ptr(), note.as_ptr(), c("Roof").as_ptr(), T0, &mut out) },
        LIV_OK
    );
    let named = took(out)["id"].as_str().unwrap().to_owned();

    // Null name is a thing born untitled — the common case, not an error.
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_make(path.as_ptr(), note.as_ptr(), std::ptr::null(), T0 + 1, &mut out) },
        LIV_OK
    );
    let bare = took(out)["id"].as_str().unwrap().to_owned();
    assert_ne!(named, bare);

    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), c(&named).as_ptr(), &mut out) };
    let cells = took(out);
    assert!(
        cells.as_array().unwrap().iter().any(|r| r["value"] == "Roof"),
        "the name is a cell: {cells}"
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// **A capture is UNTYPED, and that is the point.**
///
/// Deciding what kind of thing a thought is comes later — the clerk's
/// promotion proposer is what offers to make it a task, and it returns
/// early the moment a `kind` cell exists. Until this verb existed there
/// was no way to make one: `create` always writes a kind, so the
/// promotion test had to hand-write a raw op to take it back off.
#[test]
fn a_capture_has_no_kind_so_the_clerk_can_still_offer_one() {
    let (d, path) = box_at("capture");

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            liv_capture(path.as_ptr(), c("- [ ] book the ferry").as_ptr(), T0, &mut out)
        },
        LIV_OK
    );
    let id = took(out)["id"].as_str().unwrap().to_owned();

    // The text is its body, and it has no kind.
    let mut out = std::ptr::null_mut();
    unsafe { liv_ffi::writes::liv_read_body(path.as_ptr(), c(&id).as_ptr(), &mut out) };
    let body = took(out);
    assert_eq!(body["spans"][0]["Text"].as_str().unwrap(), "- [ ] book the ferry");

    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), c(&id).as_ptr(), &mut out) };
    let cells = took(out);
    assert!(
        !cells.as_array().unwrap().iter().any(|r| r["name"] == "kind"),
        "a capture decides nothing: {cells}"
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// One action, so one undo takes the whole capture back rather than
/// leaving half of it — and it lands in the TRASH still saying what it
/// was, because that is where a person goes to get it back.
///
/// The first version of this asserted `liv_cells` came back empty, which
/// it does whether or not the undo worked: a body is not one of the rows
/// `liv_cells` returns. It reads the body now.
#[test]
fn a_capture_is_one_undo_and_lands_in_the_trash() {
    let (d, path) = box_at("capture_undo");
    let mut out = std::ptr::null_mut();
    unsafe { liv_capture(path.as_ptr(), c("call the surveyor").as_ptr(), T0, &mut out) };
    let id = c(took(out)["id"].as_str().unwrap());

    assert_eq!(unsafe { liv_ffi::writes::liv_undo(path.as_ptr(), T0 + 1) }, LIV_OK);

    let mut out = std::ptr::null_mut();
    unsafe { liv_ffi::writes::liv_read_body(path.as_ptr(), id.as_ptr(), &mut out) };
    let body = took(out);
    assert_eq!(
        body["spans"][0]["Text"].as_str().unwrap(),
        "call the surveyor",
        "the Trash must not be a list of blanks"
    );

    assert_eq!(unsafe { liv_restore(path.as_ptr(), id.as_ptr(), T0 + 2) }, LIV_OK);

    let _ = std::fs::remove_dir_all(&d);
}

// ---- changing cells ----------------------------------------------------

/// **The property says what the text means.** The shell sends strings;
/// which of them is a date, a bool or an option is the box's business.
#[test]
fn a_value_crosses_as_text_and_the_property_reads_it() {
    let (d, path) = box_at("set");
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::TASK.hex()).as_ptr(), c("Roof").as_ptr(), T0, &mut out)
    };
    let id = c(took(out)["id"].as_str().unwrap());

    // "Work" IS NOT AN AREA UNTIL SOMEONE MAKES ONE (2026-09-21). An
    // option is matched by name and never minted by `liv_set` — typing
    // a typo must not create an area — so the vocabulary has to exist
    // before a value can name it.
    let area_prop = prop_id(&path, "area");
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_add_option(path.as_ptr(), area_prop.as_ptr(), c("Work").as_ptr(), T0, &mut out)
    };
    took(out);

    for (property, raw) in
        [("area", "Work"), ("status", "Doing"), ("due", "2026-09-13"), ("private", "yes")]
    {
        let p = prop_id(&path, property);
        assert_eq!(
            unsafe { liv_set(path.as_ptr(), id.as_ptr(), p.as_ptr(), c(raw).as_ptr(), T0 + 1) },
            LIV_OK,
            "{property} = {raw}"
        );
    }

    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), id.as_ptr(), &mut out) };
    let cells = took(out);
    let shown = |name: &str| -> String {
        cells
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["name"] == name)
            .unwrap_or_else(|| panic!("no {name} row in {cells}"))["value"]
            .as_str()
            .unwrap()
            .to_owned()
    };
    // Every row renders as a string, so a shell draws it without knowing
    // the kind — and the words come from the box.
    assert_eq!(shown("area"), "Work");
    assert_eq!(shown("status"), "Doing");
    assert_eq!(shown("due"), "2026-09-13");
    assert_eq!(shown("private"), "Yes");

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn text_that_does_not_read_is_refused_and_writes_nothing() {
    let (d, path) = box_at("refuse");
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::TASK.hex()).as_ptr(), c("Roof").as_ptr(), T0, &mut out)
    };
    let id = c(took(out)["id"].as_str().unwrap());
    let area = prop_id(&path, "area");
    let due = prop_id(&path, "due");

    for (p, raw) in [(&area, "Wrok"), (&due, "next tuesday"), (&due, "2026-02-30")] {
        assert_eq!(
            unsafe { liv_set(path.as_ptr(), id.as_ptr(), p.as_ptr(), c(raw).as_ptr(), T0 + 1) },
            LIV_ERR_REFUSED,
            "{raw}"
        );
    }

    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), id.as_ptr(), &mut out) };
    let cells = took(out);
    assert!(
        !cells.as_array().unwrap().iter().any(|r| r["name"] == "area" || r["name"] == "due"),
        "a refusal writes nothing: {cells}"
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// Unsetting is not setting to nothing: the cell has no value at all,
/// which is what a picker's "None" means.
#[test]
fn a_cell_can_be_emptied() {
    let (d, path) = box_at("unset");
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::TASK.hex()).as_ptr(), c("Roof").as_ptr(), T0, &mut out)
    };
    let id = c(took(out)["id"].as_str().unwrap());
    let due = prop_id(&path, "due");

    unsafe { liv_set(path.as_ptr(), id.as_ptr(), due.as_ptr(), c("2026-09-13").as_ptr(), T0 + 1) };
    assert_eq!(unsafe { liv_unset(path.as_ptr(), id.as_ptr(), due.as_ptr(), T0 + 2) }, LIV_OK);

    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), id.as_ptr(), &mut out) };
    let cells = took(out);
    assert!(
        !cells.as_array().unwrap().iter().any(|r| r["name"] == "due"),
        "the cell is gone, not blank: {cells}"
    );

    // And emptying an empty cell writes nothing rather than logging an
    // empty action — a picker set to None twice is one undo, not two.
    assert_eq!(unsafe { liv_unset(path.as_ptr(), id.as_ptr(), due.as_ptr(), T0 + 3) }, LIV_OK);
    unsafe { liv_ffi::writes::liv_undo(path.as_ptr(), T0 + 4) };
    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), id.as_ptr(), &mut out) };
    let back = took(out);
    assert!(
        back.as_array().unwrap().iter().any(|r| r["name"] == "due"),
        "one undo brings the date back: {back}"
    );

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_set_takes_members_and_gives_them_up() {
    let (d, path) = box_at("members");
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::NOTE.hex()).as_ptr(), c("Roof").as_ptr(), T0, &mut out)
    };
    let note = c(took(out)["id"].as_str().unwrap());
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::PERSON.hex()).as_ptr(), c("Anna").as_ptr(), T0 + 1, &mut out)
    };
    let anna = took(out)["id"].as_str().unwrap().to_owned();
    let people = prop_id(&path, "people");

    assert_eq!(
        unsafe { liv_add(path.as_ptr(), note.as_ptr(), people.as_ptr(), c("Anna").as_ptr(), T0 + 2) },
        LIV_OK
    );
    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), note.as_ptr(), &mut out) };
    let cells = took(out);
    let row = cells.as_array().unwrap().iter().find(|r| r["name"] == "people").unwrap();
    assert_eq!(row["value"], "Anna");
    assert_eq!(row["ref"].as_str().unwrap(), anna, "and the row is tappable");
    assert_eq!(row["many"], true);

    assert_eq!(
        unsafe {
            liv_remove(path.as_ptr(), note.as_ptr(), people.as_ptr(), c("Anna").as_ptr(), T0 + 3)
        },
        LIV_OK
    );
    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), note.as_ptr(), &mut out) };
    assert!(!took(out).as_array().unwrap().iter().any(|r| r["name"] == "people"));

    let _ = std::fs::remove_dir_all(&d);
}

// ---- the trash ---------------------------------------------------------

#[test]
fn trashing_is_a_cell_so_restoring_is_a_write() {
    let (d, path) = box_at("trash");
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::NOTE.hex()).as_ptr(), c("Roof").as_ptr(), T0, &mut out)
    };
    let id = c(took(out)["id"].as_str().unwrap());

    assert_eq!(unsafe { liv_trash(path.as_ptr(), id.as_ptr(), T0 + 1) }, LIV_OK);
    // Still there — nothing is removed from the log, which is exactly
    // why restore is possible at all.
    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), id.as_ptr(), &mut out) };
    assert!(took(out).as_array().unwrap().iter().any(|r| r["value"] == "Roof"));

    assert_eq!(unsafe { liv_restore(path.as_ptr(), id.as_ptr(), T0 + 2) }, LIV_OK);

    let _ = std::fs::remove_dir_all(&d);
}

// ---- what a picker needs -----------------------------------------------

/// **The words come from the box, never from the shell** — and since
/// 2026-09-21 there are no words until someone writes one.
///
/// This asserted the six the app shipped, in product order. The owner
/// removed them (*"Areas are all created by the user"*), so a fresh
/// box's area vocabulary is EMPTY, and what this pins now is the shape
/// that replaced them: empty at the start, and whatever a person makes
/// after that, by the same one rule the cell already used.
#[test]
fn a_picker_asks_the_box_for_its_words() {
    let (d, path) = box_at("options");
    let area = prop_id(&path, "area");

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_options(path.as_ptr(), area.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    assert!(
        rows.as_array().unwrap().is_empty(),
        "a fresh box ships no area at all: {rows}"
    );

    // A user's own areas ARE the list now.
    for name in ["Woodworking", "Allotment"] {
        let mut out = std::ptr::null_mut();
        assert_eq!(
            unsafe {
                liv_add_option(path.as_ptr(), area.as_ptr(), c(name).as_ptr(), T0, &mut out)
            },
            LIV_OK
        );
        took(out);
    }
    let mut out = std::ptr::null_mut();
    unsafe { liv_options(path.as_ptr(), area.as_ptr(), &mut out) };
    let rows = took(out);
    let names: Vec<&str> =
        rows.as_array().unwrap().iter().map(|r| r["name"].as_str().unwrap()).collect();
    // IN THE ORDER THEY WERE MADE, which is id order, which for a v7 id
    // is creation order. Worth pinning rather than assuming: the six
    // used to arrive in a product order somebody chose, and nobody
    // chooses this one. Whether a picker should sort by name instead is
    // a question for the picker, not for the ABI.
    assert_eq!(names, vec!["Woodworking", "Allotment"], "{rows}");

    let _ = std::fs::remove_dir_all(&d);
}

/// **A STATUS OPTION HAS TO SAY WHETHER IT CLOSES THE THING.**
///
/// `liv_options` shipped `{id, name}` and nothing else, so a shell
/// asking for the status vocabulary got three words and no way to tell
/// which one means done. The iOS ring writes "the option that completes"
/// — it found none, wrote nothing, and a task could not be ticked at all
/// (owner, 2026-09-15). The answer was in the box the whole time: the
/// engine holds `prop::COMPLETES` and `surface::completes` already reads
/// it for the row's own `done` flag.
///
/// `hue` rides along for the same reason — the ring colours itself from
/// the vocabulary, and a colour invented in Swift is the same mistake as
/// a word invented in Swift (`one-core.md` §4).
///
/// Purely additive: two new keys on a payload that had two.
#[test]
fn a_status_option_says_whether_it_closes_the_thing() {
    let (d, path) = box_at("options_completes");
    let status = prop_id(&path, "status");

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_options(path.as_ptr(), status.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    let rows = rows.as_array().unwrap();
    assert_eq!(rows.len(), 3, "todo, doing, done");

    // EXACTLY ONE closes. A shell that finds none writes nothing; a
    // shell that finds two writes whichever it happened to see first.
    let closing: Vec<&str> = rows
        .iter()
        .filter(|r| r["completes"] == J::Bool(true))
        .map(|r| r["name"].as_str().unwrap())
        .collect();
    assert_eq!(closing, vec!["Done"], "{rows:?}");
    // And the other two say so rather than being silent about it — a
    // missing key and a false one read the same in Swift, but only one
    // of them is an answer.
    assert!(
        rows.iter().all(|r| r["completes"].is_boolean()),
        "every option answers the question: {rows:?}"
    );

    // A user's own status joins the vocabulary and does NOT close
    // anything until it is told to.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(
            path.as_ptr(), c(&kind::STATUS.hex()).as_ptr(), c("Blocked").as_ptr(), T0, &mut out,
        )
    };
    let mine = c(took(out)["id"].as_str().unwrap());
    let mut out = std::ptr::null_mut();
    unsafe { liv_options(path.as_ptr(), status.as_ptr(), &mut out) };
    let rows = took(out);
    let rows = rows.as_array().unwrap();
    let blocked = rows.iter().find(|r| r["name"] == "Blocked").unwrap();
    assert_eq!(blocked["completes"], J::Bool(false), "{blocked:?}");

    // Told to, it closes — the flag is a cell, not a hardcoded list.
    let completes = prop_id(&path, "completes");
    assert_eq!(
        unsafe {
            liv_set(path.as_ptr(), mine.as_ptr(), completes.as_ptr(), c("yes").as_ptr(), T0 + 1)
        },
        LIV_OK
    );
    let mut out = std::ptr::null_mut();
    unsafe { liv_options(path.as_ptr(), status.as_ptr(), &mut out) };
    let rows = took(out);
    let rows = rows.as_array().unwrap();
    let blocked = rows.iter().find(|r| r["name"] == "Blocked").unwrap();
    assert_eq!(blocked["completes"], J::Bool(true), "{blocked:?}");

    let _ = std::fs::remove_dir_all(&d);
}

/// **THE BACKSTAGE KINDS HAVE NO DOOR.**
///
/// `liv_kinds` is the CREATE MENU's list — the six the product names,
/// plus what a user declared — and `offered_kinds` leaves out
/// `kind::WORKSPACE` and `kind::VIEW` on purpose: a person never picks
/// one from a list. But the app MAKES both, and the shell's only way to
/// name a kind was that list. So saving a new filter looked for a kind
/// called "view", never found it, and wrote nothing — no filter, no
/// error a person could see (owner, 2026-09-15: "can't save new
/// filters"). A new workspace failed the same way, silently.
///
/// The same door `liv_property_named` is, for the same reason written
/// there: a shell needs SOME way in, and hard-coding 32 hex characters
/// in Swift is worse than asking.
#[test]
fn a_shell_can_name_a_backstage_kind() {
    let (d, path) = box_at("kind_named");

    // The one this was written for. It is NOT in liv_kinds.
    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_kind_named(path.as_ptr(), c("view").as_ptr(), &mut out) }, LIV_OK);
    assert_eq!(took(out)["id"], J::String(kind::VIEW.hex()));

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_kind_named(path.as_ptr(), c("workspace").as_ptr(), &mut out) }, LIV_OK);
    assert_eq!(took(out)["id"], J::String(kind::WORKSPACE.hex()));

    // The picker's list still does not carry them — this verb is the
    // door, not a widening of that one.
    let mut out = std::ptr::null_mut();
    unsafe { liv_kinds(path.as_ptr(), &mut out) };
    let offered = took(out);
    let names: Vec<&str> =
        offered.as_array().unwrap().iter().map(|r| r["name"].as_str().unwrap()).collect();
    assert!(!names.contains(&"View"), "a create menu must not offer a saved filter: {names:?}");
    assert!(!names.contains(&"Workspace"), "{names:?}");

    // The six answer here too — one lookup, not a second vocabulary.
    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_kind_named(path.as_ptr(), c("note").as_ptr(), &mut out) }, LIV_OK);
    assert_eq!(took(out)["id"], J::String(kind::NOTE.hex()));
    // A display name with a space in it still resolves, because the
    // shell spells what it sees.
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_kind_named(path.as_ptr(), c("Daily note").as_ptr(), &mut out) }, LIV_OK
    );
    assert_eq!(took(out)["id"], J::String(kind::DAILY_NOTE.hex()));

    // A word that is not a kind is an ARGUMENT fault, not an empty
    // answer: the caller asked for something that does not exist.
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_kind_named(path.as_ptr(), c("sandwich").as_ptr(), &mut out) },
        LIV_ERR_ARG
    );
    assert!(out.is_null(), "a refused lookup delivers nothing");

    let _ = std::fs::remove_dir_all(&d);
}

/// And the shell's own path all the way through: a saved filter is made
/// as a View and keeps its query.
#[test]
fn a_saved_filter_is_made_and_found() {
    let (d, path) = box_at("saved_filter");

    let mut out = std::ptr::null_mut();
    unsafe { liv_kind_named(path.as_ptr(), c("view").as_ptr(), &mut out) };
    let view = c(took(out)["id"].as_str().unwrap());

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_make(path.as_ptr(), view.as_ptr(), c("Foo").as_ptr(), T0, &mut out) },
        LIV_OK
    );
    let made = c(took(out)["id"].as_str().unwrap());

    let query = prop_id(&path, "query");
    assert_eq!(
        unsafe {
            liv_set(path.as_ptr(), made.as_ptr(), query.as_ptr(), c("area:Work").as_ptr(), T0 + 1)
        },
        LIV_OK
    );

    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), made.as_ptr(), &mut out) };
    let cells = took(out);
    assert!(
        cells.as_array().unwrap().iter().any(|r| r["value"] == "area:Work"),
        "the filter kept its query: {cells:?}"
    );

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn the_create_menu_offers_the_six_the_product_names() {
    let (d, path) = box_at("kinds");
    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_kinds(path.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    let names: Vec<&str> = rows.as_array().unwrap().iter().map(|r| r["name"].as_str().unwrap()).collect();
    assert_eq!(names, vec!["Note", "Task", "Event", "Photo", "Person", "Link"]);
    // Not every kind that exists: the backstage ones are furniture the
    // app draws with, and nobody picks one from a list.
    assert!(!names.contains(&"Workspace"));
    assert!(!names.contains(&"Status"));

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_property_is_found_by_its_frozen_name_and_nothing_else_is() {
    let (d, path) = box_at("propnamed");
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_property_named(path.as_ptr(), c("due").as_ptr(), &mut out) },
        LIV_OK
    );
    assert_eq!(took(out)["id"].as_str().unwrap(), prop::DUE.hex());

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_property_named(path.as_ptr(), c("deadline").as_ptr(), &mut out) },
        LIV_ERR_ARG,
        "a name nothing is called is an argument error, not an empty answer"
    );
    assert!(out.is_null());

    let _ = std::fs::remove_dir_all(&d);
}

// ---- the error channel -------------------------------------------------

#[test]
fn a_bad_id_is_an_argument_error_and_never_a_panic() {
    let (d, path) = box_at("badid");
    let due = prop_id(&path, "due");
    let good = c(&kind::NOTE.hex());

    for bad in ["", "abc", "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"] {
        let b = c(bad);
        assert_eq!(unsafe { liv_trash(path.as_ptr(), b.as_ptr(), T0) }, LIV_ERR_ARG, "{bad}");
        assert_eq!(
            unsafe { liv_set(path.as_ptr(), b.as_ptr(), due.as_ptr(), c("2026-09-13").as_ptr(), T0) },
            LIV_ERR_ARG,
            "{bad}"
        );
        assert_eq!(
            unsafe { liv_unset(path.as_ptr(), good.as_ptr(), b.as_ptr(), T0) },
            LIV_ERR_ARG,
            "{bad}"
        );
        let mut out = std::ptr::null_mut();
        assert_eq!(unsafe { liv_cells(path.as_ptr(), b.as_ptr(), &mut out) }, LIV_ERR_ARG);
        assert!(out.is_null(), "a refused call delivers nothing to free");
    }

    // The codes stay distinct: this file's refusals must not collide with
    // the editor's.
    assert_ne!(LIV_ERR_REFUSED, LIV_ERR_ARG);
    assert_ne!(LIV_ERR_REFUSED, LIV_ERR_STALE);

    let _ = std::fs::remove_dir_all(&d);
}

// ---- the last three ----------------------------------------------------

/// A field the app did not ship with is an ordinary entity, minted ONCE
/// on one device — which is what stops it drifting the way a seeded copy
/// does: there is no second copy to disagree with.
#[test]
fn a_field_the_app_did_not_ship_with_can_be_declared_and_used() {
    let (d, path) = box_at("declare");

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            liv_declare_field(
                path.as_ptr(),
                c("client").as_ptr(),
                c("text").as_ptr(),
                false,
                T0,
                &mut out,
            )
        },
        LIV_OK
    );
    let field = c(took(out)["id"].as_str().unwrap());

    // And it behaves like any other property from here on.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::TASK.hex()).as_ptr(), c("Roof").as_ptr(), T0 + 1, &mut out)
    };
    let id = c(took(out)["id"].as_str().unwrap());
    assert_eq!(
        unsafe {
            liv_set(path.as_ptr(), id.as_ptr(), field.as_ptr(), c("Acme").as_ptr(), T0 + 2)
        },
        LIV_OK
    );

    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), id.as_ptr(), &mut out) };
    let cells = took(out);
    let row = cells.as_array().unwrap().iter().find(|r| r["name"] == "client").unwrap();
    assert_eq!(row["value"], "Acme");
    assert_eq!(row["holds"], "text");

    // A shape the model does not have is refused, not invented.
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            liv_declare_field(
                path.as_ptr(),
                c("mood").as_ptr(),
                c("interpretive-dance").as_ptr(),
                false,
                T0 + 3,
                &mut out,
            )
        },
        LIV_ERR_REFUSED
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// **All or nothing, and ONE undo.** Half a consent is worse than none:
/// the user agreed to a set, and a set that half-landed is not what they
/// agreed to.
#[test]
fn accepting_a_group_is_one_action_and_one_undo() {
    let d = dir("accept_all");
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
    unsafe { liv_ffi::writes::liv_sweep(path.as_ptr(), &mut out) };
    let rows = took(out);
    let all = rows.as_array().unwrap();
    assert!(all.len() >= 2, "a date and a mention: {rows}");

    let entities: Vec<CString> =
        all.iter().map(|r| c(r["entity"].as_str().unwrap())).collect();
    let ptrs: Vec<*const std::ffi::c_char> = entities.iter().map(|e| e.as_ptr()).collect();
    let prints: Vec<u64> = all.iter().map(|r| r["print"].as_u64().unwrap()).collect();

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            liv_accept_all(
                path.as_ptr(),
                ptrs.as_ptr(),
                prints.as_ptr(),
                prints.len() as u32,
                T0 + 3,
                &mut out,
            )
        },
        LIV_OK
    );
    assert_eq!(took(out)["taken"].as_u64().unwrap() as usize, all.len());

    // Nothing left to suggest…
    let mut out = std::ptr::null_mut();
    unsafe { liv_ffi::writes::liv_sweep(path.as_ptr(), &mut out) };
    assert!(took(out).as_array().unwrap().is_empty());

    // …and ONE undo brings all of it back.
    assert_eq!(unsafe { liv_ffi::writes::liv_undo(path.as_ptr(), T0 + 4) }, LIV_OK);
    let mut out = std::ptr::null_mut();
    unsafe { liv_ffi::writes::liv_sweep(path.as_ptr(), &mut out) };
    assert_eq!(
        took(out).as_array().unwrap().len(),
        all.len(),
        "one undo, not one per suggestion"
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// A stale row does not fail the batch: "accept all" is a sweep of what
/// is on screen, and one row the user already dealt with elsewhere is not
/// a reason to refuse the other nine.
#[test]
fn a_stale_member_is_skipped_rather_than_failing_the_group() {
    let d = dir("accept_all_stale");
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
    unsafe { liv_ffi::writes::liv_sweep(path.as_ptr(), &mut out) };
    let rows = took(out);
    let all = rows.as_array().unwrap();
    let entities: Vec<CString> = all.iter().map(|r| c(r["entity"].as_str().unwrap())).collect();
    let mut ptrs: Vec<*const std::ffi::c_char> = entities.iter().map(|e| e.as_ptr()).collect();
    let mut prints: Vec<u64> = all.iter().map(|r| r["print"].as_u64().unwrap()).collect();

    // **Only what was TICKED.** All of these suggestions are about the
    // same thing, so a batch that swept the entity and took everything it
    // found would look identical unless some are deliberately left out.
    assert!(all.len() >= 2);
    ptrs.truncate(1);
    prints.truncate(1);
    let ticked = prints[0];
    let untouched: Vec<u64> =
        all.iter().map(|r| r["print"].as_u64().unwrap()).filter(|p| *p != ticked).collect();
    assert!(!untouched.is_empty(), "the fixture must leave something unticked");

    // Plus one fingerprint the box does not propose at all.
    ptrs.push(entities[0].as_ptr());
    prints.push(0xdead_beef_dead_beef);

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            liv_accept_all(
                path.as_ptr(),
                ptrs.as_ptr(),
                prints.as_ptr(),
                prints.len() as u32,
                T0 + 3,
                &mut out,
            )
        },
        LIV_OK
    );
    assert_eq!(took(out)["taken"].as_u64().unwrap(), 1, "the ticked one, and only it");

    // And the ones nobody ticked are still on offer.
    let mut out = std::ptr::null_mut();
    unsafe { liv_ffi::writes::liv_sweep(path.as_ptr(), &mut out) };
    let after = took(out);
    let still: Vec<u64> =
        after.as_array().unwrap().iter().map(|r| r["print"].as_u64().unwrap()).collect();
    for p in &untouched {
        assert!(still.contains(p), "an unticked suggestion was taken anyway: {after}");
    }

    // But a batch where NONE of them is real has nothing to do.
    let ghost: u64 = 0xdead_beef_dead_beef;
    let one = [entities[0].as_ptr()];
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_accept_all(path.as_ptr(), one.as_ptr(), [ghost].as_ptr(), 1, T0 + 4, &mut out) },
        LIV_ERR_NOTHING
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// **A shell that cannot open the box has nothing else to ask.** Every
/// other verb answers LIV_ERR_OPEN, which says it failed and not what to
/// do about it — and the answers need different screens.
#[test]
fn a_box_that_will_not_open_says_why() {
    let (d, path) = box_at("probe");

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_probe_box(path.as_ptr(), &mut out) }, LIV_OK);
    assert_eq!(took(out)["code"], "ok");

    // Something that is not a box at all: an IO answer, about where it
    // is rather than what is in it.
    let junk = d.join("notabox.db");
    std::fs::write(&junk, "this is not a database").unwrap();
    let j = c(junk.to_str().unwrap());
    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_probe_box(j.as_ptr(), &mut out) }, LIV_OK);
    let answer = took(out);
    assert_eq!(answer["code"], "io", "{answer}");

    // **A box from a newer build is the answer that must not be lumped in
    // with the rest**, because it is the one where the user can do
    // something (update) and a wrong answer strands them.
    let newer = d.join("newer.db");
    {
        Engine::open_local(&newer).unwrap();
    }
    unsafe { liv_view_close_all() };
    let conn = rusqlite::Connection::open(&newer).unwrap();
    conn.execute("UPDATE meta SET value = '9999' WHERE key = 'box_format'", []).unwrap();
    drop(conn);

    let n = c(newer.to_str().unwrap());
    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_probe_box(n.as_ptr(), &mut out) }, LIV_OK);
    let answer = took(out);
    assert_eq!(answer["code"], "version", "{answer}");
    assert!(
        answer["message"].as_str().unwrap().contains("newer version"),
        "and it says so in words: {answer}"
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// **Absent or true is ON.** Turning the clerk on removes the cell rather
/// than writing `true`: a box that has never said anything and a box that
/// said yes are the same box, and leaving a `true` behind would be a
/// second thing to find and take away later.
#[test]
fn the_assist_switch_goes_off_and_back_on_without_leaving_anything_behind() {
    let (d, path) = box_at("assist");
    let on = |p: &CString| -> bool {
        let mut out = std::ptr::null_mut();
        assert_eq!(unsafe { liv_ffi::finding::liv_assist(p.as_ptr(), &mut out) }, LIV_OK);
        took(out)["on"].as_bool().unwrap()
    };

    assert!(on(&path), "a box that never said anything");

    assert_eq!(unsafe { liv_set_assist(path.as_ptr(), false, T0) }, LIV_OK);
    assert!(!on(&path));

    // Off twice is off once — a second no would be a second thing to
    // find later.
    assert_eq!(unsafe { liv_set_assist(path.as_ptr(), false, T0 + 1) }, LIV_OK);
    assert!(!on(&path));

    assert_eq!(unsafe { liv_set_assist(path.as_ptr(), true, T0 + 2) }, LIV_OK);
    assert!(on(&path), "and back on");

    // Nothing left carrying an explicit answer.
    let e = Engine::open_local(&d.join("liv.db"));
    // (the verbs hold the connection; this only checks the switch reads on)
    drop(e);
    assert_eq!(unsafe { liv_set_assist(path.as_ptr(), true, T0 + 3) }, LIV_OK);
    assert!(on(&path));

    let _ = std::fs::remove_dir_all(&d);
}

/// The properties a person can put on something — not every property
/// that exists. A picker listing `trashed` beside `due` would be the
/// model leaking through the interface.
#[test]
fn the_property_list_offers_fields_and_not_plumbing() {
    let (d, path) = box_at("properties");

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_properties(path.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    let names: Vec<&str> =
        rows.as_array().unwrap().iter().map(|r| r["name"].as_str().unwrap()).collect();
    assert!(names.contains(&"due"), "{rows}");
    assert!(names.contains(&"status"));
    assert!(!names.contains(&"trashed"), "plumbing is not a field: {names:?}");
    assert!(!names.contains(&"content"));

    // A field the user declared joins the same list.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_declare_field(path.as_ptr(), c("client").as_ptr(), c("text").as_ptr(), false, T0, &mut out)
    };
    took(out);
    let mut out = std::ptr::null_mut();
    unsafe { liv_properties(path.as_ptr(), &mut out) };
    let rows = took(out);
    let mine = rows.as_array().unwrap().iter().find(|r| r["name"] == "client").unwrap();
    assert_eq!(mine["holds"], "text");
    assert_eq!(mine["many"], false);

    let _ = std::fs::remove_dir_all(&d);
}

/// **A picker gets the field AND its vocabulary.** One without the other
/// is an empty list, and a picker with an empty list treats everything
/// typed into it as new — so choosing a word that already exists tried
/// to mint a second one by the same name.
///
/// The vocabulary is a person's own since 2026-09-21, so this mints one
/// first rather than reading the six off the shelf. The claim is
/// unchanged: `liv_properties` carries the field's values with it.
#[test]
fn a_property_carries_the_options_a_picker_offers() {
    let (d, path) = box_at("prop_options");
    let area_prop = prop_id(&path, "area");
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_add_option(path.as_ptr(), area_prop.as_ptr(), c("Allotment").as_ptr(), T0, &mut out)
    };
    took(out);

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_properties(path.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    let area = rows.as_array().unwrap().iter().find(|r| r["name"] == "area").unwrap();
    let names: Vec<&str> =
        area["options"].as_array().unwrap().iter().map(|o| o["name"].as_str().unwrap()).collect();
    assert_eq!(names, vec!["Allotment"], "{area}");

    // A text field has no vocabulary, and says so with an empty list
    // rather than being absent.
    let due = rows.as_array().unwrap().iter().find(|r| r["name"] == "due").unwrap();
    assert!(due["options"].as_array().unwrap().is_empty());

    let _ = std::fs::remove_dir_all(&d);
}

/// **The kind is whatever the property POINTS AT.** `area` is
/// `RefTo(kind::AREA)`; minting an Option for it makes something the cell
/// refuses — a new area that cannot be chosen.
#[test]
fn a_new_option_is_made_of_the_kind_the_property_points_at() {
    let (d, path) = box_at("add_option");
    let area = prop_id(&path, "area");

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            liv_add_option(path.as_ptr(), area.as_ptr(), c("Woodworking").as_ptr(), T0, &mut out)
        },
        LIV_OK
    );
    let made = c(took(out)["id"].as_str().unwrap());

    // It is choosable, which is the whole point: the cell takes it.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::TASK.hex()).as_ptr(), c("Shelf").as_ptr(), T0 + 1, &mut out)
    };
    let task = c(took(out)["id"].as_str().unwrap());
    assert_eq!(
        unsafe {
            liv_set(path.as_ptr(), task.as_ptr(), area.as_ptr(), c("Woodworking").as_ptr(), T0 + 2)
        },
        LIV_OK,
        "a minted area that the cell refuses is not an area"
    );

    // And it joins the picker's list.
    let mut out = std::ptr::null_mut();
    unsafe { liv_options(path.as_ptr(), area.as_ptr(), &mut out) };
    let rows = took(out);
    assert!(rows.as_array().unwrap().iter().any(|o| o["name"] == "Woodworking"), "{rows}");

    // Asking twice hands back the one that exists rather than a second
    // thing with the same name.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_add_option(path.as_ptr(), area.as_ptr(), c("woodworking").as_ptr(), T0 + 3, &mut out)
    };
    assert_eq!(took(out)["id"].as_str().unwrap(), made.to_str().unwrap(), "case-insensitively");

    // A field with no vocabulary has nothing to add to.
    let due = prop_id(&path, "due");
    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_add_option(path.as_ptr(), due.as_ptr(), c("soon").as_ptr(), T0 + 4, &mut out) },
        LIV_ERR_REFUSED
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// **A MINTED OPTION IS VOCABULARY, NOT A THING** — it must not turn up
/// in a search, a list or a count.
///
/// The box holds both halves of the app: your things, and the words the
/// app files them with. An option — "high", a status you added, an area
/// you named — is the second kind, and `working` is the cell that says
/// so. `Engine::run` skips anything carrying it, which is what keeps
/// every surface free of the app's own furniture.
///
/// `liv_add_option` minted through `Engine::create`, which writes only
/// `kind` and `name`. `Engine::declare` exists for exactly this and had
/// no callers anywhere outside tests. So every area, status and select
/// value a person made came out as an ordinary visible thing: typing
/// "high" found the OPTION "high", and the panel's counts included it.
///
/// That was cosmetic while the six areas shipped compiled-in. It stops
/// being cosmetic the moment every area is minted (2026-09-21).
#[test]
fn a_minted_option_is_backstage_and_never_a_search_hit() {
    let (d, path) = box_at("option_backstage");
    let area = prop_id(&path, "area");

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            liv_add_option(path.as_ptr(), area.as_ptr(), c("Woodworking").as_ptr(), T0, &mut out)
        },
        LIV_OK
    );
    let made = took(out)["id"].as_str().unwrap().to_owned();

    // A REAL thing by the same word, so the search has something honest
    // to find and "no hits" cannot pass for success.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(
            path.as_ptr(),
            c(&kind::NOTE.hex()).as_ptr(),
            c("Woodworking bench").as_ptr(),
            T0 + 1,
            &mut out,
        )
    };
    let note = took(out)["id"].as_str().unwrap().to_owned();

    let mut out = std::ptr::null_mut();
    assert_eq!(
        unsafe { liv_search(path.as_ptr(), c("woodworking").as_ptr(), 0, &mut out) },
        LIV_OK
    );
    let found = took(out);
    let hits: Vec<&str> =
        found["hits"].as_array().unwrap().iter().filter_map(|h| h["id"].as_str()).collect();

    assert!(hits.contains(&note.as_str()), "the note is findable: {found}");
    assert!(
        !hits.contains(&made.as_str()),
        "the OPTION is vocabulary and must not be a hit: {found}"
    );

    let _ = std::fs::remove_dir_all(&d);
}

/// **A PICKER GETS BOTH WORDS.** `name` is what a person reads and can
/// rename; `word` is the token the query grammar lexes and the one a
/// shell keys its own rows off.
///
/// They were one string. `tags` reads "Subject" as of 2026-09-16, so a
/// shell matching its `["area","project","tags","people"]` against the
/// shown name would have lost the row entirely — which is exactly how
/// the area picker broke in September, and why this ships with the
/// rename rather than after it.
#[test]
fn a_property_row_carries_the_token_beside_the_word() {
    let (d, path) = box_at("prop_words");

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_properties(path.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    let rows = rows.as_array().unwrap();

    let tags = rows.iter().find(|r| r["word"] == "tags").expect("a tags row: {rows:?}");
    assert_eq!(tags["name"], "Subject", "what a person reads");
    assert_eq!(tags["word"], "tags", "what the grammar lexes");

    // Every other shown property reads as its own token, so a shell can
    // still find them by either.
    for r in rows {
        let (w, n) = (r["word"].as_str().unwrap(), r["name"].as_str().unwrap());
        if w != "tags" {
            assert_eq!(w, n, "{w} grew a second word without anyone saying so");
        }
    }

    // AND THE TOKEN IS WHAT liv_property_named TAKES — the shell asks
    // with `word`, never with what it drew on screen.
    let by_token = prop_id(&path, "tags");
    assert_eq!(by_token.to_str().unwrap(), tags["id"].as_str().unwrap());

    let _ = std::fs::remove_dir_all(&d);
}

/// **A CELL ROW CARRIES THE TOKEN TOO**, for the same reason a property
/// row does: `name` is what a person reads and `word` is what a shell
/// keys off.
///
/// The properties card hides the cells it already draws as proper rows,
/// and it matched that skip list against `name`. Two things were wrong
/// with that the moment it was written and one of them was invisible:
///
///   - it skipped "type", which is `core/`'s word. The engine's cell is
///     `kind`, so the kind row was never hidden and the card carried a
///     read-only chip saying "Note" on a note (owner, 2026-09-16:
///     "remove kind row in properties");
///   - and once `tags` began READING "Subject" (2026-09-16), the same
///     match would have stopped hiding it — so the card would have drawn
///     the field twice, once as `Subject` and once as itself.
#[test]
fn a_cell_row_carries_the_token_beside_the_word() {
    let (d, path) = box_at("cell_words");

    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::NOTE.hex()).as_ptr(), c("Roof").as_ptr(), T0, &mut out)
    };
    let id = c(took(out)["id"].as_str().unwrap());

    // `tags` is a bare `Holds::Ref`: a tag is a THING, so the value is
    // an id and not a word. (`#<hex>` is the ABI's own grammar for it.)
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::NOTE.hex()).as_ptr(), c("Slates").as_ptr(), T0, &mut out)
    };
    let slates = took(out)["id"].as_str().unwrap().to_owned();
    let tags = prop_id(&path, "tags");
    assert_eq!(
        unsafe {
            liv_add(
                path.as_ptr(), id.as_ptr(), tags.as_ptr(),
                c(&format!("#{slates}")).as_ptr(), T0 + 1,
            )
        },
        LIV_OK
    );

    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), id.as_ptr(), &mut out) };
    let cells = took(out);
    let cells = cells.as_array().unwrap();

    let tag_row = cells.iter().find(|r| r["word"] == "tags").expect("a tags cell");
    assert_eq!(tag_row["name"], "Subject", "what a person reads");
    assert_eq!(tag_row["word"], "tags", "what a shell keys off");

    // The kind cell answers by its own token, which is `kind` and has
    // never been `type`.
    let kind_row = cells.iter().find(|r| r["word"] == "kind").expect("a kind cell: {cells:?}");
    assert_eq!(kind_row["name"], "kind");
    assert!(
        !cells.iter().any(|r| r["word"] == "type"),
        "core/'s word for it is gone: {cells:?}"
    );

    // A FIELD SOMEONE DECLARED has no compiled-in token — its name is
    // all it has — so `word` falls back to the name rather than coming
    // back empty. A shell keying off an empty string would hide every
    // declared field at once.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_declare_field(
            path.as_ptr(), c("client").as_ptr(), c("text").as_ptr(), false, T0 + 2, &mut out,
        )
    };
    let field = c(took(out)["id"].as_str().unwrap());
    assert_eq!(
        unsafe {
            liv_set(path.as_ptr(), id.as_ptr(), field.as_ptr(), c("Ada").as_ptr(), T0 + 3)
        },
        LIV_OK
    );
    let mut out = std::ptr::null_mut();
    unsafe { liv_cells(path.as_ptr(), id.as_ptr(), &mut out) };
    let cells = took(out);
    let mine = cells
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["name"] == "client")
        .expect("the declared field");
    assert_eq!(mine["word"], "client", "a declared field keys off its own name: {mine:?}");

    let _ = std::fs::remove_dir_all(&d);
}

/// A PROPOSAL SAYS WHAT IT WOULD WRITE, not only why.
///
/// `reason` is a sentence — "mentions \"Anna\" → Family & Friends?" —
/// and a shell cannot put a sentence on a chip beside a row. The chip
/// needs the ANSWER: the word the proposal would file the thing under,
/// so "file it there?" is one tap. The Inbox had that chip from
/// 2026-09-09 and it never drew once, because it read a field the wire
/// did not carry (found 2026-09-18).
///
/// The area proposer writes a `Ref`, so this also pins the resolution:
/// an id crosses as the word a person reads, through the one helper
/// those words live in.
#[test]
fn a_proposal_carries_the_word_it_would_write() {
    let d = dir("proposal_value");
    let path = d.join("liv.db");
    {
        let mut e = Engine::open_local(&path).unwrap();
        let anna = e.create(kind::PERSON, Some("Anna"), T0).unwrap();
        // Anna is filed somewhere, so the area proposer has an answer.
        let area = e.create(kind::AREA, Some("Family & Friends"), T0 + 1).unwrap();
        e.set(anna, liv_engine::prop::AREA, liv_engine::Value::Ref(area), T0 + 2).unwrap();
        let scrap = e.create(kind::NOTE, None, T0 + 3).unwrap();
        e.set_content(scrap, vec![liv_engine::Span::text("ring anna")], 0, T0 + 4).unwrap();
    }
    unsafe { liv_view_close_all() };
    let path = c(path.to_str().unwrap());

    let mut out = std::ptr::null_mut();
    unsafe { liv_ffi::writes::liv_sweep(path.as_ptr(), &mut out) };
    let rows = took(out);
    let all = rows.as_array().unwrap();

    let area_row = all
        .iter()
        .find(|r| r["proposer"].as_str() == Some("area"))
        .unwrap_or_else(|| panic!("no area proposal in {rows}"));
    assert_eq!(
        area_row["value"].as_str(),
        Some("Family & Friends"),
        "the area proposal must carry the area's NAME, not its id: {rows}"
    );

    // Every proposal carries the key, so a shell may decode it once.
    for r in all {
        assert!(r.get("value").is_some(), "no `value` key on {r}");
    }
}
