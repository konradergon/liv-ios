//! The sweep: what the clerk would suggest, read off the box.
//!
//! **The queue is in the engine; the reading is here.** `engine/src/clerk.rs`
//! holds accept, decline and the refusal set — the mechanics of consent.
//! This holds the heuristics: dates in English, a closed lexicon of
//! priority words, what counts as a mention. Those are product, not
//! storage, and the engine stays free of them so that the box does not
//! have opinions about English.
//!
//! **The sweep is a pure function of the box.** It reads, writes nothing,
//! and returns proposals — the only thing a proposer can express. Nothing
//! is stored: the same box sweeps to the same list in every process, which
//! is what lets a refusal be a fingerprint rather than a remembered
//! object, and what makes "accept the second one" mean the proposal the
//! user just read.
//!
//! ## What `core/` needed and this does not
//!
//! `core/`'s sweep opens with a `Vocabulary::find` that can return `None`
//! — a box that predates the starter library has no `due` property, so it
//! gets no proposals at all, and four of the six proposers carry an
//! `Option<Id>` they must check before speaking. None of that survives:
//! the engine compiles its furniture in, so `due`, `related`, `priority`,
//! `status`, `area`, the task kind and the todo option are simply there.
//! That is the whole of what "furniture is a floor" buys at this layer.
//!
//! ## What is NOT here, and why
//!
//! **`propose_dedupe` is blocked**, and not on effort. Its merge is three
//! commands per loser: copy the cells, trash it, and REDIRECT it — so that
//! everything already pointing at the loser resolves to the survivor
//! instead. `op-format.md` promises redirect as *"`SetCell` on a reserved
//! property"*, and the model never declared one. Building the merge
//! without it would trash a duplicate and silently orphan every reference
//! to it, which is worse than not offering the merge. What it needs is a
//! `prop::REDIRECT` and every read resolving through it — engine work, and
//! a subsystem rather than a patch.

use std::collections::{BTreeSet, HashMap, HashSet};

use crate::words::{contains_word, words};

use liv_engine::{
    civil_from_days, days_from_civil, kind, prop, rich, status, Engine, EntityId, LogError, Op,
    Proposal, Value,
};

/// The consent gate. **Absent or true is ON; only an explicit `false`
/// silences the clerk** — an older box that never set it is not a box
/// that said no.
///
/// `core/` finds this by hunting for a working entity named "assist" and
/// taking whatever bool cell it carries. The engine has a compiled-in
/// property for it, so the question is asked of the box rather than of a
/// naming convention.
pub fn assist_enabled(e: &Engine) -> Result<bool, LogError> {
    for id in e.with_value(prop::AUTOMATION, &Value::Bool(false))? {
        if !e.is_trashed(id)? {
            return Ok(false);
        }
    }
    Ok(true)
}

/// Everything the clerk would suggest about this box, in a stable order.
///
/// **Deterministic, or triage lies.** The inbox is re-derived by every
/// process, so "accept the second one" has to mean the proposal the user
/// just read. Entities by id — which for a v7 id is creation order — and
/// within an entity: dates, then mentions, then the area those mentions
/// imply, then priority, then promotion.
///
/// Already-declined proposals are dropped here rather than by the caller,
/// because a refusal is what makes the queue shrink as the user works.
pub fn sweep(e: &Engine) -> Result<Vec<Proposal>, LogError> {
    if !assist_enabled(e)? {
        return Ok(Vec::new());
    }
    let gaz = gazetteer(e)?;

    let mut out = Vec::new();
    let mut ids = e.all_entities()?;
    ids.sort();
    for id in ids {
        about(e, id, &gaz, &mut out)?;
    }
    keepable(e, out)
}

/// What the clerk would suggest about ONE thing.
///
/// **Identical to the entry `sweep` would produce for it**, which is the
/// whole point: accepting a suggestion re-derives it from the box to check
/// the box still makes it, and re-deriving the WHOLE box to find one
/// entity's proposal cost 120 ms in a 500-note box — every tap in the
/// inbox re-reading everything. The guarantee is unchanged (the proposal
/// is recomputed, matched by fingerprint, and gone if the box no longer
/// makes it); only the reading is narrowed to the thing it is about.
pub fn sweep_one(e: &Engine, id: EntityId) -> Result<Vec<Proposal>, LogError> {
    if !assist_enabled(e)? {
        return Ok(Vec::new());
    }
    let mut out = Vec::new();
    about(e, id, &gazetteer(e)?, &mut out)?;
    keepable(e, out)
}

/// One entity's proposals, in the order the inbox reads them.
fn about(
    e: &Engine,
    id: EntityId,
    gaz: &Gazetteer,
    out: &mut Vec<Proposal>,
) -> Result<(), LogError> {
    if e.is_trashed(id)? || working(e, id)? {
        return Ok(());
    }
    let Some(spans) = body(e, id)? else { return Ok(()) };
    let text = rich::plain(&spans);
    if text.trim().is_empty() {
        return Ok(());
    }

    // **"Tomorrow" means the day after the THOUGHT**, not the day after
    // the sweep. Relative words resolve against the thing's own creation
    // day, which also makes the proposal identical across sweeps — what
    // the inbox shows is what accepting it commits. A proposal that
    // drifts with the clock is a lie waiting for midnight.
    //
    // The engine needs no `created` cell for this: a v7 id carries its
    // own millisecond, so everything has an anchor and the "no creation
    // date, no relative guesses" branch `core/` needs has nothing to
    // guard.
    let anchor = day_of_id(id);

    dates(e, id, &text, anchor, out)?;
    // The names this text contains, found ONCE — both the mentions
    // proposer and the area proposer read them.
    let mentioned = mentions_in(&text, id, gaz);
    mentions(e, id, &mentioned, gaz, out)?;
    area(e, id, &mentioned, gaz, out)?;
    priority(e, id, &text, out)?;
    promotion(e, id, &spans, out)?;
    Ok(())
}

/// The two filters every sweep ends with: what the clerk is allowed to
/// say, and what it has already been told not to say again.
///
/// The refusals come back in ONE scan rather than a read per proposal —
/// a sweep asks about every draft it found, so a point read each is the
/// N+1 that standing rule 2 exists to catch.
fn keepable(e: &Engine, mut found: Vec<Proposal>) -> Result<Vec<Proposal>, LogError> {
    found.retain(permitted);
    if found.is_empty() {
        return Ok(found);
    }
    let refused = e.refusals()?;
    found.retain(|p| match p.ops.first() {
        Some(op) => !refused.contains(&(op.entity(), liv_engine::print_text(p.fingerprint()))),
        None => true,
    });
    Ok(found)
}

/// **The clerk never touches a value judgment** (catalog a13).
///
/// A hard invariant rather than a convention each proposer remembers, so
/// a future proposer cannot smuggle one in — and a FUNCTION rather than a
/// closure inside `sweep`, because an invariant about proposals nobody
/// makes yet cannot be tested through proposals. The first version of
/// this was a `retain` in the sweep, and deleting it changed no test:
/// none of the five proposers sets `private`, so the guard was real and
/// its test was not.
pub fn permitted(p: &Proposal) -> bool {
    !p.ops.iter().any(|op| {
        matches!(op, Op::SetCell { prop, .. } | Op::AddToSet { prop, .. } if *prop == prop::PRIVATE)
    })
}

// ---- the proposers -----------------------------------------------------

/// "friday", "today", "tomorrow", "2026-07-10" — the first date wins.
///
/// Only for something with no due yet: **the clerk suggests, never
/// competes.** Every proposer below repeats that check, and it is the
/// whole difference between an assistant and an autocorrect.
fn dates(
    e: &Engine,
    id: EntityId,
    text: &str,
    anchor: i32,
    out: &mut Vec<Proposal>,
) -> Result<(), LogError> {
    if e.one(id, prop::DUE)?.is_some() {
        return Ok(());
    }
    let Some((word, day)) = first_date(text, anchor) else { return Ok(()) };
    out.push(Proposal {
        ops: vec![Op::SetCell {
            entity: id,
            prop: prop::DUE,
            value: Value::Date(liv_engine::DateSpec::Day(day)),
            replaces: vec![],
        }],
        proposer: "dates".into(),
        reason: format!("contains \"{word}\" → due {}?", show_day(day)),
    });
    Ok(())
}

/// A known name in the text becomes a proposed relation — once.
fn mentions(
    e: &Engine,
    id: EntityId,
    mentioned: &[usize],
    gaz: &Gazetteer,
    out: &mut Vec<Proposal>,
) -> Result<(), LogError> {
    let already: HashSet<EntityId> = e
        .cell(id, prop::RELATED)?
        .into_iter()
        .filter_map(|(_, v)| match v {
            Value::Ref(t) => Some(t),
            _ => None,
        })
        .collect();
    for &at in mentioned {
        let named = &gaz.names[at];
        if already.contains(&named.id) {
            continue;
        }
        out.push(Proposal {
            ops: vec![Op::AddToSet {
                entity: id,
                prop: prop::RELATED,
                value: Value::Ref(named.id),
            }],
            proposer: "mentions".into(),
            reason: format!("mentions \"{}\" → relate?", named.name),
        });
    }
    Ok(())
}

/// **Where it goes, read off what it mentions.**
///
/// A thought about Sam belongs where Sam is filed. If the names this text
/// contains are all filed under ONE area, propose it; two areas is a coin
/// flip, and the clerk does not flip coins — it stays quiet and lets the
/// mentions speak. A mention filed nowhere says nothing.
///
/// `core/` has a branch here for a box whose `area` is still a TEXT cell
/// rather than a select, and copies the cell "as found" so the proposal
/// writes back whatever kind the box keeps. The engine's `area` is
/// `RefTo(kind::AREA)` and cannot be anything else, so that branch has
/// nothing to be about.
fn area(
    e: &Engine,
    id: EntityId,
    mentioned: &[usize],
    gaz: &Gazetteer,
    out: &mut Vec<Proposal>,
) -> Result<(), LogError> {
    if e.one(id, prop::AREA)?.is_some() {
        return Ok(());
    }
    let mut found: Option<(EntityId, usize)> = None;
    for &at in mentioned {
        let Some(Value::Ref(filed)) = e.one(gaz.names[at].id, prop::AREA)? else { continue };
        match found {
            None => found = Some((filed, at)),
            Some((first, _)) if first == filed => {}
            // Two areas. Say nothing.
            Some(_) => return Ok(()),
        }
    }
    let Some((filed, at)) = found else { return Ok(()) };
    let Some(name) = e.name(filed)?.or_else(|| liv_engine::model::label(filed).map(str::to_owned)) else {
        return Ok(());
    };
    out.push(Proposal {
        ops: vec![Op::SetCell {
            entity: id,
            prop: prop::AREA,
            value: Value::Ref(filed),
            replaces: vec![],
        }],
        proposer: "area".into(),
        reason: format!("mentions \"{}\" → {name}?", gaz.names[at].name),
    });
    Ok(())
}

/// A CLOSED priority-word lexicon: the first trigger wins, and only when
/// it names a real option. **Never an invented value** — if the box has no
/// option by that name the proposer stays quiet rather than mint one,
/// because minting vocabulary is a decision and this is a suggestion.
fn priority(
    e: &Engine,
    id: EntityId,
    text: &str,
    out: &mut Vec<Proposal>,
) -> Result<(), LogError> {
    if e.one(id, prop::PRIORITY)?.is_some() {
        return Ok(());
    }
    let lower = text.to_lowercase();
    let want = if lower.contains("urgent") || lower.contains("asap") || text.contains("!!!") {
        "high"
    } else if lower.contains("low priority") || lower.contains("whenever") {
        "low"
    } else {
        return Ok(());
    };
    let Some(option) = option_named(e, prop::PRIORITY, want)? else { return Ok(()) };
    out.push(Proposal {
        ops: vec![Op::SetCell {
            entity: id,
            prop: prop::PRIORITY,
            value: Value::Ref(option),
            replaces: vec![],
        }],
        proposer: "priority".into(),
        reason: format!("a priority word → priority {want}?"),
    });
    Ok(())
}

/// An untyped capture whose body opens with a checkbox is a task waiting
/// for its kind. Promotes the scrap IN PLACE — pulling a line out of the
/// middle of a note is a different door, because that needs a new id.
fn promotion(
    e: &Engine,
    id: EntityId,
    spans: &[rich::Span],
    out: &mut Vec<Proposal>,
) -> Result<(), LogError> {
    if e.one(id, prop::KIND)?.is_some() {
        return Ok(());
    }
    let first = spans.iter().find_map(|s| match s {
        rich::Span::Break(b) => Some(b),
        _ => None,
    });
    if !matches!(first, Some(rich::Block::Task { .. })) {
        return Ok(());
    }
    out.push(Proposal {
        ops: vec![
            Op::SetCell { entity: id, prop: prop::KIND, value: Value::Ref(kind::TASK), replaces: vec![] },
            Op::SetCell {
                entity: id,
                prop: prop::STATUS,
                value: Value::Ref(status::TODO),
                replaces: vec![],
            },
        ],
        proposer: "promotion".into(),
        reason: "starts with a checkbox → make it a task?".into(),
    });
    Ok(())
}

// ---- the gazetteer -----------------------------------------------------

/// One name the clerk can spot in someone's writing.
struct Named {
    id: EntityId,
    /// As written, for the sentence the user reads.
    name: String,
    /// Lowercased ONCE per sweep rather than once per entity per name.
    lowered: String,
}

/// Every name in the box, plus a word index into it.
///
/// **The index is what stops the mentions proposer being quadratic.**
/// Without it every thing with a body walks every name in the box;
/// `core/` measured that at 8.9 ms for 250 notes, 35.4 for 500 and 141.7
/// for 1,000 — four times the work for twice the box.
struct Gazetteer {
    names: Vec<Named>,
    /// First whole word of each lowered name → its places in `names`. A
    /// name can only be found in a text containing its first word AS a
    /// word, because `contains_word` demands a boundary on both sides —
    /// so this prefilter can never hide a match.
    by_first_word: HashMap<String, Vec<usize>>,
    /// Names with no alphanumeric run at all. Vanishingly rare, and
    /// checked against everything so the prefilter stays a prefilter.
    wordless: Vec<usize>,
}

/// **Two queries, not two per entity.** This used to walk `all_entities`
/// asking `is_trashed` and `name` of each, which is an N+1 of exactly the
/// shape standing rule 2 exists to catch — and it measured 36 ms at a
/// thousand entities, most of the cost of accepting one suggestion.
///
/// `one_each` keeps `one`'s rule about contention, so a contended name is
/// still not a name the clerk will match on. The order is the same: the
/// scan comes back in entity order, which for a v7 id is creation order.
fn gazetteer(e: &Engine) -> Result<Gazetteer, LogError> {
    let trashed: HashSet<EntityId> =
        e.with_value(prop::TRASHED, &Value::Bool(true))?.into_iter().collect();
    let mut names = Vec::new();
    for (id, value) in e.one_each(prop::NAME)? {
        if trashed.contains(&id) {
            continue;
        }
        // Three characters. Below that a "name" matches half the box —
        // and the shortest thing anyone actually calls something is three.
        match value {
            Value::Text(name) if name.chars().count() >= 3 => {
                names.push(Named { id, lowered: name.to_lowercase(), name })
            }
            _ => {}
        }
    }

    let mut by_first_word: HashMap<String, Vec<usize>> = HashMap::new();
    let mut wordless = Vec::new();
    for (at, named) in names.iter().enumerate() {
        match words(&named.lowered).next() {
            Some(first) => by_first_word.entry(first.to_owned()).or_default().push(at),
            None => wordless.push(at),
        }
    }
    Ok(Gazetteer { names, by_first_word, wordless })
}

/// Every known name this text contains, in GAZETTEER order, the thing's
/// own name excluded.
///
/// The order matters as much as the speed: a `BTreeSet` of places restores
/// exactly the order a whole-gazetteer walk would have produced, so the
/// inbox reads the same however the prefilter narrowed it.
fn mentions_in(text: &str, own: EntityId, gaz: &Gazetteer) -> Vec<usize> {
    let lower = text.to_lowercase();
    let mut candidates: BTreeSet<usize> = gaz.wordless.iter().copied().collect();
    let mut seen: HashSet<&str> = HashSet::new();
    for word in words(&lower) {
        if !seen.insert(word) {
            continue;
        }
        if let Some(at) = gaz.by_first_word.get(word) {
            candidates.extend(at.iter().copied());
        }
    }
    candidates
        .into_iter()
        .filter(|&at| gaz.names[at].id != own && contains_word(&lower, &gaz.names[at].lowered))
        .collect()
}

// ---- dates in words ----------------------------------------------------

const WEEKDAYS: [&str; 7] =
    ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];

/// Scan the words; the first that names a day wins. Relative words resolve
/// against `anchor` — the day the text was written.
fn first_date(text: &str, anchor: i32) -> Option<(String, i32)> {
    for raw in text.split_whitespace() {
        let word: String = raw
            .trim_matches(|c: char| !c.is_ascii_alphanumeric() && c != '-')
            .to_lowercase();
        if word.is_empty() {
            continue;
        }
        if word == "today" {
            return Some((word, anchor));
        }
        if word == "tomorrow" {
            return Some((word, anchor + 1));
        }
        if let Some(target) = WEEKDAYS.iter().position(|w| *w == word) {
            // **The NEXT such day, counting from the anchor**, with the
            // anchor's own weekday meaning today rather than a week away.
            // Day 0 of the epoch was a Thursday, which is where the 3
            // comes from.
            let anchor_weekday = (anchor + 3).rem_euclid(7) as usize;
            let delta = (target + 7 - anchor_weekday) % 7;
            return Some((word, anchor + delta as i32));
        }
        if let Some(day) = iso_day(&word) {
            return Some((word, day));
        }
    }
    None
}

/// `yyyy-mm-dd`, validated just enough not to be a lie. Digits only in the
/// digit positions: a bare `parse()` accepts "-234-01-01", and a negative
/// year is not a date anybody meant.
fn iso_day(word: &str) -> Option<i32> {
    let b = word.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let digits = |r: std::ops::Range<usize>| b[r].iter().all(u8::is_ascii_digit);
    if !digits(0..4) || !digits(5..7) || !digits(8..10) {
        return None;
    }
    let year: i32 = word[0..4].parse().ok()?;
    let month: u32 = word[5..7].parse().ok()?;
    let day: u32 = word[8..10].parse().ok()?;
    if !(1..=12).contains(&month) || day == 0 || day > days_in_month(year, month) {
        return None;
    }
    Some(days_from_civil(year, month, day))
}

fn days_in_month(year: i32, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 => 29,
        2 => 28,
        _ => 0,
    }
}

/// The day a reason names, for the sentence the user reads.
fn show_day(day: i32) -> String {
    let (y, m, d) = civil_from_days(day);
    format!("{y:04}-{m:02}-{d:02}")
}

// ---- reading the box ---------------------------------------------------

fn working(e: &Engine, id: EntityId) -> Result<bool, LogError> {
    Ok(matches!(e.one(id, prop::WORKING)?, Some(Value::Bool(true))))
}

fn body(e: &Engine, id: EntityId) -> Result<Option<Vec<rich::Span>>, LogError> {
    Ok(match e.one(id, prop::BODY)? {
        Some(Value::Rich(spans)) if !spans.is_empty() => Some(spans),
        _ => None,
    })
}

/// The day a v7 id was minted. Every engine id carries its own
/// millisecond, so nothing needs a `created` cell to have an anchor.
fn day_of_id(id: EntityId) -> i32 {
    crate::day_of(id.millis() as i64)
}

/// An option of `property` with that name, compiled-in or minted.
fn option_named(
    e: &Engine,
    property: EntityId,
    want: &str,
) -> Result<Option<EntityId>, LogError> {
    for (_, v) in e.cell(property, prop::OPTIONS)? {
        let Value::Ref(option) = v else { continue };
        let name = e
            .name(option)?
            .or_else(|| liv_engine::model::label(option).map(str::to_owned));
        if name.is_some_and(|n| n.eq_ignore_ascii_case(want)) {
            return Ok(Some(option));
        }
    }
    Ok(None)
}
