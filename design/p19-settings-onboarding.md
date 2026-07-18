# P19 — Settings + Onboarding (BP-13 + BP-2)

**What this phase builds — and it is the FINAL phase.** The two surfaces the blueprint assessment left standing at the end of the scorecard: Settings as the **fourth overlay carve-out** (the modal that answers to the one search grammar — properties panel, vocabulary shelves, the shortcut map that completes gate 5-R2, the Assist panel with the constitution's third budgeted setting), and the **BP-2 first-run tour** run inside the live app with zero dialogs. It also pays three standing debts in one motion: the constitution's three budgeted settings (capture hotkey · store location · automation switch) finally get their rows, the P11.5 kind-resolution gap (`InspectorEditors.swift:765-771`) is closed for the inspector and the new panel together, and the orphan pref `app.inspector.hints.v1` (`DigitMap.swift:17`) gets its first writer. When 19i lands, every BP row is dispositioned and the phase ledger closes.

**The spine is constitution-first; the grafts are earned.** Three design angles were drafted and judged. This doc takes the constitution proposal's reconciliation stances (overlay-not-window, settings answer to the grammar without being entities — including its trick of folding live `snap.properties` into the search pool at query time — pre-commit counts instead of confirm dialogs, the delta ledger), the risk proposal's sequencing regime (the three dangerous cores — the multi-carrier rename, the keymap that can brick keyboard access, the unrehearsable tour — get named kill-shots in early headless slices, with the CLI and a `LOTUS_BOX_PATH` harness as proving grounds), and the fidelity proposal's dispositioning grammar (features with no lotus referent keep their story as **locked "convention — not configurable" rows** and honesty lines rather than vanishing — bp13 ann. 26's own move). One claim made by two of the three angles is **corrected**: closing the kind-resolution gap is *not* zero-Rust — the as-built comment those designs cite records that hide-on-kind is a reference cell to a kind entity **whose id the snapshot doesn't carry** — so the kind-id wire seam is budgeted explicitly (19c). Section 5 records where the angles disagreed and who won.

**Rulings bind and are re-verified against the tree.** No new permanent chrome, no dead buttons, dialog-free (grouped transaction + pre-commit count + undo toast, never a modal confirm), theme/font panels stay cut, subscription proxy banned, amber = AI only, lake-green = selection/today only. As-built anchors checked 2026-07-15: the box lives at `~/Library/Application Support/lotus/lotus.log` (`main.swift:27-29`), **not** `~/lotus/`; `app:open-settings` is a live stub with **⌘, already bound** (`Window.swift:2413-2419`), reached from the hub-footer gear (`Chrome.swift:519-521` → `Window.swift:1745-1746`) — P19 replaces an alert body, **zero new chrome**; the undo chord is **⌘⌥Z** (`Window.swift:2395`); ~23 `CommandDef`s register with fixed bindings (`Window.swift:2263-2464`); `overlayActive` swallows the map (`Commands.swift:129`); reserved letters N/M/H/L/F/G/S/W (`DigitMap.swift:48`); the capture hotkey ⌃⌥Space is hardcoded with its own "one of the budgeted settings" comment (`main.swift:379-404`); `clerk::sweep` runs unconditionally (`ffi/src/lib.rs:427-434, 450-459`); verbs verified — `lotus_undo_at`:1313, `lotus_open_daily_note_at`:1607, `lotus_distinct_values_at`:1677 (the brief's `lotus_value_pool_at` does not exist), `lotus_status_options_at`:1717, `lotus_add_status_option_at`:1748, `lotus_add_property_at`:1788.

---

## 1 · Reconciliation ledger

### 1.1 Where settings live — the fourth overlay carve-out
- **Law:** interface.md 0.5 sanctions overlays (search palette, switcher, vault graph); no new permanent chrome; the constitution's settings budget (`productivity_app.md:550-557`); dialog-free.
- **Blueprint want:** bp13 a1/a35 — a 920px modal over the scrim; Esc closes; reopens to last panel; changes apply instantly, no Save; scope tag on every row; opened by gear or Ctrl+,.
- **Reconciliation:** the blueprint's modal **is** our overlay — nothing bends. A centered ~920px card (max 95%, 30px vertical inset, radius 14) over a scrim, in the search-palette anatomy: header (gear · "Settings" · search focused on open · ×) / **six-group nav** ~198px (**Appearance · Properties & Vocabulary · Shortcuts · Capture & Store · Assist · Startup**) / scrollable panel / the shared footbar grammar (`⌘,` open · `Esc` close · `↑↓` groups · type filters · `⏎` jump — right-aligned: *"changes apply instantly — there is no Save button"*). Entry points all exist: ⌘, (replace the stub's alert body), the hub gear, plus the standard app-menu "Settings…" item routed to the same command. Esc layers (dropdown first, then the overlay); reopen restores the last panel (`app.settings.lastPanel.v1`, internal, no row). Every destructive-ish act answers with an **undoable toast, never a confirm** — bp13 a35 and the dialog-free law agree verbatim. No "Sync & Account · future" group: a nav item for a banned feature is dead chrome (recorded deviation from a34's honesty-over-polish; the honesty survives as one line in Capture & Store, §1.7). New file `shell/macos/Sources/Settings.swift`, hosted in the existing overlay ZStack.
- **Delta:** modal→overlay (shape only). Zero Rust.

### 1.2 Search-over-entries — settings answer to the grammar without being entities
- **Law:** one grammar everywhere; transient UI state is never an entity; assessment: "settings-as-objects searched by the one grammar."
- **Blueprint want:** bp13 a2–a4 — type-to-filter over every entry; result rows carry group·scope·kind chips; digits 1–9 cycle group facets; flash the exact row; 0 results hands ⏎ to the vault palette.
- **Reconciliation:** entries are a **static shell-side table** — `SettingEntry{id, label, group, scope(.vault/.app), kind, keywords, panelAnchor, currentValue()}` (`SettingsEntries.swift`) — rendered in the property-row grammar: bolded match, muted current value, chips `group · scope (lake-green-tinted) · kind`, `⏎` on selection. **Live `snap.properties` folds into the pool at query time**, so the data that *is* objects (property and vocabulary rows) really is searched as objects, while knob-descriptions never pollute Everything. ⏎/click opens the owning panel and flashes the exact row (~1.6s accent-soft). Digits cycle group facets include→exclude→off — the D21 map consulted, never forked. 0 results: ⏎ closes Settings and opens the search palette pre-filled. **Rejected and recorded: settings-as-box-entities.**
- **Delta:** none. Zero Rust.

### 1.3 The two scopes — enumerated, nothing migrates
- **Law:** cells in the box travel; shell prefs are machine hardware; transient state stays out of the box.
- **Reconciliation:** **Vault scope** (existing verbs unless noted): property definitions — name/value-kind/icon/digit-key/hide-when-empty/hide-on-kinds/core-on-kinds via `lotus_set_at`/`add_cell`/`remove_cell`/`unset_at`; add/delete via `lotus_add_property_at`/`lotus_trash_at`; status + priority option entities (name/hue/order/for-type/completes); the new `hidden` cell on options (§1.5); vault-wide value rename (**the one new mutation verb**, §1.5); the automation switch on a WORKING `assist` entity (§1.8). **App scope** (`@AppStorage`): `app.appearance` (exists), `app.inspector.hints.v1` (exists — P19 is its first writer), new `app.startup.v1`, `app.keymap.v1`, `app.capture.hotkey.v1`, `app.reading.serif.v1`/`app.glyph.strength.v1` (if the mockup earns them), `app.onboarding.v1` (done · step · banner dismissal), `app.settings.lastPanel.v1`. **Keychain, neither scope:** the BYOK key (SecItem). All fifteen other audited `@AppStorage` keys (tabs, pane geometry, lens memory, graph knobs, the timer, what-next dismissals) stay **internal with no rows** — observation-reachable transient state; the inventory's audit table lands in this file's delta log verbatim as the record.
- **Delta:** none — the split falls out of the laws.

### 1.4 Properties panel — the definitions editor, dialog-free, and the kind seam paid
- **Law:** one txn one undo; deletion never cascades; never a modal confirm; shared components over forks.
- **Blueprint want:** bp13 a6–a14 — the table (Property·Type·Shortcut·Core·⋯, spine first, customs last with live provenance); vault-wide rename/retype/re-icon with count-confirm; the D21 shortcut cell; core star (kind-tuned); the row ⋯ menu = the inspector's; customs deletable, spine hideable-not-deletable; digit-hint segmented row heading the panel.
- **Reconciliation:** the inspector's **mirror, not a second editor** — one schema, two doors. Rename/retype/re-icon are one-cell writes on the definition entity — **vault-wide by construction** (cells key on def id). The count-confirm dialog becomes the constitutional pattern: live carrier count on the control *before* commit ("carried by 41 objects") → one transaction → toast *"Renamed on 41 objects — ⌘⌥Z undoes."* **Retype delta recorded:** sets `value-kind` only; carrier cells are never rewritten (schema-on-read; `views::display` re-renders) — a deliberate, safer divergence from Liv's rewrite-every-file. Delete = custom-only `lotus_trash_at`; carriers keep their cells — bp13 a14's "delete only un-indexes" is *literally* our semantics. The row ⋯ menu is extracted into a shared component adopted by **both** this table and the inspector, un-graying `InspectorEditors.swift:769-771` — and this is where the correction bites: hide-on-kind is a **reference cell to a kind entity whose id the snapshot doesn't carry**, so the writers need the **kind-id wire seam** (an optional snapshot key exposing kind-entity ids alongside `hideOnKinds`/`coreOnKinds`) budgeted in 19c — *not* zero-Rust. Core star writes `core-on-kinds` for the current kind context (small picker on click); star-off toast: "Moved to MORE PROPERTIES — still keyboard-reachable." Add property = the inspector's N-row schema-on-read flow, shared. The digit-hint row (a6) heads the Shortcuts panel instead (§1.6) and is cross-linked here.
- **Delta:** count-confirm→pre-commit count + undo toast; retype-no-rewrite; **one additive wire seam (kind ids)**.

### 1.5 Vocabulary shelves + the seed layer (D17)
- **Law:** append-only (nothing hard-deleted — D17's "reversible forever" holds by construction); seeds are offers; the applySnapshot rule (every new wire key optional).
- **Blueprint want:** bp13 a15–a18 — three shelves per property (in-your-vault with counts / seeded dashed, hideable, renameable / hidden, restorable); used seeds migrate up; per-kind status vocabularies re-keying task-board columns; the gazetteer panel.
- **Reconciliation:** *In your vault* = `lotus_distinct_values_at` with counts; chip click → rename or recolor. Value rename is **the one true multi-entity rewrite** — the only rename the data model doesn't give for free — and gets the phase's one required verb: **`lotus_rename_value_at(path, property, old, new) → count`**, ONE grouped transaction across all carriers, `with_box` + `Committed::Wrote`, one `lotus_undo_at` restores everything; merge-on-collision is legal, shown as a count before commit, and un-merges on undo. *Seeded* = System-authored option with zero carriers, dashed; hover-× hides (a `hidden:true` cell), double-click renames in place, "Hide all seeded" per property; a used seed **migrates up automatically** — the distinction is derived, so this is free. *Hidden* = collapsed, struck-through, per-chip Restore. Seeded-vs-used goes on the wire as **optional** keys `OptionRow.{count, seeded, hidden}` + `PropertyRow.seeded`. Per-kind status table rides existing verbs (`status_options`/`add_status_option`/set/trash/`for-type` cells); board columns re-key because they already project from options. Priority add rides the small generic **`lotus_add_option_at`** (`add_status_option` minus the for-type leg) — without it the shelf's ghost "add" is a dead button on non-status selects. **Gazetteer editing collapses into this panel + ordinary entity renames** (the gazetteer is derived, `clerk.rs:271-291`) — build nothing separate; record the reconciliation.
- **Delta:** 2 additive verbs · 4 optional wire keys · the `hidden` cell convention (data only).

### 1.6 The shortcut editor — R2 completed: one table, two sections, brick-proof
- **Law:** D21 one global map; the two-scopes law; never a modal, never a silent double-binding; the P11.5 partial ruling (digit-key cells are the override store; DigitMap is the reader whose own header names this editor as its writer).
- **Blueprint want:** bp13 a9–a11 + OQ-1 — the shortcut cell as the map editor; record mode; conflict warnline; press-again-to-steal; do command bindings join the table?
- **Reconciliation:** **OQ-1 ruled: Option A — one table, two sections.** *Section 1, property keys (vault):* recorder cell → `digit-key` cells via `lotus_set_at`; reserved letters render locked with the reason; travels with the box, so the Windows shell reads the same cells. *Section 2, command chords (app):* the ~23 `CommandDef`s grouped by category; overrides in `app.keymap.v1` consulted at registration; per-row reset; chords are platform hardware (⌘ vs Ctrl) and **never enter the box**. Conflicts cross-section: inline red warnline ("⚠ `3` belongs to **subjects** — pick another key, or press again to steal it"); press-again steals; toast + one undo (vault steal = set + unset in one grouped commit). **The brick-proof spine ships before the editor** (the risk graft, adopted whole): an **unstealable set** enforced at record *and* load time (⌘, · Esc · ⌘⌥Z · the app menu never rebind — the mouse path to *Settings…* and *Reset all shortcuts* always exists); load-time validation (malformed pref → discard, log to the box file, run on defaults — never crash, never half-apply); conflict detection as a pure function over defaults ∪ overrides ∪ digit-key cells; `app:reset-shortcuts` as both a command and a fixed NSMenu item. The digit-hint visibility row (Always/Hover/Off — "the keys THEMSELVES always work") heads this panel: the PLAN-guard template — display, never behavior.
- **Delta:** none in Rust. Gate 5-R2 closes here.

### 1.7 Capture & Store — the budgeted rows, plus the locked-row grammar for what has no referent
- **Law:** capture asks nothing (already law); captures are unnamed scraps (no naming referent; collisions impossible — names aren't keys); R1 unratified (all file-pool knobs gated); no dead buttons.
- **Blueprint want:** bp13 a25–a29 — naming-convention radios, collision policy, auto-sort pools, per-type overrides, workspace-folder bindings, frontmatter mirror, `.liv/` OQ-2; a34's Sync & Account placeholder.
- **Reconciliation:** one panel, everything on it real: (1) **capture hotkey** — budgeted setting #1: a recorder row (default ⌃⌥Space), `app.capture.hotkey.v1`, live Carbon re-registration; (2) **the locked convention row** (fidelity's graft — bp13 a26's own grammar): lock glyph + "convention — not configurable" — *"Capture never asks for a name, a folder, or a type. Scraps are routed later from the Inbox."* The whole naming story on one page, zero dead controls; (3) **store location** — budgeted setting #2: read-only mono row showing the true path (`~/Library/Application Support/lotus/lotus.log`) + Reveal in Finder; the relocation *flow* (move + relock + re-point) deferred to its own design — a dead "Change…" is worse than none; (4) **Export** row linking the existing composer — the trust beat's settings anchor; (5) **the sync honesty line** absorbing a34's futbox: *"The box is one file. Multi-device sync isn't built — sync the file with any tool you trust; Liv won't fight it."* Cut: naming radios, collision row, and the Library panel wholesale (R1-gated; if R1 ratifies as projection, per-type export rules return as BP-14's small map — OQ-2 dies with it, its write-into-folder recommendation carried forward).
- **Delta:** panels renamed to the lotus truth; the cuts recorded.

### 1.8 Assist — the automation switch + BYOK, nothing fake
- **Law:** AI quarantined (proposals only); amber = AI only; subscription proxy banned; no dead buttons; the P16 fence; the constitution's third budgeted setting.
- **Blueprint want:** bp13 a30–a32 — plan proxy + cap meter, BYOK fallback, aggressiveness segmented row, the fixed-contract rulebox.
- **Reconciliation:** three rows, all real. (1) **The automation switch** — today `clerk::sweep` runs unconditionally; it gets its consent: a cell on a small backstage WORKING `assist` entity (the pins pattern, `content.rs:759+`); `sweep` yields nothing when off. **Vault-scoped** — the consent boundary belongs to the data, so the CLI and every future shell honor it; default ON (the clerk is deterministic and quiet), preserving as-built behavior byte-for-byte. The one sanctioned services touch: failing-test-first, owner sign-off. (2) **BYOK slot** — Keychain SecItem, functional store/clear (it *really* stores), honestly captioned dormant: *"No model is wired yet. The key waits in your Keychain for the answerer — the first fence to open (P16 D2). Never in your vault, never synced."* (3) **The fixed-contract rulebox** — amber-bordered copy, deliberately not controls (amber is right here: it *is* about AI): proposals only, visible accept/dismiss, values from vault + seeds, never re-asks a dismissed field, never touches tier. Pre-empts the "where do I turn this off" search. Cut: plan picker + cap meter (banned); the aggressiveness knob (deferred behind the fence — the deterministic proposers are quiet by construction; the switch *is* the volume control; no second consent toggle, per the standing owner answer).
- **Delta:** 1 WORKING seed + 1 guard in `clerk.rs` + 1 optional snapshot key (flagged).

### 1.9 Appearance + Startup — the post-cut remainder
- **Law:** theme/font/shape cards cut (assessment ruling stands); display-only knobs never fork behavior.
- **Reconciliation:** **Appearance:** light/dark/system (writes existing `app.appearance` — one pref, two doors with the Chrome sun/moon button) · reading-mode serif toggle + inline glyph strength Normal/Minimal/Off (bp13 a22's survivors — **build only if the mockup earns them**; both display-only, density-legal). **Startup:** one radio, `app.startup.v1`: **Continue where I left off (default — this IS the as-built behavior** via `app.activeExtension.v1`/`app.activeWorkspace.v1`/`app.tabs.v1.*`) · Fixed workspace (picker) · Today's note (`lotus_open_daily_note_at` at launch — subsumes the P12-dropped daily toggle and bp13 a24's startup row). The blueprint's "Open Welcome screen" mode is replaced by the replay entries (§1.10) — a startup mode for a one-time tour is dead weight. **The Daily-notes panel does not exist** (P12: "nothing to configure"; the template stays the D4 `const`, `content.rs:195-200` — copy refinement is a copy change, not a setting).
- **Delta:** startup default Continue (blueprint said Fixed) — recorded.

### 1.10 Onboarding — the tour is the product running; zero dialogs
- **Law:** "the first run asks nothing … never a setup wizard" (`productivity_app.md:559-568`); dialog-free; amber = AI only (bubbles are lake-green — bp2 a8 itself agrees: accent = the app speaking); no new chrome rows; R1 unratified.
- **Blueprint want:** BP-2 whole — the vault dialog, capture ×3, THE CLICK, find-it-back, coach bubbles, seeded banner, after-state, <60s, resume-at-dot, skip everywhere.
- **Reconciliation:** **Split on R1** (firm): the box auto-seeds silently (`seed_if_fresh`, `lib.rs:64-84`) — "asks nothing" is *already built* — so the tour ships **R1-independent with zero dialogs** (one better than the blueprint's one); the vault-location moment + "point Liv at a folder I already have" become a recorded insertion point if R1 ratifies (with the OneDrive caveat, bp2 OQ-3). **First-run detection is a conjunction:** `snap.everything.isEmpty && !app.onboarding.v1.done` — a fresh box has only WORKING seeds; the pref conjunct protects an existing user with a fresh prefs file; all four quadrants tested. **The trust beat keeps the claim, re-grounds the substance** (bp2 ⑸: voice may change, claim may not): *"Everything you write lives in one append-only file on your disk — nothing is ever overwritten or silently deleted. Export it whole as plain files, any time; inspect it without Liv (`lotus --log … list --all`). If Liv disappeared tomorrow, you keep it all — structure included."* Owner voice pass required (bp2 OQ-1's successor). The `will create →` line shows the mono truth: one file, the whole vault. **The script over as-built surfaces:** Welcome overlay card (not a dialog; Start `⌘⏎`, Skip) → optional **topic-picking** chips (skippable; writes ordinary seed vocabulary — the recorded amendment: the first run may *offer*, never require) → **① capture ×3** (⌃⌥Space, destination readout, send clears + refocuses, "2 captured · 1 to go", gated dashed Continue — an explained-disabled button, not a dead one; the ✦ AI-name pill is cut until the fence opens — captures are honestly unnamed) → **② THE CLICK** (Inbox › Tidy; the wand runs the **deterministic clerk** on **fixed, tested strings** — a services test asserts each scripted capture fires ≥1 proposer, so the aha beat can never be a dead wand; Accept `⏎` writes in one transaction, chips land ≤180ms, toast "Filed — …"; Dismiss teaches "Liv never re-asks the same field"; the **seeded banner** above the list, lake-green left border, links Settings → Vocabulary, dismissal = app pref) → **③ find it back** (⌘F, click the facet chip just filed, "1 match · 2 hidden by filter · clear", digits cycle — D21 visible on day one) → finish strip *"That's Liv — you're in."* No confetti; the reward is the working vault. **Choreography:** coach bubbles are non-activating shell views in the overlay ZStack — lake-green border, anchored, **never intercept input** (the surface below stays fully live), advance on completed action not timers, dots + `TOUR · n of 3` in the bubble header, skip link in every bubble, Esc innermost-first (open editor first, second Esc skips), forward-jump disabled, step index persisted, **resume validates the target surface** else degrades to the after-state. **After-state:** the as-built shell IS the landing — seeded types/values render muted + dashed "seeded" until first use (rides §1.5's wire flags, in VaultTree and pickers), the Inbox rail item wears the unfiled count, the Dashboard's What-next strip is the recommended next move, empty surfaces keep their one-line verb-carrying states. **Replay** (bp2 OQ-4): Help-menu item + workspace-hub popover entry — existing chrome. **Rehearsability is a deliverable:** the `LOTUS_BOX_PATH` env override lands mid-phase so the full script is re-runnable dozens of times against genuinely fresh boxes. **Ordering dependency (owner ruling):** the Keep⇄Composer capture toggle lands before the script freezes.
- **Delta:** vault dialog R1-gated out · trust beat re-grounded · AI beats → deterministic clerk · tour/banner state = app pref (blueprint said per-vault; overruled by the transient-state law) · "asks nothing" amended to "may offer."

### 1.11 Small collisions (each recorded)

| Blueprint want | Law | Reconciliation |
|---|---|---|
| count-confirm dialogs (a8/a15) | dialog-free | pre-commit live count + one grouped txn + "⌘⌥Z undoes" toast |
| marigold OQ badges in the shipped UI | amber = AI only | badges are blueprint apparatus; only the Assist rulebox is amber (it IS about AI) |
| coach bubbles / banner in marigold territory | amber = AI only | lake-green = the app speaking; amber appears once, on the proposal card |
| "Sync & Account · future" nav group (a34) | no dead chrome | cut; one honesty line in Capture & Store |
| retype rewrites every file | schema-on-read | `value-kind` cell only; carriers re-render, never rewritten |
| settings entries as vault objects | transient state ≠ entity | grammar without storage; live properties folded in at query time |
| startup default = Fixed workspace (a33) | as-built behavior | Continue where I left off |
| banner dismissal "per vault" (bp2 ⑬) | transient UI ≠ entity | app pref; delta recorded |

---

## 2 · The slice plan

**The hazard register drives the order** (the risk angle's regime, adopted): every failure mode gets a named kill-shot in an early, small slice; the overlay panels are assembled from parts already proven.

| Hazard | Kill-shot |
|---|---|
| H1 torn multi-carrier rename (forever, in an append-only log) | one-grouped-transaction test + crash-injection replay + CLI run on a **copy** of a real box — all before any UI (19b) |
| H2 the keymap bricks ⌘,/Esc — settings locks itself out | unstealable set enforced at record AND load · load-time pref validation · fixed *Reset all shortcuts* menu item · the brick-attempt script as the review gate (19g) |
| H3 one non-optional wire key drops the snapshot | every new key optional; the P18 two-box decode test re-run on every wire slice (19c, 19h) |
| H4 an existing user gets toured (fresh prefs, full box) | detection is a conjunction; all four quadrants tested (19i) |
| H5 a dead wand in moment 2 | scripted capture strings frozen early + a services test asserting `clerk::sweep` proposes on each (19c) |
| H6 the tour is unrehearsable, discovered once, at the end | `LOTUS_BOX_PATH` harness lands mid-phase; the script is re-run continuously (19c → 19i) |
| H7 the kind seam mis-scoped as "zero Rust" | kind-entity ids budgeted on the wire, T-first — the correction all three judges demanded (19c) |
| H8 seed idempotence (the `assist` entity) | self-guarded seed + open-seed-open test (19h) |
| H9 coach bubbles block the live app | non-activating pass-through views + a manual input-through-the-bubble acceptance script (19i) |
| H10 resume-at-dot into a stale surface | resume validates the target surface, else degrades to the after-state; kill-matrix at every dot (19i) |

**Nothing dangerous ships dark:** the rename verb is proven on the CLI against a box copy before any shelf exists; the keymap spine passes the brick-attempt script before the editor renders; the tour strings are test-pinned to the clerk before a single bubble is drawn.

| # | Name | What ships | Method | Rust delta | Depends | Acceptance |
|---|---|---|---|---|---|---|
| **19a** | **The fourth palette: settings shell + entry search** | `Settings.swift` + `SettingsEntries.swift`: the overlay card + scrim, six-group nav, footbar, search focused on open; the `SettingEntry` table + live `snap.properties` folded in at query time; result rows in the property-row grammar (bold match · current value · group/scope/kind chips); digits 1–9 group facets; ⏎ flash-the-row (~1.6s); 0-results ⏎ → search palette pre-filled; Esc layering; last-panel memory. Replaces the `app:open-settings` alert body (Window.swift:2414); gear + ⌘, + a new app-menu "Settings…" all route here; `overlayActive` wired. Panels are stubs with real headers. | Mockup-first (M1) | **Zero** | — | ⌘, opens focused on search over any surface; typing "digit" surfaces the hints row with its chips; typing "subjects" surfaces the live property row; ⏎ lands on the flashed row; digits cycle group facets; 0-results ⏎ hands the query to the palette; Esc dropdown-first then overlay; reopen restores the last panel; no Save button exists |
| **19b** | **Rust I: the rename engine, headless** | `services::rename_value` + **`lotus_rename_value_at(path, prop, old, new) → count`** (ONE grouped transaction, `with_box` + `Committed::Wrote`) + **`lotus_add_option_at(path, property, name)`** + CLI `rename-value` subcommand + `lotus.h` decls. | **Failing-test-first**: one txn / one `lotus_undo_at` restores 20+ mixed-kind carriers byte-identically; crash-injection mid-txn → replay to pre-rename state; kind discipline (string/select/list cells only — refs and dates untouched); merge-on-collision counted and un-merged by undo; add_option idempotent. Then the CLI against a **copy** of a real box. | 2 additive verbs + services helper + CLI (flagged) | — (∥ 19a) | `cargo test` green including the crash test; CLI rename shows the true count; a single undo restores every carrier; if the transaction layer cannot group cross-entity writes, STOP and escalate — never fake it with N transactions |
| **19c** | **Rust II: the seed layer + kind ids on the wire (+ the rehearsal harness)** | Optional snapshot keys `OptionRow.{count, seeded, hidden}` + `PropertyRow.seeded`; the **kind-id seam** (kind-entity ids exposed as an optional key so hide-on-kind/core-on-kinds writers can pass `#<id>` refs); the `hidden:true` cell convention; decoder additions (all optional); pickers/boards filter hidden shell-side. Also lands now: the **`LOTUS_BOX_PATH` env override** in `main.swift` (H6) and the **frozen tour capture strings** with their services test (H5) — each scripted string must fire ≥1 `clerk::sweep` proposer. | **Failing-test-first**; the two-box decode test both directions (P18's H1 recipe) | Wire-only + test assertions (flagged) | — (∥ 19a/19b) | A pre-P19 box decodes under the new decoder; a P19 snapshot with every new key deleted still decodes; seeded derivation flips when count>0; each tour string yields a proposal; the env override opens a temp box end-to-end |
| **19d** | **The budgeted panels: Appearance · Startup · Capture & Store** | Light/dark/system row (`app.appearance` — one pref, two doors); reading-mode + glyph-strength (if M3 earned them); the Startup radio (`app.startup.v1`: Continue default / Fixed workspace / Today's note via `lotus_open_daily_note_at`); the **KeyRecorder** control proven on its first row — the capture hotkey (`app.capture.hotkey.v1`, live Carbon re-registration); the locked "capture asks nothing" convention row; store-location read-only row (true path + Reveal in Finder) + Export link + the sync honesty line. | Mockup-first (M3's kit) | **Zero** | 19a | Every row applies instantly per its scope tag; a rebound hotkey summons capture and survives relaunch; each startup mode is honored at next launch; reading/glyph knobs change display only (no layout, no behavior); the locked row renders with no control; no dead buttons anywhere |
| **19e** | **The definitions editor** | The property table (spine first, customs last, live "custom · on N" provenance); inline rename/retype/re-icon with pre-commit counts + the ⌘⌥Z undo toast; retype = `value-kind` only (delta demonstrated); Add property (the inspector's shared schema-on-read flow); core star with kind picker (`core-on-kinds` writer via 19c's ids); the row ⋯ menu extracted into `PropertyRowMenu.swift` and adopted by **both** the table and the inspector — `InspectorEditors.swift:769-771` un-grayed; hide-on-kind / hide-when-empty writers; custom delete via trash. | Mockup-first (rides M1); writes ride existing verbs + 19c ids | Zero new (consumes 19c) | 19a, 19c | Rename shows "carried by N" before commit, lands as ONE transaction, ⌘⌥Z reverts wholesale; retype re-renders values without rewriting cells (asserted via CLI `list --all`); one menu component serves both surfaces; spine rows hideable-never-deletable; delete leaves carrier cells intact |
| **19f** | **Vocabulary shelves + status vocabularies + the seed skin** | Three shelves per property (vault with counts / seeded dashed with hover-× hide, in-place rename, Hide-all / hidden collapsed with Restore); vault-chip rename = 19b's verb (count in the editor, toast + one undo) + recolor; the per-kind status table (add/rename/recolor/reorder/retire/re-scope); priority add via `lotus_add_option_at`; **seed-muted rendering everywhere** — muted + dashed "seeded" tag in VaultTree (`Spaces.swift`) and pickers until first use; the gazetteer reconciliation recorded (nothing separate built). | Mockup-first (M2) | Zero new (consumes 19b, 19c) | 19a, 19b, 19c | Renaming a value on 23 carriers updates every row/chip/facet and undoes in one ⌘⌥Z; a hidden seed vanishes from all pickers, survives restart, restores from the shelf; a used seed migrates shelves automatically; task-board columns re-key on a status rename; nothing is ever hard-deleted |
| **19g** | **One shortcut map (R2 complete) + the brick-proof spine** | Spine first: `app.keymap.v1` with load-time validation (malformed → discard + box-log line + defaults); the pure conflict function over defaults ∪ overrides ∪ digit-key cells; the **unstealable set** (⌘, · Esc · ⌘⌥Z · menus); `app:reset-shortcuts` command + fixed NSMenu item. Then the editor: one table, two sections — property keys (recorder → `digit-key` cells; reserved N/M/H/L/F/G/S/W locked with captions) + command chords (~23 `CommandDef`s by category, per-row reset); cross-section conflict warnline + press-again-to-steal + undoable toast; the digit-hint row heading the panel (first writer of `app.inspector.hints.v1`). | Spine first with the **brick-attempt script** as the review gate; Mockup-first (M3) for the table | **Zero** | 19a, 19d (recorder) | The brick-attempt script cannot lock keyboard access: rebinding ⌘,/Esc is refused with the reason inline; a hand-corrupted pref boots on defaults with a log line; Reset-all restores from any scrambled state; a rebound digit works in inspector + palette + suggestion chips simultaneously; chord overrides survive relaunch and never enter the box; steal = one grouped commit, one undo, no modal |
| **19h** | **Assist: the automation switch + BYOK** *(the sanctioned services touch — owner sign-off gate)* | The WORKING `assist` entity seed + automation cell (default ON); the `clerk::sweep` guard — off ⇒ zero proposals, both FFI call sites and the CLI inherit consent; the switch exposed as an optional snapshot key; the panel: switch row (vault tag) · BYOK Keychain row (functional store/clear, dormant-honest caption) · the amber fixed-contract rulebox. | **Failing-test-first** for guard + seed idempotence; Mockup-first for the panel | 1 seed + 1 guard + 1 optional key (flagged) | 19a | Off → the Tidy lens and the CLI both stop proposing; on = today's behavior byte-for-byte; the toggle travels with the box; the key round-trips through the Keychain and appears nowhere in the log or prefs; amber appears on this panel only; open-seed-open = exactly one assist entity |
| **19i** | **Onboarding: first-run, the tour, replay** | First-run conjunction; the Welcome overlay card (trust beat, one-file `will create →` truth, Start `⌘⏎`, Skip); the optional topic-picking step; `Onboarding.swift` — the coach-bubble component (lake-green, anchored, input pass-through, ≤180ms, dots + `TOUR · n of 3`, skip in every bubble); the three moments over as-built surfaces on 19c's frozen strings; the seeded banner (deep-links Settings → Vocabulary; app-pref dismissal); gated Continue; Esc innermost-first; resume-at-dot with surface validation; the finish strip; `app.onboarding.v1`; replay via Help menu + hub popover; the after-state (seed skin from 19f + the Inbox unfiled badge). | Mockup-first (M4) + the stopwatch scripted run + the kill-matrix at every dot | **Zero** | 19c, 19d, 19f, 19h; **external: the Keep⇄Composer capture toggle lands before the script freezes** | Fresh box + fresh prefs → tour; a non-empty box never tours regardless of prefs; kill/relaunch at every dot resumes or degrades — never a stuck state; skip anywhere → the after-state with seeds intact, never auto-shows again; the full scripted run < 60s with zero dialogs and zero dead beats; every bubble leaves the surface beneath it fully live |

**Sequencing logic:** 19a ∥ 19b ∥ 19c open three tracks — the shell shape and both Rust proofs land before any dangerous panel exists. 19d–19h assemble from proven parts (the risk judge's "monster convergence slice" objection is answered by splitting the definitions editor, the shelves, and the shortcut map into three slices with disjoint dependencies). 19i is last but **rehearsed from mid-phase** via 19c's harness — the finale is a scripted run of things that already work.

**Total Rust budget** (all additive, all flagged, all failing-test-first — in 19b/19c/19h only): 2 verbs (`lotus_rename_value_at`, `lotus_add_option_at`) · 5 optional wire keys (`OptionRow.count/.seeded/.hidden`, `PropertyRow.seeded`, kind-entity ids) + the assist-switch key · 1 WORKING seed (`assist`) · 1 guard in `clerk::sweep` · 1 CLI subcommand · test-only string assertions. Everything else — rename/retype/icons/hide/core-star/status shelf/digit-keys/hotkeys/startup — rides existing verbs: **zero new mutation paths beyond the one the data model can't give for free.**

---

## 3 · Open owner calls (each with a firm recommendation)

1. **Gate 5-R2 / bp13 OQ-1 — command bindings in the same table?** **Ratify Option A: one table, two sections** — property keys as vault `digit-key` cells (travel to Windows), command chords as `app.keymap.v1` (platform hardware, never in the box). D21's whole point is one place to learn keys; the scope split falls straight out of the two-scopes law. Needed before 19g.
2. **`lotus_rename_value_at` — the phase's one required verb.** **Approve**, with the 19b kill-shot set (one-txn/one-undo, crash injection, CLI-on-a-copy) as the review gate. If the transaction layer can't group cross-entity writes, the slice stops and escalates — it never ships as N transactions.
3. **The kind-id wire seam.** **Approve** — the honest correction: hide-on-kind is a reference cell to a kind entity whose id the snapshot doesn't carry, so closing the P11.5 gap requires one additive optional key. Without it, both "Hide on ⟨kind⟩" and the core star stay gray in *both* surfaces.
4. **`lotus_add_option_at`.** **Approve** (it's `add_status_option` minus the for-type leg, trivially testable); the alternative is a frozen priority lexicon and a dead ghost-"add" on non-status selects — a no-dead-buttons violation waiting to happen.
5. **The automation switch: vault-scoped cell on a WORKING `assist` entity, default ON.** **Approve** — consent belongs to the box so the CLI honors it too; the one services-zone touch, T-first, sign-off before 19h. No second consent toggle (the standing answer holds).
6. **R1 vs onboarding.** **Ship the split**: the tour is R1-independent (zero dialogs, box path fixed); the vault-location moment + point-at-existing-folder are a recorded insertion point if R1 ratifies (OneDrive caveat attached). Do not block the final phase on R1.
7. **Trust-beat copy.** The claim may not change; the grounding must. **Adopt the append-only-log + Export + CLI-inspectability formulation** (§1.10) → owner voice pass, together with the frozen tour capture strings (bp2 OQ-1's successor).
8. **Topic-picking.** **Include, skippable**, writing ordinary seed vocabulary; record the deliberate amendment — the first run may *offer*, never require.
9. **Tour/banner state scope.** **App pref** (`app.onboarding.v1`) — transient UI, not authored curation. The blueprint said per-vault; overruled, delta recorded.
10. **Store relocation.** **Read-only row + Reveal now; defer the move flow** (move + relock + re-point is risky and deserves its own design). Recorded.
11. **No "future" nav group.** **Cut Sync & Account entirely** — a nav item for a banned feature is dead chrome; the honesty survives as one sentence in Capture & Store. A visible deviation from bp13 a34 — record it.
12. **Reading-mode + glyph-strength.** **Build-if-M3-earns-them** — both display-only and density-legal; neither is required by any law.
13. **Startup default.** **Continue where I left off** (the as-built behavior), not the blueprint's Fixed workspace.
14. **The CUT ledger (§6) — sign off as a block.**

---

## 4 · Where the angles disagreed (and who is right)

- **Where the danger lands.** Fidelity buried `lotus_rename_value_at` inside its fattest UI slice with no isolated proof; **risk is right** — the rename engine ships headless first, with crash injection and a CLI run against a box copy before any shelf renders (19b). Adopted wholesale.
- **The "zero Rust" kind-seam claim.** Both risk (S2) and constitution (19c) promised to close the P11.5 gap with no Rust; the very comment they cite (`InspectorEditors.swift:765-771`) records that the snapshot doesn't carry kind-entity ids. **Fidelity is right** (it budgeted the seam), and all three judges concur — the seam is budgeted explicitly in 19c.
- **Keymap brick protection.** Only risk named the settings-locks-itself-out failure mode. **Adopted whole**: unstealable set, load-time validation, the fixed Reset-all menu item, and the brick-attempt script as 19g's review gate.
- **Cut vs locked row.** Risk and constitution cut the Capture panel wholesale; fidelity kept the story as bp13 a26's own locked "convention — not configurable" grammar. **Fidelity is right** for capture-asks-nothing and the sync honesty line — narrative surface preserved at zero dead controls. **Constitution is right** for the Sync & Account *nav group* — a group for a banned feature is dead chrome; a sentence is honesty.
- **The monster convergence slice.** Risk's S6 merged the property table, the shortcut editor, the shelves, and the status table into one slice depending on five others. **Split here** into 19e/19f/19g with disjoint dependencies.
- **The undo chord.** Constitution wrote ⌘Z in its acceptance criteria; the as-built chord is **⌘⌥Z** (`Window.swift:2395`). Fidelity had it right; every toast in this doc says ⌘⌥Z.
- **Settings search over live data.** Constitution's fold-`snap.properties`-into-the-pool trick makes "settings-as-objects" literally true for the data that *is* objects. **Adopted** (the one judge who noticed called it the best idea of the three).
- **The rehearsal harness and the scripted strings.** Risk's `LOTUS_BOX_PATH` override + the sweep-fires-on-these-strings services test convert the tour's worst failure (a dead wand, discovered once, in front of a new user) into a continuously rehearsed artifact. **Adopted — and moved earlier** than risk had it: the harness lands with 19c, not with the tour.
- **The Daily-notes panel.** Fidelity offered a slim locked-viewer panel; constitution cut it. **Constitution is right** — P12 ruled "nothing to configure," and the one surviving toggle lives in the Startup radio. Re-opening a P12 ruling for a one-lock-row panel isn't worth the nav slot.
- **Startup default.** Fidelity and constitution both overrode the blueprint's Fixed-workspace default with Continue (the as-built behavior). **Agreed and adopted** (owner call #13).

---

## 5 · Mockup surfaces to draw first (in order; each gates its slice)

1. **M1 — the overlay + search + the Properties panel** (gates 19a/19e): scrim, ~920px card, six-group nav, footbar; the search dropdown mid-query "dig" with grammar chips and a live-property hit; a flashed row landing; the full property table with one custom row's provenance and a rename-in-progress showing "carried by 41 objects" + the ⌘⌥Z toast. Proves the fourth-palette shape, the no-Save contract, the row grammar, and the dialog-free count-confirm — in the flush-card skin, tighter than the blueprint (feature-complete, space-conservative).
2. **M2 — vocabulary shelves + status vocabularies** (gates 19f): pill tabs; three shelves (dashed seeds with one mid-rename, the collapsed Hidden shelf); the per-kind status table with its add-ghost; the value-rename toast with a merge count. Proves the D17 layering and the seed-muted chip language VaultTree will reuse. If the three shelf-boxes run long, draw the collapsed single-box variant too — suggest the space saving, don't butcher.
3. **M3 — the controls kit + shortcuts mid-conflict** (gates 19d/19g): every control primitive on one sheet — segmented, toggle, KeyRecorder (recording state, dashed kbd), radio card, locked convention row, scope tags, the read-only store row — beside the one-table-two-sections shortcut map with the red conflict warnline ("press again to steal"), a reserved-letter lock, and a chord row's reset affordance. Settles the kit so 19d/19g are assembly; also the earn-it gate for reading-mode/glyph-strength.
4. **M4 — onboarding twin-panel** (gates 19i): left, the Welcome card (the trust-beat copy — the single highest-stakes wording in P19 — the one-file `will create →` line, topic chips, Start/Skip) above moment ② live: the Tidy lens, a lake-green coach bubble anchored and non-blocking, the amber proposal card on the scripted Steven row, the seeded banner, the gated Continue; right, the after-state — VaultTree with muted dashed "seeded" rows and one lit used value, the Inbox badge, the finish strip "⏱ 0:5x — under budget." Proves bubbles-not-modals, the seed distinction, and that the tour is the product running.

---

## 6 · Cuts, deferrals, and recorded deltas

**Cut (the whole list, named):** theme cards · shape flavor · UI-font picker (prior ruling stands) · subscription proxy + plan picker + cap meter + Account/Devices rows + the Sync & Account nav group (banned feature; dead chrome) · the Daily-notes panel — folder, title format, template picker, per-workspace templates (P12 drops; the D4 template stays a `const`) · naming-convention radios + collision-policy row (no lotus referent — captures are unnamed scraps; collisions can't exist) · the Library & folders panel wholesale — auto-sort pools, per-type overrides, workspace-folder bindings, frontmatter mirror, `.liv/`-in-shared (all R1-gated; **bp13 OQ-2 is moot**, its write-into-folder recommendation carried to BP-14 if R1 ratifies) · the suggestion-aggressiveness knob (the switch is the volume control) · BP-2's vault-location dialog + point-at-existing-folder (R1-gated insertion point) · the ✦ AI-name pill + `people:Steven` derivation (bp2 OQ-2 — fence-gated) · the "Open Welcome screen" startup mode (replaced by replay) · settings-as-box-entities (rejected).

**Deferred, with the named reason:** store relocation flow (move + relock + re-point — its own design; the read-only row ships now) · the aggressiveness knob (returns if/when a brain makes the clerk loud) · file-pool settings (return as BP-14's export-rules map if R1 ratifies as projection) · reading-mode/glyph-strength if M3 doesn't earn them (density-legal but unrequired).

**Relocated, feature intact:** bp13's modal → the fourth overlay · count-confirm dialogs → pre-commit counts + grouped txn + undo toast · the gazetteer panel → the shelves + ordinary entity renames (the gazetteer is derived) · a24's open-today toggle → the Startup radio · a34's honesty → the Capture & Store sync line · the naming story → the locked convention row · BP-2's welcome dialog → a zero-dialog overlay card.

**Recorded deltas (the delta log for this file, maintained through 19i):** modal→overlay · confirm→count+undo (⌘⌥Z) · retype sets `value-kind` only, never rewrites cells (schema-on-read; safer than Liv) · the kind-id seam is a real wire addition, not zero-Rust · settings answer to the grammar without being entities (live properties folded in at query time) · nothing migrates from prefs to the box (the full fifteen-key audit appended) · chords never travel; digit-keys always do · the unstealable set + Reset-all (beyond the blueprint — brick protection) · seeded-hide = a `hidden` cell (append-only gives "reversible forever" by construction) · startup default Fixed→Continue · Sync & Account nav cut (deviation from a34, honesty relocated) · the vault dialog R1-gated out; the trust beat re-grounded on the append-only log + Export + CLI with the claim intact · tour/banner state = app pref, not per-vault · "the first run asks nothing" amended to "may offer, never require" (topic-picking) · AI tour beats run on the deterministic clerk with frozen, test-pinned strings · amber appears exactly twice in P19: the Assist rulebox and the tour's proposal card · `~/Library/Application Support/lotus/lotus.log` is the store-location truth shown in Settings.
---

## 7 · As built — the 19i close-out (and the phase's end)

Shipped: `Onboarding.swift` (TourState · the frozen-string mirror · CoachBubble ·
TourOverlay · SeededBanner), the first-run conjunction on the window's first
snapshot, resume-at-dot with surface validation (a dead assist queue degrades
2→3, never sticks), replay via the Help menu **and** the hub popover row, the
seeded banner atop the Spaces|Vault panel, `LOTUS_BOX_PATH` rehearsal
(landed 19c). All four first-run quadrants behave: fresh box + fresh prefs →
tour; a non-empty box marks `done` on first sight and never tours; `done`
never re-fires; replay is the only re-entry.

**Deltas against §1.10's script, recorded:**

- **The external dependency did not land.** The Keep⇄Composer capture toggle
  (the P12 gap) never shipped, so the script froze without it — moment ①
  teaches ⌃⌥Space alone. If the toggle lands, moment ① gains one sentence;
  nothing else moves.
- **Moment ① pre-lands the scraps.** The design had the user type the three
  captures behind a gated "2 captured · 1 to go" Continue. As built, **Start**
  captures the frozen strings itself (with any picked topic rooms) in ordinary
  writes, and moment ① explains the hotkey over the live surface. The typing
  rehearsal bought little and cost a stall point; the strings must be
  byte-exact anyway (the services test pins them).
- **Moment ②'s gate is dropped, not broken.** The frozen-strings test
  guarantees the wand is never dead, and triaging the queue empty IS the
  moment working — so Continue is always live. An explained-disabled button
  guarding an impossible state is dead chrome.
- **Moment ③ folds "find it back" into the vocabulary beat** (⌘F + the
  one-color law + the seed shelves in one bubble); the finish strip carries
  the full key litany. Three moments stayed three; none went dead.
- **Esc-innermost is welcome-card-only.** Moments 1–3 never intercept input
  (the stronger form of pass-through), so Esc always belongs to the live
  surface beneath; the scrimmed welcome consumes Esc as skip, and every
  bubble carries the Skip link. "Second Esc skips" had no honest owner once
  bubbles stopped owning the keyboard.
- **The seeded banner lives on the Spaces|Vault panel,** not above the Inbox
  list — visible from every surface, one home, and it self-retires: it shows
  only while pristine seeds exist (seeded ∧ unused ∧ unhidden) and never
  during the tour. Dismissal stays the app pref.
- **No timers anywhere** — bubbles advance on clicks only; the ≤180ms budget
  applies to the accept beat it always described, not to choreography.

**Rehearse it:** `LOTUS_BOX_PATH=$(mktemp -d)/tour.log ./shell/macos/build/lotus`
— then `defaults delete com.lotus.app app.onboarding.v1` between runs (or use
a fresh `defaults` domain) to re-arm the pref conjunct.

*With 19i the P19 table is fully shipped and the roadmap (P1–P19) closes.*

---

## 8 · The P19 review (adversarial pass, applied)

Ten finders over the phase diff (`e19ec9d..HEAD`), one risk dimension each;
42 findings survived a three-lens adversarial verify (trace · reachability ·
phase-scope) — 4 high, 17 medium, 21 low. All applied, failing-test-first on
the Rust side. The highs:

1. **The consent gate keyed on a renameable NAME.** `assist_enabled` looked
   up the `automation` property by name and defaulted ON when missing — and
   the definitions table offered Rename on that very row, so renaming it
   silently resurrected the clerk over a recorded OFF (CLI-reproduced).
   Now: `clerk::assist_switch` resolves the backstage `assist` entity's
   sole non-WORKING Bool cell, whatever the property is named; the wire's
   `assist.prop` carries the current name so the toggle keeps a write
   target; the seed guards on the entity (a foreign `automation` property
   no longer starves the switch); plumbing definitions left the definitions
   table and the settings search.
2. **Phantom writes on persist failure.** Both new verbs collapsed every
   error into `Committed::Read`, caching a store one committed transaction
   ahead of a torn disk — later writes then commit onto the gap and vanish
   at the next cold replay. Now Refused → Read, Persist → Failed (the house
   split), and `add_option`'s idempotent hit tags Read, not Wrote.

The rest, grouped: the rename engine refuses ambiguous same-named options
(per-kind `status` names are DESIGNED to collide) and skips WORKING
plumbing in text renames; the persisted pending queue reads empty while
the switch is off ("off means SILENCE" now covers yesterday's queue);
`add_option` enforces select/status + untrashed. One **new additive verb**
— `lotus_kind_flag_at` (with_box + Committed, tested, **flagged**) —
because `set` replaces every cell of a property: hide-on-kind now
accumulates per kind instead of un-hiding the previous one, and it powers
the 19e **core star**, which now exists in both surfaces. The keymap got
its steal-really-unbinds half (an unbound sentinel in `app.keymap.v1`),
load-time rejection of chords shadowing ⌘,/⌘⌥Z, recorder discipline (no
shift-only global chords, named keys for arrows/Return/F-keys, reserved
refusals in both recorders), sanctioned-alias awareness in `conflicts()`
(the stock map boots warnline-free), digit-key press-again-to-steal, and
the brick-proof pair now answers OVER overlays — where the rename toasts
advertise it. The capture hotkey pref self-heals instead of trapping
`UInt32(_:)` in a launch loop. Settings: plumbing filtered, shelf
partition by seeded-ness (user-born unused options have a home), retired
status options gained a Restore door, toasts pin to the panel, Esc closes
from any focus, facets show themselves and die with the query, stale ⏎
can no longer hand a visible-results query to the vault, BYOK respects
the Keychain's answer, definition renames collision-guard through the ONE
shared door, hidden options left the priority menu, and the app menu
gained its standard **Settings…** item. The tour: replay works mid-tour
and closes overlays beneath, the dot no longer advances over a refused
navigation, a mid-tour pref from another box neither resumes nor blocks
(`app.onboarding.v1` now records its box), replay says "your vault →"
instead of "will create →", the assist moment degrades honestly when the
switch is off, and every "⌘Z never expires" now says **⌘⌥Z**.

**Recorded deltas (v0, deliberate):** the settings ⏎ jump lands a
breadcrumb pill, not an exact-row flash — rows across six panels carry no
stable flash identity yet; revisit if the pill proves too quiet. And on a
box carrying a FOREIGN `automation` property, the seeded switch still
works (the gate reads the cell, not the name) but name-keyed `set` writes
remain ambiguous between the two definitions — the entity-based gate makes
this harmless for consent; noted, not built around.
