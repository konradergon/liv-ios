//! Content — the editor's service. One entity's content read as spans,
//! written back whole, guarded by a fingerprint of what the writer last
//! saw. A save is to a value, never a moment: if the stored content moved
//! since the base was read, the save refuses and the shell shows both.
//!
//! Also home to the one value parser (moved from the CLI so every shell
//! parses "friday 10:00" the same way) and the birth of a note.

use lotus_core::{
    props, Author, Cell, Command, DateTime, Entity, Id, PersistError, RichText, Session, Span,
    Store, Value,
};

use crate::{property_id, run, Constraint, Op, Query};

/// FNV-1a, the same hash the proposal fingerprint uses — deterministic
/// across processes, cheap, and honest about what it is: an identity
/// check, not cryptography.
pub fn fnv(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// The identity of a stored content value: FNV-1a over its serde bytes.
/// Zero when no content cell exists — zero is never a real fingerprint,
/// exactly as zero is never a real id.
pub fn content_fingerprint(value: Option<&Value>) -> u64 {
    match value {
        None => 0,
        Some(value) => fnv(&serde_json::to_vec(value).unwrap_or_default()),
    }
}

/// An entity's content as spans. Legacy plain-text content reads as one
/// Text span; the fingerprint still covers the stored value, so a save
/// over legacy content replaces it honestly.
pub fn content_spans(entity: &Entity) -> Vec<Span> {
    match entity.get(props::CONTENT) {
        Some(Value::RichText(rich)) => rich.spans.clone(),
        Some(Value::Text(text)) => vec![Span::Text(text.clone())],
        _ => Vec::new(),
    }
}

#[derive(Debug)]
pub enum ContentError {
    /// The stored content moved since the base fingerprint was read.
    /// Re-read, then save — there is no force flag.
    Stale,
    /// No such entity, or a span references an entity that does not exist.
    Invalid,
    Persist(PersistError),
}

/// Replace the entity's whole content in one transaction — the editor's
/// save. Empty spans remove content. Returns the fresh fingerprint.
/// Unchanged spans commit nothing: a gesture translates into commands,
/// or into nothing.
pub fn set_content(
    session: &mut Session,
    id: Id,
    spans: Vec<Span>,
    base: u64,
) -> Result<u64, ContentError> {
    let store = session.store();
    let id = store.resolve(id);
    let Some(entity) = store.get(id) else {
        return Err(ContentError::Invalid);
    };
    let current = entity.get(props::CONTENT);
    let new = (!spans.is_empty()).then_some(Value::RichText(RichText { spans }));
    // The no-op wins before the guard: writing what is already there is
    // never stale, whatever base the writer believed — its intent is the
    // log's state already.
    if current == new.as_ref() {
        return Ok(content_fingerprint(current));
    }
    if content_fingerprint(current) != base {
        return Err(ContentError::Stale);
    }
    // A reference to nothing is not content.
    if let Some(Value::RichText(rich)) = &new {
        for span in &rich.spans {
            if let Span::Ref(target) = span {
                if store.get(*target).is_none() {
                    return Err(ContentError::Invalid);
                }
            }
        }
    }

    let mut commands: Vec<Command> = entity
        .all(props::CONTENT)
        .cloned()
        .map(|old| Command::RemoveCell {
            entity: id,
            cell: Cell { property: props::CONTENT, value: old },
        })
        .collect();
    let fresh = content_fingerprint(new.as_ref());
    if let Some(value) = new {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: props::CONTENT, value },
        });
    }
    session
        .commit(commands, "edit", Author::User)
        .map_err(ContentError::Persist)?;

    // A pending proposal derived from the old words is stale the moment
    // they change: retract it — no refusal recorded — and let the next
    // sweep re-derive from the words that are actually there. Exactly
    // the shapes the clerk emits: a proposer's single AddCell on this
    // entity.
    let stale: Vec<usize> = session
        .store()
        .pending()
        .iter()
        .enumerate()
        .filter(|(_, p)| {
            matches!(&p.author, Author::Proposer(_))
                && matches!(
                    p.commands.as_slice(),
                    [Command::AddCell { entity, .. }] if *entity == id
                )
        })
        .map(|(i, _)| i)
        .collect();
    for index in stale.into_iter().rev() {
        session.retract(index).map_err(ContentError::Persist)?;
    }
    Ok(fresh)
}

/// Birth of a note: Create + type + created, one transaction. The caller
/// drops straight into renaming — the entity is born nameless, like a
/// scrap, but typed, so expectations apply from the first moment.
pub fn create_note(session: &mut Session, created: DateTime) -> Result<Id, PersistError> {
    let note_type = find_type(session.store(), "note");
    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    if let Some(t) = note_type {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: props::TYPE, value: Value::Reference(t) },
        });
    }
    commands.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::CREATED, value: Value::DateTime(created) },
    });
    session.commit(commands, "new note", Author::User)?;
    Ok(id)
}

/// Birth of a workspace: Create + type + name + created (+ parent and
/// a trailing order among its new siblings), one transaction. Working:
/// navigation chrome, not a thought.
pub fn create_workspace(
    session: &mut Session,
    name: &str,
    parent: Option<Id>,
    created: DateTime,
) -> Result<Id, PersistError> {
    let store = session.store();
    let workspace_type = find_type(store, "workspace");
    let parent_prop = property_id(store, "parent");
    let order_prop = property_id(store, "order");

    // Land after the last sibling: max order among same-parent
    // workspaces, plus ten.
    let next_order = order_prop
        .map(|order| {
            store
                .entities()
                .filter(|e| !e.trashed)
                .filter(|e| match (parent, parent_prop) {
                    (Some(p), Some(pp)) => e.has(pp, &Value::Reference(p)),
                    (None, Some(pp)) => e.get(pp).is_none(),
                    _ => true,
                })
                .filter_map(|e| match e.get(order) {
                    Some(Value::Number(n)) => Some(*n),
                    _ => None,
                })
                .fold(0.0_f64, f64::max)
                + 10.0
        })
        .unwrap_or(10.0);

    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    let mut add = |property: Id, value: Value| {
        commands.push(Command::AddCell { entity: id, cell: Cell { property, value } });
    };
    add(props::NAME, Value::text(name));
    add(props::WORKING, Value::Bool(true));
    add(props::CREATED, Value::DateTime(created));
    if let Some(t) = workspace_type {
        add(props::TYPE, Value::Reference(t));
    }
    if let (Some(p), Some(pp)) = (parent, parent_prop) {
        add(pp, Value::Reference(p));
    }
    if let Some(op) = order_prop {
        add(op, Value::Number(next_order));
    }
    session.commit(commands, "new workspace", Author::User)?;
    Ok(id)
}

/// Trash an entity and every descendant reachable through `parent`
/// references — one gesture, one transaction, one undo step. Liv's
/// delete-workspace warns "N child workspaces will also be deleted";
/// here it is a trash, so even that is reversible.
pub fn trash_tree(session: &mut Session, root: Id) -> Result<usize, ContentError> {
    let store = session.store();
    let root = store.resolve(root);
    if store.get(root).is_none() {
        return Err(ContentError::Invalid);
    }
    let Some(parent_prop) = property_id(store, "parent") else {
        return Err(ContentError::Invalid);
    };
    // Walk the tree breadth-first; cycles cannot recur into the list
    // because each entity enters at most once.
    let mut doomed = vec![root];
    let mut i = 0;
    while i < doomed.len() {
        let node = doomed[i];
        for entity in store.entities() {
            if !entity.trashed
                && entity.has(parent_prop, &Value::Reference(node))
                && !doomed.contains(&entity.id)
            {
                doomed.push(entity.id);
            }
        }
        i += 1;
    }
    let commands: Vec<Command> = doomed.iter().map(|id| Command::Trash { entity: *id }).collect();
    let count = commands.len();
    session
        .commit(commands, "trash workspace tree", Author::User)
        .map_err(ContentError::Persist)?;
    Ok(count)
}

/// Remove every cell of one property — the inverse of set_property's
/// replace, for "make top-level" and its kin. A property the entity
/// does not carry is a no-op, not an error.
pub fn unset_property(session: &mut Session, id: Id, prop_name: &str) -> Result<(), String> {
    let store = session.store();
    let id = store.resolve(id);
    let entity = store.get(id).ok_or(format!("no entity #{id}"))?;
    let property =
        property_id(store, prop_name).ok_or(format!("no property named {prop_name}"))?;
    let commands: Vec<Command> = entity
        .all(property)
        .cloned()
        .map(|old| Command::RemoveCell {
            entity: id,
            cell: Cell { property, value: old },
        })
        .collect();
    if commands.is_empty() {
        return Ok(());
    }
    session
        .commit(commands, format!("unset {prop_name}"), Author::User)
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// A type is front-of-house and carries expectations; that pair is what
/// distinguishes "note" the type from anything else that borrows the word.
pub fn find_type(store: &Store, name: &str) -> Option<Id> {
    let query = Query {
        constraints: vec![
            Constraint { property: props::NAME, op: Op::Equals(Value::text(name)) },
            Constraint { property: props::EXPECTED, op: Op::Exists },
        ],
        include_working: true,
        ..Query::default()
    };
    run(store, &query).first().copied()
}

/// Set one property to one value: replace-the-cell semantics, one
/// transaction, one undo step. The value is parsed by the property's own
/// declared kind — the definition entity says what its cells hold.
/// One parser, three shells: the CLI, the window, the inspector to come.
pub fn set_property(
    session: &mut Session,
    id: Id,
    prop_name: &str,
    raw: &str,
) -> Result<(), String> {
    let store = session.store();
    let id = store.resolve(id);
    let entity = store.get(id).ok_or(format!("no entity #{id}"))?;
    let property =
        property_id(store, prop_name).ok_or(format!("no property named {prop_name}"))?;
    let kind = match store.get(property).and_then(|p| p.get(props::VALUE_KIND)) {
        Some(Value::Text(kind)) => kind.clone(),
        _ => return Err(format!("{prop_name} declares no value kind")),
    };
    let value = parse_value(store, property, &kind, raw)?;

    let commands: Vec<Command> = entity
        .all(property)
        .cloned()
        .map(|old| Command::RemoveCell {
            entity: id,
            cell: Cell { property, value: old },
        })
        .chain(std::iter::once(Command::AddCell {
            entity: id,
            cell: Cell { property, value },
        }))
        .collect();
    session
        .commit(commands, format!("set {prop_name}"), Author::User)
        .map_err(|e| e.to_string())?;
    Ok(())
}

fn parse_value(store: &Store, property: Id, kind: &str, raw: &str) -> Result<Value, String> {
    match kind {
        "text" => Ok(Value::text(raw)),
        "richtext" => Ok(Value::RichText(RichText {
            spans: vec![Span::Text(raw.to_string())],
        })),
        "number" => raw
            .parse()
            .map(Value::Number)
            .map_err(|_| format!("not a number: {raw}")),
        "bool" => match raw {
            "true" | "yes" => Ok(Value::Bool(true)),
            "false" | "no" => Ok(Value::Bool(false)),
            _ => Err(format!("not a bool: {raw}")),
        },
        "datetime" => parse_civil(raw).ok_or(format!("not a date: {raw} (yyyy-mm-dd [hh:mm])")),
        "reference" => {
            let id: Id = raw
                .trim_start_matches('#')
                .parse()
                .map_err(|_| format!("not an entity id: {raw}"))?;
            store
                .get(id)
                .map(|_| Value::Reference(id))
                .ok_or(format!("no entity #{id}"))
        }
        "select" => {
            let wanted = raw.to_lowercase();
            store
                .get(property)
                .into_iter()
                .flat_map(|def| def.all(props::OPTIONS))
                .find_map(|option| match option {
                    Value::Reference(target) => match store.get(*target)?.get(props::NAME) {
                        Some(Value::Text(name)) if name.to_lowercase() == wanted => {
                            Some(Value::Select(*target))
                        }
                        _ => None,
                    },
                    _ => None,
                })
                .ok_or(format!("no option named {raw}"))
        }
        other => Err(format!("cannot parse a {other} value yet")),
    }
}

fn parse_civil(raw: &str) -> Option<Value> {
    let (date, time) = match raw.split_once(' ') {
        Some((d, t)) => (d, Some(t)),
        None => (raw, None),
    };
    let mut ymd = date.split('-');
    let year: i32 = ymd.next()?.parse().ok()?;
    let month: u32 = ymd.next()?.parse().ok()?;
    let day: u32 = ymd.next()?.parse().ok()?;
    if ymd.next().is_some() || !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    match time {
        None => Some(Value::DateTime(DateTime::date(year, month, day))),
        Some(t) => {
            let (h, m) = t.split_once(':')?;
            let hour: u32 = h.parse().ok()?;
            let minute: u32 = m.parse().ok()?;
            if hour > 23 || minute > 59 {
                return None;
            }
            Some(Value::DateTime(DateTime::at(year, month, day, hour, minute)))
        }
    }
}
