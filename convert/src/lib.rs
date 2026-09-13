//! One way, once: a `core/` box becomes an engine box.
//!
//! **Why this exists before any Swift moves.** Stage 4 repoints the shell
//! one surface at a time, and a repointed surface reads the engine's box.
//! Without this, the first surface to move goes blank — not because it is
//! wrong, but because the data is in the other file. So the converter is
//! the actual first step of stage 4, and it is pure Rust, which means it
//! can be finished and proven here.
//!
//! ## What it promises
//!
//! * **The original is never touched.** It reads the log and writes a new
//!   database beside it. If the result is wrong, delete it and run again.
//! * **It is deterministic.** The same box converts to the same bytes,
//!   because every engine id is derived from the core id and its creation
//!   time rather than minted. That is what makes `convert twice, get the
//!   same digest` a test rather than a hope.
//! * **It counts what it could not carry** rather than dropping it
//!   quietly. `Report` is the answer to "did this work", and a caller that
//!   ignores it deserves what it gets.
//!
//! ## What it cannot carry, and says so
//!
//! * **Rich text becomes plain text.** The engine has no blocks yet
//!   (`core-plan.md` Phase 8), so a body's structure flattens to its text.
//!   Nothing is lost that a re-parse cannot rebuild, but it is a change.
//! * **A file reference becomes nothing.** `core`'s `FileRef` carries a
//!   device-local path; the engine's `Blob` carries a content hash, and
//!   there is no blob store yet (Phase 11). Inventing a hash would be
//!   worse than counting the loss.
//! * **A type the engine has no kind for is refused**, and the entity
//!   keeps every other cell. Kinds are ours and do not grow from a box
//!   (`what-liv-is-for.md`), so a box that has invented one is telling us
//!   something we should read, not something to silently absorb.

use std::collections::HashMap;

use liv_core::{props, Session, Store, Value as CoreValue};
use liv_engine::{
    kind, model, prop, Author, DateSpec, Engine, EntityId, Op, Value as EngineValue,
};

// The date arithmetic moved to `liv-engine` on 2026-09-13: the engine
// defines what a `DateSpec::Day` is, so reading one back is reading its
// own format — and the surfaces need it too, for a made name. Re-exported
// here because this crate's callers already ask it for them.
pub use liv_engine::{civil_from_days, days_from_civil, split_civil};

/// What the conversion carried, and what it could not.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Report {
    pub entities: usize,
    pub cells: usize,
    /// Bodies whose structure was flattened to text.
    pub flattened: usize,
    /// File references with nowhere to point.
    pub files_dropped: usize,
    /// Cells whose property the engine does not know and the box did not
    /// declare — carried anyway, with no opinion, exactly as the engine
    /// promises for an undeclared property.
    pub undeclared: usize,
    /// Type names with no kind. Each one is named, because a list of
    /// counts is not actionable.
    pub unknown_kinds: Vec<String>,
    /// Core entities that were NOT converted because the engine already
    /// has them compiled in: property definitions, types, and the areas
    /// and statuses Liv ships with. Every reference to one lands on the
    /// frozen id.
    pub resolved: usize,
    /// Options the six and the three do not cover — a seventh area, a
    /// fourth status, a select's own choices. Minted as entities, which is
    /// what the 2026-08-29 amendment allows.
    pub minted_vocabulary: usize,
}

impl Report {
    /// Nothing surprising happened.
    pub fn clean(&self) -> bool {
        self.files_dropped == 0 && self.unknown_kinds.is_empty()
    }
}

/// Convert the box at `from` into a new engine box at `to`.
///
/// `to` must not already exist — this refuses rather than merging, because
/// a converter that runs twice into the same file is a converter that can
/// double a box, and "run it again" is the first thing anyone tries.
pub fn convert(
    from: &std::path::Path,
    to: &std::path::Path,
) -> Result<Report, Box<dyn std::error::Error>> {
    if to.exists() {
        return Err(format!("{} already exists", to.display()).into());
    }
    let session = Session::open(from)?;
    let mut engine = Engine::open_local(to)?;
    let report = pour(session.store(), &mut engine)?;
    Ok(report)
}

/// The conversion itself, against an open store and an open engine — so a
/// test can use an in-memory engine and never touch a disk.
pub fn pour(
    store: &Store,
    engine: &mut Engine,
) -> Result<Report, Box<dyn std::error::Error>> {
    let mut report = Report::default();
    let names = name_index(store);
    let props = property_map(store, &names);
    let kinds = kind_map(store, &names);
    let options = option_map(store, &names, &props);

    // **What the box already has, we already have.** A core box carries
    // its schema as entities — 51 property definitions, a type per kind,
    // an option per area and status. Copying those in would give a
    // converted box a second "due" and a second "Work" sitting beside the
    // compiled-in ones in every picker, which is exactly the drift the
    // furniture exists to prevent. So they are RESOLVED, not converted:
    // skipped as entities, and every reference to one lands on the frozen
    // id instead.
    let mut ids: HashMap<liv_core::Id, EntityId> = HashMap::new();
    let mut skip: std::collections::HashSet<liv_core::Id> = Default::default();
    let mut ordered: Vec<&liv_core::Entity> = store.entities().collect();
    ordered.sort_by_key(|e| e.id);
    for e in &ordered {
        if let Some(frozen) = props.get(&e.id) {
            ids.insert(e.id, *frozen);
            skip.insert(e.id);
            report.resolved += 1;
            continue;
        }
        if let Some(frozen) = kinds.get(&e.id) {
            ids.insert(e.id, *frozen);
            skip.insert(e.id);
            report.resolved += 1;
            continue;
        }
        if let Some(Frozen::Is(frozen)) = options.get(&e.id) {
            ids.insert(e.id, *frozen);
            skip.insert(e.id);
            report.resolved += 1;
            continue;
        }
        ids.insert(e.id, engine_id(e.id, created_ms(e)));
    }

    for e in &ordered {
        if skip.contains(&e.id) {
            continue;
        }
        let id = ids[&e.id];

        // **Registers are collected, not appended.** Every `SetCell` here
        // passes an empty `replaces` — correct, because a converted box
        // has no prior dots to name — but that means two SetCells on one
        // property inside one group leave BOTH values live, and a
        // contended register reads as no value at all (core.md §5).
        //
        // It happened: the converter marks a minted option `working`, and
        // an option that already carried a `working` cell got a second
        // one, went contended, and reappeared in Everything next to the
        // notes. A test caught it. So a register is written once, last
        // value wins, and a set keeps every member.
        let mut registers: Vec<(EntityId, EngineValue)> = Vec::new();
        let mut members: Vec<(EntityId, EngineValue)> = Vec::new();
        let mut put = |prop: EntityId, value: EngineValue| {
            if model::is_many(prop) {
                if !members.iter().any(|(p, v)| *p == prop && *v == value) {
                    members.push((prop, value));
                }
            } else if let Some(slot) = registers.iter_mut().find(|(p, _)| *p == prop) {
                slot.1 = value;
            } else {
                registers.push((prop, value));
            }
        };

        for cell in &e.cells {
            // `created` is not carried: a v7 id holds its own millisecond,
            // and two answers to "when was this made" is one too many.
            if cell.property == props::CREATED {
                continue;
            }
            // `type` becomes `kind`, and only if we have one.
            if cell.property == props::TYPE {
                let CoreValue::Reference(t) = cell.value else { continue };
                match kinds.get(&t) {
                    Some(k) => put(prop::KIND, EngineValue::Ref(*k)),
                    None => {
                        let name = names.get(&t).cloned().unwrap_or_else(|| format!("#{t}"));
                        if !report.unknown_kinds.contains(&name) {
                            report.unknown_kinds.push(name);
                        }
                    }
                }
                continue;
            }

            let Some(target) = props.get(&cell.property).copied().or_else(|| {
                report.undeclared += 1;
                ids.get(&cell.property).copied()
            }) else {
                continue;
            };

            let Some(value) = value(&cell.value, &ids, &names, &mut report) else { continue };
            put(target, value);
            report.cells += 1;
        }

        // A minted option says what it is, so a seventh area is an area
        // and not a loose entity with a name.
        if let Some(Frozen::Mint(k)) = options.get(&e.id) {
            put(prop::KIND, EngineValue::Ref(*k));
            put(prop::WORKING, EngineValue::Bool(true));
            report.minted_vocabulary += 1;
        }

        if e.trashed {
            put(prop::TRASHED, EngineValue::Bool(true));
        }

        let mut ops = vec![Op::CreateEntity { entity: id }];
        for (prop, value) in registers {
            ops.push(Op::SetCell { entity: id, prop, value, replaces: vec![] });
        }
        for (prop, value) in members {
            ops.push(Op::AddToSet { entity: id, prop, value });
        }

        // ONE ENTITY IS ONE GROUP. The core's transactions are not the
        // engine's actions and there is no honest mapping between them —
        // so rather than invent one, the conversion says what it is: a
        // single import action per thing, with `Author::Proposer` naming
        // the converter, which is the vocabulary the format already has
        // for "this did not come from the user's hands".
        engine.commit(
            ops,
            liv_engine::action::CREATE,
            Author::Proposer("convert".into()),
            created_ms(e),
        )?;
        report.entities += 1;
    }

    Ok(report)
}

// ---- the maps ----------------------------------------------------------

fn name_index(store: &Store) -> HashMap<liv_core::Id, String> {
    let mut out = HashMap::new();
    for e in store.entities() {
        if let Some(CoreValue::Text(n)) = e.get(props::NAME) {
            out.insert(e.id, n.clone());
        }
    }
    out
}

/// Core property definition → engine property, by NAME.
///
/// The engine's 55 compiled-in properties were written from a census of a
/// fresh `core/` box, so this matches on the words that box already uses.
/// A property with no match is not an error: it is a field the box
/// declared and the engine will carry without an opinion.
fn property_map(
    store: &Store,
    names: &HashMap<liv_core::Id, String>,
) -> HashMap<liv_core::Id, EntityId> {
    let by_name: HashMap<&str, EntityId> =
        model::PROPS.iter().map(|p| (p.name, p.id)).collect();
    let mut out = HashMap::new();
    // The four the core reserves by constant rather than by name.
    out.insert(props::NAME, prop::NAME);
    out.insert(props::CONTENT, prop::BODY);
    out.insert(props::WORKING, prop::WORKING);
    out.insert(props::PRIVATE, prop::PRIVATE);
    for e in store.entities() {
        if let Some(name) = names.get(&e.id) {
            if let Some(target) = by_name.get(name.as_str()) {
                out.insert(e.id, *target);
            }
        }
    }
    out
}

/// Core OPTION entity → what it is in the engine.
///
/// **An option of `area` IS an area**, and if it is one of the six it is
/// the frozen one — not a copy of it. This is the whole reason the
/// converter has to understand the box rather than copy it: a converted
/// "Work" that is not `area::WORK` is precisely the drift the compiled-in
/// furniture exists to prevent, and it would sit next to the real Work in
/// every picker.
///
/// An option the six do not cover becomes a minted area, which is what
/// the 2026-08-29 amendment allows. An option of `status` gets the same
/// treatment against the three. Anything else is a plain `kind::OPTION`.
fn option_map(
    store: &Store,
    names: &HashMap<liv_core::Id, String>,
    props: &HashMap<liv_core::Id, EntityId>,
) -> HashMap<liv_core::Id, Frozen> {
    let mut out = HashMap::new();
    for e in store.entities() {
        let Some(owner) = props.get(&e.id).copied() else { continue };
        for value in e.all(props::OPTIONS) {
            let CoreValue::Reference(opt) = value else { continue };
            let name = names.get(opt).map(String::as_str).unwrap_or_default();
            let what = if owner == prop::AREA {
                match frozen_area(name) {
                    Some(a) => Frozen::Is(a),
                    None => Frozen::Mint(kind::AREA),
                }
            } else if owner == prop::STATUS {
                match frozen_status(name) {
                    Some(st) => Frozen::Is(st),
                    None => Frozen::Mint(kind::STATUS),
                }
            } else {
                Frozen::Mint(kind::OPTION)
            };
            out.insert(*opt, what);
        }
    }
    out
}

/// Either this already exists compiled in, or it becomes an entity of a
/// kind.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Frozen {
    Is(EntityId),
    Mint(EntityId),
}

fn frozen_area(name: &str) -> Option<EntityId> {
    liv_engine::AREAS.iter().copied().find(|a| eqi(model::label(*a), name))
}

fn frozen_status(name: &str) -> Option<EntityId> {
    liv_engine::STATUSES.iter().copied().find(|s| eqi(model::label(*s), name))
}

/// Does this option name one of ours?
///
/// **Loose on purpose, and only here.** A box writes `todo` and our label
/// is `To do`; a box writes `Family & Friends` and could as easily have
/// `family and friends`. Letters and digits only, folded to lowercase, so
/// the six areas and three statuses in an existing box land on the frozen
/// ids instead of being minted beside them — which is the difference
/// between a converted box that has one Work and one that has two.
///
/// Nothing else in the tree matches names this way. This runs once, over a
/// vocabulary we wrote ourselves, on a path where a miss is visible in the
/// report as a minted option.
fn eqi(label: Option<&str>, name: &str) -> bool {
    fn fold(s: &str) -> String {
        s.chars().filter(|c| c.is_alphanumeric()).flat_map(char::to_lowercase).collect()
    }
    label.map(|l| fold(l) == fold(name)).unwrap_or(false)
}

/// Core type entity → engine kind, by name.
fn kind_map(
    store: &Store,
    names: &HashMap<liv_core::Id, String>,
) -> HashMap<liv_core::Id, EntityId> {
    let mut out = HashMap::new();
    for e in store.entities() {
        let Some(name) = names.get(&e.id) else { continue };
        if let Some(k) = kind_named(name) {
            out.insert(e.id, k);
        }
    }
    out
}

/// The word a box uses for a kind, and ours for it. Lowercased, because a
/// box writes "note" and the model's label is "Note".
pub fn kind_named(name: &str) -> Option<EntityId> {
    Some(match name.to_lowercase().as_str() {
        "note" => kind::NOTE,
        "task" => kind::TASK,
        "event" => kind::EVENT,
        "photo" => kind::PHOTO,
        "person" | "contact" => kind::PERSON,
        "link" => kind::LINK,
        "project" => kind::PROJECT,
        "file" => kind::FILE,
        "list" => kind::LIST,
        "habit" => kind::HABIT,
        "check-in" | "checkin" => kind::CHECKIN,
        "workspace" => kind::WORKSPACE,
        "view" | "saved view" => kind::VIEW,
        "layer" => kind::LAYER,
        "widget" => kind::WIDGET,
        "pin" => kind::PIN,
        "daily-note" | "daily note" => kind::DAILY_NOTE,
        _ => return None,
    })
}

// ---- values ------------------------------------------------------------

fn value(
    v: &CoreValue,
    ids: &HashMap<liv_core::Id, EntityId>,
    names: &HashMap<liv_core::Id, String>,
    report: &mut Report,
) -> Option<EngineValue> {
    Some(match v {
        CoreValue::Text(s) => EngineValue::Text(s.clone()),
        CoreValue::RichText(rt) => {
            report.flattened += 1;
            EngineValue::Text(flatten(rt, names))
        }
        CoreValue::Number(n) if n.is_finite() => EngineValue::Number(*n),
        // A non-finite number has no defined ordering and would make two
        // stores disagree about the same value (op.rs refuses it at the
        // door). The core guards its own seam too, so this is for one
        // that entered another way.
        CoreValue::Number(_) => return None,
        CoreValue::Bool(b) => EngineValue::Bool(*b),
        CoreValue::DateTime(dt) => EngineValue::Date(date(dt)),
        CoreValue::Select(id) | CoreValue::Reference(id) => EngineValue::Ref(*ids.get(id)?),
        CoreValue::File(_) => {
            report.files_dropped += 1;
            return None;
        }
    })
}

/// A packed civil stamp becomes a day or an instant.
///
/// **`date_only` is the whole distinction.** "Due Friday" and "starts
/// 14:00" are different things, and a floating day that shifts when the
/// device changes zone is the most common quiet corruption in a personal
/// app (op.rs). The core says which it is; this keeps it.
///
/// The span `end` does not survive: `DateSpec` has no second endpoint. It
/// is not counted as a loss because nothing in the shipping app writes one
/// — P11 added the format and the surfaces never used it.
fn date(dt: &liv_core::DateTime) -> DateSpec {
    let (y, m, d, hh, mm) = split_civil(dt.civil);
    let day = days_from_civil(y, m, d);
    if dt.date_only {
        DateSpec::Day(day)
    } else {
        DateSpec::Instant {
            ms: day as i64 * 86_400_000 + hh as i64 * 3_600_000 + mm as i64 * 60_000,
            tz: 0,
        }
    }
}

/// Rich text, as its words.
///
/// The engine has no blocks yet (`core-plan.md` Phase 8), so structure
/// flattens. It flattens to MARKDOWN rather than to bare text, because the
/// editor already round-trips markdown — so a body that was a checklist
/// comes back a checklist when blocks land, and `note_tasks` can still see
/// an open box in the meantime.
///
/// `RichText` is a flat span list where `Break(block)` types the paragraph
/// that FOLLOWS it, so this is one left-to-right walk and never a tree.
fn flatten(rt: &liv_core::RichText, names: &HashMap<liv_core::Id, String>) -> String {
    let mut out = String::new();
    for span in &rt.spans {
        match span {
            liv_core::Span::Text(t) => out.push_str(&t.text),
            liv_core::Span::Break(block) => {
                out.push('\n');
                out.push_str(&marker(block));
            }
            // The editor's own token, and it carries a NAME rather than a
            // raw id (`core-decisions.md`). A link to something that is
            // gone keeps its brackets, so the text still reads.
            liv_core::Span::Ref(id) => {
                out.push_str("[[");
                out.push_str(names.get(id).map(String::as_str).unwrap_or("?"));
                out.push_str("]]");
            }
        }
    }
    out
}

/// What a paragraph of this kind starts with in markdown.
fn marker(block: &liv_core::Block) -> String {
    match block {
        liv_core::Block::Body | liv_core::Block::Rule => String::new(),
        liv_core::Block::Heading(level) => format!("{} ", "#".repeat((*level).clamp(1, 6) as usize)),
        liv_core::Block::Quote => "> ".to_owned(),
        liv_core::Block::Bullet { depth } => format!("{}- ", "  ".repeat(*depth as usize)),
        liv_core::Block::Ordered { depth } => format!("{}1. ", "  ".repeat(*depth as usize)),
        liv_core::Block::Task { depth, done } => {
            format!("{}- [{}] ", "  ".repeat(*depth as usize), if *done { 'x' } else { ' ' })
        }
        liv_core::Block::Code { .. } => "    ".to_owned(),
        liv_core::Block::Callout { .. } => "> ".to_owned(),
    }
}

// ---- ids ---------------------------------------------------------------

fn created_ms(e: &liv_core::Entity) -> u64 {
    match e.get(props::CREATED) {
        Some(CoreValue::DateTime(dt)) => {
            let (y, m, d, hh, mm) = split_civil(dt.civil);
            let day = days_from_civil(y, m, d) as i64;
            (day * 86_400_000 + hh as i64 * 3_600_000 + mm as i64 * 60_000).max(0) as u64
        }
        _ => 0,
    }
}

/// A core id and its creation time become one engine id.
///
/// **Derived rather than minted, on purpose.** Minting would make the
/// conversion non-reproducible, and "convert twice, get the same digest"
/// is the cheapest possible proof that it is not doing something
/// different each time. The layout is v7's — 48 bits of millisecond, then
/// the version nibble — so id order is still creation order and the
/// twenty-one sites that sort by id keep meaning what they meant.
///
/// Version 7 also cannot collide with the furniture, which is version 8.
pub fn engine_id(core: liv_core::Id, created_ms: u64) -> EntityId {
    EntityId(engine_id_bytes(core, created_ms))
}

fn engine_id_bytes(core: liv_core::Id, created_ms: u64) -> [u8; 16] {
    let mut out = [0u8; 16];
    let ms = created_ms & 0xffff_ffff_ffff;
    out[0] = (ms >> 40) as u8;
    out[1] = (ms >> 32) as u8;
    out[2] = (ms >> 24) as u8;
    out[3] = (ms >> 16) as u8;
    out[4] = (ms >> 8) as u8;
    out[5] = ms as u8;
    // Version 7 in the high nibble; the low nibble and the next byte carry
    // the top of the core id, so two entities made in the same millisecond
    // still differ.
    out[6] = 0x70 | ((core >> 60) & 0x0f) as u8;
    out[7] = (core >> 52) as u8;
    // RFC 4122 variant, then the core id itself — which makes a converted
    // box readable in a hex dump and a mismapping obvious.
    out[8] = 0x80;
    out[9..16].copy_from_slice(&core.to_be_bytes()[1..8]);
    out
}

/// Did this id come out of a conversion? Version 7, where the furniture is
/// version 8 and a minted id is also 7 — so this answers "is it a thing"
/// and not "where did it come from". Kept because a hex dump of a
/// converted box should be readable, and a caller checking the nibble
/// should have the constant named rather than written out.
pub fn looks_like_entity(id: EntityId) -> bool {
    id.0[6] >> 4 == 0x7
}
