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
