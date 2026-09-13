//! The verbs every tap uses: make a thing, change a cell, throw it away.
//!
//! **`writes.rs` was the editor's doors; these are the app's.** That
//! batch reached bodies, undo, files, renames and the clerk — everything
//! the editor and the inbox need — and left the engine unable to do the
//! ordinary things: capture a scrap, tick a checkbox, file something
//! under Work, put it in the trash. Those are what the six screens are
//! made of, and without them a shell on the engine can read and never
//! touch.
//!
//! **A value crosses as TEXT, and the property says what it means.** The
//! shell sends "yes", "3", "2026-09-13", "Work"; whether that is a bool,
//! a number, a date or an option is a fact about the property, which the
//! box already knows (`engine/src/value.rs`). The alternative — the shell
//! declaring the type of everything it sends — puts the model in two
//! places and makes every new field a Swift change. `LIV_ERR_REFUSED`
//! comes back with nothing written when the text does not read.
//!
//! A property is named by its ID, not its name. `core/`'s `liv_set_at`
//! takes a name and looks it up, which quietly makes renaming a field
//! break every caller that spelled it; the shell already holds ids.

use std::ffi::c_char;

use liv_engine::{value::ValueError, EntityId, Value, WriteError};
use serde_json::json;

use crate::surfaces::{deliver, with_engine, LIV_ERR_ARG, LIV_ERR_READ, LIV_OK};
use crate::writes::{id_arg, text, LIV_ERR_REFUSED};

/// Refused, and never a read failure: a value that will not parse is the
/// caller being wrong, which is a different thing from the box breaking.
fn refused<T>(_: ValueError) -> Result<T, i32> {
    Err(LIV_ERR_REFUSED)
}

fn wrote(e: WriteError) -> i32 {
    match e {
        WriteError::Refused(_) => LIV_ERR_REFUSED,
        _ => LIV_ERR_READ,
    }
}

// ---- making things -----------------------------------------------------

/// Make one thing of a kind, optionally named. `{"id":hex}`.
///
/// `name` may be null for something born untitled — a scrap the user is
/// about to type into, which is the common case and not an error.
///
/// # Safety
/// `path` and `kind` must be valid C strings; `name` may be null; `out`
/// must be a valid pointer to a `char *` freed with `liv_string_free`.
#[no_mangle]
pub unsafe extern "C" fn liv_make(
    path: *const c_char,
    kind: *const c_char,
    name: *const c_char,
    now_ms: u64,
    out: *mut *mut c_char,
) -> i32 {
    let kind = match id_arg(kind) {
        Ok(i) => i,
        Err(e) => return e,
    };
    let name = if name.is_null() {
        None
    } else {
        match text_of(name) {
            Ok(s) => Some(s),
            Err(e) => return e,
        }
    };
    match with_engine(path, |e| match e.create(kind, name, now_ms) {
        Ok(id) => Ok(json!({ "id": id.hex() })),
        Err(err) => Err(wrote(err)),
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Capture a scrap: one untyped note whose body is this text, in ONE
/// action. `{"id":hex}`.
///
/// **Untyped on purpose.** A capture is a thought, not a decision about
/// what kind of thing it is — the clerk's promotion proposer is what
/// offers to make it a task later, and it can only offer that because
/// nothing here decided first.
///
/// One action, so one undo takes the whole capture back rather than
/// leaving an empty note behind.
///
/// # Safety
/// `path` and `text` must be valid C strings; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_capture(
    path: *const c_char,
    text: *const c_char,
    now_ms: u64,
    out: *mut *mut c_char,
) -> i32 {
    let text = match text_of(text) {
        Ok(s) => s,
        Err(e) => return e,
    };
    match with_engine(path, |e| match e.capture(text, now_ms) {
        Ok(id) => Ok(json!({ "id": id.hex() })),
        Err(err) => Err(wrote(err)),
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

// ---- changing cells ----------------------------------------------------

/// Set a register: replace whatever is in this cell.
///
/// # Safety
/// `path`, `entity`, `property` and `value` must be valid C strings.
#[no_mangle]
pub unsafe extern "C" fn liv_set(
    path: *const c_char,
    entity: *const c_char,
    property: *const c_char,
    value: *const c_char,
    now_ms: u64,
) -> i32 {
    cell_verb(path, entity, property, value, now_ms, Change::Set)
}

/// Add a member to a set — a tag, a person, one of several.
///
/// # Safety
/// As `liv_set`.
#[no_mangle]
pub unsafe extern "C" fn liv_add(
    path: *const c_char,
    entity: *const c_char,
    property: *const c_char,
    value: *const c_char,
    now_ms: u64,
) -> i32 {
    cell_verb(path, entity, property, value, now_ms, Change::Add)
}

/// Take a member out of a set. **Add-wins**: a member added concurrently
/// on another device survives this, which is why a tag added on the phone
/// is not lost by a removal on the laptop.
///
/// # Safety
/// As `liv_set`.
#[no_mangle]
pub unsafe extern "C" fn liv_remove(
    path: *const c_char,
    entity: *const c_char,
    property: *const c_char,
    value: *const c_char,
    now_ms: u64,
) -> i32 {
    cell_verb(path, entity, property, value, now_ms, Change::Remove)
}

enum Change {
    Set,
    Add,
    Remove,
}

fn cell_verb(
    path: *const c_char,
    entity: *const c_char,
    property: *const c_char,
    value: *const c_char,
    now_ms: u64,
    how: Change,
) -> i32 {
    let (entity, property) = match (id_arg(entity), id_arg(property)) {
        (Ok(a), Ok(b)) => (a, b),
        _ => return LIV_ERR_ARG,
    };
    let raw = match unsafe { text_of(value) } {
        Ok(s) => s,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let v: Value = match e.parse_value(property, raw) {
            Ok(v) => v,
            Err(err) => return refused(err),
        };
        match how {
            Change::Set => e.set(entity, property, v, now_ms),
            Change::Add => e.add(entity, property, v, now_ms),
            Change::Remove => e.remove(entity, property, &v, now_ms),
        }
        .map(|_| ())
        .map_err(wrote)
    }) {
        Ok(()) => LIV_OK,
        Err(e) => e,
    }
}

/// Empty a register. **Not the same as setting it to nothing** — an unset
/// cell has no value, which is what a picker's "None" means, and what a
/// date cleared off a task means.
///
/// # Safety
/// `path`, `entity` and `property` must be valid C strings.
#[no_mangle]
pub unsafe extern "C" fn liv_unset(
    path: *const c_char,
    entity: *const c_char,
    property: *const c_char,
    now_ms: u64,
) -> i32 {
    let (entity, property) = match (id_arg(entity), id_arg(property)) {
        (Ok(a), Ok(b)) => (a, b),
        _ => return LIV_ERR_ARG,
    };
    match with_engine(path, |e| e.unset(entity, property, now_ms).map(|_| ()).map_err(wrote)) {
        Ok(()) => LIV_OK,
        Err(e) => e,
    }
}

// ---- the trash ---------------------------------------------------------

/// Into the trash, and back out. **Trashing is a cell, not a deletion** —
/// nothing is removed from the log, which is what makes restore a write
/// rather than a resurrection.
///
/// # Safety
/// `path` and `entity` must be valid C strings.
#[no_mangle]
pub unsafe extern "C" fn liv_trash(
    path: *const c_char,
    entity: *const c_char,
    now_ms: u64,
) -> i32 {
    bin(path, entity, now_ms, true)
}

/// # Safety
/// As `liv_trash`.
#[no_mangle]
pub unsafe extern "C" fn liv_restore(
    path: *const c_char,
    entity: *const c_char,
    now_ms: u64,
) -> i32 {
    bin(path, entity, now_ms, false)
}

fn bin(path: *const c_char, entity: *const c_char, now_ms: u64, away: bool) -> i32 {
    let entity = match id_arg(entity) {
        Ok(i) => i,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        if away { e.trash(entity, now_ms) } else { e.restore(entity, now_ms) }
            .map(|_| ())
            .map_err(wrote)
    }) {
        Ok(()) => LIV_OK,
        Err(e) => e,
    }
}

// ---- what a picker needs -----------------------------------------------

/// Everything a `RefTo` property may point at, named and in order:
/// `[{"id":hex,"name":…}]`.
///
/// **The words come from the box, never from the shell.** The current
/// tree keeps the six area names as a Swift constant, which
/// `one-core.md` §4 records as a mistake: a shell that carries its own
/// copy of the furniture drifts from the box that stores it. A picker
/// asks.
///
/// Compiled-in furniture and a user's own come back in one list, because
/// that is what the cell accepts and a picker that separated them would
/// be inventing a distinction the model does not have.
///
/// # Safety
/// `path` and `property` must be valid C strings; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_options(
    path: *const c_char,
    property: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let property = match id_arg(property) {
        Ok(i) => i,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let rows: Vec<serde_json::Value> = e
            .options_for(property)
            .map_err(|_| LIV_ERR_READ)?
            .into_iter()
            .map(|(id, name)| json!({ "id": id.hex(), "name": name }))
            .collect();
        Ok(serde_json::Value::Array(rows))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// One thing's cells, as the inspector reads them:
/// `[{"property":hex,"name":…,"holds":…,"many":bool,"value":…,"ref":hex?,
///    "contended":bool}]`.
///
/// `value` is always the DISPLAY string, so a shell renders a row without
/// knowing the kind; `ref` carries the target when there is one, for a
/// row that is tappable. **`contended` is not decoration** — two devices
/// can leave a register holding two values, and the model's rule is that
/// nothing silently wins, so the shell has to be able to show the choice.
///
/// # Safety
/// `path` and `entity` must be valid C strings; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_cells(
    path: *const c_char,
    entity: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let entity = match id_arg(entity) {
        Ok(i) => i,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let rows: Vec<serde_json::Value> = e
            .inspect(entity)
            .map_err(|_| LIV_ERR_READ)?
            .into_iter()
            .map(|c| {
                json!({
                    "property": c.property.hex(),
                    "name": c.name,
                    "holds": c.holds,
                    "many": c.many,
                    "value": c.shown,
                    "ref": c.target.map(|t| t.hex()),
                    "contended": c.contended,
                })
            })
            .collect();
        Ok(serde_json::Value::Array(rows))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// The kinds a create menu offers: `[{"id":hex,"name":…}]`.
///
/// The six the product names, in product order — not every kind that
/// exists. `kind::WORKSPACE` and the rest are furniture the app draws
/// with, and a person never picks one from a list.
///
/// # Safety
/// `path` a valid C string; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_kinds(path: *const c_char, out: *mut *mut c_char) -> i32 {
    match with_engine(path, |e| {
        let rows: Vec<serde_json::Value> = e
            .offered_kinds()
            .map_err(|_| LIV_ERR_READ)?
            .into_iter()
            .map(|(id, name)| json!({ "id": id.hex(), "name": name }))
            .collect();
        Ok(serde_json::Value::Array(rows))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// The id of a compiled-in property by its stable name — `"due"`,
/// `"status"`, `"area"`. `{"id":hex}`.
///
/// **A shell needs SOME way in.** Every other verb here names a property
/// by id, which is right (a rename must not break a caller), but the
/// first id has to come from somewhere and hard-coding 32 hex characters
/// in Swift is worse than asking. These names are frozen — they are the
/// ones `op-format.md` calls ordinals-on-disk-forever — so this is a
/// lookup of something stable, not of a label a user can change.
///
/// # Safety
/// `path` and `name` must be valid C strings; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_property_named(
    path: *const c_char,
    name: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let name = match text_of(name) {
        Ok(s) => s,
        Err(e) => return e,
    };
    let Some(id) = liv_engine::model::PROPS.iter().find(|p| p.name == name).map(|p| p.id) else {
        return LIV_ERR_ARG;
    };
    let _: EntityId = id;
    match with_engine(path, |_| Ok(json!({ "id": id.hex() }))) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// A C string argument, or `LIV_ERR_ARG`.
///
/// # Safety
/// `p` must be null or a valid C string.
unsafe fn text_of<'a>(p: *const c_char) -> Result<&'a str, i32> {
    text(p, LIV_ERR_ARG)
}

// ---- the last three, found by mapping the old ABI verb by verb --------

/// Declare a field the app did not ship with — the product's "new kind of
/// field behind a door in Settings". `{"id":hex}`.
///
/// `holds` is one of `text`, `number`, `bool`, `datetime`, `reference`,
/// `richtext`, `file`; `many` makes it a set rather than a register.
/// `LIV_ERR_REFUSED` for a shape the model does not have.
///
/// **It is an ordinary entity, minted ONCE on one device**, which is what
/// stops it drifting the way a seeded copy does: there is no second copy
/// to disagree with. That is the whole of the argument in §2 of
/// `rust-owns-the-mechanisms.md` — what Liv ships with is compiled in,
/// what the box adds is an entity.
///
/// # Safety
/// `path`, `name` and `holds` must be valid C strings; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_declare_field(
    path: *const c_char,
    name: *const c_char,
    holds: *const c_char,
    many: bool,
    now_ms: u64,
    out: *mut *mut c_char,
) -> i32 {
    let (name, holds) = match (text_of(name), text_of(holds)) {
        (Ok(a), Ok(b)) => (a, b),
        _ => return LIV_ERR_ARG,
    };
    match with_engine(path, |e| match e.declare_field(name, holds, many, now_ms) {
        Ok(id) => Ok(json!({ "id": id.hex() })),
        Err(err) => Err(wrote(err)),
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Accept several suggestions as ONE action. `{"taken":N}`.
///
/// **All or nothing, and one undo.** Half a consent is worse than none:
/// the user agreed to a set, and a set that half-landed is not what they
/// agreed to. One group, so one undo takes the lot back.
///
/// `entities` and `prints` are parallel arrays of `count` items — each
/// proposal named the way `liv_accept` names one, because a fingerprint
/// alone would mean re-deriving the whole box to find it.
///
/// A fingerprint the box no longer proposes is SKIPPED rather than
/// failing the batch: the inbox's "accept all" is a sweep of what is on
/// screen, and one row the user already dealt with on another device is
/// not a reason to refuse the other nine. `taken` says how many landed.
/// `LIV_ERR_NOTHING` when none of them did.
///
/// # Safety
/// `path` a valid C string; `entities` must point at `count` valid C
/// strings and `prints` at `count` `uint64_t`s; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_accept_all(
    path: *const c_char,
    entities: *const *const c_char,
    prints: *const u64,
    count: u32,
    now_ms: u64,
    out: *mut *mut c_char,
) -> i32 {
    if count == 0 {
        return crate::writes::LIV_ERR_NOTHING;
    }
    if entities.is_null() || prints.is_null() {
        return LIV_ERR_ARG;
    }
    let n = count as usize;
    let mut wanted = Vec::with_capacity(n);
    for i in 0..n {
        let entity = match id_arg(*entities.add(i)) {
            Ok(id) => id,
            Err(e) => return e,
        };
        wanted.push((entity, *prints.add(i)));
    }

    match with_engine(path, |e| {
        let mut found = Vec::new();
        // Grouped by entity, so each thing is swept once however many of
        // its suggestions were ticked.
        let mut by_entity: Vec<(liv_engine::EntityId, Vec<u64>)> = Vec::new();
        for (entity, print) in &wanted {
            match by_entity.iter_mut().find(|(id, _)| id == entity) {
                Some((_, ps)) => ps.push(*print),
                None => by_entity.push((*entity, vec![*print])),
            }
        }
        for (entity, prints) in by_entity {
            let here = liv_surface::clerk::sweep_one(e, entity).map_err(|_| LIV_ERR_READ)?;
            for p in here {
                if prints.contains(&p.fingerprint()) {
                    found.push(p);
                }
            }
        }
        if found.is_empty() {
            return Err(crate::writes::LIV_ERR_NOTHING);
        }
        let taken = found.len();
        e.accept_all(&found, now_ms).map_err(wrote)?;
        Ok(json!({ "taken": taken }))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Why the box will not open: `{"code":…,"message":…}`, or `{"code":"ok"}`
/// when it opens fine.
///
/// **A shell that cannot open the box has nothing else to ask.** Every
/// other verb here answers `LIV_ERR_OPEN`, which says that it failed and
/// not what to do about it — and the four answers need four different
/// screens. `version` means the box was written by a newer build and the
/// user should update, which is the one a wrong answer strands someone on.
///
/// Codes: `ok` | `version` | `corrupt` | `io`.
///
/// # Safety
/// `path` must be a valid C string; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_probe_box(path: *const c_char, out: *mut *mut c_char) -> i32 {
    let raw = match text_of(path) {
        Ok(s) => s,
        Err(e) => return e,
    };
    let answer = match liv_engine::Engine::open_local(std::path::Path::new(raw)) {
        Ok(_) => json!({ "code": "ok", "message": serde_json::Value::Null }),
        Err(liv_engine::LogError::UnsupportedBox { found, supported }) => json!({
            "code": "version",
            "message": format!("this box was written by a newer version of Liv (format {found}; this build reads {supported})"),
        }),
        Err(liv_engine::LogError::Decode(d)) => json!({
            "code": "corrupt",
            "message": format!("the box could not be read: {d:?}"),
        }),
        Err(liv_engine::LogError::Sqlite(e)) => json!({
            // A locked file, a missing folder, no permission — all the
            // same to a person: something about WHERE it is, not what is
            // in it.
            "code": "io",
            "message": e,
        }),
    };
    // The connection above was opened outside the pool, and dropping it
    // here is what keeps a probe from holding a box a retry needs.
    deliver(out, &answer)
}
