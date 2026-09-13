//! The engine's write verbs, and the editor's reads that go with them.
//!
//! **This is what slice 5a is named for.** The engine has had `set`,
//! `add`, `remove`, `trash`, `restore`, `undo`, `set_content`,
//! `rename_value`, `add_file` and the clerk's queue for a while, all
//! tested — and nothing in the ABI reached any of them, so no shell could
//! do anything but read. These are the doors.
//!
//! Same shape as `surfaces.rs`: `LIV_OK` or a negative code, the answer
//! through an out-pointer, ids as 32 hex characters, the connection held
//! per box. Two codes are new because these can fail in two ways a read
//! cannot — a save against a body that moved, and a write the model
//! refuses.
//!
//! **A body crosses in the shell's own span JSON** (`spans.rs`), so
//! `Editor.swift` needs no change when the data source swaps. The one
//! difference is that a `Ref` is hex rather than a number, and `LivID`'s
//! decoder was built in slice 4 to take both.

use std::ffi::{c_char, CStr};

use liv_engine::{ContentError, Proposal, RenameError, Resync};
use serde_json::json;

use crate::spans;
use crate::surfaces::{
    deliver, parse_id, with_engine, LIV_ERR_ARG, LIV_ERR_READ, LIV_OK,
};

/// The stored body moved since `base` was read. **Not an error to retry
/// blindly**: the caller re-reads and decides, which is the whole of why
/// there is no force flag.
pub const LIV_ERR_STALE: i32 = -6;
/// The write is not one the box will take — a value of the wrong kind, a
/// link to nothing, an ambiguous rename. The caller is wrong, not the box.
pub const LIV_ERR_REFUSED: i32 = -7;
/// There was nothing to undo or redo. Distinct from a failure, because a
/// shell asking on an empty box is not a shell doing anything wrong.
pub const LIV_ERR_NOTHING: i32 = -8;

/// A C string, or a code.
fn text<'a>(p: *const c_char, code: i32) -> Result<&'a str, i32> {
    if p.is_null() {
        return Err(code);
    }
    unsafe { CStr::from_ptr(p) }.to_str().map_err(|_| code)
}

fn id_arg(p: *const c_char) -> Result<liv_engine::EntityId, i32> {
    parse_id(text(p, LIV_ERR_ARG)?).ok_or(LIV_ERR_ARG)
}

// ---- the editor --------------------------------------------------------

/// One body and the fingerprint to save against.
///
/// `{"spans":[…],"print":N}`. **Zero is never a real fingerprint** — it is
/// what "no body yet" reads as, so a first save needs no special case.
///
/// # Safety
/// `path` and `id` must be valid C strings; `out` must be a valid pointer
/// to a `char *` the caller frees with `liv_string_free`.
#[no_mangle]
pub unsafe extern "C" fn liv_read_body(
    path: *const c_char,
    id: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let id = match id_arg(id) {
        Ok(i) => i,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let (spans, print) = e.content(id).map_err(|_| LIV_ERR_READ)?;
        Ok(json!({ "spans": spans::to_json(&spans), "print": print }))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Replace a body, compare-and-swap on `base`.
///
/// `{"print":N}` with the fresh fingerprint. `LIV_ERR_STALE` when the
/// stored body moved — **re-read, never overwrite**; there is no force
/// flag by design. Empty spans clear the body.
///
/// # Safety
/// As `liv_read_body`, plus `spans` a valid C string of span JSON.
#[no_mangle]
pub unsafe extern "C" fn liv_write_body(
    path: *const c_char,
    id: *const c_char,
    spans_json: *const c_char,
    base: u64,
    now_ms: u64,
    out: *mut *mut c_char,
) -> i32 {
    let id = match id_arg(id) {
        Ok(i) => i,
        Err(e) => return e,
    };
    let raw = match text(spans_json, LIV_ERR_ARG) {
        Ok(s) => s,
        Err(e) => return e,
    };
    let Some(spans) = spans::from_json(raw) else { return LIV_ERR_ARG };

    match with_engine(path, |e| match e.set_content(id, spans, base, now_ms) {
        Ok(print) => Ok(json!({ "print": print })),
        Err(ContentError::Stale) => Err(LIV_ERR_STALE),
        Err(ContentError::Invalid) => Err(LIV_ERR_REFUSED),
        Err(ContentError::Write(_)) => Err(LIV_ERR_READ),
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Every past version of one body, NEWEST first.
///
/// `[{"device","seq","at_ms","author","spans"}]`. Restoring one is an
/// ordinary `liv_write_body` of its spans over a freshly read base — the
/// log is never rewritten, so a restore is itself a version.
///
/// # Safety
/// As `liv_read_body`.
#[no_mangle]
pub unsafe extern "C" fn liv_body_history(
    path: *const c_char,
    id: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let id = match id_arg(id) {
        Ok(i) => i,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let versions = e.content_history(id).map_err(|_| LIV_ERR_READ)?;
        Ok(serde_json::Value::Array(
            versions
                .into_iter()
                .map(|v| {
                    json!({
                        "device": hex_bytes(&v.dot.device.0),
                        "seq": v.dot.seq,
                        "at_ms": v.at_ms,
                        "author": match &v.author {
                            liv_engine::Author::User => "user".to_owned(),
                            liv_engine::Author::Proposer(n) => n.clone(),
                        },
                        "spans": spans::to_json(&v.spans),
                    })
                })
                .collect(),
        ))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Both directions of one thing's links: `{"out":[hex],"in":[hex]}`.
///
/// A `[[ ]]` typed in a body is the same edge as a link picked in
/// properties — the fold indexes both — so this is the only reader either
/// list needs.
///
/// # Safety
/// As `liv_read_body`.
#[no_mangle]
pub unsafe extern "C" fn liv_links(
    path: *const c_char,
    id: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let id = match id_arg(id) {
        Ok(i) => i,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let from: Vec<String> =
            e.links_from(id).map_err(|_| LIV_ERR_READ)?.into_iter().map(|i| i.hex()).collect();
        let to: Vec<String> =
            e.links_to(id).map_err(|_| LIV_ERR_READ)?.into_iter().map(|i| i.hex()).collect();
        Ok(json!({ "out": from, "in": to }))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

// ---- undo --------------------------------------------------------------

/// What undo and redo would take, without taking it:
/// `{"undo":bool,"redo":bool}` — what a toolbar needs to know whether its
/// buttons are live.
///
/// # Safety
/// `path` a valid C string; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_undo_state(path: *const c_char, out: *mut *mut c_char) -> i32 {
    match with_engine(path, |e| {
        Ok(json!({
            "undo": e.undoable().map_err(|_| LIV_ERR_READ)?.is_some(),
            "redo": e.redoable().map_err(|_| LIV_ERR_READ)?.is_some(),
        }))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Take back this device's last action. `LIV_ERR_NOTHING` when there is
/// none — which is an answer, not a failure.
///
/// # Safety
/// `path` must be a valid C string.
#[no_mangle]
pub unsafe extern "C" fn liv_undo(path: *const c_char, now_ms: u64) -> i32 {
    match with_engine(path, |e| match e.undo(now_ms) {
        Ok(_) => Ok(()),
        Err(liv_engine::WriteError::NothingToUndo) => Err(LIV_ERR_NOTHING),
        Err(_) => Err(LIV_ERR_READ),
    }) {
        Ok(()) => LIV_OK,
        Err(e) => e,
    }
}

/// And put it back.
///
/// # Safety
/// As `liv_undo`.
#[no_mangle]
pub unsafe extern "C" fn liv_redo(path: *const c_char, now_ms: u64) -> i32 {
    match with_engine(path, |e| match e.redo(now_ms) {
        Ok(_) => Ok(()),
        Err(liv_engine::WriteError::NothingToRedo) => Err(LIV_ERR_NOTHING),
        Err(_) => Err(LIV_ERR_READ),
    }) {
        Ok(()) => LIV_OK,
        Err(e) => e,
    }
}

// ---- vocabulary --------------------------------------------------------

/// Rename one value of a property, everywhere it is carried.
///
/// `{"carriers":N}` — how many things changed on screen, which for a
/// select is not the number of writes: one write to the option's name
/// re-renders every carrier. Zero is a success, not a refusal.
///
/// `LIV_ERR_REFUSED` for an empty or unchanged name, a value nothing is
/// called, a property that does not rename, or an ambiguous rename —
/// which refuses rather than guessing, because two kinds sharing an
/// option name is the designed state of `status`.
///
/// # Safety
/// `path`, `property`, `old` and `new` must be valid C strings.
#[no_mangle]
pub unsafe extern "C" fn liv_rename_value(
    path: *const c_char,
    property: *const c_char,
    old: *const c_char,
    new: *const c_char,
    now_ms: u64,
    out: *mut *mut c_char,
) -> i32 {
    let property = match id_arg(property) {
        Ok(i) => i,
        Err(e) => return e,
    };
    let (old, new) = match (text(old, LIV_ERR_ARG), text(new, LIV_ERR_ARG)) {
        (Ok(a), Ok(b)) => (a, b),
        _ => return LIV_ERR_ARG,
    };
    match with_engine(path, |e| match e.rename_value(property, old, new, now_ms) {
        Ok(n) => Ok(json!({ "carriers": n })),
        Err(RenameError::Refused(_)) | Err(RenameError::Ambiguous(_)) => Err(LIV_ERR_REFUSED),
        Err(RenameError::Write(_)) => Err(LIV_ERR_READ),
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

// ---- files -------------------------------------------------------------

/// Take a file into the box by reference. `{"id":hex}`.
///
/// **Never copies or moves it** — the file is read to hash it and left
/// where the user put it. An unreadable path is `LIV_ERR_REFUSED`, never
/// a phantom entity with a hash of nothing.
///
/// # Safety
/// `path` and `file` must be valid C strings.
#[no_mangle]
pub unsafe extern "C" fn liv_add_file(
    path: *const c_char,
    file: *const c_char,
    now_ms: u64,
    out: *mut *mut c_char,
) -> i32 {
    let file = match text(file, LIV_ERR_ARG) {
        Ok(s) => s,
        Err(e) => return e,
    };
    match with_engine(path, |e| match e.add_file(file, now_ms) {
        Ok(id) => Ok(json!({ "id": id.hex() })),
        Err(liv_engine::FileError::Unreadable(_)) => Err(LIV_ERR_REFUSED),
        Err(_) => Err(LIV_ERR_READ),
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Re-hash what a file points at on this device.
///
/// `{"state":"unchanged"|"changed"|"broken","path":…}`. A changed hash IS
/// the integration — it is how Liv learns Word saved the file — and a
/// vanished path is `broken`, which leaves the stored hash alone: a file
/// on an unplugged drive is not a file whose contents changed.
///
/// The path is included because a shell showing a broken reference wants
/// to say WHERE it was looking, and `null` is the honest answer for a file
/// that arrived by sync and has no copy here.
///
/// # Safety
/// As `liv_read_body`.
#[no_mangle]
pub unsafe extern "C" fn liv_resync_file(
    path: *const c_char,
    id: *const c_char,
    now_ms: u64,
    out: *mut *mut c_char,
) -> i32 {
    let id = match id_arg(id) {
        Ok(i) => i,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let state = e.resync_file(id, now_ms).map_err(|_| LIV_ERR_READ)?;
        let here = e.path_of(id).map_err(|_| LIV_ERR_READ)?;
        Ok(json!({
            "state": match state {
                Resync::Unchanged => "unchanged",
                Resync::Changed(_) => "changed",
                Resync::Broken => "broken",
            },
            "path": here,
        }))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

// ---- the clerk ---------------------------------------------------------

/// What the clerk would suggest, as the inbox reads it.
///
/// `[{"entity":hex,"print":N,"proposer":…,"reason":…}]`. **A proposal is
/// named by the thing it is about and its fingerprint, never its
/// position**: the sweep is a pure function of the box and is recomputed
/// in every process, so an index would mean something different by the
/// time the user tapped it. Accepting or declining passes both back — the
/// fingerprint is the consent, the entity is what makes re-deriving it
/// cost one thing rather than the whole box.
///
/// A proposal with no ops proposes nothing and is left out, so `entity` is
/// always there: a row the shell is shown must be a row it can act on.
///
/// # Safety
/// `path` a valid C string; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_sweep(path: *const c_char, out: *mut *mut c_char) -> i32 {
    match with_engine(path, |e| {
        let found = liv_surface::clerk::sweep(e).map_err(|_| LIV_ERR_READ)?;
        Ok(serde_json::Value::Array(
            found
                .iter()
                .filter_map(|p| {
                    let entity = p.ops.first()?.entity().hex();
                    Some(json!({
                        "entity": entity,
                        "print": p.fingerprint(),
                        "proposer": p.proposer,
                        "reason": p.reason,
                    }))
                })
                .collect(),
        ))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Say yes to one suggestion, named by the thing it is about and its
/// fingerprint.
///
/// The proposal is re-derived from the box rather than taken on trust,
/// which is the point: one the box no longer makes is one the user
/// already acted on, and `LIV_ERR_NOTHING` says so rather than writing
/// something stale.
///
/// **`entity` is what makes that affordable.** It comes straight off the
/// row `liv_sweep` returned, and it means the check re-reads one thing
/// instead of the whole box. Re-sweeping everything cost 120 ms in a
/// 500-note box — every tap in the inbox re-reading everything — against
/// 3 ms here, for the same guarantee: `sweep_one` is `sweep` narrowed,
/// and a test compares them entity by entity.
///
/// # Safety
/// `path` and `entity` must be valid C strings.
#[no_mangle]
pub unsafe extern "C" fn liv_accept(
    path: *const c_char,
    entity: *const c_char,
    print: u64,
    now_ms: u64,
) -> i32 {
    let entity = match id_arg(entity) {
        Ok(i) => i,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let Some(p) = find(e, entity, print)? else { return Err(LIV_ERR_NOTHING) };
        e.accept(&p, now_ms).map_err(|_| LIV_ERR_REFUSED)?;
        Ok(())
    }) {
        Ok(()) => LIV_OK,
        Err(e) => e,
    }
}

/// Say no. **Declining is not forgetting** — the refusal persists and the
/// clerk does not ask again.
///
/// It also TRAVELS (owner, 2026-09-13): a refusal is an op, so saying no
/// on the phone says no on the laptop too. That is why this takes a clock
/// where it used to take none — it is a write now, not a note to self.
///
/// # Safety
/// As `liv_accept`.
#[no_mangle]
pub unsafe extern "C" fn liv_decline(
    path: *const c_char,
    entity: *const c_char,
    print: u64,
    now_ms: u64,
) -> i32 {
    let entity = match id_arg(entity) {
        Ok(i) => i,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let Some(p) = find(e, entity, print)? else { return Err(LIV_ERR_NOTHING) };
        e.decline(&p, now_ms).map_err(|_| LIV_ERR_REFUSED)?;
        Ok(())
    }) {
        Ok(()) => LIV_OK,
        Err(e) => e,
    }
}

fn find(
    e: &liv_engine::Engine,
    entity: liv_engine::EntityId,
    print: u64,
) -> Result<Option<Proposal>, i32> {
    let found = liv_surface::clerk::sweep_one(e, entity).map_err(|_| LIV_ERR_READ)?;
    Ok(found.into_iter().find(|p| p.fingerprint() == print))
}

fn hex_bytes(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
