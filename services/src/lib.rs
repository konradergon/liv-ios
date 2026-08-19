//! Services — milestone 3: the v0 query.
//!
//! A query is data, never a closure: it can live in a cell (a saved query is
//! an entity), travel to disk, and later be handed to the answerer. The v0
//! shape is the constitution's: a plain conjunction of
//! (property, operator, value). Traversal and aggregation wait for the
//! milestone that needs them.

pub mod clerk;
pub mod comms;
pub mod projection;
pub mod vault;
pub mod content;
mod dates;
pub mod export;
pub mod files;
pub mod habits;
pub mod import;
pub mod links;
pub mod markdown;
pub mod recurrence;
pub mod search;
pub mod tasks;
pub mod timeviews;

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;

use liv_core::{
    props, Author, Cell, Command, DateTime, Entity, Id, PersistError, RichText, Session,
    Store, Value,
};

/// Capture: an untyped entity with content and a creation date. Nothing
/// else. Every shell — the CLI today, the popup now, whatever comes —
/// builds the same scrap through this one function.
pub fn capture(
    session: &mut Session,
    text: &str,
    created: DateTime,
) -> Result<Id, PersistError> {
    let scrap = session.allocate_id();
    session.commit(
        vec![
            Command::Create { entity: scrap },
            Command::AddCell {
                entity: scrap,
                cell: Cell {
                    property: props::CONTENT,
                    // Line by line (2026-08-18). One flat span made a
                    // multi-line capture name itself with its whole body
                    // in every list — the lines ARE the storage format.
                    value: Value::RichText(RichText {
                        spans: crate::content::plain_spans(text),
                    }),
                },
            },
            Command::AddCell {
                entity: scrap,
                cell: Cell {
                    property: props::CREATED,
                    value: Value::DateTime(created),
                },
            },
        ],
        "capture",
        Author::User,
    )?;
    Ok(scrap)
}

/// A fresh box seeds the bootstrap property definitions — entities like
/// any other, authored by the system. Property names live in the box, not
/// in application code, so views can look them up and the clerk will one
/// day reuse them as its gazetteer. The first run asks nothing.
/// The onboarding tour's scripted captures (P19c — FROZEN for 19i, hazard
/// H5): each string must fire at least one clerk proposer on a fresh seeded
/// box, so the tour's assist moment can never demo a dead wand. A services
/// test asserts this on every change; edit these only with that test.
pub const TOUR_CAPTURES: [&str; 3] = [
    "Call the dentist tomorrow 10:00",
    "Renew the passport asap",
    "Team retro friday 14:00",
];

pub fn seed_if_fresh(session: &mut Session) -> Result<(), PersistError> {
    seed_bootstrap(session)?;
    seed_starter_library(session)?;
    seed_recurrence(session)?;
    seed_files(session)?;
    seed_links(session)?;
    seed_priority(session)?;
    seed_lists(session)?;
    seed_habits(session)?;
    seed_assist(session)?;
    seed_event_fields(session)?;
    seed_contact_fields(session)?;
    seed_date_roles(session)?;
    seed_workspaces(session)?;
    seed_daily_note(session)?;
    seed_status_scoping(session)?;
    seed_display_attributes(session)
}

/// The V3 inspector's substrate (P11/11e, bp1 e8/e14/e20/e26 + D11/D21):
/// five display attributes, each a cell ON a property-definition entity —
/// definitions are entities, so this is ordinary data, no core change.
/// `icon` (glyph token) · `digit-key` (the shortcut, one global map — R2
/// owns assignments) · `hide-on-kind` (reference: types where the row is
/// hidden) · `hide-when-empty` (bool: the resting panel stays short) ·
/// `core-on-kind` (reference: types where the row sits in the core card
/// instead of MORE). P11 seeds the DEFINITIONS only — no icon/digit values;
/// the starter value table is P11.5's call with R2, and it is data, not
/// schema. Own additive guard; an older box gains all five on open.
/// The daily-note type + its `workspace` reference property (P12 12a, D3).
/// A daily note is an ordinary note that carries a `type=daily-note` cell and
/// a calendar-role `date` cell (§2.3); `workspace` is the first content-to-
/// workspace membership — a narrow reference cell scoped to daily notes, NOT a
/// general membership model. Own guard (`workspace` absent) so an older box
/// gains both on open — and runs AFTER seed_date_roles so `date` resolves for
/// the type's EXPECTED cell.
fn seed_daily_note(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "workspace").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    let workspace = session.allocate_id();
    commands.push(Command::Create { entity: workspace });
    for cell in [
        Cell { property: props::NAME, value: Value::text("workspace") },
        Cell { property: props::VALUE_KIND, value: Value::text("reference") },
        Cell { property: props::WORKING, value: Value::Bool(true) },
    ] {
        commands.push(Command::AddCell { entity: workspace, cell });
    }

    // The type, EXPECTED=[content, date] so `find_type` resolves it and the
    // inspector offers both rows. `date` was seeded by seed_date_roles.
    let date = property_id(session.store(), "date");
    let daily = session.allocate_id();
    commands.push(Command::Create { entity: daily });
    for cell in [
        Cell { property: props::NAME, value: Value::text("daily-note") },
        Cell { property: props::WORKING, value: Value::Bool(true) },
        Cell { property: props::EXPECTED, value: Value::Reference(props::CONTENT) },
    ] {
        commands.push(Command::AddCell { entity: daily, cell });
    }
    if let Some(date) = date {
        commands.push(Command::AddCell {
            entity: daily,
            cell: Cell { property: props::EXPECTED, value: Value::Reference(date) },
        });
    }
    session.commit(commands, "daily-note type", Author::System)?;
    Ok(())
}

fn seed_display_attributes(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "hide-when-empty").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    for (name, kind) in [
        ("icon", "text"),
        ("digit-key", "text"),
        ("hide-on-kind", "reference"),
        ("hide-when-empty", "bool"),
        ("core-on-kind", "reference"),
    ] {
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(name) },
            Cell { property: props::VALUE_KIND, value: Value::text(kind) },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
    }
    session.commit(commands, "display attributes", Author::System)?;
    Ok(())
}

/// Universal status, scoped (P11/11d — R2, with R6 recorded as: ONE `status`
/// definition, option entities scoped by `for-type`). One additive commit,
/// guarded on its OWN property (`for-type`), that
/// (1) seeds `for-type` (reference — the kinds an option is offered to),
///     `hue` (number, 0–360 — the option's dot; values are placeholders
///     pending R3), `completes` (bool — the terminal state a checkbox
///     writes and a board folds), and `default-status` (reference — the
///     entry column, as a cell on the TYPE);
/// (2) scopes the three existing options — `todo`/`doing`/`done` gain
///     for-type→task, board order 1/2/3 (the existing `order` property),
///     placeholder hues, and `completes` on done — additive cells on
///     System-seeded entities, nothing removed or replaced;
/// (3) gives the task type `default-status → todo`. No other type gets
///     one: a new contact is born with NO status — no-default is the
///     default, and "no status" stays always-valid.
/// Event/contact/project vocabularies are NOT seeded: those are user
/// vocabularies arriving via add_status_option and P12's presets.
fn seed_status_scoping(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "for-type").is_some() {
        return Ok(());
    }
    let store = session.store();
    let status = property_id(store, "status");
    let order = property_id(store, "order");
    let task_type = content::find_type(store, "task");
    let todo = status.and_then(|s| content::find_option(store, s, "todo"));
    let doing = status.and_then(|s| content::find_option(store, s, "doing"));
    let done = status.and_then(|s| content::find_option(store, s, "done"));

    let mut commands = Vec::new();
    let new_property = |session: &mut Session, commands: &mut Vec<Command>, name: &str, kind: &str| {
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
    };
    let for_type = new_property(session, &mut commands, "for-type", "reference");
    let hue = new_property(session, &mut commands, "hue", "number");
    let completes = new_property(session, &mut commands, "completes", "bool");
    let default_status = new_property(session, &mut commands, "default-status", "reference");

    if let Some(task) = task_type {
        // Placeholder hues (R3 re-edits them as ordinary data; no test may
        // assert a specific number).
        let legacy = [(todo, 1.0, 210.0), (doing, 2.0, 45.0), (done, 3.0, 145.0)];
        for (option, position, tone) in legacy {
            let Some(option) = option else { continue };
            commands.push(Command::AddCell {
                entity: option,
                cell: Cell { property: for_type, value: Value::Reference(task) },
            });
            if let Some(order) = order {
                commands.push(Command::AddCell {
                    entity: option,
                    cell: Cell { property: order, value: Value::Number(position) },
                });
            }
            commands.push(Command::AddCell {
                entity: option,
                cell: Cell { property: hue, value: Value::Number(tone) },
            });
        }
        if let Some(done) = done {
            commands.push(Command::AddCell {
                entity: done,
                cell: Cell { property: completes, value: Value::Bool(true) },
            });
        }
        if let Some(todo) = todo {
            commands.push(Command::AddCell {
                entity: task,
                cell: Cell { property: default_status, value: Value::Reference(todo) },
            });
        }
    }

    // Universal status is the spine's claim on EVERY kind — record it as an
    // expectation on the two starter types seeded with none. This is also
    // what makes them findable: find_type keys on an EXPECTED cell (the P9
    // lesson), and person/project were unfindable — which would have made
    // their per-kind vocabularies unreachable through every seam that
    // resolves a kind by name. Additive cells; task/event/note untouched.
    //
    // The finder is CONSTRAINED and DETERMINISTIC (the review's high
    // finding, live-reproduced: a loose name-only scan over HashMap order
    // stamped user lists named "project" on 9/20 old boxes — permanently,
    // since this seed is one-shot). A starter type is WORKING plumbing with
    // no TYPE cell and no VALUE_KIND; user content always carries a TYPE
    // (or isn't WORKING), workspaces carry TYPE→workspace, and the trash is
    // excluded. min-by-id breaks any residual tie toward the earliest-
    // seeded entity — never HashMap luck.
    if let Some(status) = status {
        for name in ["person", "project"] {
            let starter_type = session
                .store()
                .entities()
                .filter(|e| {
                    !e.trashed
                        && matches!(e.get(props::NAME), Some(Value::Text(n)) if n == name)
                        && e.has(props::WORKING, &Value::Bool(true))
                        && e.get(props::TYPE).is_none()
                        && e.get(props::VALUE_KIND).is_none()
                        && e.get(props::EXPECTED).is_none()
                })
                .map(|e| e.id)
                .min();
            if let Some(t) = starter_type {
                commands.push(Command::AddCell {
                    entity: t,
                    cell: Cell { property: props::EXPECTED, value: Value::Reference(status) },
                });
            }
        }
    }
    session.commit(commands, "status scoping", Author::System)?;
    Ok(())
}

/// One status option as a kind's board/picker sees it.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct StatusOption {
    pub id: Id,
    pub name: String,
    pub order: f64,
    pub hue: Option<f64>,
    pub completes: bool,
}

/// The status vocabulary OFFERED to a kind (bp6 #8, bp1 e17): the options
/// the one `status` definition references, kept when a `for-type` cell
/// names this kind — or when the option carries no `for-type` at all (the
/// pre-scoping legacy shape: offered everywhere, never stranded). Sorted by
/// `order` (board column order = digit order), then id. An option with zero
/// carriers still appears — an empty board column keeps its header. A kind
/// with no matching options offers NOTHING: vocabularies are per-kind,
/// never inherited.
pub fn status_options_for(store: &Store, kind: Id) -> Vec<StatusOption> {
    let Some(status) = property_id(store, "status") else {
        return Vec::new();
    };
    let Some(def) = store.get(status) else {
        return Vec::new();
    };
    let for_type = property_id(store, "for-type");
    let order_prop = property_id(store, "order");
    let hue_prop = property_id(store, "hue");
    let completes_prop = property_id(store, "completes");
    let number = |e: &Entity, p: Option<Id>| match p.and_then(|p| e.get(p)) {
        Some(Value::Number(n)) => Some(*n),
        _ => None,
    };
    let mut out: Vec<StatusOption> = def
        .all(props::OPTIONS)
        .filter_map(|v| {
            let Value::Reference(option) = v else { return None };
            let e = store.get(*option)?;
            let offered = match for_type {
                None => true,
                Some(ft) => e.get(ft).is_none() || e.has(ft, &Value::Reference(kind)),
            };
            if !offered {
                return None;
            }
            let name = match e.get(props::NAME) {
                Some(Value::Text(n)) => n.clone(),
                _ => return None,
            };
            Some(StatusOption {
                id: *option,
                name,
                order: number(e, order_prop).unwrap_or(0.0),
                hue: number(e, hue_prop),
                completes: matches!(
                    completes_prop.and_then(|p| e.get(p)),
                    Some(Value::Bool(true))
                ),
            })
        })
        .collect();
    out.sort_by(|a, b| {
        a.order
            .partial_cmp(&b.order)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.id.cmp(&b.id))
    });
    out
}

/// The date ROLES of the amended spine (P11/R1, bp1 e10/e23): four datetime
/// properties beside `due` — `date` is the calendar role (positions on the
/// calendar, with `due`); `valid-until`, `occurred`, `purchased-on` are
/// lookup roles (filterable facts, never appointments — bp9 #15). A role is
/// a property, not a value attribute: zero migration, and Space-cycling a
/// role is one transaction moving the value between properties. Own guard
/// (`occurred`), NOT the starter-library `due` guard which short-circuits on
/// every shipped box — an older box gains all four on open. Offered, never
/// EXPECTED: no type's expectations change ("a date is just a row").
fn seed_date_roles(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "occurred").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    for name in ["date", "valid-until", "occurred", "purchased-on"] {
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(name) },
            Cell { property: props::VALUE_KIND, value: Value::text("datetime") },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
    }
    session.commit(commands, "date roles", Author::System)?;
    Ok(())
}

/// The properties that POSITION an entity on the calendar: {date, due}.
/// Lookup roles (valid-until / occurred / purchased-on) are never in this
/// set — that absence IS bp9 #15's off-calendar rule. Resolved by name at
/// read (the seed law: no code keys on ids). One function, one place: the
/// snapshot's `dated` union and the recurrence anchor both read it, so
/// "what renders" and "what anchors a series" can never drift apart. Order
/// matters: `date` before `due` is the anchor and display precedence for
/// rows carrying both. The per-view configurable set (feature-map #24
/// `dateField`) is deferred to the P14 calendar re-base; this function is
/// where that config will be consulted when it exists.
pub fn calendar_set(store: &Store) -> Vec<Id> {
    ["date", "due"].iter().filter_map(|n| property_id(store, n)).collect()
}

/// Event fields the calendar offers: `location` (text) and `attendees` (a
/// reference to person entities — feature-map #26, distinct from a note's
/// people-links). Additive and idempotent on its OWN guard (a `location`
/// property), NOT the starter-library `due` guard which short-circuits on
/// every existing box — so an older box that already has `due` gains these on
/// open. Offered by the calendar, never EXPECTED: an event is valid without
/// either, so the `event` type's expectations ([due]) are left untouched.
/// The contact profile fields (P14-CT): role/org/email/phone, all text,
/// additive on open (an older box gains them next launch). Offered, never
/// EXPECTED — a person is valid without any of them. Same shape as the
/// event/file field seeds. Own guard on `role`.
fn seed_contact_fields(session: &mut Session) -> Result<(), PersistError> {
    // Per-field guard, not a single sentinel: email/org/phone are common
    // fields a user may already have created by hand, so seed only the ones
    // that are ACTUALLY absent — else an upgrade box duplicates a definition
    // (the review's finding; `property_id` would then be nondeterministic).
    let mut commands = Vec::new();
    for name in ["role", "org", "email", "phone"] {
        if property_id(session.store(), name).is_some() {
            continue;
        }
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(name) },
            Cell { property: props::VALUE_KIND, value: Value::text("text") },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
    }
    if commands.is_empty() {
        return Ok(());
    }
    session.commit(commands, "contact fields", Author::System)?;
    Ok(())
}

fn seed_event_fields(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "location").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    for (name, kind) in [("location", "text"), ("attendees", "reference")] {
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(name) },
            Cell { property: props::VALUE_KIND, value: Value::text(kind) },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
    }
    session.commit(commands, "event fields", Author::System)?;
    Ok(())
}

/// The `list` type — so a manual list is a distinguishable kind (`type:list`)
/// whose ordered `related` cells are its members. Its own guard (a type named
/// "list"), additive on open like the P7/P8 passes, so an older box gains it.
/// A list expects no properties (`related` is offered, added by the gesture).
fn seed_lists(session: &mut Session) -> Result<(), PersistError> {
    let exists = session.store().entities().any(|e| {
        matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "list")
            && e.get(props::VALUE_KIND).is_none()
    });
    if exists {
        return Ok(());
    }
    let related = property_id(session.store(), "related");
    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    for cell in [
        Cell { property: props::NAME, value: Value::text("list") },
        Cell { property: props::WORKING, value: Value::Bool(true) },
    ] {
        commands.push(Command::AddCell { entity: id, cell });
    }
    // A list expects `related` — its members. This is also what makes it a
    // findable type (find_type keys on an EXPECTED cell).
    if let Some(related) = related {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: props::EXPECTED, value: Value::Reference(related) },
        });
    }
    session.commit(commands, "list type", Author::System)?;
    Ok(())
}

/// The assist switch (P19h): ONE backstage `assist` entity whose
/// `automation` bool gates EVERY clerk proposal — a vault cell, so the
/// consent travels with the box and every door (shell, CLI) inherits it.
/// Default ON (today's behavior). Self-guarded on the assist ENTITY, never
/// the property name — a pre-P19 box can carry a foreign `automation`
/// property (imports mint arbitrary frontmatter keys) and must still get
/// its switch (the P19 review).
fn seed_assist(session: &mut Session) -> Result<(), PersistError> {
    if clerk::assist_switch(session.store()).is_some() {
        return Ok(());
    }
    let automation = session.allocate_id();
    let mut commands = vec![Command::Create { entity: automation }];
    for cell in [
        Cell { property: props::NAME, value: Value::text("automation") },
        Cell { property: props::VALUE_KIND, value: Value::text("bool") },
        Cell { property: props::WORKING, value: Value::Bool(true) },
    ] {
        commands.push(Command::AddCell { entity: automation, cell });
    }
    let assist = session.allocate_id();
    commands.push(Command::Create { entity: assist });
    for cell in [
        Cell { property: props::NAME, value: Value::text("assist") },
        Cell { property: props::WORKING, value: Value::Bool(true) },
        Cell { property: automation, value: Value::Bool(true) },
    ] {
        commands.push(Command::AddCell { entity: assist, cell });
    }
    session.commit(commands, "assist switch", Author::System)?;
    Ok(())
}

/// Habits (P18b): the `habit` type (front of house — habits belong in
/// Everything) with `points` (number, default 1 at read) and `cadence`
/// (display text; N-per-week semantics deferred, feature-map #19), plus the
/// backstage `check-in` type and its `habit` reference. Self-guarded on
/// `cadence`, additive on an older box's next open.
fn seed_habits(session: &mut Session) -> Result<(), PersistError> {
    // Per-ITEM guards (the seed_contact_fields lesson, and the review's):
    // a single sentinel silently disables the whole set on any box that
    // already carries one of the names (import mints arbitrary frontmatter
    // keys as properties), and mints duplicates of the rest.
    let mut commands = Vec::new();
    let ensure_property = |session: &mut Session,
                           commands: &mut Vec<Command>,
                           name: &str,
                           kind: &str| {
        if let Some(existing) = property_id(session.store(), name) {
            return existing;
        }
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
    };
    let points = ensure_property(session, &mut commands, "points", "number");
    let _cadence = ensure_property(session, &mut commands, "cadence", "text");
    let habit_ref = ensure_property(session, &mut commands, "habit", "reference");

    let ensure_type = |session: &mut Session,
                       commands: &mut Vec<Command>,
                       name: &str,
                       expected: Id| {
        if crate::content::find_type(session.store(), name).is_some() {
            return;
        }
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(name) },
            Cell { property: props::WORKING, value: Value::Bool(true) },
            // EXPECTED makes find_type resolve it (the P9 rule).
            Cell { property: props::EXPECTED, value: Value::Reference(expected) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
    };
    ensure_type(session, &mut commands, "habit", points);
    ensure_type(session, &mut commands, "check-in", habit_ref);

    if !commands.is_empty() {
        session.commit(commands, "habit types", Author::System)?;
    }
    Ok(())
}

/// The task surface's `priority` select — one more option list the Tasks
/// list offers. It needs its OWN guard, not the starter-library's (which
/// short-circuits on `due` and so never runs on a shipped box): guarded on
/// `priority` itself, it lands additively on an older box's next open.
/// Offered, never expected — a task is valid without a priority, so the
/// `task` type's expectations are left untouched.
fn seed_priority(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "priority").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    let priority = session.allocate_id();
    commands.push(Command::Create { entity: priority });
    for cell in [
        Cell { property: props::NAME, value: Value::text("priority") },
        Cell { property: props::VALUE_KIND, value: Value::text("select") },
        Cell { property: props::WORKING, value: Value::Bool(true) },
    ] {
        commands.push(Command::AddCell { entity: priority, cell });
    }
    for option in ["low", "medium", "high"] {
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(option) },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
        commands.push(Command::AddCell {
            entity: priority,
            cell: Cell { property: props::OPTIONS, value: Value::Reference(id) },
        });
    }
    session.commit(commands, "priority property", Author::System)?;
    Ok(())
}

/// The file librarian's two properties, additive on open (an older box
/// gains them next launch): a `file` property (kind `file`, holding a
/// FileRef) and a `format` text property (the extension, so `format:pdf`
/// filters through the existing search DSL). No `file` *type* — a file
/// entity is one that carries a `file` cell (`has:file`); a same-named
/// type would collide with this property under reference-by-name.
fn seed_files(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "file").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    for (name, kind) in [("file", "file"), ("format", "text")] {
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(name) },
            Cell { property: props::VALUE_KIND, value: Value::text(kind) },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
    }
    session.commit(commands, "file properties", Author::System)?;
    Ok(())
}

/// The link substrate (P15/D6): a `url` text property + a `link` type, so a
/// dropped browser tab becomes a first-class link entity (type=link + url +
/// name) that Library facets and kind filters key on. Additive + idempotent
/// (guarded on `url`), like `seed_files` — a pre-existing box gains it on open.
fn seed_links(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "url").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    // The url property.
    let url = session.allocate_id();
    commands.push(Command::Create { entity: url });
    for cell in [
        Cell { property: props::NAME, value: Value::text("url") },
        Cell { property: props::VALUE_KIND, value: Value::text("text") },
        Cell { property: props::WORKING, value: Value::Bool(true) },
    ] {
        commands.push(Command::AddCell { entity: url, cell });
    }
    // The link type — NAME + WORKING + EXPECTED→url, so `find_type("link")`
    // (which requires an EXPECTED cell) resolves it.
    let link = session.allocate_id();
    commands.push(Command::Create { entity: link });
    for cell in [
        Cell { property: props::NAME, value: Value::text("link") },
        Cell { property: props::WORKING, value: Value::Bool(true) },
        Cell { property: props::EXPECTED, value: Value::Reference(url) },
    ] {
        commands.push(Command::AddCell { entity: link, cell });
    }
    session.commit(commands, "link substrate", Author::System)?;
    Ok(())
}

/// Milestone 6's vocabulary, additive like the starter library: the
/// recurrence rule (a text cell on the series) and exception-of (the
/// reference an exception entity carries). Old boxes gain both on open.
/// Workspaces, the Liv port's P2: one entity kind carries what Liv
/// split across Workspace records and a TreeNode store — a workspace
/// may reference a parent workspace, and the tree is that. Working
/// entities: navigation chrome, not thoughts, so default queries and
/// the gazetteer never see them.
fn seed_workspaces(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "emoji").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    let mut new_property = |session: &mut Session, name: &str, kind: &str| {
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
    };
    let emoji = new_property(session, "emoji", "text");
    let favorite = new_property(session, "favorite", "bool");
    new_property(session, "archived", "bool");
    let parent = new_property(session, "parent", "reference");
    new_property(session, "order", "number");
    let builtin = new_property(session, "builtin", "text");
    new_property(session, "bookmarked", "bool");

    // The workspace type. Its expectations make it findable the same
    // way "note" is, and offer the fields its inspector shows.
    let workspace_type = session.allocate_id();
    commands.push(Command::Create { entity: workspace_type });
    for cell in [
        Cell { property: props::NAME, value: Value::text("workspace") },
        Cell { property: props::WORKING, value: Value::Bool(true) },
        Cell { property: props::EXPECTED, value: Value::Reference(emoji) },
    ] {
        commands.push(Command::AddCell { entity: workspace_type, cell });
    }
    commands.push(Command::AddCell {
        entity: workspace_type,
        cell: Cell { property: props::EXPECTED, value: Value::Reference(favorite) },
    });
    commands.push(Command::AddCell {
        entity: workspace_type,
        cell: Cell { property: props::EXPECTED, value: Value::Reference(parent) },
    });

    // The built-in Home workspace: favourite by default, protected in
    // the shell from archive and delete.
    let home = session.allocate_id();
    commands.push(Command::Create { entity: home });
    for cell in [
        Cell { property: props::NAME, value: Value::text("Home") },
        Cell { property: props::TYPE, value: Value::Reference(workspace_type) },
        Cell { property: props::WORKING, value: Value::Bool(true) },
        Cell { property: builtin, value: Value::text("home") },
    ] {
        commands.push(Command::AddCell { entity: home, cell });
    }

    session.commit(commands, "workspaces", Author::System)?;
    Ok(())
}

fn seed_recurrence(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "recurrence").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    for (name, kind) in [("recurrence", "text"), ("exception-of", "reference")] {
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(name) },
            Cell { property: props::VALUE_KIND, value: Value::text(kind) },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
    }
    session.commit(commands, "recurrence properties", Author::System)?;
    Ok(())
}

/// What Today shows, composed once for every shell: entities due through
/// tonight (recurring series excluded — their past is not a debt), plus
/// any series occurring today, plus the still-unstructured captures.
pub struct TodaySections {
    pub due: Vec<Id>,
    pub unstructured: Vec<Id>,
}

pub fn today_sections(store: &Store, today: DateTime) -> TodaySections {
    let Some(due) = property_id(store, "due") else {
        return TodaySections { due: Vec::new(), unstructured: Vec::new() };
    };
    let recurrence_prop = property_id(store, "recurrence");

    let ymd = today.civil / 10_000;
    let tonight = DateTime {
        civil: ymd * 10_000 + 2359,
        date_only: false,
        end: None,
    };

    let mut constraints = vec![Constraint {
        property: due,
        op: Op::AtMost(Value::DateTime(tonight)),
    }];
    if let Some(recurrence) = recurrence_prop {
        constraints.push(Constraint {
            property: recurrence,
            op: Op::Missing,
        });
    }
    let mut due_now = run(
        store,
        &Query {
            constraints,
            sort: Some(Sort { property: due, descending: false }),
            ..Query::default()
        },
    );

    // A series that recurs today joins the due list as itself.
    for occurrence in recurrence::occurrences(store, today, today) {
        if !due_now.contains(&occurrence.series) {
            due_now.push(occurrence.series);
        }
    }

    let unstructured = run(
        store,
        &Query {
            constraints: vec![
                Constraint { property: props::CONTENT, op: Op::Exists },
                Constraint { property: due, op: Op::Missing },
            ],
            sort: Some(Sort { property: props::CREATED, descending: true }),
            ..Query::default()
        },
    );

    TodaySections { due: due_now, unstructured }
}

fn seed_bootstrap(session: &mut Session) -> Result<(), PersistError> {
    if !session.store().history().is_empty() {
        return Ok(());
    }
    // default-view, renderer and config are no longer seeded (T2, owner
    // 2026-08-09): nothing ever read them. Boxes that already carry the
    // rows keep them harmlessly; the ids stay reserved in props and are
    // never reused, so both generations of box agree about every id.
    let definitions: [(Id, &str, &str); 11] = [
        (props::NAME, "name", "text"),
        (props::TYPE, "type", "reference"),
        (props::CREATED, "created", "datetime"),
        (props::CONTENT, "content", "richtext"),
        (props::VALUE_KIND, "value-kind", "text"),
        (props::OPTIONS, "options", "reference"),
        (props::EXPECTED, "expected", "reference"),
        (props::QUERY, "query", "text"),
        (props::EXTERNAL_ID, "external-id", "text"),
        (props::WORKING, "working", "bool"),
        (props::PRIVATE, "private", "bool"),
    ];
    let mut commands = Vec::new();
    for (id, name, kind) in definitions {
        commands.push(Command::Create { entity: id });
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell {
                property: props::NAME,
                value: Value::text(name),
            },
        });
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell {
                property: props::VALUE_KIND,
                value: Value::text(kind),
            },
        });
        // Property definitions are plumbing on the shelf, not thoughts.
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell {
                property: props::WORKING,
                value: Value::Bool(true),
            },
        });
    }
    session.commit(commands, "bootstrap properties", Author::System)?;
    Ok(())
}

/// The starter library, milestone 5: the floor the first workflow fixed —
/// note, task, event — plus person and project, the two kinds of name the
/// clerk's gazetteer feeds on, and the properties they expect.
///
/// All ordinary entities: allocated ids (never reserved constants, so no
/// code can key on them), author system, working: true — plumbing on the
/// shelf, like the property definitions. Offers, never fixtures.
///
/// Additive by design: an older box that predates the library gains it on
/// open. Nothing is re-seeded once "due" exists, and nothing existing is
/// ever touched — a better future opinion arrives as a proposal instead.
fn seed_starter_library(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "due").is_some() {
        return Ok(());
    }

    let mut commands = Vec::new();
    let new_property = |commands: &mut Vec<Command>,
                            session: &mut Session,
                            name: &str,
                            kind: &str| {
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
    };

    let due = new_property(&mut commands, session, "due", "datetime");
    let status = new_property(&mut commands, session, "status", "select");
    let _related = new_property(&mut commands, session, "related", "reference");

    // Status options are entities; the definition references them.
    for option in ["todo", "doing", "done"] {
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(option) },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
        commands.push(Command::AddCell {
            entity: status,
            cell: Cell { property: props::OPTIONS, value: Value::Reference(id) },
        });
    }

    // The types, with their expected cells. The expected cell is the one
    // fact of expectation; defaults wait for a surface that creates
    // through templates.
    let expectations: [(&str, &[Id]); 5] = [
        ("note", &[props::CONTENT]),
        ("task", &[status, due]),
        ("event", &[due]),
        ("person", &[]),
        ("project", &[]),
    ];
    for (name, expected) in expectations {
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(name) },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] {
            commands.push(Command::AddCell { entity: id, cell });
        }
        for property in expected {
            commands.push(Command::AddCell {
                entity: id,
                cell: Cell {
                    property: props::EXPECTED,
                    value: Value::Reference(*property),
                },
            });
        }
    }

    session.commit(commands, "starter library", Author::System)?;
    Ok(())
}

/// A description of a set of entities. Plain data; `run` interprets it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Query {
    /// All constraints must hold (a conjunction).
    pub constraints: Vec<Constraint>,
    pub sort: Option<Sort>,
    /// Backstage plumbing (`working: true`) stays backstage by default.
    pub include_working: bool,
    /// The trash is its own perspective; queries see live entities.
    pub include_trashed: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Constraint {
    pub property: Id,
    pub op: Op,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Op {
    /// At least one cell of the property equals the value
    /// (a multi-valued property matches on any of its cells).
    Equals(Value),
    /// No cell of the property equals the value.
    /// Vacuously true when the property is absent: a task with no status
    /// satisfies `status != done`.
    NotEquals(Value),
    /// At least one cell of the property is present.
    Exists,
    /// No cell of the property at all — stronger than NotEquals.
    /// "Still unstructured" is a Missing, not a NotEquals.
    Missing,
    /// At least one cell orders at or before the value, by the same
    /// per-kind ordering sort uses. Grew out of Today:
    /// "everything due by tonight".
    AtMost(Value),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Sort {
    pub property: Id,
    pub descending: bool,
}

/// Interpret the query against the store. A linear scan — the simplest
/// thing; an index earns its place when a measurement demands it.
/// Results are stable: sorted by the sort property, entities missing it
/// last, ties (and the no-sort case) by id.
pub fn run(store: &Store, query: &Query) -> Vec<Id> {
    let mut matches: Vec<&Entity> = store
        .entities()
        .filter(|e| query.include_trashed || !e.trashed)
        .filter(|e| query.include_working || !e.has(props::WORKING, &Value::Bool(true)))
        .filter(|e| query.constraints.iter().all(|c| satisfies(e, c)))
        .collect();

    match &query.sort {
        None => matches.sort_by_key(|e| e.id),
        Some(sort) => matches.sort_by(|a, b| {
            let ord = match (a.get(sort.property), b.get(sort.property)) {
                (Some(x), Some(y)) => {
                    let ord = compare_values(x, y);
                    // Only the values reverse; entities missing the
                    // property sort last in either direction.
                    if sort.descending {
                        ord.reverse()
                    } else {
                        ord
                    }
                }
                (Some(_), None) => Ordering::Less,
                (None, Some(_)) => Ordering::Greater,
                (None, None) => Ordering::Equal,
            };
            ord.then(a.id.cmp(&b.id))
        }),
    }

    matches.into_iter().map(|e| e.id).collect()
}

fn satisfies(entity: &Entity, constraint: &Constraint) -> bool {
    match &constraint.op {
        Op::Equals(value) => entity.has(constraint.property, value),
        Op::NotEquals(value) => !entity.has(constraint.property, value),
        Op::Exists => entity.all(constraint.property).next().is_some(),
        Op::Missing => entity.all(constraint.property).next().is_none(),
        Op::AtMost(value) => entity
            .all(constraint.property)
            .any(|v| compare_values(v, value) != Ordering::Greater),
    }
}

/// Property definitions are entities, so name lookup used to be a
/// query — a full-store scan, at ~197 call sites, which twice made the
/// snapshot quadratic. The store's name index answers it now (T1,
/// owner 2026-08-09); the filters below reproduce the old query's
/// semantics exactly: not trashed, carries a value-kind, lowest id
/// wins, plumbing included (definitions ARE plumbing, but we asked).
pub fn property_id(store: &Store, name: &str) -> Option<Id> {
    store
        .named(name)
        .iter()
        .filter_map(|id| store.get(*id))
        .filter(|e| !e.trashed && e.get(props::VALUE_KIND).is_some())
        .map(|e| e.id)
        .min()
}

/// Ordering for sorting only — value *equality* stays per-kind in the core.
/// Same kind compares within the kind; different kinds group in enum order.
/// A date-only Friday sorts beside Friday 10:00 because civil packs both.
fn compare_values(a: &Value, b: &Value) -> Ordering {
    match (a, b) {
        (Value::Text(x), Value::Text(y)) => x.cmp(y),
        (Value::RichText(x), Value::RichText(y)) => plain(x).cmp(&plain(y)),
        (Value::Number(x), Value::Number(y)) => x.partial_cmp(y).unwrap_or(Ordering::Equal),
        (Value::Bool(x), Value::Bool(y)) => x.cmp(y),
        // A span ORDERS by its start — a trip "13th → 15th" is due at-or-
        // before the 13th exactly like its plain twin, and Today's AtMost
        // boundary must agree (the review's live repro). The `end` field
        // stays out of ordering entirely; per-kind *equality* still tells a
        // span from its start-only twin, which is RemoveCell's concern.
        (Value::DateTime(x), Value::DateTime(y)) => {
            (x.civil, x.date_only).cmp(&(y.civil, y.date_only))
        }
        (Value::Select(x), Value::Select(y)) => x.cmp(y),
        (Value::Reference(x), Value::Reference(y)) => x.cmp(y),
        (Value::File(x), Value::File(y)) => x.path.cmp(&y.path),
        _ => kind_rank(a).cmp(&kind_rank(b)),
    }
}

fn plain(rich: &liv_core::RichText) -> String {
    rich.spans
        .iter()
        .map(|s| match s {
            liv_core::Span::Text(t) => t.text.as_str(),
            liv_core::Span::Break(_) | liv_core::Span::Ref(_) => "",
        })
        .collect()
}

fn kind_rank(v: &Value) -> u8 {
    match v {
        Value::Text(_) => 0,
        Value::RichText(_) => 1,
        Value::Number(_) => 2,
        Value::Bool(_) => 3,
        Value::DateTime(_) => 4,
        Value::Select(_) => 5,
        Value::Reference(_) => 6,
        Value::File(_) => 7,
    }
}

#[cfg(test)]
mod seed_tests {
    use super::*;

    /// The link substrate (P15/D6) is additive + idempotent: a fresh box gains
    /// a `url` property and a `link` type; a second pass mints nothing (the
    /// contact-fields guard pattern), and `find_type("link")` resolves.
    #[test]
    fn seed_links_is_additive_and_idempotent() {
        let dir = std::env::temp_dir().join("liv_seed_links");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let mut session = Session::open(dir.join("box.log")).unwrap();

        seed_bootstrap(&mut session).unwrap();
        seed_starter_library(&mut session).unwrap();
        assert!(property_id(session.store(), "url").is_none());

        seed_links(&mut session).unwrap();
        let url = property_id(session.store(), "url").expect("url property born");
        let link = crate::content::find_type(session.store(), "link").expect("link type born");
        let count = session.store().entities().count();

        // A second pass is a no-op — no duplicate url property or link type.
        seed_links(&mut session).unwrap();
        assert_eq!(property_id(session.store(), "url"), Some(url));
        assert_eq!(crate::content::find_type(session.store(), "link"), Some(link));
        assert_eq!(session.store().entities().count(), count, "re-seed created entities");
    }

    /// The scoping seed's type finder must never stamp user content (the
    /// review's live-reproduced high): a decoy entity named "project" that
    /// is not WORKING plumbing — or is trashed — is invisible to it, and
    /// the starter type wins deterministically.
    #[test]
    fn the_scoping_seed_targets_the_starter_type_never_a_decoy() {
        let dir = std::env::temp_dir().join("liv_seed_decoy");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("box.log");
        let mut session = Session::open(&path).unwrap();

        // Everything BEFORE the scoping pass — the pre-11d world.
        seed_bootstrap(&mut session).unwrap();
        seed_starter_library(&mut session).unwrap();
        seed_recurrence(&mut session).unwrap();
        seed_files(&mut session).unwrap();
        seed_priority(&mut session).unwrap();
        seed_lists(&mut session).unwrap();
        seed_event_fields(&mut session).unwrap();
        seed_contact_fields(&mut session).unwrap();
        seed_date_roles(&mut session).unwrap();
        seed_workspaces(&mut session).unwrap();
        seed_daily_note(&mut session).unwrap();

        // A user decoy: named "project", no VALUE_KIND, no EXPECTED — the
        // exact shape the loose finder matched. Not WORKING, like all user
        // content.
        let decoy = session.allocate_id();
        session
            .commit(
                vec![
                    Command::Create { entity: decoy },
                    Command::AddCell {
                        entity: decoy,
                        cell: Cell { property: props::NAME, value: Value::text("project") },
                    },
                ],
                "decoy",
                Author::User,
            )
            .unwrap();

        seed_status_scoping(&mut session).unwrap();

        let store = session.store();
        let status = property_id(store, "status").unwrap();
        assert!(
            store.get(decoy).unwrap().get(props::EXPECTED).is_none(),
            "the decoy is untouched"
        );
        let stamped = content::find_type(store, "project").expect("the starter type is findable");
        assert_ne!(stamped, decoy);
        assert!(
            store.get(stamped).unwrap().has(props::EXPECTED, &Value::Reference(status)),
            "the starter type carries the expectation"
        );
        assert!(
            store.get(stamped).unwrap().has(props::WORKING, &Value::Bool(true)),
            "and it is the WORKING plumbing entity"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
}
