//! Content — the editor's service. One entity's content read as spans,
//! written back whole, guarded by a fingerprint of what the writer last
//! saw. A save is to a value, never a moment: if the stored content moved
//! since the base was read, the save refuses and the shell shows both.
//!
//! Also home to the one value parser (moved from the CLI so every shell
//! parses "friday 10:00" the same way) and the birth of a note.

use lotus_core::{
    props, Author, Block, Cell, Command, DateTime, Entity, Id, PersistError, RichText, Session,
    Span, Store, Value,
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
        Some(Value::Text(text)) => vec![Span::text(text.clone())],
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

/// One past version of an entity's content — the value carried by a
/// content-setting transaction, verbatim. No replay: whole-value replace
/// means every AddCell of CONTENT already holds the full content of that
/// moment, so history is a walk of the log, not a reconstruction.
pub struct ContentVersion {
    pub seq: u64,
    pub time: i64,
    pub author: Author,
    pub label: String,
    pub spans: Vec<Span>,
}

/// Every version of an entity's content, oldest first — the log IS the
/// history (feature-map T1 #10). Each entry is a whole content value;
/// restoring one is an ordinary set_content of its spans.
pub fn content_history(store: &Store, id: Id) -> Vec<ContentVersion> {
    let id = store.resolve(id);
    let mut out = Vec::new();
    for tx in store.history() {
        // An undo/redo appends the inverse of a transaction, which for a
        // content edit is a fresh AddCell of the OLD value — a phantom
        // "version" identical to one already listed. Skip reversal
        // transactions; the forward edits are the honest history, and
        // the current-content marker (client-side) reflects where undo
        // left the value.
        if tx.reverses.is_some() {
            continue;
        }
        for command in &tx.commands {
            let Command::AddCell { entity, cell } = command else {
                continue;
            };
            if store.resolve(*entity) != id || cell.property != props::CONTENT {
                continue;
            }
            let spans = match &cell.value {
                Value::RichText(rich) => rich.spans.clone(),
                Value::Text(text) => vec![Span::text(text.clone())],
                _ => continue,
            };
            out.push(ContentVersion {
                seq: tx.seq,
                time: tx.time,
                author: tx.author.clone(),
                label: tx.label.clone(),
                spans,
            });
        }
    }
    out
}

/// Birth of a note: Create + type + created, one transaction. The caller
/// drops straight into renaming — the entity is born nameless, like a
/// scrap, but typed, so expectations apply from the first moment.
/// The default daily-note body (D4 — a fixed "template note", NOT a template
/// engine): a date H1, then the Agenda / Notes / Log sections. The Agenda
/// heading reserves the slot for P16's live-agenda projection (bp9 OQ-C);
/// everything is ordinary markdown the user edits like any note. The only
/// substitution is the ISO date into the H1 — no `{{variable}}` machinery.
fn daily_template(iso_date: &str) -> RichText {
    RichText {
        spans: vec![
            Span::Break(Block::Heading(1)),
            Span::text(iso_date),
            Span::Break(Block::Heading(2)),
            Span::text("Agenda"),
            Span::Break(Block::Heading(2)),
            Span::text("Notes"),
            Span::Break(Block::Body),
            Span::Break(Block::Heading(2)),
            Span::text("Log"),
            Span::Break(Block::Body),
        ],
    }
}

/// Get-or-create today's (or any day's) daily note — the ONE new P12 seam
/// (12a). Idempotent per (date, workspace): the find-query and the
/// conditional create run in ONE session so two entry points firing close
/// together can never double-create (the daily-notes reader's race). Returns
/// (id, created) — `created=false` on the found path so the FFI can leave the
/// store's cache valid. `date` is normalized to date-only by the caller; a
/// `workspace` of `None` keys globally (an older box with no active workspace).
pub fn get_or_create_daily_note(
    session: &mut Session,
    date: DateTime,
    workspace: Option<Id>,
    created: DateTime,
) -> Result<(Id, bool), PersistError> {
    let store = session.store();
    let daily_type = find_type(store, "daily-note");
    let date_prop = property_id(store, "date");
    let workspace_prop = property_id(store, "workspace");

    // The find: a daily note on this day (in this workspace, if one is given).
    let mut constraints = Vec::new();
    if let Some(t) = daily_type {
        constraints.push(Constraint { property: props::TYPE, op: Op::Equals(Value::Reference(t)) });
    }
    if let Some(dp) = date_prop {
        constraints.push(Constraint { property: dp, op: Op::Equals(Value::DateTime(date)) });
    }
    if let (Some(wp), Some(ws)) = (workspace_prop, workspace) {
        constraints.push(Constraint { property: wp, op: Op::Equals(Value::Reference(ws)) });
    }
    let query = Query { constraints, ..Query::default() };
    if let Some(found) = run(store, &query).first().copied() {
        return Ok((found, false));
    }

    // The birth: a normal note carrying the two identifying cells + workspace
    // + name (the ISO date) + created + the template body.
    let ymd = date.civil / 10_000;
    let iso = format!("{:04}-{:02}-{:02}", ymd / 10_000, (ymd / 100) % 100, ymd % 100);
    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    if let Some(t) = daily_type {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: props::TYPE, value: Value::Reference(t) },
        });
    }
    if let Some(dp) = date_prop {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: dp, value: Value::DateTime(date) },
        });
    }
    if let (Some(wp), Some(ws)) = (workspace_prop, workspace) {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: wp, value: Value::Reference(ws) },
        });
    }
    commands.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::NAME, value: Value::text(&iso) },
    });
    commands.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::CREATED, value: Value::DateTime(created) },
    });
    commands.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::CONTENT, value: Value::RichText(daily_template(&iso)) },
    });
    session.commit(commands, "open daily note", Author::User)?;
    Ok((id, true))
}

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

/// The id of a select property's option entity by name (case-insensitive) —
/// the same OPTIONS walk `parse_value`'s select branch does, factored so
/// birth (`create_task`) resolves an option identically to a `set`.
pub fn find_option(store: &Store, property: Id, name: &str) -> Option<Id> {
    let wanted = name.to_lowercase();
    store
        .get(property)?
        .all(props::OPTIONS)
        .find_map(|value| match value {
            Value::Reference(target) => match store.get(*target)?.get(props::NAME) {
                Some(Value::Text(option)) if option.to_lowercase() == wanted => Some(*target),
                _ => None,
            },
            _ => None,
        })
}

/// Birth of a task: Create + type=task + status=todo + created, one
/// transaction. Born nameless (like `create_note`) so the caller drops into
/// renaming, but typed and already `todo`, so the list's checkbox has a
/// concrete state from the first frame. Priority and due are set later,
/// never at birth. Distinct from capture, which makes an untyped scrap the
/// clerk quarantines.
pub fn create_task(session: &mut Session, created: DateTime) -> Result<Id, PersistError> {
    let store = session.store();
    let task_type = find_type(store, "task");
    let status_prop = property_id(store, "status");
    // The entry column is a cell on the TYPE (`default-status`, P11/11d) —
    // user-editable per kind; the todo fallback keeps births byte-identical
    // on every box that predates the scoping seed.
    let todo = task_type
        .and_then(|t| store.get(t))
        .zip(property_id(store, "default-status"))
        .and_then(|(t, p)| match t.get(p) {
            Some(Value::Reference(option)) => Some(*option),
            _ => None,
        })
        .or_else(|| status_prop.and_then(|status| find_option(store, status, "todo")));

    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    if let Some(task_type) = task_type {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: props::TYPE, value: Value::Reference(task_type) },
        });
    }
    // A select cell holds a Select value (not Reference) so `status:todo`
    // search and the inspector's select control agree with a hand-set status.
    if let (Some(status), Some(todo)) = (status_prop, todo) {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: status, value: Value::Select(todo) },
        });
    }
    commands.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::CREATED, value: Value::DateTime(created) },
    });
    session.commit(commands, "new task", Author::User)?;
    Ok(id)
}

/// Birth of an event: Create + type=event + a `due` cell + created, one
/// transaction. Born with the clicked day/time as its `due` (all-day when
/// `due.date_only`), typed `event` so it lands on the calendar by property-based
/// positioning — it appears because it has a `due`, not because of its type.
/// Born nameless like `create_task`, so the caller drops into renaming.
/// Location, attendees, and notes are set after birth through the inspector,
/// never at birth. Distinct from capture, which makes an untyped scrap the
/// clerk quarantines.
pub fn create_event(
    session: &mut Session,
    due: DateTime,
    created: DateTime,
) -> Result<Id, PersistError> {
    let store = session.store();
    let event_type = find_type(store, "event");
    let due_prop = property_id(store, "due");

    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    if let Some(event_type) = event_type {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: props::TYPE, value: Value::Reference(event_type) },
        });
    }
    if let Some(due_prop) = due_prop {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: due_prop, value: Value::DateTime(due) },
        });
    }
    commands.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::CREATED, value: Value::DateTime(created) },
    });
    session.commit(commands, "new event", Author::User)?;
    Ok(id)
}

/// A new status option for a kind (bp6 #8 column-add, bp1 e17 "Edit
/// vocabulary…"): ONE commit — Create + NAME + WORKING + for-type→kind +
/// board order (max existing order for the kind + 1) + optional hue — plus
/// the OPTIONS cell on the one `status` definition that makes it real.
/// Rename / re-hue / re-order afterwards are ordinary `set`s on the option
/// entity: the option IS the column. Returns the option id.
pub fn add_status_option(
    session: &mut Session,
    kind: Id,
    name: &str,
    hue: Option<f64>,
) -> Result<Id, WriteError> {
    let store = session.store();
    let status = property_id(store, "status")
        .ok_or(WriteError::Refused("no status property".into()))?;
    let for_type = property_id(store, "for-type")
        .ok_or(WriteError::Refused("no for-type property — the scoping seed first".into()))?;
    let order_prop = property_id(store, "order");
    let hue_prop = property_id(store, "hue");
    store.get(kind).ok_or(WriteError::Refused(format!("no kind #{kind}")))?;
    let name = name.trim();
    if name.is_empty() {
        return Err(WriteError::Refused("an option needs a name".into()));
    }
    let next_order = crate::status_options_for(store, kind)
        .iter()
        .map(|o| o.order)
        .fold(0.0_f64, f64::max)
        + 1.0;
    // The number seam's law holds here too: a hue is finite or absent.
    let hue = hue.filter(|h| h.is_finite());

    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    for cell in [
        Cell { property: props::NAME, value: Value::text(name) },
        Cell { property: props::WORKING, value: Value::Bool(true) },
        Cell { property: for_type, value: Value::Reference(kind) },
    ] {
        commands.push(Command::AddCell { entity: id, cell });
    }
    if let Some(order) = order_prop {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: order, value: Value::Number(next_order) },
        });
    }
    if let (Some(hue_prop), Some(hue)) = (hue_prop, hue) {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: hue_prop, value: Value::Number(hue) },
        });
    }
    commands.push(Command::AddCell {
        entity: status,
        cell: Cell { property: props::OPTIONS, value: Value::Reference(id) },
    });
    session
        .commit(commands, "new status option", Author::User)
        .map_err(|e| WriteError::Persist(e.to_string()))?;
    Ok(id)
}

/// Why a write did not happen. The split matters at the FFI cache: a
/// refusal never touched the store (the cached snapshot stays valid,
/// `Committed::Read`), while a persist failure may have poisoned the
/// session (the entry must be evicted, `Committed::Failed`). Every seam
/// whose refusals are cheap pre-checks returns this, so the cache is never
/// evicted for a mere "no" (the review's over-eviction finding).
#[derive(Debug)]
pub enum WriteError {
    /// Refused before touching the store — the box is unchanged.
    Refused(String),
    /// The commit itself failed; the session may be poisoned.
    Persist(String),
}

/// Birth one property definition — the add-property popover's create leg
/// (P11.5g). The design ASSUMED set-on-unknown-name births a definition;
/// the failing test showed the core refuses instead, so this is the one
/// sanctioned exception: a definition entity (name + value-kind +
/// working), exactly the seeds' shape. One name, one definition — a
/// duplicate refuses; the kind must be one parse_value can read back
/// (file stays out: those are born through files::add_file).
pub fn birth_property(session: &mut Session, name: &str, kind: &str) -> Result<Id, WriteError> {
    const KINDS: [&str; 7] = [
        "text", "richtext", "number", "bool", "datetime", "reference", "select",
    ];
    let name = name.trim();
    if name.is_empty() {
        return Err(WriteError::Refused("a property needs a name".into()));
    }
    if !KINDS.contains(&kind) {
        return Err(WriteError::Refused(format!("unknown value kind {kind}")));
    }
    if property_id(session.store(), name).is_some() {
        return Err(WriteError::Refused(format!("a property named {name} already exists")));
    }
    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    for cell in [
        Cell { property: props::NAME, value: Value::text(name) },
        Cell { property: props::VALUE_KIND, value: Value::text(kind) },
        Cell { property: props::WORKING, value: Value::Bool(true) },
    ] {
        commands.push(Command::AddCell { entity: id, cell });
    }
    session
        .commit(commands, format!("add property {name}"), Author::User)
        .map_err(|e| WriteError::Persist(e.to_string()))?;
    Ok(id)
}

/// Space-cycles a date row's role (bp1 e10, bp6 #25, bp9 #17): ONE
/// transaction moving the value — civil and the date_only bit intact — from
/// `from` to the next role in the closed ring
/// due → date → valid-until → occurred → purchased-on → due.
/// RemoveCell + AddCell, one commit, one undo. Switching a calendar-role
/// date to a lookup role "pulls it off the calendar without losing the
/// dates" purely because the lens reads `calendar_set`. Returns the new
/// property. Refused — without touching the store — when the entity has no
/// datetime on `from`, when `from` is not a date role, or when the target
/// role already carries a value here (one entity's several date rows are
/// independent; cycling never merges or clobbers a sibling, bp9 #28).
pub fn cycle_date_role(session: &mut Session, entity: Id, from: Id) -> Result<Id, WriteError> {
    const RING: [&str; 5] = ["due", "date", "valid-until", "occurred", "purchased-on"];
    let store = session.store();
    let entity = store.resolve(entity);
    let e = store
        .get(entity)
        .ok_or(WriteError::Refused(format!("no entity #{entity}")))?;
    let from_name = match store.get(from).and_then(|p| p.get(props::NAME)) {
        Some(Value::Text(n)) => n.clone(),
        _ => return Err(WriteError::Refused(format!("no property #{from}"))),
    };
    let position = RING
        .iter()
        .position(|n| *n == from_name)
        .ok_or(WriteError::Refused(format!("{from_name} is not a date role")))?;
    // A merge can leave several cells on one date property; the seam
    // addresses a cycle by (entity, property) only, so "which one moves"
    // would be a guess — refuse, never guess (the review's finding).
    if e.all(from).count() > 1 {
        return Err(WriteError::Refused(format!(
            "#{entity} carries several {from_name} dates — the cycle is ambiguous"
        )));
    }
    let value = match e.get(from) {
        Some(Value::DateTime(d)) => Value::DateTime(*d),
        _ => return Err(WriteError::Refused(format!("#{entity} has no {from_name} date"))),
    };
    let next_name = RING[(position + 1) % RING.len()];
    let next = property_id(store, next_name)
        .ok_or(WriteError::Refused(format!("no property named {next_name}")))?;
    if e.get(next).is_some() {
        return Err(WriteError::Refused(format!("#{entity} already carries {next_name}")));
    }
    session
        .commit(
            vec![
                Command::RemoveCell { entity, cell: Cell { property: from, value: value.clone() } },
                Command::AddCell { entity, cell: Cell { property: next, value } },
            ],
            "cycle date role",
            Author::User,
        )
        .map_err(|e| WriteError::Persist(e.to_string()))?;
    Ok(next)
}

/// Birth of a list: Create + type=list + name + created, one transaction.
/// Named at birth (a list is named before you add to it, unlike a note).
/// Members are added later, one AddCell(related, Reference) each.
pub fn create_list(
    session: &mut Session,
    name: &str,
    created: DateTime,
) -> Result<Id, PersistError> {
    let list_type = find_type(session.store(), "list");
    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    if let Some(list_type) = list_type {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: props::TYPE, value: Value::Reference(list_type) },
        });
    }
    commands.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::NAME, value: Value::text(name) },
    });
    commands.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::CREATED, value: Value::DateTime(created) },
    });
    session.commit(commands, "new list", Author::User)?;
    Ok(id)
}

/// Add ONE cell to a (possibly multi-valued) property — list membership's
/// add-one primitive (property "related", value "#<id>"). Unlike
/// `set_property` (replace-all) and `unset_property` (remove-all), this
/// touches exactly one cell; adding a value already present is a silent
/// no-op (the log stays a set). The value is parsed by the property's
/// declared kind, exactly as `set`.
pub fn add_cell(session: &mut Session, id: Id, prop_name: &str, raw: &str) -> Result<(), String> {
    let (id, property, value) = resolve_cell(session.store(), id, prop_name, raw)?;
    // An entity may not reference ITSELF — a list can't be its own member (the
    // same guard the clerk's `related` proposer applies). Only add is guarded;
    // remove stays open so any pre-existing self-reference can still be cleared.
    if value == Value::Reference(id) {
        return Err(format!("#{id} cannot reference itself"));
    }
    if session.store().get(id).is_some_and(|e| e.has(property, &value)) {
        return Ok(());
    }
    session
        .commit(
            vec![Command::AddCell { entity: id, cell: Cell { property, value } }],
            format!("add {prop_name}"),
            Author::User,
        )
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Remove ONE cell of a property — un-tag a list member (property "related",
/// value "#<id>"). NEVER deletes the referenced entity (deletion never
/// cascades); removing a value that isn't present is a no-op, not an error.
pub fn remove_cell(
    session: &mut Session,
    id: Id,
    prop_name: &str,
    raw: &str,
) -> Result<(), String> {
    let (id, property, value) = resolve_cell(session.store(), id, prop_name, raw)?;
    if !session.store().get(id).is_some_and(|e| e.has(property, &value)) {
        return Ok(());
    }
    session
        .commit(
            vec![Command::RemoveCell { entity: id, cell: Cell { property, value } }],
            format!("remove {prop_name}"),
            Author::User,
        )
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// The (canonical id, property, parsed value) for an add/remove-cell — the
/// same resolution `set_property` does, factored out.
fn resolve_cell(
    store: &Store,
    id: Id,
    prop_name: &str,
    raw: &str,
) -> Result<(Id, Id, Value), String> {
    let id = store.resolve(id);
    store.get(id).ok_or(format!("no entity #{id}"))?;
    let property = property_id(store, prop_name).ok_or(format!("no property named {prop_name}"))?;
    let kind = match store.get(property).and_then(|p| p.get(props::VALUE_KIND)) {
        Some(Value::Text(kind)) => kind.clone(),
        _ => return Err(format!("{prop_name} declares no value kind")),
    };
    let value = parse_value(store, property, &kind, raw)?;
    Ok((id, property, value))
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

/// Trash one workspace — and only that one. Deletion never cascades
/// (the core law: productivity_app.md, "Deletion never cascades");
/// a workspace's children keep their now-dangling `parent` reference
/// and the tree builder re-roots them to the top level. Liv's
/// cascade-delete becomes a single reversible trash whose orphans
/// survive, promoted, rather than a subtree wipe.
pub fn trash_workspace(session: &mut Session, id: Id) -> Result<(), ContentError> {
    let store = session.store();
    let id = store.resolve(id);
    if store.get(id).is_none() {
        return Err(ContentError::Invalid);
    }
    session
        .commit(vec![Command::Trash { entity: id }], "trash workspace", Author::User)
        .map_err(ContentError::Persist)?;
    Ok(())
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

/// Parse a raw string into a typed Value by a property's declared kind —
/// the one kind-aware parser the inspector's `set` and the search DSL's
/// qualifiers both go through, so `status:done` and a hand-set status
/// resolve the same option identically.
pub fn parse_value(store: &Store, property: Id, kind: &str, raw: &str) -> Result<Value, String> {
    match kind {
        "text" => Ok(Value::text(raw)),
        "richtext" => Ok(Value::RichText(RichText {
            spans: vec![Span::text(raw)],
        })),
        // Finite only: Rust's f64 parser accepts "NaN"/"inf", but a knowledge
        // log has no use for either — and NaN's non-reflexive equality once
        // made such a cell unremovable (the poison-pill repro).
        "number" => raw
            .parse::<f64>()
            .ok()
            .filter(|n| n.is_finite())
            .map(Value::Number)
            .ok_or(format!("not a number: {raw}")),
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
        // A file carries a bytes-derived hash a raw string can't express, so
        // a hand-typed `set` is refused: file entities are born through
        // files::add_file (which hashes), and the cell stays read-only.
        "file" => Err("a file is added by reference, not typed".into()),
        other => Err(format!("cannot parse a {other} value yet")),
    }
}

fn parse_civil(raw: &str) -> Option<Value> {
    // "<start> -> <end>" is a SPAN (P11/11b): each side the base grammar
    // below, the same date_only reading on both (mixed sides refused), and
    // the end strictly after the start — one cell, one fact.
    if let Some((s, e)) = raw.split_once("->") {
        let start = parse_civil_single(s.trim())?;
        let end = parse_civil_single(e.trim())?;
        if start.date_only != end.date_only || end.civil <= start.civil {
            return None;
        }
        return Some(Value::DateTime(DateTime::span(start, end.civil)));
    }
    parse_civil_single(raw).map(Value::DateTime)
}

fn parse_civil_single(raw: &str) -> Option<DateTime> {
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
        None => Some(DateTime::date(year, month, day)),
        Some(t) => {
            let (h, m) = t.split_once(':')?;
            let hour: u32 = h.parse().ok()?;
            let minute: u32 = m.parse().ok()?;
            if hour > 23 || minute > 59 {
                return None;
            }
            Some(DateTime::at(year, month, day, hour, minute))
        }
    }
}
