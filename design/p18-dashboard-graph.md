# P18 — Dashboard + Graph (BP-8 + BP-12)

**What this phase builds.** The Mission Control board that feature-map T4 once refused and blueprint-assessment annulled — kept inside the surviving fence (*widgets are pure lenses over existing collections, one shared scope context, no view-builder anywhere*) — plus both graphs from BP-12: the everyday local graph as the right panel's reserved fifth lens, and the vault-wide graph as an overlay. It also pays the P13 remainder: saved views become entities, because three consumers now ask at once (the Saved-view widget, the config panel, the Library).

**The spine is constitution-first; the grafts are earned.** Three design angles were drafted and judged. This doc takes the constitution proposal's data model (widgets as small WORKING entities — no board blob, no bespoke save verb), the risk proposal's sequencing discipline (the two things that can sink P18 — the physics canvas and the entity seeds — are proven in the first four slices on small surfaces, with the CLI as the seed proving ground so nothing ships dark), and the fidelity proposal's dispositioning discipline (every blueprint annotation is named ships / relocated / deferred / cut — §7; "relocated, not cut" is enforced). Section 5 records where the angles disagreed and who won.

**Two rulings bind and are not renegotiated here.** `design/blueprint-feedback-2026-07-14.md:428-441`: the dashboard is a **normal surface in the chrome**, never a blurred overlay ("all of lotus in one window; nothing floats free"), and widget config lives in the **right panel**, never a gear popover. And P12 D1: **Today IS the daily note** — the board points at it, launches into it, and never re-implements it. Verified against the as-built tree: `RightLens` is `{metadata, assist, outline, history}` with Graph reserved (Chrome.swift:58); `Surface` ends at `calendar` (Chrome.swift:12); `lotus_search_at`:1060, `lotus_pin_at`:2121, `lotus_layer_save_at`:2157, `lotus_trash_at`:2196, `lotus_export_at`:2018, `lotus_open_daily_note_at`:1574 all exist; `create_pin`:778/`create_layer`:872 are the seed pattern; `Hues.valueHex`:58 is the hue law; the shell already inverts `backlinkIndex` (Window.swift:248–273); no saved-view substrate exists anywhere in core/services/ffi.

---

## 1 · Reconciliation ledger

### 1.1 Dashboard home — a real `Surface.dashboard`
- **Law:** feedback 2026-07-14 (surface, not overlay — ruled); no new permanent chrome rows; no dead buttons; flush-card skin.
- **Blueprint want:** bp8 ①/㉔ — full-screen overlay over the blurred app; Shift+Tab with carve-outs; Ctrl+Home unconditional (OQ-1); Esc restores exact focus.
- **Reconciliation:** `case dashboard` — the 9th `Surface` case, `isGlobalTool = true`, the **7th rail icon** (Liv's ActivityBar had a Dashboard slot, liv-ui-map:399 — 1:1-sanctioned), mounted only in the slice where widgets are real. Board cards float on the bare center material. Entry: `Shift+Tab` with Liv's ordered carve-outs (list-outdent wins; inputs keep native reverse-tab) + **⌘⇧M** unconditional alternate + View › Dashboard. The overlay's one good trick is ported, not lost: **Esc = places-history back** (P17f full replay) — "returns exactly where you were" without a scrim. `Ctrl+Home` refused (⌘Home is text navigation on macOS; two chords suffice). No badge duty ever (bp8 ㉓ is a lock).
- **Delta:** overlay→surface; gear→panel (both ordered). Zero Rust.

### 1.2 The Today cell — the Agenda widget, never a second Today
- **Law:** P12 D1, settled.
- **Blueprint want:** bp8 ⑯/⑰ — today's calendar-role events + objects dated today; multi-day countdown strip.
- **Reconciliation:** Agenda · today = a pure lens: today's occurrences with the **calendar surface's own role predicate reused** (lookup-role dates — valid-until, purchased-on — provably never appear), due/overdue tasks dated today, and **one row for the daily note** opening `.today` via `lotus_open_daily_note_at`. Multi-day event = ONE countdown strip ("in 2 days — Fri → Sun"), never duplicate rows; same object drives the calendar span. One daily note, one law.
- **Delta:** none.

### 1.3 Habits — ordinary type + backstage check-in records, stats computed on read
- **Law:** the entity discriminator; feature-map #16 ("check-in = a small entity; streaks/points = projections computed once in Services"); deletion never cascades; optional wire fields (the H1 rule); amber = AI only, lake-green = selection/today only.
- **Blueprint want:** bp8 ⑧–⑫, D13 — definition doubles as a full view; one click = one check-in row, uncheck deletes it; stat tiles; 12-week chain heatmap w/ marigold today-ring; points sparkline; OQ-4 per-habit weights; export-to-sheet.
- **Reconciliation:** **`habit`** = an ordinary seeded type (front-of-house — habits belong in Everything): NAME, optional `points` Number (default 1 — OQ-4 resolved on the habit, "+N" renders from it), optional cadence **text** cell — the recurrence v0 grammar (recurrence.rs:10–66) can't express "3×/wk"; display-only, N-per-week defers (feature-map #19). **`check-in`** = WORKING=true backstage entity: `date` + `habit` Reference + CREATED, nothing else. Check = `lotus_check_in_at`, one commit, one undo; **uncheck = `lotus_trash_at` on the exact row** — no new verb. Because `include_working=false` keeps records out of `entities[]`, stats travel in a dedicated OPTIONAL snapshot section `habits: [HabitRow]` (streaks, week points, avg/active-day, 84-day heatmap buckets, **today's check-in ids** so uncheck targets the row) — derived, stored nowhere, exactly D13. Trashing a habit leaves its check-ins; the projection skips dangling refs — the first failing test, before any seed compiles. Palette: heatmap = **neutral ink-opacity ramp** (.3/.55/.78/1); **today ring = lake-green**, never marigold; the streak flame = full-ink when streak ≥ 3, muted otherwise — **neither amber nor lake-green**. Header meta = a clickable `habits` collection link opening the type filtered in center (same definition, two lenses). D19's habit-block-in-note strip (㉒) = a clerk proposal in the ONE inbox when the P16 proposer family grows. Export-to-sheet = stretch via `lotus_export_at`; defer with that named reason if the query grammar can't reach WORKING rows.
- **Delta:** 2 seeds, 2 verbs, 1 projection, 1 optional section. Recorded: D13 view-file→entity; WORKING-for-records; both palette deltas.

### 1.4 Time entries + the single-active timer — log the closed interval, tick in the shell
- **Law:** the timers law (writes only at user action; a displaying tick is UI state); feature-map #22 (entries = entities; single-active = shell invariant; totals = projections); one txn one undo.
- **Blueprint want:** bp8 ⑳ — ■ stop writes ONE time entry (project, start, end); one app-wide timer, starting a second folds the first; VALUE_HEX bars.
- **Reconciliation:** split exactly where bp8 splits. **Log** = `time-entry` WORKING entity (target Ref + start/end DateTime + CREATED), written **whole, at stop**, by `lotus_log_time_at` — the log never holds a half-open promise. **Shell state** = `(targetId, startedAt)` in UserDefaults (survives relaunch; the textbook transient-UI case). **Start writes nothing.** Elapsed = `TimelineView(.periodic(1s))` reading the pref — zero box IO per tick (acceptance: log byte-length unchanged across 60s of ticking). Start-while-running = one commit closing the old interval + pref swap — never double-counts. Single-active is enforced **only in the shell**; a CLI may legally append overlapping entries, so the week-totals projection tolerates overlap (failing test). Bars ride `Hues.valueHex` — bar hue byte-matches the project's chip in the inspector. Rejected and recorded: open-entity-at-start.
- **Delta:** 1 seed, 1 verb, 1 projection, 1 optional section.

### 1.5 Saved views — mint the entity NOW; canned widgets stay fixed lenses
- **Law:** the anti-Notion fence; feature-map #21/#28 (bookmarking the on-screen query is sanctioned); P13 §6's deferred fast-follow.
- **Blueprint want:** bp8 ㉑ — a Saved-view card over `.liv/views/*.base`, "Choose view…" picker, can always be empty without nagging.
- **Reconciliation:** **`view`** = small WORKING entity: NAME + `query` text cell holding the **shipped ⌘F DSL string** + `renderer` text (v0: `list`) + optional workspace ref. Running a view = the existing `lotus_search_at` — **zero new read seam**. The projection widgets (Habits, Agenda, Tasks summary, Time) bind to fixed projections — no view required, no builder anywhere; the Saved-view card's picker walks **existing view entities only**. Proving surface before any widget exists: **"Save view…" on the ⌘F search surface + a Views group in the Library** — the sanctioned bookmark, end-to-end.
- **Delta:** 1 seed, 1 verb (`lotus_create_view_at`), 1 optional section.

### 1.6 The board — widgets ARE entities; the ONE inspector grammar, literally
- **Law:** feedback ruling (config = property rows in the panel); one-txn-one-undo; deletion never cascades; transient UI ≠ entity, authored curation that travels with the box = small entity (the P17g/i precedent); data-model-first, simplest thing that works.
- **Blueprint want:** bp8 ②–⑦, ㉔ — scope chip re-binding every widget; searchable gallery with `reads →` lines; hover chrome; ⚙ config as BP-1 property rows ("a widget is itself an object"); layout persisted per scope (OQ-2/3).
- **Reconciliation:** take bp8 ⑦ at face value. **Each placed widget = a small WORKING entity**: `kind` text + `scope` Reference (absent = Home) + `order` Number (float, the pins landing pattern) + optional `source` Reference (a view entity) + per-kind config cells. **No board entity v0** — one-layout-per-scope falls out of filtering widgets by scope; a grouping node with no cells of its own is dead weight (owner call #3). Consequences, all reuse: **selecting a card → the right panel's Metadata lens is the standard Inspector over the widget entity** — digit-keyed BP-1 rows, D21 footbar, genuinely zero second grammar (not rows painted over a JSON blob). Add = `lotus_widget_add_at` (lazy type-birth in one commit, the `create_pin` shape) — one undo removes it. Reorder = set `order` via existing `lotus_set_at`. Remove = `lotus_trash_at` — the source view survives (bp8's "the definition survives in the registry", for free). **`lotus_board_save_at` is cut from the budget**; layout persistence needs no bespoke verb. Nothing selected → the panel shows a board summary line (scope · N widgets). **Scope context** = shell state (bp8 ② "config, not context"), one per session, re-binding every widget from one computed snapshot slice — widgets are pure `render(ctx)`. v0 scope = Home + workspaces; project/area levels defer. Gallery: type-to-filter focused on open, rank name→description→reads, ⏎ adds and stays, dimmed "Added ✓" rows toggle off, monospace `reads →` on every row — and it lists **only shipping widgets**. Hover chrome ⑥ whole: ⠿ drag (commit order on drop), ‹ ›, ⋯ (only real items), ✕; calm at rest. Template picker ③ **cut v0** — the ㉓ empty board ships verbatim; this also dissolves the "re-apply with confirm" dialog-free collision.
- **Delta:** 1 seed (`widget`), 1 verb, 1 optional section. Recorded: OQ-2/3 answered as entities (better than the view-file asked); gear→panel; picker cut.

### 1.7 The local graph lens — the fifth slot, deterministic radial, zero Rust
- **Law:** VALUE_HEX is THE hue law; lake-green = selection/today only; the reserved `RightLens.graph` slot ("Graph waits for P18" — it landed); no timer loops.
- **Blueprint want:** bp12 Scene B — radial rings by hop depth; value-hop = ONE hop (A19); depth 1/2/3 default 2; value-hops toggle default ON; hand-off to the vault graph; auto-follows focus.
- **Reconciliation:** **deterministic radial, no physics in a 300px panel** — position = pure fn of (hub, hop, index-by-recency), zero motion, stable across opens. Ring 1 = own values (full VALUE_HEX chip recipe) + direct refs; ring 2 = what those reach; ring 3 faded (.55, dashed value edges) — context, not content. Data entirely client-side: `EntityRow.cells[].ref_target` (object→value and wikilink refs) + the existing `backlinkIndex` — the edge index built **once per `applySnapshot`**, never in the draw closure. Object click = becomes hub AND opens in center; value click = the filtered center view through **the one filter engine** (D22, the identical path a search pill takes). Depth + hops toggles in UserDefaults. **The 200-backlink degrade:** per-ring budget ~12 by recency + an honest "+N more" rim count — a count label until the overlay exists, then a button opening the overlay pre-focused (the A22 hand-off IS the degrade path). The hub ring is the only lake-green. Footer count always true. Empty state: "Focus an object to see its neighborhood."
- **Delta:** zero Rust.

### 1.8 The vault graph overlay — one Canvas, seeded springs, honest counts
- **Law:** interface 0.5 sanctioned overlays *for search specifically* — this is a second carve-out and needs the owner's word; calm motion; timers law; never silently capped.
- **Blueprint want:** bp12 Scene A — full-screen overlay, hand-rolled springs, no d3; three node kinds; two edge kinds (thin neutral value edge, **accent** wikilink edge); 238px accordion rail; zoomer/legend/count pill; A16 empty state; per-vault memory (OQ-4).
- **Reconciliation:** the vault graph **keeps the overlay shape** — it is the search palette's anatomy (summon → glance → jump → Esc; consumes no tab; a resting graph surface would be dead chrome). Rides the existing overlay stack (`overlayActive`, DialogHost); entered by **⌃⇧G** (not ⌘⇧G — macOS find-previous), the omnibox, and the lens hand-off. One `Canvas` in a `TimelineView` that **ticks only while hot**; springs seeded FNV-1a from entity ids (deterministic reopen — golden test: same snapshot → identical settled positions); **settle-and-freeze ≤4s**; Reheat; drag reheats locally and pins, double-click releases. Value nodes r≈9+members with the chip recipe promoted to nodes; objects neutral r=6 (color always means "metadata value"); orphans (no values ∧ no refs — the Route predicate's kin) dashed at the rim behind the Unlinked toggle. **The one palette collision: the wikilink edge carries its distinction in weight + opacity (heavier neutral), never hue** — lake-green is selection-only. Edges read-only ("relations are edited in the inspector CONNECTIONS, never here" — ours has it). Tooltip: ~250ms, type icon, ≤3 chips + "+N", preview-only. Rail: one search filters all three accordion sections (Filters open — kind checkboxes w/ live counts, value-family chips, Edited, Unlinked; Display — node size, labels, value-edges toggle; Forces — 3 sliders + Reheat). ⌘-click = background tab, overlay stays; value click exits to the filtered vault, pill visible. Degrade: labels hover-only >~300 visible; >~2000 run-once-freeze, pan/zoom 60fps; count pill always true. Camera/filters/display/forces = UserDefaults per box path (OQ-4: remember) — never entities. Empty state A16 verbatim, primary "Open Inbox → Route". **One GraphKit renders both graphs** — layout strategies differ, the drawing grammar is one (the calendar lesson, applied in advance). bp12 OQ-3 dissolves: Hues.swift IS the one-seed-table pass.
- **Delta:** zero Rust. One governance delta: the second overlay carve-out (owner call #4).

### 1.9 AI — the quarantine, restated
- **Law:** proposals only; amber = AI only; no dead buttons; feedback: "the dashboard never gives AI a write path."
- **Reconciliation:** **What next ships deterministic-only** (due/overdue, stale pins from the Favourites shelf, waiting-on via statusVocabulary); hover open · ＋task (pre-filled, opened in Tasks for review — the human decides, one txn one undo); **dismissals remembered by deterministic id** (hash of kind|entity|date), shell sidecar v0. AI candidates join the *same, visually identical* rows when the answerer opens. **Project summary is not mounted and not gallery-listed** until the P16 answerer fence opens. Zero amber anywhere on the board until AI actually speaks.
- **Delta:** none.

### 1.10 Small collisions (each recorded)

| Blueprint want | Law | Reconciliation |
|---|---|---|
| marigold heatmap today-ring / streak flame | amber = AI only; lake-green = today | today-ring lake-green; flame = ink-opacity |
| accent heatmap fills / sparkline / metric line | lake-green never chart ink | neutral ink ramp; VALUE_HEX only when the series IS one value |
| Pinned = `filter: tier = 1` | pins already exist (P17g shelf) | Pinned reads the shelf by default; its `source` cell is **re-aimable at any saved view**, so a user-minted `tier` property recreates the blueprint literally — no second pin system |
| weather widget | one-integration law | cut |
| ```chart``` in-note fence | embedded live query-blocks refused (T4) | board widget is the one chart host v0; note-side host deferred |
| welcome/quick-actions/nudges/launcher rows | no dead chrome | cut |
| "the amber Inbox badge never migrates here" | the one-badge law | a lock, not a collision |

---

## 2 · The slice plan

**The hazard register drives the order** (grafted from the risk angle): every failure mode gets a named kill-shot in an early, small slice.

| Hazard | Kill-shot |
|---|---|
| H1 one non-optional wire key drops the whole snapshot (×4 new sections) | standing two-box decode test (pre-P18 box under the new decoder; P18 box under a decoder with the section deleted) — re-run every seed slice |
| H2 box-lock on timer stop | optimistic strip clear + async commit + `Committed` check; test stop under a concurrent snapshot read |
| H3 Canvas redraw cost | lens: static draw, <16ms on the worst real entity; overlay: tick only while hot, frozen = one draw |
| H4 physics nondeterminism | FNV-1a-seeded positions, fixed timestep, golden layout test |
| H5 seed idempotence | self-guarded seeds (the `seed_recurrence` pattern); open-seed-open test |
| H6 WORKING rows invisible in `entities[]` | records travel ONLY in dedicated optional sections; test asserts absent-from-entities AND present-in-section |
| H7 dangling refs / overlap | projection skips dangling; totals tolerate overlapping entries |
| H8 undo grouping | every verb = ONE `with_box` transaction |
| H9 chord collisions | CommandRegistry carve-outs (ordered list); ⌃⇧G not ⌘⇧G |
| H10 per-frame edge derivation | edge index built once per applySnapshot, beside `backlinkIndex` |

**Seeds never ship dark** (the risk angle's OC-9, adopted): each seed slice proves its verbs end-to-end on the CLI (`cli/` is the sanctioned headless shell) or an already-sanctioned surface, so no dead shell UI exists at any point.

| # | Name | What ships | Method | Rust delta | Depends | Acceptance |
|---|---|---|---|---|---|---|
| **18a** | **GraphKit + local Graph lens** | `RightLens.graph`; `Graph.swift` — GraphModel (edge index once per applySnapshot) + GraphKit renderer; deterministic radial rings + depth numerals; lake-green hub only; depth 1/2/3 (default 2) + value-hops toggle (prefs); honest footer counts; "+N more" rim **count** (label, not button); both empty states. Footer "Vault graph" button does NOT mount yet. | Mockup-first (Mockup 1) | **Zero** | — | Auto-follows focus; value-hop = one hop against a known box; value-node hue byte-matches the same value's inspector chip; worst real entity renders inside one frame; toggles never touch the box; no Timer/DisplayLink anywhere |
| **18b** | **Seeds I: habits + check-ins** | `habit` + `check-in` seeds (self-guarded, Author::System); `lotus_create_habit_at`, `lotus_check_in_at` (with_box + Committed::Wrote, the create_pin shape); `habit_stats` projection (streaks/points/84-day buckets/today's ids; skips dangling); Snapshot +`habits` OPTIONAL — the H1 recipe established here. **CLI proof: `lotus habit add` / `lotus checkin` / `lotus habits`.** Swift decoder lands optional, dark. | **Failing-test-first**, every piece | 2 seeds · 2 verbs · 1 projection · 1 section | — (∥ 18a) | Two-box decode test both directions; check→uncheck = two single undos restoring exactly; trash-the-habit → non-panicking projection; open-seed-open = one type set; rows absent from `entities[]`, present in `habits` |
| **18c** | **Vault graph overlay** | Full Scene A on GraphKit: inset card + scrim, top bar (scope pill, node-search w/ first-Esc-clears/second-closes, permanent Esc hint, ✕), dot-grid canvas, all node/edge taxonomy (heavy-neutral wikilink delta), tooltip, zoomer/legend/count pill, 238px accordion rail, seeded springs (settle-freeze ≤4s, Reheat, drag-pin), A16 empty state, ⌃⇧G + omnibox entry; **the 18a "+N more" and footer hand-off go live**, camera pre-focused on the hub; per-box prefs. | Mockup-first (Mockup 2) + **golden-test-first for the layout fn** | **Zero** (needs owner calls #4/#5 first) | 18a | Same box → identical settled layout across reopens; 0% CPU once frozen (instrument); 2000-node synthetic box: run-once-freeze, pan/zoom 60fps; count pill true under every filter; ⌘-click keeps overlay; Esc ladder exact |
| **18d** | **Seeds II: time + view + widget** | `time-entry`, `view`, `widget` seeds (all WORKING); `lotus_log_time_at`, `lotus_create_view_at`, `lotus_widget_add_at` (lazy type-birth, one txn); `time_totals` projection (overlap-tolerant); Snapshot +`timeEntries` +`views` +`widgets` (OPTIONAL). **Proving surfaces: CLI `lotus time log`; "Save view…" on the ⌘F search surface + a Views group in the Library** (the sanctioned bookmark, feature-map #21/#28) — the view entity proven end-to-end before any widget exists. | **Failing-test-first** | 3 seeds · 3 verbs · 1 projection · 3 sections | 18b (recipe) | Overlapping CLI entries don't break totals; save query → reopen → identical result ids; widget_add on a fresh box births types + widget in ONE commit (one undo removes all); decoder missing every new key still yields a snapshot; a view matching nothing renders an honest empty list |
| **18e** | **Surface.dashboard + board shell** | Rail icon mounts NOW (widgets are real); Shift+Tab (carve-outs) + ⌘⇧M + View menu; the ㉓ empty board verbatim; add-widget gallery whole (type-to-filter, ⏎-adds-and-stays, Added ✓, `reads →`); scope chip (Home + workspaces); card grid (6-col, blueprint spans, ≤228px min-height, responsive 2-col) + hover chrome; **[Selection] = the standard Inspector over the widget entity**; nothing selected → board summary line. First real widgets: **Tasks summary** (statusVocabulary counts → opens Tasks filtered) + **Pinned** (the P17g shelf via EntityLine/RowKit; source re-aimable at any view). | Mockup-first (Mockups 3–4) | **Zero** (consumes 18d) | 18d | Shift+Tab mid-outdent outdents; added widget survives relaunch and travels with the box, one undo removes it; select card → Inspector rows edit real cells and the card re-renders live; reorder = one commit; Esc = places-history back; gallery lists only built widgets; no badge anywhere |
| **18f** | **Survey widgets: Agenda, Metric chart, Saved view** | Agenda · today (role-filtered occurrences + due-today + the daily-note row opening `.today` + ONE countdown strip); Metric chart (numeric property × collection × N days, computed client-side; avg/max/min footer; neutral ink, VALUE_HEX when the series IS one value); Saved-view card (dashed empty specimen verbatim; "Choose view…" over existing views only; shared list mini-lens — never a fork). | Mockup-first per widget body | Zero | 18d, 18e | A valid-until date provably never appears in Agenda (test box); multi-day event = ONE strip; every chip click lands in the one filter engine; unaimed card idles without nagging; empty fields never render |
| **18g** | **Habits & points, whole** | The span-3 card: TODAY — CHECK IN rows (+N weights) wired to `lotus_check_in_at`/`lotus_trash_at`; four stat tiles w/ plain-words formula tooltips; 12-week chain heatmap (neutral ramp, **lake-green today ring**, day-click popover w/ per-row undo, never a percentage); points sparkline (neutral ink); `habits` collection link; export-to-sheet stretch via `lotus_export_at`. | Mockup-first (rides Mockup 3's detail) | Zero (consumes 18b) | 18b, 18e | Check = one FFI call, one undo; uncheck trashes the exact row from todayCheckInIds; tiles/heatmap recompute from the projection with no stored stats; zero amber; density ≤ blueprint (26px rows, 11px cells) |
| **18h** | **Time widget + timer invariant + What next + delta log** | Per-project VALUE_HEX bars (bar → entries list); running-timer strip (TimelineView 1s tick over the pref); ▶ start on bars + "Start timer" in RowKit ⋯ menus (no interim top-band chrome — the timer ships with its widget home); ■ stop → `lotus_log_time_at`, optimistic + async; start-while-running fold; **What next deterministic-only** w/ dismissal sidecar; `design/p18-dashboard-graph.md` delta log recording every delta in §7. | Mockup-first + invariant behavior tests | Zero (consumes 18d) | 18d, 18e | Log byte-length unchanged across 60s of ticking; stop = one entity, one undo, even under a concurrent snapshot read; fold never double-counts a second; strip survives relaunch still ticking; a dismissed candidate never returns across relaunch; bar hue = chip hue everywhere |

**Sequencing logic:** 18a ∥ 18b open both tracks; the physics core (18c) and the fat seed slice (18d) land by mid-phase — every risk retired before the board (18e) begins; 18e–18h is pure assembly from proven parts. Every intermediate state is a coherent app with zero dead buttons.

**Total Rust budget** (all in 18b/18d, all flagged in the PR, all failing-test-first): 5 type seeds (`habit`, `check-in`, `time-entry`, `view`, `widget`) · 5 additive verbs (`lotus_create_habit_at`, `lotus_check_in_at`, `lotus_log_time_at`, `lotus_create_view_at`, `lotus_widget_add_at`) · 2 services projections · 4 OPTIONAL snapshot sections. `lotus_board_save_at` is **cut** — widgets-as-entities ride existing set/trash verbs.

---

## 3 · Open owner calls (each with a firm recommendation)

1. **WORKING extended from curation to backstage records** (check-ins, time entries, views, widgets — hundreds of rows, not a shelf). **Approve** — durable facts referencing vault ids that must travel with the box, the discriminator's own words; compensating rule: every WORKING record kind gets a dedicated optional snapshot section (H6) — data is never reachable only through `entities[]`.
2. **Running timer: UserDefaults pref vs open entity at start.** **Pref.** Start must cost zero IO; a half-open interval is a promise an append-only log shouldn't hold; fold and relaunch-survival both work from the pref.
3. **Board shape: widgets-as-entities, NO board entity v0.** **Approve as specified.** The 2026-07-14 feedback text said "board layout as a view entity per scope — ratify OQ-2"; this design satisfies its *intent* (layout travels with the box; config = property rows in the panel) with a strictly simpler shape — per-scope boards fall out of filtering widgets by scope, and the panel edits real cells instead of a blob. If the owner insists on the letter, a thin `board` entity can be minted later without touching the widget model. One word to lock.
4. **The vault-graph overlay as a second interface-0.5 carve-out** (0.5 was search-specific). **Grant** — summon/glance/jump/Esc, consumes no tab; a resting graph surface is dead chrome. Record as extending 0.5, not repealing 0.2. Needed before 18c starts.
5. **Chords:** Shift+Tab + ⌘⇧M for the board (already ordered); **⌃⇧G** for the graph — NOT ⌘⇧G, which is the macOS text system's find-previous. bp8 OQ-1 (`Ctrl+Home`): **refuse**. Lock all three before 18c/18e.
6. **Degrade thresholds** (labels hover-only >~300 visible; run-once-freeze >~2000; lens per-ring budget ~12 by recency). **Adopt as defaults, re-measure** on a synthetic 2000-node box at the 18c mockup gate. Never a silent cap; the count pill is the contract.
7. **Chart ink** (taste call at the 18g mockup gate). **Neutral ink everywhere by default**; VALUE_HEX only where the series IS one value (per-project bars). Lake-green appears in charts exactly twice: the heatmap today-ring and selection.
8. **Scope v0 = Home + workspaces only.** **Approve**; project/area scope defers until a scoping story exists — recorded, not dropped.
9. **What-next dismissal memory: shell sidecar vs box-resident.** **Sidecar v0** (cheap, reversible); revisit if "never re-asked" must hold across two machines.
10. **bp12 OQ-4 (graph persistence):** remember camera/filters/display/forces per box **via shell prefs** — never entities. **Approve.**
11. **Template picker: cut v0.** **Confirm the cut** — the empty board + gallery is the honest start, and it dissolves the confirm-dialog collision. Revisit if first-run friction proves real.

---

## 4 · Where the angles disagreed (and who is right)

- **The board data model.** Fidelity stored widgets as config blobs in a per-scope board entity saved by `lotus_board_save_at`, then claimed "no second editor grammar" — false by construction: rows over a JSON payload are a pseudo-inspector, and every edit round-trips a whole-board save. **Constitution is right**: widgets as entities make the ruled config panel literally the existing Inspector, cut a verb from the flagged budget, and give one-undo-per-gesture for free. Risk hedged (recommended entities in OC-3 but still shipped the verb — two write paths for one layout); the hedge is rejected.
- **Proving surfaces for seeds.** Constitution shipped 18c/18d as pure Rust exercised by nothing for four slices — exactly the failure the test-drive-core-changes memory warns about. **Risk is right**: CLI subcommands + "Save view…" on ⌘F prove every seed end-to-end with zero dead shell UI. Adopted wholesale.
- **When the physics lands.** Fidelity parked the overlay — the single riskiest render in P18 — in the final slice. **Risk is right**: the canvas core lands at slice 3, small enough to throw away. Constitution had it second, which also works; slice 3 lets the seed recipe (18b) establish first.
- **The dashboard's arrival.** Risk back-loaded the board to slice 6 of 8 and paid for it with invented interim chrome (a top-band timer strip torn out later, a throwaway "+N more" list popover). **This plan lands the board at slice 5 with no interim chrome at all**: the timer ships with its widget home (18h), and the lens's "+N more" is a plain count label until the overlay makes it a button — a label is honest, a stub popover is scaffolding.
- **Template picker.** Fidelity kept it and admitted its Starter set would offer widgets that don't exist yet — the dead-button smell named exactly. **Constitution/risk are right: cut v0** (owner call #11).
- **The streak flame.** Fidelity tinted it lake-green — violating the selection/today-only law it elsewhere enforces. **Constitution is right**: ink-opacity, neither amber nor lake-green.
- **The graph chord.** Only constitution spotted ⌘⇧G = find-previous. **⌃⇧G.**
- **Resume widget.** Fidelity shipped it small; constitution deferred. **Defer** — places history, layers, and ⌘⇧T already serve resume, and the widget is registry-only even in the blueprint's own mock. It becomes a cheap add once the board exists; recorded, not dropped.
- **The disposition discipline.** Fidelity's scorecard — every annotation named ships/relocated/deferred/cut, with "relocated, not cut" enforced — is adopted as this doc's §7, and its re-aimable-Pinned trick (shelf by default, `source` re-aimable, user-minted `tier` recreates the blueprint through existing property machinery) is grafted verbatim.

---

## 5 · Mockup surfaces to draw first (in order; each gates its slice)

1. **The local Graph lens** (gates 18a) — the 300px right card, five-lens strip with Graph active: three dashed rings + depth numerals, lake-green hub + halo (the only accent), ring-1 values in true `Hues.valueHex`, ring-3 faded/dashed, Depth 1|2|3 segment (2 on) + Value-hops toggle (on), true footer count. **Drawn three ways:** a normal note · the 200-backlink monster with the "+N more" rim count · the empty state. Both themes.
2. **The vault graph overlay** (gates 18c) — 16px-inset card over the scrim: full top bar, dot-grid canvas with all three node kinds, **both edge weights — the heavy-neutral wikilink delta must be seen to be judged**, dashed orphans at the rim, hover tooltip with the chip budget, zoomer/legend/count pill, 238px rail with Filters open. Inset: the A16 empty state. This mockup gates the edge-hue delta, the degrade thresholds, and owner call #4.
3. **The dashboard surface** (gates 18e/18g) — full window: rail with the 7th icon lit, board on bare material at lotus density (cards ≤228px min-height, 13px gaps, 26–33px rows), scope chip "Home", populated with Habits span-3 **detailed** (check-in rows, stat tiles, neutral-ramp heatmap with lake-green today ring, sparkline), Agenda + countdown strip, Pinned, Tasks summary, Time bars w/ running strip. **Plus the ㉓ empty-board state.** This mockup settles the surface skin, the 8.1/8.2 palette deltas, and the density bar in one sitting.
4. **The board's edit grammar pair** (gates 18e/18f) — the add-widget gallery open (query "ha" pre-typed, ranked rows, one dimmed "Added ✓", `reads →` lines) beside a selected card with hover chrome and the right panel showing **the standard Inspector over the widget entity** (digit-keyed source/scope/range rows, MORE PROPERTIES collapsed, D21 footbar) — and the nothing-selected board-summary state. Proves the no-gear, one-grammar ruling in pixels.

---

## 6 · Cuts, deferrals, and recorded deltas

**Cut (the whole list, named):** dashboard-as-overlay (ruled → surface) · per-card gear popover (ruled → panel) · `Ctrl+Home` chord · template picker (empty board + gallery is the honest start) · weather (no integration slot) · welcome / quick-actions / nudges / launcher / recent-activity gallery rows (dead chrome) · `tier` property (Pinned reads the P17g shelf; a user can mint `tier` themselves) · `lotus_board_save_at` + the board entity (superseded by widgets-as-entities) · interim top-band timer strip (the timer ships with its widget).

**Deferred, with the named reason:** AI Project summary + AI What-next rows (answerer fence, P16 D2 — not gallery-listed until then) · D19 habit-block-in-note suggestion (clerk proposer, P16 family; lands in the ONE inbox, never a board banner) · in-note ```chart``` fence (embedded live query-blocks refused, T4; the board widget is the one chart host v0) · export-to-sheet wiring (rides `lotus_export_at` when it lands; 18g stretch) · "3×/wk" habit cadence semantics (recurrence grammar extension, feature-map #19 — "when daily use asks") · people-as-nodes toggle (bp12 OQ-2; default-OFF per the blueprint itself) · project/area scope levels (owner call #8) · Resume widget (places history + layers + ⌘⇧T already serve resume; cheap add later).

**Relocated, feature intact:** dashboard overlay→surface · gear popover→the standard Inspector · D19 banner→inbox proposal · `filter: tier=1`→pins shelf + re-aimable source · bp8 ㉔ focus-restore→places-history Esc.

**Recorded deltas (the delta log for this file, maintained through 18h):** overlay→surface · gear→panel · D13 view-file→entity (lotus has no view-files) · WORKING extended from curation to backstage records · marigold today-ring→lake-green · streak flame→ink-opacity (neither amber nor lake-green) · accent wikilink edge→heavy neutral (weight, not hue) · heatmap/sparkline→neutral ink ramp · tier→pins shelf · OQ-2/3 answered as per-scope widget entities rather than a view-file · template re-apply collision dissolved by the cut · the second overlay carve-out (extends 0.5, does not repeal 0.2) · "+N more" as count label until 18c makes it a door.
---

## Delta log (as-built, 18a–18h — P18 COMPLETE)

- **18a** local lens: ring budget 12 by recency; "+N more" is a rim LABEL (the
  vault-graph door is the footer button). Zero Rust.
- **18b** habits: front-of-house type + WORKING check-ins, exactly as specced;
  CLI = the proving surface (`habit`/`checkin`/`habits` with chain glyphs).
- **18c** overlay: determinism BY CONSTRUCTION (seeded FNV positions, fixed dt,
  no Date/random in the sim) — no Swift test harness exists to hold a golden
  test; recorded. Wikilink edges are not derivable shell-side (span targets
  aren't in the snapshot cells), so the HEAVY edge class = explicit reference
  cells; via-value stays thin. Labels: values always, objects on hover.
- **18d** seeds: lazy-birth inside the first write's transaction (the pins
  precedent) instead of open-seeds — strengthens the one-undo acceptance
  (types unwind with the first record). Proving surfaces shipped: CLI `time`,
  palette "Save view…", Library VIEWS group.
- **18e** dashboard: overlay→surface (the 07-14 ruling); widget rows join the
  FFI row store so the standard Inspector resolves a selected card (row store
  only — id lists untouched, asserted); ⇧⇥ entry deferred (the Hotkey machinery
  can't express Tab; ⌘⇧M + rail cover it); the 6-col span grid renders as an
  adaptive flow v0.
- **18f** metric chart: v0 series = the collection's CREATION CADENCE (the
  numeric-property series waits for a property-picker config row); agenda
  derives from calendarByDay — the calendar's own function, lookup roles
  excluded by construction.
- **18g** habits card: whole, zero amber, lake-green today-ring; projection
  grew points-per-day + window check-ins (test-first) for the sparkline and
  the day popover. Export-to-sheet deferred: the export grammar cannot reach
  WORKING records yet (named).
- **18h** timer: the pref is the single source (`app.timer.v1`); start doors =
  the widget bars' ▶ + every ObjectRow's context menu (no top-band chrome);
  stop = optimistic strip clear + one async commit; start-while-running folds.
  What-next: deterministic candidates only (overdue → due-today → mid-flight),
  dismissal sidecar in shell prefs, "no AI here" stated on the card.
