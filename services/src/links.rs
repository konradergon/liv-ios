//! Links, both directions — ONE mechanism (feature-map §6).
//!
//! Two doors write the same edge:
//!   * a `[[ ]]` typed in a body → a `Span::Ref` inside the content cell;
//!   * a link picked in properties → a `related` cell.
//! Both are `Value::…targets()`, so both land in the core's backlink index
//! the moment they are committed. This module is the READER both ends of
//! every shell share: outgoing rows for the thing you are looking at, and
//! the rows pointing back at it.
//!
//! What is deliberately NOT a link: filing. `area`, `project`, `people`
//! and `type` are references too, and a project's members are what a
//! filter is for — a "linked from" list that swallowed every filed note
//! would say nothing.
//!
//! Backstage furniture (layers, pins, workspaces — anything `working`) is
//! not a link either. A saved layout holds its tabs as `related` cells;
//! it must never read as "linked from".

use crate::content::display_name;
use crate::property_id;
use liv_core::{props, Entity, Id, Span, Store, Value};

/// One end of an edge, rendered.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Link {
    /// The OTHER end — never the entity you asked about.
    pub id: Id,
    pub name: String,
    /// Type names, for the row's glyph.
    pub kinds: Vec<String>,
    /// The property the edge rides on: "related" for a picked link,
    /// "content" for one typed in a body.
    pub property: String,
    /// Typed in a body — the shell must send you to the words to remove
    /// it, because the brackets ARE the link.
    pub from_body: bool,
}

/// What this entity points at, and what points at it.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct Links {
    pub out: Vec<Link>,
    /// The wire calls it `in` — `inbound` here only because `in` is a
    /// Rust keyword.
    #[serde(rename = "in")]
    pub inbound: Vec<Link>,
}

/// Both directions for one entity. Cheap: outgoing is this entity's own
/// cells, incoming is one index lookup — never a scan of every body.
pub fn links(store: &Store, id: Id) -> Links {
    let id = store.resolve(id);
    let Some(entity) = store.get(id) else {
        return Links::default();
    };
    let related = property_id(store, "related");

    // ---- outgoing: picked links first, then the body's, in reading order.
    let mut out: Vec<Link> = Vec::new();
    let mut seen: Vec<Id> = Vec::new();
    let push = |out: &mut Vec<Link>, seen: &mut Vec<Id>, target: Id, from_body: bool| {
        let target = store.resolve(target);
        if target == id || seen.contains(&target) {
            return;
        }
        let Some(other) = store.get(target) else { return };
        if other.trashed {
            return;
        }
        seen.push(target);
        out.push(row(store, other, from_body));
    };
    if let Some(related) = related {
        for value in entity.all(related) {
            if let Value::Reference(target) = value {
                push(&mut out, &mut seen, *target, false);
            }
        }
    }
    if let Some(Value::RichText(rich)) = entity.get(props::CONTENT) {
        for span in &rich.spans {
            if let Span::Ref(target) = span {
                push(&mut out, &mut seen, *target, true);
            }
        }
    }

    // ---- incoming: one index lookup, filtered to links (not filing, not
    // furniture), and never a row that is already an outgoing one.
    let mut inbound: Vec<Link> = Vec::new();
    let mut seen_in: Vec<Id> = Vec::new();
    for back in store.backlinks(id) {
        let from_body = back.property == props::CONTENT;
        if !from_body && Some(back.property) != related {
            continue; // filing, typing, plumbing's own pointers
        }
        let source = store.resolve(back.source);
        if source == id || seen_in.contains(&source) || seen.contains(&source) {
            continue;
        }
        let Some(other) = store.get(source) else { continue };
        if other.trashed || other.has(props::WORKING, &Value::Bool(true)) {
            continue;
        }
        seen_in.push(source);
        inbound.push(row(store, other, from_body));
    }

    Links { out, inbound }
}

fn row(store: &Store, entity: &Entity, from_body: bool) -> Link {
    Link {
        id: entity.id,
        name: display_name(store, entity),
        kinds: entity
            .all(props::TYPE)
            .filter_map(|v| match v {
                Value::Reference(t) => match store.get(store.resolve(*t))?.get(props::NAME) {
                    Some(Value::Text(name)) => Some(name.clone()),
                    _ => None,
                },
                _ => None,
            })
            .collect(),
        property: if from_body { "content".into() } else { "related".into() },
        from_body,
    }
}
