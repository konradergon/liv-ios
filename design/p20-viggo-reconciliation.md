# P20+ — the Viggo-pack reconciliation (the new face)

> **Provenance.** 2026-07-18, owner: *"We have a new UI blueprints etc. Now I
> want you to continue implementing while following these exactly and override
> current decisions I have made here if something is different."* The pack:
> `…/Pitch/Viggo — pitch pack (2026-07-15)/9 - Blueprints (open index.html)/`.
> bp1–14 there are byte-identical to the spec P1–P19 was built from — the NEW
> normative artifacts are **`app-mockup.html`** (2026-07-15, "every surface
> drawn in one shell, feedback applied") and **`app-sim.html`** (the live
> simulation), plus `ai-suggestion-catalog.html`. Where the two disagree on
> CHROME, the mockup wins (the index calls it the visual walkthrough with
> feedback applied); where a BEHAVIOR exists only in the sim, the sim wins.
> Both defer to bp1–14 where they are silent.

## 1 · The override register (standing decisions this pack kills)

Each row is a prior ruling this doc formally supersedes, per the owner's
"override current decisions" directive. Everything not listed stands.

| # | Was (ruling / where) | Now (mockup/sim) |
|---|---|---|
| O1 | **Lake-green accent #2f7d6b**; never blue/violet (CLAUDE.md, interface.md §0.4, R3 era) | **The brand palette**: accent violet `#6F5BE6` (brand-light, night) / `#8B7BF0` (brand-dark); `--accent-soft` is the selection fill; amber `#F6A823` stays AI-only (`--yellow` + `--on-yellow #3a2a00`). Lake green survives only as brand-light's `--green #2f7a63` SEMANTIC token. |
| O2 | **VALUE_HEX frozen hash** — every value wears one hashed hue everywhere (R3, Hues.swift "FROZEN") | **Retired.** Chips are NEUTRAL (panel2 fill · text2 ink · border · pill); the only value color is a small semantic-token dot (green/red/yellow/purple/accent classes). The per-option `hue` cell quantizes into the semantic set (recolor menus survive re-pointed at it). |
| O3 | **Dark-only flush-card skin** off NSAppearance | **Four named themes as token swaps** — `brand-light` (boot default, "Liv · Light"), `brand-dark`, `night`, `google` — over the full token set (chrome/canvas/surface/panel/panel2 · 4 text tiers · 2 borders · accent-tinted hover · radius/shadow/font per theme). Rail Theme button cycles; Appearance pane direct-selects. |
| O4 | **⌘F canonical search; palette BAN** (constitution; P13) | **⌘K = the ONE Search-or-Ask palette** (centered pill in the top band: "Search or ask your vault…"). Search results + stateless Ask answers share the door. ⌘F stays as an alias into the same palette. The palette ban is formally lifted by the mockup's own chrome. |
| O5 | **Chats surface (aiChat)** | **Ask** — stateless, "each question starts from zero, close it and it's gone"; tool-log rows (`search_vault` / `read_note` · AUTO tags · "no write ever hides in an AUTO row"); streamed answer with numbered cites; CITED list opens objects; amber action cards carry risk tiers (AUTO/REVIEW/BLOCK). |
| O6 | No Comms anywhere | **Comms = BP-15**, a real rail surface: read-only messages resolved to people; message lists ARE saved views; fetch-at-open, external-id idempotence; feed-owned vs yours-never-touched field split; "Liv reads your messages; it never sends them." |
| O7 | ⇧⇥ dashboard entry **deferred** (P18 delta: Hotkey can't express Tab) | **Mission Control on ⇧⇥** — ships. Overlay entry over the current surface + the rail item stays. |
| O8 | Keep⇄Composer capture toggle **absent** (P12 gap; 19i external dependency, recorded) | **Ships**: Capture surface header carries the Keep\|Composer toggle; Keep = masonry card grid with chips/ages/amber AI cards. |
| O9 | Settings = the fourth OVERLAY (P19a) | **Settings = a full rail surface** — left nav (General ·3 SETTINGS· / Appearance / Properties / Vocabulary / Shortcuts / AI, each scope-tagged) + the "exactly three user settings" General page (Store location · What it looks like · Whether the assist layer runs). The P19 search-first grammar survives INSIDE the surface ("0 results never dead-ends: ⏎ hands the query to the palette"). |
| O10 | Right card = five lenses w/ ✦Assist (P17e) | **[Selection \| View] tabs** over lenses **Metadata · Outline · History · Graph · Copilot** ("History not Snapshots"; ✦Assist becomes the Copilot lens, note-scoped, opened by the editor's amber AI button). |
| O11 | One editor pane per tab | **Splits — up to 4** (`+ split` in the tab lane; the inspector marks the "focused pane"). |
| O12 | Spaces\|Vault panel, Spaces first; no Journal section | **Vault\|Spaces (Vault first)** + the left panel's JOURNAL (today-marked) / PROJECTS (dots + sub) / RECENT groups; the sim adds GLOBAL (Home · Today · Inbox·n) and per-workspace tab counts. |
| O13 | Bookmarks/pins live in Spaces › Favourites only | **The favorites/pin row** under the tab lane (`· climbing · SSK invoices · + pin` — the sim calls them *slots*: links, workspaces, today, pinned filters). |
| O14 | R1 (files-on-disk) unresolved-leaning-projection | **Ratified, files-as-interface**: the vault is presented as ONE plain folder of markdown + files ("that folder IS the database" — Settings copy), `library/…` paths on every breadcrumb, `.liv/` sidecars for settings & views ("vault rows write to `.liv/settings` and travel with the store"). The append-only box REMAINS the engine underneath (bp7: "DB as rebuildable overlay") — P20's later slices materialize the projection; the box does not get rewritten. |
| O15 | In-window chrome only | The mockup draws a **File/Edit/View/Go menu row** — on macOS this maps to the NATIVE menu bar (already real), not an in-window row. Recorded as rendered-native, not a delta. |

## 2 · What does NOT change

The Rust core's truth model (append-only log, entities = property→value
cells, commands-only mutation, one grouped txn per gesture, ⌘⌥Z), the FFI
contract and its cache guards, the amended spine (universal status +
role-typed dates), the V3 keyboard-compact inspector grammar (digit jumps,
ALT+M, presets), chip-forward rows and the density budget, the clerk's
determinism + consent switch (P19h/P19-review hardening), proposals-only AI
(the fences stay: no wired answerer until BYOK opens them), the brick-proof
keymap layer, "Liv" branding over `lotus` identifiers, and the Windows-port
boundary. The mockup is a new FACE on the same organs.

## 3 · The slices

Ordering: the token flip first (every later screenshot must already be in
brand paint), then the chassis, then surface-by-surface in rail order,
behaviors before decor within each slice. Rust stays untouched until a slice
genuinely needs a verb (flagged per the boundary rule). Every slice:
mockup-side-by-side check → build → `cargo test` → commit → design-doc log.

| Slice | Scope | Rust |
|---|---|---|
| **20a — the brand tokens** | The full token system: Theme/Tokens rebuilt over chrome/canvas/surface/panel/panel2 + 4 text tiers + 2 borders + accent-tinted hover + per-theme radius/shadow/font; themes brand-light/brand-dark/night/google (light boots default); the rail Theme cycler; VALUE_HEX retired → neutral chips + semantic dots (hue cell quantized); amber → `--yellow`/`--on-yellow`; Hanken Grotesk + Fraunces bundled, google/night font stacks fall through to system where the face isn't shippable. | none |
| **20b — the chassis** | The top band per mockup: centered Search-or-Ask pill (⌘K opens; ⌘F alias), take-the-tour button, workspace button + GLOBAL tab row, the favorites/slots row, layers icon + history arrows right-aligned; the 13-item rail in mockup order (incl. Comms/Ask placeholders that land in 20f/20g) with badge grammar; the left panel reshaped: Vault\|Spaces (Vault first) + JOURNAL/PROJECTS/RECENT (+ GLOBAL); panel metrics --lp 238 / --rp 300 / --ab 44 / heights 40·38·36·46. | none |
| **20c — notes + splits** | The editor per mockup: toolbar (B I S code H list link ⌘K · the amber AI button → Copilot lens · ⋯ source/save-version/reveal/export), H1-is-title, checkbox blocks + strikethrough, inline date chips, ghost autocomplete (Tab), footer (words/blocks · [[ hint · path · ⌘E); **splits up to 4** with focused-pane inspector marker; the [Selection\|View] right-rail tabs + the five lenses (History replaces the P17 history lens naming; Copilot = the renamed assist lens, still proposals-only). | none |
| **20d — capture + inbox** | Capture: Keep\|Composer toggle, the big field, violet Save ⌘⏎, "AI names it on save" line, saves-to picker, filter chips, the masonry card grid + card→inspector selection with amber proposal cards. Inbox: Route\|Tidy counts, source labels (quick capture/download/web clipper), Suggest-for-all, the right-panel routing card (1 New note / 2 Suggest a merge / Later·L / Commit·⌘⏎), the keyboard grammar line. | maybe (routing verbs exist; source labels may need a wire key) |
| **20e — tasks** | The left TASKS nav (FOCUS w/ counts · PROJECTS · SAVED VIEWS · + view); List\|Board\|Schedule\|Cards lenses; status groups with DONE folded ("the view stays at live work"); the amber "N of these I could do" button (clerk-derived, proposals-only); row grammar per mockup; TASK FIELDS task-only inspector section (plan/deadline dates · priority · repeat). | none expected |
| **20f — library + import + contacts + calendar** | Library pools as saved-filter chips w/ counts; LISTS; SAVED VIEWS as entities; the view header (type-to-filter · Filter/Properties/Group · Table\|Gallery · + New · Import/Export); QUICK AND-chips; NAME/ANCHOR/ST/MODIFIED columns; footer census. Contacts: GROUPS-as-filters, person page (header grid, computed IOU strip, MENTIONED IN, @-mention=property callout). Calendar: daily-note button, CALENDARS checklist (+Google row drawn; sync stays one-way-ICS per R7), auto-render copy, span bars, Month\|Week\|Day. | computed strip + pool counts likely shell-derivable; flag if not |
| **20g — comms (BP-15)** | The new surface: message lists as saved views, FILTER chips, Fetch-now row (fetch-at-open · external-id idempotence), message rows + expanded anatomy (feed-owned vs yours split), the no-compose lock line. v0 ingestion = file-drop/import-shaped (mbox/JSON drops), honestly labeled; no daemons, nothing runs on a timer. | **yes — flagged**: a `message` kind + external-id dedup on import (additive; design first) |
| **20h — mission control + ask** | Mission Control on ⇧⇥ as overlay + surface: dashboard tabs (Today · Guidance · Review · +), scope line, the mockup widget set (Habits & points w/ chain+points-line, AI project summary card drawn-with-fences, Agenda, What next, By kind census, Resume vault-wide), widget inspector over view entities, the amber habit-migration banner. Ask: the ⌘K palette's ask half — stateless Q&A SHELL with the tool-log/cites anatomy; until BYOK+fences open, the deterministic clerk answers what it can and the card says so honestly (no fake streaming). | reuse P18 verbs; flag gaps |
| **20i — settings-as-surface + onboarding refresh** | Settings moves overlay→surface (P19 panels re-homed under the new nav; the exactly-three General page; scope tags; `.liv/settings` wording only as far as O14's v0 honesty allows); the tour updated to the new chrome (take-the-tour button = replay entry; ⌘K in the finish strip). | none |
| **20j — the files projection (O14, design-first)** | Its own design doc before code: materialize the vault as `library/…` markdown + `.liv/` sidecars over the box (export pipeline generalized to a continuous projection; import round-trip; collision rules). Gated on that doc — NOT started blind. | **yes — the phase's one big Rust work** |

Sequencing: 20a → 20b are strictly serial (everything paints on them).
20c–20i then follow rail order; 20j last, behind its own design gate. The
per-area delta tables from the reconciliation map (13 areas, file-anchored)
are appended as §4 when the map completes; each slice's close-out logs its
deltas here as P17–P19 did.

## 4 · The area delta map

Thirteen readers over the pack (mockup HTML + sim JS + catalog), each delta
file-anchored against the as-built shell. **268 deltas.** The full map —
per-delta detail text, spec summaries with exact copy/geometry, as-built
anchors — is committed beside this doc as `p20-delta-map.json`; implement
each slice FROM THAT FILE (grep the area), not from memory. One-line index:

### chrome-shell — 21 deltas
- **[add/L]** Global 38px tab row between the title band and the body
- **[override/M]** Centered Search-or-Ask omni pill replaces the quiet magnifier
- **[add/S]** "✦ take the tour" pill in the title bar
- **[change/S]** Native menu bar gains Go and the mockup's View items
- **[change/M]** Workspace hub: move into the tab row, house icon, dblclick→Home workspace, popover content
- **[change/L]** Tabs become per-workspace TYPED department containers
- **[add/M]** New-tab ⌄ department picker + blank-landing card copy
- **[change/M]** Category-locked tab: padlock chip + open-routing semantics
- **[add/M]** Favorites/slots pill row in the chrome
- **[change/M]** Layers: dedicated chrome button; restore MERGES instead of replacing
- **[change/S]** Back/forward chevrons move from rail-top to the tab row; add ⌥←/⌥→
- **[change/M]** Rebuild the rail to the 13-item order with contractual tooltips
- **[change/S]** Amber inbox badge = pending suggestions, gated by the automation switch
- **[add/L]** Theme button at rail bottom cycling four named skins
- **[change/S]** Settings gear moves from the top band to the rail bottom
- **[add/S]** Vault indicator footer: "Vault: <name>"
- **[change/S]** Panel width defaults: left 238, right 300, rail 44
- **[change/S]** Ambient (vault-wide tool) chrome state
- **[add/S]** Shift+Tab toggles Mission Control
- **[add/S]** ↶ Undo button in the tab-row action cluster (sim-only)
- **[remove/S]** Title-band controls the mockup does not show — relocate, don't delete
- *open questions:* (1) Where do the two panel-collapse toggles and the running-timer band chip live in the new chrome? The mockup's title row shows only menu · omni · tour pill · wind · (2) "Vault: Viktor" click behavior: neither mockup nor sim defines the popover (switch vault? reveal in Finder? recent vaults?). Only the button itself is specified · (3) Favorites row placement conflict: mockup puts the pills INSIDE the 38px tab row behind a border-left ("＋ pin"); the sim gives them their own 30px slots bar unde · (4) Go menu contents are undefined in both mockup and sim (the span is inert). Populate with the sim's nav verbs (Home/Inbox/Back/Forward/Daily note)? Owner call. · (5) Ctrl+K on macOS: assumed ⌘K. Do ⌘F (canonical per P13 ruling) and ⌘O stay as aliases of the same palette, or does ⌘K become canonical? · (6) Hub double-click: mockup switches to the Home WORKSPACE (script 5449); as-built opens the Home hub surface (.lotusGoHome). Assumed the mockup wins — confirm, si · (7) Rail Capture item: front the existing ⌃⌥Space capture panel, or does a Capture SURFACE exist for the rail to navigate to (the sim has a capture dept surface)? · (8) Layer restore: does the pane-geometry blob (as-built app.layer.geo.<id>) survive, given the new contract says a Layer lists tab pointers only and restore merges · (9) History cap: sim 40 vs as-built 200 entries — assumed keep 200 (behavior-invisible). · (10) Does the lists surface (Surface.lists, folded into Library on the rail) disappear from Surface entirely, or stay reachable elsewhere?

### theming — 11 deltas
- **[override/L]** Four named themes replace system light/dark — a full token system
- **[override/M]** Violet accent replaces lake green in every accent job
- **[override/L]** Retire VALUE_HEX hashed per-value hues — neutral chips + semantic-token dots
- **[override/M]** Amber AI hue becomes the token --yellow #F6A823 with per-scheme mix ratios
- **[change/S]** Rail Theme button cycles the four themes (replaces the sun/moon appearance toggle)
- **[add/S]** Settings General row 'What it looks like' (2 of 3) → Appearance
- **[change/M]** Appearance pane rebuilt: theme cards + shape flavor + UI font + reading mode + glyph strength
- **[add/L]** Bundle and apply the brand fonts: Hanken Grotesk (UI) + Fraunces (brand serif)
- **[change/S]** Radius, shadows, motion become theme tokens
- **[add/S]** Per-theme surface-scoped token patches (inbox, contacts, onboarding)
- **[change/M]** Text goes to four tiers, borders to two, hover becomes a token
- *open questions:* (1) Default theme: the mockup badges 'Google Workspace' as default on the theme card and 'Google Sans' as default UI font, yet the html root and the sim both boot b · (2) Theme picker behavior: the mockup HTML renders four selectable theme cards (direct select, .on state), but the sim's behavior truth makes every Appearance row c · (3) Shape flavor shows 'Soft · 12px' selected while the active brand-light theme's --radius token is 10px — is Shape flavor an app-scope override of the theme's rad · (4) UI font is labeled 'app-scope, independent of theme' yet --font is a per-theme token (brand themes ship Hanken Grotesk, google ships Google Sans, night ships Se · (5) Status dot colors: the sim hardcodes a word→token map (todo/active/draft/done/paid/sent), but the as-built law (Hues.swift:92-116) renders each status option's  · (6) Font shipping on macOS: 'Google Sans' is not redistributable and 'Segoe UI Variable' does not exist on macOS — should the google and night themes fall through t · (7) VALUE_HEX retirement scope: Hues.swift declares the seed table FROZEN by ruling R3 ('changing any of these is a spec break'). The mockup unambiguously drops has

### notes-editor — 26 deltas
- **[change/S]** Left-panel tabs: Vault first and default
- **[change/M]** Vault pane = Journal/Projects/Recent note-nav, not file pools
- **[change/M]** Spaces pane = Pinned + flat Workspaces list
- **[add/L]** Left-panel footer vault switcher "Vault: <name>"
- **[override/L]** Content tabs move from the top band into per-pane tab rows
- **[add/S]** ＋ "new note" button per pane tab row
- **[add/L]** Splits: up to 4 side-by-side panes
- **[add/M]** Focused-pane model + inspector follow
- **[override/M]** Editor toolbar (overrides the no-toolbar law)
- **[add/M]** Amber AI pill + kebab menu in the toolbar
- **[add/L]** Source mode (Ctrl+E)
- **[change/M]** H1-is-title (kill the separate title field)
- **[add/M]** AI name-suggest wand beside the H1
- **[change/M]** Wikilinks: accent text, click navigates, Ctrl+click new tab
- **[add/L]** Ghost autocomplete (Tab accepts)
- **[add/M]** Active-line raw-marker echo
- **[add/M]** Clickable checkbox blocks (toggle in the text)
- **[change/M]** Real-task embed as a full-width pill with chips
- **[add/L · CORE]** Embedded view block in the editor
- **[add/M]** In-document AI nudge bar (move to Dashboard)
- **[add/M]** Editor footer bar (path · words · hints)
- **[add/M]** "/" slash block-insert menu
- **[change/S · CORE]** Daily template: civil title + Plan/Notes
- **[change/M]** Outline lens: level tags, caret tracking, line flash
- **[add/L · CORE]** Named versions: Save version, toggles, search
- **[add/S]** Notes-surface empty state
- *open questions:* (1) Ctrl+K double-booking: the global palette is Ctrl+K (headline override) AND the toolbar link button says "link · Ctrl+K" — is link-insert the editor-focused mea · (2) Ctrl+E rebind: as-built ⌘E = inline code; new spec Ctrl+` = inline code, Ctrl+E = source mode — confirm the macOS chords via the P19g shortcut map (⌘` collides  · (3) Up-to-4 splits require concurrent editor drafts, colliding with interface.md's "exactly one draft of one entity" — owner ruling needed (sim itself only ever sho · (4) Per-pane content tabs replace the top-band tab lane (a shipped owner decision) — do band-lane features carry over: overflow +N, tab groups, category-lock, middl · (5) Mockup Spaces pane shows only Pinned + flat Workspaces — do the as-built desk rows (Today/Capture/Everything), workspace nesting, Boards, and Archive move elsew · (6) Is the Vault pane exactly Journal/Projects/Recent (a curated nav), or sections atop a full on-disk folder tree elsewhere in the pack? RECENT's scope (vault-wide · (7) "reveal in vault" (kebab) and the footer path click — reveal in the left-panel Vault tree only (per tooltip), or also Finder-reveal once the vault is a real mar · (8) Daily-note civil title "Tuesday 14 July" vs core's ISO name cell: change the core template (read-only zone) or map ISO→civil at display? The mockup's .md filena · (9) The mockup's second pane toolbar omits the </> inline-code button — deliberate narrow-pane elision rule or drawing shorthand? · (10) Ghost autocomplete default OFF (catalog W1) vs the mockup showing it live in the hero shot — confirm the Settings toggle default for the port.

### capture-inbox — 21 deltas
- **[change/M]** Capture becomes a full navigable surface with the doorway header
- **[change/L · CORE]** Keep take box: formatting preview, Save Ctrl+⏎ button, attach/voice icon bar
- **[add/L · CORE]** AI-names-it-on-save line + saves-to path pill under the take box
- **[add/L]** Composer mode — the same doorway, full width
- **[add/M]** Quick filter chips over the wall
- **[change/L · CORE]** Wall becomes Keep-style masonry with the full card budget
- **[add/S]** Amber halo state on AI-flagged wall cards, one-shot pulse
- **[add/M · CORE]** Capture Selection-inspector extras: ✦ name mark, dest path, Tidy nudge, Apply preset
- **[add/M · CORE]** Capture View pane: the wall is an owned .view file
- **[change/S]** Inbox header: folder tabs with per-tab kbd, [ and ] become direct jumps
- **[add/M · CORE]** Route toolbar: count label + 'Suggest for all' batch button
- **[change/M · CORE]** Route rows: source provenance, per-source icon colors, chip grammar, hover actions
- **[add/S]** Route keyboard grammar: ↑↓ select, L later, Ctrl+⏎ commit, digits 1/2 pick the route
- **[change/L · CORE]** Routing card moves to the right panel with New-note/Merge options and library/notes/ destination
- **[add/L · CORE]** Merge suggestion pane (option 2) — the real merge proposer
- **[change/M · CORE]** Tidy regrouped by category; group headers become plain section labels
- **[change/L · CORE]** Tidy card anatomy: context path line, severable rows, id footer, 'Accept · ⏎ a', drop REVIEW chip
- **[change/M]** Tidy footer + toast layer for the whole loop
- **[change/S]** Badge grammar: rail pip = Route count only, grey; header badge = amber total; one soft pulse on new orphan
- **[add/M]** Workspace stamping at capture + vault-wide pool copy
- **[add/M · CORE]** Per-value '✦ assist' provenance mini-badge in the inspector
- *open questions:* (1) Shortcut mapping on macOS: the mockup is Windows-grammar (Ctrl+Alt+Space, Ctrl+⏎, Alt+M, Alt+P, Alt+→). As-built already has ⌃⌥Space; does Ctrl+⏎ become ⌘⏎ and  · (2) Commit destination: the mockup files a committed scrap to library/notes/ (a real markdown move under the vault presentation) while the as-built caption promises · (3) Tidy group actions: the mockup shows no group-level Accept all/Reject all buttons and no A/R hint — do the as-built A/R group keys (Window.swift:3202-3203) and  · (4) REVIEW tier chip: absent from every mockup card — dropped for capture/inbox proposals, or only hidden at this size? (The catalog still defines approval tiers.) · (5) Merge-pane Dismiss · Esc conflicts with the as-built deliberate choice that Esc never dismisses a proposal (dismissals are permanent, Window.swift:3189-3192). D · (6) Sim's Route pane offers 'Commit as task' (L1411) but the 2026-07-15 mockup routing card only offers New note / Suggest a merge — is commit-as-task gone from Rou · (7) Capture filter chips 'idea' and 'link': seeded vocabulary facets (capture kinds) or demo content? What predicate does each chip run? · (8) Attachment + voice capture scope: camera/clip buttons imply file ingestion attached to a scrap and mic implies local transcription — which of these ships in the · (9) AI naming on save: does the name write immediately as an assist-stamped title (editable after), or wait as a Tidy proposal until accepted? The mockup shows the  · (10) The visible deterministic id strings (assist/iou/…#type+people+amount) — derive from the existing u64 fingerprint, or a new human-readable id minted by services

### tasks — 24 deltas
- **[add/L]** Left Tasks nav panel (FOCUS section)
- **[add/M]** Left nav PROJECTS section with dots and sub-items
- **[add/M]** Left nav SAVED VIEWS section + '＋ view' button
- **[change/S]** Toolbar: title = pool/view name; labeled lens seg; project chip
- **[change/S]** Amber assist button copy + gating
- **[change/S]** List section headers: status ring dot + count; terminal groups fold
- **[change/M · CORE]** Row grammar: plan + deadline chips, green done fill, relative age
- **[change/S]** Row hover: ↗ ✦ ⋯ quick actions
- **[change/S]** AI halo = amber ring on the row/tile, not a count pill
- **[add/S]** Typed task renders its type icon in accent
- **[change/M]** Board: 198px columns, tile checkbox + chips, ⤢, drop hint, vertical Done strip
- **[remove/S]** Board: '+ New status' trailing column (relocate to the definitions editor)
- **[override/L]** Schedule lens: two-week grid replaces the bucket list
- **[add/M]** Unscheduled tray + drag-onto-day sets the plan date
- **[change/M]** Cards lens: multi-chip row + overflow + age + no-description state
- **[add/M]** Right rail: [Selection | View] segment
- **[add/L]** View tab: view-as-object pane (lens/group/sort, filters, fields, presets)
- **[change/M · CORE]** Selection header: ✦ suggest (Alt+M) action + destination path row
- **[add/M · CORE]** Task fields: plan date row (W) + role names plan/deadline/calendar
- **[add/S · CORE]** Assist-provenance chip on property rows
- **[change/S]** Copilot lens rename + lens order; footbar copy
- **[change/S]** Empty states + toggle toasts (sim copy)
- **[remove/S]** All/Open/Done filter segments (superseded by Focus nav + folded Done)
- **[remove/S]** Quick-add row on list/schedule/cards
- *open questions:* (1) Schedule lens: the mockup (2026-07-15) draws a two-week calendar grid with an Unscheduled tray, but the sim's lensSched still renders the Overdue/Today/This wee · (2) Anchor precedence on task rows: the mockup list shows @Steven for a task that also carries #climbing (cards lens shows both), implying people-before-subjects fo · (3) Board: the mockup shows neither a '+ New status' column nor a 'no status' column. Removing '+ New status' (definitions editor owns the vocabulary) seems clearly · (4) Quick-add: is the inline 'Add a task…' row really gone (capture + board ＋ only), or space-conservatively kept per the feature-complete/space-conservative memory · (5) Relative ages (5h/1d/3w) are keyed to modified; the snapshot has no modified field (EntityRow carries created only). OK to add an additive optional wire field,  · (6) Status vocabulary demo names (Open/Discuss/Follow up/Back burner) are the demo user's custom vocabulary — confirmed NOT a reseed of todo/doing/done; the Done-fo · (7) Untriaged definition: mockup tooltip says no plan AND no deadline AND no project; sim fits() checks only !due && !project (plan not consulted). Which is contrac · (8) Selection header: the mockup shows only ✦/pin/trash — should as-built add-to-list and archive actions move into the ⋯ row menu, or stay as-is? · (9) Saved views Money owed/Tournament prep/This week and the 'All tasks — by status' view: seeded demo content for the pitch, or expected starter views in a fresh v · (10) The '.liv/views/tasks-by-status.liv' path in the view header depends on the vault-as-markdown-folder presentation (another area). Until that lands, what renders

### library-import — 30 deltas
- **[add/L · CORE]** Library left rail: pools + Lists + Saved views + Vault tree
- **[change/M]** Center pool is mixed-object, not file-cell-only
- **[change/M]** Table lens: NAME / ANCHOR / ST / MODIFIED column grid
- **[change/M]** Enable the Gallery lens (Ctrl+2), remembered per view
- **[add/M]** View header: type-to-filter, Filter, Properties, expanded Group
- **[add/M]** Quick chips row — favorites that combine with AND
- **[add/S]** +New menu and new-by-kind tab chevron
- **[add/L]** Typed tabs over the Library center
- **[change/L · CORE]** Saved views become typed view objects with config + real files
- **[add/M]** View inspector pane (View half of [Selection | View])
- **[add/M · CORE]** Selection inspector: vault path row + drag-out + lookup dates
- **[add/M · CORE]** Drop-anywhere import strip + surface footer
- **[remove/M]** Lists as a separate nav surface — folded into the Library rail
- **[add/L · CORE]** Vault-as-folder substrate: library/, .liv/, .trash/ (R1)
- **[override/M]** Import/Export: one surface with a seg switch, not two sheets
- **[add/S]** Import context strip: the funnel runs inside a project
- **[change/S]** Import meter: collected / staged / deferred / discarded / to review
- **[change/M]** Funnel becomes three boxes: Pool | Review | Staged
- **[add/L]** Review property editor with digit jumps and ✦ suggestions
- **[add/M]** Pool card grammar + bookmark-folder subject candidates
- **[add/M · CORE]** Pre-commit dedupe surfaced: 'N skipped — already in the vault'
- **[change/M]** Deferred persists + palette 'Resume import — 3 deferred' deep-link
- **[override/L · CORE]** Import writes real files into library/<pool>/ (supersedes LB1 by-reference)
- **[add/L]** Download watcher: quiet stacking prompts + Settings › Import rules
- **[add/S · CORE]** 'How this stays safe' rails card
- **[change/M]** Export selection = the one filter engine with quick chips
- **[change/S]** Export structure: 'group by X then Y [flat?]' + rollup tree preview
- **[override/L · CORE]** Export Mode: Copy | Move out with typed arming (supersedes LB5 refusal)
- **[change/S]** Library ShortcutBar/footer replaced by the mockup's bars
- **[add/S · CORE]** Canvas object kind appears in Library
- *open questions:* (1) Inbox spelling collision: the Library drop strip/footer say new files go to 'MyVault/Inbox/' while capture, the watcher, and the staged footer say 'library/inbo · (2) View-file extension is inconsistent across the mockup: .view (files-all-pools.view, capture-wall.view, contacts-all.view), .base (thesis-analysis.base — the Bas · (3) Pool count scope: mockup copy says 'a saved filter over one vault' but the sim scopes counts to the active workspace lens with an 'everywhere' toggle ('counts a · (4) Saved-view opening: the mockup shows 'Thesis sources' as a second tab inside the Library center, but the sim maps files.list/files.view typed tabs to the separa · (5) Where does un-committed import state (pool + deferred, per project) persist so 'Resume import — 3 deferred' works across sessions — shell-local, .liv/ scratch,  · (6) Move-out says 'their index rows are removed' — reconcile with the append-only core (tombstone/trash semantics vs literal removal); needs an owner ruling before  · (7) Import 'collisions prompt, never overwrite' — the collision dialog itself is never shown in the mockup; its shape (rename/skip/replace?) is unspecified. · (8) The import surface exists only in the mockup HTML; the sim's Library buttons merely toast the contract. Sim-level behaviors (keyboard flow through Review, stage

### contacts — 18 deltas
- **[override/L]** Contacts becomes a 3-pane surface (groups+list | person page | inspector)
- **[add/M]** Groups card — saved filters over the one people pool
- **[override/M]** List rows: initials avatar w/ per-person hue, quick actions, modified ↓ sort
- **[add/S]** F focuses the filter; Esc clears; zero-match quiet line
- **[change/S]** New-contact flow: accent + button, rename focus, library/contacts/ path, empty stays empty
- **[add/L]** Person page: breadcrumb + read-only hero card with mirror contract
- **[add/M]** IOU entity kind (amount + people), opened via Contacts
- **[add/M]** Computed IOU net strip on the hero — never stored, never editable
- **[add/M]** MENTIONED IN · N — source-tagged backlink rows on the page
- **[change/M]** @-mention of a person also writes people:[X] — chip and property are one fact
- **[add/M]** Person body = a normal note, editable on the page
- **[override/M]** Opening a person routes to the Contacts page, not a note tab
- **[change/M]** Contact-tuned inspector core: add birthday + last-seen rows, drop role from core
- **[add/M]** Inspector destination row + Apply preset (Alt+P) + AI-suggest header action (Alt+M)
- **[add/M]** [View] pane for the contacts view (Contacts — all)
- **[change/S]** Calendar renders person birthdays (calendar role + yearly); lookups stay off
- **[change/S]** Chip grammar on contact rows: click filters, Alt+click excludes
- **[remove/S]** Drop the 'New contact' header pill, count subtitle banner, and alphabetical sort
- *open questions:* (1) Kind naming: the mockup says 'kind: contact' (View filter chip, Settings matrix column 'c contact', inspector subline 'contact · friend · area personal') while  · (2) Groups card exists only in the static mockup; the interactive sim's left rail is a plain 'People' pool with a vault-wide footnote. Assumed mockup wins (build gr · (3) The mockup demo groups filter on org/area/subjects and the demo chips filter on project/org/subjects — i.e., a group is an arbitrary saved query, not a fixed ax · (4) IOU 'settle' semantics: the sim only ever shows open IOUs and says 'settle or edit the entry'. Is settling status='paid' (STATUS_HUE has paid→green), trashing t · (5) Sim seed person fields (Steven, steven@gmail.com, +46 70 312 44 21, birthday 3 mar, last seen 12 jul) differ from the mockup steady-state (Steven Åkesson, steve · (6) 'last seen' shows a location suffix in the hero ('28 jun · Klättercentret') but the panel row holds only the date 2026-06-28 — is location a second cell on the  · (7) The breadcrumb/destination paths (library/contacts/<slug>.md, .liv/views/contacts-all.view) presume the vault-as-real-markdown-folder override. Until that lands · (8) Does the person page fully replace opening a person in an editor tab, or can a person still be opened as a plain note tab (e.g. Ctrl+click 'background tab' — ba

### calendar — 13 deltas
- **[add/M]** Left calendar card: daily-note button + CALENDARS checklist + New calendar
- **[add/L · CORE]** Google calendar sync (two-way) + sync affordances
- **[change/M]** Event chip grammar: per-calendar hues, glyph prefixes, state dims
- **[change/M]** Today cell = the daily note (framed cell, live preview)
- **[change/M]** Quick create → popover with kind + calendar + destination footer
- **[add/M]** Off-the-calendar strip with open-as-filter
- **[override/L · CORE]** Right rail: [Selection | View] replaces CalendarDayPanel
- **[change/M]** Toolbar: h2 month title, T/PgUp/PgDn/C keys, ＋ New event, scope label, quiet state
- **[add/L]** Drag editing: chip→day move, span grips, span move
- **[change/S · CORE]** Event status vocabulary + cancelled rendering
- **[change/M]** Week/Day lens details: 07–22 framing, all-day strip contents
- **[change/S]** Daily-note shortcut + surface copy alignment
- **[remove/S]** Retire the in-cell rename-prompt naming flow
- *open questions:* (1) OQ-A (bp9 31): Google sync conflict UX is unspecced — proposal is a per-event card in the Inbox Tidy queue (keep mine / take Google's / open both); needs an own · (2) OQ-B (bp9 32): recurrence exceptions (skip/move ONE occurrence) — override-on-parent recommended but unruled; affects Google exception mapping. As-built recurre · (3) OQ-C (bp9 33): does a fresh daily note embed a one-line agenda projection block by default? The today-cell preview works either way. · (4) Chip hue source: bp9 e5 says chip hue = the calendar property's hue; the sim colors by area→workspace hue (no calendar property in its seed). Which wins when bo · (5) Show-tasks wording drift: mockup View pane says '✓ due + deadline' and the left-card note says 'due or deadline', but the core's date-role ring has only one dea · (6) Ctrl+D vs ⌘⌥D for the daily note on macOS — keymap area decision; calendar copy must follow the final map. · (7) Default selection = 'next upcoming event in scope' keeps the rail on [Selection] — confirm Esc-on-grid returns to [View] even when that default selection exists

### comms — 14 deltas
- **[add/M]** Comms surface + rail button + routing
- **[add/M · CORE]** `message` kind + its properties in the vocabulary
- **[add/M]** Message lists card — the four starter saved views with live counts
- **[add/S]** Filter card — from ▾ / source ▾ / sent ▾ chips
- **[add/S]** Fetch-now toolbar row (fetch-at-open, never a timer)
- **[add/M]** Message rows: unread dot, resolving sender chip, snippet, source chip, time
- **[add/M]** Expanded message card — feed-owned vs yours split + the lock line
- **[add/S]** Computed related — never stored feed-side
- **[add/M]** Inspector integration — Selection rows + comms View-lens rows
- **[add/L · CORE]** v0 ingestion: message import (file-drop, mbox/JSON) with external-id skip-dedupe
- **[add/L · CORE]** Real refresh semantics: feed-owned upsert by external-id (the ICS merge policy)
- **[add/S]** Cross-surface hooks: dashboard nudge → comms, Ask cites messages, contact pages list messages
- **[add/S]** Comms as a New-tab department
- **[override/S]** OVERRIDE of old spec: a Comms surface exists at all (reads-only, no compose)
- *open questions:* (1) Scoping contradiction in the sim: comms is in VAULT_WIDE (app-sim.js:234, list never workspace-filtered) but the surface comment (:2218) says "workspace-scoped  · (2) Are the four starter message lists seeded as real saved-view entities (the caption calls them ordinary saved views; pinnable/editable) or surface-chrome default · (3) `sent` in the sim is a raw display string ('09:02', 'igår 22:10', 'tis'). Confirm the real property is a datetime with shell-side relative rendering (time today · (4) v0 Fetch-now behavior with file-drop-only ingestion: does the button re-scan a designated drop location, open the import flow, or honestly no-op with the "0 new · (5) The mockup's Filter card dropdowns (from ▾ / source ▾ / sent ▾) have no specified menu contents or interaction with the active saved view (narrowing vs editing  · (6) Source chips say "Slack"/"Mail" — plain text chips in the sim; does the brand-logo exception for connector tiles (feedback doc open call 7) apply to comms sourc · (7) No keyboard shortcut is assigned to the Comms surface anywhere (all other rail surfaces have historical ⌘digits in the as-built app) — intentional omission or u · (8) Should reading a message (clearing unread) write to the box as one undoable transaction per the sim (ctx.mutate), given unread is a hidden feed-ish property — a

### dashboard — 23 deltas
- **[override/L]** Mission Control overlay host on Shift+Tab (two hosts, one board engine)
- **[add/M]** Views pill row in the overlay (Today / Guidance / Review, max 10)
- **[change/M]** Header bar: scope button, contract-copy date line, Template: Starter
- **[change/M]** Add-widget gallery: popover → inline searchable pane with keyboard grammar
- **[change/S]** Gallery catalog = the mockup seven, with its exact desc + reads lines
- **[add/L · CORE]** Amber Assist banner — the habit-block migration offer
- **[change/M]** Board grid honors 6-column spans
- **[change/M]** Widget card chrome: icon + mono source link + hover action cluster
- **[change/M]** Habits & points: block order, amber/accent styling, cadence copy, habits-shown cap
- **[add/M]** 'export to sheet' on the habits points section
- **[add/L · CORE]** Project summary — the streamed AI widget
- **[change/M]** Agenda · today: chip grammar, colored dots, calendar-bound countdown
- **[change/M]** What next: identical-row grammar, hover actions, new footer copy
- **[add/L · CORE]** What next: AI candidate rows with '＋ task'
- **[change/L · CORE]** Metric chart: creation-cadence bars → numeric-property line ('Dagsslut score')
- **[override/S]** Pinned re-aims from the pins shelf back to tier = 1
- **[change/S]** Saved view widget: keep, restate reads-line against the vault folder
- **[add/S]** Board footer bar
- **[add/L]** Selection rail: the widget as an object with the numbered config grammar
- **[add/L · CORE]** View pane: the board is a per-scope view entity with template + description
- **[add/S]** Template: Starter — seed a widget set once
- **[remove/S]** Tasks summary widget leaves the gallery
- **[remove/S]** Time tracking widget leaves the gallery
- *open questions:* (1) Catalog conflict: the mockup dashboard surface specifies 7 widgets (Habits & points, Metric chart, Agenda, Project summary, What next, Pinned·tier1, Saved view) · (2) Right-rail View pane conflict: mockup rows are L/S/W/T(template)/0(descr) with no views row; sim rows are L/S/W/V(views '3 · Today active · max 10') with no tem · (3) Fate of the two as-built widgets absent from both new catalogs: Tasks summary and Time tracking. Delete outright, or keep as legacy renderers off-gallery? If Ti · (4) Pinned: confirm the override of the recorded P17g delta — the new spec's 'reads → filter: tier = 1' reverses the deliberate re-aim at the pins shelf (Dashboard. · (5) Habits card: the mockup drops the as-built '＋ habit' creation button and 'habits ›' footer from the widget (creation presumably moves to the habits.base source  · (6) Metric chart core support: charting 'any numeric property over time' needs a per-day numeric-cell series; confirm whether the current snapshot/query surface exp · (7) Mission Control overlay + the 07-14 'never an overlay' ruling: the sim explicitly restores the overlay as a SECOND host ('one board engine, two hosts — exactly  · (8) 'export to sheet' scope: one-off .xlsx of the habits points series only, or the full check-in table? (Contract line: 'a real .xlsx on demand — sheets are never 

### ask-ai — 19 deltas
- **[add/L]** The Ask overlay (the answerer) — the headline unfence
- **[add/M]** AUTO tool-call log rows — explicit OVERRIDE of P16's refusal
- **[add/M]** Streamed answer with numbered cite chips + CITED list
- **[add/L · CORE]** The Ask action card — one REVIEW proposal staged into the one queue
- **[change/S]** Ctrl(⌘)+K = the combined Search-or-Ask palette entry
- **[add/S]** Ask entry points: left-rail ambient button with the amber badge
- **[override/L]** Right-rail lens set: ✦ Assist lens → Copilot lens
- **[add/S]** Editor toolbar ✦ AI pill
- **[change/L · CORE]** Tidy card grammar: kind groups, target path, visible id, per-row severability
- **[add/M · CORE]** Risk-tier field + AUTO and BLOCK renderings
- **[add/M · CORE]** ✦ made-by-assist provenance surfaced
- **[change/M]** Halo mounting breadth beyond Tasks rows
- **[add/S]** Mission Control 'Suggestions' widget
- **[add/M]** Alt+M — ask for suggestions on the focused object + Route 'Suggest for all' + merge-suggestion card
- **[change/M · CORE]** Settings › AI page: rename, kill-list copy, Plan section, aggressiveness
- **[add/L · CORE]** Catalog adoption — deterministic rows the app must DO today
- **[add/L · CORE]** Catalog adoption — model-backed rows (BYOK/plan-gated, the fence's second door)
- **[override/M · CORE]** Dedupe survivor rule conflict — as-built keeps the OLDER, mockup keeps the NEWEST
- **[change/S]** Onboarding + tour touchpoints for the new AI grammar
- *open questions:* (1) Search→Ask handoff mechanics: the mockup sells ONE Ctrl+K 'Search or ask' doorway, but neither artifact shows the transition — the sim binds Ctrl+K to search an · (2) Undo law conflict: the Ask card promises 'on accept: by:assist provenance + 30 s undo' (and catalog O8/A7 repeat '30 s undo'), but lotus law is one never-expiri · (3) Dedupe survivor: mockup 'keep the newest, append the older body into it · history kept' vs core 'survivor = older id' + catalog O2 'keep the OLDEST' — three-way · (4) Catalog status column ('built' = old Liv src/lib code) — is it also the build-priority ordering for lotus (built rows first), and are 'planned' rows (O8/O9/T11/ · (5) Suggestion aggressiveness 'Eager — also on save when core fields sit empty' and catalog O6 suggestion toasts (5-min poll) both collide with lotus's no-timer/no- · (6) Plan section: the mockup's 'Liv subscription — server-side proxy, 62% of cap' vs the sim's BYOK-only 'no middle server' copy — which ships in the desktop app, a · (7) Ask/assist id grammar: cards display ids like assist/iou/steven-owes-me-300#type+people+amount and ask/chase-invoice-114#due+people; as-built identity is a u64  · (8) Per-row severability inside one card ('✕ drops a row; accept applies what remains'): implement as accept-subset-of-commands (new services/FFI seam) or by splitt · (9) Sim labels the Ask action card 'PROPOSAL' and stages-only ('routed to the one queue — nothing written here'); the mockup labels it 'REVIEW' with Accept writing 

### settings-onboarding — 23 deltas
- **[change/L]** Settings: overlay → full surface
- **[change/M]** Nav regrouped to the six mockup entries with icons + aft tags
- **[change/M]** Search moves into the left rail with the grammar hint
- **[add/M · CORE]** General page — the exactly-three-real-settings frame
- **[remove/S]** Capture & Store and Startup panels leave Settings
- **[override/L]** Appearance rebuilt: 4 named themes as token-swap cards
- **[add/M]** Appearance: Shape flavor, UI font, Reading mode, Inline glyph strength
- **[change/M]** Properties page: flat list → per-kind core/more/hidden matrix
- **[change/M]** Vocabulary page: pill tabs + three shelves + per-kind status block
- **[change/M]** Shortcuts page: the digit grid + the exact Commands table
- **[change/S]** AI page (renamed from Assist): Automation copy + the fixed-contract rulebox
- **[add/L · CORE]** AI page: the Plan section (subscription vs BYOK) with usage meter
- **[add/M · CORE]** AI page: Suggestion aggressiveness (Quiet / Standard / Eager)
- **[change/S]** Scope-tag system: page-level tags + nav aft tags + .liv/settings framing
- **[change/S]** Footbar re-worded to the surface contract
- **[add/S]** Title-bar '✦ take the tour' pill (replay entry)
- **[override/L]** Tour rebuilt: 3 pass-through moments → one 5-step overlay panel
- **[change/M · CORE]** Tour step 1 Folder: folder vault, Change…, existing-folder mode
- **[change/M]** Tour step 2 Topics: picks seed VOCABULARY, chips censused from the vault
- **[change/M · CORE]** Tour step 3 Capture: three new contractual prompts, simulated send, nothing written
- **[change/M]** Tour step 4 The aha: inline Inbox + suggestion diff card with degrade states
- **[add/M]** Tour step 5 Consent: the two real gates from Settings › AI
- **[remove/S]** As-built finish strip + Help-first replay framing superseded
- *open questions:* (1) Startup ('On launch') and the capture-hotkey recorder have no page in the mockup's six-group nav — relocate under General/Shortcuts, or drop the P19d knobs enti · (2) The files/import area says 'per-extension rules (ask / auto-import / ignore) live in Settings › Import' (mockup line ~1373), and the AI catalog references 'Sett · (3) Sim vs mockup conflict on Settings itself: the sim's SECS (Appearance/Vocabulary/Shortcuts/Properties/'AI & consent'/Store, no search, no General) predates the  · (4) Digit-map conflict: the sim's DIG (1 amount · 4 people · 5 project · 6 area) disagrees with the mockup Shortcuts grid (1 form · 4 project · 5 area · 6 people);  · (5) Consent-step key copy in the sim ('calls go from this machine to your provider — never through a Liv server') contradicts the mockup AI page's Liv-subscription  · (6) Does the true FIRST-RUN still write on Start (bp2: create library/ skeleton + seed vocabulary; sim step 2: 'picks write vocabulary only') while REPLAY writes no · (7) Is the 'custom · on 3 objects — born from “Steven owes me 300 kr”' provenance sublabel a real origin-tracking requirement or illustrative copy? · (8) The subscription usage meter ('this month · 62% of cap') needs a proxy/billing backend that doesn't exist — stub the plan section or defer it? · (9) Default pane on open: mockup shows General active — does it replace the as-built last-panel memory (AppStorage app.settings.lastPanel.v1)? · (10) Settings search presentation: as-built shows a results dropdown with digit facets 1–6; the mockup implies in-place filtering ('type filters everything') with no · (11) Does the as-built 'Digit hints in the inspector' toggle (absent from the mockup Shortcuts page) survive? · (12) Keep Help → 'Replay the Tour' as a duplicate entry alongside the title-bar ✦ pill?

### sim-behaviors — 25 deltas
- **[override/S]** Primary undo chord becomes ⌘Z outside text fields
- **[add/S]** Undo toast contract on every mutation
- **[add/L]** Shift+Tab Mission Control overlay (second host of the board)
- **[add/S]** Ctrl+K / ⌘K binding for the palette
- **[change/L]** Palette feature set: scope tiles, 3 display modes, kind groups, footer verbs
- **[add/M]** Everywhere scope toggle
- **[add/M]** Project-pin filter (distinct from Favourites pin)
- **[change/S]** Workspace switch lands on the desk with a scope toast
- **[change/S]** Inbox [ ] = absolute lens select; keep the triage keys
- **[change/M]** Route commit flow: two commit buttons + Later with auto-advance
- **[add/L · CORE]** IOU kind + computed person netting + the IOU accept path
- **[change/M · CORE]** Capture stamps the workspace area, visibly, one undo
- **[add/L]** Department-typed tabs (capture/dashboard/tasks/library/comms as tabs)
- **[add/L]** Editor split panes (2 shipped, '4' in copy) with one following inspector
- **[override/M]** Layer restore merges instead of replacing
- **[add/L · CORE]** Stateless Ask overlay with AUTO read log, cited stream, one proposal
- **[add/M]** Automation-off global dimming
- **[change/S]** Blank-tab landing gains the third row
- **[add/M]** Left-panel Props/Graph exits into the one search grammar
- **[add/M]** Checkbox pills rewrite the note body
- **[add/S · CORE]** Comms: opening an unread clears the flag as one undoable write
- **[add/S]** Theme cycle affordance on the rail
- **[change/S]** Mission Control quick-actions widget kbd + capture routing
- **[change/S]** openEntity home-surface routing incl. iou→person
- **[remove/S]** Retire ⌘⇧M-as-surface-nav in favor of the toggle pair
- *open questions:* (1) Search-or-Ask merge: the headline override says Ctrl+K is ONE combined palette, but the sim ships two overlays (ov-search on Ctrl+K/O, ov-ask on the rail/tab-pi · (2) Suggestion dismiss undoability: the sim routes sugg.dismiss through the undo snapshot (Ctrl+Z revives a dismissed proposal) while its own copy and the as-built  · (3) History chord: sim rail tooltips advertise Alt+←/→ for back/forward, but the as-built deliberately gave Alt+←/→ to inspector panel/doc focus (bp1 badge 32) and  · (4) Capture submit key: the capture surface submits on plain Enter (sim keydown 714) while onboarding step 3 teaches Ctrl+⏎ ('the box refocuses') — one key or both? · (5) Undo depth: the sim caps its snapshot stack at 25; the core's log undo has no such cap — is 25 a contract or a sim artifact? · (6) Layer restore: adopt the sim's merge-with-dedup ('nothing was written') and DROP the as-built stash-undo toast, or keep both (merge + undo of the merge)? · (7) Splits: the copy promises 'up to 4 panes' everywhere but the sim implements exactly 2 — is 2 acceptable for the port milestone with the 4-pane copy kept? · (8) Workspace-scoped area stamping at capture (one transaction incl. area) needs an additive FFI variant of lotus_capture_at or a sanctioned two-write pattern — own


---

## 5 · Slice log

### 20b — the chassis (as built)

**Shipped.** The band split: the 40px title row now carries sidebar-toggle ·
the centered **Search-or-Ask omni pill** (max 520, "Search or ask your
vault…", ⌘K keycap — O4's reversal of the quiet-magnifier ruling) · the
timer chip · the **✦ take-the-tour pill** (dashed, replays the tour) ·
inspector toggle. Below it the new **38px global tab row**: the workspace
hub (house glyph; single click = switcher, **double-click = the Home
WORKSPACE** per mockup:5449, superseding bp4 ⑥'s hub-surface reading;
switch toast) · the tab lane · the **⌄ department picker** ("departments
only — object kinds live inside"; Ask = "stateless, no tab needed"; Import
routes into Library) · the **slots cluster** (Today red pill → the daily
note; the pins as ◦-pills — the ONE ⌘⇧B pin source; "＋ pin" ghost menu) ·
hairline · the **Layers door** (save / per-layer Restore·Rename·Delete;
**restore MERGES** non-duplicate tabs per the sim, toast, never replaces —
the popover's LAYOUTS section removed, one home) · **↶ Undo** · the history
chevrons (dim at ring ends), moved off the rail. The **rail rebuilt** to
the mockup's order with contractual tooltips (Notes · Capture · Inbox ·
Tasks · Library · Contacts · Calendar · Dashboard/"Mission Control (⇧⇥)" ·
─ · Ask · Vault graph · ⋯ · Theme · Settings), 36pt buttons, accent-soft
active fill. Chords: **⇧⇥ Mission Control** (the Hotkey matcher learned
Tab — the P18 delta closes; ⌘⇧M alias stays), **⌘K** advertised (⌘F/⌘O
quiet aliases). Menus: the **Go menu** (Home · Inbox · Daily Note · Back
⌥← · Forward ⌥→ — the alt-arrows live as MENU key equivalents so the
inspector's scoped focus chords consume them first when it owns the
keyboard); View gains Mission Control + ✦ Take the Tour. The left panel:
**Vault | Spaces flipped (Vault first, Vault boots)** + the **"Vault: 
<name>" footer** (path · Reveal · Move-lives-in-Settings popover). Panel
defaults: right → ~300px-equivalent (23.5%), left ~238 (18.5%). Hub
popover rows carry "N tabs" per workspace. One shared **Toast** landed
(theme cycles, workspace switches, layer merges narrate through it).

**Recorded deltas (v0 staging, all deliberate):**
- Global tabs v0 = the existing working-set lane (Overview ≙ the desk tab);
  TRUE typed department containers land with 20c's content-tab split, which
  moves note tabs down into the editor area (mockup --ctabh 36).
- The Comms rail item joins with 20g; the Ask item fronts the old chat
  surface until 20h's overlay; the Capture door fronts the ⌃⌥Space panel
  until 20d's surface (no dead buttons at any point).
- ⇧⇥ lands on the dashboard SURFACE until 20h's overlay entry.
- The timer chip keeps its title-row home and the sidebar toggles stay
  (the mockup's title row is silent about both — feature-complete rule;
  flagged, not dropped).
- The JOURNAL/PROJECTS/RECENT panel content belongs to the notes surface
  and ships with 20c (this slice delivered the flip + footer).
- The category-locked tab's OPEN-ROUTING affinity (map [7]) rides with
  20c's container model; the padlock close-guard already exists.
- Slots: mockup layout (in-row) + sim grammar; workspace slots ride the
  Spaces ★ (the ghost menu points there); pinned-filter slots await saved
  views in the palette (20h).

### 20c.1 — the editor pass (as built)

**Shipped.** The per-pane **toolbar** (overrides the no-toolbar law, recorded):
B · I · S · inline-code (the pack's ⌃` chord landed; ⌘E stays an alias) ·
heading-cycle H1→H2→H3 · bullet · link ([[ picker) — plus the right cluster:
**+ split** (three states per the sim: disabled-with-reason · split-with-the-
first-other-note · solid close-split), the **✦ AI pill** (opens the Copilot
lens note-scoped; halos when a suggestion is pending, pointing into Tidy),
and the **kebab** (Source explained-disabled until 20j's projection ·
Reveal in vault · Export…). **H1-is-title**: the title renders 24/700 in the
flow with the **name wand** beside it (deterministic first-line suggestion,
amber chips accept/reject; in-body H1 sync lands with the source pass).
**Splits at 2 panes**: the second pane is a READ-ONLY preview — one draft
ever, the draft follows focus (the one-draft law holds; the sim itself never
shows more than 2); clicking the preview hands the inspector its entity.
The **footer bar** (mono path — presentational until 20j · live word count ·
[[/⌃` hints). **Checkbox blocks toggle in the text** (the marker cell
tracks the mouse; one undo). **Wikilinks navigate** (click opens the target,
the tab dedups). The **Outline lens** gained mono H-tags and caret-tracked
active rows. The right rail wears **[Selection | View]** on every surface
(O10) with the v0 View pane (each surface deepens it in its slice) and the
assist lens reads **Copilot**.

**Deferred within 20c (recorded):** ghost autocomplete + streamed anything
(fence-gated on BYOK); active-line marker echo; the embedded view block
(rides the views pass); named versions (core design — the History lens
stands as P17f built it); the slash menu (next pass); the daily note's
civil title (display-map with 20c.2; the core template holds); the empty
state (unreachable — a desk tab always exists). **20c.2 next**: the tab
anatomy (content tabs down into the pane row, the global lane becomes true
containers, locked-tab open-routing) + the Journal/Projects/Recent panel.

### 20c.2a — the panel content (as built)

The Vault pane became the mockup's note-nav: **JOURNAL** (today first —
civil-faced "Tuesday 14 July", accent-soft, opens the Today desk; recent
dailies below), **PROJECTS** (the workspace tree as dot-rows, children as
"sub", click enters through the flush gate), **RECENT** (latest titled
objects, task rows badged; sorted by creation — the wire carries no
modified stamp, recorded). The file-by-format pools yielded to the Library
surface (20f). The Spaces pane: "Favourites" reads **Pinned**, and the
interim desk rows died (JOURNAL's today + the rail's Capture door
supersede them). Daily notes wear their civil face in tab titles; the
editor's title field keeps ISO (it IS the name — the civil face is chrome,
recorded). **Still open in 20c:** the tab anatomy — content tabs down into
the pane row, the global lane as true typed containers, locked-tab
open-routing — the phase's one remaining stateful rework, next chunk.

### 20c.2b — the tab anatomy (as built; 20c closes)

The two-level anatomy landed. The **global row shows CONTAINERS**: an
Overview pill (the ungrouped set incl. the desk) + one pill per tab group,
active = canvas-fused (the mockup's melt), padlock when the group carries
locked members ("only its content opens here"). The **content tabs moved
down** into the notes center as the 36px row — the whole lane carried
(clamped widths, +N overflow, width freeze, ⌘⇧T, group bands). The
container follows the selection; a new tab lands in the ACTIVE container;
a **locked container refuses foreign opens** and routes them to Overview
(v0 of the open-affinity — true content-category matching recorded as
future); a container whose last member closes falls home to Overview; the
close-neighbor pick stays inside the visible container; the active
container persists per workspace (v1 sets decode unchanged). Group
creation (the existing "New tab group" door) now fronts the new container.
**Recorded:** department tabs beyond Editor containers (Tasks/Library as
global tabs per the sim) wait until a need shows — the rail is the
department door; the sim's dept-tag pills ride then.

### 20d — capture + inbox (as built)

**Capture is a first-class surface** (rail item, `Surface.capture`): the
doorway header (amber zap tile · "the doorway that asks nothing" · ⌃⌥Space
chip) with the **Keep | Composer toggle** (O8 — the P12 gap closes);
the take card with violet **Save ⌘⏎**; the honesty under-row ("✦ name it
later — names DERIVE on save, always editable" + the saves-to readout,
presentational until 20j); quick chips (All · Today · idea · link ·
unrouted·N → Inbox › Route); the **Keep-style masonry wall** (4 columns,
round-robin by estimated height — deterministic) with amber-haloed cards
when a Tidy suggestion waits. Composer v0: the tall card where a leading
"# " line becomes the NAME (capture hands back the id via the new
`captureId` wrapper — one capture txn + one name set; the in-transaction
namer verb is recorded). Scrap titles **display-derive** from the first
line (✦ = derived, zero writes — the honest reading of "AI names it on
save" while capture stays never-classified). **Inbox**: folder-style
Route·[ / Tidy·] tabs wearing their jump keys; "one cleanup home — halos
elsewhere point, this lists"; the Route toolbar count line + the
contractual grammar footer; **the routing card moved to the right panel**
(1 New note default · 2 Suggest-a-merge fence-explained · will-file-to
readout · Later·L · Commit·⌘⏎); the rail badge collapsed to the spec's
grammar (ONE grey Route pip; the amber total lives on the header).

**Recorded (core-needing, deferred):** Suggest-for-all (needs an
on-demand suggest verb) · the real merge proposer (fence) · the per-cell
✦assist provenance stamp (wire key) · source-provenance labels beyond
"quick capture" (wire) · workspace stamping at capture (vocabulary
ruling) · attach/voice (ingestion seam) · the capture View-pane view-file
(rides 20h's view entities) · Tidy category regroup + card anatomy (the
Tidy polish pass; A/R group keys survive keyboard-only per the
feature-complete rule) · commit-as-task kept per the sim (a later digit).

### 20e — the tasks surface (as built)

The surface owns its **left panel** now (the mockup's per-surface pattern —
the seam every 20f panel reuses): **FOCUS** presets with live counts
(Today · Upcoming · Untriaged "no date, no project — waiting for a
decision" · All), **PROJECTS** as dot-rows filtering the pool (click again
clears; the toolbar wears the ✕ chip), **SAVED VIEWS** from the P18 view
entities (click = the view's query IS the pool; **＋ view** keeps the
current pool as a new one). The toolbar title IS the pool ("All tasks — by
status", the focus label, or the view's name); the Agents pill became the
amber **"✦ N of these I could do"** (pending proposals; hidden at 0 —
consent-gating rides the queue, which empties when the switch is off).
List sections wear **ring-dot + count** and terminal groups **fold** —
"folded — the view stays about live work". The **Schedule lens is the
two-week Mon–Sun grid** (override of bp6 a16; pager + range label, today
ring, status-dot pills, +N per-day overflow) with the **UNSCHEDULED tray**
— dragging a pill onto a day writes the date (⌘⌥Z undoes; the plan role
deepens this when it lands — today the one date is `due`, recorded).
Cards carry the multi-chip row (anchor + people + red-overdue date) under
the component's own ≤3+N budget. The board lost its "+ New status" column
(the vocabulary editor owns columns; the "no status" column STAYS — the
one board door for unsetting, recorded). Copilot moved LAST in the lens
bar. Per-focus empty states carry the sim's copy. The old All/Open/Done
segments died (FOCUS + the fold supersede); quick-add SURVIVES per the
feature-complete rule (the mockup omits it — recorded).

**Recorded (deferred):** plan/deadline dual chips + the role-typed date
rows (the plan role is a vocabulary+wire change); row hover ↗✦⋯ and the
halo-ring-instead-of-count (shared RowKit surgery — the Tidy polish
pass); board tile checkbox/chips + 198px narrowing; the full View-tab
view-object pane (filters editor — rides the views deepening); typed-task
accent icons (icon vocabulary undefined); assist-provenance chips (wire).

### 20f — library · contacts · calendar (as built)

**Library** owns its left panel: the pool chip grid (colored dots, LIVE
vault-wide counts; the inbox chip navigates to Inbox › Route), the
"a pool = a saved filter — never a folder" law, LISTS (hand-ordered),
SAVED VIEWS as entities, and the VAULT note pointing at 20j. The center
pool is **mixed-object** (no longer file-cells-only), scoped by the chip +
the type-to-filter field; the table became the **NAME / ANCHOR / ST /
MODIFIED grid**; the **Gallery lens is live** (tinted big-icon tiles,
never status); "＋ New ▾" replaces the lone Add-file (note · contact ·
file-by-reference; the other kinds arrive with their kinds); the census
footer replaces the ShortcutBar. **Contacts** is the three-pane override:
GROUPS (derived from org/area values v0 — arbitrary saved-query groups
recorded) + the avatar list with filter·F in the panel; the center is the
**person page** — breadcrumb (presentational path · saved tick), the
NEUTRAL-medallion hero card with the fields grid, **MENTIONED IN · N**
(derived from reference cells, source-tagged, navigates), the body
preview with the verbatim footnote + open-as-note. **Opening a person
routes to the page** (map [11]) from every door. New-contact births
person + name prompt ("a name alone is a complete contact"). **Calendar**
got its panel (the violet daily-note door + the auto-render law; the
CALENDARS checklist + Google row are recorded for the sync pass) and the
mockup's framed **today · daily note** tag replaces the white-number
circle.

**Recorded (deferred):** view files + the View-pane config editors ·
real paths/drag-out/drop-import (20j) · import surface conversion +
watcher + export Move-out (their own pass — the sheets stand) · the IOU
kind + computed strip (vocabulary + doors first) · @-mention writes
people (editor pass) · person body as a live editor (the page previews;
open-as-note is the door) · Lists surface retirement (the rail section
now lists them; the surface code stands until the tab-container map
covers it) · calendar chip hues/drag-editing/quick-create popover /
week framing (the calendar polish pass).

### 20g — Comms (as built; the BP-15 surface exists)

**The Rust (design-first, failing-test-first — the flagged additions):**
`services::comms::import_messages` — ONE batch = ONE transaction = one
undo (type + property births ride the same commit); `external-id`
(props::EXTERNAL_ID, the P15 key) upserts: byte-identical re-import is a
literal no-op; a REFRESH updates only the FEED-OWNED cells (from · sent ·
body · source) and never yours — subjects survive, a cleared `unread` is
never re-set (unread writes at first ingest only). Senders resolve to
person entities by exact unique name match — ambiguity resolves to
nothing, never a guess; unresolved senders keep the feed-owned
`from-label`. `sent` parses the civil grammar; unparseable stamps drop
(the shell falls back to created). New verb **`lotus_import_messages_at`**
(with_box + Committed: Wrote when anything changed / Read on all-skip /
Failed on persist — cache-parity tested).

**The shell:** the rail item (between Calendar and Dashboard, no badge,
no chord — the spec assigns none), the ambient surface: message lists as
live saved-view rows (Unread-from-people-I-know · per-source · All) with
the contractual no-second-inbox caption; from/source filter chips off
distinct values; the Fetch-now row ("fetched at open — nothing runs on a
timer"; the button is the sim's own honest 0-new toast); message rows
(unread dot · resolving sender chip that OPENS the person · snippet ·
source chip · relative time); the expanded card (via/sent header ·
external-id mono chip · feed-owned vs YOURS boxes · body as received);
reading clears unread as one undoable write; sticky selection; the lock
line "Liv reads your messages; it never sends them." **v0 ingestion =
drop a JSON feed file on the surface** — honestly labeled in the empty
state; live connectors are a later fence-opening. Comms also joined the
department picker.

**Rulings recorded:** vault-wide ambient (the sim's VAULT_WIDE wins over
its stray comment) · starter lists are surface chrome v0 (seeding them as
view entities later) · text-only source chips (no brand logos) · computed
`related` scoring, the dashboard nudge, Ask citations, and the contact
page's message rows ride 20h+.

### 20h — Mission Control + Ask (as built)

**Mission Control** (O7, map [0] — the pack overrides the 07-14
never-an-overlay ruling): **⇧⇥ floats the SAME board engine** over the
live app (canvas veil, × / Esc / ⇧⇥ drop back; opening anything closes
the overlay first) — two hosts, one engine; the rail surface stays. The
registry aligned to the new catalog: **Tasks-summary and Time left the
gallery** (their renderers survive for existing boxes; the timer chip is
independent and stays), **Suggestions / By kind / Resume joined** —
Suggestions runs the REAL accept/dismiss seams with the dormant-copy
consent line; By kind is the vault census; Resume is vault-wide on
purpose (the sim's words). **Pinned re-aims at tier = 1** (map [15]
reverses the P17g re-aim; the pins shelf keeps the chrome slots).

**Ask** (O5): the palette IS the one Search-or-Ask door — the field says
so, and a trailing "?" turns it into Ask: the **AUTO tool-log with real
counts** (search_vault → live hits · read_note → live word counts ·
"no write ever hides in an AUTO row"), the **fence-stated answer strip**
("the answerer is fence-gated: a model key + the automation switch open
it — the citations below are your vault's own answer today"; no fake
streaming, ever), the numbered **CITED list** (click opens), and the
amber **REVIEW pointer** into Inbox › Tidy when a cited object has a
pending proposal. The rail's Ask item became the palette door with the
amber pending-pip (consent-gated for free); the old Chats surface left
the rail (code stands until the dept map covers it — recorded).

**Recorded (deferred):** overlay view pills (Today/Guidance/Review —
multiple boards need view entities) · the streamed Project-summary
widget, What-next AI rows, the habit-migration banner (fence/model) ·
the widget Selection/View config panes (view entities) · the 6-column
span grid + card chrome polish · Settings AI-page rename + tier field +
provenance stamps (wire) · the catalog registry adoption (its own pass).

### 20i — Settings as a surface + the tour copy refresh (as built)

**Settings is a rail SURFACE now** (O9 — the P19 fourth-overlay carve-out
retires; the struct is excised, not just unmounted). The left panel:
search with the grammar hint ("0 results never dead-ends: ⏎ hands the
query to the palette" — it really does) + the six OPTIONS with icons and
scope aft tags — **General ·3 settings· / Appearance / Properties (vault)
/ Vocabulary (vault) / Shortcuts / AI**. The center: the pane in a
max-880 column + the no-Save footbar. **The General page** carries the
exactly-three frame verbatim (Store location w/ path + Reveal · What it
looks like → Appearance w/ the live theme label · Whether the assist
layer runs → AI w/ the live ✦ on/off chip), with Startup and the capture
convention keeping quiet homes below (the mockup's nav drops both pages —
recorded keeps; the hotkey recorder moved to Shortcuts' top). Properties
and Vocabulary split along the mockup's line (one panel, gated sections).
The AI page wears the mockup's framing sentence ("nothing here changes
WHAT the AI may do — that contract is fixed"). ⌘,, the rail gear, every
receiver, and the seeded banner's deep link all navigate to the surface.
**The tour**: the finish strip points at the ✦ title-bar pill ("replay:
the ✦ pill in the title bar" — Help stays an alias) and the assist moment
carries the new consent copy ("assist may point — quiet ✦ marks — and
propose… Off = fully manual, nothing suggests").

**Recorded (deferred):** the FULL 5-step tour rebuild (map [16]–[21]:
folder vault + Change… + existing-folder mode, vocabulary-seeding topic
chips, the three new contractual capture strings w/ simulated send, the
inline-inbox aha with degrade states, the two-gate consent step) — its
own pass, entangled with 20j's folder story · the per-kind Properties
matrix · the AI page's Plan section + aggressiveness knob (fence/CORE) ·
the digit-facet search grammar retired with the overlay (recorded in
P19's doc; the surface search is filter + palette-handoff).

### 20j.1 — the projection's pure layer (as built)

`services/src/vault.rs`: the **vault slugger** (the pack's breadcrumb is
the spec — `Steven Åkesson` → `steven-akesson`; Latin fold, single-hyphen
collapse, 200-byte clamp, Windows-reserved suffixing, dot-refusal,
`untitled-<id>` fallback), **deterministic case-insensitive collision
suffixing** (id order keeps the bare stem), **pool classification**
(daily beats note; binaries by extension; unrouted scraps/messages/
unknown binaries box-only — recorded), **H1-is-title rendering** (no
`title:` key; `type:` leads the frontmatter) with `parse_vault_note`
recovering name/frontmatter/body, and `expected_files(store)` — the pure
fixpoint the 20j.2 planner converges to.

**The gate earned its keep.** The render∘parse fixpoint property test
caught FIVE real codec instabilities in the P15 markdown layer, each now
fixed in `markdown.rs`: (1) adjacent same-mark runs mis-lexed (`` `a``b` ``
became one code span with literal backticks; `~~a~~~~b~~` a four-tilde
run) — the renderer now MERGES identical-mark neighbors and normalizes
code-run marks; (2) marks emit through a nesting STACK so a shared mark
never closes+reopens at a boundary; (3) a TIGHT list item's paragraph
suppression outlived the item and glued the next paragraph onto it —
suppression now dies with `End(Item)`; (4) orphan list depths and
under-indented children flattened on reparse — depths clamp to the chain
and indentation is the cumulative parent marker width (task children
column = 2: the `[ ]` is content); (5) whitespace inside emphasis
delimiters fails flanking — boundary ws hoists out of marked runs.
**The honest contract, recorded:** distinct marker families (`**`/`_`/
`~~`, strike innermost) make REALISTIC (space-bounded) documents strictly
byte-stable; adversarial no-space compounds hit CommonMark's flanking
algebra (an outer closer preceded by an inner marker's punctuation cannot
close in ANY order) and instead **converge in one round trip** — which is
what the projector's echo suppression actually requires; the one-step
settle + occasional mark-to-literal degradation is the codec's recorded
lossy edge. Both properties are pinned by 200-case generative tests.

### 20j.2 — the materializer + manifest (as built; kill-shot A green)

`services/src/projection.rs`: the **pure planner** (`plan_projection`:
expected(store) diffed against the manifest → FsOps + the post-apply
manifest, deterministic, no IO) and the **applier** over the `VaultIo`
trait — every op verified against the CURRENT disk before acting (a
rename whose source is gone but target exists is complete work, not an
error), the **manifest written LAST** and only on full success. The
manifest (`.liv/index.json`) is a CACHE: absent or corrupt → empty →
heal (test-pinned). Trash parks files at `.trash/<original-rel-path>`
with `trash_from` remembered — **undo over the log IS undo on disk**
(rename→undo and trash→undo round-trips test-pinned). **KILL-SHOT A is
green**: the fuse-injected crash matrix aborts the apply after EVERY op
count (including at the manifest write) across create and rename
histories, then reconverges to files == expected(store) with zero loss,
zero duplicates, zero strays.

**Recorded:** digest = SHA-256 (the P15 librarian's own hash — the
design doc said blake3; corrected) · v0 projects the MARKDOWN class only
(binary byte-copies ride 20j.8) · stray files under a LOST manifest
after a rename wait for 20j.3's disk-scan reconcile (the manifest-cache
heal covers content; the orphan sweep is the scan's first job).

### 20j.3 — reconcile + ingest + echo suppression (as built; kill-shot B green)

The **scan** (read-only, `VaultIo::list` joins the trait) implements the
decision table in the design's order: rule 1 is **content-addressed
clean** — a file whose bytes equal render(store) is ours whatever the
timestamps say, so the projector's own writes are structurally incapable
of re-ingesting (**kill-shot B: 100 sync cycles, zero commits, the log
byte-identical — green**). A clean external edit (box unmoved since the
manifest's sync point) becomes `Edited`; both-sides-moved becomes
`Conflict` — **surfaced, never merged** (pinned: zero log growth); a
missing file becomes `Missing` — **the entity never dies** (pinned); a
burst beyond 25 changed files collapses to ONE `MassChange` card (the
sync-client fingerprint — pinned at 30 files, nothing applied); a stray
byte-copy of an expected file reports `OrphanCopy` for the projector.
The **ingest** batches every tier-A finding into **ONE `vault-edit`
transaction** (`Author::User`, one ⌘⌥Z — pinned): the H1 wins the name,
the body replaces content; a hand-born file under a pool folder births a
typed entity. **The duplicate factory is structurally closed**: ingest
returns the adopted (id, path, digest) triples, `adopt_into` folds them
into the manifest, and the next plan RENAMES the hand path to canonical —
the second scan+ingest cycle is pinned silent.

**Recorded:** frontmatter-cell edits on ingest are a later deepening
(v0 = name + body, exactly what the shell's own editor writes) · daily-
pool births type as plain notes v0 · the conflict/missing/mass cards'
shell UI rides the verb slice (20j.5) with the editor's keep-mine/
take-theirs grammar.

### 20j.4 — the projector lock + log self-defense (as built; kill-shot C green)

**The two-process race is serialized**: `projection::project_locked`
takes a blocking flock on `.liv/projector.lock` across load→plan→apply
only — IO-only, never the box lock, released on drop — and
**`RealVaultIo`** landed (rooted; tmp+fsync+rename through `.liv/tmp/`;
recursive list). **KILL-SHOT C is green**: two threads racing ten
projection rounds each over one real directory converge — every expected
file byte-exact, the manifest never torn, a fresh plan empty.

**The log defends itself** (design §4) in the FFI open path: a SHORTER
log than the cache last proved (a sync client replacing the append-only
source with an older copy) or a same-length different-inode swap refuses
the fast path — the miss replays honestly, nothing adopted silently —
and surfaces a notice; a **conflicted-copy sibling** of the log raises
its own notice on every open until resolved. Notices drain through the
new flagged verb **`lotus_vault_alerts_at`** (path-scoped read-and-clear
— one box's reader never swallows another's; in lotus.h). Test-pinned:
the synced-down-older-log scenario surfaces SHRANK and drains once; the
conflicted sibling surfaces by name. (The regression test retries around
parallel tests' cache clears — the guard's proof is the cache entry, and
the test suite's own `clear_cache_for_tests` races it; the mechanism is
deterministic in production where nothing clears the cache.)

### 20j.5 — the verbs + the continuous projection (as built)

**Every Wrote commit in a vault box now materializes**: `with_box` gained
the projection hook — the PLAN computes while the store is in hand (pure
CPU + one small manifest read; within the lock law), the file IO runs
AFTER checkin under the projector lock, and a projection failure never
fails the commit. **Vault discovery is by the `.liv` ancestor**
(`<root>/.liv/box/<log>` → vault mode; anything else = legacy, projection
off — every existing harness and LOTUS_BOX_PATH flow untouched, pinned by
the legacy-status test). Three flagged additive verbs (lotus.h): 
**`lotus_vault_status_at`** (cheap: mode/root/file count),
**`lotus_vault_sync_at`** (scan → tier-A ingest as ONE "vault-edit" txn →
adopt → re-project; returns edited/created/surfaced; the 20j.3 adopt-
before-plan pin is honored so hand-born files rename, never duplicate),
**`lotus_vault_rebuild_at`** (plan from an EMPTY manifest — every file
rewrites even if the manifest lies). The **CLI** gained `lotus vault
status|sync|rebuild` over the same seams (projector-lock honoring); the
shell gained the BoxModel wrappers (`vaultSync`/`vaultStatus` — the UI
rides 20j.6). FFI-pinned: the commit hook materializes a routed note;
sync ingests an outside edit exactly once (echo-proof second sync);
rebuild restores a torched `library/`; legacy stays legacy. Smoke-tested
end-to-end through the CLI on a scratch vault.

**Recorded:** the sync scan's file reads run inside the box hold v0 (the
store cannot yet snapshot out; sync is launch/user-triggered) · the
commit hook's full plan-per-commit is the optimization point (touched-id
threading later) · scrap `add` from the CLI stays box-only until routed —
correct per the materialize-on-route delta.

### 20j.6 — the fidelity flip (as built; the pack's paths stop being props)

The projected path became a **wire field** — `EntityRow.vault_path`
(`library/<pool>/<slug>`, the exact `expected_files` output joined by id;
`skip_serializing_if none` so box-only entities and legacy boxes add
nothing; cache-parity intact). The shell gained **vault-mode by
containment** in Swift (`BoxModel.vaultRoot`/`inVault`/`vaultDisplayName`
mirroring Rust `vault_root_of`) and a real **`revealInFinder(id)`** that
opens the entity's actual file. Every presentational site from 20b–20i
**flipped, gated on vault mode**: the contacts breadcrumb is the real
monospace path and CLICKS to reveal the file; the editor footer path is
real + click-reveals + the kebab's "Reveal in Finder"; `Vault: <name>`
names the real folder and its menu reveals the folder-of-markdown with
the "that folder IS the database" line; the library footer + VAULT note
name the real root; the capture saves-to help tells the truth (a scrap
waits in the box; routing writes the file); and Settings → General's
Store-location row shows the pack's verbatim copy ("one plain folder of
markdown and files — that folder IS the database…") over the real root,
with Reveal opening it. **Legacy mode keeps every honest placeholder** —
each flip is `model.inVault ? real : placeholder`, so `LOTUS_BOX_PATH`
and any non-vault box read exactly as before. Wire contract pinned: a
routed `Steven Åkesson` snapshots as `library/notes/steven-akesson.md`
(the diacritic fold proving the full chain), an unrouted scrap carries
none.

**Recorded:** the tour's folder step, the Move… flow, and existing-folder
adoption ride 20j.9 (the pack promises them but they need the migration
work) · in-editor source-mode still deferred (its own later slice) ·
drag-row-out-as-file and drop-to-import ride 20j.8.

### 20j.7 — the watcher + the divergence UI (as built)

**The read-only FSEvents watcher** (`Vault.swift`): starts in vault mode
only (idempotent, on the first snapshot), watches the vault root with
FSEvents (0.8s coalescing latency), **excludes `/.liv/`** (our own
writes), and on any other change schedules ONE debounced sync via a
cancel-and-reschedule work item — a burst of 10 or 10 000 events fires
exactly one scan once quiet. It NEVER writes: it calls the same
`vaultSync` verb the user does, and sync is echo-proof (kill-shot B), so
no write loop is constructible. Scan-at-open stays canonical (the start
surfaces pre-existing divergence immediately).

**The divergence UI**: two new flagged verbs — `lotus_vault_findings_at`
(read-only scan → JSON `[{kind,id?,path?,count?}]`; `all=1` expands a
mass burst) and `lotus_vault_resolve_at` (verdict `take-disk` | `keep-app`
| `trash`) — over three Rust resolvers (test-pinned: take-disk ingests
the disk version as one undoable txn; keep-app rewrites the file from the
store and settles the scan; trash removes the entity and the next
projection parks the file). The **`DivergenceBanner`** (amber, atop the
body, shown only when residue exists) carries the verdicts: conflicts get
Keep-mine/Take-disk, a missing file Restore/Trash, a mass burst
"Review individually". Clean edits auto-ingest and never reach the banner
— it is the you-decide residue. **CLI**: a new `lotus route ID TYPE`
(closes a real gap — the CLI couldn't type a scrap by name) let the whole
loop be smoke-tested end-to-end: route → rebuild materializes → hand-edit
→ status shows the finding → sync ingests it (1 edited). FFI-pinned: the
conflict findings→resolve round-trip settles to an empty scan.

**Recorded:** the watcher's storm→1-scan guarantee is structural (the
shell has no test harness; the safety property — no write loop — is the
Rust-pinned echo-proofness) · keep-both (import the disk copy as a new
entity) deferred to the import slice (20j.8) · conflicts route through the
banner v0, not yet the editor's inline keep-mine/take-theirs card.
