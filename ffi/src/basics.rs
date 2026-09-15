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
/// `[{"id":hex,"name":…,"completes":bool,"hue":n?}]`.
///
/// **`completes` and `hue` are the option's OWN answers**, added
/// 2026-09-15. Without them the vocabulary was three words with nothing
/// to choose between: the iOS ring writes "whichever option completes",
/// found none, wrote nothing, and a task could not be ticked. The engine
/// has held `prop::COMPLETES` all along and the row's `done` flag
/// already read it — only the picker was left guessing.
///
/// `completes` is always present, never omitted for a false: a missing
/// key and a `false` decode the same in Swift, and only one of them is
/// an answer. `hue` is absent when the option has not got one.
///
/// They mean something only for a status, and cost a cell read for
/// everything else — which is the price of one verb over two (standing
/// rule 4). A picker that does not care simply does not look.
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
        let mut rows = Vec::new();
        for (id, name) in e.options_for(property).map_err(|_| LIV_ERR_READ)? {
            rows.push(json!({
                "id": id.hex(),
                "name": name,
                // `liv_surface::completes` rather than the cell alone —
                // it also knows the frozen `status::DONE`, which carries
                // no cell because it has never needed one. Two readings
                // of "is this done" would be two answers (standing rule
                // 4); the row's own `done` flag goes through this too.
                "completes": liv_surface::completes(e, id).map_err(|_| LIV_ERR_READ)?,
                "hue": match e.one(id, liv_engine::prop::HUE).map_err(|_| LIV_ERR_READ)? {
                    Some(Value::Number(n)) => json!(n as i64),
                    _ => serde_json::Value::Null,
                },
            }));
        }
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

/// The id of a kind by its name, **the backstage ones included**.
/// `{"id":hex}`.
///
/// `liv_kinds` is the CREATE MENU's list, and `offered_kinds` leaves
/// `kind::WORKSPACE` and `kind::VIEW` out of it on purpose: a person
/// never picks one from a list. But the app MAKES both — a saved filter
/// is a View and a workspace is a Workspace — and that list was the
/// shell's only way to name a kind. So saving a new filter looked for
/// "view" among the six, did not find it, and wrote nothing: no filter,
/// and no error anyone could see (owner, 2026-09-15: "can't save new
/// filters"). A new workspace failed the same way.
///
/// This is the door `liv_property_named` is, for the reason written
/// there: a shell needs SOME way in, and hard-coding 32 hex characters
/// in Swift is worse than asking. It does NOT widen the picker — that
/// list is still the six, and a test says so.
///
/// Matched case-insensitively against the one place these words live
/// (`model::label`), so the shell may spell what it sees. `LIV_ERR_ARG`
/// for a word that is not a kind: the caller asked for something that
/// does not exist, which is not the same as an empty answer.
///
/// # Safety
/// `path` and `name` must be valid C strings; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_kind_named(
    path: *const c_char,
    name: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let name = match text_of(name) {
        Ok(s) => s.trim(),
        Err(e) => return e,
    };
    let Some(&id) = liv_engine::model::ALL_KINDS.iter().find(|&&k| {
        liv_engine::model::label(k).is_some_and(|l| l.eq_ignore_ascii_case(name))
    }) else {
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

/// Every property a person can put on something:
/// `[{"id":hex,"name":…,"holds":…,"many":bool}]`.
///
/// **The six the product names, then anything the user declared.** Not
/// every property that exists — most of them are plumbing the app needs
/// and never offers as a field to fill in, and a picker listing `trashed`
/// beside `due` would be the model leaking through the interface.
///
/// # Safety
/// `path` a valid C string; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_properties(path: *const c_char, out: *mut *mut c_char) -> i32 {
    match with_engine(path, |e| {
        let mut rows = Vec::new();
        for def in liv_engine::model::PROPS.iter().filter(|p| p.shown) {
            rows.push(json!({
                "id": def.id.hex(),
                // The CURRENT name, so a renamed field shows its new one.
                "name": e.display_name(def.id).unwrap_or(None).unwrap_or_else(|| def.name.to_owned()),
                // **THE TOKEN, beside the word.** `name` is what a person
                // reads and can rename; this is what the query grammar
                // lexes and what a shell keys its own rows off. They were
                // one string, so a property whose reading word differs
                // from its token — `tags`, which reads "Subject" — would
                // have broken every shell lookup that spelled it `tags`
                // (2026-09-16, added with `reads`).
                "word": def.name,
                "holds": holds_word(def.holds),
                "many": def.many,
                // **The vocabulary comes with the field.** A picker that
                // gets the field and not its options has an empty list,
                // and a picker with an empty list treats everything typed
                // into it as new — so choosing "Work" from the six that
                // exist tried to MINT a seventh called Work.
                "options": options_json(e, def.id),
            }));
        }
        for id in e.of_kind(liv_engine::model::kind::FIELD).map_err(|_| LIV_ERR_READ)? {
            if e.is_trashed(id).map_err(|_| LIV_ERR_READ)? {
                continue;
            }
            let shape = e.prop_shape(id).map_err(|_| LIV_ERR_READ)?;
            rows.push(json!({
                "id": id.hex(),
                "name": e.display_name(id).map_err(|_| LIV_ERR_READ)?,
                // A DECLARED field has no separate token: what it is
                // called is what it is called.
                "word": e.display_name(id).map_err(|_| LIV_ERR_READ)?,
                "holds": shape.map(|s| holds_word(s.holds)).unwrap_or("text"),
                "many": shape.map(|s| s.many).unwrap_or(false),
                "options": options_json(e, id),
            }));
        }
        Ok(serde_json::Value::Array(rows))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

fn options_json(e: &liv_engine::Engine, property: liv_engine::EntityId) -> serde_json::Value {
    serde_json::Value::Array(
        e.options_for(property)
            .unwrap_or_default()
            .into_iter()
            .map(|(id, name)| json!({ "id": id.hex(), "name": name }))
            .collect(),
    )
}

fn holds_word(h: liv_engine::model::Holds) -> &'static str {
    use liv_engine::model::Holds;
    match h {
        Holds::Text => "text",
        Holds::Number => "number",
        Holds::Bool => "bool",
        Holds::Date => "datetime",
        Holds::Ref | Holds::RefTo(_) => "reference",
        Holds::Blob => "file",
        Holds::Rich => "richtext",
    }
}

/// Turn the clerk on or off.
///
/// **The box owns where the switch lives.** `assist_enabled` answers by
/// looking for any live thing carrying an explicit no, so turning it off
/// means writing one and turning it back on means taking it away — which
/// is a rule about the model, not something a shell should have to know.
/// It was the last thing the old snapshot told the shell that the engine
/// did not.
///
/// Absent or true is ON, so turning it on removes the cell rather than
/// writing `true`: a box that has never said anything and a box that said
/// yes are the same box.
///
/// # Safety
/// `path` must be a valid C string.
#[no_mangle]
pub unsafe extern "C" fn liv_set_assist(path: *const c_char, on: bool, now_ms: u64) -> i32 {
    match with_engine(path, |e| {
        let prop = liv_engine::model::prop::AUTOMATION;
        let saying_no: Vec<liv_engine::EntityId> = e
            .with_value(prop, &Value::Bool(false))
            .map_err(|_| LIV_ERR_READ)?
            .into_iter()
            .filter(|id| !e.is_trashed(*id).unwrap_or(false))
            .collect();
        if on {
            for id in saying_no {
                e.unset(id, prop, now_ms).map_err(wrote)?;
            }
            return Ok(());
        }
        if !saying_no.is_empty() {
            // Already off. Writing a second no would be a second thing to
            // find and take away later.
            return Ok(());
        }
        let settings = e
            .create(liv_engine::model::kind::NOTE, Some("Settings"), now_ms)
            .map_err(wrote)?;
        e.set(settings, prop, Value::Bool(false), now_ms).map_err(wrote)?;
        Ok(())
    }) {
        Ok(()) => LIV_OK,
        Err(e) => e,
    }
}


/// Mint a new value for a property that points at things, and offer it.
/// `{"id":hex}`.
///
/// **The kind is whatever the property POINTS AT**, not always
/// `kind::OPTION`. `area` is `RefTo(kind::AREA)` and `status` is
/// `RefTo(kind::STATUS)`; minting an Option for either produces something
/// the cell will refuse, which is a new area that cannot be chosen.
///
/// It joins the property's declared `options` only when the property
/// declares any — a `RefTo` with no options list accepts anything of the
/// kind, and adding to a set nobody reads would be furniture with no
/// purpose.
///
/// Minting is a DECISION, so this is its own verb rather than something
/// `liv_set` does when a name does not match. Typing a typo must not
/// create a seventh area.
///
/// # Safety
/// `path`, `property` and `name` must be valid C strings; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_add_option(
    path: *const c_char,
    property: *const c_char,
    name: *const c_char,
    now_ms: u64,
    out: *mut *mut c_char,
) -> i32 {
    let property = match id_arg(property) {
        Ok(i) => i,
        Err(e) => return e,
    };
    let name = match text_of(name) {
        Ok(s) => s.trim(),
        Err(e) => return e,
    };
    if name.is_empty() {
        return LIV_ERR_REFUSED;
    }
    match with_engine(path, |e| {
        // Already called that? Hand back the one that exists rather than
        // a second thing with the same name.
        if let Some((id, _)) = e
            .options_for(property)
            .map_err(|_| LIV_ERR_READ)?
            .into_iter()
            .find(|(_, n)| n.eq_ignore_ascii_case(name))
        {
            return Ok(json!({ "id": id.hex() }));
        }
        let Some(shape) = e.prop_shape(property).map_err(|_| LIV_ERR_READ)? else {
            return Err(LIV_ERR_REFUSED);
        };
        let liv_engine::model::Holds::RefTo(class) = shape.holds else {
            // A text or number field has no vocabulary to add to.
            return Err(LIV_ERR_REFUSED);
        };
        let made = e.create(class, Some(name), now_ms).map_err(wrote)?;
        // Only where the property keeps a list. `area` keeps none and
        // takes anything of its kind, so a minted area is choosable the
        // moment it exists.
        if !e.cell(property, liv_engine::prop::OPTIONS).map_err(|_| LIV_ERR_READ)?.is_empty() {
            e.add(property, liv_engine::prop::OPTIONS, Value::Ref(made), now_ms).map_err(wrote)?;
        }
        Ok(json!({ "id": made.hex() }))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}
