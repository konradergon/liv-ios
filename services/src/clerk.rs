//! Clerk v0 — milestone 5. Regex-grade proposers, exactly the two the
//! constitution names: dates in text, mentions of known names.
//!
//! The clerk reads through the same store every view reads, writes nothing,
//! and returns proposals — the only thing a proposer can express. It runs
//! behind the write and sweeps at open; a duplicate of anything pending or
//! declined is dropped before it reaches the queue. Nothing asks again.
//!
//! The language model of milestone 8 is a brain swap behind this socket.

use lotus_core::{
    props, Author, Block, Cell, Command, DateTime, Entity, Id, Proposal, RichText, Span, Store,
    Value,
};

use crate::content::{find_option, find_type};
use crate::dates::{add_days, days_in_month, parts, show_date, weekday, WEEKDAYS};
use crate::{property_id, run, Constraint, Op, Query};

/// The properties the clerk proposes with, looked up by name once per
/// sweep. `due`/`related` are required (a box that predates the starter
/// library gets no proposals); the P16 vocabulary is optional per proposer.
struct Vocabulary {
    due: Id,
    related: Id,
    priority: Option<Id>,
    status: Option<Id>,
    task_type: Option<Id>,
    todo: Option<Id>,
}

impl Vocabulary {
    fn find(store: &Store) -> Option<Vocabulary> {
        Some(Vocabulary {
            due: property_id(store, "due")?,
            related: property_id(store, "related")?,
            priority: property_id(store, "priority"),
            status: property_id(store, "status"),
            task_type: find_type(store, "task"),
            todo: todo_option(store),
        })
    }
}

/// The `todo` status option a promoted task takes — the same resolution
/// `create_task` uses (the type's `default-status`, else the `todo` option).
fn todo_option(store: &Store) -> Option<Id> {
    find_type(store, "task")
        .and_then(|t| store.get(t))
        .zip(property_id(store, "default-status"))
        .and_then(|(t, p)| match t.get(p) {
            Some(Value::Reference(option)) => Some(*option),
            _ => None,
        })
        .or_else(|| property_id(store, "status").and_then(|s| find_option(store, s, "todo")))
}

/// Read every candidate entity, propose, and drop duplicates of anything
/// pending or declined. `today` is the caller's civil date — the clerk
/// itself has no clock.
pub fn sweep(store: &Store, _today: DateTime) -> Vec<Proposal> {
    // `_today` is deliberately unused since the anchor fix: every date the
    // clerk proposes derives from the store alone, so the sweep is a pure
    // function of the box and identical in every process. The clock stays
    // in the signature for future proposers that legitimately need one.
    let Some(vocabulary) = Vocabulary::find(store) else {
        return Vec::new();
    };
    let gazetteer = gazetteer(store);

    // Deterministic order, or triage lies: the inbox is re-derived by
    // every process, and "accept 2" must mean the same proposal the user
    // just read. Entities by id; per entity, dates before mentions;
    // the gazetteer arrives sorted from run().
    let mut entities: Vec<&Entity> = store.entities().collect();
    entities.sort_by_key(|e| e.id);

    let mut proposals = Vec::new();
    for entity in entities {
        if entity.trashed || entity.has(props::WORKING, &Value::Bool(true)) {
            continue;
        }
        let Some(text) = plain_content(entity) else {
            continue;
        };
        // "Tomorrow" means the day after the thought, not the day after
        // the sweep: relative words resolve against the scrap's own
        // creation date. This also makes proposals identical across
        // sweeps, so what the inbox shows is what accept commits. An
        // entity with no creation date gets no relative-date guesses at
        // all — a proposal that drifts with the clock is a lie waiting
        // for midnight. (Absolute dates need no anchor.)
        let anchor = match entity.get(props::CREATED) {
            Some(Value::DateTime(created)) => {
                let (y, m, d) = parts(*created);
                Some(DateTime::date(y, m, d))
            }
            _ => None,
        };
        propose_dates(&vocabulary, entity, &text, anchor, &mut proposals);
        propose_mentions(&vocabulary, entity, &text, &gazetteer, &mut proposals);
        propose_priority(store, &vocabulary, entity, &text, &mut proposals);
        propose_promotion(&vocabulary, entity, &mut proposals);
    }

    // AI never touches the owner's value judgments (catalog a13): drop any
    // proposal that would set `tier` or `private`. A hard, tested invariant so
    // a future proposer can never smuggle one in.
    let protected: Vec<Id> = [property_id(store, "tier"), Some(props::PRIVATE)]
        .into_iter()
        .flatten()
        .collect();
    proposals.retain(|p| {
        !p.commands.iter().any(|c| {
            matches!(c, Command::AddCell { cell, .. } if protected.contains(&cell.property))
        })
    });

    // Pending dedups by exact commands. Declined dedups by what the user
    // actually refused — this proposer, this entity, this property — so a
    // refusal outlives any drift in the proposed value.
    proposals.retain(|p| {
        !store.pending().iter().any(|q| q.commands == p.commands)
            && !store.declined().iter().any(|q| {
                q.commands == p.commands
                    || (decline_key(q).is_some() && decline_key(q) == decline_key(p))
            })
    });
    proposals
}

/// The durable meaning of a refusal: (proposer, entity, property). A single
/// AddCell keys on its cell; a multi-cell proposal on ONE entity (promotion)
/// keys on the first cell's property — so declining it never re-asks.
fn decline_key(proposal: &Proposal) -> Option<(&str, Id, Id)> {
    let Author::Proposer(name) = &proposal.author else {
        return None;
    };
    match proposal.commands.as_slice() {
        [Command::AddCell { entity, cell }] => Some((name.as_str(), *entity, cell.property)),
        cmds if !cmds.is_empty() && cmds.iter().all(|c| matches!(c, Command::AddCell { .. })) => {
            let (entity, first_prop) = match &cmds[0] {
                Command::AddCell { entity, cell } => (*entity, cell.property),
                _ => return None,
            };
            cmds.iter()
                .all(|c| matches!(c, Command::AddCell { entity: e, .. } if *e == entity))
                .then_some((name.as_str(), entity, first_prop))
        }
        _ => None,
    }
}

/// Everything named and front-of-house is a name worth noticing.
fn gazetteer(store: &Store) -> Vec<(Id, String)> {
    let named = Query {
        constraints: vec![Constraint {
            property: props::NAME,
            op: Op::Exists,
        }],
        ..Query::default()
    };
    run(store, &named)
        .into_iter()
        .filter_map(|id| {
            let entity = store.get(id)?;
            match entity.get(props::NAME) {
                Some(Value::Text(name)) if name.chars().count() >= 3 => {
                    Some((id, name.clone()))
                }
                _ => None,
            }
        })
        .collect()
}

/// The text spans of the content cell, flattened.
fn plain_content(entity: &Entity) -> Option<String> {
    match entity.get(props::CONTENT)? {
        Value::RichText(RichText { spans }) => Some(
            spans
                .iter()
                .filter_map(|s| match s {
                    Span::Text(t) => Some(t.text.as_str()),
                    Span::Break(_) | Span::Ref(_) => None,
                })
                .collect::<Vec<_>>()
                .join(" "),
        ),
        Value::Text(t) => Some(t.clone()),
        _ => None,
    }
}

/// "friday", "today", "tomorrow", "2026-07-10" — the first date wins.
/// Only for entities with no due yet: the clerk suggests, never competes.
fn propose_dates(
    vocabulary: &Vocabulary,
    entity: &Entity,
    text: &str,
    anchor: Option<DateTime>,
    proposals: &mut Vec<Proposal>,
) {
    if entity.all(vocabulary.due).next().is_some() {
        return;
    }
    let Some((word, date)) = first_date(text, anchor) else {
        return;
    };
    proposals.push(Proposal {
        commands: vec![Command::AddCell {
            entity: entity.id,
            cell: Cell {
                property: vocabulary.due,
                value: Value::DateTime(date),
            },
        }],
        label: format!("due {}", show_date(date)),
        author: Author::Proposer("dates".into()),
        reason: format!("contains \"{word}\" → due {}?", show_date(date)),
    });
}

/// A known name in the text becomes a proposed relation — once.
fn propose_mentions(
    vocabulary: &Vocabulary,
    entity: &Entity,
    text: &str,
    gazetteer: &[(Id, String)],
    proposals: &mut Vec<Proposal>,
) {
    let lower = text.to_lowercase();
    for (target, name) in gazetteer {
        if *target == entity.id {
            continue;
        }
        if entity.has(vocabulary.related, &Value::Reference(*target)) {
            continue;
        }
        if !contains_word(&lower, &name.to_lowercase()) {
            continue;
        }
        proposals.push(Proposal {
            commands: vec![Command::AddCell {
                entity: entity.id,
                cell: Cell {
                    property: vocabulary.related,
                    value: Value::Reference(*target),
                },
            }],
            label: format!("relate to {name}"),
            author: Author::Proposer("mentions".into()),
            reason: format!("mentions \"{name}\" → relate?"),
        });
    }
}

/// A CLOSED priority-word lexicon (P16): the first trigger wins, and only
/// when it resolves to a real `priority` option (never an invented value).
/// Proposes only for an entity with no priority yet — suggests, never competes.
fn propose_priority(
    store: &Store,
    vocabulary: &Vocabulary,
    entity: &Entity,
    text: &str,
    proposals: &mut Vec<Proposal>,
) {
    let Some(priority) = vocabulary.priority else {
        return;
    };
    if entity.all(priority).next().is_some() {
        return;
    }
    let lower = text.to_lowercase();
    let name = if lower.contains("urgent") || lower.contains("asap") || text.contains("!!!") {
        "high"
    } else if lower.contains("low priority") || lower.contains("whenever") {
        "low"
    } else {
        return;
    };
    let Some(option) = find_option(store, priority, name) else {
        return; // the option doesn't exist — stay quiet, never invent
    };
    proposals.push(Proposal {
        commands: vec![Command::AddCell {
            entity: entity.id,
            cell: Cell { property: priority, value: Value::Select(option) },
        }],
        label: format!("priority {name}"),
        author: Author::Proposer("priority".into()),
        reason: format!("a priority word → priority {name}?"),
    });
}

/// An untyped capture whose content's first block is a task checkbox is a task
/// waiting for its type (P16 promotion). Promotes the scrap IN PLACE (line-item
/// extraction from inside a note is the Agent's door — it needs a new id).
fn propose_promotion(vocabulary: &Vocabulary, entity: &Entity, proposals: &mut Vec<Proposal>) {
    let Some(task_type) = vocabulary.task_type else {
        return; // no task type in this box — nothing to promote to
    };
    if entity.all(props::TYPE).next().is_some() {
        return; // already typed
    }
    if !first_block_is_task(entity) {
        return;
    }
    let mut commands = vec![Command::AddCell {
        entity: entity.id,
        cell: Cell { property: props::TYPE, value: Value::Reference(task_type) },
    }];
    if let (Some(status), Some(todo)) = (vocabulary.status, vocabulary.todo) {
        commands.push(Command::AddCell {
            entity: entity.id,
            cell: Cell { property: status, value: Value::Select(todo) },
        });
    }
    proposals.push(Proposal {
        commands,
        label: "promote to task".into(),
        author: Author::Proposer("promotion".into()),
        reason: "starts with a checkbox → make it a task?".into(),
    });
}

/// True when the content's first paragraph break types it a task.
fn first_block_is_task(entity: &Entity) -> bool {
    let Some(Value::RichText(rich)) = entity.get(props::CONTENT) else {
        return false;
    };
    matches!(
        rich.spans.iter().find_map(|s| match s {
            Span::Break(block) => Some(block),
            _ => None,
        }),
        Some(Block::Task { .. })
    )
}

/// Scan the words; the first one that names a date wins. Relative words
/// resolve against `anchor` — the day the text was written — and are
/// skipped entirely when there is no anchor to resolve against.
fn first_date(text: &str, anchor: Option<DateTime>) -> Option<(String, DateTime)> {
    for raw in text.split_whitespace() {
        let word: String = raw
            .trim_matches(|c: char| !c.is_ascii_alphanumeric() && c != '-')
            .to_lowercase();
        if word.is_empty() {
            continue;
        }
        if word == "today" {
            if let Some(anchor) = anchor {
                let (y, m, d) = parts(anchor);
                return Some((word, DateTime::date(y, m, d)));
            }
            continue;
        }
        if word == "tomorrow" {
            if let Some(anchor) = anchor {
                return Some((word, add_days(anchor, 1)));
            }
            continue;
        }
        if let Some(target) = WEEKDAYS.iter().position(|w| *w == word) {
            if let Some(anchor) = anchor {
                let delta = (target as u32 + 7 - weekday(anchor)) % 7;
                return Some((word, add_days(anchor, delta)));
            }
            continue;
        }
        if let Some(date) = iso_date(&word) {
            return Some((word, date));
        }
    }
    None
}

/// yyyy-mm-dd, validated just enough to not be a lie. Digits only in the
/// digit positions: parse() alone would accept "-234-01-01", and a
/// negative year packs into a civil value that cannot round-trip.
fn iso_date(word: &str) -> Option<DateTime> {
    let bytes = word.as_bytes();
    if bytes.len() != 10 || bytes[4] != b'-' || bytes[7] != b'-' {
        return None;
    }
    let digits = |range: std::ops::Range<usize>| bytes[range].iter().all(u8::is_ascii_digit);
    if !digits(0..4) || !digits(5..7) || !digits(8..10) {
        return None;
    }
    let year: i32 = word[0..4].parse().ok()?;
    let month: u32 = word[5..7].parse().ok()?;
    let day: u32 = word[8..10].parse().ok()?;
    if !(1..=12).contains(&month) || day == 0 || day > days_in_month(year, month) {
        return None;
    }
    Some(DateTime::date(year, month, day))
}

/// Whole-word containment: "anna" in "call anna friday", not in "susanna".
/// The codebase's one word-boundary matcher — the clerk's gazetteer and
/// search both call it, so the boundary rule never forks. Callers lowercase
/// both sides first (the clerk convention).
pub fn contains_word(haystack: &str, needle: &str) -> bool {
    if needle.is_empty() {
        return false;
    }
    let mut start = 0;
    while let Some(at) = haystack[start..].find(needle) {
        let begin = start + at;
        let end = begin + needle.len();
        let boundary_before = begin == 0
            || !haystack[..begin].chars().next_back().unwrap().is_alphanumeric();
        let boundary_after =
            end == haystack.len() || !haystack[end..].chars().next().unwrap().is_alphanumeric();
        if boundary_before && boundary_after {
            return true;
        }
        start = end;
    }
    false
}

/// A word-boundary prefix: "chr" begins the word "christie" in "annabel
/// christie", "anna" begins "annabel". Boundary before, any continuation
/// after — the incremental-typing feel search wants, scored below a whole
/// word. Superset of `contains_word` (which also demands a boundary after).
pub fn starts_word(haystack: &str, needle: &str) -> bool {
    if needle.is_empty() {
        return false;
    }
    let mut start = 0;
    while let Some(at) = haystack[start..].find(needle) {
        let begin = start + at;
        let boundary_before = begin == 0
            || !haystack[..begin].chars().next_back().unwrap().is_alphanumeric();
        if boundary_before {
            return true;
        }
        start = begin + needle.len();
    }
    false
}
