# P17 — Shell v2 (BP-4): the chassis rebuild, sequenced behind its seeds

P17 replaces the whole macOS chrome with the BP-4 blueprint (`/Users/k/Documents/bp4-shell.html`, annotations ⟨1⟩–⟨40⟩): a **six-band vertical frame** (title · global-tab melt row · [rail · Spaces\|Vault panel · center · five-lens panel] · content-tab lane · surface), welded by a `chrome → canvas → surface` **shade ladder** and the **melt seam** (no divider under the active tab — liv-ui-map §6-18, "intended, never achieved" in Liv). This throws out the shipped shell's deliberate Claude-style divergence (`sidebar · content · inspector`, opaque cards floating over window material through ~7pt gaps, `Window.swift:1329-1374`) in favor of full Liv chrome. That is a real rebuild of `Window.swift`'s body, not a reskin, and the owner should ratify the visual break before slice 1 lands (§4-①).

It is sequenced **late** for two reasons. First, the disruptive muscle — tab groups/lock/melt, the two histories, the five-lens panel — sits on top of everything else, so it can only stabilize once the surfaces it re-homes are settled. Second, three of its pieces are **small entities** (pins, layout-layers, saved tab-groups) and one is a **creation-seam behavior** (workspace stamping); each needs a seed + failing-test-first FFI **before** its shell surface, and those seeds are cheap only because the closed value set already has what they need (`Reference(Id)`, `Number(f64)`, `Select(Id)` — `core/src/value.rs:220`).

It **consumes P13 and P16**: the Vault tree's facet counts and the omnibox search-palette come from P13 (degrade to no-count if P13 is late); the Copilot lens and the Inbox amber Tidy count are the P16 proposal cards, re-homed, not rebuilt. The Metadata lens **is** the already-landed BP-1 inspector (`InspectorPane`, `Inspector.swift:110-173`); the History lens **is** the already-shipped content-version projection (`lotus_content_history_at`), renamed from Snapshots (IA-5). Almost nothing here is new core — the new muscle is shell-side, and the small-entity seeds are additive.

> Provenance: synthesized from three P17 design angles — fidelity-first, risk-first, constitution-first — plus a judge panel. The **constitution-first discriminator** is the spine; the **risk-first sequencing** (migration hazards H1–H4) is adopted wholesale; the **fidelity-first palette grounding + melt recipe** is grafted in. Where the angles disagreed, §5 records who won. Grounded against the landed core/FFI/shell, not invented.

## 0 · The discriminator that decides everything

Every BP-4 artifact is sorted by the two-axis test (`liv-ui-map.md` §4.1 lines 4334/4335):

> An artifact is a **small entity** iff it is **authored curation** (loss = a lost user decision) **and must travel with the box** (references vault ids, meaningless elsewhere). Otherwise it is a **shell preference** — even when it references entity ids — because it is *derived from navigation*, recreatable, and machine-local.

| Artifact | Authored? | Must travel? | Verdict |
|---|---|---|---|
| Pins / favorites | yes | yes | **entity** |
| Layout-layer (open-id list) | yes | yes | **entity** (+ geometry = pref) |
| Saved tab-group | yes | yes | **entity** (= a layer) |
| Places history · per-tab back-stack | no | no | **pref** |
| Tab lock / group tint / melt | no | no | **pref** |
| Which lens is showing | no | no | **pref** |
| Workspace stamping | — | — | **neither** — a deterministic creation default |

Chrome muscle (tabs, histories, lenses) = pure shell. Durable curations (pins, layers, saved-groups) = small entities under one rule. Stamping = a third thing. That trichotomy drives the slice order: **every entity-bearing piece lands its seed + failing-test-first FFI before its surface.**

## 1 · The four migration hazards (the sequencing is built to defuse these)

All four are real, cited, and verified against the code. They are why the plan is risk-ordered, not fidelity-ordered.

- **H1 — snapshot decode is all-or-nothing.** `Snapshot` fields are non-optional; `applySnapshot` does `try? decode` then `if let snap { self.snap = snap }` (`Window.swift:129-139,330,335`). One missing key → whole decode nils → UI freezes on stale data, no error (the header already warns, `Window.swift:36`). **Rule:** every new wire field (`pins`, any layer projection) is decoded **optional** (`let pins: [PinRow]?`, consumed `?? []`), and the **core emits it before the shell reads it**. Ship a decode-canary test.
- **H2 — `app.tabs.v1.<workspace>` is the wrong shape and scope.** Today: per-workspace `Saved{tabs,activeId}` (`Tabs.swift:38,47`). BP-4 wants global tabs holding content-tabs + per-tab stacks. Reusing the key → old decode falls to a default desk = **silent loss of the user's open tabs**. **Rule:** new namespace `app.tabs.v2` + `app.contentTabs.v2.*`, one-time v1→v2 migration (each old tab → one content-tab under one global tab), **keep v1 on disk for rollback**.
- **H3 — `app.layout.panes.v4` assumes left%+center+right%=100.** The clamp gymnastics (`reconcilePanes`/`leftLiveMax`, `Chrome.swift:133-176`) misfire once a fixed 44px rail leaves the sum ≠ 100. **Rule:** isolate the geometry change in **its own slice** with `app.layout.panes.v5` + v4→v5 migration; adopt fixed tokens (`--ab 44 / --lp 238 / --rp 300`, center flex) and **delete** the dual-% cascade rather than patch it.
- **H4 — box-lock + one-undo on new write paths.** Pins and stamping must route `with_box` + tag `Committed` (Read/Wrote/Failed) or tab-switch lag returns (the FFI-store-cache memory). Stamping wants **one** transaction (create + stamp) so a single ⌘Z unwinds the birth with no un-stamped flicker. **Rule:** additive verbs only, mirror `with_box` + `Committed`, failing-test-first, flagged in the PR; the lock is never held across a chip render.

One low-risk item: the rail iterates `Surface.allCases` (`Chrome.swift:347`); BP-4 drops **Lists** from the rail. Decouple rail membership from the enum — render a curated `[RailItem]`, keep the `.lists` case alive so stored state still decodes (`Surface(rawValue:) ?? .notes` already tolerates it).

## 2 · Reconciliation ledger — one entry per BP-4 component

### (a) Activity rail — exactly 10 + the Notes-above-the-hairline seam
- **Law touched:** none (pure re-arrangement).
- **BP-4 want:** a standalone 44px icon strip; back/forward chevrons → hairline → **Notes** (alone, primary altitude) → **altitude-seam hairline** → Chats · Tasks · Library · Inbox · Contacts · Calendar (6 ambient) → spacer → Pin-project · Extensions · Settings. Active = accent-soft fill + 3px left-edge bar. Count = 10.
- **Reconciliation:** rebuild `SurfaceNav`/`NavRow` (`Chrome.swift:339-392`) from 8 labeled rows folded into the panel into the icon strip. 8→10: Lists folds into Library; add Pin-project + Extensions (absorbs Messages/Finances stubs, IA-8); theme toggle → Settings (IA-9). Active state = `Theme.primary` (lake-green — legitimate, it *is* selection of a place). **Inbox dual count (IA-3):** Route count top-right in a **neutral structural tone** (text2/muted — *not* blue, which is banned, and *not* lake-green, reserved for selection) + amber Tidy count bottom (amber is AI-only, correct). Floating "N things I can tidy" pill stays cut; in-place halos remain.
- **Core/seed/ffi delta:** none.

### (b) Two-tab left panel — Spaces | Vault
- **Law touched:** none.
- **BP-4 want:** a 238px panel with exactly two segmented tabs. Vault = filter box + real-content tree (Areas/Projects/Recent, value-dot-or-glyph rows, no view-files at root, IA-11). Spaces = Pinned (favourite workspaces + pinned objects, one source) + Workspaces + a foot vault-switcher.
- **Reconciliation:** revive `SidebarView.tree/.vault` (`Spaces.swift:113`), reuse `SpacesTree` (`Spaces.swift:225-478`) for Vault, retire the top-right `spacesPicker` popover (`Window.swift:1136-1184`). The IA cuts are half-done as dead code — `PropertiesBrowser`/`BookmarksPanel` (`Spaces.swift:969,1133`) are mounted nowhere and are **deleted, not resurrected** (Props → facets IA-2, Saved → Pinned IA-4, Graph → overlay IA-1). Pinned renders empty-state until the pin seed lands (17g).
- **Core/seed/ffi delta:** none (facet counts degrade to no-count if P13 is late).

### (c) Home hub + workspace switcher + stamping
- **Law touched:** silent-mutation ban; *accept = the normal manual save seam*; dialog-free.
- **BP-4 want:** the hub pill wears the active workspace name (single-click → switcher popover, double-click → Home surface); switcher shows the stamp rule ("✓ · stamps area=studies"); on object creation the workspace stamps its default as a clerk-visible, editable chip.
- **Reconciliation:** **stamping bypasses the proposal queue** — it is a *deterministic creation default*, not an AI proposal. Forcing it through the amber quarantine would be a category error (amber = AI-only) and manufacture a false proposal card, violating *accept = the manual seam*. Instead: (1) **one transaction, one undo** — create mints the entity *and* writes the stamped cells atomically; (2) **visibility = the chip in normal cell tone**, tagged `by:`-style "from workspace" provenance — the chip *is* the "never silent"; (3) **dismissal = ordinary cell editing**, no confirm; (4) **back-fill** (Liv's `applyDefaults` offer) rides the grouped-transaction + undo count-confirm seam, never a modal.
- **Core/seed/ffi delta:** **real, but mostly already built.** The atomic-stamp mechanic *ships* — `ImportDefaults{stamps: Vec<(Id,Id)>}` writes reference cells inside one `session.commit` (`services/src/import.rs:41-46`), exposed via `lotus_import_batch_at` (`ffi/src/lib.rs:1857-1893`). P17 **lifts it from the import funnel onto the single-create seam**. What's missing: `seed_workspaces` seeds only `favorite`, not `default-*` cells (`services/src/lib.rs:597-659`). So: extend the workspace seed with `default-area`/`default-project` reference cells; prefer a compound create+set through existing verbs; add `lotus_create_in_workspace_at` (returns the stamped cell set) **only if** no compound seam exists — additive, `with_box`+`Committed`, test-first, flagged. (17h.)

### (d) Pins + favorites — one source, heterogeneous targets
- **Law touched:** *transient UI state is never an entity* (feature-map tale 6).
- **BP-4 want:** ONE pin source read by two surfaces (favorites pill row + Spaces›Pinned); pin in either → appears in both; drag reorders both; targets = object/view/workspace/daily/file.
- **Reconciliation:** **entity** — both axes agree (references a vault id → must travel; authored curation → loss = a lost decision), same category as a saved view, which the constitution already makes an entity. This is *not* the tale-6 failure (Liv minting a note per *opened tab* — derived, recreatable). A small backstage `pin` type, rendered at secondary-label opacity, never `by:assist`. Two heterogeneity traps closed or Liv's disease re-enters: **pin-a-scope mints a saved-view entity first**, then pins its id (a pin never carries a serialized query); **a memo-pin references a real note** (create-then-rename), so the text lives in the log. Today's `favorite` bool (`services/src/lib.rs:615`) is **unioned** into the Pinned query now, migrated to `pin{workspace}` later (zero-risk).
- **Core/seed/ffi delta:** seed a `pin` type (`target-kind`=`Select(Id)`, `target`=`Reference(Id)`, `order`=`Number(f64)` float key, optional `label`/`icon`=`Text` — **zero new value kind**). Snapshot gains **optional** `pins: [PinRow]?` (H1). Prefer generic create + `lotus_set_at` for reorder-as-one-cell + `lotus_trash_at` for unpin; add `lotus_pin_reorder_at` **only if** grouped-reorder needs one transaction (additive, tested, flagged). (17g.)

### (e) Global tabs — category-lock / groups / melt
- **Law touched:** the tabs ban (annulled); tale 6.
- **BP-4 want:** global tabs in a 38px melt row; active tab draws **no divider** (canvas fill + 3px seam strip); inactive-behind on chrome; groups tint with GROUP_PALETTE; category-lock badge constrains `+`/`▾`; rapid-close width freeze; middle-click close; Shift-select multi-group.
- **Reconciliation:** **100% shell prefs.** A tab's only content is an entity id; melt/lock/group carry no user data. Melt = a rendering choice (active fill = `--canvas` global / `--surface` content-lane + a seam strip). Groups = a `GROUP_PALETTE` tint (one of the **8 muted value-hues, never the accent, never blue/violet**) + pref membership; "colour, not lines." The **one carve-out:** Liv's "Save these tabs as a group" is authored+durable → a **Layer entity** (h), not a per-tab note — keep that boundary explicit or tale 6 re-enters through the "save group" door.
- **Core/seed/ffi delta:** none.

### (f) The two histories
- **Law touched:** transient-UI-never-an-entity; history-as-projection.
- **BP-4 want:** a universal/places history (rail chevrons ⟨1⟩: workspace/rail/global-tab switches + object opens — *not* text edits, *not* in-tab doc history) + a per-content-tab back-stack (content-lane arrows ⟨27⟩: docs opened within the active tab, browser-style, independent).
- **Reconciliation:** **both shell prefs, never a log write** (the constitution's own framing). Split the single merged `NavHistory` (`Chrome.swift:53-97`). Both are bounded rings, **dangling-id-tolerant on replay** (target trashed → prune, like the current `reconcile` guard). **Close tombstones** a tab's back-stack in a last-N ring so Ctrl+Shift+T restores tab *and* stack; past the ring it drops (recreatable navigation, not data). Cross-restart persistence is optional polish — in-memory is legal since loss ≠ data loss.
- **Core/seed/ffi delta:** none.

### (g) Five-lens right panel
- **Law touched:** none beyond BP-1/BP-12/P16.
- **BP-4 want:** a 46px view-tab bar — Metadata · Copilot · Outline · History · Graph; per-extension last-lens memory; active = accent underline.
- **Reconciliation:** purely presentational re-home; each lens is already-owned machinery. **Metadata** = the BP-1 inspector (`InspectorPane`, grammar-locked). **History** = the shipped `lotus_content_history_at` projection, renamed from Snapshots (IA-5), document versions ONLY, Restore = an **append** (never rewrite). **Outline** = a shell parse of the note body (no storage; not the click-to-scroll one — that stays composer-side). **Copilot** = the P16 amber cards, the AI's only panel home (writes stay proposals — no third door). **Graph** = the **local** BFS graph (IA-1; vault-wide → full-screen overlay), gated on **VALUE_HEX/R3**. Outline+History fold in from the editor rail (IA-5). **Ship 4 lenses if R3 is late.**
- **Core/seed/ffi delta:** none (History reuses `lotus_content_history_at`; the existing `HistorySection`, `Window.swift:4667`, lifts out of the inspector scroll into its own lens).

### (h) Layers = workspace layout snapshots
- **Law touched:** §4.1 line 4325 ("named marker on a log position; Restore re-applies, never rewrites").
- **BP-4 want:** a Layers icon in the global-actions cluster → Save/Restore/Import; snapshots are workspace-level layouts split out of the right panel.
- **Reconciliation:** the word "snapshot" hides two mechanisms — split them. A **layout-layer's content** = a list of entity ids to reopen (authored + must travel → **small entity**); its **geometry** (pane widths, collapse) = an opaque **shell-pref blob** keyed by the layer id. **Restoring mutates nothing in the log** — it opens tabs and sets widths; the only log writes are create/rename/delete of the layer entity. Because it points at *live* ids it needs **no log-position marker** (markers are only for the content-version case, which is the History lens's append, not Layers). One-step-undo toast on restore.
- **Core/seed/ffi delta:** a small `layer` seed type (id-list content, mirrors the pin seed); geometry = shell pref. **No FFI for restore.** (17i.)

## 3 · The ~9-slice plan

Risk-ordered so no slice is a broken intermediate: **17a touches no persisted state**, the geometry migration is isolated (17b), the tab-data rewrite is validated behind the *current* look before any new tab UX sits on it (17c → 17d–e), and the entity/core-adjacent slices land last, each seed-first. Slices 17a–17b are the **pull-early bundle** — ship the moment the current chrome chafes.

### 17a — Rail-of-10 + Notes-seam + two-tab panel
- **Ships:** the curated 44px `[RailItem]` strip (decoupled from `Surface.allCases`), nav chevrons relocated to the rail top, the altitude-seam hairline, Inbox dual-count (neutral Route + amber Tidy), Extensions absorbing Messages/Finances, theme→Settings; the Spaces\|Vault two-tab panel reviving `SidebarView`+`SpacesTree`; delete `PropertiesBrowser`/`BookmarksPanel`. **Rendered inside the existing `leftPct` region** (rail fixed 44 within it) — **no `app.layout.panes.v4` change, zero new persisted state.**
- **Method:** mockup-first.
- **Depends:** nothing.
- **Acceptance:** rail reads as exactly 10 icons with Notes alone above the seam; Inbox shows two counts, neither blue nor lake-green for Route; panel reads as *two* tabs; **reverting the slice restores the shipped shell with no persisted-state cleanup.**

### 17b — Fixed-frame geometry + Home hub + switcher
- **Ships:** the six-band frame with fixed tokens (`--ab 44 / --lp 238 / --rp 300`, center flex, content-tab lane, `Theme.chrome/canvas/surface` shade-ladder tokens added to `Tokens.swift`); retire `leftLiveMax`/`reconcilePanes`; `app.layout.panes.v5` + v4→v5 migration. The global-tab band appears with the **Home hub** pill (name-tracking, single→switcher popover, double→Home surface) + switcher (type-to-filter, `✓` current, "stamps area=…" line shown only if the workspace carries defaults — forward-compatible with 17h).
- **Method:** mockup-first + a migration unit check.
- **Depends:** 17a.
- **Acceptance:** frame reads as BP-4 in the lotus palette (accent = lake-green selection/today only; dots from value-hues, never accent/blue/violet); right panel still drag-collapsible; v4→v5 migration round-trips a real box with a safe default fallback.

### 17c — Global tab **model** rewrite (data layer, behind the current look)
- **Ships:** the two-tier tab store (global tabs per workspace, each holding content-tabs); `app.tabs.v2` + `app.contentTabs.v2.*`; **v1→v2 migration** (each old `WorkspaceTab` → one content-tab under one global tab; v1 kept for rollback). Today's dedup/close-neighbour/reconcile semantics (`Tabs.swift:93-206`) preserved **exactly**, rendered behind the current strip look so it is a pure refactor validated against known behavior.
- **Method:** mockup-first for parity + a migration/reconcile unit test (H2).
- **Depends:** 17b.
- **Acceptance:** a v1 box's open tabs survive the upgrade unchanged; every existing tab interaction (open/dedup/close-neighbour/prune-stale) behaves identically; v1 remains on disk.

### 17d — Melt + content-tab lane + note-header crumb
- **Ships:** the melt (active tab fill = `Theme.canvas`/`Theme.surface` + a seam-cover strip → **no divider under the active tab**, UM§6-18 achieved); the 36px content-tab lane with per-tab arrows (stubbed until 17f); `+` new note + `▾` menu (New note · From template · **Recently closed**, Ctrl+Shift+T); the note-header crumb — *destination always visible* ("in **Master thesis** › meetings · real path · saved ✓"), click-segment navigates, click-title renames (non-blocking, D07).
- **Method:** mockup-first (the melt is the crux pixel decision — de-risk the SwiftUI seam-cover before wiring). **The SwiftUI melt recipe:** render `.gbar` and `main` in a `ZStack`; fill the active tab `Theme.canvas` and extend its bottom edge ~3pt into the region below via a negative-inset overlay drawn *after* the region's top hairline, so the fill covers the seam — the analog of the CSS `::after` strip.
- **Depends:** 17c.
- **Acceptance:** no border renders under the active tab at any width; the tab and canvas read as one sheet; crumb path matches the entity's true location.

### 17e — Category-lock + tab groups
- **Ships:** Shift-select grouping; `GROUP_PALETTE` **value-hue** bands (gated on VALUE_HEX; never the accent) + collapse-pill + count; lock-to-category badge constraining `+`/`▾`; rapid-close width freeze (`useFrozenTabStripWidths`); middle-click close.
- **Method:** mockup-first.
- **Depends:** 17c, 17d.
- **Acceptance:** group bands are demonstrably a value-hue, not lake-green/blue/violet; unlocking a tab never loses its content; widths freeze during rapid closes and release on mouse-leave.

### 17f — Dual history
- **Ships:** the split into places-history (rail chevrons ⟨1⟩) + per-content-tab back-stack (content-lane arrows ⟨27⟩); bounded rings; dangling-id-tolerant replay; close-tombstone ring feeding Ctrl+Shift+T reopen-with-stack.
- **Method:** mockup-first for the arrows + shell unit tests for ring/replay/tombstone (dedup, forward-truncation, dangling prune).
- **Depends:** 17c, 17d.
- **Acceptance:** places-history records places (not text edits, not in-tab docs); forward dims at head; a trashed target is pruned on replay, never crashes; reopening a closed tab restores its own stack.

### 17g — Pins: seed + FFI + favorites/Pinned shell (first entity slice)
- **Ships (core-first sub-order):** the `pin` seed type + `PinRow` snapshot projection + write path; then the favorites pill row in the global band (ghost `+` pins the current tab, hover→lake-green, right-click→Unpin) **and** Spaces›Pinned, both over the same query; drag reorders both.
- **Method:** **failing-test-first** in services+ffi (round-trips `{target-kind,target,order}`; reorder is one grouped transaction; dangling target tolerated); then mockup-first for the two surfaces.
- **Core/seed/ffi:** seed `pin`; core emits `pins` **before** the shell reads it (H1); snapshot field **optional**; one additive verb (`lotus_pin_reorder_at`) only if grouped-reorder needs it — `with_box`+`Committed`, tested, **flagged in the PR**.
- **Depends:** 17b (band), 17c (pin-the-current-tab). **Owner-flagged.**
- **Acceptance:** pin in either surface appears in both; drag reorders both at once; a missing `pins` key does not drop the snapshot; scope-pin mints a saved-view first, memo-pin references a real note.

### 17h — Workspace stamping
- **Ships (core-first):** (a) workspace carries `default-area`/`default-project` reference cells; (b) a create-in-workspace path that mints + stamps atomically, one undo; (c) the visible **chip** in the inspector (normal tone, "from workspace" provenance) + the switcher's "stamps area=studies" line going live.
- **Method:** **failing-test-first** for (a)+(b) (creating in a workspace with `default-area=studies` yields the object carrying that cell in one transaction a single undo fully unwinds; a defaults-free workspace stamps nothing); mockup-first for the chip.
- **Core/seed/ffi:** extend `seed_workspaces` with the `default-*` expectation; **prefer** lifting the shipped `ImportDefaults{stamps}` machinery (`services/src/import.rs`) onto the single-create seam; add `lotus_create_in_workspace_at` only if no compound seam exists — additive, tested, **flagged**.
- **Depends:** 17b (switcher). **Owner-flagged.**
- **Acceptance:** one ⌘Z unwinds the whole birth including stamps, with no un-stamped flicker; the chip renders in normal (not amber) tone; clearing it is ordinary cell editing.

### 17i — Five-lens right panel + Layers
- **Ships:** the 46px five-lens bar (Metadata · Copilot · Outline · History · Graph) with per-extension last-lens memory; Outline+History folded in from the editor rail; History renamed from Snapshots; the Layers menu (Save/Restore/Import) in the global-actions cluster.
- **Method:** mockup-first for the lens bar (presentation over existing projections); **failing-test-first** only for the Layers **layer entity** (create/rename/delete) — restore itself is pure shell (open ids + set geometry, **zero log write**).
- **Core/seed/ffi:** a small `layer` seed type (mirrors the pin seed); geometry = shell-pref blob. **No FFI for restore.** Graph lens gated on VALUE_HEX/R3 — **ship 4 lenses if R3 is late.**
- **Depends:** 17e (a tab arrangement to snapshot), 17g (seed pattern), P16 (Copilot), R3 (Graph). **Owner-flagged** (layer seed).
- **Acceptance:** History-lens Restore appends (never rewrites); Layers-restore writes no log; each lens remembers its last-used state per extension.

**Sequencing summary:** 17a–17b ship early (pure shell, revertable) · 17c–17f disruptive-but-still-shell chrome · **seed before shell** at 17g, **core before chip** at 17h, **layer seed before restore** at 17i. No slice requires a snapshot field or persisted-state shape the previous slice didn't already ship.

## 4 · Open owner calls (with recommended answers)

**① Ratify the visual break.** The blueprint replaces the shipped "flush canvas / floating cards over material" look (commits eab213b/379a37b) with BP-4's bordered regions + shade ladder + melt. → **Recommend: ratify.** The blueprint is the target and the directive is "copy Liv exactly"; the melt is the payoff (§6-18, never achieved in Liv).

**② Pins are entities, not the `app.slots.v1` pref.** → **Recommend: yes.** Ratify the two traps closed (pin-a-scope mints a saved-view first; memo-pin references a real note) and the migration (union the `favorite` bool into the Pinned query now, migrate to `pin{workspace}` later).

**③ Shortcut map — fixed bindings or the R2 editor?** → **Recommend: fixed defaults, registered in the existing command registry.** P17 does **not** need the R2 shortcut *editor*; it needs the registry (exists) + a two-line owner assignment (④). Register rail digits + both histories as registry defaults so they become rebindable when R2 lands. Put the fixed-map *reversal* in writing (R2's own instruction, lines 405–406); the editor ruling stays gated to P13/P19.

**④ Q1/Q4 bindings.** → **Recommend, in writing:** universal/places back-forward = **Ctrl+Alt+←/→ + mouse 4/5** (Alt+←/→ is taken by the D21 doc↔panel jump, `Inspector.swift:36`; nav was already moved off ⌥←/→ for that reason, `Chrome.swift:55-56`); per-content-tab back-stack = **⌘[ / ⌘]** (retiring today's single merged ⌘[/⌘] onto the per-tab history). Rail digits = **Ctrl+1…7 for the seven above-seam items** (Notes + 6 ambient), global scope; the 3 utility items get no digit. Resolve Liv's composer-scope `Ctrl+1..8 goto-tab-N` collision by moving **content-tab jump to ⌘1…⌘9** (distinct modifier, no scope ambiguity) rather than relying on scope-gated dispatch of the same chord.

**⑤ Stamping bypasses the proposal queue.** → **Recommend: yes.** A workspace default is a deterministic creation **stamp** (chip + "from workspace" provenance + one-undo, **normal tone, never amber**); the clerk's separate AI proposal stays queued. Guards *accept = the manual seam* + dialog-free.

**⑥ "Snapshot" = two mechanisms.** → **Recommend: yes.** Layout-layer restore **never writes the log** (small entity id-list + geometry pref); content-version restore **appends, never rewrites** (History lens). Sharpens §4.1 line 4325.

**⑦ Inbox Route badge hue.** → **Recommend: neutral structural tone** (text2/muted). Blue is banned; lake-green is selection-only; amber is AI-only. Amber Tidy stays. Keeps two-counts-two-jobs without minting a third accent.

**⑧ Tree/chip/group dots.** → **Recommend: all dots from VALUE_HEX (`Hues.swift`), gated on R3; degrade to a muted neutral set if R3 is absent.** The blueprint's literal `var(--accent)` on the workspace dot (line 320) and subjects-chip dot (line 481) would paint lake-green dots — a direct breach. Accent and amber never appear as a dot.

**⑨ 17a ships early?** → **Recommend: yes, and go further — 17a touches no persisted state** (render rail+panel inside the existing `leftPct`, defer the fixed-token migration to 17b). Instantly revertable, the strongest de-risk.

**⑩ R3 gates only the Graph lens.** → **Recommend: ship 17i with four lenses** if R3 slips; Graph (and the 17e group-band value-hues) light up when R3 lands.

## 5 · Where the angles disagreed (and who is right)

- **Sequencing / migration discipline — risk-first wins.** Fidelity-first made 17a a big-bang chassis rebuild *including* the fixed-rail geometry change, declared "pure shell, zero risk," and never touched the `app.layout.panes.v4` cascade (H3) or a versioned tab key (H2). Constitution-first sequenced seed-before-shell correctly but was blind to the *existing*-state migrations — its rail-out-to-a-strip slice-1 breaks the pane arithmetic, and its tab slice never bumps `app.tabs.v1`. **Adopted:** risk-first's H1–H4 rules, the zero-persisted-state 17a, the isolated v4→v5 geometry slice, and the v2 tab-key migration with v1 kept for rollback.
- **Stamping mechanism — constitution-first wins.** Both other angles treated `lotus_create_in_workspace_at` as new muscle needing a fresh compound verb + test. Constitution-first found the atomic-stamp path **already ships** (`ImportDefaults{stamps}` → `lotus_import_batch_at`) and only needs lifting onto the single-create seam. **Adopted:** prefer lifting the shipped mechanic; add a verb only if no compound seam exists.
- **Palette-breach grounding + the melt recipe — fidelity-first wins.** It alone pinned the breaches to exact DOM offsets (accent-dots at lines 320/481, the google-brand aperture at 311) and gave a concrete SwiftUI seam-cover recipe for the melt (the ZStack negative-inset overlay), where the others gave one CSS sentence. **Adopted:** the remap-the-hue-source-keep-the-geometry rule and the melt recipe (17d).
- **Inbox Route badge — fidelity/constitution win, risk loses.** Risk-first repeatedly wrote "blue Route" and never flagged that blue violates the most-guarded palette law. **Adopted:** neutral, not blue (⑦).
- **Home hub placement — risk-first was wrong, corrected.** Risk-first crammed the Home hub into the last slice; constitution-first landed it early. **Adopted:** Home hub in 17b, once the band exists — an early visible headline, no persisted-state cost.

## 6 · The mockups to draw first

Ranked by constitutional + fidelity risk retired.

1. **The whole six-band frame at rest, in the lotus palette.** Must show: rail 44 / left panel 238 / center / right 300; title 40 / global-tab 38 / content-tab 36; the `chrome → canvas → surface` recessed→page→raised ladder with the active tab melting flush (no divider); the 44px rail with the altitude seam + accent-left-bar; dots drawn from value-hues (not accent/blue/violet), accent = lake-green selection only, amber = AI only. If this reads right, the whole skin is safe.
2. **The global melt row in all three tab states.** Must show: active **melt** (canvas fill, seam covered, no divider), inactive-**behind** (transparent on chrome), and **category-locked + a collapsed group pill** (GROUP_PALETTE value-hue, demonstrably not the accent), plus the favorites pill row turning lake-green on hover. De-risks the hardest, most-visible slice (17d/e) before data wiring.
3. **The Metadata lens with a stamped chip.** Must show: the 46px five-lens bar; the BP-1 digit grid (rows 1–9,0, `18px|82px|1fr`, focused-row grows to the 36px control height with an accent ring), the role-typed date pill ("occurred ▾"), the dashed-ghost "set status" (inspector-only), MORE·N collapse, the always-visible footbar — **and the `area=studies` chip in normal tone with "from workspace" provenance, not an amber card.** The most constitution-load-bearing surface after the frame; Copilot as a second state proves amber-only.
4. **The switcher popover + Spaces›Pinned, side by side.** Must show: the switcher's "✓ · stamps area=studies" line + footer rule, and the Pinned section showing the **same** four heterogeneous pins (daily note · view · workspace · file) the favorites row shows — the "one source, two surfaces" claim made literal.

(If only three fit, draw 1, 2, 3 — #4's content is partly provable inside #1 and #3.)