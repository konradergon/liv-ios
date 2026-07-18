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

*(appended from the reconciliation workflow — pending)*
