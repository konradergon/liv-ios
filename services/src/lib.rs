//! Services — milestone 3: the v0 query.
//!
//! A query is data, never a closure: it can live in a cell (a saved query is
//! an entity), travel to disk, and later be handed to the answerer. The v0
//! shape is the constitution's: a plain conjunction of
//! (property, operator, value). Traversal and aggregation wait for the
//! milestone that needs them.

pub mod clerk;
pub mod content;
mod dates;
pub mod recurrence;
pub mod search;

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;

use lotus_core::{
    props, Author, Cell, Command, DateTime, Entity, Id, PersistError, RichText, Session, Span,
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
                    value: Value::RichText(RichText {
                        spans: vec![Span::text(text)],
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
pub fn seed_if_fresh(session: &mut Session) -> Result<(), PersistError> {
    seed_bootstrap(session)?;
    seed_starter_library(session)?;
    seed_recurrence(session)?;
    seed_workspaces(session)
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
    let definitions: [(Id, &str, &str); 14] = [
        (props::NAME, "name", "text"),
        (props::TYPE, "type", "reference"),
        (props::CREATED, "created", "datetime"),
        (props::CONTENT, "content", "richtext"),
        (props::VALUE_KIND, "value-kind", "text"),
        (props::OPTIONS, "options", "reference"),
        (props::EXPECTED, "expected", "reference"),
        (props::DEFAULT_VIEW, "default-view", "reference"),
        (props::QUERY, "query", "text"),
        (props::RENDERER, "renderer", "text"),
        (props::CONFIG, "config", "text"),
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

/// Property definitions are entities, so name lookup is itself a query:
/// the entity carrying a value-kind whose name matches.
pub fn property_id(store: &Store, name: &str) -> Option<Id> {
    let query = Query {
        constraints: vec![
            Constraint {
                property: props::NAME,
                op: Op::Equals(Value::text(name)),
            },
            Constraint {
                property: props::VALUE_KIND,
                op: Op::Exists,
            },
        ],
        include_working: true, // definitions are plumbing, but we asked
        ..Query::default()
    };
    run(store, &query).first().copied()
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
        (Value::DateTime(x), Value::DateTime(y)) => x.cmp(y),
        (Value::Select(x), Value::Select(y)) => x.cmp(y),
        (Value::Reference(x), Value::Reference(y)) => x.cmp(y),
        (Value::File(x), Value::File(y)) => x.path.cmp(&y.path),
        _ => kind_rank(a).cmp(&kind_rank(b)),
    }
}

fn plain(rich: &lotus_core::RichText) -> String {
    rich.spans
        .iter()
        .map(|s| match s {
            lotus_core::Span::Text(t) => t.text.as_str(),
            lotus_core::Span::Break(_) | lotus_core::Span::Ref(_) => "",
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
