# P11 Spine Model — the amended spine is three seed passes, one struct field, and one anchor rule: date roles are seeded *properties* (`due` becomes one of five), a span is an optional `end` inside the DateTime value, recurrence anchors on the positioning set, and status scopes by `for-type` cells on the option entities it already has

Building on the shipped tree (`services/src/{lib,content,recurrence,search}.rs`,
`ffi/src/lib.rs`, `core/src/{value,entity}.rs`) and the substrate P1–P10 laid
down. P11 is **THE AMENDED SPINE** (blueprint-assessment.md §2.1, §4): the
core/services/FFI substrate for R1 (role-typed dates: calendar / valid-until /
occurred / purchased-on, start + optional end spans, recurrence on ANY dated
object) and R2 (universal status: ONE property, per-kind user vocabularies as
option entities carrying scope + order + hue). **It is core-only.** No shell
file changes. The single allowed visible effect is the calendar quietly
re-basing: an entity carrying a calendar-role `date` cell starts rendering on
the month grid through the *existing* snapshot shape (§7), exactly as
blueprint-assessment.md §4 permits ("no visible UI change yet except the
calendar quietly re-basing").

The spine lands on a core that mostly anticipated it. Today there is exactly
ONE user-facing date property, `due` (`lib.rs:432`, datetime), read by
`today_sections` (`lib.rs:296-347`), the recurrence engine
(`recurrence.rs:75,92`), and the snapshot (`ffi/src/lib.rs:456,468-484`); and
ONE status vocabulary, the task-scoped `todo/doing/done` select whose options
are already **entities** referenced from the definition by `props::OPTIONS`
cells (`lib.rs:433,437-450`). Because behavior already hangs on properties
resolved by *name* (never id — the seed law, `lib.rs:403-405`), and because
lotus is schema-on-read, almost everything below is **additive seed passes on
their own guards** plus a handful of thin services and FFI seams. The only
change to `core/` itself is the span field (§3) — made failing-test-first, per
the standing law (memory: test-drive-core-changes; the design-workflow docs
have had real cache bugs before).

What the blueprints demand and P11 delivers as substrate: the four-role closed
set with "role decides rendering" (bp1-inspector.html e10/e23 — only
role=calendar positions; lookup roles are "filterable, never calendar
clutter"), several independent date rows on one object (bp9 #28, bp1 e25),
Space-cycles-the-role as one lossless write (bp6 #25, bp9 #17), start +
optional end as ONE object / one drag target (bp9 #12, bp6 #17), repeat on any
dated object with virtual never-materialized occurrences (bp9 #13, bp1 e21/e23),
board columns that ARE the user's ordered vocabulary — existing even when
empty (bp6 #8/#33), one-command status writes (bp6 #10, bp9 #14), per-kind
vocabularies off one universal property (bp1 e11/e17, bp9 #18/#29), the
always-valid no-status ghost (bp1 e11, bp9 #22), entry-column create defaults
(bp6 #21), the V3 inspector's per-property display attributes (bp1 e8/e13/e14/
e26), and the usage-count/value-pool service (bp1 e9/e13, "on 12 objects").
What P11 does **not** build: any of their UI. The date editor popover, the
board, the status picker, the off-calendar strip, and the V3 inspector are
P11.5/P14 shell phases mounting these seams.

**Gate discharged inline:** §5-R6 (status split-or-union) is adopted here as
the assessment recommends — ONE `status` definition, options scoped by
`for-type`, order + hue on the option, type-seeded defaults are seeds,
no-status always valid (§5 below records it). The owner ratifies R6 by
approving this document; if R6 is ruled differently, slice 11d changes and
nothing else does. R1 (files), R2 (shortcut map), R3 (VALUE_HEX values), and
R7 (Google sync) gate **nothing** in P11 (§10).

## 1 · The load-bearing decisions

1. **Date roles are seeded PROPERTIES, not a role attribute on the value.**
   P11 seeds four datetime property definitions — `date` (the calendar role),
   `valid-until`, `occurred`, `purchased-on` — beside the existing `due`
   (assessment §2.1: "roles are properties, not value attributes"). Justified
   against the core three ways. (a) *Positioning already hangs on properties*:
   the snapshot's `dated` is a query on the `due` property (`ffi:468-484`),
   `today_sections` queries `due` (`lib.rs:308-311`), search qualifiers
   resolve property-by-name (`search.rs:358-386`) — so "only calendar-role
   dates render" falls out of *which properties the lens reads*, no new
   mechanism. (b) *Zero migration*: a role attribute would change the
   DateTime value's serialized shape for every existing cell; a new property
   is schema-on-read, and every shipped `due` cell is untouched. (c) *The
   role behaviors come free*: "Space cycles the role" (bp1 e10) is one
   transaction moving a value between properties (§2.3); each lookup role is
   instantly a search qualifier (`valid-until<2027-01-01` works the day it
   seeds, via `at_most_constraint`, `search.rs:366-370`); "a date is just a
   row; add another via N" (bp1 e25) is just another cell. The rejected
   alternative — a `role` field inside `Value::DateTime` — touches the Value
   enum, serde, equality, and every match site, to buy nothing the property
   split doesn't already give.

2. **`due` is NOT renamed, migrated, or rewritten — it becomes one of five
   coexisting roles.** The positioning set (the roles the calendar renders)
   is exactly **{`date`, `due`}** (assessment §2.1: the lens "names its
   positioning set `{date, due}`; lookup roles are simply never in the set";
   bp9 #14/#16: tasks render on `due`, events on calendar-role dates;
   valid-until/occurred/purchased-on NEVER appear). Every shipped box has
   `due` cells; every one keeps its exact civil value, its `date_only` bit,
   and its place on the calendar and in Today. Compat is a test obligation,
   not a hope (§8, 11a). For v1 the positioning set is resolved **in one
   services function by name** (`calendar_set`, §2.2) — the per-view
   config-cell version of it (feature-map #24's configurable `dateField`)
   is deferred to the P14 calendar re-base, so P11 does not invent view
   config that no view yet reads.

3. **A span is an optional `end` INSIDE the DateTime value — not a paired
   `end` cell, not a ninth Value kind.** `core/src/value.rs`'s `DateTime`
   struct (`:171-176`) gains `end: Option<i64>` with `#[serde(default)]`
   (§3). This is the assessment's recommended "range variant on the DateTime
   value kind" (§2.1: "one cell = one fact = one drag target, which BP-9's
   span-grip needs") landed in the cheapest honest shape: the value *kind*
   stays `"datetime"`, so search, facets, `property_kind`, `parse_value`
   dispatch, and the property catalog are all untouched; old logs
   deserialize with `end = None` (zero migration); a paired-`end`-cell would
   split one fact across two cells (an orphaned `end` after role-cycling is a
   whole bug class); a new enum variant would touch `kind_rank`
   (`lib.rs:626-637`), `compare_values` (`:602-614`), and every
   `match Value::DateTime` site to represent something that is still a
   datetime. **This is the one `core/` change in P11 and it is written
   failing-test-first** (memory: test-drive-core-changes).

4. **Recurrence anchors on the positioning set, per entity, `date` before
   `due`.** `recurrence::occurrences` today hardcodes `due` as the anchor
   (`recurrence.rs:75,92-95`). P11 generalizes: a series is any live,
   non-working entity with a `recurrence` rule cell AND a dated cell on a
   property in the anchor set; the anchor is the first of [`date`, `due`]
   present (§4). A rule on an entity whose only dates are lookup roles does
   not expand — occurrences exist to *render*, and lookup roles never render
   (bp9 #15). The parameterized engine (`occurrences_anchored`) takes an
   explicit anchor-property list, so a future lens that wants lookup
   expansion asks for it instead of the law changing. Exceptions stay
   ordinary entities carrying `exception-of` + their own dated cell on the
   series' anchor property — this **is** bp9 OQ-B's recommended
   override-on-parent answer, and it is already the engine's shape
   (`recurrence.rs:135-153`); P11 generalizes it rather than inventing it.
   Occurrences stay virtual, stored nowhere, capped at a year
   (`recurrence.rs:81-82`) — "nothing is spawned; no debt."

5. **Universal status = the ONE existing `status` definition + enriched
   option entities. (R6, adopted as recommended.)** The single `status`
   select (`lib.rs:433`) is kept for every kind. Per-kind vocabularies are
   the option ENTITIES it already references (`lib.rs:437-450`), each gaining
   additive cells: `for-type` (reference → a type entity; the scope),
   `order` (the EXISTING `order` number property, `lib.rs:227` — board-column
   order, fractional insert-between like workspaces), `hue` (number, 0–360 —
   the dot/chip color; *values* are data awaiting R3, tests never assert a
   color), and `completes` (bool — marks the done/terminal option that
   bp9 #14's in-grid checkbox writes and bp6 #13's fold-Done folds; the
   consumers *imply* this marker but no badge names it — recorded as a
   designer's call for the owner to nod at, §10). The per-kind offer is a
   query (`status_options_for`, §5.2), never a scan of task values — an
   empty column still exists because the option entity exists (bp6 #33).
   The entry-column create default is a `default-status` reference cell ON
   the type entity — a *seed*, user-editable per kind (R6's own text).
   "No status" stays always-valid structurally: it is the absence of a cell,
   which the query layer already treats vacuously.

6. **Every seed is its OWN additively-guarded pass — the seed-guard trap is
   law.** `seed_starter_library` short-circuits the moment `due` exists
   (`lib.rs:411`), i.e. on every shipped box; anything added inside it never
   runs again. P11 adds **three** new passes to `seed_if_fresh`
   (`lib.rs:63-72`), each guarded on its own sentinel exactly like
   `seed_priority` (guard `priority`, `lib.rs:141`) and `seed_event_fields`
   (guard `location`, `lib.rs:82`): `seed_date_roles` (guard `occurred`),
   `seed_status_scoping` (guard `for-type`), `seed_display_attributes`
   (guard `hide-when-empty`). Each is idempotent, lands on an older box that
   already has `due`, adds cells and entities but **never removes or
   replaces an existing value** (the presets law — "NEVER overwrites a
   filled value," bp1 e5 — applied to seeds), and carries the two mandatory
   tests: `_is_idempotent` and `_lands_on_a_box_that_already_has_due`
   (tasks.rs:44-78, events.rs pattern). All new definitions take **allocated
   ids** (never new `props::` constants — `entity.rs:54-85` stays closed;
   code resolves by name, so nothing can key on an id).

7. **Every new FFI seam routes through `with_box` and returns an honest
   `Committed` tag — or the tab-lag bug class returns.** The store cache
   (`ffi:190-232`) reconciles at `checkin` (`:301-324`) off the
   `Committed::{Read,Wrote,Failed}` contract (`:348-359`; memory:
   ffi-store-cache). Every seam in §7 — role cycling, span editing, the
   option offer, option birth, distinct values — goes through `with_box`
   (`:365-376`): reads tag `Read` (cache verbatim), successful mutations tag
   `Wrote` (re-sweep + re-cache), refused mutations tag `Read`, failed
   persists tag `Failed` (evict). Slice 11f runs the full cache battery
   against each (§8). Every export gets its hand-maintained
   `shell/macos/lotus.h` declaration — an export without its `.h` line is
   unresolved (the P9/P10 law).

## 2 · Role-typed dates (R1) — four new properties beside `due`

### 2.1 `seed_date_roles` — the seed pass

```rust
/// The date ROLES of the amended spine (R1, bp1 e10/e23): four datetime
/// properties beside `due` — `date` is the calendar role (positions on the
/// calendar, with `due`); `valid-until`, `occurred`, `purchased-on` are
/// lookup roles (filterable facts, never appointments — bp9 #15). A role is
/// a property, not a value attribute: zero migration, and Space-cycling a
/// role is one transaction moving the value between properties. Own guard
/// (`occurred`), NOT the starter-library `due` guard which short-circuits
/// on every shipped box — an older box gains all four on open. Offered,
/// never EXPECTED: no type's expectations change ("a date is just a row").
fn seed_date_roles(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "occurred").is_some() {
        return Ok(());
    }
    // four datetime property definitions, allocated ids, Author::System,
    // WORKING:true — the exact shape of seed_event_fields (lib.rs:81-99)
    for name in ["date", "valid-until", "occurred", "purchased-on"] { ... }
    session.commit(commands, "date roles", Author::System)
}
```

Inserted into `seed_if_fresh` after `seed_event_fields`. No expectations
change: `task` still expects `[status, due]`, `event` still `[due]`
(`lib.rs:455-461`) — an event's move to calendar-role `date` cells is a P14
authoring choice, not a P11 rewrite. Each new property is automatically
AtMost-qualifiable in search (`valid-until<2027-01-01`) because qualifiers
parse through `parse_value` by declared kind (`search.rs:366-386`) — the
"filterable facts" half of bp9 #15 costs nothing.

### 2.2 The positioning set — `calendar_set`

```rust
/// The properties that POSITION an entity on the calendar: {date, due}.
/// Lookup roles (valid-until / occurred / purchased-on) are never in this
/// set — that absence IS bp9 #15's off-calendar rule. Resolved by name at
/// read (the seed law: no code keys on ids). One function, one place: the
/// snapshot's `dated` union (§7) and the recurrence anchor (§4) both read
/// it, so "what renders" and "what anchors a series" can never drift apart.
/// The per-view configurable set (feature-map #24 `dateField`) is deferred
/// to the P14 calendar re-base; this function is where that config will be
/// consulted when it exists.
pub fn calendar_set(store: &Store) -> Vec<Id> {
    ["date", "due"].iter().filter_map(|n| property_id(store, n)).collect()
}
```

Order matters: `date` before `due` is the anchor precedence (§4) and the
positioning-date precedence for rows carrying both (§7). (Precedence only
breaks ties on a single row's displayed date; both facts stay queryable.)

### 2.3 Role cycling — one lossless transaction

The ring, closed and ordered (bp1 e10's four roles + `due`; bp6 #25 lists the
cycle on the tasks page, eliding `purchased-on`; the full closed set from
bp1 lines 494-505 includes it):

```
due → date → valid-until → occurred → purchased-on → due
```

```rust
/// Space-cycles a date row's role (bp1 e10, bp6 #25, bp9 #17): ONE
/// transaction moving the value — civil, date_only bit, and span end intact
/// — from `from` to the next role in the ring. RemoveCell(from, v) +
/// AddCell(next, v), one commit, one undo. Switching a calendar-role date
/// to a lookup role "pulls it off the calendar without losing the dates"
/// (bp9 #17) purely because the lens reads calendar_set. Returns the new
/// property. Refused (no such cell / not a datetime / target role already
/// carries a value on this entity) without touching the store.
pub fn cycle_date_role(session: &mut Session, entity: Id, from: Id)
    -> Result<Id, String>
```

The "target already carries a value" refusal keeps one entity's several date
rows independent (bp9 #28: `last seen` occurred + `birthday` calendar coexist)
— cycling never merges or clobbers a sibling row. FFI: §7.1.

## 3 · Spans (R1) — the one `core/` change, failing-test-first

### 3.1 The shape

```rust
/// Civil wall-clock time, never a bare instant. ... (existing doc)
/// A value may be a SPAN: `end`, when present, is a second packed civil
/// strictly after `civil`, with the same date_only reading applied to both
/// ends — "start → end", one cell, one fact, one drag target (bp9 #12,
/// bp6 #17). Absent on every value written before P11 (serde default), so
/// old logs replay unchanged. end == start is not a span; the writer
/// collapses it to None (bp9 #17: clearing the end collapses to a single
/// day).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct DateTime {
    pub civil: i64,
    pub date_only: bool,
    #[serde(default)]
    pub end: Option<i64>,
}
```

Why this exact shape (over the two alternatives the assessment left open):

- **vs. a paired `end` cell**: two cells for one fact breaks "one click-target,
  one drag-target" (bp9 #12: dragging the middle moves the whole span — one
  write); role-cycling (§2.3) and unset would have to know to carry a sibling
  cell along or orphan it; equality/dedup would need a cross-cell rule the
  core has no vocabulary for.
- **vs. a new `Value::DateRange` variant**: a ninth kind multiplies every
  query and renderer (the enum's own warning, `value.rs:200-201`), forks
  `kind_rank`/`compare_values`/`parse_value`/`facet` treatment, and makes
  "add an end to this date" a *kind change* instead of an edit.
- **Derive-audit**: field order keeps `civil` first, so derived `Ord` still
  sorts by start (then `date_only`, then `end`) — every existing sort
  (`Sort { property: due }`, `dated`) is stable for non-spans. `Copy` holds
  (`Option<i64>` is `Copy`). Per-kind equality now includes `end` — a span
  is not equal to its start-only twin, which is what RemoveCell/dedup should
  believe. `DateTime::date`/`::at` constructors set `end: None`; a new
  `DateTime::span(start, end)` constructor enforces `end > start || None`.

**Failing test first, in this order**: (1) write the serde-compat test — a
log line serialized by the *old* struct (no `end` key) deserializes with
`end == None` — and watch it fail to compile until the field lands with
`#[serde(default)]`; (2) the equality/ordering tests; (3) then the field.

### 3.2 Writing spans

- `parse_civil` (`content.rs`, the `"datetime"` branch of `parse_value`,
  `:575`) accepts `"<start> -> <end>"` (each side the existing
  `yyyy-mm-dd [hh:mm]` grammar; mixed date-only/timed sides refused; end ≤
  start refused). This makes the inspector's existing `set` seam and the
  search DSL span-capable with no new entry point — the mirror contract
  (bp9 #12: calendar drag and the inspector date row are "the same write")
  is honest because both go through `parse_value`.
- A dedicated FFI seam for the shell's three drag gestures (§7.1,
  `lotus_set_span_at`): start/end/whole-span edits all reduce to ONE
  `set_property` of one DateTime value — one command, one undo toast, logged
  in the entity's activity (bp9 #11).
- Recurrence and spans: a series whose anchor value carries an `end` anchors
  on its **start**; span-shaped *occurrences* (a recurring 3-day block) are
  deferred (§9) — `Occurrence` keeps its single `date`.

## 4 · Recurrence generalized (R1) — anchor on the positioning set

### 4.1 The engine change (`services/src/recurrence.rs`)

```rust
/// Every occurrence of every live series inside [from, to], exceptions
/// subtracted, ordered by date then series id. A series is any live,
/// non-working entity carrying a `recurrence` rule AND a dated cell on one
/// of `anchors` — the anchor is the FIRST anchor property present (P11:
/// calendar_set order, `date` then `due`). Repeat is available on ANY dated
/// object (R1, bp1 e23, bp9 #13/#28): a note, a contact's birthday, an
/// event — nothing here reads a type. Occurrences are computed at render
/// and stored nowhere; the window is the horizon, capped at a year.
pub fn occurrences_anchored(store: &Store, from: DateTime, to: DateTime,
                            anchors: &[Id]) -> Vec<Occurrence>

/// The default expansion every lens reads: anchored on the positioning set.
pub fn occurrences(store: &Store, from: DateTime, to: DateTime) -> Vec<Occurrence>
    // = occurrences_anchored(store, from, to, &calendar_set(store))
```

Mechanically: the hardcoded `due_prop` lookup (`recurrence.rs:75`) and anchor
read (`:92-95`) become a walk over `anchors` (first `Some` wins); everything
else — `occurs_on` (`:119-131`), the cap (`:81-82`), sort order — is
untouched. The public `occurrences(store, from, to)` **keeps its signature**,
so `today_sections` (`lib.rs:328`) and `build_snapshot_windowed` (`ffi:487`)
recompile unchanged — the due-anchored world is bit-identical because
`calendar_set` includes `due` and pre-P11 series carry only `due`.

Anchor rules, stated plainly:

1. Anchor = first of [`date`, `due`] with a DateTime cell on the series
   entity. (An entity with both: `date` wins — the calendar role is "renders
   on the calendar"; the pre-existing `due` path is unchanged because
   pre-P11 entities have no `date` cell.)
2. A rule on an entity with only lookup-role dates is **inert** (§1.4). The
   engine's parameterization (`occurrences_anchored`) is the sanctioned
   escape hatch, not a behavior flag.
3. A span-valued anchor anchors on its start (§3.2).

### 4.2 Exceptions — override-on-parent, generalized (answers bp9 OQ-B)

`exception_dates` (`recurrence.rs:135-153`) currently reads each exception
entity's `due`. Generalized: an exception covers the date of its own cell on
the **series' anchor property** (passed in, since the caller just resolved
it). Pre-P11 exceptions carry `due` and their series anchor on `due` — they
keep working verbatim. An exception stays an *ordinary entity* — one file of
truth, overrides as data, never a detached copy (assessment §2.1; bp9 #32's
recommended answer, adopted here — §10).

### 4.3 Today, unchanged — with one honest note

`today_sections` still reads `due` only (`lib.rs:297,308-317`): Today's
"due" list is about *obligation*, and the series-past-is-not-a-debt exclusion
(`:312-317`) stands. One behavioral note to record: the series-occurring-today
re-add (`:328-332`) calls `occurrences`, so a **date-anchored** series
occurring today (a birthday) will join Today's due list once such data exists.
No pre-P11 data changes appearance (no `date` cells exist yet); a birthday
appearing in Today on the day is the calendar-lens behavior bp1 e21 describes.
Flagged, deliberate, test-pinned (11c).

## 5 · Universal status (R2 / R6) — scope the options it already has

### 5.1 `seed_status_scoping` — the seed pass

Guarded on `property_id("for-type")`. One commit that:

1. Creates three property definitions (allocated ids, System, WORKING):
   - `for-type` — reference; on an OPTION entity, the type(s) it is offered
     to. Reference cells are multi-valued by nature, so an option may serve
     several kinds (union namespace); one cell is the seeded norm.
   - `hue` — number; 0–360. On an option entity: its dot/chip color. (bp9
     #5/#7 put an editable hue on the `calendar` select's options; the
     assessment §2.1/R6 puts it on status options too — adopted. Seed values
     are placeholders pending R3; no test asserts a specific number.)
   - `completes` — bool; on an option entity, marks the completion/terminal
     state its kind's checkbox writes (bp9 #14) and the board folds (bp6
     #13). Designer's addition — see §10.
2. **Adds cells to the three existing option entities** (`todo`/`doing`/
   `done`, `lib.rs:437-450`): `for-type → task`, `order` 1.0/2.0/3.0 (the
   existing `order` property, `lib.rs:227` — no new definition), seed hues,
   and `completes: true` on `done`. Additive cells on System-seeded
   entities; nothing existing is removed or replaced.
3. Creates a `default-status` reference property and adds
   `default-status → todo` to the **task type** entity — the entry-column
   default as a cell on the type (bp6 #21 "status = the vocabulary's entry
   column"; R6: "type-seeded defaults are seeds, user-editable per kind").
   No other type gets one: a new contact is born with NO status (bp9 #22) —
   no-default is the default.

**What P11 does NOT seed**: event/contact/project vocabularies (registered/
confirmed/…, follow-up/dormant). Those are *user* vocabularies (bp1 e11
"user vocabulary per kind") arriving via the vocabulary-editing seam (§5.3)
and P12's presets (bp1 e5: presets seed vocabularies). Seeding them would
front-run the preset mechanism and stamp Viktor's examples as fixtures.

**Compat spelled out**: a status cell is `Value::Select(option_id)`
(`content.rs:250-256`) — identity is the option ENTITY id, not its scoping —
so every existing status cell, `status:done` qualifier, and inspector select
keeps working with zero rewrite. `create_task` (`content.rs:236-264`) is
re-pointed to read the task type's `default-status` cell, falling back to
`find_option(store, status, "todo")` (`content.rs:216-228`) — births are
byte-identical on every existing box.

### 5.2 The per-kind offer — a query, never a value scan

```rust
pub struct StatusOption { pub id: Id, pub name: String, pub order: f64,
                          pub hue: Option<f64>, pub completes: bool }

/// The status vocabulary OFFERED to a kind (bp6 #8, bp1 e17): the options
/// the one `status` definition references (props::OPTIONS), kept when a
/// `for-type` cell names this kind — or when the option carries no
/// `for-type` at all (the pre-scoping legacy shape: offered everywhere,
/// never lost). Sorted by `order` (board column order = digit order,
/// bp1 e17), then id. An option with zero carriers still appears — an
/// empty board column keeps its header (bp6 #33). A kind with no matching
/// options offers NOTHING (bp6-#33's inverse: vocabularies are per-kind,
/// not inherited from task).
pub fn status_options_for(store: &Store, kind: Id) -> Vec<StatusOption>
```

The no-`for-type` ⇒ offered-everywhere rule is the backward-safe degenerate
case (an old app version's freshly-created option is never stranded); after
`seed_status_scoping` runs, no seeded option is in that state.

`facet_properties` (`search.rs:241-262`) keeps treating `status` as one
facetable select — the union namespace means `status:done` stays one
qualifier vault-wide, which is exactly R6's point.

### 5.3 Vocabulary editing — one birth verb, existing edit seams

```rust
/// A new status option for a kind (bp6 #8 column-add, bp1 e17 "Edit
/// vocabulary…"): one commit — Create + NAME + WORKING + for-type→kind +
/// order (max existing order for the kind + 1) + optional hue — plus the
/// AddCell(status_def, OPTIONS→option) that makes the one definition
/// reference it. Returns the option id.
pub fn add_status_option(session: &mut Session, kind: Id, name: &str,
                         hue: Option<f64>) -> Result<Id, String>
```

Rename / re-hue / re-order an option = ordinary `set` on the option entity
(NAME via the existing rename path; `order`/`hue` parse through
`parse_value`'s number branch) — column rename/reorder "edits the status
property itself, vault-wide" (bp6 #8) because the option IS the column.
Option retirement (what happens to cells carrying a removed option) is
deferred to the settings/vocabulary shelf (§9).

## 6 · Display attributes + the usage-count service (the V3 inspector's substrate)

### 6.1 `seed_display_attributes`

Guarded on `property_id("hide-when-empty")`. Five property definitions
(allocated ids; all cells live ON property-definition entities — definitions
are entities, so this is ordinary data, no core change):

| property          | kind      | on a definition, means                                             | bp source |
|-------------------|-----------|--------------------------------------------------------------------|-----------|
| `icon`            | text      | glyph token the row renders                                        | bp1 rows (i-tree, i-flag, …) |
| `digit-key`       | text      | the digit/letter shortcut, keyed by property NAME, one global map   | bp1 e8 / D21 |
| `hide-on-kind`    | reference | type entities on which the row is hidden (multi-valued)             | bp1 e26 row menu |
| `hide-when-empty` | bool      | empty row auto-hides ("keeps the resting panel short")              | bp1 e14/e26 |
| `core-on-kind`    | reference | type entities where the row sits in the core card (else MORE)       | bp1 e14/e20, D11 |

P11 seeds the **definitions only** — no icon/digit *values*. The starter
value table (which glyph on which property, the digit map) is P11.5's call
with R2, and it is data, not schema. Scope rules land free: "name/type edits
apply vault-wide; hide applies per kind" (bp1 e26) is exactly
definition-cells vs `hide-on-kind` reference targets.

### 6.2 Usage counts + distinct values (`services/src/search.rs`)

```rust
/// How many live entities carry at least one cell of each user property —
/// the "on 12 objects" count in the add-property picker (bp1 e13) and the
/// property table. Working entities and trash excluded (the query laws).
pub fn usage_counts(store: &Store) -> Vec<(Id, usize)>

/// The distinct values of a property across the live set, each with its
/// carrier count, deterministically ordered (count desc, then display) —
/// layer ① of the value pool (bp1 e9: "values in this vault (with usage
/// counts)"), and the status picker's per-option counts. candidate_values
/// (search.rs:266-277) promoted from facet-internal to public, plus counts.
pub fn distinct_values(store: &Store, property: Id) -> Vec<(Value, usize)>
```

These are P6's facet-count machinery extended (assessment §2.2: "the
facet-count service already computes hypothetical result sizes — extend it"),
not a parallel engine.

## 7 · FFI seams + what `build_snapshot` exposes (the quiet calendar re-base)

### 7.1 New seams — every one `with_box` + a correct `Committed` tag

```c
/* Space-cycles a date row's role: one transaction moving the value (civil +
   date_only + span end intact) from `property` to the next role in the ring
   due→date→valid-until→occurred→purchased-on→due. Returns the NEW property
   name (caller frees), or NULL on busy/refusal.        Wrote | Read | Failed */
char *lotus_cycle_date_role_at(const char *path, uint64_t id, const char *property);

/* Writes a date/span cell as ONE command (the mirror contract: inspector
   row, calendar drag, and span-grip drag are all this write — bp9 #11/#12).
   end_civil = 0 means no end (a plain date); end must be > start.
   date_only applies to both ends. Returns 1, or 0 on busy/refusal.
                                                        Wrote | Read | Failed */
int32_t lotus_set_span_at(const char *path, uint64_t id, const char *property,
                          int64_t start_civil, int64_t end_civil, int32_t date_only);

/* The status vocabulary OFFERED to a kind, sorted by board order: JSON
   [{id, name, order, hue, completes}]. Options with no carriers included
   (an empty column keeps its header, bp6 #33).                        Read */
char *lotus_status_options_at(const char *path, const char *kind);

/* A new status option for a kind (column-add / "Edit vocabulary…"): one
   commit, ordered last. hue < 0 means none. Returns the option id, or 0.
                                                               Wrote | Failed */
uint64_t lotus_add_status_option_at(const char *path, const char *kind,
                                    const char *name, double hue);

/* Layer ① of the value pool: a property's distinct live values with usage
   counts, JSON [{value, count}], deterministic order.                 Read */
char *lotus_distinct_values_at(const char *path, const char *property);
```

All five declared in `shell/macos/lotus.h`. Status writes need no new seam:
board drag / in-grid checkbox / inspector picker are all the existing
`lotus_set_at(path, id, "status", "<option name>")` (`ffi:1075`) — one write,
already routed and tagged (bp6 #10/#24, bp9 #14 "same as dragging its kanban
card"). Role-date `set`s likewise ride `lotus_set_at` (the four new
properties parse as datetimes, now span-capable, §3.2).

### 7.2 The catalog, enriched additively

`build_properties` (`ffi:406-434`) gains additive JSON fields — Swift's
decoder ignores unknown keys, so no shell change now, and P11.5 reads them
without an FFI bump:

- `PropertyRow`: `usage` (live-carrier count, §6.2), `icon`, `digitKey`,
  `hideWhenEmpty`, `hideOnKinds: [name]`, `coreOnKinds: [name]` (absent when
  unset).
- `OptionRow` (`ffi:95-100` sibling): `order`, `hue`, `completes`,
  `forTypes: [name]`. The flat option list stays complete and un-duplicated —
  the one FFI compat surface for status (compat test, 11d).

### 7.3 The snapshot re-base — the single allowed visible effect

`build_snapshot_windowed` (`ffi:455-`) changes in exactly three places, all
inside the existing `Snapshot`/`EntityRow` shape (`:160-176`, `:102-118`):

1. **`dated` becomes the positioning-set union**: entities with a cell on
   ANY `calendar_set` property (today: `due` Exists minus `recurrence`,
   `:468-484`) — run per set-property, merged, deduped, sorted by
   positioning date. Lookup-role-only entities stay OUT (bp9 #15's negative
   space, structurally).
2. **`EntityRow.due` becomes the positioning date**: the entity's `due` cell
   if present, else its `date` cell (`calendar_set` precedence);
   `due_date_only` follows the same cell. Every row on every shipped box is
   byte-identical (no `date` cells exist yet); an entity carrying only a
   calendar-role `date` fills the field the shipped `CalendarView` already
   buckets by — **that is the whole re-base**, no shell change.
3. **Two additive `EntityRow` fields** for later shells: `due_end`
   (`Option<i64>`, the positioning cell's span end — the P14 span bar reads
   this) and `positioned_by` (the positioning property's name, `"due"`/
   `"date"`, absent when undated — so the P14 grid can draw the task
   checkbox on `due` rows, bp9 #14, without re-deriving). Additive JSON:
   today's Swift decode is untouched.

`occurrences` (`:487-490`) picks up date-anchored series automatically via
§4's `occurrences` wrapper. `lotus_snapshot_at` remains the current-month
wrapper (`:440-449`); on a box with no role cells its output is identical
except the two additive fields — pinned by the 11f regression test.

## 8 · Slice plan (each an independent commit: build → failing tests → review → fix; smallest first)

House test style throughout: per-test temp box + `seed_if_fresh` (`fresh`/
`boxed` harnesses, events.rs:9-30, recurrence.rs:8-51), one behavioral
assertion per test, store read directly via `property_id`/`props` — and for
every seed the two mandatory guards: `_is_idempotent` (re-run `seed_if_fresh`,
definition count == 1) and `_lands_on_a_box_that_already_has_due`
(tasks.rs:44-78 pattern). FFI tests use `fresh_box`/`read_json`/
`clear_cache_for_tests` (`ffi:1463-1487, :216`).

- **11a — the four role seeds + the positioning set + role cycling.**
  *Rust:* `seed_date_roles` (§2.1) into `seed_if_fresh`; `calendar_set`
  (§2.2); `content::cycle_date_role` (§2.3). *FFI:* `lotus_cycle_date_role_at`
  + `lotus.h`. *Failing tests first:*
  `the_four_date_roles_seed_beside_due_and_are_idempotent` (each of
  date/valid-until/occurred/purchased-on is a datetime, WORKING, alongside
  `due`); `date_roles_land_on_a_box_that_already_has_due`;
  `the_calendar_positioning_set_is_date_and_due_only`;
  `a_lookup_role_date_is_filter_only_never_positioned` (an entity with only
  `occurred` is absent from `today_sections.due` and the snapshot's `dated`,
  but found by an `occurred`-qualifier query);
  `an_entity_may_carry_several_date_rows_at_once` (due + valid-until +
  occurred coexist, bp9 #28);
  `space_cycles_the_role_as_one_transaction_moving_the_value` (one commit;
  old cell gone, next-role cell present);
  `role_cycling_is_lossless_round_trip` (full ring back to origin: civil +
  date_only identical); `cycling_refuses_when_the_target_role_is_occupied`;
  `an_event_with_only_due_still_renders_on_the_calendar` (P10 regression);
  FFI: `role_cycle_round_trips_through_the_cache` (hit-path write visible
  without re-open = the `Wrote` contract; then `clear_cache_for_tests` +
  replay agrees), `a_refused_cycle_is_tagged_read_and_leaves_the_cache_verbatim`.

- **11b — the span end (the one core change) + the span seam.**
  *Core, failing-test-first (§3.1 order):* `DateTime.end: Option<i64>`
  `#[serde(default)]` + `DateTime::span`. *Rust:* `parse_civil`
  `"start -> end"` grammar (§3.2). *FFI:* `lotus_set_span_at` + `lotus.h`.
  *Tests:* `an_old_log_datetime_deserializes_with_no_end` (serde compat —
  written before the field, the load-bearing one);
  `a_span_parses_start_and_optional_end`;
  `a_span_edit_round_trips_start_and_end_across_reopen` (civil ×2 +
  date_only survive a fresh `Session::open`);
  `a_zero_length_span_equals_a_plain_date` (end==start collapses to None;
  span ≠ start-only twin under per-kind equality);
  `spans_sort_by_start_among_plain_dates`;
  `span_editing_is_one_command_one_undo`;
  `cycling_a_span_keeps_its_end` (§2.3 meets §3);
  FFI: `a_span_write_is_tagged_wrote_and_a_bad_span_is_refused_read`
  (end ≤ start → 0, cache verbatim), `a_failed_persist_evicts_the_cache`.

- **11c — recurrence generalized to any dated entity + exceptions.**
  *Rust:* `occurrences_anchored` + `occurrences` wrapper (§4.1);
  `exception_dates` takes the anchor property (§4.2). No FFI change (the
  snapshot's call site recompiles). *Tests* (extend recurrence.rs's
  `boxed`/`series` harness; parameterize `series` on an anchor property):
  `recurrence_expands_on_a_non_event_dated_entity` (a plain note: rule +
  `date` cell → weekly expansion on the anchor's weekday);
  `a_date_anchored_series_uses_the_date_not_due`;
  `a_rule_on_a_lookup_only_entity_is_inert` (…and
  `occurrences_anchored_expands_it_when_explicitly_asked`);
  `an_exception_on_a_date_anchored_series_suppresses_exactly_one_date`
  (exception = ordinary entity, `exception-of` + its own `date` cell, never
  a detached copy);
  `occurrences_stay_virtual_for_any_anchor` (history().len() unchanged);
  `the_year_horizon_cap_holds_regardless_of_anchor`;
  `a_due_anchored_series_is_unchanged_by_generalization` (the whole existing
  recurrence suite green, plus an explicit same-output pin);
  `a_date_anchored_series_occurring_today_joins_today` (§4.3, pinned as
  deliberate).

- **11d — universal status: scoping seed + offer + entry default + vocab
  birth. (R6 as recorded in §5.)**
  *Rust:* `seed_status_scoping` (§5.1); `status_options_for` (§5.2);
  `add_status_option` (§5.3); `create_task` reads `default-status` with the
  todo fallback. *FFI:* `lotus_status_options_at` +
  `lotus_add_status_option_at` + `lotus.h`; `OptionRow` enrichment (§7.2).
  *Tests:* `status_scoping_seeds_idempotent_and_lands_on_a_box_that_already_has_due`;
  `the_existing_todo_doing_done_become_task_scoped` (per-kind offer for
  `task` = exactly the three legacy options, ordered 1/2/3);
  `an_option_carries_board_order_and_hue_and_they_round_trip` (existence +
  round-trip only — never a specific color, R3);
  `done_is_marked_completes`;
  `status_options_are_scoped_per_kind_by_for_type` (an option added for
  `project` never appears in the task offer);
  `a_kind_with_no_status_options_offers_none`;
  `an_unscoped_option_is_offered_everywhere` (the legacy degenerate rule);
  `the_entry_default_is_a_cell_on_the_type_and_user_editable` (re-point
  `default-status` → doing; a new task births doing);
  `create_task_still_births_status_select_todo` (compat — Value::Select,
  not Reference); `no_status_is_always_valid` (absent cell, vacuous
  queries, nothing forces one);
  `pre_existing_status_select_cells_survive_the_scoping` (`status:done`
  query still matches);
  `build_properties_option_offer_stays_backward_compatible` (flat list:
  no drops, no duplicates, additive fields only);
  FFI: `the_option_offer_seam_is_a_read` (cache verbatim),
  `add_status_option_is_tagged_wrote`, `a_locked_box_refuses_every_new_seam`
  (Guard 5 pattern, `ffi:1547`).

- **11e — display attributes + usage/distinct-value service.**
  *Rust:* `seed_display_attributes` (§6.1); `usage_counts` +
  `distinct_values` (§6.2). *FFI:* `PropertyRow` enrichment (§7.2);
  `lotus_distinct_values_at` + `lotus.h`. *Tests:*
  `display_attributes_seed_idempotent_and_land_on_an_old_box`;
  `a_property_definition_carries_display_attributes_across_reopen` (set
  icon/digit-key/hide-when-empty on a definition, reopen, read back);
  `hide_on_kind_is_per_kind` (hidden on task ≠ hidden on note);
  `usage_count_counts_live_entities_carrying_a_property` (working + trashed
  excluded); `usage_count_of_an_unused_property_is_zero`;
  `distinct_values_lists_each_value_once_with_counts_deterministically`
  ({A:3, B:1}, stable order);
  `a_status_options_usage_count_drives_the_picker` (per-option carrier
  counts via distinct_values(status));
  FFI: `distinct_values_is_a_read`, `the_catalog_carries_usage_and_attributes`.

- **11f — the snapshot re-base + the full cache battery (the visible
  effect, last).**
  *FFI only:* `dated` = positioning-set union; `EntityRow.due` =
  positioning date; additive `due_end` + `positioned_by` (§7.3). *Tests:*
  `a_box_with_only_due_cells_snapshots_identically_modulo_additive_fields`
  (the load-bearing regression pin);
  `an_entity_with_only_a_calendar_role_date_enters_dated_and_fills_due`
  (the re-base itself);
  `a_lookup_only_entity_never_enters_dated` (bp9 #15);
  `an_entity_with_both_due_and_date_positions_by_due_once` (precedence, no
  double row — multi-row rendering deferred, §9);
  `a_span_fills_due_end_and_a_plain_date_leaves_it_absent`;
  `positioned_by_names_the_property`;
  `a_date_anchored_series_occurrences_reach_the_window` (windowed snapshot
  over a future month, P10's steer test re-run for date anchors);
  cache battery across ALL P11 seams:
  `an_external_append_invalidates_before_a_new_seam_reads` (`ffi:1510`
  pattern), `a_locked_box_refuses_every_new_seam`,
  `every_wrote_seam_is_visible_on_the_next_cache_hit_without_reopen`,
  `every_failed_seam_evicts` — one test per seam per contract row.

Dependency note: 11a/11b/11d/11e are mutually independent; 11c needs 11a
(`calendar_set`); 11f needs 11a and reads 11b's `end`. If pressure demands,
11e can slide behind 11f without breaking anything — nothing in 11f reads it.

## 9 · Deferred (named, not built in P11)

**All shell** — the bp1 date editor popover (Space/⏎/R choreography), the
status picker + ghost pill, the board lens (columns off `status_options_for`,
drag, fold-Done via `completes`), the off-calendar strip, span bars + grips +
drag-to-reschedule gestures, the V3 inspector rows/MORE/row-menu (P11.5/P14 —
they mount these seams verbatim) · **per-kind vocabularies beyond task**
(event registered/confirmed/…, contact follow-up/dormant — user data via
`add_status_option` + P12 presets, never seeds) · **the digit/icon starter
value table** (data on the 11e definitions; P11.5 with R2 — the `digit-key`
cell is storage, the one-global-map ownership question is R2's) ·
**hue seed values / VALUE_HEX reconciliation** (R3 gates P11.5; the 11d hue
cells are placeholders the R3 pass re-edits as ordinary data) · **per-view
positioning-set config** (feature-map #24 `dateField`; `calendar_set` is the
single consultation point when it lands, P14) · **the Schedule lens's
"tasks-only vs all calendar-role objects, ghosted"** (bp6 #16, unresolved in
the consumer — P11 deliberately makes the set {date, due} so P14 can render
either without core change) · **multi-row calendar rendering** (an entity
with `due` AND `date` drawing twice — needs a row-shape change; v1 positions
once, due-first, §7.3) · **span-shaped occurrences** (a recurring 3-day
block; `Occurrence` keeps one date, §3.2) · **option retirement** (removing
a vocabulary entry that live cells reference — the settings/vocabulary
shelf's conflict moment, P19) · **`>`/after date qualifiers** (search still
ships AtMost only; the roles inherit that, not fix it) · **recurrence
exception *editing* UI** ("edit just this one" — the data path is 11c;
the gesture is P14) · **ICS / Google external-id mapping** (R7 — recurrence
generalization is in scope, sync is not).

## 10 · Rulings recorded + conflicts for the owner (Konrad)

1. **R6 — adopted as the assessment recommends, needs your ratification
   (it gates the phase).** ONE `status` definition; options scoped by
   `for-type` (union namespace, per-kind offer); `order` + `hue` on the
   option; type-seeded defaults are seeds (`default-status` cell,
   user-editable); no-status always valid (blueprint-assessment.md §5-R6).
   Approving this doc ratifies it; ruling "split" instead changes slice 11d
   only.

2. **`completes` on an option — a designer's addition the badges imply but
   never name.** bp9 #14's in-grid checkbox and bp6 #13's fold-Done both
   require knowing WHICH per-kind option is terminal; no blueprint badge
   marks it on the option entity. P11 marks it with a bool cell and seeds it
   on `done`. Nod or rename.

3. **Hue on STATUS options is assessment-sourced, not badge-sourced.** The
   badges put an editable hue only on the `calendar` select's options
   (bp9 #5/#7); assessment §2.1/R6 extends it to status options — adopted,
   values deferred to R3. If you'd rather status dots derive purely from
   VALUE_HEX, the `hue` cells become overrides and nothing else moves.

4. **bp9 OQ-B (recurrence exceptions) — closed by adoption.** Override-on-
   parent, exceptions as ordinary entities — the blueprint's own
   recommendation and already the engine's shape; 11c generalizes it. The
   Google exception-sync mapping it also constrains stays fenced with R7.

5. **The positioning set lives in code for v1** (`calendar_set`, resolved by
   name), not in view config — a deliberate simplification of the
   assessment's "lens config names its positioning set," because no view
   entity reads config yet. The function is the single seam the P14 config
   slides into. Flagging the divergence so it's chosen, not drifted-into.

6. **"Board order" as a persisted attribute** is asserted by the assessment
   (§2.1/§4) and only *implicit* in bp1/index (picker digit order = column
   order). Adopted as the `order` cell — reusing the existing `order`
   property (`lib.rs:227`) rather than minting a second ordering vocabulary.

7. **One Today note:** after 11c, a *date*-anchored series occurring today
   joins Today's due list (§4.3) — new behavior reachable only by new data,
   test-pinned. Shout if Today should stay due-only even then.
