# P13 Search v2 — the pinned "missing 20%" over the blessed palette: the ⌘F entity palette gets live facet value-counts, the D21 digit map on facets, include→exclude→off cycling (the one services change — `-key:value`→`Op::NotEquals`, which already exists and is already evaluated), three display modes, kind-grouped never-capped results, query pills, and a hint footbar — every command-mode, view-file, scope-connector, and AI leg refused or deferred with a recorded reason, the whole surface re-shaped from the shipped `SearchPopup`/`FacetBar` onto the P11.5 kit with ZERO lotus_core change

Building on the landed P6 search model (design/p6-search-model.md) and the landed
P11.5 grammar kit (p11.5-grammar-kit.md; `RowKit`, `DigitMap`, `Hues`,
`InspectorEditors`, `InspectorFootbar`) and the shipped shell
(`shell/macos/Sources/{Window,Inspector,InspectorEditors,RowKit,DigitMap,Hues,Commands}.swift`).
P13 is **BP-3** (`/Users/k/Documents/bp3-search.html`, 31 annotations + 4 open
questions), whose own header pins the work: *"Largely built; this page pins the
missing 20%."* The centered ⌘F palette that **searches ENTITIES** is the single
sanctioned reversal of the palette ban (interface.md 0.5; owner directive
2026-07-07) and it already ships: `SearchPopup` (Window.swift:2560) draws the
scrim, `FacetBar`/`FacetChip` (:2461/:2519) render Liv's one great idea
(hypothetical facet counts under the current filter), `.lotusSearchFor`
chip-click filtering (P11.5c) and `initialQuery` seeding are wired, and the
whole Rust seam (`lotus_search_at` → `services::search`: DSL `parse()`, ranked
`search()`, `facet()`, `distinct_values()`, quote-aware `tokenize()`) is landed.

**P13 is overwhelmingly a SHELL re-shape over seams that already exist.** The
four readers verified that the one substantive addition — facet
include/exclude/off cycling — is **NOT a lotus_core change**: `Op::NotEquals`
already exists in the Op enum and is already evaluated by `satisfies()`
(services/src/lib.rs:15,73) with the exact "vacuously true where the cell is
absent" semantics BP-3 wants; the archived gate (search.rs:126) is its only
current instance. So exclusion is a **services-layer** `parse()`/`facet()`
extension, failing-test-first (memory: test-drive-core-changes — the failing
test is written first, the doc's reasoning is not trusted). Date **ranges**
(`Op::AtLeast`) would be a genuine lib.rs change and stay **deferred** exactly
as P11.5 §8 already deferred `>`/`after:`.

Every visible slice is **mockup-first**: a static exhibit cloned from BP-3
(default quick-nav / active-query / results), re-hued to the lotus palette
(lake green `#2f7d6b`, never the blueprint blue), approved against the
blueprint before a line of Swift (memory: copy-liv-exactly). The one core-ish
slice is **failing-test-first**. What varies is data and display mode, never the
palette's anatomy.

## 0 · Owner decisions (confirmed 2026-07-11, before mockups)

Six forks were put to the owner; all four that genuinely forked the design were
answered **as recommended**, and the two minor ones take their recommended
defaults. No override — the decisions below are written into §1–§5:

- **Command mode: REFUSE entirely** (§1.1). No `>` prefix, no Search|Commands
  segment, not even a static frame — the constitution's palette ban stands; the
  palette searches ENTITIES only. macOS's Help-menu search over the menu bar is
  the OS-provided command discovery.
- **Chord: ⌘F canonical + ⌘O alias** (§1.7). Align the code to interface.md's
  ⌘F while keeping the shipped ⌘O as an alias; both open the one palette. Add
  the two-stage Esc (popover, then palette).
- **Result order: KIND-GROUPED** (§1, slice 13d). bp3-faithful fixed-order
  groups (tasks→events→notes→files→contacts) with collapsible headers, rank
  preserved within each group, client-side over the ranked ids.
- **Saved-search entity: DEFER from P13** (§1.2). The raw query stays
  re-runnable; Save/Export/Open-in-view render as reserved disabled frames. A
  cheap fast-follow when wanted.
- **Subnotes default-gate: DEFER** (§1.6, recommended) — a default-OFF subnotes
  gate is new silent scoping; not built. Archived-off (which IS law) ships.
- **Scope row: a single static "This vault" tile** (§1.3, recommended), no
  `+add source`; Drive/Web/connectors defer.

## 1 · The load-bearing decisions

1. **Command mode is REFUSED; the palette searches ENTITIES only. Record the
   delta.** BP-3 Scene C — the `>` prefix (a27), the Search|Commands segment
   (a3), commands-as-faceted-objects with a command facet mini-rail (a28/a29),
   Ctrl+Shift+P (a30/a31), and value-taking-command pickers (a31) — collides
   head-on with the still-standing refusal: feature-map T4 pins *"Command
   palette; commands as searchable faceted objects — Decided 0.2: no palette, no
   overlay → menu bar + the fixed keyboard map; **⌘F searches ENTITIES**"*
   (feature-map.md:304). interface.md 0.5 blessed a palette that searches
   *entities*, never commands-as-objects. Command mode also reintroduces a
   mutation surface (a28/a31: "Set tier…" runs a write from the palette) that
   duplicates the inspector's D21 editors and the menu bar — the "one door" law
   resists it. **RECORDED DELTA (a):** BP-3 Scene C is not built — no `>`
   prefix, no Search|Commands segment, no command facets, no Ctrl+Shift+P, and
   **not even a static Commands segment** (rendering the segment invites the
   reduction). The lotus-honest discoverability equivalent is the platform's own
   provision — macOS's Help-menu system search over the app's menu bar IS the
   command palette, supplied by the OS — the exact *"the OS answers → no lotus
   surface"* reconciliation feature-map.md:305 uses for rebindable hotkeys.
   Commands stay in the `CommandRegistry`, taught through the hover hints and the
   footbar (a11/a16). *(One reader argued interface.md:76-79 annuls the palette
   ban wholesale and command mode could ship as a second mode; the parent
   directive and two readers rule the entity-only reading — the ban on
   commands-as-a-second-source stands. Recorded, not silently dropped.)*

2. **Save-as-view / Open-in-view / Export DEFER to the views/files substrate;
   the minimal shippable is the always-re-runnable raw query.** BP-3 a14 saves
   *"a view definition in `.liv/views/*.base` (D20)… Files → Views… pinnable to
   Spaces"*; a15 opens the result set as a center view with a filters-as-rows
   right rail (the D22 engine); a13 exports N to md/csv. All three lean on a
   views/files substrate lotus refuses (feature-map T4:308-309; interface.md
   80-81 "a second source of truth"; `.liv/views/` has no counterpart yet,
   p11.5-grammar-kit.md §8:672). **RECORDED DELTA (b):** carry P11.5 §9.2 (the
   destination line) and P12 §1.2 (no folders) forward — the raw DSL string IS
   the re-runnable saved query for free (chip-click already seeds it via
   `pendingSearch`); Save/Open-in-view/Export render as **reserved/disabled
   footer frames with help text** (the P11.5 §9.6 ship-disabled precedent) so
   the layout diffs clean when the substrate lands. Export is a pure read over
   the hits (a13 "nothing changes") and rides the same `SearchQuery` the palette
   already builds — the seam is ready, the export service (feature-map #42, T2)
   is not. **The saved-search ENTITY** (a props::QUERY text cell via
   `lotus_set_at` + a sidebar "Saved" bookmark — feature-map #28, P6 §9:228,
   needs *no* views substrate) is **recommended DEFERRED from P13** to hold the
   budget, but it is a cheap fast-follow the owner may pull in (owner question §7).

3. **Scope tiles ship as a single "This vault" frame; Drive/Web/connectors and
   `+add source` defer.** BP-3 a4/a5 offer vault/Drive/Web tiles + connector
   sources (Notion, Slack) with per-scope counts. These are external
   integrations behind the one-integration fence (feature-map T2:191-192;
   T3 #20 connectors "Fenced":274). Files are **not** a separate scope — file
   entities live in the same box and their extracted foreign text already folds
   into the CONTENT tier (search.rs `extracted`), so "This vault" already covers
   files. **RECORDED DELTA (c):** ship at most a single static "This vault" tile
   for blueprint recognizability (or omit the row — owner question §7); OMIT
   `+add source`; defer Drive/Web/connectors and the Alt+V/D/W scope shortcuts
   to P15+/never-for-web. This moots BP-3 OQ-1 (Drive indexed-vs-API) and OQ-4
   (per-source index cost) — one scope, no picker. The scope-failed empty state
   (a26) collapses to a lotus next-moves empty state (§2, ruling §7).

4. **Facet include→exclude→off cycling is the one services change — and it is
   NOT a lotus_core change (`Op::NotEquals` already exists and is already
   evaluated). Failing-test-first.** BP-3 a8/a18/a19/a24 want per-value cycling
   (include→exclude→off), red + "not" + strikethrough for exclude, and include
   AND exclude coexisting within one facet (subjects: climbing, **not** gym).
   The shipped DSL never emits exclusion except the archived gate: `parse()`
   emits `Op::Equals` for `key:value`; a leading `-` is not handled —
   `-object:contact` splits to key `-object`, fails property resolution, and
   **silently demotes to a free-text term** (search.rs `split_qualifier`).
   **VERIFIED**: `Op::NotEquals(Value)` already exists (lib.rs:15) and
   `satisfies()` evaluates it as `!entity.has(property, value)`, vacuously true
   where the cell is absent (lib.rs:73) — so user exclusion rides the identical
   `run()`/`satisfies()` path the archived gate already proves, with ZERO edit
   to lotus_core, `Op`, `Query`, or `satisfies`. **RECORDED DELTA (d):** three
   deltas, all services/shell — (1) `parse()`/`tokenize()` recognize a leading
   `-` (spelling `-key:value` per bp3 a17's rendered pills) → `Constraint{prop,
   NotEquals(value)}`; (2) `FacetValue` gains an exclude/tri-state flag (today
   only `active: bool`, search.rs:57) and `facet()` detects `NotEquals`-active
   values (today its active-scan reads only `Op::Equals`, search.rs:214);
   (3) the shell renders exclude = red ValueChip + strikethrough. Coexisting
   include+exclude is just two constraints ANDed by `run()`. **Write the failing
   `search.rs` test first** — `parse("-tier:1")` builds `NotEquals`; `run()`
   drops tier:1; include+exclude on one property both apply — and do NOT trust
   that it needs core work; verify it rides the existing Op (memory:
   test-drive-core-changes). This is the headline of the "missing 20%".

5. **AI-suggest (Alt+M, ✦) ships as a static/inert frame; the behavior is P16.**
   BP-3 a11/a25 put a "✦ AI suggest metadata (Alt+M)" hover action + an
   accept/dismiss card in the rows. Every AI write is a proposal by law
   (interface 0.3:82-86); the proposals inbox is a different surface (P12) — the
   palette must not become a second mutation door. **RECORDED DELTA (e):** carry
   the P11.5 §2.8 / P12 §1.3 pattern — render the ✦ hover slot inert reusing the
   already-reserved amber (`Theme.warning`); NO suggestion seam, NO
   accept/dismiss wiring. The real feature lands in the AI pass (P16) where
   suggestions enter the ONE inbox, not the palette, with zero UI change here.

6. **Archived-off is already DSL law and ships as-is; subnotes-off is NOT law —
   the brief's premise is half-true, so it is flagged and deferred.** Archived
   is excluded by default via `Constraint{archived, NotEquals(true)}` unless
   `is:archived` (search.rs:126; P6 §1; feature-map #13) — the Filters "archived"
   toggle (a20, OFF by default) wires directly to that existing flag, zero new
   work. **CORRECTION / RECORDED DELTA:** the paired claim that **subnotes-off**
   is "already the DSL law" is **false** — `search.rs` has no parent/child gate
   at all (verified: zero matches; a `parent` reference property exists at
   lib.rs, and subnotes are feature-map #11 "S", but nothing hides child notes
   from default search today). A default-OFF subnotes toggle would be a **new
   silent scoping gate** — the exact silent-scoping the cautionary tales warn
   against (feature-map #3). **Recommend defer** the default-OFF behavior (owner
   question §7); the `has:parent`/`no:parent` DSL primitives already exist if the
   owner later wants it (a one-line base-gate mirroring archived).

7. **The chord: docs say ⌘F, the shipped code binds ⌘O — reconcile. Recommend
   ⌘F canonical + ⌘O alias.** VERIFIED live discrepancy: `registerCommands`
   binds the palette to **⌘O** (`switcher:open`, `Hotkey(modifiers:[.mod],
   key:"o")`, Window.swift:1598-1599; `.mod` = ⌘) — there is **no ⌘F binding in
   the shell** — while interface.md 0.5 + the keyboard map (:221) + P6 say **⌘F**
   (and BP-3 says Ctrl+O, which is the web app's ⌘O). So the code already
   diverged toward the blueprint and interface.md's ⌘F law is currently
   un-honored. **RECORDED DELTA (f):** bless **⌘F canonical** (the blessed
   native-Find law, muscle-memory standard) and keep **⌘O as an alias** (the
   shipped code + BP-3's Ctrl+O; fits Scene A's "O = open/jump" intent). Both
   fire the one action (open the one palette), so "no chord does different things
   on different surfaces" (interface.md:224) holds. Owner-decidable (§7); either
   way align code+docs and wire-or-remove the disabled "Command Palette…" menu
   item (which reserved the refused command-mode slot). **Also add the two-stage
   Esc** (a1): first Esc closes an open facet popover, second closes the palette
   — `SearchPopup`'s single dismiss (Window.swift:2604) lacks it.

8. **P13 re-shapes the shipped palette onto the P11.5 kit; no new palette, no
   parallel component.** Every BP-3 addition is a new sub-view hosted inside the
   existing `SearchPopup` body (Window.swift:2560, mounted at :1005 via
   `searchOverlay`). The facet rail re-shapes from value-chip-rows to
   property-chips; result rows converge onto `ObjectRow`; the facet-value
   popover is built from `ValuePoolPopover`'s chrome; pills reuse `ValueChip`'s
   red variant; the footbar factors from `InspectorFootbar.pair`; the facet
   digit map IS `DigitMap.resolve` (P11.5, R2). The never-hue set
   (status/priority/tier/type) already governs facet chips (Window.swift:2480,
   `Inspector.swift:1004`) and is preserved.

9. **Deferred from BP-3, decided (§6): command mode, save-as-view/export/
   open-in-view (+ the saved-search entity), Drive/Web scopes/connectors,
   AI-suggest, the subnotes default-gate, date ranges (`Op::AtLeast`), the
   highlighted-body snippet, favourite-facet customization (★-pin/drag), and the
   name-only match-scope flag.** Each has a named reason — a refused surface, a
   missing substrate, or a real core change held out of budget — not missing will.

## 2 · The palette surfaces (inside the one `SearchPopup`)

### 2.1 Quick-nav / recents — the empty-query state (a10)

With no query the palette is a jump list of recent objects (↑↓+⏎ opens). BP-3
wants "recently opened/edited." Today an empty query yields `search()`'s
score-0 order, which collapses to **created_key-DESC** (newest CREATED, not
modified or opened — search.rs:190,516). A true recently-*opened* list conflicts
with commands-only mutation (an open is not a command; the log has no
open-history). **RECOMMEND** approximating recency by **MODIFIED-desc** — a
cheap sort-key change to the empty-terms path in `search.rs`, expressible over
the existing wire (still returns bare hits, no new seam) — and **decline** an
open-tracking substrate (record the delta: "recents in lotus = newest-modified;
opened-history is not written to the append-only log"). Ctrl+⏎ "new content tab"
needs the tab system (P17) — deferred. Rendered as `ObjectRow` (Compact mode).

### 2.2 Active-query pills (a2/a17/a18) — the query rendered as removable tokens

`tier:1 #climbing -object:contact` renders each completed token as a removable
capsule: include = accent, exclude(−) = red; **Clear all** wipes the query but
keeps scopes; **⌫** on empty input pops the newest pill; click a pill removes it.
**SwiftUI: a new `QueryPill` row.** It is a *display* render of the raw query
string, NOT a second parser: Rust stays the single semantic parser (P6 §6; the
authoritative filter is always `lotus_search_at` over the string). The shell
already does quote-aware token surgery for `FacetBar.toggle`/`searchQualifier`
(Window.swift:2417,2497) and already holds the catalog (`model.properties()`),
so it can split tokens on `:`/`<`/leading-`-` and tell a resolved qualifier from
a demoted free-text term for **display** — the pill row is that same token layer,
not a re-parse. **RECONCILIATION / contingent seam:** if the f-h review shows the
shell cannot faithfully distinguish a resolved qualifier pill from demoted free
text (e.g. an unresolved `foo:bar`), THEN expose the parsed `SearchQuery` over
the wire (a `pills`/qualifiers field on `SearchResult`) so pills stay a render of
the one parser — flagged, verified before any Rust is written, not assumed.
`QueryPill` reuses `ValueChip`'s include(accent)/exclude(red) styling; the
remove-on-click + ⌫-pops-last semantics are new. Chip-click becomes **additive**
(a24: adds an include pill and re-runs) — today `FacetChip.toggle` is a
single-select *pivot* that drops the existing key first (Window.swift:2510);
P13's pill layer makes it additive. **RECORDED DELTA:** chip-click is additive in
the palette.

### 2.3 The facet rail + value popovers (a6/a7/a8/a18/a19) — re-shaped

**RECORDED DELTA:** `FacetBar` changes shape from a per-VALUE chip row to one
`FacetChip` per **property** carrying the property name + its distinct-value
count + its D21 digit `KeyCap` (`object · 6` on digit 0, `type · 14` on 2,
`subjects · 23` on 3 …). The per-value chips move INTO a new popover. Count reads
`Facet.values.count`; the digit label reads `DigitMap.resolve(catalog)[name]`.
Click opens the value popover.

**`FacetValuePopover` — the same type-to-filter shape as the P11.5
`ValuePoolPopover`.** It reuses the shared popover chrome verbatim —
`PopCap`/`PopRow`/`PopHint` + the filter field + the value list with a
`Hues.valueHex` dot + name + live count (InspectorEditors.swift:77-299). What is
NEW on top: (1) the include/exclude/OFF **tri-state** per row (`.vrow.inc`
accent · `.vrow.exc` red + strikethrough — the tension-(d) exclusion); (2) digit
cycling — `1-9` on a value cycle include→exclude→off, direct `I`/`X`/`O`, ↑↓ move
— which is popover-*local* key handling exactly like P11.5's status picker
reading digits locally (InspectorEditors.swift:386); (3) the key-hint footer.
The value pool + counts already have a seam: `facet()` returns counts under the
current filter (Liv's one great idea, dropping the property's own constraints so
counts exclude-self, search.rs:205); `distinct_values()`/`BoxModel.distinctValues`
supply the full pool. The **never-hue set** (status/priority/tier/type) uses the
StatusDot / neutral ladder in the popover dot, NOT raw VALUE_HEX (P11.5 §5.3).
**The digit map IS the shipped inspector map** — `DigitMap.resolve` (P11.5, R2
defaults `1 form · 2 type · 3 subjects · 4 project · 5 area · 6 people · 7 tier ·
8 dates · 9 status`), with the one reconciliation that **digit 0 = the "object"
(kind) facet**: `DigitMap` binds 0→`description`, which is free-text and never
faceted, so 0 is free in the facet surface and "object" takes it (RECORDED
DELTA). The "object"/kind facet maps onto the existing `type:` reference
qualifier the DSL already resolves — no new kind-facet primitive.

**Favourite rail customization DEFERS.** The ★-pin/drag-reorder/per-user
favourites (a6) lean on the display-attribute substrate + R2's per-user pins.
Ship a **curated/fixed** favourite set now (derived from `facet_properties()`);
user customization is P19. RECORDED DELTA.

### 2.4 The Filters panel (a20) — ship the archived toggle, static-frame the rest

BP-3's Filters panel pushes results down, never covers them. **Ships working:**
the **Archived** toggle (splices `is:archived` into the query string, the
parse-first pattern `FacetChip` already uses — zero new work). **Static-frame /
defer** (each a reserved row, P11.5 §9.6 ship-disabled precedent): date
**ranges** (need `Op::AtLeast`, a real lib.rs change — deferred, §6); "created in
workspace" (needs a workspace scope seam); **subnotes** default-gate (§1.6, not
law); and **name-only vs name+content** match-scope (a small services flag
threading a match-scope through `parse()`/`search()` to skip the cells+content
tiers — deferable, default stays name+content = current behavior). "Reset clears
the panel, not the pills."

### 2.5 Result display modes (a12/a21/a22/a23/a24) — one row kit, three tunings

**RECORDED DELTA against the brief's "ObjectCard = metadata":** BP-3's metadata
mode (a24) is **row-shaped**, so all three modes are `ObjectRow` tunings, not a
component swap — `ObjectCard`/`ObjectTile` stay reserved for the board/gallery
passes (they carry no status dot by design, RowKit.swift).

- **Compact (36px)** = `ObjectRow` verbatim (RowKit.swift): kind icon · title ·
  exactly one `anchorChip` (project→subject→people→role-date) · `StatusDot` ·
  modified; empty fields never render (a23 == the shipped budget). This completes
  the P11.5 §4.3 convergence — replace the bespoke `resultRow`
  (Window.swift:2693) with `ObjectRow`, gaining selection/hover-open/double-tap,
  and pass a palette-local `chipTap` that sets `query` in place (don't navigate).
- **Context (50px)** = `ObjectRow` + a matched snippet subtitle with a **field
  label**. The field label is already carried: `Hit.field`/`MatchField`
  (Name/Cell/Content/Structured) is decoded shell-side but unused today. The
  **highlighted body snippet** (`<mark>`) needs a snippet span the P6 seam
  deliberately omits (bare ids + score + `MatchField`, p6-search-model.md:161).
  **RECOMMEND** ship Context with the field label only; treat the highlighted
  body snippet as a **deferred seam extension** (`Hit` gains an optional snippet
  string, failing-test-first) — P11.5 §8 already parked exactly this.
- **Metadata** = `ObjectRow` with an expanded chip budget: up to 2 extra chips +
  `+N` overflow, each in its hash-stable `VALUE_HEX` hue (`Hues.valueHex`, frozen
  R3, same in graph/inspector/facets). Extra chips read from `EntityRow.cells`
  already in the snapshot — no seam. `ObjectRow` today hard-limits to one anchor
  chip (illegal-states-unrepresentable, P11.5 decision 8), so Metadata mode needs
  a `chips:[Anchor]` parameter or a metadata variant.

**`DisplayModeSwitch`** — a new 3-way segmented control, persisted via
`@AppStorage` (mirroring `DigitHintVisibility`), driven by Alt+1/2/3 registered
as ordinary `CommandDef`s. **`ResultGroupHeader`** — results group by object kind
in a **fixed order** (tasks→events→notes→files→contacts→chats) with a per-kind
count; a header collapses its group. `search()` returns one globally-ranked list
today (search.rs:190) — grouping is a **client-side stable partition** over the
ranked ids (kind order is shell chrome, `rowKindIcon` maps kind→icon), preserving
rank within each group. **RECORDED DELTA / owner question §7:** kind-grouping
reorders away from pure score; BP-3 makes it the default. **The true count**
(a12, "482 indexed · showing 6 recent", never silently capped) — the wire
carries no total and hits truncate at 200 (search.rs:193, ffi:871). A reader
showed the wire cannot express it, so P13 adds a cheap `total: usize` to
`SearchResult` (= `run(&sq.query).len()`; `run()` already executes for facets)
and raises/removes the 200 truncation to a shell-driven page size. This is the
named cautionary-tale-#3 fix (the silent 30-cap). Small services/FFI delta, no
lib.rs. **Row-hover actions** (a11): the ↗ open (needs tabs, P17 — deferred), the
✦ AI-suggest (static/inert, §1.5), and the ⋯ menu (ship the copy-link/pin subset
that works today; reveal-in-folder needs the files substrate — deferred).

### 2.6 The footbar (a16) + empty state (a26)

The always-visible shortcut contract reuses the inspector's footbar grammar —
factor `InspectorFootbar.pair` (Inspector.swift:1407) into a shared KeyCap-pair
helper so the palette and inspector teach the same keys from one source
(↑↓ move · ⏎ open · Tab into rail · 0-9 open a facet). Ship hints always-on
first; the on-hover/always/off visibility setting is a settings-budget item
(interface.md caps settings at four) — flag it, ride `DigitHintVisibility` if
adopted. The **empty state** keeps BP-3 a26's spirit without the multi-scope
story: under one scope it names the vault-relevant next moves — "Clear last
qualifier ⌫ · Open Filters · include archived?" — replacing the bare "Nothing
matches." (Window.swift:2619). RECORDED DELTA.

## 3 · The minimal core work — services-only, failing-test-first

**Rust budget: ZERO lotus_core change.** The one substantive change is a
**services-layer** extension; two additive touches (total count, recency sort)
ride the same FFI decode change; date ranges (`Op::AtLeast`, a real lib.rs
change) are DEFERRED.

### 3.1 The DSL exclusion extension (FAILING-TEST-FIRST)

In `services/src/search.rs` only (no `lib.rs`, no new `Op`):
1. `tokenize()`/`parse()` recognize a leading `-` on a qualifier (`-key:value`,
   the a17 spelling) → `Constraint{property, Op::NotEquals(value)}` (the Op and
   its `satisfies()` arm already exist, lib.rs:15,73).
2. `FacetValue` (search.rs:53) gains an exclude/tri-state (today only
   `active: bool`); `facet()`'s active-scan (search.rs:214) additionally detects
   `Op::NotEquals` values so the chip/row can render the "not" state.
3. Counts already respect existing exclusions (facet() runs `run(base + probe)`).

**The failing tests, written first:** `parse("-tier:1")` yields
`Constraint{tier, NotEquals(Number(1))}` (not a demoted free-text term);
`run()` drops tier:1 objects while keeping cell-absent objects (vacuous truth);
include+exclude on ONE property both apply (`#climbing -subject:gym`);
`facet()` marks the excluded value. Verify it rides the existing Op — do not
trust that it needs core work (memory: test-drive-core-changes).

### 3.2 Additive: the true count + the recency sort (same FFI touch)

- `SearchResult` gains `total: usize` (= `run(&sq.query).len()`; cheap, `run`
  already executes) and the 200 truncation becomes a shell-driven page size —
  the never-capped count (a12).
- The empty-terms ordering changes from CREATED-desc to **MODIFIED-desc** (a10)
  — a sort-key tweak, no new seam, no new state. Failing test: an edited-later
  entity sorts above an older-edited one under the empty query.

### 3.3 What stays shell-side (zero Rust)

The pill display layer (§2.2), kind-grouping (§2.5), display modes, the Filters
archived toggle (`is:archived` string-splice), the facet-value popover UI, and
the favourite rail are all shell over existing seams. The facet-value pool +
counts already ship (`facet()`, `distinct_values()`).

## 4 · Swift decode shapes — additive, Optional, `try?`-safe

The decoder uses `.convertFromSnakeCase` (Window.swift:238) and `applySnapshot`
decodes with `try?` (one missing required key silently drops the whole snapshot,
P11.5 decision 12), so every new wire field is **Optional with a defaulting
accessor**:

```swift
// SearchFacetValue gains the tri-state (wire: `active` stays; add `excluded`)
struct SearchFacetValue: Codable {
    let label: String
    let count: Int
    let active: Bool?        // include (Op::Equals)
    let excluded: Bool?      // NEW — Op::NotEquals active; nil → false
    var state: FacetState { excluded == true ? .exclude : (active == true ? .include : .off) }
}

// SearchResult gains the honest total (wire: `total`)
struct SearchResult: Codable {
    let hits: [SearchHit]
    let facets: [SearchFacet]
    let total: Int?          // NEW — true match count; nil → hits.count (old fixtures)
}
```

The `SearchHit.field` (why-matched) is already decoded — Context mode's field
label needs no new field. The contingent pills field (§2.2), if the review
forces it, is one additive Optional array of `{key, op, label}`. No other new
`Codable`. New shell-only state: the display mode (`@AppStorage`) and per-session
group-collapse — neither is wire.

## 5 · Slice plan (each an independent commit: mockup-first where visible, failing-test-first for core)

Rust in this plan: **zero lotus_core; one services extension (13a).** Two
independent tracks: the search-service track (13a) and the shell re-shape
(13b→13e), which consumes 13a's tri-state and total.

- **13a — search-service deltas (CORE-ish, FAILING-TEST-FIRST).** §3 verbatim:
  the `-key:value`→`Op::NotEquals` `parse()` extension; `FacetValue` tri-state +
  `facet()` `NotEquals`-detection; `SearchResult.total`; the empty-query
  MODIFIED sort; the FFI decode (`excluded`, `total`). Tests first per §3.1/§3.2.
  Verify it rides the existing Op (no lib.rs change). Invisible; no mockup.
- **13b — facet rail reshape + FacetValuePopover (MOCKUP-FIRST).** Re-shape
  `FacetBar` to one property-chip per facet (name + count + `DigitMap` KeyCap,
  object on 0); build `FacetValuePopover` from the `ValuePoolPopover` chrome +
  the include/exclude/off tri-state rows (consuming 13a) + digit cycling
  (`1-9`/`I`/`X`/`O`) + the key-hint footer; red-strikethrough exclude; never-hue
  ladder in the dot. Mockup: bp3 `.frail`/`.pop` (a6/a7/a8/a18/a19).
- **13c — query pills + additive chip-click + two-stage Esc (MOCKUP-FIRST).**
  The `QueryPill` row (include=accent/exclude=red, ✕ remove, ⌫ pops newest,
  Clear all) as a display render of the query string; chip-click becomes
  additive; the two-stage Esc (popover→palette). Flag the contingent pills seam
  only if the review shows the shell can't distinguish resolved from demoted
  tokens. Mockup: bp3 `.pills` (a2/a17/a18/a24).
- **13d — display modes + group headers + true count + row hover
  (MOCKUP-FIRST).** `DisplayModeSwitch` (Compact/Context/Metadata, Alt+1/2/3,
  `@AppStorage`); converge Compact onto `ObjectRow` (retire the bespoke
  `resultRow`, palette-local chipTap); Context = `MatchField` field label
  (highlighted-body snippet deferred); Metadata = expanded chip budget + `+N`;
  `ResultGroupHeader` kind-grouping (fixed order, client-side); the "N indexed ·
  showing M" count line (13a's total); the ⋯ hover subset (copy-link/pin), ✦
  inert, ↗ deferred. Mockup: bp3 results (a12/a21/a22/a23/a24/a25).
- **13e — Filters panel + footbar + recents empty state + scope/footer frames
  (MOCKUP-FIRST).** Filters frame with the working Archived toggle (`is:archived`)
  + static-deferred date-range/workspace/subnotes/name-only rows; the palette
  footbar (factored `InspectorFootbar.pair`); the empty-query recents list
  (`ObjectRow`, MODIFIED sort); the next-moves empty state; the single "This
  vault" scope frame (or omit); Save/Export/Open-in-view reserved/disabled footer
  frames with help text. Mockup: bp3 `.filters`/`.hints`/`.scoperow`/footer
  (a4/a13/a14/a15/a16/a20/a26).

The two tracks are independent; within the shell track 13b introduces the
tri-state popover 13c/13d build on, so 13b precedes 13c/13d.

## 6 · Deferred (named, not built in P13)

- **Command mode / BP-3 Scene C** (a3/a27-a31) — REFUSED per feature-map T4 +
  interface.md palette ban (§1.1). The OS Help-menu search is the platform
  equivalent. No `>`, no Search|Commands segment, no command facets, no
  Ctrl+Shift+P, not even a static segment.
- **Save-as-view / Open-in-view / Export** (a13/a14/a15) — lean on the refused
  `.liv/views/*.base` views/files substrate (feature-map T4:308-309); the
  re-runnable raw query is the shippable equivalent; reserved/disabled frames.
- **The saved-search ENTITY** (feature-map #28, P6 §9) — recommended deferred to
  hold the budget though it needs no substrate; a cheap fast-follow (owner §7).
- **Drive/Web scopes + `+add source` connectors + Alt+V/D/W** (a4/a5) — the
  one-integration fence (T2/T3 #20); Vault-only ships; OQ-1/OQ-4 dissolve.
- **AI-suggest metadata** (Alt+M, a11/a25) — proposals = P16; static/inert frame,
  amber reserved (`Theme.warning`), P11.5 §2.8 / P12 §1.3 pattern.
- **Date RANGES / `Op::AtLeast`** (a20) — the one genuine lib.rs change; deferred
  exactly as P11.5 §8 deferred `>`/`after:`. Filters date rows static.
- **Subnotes default-OFF gate** — not law today; silent-scoping concern; the
  `has:parent`/`no:parent` primitives exist if the owner wants it later (§1.6).
- **Highlighted body snippet** (Context mode) — the P6 seam returns bare ids; a
  deferred `Hit` snippet-span extension (field label ships now).
- **Favourite-facet ★-pin / drag-reorder** (a6) — display-attribute substrate +
  R2 per-user pins; a curated/fixed favourite set ships; customization P19.
- **Name-only vs name+content match-scope** (a2/a20) — a small services flag;
  default name+content ships; the name-only gate is deferable.
- **Ctrl+⏎ open-in-new-tab / ↗ hover-open** (a11/a25) — needs the tab system
  (P17); ↑↓+⏎-opens-and-closes ships.
- **The hint-visibility setting** (a16) — settings-budget item; hints ship
  always-on.
- **reveal-in-folder** (a11 ⋯ menu) — the files substrate (R1).

## 7 · Rulings recorded + the genuinely open owner calls

**Ruled here (not owner-blocking):**

1. **Command mode REFUSED** — the entity palette is the sole blessed overlay;
   OS Help-menu search is the discoverability equivalent (§1.1).
2. **Save/Open-in-view/Export defer**, extending P11.5 §9.2 / P12 §1.2 — the raw
   query is the re-runnable saved search; frames reserved (§1.2).
3. **Facet exclusion is services-only, failing-test-first** — `Op::NotEquals`
   already exists and is already evaluated; no lib.rs change (§1.4, §3.1).
4. **Date ranges (`Op::AtLeast`) deferred** — the one true lib.rs change stays
   out of budget (§6). BP-3 OQ-2 (digit-8 date crowding) resolves by deferral:
   digit 8 opens one date facet whose popover asks which date (created/edited/
   role) and applies a **preset** (single `AtMost` bound); custom ranges wait for
   `Op::AtLeast`.
5. **Archived-off ships as-is (DSL law); subnotes-off is NOT law** — the brief's
   premise corrected; the default subnotes-gate is deferred (§1.6).
6. **Metadata mode = `ObjectRow` with an expanded chip budget, NOT `ObjectCard`**
   — corrects the brief's framing; `ObjectCard`/`ObjectTile` stay reserved for
   board/gallery (§2.5).
7. **Recents = newest-MODIFIED** — opened-history is not written to the
   append-only log (§2.1); a sort tweak, no seam.
8. **The facet digit map = the shipped `DigitMap` (P11.5, R2)**, object on the
   spare digit 0 (description-0 is never faceted); per-property digit editing
   stays P19 (§2.3).
9. **The pill row is a display render of the query string**, not a second parser;
   Rust stays the single semantic parser; a wire pills-seam only if the review
   proves the shell can't distinguish resolved from demoted tokens (§2.2).
10. **The result-count seam is justified** — a reader showed the wire carries no
    total; `SearchResult.total` is the cautionary-tale-#3 fix (§2.5, §3.2).

**Genuinely open owner calls (recommendations in §0 form):** see `ownerDecisions`
— the chord (⌘F vs ⌘O), confirm the command-mode refuse, whether the saved-search
entity ships now, the subnotes default-gate, kind-grouping-vs-pure-rank, and
scope-tile fidelity (single tile vs omit). Each forks a mockup or the code; none
blocks 13a.

## 8 · Fix-round deltas (P13 review, recorded)

The adversarial review confirmed 7 findings (+2 correct-but-split); fixed:

- **Query pills: input binds directly to the raw query; pills are a VIEW,
  not a hidden-qualifier split.** The 13c freeText binding was fragile — it
  collapsed multi-word free text (a typed space was normalized away) and its
  ⌫-pop stole Backspace from the facet popover's filter field. Reverted to
  `TextField(text: $query)` with the pill row rendering the query's qualifier
  tokens (✕ removal, Clear-all, exclude-red). Qualifiers show inline in the
  input too — a recorded delta from bp3's hidden-qualifier input, chosen for
  robustness (the split had data-loss bugs). The ⌫-pop is dropped (the ✕
  removes pills).
- **FacetValuePopover keyboard digit/I·X·O cycle deferred.** The bare-key
  onKeyPress handler stole digits and i/x/o from the auto-focused type-to-
  filter field (canonical labels like "doing"/"done" were unfilterable).
  Removed it; click-to-cycle (off→include→exclude→off) + type-to-filter
  remain. Keyboard value-cycle conflicts with the filter field and is
  deferred.
- **"0–9 open a facet" un-advertised.** No palette-level digit opens a facet
  (a bare digit types into the query); the footbar no longer claims it.
  Deferred — it needs a focus mode where the rail, not the input, owns digits.
- **metadataChips honors the never-hue set** (tier renders neutral, not
  VALUE_HEX — the frozen budget).
- **Kind-group collapse re-anchors the selection** (highlighted resets, so
  Enter can't open the wrong row over the shifted display order).
- **Chip-click include drops a contradicting exclude** of the same value
  (no more `key:value` AND `-key:value`).
