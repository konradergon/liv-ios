//! The query grammar, and asking the box a question with it.
//!
//! **THE ONE TOKENISER.** It lived in `services/src/search.rs`, which
//! depends on `core/`, so nothing over the engine could reach it — and a
//! second lexer for the same user-facing syntax is exactly what standing
//! rule 4 calls a defect. It moves here, unchanged in behaviour, and
//! `services/` imports it back: one grammar, one parser, in the crate that
//! has no dependencies above it.
//!
//! The lexer is deliberately STOREless. It says what a token looks like —
//! `key:value`, `-key:value`, `is:flag`, `key<value`, a bare word — and
//! has no opinion about whether the property exists. Resolution is a
//! separate step because a picker editing a draft query calls the lexer on
//! every keystroke and must never touch the box.
//!
//! **A user never types this.** Standing rule 5: filters and workspaces
//! are built from pickers over furniture that already exists, and the text
//! grammar is the storage format plus an advanced escape hatch.
//!
//! ## Running one
//!
//! `core/`'s `run` is a linear scan with a comment admitting it — *"the
//! simplest thing; an index earns its place when a measurement demands
//! it"*. The measurement demanded it: that scan is what made a snapshot
//! cost the box rather than the screen. Here the most selective constraint
//! drives an index seek and the rest filter the survivors.

use crate::id::EntityId;
use crate::model::prop;
use crate::op::Value;

// ---- the grammar ------------------------------------------------------

/// What one token of the grammar is, before the box is consulted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TermOp {
    Equals,
    NotEquals,
    AtMost,
    Has,
    No,
    Is,
    /// A bare word, or anything unreadable. A REQUIRED word, never
    /// dropped (owner, 2026-08-27: *"typo shows nothing"*).
    Text,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Term {
    pub op: TermOp,
    /// The property name as typed, with any leading `-` removed.
    pub key: String,
    pub value: String,
    /// The token respelled canonically, so joining a term list reproduces
    /// a query the parser reads back the same way.
    pub raw: String,
}

/// Split a raw query into terms. No box, no resolution, no opinion about
/// whether a property exists.
pub fn lex(raw: &str) -> Vec<Term> {
    tokenize(raw).iter().map(|t| classify(t)).collect()
}

fn classify(token: &str) -> Term {
    if let Some((key, val)) = split_qualifier(token, ':') {
        let (op, key) = match key {
            "is" => (TermOp::Is, key),
            "has" => (TermOp::Has, key),
            "no" => (TermOp::No, key),
            _ => match key.strip_prefix('-') {
                Some(bare) => (TermOp::NotEquals, bare),
                None => (TermOp::Equals, key),
            },
        };
        return Term { raw: spell(&op, key, val), op, key: key.to_owned(), value: val.to_owned() };
    }
    if let Some((key, val)) = split_qualifier(token, '<') {
        return Term {
            raw: format!("{key}<{val}"),
            op: TermOp::AtMost,
            key: key.to_owned(),
            value: val.to_owned(),
        };
    }
    Term { op: TermOp::Text, key: String::new(), value: token.to_owned(), raw: token.to_owned() }
}

/// `key:value`, and where the quotes go when something carries a space.
///
/// The VALUE is quoted — `people:"Anna Karlsson"`. A key with a space is
/// the odd case, and there the WHOLE term is quoted instead, minus
/// included: `"valid until:friday"`. Either way the tokeniser strips the
/// quotes and keeps the spaces, so both arrive as one token and split
/// correctly.
fn spell(op: &TermOp, key: &str, value: &str) -> String {
    let minus = if *op == TermOp::NotEquals { "-" } else { "" };
    if key.contains(' ') {
        return format!("\"{minus}{key}:{value}\"");
    }
    if value.contains(' ') {
        return format!("{minus}{key}:\"{value}\"");
    }
    format!("{minus}{key}:{value}")
}

fn tokenize(raw: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut quoted = false;
    for c in raw.chars() {
        match c {
            '"' => quoted = !quoted,
            c if c.is_whitespace() && !quoted => {
                if !current.is_empty() {
                    out.push(std::mem::take(&mut current));
                }
            }
            c => current.push(c),
        }
    }
    if !current.is_empty() {
        out.push(current);
    }
    out
}

/// Split a token at the first `sep` into a non-empty (key, value). `None`
/// when either side is empty, so `key:` — a key the user is still typing —
/// degrades to free text rather than a half-qualifier.
///
/// **It does NOT rescue a bare URL**, and the comment this inherited said
/// it did. `http://example.com` splits happily into `http` and
/// `//example.com`, because both halves are non-empty. That is correct
/// here and fixed one layer up: a qualifier whose key names no property
/// falls back to the whole token as free text, which is where "does this
/// exist" is answerable at all. A lexer that guessed at schemes would be
/// the lexer having an opinion about the box.
fn split_qualifier(token: &str, sep: char) -> Option<(&str, &str)> {
    let (key, val) = token.split_once(sep)?;
    if key.is_empty() || val.is_empty() {
        None
    } else {
        Some((key, val))
    }
}

// ---- the question -----------------------------------------------------

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Query {
    /// All constraints must hold — a conjunction.
    pub constraints: Vec<Constraint>,
    pub sort: Option<Sort>,
    /// Backstage plumbing (`working: true`) stays backstage by default.
    pub include_working: bool,
    /// The trash is its own perspective; queries see live things.
    pub include_trashed: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Constraint {
    pub property: EntityId,
    pub op: Op,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Op {
    /// At least one cell of the property equals the value. A multi-valued
    /// property matches on any of its cells.
    Equals(Value),
    /// No cell equals it. **Vacuously true when the property is absent**:
    /// a task with no status satisfies `status != done`.
    NotEquals(Value),
    /// At least one cell is present.
    Exists,
    /// No cell at all — stronger than `NotEquals`. "Still unstructured" is
    /// a Missing, not a NotEquals.
    Missing,
    /// At least one cell orders at or before the value. Grew out of
    /// Today: "everything due by tonight".
    AtMost(Value),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Sort {
    pub property: EntityId,
    pub descending: bool,
}

impl crate::engine::Engine {
    /// Everything the query admits, in a stable order.
    ///
    /// **The most selective constraint drives the read.** An `Equals` is
    /// an index seek (`cells_by_value`), so one is chosen to produce the
    /// candidates and the rest filter them. Only a query with no `Equals`
    /// at all falls back to reading every entity — which is what `core/`
    /// does for every query, and is why a snapshot cost the box.
    ///
    /// Stable: by the sort property, things missing it last, ties and the
    /// no-sort case by id, which for a v7 id is creation order.
    pub fn run(&self, query: &Query) -> Result<Vec<EntityId>, crate::log::LogError> {
        let candidates = match query.constraints.iter().find_map(|c| match &c.op {
            Op::Equals(v) => Some((c.property, v)),
            _ => None,
        }) {
            Some((prop, value)) => self.with_value(prop, value)?,
            None => self.all_entities()?,
        };

        let mut out = Vec::new();
        for id in candidates {
            if !query.include_trashed && self.is_trashed(id)? {
                continue;
            }
            if !query.include_working
                && matches!(self.one(id, prop::WORKING)?, Some(Value::Bool(true)))
            {
                continue;
            }
            let cells = self.cells_of(id)?;
            if query.constraints.iter().all(|c| satisfies(&cells, c)) {
                out.push(id);
            }
        }

        match &query.sort {
            None => out.sort(),
            Some(sort) => {
                let mut keyed: Vec<(Option<Value>, EntityId)> = Vec::with_capacity(out.len());
                for id in out {
                    keyed.push((self.one(id, sort.property)?, id));
                }
                keyed.sort_by(|(a, ai), (b, bi)| {
                    let ord = match (a, b) {
                        (Some(x), Some(y)) => {
                            let ord = compare(x, y);
                            // Only the VALUES reverse. Things missing the
                            // property sort last in either direction —
                            // "no due date" is not "the furthest future".
                            if sort.descending {
                                ord.reverse()
                            } else {
                                ord
                            }
                        }
                        (Some(_), None) => std::cmp::Ordering::Less,
                        (None, Some(_)) => std::cmp::Ordering::Greater,
                        (None, None) => std::cmp::Ordering::Equal,
                    };
                    ord.then_with(|| ai.cmp(bi))
                });
                out = keyed.into_iter().map(|(_, id)| id).collect();
            }
        }
        Ok(out)
    }
}

/// Does one entity's cells satisfy one constraint?
fn satisfies(cells: &[(EntityId, crate::id::Dot, Value)], c: &Constraint) -> bool {
    let mine = || cells.iter().filter(|(p, _, _)| *p == c.property);
    match &c.op {
        Op::Equals(want) => mine().any(|(_, _, v)| v == want),
        Op::NotEquals(want) => !mine().any(|(_, _, v)| v == want),
        Op::Exists => mine().next().is_some(),
        Op::Missing => mine().next().is_none(),
        Op::AtMost(want) => mine().any(|(_, _, v)| compare(v, want) != std::cmp::Ordering::Greater),
    }
}

/// Order two values of the same kind. Different kinds never compare —
/// they are not two points on one line — and answer Equal so a sort over a
/// mixed cell stays stable instead of inventing an order.
fn compare(a: &Value, b: &Value) -> std::cmp::Ordering {
    use std::cmp::Ordering;
    match (a, b) {
        (Value::Text(x), Value::Text(y)) => x.to_lowercase().cmp(&y.to_lowercase()),
        (Value::Number(x), Value::Number(y)) => x.partial_cmp(y).unwrap_or(Ordering::Equal),
        (Value::Bool(x), Value::Bool(y)) => x.cmp(y),
        (Value::Date(_), Value::Date(_)) => {
            // The same reading `cells.at_ms` uses, so a sort and a window
            // query put a floating day and a real instant in the same
            // order — one place decides what a date is worth.
            crate::view::at_ms(a).cmp(&crate::view::at_ms(b))
        }
        (Value::Ref(x), Value::Ref(y)) => x.0.cmp(&y.0),
        (Value::Blob(x), Value::Blob(y)) => x.cmp(y),
        _ => Ordering::Equal,
    }
}
