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
    props, Author, Cell, Command, DateTime, Entity, Id, Proposal, RichText, Span, Store, Value,
};

use crate::dates::{add_days, days_in_month, parts, show_date, weekday, WEEKDAYS};
use crate::{property_id, run, Constraint, Op, Query};

/// The properties the clerk proposes with, looked up by name once per
/// sweep. None when a box predates the starter library.
struct Vocabulary {
    due: Id,
    related: Id,
}

impl Vocabulary {
    fn find(store: &Store) -> Option<Vocabulary> {
        Some(Vocabulary {
            due: property_id(store, "due")?,
            related: property_id(store, "related")?,
        })
    }
}

/// Read every candidate entity, propose, and drop duplicates of anything
/// pending or declined. `today` is the caller's civil date — the clerk
/// itself has no clock.
pub fn sweep(store: &Store, today: DateTime) -> Vec<Proposal> {
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
        // sweeps, so what the inbox shows is what accept commits.
        let anchor = match entity.get(props::CREATED) {
            Some(Value::DateTime(created)) => {
                let (y, m, d) = parts(*created);
                DateTime::date(y, m, d)
            }
            _ => today,
        };
        propose_dates(&vocabulary, entity, &text, anchor, &mut proposals);
        propose_mentions(&vocabulary, entity, &text, &gazetteer, &mut proposals);
    }

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

/// The durable meaning of a refusal: (proposer, entity, property).
fn decline_key(proposal: &Proposal) -> Option<(&str, Id, Id)> {
    match (&proposal.author, proposal.commands.as_slice()) {
        (Author::Proposer(name), [Command::AddCell { entity, cell }]) => {
            Some((name.as_str(), *entity, cell.property))
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
                    Span::Text(t) => Some(t.as_str()),
                    Span::Ref(_) => None,
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
    anchor: DateTime,
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

/// Scan the words; the first one that names a date wins. Relative words
/// resolve against `anchor` — the day the text was written.
fn first_date(text: &str, anchor: DateTime) -> Option<(String, DateTime)> {
    for raw in text.split_whitespace() {
        let word: String = raw
            .trim_matches(|c: char| !c.is_ascii_alphanumeric() && c != '-')
            .to_lowercase();
        if word.is_empty() {
            continue;
        }
        if word == "today" {
            let (y, m, d) = parts(anchor);
            return Some((word, DateTime::date(y, m, d)));
        }
        if word == "tomorrow" {
            return Some((word, add_days(anchor, 1)));
        }
        if let Some(target) = WEEKDAYS.iter().position(|w| *w == word) {
            let delta = (target as u32 + 7 - weekday(anchor)) % 7;
            return Some((word, add_days(anchor, delta)));
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
fn contains_word(haystack: &str, needle: &str) -> bool {
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
