# P14 Tasks v2 / Calendar re-base / Contacts — the "mount the built kit" phase: the board lens finally MOUNTS (columns = the status vocabulary, drag = the existing `set(status)` command, tile = the no-status `ObjectTile` by construction, Done folded via `completes`) with manual within-column ordering DEFERRED because it alone needs a new core primitive; the Schedule + Cards lenses ship as client-side re-groupings of the one task pool; the Calendar sheds its Liv-holdover mini-month rail and re-lays-out to bp9's header ‹ ›+Today with the day-panel "Open daily note" footer wired to the landed P12 seam; and Contacts ships as a near-zero-novelty surface (person list = `ObjectRow`, the one shared `InspectorPane`, a `create_person` twin) whose ONLY real core cost is a minimal additive contact-fields seed — every quick-entry token, saved-view substrate, AI leg, Google sync, time-tracker and habit refused or deferred with a named reason, the whole phase riding the P11.5 grammar kit with ONE small services seed (contact fields) and ZERO lotus_core change

Building on the landed P11 amended spine (design/p11-spine-model.md — the status
vocabulary via `lotus_status_options_at`/`for_types`/`hue`/`completes`, the
role-typed date positioning set `{date, due}`, the recurrence engine with virtual
occurrences + exceptions-as-entities), the landed P11.5 grammar kit
(design/p11.5-grammar-kit.md — `RowKit` `ObjectRow`/`ObjectCard`/`ObjectTile`, the
V3 `InspectorPane` + `DigitMap` + anchored `InspectorEditors`, `Hues`/VALUE_HEX),
P12 (design/p12-capture-daily-inbox.md — the daily-note seam
`lotus_open_daily_note_at`, whose calendar day-panel footer was **explicitly
DEFERRED to P14**), and P13 (design/p13-search-v2.md — the search v2 DSL + facet
engine reused here for Contacts filtering and "Open as filter"). P14 is the
**BP-6 + BP-9 pass**: bp6-tasks.html (35 annotations, "ClickUp metadata logic")
and bp9-calendar-contacts.html (34 annotations, "the light pair").

**P14 is large — three surfaces — but overwhelmingly SHELL over seams that
already exist.** The four readers verified that the board's every substrate is
landed (`ObjectTile` with no status parameter by construction; columns =
`statusVocabulary` in board order; **drag = the already-shipping
`model.set(id,"status",name)` → `Value::Select` command**, the same write the
checkbox and inspector picker already issue; Done folds off the `completes`
bit); that Schedule + Cards are client-side re-groupings of the one already-loaded
task pool (`ObjectCard` exists, the `{date,due}` role set is P11 law); that the
calendar's re-base is a **deletion** (the mini-month rail + "My calendars"
checklist) plus a re-layout over the existing `topBar`/`WeekTimeGrid`/`buildByDay`
plumbing, and the day-panel daily-note footer is a **single unwired call to the
complete P12 seam**; and that Contacts is assembly from settled grammars
(`Surface.contacts` already occupies its enum slot — no nav-budget hit).

**The entire P14 Rust budget is ONE small additive services seed** — the contact
profile-field seed (`seed_contact_fields`: role/org/email/phone on an additive
guard, §3.2, failing-test-first per memory: test-drive-core-changes) — plus, IF
and only IF the owner pulls manual kanban ordering into scope, the **Placement
entities** primitive (a genuinely new append-only core type, §3.1,
failing-test-first). The recommendation is to **defer Placement** and ship the
board without hand-drag ordering, honoring feature-map #18's "the board is a
candidate renderer that must justify itself, then build." Everything else — the
lens switcher, the board render + drag, Schedule/Cards, the calendar re-base, the
daily-note wiring, the Contacts list + inspector — composes shell-side from seams
that ship.

Every visible slice is **mockup-first**: a static exhibit cloned 1:1 from bp6/bp9,
re-hued to the lotus palette (lake green `#2f7d6b`, never the blueprint
blue/violet), approved against the blueprint before a line of Swift (memory:
copy-liv-exactly / copy-exactly). The core-ish slices (the contact-fields seed;
Placement if built) are **failing-test-first**. What varies per lens is data and
grouping key, never the row/tile/card anatomy.

## 0 · Owner decisions (recommendations, before mockups)

Five forks genuinely fork the design before mockups; each is written into §1–§5
with a recommendation. The parent may confirm or override; the recorded deltas
hold either way. See `ownerDecisions` for the compact form.

- **D1 — Board manual ordering: DEFER Placement entities (recommended).** The
  board ships with cross-column drag = `set(status)` (the free existing seam);
  cards sort by the existing due-ascending key within a column. Within-column
  hand-drag ordering needs Placement entities — a NEW core primitive that does
  not exist — and is deferred until real task volume justifies it (feature-map
  #18). If pulled in, it is failing-test-first core work (§3.1).
- **D2 — Contacts surface: SHIP (recommended).** bp9 a1 calls it "near-zero
  novelty" by design; the `Surface.contacts` enum slot is already spent (no
  budget hit); the only real cost is the contact-fields seed (§3.2). Ship it
  thin — list + inspector + `create_person` — and defer the groups rail, the
  in-body card block, and vCard import.
- **D3 — Saved views: built-in Focus shortcuts only; DEFER the savable entity
  (recommended).** Ship Today/Upcoming/All-tasks + project-scope as hardcoded
  filter presets (the current All/Open/Done idiom, no substrate); DEFER both the
  `.base` view-file substrate AND the user-savable bookmarked-query entity,
  matching P13's recommended-deferral. The bookmarked-query entity (a `props::QUERY`
  cell + a sidebar "Saved" row, needs no substrate — feature-map #21/#28) is a
  cheap fast-follow the owner may pull in.
- **D4 — Calendar lens set: Month | Week | Day; REMOVE Agenda (recommended).**
  bp9 a3 ships exactly three lenses and blesses Day as "one column of the same
  [week] renderer" — Day is already built (`WeekTimeGrid([selectedDay])`, zero
  cost). Keep it. The current 4th `agenda` mode is a non-bp9 lotus artifact —
  copy-exactly DROPS it. (The brief item (d) said "Day defers"; bp9 a3
  supersedes — recorded delta §1.11.)
- **D5 — Task-field digit allocation (bp6 header OQ-i): a task-LOCAL block on
  digits 1–4 (recommended).** status(1)/date(2)/priority(3)/recurrence(4) form a
  task-local inspector block, distinct from the global search facet digit map —
  the inspector's `DigitMap` is already a per-surface resolve over the visible
  catalog, so a task-local ordering is natural and avoids collision with the
  search facet semantics (include→exclude→off). Owner-decidable.

## 1 · The load-bearing decisions

Each resolves a brief tension (a)–(h) with a recommendation and a RECORDED DELTA.
Precedents cited: P13/§1.2 and P11.5 §8 deferred the views/files substrate; P12
§1.3 / P13 §1.5 render AI legs as inert frames (proposals are a different
surface); P11 ruled recurrence exceptions are entities.

### 1.1 The board lens SHIPS as a mount of the built kit. (tension a, part 1)

**SHIPS.** The board is the P14 pass by prior explicit assignment: grammar-kit §8
("the board is BP-6's pass; the components ship, their surfaces don't exist yet")
and p11-spine §9 ("the board lens — columns off `status_options_for`, drag,
fold-Done via `completes` — P11.5/P14 mount these seams verbatim"). feature-map
#18's justify-then-build gate is **satisfied**: P11 landed the whole board
substrate deliberately so P14 mounts it. **RECORDED DELTA (a-1):** the board ships
as ONE lens in a List/Board/Schedule/Cards switcher over the ONE task pool
(bp6 a6), never replacing the list; the current `TasksView` (Window.swift:3517)
is a status-grouped *list* with no board — the board is a horizontal re-layout of
the same `statusVocabulary` grouping key, plus `ObjectTile` cards and the drop
seam. No new renderer component (`ObjectTile` exists, RowKit.swift:311); no new
core.

- **Columns = the user's status vocabulary in board order** (bp6 a8):
  `statusVocabulary(model, kind:"task")` (RowKit.swift:345) derives the ordered
  options from the one `status` property, filtered by each option's `for_types`,
  sorted by `boardOrder` — the exact key `TasksView` already groups sections by
  (Window.swift:3560-3575). The column `+` births a task with that column's status
  = `createTask` then `model.set(id,"status",columnName)`.
- **The tile carries NO status chip — by construction** (bp6 a9): `ObjectTile`
  has no status parameter in its initializer (RowKit.swift:308-310, "the
  prohibition IS the initializer"); it carries title + person + one dateText +
  tier only. The column carries the status; the tile cannot show it even by
  mistake. This is the lens-aware "status grayed on the board" budget (bp6 a29)
  enforced for free.
- **Done folded** (bp6 a13): `completes`-true columns render as a collapsed rail
  showing just a count; the unfold is session-only ephemeral shell `@State` (no
  persistence needed). Terminal-ness is already data (`OptionRow.isTerminal` reads
  `completes`, Window.swift:43).
- **Empty columns keep their header** (bp6 a33): free, because `statusVocabulary`
  returns ALL options regardless of membership.

### 1.2 Board drag = `set(status)` — the seam already exists. (tension a, part 2)

**SHIPS, zero new core.** Dropping a tile in another column is ONE metadata write
— `model.set(id,"status",name)` → `content::set_property` writes `Value::Select`,
undoable through the append-only log (Window.swift:388-390; the checkbox
`taskStatusToggle` at :2560 and the inspector picker already issue exactly this).
Board drag = a SwiftUI `.onDrop` invoking `model.set` with the destination
column's option name. A "no status" object gains one on first drag out (bp6 a10)
for free — the first `set` writes the cell. The empty/last slot of each column is
a visible drop target that names the write it will make (bp6 a33). **No new FFI,
no new Op, no core change.**

### 1.3 Manual within-column ordering DEFERS — the one thing needing a new core primitive. (tension a, part 3)

**DEFERS (recommended, D1).** bp6's annotations spec only cross-column status
writes (a10); within-column reordering is unspecified there but implied by a
kanban. It needs **Placement entities** — feature-map #18 names it exactly
("manual order = Placement entities, working:true"). A grep of core/services/ffi
finds no Placement primitive; the seeded `order` NUMBER property serves only
workspace-tree order and status-**column** order (lib.rs:548, :227), never
per-card order. **RECORDED DELTA (a-3):** P14 board cards sort by the existing key
(due-ascending, nil-due last — the current `TasksView` sort, Window.swift:3570),
NOT by hand-drag. Placement is a genuinely new append-only core type (an order +
a reference to the placed entity + column context) and, per the standing rule for
core changes, would be **failing-test-first** (§3.1) — deferred to a dedicated
pass until task volume justifies the board (feature-map #18's gate). Cross-column
drag (which the owner sees) ships now; manual sequencing (which nobody has asked
for) waits.

### 1.4 Board column management SHIPS; option retirement defers to P19.

**SHIPS** (bp6 a8/a33): column rename/reorder/completes-edit edits the P11 status
option entities' `name`/`order`/`completes`/`hue` cells through the ordinary
`set` seam plus the landed `lotus_add_status_option` (ffi:1500) for new columns —
reserved for this board pass by grammar-kit §8 ("the BP-6 board pass owns
ordering/renaming/completes editing"). **DEFERS:** option *retirement* (removing a
vocabulary entry that live cells still reference) — p11-spine §9 assigns it to
"the settings/vocabulary shelf's conflict moment, P19."

### 1.5 The Schedule lens SHIPS as a client-side grouping of the pool. (tension b)

**SHIPS, zero core** (bp6 a16). Reserved for P14 by p11-spine §9 ("P11 deliberately
makes the set `{date, due}` so P14 can render either without core change"). The
buckets (Overdue / Today / This week / Later) are a pure re-group of the
already-loaded task rows by `due` — the same client-side-segment pattern P8 §5.3
established and `CalendarView.buildByDay` uses to bucket by day. Each row carries
`due: Int64?` already (Window.swift:71). **RECORDED DELTA (b):** ship bp6 a16's
"both, ghosted" — role=due task dates render live, role=calendar dates from other
objects render as ghost context (the `{date,due}` positioning set already supports
this); lookup roles (valid-until/occurred/purchased-on) NEVER appear
(dateroles.rs proves it). **Drag-an-entry-to-set-due** rides the existing
`set(due)` seam but is DEFERRED with the board's within-column drag and the
calendar's drag-to-reschedule (a coherent "reschedule gestures" follow-slice) —
the Schedule lens ships read-first.

### 1.6 The Cards lens SHIPS (cheap). Write-down mode + the token parser are REFUSED. (tension f)

**Cards SHIPS** (bp6 a15): `ObjectCard` (RowKit.swift:271) IS the card verbatim
(type + title + 2-line description clamp + ≤3 chips + `+N`, no status dot). The
component exists; the mount is cheap. The 2-line clamp reads a `description` text
property (feature-map #30); where absent the clamp is simply empty (empty fields
never render).

**Write-down mode + the `due:`/`!high`/`@name`/`#tag` token parser are
DOUBLE-REFUSED** (bp6 a7/a19/a20/a21). (1) feature-map #20: "refuse the parser at
capture — a token syntax is a type-picker in disguise; the clerk proposes dates
and mentions from plain text, extended with a priority-word pattern." (2) The
whole Write-down surface is feature-map T4 "write mode." **RECORDED DELTA (f):** no
title-token parser ships; the tasks quick-add stores the title literally (as it
already does — `createTask` then `set(name)`, no parsing, Window.swift:3674). The
Write-down lens is **OMITTED** from the switcher (it exists only to host the
refused parser + a sync-to-pool step; rendering an inert mode invites the
reduction). The clerk's priority-word/date/mention proposals are the sanctioned
substitute and land in the P16 AI pass, entering the ONE inbox — not P14.

### 1.7 Saved views: built-in Focus shortcuts ship; the substrate + savable entity DEFER. (tension c, D3)

The `.liv/views/*.base` view-file substrate (bp6 a4 "each row is a .liv
view-file", a28 the view-as-object filter engine, a29 the fields-shown picker,
a31 presets/Alt+S) and the editable **[View] rail segment** (bp6 a22/a28) DEFER —
they lean on the views/files substrate lotus refuses (feature-map T4:308;
interface.md 0.3 "a second source of truth"), the exact fence P13 §1.2 and P11.5
§8 already recorded. **RECORDED DELTA (c):** carry P13 §1.2 forward. The
navigate-then-refine left rail's **Focus section (Today / Upcoming / All tasks)**
ships as **built-in hardcoded filter presets** (the current All/Open/Done segment
idiom — no substrate, no persisted view-object); **project scoping** = a
`project`-reference filter on the P13 search DSL applied via chip-click (bp6 a3,
"leaf-only" project rows are a display concern). The bp6 saved-views tree (a4/a5),
the presets row (a31), and the [View] segment (a22/a28/a29) render as
**reserved/disabled frames** (the P11.5 §9.6 ship-disabled precedent) so the
layout diffs clean when the substrate lands. The **savable bookmarked-query
entity** (a `props::QUERY` cell + a sidebar "Saved" row — feature-map #21/#28,
needs NO substrate) is **recommended DEFERRED** to hold the budget but is a cheap
fast-follow the owner may pull in (owner call D3). If the left rail is a P14
budget risk, it may ship as just the Focus shortcuts inline (matching today's
`TasksView`, which has no rail at all) — the full navigate-then-refine rail is
itself deferrable.

### 1.8 The [Selection | View] segmented rail: Selection ships, View defers. (bp6 a22 / bp9 a16)

The owner's 2026-07-09 merge ruling (bp6 a22, a header LOCK): the right rail is
SEGMENTED [Selection | View]; focusing an object auto-switches to Selection; never
two competing property editors. **Selection = the P11.5 V3 `InspectorPane`, which
exists** and is already embedded on selection in `Calendar.swift`:181 — SHIPS on
both Tasks and Calendar (auto-switch-to-Selection-on-focus is shell behavior).
**[View] leans on the views substrate — DEFERS** (§1.7) as a reserved/disabled
frame. On the Calendar, lotus's current day-panel serves as the no-selection empty
state (bp9's [View] rows — lens/week-starts/show-tasks — live for now as local
`@AppStorage` view state, never a `.base` cell). RECORDED DELTA: no view-as-object
in P14.

### 1.9 AI legs render as inert frames; the behavior is P16. (tension g)

**DEFERS to P16; static/inert frames** (bp6 a30 Agents button + count, a34 plan
preview, a35 Approve/Reject per card; the row `✦` wand). Every AI write is a
proposal by law (interface.md 0.3); proposals enter the ONE inbox (P12), not the
tasks surface — the exact ruling P13 §1.5 recorded for the palette. **RECORDED
DELTA (g):** the Agents button + plan-preview overlay + per-card approve/reject
render as reserved/inert frames reusing the already-reserved amber
(`Theme.warning`); NO suggestion seam, NO wiring (the ship-disabled precedent).
The count may be computed quietly but nothing executes. The row `✦` maps to the
clerk proposer (Alt+M) in P16. No second mutation door on the tasks surface.

### 1.10 The workroom pop-out: the existing open-as-tab IS the lotus workroom.

bp6 a11/a12/a32 add a `⤢` pop-out "workroom" (body + checklist + activity), a
mirror-contract surface. bp6 a12 itself says "quick edits never need it."
**RECOMMEND** the existing single-click-selects / double-click-opens-as-tab path
(`openRow`/`openEntityTab`, Window.swift:3617) IS the lotus workroom equivalent
(matching interface.md's grammar: click selects, Enter/double opens) — ship NO new
pop-out surface. Its checklist implies subtasks (deferred, P8 §8). J/K move +
Space-opens are a small keymap add if wanted. RECORDED DELTA: no new pop-out
component in P14.

### 1.11 Calendar re-base: REMOVE the mini-month rail + "My calendars"; re-layout to bp9; keep Month/Week/Day, remove Agenda. (tension d, D4)

**SHIPS (removal + re-layout).** bp9 a2 navigates entirely from the header
‹ ›+Today (T) with **no mini-month rail**; the only left column bp9 draws is the
Google-subscription checklist, which is a different (refused) device. lotus's
`CalendarView` carries a 232pt left rail — the mini-month navigator
(Calendar.swift:298-374) + the "My calendars" per-kind checklist (:253-259) — a
Liv holdover the owner flagged for removal, and p10 §6.6 itself pre-deferred the
mini-month as polish. **RECORDED DELTA (d-1):** DELETE `rail(_:)` and its `showRail`
gate; navigation survives — the `stepMonthOnly`/`goToday` logic already lives in
the `topBar`'s ‹ Today › chevrons (Calendar.swift:416-428). The "My calendars"
kind filter drops to defaults or a lighter control (the `@AppStorage show*` flags
persist as local view state, no rail).

**RECORDED DELTA (d-2), the lens set (D4):** keep **Month | Week | Day**; REMOVE
the **Agenda** mode. bp9 a3 ships exactly Month|Week|Day and defines Day as "one
column of the same [week] renderer" — which lotus already built
(`WeekTimeGrid([selectedDay])`, Calendar.swift:119-128, zero cost). feature-map
#23's "day view waits for a reason" is **superseded by bp9 a3** blessing Day as the
n=1 week renderer at zero cost — record the reversal. The current 4th `agenda`
mode (Calendar.swift:14, `agendaBody`) is a non-bp9 lotus artifact that
copy-exactly DROPS. Week = "the same renderer at another density" is already
realized (`WeekTimeGrid`, "7 or 1 columns"). Owner-decidable if he prefers the
brief's "defer Day"; recommend the bp9-faithful three-lens toggle.

### 1.12 The daily-note footer: wire the day panel to the landed P12 seam. (tension d, part 2 — the headline P14 wiring)

**SHIPS, zero new core.** The P12 seam `lotus_open_daily_note_at(path, date_civil,
workspace)` (ffi:1365) is complete and idempotent (routes through
`get_or_create_daily_note` in ONE session so two entry points never
double-create), exposed as `BoxModel.openDailyNote(dateCivil:workspace:done:)`
(Window.swift:494). `Calendar.swift` currently has ZERO daily-note reference —
the day panel's only footer is a "new event this day" button (:649). **RECORDED
DELTA (d-3):** the day panel gains an **"Open daily note" footer** →
`model.openDailyNote(dateCivil: selectedDay*10000, workspace:) { id in open(id) }`
(bp9 a8/a9, at ⌘⌥D — the owner-chosen shipped-Liv chord, NOT bp9's Ctrl+D, per
P12 D2). Additionally (bp9 a8/a9): (a) today's month cell reads as a daily-note
page — a "TODAY · daily note" tag + today's events + a **live first-lines
preview** of the note's body (a small new read of the note entity's content
spans); (b) **clicking a day NUMBER** opens/creates that day's note (the exact
entry point P12 deferred — `get_or_create_daily_note` already accepts an arbitrary
date); (c) a **dot beside the number = the note exists** (a cheap per-day
existence check: daily-note-typed entities whose `date` cell matches each rendered
day, carried as a `Set<Int64>` alongside `buildByDay` — computed shell-side, no
wire, create ONLY on click). The "Today's daily note" affordance maps to the same
call. Pure shell wiring over an existing seam.

### 1.13 The calendar month-grid renderers: span bar, ↻ marker, in-grid task checkbox, cancelled strikethrough, off-calendar strip. (bp9 a11–a15/a17/a18)

All ship over LANDED substrate; the only new visual work is the **multi-cell span
bar**. **RECORDED DELTAS (d-4):**
- **Event chip** (bp9 a11): select→inspect, double-click→open, **drag→date-write**
  = `model.set(id,"date"/"due", newCivil)` (a `Value::DateTime` command mirroring
  the inspector's date row, toast+undo). Past-chip dim + hover tooltip are polish.
- **The 3-day span bar** (bp9 a12/a17): the start+end primitive is LANDED
  (`core/src/value.rs` `DateTime.end: Option<i64>`, "end==start collapses to
  None"; `DateTime::span`). P14 build is PURELY the renderer — draw one continuous
  bar across covered cells (breaking per week row, one click-target) with drag-grips
  that write `DateTime.end` via the inspector's date-row command; clearing end
  collapses to a single-day chip. This is the "unanimous #1 fix" stress-test of R1.
- **Recurring ↻ chip** (bp9 a13): the engine is landed; `buildByDay` already
  unions occurrences and draws the SERIES entity on each occurrence day
  (Calendar.swift:217) so a click selects the one underlying object. Only the `↻`
  glyph marker on computed instances is a small renderer add.
- **Task-due checkbox chip** (bp9 a14): add the in-grid checkbox so completion
  works in place — `taskStatusToggle` writes status in one command (already wired
  in the day panel, :685). Neutral hue (dates are facts, not values).
- **status=cancelled strikethrough** (bp9 a18): a small chip-renderer delta;
  never a delete.
- **Off-calendar lookup strip** (bp9 a15): lookup roles
  (valid-until/occurred/purchased-on) stay OFF the grid (already law + tested,
  dateroles.rs). An optional, dismissible explainer strip lists them with an "Open
  as filter" button → the P13 ⌘F palette pre-filled (e.g. `valid-until<2027-06`).
  The load-bearing part (they never position) needs no work; the strip is polish.

### 1.14 Contacts SHIPS as a near-zero-novelty surface. (tension e, D2)

**SHIPS (recommended).** bp9 a1 is decisive: "Calendar and Contacts are SEPARATE
rail extensions... pure consumers of settled grammars with near-zero novelty."
**Budget check PASSES:** `Surface.contacts` already exists in the enum
(Chrome.swift:19, label "Contacts", symbol "person.2") but is unrouted — it falls
to `ExtensionStub` ("Coming soon", Window.swift:1287) — so wiring it is NOT a new
Surface budget hit; the slot is already spent. The surface is assembly: a
person-filtered list (`model.rows(...).filter{kinds.contains("person")}` — the
exact `TasksView` idiom) rendered as `ObjectRow` (bp9 a23: avatar-as-type-signal +
name + ONE anchor chip [org else first subject] + modified, 36px, no status dot
since Steven has no status) + the shared `InspectorPane` on selection (bp9 a26:
"the panel on the right is the one and only property editor") + the standard
`Editor` for an opened contact's `.md`. **The ONE real gap:** the `person` type is
seeded EMPTY (lib.rs:781, `("person", &[])`) — role/org/email/phone are referenced
in `InspectorLayout.coreTables["person"]` but NEVER seeded, so they silently
vanish from the inspector (a name absent from the catalog doesn't render). §3.2
seeds them minimally — the phase's one core-ish change. New-contact birth = a
`create_person` twin of `create_event`/`create_task` (the deliberate "New contact"
button, bp9 a22), born as `.md` under `library/contacts/` (D25), name focused for
rename, inspector opened with empty profile rows (D11: a name alone is a complete
contact, zero fill-pressure).

**What DEFERS within Contacts** (bp9): the **groups rail** (a20, "a group = a saved
filter over the people pool") rides the saved-view track (§1.7) — ship as
built-in filter shortcuts + the P13 filter box, or static frames; the **in-body
contact-card projection block** (a27) is authoring-adjacent (feature-map T4:308
fences "embedded live query-blocks in notes") — DEFER, or ship ONLY as a strictly
read-only mirror with a fixed field set (no per-template picker) if the owner
wants it; the **person-chip hover peek card** (a25) is an AI/hover affordance —
DEFER (the `@`-mention autocomplete writing the people reference is the shippable
half); **vCard/macOS-Contacts import** (feature-map #45) is a T2 integration —
DEFER; the **file-path crumb** defers by the same files-as-truth ruling as P11.5
§9.2. The `✦` suggest action ships static (P16).

### 1.15 Time tracking + habits DEFER. (tension h)

Both DEFER; nothing ships. feature-map #22 (time tracking, "build when the owner
asks twice") and #16 (habits, "deferred until daily use demands"). Neither appears
in bp6 or bp9. No time-entry entities, no single-active-timer invariant, no habit
check-ins/streaks/heatmaps.

### 1.16 Recorded palette-law & naming deltas that cut across both surfaces.

- **HUE COLLISION (palette law #25, throughout bp9):** the per-calendar
  subscription hues (a5–a7), per-group dots (a20), and per-avatar tints (a23)
  violate lotus's one-accent budget ("calendars are distinguished by view, not by
  a hue system"). **RECORDED DELTA:** distinguish by name/checkbox/view, never
  color; the avatar is a single neutral/accent, not a per-contact hue; chip hues
  obey the frozen VALUE_HEX / status-dot budget (`Hues`), never the blueprint's
  free hues. Do NOT build on the stale hardcoded `statusColor`/`priorityColor`
  (Window.swift:2423/2578) — read hue from `OptionRow.hue` via `StatusDot`.
- **Google two-way sync (bp9 a6/a31, OQ-A) is beyond even the ICS fence**
  (feature-map #43): ship the sync badge + read-only `googleId` row **STATIC
  only** — no OAuth, no push/pull, no conflict UX. When the fence opens, the
  conflict resolution aligns with AI-as-suggester (a proposal card in the P12
  Inbox Tidy queue, P16), never a silent overwrite.
- **OQ-B recurrence exceptions — lotus already ruled the OTHER way.** bp9 a32
  recommends "override-on-parent"; the P11 engine implements exceptions as
  **ordinary entities** (feature-map #19; MEMORY). **RECORDED DELTA:** editing/
  skipping a single occurrence writes a small exception ENTITY, not an override
  cell on the parent `.md` — bp9's recommendation is reversed per the constitution
  (append-only, no shadow-copy materialization). No new ruling needed.
- **OQ-C daily-note template — already resolved in P12:** a static Agenda heading
  ships now (content.rs `daily_template`, which cites bp9 OQ-C); the live-agenda
  projection block is P16. No P14 work.
- **Naming deltas:** bp9's inspector "people" row + violet "calendar" date-role
  pill vs lotus's seeded `attendees`/`people-links` reference + `date` property —
  record the DISPLAY labels the surfaces show (recommend "people" / "calendar" as
  display labels over the seeded properties); bp6's `!p1`/`!p2`/`High` priority
  naming vs lotus's low/med/high select (a 4th "urgent" arrives additively later,
  P8 §3.1); bp6's `T1`/`T2` tier NUMBER is distinct from the priority select —
  both exist, both render (tier neutral, never VALUE_HEX-hued).

## 2 · The surfaces

Every row/tile/card is a P11.5 kit component; every property editor is the one
shared `InspectorPane`. No new component is invented — the novelty budget is spent
on mounts, drop targets, the span bar, and the daily-note wiring.

### 2.1 Tasks v2 — the lens switcher over ONE pool

A `TasksView` re-shaped to host a **lens enum** (`@State`, ephemeral — NOT a
persisted view-object; D3) driving `List | Board | Schedule | Cards` (Ctrl+1..4;
Write-down omitted, §1.6). The `everything → filter{task} → group` pipeline
(Window.swift:3529) is shared by all lenses; only the grouping key + layout change.

- **List lens** (bp6 a14) — already the shipping lens; rows ARE `ObjectRow` (the
  34px BP-7 budget: kind-signal + title + exactly ONE anchor chip
  [project→subjects→people→due] + **`StatusDot`** + modified). The list is the ONE
  lens that shows the status DOT (a fact-signal, not a chip) — the board tile drops
  even that (the column carries status). Grouped under `statusVocabulary` section
  headers in board order. Chip-tap = FILTER (posts `.lotusSearchFor`), never
  select. Keep verbatim; confirm it is `ObjectRow` at budget.
- **Board lens** (bp6 a8–a13) — horizontal columns = `statusVocabulary` board
  order; each column is a `LazyVStack` of `ObjectTile` (no status) sorted by
  `dueKey`; the column `+` births a task with that status; `.onDrop` per column
  invokes `model.set(status)`; `completes`-columns fold to a count rail (session
  `@State`); empty columns keep headers. Column management (rename/reorder/
  completes) edits the option entities via the inspector/`lotus_add_status_option`.
- **Schedule lens** (bp6 a16) — the same task rows re-bucketed by `due` into
  Overdue / Today / This week / Later (client-side, `Civil.todayYMD` at
  Window.swift:837); calendar-role events ghosted; lookup roles never appear. Rows
  are `ObjectRow`. Drag-to-set-due deferred (§1.5).
- **Cards lens** (bp6 a15) — `ObjectCard` gallery; description 2-line clamp; ≤3
  chips + `+N`; no status dot (grouping carries state). Cheap mount.

The right rail is the segmented [Selection | View]: Selection = `InspectorPane`
(auto-switch on focus, mirroring `Calendar.swift`:181); View = reserved frame
(§1.8). The quick-add stays literal (no token parsing, §1.6). The footbar mirrors
the P13 search-palette footer (bp6 a27 — "the two surfaces teach each other";
factor a shared KeyCap-pair helper). The Agents button + plan overlay + row `✦`
render inert (§1.9).

### 2.2 Calendar — re-based to bp9

`CalendarView` with `rail(_:)` DELETED. The header (`topBar`) carries: title +
‹ ›+Today (T) nav, the Month|Week|Day toggle (Agenda removed, §1.11), and the
`+ New event` accent button (bp9 a4 — quick-create popover: title · date · time;
the always-visible "will save to → library/events/" destination line is a
files-as-truth affordance, DEFER with the crumb per §1.14/P11.5 §9.2, or ship the
static destination text only). `WeekTimeGrid` serves Week and Day (n=1). The month
grid (`monthBody`/`DayCell`) gains the §1.13 renderers (span bar, ↻, in-grid task
checkbox, cancelled strikethrough, off-calendar strip). The day panel gains the
§1.12 "Open daily note" footer; day-number click opens/creates that day's note;
the dot=exists marker; today's cell reads as a daily-note page with a live
first-lines preview. `rightColumn` swaps the day panel for `InspectorPane` on
selection (already wired, :181). `buildByDay` + occurrence windowing + `createEvent`
inherit unchanged.

### 2.3 Contacts — the thin surface

Route `Surface.contacts` → a new `ContactsView` (add `case .contacts:` to the
router at Window.swift:1262, no new enum case). Body = a person-filtered list of
`ObjectRow` (avatar-as-type-signal, one anchor chip = org else first subject, no
status dot until set) + the P13 filter box scoped to the person pool (type-to-filter
across name + properties; quiet one-liner empty state; ⏎ opens a single match) +
the shared `InspectorPane` on selection + the standard `Editor` for an opened
contact. A `create_person` birth verb (a `create_event` twin) powers the "New
contact" button (born `.md` under `library/contacts/`, empty profile rows). The
inspector renders role/org/email/phone (once §3.2 seeds them) + the R1-free date
rows (last-seen = `occurred` lookup [filterable, off-calendar]; birthday = `date`
role + yearly recurrence [auto-renders every Nov 2 with `↻` on the Calendar]) +
the universal status ghost (dashed until set) + the Connections/backlinks section
(already in `InspectorPane`). The `@`-mention path writes the people reference from
the contacts pool (chip and property are one fact); the peek card + groups rail +
in-body card block DEFER (§1.14).

## 3 · The minimal core work

**Rust budget: ZERO lotus_core change. ONE small additive services seed** (contact
fields, §3.2, failing-test-first). Placement entities (§3.1) are a genuinely new
core primitive that is **DEFERRED** (D1) — described here only so the failing-test-
first plan is on record if the owner pulls manual ordering into scope.

### 3.1 Placement entities (DEFERRED — the only P14 primitive, failing-test-first if built)

Manual within-column kanban order (§1.3) is the ONLY P14 candidate needing a new
core type. If built: a Placement is an append-only entity carrying an `order`
number + a reference to the placed task + a column/status context, with a
services op to read a column's ordered members and a `set`-style op to reorder.
Per memory (test-drive-core-changes), the **failing test is written first** (a
`services/tests` case: two tasks in one column reorder; the board reads the new
order; the log stays append-only), and the doc's reasoning is not trusted.
**Recommendation: DO NOT BUILD in P14** — the board ships with due-sort; Placement
waits until real task volume justifies it (feature-map #18). Zero core if deferred.

### 3.2 The contact-fields seed (services, additive guard, FAILING-TEST-FIRST)

The one shippable core-ish change. `person` seeds empty (lib.rs:781); §1.14 needs
role/org/email/phone to render. Add `seed_contact_fields` on its OWN additive
guard (the established pattern — `seed_priority`/`seed_event_fields` guard on a
sentinel property so older boxes gain the fields on open): create `role` (text),
`org`/company (text or reference), `email` (text), `phone` (text). `occurred`
(last-seen) and the `date`/calendar role (birthday) already exist. **The failing
test, written first:** a fresh box seeds the four properties; re-opening does not
duplicate them (idempotency); a person entity can carry all four cells. No new
core primitive — property seeding only — but test-worthy per the standing rule.

### 3.3 What stays shell-side (zero Rust)

The lens switcher, the board render + drag (`set(status)` exists), column
management (`lotus_add_status_option` exists), Schedule/Cards re-groupings, the
calendar re-base + all §1.13 renderers (span bar reads the landed `DateTime.end`;
`↻` reads the landed occurrence union), the daily-note wiring (`lotus_open_daily_
note_at` exists), the Contacts list + inspector + `create_person` (a
`create_event` twin over the existing create seam), and the daily-note-exists dot
(a shell-computed `Set<Int64>`). All compose over seams that ship.

## 4 · Swift decode shapes — additive, Optional, `try?`-safe

P14 adds **essentially no new wire shapes.** The decoder uses
`.convertFromSnakeCase` and `applySnapshot` decodes with `try?` (one missing
required key silently drops the whole snapshot, P11.5 decision 12), so any new
field is Optional with a defaulting accessor.

- **Contact profile fields** decode through the existing GENERIC cell path — a
  person's `role`/`org`/`email`/`phone` are ordinary cells on `EntityRow.cells`,
  rendered by the catalog-driven `InspectorPane`. No new `Codable`.
- **The span bar** reads `DateTime.end` (already decoded), **recurrence `↻`** reads
  the already-decoded `snap.occurrences`. No new field.
- **The daily-note-exists dot** is computed shell-side from `snap.everything` /
  `snap.dated` (daily-note-typed entities with a `date` cell) into a `Set<Int64>`
  of day-keys — **no wire field.** If a per-day existence probe proves too costly
  over the snapshot, the fallback is one additive Optional (`daysWithDailyNote:
  [Int64]?`) on the calendar window response — flagged, verified before any Rust,
  not assumed.

New shell-only state: the Tasks lens enum (`@State`), the board session
fold-set, the calendar lens (`@AppStorage`) — none is wire.

## 5 · Slice plan

Each slice is an independent commit: mockup-first where visible (a static bp6/bp9
exhibit re-hued to lotus, approved before Swift), failing-test-first for the one
core-ish slice (P14-CT). **P14 is large; it sequences a Tasks track (P14a–P14e)
before a Calendar track (P14f–P14h), with the Contacts track (P14-CT, P14i) able
to land in parallel** — the tracks share only the P11.5 kit and touch disjoint
files (`Window.swift` `TasksView` vs `Calendar.swift` vs a new `ContactsView`).

**Tasks track**
- **P14a — Tasks lens switcher + List convergence (MOCKUP-FIRST, no core).** The
  `List|Board|Schedule|Cards` switcher (Ctrl+1..4, Write-down omitted) over the one
  pool as an ephemeral `@State` enum; confirm List rows are `ObjectRow` at the 34px
  budget with the `StatusDot`; the built-in Focus shortcuts (Today/Upcoming/All) +
  project-scope chip-filter; reserved saved-view/[View] frames. Mockup: bp6 vtoggle
  + list + left rail (a5/a6/a14).
- **P14b — Board lens render + drag + fold (MOCKUP-FIRST, no core).** Columns =
  `statusVocabulary` board order; `ObjectTile` cards (no status) sorted by dueKey;
  column `+` births with status; `.onDrop` → `model.set(status)`; `completes`-fold
  rail; empty columns keep headers; the named drop-target hint. Mockup: bp6 board
  (a8/a9/a10/a13/a33).
- **P14c — Board column management (MOCKUP-FIRST, no core).** Rename/reorder/
  completes-edit of the status option entities via the inspector +
  `lotus_add_status_option`. (Option retirement stays P19.) Mockup: bp6 a8.
- **P14d — Schedule + Cards lenses (MOCKUP-FIRST, no core).** Schedule = client-side
  due-buckets (Overdue/Today/This week/Later, calendar-role ghosted, lookup off);
  Cards = `ObjectCard` gallery. Mockup: bp6 a15/a16.
- **P14e — [Selection|View] rail + footbar + AI-leg frames (MOCKUP-FIRST, no
  core).** Selection = `InspectorPane` (auto-switch on focus); View = reserved
  frame; the shared footbar (factored KeyCap-pair); the Agents button +
  plan-preview overlay + row `✦` as inert amber frames. Mockup: bp6 a22/a27/a30/
  a34/a35.

**Calendar track**
- **P14f — Calendar re-base: delete the rail + re-layout (MOCKUP-FIRST, no core).**
  Remove `rail(_:)` (mini-month + "My calendars"); header ‹ ›+Today + Month|Week|Day
  toggle (Agenda removed); `WeekTimeGrid` serves Day at n=1. Mockup: bp9 a2/a3.
- **P14g — Month-grid renderers (MOCKUP-FIRST, no core).** The multi-cell span bar
  + drag-grips (`DateTime.end`); the `↻` occurrence marker; the in-grid task-due
  checkbox; status=cancelled strikethrough; the off-calendar lookup strip with
  "Open as filter" → P13 ⌘F. Mockup: bp9 a11/a12/a13/a14/a15/a17/a18.
- **P14h — Daily-note wiring (MOCKUP-FIRST, no core — the headline).** The day-panel
  "Open daily note" footer → `lotus_open_daily_note_at(selectedDay)` at ⌘⌥D;
  day-number click opens/creates; the dot=exists marker (shell `Set<Int64>`); today's
  cell as a daily-note page with a live first-lines preview. Mockup: bp9 a8/a9.

**Contacts track (parallel)**
- **P14-CT — contact-fields seed (CORE-ish services, FAILING-TEST-FIRST).** §3.2:
  `seed_contact_fields` (role/org/email/phone) on an additive guard; idempotency +
  render tests written FIRST. Invisible; no mockup.
- **P14i — Contacts surface (MOCKUP-FIRST, consumes P14-CT).** Route
  `Surface.contacts` → `ContactsView`: person-list `ObjectRow` + P13 filter box +
  `InspectorPane` + `Editor` + a `create_person` birth verb; the R1-free date rows
  + status ghost + connections inherit from the inspector; the `@`-mention path.
  Groups rail, in-body card block, peek card, vCard import DEFER. Mockup: bp9 a1/
  a20/a21/a22/a23/a26/a28/a29.

## 6 · Deferred (named, not built in P14)

- **Manual within-column kanban ordering / Placement entities** — a NEW core
  primitive; the board ships with due-sort; failing-test-first if ever pulled in
  (§1.3, feature-map #18).
- **Schedule/Calendar drag-to-reschedule** — the `set(due)`/`set(date)` seam
  exists; the gesture defers as a coherent follow-slice (§1.5).
- **Saved-view `.base` substrate + presets + the editable [View] segment +
  savable bookmarked-query entity** — the views/files fence (feature-map T4;
  P13 §1.2 precedent); built-in Focus shortcuts ship instead (§1.7).
- **Write-down mode + the `due:`/`!high`/`@name`/`#tag` token parser** — REFUSED
  (feature-map #20; a type-picker in disguise); the clerk's proposals are P16
  (§1.6).
- **AI legs** (Agents / plan-preview / approve-reject / row `✦`) — proposals enter
  the ONE inbox, P16; inert amber frames now (§1.9).
- **The workroom pop-out** — the existing open-as-tab is the equivalent; its
  checklist implies subtasks (P8 §8 deferred) (§1.10).
- **Contacts groups rail, in-body contact-card projection, hover peek card, vCard
  import, the file-path crumb** — saved-views/authoring/integration/files fences
  (§1.14).
- **Google two-way sync** (badge + `googleId` static only) — beyond the ICS fence
  (feature-map #43); conflict UX is P16 proposals (§1.16, OQ-A).
- **Per-calendar / per-group / per-avatar hues** — palette law #25; distinguish by
  view, not color (§1.16).
- **Time tracking + habits** — deferred until the owner asks twice / daily use
  demands (§1.15).
- **The Agenda calendar mode** — a non-bp9 lotus artifact; copy-exactly removes it
  (§1.11).
- **The live-agenda daily-note projection block** — P16 (bp9 OQ-C; the static
  Agenda heading ships, resolved in P12).

## 7 · Rulings recorded + genuinely-open owner calls

**Ruled here (not owner-blocking):**

1. **The board SHIPS as a mount** — every substrate landed in P11/P11.5; the
   feature-map #18 justify-then-build gate is satisfied (§1.1).
2. **Board drag = the existing `set(status)` command** — zero new core (§1.2).
3. **Manual ordering DEFERS** — Placement is a new primitive; due-sort ships
   (§1.3, D1).
4. **Column management ships; option retirement is P19** (§1.4).
5. **Schedule + Cards ship as client-side re-groupings** — zero core; Schedule is
   "both, ghosted" (§1.5/§1.6).
6. **Write-down + the token parser REFUSED** — the clerk is the substitute, P16
   (§1.6).
7. **Saved-view substrate + savable entity DEFER; built-in Focus shortcuts ship**
   (§1.7, extending P13 §1.2).
8. **[Selection] = the shared `InspectorPane`, ships; [View] defers** (§1.8).
9. **AI legs inert; behavior is P16** (§1.9, extending P13 §1.5).
10. **The workroom = the existing open-as-tab; no new pop-out** (§1.10).
11. **The mini-month rail + "My calendars" are DELETED; Month|Week|Day keep Day,
    Agenda removed** — feature-map #23's "day defers" superseded by bp9 a3 (§1.11).
12. **The daily-note footer wires the landed P12 seam at ⌘⌥D** — zero new core
    (§1.12).
13. **The span bar renders the landed `DateTime.end`; exceptions stay entities**
    (bp9 OQ-B reversed in lotus's favor); the daily-note template is P12's static
    heading (bp9 OQ-C) (§1.13/§1.16).
14. **Contacts ships thin** — the enum slot is spent; the one core cost is the
    contact-fields seed (§1.14, D2).
15. **Google sync static; per-calendar/group/avatar hues refused; naming deltas
    recorded** (§1.16).

**Genuinely open owner calls (recommendations in `ownerDecisions`):** board manual
ordering (defer, D1), Contacts ship (yes, D2), saved-views scope (Focus shortcuts
only; defer the savable entity, D3), the calendar lens set (keep Day, remove
Agenda, D4), and the task-field digit allocation (task-local, D5). None blocks the
one failing-test-first slice (P14-CT) or the mockup gates. **P14 is large and
should sequence the Tasks track before the Calendar track**, with Contacts landing
in parallel.

## 8 · P14g build-note (as shipped)

The month-grid renderers of §1.13 landed in `Calendar.swift`, all over the landed
substrate, ZERO core change:

- **In-grid task checkbox** — `DayCell.pill` gains a leading checkbox for any
  task row (`kinds.contains("task") || status != nil`); it fires the same
  `taskStatusToggle(model,row)` used everywhere, wired down as a `taskToggle`
  closure. Done-ness (fill + strikethrough) is `taskIsDone` on `CalendarView`,
  deriving the terminal status client-side from `statusVocabulary` — the exact
  `completes` rule the list uses, so a cell reads done identically in both
  surfaces. **This also covers the cancelled strikethrough (bp9 a18):** a
  terminal `cancelled` option strikes through by the same path; a distinct
  non-task "cancelled event" strike was NOT built (no such vocab today).
- **Recurrence ↻ marker** — a trailing `repeat` glyph when the row carries a
  non-empty `recurrence` cell (occurrences already draw the series entity).
- **Multi-day span bar** — a `monthByDay` expansion (MONTH-ONLY: the week/day
  time grids place a row at its start HHmm and a continuation day has no honest
  time on that axis, so `buildByDay` stays the single-placement source) appends
  a spanning row to every civil day in `(start, end]`. `pill` reads the span
  geometry from `key` vs `dueEnd`: a continuation cell squares off the edge it
  flows through (`UnevenRoundedRectangle`), drops its leading bar + start time,
  and re-anchors the title at each week row's first cell (Google/Fantastical).
  Spans float to the top of every crossed cell so a single bar reads continuous.
  A TIMED end at exactly midnight is EXCLUSIVE (iCal/Google: a 09:00→next-00:00
  event is one day, not two); all-day (`dueDateOnly`) ends stay inclusive —
  centralized in the file-scoped `spanEndDay(row)` so `monthByDay` and `pill`
  agree. The week-row title re-anchor tests MONDAY (`isMondayFirstCell`, matching
  the grid's fixed Mon..Sun layout) — NOT the locale's `firstWeekday`, which is
  Sunday on the default en_US config and put the title on the wrong column. The
  leading element (checkbox/time) draws on the START cell only; continuation
  cells carry the bare bar. (All three were P14g-review findings, fixed + logic-
  verified with a standalone civil-arithmetic check before commit.)

**Deferred within P14g (named):**
- **Span drag-grips** (interactive resize writing `DateTime.end`) — the read-only
  bar ships; the write path is the inspector's date row today. A grip that
  rewrites `dueEnd` across month cells is real geometry+command machinery for
  marginal gain over the inspector; deferred.
- **Off-calendar lookup strip** (bp9 a15) — the load-bearing part (lookup roles
  never position) is already law+tested; the dismissible explainer strip with an
  "Open as filter" jump to the ⌘F palette is polish, deferred.
- **Event-chip drag→date-write** (bp9 a11) — single-day drag-to-reschedule; the
  same command as the deferred grips, deferred with them.
