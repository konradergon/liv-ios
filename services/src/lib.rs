//! Services — milestone 3: the v0 query.
//!
//! A query is data, never a closure: it can live in a cell (a saved query is
//! an entity), travel to disk, and later be handed to the answerer. The v0
//! shape is the constitution's: a plain conjunction of
//! (property, operator, value). Traversal and aggregation wait for the
//! milestone that needs them.

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
                        spans: vec![Span::Text(text.to_string())],
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
    }
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
            lotus_core::Span::Text(t) => t.as_str(),
            lotus_core::Span::Ref(_) => "",
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
