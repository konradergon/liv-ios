//! Services — milestone 3: the v0 query.
//!
//! A query is data, never a closure: it can live in a cell (a saved query is
//! an entity), travel to disk, and later be handed to the answerer. The v0
//! shape is the constitution's: a plain conjunction of
//! (property, operator, value). Traversal and aggregation wait for the
//! milestone that needs them.

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;

use lotus_core::{props, Entity, Id, Store, Value};

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
