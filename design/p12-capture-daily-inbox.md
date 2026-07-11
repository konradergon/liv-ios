# P12 Capture / Daily-notes / Inbox — the wedge pair on lotus honesty: Quick Capture stays a bare doorway that asks nothing, the Inbox becomes ONE surface with Route and Tidy lenses (never two cleanup surfaces), the daily note is an ordinary note carrying `type=daily-note` + a calendar-role `date` cell born through the single new seam `lotus_open_daily_note_at`, and every folder path, AI proposer, and file attachment defers with a named reason — the whole pair rides the P11.5 grammar kit (InspectorPane, RowKit, DigitMap, InspectorEditors, VALUE_HEX) with exactly ONE new Rust seam

Building on the landed P11.5 grammar kit (p11.5-grammar-kit.md; commits `b80069f…550018e`)
and the shipped shell (`shell/macos/Sources/{Window,Inspector,InspectorEditors,InspectorLayout,RowKit,DigitMap,Hues,Calendar,Commands}.swift`).
P12 is **THE WEDGE PAIR** (bp5-capture-inbox.html:297-305): one panel to get a
thought out of your head in seconds (**Quick Capture**, never blocks) and one to
give every orphan exactly one address where it gets **routed** or **tidied**
(**Inbox: Route | Tidy**), plus the owner-directed **daily note** reached from
Today, the menu, and a chord. The primary blueprint is bp5 (24 annotations
a1–a24 + 4 open questions); the daily-notes model is liv-ui-map §2.20 + bp9 e8/e9.

Grammar locks the blueprint declares and P12 honors: **BP-1 V3 inspector**
(the inline Route inspector IS the shared `InspectorPane`, a18), **BP-7 V2
chip-forward** (capture cards are `ObjectCard`, orphan rows are `ObjectRow`,
chips are `ValueChip`/VALUE_HEX — a10/a15/a12), **IA-3 Route/Tidy** (one inbox,
two lenses — a14). P12 is **almost entirely shell**: the four readers verified
that the capture seam (`services::capture`, lib.rs:27-57 — content+created,
"Nothing else"), the accept/reject plumbing (`lotus_accept_at`/`lotus_reject_at`,
ffi:1032-1055), the clerk's two live proposers (dates+mentions, clerk.rs:146-208),
and the whole P11.5 kit already exist. **The entire P12 Rust budget is ONE new
seam** — the atomic get-or-create daily note (§3.1) — justified because it is the
one place a query-then-create race across two `with_box` scopes can double-create
(daily-notes reader; failing-test-first per memory: test-drive-core-changes).
Everything else the two panels need is composed shell-side from seams that ship.

Every visible slice is **mockup-first**: a static exhibit cloned from bp5
(Quick Capture panel A / Inbox Route+Tidy panel B), re-hued to the lotus palette
(lake green `#2f7d6b`, never the blueprint blue/violet), approved against the
blueprint screenshots before a line of Swift — the owner's copy-exactly rule
(memory: copy-liv-exactly). The one core slice is **failing-test-first**. What
varies per surface is data and lens, never the anatomy.

## 0 · Owner decisions (resolved 2026-07-11, before mockups)

Four forks were put to the owner; the answers below OVERRIDE the workflow's
recommendations where they differ, and §2.3 / §3.1 / §5 are written to them:

- **D1 — Today topology: "Today IS the daily note."** (Owner overrode the
  synthesizer's "dashboard + separate tab" rec.) The Today surface itself
  becomes today's daily-note editor — opening the app lands you in a writable
  page. The old Due/unstructured aggregation is NOT kept on Today; the day's
  agenda/due is subsumed by the daily note's live-agenda block (the bp9 OQ-C
  projection, deferred to P16) and otherwise lives in Tasks/Calendar. See §2.3.
- **D2 — Open-today chord: ⌘⌥D.** (Owner chose the shipped-Liv keymap chord
  over bp9's Ctrl+D.) Verified free in Commands.swift (⌘[ /⌘] are nav history,
  Alt+←/→ inspector focus/blur; no D binding). Supersedes ruling §7.5's OQ-1
  note for the daily chord specifically; the global CAPTURE chord stays ⌃⌥Space.
- **D3 — Per-workspace daily notes: ship the workspace cell now.** Each daily
  note carries a narrow `workspace` reference cell; get-or-create keys on
  type+date+workspace. Scoped to daily notes ONLY — not a general
  content-membership model. See §3.1.
- **D4 — Birth body: a fixed default template body ("ideally a template
  note"), NOT blank.** bp9 OQ-C leaves the template open and recommends a live
  agenda block — which is a P16 projection. The shippable half is a FIXED
  starter body (a real "template note"): born on creation, edited like any
  note, no {{variable}} engine, no template-authoring UI (the constitution's
  fence stands). The live-agenda-projection block reserves its slot for P16.
  The exact copy is a taste call (bp9 flags "needs Viktor's voice") the owner
  refines at the mockup gate — it is one string constant. See §3.1.

## 1 · The load-bearing decisions

1. **Route and Tidy are two LENSES on the one Inbox surface, not two surfaces.**
   The constitution makes the inbox "the shell's one surface that is not a view"
   (productivity_app.md:1044-1047); feature-map T4 refuses "second/third cleanup
   surfaces" (feature-map.md:318). bp5 itself already conforms — a13 CUTS the
   floating "N things I can tidy" pill; a14 makes Route|Tidy tabs sharing one
   address, cycled with `[ ]` because "digits stay reserved for the property
   map" (D21). Route lens = untyped-scrap orphans; Tidy lens = the existing
   `ProposalRow` clerk queue. Two renderers over one address. **RECORDED DELTA
   (b):** compatible with "one inbox by law" — it is one inbox, two lenses,
   never a refused Assist panel.
2. **No folders — commit is a cell-stamp, not a file move; the destination line
   stays deferred exactly as P11.5 §9.2 ruled.** lotus stores entities in an
   append-only box log; there is no truthful path and the row's promise ("reveal
   in vault tree") cannot be kept (p11.5-grammar-kit.md:352-355, §9.2:693-700).
   bp5 a6 ("will save to → library/inbox/"), a7, and a21 (note→notes/, link→links/,
   pdf→pdf/) all lean on folders. A scrap is already IN the box the instant
   `lotus_capture_at` commits; "Commit" from Route means **stamp a `type` cell**
   so the scrap drops out of the untyped-orphan set. **RECORDED DELTA (a):**
   carry P11.5 §9.2 forward unchanged — omit the folder line; reserve the layout
   slot so mockups diff cleanly if a projection/export story (§5-R1) later gives
   objects a real path. OQ-3's kind-based pools dissolve (there is one box).
3. **AI = proposals only; every proposer is P16. P12 ships the FRAMES + real
   plumbing, not new proposers.** AI gets "two doors: reads through queries,
   writes through proposals" (feature-map.md:27-28). The four bp5 AI legs —
   a2 name-on-send, a17 merge-suggestion, a18/a24 Alt+M metadata, a23 Tidy
   heuristics — are all T3 items. **Crucially the Tidy lens is NOT empty on day
   one:** the clerk already emits deterministic date + mention proposals
   (clerk.rs:146-208), surfaced with accept/reject that ships. Every AI
   affordance (name row, merge card, Suggest-all, marigold halo) renders as
   **static chrome** with `Theme.warning` reserved, wiring no new proposer.
   **RECORDED DELTA (c):** everything a user can do by hand ships in P12;
   everything the clerk must SUGGEST arrives later through the same inbox with
   zero UI change (exact P11.5 pattern for the deferred BP-1 AI card).
4. **Capture asks nothing, never blocks, focus stays; the scrap is bare.**
   Verified: `capture()` commits exactly CONTENT + CREATED, "Nothing else"
   (services/src/lib.rs:27-57). The global ⌃⌥Space `CapturePanel` (main.swift)
   already gives frictionless capture and clears only on log-confirmed success
   ("never lose a thought"). **RECORDED DELTA (bp5 a4):** the silent
   workspace-stamp of `area · studies · master-thesis` collides with
   capture-asks-nothing and the bare scrap — it becomes either a visible clerk
   proposal (P16) or an EXPLICIT editable chip the user adds on the in-app wall
   (writing reference cells, one undo). No silent capture-time metadata write,
   ever.
5. **The daily note is an ordinary note carrying two identifying cells.**
   Owner directive + blueprint era WIN over feature-map T1 #8's stale "resist
   rebuilding Today as a note" (feature-map.md:77-79) — but that line's positive
   half ("an ordinary note with a date cell … No template/folder machinery") IS
   the spec. A daily note = a normal note-shaped entity: a seeded **`daily-note`
   TYPE** (EXPECTED=[content, date] so `find_type` resolves it, content.rs:685-695)
   + a **`date` cell** (`DateTime::date`, the existing calendar-positioning role,
   lib.rs:346) + CREATED + a NAME = the ISO date + empty CONTENT. **RECORDED
   DELTA (d):** upgraded from feature-map #8's "nothing" to "a distinct type +
   a date cell + a get-or-create seam," because get-or-create must distinguish
   the day's note from any other dated note. NO template, NO folder/customPath,
   NO carry-over (the last a confirmed non-delta — Liv has none either).
6. **Get-or-create is the one atomic Rust seam; the orphan set is shell-side.**
   Two separate `with_box` FFI calls (snapshot-then-create) can both observe no
   daily note and both create one (ffi:246-249, 408-419) — so get-or-create runs
   the find-query and the conditional create inside ONE session
   (`lotus_open_daily_note_at`, §3.1), failing-test-first. The Route orphan set,
   by contrast, is `content ∧ ¬type` and expressible **client-side** over
   `snap.entities` (`kinds.isEmpty && contentPrint != 0 && !trashed`,
   Window.swift:70,84) — `everything`/`entities[]` already exclude working
   plumbing (`include_working=false`, lib.rs:770,815), so no defs/types leak.
   **Zero core change for orphans in P12**; promote to a services `orphans`
   bucket (failing-test-first) only when Route volume/pagination justifies it.
7. **Merge (a17) is deferred WHOLE — proposer AND execution — to P16.** The
   sharpest correction to the brief's KNOWN FACTS: there is **no `lotus_merge`
   FFI** (grep confirms; merge lives only in `core::Store::merge`,
   store.rs:291-320, called from a test at ffi:2144), and entity-merge COPIES
   cells the survivor lacks, SKIPPING the already-present `content` cell — so it
   would NOT append a scrap's body. The merge card is an AI-suggestion surface
   (marigold halo; "the processor suggests a merge"); with no proposer there is
   nothing to execute in P12. Ship it **static**. When P16 builds it, the
   accepted merge rides `lotus_accept_at` over a proposal carrying the transaction
   — **no new merge FFI is required for the accept path**, which is exactly what
   holds the P12 Rust budget at ONE seam. The content-append-vs-entity-merge
   decision (a17 body-append vs true dedupe) is recorded for P16 (OQ-4).
8. **P12 mounts the P11.5 kit and retires `EntityLine`.** bp5 is built ON the
   kit: a18 = the shared `InspectorPane` re-bound by orphan selection, a10 =
   `ObjectCard` (its debut mount is the capture wall), a15 = `ObjectRow` +
   `anchorChip`, a12 = `DigitMap` chip-click. P11.5 decision 9 already reserved
   Today for P12 and said `EntityLine` "survives only on the waiting surfaces
   and dies with them" (p11.5-grammar-kit.md:80-82). **No new row/card/inspector
   component is built.** `EntityLine` (Window.swift:1576, used at TodayView:1880/1892)
   is retired as Today and Inbox move onto the kit.
9. **The inbox count stays the app's only badge; under bp5 it means Route
   orphans + actionable Tidy.** feature-map T4:314 — "the inbox count — the only
   badge in the application." The shell currently badges the rail with
   `unstructured.count` (Chrome.swift:351), which is the wrong set (content∧¬due)
   AND mismatches the surface (which lists proposals). P12 recomputes the one
   amber badge = orphans + actionable proposals, hiding at zero (bp5 a13/a22).
   No second badge; halos are static presence chrome, not live counts.
10. **Deferred from bp5, decided (§6): the AI name row, merge card, Alt+M/
    Suggest-metadata, "group tabs," the folder destination line, camera/mic
    attachment, composer-mode straight-to-note routing, and per-workspace
    generalization.** Each has a named reason — missing substrate or a fenced
    roadmap layer, not missing will.

## 2 · The three surfaces

### 2.1 Quick Capture (panel A) — the doorway that asks nothing

**Purpose (bp5 header).** Get a thought out of your head in seconds; never
block, never ask for a name. Two layout modes (a8): **Keep** = take box + wall
of past captures; **Composer** = full-page writing surface (same chips). The
mode is `capture.layoutMode`, a **shell UserDefaults flag, never an entity**
(feature-map.md:358-360's cautionary tale 6) — two density modes of one surface,
never tabs or panes (feature-map.md:299).

**SwiftUI structure (reusing the kit):**

```
QuickCaptureView                         // replaces the dumb TodayView TextField
 ├─ CaptureBox         (a1)  live-markdown take box over the Editor content
 │                           surface; Esc clears; ⌃⏎ (a7) = lotus_capture_at,
 │                           input clears on success, focus STAYS PUT
 ├─ [AI name row       (a2)  STATIC frame — ✎ wires to lotus_set_at(name);
 │                           ✦ suggest inert until P16; native default nameless]
 ├─ ChipStrip          (a4/a5) editable metadata chips via the P11.5 D17 value
 │                           pool + AddPropertyPopover; × removes; NO auto-stamp
 ├─ [destination line  (a6)  OMITTED — §6, slot reserved (P11.5 §9.2 precedent)]
 ├─ [AttachmentStrip   (a11) camera/mic STATIC-disabled; clip → lotus_add_file_at
 │                           only if trivial, else disabled]
 ├─ Keep⇄Composer      (a8)  segmented control over capture.layoutMode
 ├─ WallFilters        (a9)  simple client-side chips over the orphan set;
 │                           "unrouted · N" deep-links to Inbox › Route
 └─ CaptureWall        (a10) LazyVGrid of ObjectCard — the FIRST real ObjectCard
                             mount; hover ↗ open · ⋯; ✦ suggest inert (P16)
```

**Reconciliations.** Take box writes through the existing `lotus_capture_at`
(ffi:31-65); a Composer capture still writes the same bare scrap (OQ-2 →
recommend: lands as an orphan like Keep mode, so one routing law covers both).
The chip strip reuses `ValuePoolPopover`/`AddPropertyPopover` verbatim
(InspectorEditors.swift:123,599) — chips write reference/select cells, `×`
removes via `lotus_remove_cell_at`. Chip click filters the wall by value via
`DigitMap`; Alt-click-exclude defers with the D22 filter pass (P11.5 precedent).

**Ships:** take box (real capture), the ObjectCard wall over the client-side
orphan set, editable chips (manual), Keep⇄Composer toggle, include-click chip
filter. **Static/inert:** AI name row (✦), camera/mic, wall AI-suggest.
**Omitted:** the folder destination line (slot reserved).

### 2.2 Inbox: Route | Tidy (panel B) — one surface, two lenses

**SwiftUI structure (rebuilds the bespoke `InboxView`, Window.swift:1937):**

```
InboxView                                // one .inbox Surface (⌘4)
 ├─ LensSwitch         (a14) Route | Tidy segmented control, cycled with [ ]
 │                           (NOT digits — D21 reserved); a/r triage stays
 ├─ Route lens ─────────────────────────────────────────────
 │   ├─ OrphanList     (a15) ObjectRow per untyped scrap (client-side
 │   │                       content∧¬type); ↑↓ moves selection; source line
 │   │                       synthesizes "quick capture", provenance deferred
 │   ├─ InspectorPane  (a18) THE shared V3 inspector, re-bound to the selected
 │   │                       orphan (Inspector.swift:110, topPadding tuned);
 │   │                       "type: [set type]" ghost row IS the empty TYPE cell;
 │   │                       date role (a19), status (a20), +property (a5) all
 │   │                       reuse InspectorEditors as-is
 │   ├─ [merge card    (a16/a17) STATIC frame — "1 New note (default) · 2 merge";
 │   │                       execution + proposer defer to P16 (§1.7)]
 │   └─ CommitBar      (a21) "Commit" = stamp the chosen type (lotus_add_cell_at
 │                           type=<kind>) → scrap leaves the orphan set; badge −1;
 │                           next orphan auto-selected. "Later" = no-op, no nag.
 │                           NO folder line (§6).
 ├─ Tidy lens ──────────────────────────────────────────────
 │   ├─ AssistQueue    (a23) the existing ProposalRow clerk queue (dates+mentions)
 │   │                       rendered as cards; accept/reject via
 │   │                       lotus_accept_at/reject_at; dismiss = declined sidecar
 │   ├─ [heuristic cards (a23) "missing type"/"group tabs"/dedupe — STATIC; the
 │   │                       proposers are P16]
 │   └─ SuggestForAll  (a24) wired to a clerk re-sweep surfaced as per-orphan
 │                           review cards (never auto-apply); richer suggest = P16
 └─ EmptyState         (a22) calm frame naming the capture shortcut; amber hides
                             when orphans + actionable-tidy = 0
```

**Reconciliations.** The Route inspector is the whole point of a18 — mounting
`InspectorPane` inline bound to `$selection` re-binds on every orphan pick for
free (current-state reader: it is already model+selection driven). The `form`
row (bp5 row 1, capture/file origin) has **no backing cell** — synthesize
read-only from provenance or omit; the `type` ghost row is the native empty TYPE
cell that drives the commit path. Row-menu "Change type" stays deferred (P11.5
§2.8 — needs the kind-resolution seam). Commit stamps a cell; the orphan drops
out of the client-side query by construction (it now has a type). "Later" matches
the core's declined-sidecar ethos of never re-nagging ("Absence creates no debt").

**Ships:** Route orphan list + inline inspector + manual type-stamp commit (fully
functional, no AI); Tidy over the live clerk proposals with accept/reject; the
badge recount. **Static:** merge card, heuristic cards, marigold halo.

### 2.3 The daily note — Today IS the note (owner D1)

**Purpose.** Deliver the owner's Liv daily notes, and per **D1 the Today
surface ITSELF becomes today's daily-note editor**: entering `.today`
get-or-creates today's note and renders it in the existing composer/editor
(P4). Opening the app lands you in a writable page for today. `⌘⌥D` (D2) from
anywhere jumps to Today's note; a non-today date (P14 calendar) opens that
day's note as a tab via the same seam.

**What happens to the old Today aggregation.** The Due list + unstructured
list are REMOVED from Today (D1). The day's agenda/due is subsumed by the
daily note's **live-agenda block** — the bp9 OQ-C projection (today's events +
due tasks rendered into the note), which is a query-projection and **defers to
P16**; its slot is reserved at the top of the template body (§3.1). Until then,
"what's due today" lives in Tasks (P14) and Calendar — matching Liv, where the
daily note is a note and due/agenda is calendar/tasks. No Due aggregation is
re-invented on Today.

**SwiftUI / entry points.** All converge on the one seam (§3.1):

```
"Open today's daily note"
 ├─ .today surface    → on appear, lotus_open_daily_note_at(today, workspace)
 │                       → render that note id in the editor AS the Today body
 │                       (the dumb capture TextField + Due/unstructured lists at
 │                       Window.swift:1840-1919 are REMOVED wholesale)
 ├─ Command + ⌘⌥D     → switch to .today (today's note); a selected non-today
 │                       date opens that day's note as a tab (P14)
 └─ Menu item         → main.swift:193-195 'Daily Note' item, isEnabled flips
                         true, action switches to .today
```

**Reconciliations & deltas (record all six).** Drop: (1) template machinery
(tpl_daily body/{{vars}} — feature-map #9 fences authoring; born blank);
(2) folder/customPath/titleFormat/filename-sanitization (no files — the `date`
cell replaces `calendarDate`; no destination crumb, extending P11.5 §9.2);
(3) NoteOverlay/NotePreviewModal (a real editor tab); (4) the Daily-Notes
settings panel + open-on-startup (nothing to configure); (5) habit checkboxes
in bodies (feature-map #16, deferred); (6) carry-over — a **non-delta** (absent
on both sides; note it so no one "restores" it). The bp9 "dot beside the day =
note exists" and "today's cell knows its note" fall out **for free**: the `date`
cell lands the note in `snapshot.dated` (positioned_by=`date`, lib.rs:346-348),
so the calendar can query `type==daily-note` within a day to draw the dot — but
the today-cell-IS-the-note wiring is P14's calendar re-base, not P12.

**Ships:** the seam, the type seed, the command+chord+menu+Today entry, opening
a real editor tab, the calendar dot for free. **Defers:** the calendar
day-panel footer entry and the day-number open-or-create (P14), open-on-startup,
per-workspace generalization beyond the narrow daily-note cell (owner decision).

**A daily note must NOT leak into Today's `unstructured` list.** `unstructured`
= content∧¬due with **no type filter** (lib.rs:611-621, verified), so a daily
note (content + `date`, no `due`) would match. This is moot the moment the dumb
Today list is retired (§2.3 removes it) — but the bucket still feeds the rail
badge, which P12 repoints at the orphan set anyway (§1.9). So **no core query
change is required in P12**; if a later surface reads `unstructured`, constrain
it to `¬type` failing-test-first at that time (recorded, not built here).

## 3 · The minimal core work — ONE new seam, failing-test-first

**Rust budget: exactly ONE new seam** (`lotus_open_daily_note_at`) + one additive
data seed (the `daily-note` type). The orphan set is shell-side (§1.6); merge
defers whole (§1.7); the `unstructured` predicate fix is not needed in P12 (§2.3).

### 3.1 `lotus_open_daily_note_at` — get-or-create (FAILING TEST FIRST)

**Why a seam and not shell composition.** Query-then-create spans two `with_box`
scopes; two entry points firing close together can both create. The seam runs
the find and the conditional create in ONE session, keeping the "find that type
on that date" logic in one tested place (daily-notes reader; ffi:246-249,408-419).

**Services fn** (content.rs, modeled on `create_note` at :195):
`get_or_create_daily_note(session, date: DateTime /*dateOnly*/, workspace: Id, created: DateTime) -> Result<Id, PersistError>` — run
`Query[ type == daily-note, date == dateOnly, workspace == ws ]` (workspace
ships now, D3); return the first hit, else Create + type=daily-note + date +
`workspace` ref + created + name=ISO-date + **the default template body**
(D4), one commit, `Author::User`.

**The default template body (D4).** A FIXED starter body — a real "template
note", not a template engine. One `const` string of markdown rich-text spans
born into CONTENT on creation, then edited like any note. It reserves the
top slot for the P16 live-agenda block (a deletable projection of today's
events + due — bp9 OQ-C's recommendation, which is a query-projection P12 does
not build). The concrete copy is a taste call (bp9: "needs Viktor's voice");
the owner refines the constant at the mockup gate. Starting proposal (minimal,
non-inventive — a date anchor + the reserved agenda slot + open sections):
`# {ISO date}` · `## Agenda` (the P16 projection lands here) · `## Notes` ·
`## Log`. No `{{variable}}` expansion beyond the one date substitution; no
per-workspace template variants; no authoring UI.

**FFI wrapper** (ffi, through `with_box`, per the ffi-store-cache law): returns
the id, tagging `Committed::Read` on the found path (store untouched) and
`Committed::Wrote` on birth (forces the re-sweep). Copy the shape of
`lotus_create_note_at` (ffi:1340-1347).

**The type seed** (additive, self-guarded, `Author::System`, in
`seed_starter_library` — the exact `seed_date_roles`/starter-type pattern,
lib.rs:740-761): a `daily-note` type with WORKING=true and EXPECTED=[content, date]
so `find_type` resolves it (content.rs:685-695) and the inspector offers both
rows. Guard on the type name's absence so an older box gains it on open. A
`workspace` reference property is seeded the same way (additive, D3) if absent.

**The failing test, written first (memory: test-drive-core-changes — do not
trust the doc's reasoning):**
- calling the seam twice for the same `(ymd, workspace)` returns the **same
  id** and leaves **exactly one** daily-note entity;
- a different date yields a different id;
- **the same date in two workspaces yields two entities** (D3 ships now);
- the born note carries type=daily-note + date + workspace + the template body
  (CONTENT non-empty).

**BoxModel wrapper** (Window.swift, mirroring `createNote` at :477): one
`lotus_open_daily_note_at` call + `refresh()`.

### 3.2 The orphan / Route query — shell-side in P12 (zero Rust)

Route orphans = `content ∧ ¬type`, iterated over `snap.entities`
(`!trashed && kinds.isEmpty && contentPrint != 0`). `EntityRow` already carries
`kinds` (empty when typeless) and `contentPrint` (0 when no content),
Window.swift:70,84. **RECORDED DELTA:** orphan = content∧¬type; the legacy
`unstructured` = content∧¬due bucket is retained for Today's aggregation only
and is NOT the Route set. Promotion to a services `orphans` bucket (a new
`Constraint{TYPE, Op::Missing}` + `Constraint{CONTENT, Op::Exists}` query, both
ops exist) is **failing-test-first** and deferred until Route volume warrants it.

## 4 · Swift decode shapes

**Essentially none.** The daily note is a normal note entity that flows through
`entities[]`; the seam returns a bare `u64` id (like `create_note`) — no new
snapshot struct, no new `Codable`. The orphan set reads existing `EntityRow`
fields (`kinds`, `contentPrint`). Route/Tidy read the existing
`inbox: [ProposalRow]` and `entities[]`. All P11-added decode fields remain
Optional + `try?`-safe (P11.5 decision 12). The only new shell state is
`capture.layoutMode` (UserDefaults, not wire). If §3.2's `orphans` bucket is
later promoted, it adds exactly one id-list field (`orphans: [UInt64]?`),
optional and additive.

## 5 · Slice plan (each an independent commit)

Rust in this plan: **one seam + one type seed, in 12a only.** Two independent
tracks (like P11.5): the daily-note track (12a→12b) and the capture/inbox track
(12c→12d→12e). Order matters only where stated.

- **12a — daily-note seam + type seed (CORE, FAILING-TEST-FIRST).** §3.1 verbatim:
  seed the `daily-note` type additively; `get_or_create_daily_note` in content.rs;
  `lotus_open_daily_note_at` through `with_box` (Read on found, Wrote on birth);
  the `BoxModel` wrapper. Tests first: idempotent per (date[,workspace]); one
  entity; distinct dates distinct ids. Invisible; no mockup.
- **12b — Today becomes the daily note + entry points (MOCKUP-FIRST for Today).**
  Per D1: rework the `.today` surface to get-or-create today's note on appear
  and render it in the existing editor AS the Today body — REMOVE the dumb
  one-line capture TextField and the Due/unstructured lists wholesale
  (Window.swift:1840-1919); retire `EntityLine` on Today. Register `⌘⌥D`
  (D2, verified free); enable main.swift's `Daily Note` menu item (action →
  switch to `.today`). The live-agenda block is P16 (template slot reserved).
- **12c — Quick Capture surface: Keep wall (MOCKUP-FIRST).** `QuickCaptureView`:
  live-markdown take box over `lotus_capture_at`; the ObjectCard capture wall
  (RowKit's debut ObjectCard mount) over the client-side orphan helper (§3.2);
  wall quick filters + chip-click via DigitMap; editable chips via the P11.5
  value pool; Keep⇄Composer toggle (UserDefaults); AI name row + camera/mic
  static; destination line omitted (slot reserved). Mockup: bp5 panel A.
- **12d — Inbox rebuild: Route lens (MOCKUP-FIRST).** Rebuild `InboxView` as one
  surface with a Route|Tidy segmented control (`[ ]` cycle). Route: orphan
  `ObjectRow`s + inline `InspectorPane` (rebind on selection) + reused
  InspectorEditors + commit bar (stamp type, auto-advance, no folder line) +
  "Later" no-op; recompute the amber badge = orphans + actionable proposals,
  hide at 0. Mockup: bp5 panel B Route.
- **12e — Inbox Tidy lens (MOCKUP-FIRST).** Tidy lens = the existing clerk
  ProposalRows (dates+mentions) as assist cards with accept/reject; "Suggest for
  all" wired to a clerk re-sweep as per-orphan review cards (never auto-apply);
  merge card + heuristic cards + marigold halo render static (proposers P16).
  Mockup: bp5 panel B Tidy.

The two tracks are independent; within the capture track 12c introduces the
client-side orphan helper that 12d reuses, so 12c precedes 12d.

## 6 · Deferred (named, not built in P12)

- **The folder destination line + kind-based commit pools** (bp5 a6/a7/a21,
  OQ-3) — no truthful per-object path; carry P11.5 §9.2 forward; the slot is
  reserved so mockups diff cleanly if a projection/export story (§5-R1) lands.
- **All AI proposers → P16:** a2 name-on-send, a17 merge target-suggestion +
  execution, a18/a24 Alt+M metadata suggestion, a23 "missing type"/"group tabs"/
  dedupe heuristics. Frames + plumbing ship; producers defer. `Theme.warning`
  reserved.
- **The merge execution seam** — no `lotus_merge` FFI is added; when the P16
  proposer emits a merge, it rides `lotus_accept_at` as a proposal payload. The
  a17 body-append-vs-entity-merge choice is recorded for P16 (OQ-4); true
  `Session::merge` is reserved for the a23 dedupe card.
- **File/camera/mic attachment** (bp5 a11) — files-by-reference is the sanctioned
  first integration, gated on §5-R1/P15; transcription is a later service.
  Ship the strip static/disabled; capture stays text → bare scrap.
- **Composer-mode straight-to-note routing** (OQ-2) — recommend Composer
  captures land as orphans like Keep mode (one routing law); a typed Composer
  capture simply isn't an orphan. Owner confirms.
- **Workspace auto-stamp at capture** (bp5 a4) — silent stamp REFUSED; ships as
  manual chips now, visible clerk proposal later (P16).
- **Per-workspace generalization beyond daily notes** — the narrow `workspace`
  cell on daily notes is the only content-workspace membership P12 touches;
  do NOT generalize content-membership.
- **Calendar day-panel footer + day-number open-or-create + open-on-startup**
  (daily-note entry points 4–6) — P14 calendar re-base / settings budget.
- **The services `orphans` bucket + the `unstructured` ¬type fix** — shell-side
  suffices in P12; promote failing-test-first when volume/a reading surface
  warrants (§3.2, §2.3).
- **Alt+click chip-exclude** — the D22 filter-engine pass (include-click ships).
- **Habit checkboxes / streaks** (Liv §2.22) — feature-map #16, deferred.

## 7 · Rulings recorded + the genuinely open owner calls

**Ruled here (not owner-blocking):**

1. **Route/Tidy = one surface, two lenses** — compatible with "one inbox by law"
   (§1.1). Cycle with `[ ]`, never digits.
2. **Destination line — defer, extend P11.5 §9.2** (§1.2). Commit stamps a cell;
   no folder path; slot reserved.
3. **Merge deferred whole to P16; no `lotus_merge` FFI in P12** (§1.7). The
   accept path rides `lotus_accept_at`.
4. **Orphan = content∧¬type, client-side in P12** (§3.2). The `unstructured`
   bucket (content∧¬due) is Today-only and not the Route set.
5. **Global capture chord stays ⌃⌥Space** — already the constitutional fixed map
   (interface.md); bp5's proposed Ctrl+Alt+N is superseded. Record the delta on
   OQ-1.
6. **`capture.layoutMode` is a shell UserDefaults flag, never an entity**
   (feature-map cautionary tale 6).
7. **`EntityLine` is retired** as Today and Inbox move onto the RowKit (P11.5
   decision 9).

**Resolved by the owner (§0), no longer open:** open-today chord = **⌘⌥D**
(D2); Today topology = **Today IS the daily note** (D1); per-workspace = **ship
the workspace cell now** (D3); birth body = **a fixed default template body**,
live-agenda projection deferred to P16 (D4). These override the synthesizer's
recommendations where they differ and are written into §2.3 / §3.1 / §5.

**Owner refines at the mockup gate:** the exact daily-note template copy (bp9
flags it "needs Viktor's voice" — it is one string constant).
