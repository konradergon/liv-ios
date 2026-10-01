# Blueprint Assessment — the Liv BP set on the lotus core

> **Status:** 0.1 — 2026-07-09, lead-engineer assessment. Inputs: the five readers'
> structured reports over the fifteen blueprint pages (BP-1…BP-14 + the AI suggestion
> catalog), reconciled against `liv-ui-map.md` 1.0 (the interface spec of record),
> `feature-map.md` 1.0 (the mapping + refusals record), the git log through P10, and
> the core as it stands (`core/`, `services/`, `ffi/`, `shell/macos/Sources/`).
>
> The blueprint set is **Liv-as-amended**, not Liv-as-shipped: it bakes in the IA-1…IA-12
> cuts, the amended spine (R1 role-typed dates, R2 universal status, "blessed
> 2026-07-09"), the V3 inspector, the BP-7 V2 render budget, and the one-AI-grammar.
> That means it *supersedes parts of what liv-ui-map mined from shipped code* — and
> parts of what we just built from it.

---

## 1 · VERDICT

**Yes — the blueprint set is implementable on the lotus core, and the core is the
right substrate for most of it.** Roughly: **~60% of the delta is pure shell work**
on mechanisms the core already has, **~25% is core/seed/FFI extension** that fits the
architecture cleanly, and **~15% collides with standing lotus invariants** and needs
an owner ruling before its surfaces can even be designed.

**Fits as-is (the core anticipated it):**
- **Schema-on-read** — property definitions are entities in a global namespace;
  a property exists vault-wide the moment one entity carries a cell. BP-1's "N row",
  BP-13's property table, and "instantly filterable" are already structural.
- **The one-AI-grammar** (halo → suggestion card → plan card, deterministic ids,
  dismissals never re-ask, accept runs the manual seam, values never invented) maps
  ~1:1 onto what lotus has by *law*: proposals quarantined in the queue, the declined
  sidecar, the gazetteer, provenance, one-transaction undo. BP-10's philosophy block
  is a restatement of the constitution. This is the best-fitting blueprint.
- **Views-as-objects, saved searches, presets** — saved views (query + renderer +
  config) are entities; a preset *is* a type with expectations. `.base`/`.view` files
  become an import/export *format*, never the storage (liv-ui-map §4.1).
- **Recurrence** — the series-is-one-entity / occurrences-are-virtual / exceptions-
  are-entities engine already exists and is strictly better-shaped than the
  blueprints' "spawn next instance on completion" wording (nothing is spawned; no
  debt). BP-9 badge 13 ("occurrences computed at render, never duplicated") is
  literally the lotus design.
- **Habit check-ins / time entries as "DB rows, never files"** (BP-8) — on lotus
  everything is an entity + projections computed-once in services; feature-map #16
  converged on this years before the blueprint did.

**Needs core/seed/FFI extension (clean fits, real work):**
- The amended spine: role-typed dates (four roles + spans + recurrence-on-anything)
  vs today's single seeded `due`; universal per-kind status vs the task-only
  todo/doing/done seed (§2).
- Per-property display attributes (hide-on-kind, hide-when-empty, core-flag, icon,
  digit key), usage-count / distinct-value services for pickers and facets, a
  tool-tier registry for AI, option entities carrying order + hue.

**Conflicts with lotus invariants (ruling required, §5):**
1. **Files as real sibling folders on disk as the source of truth** — the blueprint
   set's spine promise (BP-2 trust beat, BP-5 commit-as-file-move, BP-7 pools +
   rename-on-disk + drag-out, BP-11 H1-renames-the-file, BP-13 D05 two-way
   frontmatter mirror, .liv/ on disk) vs the constitution's *log is the disk truth;
   files by reference; never move user files; no second truth*. liv-ui-map §4.3(1)
   already ruled the mirror "the disease lotus exists to cure."
2. **Google Calendar two-way sync** (BP-9) — architecturally refused; one-way ICS
   import is the sanctioned, fenced path.
3. **Watched-folder auto-import** (BP-14 Downloads watcher) — "nothing runs on a
   timer"; §4.4 allows only an *inbound* watcher on a designated import folder.
4. **Live embedded query-blocks in notes** (BP-11 interactive data-view fences) —
   refused as an authoring-surface/embedded-editor failure mode; the lotus-clean
   equivalent is a view pill that opens the lens (or a read-only live projection).

None of these kill the blueprint set. Each has a lotus-clean equivalent that
preserves the *UI promise* while keeping one truth — but the owner must rule, page by
page, before BP-2/BP-5/BP-7/BP-9-sync/BP-11-embeds/BP-14 enter the design workflow.

**Supersessions of things just built** (expect rework, not greenfield): BP-1
supersedes the P5 inspector's grammar; BP-3 supersedes the P6 search palette's
interaction model; BP-9 supersedes the data basis of the calendar shipped last week
(kind filters → calendar-role dates; day panel inspector → segmented [Selection|View];
today cell → daily note); BP-4 supersedes the current chrome's IA. The substrate
under all four survives; the grammar on top changes.

---

## 2 · THE STRUCTURAL DELTAS

The six changes that cut across every page. Ordered by how many surfaces consume them.

### 2.1 The amended spine — universal status + role-typed dates (R1/R2)

**What the blueprints demand.** Every kind carries a single-select `status` with a
user-editable, *per-kind*, ordered vocabulary (board columns ARE the vocabulary;
empty is a valid ghost state). Every date carries a *role* — `calendar` /
`valid-until` / `occurred` / `purchased-on` (+ task `due`) — where only
calendar-role (and due) dates render on Calendar/Schedule; the rest are
filter-only "lookup" facts. Dates support start + optional end (spans) and
recurrence on ANY dated object; one object may carry several date rows.

**What lotus has.** One seeded `due` date + `status` (todo/doing/done) expected on
the task type; the calendar lens already positions entities by *whichever date
property the view config names* ("behavior hangs on properties, never on types" —
feature-map #24). Recurrence exists but is wired to the event/task path.

**Core/seed/FFI work.**
- **Roles are properties, not value attributes.** Seed four date property
  definitions (`date` [calendar], `valid-until`, `occurred`, `purchased-on`) beside
  `due`. The calendar/schedule lens config names its positioning set
  `{date, due}`; lookup roles are simply never in the set. "Space cycles the role"
  in the UI = one transaction moving the value between properties. No new value
  machinery; zero migration (schema-on-read).
- **Spans**: extend the date story with an end — either a paired `end` cell or a
  range variant on the DateTime value kind. Decide in the design workflow with a
  failing test first (memory: test-drive-core-changes); the range value is cleaner
  (one cell = one fact = one drag target, which BP-9's span-grip needs).
- **Recurrence generalization**: `services/recurrence.rs` takes (entity,
  date-property) instead of assuming events; a rule cell may sit on anything with a
  dated cell. Exceptions stay ordinary entities (this answers BP-9 OQ-B: overrides
  as data, never detached copies).
- **Universal status**: keep ONE `status` property definition; per-kind vocabularies
  = option entities carrying a `for-type` reference plus `order` and `hue` cells.
  This is the "shared select: split-or-union" open decision from feature-map #17 —
  R2 makes it bite *now* (§5). Entry-column default = an expectation default on the
  type. Board drag = one command setting status (undoable, logged — already the
  board-renderer design of feature-map #18).
- **FFI**: new seams for role cycling, span editing, option-vocabulary editing, and
  per-kind option queries — every one routed through `with_box` and tagged
  Committed Read/Wrote/Failed (memory: ffi-store-cache), or the tab-lag class of
  bug returns.

**Shell rework.** The date row editor (Space cycles, ⏎ opens role+start+end+repeat),
the status row/ghost, board columns re-keying live off option entities, and the
calendar re-basing (§3, BP-9). Every already-built surface that shows a date or a
status (Today, Tasks, Calendar, inspector, search facets) re-reads through the new
seeds — mostly config, not rewrites, *because* positioning was already
property-driven.

### 2.2 The V3 keyboard-compact inspector (BP-1) vs the current inspector

**Delta.** The P5 inspector (property sheet, edit cells natively) is grammatically
superseded: digit column keyed by property NAME (D21, shared with search), focused
row 30→36px with an anchored type-to-filter editor over the three-layer value pool,
`MORE PROPERTIES · N` collapse, CONNECTIONS (typed relations / backlinks / body
wikilinks), Obsidian row menu, footbar contract, kind-tuned core visibility — ONE
component, never forked per kind, reused verbatim by capture/inbox (BP-5), tasks
rail (BP-6), files rail (BP-7), widget config (BP-8), settings mirror (BP-13), and
the import funnel (BP-14). This is the highest-leverage single build in the set.

**Core/seed/FFI.** Small and clean: per-property display attributes on the
definition entity (icon, core-flag per kind, hide-on-kind, hide-when-empty, digit
key); a usage-count/distinct-values service (the facet-count service from P6 already
computes hypothetical result sizes — extend it); rename/retype = editing the
definition entity (exists, "the uniform way"); relations = `related` cells +
promoted relation entities; backlinks are already derived-never-stored. Bidirectional
delete is a composite command. The three-strata connections view is a projection.

**Shell.** The big one: native focus choreography (digit into collapsed MORE,
two-stage Esc, Alt+→/←), anchored editors, the row menu, per-kind presets
(= apply a type, feature-map #33). Everything downstream mounts this component, so
it comes immediately after the spine.

### 2.3 Shell v2 IA (BP-4) vs the current chrome

**Delta.** The current chrome is P1–P3 of Liv-as-shipped (three rows, spaces
sidebar, per-workspace native tabs, palette) with our own simplifications. Shell v2
is Liv-as-amended: activity rail of exactly 10 with the Notes-above-the-hairline
seam, two-tab left panel (Spaces | Vault) absorbing Props→facets and Saved→Pinned,
Home hub + workspace stamping, favorites row sharing ONE pin source with
Spaces›Pinned, global tabs with category-lock/groups/melt shading, TWO history
systems (places history + per-content-tab back-stack), right panel as five lenses
(Metadata = BP-1, Copilot, Outline, History, Graph), Layers = workspace layout
snapshots. Usefully, BP-4 *resolves* several liv-ui-map §6 open decisions in the
"approved, unshipped" direction (items 10, 11, 16, 18 — two-tab sidebar, History
rename, assist-chip removal, tab melt): jump straight to the approved state, don't
port the shipped one.

**Core/seed/FFI.** Modest: pins as small entities (one source, heterogeneous
targets: object/view/workspace); workspace default-property stamping is a creation
default (clerk-visible chip, never silent); layout snapshots = named markers on log
positions (liv-ui-map §4.1) for the *content* part, shell prefs for pure geometry.
The two histories are **shell state, not entities** (constitution: transient UI
state is never an entity) — persisted as shell preferences.

**Shell.** Large, but incremental: the rail and two-tab panel are re-arrangements of
existing parts; tab groups/locking/melt and dual history are the new muscle. The
Tauri-isms (hide-to-tray, CSS shade ladder) translate to native materials — already
our directive.

### 2.4 Chip-forward object rows (BP-7 V2) + VALUE_HEX

**Delta.** One render kit — row (32–36px), card, tile — with a hard budget: type
icon · title · ONE anchor chip (project → subject → people → role-date) · status
dot · modified; empty fields never render; chips are live filters everywhere
(click = include, Alt+click = exclude); every value wears a hash-stable,
theme-independent hue identical across rows, facets, inspector, graph, tree dots.

**Core/seed/FFI.** The anchor is a derived precedence rule — a pure function in the
shell or a service helper. VALUE_HEX is one deterministic string→hue function;
trivial to implement, but it *is* a visual-law question: the lotus color budget was
"one accent + five status dots," annulled for UI-taste by the Liv pivot, and
liv-ui-map §3.6/§6-23 keeps the value-hue subsystems "re-hued." The blueprints
additionally found cross-page hue disagreements (BP-12 Q3) — the seed table needs
one owner pass (§5).

**Shell.** Build the kit once, then every surface (search results, capture wall,
task tiles, file rows, graph tooltips, agenda) mounts it. Cheap after the first.

### 2.5 The one-AI-grammar (BP-10 + CAT) vs the current inbox-proposals seam

**Delta.** Halo (points, in place) → suggestion card (visible diff, accept/dismiss,
alternatives, digits) → plan card (AUTO/REVIEW/BLOCK risk tiers) + Copilot
(selection rewrites) + Jarvis (scoped chat with a structural write gate) + ONE queue
home (Inbox › Tidy). The catalog pins 49 behaviors, each with trigger / seam /
dismiss-id / vocabulary source.

**Mapping.** This is the *smallest* structural delta because lotus's two-doors law
already is the grammar: answerer = AUTO reads (add the visible tool log); clerk
proposers = suggestion cards (deterministic ids ≡ proposal identity; dismiss ≡
declined sidecar; "never re-asks" is structural — feature-map cautionary tale 5);
agents = plan cards (one drafted transaction, one confirmation, one undo);
Inbox › Tidy ≡ lotus's one inbox, by law. Accept-runs-the-manual-seam is
structurally true (proposals are transactions of ordinary commands). The
prompt-injection guard is the write gate, by construction.

**Core/seed/FFI.** A tool-tier registry (tier is a property of each tool, floors,
raise-only); provenance already exists (`by:assist`/`by:jarvis` = Author on the
command); 30s-undo = the undo we have. CAT's "universal SuggestionTray" is — to the
letter — the persisted proposal queue we shipped in Milestone 7; do not build a
second one.

**Shell.** The halo/anchored-card presentation layer (marigold presence over
heterogeneous hosts), the plan-card idiom with hold-to-confirm, Copilot's streamed
preview coalescing to ONE command on accept, and Jarvis's pause/resume transcript.
The T3 table in feature-map already maps all 20 behavior families; CAT refines them
to 49 rows — port deterministic proposers first, model brains second (existing law).

### 2.6 Files as real sibling folders on disk vs reference-only files

**Delta.** The blueprints make the filesystem the product's trust story: captures
land as files in `library/inbox/`, commit physically moves them to kind pools,
pools are flat real folders (D06), rename edits the filename with per-pool
uniqueness + collision prompts (D07), H1-edits rename the file (BP-11), frontmatter
mirrors two-way with the DB "authoritative" (D05), views live as `.liv/views/*`
files on disk, onboarding indexes an existing folder in place, and a destination
line ("will save to →") is permanent UI everywhere.

**The conflict.** Lotus's persistence law: the append-only log is the disk truth;
foreign files are referenced (path + content hash), never moved, copied once at
import; caches rebuildable; no watcher, no mirror, no second truth. liv-ui-map
§4.3(1) already ruled the live mirror impossible-without-the-disease, and
feature-map's cautionary tale 1 documents the exact bug class (Liv's 2.5-second
self-write suppression window). *This is the one place the blueprint set and the
constitution point in opposite directions*, and it is load-bearing for BP-2, BP-5,
BP-7, BP-13, BP-14, and parts of BP-11.

**The recommended shape (needs the ruling, §5-R1).** A three-way split that keeps
one truth and keeps the promise:
1. **Foreign bytes** (pdf/docx/xlsx/images) — already real files; at import they may
   be *copied once* into `library/<pool>/` (import copies is existing law), then
   referenced + hashed. Pools-on-disk for foreign files costs nothing
   architecturally. Drag-out offers the real path (feature-map #46). A changed hash
   re-extracts.
2. **Native objects** (notes/events/contacts/views) — entities in the log, with a
   **materialized-export service**: a continuous *one-way* projection of the box
   into `library/…` as `.md`/`.base` artifacts, rebuildable, never read back except
   through explicit import. The destination line stays honest ("will export to →");
   the Finder story ("your notes survive the app") stays true; the watcher/
   suppression bug class stays unconstructible. Rename/H1-edit updates a *cell*;
   the export artifact follows; per-pool name uniqueness becomes an export-layer
   collision policy (names are cells; ids are identity — duplicate names stay legal
   inside the box, feature-map T4).
3. **Inbound** — one designated import folder MAY be watched (liv-ui-map §4.4:
   watching for NEW material is import, not a mirror). The BP-14 Downloads toast
   rides on this carve-out; general watched-folder auto-import stays refused.

If the owner instead overturns the law and wants disk-as-truth, that is a different
core (a reconciler, not a log) — say so out loud before any of these surfaces are
designed. The assessment assumes the split above.

---

## 3 · SURFACE-BY-SURFACE MAP

| BP | Surface | State | What exists / what changes |
|---|---|---|---|
| **BP-1** | Inspector V3 | **Partial — supersedes P5** | P5 inspector ships (property sheet, native cell edits, presets-as-types). Rework to the V3 grammar: digit column (D21), anchored layered-pool editors (pool layers exist: used values query + starter seed + create), MORE collapse, CONNECTIONS strata (backlinks derived; typed relations = promoted entities), row menu → definition-entity commands, kind-tuned core via expectations. New core: display attributes on definitions, usage-count service. |
| **BP-2** | Onboarding | **New** | Nothing exists. Gated on the files ruling (vault bootstrap, "will create →" preview), the seed-vocabulary layer (D17 — gazetteer + starter library exist; the seeded-vs-used distinction in tree/facets is new), and BP-1/BP-7 kits. Coach-bubble choreography is pure shell. Late (with P16-equivalent). |
| **BP-3** | Search palette | **Partial — supersedes P6** | P6 ships: centered ⌘F palette, DSL, facet chips *with counts as hypothetical result sizes* (Liv's one great idea, already ours), search service. Add: D21 digit map + include→exclude→off cycling, qualifier↔pill round-trip on ONE query object, three display modes, never-cap + fixed kind order, Filters panel = the one D22 engine, Save-as-view wiring (bookmark verb exists), '>' command mode (commands-as-objects — annulled refusal, now in scope), footer Export (export service). Drive/Web scopes stay **fenced** (one-integration law) — ship the scope-tile UI with This-vault only. |
| **BP-4** | Shell v2 | **Partial — supersedes current chrome IA** | P1–P3 ship (rows, rail, spaces, per-workspace tabs). Rework per §2.3: rail-of-10 + seam, two-tab left panel, hub + stamping, one pin source, tab lock/groups/melt, dual history (shell prefs), right panel five lenses, Layers, File/View menus. Resolves liv-ui-map §6 items 10/11/16/18 in the approved direction. |
| **BP-5** | Capture + Inbox (Route/Tidy) | **Partial — replaces the Today one-line capture (the owner's loudest complaint)** | Exists: capture() + ⌃⌥Space popup (asks nothing — already law), proposal inbox + declined sidecar, clerk name-proposer slot (T3 #4), merge composite (feature-map #4). New: Keep/Composer capture surface with card wall, Route as the orphan router (what's-missing is a query; commit = stamp cells + [pending files ruling] the export/move), Tidy = the proposals queue rendered per-row with the shared BP-1 inline inspector, two-answer merge routing proposer. Destination-line semantics await §5-R1. |
| **BP-6** | Tasks (5 modes + rail) | **Partial** | P8 ships: task substrate, checkbox, priority, Open/All/Done. New: Board lens (feature-map #18 demanded justification — the owner's blueprint IS the justification; columns = status option entities, drag = one command), Schedule lens (consumes the spine; reuses calendar machinery), Cards via the BP-7 kit, Write-down bulk-entry mode (the refused capture-token parser is still refused *at capture*; write-down is a distinct bulk-entry surface with a deferred transactional sync — annulled-refusal territory, flag in review), segmented [Selection|View] rail (owner ruling 2026-07-09) where [Selection] = BP-1 and [View] = the view entity's own cells. Workroom pop-out = editor over the same entity (mirror contract). |
| **BP-7** | Files & Library | **Partial** | P7 ships: files by reference + hash, extraction cache feeding search, Library saved view, open-externally. New: pool browsing (gated §5-R1: foreign files copy-in yes; native pools = export projection), four lenses over one filtered collection (Table exists as a renderer; Folder lens = disk truth for foreign/exported artifacts; Gallery must justify itself — images are the cheap case; Kanban shares BP-6's board), the ONE filter engine (D22) extracted from P6 and reused, property-display picker (view config), drag-out (file promises), drag-in → inbox, E3 collision prompt (export-layer policy). Views section surfaces view entities (never fake a `.liv/` tree if R1 lands on projection). |
| **BP-8** | Dashboard / Mission Control | **New** (old refusal annulled) | Widgets = pure lenses over saved views/queries with ONE shared scope context — exactly "lens + saved view," no view-builder needed (the anti-Notion rule is our fence restated). Habit check-ins = small entities + projections computed-once (feature-map #16); time entries = entities (deferred #22, now scheduled); metric chart = first chart lens (must justify — it now does); project summary = answerer (T3 #14); what-next = deterministic proposers + answerer, dismissals via sidecar. Overlay entry (Shift+Tab carve-outs) is shell. Layout = shell prefs or a view entity per scope (BP-8 OQ-2 → prefer view entity). |
| **BP-9** | Calendar + Contacts | **Partial — SUPERSEDES the just-shipped P10 calendar's basis** | Keep: the month/week/day/agenda grids, mini-month, day panel plumbing, recurrence engine, honest window. Change: data basis from kind filters → calendar-role date set {date, due} (lookup roles never render — the off-calendar strip is the point); subscriptions = saved filter sets over an ordinary `calendar` select property (color law: option-entity hues); drag-to-reschedule + span grips = one command editing the date cell (mirror contract with the inspector row); today-cell-as-daily-note (needs P11 daily notes); embedded day-panel inspector → segmented [Selection|View]; task-due checkbox in-grid = the same status write. **Google two-way sync: refused** — one-way ICS import when the files integration proves the pattern (feature-map #43); BP-9's googleId/etag machinery maps to `external-id` + feed-owned-fields-refresh on *import*, and OQ-A's conflict card becomes a Tidy proposal on re-import. Contacts: new light surface — person type exists; groups = saved views; @-mention writes the people cell; contact page = a note entity, rail is the only editor. |
| **BP-10 + CAT** | AI presence + 49-behavior catalog | **Partial — the seam exists, the faces are new** | See §2.5. Exists: two doors, queue, sidecar, provenance, undo, clerk v0 (dates/mentions, sweep-behind-write, duplicate drop), recurrence sweep. New: halo/card/plan-card presentation, tool-tier registry, Copilot streamed-preview → one command, Jarvis loop with the structural write gate (constitution: quarantine IS the gate), the deterministic proposer library (CAT M/N/O/T families — port as regex-grade proposers first), answerer surfaces with citations-as-deep-links. Ratify liv-ui-map §6-20 (per-write cards vs one-transaction agents) — P13 assumed per-write cards; BP-10's plan card agrees. |
| **BP-11** | Composer | **Mostly built — deltas only** | P4a–d ship: native live-preview marks/blocks, input rules, wikilinks, block widgets (code/callout/rule), content history (log-native restore). Deltas: H1-as-title *convention* (name is a cell; no file rename under R1-projection — the export artifact follows), LinkPicker subnote materialization (`parent` reference, feature-map #11), slash menu completion, checklist promote-to-task (worked example 3), selection-AI single-write contract (T3 #7 — agent transaction, preview inline), snapshots = named log markers (exists). **Rulings:** embedded interactive data-view fences (§5-R4: pill-that-opens-lens vs read-only live projection vs full interactive embed) and ghost text (deferred T3 #18; BP-11's own OQ-1 recommendation — OFF by default — is acceptable if built read-only). Outline/History rail tabs fold into BP-4's five-lens panel. |
| **BP-12** | Graph (vault overlay + local) | **New** (deferred candidate, now scheduled) | Pure projection: value nodes from distinct area/project/subject values, membership + wikilink edges, orphan predicate, one-hop-through-value BFS — all overlay queries. Canvas + hand-rolled physics is real shell work (no d3 = fine, we're native anyway). VALUE_HEX must be settled first (§5-R3). Ship local graph (rail tab) before the vault overlay. |
| **BP-13** | Settings | **New** (P15, reshaped) | Settings window annulled-into-scope. Settings-as-objects searched by the one grammar = commands/settings as metadata-carrying entries (BP-3 command mode shares this). Properties panel = the definitions editor (core exists; vault-wide rename/retype with count-confirm = one grouped transaction + undo — no confirm dialogs, matches our dialog law). Vocabulary shelves = option/gazetteer editing. Two scopes: vault-scoped cells in the box vs app-scoped shell prefs (`.liv/settings` only if R1 lands on projection-with-artifacts). Shortcut editor gated on §5-R2. Theme/font panels: **cut** — system light/dark + lake green stands (liv-ui-map §3.7); appearance reduces to reading-mode + glyph-strength + density-legal knobs. |
| **BP-14** | Import / Export | **Partial concepts (P12/P14), new surfaces** | Aligned by design: import copies + `external-id` no-op re-import (#41), one batch = one transaction = one undo (#40), bookmark folders → grouped subject proposals, export service takes a query (#42), title-that-arrived survives. New: the resumable funnel — staging lives as *scrap entities in the box flagged staged* (nothing else survives restart honestly; "pre-vault" purity is a Liv-ism — a staged scrap that never commits is trashed wholesale), Commit = the one grouped transaction; Downloads toast rides the §4.4 inbound-watcher carve-out (§5-R5); per-type rules = a small settings map; export compose (group-by up to two levels, live tree preview, per-file failure list); **move-out** = export + trash-with-dead-link-flags, typed-confirm (the one sanctioned scary dialog). |

---

## 4 · PHASED PLAN

Keep the loop (design workflow → slices → failing-test-first for core → review).
Replace P11–P16 with the following; smallest-first, spine and grammar before
consumers. Slice counts are rough (a slice ≈ one committed, reviewed increment at
the granularity of the P10 slices).

**P11 — The amended spine (core/services/FFI). ~6 slices.**
11a role-typed date seeds + calendar-set config (failing tests first);
11b span/range value + editing commands; 11c recurrence generalization to any
dated entity + exception-override tests; 11d universal status: option entities
(for-type, order, hue) + per-kind offer queries + entry default; 11e property
display attributes + usage-count/distinct-value service; 11f FFI seams (with_box +
Committed tags throughout). **Gate: §5-R6 (status split-or-union) ruled first.**
No visible UI change yet except the calendar quietly re-basing.

**P11.5 — The grammar kit (shell). ~8 slices.**
V3 inspector component (digit column, anchored editors, MORE, footbar, row menu,
CONNECTIONS), the D21 digit map registry (one map, hint visibility as a setting),
the BP-7 V2 row/card/tile kit + anchor precedence + status dot, VALUE_HEX function
+ seed table (**gate: §5-R3**). Replace the P5 inspector in place; mount the row kit
in Tasks/Library/Search as a pure re-skin.

**P12 — Capture, daily notes, Inbox (BP-5 + old P11 content; the Today rework). ~7 slices.**
Daily note = ordinary note + date cell, Ctrl+D open-or-create; Keep/Composer
capture surface + card wall; Route (orphan query + commit stamping + auto-advance);
Tidy = proposals rendered per-row with the shared inspector; merge-routing proposer
+ conflict moment; templates via type expectations. This lands the owner's loudest
live-testing complaint early. **Gate: §5-R1 for destination-line wording only**
(stamping works either way).

**P13 — Search v2 + the one filter engine (BP-3). ~6 slices.**
Extract D22 as the single engine (palette/Files/Tasks/view-tab share it); query
object with qualifier↔pill round-trip; digit facet cycling; display modes;
save-as-view + open-in-view; empty states; command mode. Supersedes P6 palette
internals; keeps the search service and facet-count service.

**P14 — Tasks v2 + Calendar re-base + Contacts (BP-6 + BP-9). ~9 slices.**
Board lens (columns = option entities, drag-write, fold Done); Schedule lens +
unscheduled tray; [Selection|View] rail; write-down mode (flag for review);
calendar-as-lens finishing (spans + grips + drag-reschedule + off-calendar strip +
subscriptions-as-filters); today-cell = daily note (from P12); contacts surface +
groups + @-mention people writes. **Google sync stays fenced; ICS one-way lands
here or in P15 if the fence opens.**

**P15 — Files/Library v2 + Import/Export (BP-7 + BP-14). ~10 slices.**
**Hard gate: §5-R1 ruled.** Materialized-export service (if ruled as recommended);
pool browsing + four lenses; property-display picker; drag-out/drag-in; import
funnel (staged scraps + one-transaction commit + collision policy); Downloads
inbound watcher + per-type rules (**gate §5-R5**); export compose + move-out.

**P16 — AI presence (BP-10 + CAT; replaces old P13/P14). ~10 slices.**
Tool-tier registry; halo + anchored card faces over the queue; plan card + BLOCK
hold-to-confirm; deterministic proposer library (CAT families, ids = proposal
identity); answerer surfaces (project summary, what-next reads); Copilot selection
rewrites (one coalesced command); Jarvis loop + transcript + write gate. Model
brains socket in last (deterministic first — existing law).

**P17 — Shell v2 (BP-4). ~9 slices.**
Rail-of-10 + seam; two-tab left panel (facet counts absorbed by P13); hub +
stamping chip; one pin source + favorites row; tab category-lock + groups + melt;
dual history (shell prefs); right panel five lenses (Outline/History fold in from
the editor); Layers. Sequenced late deliberately: it's disruptive chrome-wide and
consumes P13/P16 pieces — but 17a (rail + panels) can be pulled earlier if the
current chrome chafes.

**P18 — Dashboard + Graph (BP-8 + BP-12). ~8 slices.**
Habit check-in entities + projections; time entries + single-active-timer shell
invariant; widget board = lenses over saved views + one scope context; overlay
entry; local graph rail tab; vault graph overlay + physics canvas.

**P19 — Settings + Onboarding (BP-13 + BP-2; replaces old P15 + the P16 remainder). ~8 slices.**
Settings modal + search-over-entries; properties/vocabulary panels; shortcut map
editor (**gate §5-R2**); capture/naming, library-rules, AI panels (BYOK-in-Keychain
only — no subscription proxy); startup; onboarding tour + vault bootstrap
(**gates §5-R1, seed-layer distinction**), 60-second script.

Cross-cutting every phase: the D21 map rows a surface owns, empty states, the
BP-7 budget, context menus/DnD, and re-review of any blueprint OQ that the phase's
design workflow touches. The existing per-phase review discipline stands — the P1–P10
history shows the review pass catches 5–30 real findings per phase; budget for it.

---

## 5 · RULINGS NEEDED FIRST

The cross-page rulings the blueprint index itself demands, plus the conflicts this
assessment found. Each needs ONE written owner call before the owning phase's
design workflow starts.

**R1 · Files: real-folders-on-disk vs the log (blocks P15, colors P12/P19; the big one).**
The blueprints' central trust promise vs the constitution's one-truth law
(§2.6). Recommended: the three-way split — foreign files copy-in-once to real
pools; native objects get a continuous one-way materialized export into
`library/` (rebuildable, never read back); one designated inbound import folder
may be watched. Explicitly includes sub-rulings: D05 two-way frontmatter mirror
(recommend: export-only mirror; import parses frontmatter once), D07 rename-on-disk
(recommend: names are cells; uniqueness is an export-layer policy), commit-as-move
(recommend: commit = stamp + re-materialize), and `.liv/` in shared bound folders
(BP-13 OQ-2 — moot under projection: recommend keep-local, export artifacts only).

**R2 · The shortcut-map owner (blocks P11.5, P13, P19).**
One global digit/shortcut map (D21) shared by inspector, search facets, suggestion
cards, and settings — who owns assignments, are command bindings in the same table
(BP-13 OQ-1, recommend one table two sections), what binds universal back/forward
(BP-4 Q1), rail Ctrl+1…7 (BP-4 Q4), digit-8 date crowding (BP-3 Q2 — recommend one
date facet that asks which role). Note this *reverses* the old fixed-map law the
same way the palette reversal went (interface.md 0.5) — the owner should say so in
writing.

**R3 · The value-hue seed table (blocks P11.5, P18).**
VALUE_HEX as one deterministic hash + a seed table every page agrees on (BP-12 Q3
found cross-page disagreements), reconciled with the lotus color law (liv-ui-map
§6-23: colorful chips always-on vs opt-in). One pass, one table, then it's frozen.

**R4 · The binder ruling (BP-1 OQ-1; blocks nothing mechanical, shapes seeds).**
What is SSK/a client/a car: entity hub (a seventh kind) vs client-as-project.
Recommend entity-hub-as-plain-entity: lotus has no fixed kind set — a "binder" is
an entity whose type is `organization`/`client` with `related` references;
CONNECTIONS is the binder view. No core cost either way; pickers need the answer.

**R5 · The inbound-watcher carve-out (blocks P15).**
Ratify liv-ui-map §4.4: a watcher on ONE designated import folder (the BP-14
Downloads flow) is import, not a mirror; everything else stays sweep-at-open.
Includes BP-14 OQ-4 defaults (recommend: unanswered asks queue into Route, no
30s vanishing).

**R6 · Status: split-or-union (blocks P11).**
Universal status with per-kind vocabularies forces the deferred shared-select
decision. Recommend: ONE `status` definition, option entities scoped by `for-type`
reference (union namespace, per-kind offer, board-column order + hue on the
option). Also ratify: type-seeded defaults are *seeds*, user-editable per kind (R2's
own text), and "no status" is always valid.

**R7 · Google Calendar (blocks the BP-9 sync work-package only).**
The blueprint specs two-way sync; the architecture refuses it ("sync engines are
where unified information systems go to die"). Recommend: hold the refusal — one-way
ICS import behind the files fence, feed-owned-fields-refresh merge policy kept
verbatim, conflict cards as Tidy proposals on re-import (answers BP-9 OQ-A). If the
owner insists on two-way, that is a fence-opening with its own design workflow,
not a calendar slice.

**R8 · Embedded data-views in notes (blocks the BP-11 delta slice).**
Live interactive query-blocks in note bodies vs the fenced authoring-surface
refusal. Options: (a) view pill that opens the lens (current law), (b) read-only
live projection block (renders, never edits), (c) full interactive embed (BP-11's
spec — drag writes status in-body). Recommend (b) now, (c) only if daily use asks;
either way the query edits only in the view entity.

**R9 · Ghost text (BP-11 OQ-1; small).**
Deferred by feature-map T3 #18 (silent-assistant failure mode). BP-11's own
recommendation — OFF by default, per-vault opt-in, forward-only, acceptance is the
user's keystroke — is compatible; ratify or keep deferred.

**Also ratify in passing** (already ruled in-repo, blueprints agree): the three
impossibles (liv-ui-map §6-19 — import/export not mirror, native link cards not
webviews, mermaid-as-code); per-write plan cards vs one-transaction agents
(§6-20 — BP-10 sides with per-write REVIEW cards; keep); write-down mode's bulk
parser as a distinct surface (never at capture); "spawn on completion" wording
read as virtual occurrences (no spawn, no debt).

---

*Bottom line: the core doesn't just survive this blueprint set — most of the set is
the core's own laws wearing Liv's clothes. The work is one honest spine extension,
one inspector, one files ruling, and a long tail of disciplined shell phases.*
