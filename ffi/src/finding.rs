//! Finding things: search, the query grammar, and the furniture a
//! workspace is made of.
//!
//! **The last of the gap the 5b audit found.** `surface/src/search.rs`
//! and `engine/src/query.rs` were both built and tested and neither had
//! a door — the same shape as the write verbs before `writes.rs`, one
//! layer along. Search is the app's navigation; without it the swap
//! takes away the way people find anything.
//!
//! ## Two jobs, one grammar
//!
//! The same text means two different things depending on where it is
//! typed, and the parser is told which:
//!
//! - **A search box WIDENS.** `is:archived` means "look in the archive
//!   too", because someone searching for a thing wants it found.
//! - **A lens RESTRICTS.** The same `is:archived` in a workspace filter
//!   means "only archived things", because a filter is a boundary.
//!
//! One parser either way (standing rule 4). `liv_search` is the first,
//! `liv_lens` the second, and they are separate verbs rather than a
//! flag because the two answers are shaped differently: a search is
//! ranked hits with facets, a lens is a flat set of ids.
//!
//! ## A user never types this
//!
//! Standing rule 5: the text grammar is the storage format and an
//! advanced escape hatch, not the interface. `liv_terms` exists so a
//! shell can show a stored filter as chips a person edits by tapping —
//! it turns text into the pieces a picker draws, so that the picker,
//! and not a text field, is what the user actually uses.

use std::ffi::c_char;

use liv_engine::{prop, EntityId, Value};
use liv_surface::search::{self, Field, Mode};
use serde_json::json;

use crate::surfaces::{deliver, with_engine, LIV_ERR_ARG, LIV_ERR_READ};
use crate::writes::{id_arg, text};

fn text_of<'a>(p: *const c_char) -> Result<&'a str, i32> {
    text(p, LIV_ERR_ARG)
}

/// Ranked hits and the facet rows beside them.
///
/// `{"hits":[{"id":hex,"score":N,"field":…}],
///   "facets":[{"property":hex,"label":…,
///              "values":[{"label","count","active","excluded"}]}]}`
///
/// `field` says WHERE the best match was — `name`, `cell`, `filed`,
/// `content`, or `structured` for a pure-qualifier hit — so a row can
/// hint why it is in the list rather than leaving the user to guess.
///
/// **`limit` bounds the hits, never the facets.** A facet count is over
/// everything the query matches: a row saying "Work 12" when the list
/// shows 10 is telling the truth about the box, and a count that changed
/// with how far the user had scrolled would be useless for pivoting.
///
/// # Safety
/// `path` and `query` must be valid C strings; `out` must be a valid
/// pointer to a `char *` freed with `liv_string_free`.
#[no_mangle]
pub unsafe extern "C" fn liv_search(
    path: *const c_char,
    query: *const c_char,
    limit: u32,
    out: *mut *mut c_char,
) -> i32 {
    let raw = match text_of(query) {
        Ok(s) => s,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let s = search::parse(e, raw).map_err(|_| LIV_ERR_READ)?;
        // Zero means "no ceiling" rather than "no results": a caller that
        // did not think about paging wants the answer, not an empty list.
        let cap = if limit == 0 { usize::MAX } else { limit as usize };
        let hits: Vec<serde_json::Value> = search::search(e, &s, cap)
            .map_err(|_| LIV_ERR_READ)?
            .into_iter()
            .map(|h| {
                json!({ "id": h.id.hex(), "score": h.score, "field": field_word(h.field) })
            })
            .collect();

        let mut facets = Vec::new();
        for property in search::facet_properties(e, &s).map_err(|_| LIV_ERR_READ)? {
            let f = search::facet(e, &s, property).map_err(|_| LIV_ERR_READ)?;
            if f.values.is_empty() {
                continue;
            }
            facets.push(json!({
                "property": f.property.hex(),
                "label": f.label,
                "values": f.values.iter().map(|v| json!({
                    "label": v.label,
                    "count": v.count,
                    // Include → exclude → off is a three-state cycle, so
                    // the chip needs both flags rather than one.
                    "active": v.active,
                    "excluded": v.excluded,
                })).collect::<Vec<_>>(),
            }));
        }
        Ok(json!({ "hits": hits, "facets": facets }))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

fn field_word(f: Field) -> &'static str {
    match f {
        Field::Name => "name",
        Field::Cell => "cell",
        Field::Filed => "filed",
        Field::Content => "content",
        Field::Structured => "structured",
    }
}

/// The ids a LENS admits: `{"ids":[hex],"terms":[…]}`.
///
/// The same grammar as `liv_search` read the other way round —
/// `is:archived` RESTRICTS here where it widens there — because a
/// workspace filter is a boundary and a search is a hunt.
///
/// The lexed terms come back with the ids so a shell can draw the filter
/// as chips in the same breath it applies it, without parsing the text
/// itself (standing rule 4).
///
/// # Safety
/// As `liv_search`.
#[no_mangle]
pub unsafe extern "C" fn liv_lens(
    path: *const c_char,
    query: *const c_char,
    out: *mut *mut c_char,
) -> i32 {
    let raw = match text_of(query) {
        Ok(s) => s,
        Err(e) => return e,
    };
    match with_engine(path, |e| {
        let s = search::parse_mode(e, raw, Mode::Lens).map_err(|_| LIV_ERR_READ)?;
        // Everything the lens admits, in the box's own order — a lens is
        // a boundary, not a ranking, so there is nothing to score.
        let ids: Vec<String> = search::search(e, &s, usize::MAX)
            .map_err(|_| LIV_ERR_READ)?
            .into_iter()
            .map(|h| h.id.hex())
            .collect();
        Ok(json!({ "ids": ids, "terms": lexed(raw) }))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Split a query into its terms — no box, no lock, no opinion about
/// whether a property exists.
///
/// Named `liv_terms` rather than `liv_lex` because the core-era ABI
/// already exports a `liv_lex` over `core/`'s grammar. Both live until
/// `core/` goes; every engine verb is purely additive, and a collision
/// would be the one way to break the old shell while replacing it.
///
/// `[{"op":…,"key":…,"value":…,"raw":…}]`. `raw` is the term respelled
/// canonically, so joining a term list back together reproduces a query
/// the parser reads the same way — which is what lets a shell edit a
/// filter as chips and write the result back as text.
///
/// **This is what keeps standing rule 5 true.** The user never types the
/// grammar; the grammar is the storage format, and this is how a picker
/// reads it.
///
/// # Safety
/// `query` must be a valid C string; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_terms(query: *const c_char, out: *mut *mut c_char) -> i32 {
    let raw = match text_of(query) {
        Ok(s) => s,
        Err(e) => return e,
    };
    deliver(out, &lexed(raw))
}

fn lexed(raw: &str) -> serde_json::Value {
    serde_json::Value::Array(
        liv_engine::query::lex(raw)
            .into_iter()
            .map(|t| {
                json!({
                    "op": match t.op {
                        liv_engine::query::TermOp::Equals => "equals",
                        liv_engine::query::TermOp::NotEquals => "not-equals",
                        liv_engine::query::TermOp::AtMost => "at-most",
                        liv_engine::query::TermOp::Has => "has",
                        liv_engine::query::TermOp::No => "no",
                        liv_engine::query::TermOp::Is => "is",
                        liv_engine::query::TermOp::Text => "text",
                    },
                    "key": t.key,
                    "value": t.value,
                    "raw": t.raw,
                })
            })
            .collect::<Vec<_>>(),
    )
}

// ---- what a picker offers ----------------------------------------------

/// Every value this property is actually carrying, commonest first:
/// `[{"label":…,"ref":hex?,"count":N}]`.
///
/// **A different question from `liv_options`.** That asks what a cell MAY
/// hold; this asks what it does. A free-text field has no options and
/// still wants to offer what the user has typed before, and a facet row
/// counting areas wants the ones in use rather than the six that exist.
///
/// Trashed things are left out: offering what the trash holds is offering
/// someone their own deletions back.
///
/// # Safety
/// `path` and `property` must be valid C strings; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_values_in_use(
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
            .values_in_use(property)
            .map_err(|_| LIV_ERR_READ)?
            .into_iter()
            .map(|v| json!({ "label": v.label, "ref": v.target.map(|t| t.hex()), "count": v.count }))
            .collect();
        Ok(serde_json::Value::Array(rows))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// Every file reference this device cannot open:
/// `[{"id":hex,"name":…,"path":…|null,"why":"absent"|"gone"}]`.
///
/// **A hash travels and a path does not**, which is why the two states
/// are told apart rather than both being called broken. A file added on
/// the laptop reaches the phone as a real, valid reference with no local
/// copy — `absent`, and the answer is "find it for me". A path this
/// device knows that no longer holds a file is `gone`, and that one is
/// broken.
///
/// Neither touches the stored hash: a file on an unplugged drive is not a
/// file whose contents changed.
///
/// # Safety
/// `path` a valid C string; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_file_alerts(path: *const c_char, out: *mut *mut c_char) -> i32 {
    match with_engine(path, |e| {
        let rows: Vec<serde_json::Value> = e
            .file_alerts()
            .map_err(|_| LIV_ERR_READ)?
            .into_iter()
            .map(|a| {
                json!({ "id": a.entity.hex(), "name": a.name, "path": a.path, "why": a.why })
            })
            .collect();
        Ok(serde_json::Value::Array(rows))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

// ---- workspaces and saved filters --------------------------------------

/// The workspace tree:
/// `[{"id":hex,"name","emoji","favorite","archived","builtin","parent",
///    "order","query"}]`.
///
/// **A workspace is an ordinary entity**, so there is no verb here that
/// makes one: `liv_make` with the workspace kind and `liv_set` of its
/// cells already do, which is the whole point of the primitives existing.
/// This only reads.
///
/// Archived workspaces are INCLUDED, with the flag — the switcher shows
/// them behind a disclosure, and filtering them out here would take that
/// choice away from the shell.
///
/// # Safety
/// `path` a valid C string; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_workspaces(path: *const c_char, out: *mut *mut c_char) -> i32 {
    furniture(path, out, liv_engine::model::kind::WORKSPACE, true)
}

/// The saved filters: the same shape, and the same reason there is no
/// verb here that makes one.
///
/// # Safety
/// As `liv_workspaces`.
#[no_mangle]
pub unsafe extern "C" fn liv_views(path: *const c_char, out: *mut *mut c_char) -> i32 {
    furniture(path, out, liv_engine::model::kind::VIEW, false)
}

fn furniture(
    path: *const c_char,
    out: *mut *mut c_char,
    of: EntityId,
    tree: bool,
) -> i32 {
    match with_engine(path, |e| {
        let mut rows = Vec::new();
        for id in e.of_kind(of).map_err(|_| LIV_ERR_READ)? {
            if e.is_trashed(id).map_err(|_| LIV_ERR_READ)? {
                continue;
            }
            let one = |p: EntityId| e.one(id, p).unwrap_or(None);
            let as_text = |v: Option<Value>| match v {
                Some(Value::Text(s)) => Some(s),
                _ => None,
            };
            let as_bool = |v: Option<Value>| matches!(v, Some(Value::Bool(true)));
            let mut row = json!({
                "id": id.hex(),
                // Never an id as a name (§3a): a nameless workspace is
                // for the shell to title, and a hex string is not a name.
                "name": as_text(one(prop::NAME)),
                "query": as_text(one(prop::QUERY)),
            });
            if tree {
                let m = row.as_object_mut().unwrap();
                m.insert("emoji".into(), json!(as_text(one(prop::EMOJI))));
                m.insert("favorite".into(), json!(as_bool(one(prop::FAVORITE))));
                m.insert("archived".into(), json!(as_bool(one(prop::ARCHIVED))));
                m.insert("builtin".into(), json!(as_text(one(prop::BUILTIN))));
                m.insert(
                    "parent".into(),
                    json!(match one(prop::PARENT) {
                        Some(Value::Ref(p)) => Some(p.hex()),
                        _ => None,
                    }),
                );
                m.insert(
                    "order".into(),
                    json!(match one(prop::ORDER) {
                        Some(Value::Number(n)) => Some(n),
                        _ => None,
                    }),
                );
            }
            rows.push(row);
        }
        Ok(serde_json::Value::Array(rows))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}

/// The clerk's consent switch: `{"on":bool}`.
///
/// **Absent or true is ON; only an explicit `false` silences it** — an
/// older box that never set it is not a box that said no. Turning it off
/// is an ordinary `liv_set` of the automation property, which is why
/// there is no writer here.
///
/// # Safety
/// `path` a valid C string; `out` as above.
#[no_mangle]
pub unsafe extern "C" fn liv_assist(path: *const c_char, out: *mut *mut c_char) -> i32 {
    match with_engine(path, |e| {
        let on = liv_surface::clerk::assist_enabled(e).map_err(|_| LIV_ERR_READ)?;
        Ok(json!({ "on": on, "property": prop::AUTOMATION.hex() }))
    }) {
        Ok(v) => deliver(out, &v),
        Err(e) => e,
    }
}
