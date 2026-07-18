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
