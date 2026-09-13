//! Search: resolving a typed query, ranking what it admits, and the
//! facets beside it.
//!
//! The GRAMMAR is the engine's (`liv_engine::query`) — one lexer, and it
//! knows nothing about any box. This is the half that does: turning a
//! lexed term into a constraint, scoring the survivors, and counting what
//! each facet value would yield.
//!
//! ## `is:archived` cannot mean one thing
//!
//! In a **workspace** it means *show me my archived things*; in a **search
//! box** it means *look in the archive too* (owner, 2026-08-27: "lens
//! means only, search means include"). Those are opposite filters over the
//! same token, so the grammar stays one and the CALLER says which job it
//! is doing. Getting this backwards makes a workspace called Archive show
//! everything plus the archive.
//!
//! ## A typo shows nothing
//!
//! Every free-text word is REQUIRED (owner, 2026-08-27). A query is an AND
//! over its terms, and a word that matches nothing anywhere drops the
//! candidate rather than being quietly ignored — because a search that
//! silently drops the word you misspelled shows you a confident list of
//! the wrong things.

use liv_engine::{
    kind, model, prop, query::TermOp, Constraint, DateSpec, Engine, EntityId, LogError, Query,
    QueryOp, Value,
};

use crate::words::{contains_word, starts_word};

/// Which job the query is doing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// A search box: the flags WIDEN what is looked at.
    Search,
    /// A workspace lens or a saved filter: the flags RESTRICT to it.
    Lens,
}

/// A parsed query: the free-text remainder, plus the structured question.
#[derive(Debug, Clone, Default)]
pub struct Search {
    /// Lowercased free-text words, ANDed.
    pub terms: Vec<String>,
    pub query: Query,
}

/// Where a term matched best, so a row can hint why it is here.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Field {
    Name,
    Cell,
    /// What the thing is filed UNDER — a select or a reference.
    Filed,
    Content,
    /// A pure-qualifier hit: no free-text word matched a field, because
    /// there were none to match.
    Structured,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Hit {
    pub id: EntityId,
    pub score: f32,
    pub field: Field,
}

// ---- resolving ---------------------------------------------------------

/// Parse for a search box.
pub fn parse(e: &Engine, raw: &str) -> Result<Search, LogError> {
    parse_mode(e, raw, Mode::Search)
}

/// Parse, saying which job it is for.
pub fn parse_mode(e: &Engine, raw: &str, mode: Mode) -> Result<Search, LogError> {
    let mut terms = Vec::new();
    let mut constraints = Vec::new();
    let mut include_working = false;
    let mut include_trashed = false;
    let mut include_archived = false;

    for term in liv_engine::lex(raw) {
        let lower = term.raw.to_lowercase();
        let (key, val) = (term.key.as_str(), term.value.as_str());
        match term.op {
            // THE FLAGS, and the one place Mode matters.
            TermOp::Is => match flag_prop(val) {
                Some((property, gate)) => {
                    if mode == Mode::Search && gate {
                        // A search WIDENS: lift the gate and add nothing.
                        match property {
                            p if p == prop::ARCHIVED => include_archived = true,
                            p if p == prop::TRASHED => include_trashed = true,
                            _ => include_working = true,
                        }
                    } else {
                        // A lens RESTRICTS — and a lens that asks for the
                        // archive must be shown it, so the gate is lifted
                        // AND the constraint narrows to it. One without
                        // the other is an empty screen.
                        match property {
                            p if p == prop::ARCHIVED => include_archived = true,
                            p if p == prop::TRASHED => include_trashed = true,
                            p if p == prop::WORKING => include_working = true,
                            _ => {}
                        }
                        constraints.push(Constraint {
                            property,
                            op: QueryOp::Equals(Value::Bool(true)),
                        });
                    }
                }
                None => terms.push(lower),
            },
            TermOp::Has => match property_named(e, val)? {
                Some(p) => constraints.push(Constraint { property: p, op: QueryOp::Exists }),
                None => terms.push(lower),
            },
            TermOp::No => match property_named(e, val)? {
                Some(p) => constraints.push(Constraint { property: p, op: QueryOp::Missing }),
                None => terms.push(lower),
            },
            TermOp::Equals | TermOp::NotEquals | TermOp::AtMost => {
                match resolve(e, key, val, &term.op)? {
                    Some(c) => constraints.push(c),
                    // **An unresolvable qualifier is words.** `http://x`
                    // lexes as `http` = `//example.com` and no property is
                    // called `http`; the whole token becomes a required
                    // free-text term, which is the only place that
                    // question is answerable.
                    None => terms.push(lower),
                }
            }
            TermOp::Text => terms.push(term.value.to_lowercase()),
        }
    }

    // **Archived is backstage by default.** Only things explicitly
    // archived are hidden — `NotEquals` is vacuously true where the cell
    // is absent, so everything that never took a position is still here.
    if !include_archived {
        constraints.push(Constraint {
            property: prop::ARCHIVED,
            op: QueryOp::NotEquals(Value::Bool(true)),
        });
    }

    Ok(Search {
        terms,
        query: Query { constraints, sort: None, include_working, include_trashed },
    })
}

/// `is:<flag>` → the flag's own bool property, and whether it is a GATE.
///
/// Three of the four are gates: they name something the query laws hide by
/// default, so a search asking for them has to lift a gate rather than add
/// a filter. `bookmarked` hides nothing, so it is an ordinary equality in
/// both modes.
fn flag_prop(flag: &str) -> Option<(EntityId, bool)> {
    Some(match flag {
        "archived" => (prop::ARCHIVED, true),
        "trashed" => (prop::TRASHED, true),
        "working" => (prop::WORKING, true),
        "bookmarked" => (prop::BOOKMARKED, false),
        _ => return None,
    })
}

/// A property by the name the user typed — compiled-in or declared.
fn property_named(e: &Engine, name: &str) -> Result<Option<EntityId>, LogError> {
    if let Some(def) = model::PROPS.iter().find(|d| d.name.eq_ignore_ascii_case(name)) {
        return Ok(Some(def.id));
    }
    for id in e.of_kind(kind::FIELD)? {
        if e.name(id)?.is_some_and(|n| n.eq_ignore_ascii_case(name)) {
            return Ok(Some(id));
        }
    }
    Ok(None)
}

fn resolve(
    e: &Engine,
    key: &str,
    raw: &str,
    op: &TermOp,
) -> Result<Option<Constraint>, LogError> {
    let Some(property) = property_named(e, key)? else { return Ok(None) };
    let Some(value) = value_for(e, property, raw)? else { return Ok(None) };
    Ok(Some(Constraint {
        property,
        op: match op {
            TermOp::NotEquals => QueryOp::NotEquals(value),
            TermOp::AtMost => QueryOp::AtMost(value),
            _ => QueryOp::Equals(value),
        },
    }))
}

/// What the user typed, as a value of the kind that property holds.
///
/// A reference resolves BY NAME — `kind:task` names the task kind, and
/// `area:work` the Work area — because a person types a word and an id is
/// never a name.
fn value_for(e: &Engine, property: EntityId, raw: &str) -> Result<Option<Value>, LogError> {
    let holds = match model::PROPS.iter().find(|d| d.id == property) {
        Some(def) => def.holds,
        None => match e.prop_shape(property)? {
            Some(shape) => shape.holds,
            None => return Ok(None),
        },
    };
    Ok(match holds {
        model::Holds::Text => Some(Value::Text(raw.to_owned())),
        model::Holds::Number => raw.parse().ok().map(Value::Number),
        model::Holds::Bool => match raw {
            "true" | "yes" => Some(Value::Bool(true)),
            "false" | "no" => Some(Value::Bool(false)),
            _ => None,
        },
        model::Holds::Date => iso_day(raw).map(|d| Value::Date(DateSpec::Day(d))),
        model::Holds::Ref | model::Holds::RefTo(_) => named_thing(e, raw)?.map(Value::Ref),
        model::Holds::Blob | model::Holds::Rich => None,
    })
}

/// The one thing in the box with that name, compiled-in furniture
/// included. `None` when nothing has it — and when more than one does,
/// which is a question the box cannot answer.
fn named_thing(e: &Engine, raw: &str) -> Result<Option<EntityId>, LogError> {
    let mut found = None;
    for id in model::ALL_KINDS.iter().chain(model::AREAS).chain(model::STATUSES) {
        if model::label(*id).is_some_and(|l| l.eq_ignore_ascii_case(raw)) {
            if found.is_some() {
                return Ok(None);
            }
            found = Some(*id);
        }
    }
    for id in e.with_value(prop::NAME, &Value::Text(raw.to_owned()))? {
        if found.is_some() {
            return Ok(None);
        }
        found = Some(id);
    }
    Ok(found)
}

fn iso_day(raw: &str) -> Option<i32> {
    let b = raw.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    Some(liv_engine::days_from_civil(
        raw[0..4].parse().ok()?,
        raw[5..7].parse().ok()?,
        raw[8..10].parse().ok()?,
    ))
}

// ---- ranking -----------------------------------------------------------

/// Run the structured question, then rank the survivors.
///
/// **Every free-text word is required.** A candidate is kept only if each
/// term matches SOME field; its score is the sum of each term's best field
/// weight. Ranked score-descending, then most-recently-touched, then id —
/// a total, stable order, so the same box searches to the same list.
///
/// A query with no free-text words is still a search: it returns the
/// structured answer in `run`'s own order.
pub fn search(e: &Engine, s: &Search, limit: usize) -> Result<Vec<Hit>, LogError> {
    let mut hits = Vec::new();
    for id in e.run(&s.query)? {
        let text = searchable(e, id)?;
        let mut score = 0.0f32;
        let mut best = -1.0f32;
        let mut field = Field::Structured;
        let mut all = true;
        for term in &s.terms {
            let (weight, matched) = score_term(&text, term);
            if weight <= 0.0 {
                all = false;
                break;
            }
            score += weight;
            if weight > best {
                best = weight;
                field = matched;
            }
        }
        if all {
            hits.push((e.touched(id)?, Hit { id, score, field }));
        }
    }

    // **Most recently EDITED first** among equal scores. `core/` builds a
    // monotonic sequence per entity with one pass over the whole history
    // for this, because a wall-clock `modified` ties across rapid edits.
    // Here the fold already maintains `touched_ms`, so the tiebreak is a
    // column read.
    hits.sort_by(|(ta, a), (tb, b)| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| tb.cmp(ta))
            .then_with(|| a.id.cmp(&b.id))
    });
    hits.truncate(limit);
    Ok(hits.into_iter().map(|(_, h)| h).collect())
}

/// The four tiers of text one thing offers a search.
///
/// **Number, date and bool stay out**, and that is the half of the old
/// rule worth keeping: it is what stops "2026" surfacing everything with a
/// due date. A filing is a short human label somebody chose; a timestamp
/// is not.
struct Searchable {
    name: String,
    cells: String,
    filed: String,
    content: String,
}

fn searchable(e: &Engine, id: EntityId) -> Result<Searchable, LogError> {
    let mut s = Searchable {
        name: String::new(),
        cells: String::new(),
        filed: String::new(),
        content: String::new(),
    };
    for (property, _, value) in e.cells_of(id)? {
        match (property, &value) {
            (p, Value::Text(t)) if p == prop::NAME => s.name = t.to_lowercase(),
            (p, Value::Rich(spans)) if p == prop::BODY => {
                s.content = liv_engine::rich::plain(spans).to_lowercase()
            }
            (_, Value::Text(t)) => push(&mut s.cells, &t.to_lowercase()),
            (_, Value::Rich(spans)) => {
                push(&mut s.cells, &liv_engine::rich::plain(spans).to_lowercase())
            }
            // A reference is filed-under, and it reads as the target's
            // name — the same string the chip on the row shows, which is
            // why typing a filing's words reaches the thing filed there.
            (_, Value::Ref(target)) => {
                let shown = e
                    .name(*target)?
                    .or_else(|| model::label(*target).map(str::to_owned))
                    .unwrap_or_default();
                push(&mut s.filed, &shown.to_lowercase());
            }
            _ => {}
        }
    }
    Ok(s)
}

fn push(bucket: &mut String, words: &str) {
    if words.is_empty() {
        return;
    }
    if !bucket.is_empty() {
        bucket.push(' ');
    }
    bucket.push_str(words);
}

/// One term's best field-match.
///
/// Whole name, then a leading prefix of the name, then a word-boundary
/// prefix inside it, then a whole word in another cell, then a
/// word-boundary PREFIX of something it is filed under, then a whole word
/// in the body.
///
/// **The filing tier takes a prefix and the body tier does not**, and that
/// is the point of having both: the owner's report was that typing "test"
/// did not reach a note filed under "Testjunk", and standing rule 5 says
/// nobody types `area:Testjunk` to fix that. A filing is a short label
/// reached by incremental typing; a body is long enough that a whole word
/// is the honest unit.
fn score_term(text: &Searchable, term: &str) -> (f32, Field) {
    if text.name == term {
        (100.0, Field::Name)
    } else if text.name.starts_with(term) {
        (60.0, Field::Name)
    } else if starts_word(&text.name, term) {
        (40.0, Field::Name)
    } else if contains_word(&text.cells, term) {
        (20.0, Field::Cell)
    } else if starts_word(&text.filed, term) {
        (15.0, Field::Filed)
    } else if contains_word(&text.content, term) {
        (10.0, Field::Content)
    } else {
        (0.0, Field::Structured)
    }
}

// ---- facets ------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub struct FacetValue {
    pub value: Value,
    pub label: String,
    /// How many things this query WOULD yield if this value were also
    /// required.
    pub count: usize,
    /// The query already includes it — the chip reads as chosen.
    pub active: bool,
    /// The query already excludes it. Include → exclude → off is the
    /// three-state cycle.
    pub excluded: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Facet {
    pub property: EntityId,
    pub label: String,
    pub values: Vec<FacetValue>,
}

/// What each value of one property would yield under the current filter.
///
/// **The count EXCLUDES this property's own constraints.** Without that, a
/// facet you have already picked shows its own count and nothing else, and
/// there is no way to pivot to a sibling — which is the one thing a facet
/// row is for.
pub fn facet(e: &Engine, s: &Search, property: EntityId) -> Result<Facet, LogError> {
    let mut base = s.query.clone();
    base.constraints.retain(|c| c.property != property);

    let own: Vec<&QueryOp> = s
        .query
        .constraints
        .iter()
        .filter(|c| c.property == property)
        .map(|c| &c.op)
        .collect();

    let mut values = Vec::new();
    for value in candidates(e, &base, property)? {
        let mut probe = base.clone();
        probe.constraints.push(Constraint {
            property,
            op: QueryOp::Equals(value.clone()),
        });
        let count = e.run(&probe)?.len();
        // A value nothing would yield is not a choice.
        if count == 0 {
            continue;
        }
        values.push(FacetValue {
            active: own.iter().any(|op| matches!(op, QueryOp::Equals(x) if *x == value)),
            excluded: own.iter().any(|op| matches!(op, QueryOp::NotEquals(x) if *x == value)),
            label: shown(e, &value)?,
            value,
            count,
        });
    }
    values.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| a.label.cmp(&b.label)));
    Ok(Facet {
        property,
        label: model::label(property).map(str::to_owned).unwrap_or_default(),
        values,
    })
}

/// Which properties are worth a chip row for this result: the kind, plus
/// every select-shaped property that actually appears on it. Drops facets
/// that would show nothing, and bounds the cost.
pub fn facet_properties(e: &Engine, s: &Search) -> Result<Vec<EntityId>, LogError> {
    let base = e.run(&s.query)?;
    let present = |property: EntityId| -> Result<bool, LogError> {
        for id in &base {
            if e.one(*id, property)?.is_some() {
                return Ok(true);
            }
        }
        Ok(false)
    };

    let mut out = Vec::new();
    if present(prop::KIND)? {
        out.push(prop::KIND);
    }
    for def in model::PROPS.iter() {
        if def.id == prop::KIND || !matches!(def.holds, model::Holds::RefTo(_)) {
            continue;
        }
        if present(def.id)? {
            out.push(def.id);
        }
    }
    for id in e.of_kind(kind::FIELD)? {
        if matches!(e.prop_shape(id)?, Some(shape) if matches!(shape.holds, model::Holds::RefTo(_)))
            && present(id)?
        {
            out.push(id);
        }
    }
    Ok(out)
}

fn candidates(
    e: &Engine,
    base: &Query,
    property: EntityId,
) -> Result<Vec<Value>, LogError> {
    let mut out: Vec<Value> = Vec::new();
    for id in e.run(base)? {
        for (_, v) in e.cell(id, property)? {
            if !out.contains(&v) {
                out.push(v);
            }
        }
    }
    Ok(out)
}

/// A value as the row shows it.
fn shown(e: &Engine, v: &Value) -> Result<String, LogError> {
    Ok(match v {
        Value::Text(t) => t.clone(),
        Value::Bool(b) => (if *b { "yes" } else { "no" }).to_owned(),
        Value::Number(n) => format!("{n}"),
        Value::Ref(target) => e
            .name(*target)?
            .or_else(|| model::label(*target).map(str::to_owned))
            .unwrap_or_default(),
        _ => String::new(),
    })
}
