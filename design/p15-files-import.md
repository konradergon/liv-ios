# P15 Files / Import & Export — the "run a tool, don't live in a vault" phase

P15 mounts the **import** and **export** services and their transient surfaces
over the **by-reference file model already landed in P7** (`services/src/files.rs`:
`add_file`/`resync_file`/`extracted_text`; the hash-keyed sidecar cache; the
`file` + `format` seeds; `props::EXTERNAL_ID`). The two governing blueprints —
bp7 (Files/Library) and bp14 (Import/Export) — are **deeply vault-coupled**
(pools = real folders, an on-disk vault tree, on-disk rename, `.base`/`.liv`
view-files, collision prompts, a Downloads watcher, export move-out). Every one
of those collides with the constitution's persistence + timer + names-are-cells
laws, so P15 keeps the blueprints' *ideas* and reconciles their *mechanics*:
a "pool" is a saved facet view, not a folder; the "3-box funnel" collapses
because **creating the entity IS the commit** (there is no vault-write to stage
for); import **references** binaries and **ingests** native content but never
copies bytes inward; export is the one sanctioned **outbound copy**, a
projection and never a mirror. AI classification is quarantined to P16; the
watcher and move-out are refused outright. **Net: two new services, ~three new
FFI verbs, two additive seeds (`url` + `link`), two content-pane surfaces + a
Library lens upgrade — and no `core` change.**

> Provenance: this design is synthesized from a P15 design workflow (two
> substantive angles — *reconciliation* + *surfaces* — plus a synthesis pass;
> the *services* angle failed its structured-output cap and the *scope* angle
> returned junk, so §3 and the substrate-gap decisions below are validated
> directly against the code, per the house rule "test-drive core changes, don't
> trust the doc's reasoning"). The two substrate gaps the failed services angle
> would have caught — **link entities are unseeded** and **there is no
> markdown↔spans parser** — are resolved in D6/D7 and §3.

## 0 · Owner decisions (recommendations, before mockups)

Each is a genuine fork; the recommendation is the most lotus-faithful reading.
The parent may confirm or override.

**D1 — Where does the pre-commit import buffer live? RECOMMEND: shell scratch
pre-commit, the P12 Inbox for post-commit routing (a hybrid).** The two angles
split: mint cheap orphan entities at drop (reuse) vs. keep candidates as pure
shell state until one explicit commit. bp14 a6 ("nothing written at this stage")
and #40 ("Import N → the ONE transaction, one undo") both read cleanest when the
**commit button is the transaction**, not the drop — and minting discardable
entities at drop manufactures junk that soft-trash must then mop up (scar #6:
"UI state as content becomes junk" argues *for* shell state here, the same
category as the already-sanctioned editor draft). So the pre-commit pool /
deferred shelf is shell state (an `ImportFunnelModel` + a UserDefaults JSON
shelf); **after** the one `commit_batch`, entities that land unrouted are
triaged in the **existing P12 Inbox Route/Tidy lens** — no bespoke rich review
pane, no inspector refactor.

**D2 — Does the funnel's review pane get the full inspector grammar? RECOMMEND:
no — defer the `InspectorPane`→`PropertyRowList` extraction.** Under D1 the
pre-commit funnel needs only inherited project/area default chips (editable) + a
candidate list + discard. Rich per-property editing lives post-commit in the
Inbox, which already has the grammar. Do not refactor `InspectorPane` in P15.

**D3 — Gallery lens in P15, or defer? RECOMMEND: Table only; Gallery is a named
candidate, deferred.** #35/#18's law is that a renderer earns its slot with real
data volume — "it's cheap" is not the test. Build the lens switcher 2-slot-ready
but ship only Table; promote Gallery if a real library shows image volume.
Kanban-over-files is **refused**, not deferred (files carry no status
vocabulary; renderers key on properties, not types).

**D4 — Import service placement. RECOMMEND: a new `services/src/import.rs`**
(keeps `files.rs` focused), `commit_batch(session, items, defaults)`. The owner
may fold it into `files.rs` if preferred — non-contentious.

**D5 — Export selector: query- or id-driven? RECOMMEND: id-driven at the service
boundary.** bp14 a28's per-item uncheck means the shell resolves `filter query →
matched set − unchecks → id list` and hands the service resolved ids; the P13
filter engine stays the *selector* in the UI. Two functions:
`export_plan(store, ids, group_by) -> ExportTree` (pure, computes the a30
preview) + `export_write(store, plan, dest) -> io::Result<u64>` (copy-only).

**D6 — Link entity substrate. OWNER RULED: seed a `url` text property + a `link`
type (additive, idempotent guard).** #39 ("a link entity — url + title scraped
once; open launches the browser; no webview, no re-unfurl") wants links as
first-class objects; no `url` property or `link` type exists in the seed today.
Minimal additive seed, in the `seed_files` idiom: a `url` property (text) + a
`link` type. A dropped tab → `Create` + `type=link` + `url` cell + `name` (the
scraped title), so Library facets and kind filters key on the `link` type.

**D7 — Markdown import/export body fidelity. OWNER RULED: full rich markdown
parse in P15** (fidelity over schedule — consistent with "copy Liv exactly").
There is no markdown↔spans parser today, but the landed content model is a
*complete* markdown target: `Span::{Text(marks: BOLD/ITALIC/CODE/STRIKE),
Break(Block), Ref(Id)}` with `Block::{Body, Heading(1–6), Quote, Bullet{depth},
Ordered{depth}, Task{depth,done}, Code{lang}, Callout{kind}, Rule}` — CommonMark
maps to it almost 1:1. So P15a builds a real `parse_markdown(&str) -> RichText`
using the **vetted `pulldown-cmark` crate** (the same "vetted, not hand-rolled"
call P7 made for `sha2` — a CommonMark parser must not be hand-rolled) plus a
spans→markdown renderer for export. Three bounded limits, recorded as DELTAS:
(a) `[[Wikilink]]` → `Span::Ref` needs name→id resolution, done in a **second
pass** after the batch's entities exist (a forward ref to a not-yet-imported note
resolves once its target lands; an unresolved name stays literal text and the
clerk/backlinks reconcile later); (b) inline `[text](url)` has no href slot in
the span model → it keeps its visible text (a link *mark* is a separate
content-model change, out of scope); (c) YAML frontmatter is parsed as flat
`key: value` (+ simple `[a, b]` lists) by a minimal hand parser — nested YAML
defers rather than pulling in `serde_yaml`. Export renders marks + blocks back to
markdown and cells to a frontmatter block.

**D8 — Sandbox posture. RESOLVED (not a fork): the app is not sandboxed** (no
entitlements file, no security-scoped bookmarks; P7's `addFileFlow` uses
`NSOpenPanel → url.path` directly). So bulk drag-in can re-hash dropped files and
export can write to a chosen dir without scoped-bookmark machinery. If the app
ever sandboxes, revisit (a bookmark per referenced file keyed by `hex(hash)`).

## 1 · Load-bearing decisions (recorded deltas)

**LB1 — Import = *reference* binaries, *ingest* native content, never copy bytes
inward.** (a20 "files copied to type pools", #41 "import copies" vs #34/P7's
by-reference law.) "Copy" means the *log* ingests meaning: a link → a link
entity (url+title scraped once, #39); a scrap → `capture()`; a markdown/native
item → a note entity with content spans + frontmatter cells. Binaries become
`File` **references** via `files::add_file` (path+hash, bytes untouched). No
`library/` directory exists; nothing is copied into any pool.

**LB2 — One transaction, one undo, at the COMMIT button — not at drop.** (a20,
#40.) The "collected → staged → committed" states collapse to `shell-scratch →
committed`; `commit_batch` wraps every item in one `session.commit`, so one ⌘Z
reverts the whole import. Per-item routing afterwards (project/subject cells set
in the Inbox) is its own undo step.

**LB3 — `external-id` dedupe makes re-import a literal no-op.** (a3/#41,
`props::EXTERNAL_ID=12` seeded.) File external-id = `hex(hash)`; link
external-id = the url; imported-note external-id = the source path (or a
frontmatter `id`). `commit_batch` skips any item whose external-id matches a
live entity. Re-dropping the same `bookmarks.html`/folder yields zero new
entities.

**LB4 — "Pools" are `format`/`type` facet views, never folders.** (a2–a4/a16/a26
vs files-as-truth REFUSED, P7 never-move-bytes.) A pool is a saved view faceted
on the `format`/`type` property over the P13 DSL (`format:pdf`, `type:link`);
counts are live query counts; nothing is "in" a pool — entities *match* it. No
pool store, no vault tree, no on-disk rename.

**LB5 — Export is the one sanctioned OUTBOUND write; copy-only; a projection,
not a mirror.** (a31/a33 vs never-move-bytes, scar #1.) The move-out arm and its
typed-confirm are removed from the signature entirely. `export_write` copies
referenced file bytes and renders native entities to `.md` into a user-chosen
dir; the log records nothing and keeps no back-reference. Doc-comment: "export
is a projection, not a mirror."

**LB6 — Import & Export are content tabs, not surfaces.** (bp14 a1 "no rail
slot".) The `Surface` enum is untouched; add `TabKind.importFunnel` /
`.exportComposer` (bare `Codable` markers) reached by ⌘⇧I / ⌘⇧E + File menu +
two Library-header icons + palette entries. Heavy funnel/composer state lives in
separate `ObservableObject`s looked up per active tab, never in the enum (keeps
tab persistence lean, scar #6).

**LB7 — File rows use `format` as the ONE anchor chip; one filter engine.**
(a19/a10 vs color law + D22.) `anchorChip(for:)` (RowKit.swift:132) returns a
file entity's `format` as its anchor chip — text + at most a small tinted dot,
never the value rainbow. Any in-surface narrowing routes through the P13 DSL,
never a parallel matcher.

**LB8 — The bookmark-folder→subject proposer is deterministic (no LLM).** (a8,
#40.) Folder / tab-group names arrive as a **grouped, severable clerk proposal**
for `subject`/`related` (constitution 1.3), dismissals to the declined sidecar
(scar #5). The rule "a title that arrived with the link survives" (#40) is a
`commit_batch` invariant — a later scrape never clobbers a provided title.

**LB9 — Links + markdown-frontmatter are new *substrate*, additively seeded.**
(D6/D7.) `seed_files`-style additive guards add a `url` property + a `link`
type; the frontmatter importer creates property definitions on demand (the
`lotus_add_property_at` seam from P12). No `core` change; a pre-existing box
gains the seeds on next open, idempotently.

## 2 · Reconciliation table (every annotation ruled)

**bp7 — Files / Library**

| Ann | Verdict | Note |
|---|---|---|
| a1 Import/Export as toolbar actions | **KEEP** | ⌘⇧I/⌘⇧E + header icons; "a tool you run" (#41/#42). |
| a2–a4 pool tiles = real folders | **RECONCILE (refuse folder half)** | Pools = `format`/`type` facet views (LB4). |
| a5 Views = hidden `.base` files | **RECONCILE** | Saved views are entities (query+renderer+config), not disk files. |
| a6 drop-onto-view = retag | **DEFER** | Positive-facet stamp as a command/proposal; nicety, past P15. |
| a7 Vault tree (on-disk folders) | **REFUSE** | files-as-truth / never-move (T4, P7). |
| a8 system rows (`.liv`/`.trash`) | **REFUSE / RECONCILE** | `.liv` refuse (log is truth); `.trash` = a `trashed` query, not a folder. |
| a9 content-tab melt chrome | **REFUSE chrome** | Lenses swap in place; no Liv tab row. |
| a10 type-to-filter box | **RECONCILE** | Same P13 DSL, view-scoped. |
| a11 filter = the one engine | **KEEP** | P13 palette (D22). |
| a12 quick-filter favorites | **KEEP** | P13. |
| a13 active-filter chips (Alt-exclude, digit facets) | **KEEP** | P13. |
| a14 property-display picker | **KEEP** | Table lens view config (#21); display only. |
| a15 four-lens switcher ⌃1–4 | **RECONCILE → 2** | Table KEEP; Gallery deferred candidate (D3); Folder + Kanban REFUSE. |
| a16 New-by-kind menu | **RECONCILE** | Create-by-type; drop "will save to library/<pool>/". |
| a17 table-header sort | **KEEP** | List/Table law. |
| a18 32–36px row budget | **KEEP** | `ObjectRow` landed; drag-out = the real file (#46). |
| a19 anchor chip | **RECONCILE** | `format` chip, text+dot, no rainbow (LB7). |
| a20 status dot (fixed five) | **KEEP** | Verbatim color law. |
| a21 row hover quick-actions | **RECONCILE** | Open/⋯ OK; ✦ suggest → P16. |
| a22 empty state | **KEEP** | Calm, names filter, one action. |
| a23 Folder lens (rename on disk) | **REFUSE** | never-rename-bytes; becomes the group-by control. |
| a24 Gallery budget | **DEFER** | Candidate renderer (D3/#35). |
| a25 Kanban lens | **REFUSE** | Files have no status vocab. |
| a26 drag-in COPIES to library/inbox/ | **RECONCILE** | add-by-reference; never copies (LB1). |
| a27 collision prompt (E3) | **REFUSE** | names-are-cells (T4/#11). |
| a28 per-pool uniqueness (R4) | **REFUSE** | moot in lotus. |

**bp14 — Import / Export**

| Ann | Verdict | Note |
|---|---|---|
| a1 File-menu Import/Export, content tab | **KEEP** | LB6. |
| a3 "Resume import — N deferred" | **RECONCILE** | Deferred shelf = shell scratch (D1); palette entry re-opens the funnel. |
| a4 funnel inside a project (re-aims future) | **RECONCILE** | Default project/area *cell* per commit; append-only re-aims future (T4). |
| a5 progress meter | **KEEP** | Honest live counts (scar #3). |
| a6 pool drop zone (20–200 tabs / files / bookmarks.html) | **KEEP** | The one heavy net-new component; parses to shell candidates. |
| a7 pool card (favicon/title/domain/captured) | **RECONCILE** | Once-scraped title+url; favicon one-time, no unfurl loop/webview (#39). |
| a8 folder-names → candidate subjects | **KEEP** | Deterministic proposer, no LLM (LB8). |
| a9 scrap → Quick Capture | **KEEP** | `capture()`. |
| a11 deferred shelf (survives close) | **RECONCILE** | Shell UserDefaults JSON, never entities (D1). |
| a12 review header | **KEEP** | Chip/row grammar. |
| a13 V3 inspector rows, digit-jump | **RECONCILE → defer rich form** | D2: pre-commit shows inherited defaults; rich rows post-commit in Inbox. |
| a14 AI-suggested chip + alternatives | **REFUSE in P15** | Quarantined to P16. |
| a15 inherited project/area chips | **KEEP semantics / RECONCILE visual** | Real default cells; text+dot not solid-hue. |
| a16 Commit → Staged | **RECONCILE** | Commit = the one `commit_batch` (LB2); no separate staged store. |
| a17 Defer | **RECONCILE** | Shell shelf. |
| a18 Discard (30s undo) | **RECONCILE** | Pre-commit: drop the scratch item. Post-commit: soft-trash + ⌘Z; no bespoke timer. |
| a19 staged row | **RECONCILE** | Existing row grammar; "staged" is shell state. |
| a20 "Import 23 →" one transaction | **KEEP** | LB2; links→link entities (not `.md`), files→by-reference (not copied). |
| a21 destination line always visible | **KEEP / RECONCILE meaning** | Names what's *created* ("N links · M files referenced"), not a path. |
| a22–a26 Downloads watcher + per-type rules | **REFUSE** | timer/poller + silent-mutation law (T4). |
| a27 export select-by-filter | **KEEP** | P13 engine (D5). |
| a28 matched rows + per-item uncheck | **KEEP** | Needs a checkbox param distinct from `ObjectRow.toggle` (§4). |
| a29 structure composer (group ≤2 levels) | **KEEP** | `group_by: [PropId]` ≤2. |
| a30 tree preview | **KEEP** | `export_plan` computed projection. |
| a31 Copy vs MOVE-OUT | **KEEP copy / REFUSE move** | LB5. |
| a32 destination always visible | **KEEP** | scar #3. |
| a33 export button (copy immediate / move confirm) | **RECONCILE** | Copy-immediate KEEP; move + typed-confirm removed. |

Fenced / out of scope: **ICS calendar feeds** in the funnel — REFUSE in P15
(fenced until files prove the pattern, #43).

## 3 · Core / services design (~zero `core` change — validated against code)

All work is append-only commands + a read-only export projection + two additive
seeds. No `core` change. New services + FFI + seeds only.

**Seeds (`services/src/lib.rs`, additive, `seed_files` idiom — LB9)**

```
seed_links(session):
    guard: property_id(store, "url").is_some() → return          // idempotent
    create a `url` text property (working: true)
    create a `link` type entity (find_type("link") guards re-seed)
```

**Markdown ↔ spans (`services/src/content.rs` or a new `markdown.rs`, D7)**

```rust
/// CommonMark → the landed span model, via pulldown-cmark (vetted, like sha2).
/// [[Wikilink]] → a placeholder resolved in commit_batch's second pass;
/// [text](url) keeps its text (no href in the span model); fenced code, task
/// list items, headings, quotes, marks all map to Block/Marks.
pub fn parse_markdown(raw: &str) -> RichText;

/// RichText → markdown for export (marks → **/_/`/~~, blocks → #/>/-/1./- [ ]).
pub fn render_markdown(text: &RichText) -> String;

/// The YAML frontmatter block (flat key: value + simple [a,b] lists) → pairs;
/// returns (pairs, body). No frontmatter → (empty, whole input).
pub fn split_frontmatter(raw: &str) -> (Vec<(String,String)>, String);
```

**`services/src/import.rs` (new — D4)**

```rust
pub enum ImportItem {
    Link { url: String, title: Option<String> },   // → link entity (url+title once, #39)
    File { path: String },                          // → files::add_file (by reference, LB1)
    Note { frontmatter: Vec<(String,String)>, body: String, source_id: String },  // → note + cells (D7)
    Scrap { text: String },                         // → capture() (#9/a9)
}
pub struct ImportDefaults { pub project: Option<Id>, pub area: Option<Id>, pub subject: Option<Id> }

/// One transaction, one undo (LB2). external-id dedupe (LB3). Never copies bytes (LB1).
/// Note.body → paragraph-split plain TextSpans; frontmatter keys → cells,
/// creating property defs on demand (D7). Returns the created/skipped ids.
pub fn commit_batch(
    session: &mut Session,
    items: &[ImportItem],
    defaults: &ImportDefaults,
) -> Result<Vec<Id>, PersistError>;
```

Per item: compute external-id (`hex(hash)` File · `url` Link · `source_id`
Note); skip if a live entity already carries it (LB3). Else create/reference the
entity, stamp `defaults` as ordinary cells, and — for a Note — create any
missing frontmatter property defs (the `lotus_add_property_at` seam) before
adding their cells. All within one `session.commit`.

**`services/src/export.rs` (new)**

```rust
pub struct ExportTree { /* dir/file projection for the a30 preview */ }

/// Pure, read-only; computes the a30 tree preview from a resolved id set (D5).
/// group_by is clamped to ≤ 2 levels (a29).
pub fn export_plan(store: &Store, ids: &[Id], group_by: &[PropId]) -> ExportTree;

/// Copy-only (LB5). Native entities → markdown (content spans → md, cells →
/// frontmatter, D7); file entities → copy referenced bytes into the composed
/// structure. Commits NOTHING; reads originals, never mutates the log.
pub fn export_write(store: &Store, plan: &ExportTree, dest: &Path) -> io::Result<u64>;
```

**FFI (`ffi/src/lib.rs`, the landed `with_box` pattern)**

```rust
// mutates → Committed::Wrote (like lotus_add_file_at)
lotus_import_batch_at(box: *const c_char, items_json: *const c_char,
                      project_id: u64, area_id: u64) -> i64        // count committed, <0 = err
// read-only over the snapshot → Committed::Read; bytes land OUTSIDE the box
lotus_export_at(box: *const c_char, ids_json: *const c_char,
                group_props_json: *const c_char, dest: *const c_char) -> i64   // count written, <0 = err
```

`0` project/area = "none"; `items_json` and `ids_json` are the shell-resolved
sets (D1/D5). Optionally a thin `lotus_export_plan_at(...) -> *mut c_char` (JSON
tree) if the preview needs the real projection rather than a shell estimate —
decide at 15f.

**Failing-test-first list** (write red first — memory: test-drive-core-changes):

1. `commit_batch` of 3 items commits in **one** transaction — one undo reverts
   all 3 (not 3 undos).
2. Re-`commit_batch` the same 3 external-ids → **0** new entities (LB3 no-op).
3. A `File` item creates a by-reference file entity (`type=file` + `File` cell);
   source bytes unmoved, **no copy** (LB1).
4. A `Link` item creates a `link` entity carrying `url`+`name`; a provided title
   is **not** clobbered by a later scrape (LB8/#40).
5. A `Note` item: `split_frontmatter` keys become cells (missing defs created);
   `parse_markdown` body lands as rich spans; `source_id` becomes the
   external-id.
5b. `parse_markdown` maps headings/quote/bullets/ordered/task/code/rule + the
   four inline marks (round-trips through `render_markdown` for the covered
   subset); `[[Name]]` becomes a `Ref` once the batch resolves the target,
   else stays literal; `[text](url)` keeps its text.
6. `ImportDefaults{project,area}` stamped on every committed entity; empty
   defaults stamp nothing.
7. `seed_links` is additive + idempotent (a box with a hand-made `url` gains no
   duplicate; re-seed is a no-op) — mirrors the P14 contact-fields guard.
8. `export_write` of N entities lands N outputs in dest; `store` unchanged after
   (read-only).
9. 2-level `group_by` nests dirs exactly 2 deep; a 3rd level is clamped.
10. A file entity's bytes are copied to dest byte-identical; the original is
    untouched.
11. A native note's content spans `render_markdown` to markdown and the
    frontmatter block carries its cells (D7 export projection).
12. `parse_markdown` → `render_markdown` round-trips headings, marks, bullets,
    task items, and refs for the covered CommonMark subset.

## 4 · Surfaces (SwiftUI plan)

**Budget: 0 new `Surface` cases; +2 `TabKind` markers; +2 net-new views; +2
small net-new components; +1 `anchorChip` extension; 0 `InspectorPane` refactor
(D2).**

**Library — upgrade `LibraryView` (Window.swift:3584)**
- `@State lens: LibraryLens = .table` (`enum LibraryLens { table, gallery }` —
  ship Table only, switcher wired 2-slot-ready, D3) + `@State groupBy: PropId?`.
- Header: existing `LensHeader` + a `libraryLensSwitcher` cloned from the
  `TasksView` idiom (TaskLens + its ⌃-chords) + a group-by `Menu` (the reconciled
  "Folder"→group-by-property control) + existing Add-file button + Import/Export
  header icons (LB6).
- Body: `tableLens(files)` = the current `ObjectRow` ForEach, wrapped in
  `SectionLabel` groups when `groupBy` is set. `ShortcutBar`:
  `[("⌃1","table"),("⏎","open"),("⌘⇧O","add file")]`.
- Extend `anchorChip(for:)` so a file entity returns its `format` chip (LB7).

**Import funnel — new `Import.swift`, tab `.importFunnel`** (all shell scratch, D1)
- `final class ImportFunnelModel: ObservableObject { @Published candidates:[ImportCandidate]; @Published project/area:UInt64?; shelf load/save UserDefaults JSON }` — held outside `TabKind` (LB6).
- `struct ImportCandidate: Identifiable { kind; source; title; state:.collected/.deferred/.discarded }` — pure scratch (D2).
- Regions: `ProgressMeter` (a5, small) + `PoolDropZone` (a6, the one heavy
  net-new `NSViewRepresentable` — parses dropped OS files / tab URLs / a whole
  `bookmarks.html`; folder-names → subject *defaults*, plain editable) +
  candidate list in the `ObjectRow` shape + inherited project/area chips
  (`ValueChip`, text+dot) + Discard (drop scratch) + destination line ("N links ·
  M files referenced", LB1) + **"Import N →"** → `lotus_import_batch_at`.
- After commit, route the reader into the **existing P12 Inbox Route/Tidy lens**
  (D1) — no bespoke rich pane.

**Export composer — new `Export.swift`, tab `.exportComposer`**
- `final class ExportComposerModel: ObservableObject { query; excluded:Set<UInt64>; group1/group2:PropId?; dest:URL? }`.
- Regions: filter bar reusing the P13 query + facet chips (a27) + matched
  checklist (a28) + structure composer (two group-by `Menu`s ≤2, a29) +
  `ExportTreePreview` (a30, small outline over `export_plan`) + destination line
  (NSOpenPanel folder, a32) + **"Export N →"** copy-only → `lotus_export_at`.
- **Gotcha (real):** `ObjectRow.toggle` strikethroughs the title when done —
  wrong for an export checklist. Add a distinct `checkbox: Binding<Bool>?` param
  (or a dedicated `ExportRow`); do not reuse `toggle`.

**File-menu wiring:** File-menu commands post notifications that open the tab +
set the surface; bind ⌘⇧I / ⌘⇧E in the fixed keyboard map (same on every
surface).

## 5 · Slice plan (services before surfaces)

- **P15a — links seed + markdown parser + import service + FFI.** `seed_links`;
  `parse_markdown`/`render_markdown`/`split_frontmatter` (pulldown-cmark);
  `import.rs::commit_batch` (with the `[[ref]]` second pass); `lotus_import_batch_at`.
  **Gate: failing-test-first** (tests 1–7, 12). Deliverable: batch import (files
  by reference, links, notes with rich-markdown body + frontmatter cells, scraps)
  in one undo with external-id dedupe — no surface yet. *Build note:* adding
  `pulldown-cmark` needs cargo to fetch the crate; if the build box is offline,
  vendor it. Consider splitting the parser into its own commit (P15a-md) if the
  slice runs large.
- **P15b — folder-name→subject proposer → FOLDED into P15e** (reshape, recorded
  after building P15a). The clerk's `sweep` is a *pure function of the store*
  (`services/src/clerk.rs`), so a proposer cannot see import-time bookmark-folder
  structure, which never lands in the log — it lives only in the funnel surface.
  And an imported *note's* body mentions already get `propose_mentions` for free
  (its content IS in the store). The folder-name signal is therefore unique to
  *links* (a bookmarks.html hierarchy), whose folder data exists only at the
  funnel. So P15e resolves a folder name to a known subject and passes it via the
  already-built `ImportDefaults.stamps` (deterministic, no proposal) — with
  ambiguous names deferred. No standalone clerk proposer, no new core.
- **P15c — export service + FFI.** `export.rs::{export_plan,export_write}`;
  `lotus_export_at`. **Gate: failing-test-first** (tests 8–11); copy-only,
  markdown projection, byte-copy, source untouched.
- **P15d — Library lens upgrade.** Table switcher (2-slot-ready), group-by
  control, `format` anchor chip. **Gate: mockup** (Table only; Gallery marked a
  deferred candidate so the mockup does not over-promise).
- **P15e — Import funnel surface.** `.importFunnel` tab, `PoolDropZone`, progress
  meter, inherited defaults, "Import N →" → route to Inbox. **Gate: mockup.**
- **P15f — Export composer surface.** `.exportComposer` tab, filter selector,
  matched checklist (checkbox param), structure composer, tree preview, "Export
  N →" copy. **Gate: mockup.**

Each slice: build → tests/mockup → adversarial review → fix confirmed → commit.

## 6 · Deferred (named, with reasons)

- **Gallery lens** — candidate renderer; build when image volume justifies (#35).
  Switcher wired 2-slot-ready. (D3)
- **Kanban-over-files** — REFUSED (not deferred): files carry no status vocab.
- **Folder lens / vault tree / on-disk rename** — REFUSED: files-as-truth +
  never-move/rename-bytes (T4, P7).
- **`InspectorPane`→`PropertyRowList` extraction** — deferred; D1's hybrid makes
  rich pre-commit editing unnecessary in P15. (D2)
- **drop-onto-view retag (bp7 a6)** — nicety; a positive-facet stamp, past P15.
- **New Word/Sheet create-and-hand-off (#38, bp7 a16)** — writes bytes; P7 §9
  already defers.
- **`.md`-card materialization of links, `.base`/`.liv` view-files, index.db** —
  REFUSED: the log is the one truth; links are entities.
- **Downloads watcher + per-type auto-rules (bp14 a22–26)** — REFUSED:
  timer/poller + silent-mutation law.
- **Export move-out (a31/a33)** — REFUSED: never-move-bytes + dead-link rot
  (scar #1).
- **AI-suggested classification chips (a14)** — quarantined to P16.
- **Inline-link href + nested YAML frontmatter** — no href slot in the span
  model, and flat frontmatter covers Obsidian's common case; both defer, not the
  whole markdown parse (which ships — D7).
- **ICS / calendar feed import** — fenced until files prove the pattern (#43).

## 7 · Rulings recap + genuinely-open owner calls

**Ruled here (recommendations, not owner-blocking):** the pre-commit buffer is
shell scratch + the P12 Inbox for post-commit routing (D1); no inspector
refactor (D2); Table-only, Gallery a deferred candidate, Kanban refused (D3);
`import.rs` module (D4); id-driven export with a plan/write split (D5); a `url`
property + `link` type seed (D6); frontmatter+plain-text import / spans→md export
with rich-format parse deferred (D7); not sandboxed, so no scoped-bookmark work
(D8). Import references binaries and ingests native content, never copies bytes
inward (LB1); one transaction / one undo at the commit button (LB2); export is
copy-only, a projection not a mirror (LB5); import/export are content tabs, not
surfaces (LB6).

**Owner-ruled (this round):**
- **D6** → a `link` type + `url` property (links are first-class).
- **D7** → full rich markdown parse in P15 (pulldown-cmark), with the three
  bounded limits recorded as deltas (wikilink second-pass resolution, inline-link
  text-only, flat frontmatter).

**Still my call (implementation, not owner-blocking):** the shell-scratch buffer
model (D1) — confirm at the P15e funnel mockup if you want to weigh in; P15a–c
proceed on the recommendations.
