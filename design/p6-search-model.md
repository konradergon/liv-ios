# P6 Search Model — service + DSL + facets + in-place shell

Decided against the shipped tree (`services/src/lib.rs`, `clerk.rs`,
`content.rs`, `views/src/lib.rs`, `ffi/src/lib.rs`,
`shell/macos/Sources/Window.swift`). Search is **navigation, not an
overlay** (interface.md 0.2; feature-map #27). Liv's 4,251-line
QuickSwitcher is **not ported**; its one genuinely great idea — facet
counts as *hypothetical result sizes under the current filter* — is,
as a service helper.

## 1 · The four load-bearing decisions

1. **Text match is a separate scored pass over `run()`'s result — not a
   new `Op`.** `Op` (lib.rs) is five exact-match variants
   (`Equals/NotEquals/Exists/Missing/AtMost`); `satisfies()` is a per-kind
   equality matcher. The DSL splits a raw string into **qualifiers** (→
   `Constraint`s, run by `run()`) and **free-text terms** (→ a scoring
   pass over the survivors). `run()` and `Op` stay pure and exact.

2. **Searchable text comes from `views::display`, not a hand-rolled
   flatten.** `display(store,&Value)` resolves a `Ref` span to the
   target's NAME, so a wiki-linked `[[Anna]]` is findable by "anna" —
   search sees exactly what the shell renders. Free text matches only
   **NAME + CONTENT + other Text/RichText cells**; structured kinds
   (Number/DateTime/Bool/Select/Reference) are reached through
   qualifiers, never as incidental text (so "2026" does not surface
   every due date).

3. **One word-boundary primitive, shared.** `clerk::contains_word`
   ("anna" matches "call anna friday", not "susanna") becomes `pub`;
   both clerk and search call it. Search adds `starts_word` (prefix, for
   incremental-typing feel), scored below whole-word.

4. **Facet counts are `run()` re-run with one extra constraint.** For a
   candidate value `v` of property `P`, `count = run(base +
   Constraint{P, Equals(v)}).len()` — literally the hypothetical result
   size under the current filter. The idiom `today_sections` and
   `build_snapshot` already use. O(values × entities) linear scan, fine
   at single-user scale — no index in P6 (matches `run()`'s stance:
   "an index earns its place when a measurement demands it").

**Defaults:** search inherits `run()`'s gates —
`include_working:false`, `include_trashed:false` — so property
definitions, status options and workspaces never surface. Archived is
excluded by default (a `Constraint{archived, NotEquals(Bool(true))}` the
base query carries) and re-included on demand via `is:archived`
(feature-map #9 parity).

## 2 · The Rust service — `services/src/search.rs`

### 2.1 Types

```rust
pub struct Hit { pub id: Id, pub score: f32, pub field: MatchField }
pub enum MatchField { Name, Cell, Content, Structured }

pub struct FacetValue { pub value: Value, pub label: String,
                        pub count: usize, pub active: bool }
pub struct Facet { pub property: Id, pub label: String,
                   pub values: Vec<FacetValue> }   // count-desc, 0 dropped

pub struct SearchQuery { pub terms: Vec<String>, pub query: Query }
```

### 2.2 Functions

```rust
pub fn parse(store: &Store, raw: &str) -> SearchQuery;
pub fn search(store: &Store, sq: &SearchQuery, limit: usize) -> Vec<Hit>;
pub fn facet(store: &Store, sq: &SearchQuery, property: Id) -> Facet;
pub fn facet_properties(store: &Store, sq: &SearchQuery) -> Vec<Id>;
// internal: searchable(store,&Entity)->Searchable{name,cells,content};
//           candidate_values(store,&sq,property)->Vec<Value>
```

### 2.3 Pipeline

```
raw ─ parse ─→ SearchQuery{terms, query}
             run(store,&query)            structured candidate ids (gates+qualifiers)
             for each candidate e:
                 s = searchable(store,e)  // display()-flattened
                 score each term over s.name / s.cells / s.content
                 keep e iff EVERY term matches somewhere (AND)
                 hit.score = Σ best-per-term tier; hit.field = best overall
             sort score desc, then CREATED desc, then id (stable), truncate
```
Empty terms ⇒ the structured result in `run()`'s order (a pure-qualifier
query is still a search).

### 2.4 Edits to existing files (shared primitives)

- `clerk.rs` — `contains_word` → `pub`; add `pub fn starts_word` (prefix
  at a word boundary). Lowercase at the call site (clerk convention).
- `content.rs` — `parse_value`, `parse_civil` → `pub`. The DSL parses
  `status:done`, `due:2026-07-08` through the **same** kind-aware path
  `set` uses — one parser, three shells.
- No change to `run`, `Op`, `Query`, `satisfies`, `display`.

## 3 · The query DSL

```
token := qualifier | word
qualifier := key ':' value        type:task   status:done   due:2026-07-08
           | key '<' value        due<2026-07-10          (→ AtMost)
           | 'is' ':' flag        is:archived  is:trashed  is:working
           | 'has' ':' key        has:status  (→ Exists)
           | 'no'  ':' key        no:status   (→ Missing)
key   := bare single-word property name (property_id; multi-word ⇒ free text)
value := bareword | '"' phrase '"'
word  := free-text term (ANDed)
```

**Robustness:** an unrecognized key (`property_id` → `None`) demotes the
whole token to a free-text word — a search never errors on a typo.
`>` / `after:` is **deferred** (no `Op::AtLeast` today; a one-line
amendment when measured). v0 ships `<`/`≤` only.

## 4 · Ranking tiers

Per term, the **best** field-match sets that term's contribution; the
hit's total is the sum; ties break by CREATED desc, then id.

| Tier | Condition | Weight |
|---|---|---|
| 1 | term == whole NAME (case-folded equality) | 100 |
| 2 | NAME starts_word term (prefix) | 60 |
| 3 | NAME contains_word term (mid-name whole word) | 40 |
| 4 | another Text/RichText cell contains_word term | 20 |
| 5 | CONTENT body contains_word term | 10 |
| — | no field matches term ⇒ entity dropped (AND) | |

No AI rerank — that is the P13 answerer door.

## 5 · Facet counts (Liv's one great idea, natively)

For each candidate value of a facetable property, clone the base query,
push `Constraint{property, Equals(value)}`, and `run().len()`. Drop
zero-count values; sort count-desc; mark `active` when the base query
already constrains that property to that value. Candidate universe =
distinct values **present in the current base result** (Select facets
intersect the definition's `OPTIONS`), so zero-count facets vanish as
the filter narrows — true "hypothetical size under the current filter."
`facet_properties` bounds cost to Select properties + reserved `TYPE`
that actually vary across the base result.

## 6 · The C seam

One new read-only function, mirroring `lotus_snapshot`
(open_swept → build → drop → into_raw). Search is query-driven and
debounced; it must not ride or invalidate the cached snapshot, and needs
a rank order the snapshot's fixed section arrays cannot carry.

```c
// Ranked hits + facet counts for a raw DSL query, as JSON.
// malloc'd string, free with lotus_string_free. Null on failure.
char *lotus_search_at(const char *path, const char *raw_query);
```

The shell ships the **raw DSL string only** — Rust is the single parser.
Response (bare ids: the shell reuses its existing `EntityRow`/`model.rows`
map — no new row type, no preview payload):

```json
{ "hits":   [ {"id":4131,"score":100.0,"field":"name"} ],
  "facets": [ {"property":2,"label":"Type","values":[
                {"value":{"Reference":4100},"label":"Task","count":12,"active":false} ]} ] }
```

## 7 · The Swift shell

The "field at the top of the sidebar, results in place" scaffolding
largely exists (`query` @State, `searchFocused` FocusState, the
`!query.isEmpty` branch swaps `ResultsView` into `deskContent`,
`.lotusFocusSearch`). P6 wires the data source; builds no overlay.

- **⌘F field** atop the sidebar (above `SurfaceNav`, reachable from every
  surface) bound to the existing `query`/`searchFocused`. Repoint
  `.lotusFocusSearch` and `SidebarHeader`'s search action to focus it
  (decoupled from `WorkspaceSwitcher`, which stays a workspace picker).
- **`BoxModel.search`** — a read-returning method modeled on `refresh()`:
  `lotus_search_at` on `boxQueue`, decode, publish `@Published
  searchResult`. Debounce (~150ms cancelable `Task` on `query` change)
  before the box hop so keystrokes don't thrash the lock.
- **`ResultsView` reworked** — same shape (LensHeader "N matches" +
  `ForEach(EntityLine)` + empty state) but driven by
  `searchResult.hits` in rank order via `model.rows`; the client-side
  `.filter` is deleted. `EntityLine` reused verbatim.
- **Native facet chips** above the list — a horizontal row of native
  chips (the `pickerStrip` idiom, lake-green, NOT Liv's rainbow), each
  value showing its hypothetical `count`. Parse-first: clicking a value
  splices/removes its `key:value` token in the `query` string, so field
  and chips are one source of truth.

## 8 · Slice plan (each an independent commit: build → tests → review → fix)

- **6a — the core search service (pure Rust, the spine).**
  `services/src/search.rs`: `Hit`/`MatchField`/`SearchQuery`, `parse`,
  `search`, the ranking tiers, `searchable` via `views::display`. Make
  `contains_word` `pub` + add `starts_word`; `parse_value`/`parse_civil`
  `pub`. Unit tests: ranking order (name-eq > prefix > substring > cell >
  content); AND-of-terms; wiki-link found by target name through
  `display`; gates exclude working/trashed; archived excluded by default,
  `is:archived` includes; qualifier `type:`/`status:`/`due<` build the
  right `Constraint`s; a typo'd qualifier demotes to free text. No FFI,
  no shell.

- **6b — facet counts + the C seam.** `Facet`/`FacetValue`, `facet`,
  `facet_properties`, `candidate_values`; `lotus_search_at` +
  `build_search` assembling `{hits, facets}`. Tests: count ==
  `run(base+Equals(v)).len()`; adding a facet constraint never grows the
  count; zero-count dropped; FFI round-trip (raw string → JSON).

- **6c — the shell field + results in place.** `SearchField` atop the
  sidebar; repoint `.lotusFocusSearch`/`SidebarHeader`; debounced
  `BoxModel.search` + `@Published searchResult`; rework `ResultsView` to
  render ranked hits via `model.rows` (drop the `.filter`).

- **6d — native facet chips (parse-first).** Render `searchResult.facets`
  as a native chip row; clicking splices/removes the `key:value` token.
  *(May merge with 6c if small — prefer 4 slices.)*

## 9 · Deferred (noted, not in P6)

FTS/SQLite index · AI/smart rerank (P13) · extracted foreign-file text
(P7/P12) · the overlay/palette, Preview/Context modes, ResultPreviewPane,
drag-to-list, connectors/`in:Vault` · saved searches #28 (fast-follow: a
`props::QUERY` text cell via `lotus_set_at` + the bookmark verb; `parse`
unblocks it) · date `>`/`after:` (needs `Op::AtLeast`) · exclude-facet
`no:`/`!` cycle · multi-word qualifier keys.
