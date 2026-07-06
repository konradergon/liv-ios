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
        propose_dates(&vocabulary, entity, &text, today, &mut proposals);
        propose_mentions(&vocabulary, entity, &text, &gazetteer, &mut proposals);
    }

    proposals.retain(|p| {
        !store.pending().iter().any(|q| q.commands == p.commands)
            && !store.declined().iter().any(|q| q.commands == p.commands)
    });
    proposals
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
    today: DateTime,
    proposals: &mut Vec<Proposal>,
) {
    if entity.all(vocabulary.due).next().is_some() {
        return;
    }
    let Some((word, date)) = first_date(text, today) else {
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

// ---- civil date arithmetic, dependency-free ----
// The clerk needs "next friday" from a packed civil date; fifty lines of
// calendar beat a clock dependency in a layer that must stay pure.

fn parts(date: DateTime) -> (i32, u32, u32) {
    let ymd = date.civil / 10_000;
    ((ymd / 10_000) as i32, ((ymd / 100) % 100) as u32, (ymd % 100) as u32)
}

fn leap(year: i32) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

fn days_in_month(year: i32, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if leap(year) {
                29
            } else {
                28
            }
        }
        _ => 30,
    }
}

fn add_days(date: DateTime, days: u32) -> DateTime {
    let (mut y, mut m, mut d) = parts(date);
    for _ in 0..days {
        d += 1;
        if d > days_in_month(y, m) {
            d = 1;
            m += 1;
            if m > 12 {
                m = 1;
                y += 1;
            }
        }
    }
    DateTime::date(y, m, d)
}

/// Sakamoto's method; 0 = Sunday.
fn weekday(date: DateTime) -> u32 {
    let (mut y, m, d) = parts(date);
    const T: [i32; 12] = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
    if m < 3 {
        y -= 1;
    }
    ((y + y / 4 - y / 100 + y / 400 + T[(m - 1) as usize] + d as i32).rem_euclid(7)) as u32
}

const WEEKDAYS: [&str; 7] = [
    "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
];

/// Scan the words; the first one that names a date wins.
fn first_date(text: &str, today: DateTime) -> Option<(String, DateTime)> {
    for raw in text.split_whitespace() {
        let word: String = raw
            .trim_matches(|c: char| !c.is_ascii_alphanumeric() && c != '-')
            .to_lowercase();
        if word.is_empty() {
            continue;
        }
        if word == "today" {
            return Some((word, DateTime::date(parts(today).0, parts(today).1, parts(today).2)));
        }
        if word == "tomorrow" {
            return Some((word, add_days(today, 1)));
        }
        if let Some(target) = WEEKDAYS.iter().position(|w| *w == word) {
            let delta = (target as u32 + 7 - weekday(today)) % 7;
            return Some((word, add_days(today, delta)));
        }
        if let Some(date) = iso_date(&word) {
            return Some((word, date));
        }
    }
    None
}

/// yyyy-mm-dd, validated just enough to not be a lie.
fn iso_date(word: &str) -> Option<DateTime> {
    let bytes = word.as_bytes();
    if bytes.len() != 10 || bytes[4] != b'-' || bytes[7] != b'-' {
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

fn show_date(date: DateTime) -> String {
    let (y, m, d) = parts(date);
    format!("{y:04}-{m:02}-{d:02}")
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
