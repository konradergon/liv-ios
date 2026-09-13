//! The verbs every tap uses, across the C ABI.
//!
//! Without these a shell on the engine can read and never touch: no
//! capture, no create, no ticking a checkbox, no filing, no trash. They
//! are the difference between the swap being possible and being an
//! amputation.

use std::ffi::{CStr, CString};

use liv_engine::{kind, prop, Engine};
use liv_ffi::basics::*;
use liv_ffi::surfaces::{liv_view_close_all, LIV_ERR_ARG, LIV_OK};
use liv_ffi::writes::{LIV_ERR_REFUSED, LIV_ERR_STALE};
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

/// **The words come from the box, never from the shell.** The current
/// tree keeps the six area names as a Swift constant, which
/// `one-core.md` §4 records as a mistake.
#[test]
fn a_picker_asks_the_box_for_its_words() {
    let (d, path) = box_at("options");
    let area = prop_id(&path, "area");

    let mut out = std::ptr::null_mut();
    assert_eq!(unsafe { liv_options(path.as_ptr(), area.as_ptr(), &mut out) }, LIV_OK);
    let rows = took(out);
    let names: Vec<&str> = rows.as_array().unwrap().iter().map(|r| r["name"].as_str().unwrap()).collect();
    assert_eq!(
        names,
        vec!["Work", "Health", "Money", "Home", "Family & Friends", "Learning"],
        "the six, in product order, spelled by the box"
    );

    // A user's own area joins the same list, because that is what the
    // cell accepts — one rule, not two.
    let mut out = std::ptr::null_mut();
    unsafe {
        liv_make(path.as_ptr(), c(&kind::AREA.hex()).as_ptr(), c("Woodworking").as_ptr(), T0, &mut out)
    };
    took(out);
    let mut out = std::ptr::null_mut();
    unsafe { liv_options(path.as_ptr(), area.as_ptr(), &mut out) };
    let rows = took(out);
    assert_eq!(rows.as_array().unwrap().len(), 7);
    assert_eq!(rows[6]["name"], "Woodworking");

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
