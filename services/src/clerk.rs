//! Clerk v0 — milestone 5. Regex-grade proposers, exactly the two the
//! constitution names: dates in text, mentions of known names.
//!
//! The clerk reads through the same store every view reads, writes nothing,
//! and returns proposals — the only thing a proposer can express. It runs
//! behind the write and sweeps at open; a duplicate of anything pending or
//! declined is dropped before it reaches the queue. Nothing asks again.
//!
//! The language model of milestone 8 is a brain swap behind this socket.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use liv_core::{
    props, Author, Block, Cell, Command, DateTime, Entity, Id, PersistError, Proposal, RichText,
    Session, Span, Store, Value, NONE,
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
/// Resolve the assist switch: the backstage `assist` entity and its switch
/// cell — the sole non-WORKING Bool cell on it, WHATEVER its property is
/// named today. The P19 review's high: the `automation` definition rides
/// the ordinary definitions catalog, so a rename (or retype) through an
/// ordinary door must never move the consent. The cell survives both —
/// only the definition's display attributes change. Returns
/// (entity, switch property, on).
pub fn assist_switch(store: &Store) -> Option<(Id, Id, bool)> {
    store
        .entities()
        .find(|e| {
            !e.trashed
                && e.has(liv_core::props::WORKING, &Value::Bool(true))
                && matches!(e.get(liv_core::props::NAME), Some(Value::Text(n)) if n == "assist")
        })
        .and_then(|e| {
            e.cells.iter().find_map(|c| match &c.value {
                Value::Bool(on) if c.property != liv_core::props::WORKING => {
                    Some((e.id, c.property, *on))
                }
                _ => None,
            })
        })
}

/// The P19h consent gate. Absent (an older box) or true = on; only an
/// explicit false silences the clerk.
pub fn assist_enabled(store: &Store) -> bool {
    !matches!(assist_switch(store), Some((_, _, false)))
}

/// Can the sweep REBUILD a pending draft by this author from the store
/// alone? True only for the clerk's own proposers, which read the words
/// and re-derive. A draft from anyone else — a model, another device —
/// exists only in the draft itself; retracting it loses it (owner,
/// 2026-08-07).
pub fn rederivable(author: &Author) -> bool {
    matches!(author, Author::Proposer(name)
        if ["dates", "mentions", "priority", "promotion", "dedupe"]
            .contains(&name.as_str()))
}

pub fn sweep(store: &Store, _today: DateTime) -> Vec<Proposal> {
    // `_today` is deliberately unused since the anchor fix: every date the
    // clerk proposes derives from the store alone, so the sweep is a pure
    // function of the box and identical in every process. The clock stays
    // in the signature for future proposers that legitimately need one.
    // The automation switch (P19h): a vault cell on the assist entity gates
    // every proposal — off means SILENCE, in every process, by consent that
    // travels with the box.
    if !assist_enabled(store) {
        return Vec::new();
    }
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
    // Whole-store, once per sweep: exact-identity duplicate merges.
    propose_dedupe(store, &mut proposals);

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

// MARK: - grouping + severable group-accept (P16b)

/// What makes two proposals "alike" (constitution 1.3): the same proposer and
/// the same kind of change — a merge, a promotion, or a specific property.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Facet {
    Merge,
    Promote,
    Property(Id),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct GroupKey {
    pub author: String,
    pub facet: Facet,
}

/// A group of alike proposals (indices into the slice `groups` was given).
#[derive(Debug, Clone)]
pub struct Group {
    pub key: GroupKey,
    pub members: Vec<usize>,
}

/// The group a proposal belongs to — a pure function (the inbox is re-derived by
/// every process, so the group is derived, never stored).
pub fn group_key(proposal: &Proposal) -> GroupKey {
    let author = match &proposal.author {
        Author::Proposer(name) => name.clone(),
        _ => "user".into(),
    };
    let facet = if proposal.commands.iter().any(|c| matches!(c, Command::Redirect { .. })) {
        Facet::Merge
    } else if proposal
        .commands
        .iter()
        .any(|c| matches!(c, Command::AddCell { cell, .. } if cell.property == props::TYPE))
    {
        Facet::Promote
    } else if let Some(Command::AddCell { cell, .. }) = proposal.commands.first() {
        Facet::Property(cell.property)
    } else {
        Facet::Property(NONE)
    };
    GroupKey { author, facet }
}

/// Bucket proposals into groups, in first-seen order (deterministic because the
/// sweep yields proposals in entity-id order).
pub fn groups(proposals: &[Proposal]) -> Vec<Group> {
    let mut order: Vec<GroupKey> = Vec::new();
    let mut members: HashMap<GroupKey, Vec<usize>> = HashMap::new();
    for (i, proposal) in proposals.iter().enumerate() {
        let key = group_key(proposal);
        if !members.contains_key(&key) {
            order.push(key.clone());
        }
        members.entry(key).or_default().push(i);
    }
    order
        .into_iter()
        .map(|key| {
            let members = members.remove(&key).unwrap_or_default();
            Group { key, members }
        })
        .collect()
}

/// Accept several pending proposals (by index) as ONE transaction, one undo
/// (constitution 1.3). Concatenates their commands, commits once under the first
/// member's author, then retracts each from the pending queue. Commit-then-retract
/// is crash-safe *because clerk proposals are re-derivable* — a crash after the
/// commit leaves stale pending whose preconditions the next sweep no longer finds,
/// so nothing is re-derived. (This safety does NOT transfer to a future Agent's
/// non-re-derivable draft.) Composed entirely from public Session methods.
pub fn accept_group(session: &mut Session, selected: &[usize]) -> Result<u64, PersistError> {
    let (commands, author) = {
        let pending = session.store().pending();
        let author = selected
            .first()
            .and_then(|&i| pending.get(i))
            .map(|p| p.author.clone())
            .unwrap_or(Author::User);
        let mut commands = Vec::new();
        for &i in selected {
            if let Some(p) = pending.get(i) {
                commands.extend(p.commands.clone());
            }
        }
        (commands, author)
    };
    if commands.is_empty() {
        return Ok(0);
    }
    let seq = session.commit(commands, "accept group".to_string(), author)?;
    // Descending, so the indices stay valid as members are drained.
    let mut ordered = selected.to_vec();
    ordered.sort_unstable_by(|a, b| b.cmp(a));
    ordered.dedup();
    for i in ordered {
        let _ = session.retract(i);
    }
    Ok(seq)
}

/// The durable meaning of a refusal: (proposer, entity, property). A single
/// AddCell keys on its cell; a multi-cell proposal on ONE entity (promotion)
/// keys on the first cell's property — so declining it never re-asks.
fn decline_key(proposal: &Proposal) -> Option<(&str, Id, Id)> {
    let Author::Proposer(name) = &proposal.author else {
        return None;
    };
    // A merge (contains a Redirect) keys on (survivor, first loser) — stable even
    // if the copied cells drift between the decline and the next sweep.
    if let Some(Command::Redirect { entity, to, .. }) =
        proposal.commands.iter().find(|c| matches!(c, Command::Redirect { .. }))
    {
        return Some((name.as_str(), *to, *entity));
    }
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
/// One name the clerk can spot in someone's writing.
struct Named {
    id: Id,
    /// As written, for the label the user reads.
    name: String,
    /// Lowercased ONCE per sweep. This used to be recomputed inside the
    /// per-entity loop — an allocation per entity per name.
    lowered: String,
}

/// Every name in the box, plus a word index into it.
///
/// The index is what stops the mentions proposer being quadratic. Without
/// it, each entity that has content walks EVERY name in the box; with it,
/// each entity looks up only the names whose first word it actually
/// contains. Measured 2026-08-19 on notes with bodies: the sweep cost
/// 8.9 ms at 250 notes, 35.4 at 500 and 141.7 at 1,000 — four times the
/// work for twice the box.
struct Gazetteer {
    names: Vec<Named>,
    /// First whole word of each lowered name → its indices in `names`.
    /// A name can only be found in a text that contains its first word as
    /// a word, because `contains_word` demands a boundary on both sides —
    /// so this prefilter can never hide a match.
    by_first_word: HashMap<String, Vec<usize>>,
    /// Names with no alphanumeric run at all. Vanishingly rare; checked
    /// against every entity so the prefilter stays a prefilter.
    wordless: Vec<usize>,
}

/// The alphanumeric runs of a string, lowercased input assumed.
fn words(text: &str) -> impl Iterator<Item = &str> {
    text.split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty())
}

fn gazetteer(store: &Store) -> Gazetteer {
    let named = Query {
        constraints: vec![Constraint {
            property: props::NAME,
            op: Op::Exists,
        }],
        ..Query::default()
    };
    let names: Vec<Named> = run(store, &named)
        .into_iter()
        .filter_map(|id| {
            let entity = store.get(id)?;
            match entity.get(props::NAME) {
                Some(Value::Text(name)) if name.chars().count() >= 3 => Some(Named {
                    id,
                    lowered: name.to_lowercase(),
                    name: name.clone(),
                }),
                _ => None,
            }
        })
        .collect();

    let mut by_first_word: HashMap<String, Vec<usize>> = HashMap::new();
    let mut wordless = Vec::new();
    for (at, named) in names.iter().enumerate() {
        match words(&named.lowered).next() {
            Some(first) => by_first_word.entry(first.to_string()).or_default().push(at),
            None => wordless.push(at),
        }
    }
    Gazetteer { names, by_first_word, wordless }
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
    gazetteer: &Gazetteer,
    proposals: &mut Vec<Proposal>,
) {
    let lower = text.to_lowercase();

    // Look up only the names this text could possibly contain, then walk
    // them IN GAZETTEER ORDER. The order matters as much as the speed:
    // the inbox is re-derived by every process and "accept 2" must mean
    // the proposal the user just read, so a BTreeSet of indices restores
    // exactly the order the old whole-gazetteer loop produced.
    let mut candidates: BTreeSet<usize> = gazetteer.wordless.iter().copied().collect();
    let mut seen: HashSet<&str> = HashSet::new();
    for word in words(&lower) {
        if !seen.insert(word) {
            continue;
        }
        if let Some(at) = gazetteer.by_first_word.get(word) {
            candidates.extend(at.iter().copied());
        }
    }

    for at in candidates {
        let named = &gazetteer.names[at];
        if named.id == entity.id {
            continue;
        }
        if entity.has(vocabulary.related, &Value::Reference(named.id)) {
            continue;
        }
        if !contains_word(&lower, &named.lowered) {
            continue;
        }
        proposals.push(Proposal {
            commands: vec![Command::AddCell {
                entity: entity.id,
                cell: Cell {
                    property: vocabulary.related,
                    value: Value::Reference(named.id),
                },
            }],
            label: format!("relate to {}", named.name),
            author: Author::Proposer("mentions".into()),
            reason: format!("mentions \"{}\" → relate?", named.name),
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

/// Exact-identity duplicate merges (P16). Buckets non-trashed/non-working
/// entities by an EXACT key — url, else external-id, else (type, casefold name)
/// — and for each bucket ≥2 emits ONE severable merge into the oldest (survivor).
/// Never fuzzy ("Anna" ≠ "Annabel" — near-matches are the LLM audit tier); never
/// copies `tier`/`private`; each entity is in exactly one bucket, so pairs are
/// vertex-disjoint (a star into the survivor, no chains).
fn propose_dedupe(store: &Store, proposals: &mut Vec<Proposal>) {
    let protected: Vec<Id> = [property_id(store, "tier"), Some(props::PRIVATE)]
        .into_iter()
        .flatten()
        .collect();
    let url_prop = property_id(store, "url");

    let mut ents: Vec<&Entity> = store
        .user_entities()
        .collect();
    ents.sort_by_key(|e| e.id);

    // BTreeMap for a deterministic bucket order; within a bucket the ids stay in
    // ascending (push) order, so ids[0] is the oldest survivor.
    let mut buckets: BTreeMap<String, Vec<Id>> = BTreeMap::new();
    for e in &ents {
        if let Some(key) = identity_key(e, url_prop) {
            buckets.entry(key).or_default().push(e.id);
        }
    }

    for ids in buckets.into_values() {
        if ids.len() < 2 {
            continue;
        }
        let survivor = ids[0];
        let Some(surv) = store.get(survivor) else {
            continue;
        };
        let mut commands = Vec::new();
        let mut planned: Vec<Cell> = Vec::new();
        for &loser_id in &ids[1..] {
            let Some(loser) = store.get(loser_id) else {
                continue;
            };
            // Copy every loser cell the survivor lacks — except the protected
            // value-judgments and already-planned duplicates (mirrors Store::merge).
            for cell in &loser.cells {
                if protected.contains(&cell.property)
                    || surv.has(cell.property, &cell.value)
                    || planned.iter().any(|c| c == cell)
                {
                    continue;
                }
                planned.push(cell.clone());
                commands.push(Command::AddCell { entity: survivor, cell: cell.clone() });
            }
            commands.push(Command::Trash { entity: loser_id });
            commands.push(Command::Redirect { entity: loser_id, to: survivor, before: NONE });
        }
        let losers = ids.len() - 1;
        proposals.push(Proposal {
            commands,
            label: format!(
                "merge {losers} duplicate{} into #{survivor}",
                if losers == 1 { "" } else { "s" }
            ),
            author: Author::Proposer("dedupe".into()),
            reason: format!("exact duplicate → merge into #{survivor}?"),
        });
    }
}

/// An entity's EXACT identity for dedupe, or None (no identity → never merged).
fn identity_key(entity: &Entity, url_prop: Option<Id>) -> Option<String> {
    if let Some(url) = url_prop {
        if let Some(Value::Text(u)) = entity.get(url) {
            return Some(format!("url\u{1}{}", u.to_lowercase()));
        }
    }
    if let Some(Value::Text(ext)) = entity.get(props::EXTERNAL_ID) {
        return Some(format!("ext\u{1}{ext}"));
    }
    if let Some(Value::Text(name)) = entity.get(props::NAME) {
        let ty = entity
            .all(props::TYPE)
            .find_map(|v| match v {
                Value::Reference(t) => Some(*t),
                _ => None,
            })
            .unwrap_or(NONE);
        return Some(format!("name\u{1}{ty}\u{1}{}", name.to_lowercase()));
    }
    None
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
