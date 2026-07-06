# Lotus Feature Map — Liv parity, on the constitution

> **Status:** 1.0 — the durable digest of Liv's five feature inventories (~300k tokens of
> friend-fixes), merged, deduplicated, and mapped onto lotus. Future sessions read this
> instead of Liv. Where this document and `productivity_app.md` / `interface.md` disagree,
> the constitution and the interface brief win — always.
>
> Scope instruction from the owner: *reach Liv's feature scope; copy its workflows;
> never break the core architecture.*

---

## How to read the mappings

Every Liv feature is carried by one of the mechanisms lotus already has. The vocabulary:

- **property / cell** — a new field is one property definition entity; instantly queryable, zero migration
- **type + expectations** — templates, defaults, "what fields does a meeting have"
- **lens** — a renderer plus a saved view (query + renderer + config); the config maps properties to visual dimensions
- **saved view** — bookmarking the on-screen query; the fence stops at the verb *save*
- **clerk proposer** — reads via queries, emits proposals; dismissals live in the declined sidecar, so nothing asks again
- **answerer** — read-only; question → query → cited entities → deep links
- **agent** — a goal drafted as one transaction; one confirmation, one undo step
- **service** — projections, import/export, extraction caches; computed once, every view agrees
- **shell** — window, hotkey, popup, inbox, menus; owns no data

AI gets **two doors, no third**: reads through queries, writes through proposals. Anything
that needs another door is wrong by construction.

**What already exists** (do not rebuild): entities/cells/values, commands + transactions +
append-only log + undo, the v0 query (conjunction + sort + AtMost), List/Table renderer,
Today sections, month calendar, capture (`capture()` + macOS shell), clerk v0 (dates +
mentions proposers, sweep-behind-write, duplicate drop), recurrence (rule text, virtual
occurrences, exceptions, no-debt), persisted proposal queue + refusals sidecar,
provenance, starter library (note/task/event/person/project; due/status/related).

Sizes: **S** = small (days), **M** = a real chunk, **L** = milestone-scale.

---

## T1 — Makes the skeleton livable

The everyday note / task / calendar / editor workflows.

### Capture & inbox

**1. Frictionless capture** (S — polish only)
*Liv:* "Take a note…" box; never asks for a name; metadata pre-filled; five rapid captures land findable with zero dialogs.
*Lotus:* already the law and the code — `capture()` makes a scrap (content + created, nothing else) via the ⌃⌥Space popup; the shell holds no session. AI-name-on-send becomes a clerk proposer (T3 #4). Nothing new in core.

**2. Inbox as orphan router** (M)
*Liv:* Inbox tab lists unprocessed captures with what's missing ("no area · no project"); per-row Suggest and bulk Suggest-all; commit applies metadata.
*Lotus:* the proposal inbox is already the shell's one non-view surface. "What's missing" is a query (`content exists`, `due missing`, `type missing`). Suggestions are clerk proposals; bulk is a proposal **group** (alike proposals group, sever, commit as one transaction — constitution 1.3). New: group rendering + single-key triage (a/r) in the GUI shell.

**3. One cleanup address, permanent dismissals** (S)
*Liv:* Tidy queue of heuristic suggestions; deterministic ids so Dismiss never re-nags; three cleanup entry points consolidated to one.
*Lotus:* structural for free — heuristic proposers + the declined sidecar; duplicates of pending or declined never reach the queue. There is exactly one inbox by law. New: the heuristic proposers themselves (T3 #10).

**4. Merge routing ("which note does this belong in?")** (M)
*Liv:* processor suggests merging a capture into an existing note.
*Lotus:* merge is already a first-class composite (copy cells, trash loser, one redirect). New: a clerk proposer that emits merge proposals, and a small conflict-resolution moment on accept.

### Notes & editor

**5. The editor** (L)
*Liv:* CodeMirror live-preview markdown, slash menu, toolbar, source toggle, callouts, tables, math.
*Lotus:* the Editor renderer — one entity's rich-text content in a centered ~65-char column, keyboard formatting only, **no toolbar in v1** (interface law). Content is spans, not markdown files; markdown syntax is at most an input convention. Embedded references render as pills; an embedded task draws its live checkbox. This is the single biggest T1 build.

**6. Links, relations, backlinks** (M)
*Liv:* [[wiki-links]] create edges; Connections panel; typed relations; manual vs body-derived origins; backlinks pane.
*Lotus:* `Span::Ref` in content plus reference properties — one relationship mechanism; backlinks are automatic (references indexed both directions). A relation carrying data (label, role) is a promoted entity. Liv's manual-vs-wikilink origin distinction falls out naturally: a body ref lives in content, a `related` cell lives in the inspector. New: the insert-reference picker in the editor.

**7. Task inside a note** (M)
*Liv:* checkbox lines in notes surface in a cross-note checklist; check state syncs.
*Lotus:* worked example 3 — the note embeds a reference to a real task; the checkbox gesture edits the task entity; the same task appears in every lens. Plain-text checkboxes are just text until promoted — an explicit act or a clerk proposal. New: editor gesture + promotion proposer.

**8. Daily notes** (S)
*Liv:* Ctrl+D opens today's note; today's calendar cell *is* the daily note; daily-note card aggregates the day.
*Lotus:* Today is already the orientation surface and aggregates the day by query. A "daily note" is an ordinary note with a date cell, born from Today's lead capture line (⌘N). No template/folder machinery. Genuinely new: nothing — resist rebuilding Today as a note.

**9. Templates** (S/M)
*Liv:* built-in + user templates, `{{date}}` variables, template-authoring editor.
*Lotus:* types carry expectations; defaults are Expectation entities; creating through a type's template reads them. Date-ish variables are creation-time defaults. **No template-authoring surface** — authoring is fenced; the clerk learns the schema instead (law). New: template-create flow in the shell.

**10. Version history** (M)
*Liv:* right-panel History tab with note snapshots, review/restore.
*Lotus:* the log *is* history. Per-entity history is a projection (transactions touching the id); content edits replace the whole value, so every save is already a snapshot. Restore = re-committing an old value as a new command (append, never rewrite). New: a History pane in the inspector.

**11. Subnotes / hierarchy** (S)
*Liv:* container notes own children; per-container name uniqueness; breadcrumbs.
*Lotus:* a `parent` reference property — hierarchy is only one relationship. Names are cells, not filenames, so the whole uniqueness/collision apparatus is moot. New: breadcrumb affordance, if daily use asks.

**12. Lists / collections with membership** (S/M)
*Liv:* Lists are joinable collections whose metadata stamps members by template mode.
*Lotus:* a list is either a saved view (query membership) or an entity holding multi-valued `related` references (manual membership). Stamping members is a clerk proposal on join — never a silent fold. New: small add-to-list gesture.

**13. Archive** (S)
*Liv:* archived objects hidden from default search, includable on demand; distinct from trash.
*Lotus:* one boolean property; default views filter it exactly like `working`; "include archived" is a query variation, not a setting. Trash already exists (soft, never cascades).

**14. Extract selection → task / event / contact / note** (M)
*Liv:* highlight text, extract an object; source note untouched; back-link added ("convert text, not the note" — founder-locked).
*Lotus:* a shell gesture composing one transaction: create entity, add cells, add the back-reference. One undo step. The AI-assisted variant is a proposal (T3 #7). Keep Liv's rule: the note stays a note.

**15. Note merge & duplicate cleanup** (M)
*Liv:* near-duplicate detection, merge with survivor choice.
*Lotus:* merge composite exists; zero writes to referrers; one undo step. New: duplicate-detection proposer (equality is defined per value kind — dedup depends on it) + conflict UI.

**16. Habit / metric tracking** (M — deferred until daily use demands)
*Liv:* checkbox habits in daily notes, points, streaks, heatmaps; numeric fields charted; "computed, never stored."
*Lotus:* a check-in is a small entity (date + reference to a habit entity); streaks/points are projections computed once in Services — Liv independently converged on lotus's projection rule; keep it. Rendered by list/calendar lenses, **not** a widget board (T4). Charts wait for a lens that justifies itself.

### Tasks

**17. Task model** (S)
*Liv:* status/priority/due/recurrence; per-workspace status sets.
*Lotus:* exists — task type expects status (todo/doing/done) + due. Priority is one more select property (seed or let the clerk learn it). Divergent status vocabularies are the known "shared select" open decision (split-or-union) — decide when it bites; do not pre-build per-scope status sets.

**18. Board / kanban lens** (M)
*Liv:* kanban where columns are filters; drag changes the field; done cards dim.
*Lotus:* the board renderer — position by a select property; drag = a command setting status; manual order = Placement entities (worked example 8, `working: true`). Board is a **candidate renderer that must justify itself** (Today took list); justify it with real task volume, then build.

**19. Recurring tasks** (S)
*Liv:* recurrence spawns next occurrence on completion; RRULE ambitions; lineage.
*Lotus:* exists and is better-shaped: the series is one entity, occurrences are virtual (query-layer expansion, horizon = asked window ≤ 1 year), exceptions are ordinary entities, past occurrences accumulate no debt. Richer grammar ("every 2 weeks", "3 days after done") is a grammar extension when daily use asks. Liv's ClickUp gotcha (spawned tasks firing triggers) is structurally moot — nothing is spawned.

**20. Quick-entry tokens (`due:`, `!high`, `@name`, `#tag`)** (S)
*Liv:* inline tokens parsed out of the typed title.
*Lotus:* refuse the parser at capture (capture never requires structure; a token syntax is a type-picker in disguise). The clerk already proposes dates and mentions from plain text — extend it with a priority-word pattern. Same outcome, one confirming keystroke, no syntax to learn.

**21. Saved task views** (S)
*Liv:* "Weekly triage", "High priority list", view presets with fields/sort/filters.
*Lotus:* saved views — query + renderer + config; bookmarking the on-screen query is explicitly allowed. Appear in the sidebar (navigation is a view of views).

**22. Time tracking** (M — deferred)
*Liv:* start/stop timer per project/task; single-active-timer invariant; totals per scope.
*Lotus:* time-entries are entities (start, end, reference to task/project); single-active-timer is a shell invariant; totals are projections. Not in the first workflow; build when the owner asks twice.

### Calendar

**23. Month / week calendar** (S)
*Liv:* Month/Week/Day toggles, event chips, today highlighted.
*Lotus:* month lens exists; week is the same renderer at another density/config. Day view waits for a reason.

**24. Anything with a date appears** (existing)
*Liv:* any object kind on the calendar via a configurable date field.
*Lotus:* already the design — the view config names which date property positions entities. Behavior hangs on properties, never on types.

**25. Multiple "calendars"** (S)
*Liv:* named color-coded calendars in a left panel.
*Lotus:* saved calendar views with different queries. Color budget is law (one accent; five status dots) — calendars are distinguished by view, not by a hue system.

**26. Events** (S)
*Liv:* events with location, attendees (distinct from people-links), agenda, linked note.
*Lotus:* event type exists. Location/notes = properties; attendee = reference; attendee-with-role = promoted Attendance entity (worked example already). Linked agenda note = a reference.

### Search, metadata & schema

**27. Search** (M)
*Liv:* omnibox + palette, query syntax, facet chips with counts, result modes, "search is the trust that beats tab-hoarding."
*Lotus:* ⌘F at the top of the sidebar; results render as the list lens in place — **no palette, no overlay** (decided 0.2). Full-text index exists in the store shape; extend it over extracted foreign text. Facets are constraints; keep Liv's one genuinely great idea — facet counts as *hypothetical result sizes under the current filter*, a service helper. New: search service polish + shell field.

**28. Saved searches** (S)
*Liv:* Save from the palette → live view, pinnable.
*Lotus:* the bookmark verb — saved query entities appear in the sidebar. Exists conceptually; wire the gesture.

**29. Property system** (existing / S)
*Liv:* Obsidian-parity typed properties; custom properties schema-on-read; instantly filterable; user-retypable ("active" must not hard-code tri-state).
*Lotus:* already structural — property definitions are entities in a global namespace, closed value-kind set, everything queryable with zero migration. Retyping = editing the definition entity, the uniform way. Liv's warning holds: never hard-code field behavior (renderers key on properties, never types).

**30. The metadata grammar (form/type, subjects, tier, description, sources…)** (S)
*Liv:* one grammar across all kinds; form vs type as orthogonal single-selects; tier 1–3 number; subjects list.
*Lotus:* all just properties. The form/type split dissolves: `type` is multi-valued, so "a pitch that's atomic" is two types — no second axis needed. tier = number, description = text, subjects = multi-valued select/reference, sources = multi-valued. Seed sparingly; the clerk proposes the schema per user (law: The Clerk Files the Schema Too).

**31. Inspector** (M)
*Liv:* right-panel metadata editor; core fields prominent, rest collapsed; fully keyboard-first; friendly empty prompts; "visibility ≠ obligation."
*Lotus:* the inspector is the third window region (⌘I; open in Table, closed in Today). Expectations drive which fields offer themselves blank — an affordance, never a question; blank costs nothing. Editing a cell is the same gesture as everywhere (uniform grammar). New: build it in SwiftUI.

**32. Value pickers with seeded vocabulary** (S)
*Liv:* three layers — used values, shipped seed set, create-new; never an empty picker.
*Lotus:* existing values are a query; the starter library is the seed; the gazetteer already exists for the clerk. Same three layers, no new mechanism.

**33. Metadata presets** (covered)
*Liv:* saved metadata bundles applied in one action.
*Lotus:* a preset **is** a type with expectations. "Apply preset" = add the type. No preset store.

---

## T2 — The integrations

Constitution: **at most one integration until the core is proven** — local files first, by
reference with a content hash. Everything else in this tier is sequenced behind it.

**34. Local files by reference** (L — the sanctioned first integration)
*Liv:* files as vault-owned pool objects, dual-write mirrors, watchers.
*Lotus:* the librarian, not the vault — an entity referencing path + content hash. The ladder, every rung read-only: icon/filename/properties → extracted plain text (cached, feeds search) → thumbnail → open externally. A changed hash *is* the integration: re-extract, refresh, done. Never move, copy, or rename user files. Caches are rebuildable, never cells.

**35. Library view (files by kind)** (M)
*Liv:* browser over pools with type filters, grid/list.
*Lotus:* saved views filtering file entities (format is a property). The image grid is the Gallery renderer — a candidate that must justify itself; images are the one foreign format cheap enough to render natively.

**36. Word/PDF preview & text extraction** (M)
*Liv:* read-only .docx structured preview (hand-rolled zip/XML), explicitly no editing.
*Lotus:* rungs 2–3 of the ladder — extraction cache + optional thumbnail. Liv independently landed on read-only-by-decision; lotus has it as law (no rung five). Keep Liv's hand-rolled parser instinct: extraction is a cache, cheap and disposable.

**37. Open externally / reveal** (S)
*Lotus:* rung 4; a gesture that mutates nothing, so nothing to record or undo. Shell.

**38. Create-and-hand-off documents** (S — optional)
*Liv:* "New Word doc" writes a real minimal .docx and opens it.
*Lotus:* permissible as a shell convenience: write minimal bytes once, create the file entity, open externally, never touch the bytes again. The entity owns the meaning; Word owns the words.

**39. Links** (S)
*Liv:* links as first-class objects with unfurl, favicons, embedded mini-browser.
*Lotus:* a link entity — url + title scraped **once** at capture. Paste-a-URL is a capture path (the clerk can propose the title). Open launches the browser. No webview, no snapshots, no re-unfurl loop (a scraped page is allowed to go stale; an archived page is a stale mirror by definition).

**40. Bulk link import (browser tabs / bookmarks HTML)** (M)
*Liv:* drag 20–200 tabs; folder names become candidate subjects; titles never clobbered by unfurl. (Owner-fenced in Liv; don't invent mechanics.)
*Lotus:* the import service — one batch = one transaction (one undo); folder names arrive as grouped clerk proposals for subjects/related. Keep Liv's rule: a title that arrived with the link survives.

**41. Import (bulk onboarding, Obsidian vaults)** (L)
*Liv:* point at folders, auto-classify, AI batch-suggest, approve in bulk; frontmatter round-trip.
*Lotus:* import **copies**; `external-id` makes re-import a no-op; frontmatter keys become cells (property definitions created as needed — the clerk proposes consolidations afterward). AI classification = grouped proposals, severable, one keystroke per group. A tool you run, not a place you live.

**42. Export** (M)
*Liv:* filter-select, compose folder structure, copy/move; export-N from search.
*Lotus:* an export service taking a query — notes to markdown, batches to folders. Export is the honest answer to files-as-truth: the user can always get everything out, without lotus pretending files are the store.

**43. ICS calendar feeds — FENCED** (L, only after files prove the pattern)
*Liv:* one-way secret-URL feed import; RRULE expansion; re-sync refreshes feed-owned fields while **preserving user-added metadata**; source deletions delete locally.
*Lotus:* when the fence opens: one-way import copies; VEVENT UID → `external-id` (per-occurrence composite ids); feed-owned cells refreshed, user cells never touched — Liv's merge policy is exactly the entity-owns-meaning split; keep it verbatim. Until then: two calendars coexist honestly — the real calendar holds the world's appointments; lotus holds the dates the user makes.

**44. Google Calendar two-way sync** — refused; see T4.

**45. Contacts** (M)
*Liv:* people vault with profile fields; people-chips link objects to contacts; groups.
*Lotus:* person type exists. Profile fields (email, phone, company, role, birthday) are properties — let the clerk propose them as expectations after a few uses, or seed minimally. People lists = saved views. One-shot import from vCard/macOS Contacts is an import (copy + external-id), not a sync.

**46. Deep links & drag-out** (S/M)
*Liv:* drag rows to Slack/Finder with file URIs; reveal-in-OS fallback.
*Lotus:* `app://entity/4211` is already law (paste into an email; resolves for years). Drag-out: file entities offer their real path; native entities offer text + deep link. Shell seam work.

---

## T3 — The AI layer

Two doors: the **answerer** reads (queries in, cited entities out), **proposers/agents**
write (commands quarantined in the queue). Liv's three altitudes (deterministic assist /
one-shot LLM / full agent) survive intact — they differ only in the brain, never in the
door. Models are sockets, never wires; the API key lives in the Keychain behind the
menu-bar item (a budgeted setting: observation cannot reach it, the OS does not answer it).

| # | Liv behavior | Door | Lotus mapping / what's new | Size |
|---|---|---|---|---|
| 1 | Ask-the-vault chat; answers cite objects by name | **Answerer** | Question → query → top entities serialized → answer citing ids; citations render as deep links. New: the ask surface + serialization. | M |
| 2 | Chat offers actions ("draft that email as a task?") | Answerer → **agent** | The offer is text; accepting it drafts a proposal. No action ever lands from the chat directly. | S |
| 3 | ALT+M metadata suggestion with in-pool alternatives | **Clerk (LLM brain swap)** | Milestone-9 socket: same proposer interface, model brain, fed the gazetteer so it never invents values (law, not prompt-craft). Alternatives ride as severable group members. | M |
| 4 | Capture titling (AI names the scrap, visibly) | **Clerk proposer** | A name proposer: Add Cell `name` on fresh scraps. Liv's "AI suggests ONLY the name at capture" matches capture-asks-nothing. | S |
| 5 | Meeting notes → extracted tasks, reviewed before create | **Proposer/agent** | One grouped proposal: N creates + back-references, severable per member, one undo. | M |
| 6 | Note splitting (2–6 atomic notes proposed) | **Agent** | Goal → one drafted transaction (creates, content moves, references). One confirmation. | M |
| 7 | Selection rewrites (rephrase/tighten/expand), accept-in-place | **Agent** | Drafts a content-replace transaction; previewed inline; accept = commit, reject = drop. Inline preview is just another face of the queue. | M |
| 8 | Task assist: suggest next steps, draft a message to copy | **Answerer** | Pure read; the draft is text on screen, never sent, never saved. | S |
| 9 | Task copilot: one validated status/priority/due patch | **Clerk proposer** | Proposal of Add Cell(s); select values validated against option entities by construction. | S |
| 10 | Deterministic nudges/cleanup: missing metadata, duplicates, stale, unlinked, orphans | **Heuristic proposers (no LLM)** | Liv proved these work offline — port the rules as regex-grade proposers beside dates/mentions. Dismissal memory = the declined sidecar, already structural. | M |
| 11 | Metadata audit: value clusters, canonical spelling, merge proposals | **Proposer** + merge | Near-duplicate vocabulary → proposals to merge property values/definitions ("merge repairs property definitions like it repairs people"). | M |
| 12 | Recurring template drafts ("dagordning ready — review?") | **Agent on the sweep** | No timers, ever: the open-time sweep sees an occurrence inside the window and drafts the document as a note-entity proposal. Review, edit, accept. | M |
| 13 | Document-producer agents (meeting notes → agenda .docx) | **Agent** + export | The agent drafts a note entity (one transaction); .docx is an export action afterward. Lotus never authors foreign bytes as a surface. | M |
| 14 | Project status summary ("where am I?") | **Answerer** | Scope = a query (project reference); compact serialization; cited bullets. | S |
| 15 | Ambient context (assistant sees the current view/selection) | **Answerer input** | The active view is an entity; its query + the selection are handed as context. `private` cells excluded; the automation switch kills the whole layer. | S |
| 16 | Metadata backfill over old thin objects | **Agent** | A sweep drafting grouped proposals; sublinear triage makes 1,200 objects a few group-accepts, not 1,200 keystrokes. (Owner-fenced in Liv — confirm before building.) | M |
| 17 | Search smart-rerank (guaranteed permutation) | **Answerer-as-projection** | Read-only reorder of results for display; keep Liv's permutation guarantee. Defer. | S |
| 18 | Inline ghost-text autocomplete | **Deferred** | Tension with the silent-assistant failure mode ("nobody trusts autocorrect"). If ever built: read-only suggestion, acceptance is the user's own keystroke. Not v1. | M |
| 19 | Custom prompt library | **Agent config as data** | Prompts are entities (data in the box); running one is an agent invocation. Low priority. | S |
| 20 | MCP / external connectors (Notion, Google, ClickUp) | **Fenced** | The external agent socket is an Open Decision, explicitly fenced. When it opens: external agents enter through the same proposal queue — quarantine is the prompt-injection defense Liv designed risk tiers to approximate. | — |

**Liv rules to keep as law-restatements:** never invent values (the gazetteer *is* the
mechanism); dismissals are permanent (declined sidecar); every accept runs the same
command path the user could click (structurally true — proposals are transactions);
deterministic offline suggesters first, model brains second, always falling back silently.

---

## T4 — Explicitly refused

One line each: what refuses it, and the lotus-clean equivalent if any.

| Liv feature | Refused by | Lotus-clean equivalent |
|---|---|---|
| Two-layer tabs, typed tabs, tab groups, composers, parked tabs, tab snapshots, superspaces | interface: "No tabs — ever"; Lesson 2 (two tab systems grew because one existed) | One lens at a time, stateless switching; saved views in the sidebar |
| Workspaces / Spaces / vault switcher / metadata stamping | One window, one box (single-writer log); The System Arrives Designed | project/area are reference properties; a "workspace" is a saved view; the clerk proposes the project reference from context — visibly |
| Multi-window, split panes, detachable panels, parked rails | Banned list (interface) | One window; the capture popup is the only floater |
| Themes, appearance flavors, font pickers, density settings | Materials: "no custom fonts, ever"; "there is no theme" | System light/dark, SF Pro, SF Symbols |
| Hash-stable 12-hue value colors, per-workspace accents, emoji pickers | Color: one accent meaning three things; five status dots; no pill rainbow | Text + small tinted dot |
| Command palette; commands as searchable faceted objects | Decided 0.2: no palette, no overlay | Menu bar + the fixed keyboard map; ⌘F searches entities |
| Rebindable hotkeys, per-property shortcut maps (D21) | Settings budget; "no chord does different things on different surfaces" | Fixed map; macOS App Shortcuts already answers rebinding (the OS answers → no setting) |
| Settings window, searchable settings, per-vault toggles, startup-behavior options | Banned: "a settings window"; the budget rule | Menu-bar item; the four budgeted settings are the whole list; lotus opens to Today |
| Dashboard / Mission Control widget boards, widget registry, habit widgets | "No view builder"; Today is the orientation surface | Today, plus saved views |
| View builders, DataViewBuilder, embedded live query-blocks in notes | Fenced authoring surfaces; no formula fields; the embedded-editor failure mode | Save the on-screen query (bookmark); a note references the saved view as a pill that opens the lens |
| Files-as-truth vault, .md mirror, frontmatter write-through, .base/.canvas interop, file watcher, self-write suppression | Persistence: the log is the disk truth; the stale mirror failure mode | Import once (external-id dedupe) + export service; foreign bytes stay foreign, by reference + hash |
| Embedded mini-browser, webview tabs, save-as-new-link banner | "No embedded webview in the first release"; librarian | Link entity; Open launches the browser |
| Embedded Office editing (docked Word pane) | Librarian rung 4; "no rung five" | Open externally; changed hash re-extracts |
| Google Calendar two-way push sync (etags, 412s) | "Sync engines are where unified information systems go to die" | Native events now; one-way ICS import when the fence opens (T2 #43) |
| Watched-folder auto-import, background pollers, 5-minute suggestion toasts | "Nothing runs on a timer"; absence creates no debt | The sweep at open; proposals queue silently |
| Badges, amber halos, per-workspace dots, hover-reveal AI heads | Banned: badges anywhere but the inbox count; hover-only affordances | The inbox count — the only badge in the application |
| Persistent AI chat sessions, per-chat memory, model pickers per chat, chats-as-notes | "No chat silo" | Answers are cited entities; actions are proposals; the surface is stateless |
| Auto-accept, unattended automation, webhook triggers, automation builders | "No silent mutation"; auto-accept fenced | The proposal queue; agents draft, the user confirms |
| Write mode (tasks as an editable markdown buffer merged back by title match) | New-interaction-model smell; uniform grammar | Capture + clerk for bulk entry; board/list gestures for edits |
| Second/third cleanup surfaces (Assist panel + Inbox + floating pill) | The inbox is the shell's one non-view surface | All suggestions are proposals in the one inbox |
| Favorites pill rows, SlotsBar, bookmark rails, pinned sections | Lesson 1: chrome scatters unless gathered — one sidebar | Saved views in the sidebar |
| Focus/zen mode toggle | Opinions over options; each surface has a density budget | Today and the editor are already the calm surfaces |
| Semantic-search settings seam (honest stub) | Settings budget; no speculative knobs | The answerer is the semantic door, when it earns it |
| Extensions gallery ("Browse extensions"), custom department tabs | "No plugin gallery" | — |
| Naming collision prompts, filename sanitization, path caches | Names are cells; ids are identity; no filesystem coupling | Duplicate names are legal; pickers disambiguate by context |
| Web/no-Tauri fallback runtime | Milestone-4 decision: macOS-native shell | — |
| AI subscription proxy / per-user caps | Liv's business model, not lotus's; "no model marriage" either way | BYO key in the Keychain behind a socket |

**Deferred, not refused** (candidates that must justify their existence): graph lens
(vault-wide and local), gallery, timeline, board-vs-list for Today, outline pane,
back/forward navigation history, ghost autocomplete, time tracking, habit projections,
day-view calendar, email integration, ICS feeds (fenced), external agent socket,
auto-accept policy.

---

## Cautionary tales worth keeping from Liv

Liv's docs are a graveyard map. The scars worth remembering, beyond those already named
in `interface.md`:

1. **Dual sources of truth rot.** Liv's DB + .md mirror needed a 2.5-second self-write
   suppression window because its own file watcher caused an app-wide freeze loop, plus
   path caches to survive renames, plus double-indexing fixes. Lotus's one log makes the
   entire bug class unconstructible. Never add a second truth "for interop" — import/export instead.
2. **Decided-removed features kept shipping.** Liv's dual layout modes and second tab
   system were decided dead but still in the code at handoff. When lotus decides, the
   code changes in the same milestone.
3. **Silent scoping and silent caps destroy trust.** Liv had results silently
   workspace-limited and a silent 30-item cap — both called out as failure modes. Lotus
   queries are explicit data; keep counts true and scope visible.
4. **Metadata vocabulary drifts; audit modules follow.** Liv grew a whole audit/cleanup
   apparatus ("Analyses" vs "analysis") because values were invented freely. The
   gazetteer + merge-on-definitions is the structural prevention; the audit proposer
   (T3 #11) is the repair.
5. **Deterministic suggestion ids were load-bearing.** Liv's dismissal memory worked
   only because ids were derived from (kind, target, value). Lotus's declined sidecar +
   duplicate-drop is the same guarantee, structurally. Preserve it when writing proposers:
   the same fact must produce the same proposal.
6. **UI state persisted as content becomes junk data.** Liv minted a note per opened
   surface tab and later needed a one-time archival migration. The constitution already
   forbids it (transient UI state is never an entity) — hold that line in the shell.
7. **Webview editors bite.** Liv's WKWebView editor had an unresolved duplicate-caret
   bug with a designed-but-unverified fix. The lotus editor is native; do not smuggle a
   webview in for markdown niceties.
8. **Timezone discipline converged.** Liv learned string-based wall-clock date handling
   the hard way; lotus's civil DateTime (packed wall-clock + date-only flag) is the same
   lesson pre-paid. Never round-trip through instants.
9. **The merge policy for external data is the entity split.** Liv's ICS/Google re-sync
   preserving user metadata on remote-owned events is exactly "the entity owns the
   meaning, the source owns its fields." When the calendar fence opens, keep it verbatim.
10. **Prompt injection defense is the write gate.** Liv's rule — never auto-chain a write
    off untrusted read content — is enforced in lotus by construction: the only write any
    model reaches is quarantine.
11. **Owner-fenced items stay fenced.** Liv reserved several decisions for its owner
    (typed-tab menus, metadata backfill, bulk link import mechanics). The lotus versions
    (T2 #40, T3 #16) should likewise be confirmed with Konrad before building — stub,
    don't invent.