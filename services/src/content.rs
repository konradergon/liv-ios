//! Content — the editor's service. One entity's content read as spans,
//! written back whole, guarded by a fingerprint of what the writer last
//! saw. A save is to a value, never a moment: if the stored content moved
//! since the base was read, the save refuses and the shell shows both.
//!
//! Also home to the one value parser (moved from the CLI so every shell
//! parses "friday 10:00" the same way) and the birth of a note.

use liv_core::{
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
    // sweep re-derive from the words that are actually there. ONLY the
    // sweep's own proposers qualify: their drafts are pure functions of
    // the words. Anything else (a model's suggested title, a draft from
    // another device) cannot be rebuilt — retracting those here meant
    // typing one character silently destroyed them (owner, 2026-08-07).
    let stale: Vec<usize> = session
        .store()
        .pending()
        .iter()
        .enumerate()
        .filter(|(_, p)| {
            crate::clerk::rederivable(&p.author)
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
    } else if let Some(wp) = workspace_prop {
        // None = the global bucket: the note must have NO workspace cell, so
        // a workspace-less find never adopts a workspace-scoped note and the
        // two buckets stay isolated (the review's finding). The shell resolves
        // nil to the Home workspace id, so None is only genuine no-workspace.
        constraints.push(Constraint { property: wp, op: Op::Missing });
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

// ---- the rename engine (P19b): one vault-wide value rename, one txn ----

/// Mint an option entity for a select/status property (the shelves' ghost
/// "+ option", P19): NAME + WORKING + an OPTIONS reference on the property,
/// one commit. Idempotent — an existing option of that name is returned.
/// Returns `(id, created)` — `created` is false on the idempotent hit, so
/// the FFI can tag Read (nothing committed) instead of a phantom Wrote.
pub fn add_option(
    session: &mut Session,
    property: Id,
    name: &str,
) -> Result<(Id, bool), WriteError> {
    let store = session.store();
    let property = store.resolve(property);
    let def = store
        .get(property)
        .ok_or_else(|| WriteError::Refused(format!("no property #{property}")))?;
    // `get` answers for trashed entities too (the standing gotcha) — a
    // retired definition takes no new vocabulary.
    if def.trashed {
        return Err(WriteError::Refused("that property is trashed".into()));
    }
    // Kind discipline: options belong to select/status properties only.
    match def.get(props::VALUE_KIND) {
        Some(Value::Text(kind)) if kind == "select" || kind == "status" => {}
        _ => return Err(WriteError::Refused("only a select property takes options".into())),
    }
    let name = name.trim();
    if name.is_empty() {
        return Err(WriteError::Refused("an option needs a name".into()));
    }
    if let Some(existing) = find_option(store, property, name) {
        return Ok((existing, false));
    }
    let id = session.allocate_id();
    let commands = vec![
        Command::Create { entity: id },
        Command::AddCell {
            entity: id,
            cell: Cell { property: props::NAME, value: Value::text(name) },
        },
        Command::AddCell {
            entity: id,
            cell: Cell { property: props::WORKING, value: Value::Bool(true) },
        },
        Command::AddCell {
            entity: property,
            cell: Cell { property: props::OPTIONS, value: Value::Reference(id) },
        },
    ];
    session
        .commit(commands, "new option", Author::User)
        .map_err(|e| WriteError::Persist(e.to_string()))?;
    Ok((id, true))
}

/// Toggle one KIND reference on a definition's display-attribute property
/// ("hide-on-kind" / "core-on-kind") — additive PER KIND: `set_property`
/// replaces every cell of a property, so hiding on a second kind through it
/// silently un-hid the first (the P19 review). One commit; idempotent
/// no-ops commit nothing. Returns whether anything changed.
pub fn toggle_kind_ref(
    session: &mut Session,
    def: Id,
    prop_name: &str,
    kind: Id,
    on: bool,
) -> Result<bool, WriteError> {
    let store = session.store();
    let def = store.resolve(def);
    let entity = store
        .get(def)
        .filter(|e| !e.trashed)
        .ok_or_else(|| WriteError::Refused(format!("no definition #{def}")))?;
    let property = property_id(store, prop_name)
        .ok_or_else(|| WriteError::Refused(format!("no property named {prop_name}")))?;
    match store.get(property).and_then(|p| p.get(props::VALUE_KIND)) {
        Some(Value::Text(k)) if k == "reference" => {}
        _ => return Err(WriteError::Refused("kind flags live on reference properties".into())),
    }
    let kind = store.resolve(kind);
    if store.get(kind).filter(|e| !e.trashed).is_none() {
        return Err(WriteError::Refused(format!("no kind #{kind}")));
    }
    let present = entity.has(property, &Value::Reference(kind));
    if present == on {
        return Ok(false);
    }
    let cell = Cell { property, value: Value::Reference(kind) };
    let command = if on {
        Command::AddCell { entity: def, cell }
    } else {
        Command::RemoveCell { entity: def, cell }
    };
    session
        .commit(vec![command], format!("{prop_name} flag"), Author::User)
        .map_err(|e| WriteError::Persist(e.to_string()))?;
    Ok(true)
}

/// Rename one VALUE everywhere it is carried — ONE grouped transaction, one
/// undo (the count-confirm seam; never a modal). Kind discipline: text cells
/// rewrite; select/status renames the OPTION entity (carriers re-render for
/// free) or MERGES into an existing option of the new name (carriers
/// repointed, the loser trashed — undo un-merges wholesale). References and
/// dates refuse: a rename is a vocabulary act, not a data edit. Returns the
/// carrier count for the toast.
pub fn rename_value(
    session: &mut Session,
    prop_name: &str,
    old: &str,
    new: &str,
) -> Result<usize, WriteError> {
    let store = session.store();
    let old = old.trim();
    let new = new.trim();
    if new.is_empty() {
        return Err(WriteError::Refused("a value needs a name".into()));
    }
    if old == new {
        return Err(WriteError::Refused("that is already the name".into()));
    }
    let property = property_id(store, prop_name)
        .ok_or_else(|| WriteError::Refused(format!("no property named {prop_name}")))?;
    let kind = match store.get(property).and_then(|p| p.get(props::VALUE_KIND)) {
        Some(Value::Text(kind)) => kind.clone(),
        _ => return Err(WriteError::Refused("the property declares no value kind".into())),
    };

    let commands: Vec<Command>;
    let count: usize;
    match kind.as_str() {
        "text" => {
            let mut rewrites = Vec::new();
            // WORKING entities are name-keyed plumbing (options, types,
            // definitions) — a vocabulary rename rewrites CARRIERS only,
            // or `rename_value("name", …)` corrupts the lookups themselves
            // (the P19 review).
            for entity in store
                .user_entities()
            {
                for cell in entity.cells.iter().filter(|c| c.property == property) {
                    if matches!(&cell.value, Value::Text(t) if t == old) {
                        rewrites.push(entity.id);
                    }
                }
            }
            count = rewrites.len();
            commands = rewrites
                .into_iter()
                .flat_map(|id| {
                    [
                        Command::RemoveCell {
                            entity: id,
                            cell: Cell { property, value: Value::text(old) },
                        },
                        Command::AddCell {
                            entity: id,
                            cell: Cell { property, value: Value::text(new) },
                        },
                    ]
                })
                .collect();
        }
        "select" | "status" => {
            // Same-named options across kinds are the DESIGNED state of
            // `status` (for-type scoping, no cross-kind dedup) — a rename
            // keyed only by name cannot pick one, so it refuses, never
            // guesses (the P19 review).
            let count_named = |name: &str| -> usize {
                let wanted = name.to_lowercase();
                store
                    .get(property)
                    .map(|p| {
                        p.all(props::OPTIONS)
                            .filter(|v| match v {
                                Value::Reference(t) => matches!(
                                    store.get(*t).and_then(|o| o.get(props::NAME)),
                                    Some(Value::Text(n)) if n.to_lowercase() == wanted
                                ),
                                _ => false,
                            })
                            .count()
                    })
                    .unwrap_or(0)
            };
            if count_named(old) > 1 {
                return Err(WriteError::Refused(format!(
                    "two kinds share an option named {old} — this rename is ambiguous"
                )));
            }
            if count_named(new) > 1 {
                return Err(WriteError::Refused(format!(
                    "two kinds share an option named {new} — this merge is ambiguous"
                )));
            }
            let option = find_option(store, property, old).ok_or_else(|| {
                WriteError::Refused(format!("no option named {old}"))
            })?;
            let target = find_option(store, property, new).filter(|t| *t != option);
            let carriers: Vec<Id> = store
                .entities()
                .filter(|e| !e.trashed && e.has(property, &Value::Select(option)))
                .map(|e| e.id)
                .collect();
            count = carriers.len();
            match target {
                None => {
                    // A plain rename: the option's NAME cell moves; every
                    // carrier re-renders for free.
                    let current = match store.get(option).and_then(|o| o.get(props::NAME)) {
                        Some(Value::Text(name)) => name.clone(),
                        _ => old.to_string(),
                    };
                    commands = vec![
                        Command::RemoveCell {
                            entity: option,
                            cell: Cell { property: props::NAME, value: Value::text(current) },
                        },
                        Command::AddCell {
                            entity: option,
                            cell: Cell { property: props::NAME, value: Value::text(new) },
                        },
                    ];
                }
                Some(existing) => {
                    // MERGE: repoint every carrier, detach and trash the
                    // loser — all one commit, un-merged by one undo.
                    let mut merged = Vec::new();
                    for id in &carriers {
                        merged.push(Command::RemoveCell {
                            entity: *id,
                            cell: Cell { property, value: Value::Select(option) },
                        });
                        merged.push(Command::AddCell {
                            entity: *id,
                            cell: Cell { property, value: Value::Select(existing) },
                        });
                    }
                    if store
                        .get(property)
                        .map(|p| p.has(props::OPTIONS, &Value::Reference(option)))
                        == Some(true)
                    {
                        merged.push(Command::RemoveCell {
                            entity: property,
                            cell: Cell {
                                property: props::OPTIONS,
                                value: Value::Reference(option),
                            },
                        });
                    }
                    merged.push(Command::Trash { entity: option });
                    commands = merged;
                }
            }
        }
        other => {
            return Err(WriteError::Refused(format!(
                "{other} values don't rename — vocabulary only (text, select, status)"
            )));
        }
    }
    if commands.is_empty() {
        return Ok(0);
    }
    session
        .commit(commands, "rename value", Author::User)
        .map_err(|e| WriteError::Persist(e.to_string()))?;
    Ok(count)
}

// ---- pins (P17g): the Favourites shelf as small backstage entities ----

/// A target's live pin, if one exists — the idempotence + unpin lookup.
fn live_pin(store: &Store, target: Id) -> Option<Id> {
    let pin_type = find_type(store, "pin")?;
    let target_prop = property_id(store, "target")?;
    store
        .entities()
        .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(pin_type)))
        .find(|e| e.has(target_prop, &Value::Reference(target)))
        .map(|e| e.id)
}

/// Pin an object to the Favourites shelf. The pin is a small BACKSTAGE
/// entity (WORKING — never in Everything, the workspace rule): type=pin,
/// `target` reference, float `order` landing after the last pin. One pin
/// per target — re-pinning returns the existing pin. The type and the
/// `target` property are birthed lazily INSIDE the same transaction as the
/// first pin, so a pin is always one commit, one undo.
pub fn create_pin(
    session: &mut Session,
    target: Id,
    created: DateTime,
) -> Result<Id, PersistError> {
    let store = session.store();
    let target = store.resolve(target);
    if let Some(existing) = live_pin(store, target) {
        return Ok(existing);
    }

    let pin_type = find_type(store, "pin");
    let target_prop = property_id(store, "target");
    let order_prop = property_id(store, "order");

    // Land after the last pin: max order among live pins, plus ten.
    let next_order = match (pin_type, order_prop) {
        (Some(t), Some(order)) => {
            store
                .entities()
                .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(t)))
                .filter_map(|e| match e.get(order) {
                    Some(Value::Number(n)) => Some(*n),
                    _ => None,
                })
                .fold(0.0_f64, f64::max)
                + 10.0
        }
        _ => 10.0,
    };

    let mut commands = Vec::new();
    let type_id = pin_type.unwrap_or_else(|| {
        let t = session.allocate_id();
        commands.push(Command::Create { entity: t });
        for cell in [
            Cell { property: props::NAME, value: Value::text("pin") },
            Cell { property: props::WORKING, value: Value::Bool(true) },
            // EXPECTED makes find_type resolve it (the P9 rule).
            Cell { property: props::EXPECTED, value: Value::Reference(props::NAME) },
        ] {
            commands.push(Command::AddCell { entity: t, cell });
        }
        t
    });
    let target_prop = target_prop.unwrap_or_else(|| {
        let p = session.allocate_id();
        commands.push(Command::Create { entity: p });
        for cell in [
            Cell { property: props::NAME, value: Value::text("target") },
            Cell { property: props::VALUE_KIND, value: Value::text("reference") },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: p, cell });
        }
        p
    });

    let id = session.allocate_id();
    commands.push(Command::Create { entity: id });
    let mut add = |property: Id, value: Value| {
        commands.push(Command::AddCell { entity: id, cell: Cell { property, value } });
    };
    add(props::WORKING, Value::Bool(true));
    add(props::CREATED, Value::DateTime(created));
    add(props::TYPE, Value::Reference(type_id));
    add(target_prop, Value::Reference(target));
    if let Some(op) = order_prop {
        add(op, Value::Number(next_order));
    }
    session.commit(commands, "pin", Author::User)?;
    Ok(id)
}

/// Unpin a target: trash its live pin (soft, reversible). Returns whether
/// a pin was found — a target with no pin is a quiet no-op, not an error.
pub fn remove_pin(session: &mut Session, target: Id) -> Result<bool, PersistError> {
    let store = session.store();
    let target = store.resolve(target);
    let Some(pin) = live_pin(store, target) else {
        return Ok(false);
    };
    session.commit(vec![Command::Trash { entity: pin }], "unpin", Author::User)?;
    Ok(true)
}

// ---- layers (P17i): workspace layout snapshots as small entities ----

/// Save a layout layer: a NAMED backstage entity whose ordered `related`
/// cells are the tabs to reopen, scoped to a workspace. Mirrors the pin
/// seed — the `layer` type is birthed lazily inside the same transaction
/// as the first save, so a save is always one commit, one undo. Restore
/// is pure shell (mutates nothing in the log); rename/delete ride the
/// ordinary set/trash doors.
pub fn create_layer(
    session: &mut Session,
    name: &str,
    workspace: Option<Id>,
    members: &[Id],
    created: DateTime,
) -> Result<Id, PersistError> {
    let store = session.store();
    let layer_type = find_type(store, "layer");
    let related = property_id(store, "related");
    let ws_prop = property_id(store, "workspace");
    let members: Vec<Id> = members.iter().map(|m| store.resolve(*m)).collect();

    let mut commands = Vec::new();
    let type_id = layer_type.unwrap_or_else(|| {
        let t = session.allocate_id();
        commands.push(Command::Create { entity: t });
        let expected = related.unwrap_or(props::NAME);
        for cell in [
            Cell { property: props::NAME, value: Value::text("layer") },
            Cell { property: props::WORKING, value: Value::Bool(true) },
            // EXPECTED makes find_type resolve it (the P9 rule).
            Cell { property: props::EXPECTED, value: Value::Reference(expected) },
        ] {
            commands.push(Command::AddCell { entity: t, cell });
        }
        t
    });

    let id = session.allocate_id();
    commands.push(Command::Create { entity: id });
    let mut add = |property: Id, value: Value| {
        commands.push(Command::AddCell { entity: id, cell: Cell { property, value } });
    };
    add(props::NAME, Value::text(name));
    add(props::WORKING, Value::Bool(true));
    add(props::CREATED, Value::DateTime(created));
    add(props::TYPE, Value::Reference(type_id));
    if let (Some(w), Some(wp)) = (workspace, ws_prop) {
        add(wp, Value::Reference(w));
    }
    if let Some(related) = related {
        for member in members {
            add(related, Value::Reference(member));
        }
    }
    session.commit(commands, "save layout", Author::User)?;
    Ok(id)
}

// ---- habits (P18b): front-of-house habits, backstage check-in records ----

/// Create a habit — an ordinary front-of-house entity (habits belong in
/// Everything): NAME + type + optional `points` (default 1 at read) +
/// optional `cadence` display text. One commit.
pub fn create_habit(
    session: &mut Session,
    name: &str,
    points: Option<f64>,
    cadence: Option<&str>,
    created: DateTime,
) -> Result<Id, PersistError> {
    let store = session.store();
    let habit_type = find_type(store, "habit");
    let points_prop = property_id(store, "points");
    let cadence_prop = property_id(store, "cadence");

    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    let mut add = |property: Id, value: Value| {
        commands.push(Command::AddCell { entity: id, cell: Cell { property, value } });
    };
    add(props::NAME, Value::text(name));
    add(props::CREATED, Value::DateTime(created));
    if let Some(t) = habit_type {
        add(props::TYPE, Value::Reference(t));
    }
    if let (Some(p), Some(pp)) = (points, points_prop) {
        add(pp, Value::Number(p));
    }
    if let (Some(c), Some(cp)) = (cadence, cadence_prop) {
        add(cp, Value::text(c));
    }
    session.commit(commands, "new habit", Author::User)?;
    Ok(id)
}

/// A habit's live check-in on a civil day, if one exists.
fn check_in_on(store: &Store, habit: Id, day: i64) -> Option<Id> {
    let checkin_type = find_type(store, "check-in")?;
    let habit_prop = property_id(store, "habit")?;
    let date_prop = property_id(store, "date")?;
    store
        .entities()
        .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(checkin_type)))
        .filter(|e| e.has(habit_prop, &Value::Reference(habit)))
        .find(|e| matches!(e.get(date_prop), Some(Value::DateTime(dt)) if dt.civil / 10_000 == day))
        .map(|e| e.id)
}

/// Check a habit in on a day: one WORKING backstage record (habit reference +
/// date), one commit, one undo. Idempotent per (habit, day) — the checkbox
/// toggle is safe. Uncheck = trash the exact row (no verb of its own).
pub fn check_in(
    session: &mut Session,
    habit: Id,
    day: i64,
    created: DateTime,
) -> Result<Id, PersistError> {
    let store = session.store();
    let habit = store.resolve(habit);
    if let Some(existing) = check_in_on(store, habit, day) {
        return Ok(existing);
    }
    let checkin_type = find_type(store, "check-in");
    let habit_prop = property_id(store, "habit");
    let date_prop = property_id(store, "date");

    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    let mut add = |property: Id, value: Value| {
        commands.push(Command::AddCell { entity: id, cell: Cell { property, value } });
    };
    add(props::WORKING, Value::Bool(true));
    add(props::CREATED, Value::DateTime(created));
    if let Some(t) = checkin_type {
        add(props::TYPE, Value::Reference(t));
    }
    if let Some(hp) = habit_prop {
        add(hp, Value::Reference(habit));
    }
    if let Some(dp) = date_prop {
        add(dp, Value::DateTime(DateTime::at(
            (day / 10_000) as i32,
            ((day / 100) % 100) as u32,
            (day % 100) as u32,
            0,
            0,
        )));
    }
    session.commit(commands, "check in", Author::User)?;
    Ok(id)
}

// ---- P18d: time entries · saved views · widgets (lazy-birth, one txn) ----

/// Push Create+cells for a new backstage PROPERTY definition; returns its id.
fn push_property_birth(
    session: &mut Session,
    commands: &mut Vec<Command>,
    name: &str,
    kind: &str,
) -> Id {
    let id = session.allocate_id();
    commands.push(Command::Create { entity: id });
    for cell in [
        Cell { property: props::NAME, value: Value::text(name) },
        Cell { property: props::VALUE_KIND, value: Value::text(kind) },
        Cell { property: props::WORKING, value: Value::Bool(true) },
    ] {
        commands.push(Command::AddCell { entity: id, cell });
    }
    id
}

/// Push Create+cells for a new backstage TYPE; EXPECTED makes find_type
/// resolve it (the P9 rule). Returns its id.
fn push_type_birth(session: &mut Session, commands: &mut Vec<Command>, name: &str, expected: Id) -> Id {
    let id = session.allocate_id();
    commands.push(Command::Create { entity: id });
    for cell in [
        Cell { property: props::NAME, value: Value::text(name) },
        Cell { property: props::WORKING, value: Value::Bool(true) },
        Cell { property: props::EXPECTED, value: Value::Reference(expected) },
    ] {
        commands.push(Command::AddCell { entity: id, cell });
    }
    id
}

/// Log ONE closed time interval against a target — written whole, at stop
/// (the log never holds a half-open promise; the running timer is shell
/// state). Lazily births the `time-entry` type + start/end (+target)
/// properties inside the same transaction: one commit, one undo.
pub fn log_time(
    session: &mut Session,
    target: Id,
    start: DateTime,
    end: DateTime,
) -> Result<Id, PersistError> {
    let store = session.store();
    let target = store.resolve(target);
    let entry_type = find_type(store, "time-entry");
    let target_prop = property_id(store, "target");
    let start_prop = property_id(store, "start");
    let end_prop = property_id(store, "end");

    let mut commands = Vec::new();
    let target_prop =
        target_prop.unwrap_or_else(|| push_property_birth(session, &mut commands, "target", "reference"));
    let start_prop =
        start_prop.unwrap_or_else(|| push_property_birth(session, &mut commands, "start", "datetime"));
    let end_prop =
        end_prop.unwrap_or_else(|| push_property_birth(session, &mut commands, "end", "datetime"));
    let type_id =
        entry_type.unwrap_or_else(|| push_type_birth(session, &mut commands, "time-entry", start_prop));

    let id = session.allocate_id();
    commands.push(Command::Create { entity: id });
    let mut add = |property: Id, value: Value| {
        commands.push(Command::AddCell { entity: id, cell: Cell { property, value } });
    };
    add(props::WORKING, Value::Bool(true));
    add(props::CREATED, Value::DateTime(end));
    add(props::TYPE, Value::Reference(type_id));
    add(target_prop, Value::Reference(target));
    add(start_prop, Value::DateTime(start));
    add(end_prop, Value::DateTime(end));
    session.commit(commands, "log time", Author::User)?;
    Ok(id)
}

/// Save a view: a NAMED backstage entity carrying the query string — the one
/// filter engine's bookmark (feature-map #21/#28). One commit.
pub fn create_view(
    session: &mut Session,
    name: &str,
    query: &str,
    created: DateTime,
) -> Result<Id, PersistError> {
    let store = session.store();
    let view_type = find_type(store, "view");
    let query_prop = property_id(store, "query");

    let mut commands = Vec::new();
    let query_prop =
        query_prop.unwrap_or_else(|| push_property_birth(session, &mut commands, "query", "text"));
    let type_id =
        view_type.unwrap_or_else(|| push_type_birth(session, &mut commands, "view", query_prop));

    let id = session.allocate_id();
    commands.push(Command::Create { entity: id });
    let mut add = |property: Id, value: Value| {
        commands.push(Command::AddCell { entity: id, cell: Cell { property, value } });
    };
    add(props::NAME, Value::text(name));
    add(props::WORKING, Value::Bool(true));
    add(props::CREATED, Value::DateTime(created));
    add(props::TYPE, Value::Reference(type_id));
    add(query_prop, Value::text(query));
    session.commit(commands, "save view", Author::User)?;
    Ok(id)
}

/// Add a board widget: a small backstage entity — kind + scope + span +
/// float order (the pins pattern). Config edits ride the ordinary set door
/// (the Inspector); removal rides trash. One commit, one undo — including
/// the lazy type/property births on a fresh box.
pub fn add_widget(
    session: &mut Session,
    kind: &str,
    workspace: Option<Id>,
    span: Option<f64>,
    created: DateTime,
) -> Result<Id, PersistError> {
    let store = session.store();
    let widget_type = find_type(store, "widget");
    let kind_prop = property_id(store, "widget-kind");
    let span_prop = property_id(store, "span");
    let range_prop = property_id(store, "range");
    let order_prop = property_id(store, "order");
    let ws_prop = property_id(store, "workspace");

    // Land after the last widget: max order + 10.
    let next_order = match (widget_type, order_prop) {
        (Some(t), Some(order)) => {
            store
                .entities()
                .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(t)))
                .filter_map(|e| match e.get(order) {
                    Some(Value::Number(n)) => Some(*n),
                    _ => None,
                })
                .fold(0.0_f64, f64::max)
                + 10.0
        }
        _ => 10.0,
    };

    let mut commands = Vec::new();
    let kind_prop =
        kind_prop.unwrap_or_else(|| push_property_birth(session, &mut commands, "widget-kind", "text"));
    let span_prop =
        span_prop.unwrap_or_else(|| push_property_birth(session, &mut commands, "span", "number"));
    if range_prop.is_none() {
        // Born beside widget-kind so the Inspector can offer it immediately.
        let _ = push_property_birth(session, &mut commands, "range", "text");
    }
    let type_id =
        widget_type.unwrap_or_else(|| push_type_birth(session, &mut commands, "widget", kind_prop));

    let id = session.allocate_id();
    commands.push(Command::Create { entity: id });
    let mut add = |property: Id, value: Value| {
        commands.push(Command::AddCell { entity: id, cell: Cell { property, value } });
    };
    add(props::WORKING, Value::Bool(true));
    add(props::CREATED, Value::DateTime(created));
    add(props::TYPE, Value::Reference(type_id));
    add(kind_prop, Value::text(kind));
    if let Some(s) = span {
        add(span_prop, Value::Number(s));
    }
    if let (Some(w), Some(wp)) = (workspace, ws_prop) {
        add(wp, Value::Reference(w));
    }
    if let Some(op) = order_prop {
        add(op, Value::Number(next_order));
    }
    session.commit(commands, "add widget", Author::User)?;
    Ok(id)
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
    // THE NAME INDEX, not a scan (T2, owner 2026-08-22). This built a
    // Query and ran a full-store scan, on every call — and `create_note`
    // calls it on every creation, so building a box was O(n²): 6,557
    // notes/s at 10,000 entities, 1,354/s at 40,000, with 98% of a
    // 500,000-entity build's samples inside this one function.
    //
    // The index T1 added answers exactly this question. The two filters
    // reproduce what the query did: `run` drops trashed entities and
    // sorts by id before `first()`, and `names` is deliberately
    // unfiltered ("trash and plumbing are read-time concerns"), so the
    // read-time concerns live here now.
    //
    // `include_working: true` had no filter to bypass — the working flag
    // is not a constraint the name index can carry — and no type entity
    // has ever worn it.
    store
        .named(name)
        .iter()
        .copied()
        .filter(|&id| {
            store.get(id).is_some_and(|e| {
                !e.trashed && e.all(props::EXPECTED).next().is_some()
            })
        })
        .min()
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

/// Stamp an entity's TYPE by type NAME — the Inbox Route commit (P12 12d)
/// and, later, the inspector's type editor. `set_property` can't: TYPE is a
/// reference and its parser wants "#id", but type entities are working
/// plumbing the shell never sees. This resolves the name via `find_type`
/// and replaces the TYPE cell (one type, not two). An unknown name refuses.
pub fn set_type(session: &mut Session, id: Id, type_name: &str) -> Result<(), WriteError> {
    let store = session.store();
    let id = store.resolve(id);
    let entity = store.get(id).ok_or(WriteError::Refused(format!("no entity #{id}")))?;
    let type_id = find_type(store, type_name)
        .ok_or(WriteError::Refused(format!("no type named {type_name}")))?;
    let commands: Vec<Command> = entity
        .all(props::TYPE)
        .cloned()
        .map(|old| Command::RemoveCell { entity: id, cell: Cell { property: props::TYPE, value: old } })
        .chain(std::iter::once(Command::AddCell {
            entity: id,
            cell: Cell { property: props::TYPE, value: Value::Reference(type_id) },
        }))
        .collect();
    session
        .commit(commands, format!("set type {type_name}"), Author::User)
        .map_err(|e| WriteError::Persist(e.to_string()))?;
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

pub(crate) fn parse_civil(raw: &str) -> Option<Value> {
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


// MARK: the display name — what a LIST calls this entity

/// The name to SHOW for an entity: its name cell, else the first
/// non-empty line of its content with the block marker taken off, else
/// `#id`.
///
/// This is what every list in every shell wants, and until 2026-08-07
/// the snapshot handed them `liv_views::summary` instead — the whole
/// body flattened into one line, so a daily note read as
/// "Thu 6 Aug ## Today - [ ] milk ## Notes" everywhere it appeared.
/// `summary` still exists and still means what it says; it is simply not
/// the answer to "what is this called" (owner, 2026-08-07).
/// Plain typed text → spans, one `Break(Body)` per newline.
///
/// The ONE grammar for "someone typed this into a box" (standing rule 4).
/// Markers stay literal — `## Gear` is the characters `## Gear`, and the
/// renderer decides what that looks like — so this never guesses at
/// structure the typist did not ask for. `markdown.rs` is the other
/// parser, and it is for FILES, which really are markdown.
///
/// The lines matter because everything downstream counts them: a name is
/// the first line (`source_name`), the clerk reads line by line, and the
/// editor round-trips paragraphs.
pub fn plain_spans(text: &str) -> Vec<Span> {
    let mut spans = Vec::new();
    for (i, line) in text.split('\n').enumerate() {
        if i > 0 {
            spans.push(Span::Break(Block::Body));
        }
        if !line.is_empty() {
            spans.push(Span::text(line));
        }
    }
    spans
}

pub fn display_name(store: &Store, entity: &Entity) -> String {
    match entity.get(props::CONTENT) {
        Some(Value::RichText(rich)) => source_name(store, entity, rich),
        _ => source_name(store, entity, &RichText::default()),
    }
}

/// The note's own display name: the name cell, else its FIRST non-empty
/// line with any block marker stripped. Never a whole-body summary.
pub(crate) fn source_name(store: &Store, entity: &Entity, rich: &RichText) -> String {
    if let Some(Value::Text(name)) = entity.get(props::NAME) {
        if !name.trim().is_empty() {
            return name.clone();
        }
    }
    let mut text = String::new();
    let mut block = Block::Body;
    let mut started = false;
    for span in &rich.spans {
        match span {
            Span::Break(next) => {
                if started {
                    let line = strip_marker(&block, &text);
                    if !line.is_empty() {
                        return line;
                    }
                    text.clear();
                }
                block = next.clone();
                started = true;
            }
            Span::Text(t) => {
                text.push_str(&t.text);
                started = true;
            }
            Span::Ref(target) => {
                text.push_str(&crate::tasks::name_of(store, *target));
                started = true;
            }
        }
    }
    let line = strip_marker(&block, &text);
    if line.is_empty() {
        format!("#{}", entity.id)
    } else {
        line
    }
}

/// One line, ALL syntax off — block markers, inline markers, reference
/// tokens. "Syntax must never appear in a title" (owner, 2026-08-07).
/// The rules mirror the iOS editor's scanner (EditorStyle.swift
/// MarkScan.shape / .inline) to the letter, so the stored title and the
/// live editor preview never disagree about the same line.
fn strip_marker(block: &Block, text: &str) -> String {
    if let Some(words) = crate::tasks::task_words(block, text) {
        return words;
    }
    let line = strip_block_marker(text.trim());
    strip_inline(line).trim().to_string()
}

/// The block marker, matched precisely — a greedy leading-character trim
/// mangled a line STARTING with bold ("**Bold start** rest" became
/// "Bold start** rest") and kept the brackets of a checked box.
fn strip_block_marker(line: &str) -> &str {
    let b = line.as_bytes();
    // A rule line (3+ of - * _, nothing else) has no words at all.
    if let Some(&first) = b.first() {
        if matches!(first, b'-' | b'*' | b'_') {
            let run = b.iter().take_while(|c| **c == first).count();
            if run >= 3 && b[run..].iter().all(|c| matches!(c, b' ' | b'\t')) {
                return "";
            }
        }
    }
    // Heading: 1-6 hashes then a space. "#errands" is the user's text.
    let hashes = b.iter().take_while(|c| **c == b'#').count();
    if (1..=6).contains(&hashes) && b.get(hashes) == Some(&b' ') {
        return line[hashes + 1..].trim_start();
    }
    // A checkbox, either state (the OPEN state was already taken by
    // task_words; this catches "- [x] " so a done line keeps its words).
    if b.len() >= 6
        && b[0] == b'-'
        && b[1] == b' '
        && b[2] == b'['
        && matches!(b[3], b' ' | b'x' | b'X')
        && b[4] == b']'
        && b[5] == b' '
    {
        return line[6..].trim_start();
    }
    // Bullet: "- " or "* ".
    if b.len() >= 2 && matches!(b[0], b'-' | b'*') && b[1] == b' ' {
        return line[2..].trim_start();
    }
    // Ordered: up to four digits then ". ".
    let digits = b.iter().take_while(|c| c.is_ascii_digit()).count();
    if (1..=4).contains(&digits) && b.get(digits) == Some(&b'.') && b.get(digits + 1) == Some(&b' ')
    {
        return line[digits + 2..].trim_start();
    }
    // Quote: ">" with or without its space.
    if b.first() == Some(&b'>') {
        let skip = if b.get(1) == Some(&b' ') { 2 } else { 1 };
        return line[skip..].trim_start();
    }
    line
}

/// Inline markers off, words kept. Pairs must close on the same line —
/// an unclosed marker is literal text. `code` wins over everything
/// inside it. A named reference token reads as its name; a nameless one
/// stays as typed (there is nothing better to show). All markers are
/// ASCII, so byte scanning is UTF-8 safe.
fn strip_inline(line: &str) -> String {
    let b = line.as_bytes();
    let find = |pat: &[u8], from: usize| -> Option<usize> {
        (from..b.len().saturating_sub(pat.len() - 1)).find(|&j| &b[j..j + pat.len()] == pat)
    };
    let mut out: Vec<u8> = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c == b'`' {
            if let Some(close) = find(b"`", i + 1) {
                out.extend_from_slice(&b[i + 1..close]);
                i = close + 1;
                continue;
            }
        }
        if c == b'[' && b.get(i + 1) == Some(&b'[') {
            let digits_end = (i + 2..b.len()).find(|&j| !b[j].is_ascii_digit()).unwrap_or(b.len());
            let digits = &line[i + 2..digits_end];
            if !digits.is_empty() && digits.parse::<u64>().is_ok() {
                if b.get(digits_end) == Some(&b']') && b.get(digits_end + 1) == Some(&b']') {
                    out.extend_from_slice(&b[i..digits_end + 2]); // nameless: as typed
                    i = digits_end + 2;
                    continue;
                }
                if b.get(digits_end) == Some(&b'|') {
                    if let Some(close) = find(b"]]", digits_end + 1) {
                        out.extend_from_slice(&b[digits_end + 1..close]); // the name
                        i = close + 2;
                        continue;
                    }
                }
            }
        }
        if c == b'*' && b.get(i + 1) == Some(&b'*') {
            if let Some(close) = find(b"**", i + 2) {
                if close > i + 2 {
                    out.extend_from_slice(&b[i + 2..close]);
                    i = close + 2;
                    continue;
                }
            }
        }
        if c == b'*' {
            if let Some(close) = find(b"*", i + 1) {
                if close > i + 1 && b.get(close + 1) != Some(&b'*') {
                    out.extend_from_slice(&b[i + 1..close]);
                    i = close + 1;
                    continue;
                }
            }
        }
        if c == b'~' && b.get(i + 1) == Some(&b'~') {
            if let Some(close) = find(b"~~", i + 2) {
                if close > i + 2 {
                    out.extend_from_slice(&b[i + 2..close]);
                    i = close + 2;
                    continue;
                }
            }
        }
        out.push(c);
        i += 1;
    }
    String::from_utf8(out).unwrap_or_else(|_| line.to_string())
}
