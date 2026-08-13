//! Search as navigation (P6). A thin scored pass layered on `run`: the
//! query DSL splits a raw string into structured *qualifiers* (Constraints
//! that `run` interprets) and free-text *terms* (a ranking pass over the
//! survivors). `run` and `Op` stay pure and exact; tokenization and ranking
//! live here. Searchable text is `views::display`-flattened, so search sees
//! exactly what the shell renders — a wiki-linked `[[Anna]]` (a Ref span)
//! is findable by "anna" because display resolves the reference to a name.

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;

use liv_core::{props, Entity, Id, Store, Value};
use liv_views::display;

use crate::clerk::{contains_word, starts_word};
use crate::content::parse_value;
use crate::{property_id, run, Constraint, Op, Query};

/// One ranked result. `score` orders hits (higher first); `field` records
/// where the best match landed so the shell can hint why it matched.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hit {
    pub id: Id,
    pub score: f32,
    pub field: MatchField,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MatchField {
    Name,
    Cell,
    Content,
    /// A pure-qualifier hit — no free-text term matched a field.
    Structured,
}

/// A parsed query: the free-text remainder plus the structured `Query` that
/// `run` interprets. `parse` is the single source of truth — the shell ships
/// the raw string; the DSL is never re-parsed anywhere else.
#[derive(Debug, Clone, Default)]
pub struct SearchQuery {
    /// Lowercased free-text words, ANDed.
    pub terms: Vec<String>,
    /// Qualifier-derived constraints + the gate flags.
    pub query: Query,
}

/// One candidate facet value and how many results it *would* yield under the
/// current filter — Liv's one great idea, as a number. `active` marks a value
/// the current query already constrains this property to.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FacetValue {
    pub value: Value,
    pub label: String,
    pub count: usize,
    /// The current query INCLUDES this value (Op::Equals) — renders accent.
    pub active: bool,
    /// The current query EXCLUDES this value (Op::NotEquals) — renders red +
    /// strikethrough. include→exclude→off is the three-state cycle (bp3 a19).
    pub excluded: bool,
}

/// All candidate values for one facetable property, ready to render as a chip
/// row — count-descending, zero-count values dropped.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Facet {
    pub property: Id,
    pub label: String,
    pub values: Vec<FacetValue>,
}

/// Parse a raw DSL string into free-text terms + a structured Query.
///
/// Qualifiers: `key:value` (Equals), `key<value` (AtMost, dates), `is:flag`
/// (archived/trashed/working gates), `has:key` (Exists), `no:key` (Missing).
/// Keys resolve through `property_id`; a `reference` key's value resolves by
/// entity name (so `type:task` finds the type named "task"), everything else
/// through the shared `parse_value`. An unrecognized or unparseable qualifier
/// demotes to a free-text word — a search never errors on a typo. Archived is
/// excluded by default (a `NotEquals(true)` the base query carries) unless
/// `is:archived` asks for it.
pub fn parse(store: &Store, raw: &str) -> SearchQuery {
    let mut terms = Vec::new();
    let mut constraints = Vec::new();
    let mut include_working = false;
    let mut include_trashed = false;
    let mut include_archived = false;

    for token in tokenize(raw) {
        let token = token.as_str();
        let lower = token.to_lowercase();
        if let Some((key, val)) = split_qualifier(token, ':') {
            match key {
                "is" => match val {
                    "archived" => include_archived = true,
                    "trashed" => include_trashed = true,
                    "working" => include_working = true,
                    _ => terms.push(lower),
                },
                "has" => match property_id(store, val) {
                    Some(p) => constraints.push(Constraint { property: p, op: Op::Exists }),
                    None => terms.push(lower),
                },
                "no" => match property_id(store, val) {
                    Some(p) => constraints.push(Constraint { property: p, op: Op::Missing }),
                    None => terms.push(lower),
                },
                // A leading '-' on a property qualifier EXCLUDES it
                // (bp3 a17): `-object:contact` → Op::NotEquals. is/has/no
                // do not take the prefix — a '-is:'/'-has:' demotes to text.
                _ => {
                    let constraint = match key.strip_prefix('-') {
                        Some(bare) => not_equals_constraint(store, bare, val),
                        None => equals_constraint(store, key, val),
                    };
                    match constraint {
                        Some(c) => constraints.push(c),
                        None => terms.push(lower),
                    }
                }
            }
        } else if let Some((key, val)) = split_qualifier(token, '<') {
            match at_most_constraint(store, key, val) {
                Some(c) => constraints.push(c),
                None => terms.push(lower),
            }
        } else {
            terms.push(lower);
        }
    }

    // Archived is backstage by default: only entities explicitly archived
    // are hidden (NotEquals is vacuously true where the cell is absent).
    if !include_archived {
        if let Some(archived) = property_id(store, "archived") {
            constraints.push(Constraint {
                property: archived,
                op: Op::NotEquals(Value::Bool(true)),
            });
        }
    }

    SearchQuery {
        terms,
        query: Query {
            constraints,
            sort: None,
            include_working,
            include_trashed,
        },
    }
}

/// The search: `run` the structured query, then score each survivor's
/// searchable text against the free-text terms. A candidate is kept only if
/// *every* term matches some field (AND); its score is the sum of per-term
/// best-field weights. Ranked score-desc, then newest-created, then id (a
/// total, stable order). Empty terms yield the structured result in `run`'s
/// own order — a pure-qualifier query is still a search.
///
/// `extracted` supplies a file entity's cached foreign text (a PDF's words),
/// folded into the CONTENT tier — the search corpus extended over files
/// WITHOUT any cell being written to the log. The caller (which knows the
/// box path) reads the cache and passes it in; `search.rs` never touches the
/// filesystem. A non-file entity yields `""`.
pub fn search<F: Fn(&Entity) -> String>(
    store: &Store,
    sq: &SearchQuery,
    limit: usize,
    extracted: F,
) -> Vec<Hit> {
    let mut hits: Vec<Hit> = Vec::new();
    for id in run(store, &sq.query) {
        let Some(entity) = store.get(id) else { continue };
        let text = searchable(store, entity, &extracted(entity));

        let mut score = 0.0f32;
        let mut best_weight = -1.0f32;
        let mut field = MatchField::Structured;
        let mut all = true;
        for term in &sq.terms {
            let (weight, matched) = score_term(&text, term);
            if weight <= 0.0 {
                all = false;
                break;
            }
            score += weight;
            if weight > best_weight {
                best_weight = weight;
                field = matched;
            }
        }
        if all {
            hits.push(Hit { id, score, field });
        }
    }

    // Recency tiebreak (bp3 a10): most-recently-EDITED first. One O(history)
    // pass builds a monotonic seq per entity — wall-clock `modified` ties
    // across rapid edits and cannot order recents.
    let recency = store.recency();
    let seq = |id: Id| recency.get(&id).copied().unwrap_or(0);
    hits.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(Ordering::Equal)
            .then_with(|| seq(b.id).cmp(&seq(a.id)))
            .then_with(|| a.id.cmp(&b.id))
    });
    hits.truncate(limit);
    hits
}

/// Facet counts for one property under the current filter: for each
/// candidate value, the hypothetical result size if that value were also
/// required. Counts *exclude self* — the base drops this property's own
/// constraints — so an already-picked facet still shows its siblings and
/// you can pivot. Zero-count values are dropped; the rest sort count-desc.
pub fn facet(store: &Store, sq: &SearchQuery, property: Id) -> Facet {
    // The base minus this property's constraints, so sibling values stay
    // visible and countable.
    let mut base = sq.query.clone();
    base.constraints.retain(|c| c.property != property);

    let own: Vec<&Op> = sq
        .query
        .constraints
        .iter()
        .filter(|c| c.property == property)
        .map(|c| &c.op)
        .collect();
    let is_active = |v: &Value| own.iter().any(|op| matches!(op, Op::Equals(x) if x == v));
    let is_excluded = |v: &Value| own.iter().any(|op| matches!(op, Op::NotEquals(x) if x == v));

    let mut values = Vec::new();
    for value in candidate_values(store, &base, property) {
        let mut probe = base.clone();
        probe.constraints.push(Constraint { property, op: Op::Equals(value.clone()) });
        let count = run(store, &probe).len();
        if count == 0 {
            continue;
        }
        values.push(FacetValue {
            active: is_active(&value),
            excluded: is_excluded(&value),
            label: display(store, &value),
            value,
            count,
        });
    }
    values.sort_by(|a, b| b.count.cmp(&a.count));
    Facet { property, label: property_name(store, property), values }
}

/// Which properties are worth faceting for the current result: the reserved
/// TYPE reference plus every select-kind property, kept only when it actually
/// appears on the base result. Bounds the O(values × entities) cost and drops
/// facets that would show nothing.
pub fn facet_properties(store: &Store, sq: &SearchQuery) -> Vec<Id> {
    let base = run(store, &sq.query);
    let present = |property: Id| {
        base.iter()
            .any(|id| store.get(*id).is_some_and(|e| e.all(property).next().is_some()))
    };

    let mut out = Vec::new();
    if present(props::TYPE) {
        out.push(props::TYPE);
    }
    for e in store.entities() {
        if e.id == props::TYPE || out.contains(&e.id) {
            continue;
        }
        let is_select = matches!(e.get(props::VALUE_KIND), Some(Value::Text(k)) if k == "select");
        if is_select && present(e.id) {
            out.push(e.id);
        }
    }
    out
}

/// How many live entities carry at least one cell of each user property —
/// the "on 12 objects" count in the add-property picker (bp1 e13) and the
/// property table. Every user definition appears, zeros included (the
/// picker still offers an unused property); working entities and the trash
/// are excluded, the query laws. Deterministic: sorted by definition id.
pub fn usage_counts(store: &Store) -> Vec<(Id, usize)> {
    use std::collections::{HashMap, HashSet};
    // One pass over live cells — O(total cells), never definitions ×
    // entities (the review measured the nested walk at ~150× the one-pass
    // shape, on the snapshot hot path). Each entity counts once per
    // distinct property it carries.
    let mut carriers: HashMap<Id, usize> = HashMap::new();
    for e in store
        .user_entities()
    {
        let mut seen: HashSet<Id> = HashSet::new();
        for cell in &e.cells {
            if seen.insert(cell.property) {
                *carriers.entry(cell.property).or_insert(0) += 1;
            }
        }
    }
    let mut counts: Vec<(Id, usize)> = store
        .entities()
        .filter(|e| {
            e.id >= props::FIRST_USER_ID
                && !e.trashed
                && matches!(e.get(props::VALUE_KIND), Some(Value::Text(_)))
        })
        .map(|e| (e.id, carriers.get(&e.id).copied().unwrap_or(0)))
        .collect();
    counts.sort_by_key(|(id, _)| *id);
    counts
}

/// The distinct values of a property across the live set, each with its
/// carrier count, deterministically ordered (count desc, then display) —
/// layer 1 of the value pool (bp1 e9: "values in this vault, with usage
/// counts") and the status picker's per-option counts. The facet-internal
/// candidate walk, promoted and counted — never a parallel engine.
pub fn distinct_values(store: &Store, property: Id) -> Vec<(Value, usize)> {
    use std::collections::HashMap;
    // Reads resolve through redirects (the merge law): a survivor and its
    // merged-away loser are ONE value, never a split pool row.
    let canonical = |v: &Value| -> Value {
        match v {
            Value::Reference(id) => Value::Reference(store.resolve(*id)),
            Value::Select(id) => Value::Select(store.resolve(*id)),
            other => other.clone(),
        }
    };
    // Dedup by serialized identity — O(1) per cell (the review measured the
    // per-cell linear scan at 339ms on a 10k-distinct text property, inside
    // the box lock). A NaN that serde refuses buckets under "" — one bucket,
    // and the seam refuses new NaNs anyway.
    let mut counts: HashMap<String, (Value, usize)> = HashMap::new();
    for e in store
        .user_entities()
    {
        for value in e.all(property) {
            let value = canonical(value);
            let key = serde_json::to_string(&value).unwrap_or_default();
            counts.entry(key).and_modify(|(_, c)| *c += 1).or_insert((value, 1));
        }
    }
    // Sort on precomputed keys — display() once per value, never per
    // comparison.
    let mut out: Vec<(Value, usize, String)> = counts
        .into_values()
        .map(|(value, count)| {
            let shown = display(store, &value);
            (value, count, shown)
        })
        .collect();
    out.sort_by(|(_, ca, da), (_, cb, db)| cb.cmp(ca).then_with(|| da.cmp(db)));
    out.into_iter().map(|(value, count, _)| (value, count)).collect()
}

/// The distinct values of a property across a query's result — the candidate
/// universe for a facet, so values absent from the current result never show.
fn candidate_values(store: &Store, base: &Query, property: Id) -> Vec<Value> {
    let mut seen: Vec<Value> = Vec::new();
    for id in run(store, base) {
        let Some(entity) = store.get(id) else { continue };
        for value in entity.all(property) {
            if !seen.contains(value) {
                seen.push(value.clone());
            }
        }
    }
    seen
}

fn property_name(store: &Store, property: Id) -> String {
    match store.get(property).and_then(|e| e.get(props::NAME)) {
        Some(Value::Text(name)) => name.clone(),
        _ => format!("#{property}"),
    }
}

/// The searchable text of an entity, per field, `display`-flattened and
/// lowercased. `cells` is every *other* Text/RichText cell — structured
/// kinds (Number/DateTime/Bool/Select/Reference) are reached through
/// qualifiers, never as incidental text.
struct Searchable {
    name: String,
    cells: String,
    content: String,
}

fn searchable(store: &Store, entity: &Entity, extracted: &str) -> Searchable {
    let flatten = |v: &Value| display(store, v).to_lowercase();
    let name = entity.get(props::NAME).map(flatten).unwrap_or_default();
    let mut content = entity.get(props::CONTENT).map(flatten).unwrap_or_default();

    // A file's cached extracted text joins the CONTENT tier — a PDF is
    // findable by its words, scored like body text, never a stored cell.
    if !extracted.is_empty() {
        if !content.is_empty() {
            content.push(' ');
        }
        content.push_str(&extracted.to_lowercase());
    }

    let mut cells = String::new();
    for cell in &entity.cells {
        if cell.property == props::NAME || cell.property == props::CONTENT {
            continue;
        }
        if matches!(cell.value, Value::Text(_) | Value::RichText(_)) {
            if !cells.is_empty() {
                cells.push(' ');
            }
            cells.push_str(&flatten(&cell.value));
        }
    }
    Searchable { name, cells, content }
}

/// One term's best field-match: whole-name equality > leading name prefix >
/// a word-boundary prefix inside the name > a whole word in another cell >
/// a whole word in the content body. Weight 0 = no match anywhere.
fn score_term(text: &Searchable, term: &str) -> (f32, MatchField) {
    if text.name == term {
        (100.0, MatchField::Name)
    } else if text.name.starts_with(term) {
        (60.0, MatchField::Name)
    } else if starts_word(&text.name, term) {
        (40.0, MatchField::Name)
    } else if contains_word(&text.cells, term) {
        (20.0, MatchField::Cell)
    } else if contains_word(&text.content, term) {
        (10.0, MatchField::Content)
    } else {
        (0.0, MatchField::Structured)
    }
}

/// Split a token at the first `sep` into a non-empty (key, value). Returns
/// None when either side is empty, so a bare "http://x" or "key:" degrades
/// to free text rather than a half-qualifier.
/// Whitespace tokens — except that a double-quoted run keeps its spaces:
/// `people:"Anna Karlsson"` is ONE token, `people:Anna Karlsson`, quotes
/// stripped. The chip-click contract depends on it (the P11.5 review's
/// live-reproduced high: without quoting, multi-word values split into a
/// half-qualifier plus junk free-text terms). An unclosed quote runs
/// tolerantly to the end of the input.
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

fn split_qualifier(token: &str, sep: char) -> Option<(&str, &str)> {
    let (key, val) = token.split_once(sep)?;
    if key.is_empty() || val.is_empty() {
        None
    } else {
        Some((key, val))
    }
}

/// `key:value` → an Equals constraint. A `reference` key resolves its value
/// by entity name (`type:task`); every other kind through `parse_value`.
fn equals_constraint(store: &Store, key: &str, val: &str) -> Option<Constraint> {
    let property = property_id(store, key)?;
    let value = qualifier_value(store, property, val)?;
    Some(Constraint { property, op: Op::Equals(value) })
}

/// `-key:value` → a NotEquals constraint (exclude). Same resolution as
/// `equals_constraint`; Op::NotEquals already exists and is evaluated by
/// `satisfies` (vacuously true where the cell is absent), so a user
/// exclusion rides the identical path the archived gate already proves.
fn not_equals_constraint(store: &Store, key: &str, val: &str) -> Option<Constraint> {
    let property = property_id(store, key)?;
    let value = qualifier_value(store, property, val)?;
    Some(Constraint { property, op: Op::NotEquals(value) })
}

/// `key<value` → an AtMost constraint (dates: "due at or before"). Only the
/// `≤` direction exists in `Op`; `>` / `after:` is deferred.
fn at_most_constraint(store: &Store, key: &str, val: &str) -> Option<Constraint> {
    let property = property_id(store, key)?;
    let value = qualifier_value(store, property, val)?;
    Some(Constraint { property, op: Op::AtMost(value) })
}

fn qualifier_value(store: &Store, property: Id, raw: &str) -> Option<Value> {
    match property_kind(store, property)?.as_str() {
        "reference" => resolve_reference(store, raw),
        kind => parse_value(store, property, kind, raw).ok(),
    }
}

/// A property's declared value-kind, read from its definition — the same
/// VALUE_KIND cell `set_property` keys on.
fn property_kind(store: &Store, property: Id) -> Option<String> {
    match store.get(property)?.get(props::VALUE_KIND) {
        Some(Value::Text(kind)) => Some(kind.clone()),
        _ => None,
    }
}

/// Resolve a reference qualifier's value by entity name (case-insensitive):
/// `type:task` → the id of the type named "task". `entities()` is a HashMap
/// in no particular order, so on a name collision we take the LOWEST id —
/// deterministic (the same box always resolves the same), and it biases
/// toward the low-id seeded types over a later same-named note, which is
/// what `type:` wants. Mirrors `run`'s sort-by-id tiebreak.
fn resolve_reference(store: &Store, raw: &str) -> Option<Value> {
    let wanted = raw.to_lowercase();
    store
        .entities()
        .filter(|e| !e.trashed)
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(name)) if name.to_lowercase() == wanted)
        })
        .min_by_key(|e| e.id)
        .map(|e| Value::Reference(e.id))
}
