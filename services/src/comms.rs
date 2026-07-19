//! Comms (P20g, BP-15): read-only message ingestion. Messages are ordinary
//! entities (type `message`); `external-id` (props::EXTERNAL_ID) is the
//! dedupe key. ONE batch = ONE transaction = one undo — type and property
//! births ride the same commit (the backstage lazy-birth pattern). A
//! re-import with identical feed fields is a literal no-op; a REFRESH
//! updates only the FEED-OWNED cells (from/sent/body/source) and never
//! touches yours (subjects, status, a cleared `unread`). Senders resolve
//! to person entities by exact name match — Liv never guesses; an
//! unresolved sender stays feed-owned text (`from-label`).

use crate::content::{self, find_type};
use crate::property_id;
use lotus_core::*;

pub struct MessageDrop {
    pub external_id: String,
    pub from: String,
    pub source: String,
    /// "yyyy-mm-dd [hh:mm]" — unparseable stamps are dropped (the shell
    /// falls back to created; refuse-never-guess).
    pub sent: Option<String>,
    pub body: String,
}

pub struct ImportOutcome {
    pub created: usize,
    pub updated: usize,
    pub skipped: usize,
}

/// Find the person entity whose NAME equals the sender (case-insensitive,
/// exactly one match — ambiguity resolves to nothing, never a guess).
fn resolve_person(store: &Store, name: &str) -> Option<Id> {
    let person_type = find_type(store, "person")?;
    let wanted = name.to_lowercase();
    let mut hits = store.entities().filter(|e| {
        !e.trashed
            && e.has(props::TYPE, &Value::Reference(person_type))
            && matches!(e.get(props::NAME), Some(Value::Text(n)) if n.to_lowercase() == wanted)
    });
    let first = hits.next()?;
    if hits.next().is_some() {
        return None;
    }
    Some(first.id)
}

fn find_by_external_id<'a>(store: &'a Store, ext: &str) -> Option<&'a Entity> {
    store.entities().find(|e| {
        !e.trashed && matches!(e.get(props::EXTERNAL_ID), Some(Value::Text(x)) if x == ext)
    })
}

pub fn import_messages(
    session: &mut Session,
    drops: &[MessageDrop],
) -> Result<ImportOutcome, content::WriteError> {
    let mut commands: Vec<Command> = Vec::new();
    let mut created = 0;
    let mut updated = 0;
    let mut skipped = 0;

    // Lazy births, batch-scoped: resolve-or-mint each plumbing piece ONCE,
    // pushing the birth commands into this same transaction.
    let store = session.store();
    let mut message_type = find_type(store, "message");
    let mut prop_from = property_id(store, "from");
    let mut prop_from_label = property_id(store, "from-label");
    let mut prop_source = property_id(store, "source");
    let mut prop_sent = property_id(store, "sent");
    let mut prop_unread = property_id(store, "unread");
    let prop_content = property_id(store, "content")
        .ok_or_else(|| content::WriteError::Refused("no content property".into()))?;

    // Pre-resolve everything that needs &Store before we start pushing.
    struct Plan {
        existing: Option<Id>,
        person: Option<Id>,
        sent_value: Option<Value>,
        current_body: Option<String>,
        current_source: Option<String>,
        current_sent: Option<Value>,
        current_from: Option<Id>,
        current_label: Option<String>,
    }
    let plans: Vec<Plan> = drops
        .iter()
        .map(|drop| {
            let existing = find_by_external_id(store, &drop.external_id);
            let text_of = |e: &Entity, p: Option<Id>| match p.and_then(|p| e.get(p)) {
                Some(Value::Text(t)) => Some(t.clone()),
                _ => None,
            };
            Plan {
                existing: existing.map(|e| e.id),
                person: resolve_person(store, &drop.from),
                sent_value: drop.sent.as_deref().and_then(content::parse_civil),
                current_body: existing.and_then(|e| text_of(e, Some(prop_content))),
                current_source: existing.and_then(|e| text_of(e, prop_source)),
                current_sent: existing
                    .and_then(|e| prop_sent.and_then(|p| e.get(p)))
                    .cloned(),
                current_from: existing.and_then(|e| {
                    prop_from.and_then(|p| match e.get(p) {
                        Some(Value::Reference(t)) => Some(*t),
                        _ => None,
                    })
                }),
                current_label: existing.and_then(|e| text_of(e, prop_from_label)),
            }
        })
        .collect();

    let birth_property =
        |session: &mut Session, commands: &mut Vec<Command>, name: &str, kind: &str| -> Id {
            let id = session.allocate_id();
            for cell in [
                Cell { property: props::NAME, value: Value::text(name) },
                Cell { property: props::VALUE_KIND, value: Value::text(kind) },
                Cell { property: props::WORKING, value: Value::Bool(true) },
            ] {
                commands.push(Command::AddCell { entity: id, cell });
            }
            commands.insert(commands.len() - 3, Command::Create { entity: id });
            id
        };

    for (drop, plan) in drops.iter().zip(plans) {
        if drop.external_id.trim().is_empty() {
            skipped += 1;
            continue;
        }
        // Feed-owned upsert legs, shared by create and refresh.
        let sent_changed = plan.sent_value.is_some() && plan.sent_value != plan.current_sent;
        match plan.existing {
            Some(id) => {
                let body_changed = plan.current_body.as_deref() != Some(drop.body.as_str());
                let source_changed = plan.current_source.as_deref() != Some(drop.source.as_str());
                let from_changed = plan.person != plan.current_from
                    || (plan.person.is_none()
                        && plan.current_label.as_deref() != Some(drop.from.as_str()));
                if !body_changed && !source_changed && !sent_changed && !from_changed {
                    skipped += 1;
                    continue;
                }
                updated += 1;
                if body_changed {
                    if let Some(old) = plan.current_body {
                        commands.push(Command::RemoveCell {
                            entity: id,
                            cell: Cell { property: prop_content, value: Value::text(old) },
                        });
                    }
                    commands.push(Command::AddCell {
                        entity: id,
                        cell: Cell { property: prop_content, value: Value::text(&drop.body) },
                    });
                }
                if source_changed {
                    let prop = *prop_source.get_or_insert_with(|| {
                        birth_property(session, &mut commands, "source", "text")
                    });
                    if let Some(old) = plan.current_source {
                        commands.push(Command::RemoveCell {
                            entity: id,
                            cell: Cell { property: prop, value: Value::text(old) },
                        });
                    }
                    commands.push(Command::AddCell {
                        entity: id,
                        cell: Cell { property: prop, value: Value::text(&drop.source) },
                    });
                }
                if sent_changed {
                    let prop = *prop_sent.get_or_insert_with(|| {
                        birth_property(session, &mut commands, "sent", "datetime")
                    });
                    if let Some(old) = plan.current_sent {
                        commands.push(Command::RemoveCell {
                            entity: id,
                            cell: Cell { property: prop, value: old },
                        });
                    }
                    if let Some(value) = plan.sent_value.clone() {
                        commands.push(Command::AddCell {
                            entity: id,
                            cell: Cell { property: prop, value },
                        });
                    }
                }
                // from/from-label refresh intentionally minimal: a NEW
                // resolution writes; an existing user-visible resolution is
                // never torn down by a feed hiccup.
                if let (Some(person), true) = (plan.person, from_changed) {
                    let prop = *prop_from.get_or_insert_with(|| {
                        birth_property(session, &mut commands, "from", "reference")
                    });
                    if let Some(old) = plan.current_from {
                        commands.push(Command::RemoveCell {
                            entity: id,
                            cell: Cell { property: prop, value: Value::Reference(old) },
                        });
                    }
                    commands.push(Command::AddCell {
                        entity: id,
                        cell: Cell { property: prop, value: Value::Reference(person) },
                    });
                }
            }
            None => {
                created += 1;
                let ty = *message_type.get_or_insert_with(|| {
                    let id = session.allocate_id();
                    commands.push(Command::Create { entity: id });
                    for cell in [
                        Cell { property: props::NAME, value: Value::text("message") },
                        Cell { property: props::WORKING, value: Value::Bool(true) },
                        Cell {
                            property: props::EXPECTED,
                            value: Value::Reference(props::EXTERNAL_ID),
                        },
                    ] {
                        commands.push(Command::AddCell { entity: id, cell });
                    }
                    id
                });
                let id = session.allocate_id();
                commands.push(Command::Create { entity: id });
                for cell in [
                    Cell { property: props::TYPE, value: Value::Reference(ty) },
                    Cell { property: props::EXTERNAL_ID, value: Value::text(&drop.external_id) },
                    Cell { property: prop_content, value: Value::text(&drop.body) },
                ] {
                    commands.push(Command::AddCell { entity: id, cell });
                }
                let source_prop = *prop_source.get_or_insert_with(|| {
                    birth_property(session, &mut commands, "source", "text")
                });
                commands.push(Command::AddCell {
                    entity: id,
                    cell: Cell { property: source_prop, value: Value::text(&drop.source) },
                });
                if let Some(value) = plan.sent_value.clone() {
                    let sent_prop = *prop_sent.get_or_insert_with(|| {
                        birth_property(session, &mut commands, "sent", "datetime")
                    });
                    commands.push(Command::AddCell {
                        entity: id,
                        cell: Cell { property: sent_prop, value },
                    });
                }
                if let Some(person) = plan.person {
                    let from_prop = *prop_from.get_or_insert_with(|| {
                        birth_property(session, &mut commands, "from", "reference")
                    });
                    commands.push(Command::AddCell {
                        entity: id,
                        cell: Cell { property: from_prop, value: Value::Reference(person) },
                    });
                } else {
                    let label_prop = *prop_from_label.get_or_insert_with(|| {
                        birth_property(session, &mut commands, "from-label", "text")
                    });
                    commands.push(Command::AddCell {
                        entity: id,
                        cell: Cell { property: label_prop, value: Value::text(&drop.from) },
                    });
                }
                let unread_prop = *prop_unread.get_or_insert_with(|| {
                    birth_property(session, &mut commands, "unread", "bool")
                });
                commands.push(Command::AddCell {
                    entity: id,
                    cell: Cell { property: unread_prop, value: Value::Bool(true) },
                });
            }
        }
    }

    if commands.is_empty() {
        return Ok(ImportOutcome { created, updated, skipped });
    }
    session
        .commit(commands, "message import", Author::User)
        .map_err(|e| content::WriteError::Persist(e.to_string()))?;
    Ok(ImportOutcome { created, updated, skipped })
}
