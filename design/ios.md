# iOS — the phone shell

> Status: **ALPHA**, shipping from this tree. Revisions here stop at rev 28
> (2026-08-16); `design/changelog.md` carries every batch since, so parts of
> this file are two weeks behind the code. Two statements in the old status
> line were dead and are struck: it is no longer "M1 in progress" (M1 was
> passed by M3–M5 and eight roadmap phases), and the accent is NOT lake
> green — `Theme.swift` uses the system tint and `2f7d6b` appears nowhere in
> the shell. Corrected in the 2026-08-20 alignment pass; see
> `design/spec-alignment.md` for what changed and what waits on a ruling.
>
> **The blueprints are a quarry, not a contract (owner, 2026-08-20):**
> *"it should be a super simplified version of the blueprints only bringing
> the best bits and fitting well into a phone."* A gap between a `bp*.html`
> mockup and this shell is not a defect by default — see
> `design/spec-alignment.md`. Blueprint rules about QUALITY still bind.
>
> (Source renamed lotus→liv 2026-07-22 — this doc's verbs read `liv_*`.)
> Produced 2026-07-21
> from a full read of the specs, core, FFI, and macOS shell, plus a
> three-architecture sync design pass judged through integrity / UX / cost
> lenses (unanimous verdict). Open owner decisions are collected in §8.
> Mockups: see the published artifact (phone frames, accent toggle).

## 0. What the phone is

> **Contradicted by two higher-ranked documents (2026-08-20).**
> `design/what-liv-is-for.md` — which CLAUDE.md ranks above every spec on
> product questions — says "The phone is not a feeder for a computer app. It
> is this product, on a phone, and it stands alone", and CLAUDE.md says
> `shell/ios/` is THE app. The satellite framing below, and the sync funnel
> in §2 that follows from it, are left in place as record. What to do with
> the still-running Outbox is an open ruling, not an edit.

The phone is a **capture satellite**, not a second desk. Its priorities, from
the owner:

- **P1** — photograph and capture ideas with fast, optional metadata; content
  reaches the desktop box.
- **P2** — add tasks; local notifications for due tasks and calendar events.
- ~~**P3** (low) — a unified read-only view of imported messages~~ —
  **KILLED, owner decision 2026-07-26.** The unified-inbox category is a
  graveyard and nothing here differentiates. The core's
  `liv_import_messages_at` verb stays (shipped, tested, harmless); no
  mobile surface will ever be built on it.
- **P4** (hardest) — notes sync.

One sentence of architecture: the phone links the **same Rust core** as a
static library (verified compiling for `aarch64-apple-ios` — the whole
workspace checks clean), keeps its **own local box** for instant offline
capture, and ships content to the desk as **write-once import batches** that
the desktop drains through the existing idempotent `liv_import_batch_at`.
The log never crosses a sync boundary. Multi-device *sync* stays un-built,
exactly as the constitution fences it — this is a capture funnel plus a
read-only mirror, and it says so in its own UI.

## 1. Shell contract (identical to macOS)

- Link `liv_ffi` staticlib via `liv.h` (xcframework wrapping
  `aarch64-apple-ios` + `-sim`; the unix-only `MetadataExt` in ffi is fine on
  Darwin). New build script — `build.sh` is host-only.
- One serial queue for all FFI; every verb opens the box, runs one txn, checks
  in; refresh-after-every-act; retry-with-backoff on `locked`.
- Snapshot decoding: **every wire field Optional** (the `applySnapshot` bug
  class), snake_case, `liv_string_free` on every returned string. On iOS,
  prefer a *throwing* decode with a logged error over macOS's silent `try?`.
- The box lives in the **App Group** container so the app, share extension,
  and widget App Intents share it (per-call advisory flocks are safe within
  one device; the box file itself is never cloud-synced).

## 2. Sync — "Satellite": outbox over iCloud Drive

Three architectures were designed independently and judged adversarially:

| | verdict |
|---|---|
| **A. Satellite outbox** — phone-native batches + media in iCloud Drive; desktop drains at open via `liv_import_batch_at` | **Winner, all three lenses** (integrity 8.5, UX 8, cost 8). Idempotent by construction; the log never syncs; phase 1 needs zero core/services/ffi changes. |
| B. Vault-folder mediation — phone writes markdown into `library/` pools; P20j reconcile adopts | Rejected for v1: v0 ingest drops frontmatter metadata (P1 fails), >25-file mass-change cliff strands vacations, binaries wait on 20j.8. **Remains the designed P4 notes channel.** |
| C. Translated oplog — true two-way peer via services-layer id translation | Rejected as first ship by its own staging plan ("Stage 1 is A"). It is the *destination* if write-back is ever wanted; A's external-id discipline is specified to be forward-compatible with it. |

### 2.1 Topology

```
iPhone   AppGroup/liv/liv.log        phone's own box (cache + capture roll, disposable)
         AppGroup/outbox/              batches being assembled (immutable once closed)
iCloud   Satellite/outbox/<dev>/batch-<ULID>.json   write-once; writer+deleter: phone
         Satellite/media/<dev>/<s2>/<sha256>.heic   write-once; writer+deleter: phone
         Satellite/ack/<dev>/batch-<ULID>.json      writer: desktop
         Satellite/snapshot/desk.json.gz            atomic replace; writer: desktop
Mac      the real box — THE single writer; drains at open (+ read-only FSEvents
         card mid-session, P20j watcher pattern: surfaces, never auto-applies)
```

Single-writer-per-file everywhere → iCloud has nothing to fork; a conflicted
copy anyway is byte-identical content that dedupes to a no-op. Transport is
dumb files, so a user who hates iCloud can point `Satellite/` at
Dropbox/Syncthing later.

### 2.2 The batch protocol

- Batch = `{v, batch: ULID, device: UUID, device_name, created (civil, no tz),
  items: [phone-native items]}`. Closed on resignActive / share completion;
  **immutable forever**; tmp+rename at every write site (verified same-volume).
  Unknown `v` at the drainer ⇒ hold the whole batch + "update Liv on this Mac"
  card — never partial-parse.
- External-id scheme: `ios://<device-uuid>/<item-uuid>` → lands as a real
  `EXTERNAL_ID` cell. **The phone never ships scraps** (no identity, no
  dedupe — the one duplication vector, closed by rule).
- Phase-1 lowering (desktop drainer, zero owner changes): idea →
  `{kind:"note", source_id, frontmatter:[[title],[liv_kind,"idea"]]}`; link →
  `{kind:"link"}` (URL dedupe); photo → bytes to sha-named media file, drainer
  hash-verifies (**verify-then-skip**, tmp+rename) then copies to the media
  home (§8) and lowers to `{kind:"file", path}` — SHA-256 dedupe makes every
  re-drain a no-op; caption → a note item whose body wikilinks `[[<sha>.heic]]`
  (in-batch resolution gives a real Ref span today). Task/event → note with
  **real typed `due`/`status` cells** (seeded user properties parse by declared
  kind — date views and status chips work day one) + `liv_kind` marking intent;
  TYPE stays `note` until phase 2 (frontmatter refuses core props — correct).
- Phase 2 (owner-gated, additive services diff, **no FFI change**):
  `ImportItem::Task/Event/Scrap{source_id}` serde-tagged variants; drainer
  flips its lowering table; field phones never update. Backlog retype = one
  explicit migration card (`liv_set_type_at`) or clerk proposals — owner's
  pick; nothing auto-mutates.
- Drain: readiness gate (any dataless file defers the *whole* batch — one
  batch stays one transaction), then one `liv_import_batch_at` call = **one
  desktop transaction = one undo = one card**: "From Konrad's iPhone: 5
  brought in (2 already here) · Undo". Transaction label carries provenance:
  `phone·<device8>#<ULID>` — the drained-set is rebuildable from the box
  alone. `imported == 0` acks silently. In vault mode the projection then
  materializes the new entities as markdown for free.
- Acks are an **optimization, not a correctness mechanism**: lose them all and
  the next drain self-heals to `imported: 0`. Forked ack copies max-merge
  (monotonic maxima). On ack, the phone marks items shipped, caches thumbs,
  deletes its own batch + media. Phone UI shows honest per-item
  **Pending → Uploaded → Delivered** states and "N drops waiting for your
  desk since <date>".
- Read-back: the desktop writes `desk.json.gz` (full snapshot, gzipped, atomic)
  after each open/drain; the phone renders a **read-only "At the desk" view**
  labeled "as of <time>". Echo-merge: snapshot entities whose external-id is
  `ios://<this-device>/…` collapse with the local shipped copy, desk version
  winning display. No write-back in v1 — "follow up" creates a new capture.
- Hard denylist: phone and drainer refuse to touch any path outside their
  declared `Satellite/` subtrees, and never anything matching `.liv*`/`.trash`.
- Cheap insurance (grafted from B, architecture-independent): desktop rotates
  a copy of `liv.log` into local `.liv/backups/` at open.
- Ship gate: crash-at-every-step property tests — random batches, kill the
  drainer mid-media-copy / mid-import / mid-ack, redeliver everything twice,
  assert convergence with zero duplicates and zero torn attachments.

### 2.3 Honest limits (v1)

- The desk mirror is as fresh as the last desktop open. Labeled, not hidden.
- No write-back: you cannot complete a desk task from the phone in v1. The
  stale mirror renders desk rows read-only with a desk glyph.
- Two desks: v1 declares **one home desk** (else first-ack cleanup silently
  starves desk #2 — must be resolved before the Windows drainer exists).
- Offline capture followed by immediate uninstall loses staged batches
  (App Group dies with the app) — irreducible without CloudKit; promote
  eagerly on every foreground.

## 3. P2 — tasks and notifications

- Task add/edit on the phone's own box: `liv_create_task_at` + `liv_set_at`
  / `liv_set_span_at`; status vocabulary is **dynamic** via
  `liv_status_options_at` (checkbox writes the `completes`-marked option,
  never a hardcoded "done"; hue from the option's cell).
- Notifications are **shell territory**: schedule local UNNotifications from
  the union of the phone box and the desk mirror — dues + events from
  `liv_snapshot_window_at` (window-capped expansion covers iOS's 64-slot
  budget), refreshed at open/foreground + opportunistic BGTask. No push infra,
  no daemons, core untouched; staleness is accepted ("absence creates no
  debt"). Flagged in §8 for an explicit ruling on the no-timers reading.
- The app icon badge carries the **proposal-inbox count only** — the app's one
  badge, by law.

## 4. P3 — messages — KILLED (2026-07-26)

Killed by owner decision. The rationale, recorded: every unified-inbox
product has died or pivoted; the connector fence was never opened; and the
mobile app's job is capture, not reading feeds. `liv_import_messages_at`
stays in the core (shipped and tested — deleting working code buys
nothing), but no phone or roadmap surface builds on it. Section number
kept so cross-references in the eval and earlier docs stay valid.

## 5. P4 — notes (later)

Phone note *capture* ships in P1 (notes travel as import items). Note
*editing/sync* waits for either: (a) vault-folder mediation for the markdown
class once 20j.8 + the fm-ingest whitelist land — with B's `liv_md_parse` /
`liv_md_patch` pure codec verbs (worth proposing independently: they also
serve the Windows port and prevent frontmatter-strip ping-pong); or (b) the C
oplog design as the eventual two-way destination. Content CAS
(`liv_set_content_at`, `-1` = stale ⇒ reload + keep local draft, never
force) is the phone editor's conflict primitive for its own box today.

## 6. Information architecture — desk-first, features as windows (rev 2, owner-directed 2026-07-22)

> Revision 2 (same day, superseding the two-mode toggle): **the body is
> always the Desk** — content tabs over entities, the Obsidian idioms.
> Features are transient **windows summoned from an always-present menu
> button**, presented over the whole chrome, bar included. No mode to be
> in; nothing to toggle back out of.

**Top bar**: far left the **workspace hub** — house glyph + workspace name
+ ⌄ (the desktop HomeHub; stamps defaults on new entities); far right the
**settings gear**.

> **Rev 4 (owner-directed, 2026-08-01): the three-zone model.** Tabs hold
> EDITABLE content and nothing else — a note is a tab, a view is a visit.
> The app has three zones with one door each:
> **left, the library** — a solid slide-over panel holding everything
> about the APP: workspace, the five views (Today/Everything/Inbox/Tasks/
> Calendar), capture doors, Settings. Opened by the top-left circle.
> **center, the desk** — one editable thing, full-bleed.
> **right, the item panel** — everything about THIS note: metadata
> (SCHEDULE/FILING/OTHER — never the content, which is the note itself,
> not one of its properties) and the item's verbs (Save as template,
> Undo, Move to Trash). Opened by the top-right circle.
> The `^` features menu is deleted; the bottom bar is ONE row (‹ ›
> search + [tabs]) and retires while a panel is up. Views stay cheap
> stateless projections over the box, so they need no persistence or
> instances mechanism — nothing tempts them back into the tab plane.
>
> **Rev 5 (owner-directed, 2026-08-02): describe vs act.** The top-right
> door is a **`•••` menu**, not the panel itself: *Properties* (opens the
> right panel), *Save as template*, *Move to Trash*. The panel is renamed
> **Properties** and now only DESCRIBES — the verbs left it for the menu,
> because a metadata inspector that also acts on the document blurs the
> line the menu exists to draw. The panel's old *Undo* is deleted
> outright: it was the box-level "undo last transaction" masquerading as
> a property undo, and undo-without-redo is a trap. Trash confirms, then
> closes the tab and offers **Undo on a transient chip** (5s) — the core
> has no restore verb, and undo-right-after IS restore precisely while
> the trash is the last transaction, which the shell guarantees by
> flushing the editor BEFORE trashing (a teardown flush after it would
> make the chip undo the wrong write — found live). *Save as template*
> acknowledges on the same chip. **Due** grew up: Today / Tomorrow /
> a real date picker / an opt-in time (a due is a DAY unless you add a
> clock; quick picks move the day and keep the time), plus Clear —
> commits as you pick, no Set button. The bottom bar also retires while
> a KEYBOARD is up: keyboard avoidance would park it on top of the
> editor's formatting row, two bars stacked over the keys.
>
> **Rev 6 (owner-directed 2026-08-03, with reference screenshots:
> Notesnook sidebar + editor, ClickUp Today/Tasks/dates, Apple
> Calendar).** The owner's principles, now standing law for this shell:
> *frequent actions get dedicated UI, never an overflow menu; minimize
> modal dialogs and interruptive menus; AI never acts without explicit
> approval; workspaces define context consistently via property
> filtering; ClickUp as visual/surface inspiration, kept simpler.*
> What changes:
>
> 1. **Both side panels are FULL-SCREEN and swiped into from anywhere**
>    (swipe right = library, swipe left = properties), plus their
>    doors. Notesnook sidebar is the layout model.
> 2. **The library reorganizes into three bands**: *Global* (Today,
>    Inbox) — views that ignore the workspace lens; *Workspace*
>    (Calendar, Tasks, Everything) — content views that FILTER by the
>    active workspace's query; *bottom, pinned* (workspace switcher,
>    Settings). The Camera row leaves the sidebar (owner: current
>    behaviour "seems useless"; scanning is future work) — the camera
>    stays reachable from the capture chooser.
> 3. **Workspace filtering becomes consistent**: the workspace-band
>    views apply the active workspace query to their rows, the same
>    lens capture already stamps with. A workspace = its tabs + its
>    filter, everywhere.
> 4. **Properties leaves the ••• menu** for a dedicated top-right door
>    (frequent action → dedicated UI) + the swipe. The ••• keeps only
>    secondary verbs: **Duplicate note** (new: a fresh note carrying
>    this note's property cells — filing context without the body),
>    Save as template, Move to Trash; Share/Export join later. The
>    owner's open question ("dual access from ••• too?") is answered
>    NO — a third path to the same panel is the unclean he suspected.
> 5. **The New Tab screen is an overlay, never a tab.** `+` opens a
>    full-screen chooser (create note / task / event / photo /
>    template / switch workspace); choosing creates the tab. An EMPTY
>    desk shows the same chooser as its body — the "desk is never
>    empty" invariant survives as "the empty desk IS the chooser".
> 6. **New-task flow simplifies** — the post-creation quick menu goes;
>    creation should be one uninterrupted gesture.
> 7. **The keyboard toolbar goes transparent** (Notesnook): the system
>    keyboard material shows through; it must never scroll vertically.
> 8. **Templates get a safeguard** (owner: "prone to misuse"): a
>    template opened on the desk wears a visible banner naming it a
>    template, whose primary action is "New note from this template" —
>    so editing-the-template-when-you-meant-a-copy stops being the
>    default trap. Considered alternative (a buried "default note
>    content" setting) rejected: an editable object beats a setting.
> 9. **"Apply Properties" rides the CLERK, not an LLM**: the Rust
>    clerk's deterministic proposals, reviewed in the Properties panel
>    — suggest, show the diff, apply only what the user accepts.
>    Nothing automatic, per the AI principle and the constitution's
>    quarantine.
> 10. Deferred, recorded as TBD: the Filter button, the Graph view,
>    Share/Export, ClickUp-style task relations.
>
> **Rev 7 (owner-directed 2026-08-05, roadmap phase 4): the day is an
> hour grid.** Apple Calendar's shape under the month navigator: an
> ALL-DAY band (timeless events as pills, timeless TASKS as pills that
> keep their status ring), then a scrollable 24-hour grid where a timed
> item is a positioned block, with a red now-line on today and the view
> opening at now (or 08:00 on another day). **Tap an empty hour** and an
> event is created AT that hour, landing as a desk tab for naming — the
> same capture-asks-nothing door the month grid's long-press uses for
> all-day events. A block's tap opens it; its time is changed in the
> Properties panel's due row (rev 5's editor: date, opt-in time, Clear).
> No scroll bar — the hour labels say where you are.
>
> **Drag-to-move, done in UIKit (owner: "do the UIKit drag properly").**
> Press a block, then move it: 15-minute steps, the block draws at the
> live minute while it is in the air, one `setSpan` on release. SwiftUI
> cannot express this — a vertical drag inside a vertically scrolling
> view never reaches the app. Instrumented live, all zero events: a
> plain `DragGesture` on the block, `LongPressGesture.sequenced(before:)`
> (Apple Calendar's grammar), and a `highPriorityGesture` on a grip; a
> Menu and a Button placed inside a block also lost their taps to the
> block's own tap.
>
> What works, and the two rules that make it work (`HourGridDrag`):
> a `UILongPressGestureRecognizer` on **the window**, not the block and
> not the scroll view — recognizers added to SwiftUI's hosting scroll
> view are never offered the touch (verified: `shouldBegin` was not
> called even for a real 0.8s press), while the window sees everything.
> (1) `gestureRecognizerShouldBegin` returns false unless the touch is
> inside a movable block, in the grid's own content space, so ordinary
> taps and scrolls never even reach the arbiter. (2)
> `shouldRecognizeSimultaneouslyWith` MUST return true — refusing it
> starved the scroll view's pan and the grid stopped scrolling entirely;
> safety comes instead from switching `isScrollEnabled` off for the
> duration of a lift. Block geometry is computed ONCE and shared by the
> renderer and the hit-test, so what you grab is what you see.
> Occurrences are not movable (moving one instance of a series is a
> recurrence edit). A drag is finger-only, so the same move is exposed
> as five accessibility actions (±15 min, ±1 h, Pick a time).
>
> **Rev 8 (roadmap phase 7, 2026-08-06): Share & Export.** The •••
> menu gains its two secondary residents. **Share** hands the note to
> the system share sheet as markdown text; **Export as Markdown** hands
> over a real `.md` file, so "Save to Files" produces markdown rather
> than a .txt of the same words. Both are READS — nothing is written to
> the box. Both flatten through `SpanText.spansToText`, the one
> flattener in the shell, and add an `# H1` title only when the note
> carries a name its first line does not already state (a file that
> opens "- [ ] milk" tells the reader nothing). The filename is the
> note's own name with the characters a filesystem argues about
> stripped, capped, and never empty — `liv-note-<id>.md` when there is
> no name. A sixth self-check suite (`-share.selfcheck 1`, 12
> assertions) pins the markdown and filename shaping. An empty note
> refuses to share rather than handing over a blank file.
>
> **Overlapping blocks split the width** instead of hiding each other
> (`CalLayout.slots`, pure and self-checked): a cluster of overlapping
> spans shares columns, greedily reusing a column as soon as it frees,
> and a block that merely starts where another ends gets the full width
> back.
>
> Two latent bugs fell out of the work: `-desk.boot <feature>` was being
> wiped a frame after it was set (the workspace-adopt onChange clears
> every overlay), so headless feature-view verification silently didn't
> work — the boot state now applies one hop later, and `calendar` and
> `everything` joined the roster. And labelling a container that carries
> children flattens the subtree for VoiceOver, which had hidden a
> block's status ring.
>
> **Shipped 2026-08-04** (all ten except the TBDs): full-screen swiped
> panels; the three-band library (Camera row removed); Everything now
> lensed — its old "never hides" rule retired by principle 3, chip worn;
> Today's occurrence loop was the one lens gap, closed; the ••• is
> secondary-only with the new **Duplicate note** (properties, not body;
> due copied structurally, never as its display string); the chooser
> overlay + empty-desk-is-the-chooser; direct task creation (its first
> line is its name — the CaptureSheet now serves only events); the
> transparent toolbar (known rule-2 delta on hardware keyboards,
> accepted); the template banner; and **Suggested** — the clerk's
> per-note proposals in the Properties panel with per-proposal ✓/✗,
> gated by the assist consent switch now toggleable in Settings (the
> ONE Settings row that writes a cell, because consent lives in the box
> and both shells must agree about it). The clerk is deterministic Rust
> (regex-grade proposers, no model, no network) — "AI" property
> application per the owner's flow, with the LLM tier still quarantined.

**Bottom bar** (rev 4: one row — ‹ › search + [tab count]; the features
button is gone, features live in the library):

- Far left, always: the **features button** (`^`) — opens the feature menu
  (ClickUp "More" idiom): Today, Everything, Inbox, Tasks, Calendar,
  Capture, Camera. It carries the amber proposal-count badge (the app's
  only badge — Inbox lives behind this menu). **Selecting a feature opens
  it as a window covering everything**, dismissed by its `v`, by dragging
  its header down, or by opening a row (which lands as a Desk tab).
- Right of it, one pill, always present (copy Obsidian): **‹ › search +
  [tab count]** — back/forward over tab-activation history (greyed when
  empty), the global Liv search, new tab (the capture door), and the
  tab-count square opening the card switcher (previews, ✕ per card,
  "N tabs", Done).

**The body** is the active Desk tab: an entity (content + the metadata
collapse button) or the New-tab verb stack. **Opening any row anywhere —
in a feature window, search, the switcher — lands it as a Desk tab** and
dismisses whatever summoned it. Desk tabs + activation history persist per
device (transient shell state, never cells).

**Four chrome rules (owner, 2026-07-29).**

1. The `^` menu is a **solid panel pinned to the bottom edge that covers
   the bar it was summoned from**. Its own far-left `v` sits exactly where
   the `^` sits, so the toggle never appears to move.
2. **No translucency anywhere.** Blur materials are gone from the bar, the
   menu and the camera chrome; every floating surface is an opaque theme
   colour. Nothing underneath may read through.
3. **A feature window and the tab view each take the entire screen** — top
   bar and bottom bar both covered, no sheet inset, no strip of desk above,
   no grabber. A feature window carries a 40pt header whose one control is
   the `v` that closes it (that header also accepts a downward drag); the
   tab view carries the same header, and its `+ | N tabs | Done` footer is a
   second way out. That top band is not decoration — a scroll view touching
   the top safe area draws its content through it, so without a band ahead
   of it a scrolled row collides with the clock and the Dynamic Island.
   A full-width header must also BE the control it advertises: SwiftUI
   merges the band into one accessibility element whose activation point is
   the band's centre, so wiring only the glyph leaves Voice Control and
   Switch Control with no way to close a full-screen surface.
4. **Hide what the moment does not need; keep it one action away.**
   (Owner, 2026-07-30; sharpened 2026-07-31.) While you write, the note is
   the screen: the persistent top bar is gone (Workspace and Settings live
   behind the desk's floating `…`), the two floating circles stay put in
   every state (owner, 2026-08-01 — they are the constant), the
   advisory notices and status line hide, and the DETAILS row and meta
   line are gone from the editing view entirely — properties live behind
   the metadata chevron. Every note carries an Obsidian-style title line
   that is PART OF THE NOTE, not a header: it lives inside the editor's
   own scroll view, starts below the floating circles, and slides up under
   them as you read (owner, 2026-08-01).
   the name cell when a human has set it, else the DERIVED title (first
   content line, markers stripped) as a grey suggestion — display-only,
   never written to the box, so the name cell's absence itself records
   that the user has not titled it, and nothing automatic can ever
   overwrite a human title. A new note focuses the BODY, never the title,
   and an empty note is a blinking caret — no placeholder text in the
   BODY. Amended 2026-08-06: the TITLE line does show a grey "Untitled"
   when the note has no name, so it reads the same there as it does in
   every list (owner).
   Formatting is one scrollable toolbar riding
   DIRECTLY above the keyboard (the Bear shape — the owner tried the
   hidden-`Aa` panel of 2026-07-30 and rejected it); the keyboard covers
   the bottom bar. No explanatory micro-text anywhere in the chrome.

5. **One motion.** Navigation areas move from and into view — one curve,
   one duration (`LivMotion.nav`), no rotations, no combined fades, no
   springs. Calm beats clever.

**Metadata**: when the current body shows something that carries metadata,
a **collapse button sits at the top-right of the body** (the Obsidian
properties-chevron idiom). Tapping it slides the **metadata editor** over the
whole body — the desktop right-panel inspector, full-bleed: title, property
rows, three-layer pickers, add-property. Tapping again (or the chevron
reversing) collapses back to content. One editor everywhere; no per-feature
forms.

Deep links unchanged: `liv://capture`, `liv://capture/photo`, `liv://inbox`,
`liv://entity/<id>` (opens as a Desk tab), … used by widgets, quick actions,
and notifications. (Naming note: the read-only desktop mirror from §2.2 is
surfaced as **"On the Mac"** — never "desk" — to keep it distinct from Desk
view.)

Surfaces (bodies; mockups in the artifact):

- **Today** — 7-day date strip; compact 2×2 count tiles (Today / Overdue /
  Upcoming / Pinned); merged agenda (events by civil time, then dues, then a
  collapsed "Captured today" strip). Swipe right = reschedule
  (Tonight/Tomorrow/Weekend/Pick), swipe left = status (first two dynamic
  options + …). Desk-mirror rows read-only with a desk glyph. **Inline
  quick-add under the selected day** (absorbed from ClickUp's agenda "New"
  row, eval §4.1): a ghost row beneath the agenda; typing a name creates a
  task whose **due is inherited from the selected day** (date-only) —
  task-with-due in ~3 gestures, no picker on the dominant path.
- **New tab (the capture door)** — Desk `+` opens it; verbs Capture idea /
  New task / New event / Photo / Open…. One field, asks nothing, **no token
  grammar** (refused by law — typed `due:` stays literal text). Chips unlock
  **after** save: +Tag +Project +Person +Due +Type via the three-layer picker
  (used values → seed → create-new); the saved entity becomes this tab's
  content. Draft survives every interruption; field clears only on confirmed
  commit. **Serial capture is a persistent sheet** (absorbed from ClickUp's
  create-and-start-another, eval §4.2, replacing the old "Another" button):
  save clears the field and keeps the sheet, the confirmation collapses to a
  tappable toast, and **serial captures reuse one Desk tab** — the tab-hygiene
  rule answering eval §3(b)1. Lands with the capture-path bug-fix pass.
- **Camera flow** — shutter first: bytes land in the App Group and
  `liv_add_file_at` commits **at the shutter sound**; a post-shot tray
  (thumbnails, optional caption, chip row, "apply to all (n)") tags while the
  viewfinder stays live.
- **Inbox** — Route lens (untyped scraps; type verbs convert in place, then
  type-appropriate chips) and Tidy lens (clerk proposals, amber; swipe right =
  accept, left = reject; "Accept all" → `liv_accept_group_at`). The phone
  runs the same deterministic at-open sweep (§8 flag).
- **Tasks** — count tiles over a status-grouped flat list; groups from the
  vocabulary in vocabulary order; `completes` groups collapsed; inline
  quick-add into the active group.
- **Calendar** — month grid (≤3 neutral dots per day, today ringed) over a
  fixed day panel (all-day pills, timed rows, occurrences with a repeat glyph
  opening the *series*). `liv_snapshot_window_at` over the visible range
  only.
- **Desk tab body (entity)** — content first (spans model, Ref spans
  navigate = open as another tab; CAS editor); the metadata collapse button
  top-right opens the full-body inspector (property rows, pickers,
  add-property, trash/undo); history lens later.

  > **Rev 16 (2026-08-11): the codec writes the core's blocks.** Until
  > now the phone stored markdown markers as literal text — every line a
  > Body paragraph, `## Title` saved as the characters `## Title` (the
  > recorded deviation from D19, which the core's own
  > `services/src/tasks.rs` grew a second read-form to tolerate). The
  > codec now derives each line's block through `MarkScan.shape` — the
  > SAME scanner the styler renders with, so screen and box can never
  > disagree — and each delimiter pair through `MarkScan.inline` into
  > mark bits. Markers live only in the buffer; the box stores
  > `Heading/Task/Bullet/Ordered/Quote/Rule` and marks. Rendering is
  > untouched. Legacy notes convert wholesale on their first edit —
  > verified live: one checkbox toggle from the Tasks view rewrote a
  > seeded literal note into 7 structural breaks with the toggled line
  > done. What still flattens (banner-gated, never silent): Code fences,
  > Callouts, combined marks, and any marked run whose rendered form the
  > scanner would not re-derive — decided by rendering and rescanning,
  > not by delimiter arithmetic. Canonicalisations pinned in the
  > self-check: rule variants → `---`, `>x` gains its space, odd indents
  > floor to two-space units, ordered numbers renumber from 1 per run,
  > a tab becomes two spaces, `* ` becomes `- `, an indented heading or
  > quote loses its indent, and depth clamps at 15.
  >
  > The banner is computed by RENDERING AND RESCANNING with the same
  > `name` and `isKnown` closures the save uses — reasoning about cases
  > leaked twice (a trailing `*` inside bold; a Body paragraph whose
  > text begins `# `, which the Rust importer produces from `\#`).
- **Search (global magnifier)** — full-screen overlay from anywhere: pill
  bar, `liv_search_at`, kind-grouped flat rows, pinned capsules; a result
  opens as a Desk tab. **Find-or-create** (absorbed from Obsidian's quick
  switcher, eval §4.3): a non-matching query offers "Create '<query>'" —
  captures the text as a scrap and opens it as a tab; retrieval and capture
  share one 3-gesture surface.
- **Settings** — box info, Handoff status (per-item ledger + hazard card),
  assist switch, notification prefs (64-cap honesty footer), appearance.
  Settings never write cells.
- **Share extension** — save-first, chips after; links via one-item import
  batches (URL dedupe), text as notes with `ios-share://` source_ids, images
  staged then hashed. Busy flock ⇒ spool JSON drained by the main app.
- **Widgets** — lock-screen capture/camera circulars, next-due rectangular,
  medium Today with interactive checkboxes (App Intents against the App Group
  box); honest "as of" staleness footer.

> **Theme delta (owner, 2026-07-31):** the lake-green identity is retired
> ("yuck", verbatim). The app wears a generic dark theme — neutral dark
> greys, the system blue as the one accent — and renders dark regardless
> of the system setting. `interface.md`'s lake-green law is superseded for
> the phone by this delta; recorded here rather than by rewriting history.

## 7. Visual design

**The palette is the app icon's, to a measured floor (rev 18, owner
2026-08-15).** Three arms — violet, pink, amber — used as three hue
families: violet is chrome and notes, pink is tasks and people, amber is
events, files and captures. No blue, no cyan, no green in the kinds;
none is in the mark. Every colour clears 7:1 against its own ground in
both schemes, asserted by `-palette.selfcheck 1`. Soft fills are opaque
tints mixed into the ground (`LivTheme.tint`), never `.opacity` over
whatever is behind. The accent and the note tone are one step apart on
the same arm, and the check refuses to let them merge.


Structure from ClickUp mobile; soul, tokens, and density from Liv:

- ThemeSpec token system ports 1:1 (`UIColor(dynamicProvider:)`) —
  brand-light / brand-dark as system light/dark. Neutral chips + 6pt semantic
  dots (FNV-1a-64 mod 5, frozen vectors — port verbatim); amber = AI presence
  only; status hue from the option entity. No per-tag rainbow, no pastel tile
  tints, one accent.
- Compact on purpose: 44pt touch minimums, but 40–44pt rows, hairline
  separators, tonal elevation, no card chrome, no shadows except floaters.
  SF Pro / SF Symbols.
- **Accent — DECIDED (owner, 2026-07-22): lake green `#2f7d6b`** (a lighter
  `#5CB596`-family tone on dark grounds), per the CLAUDE.md law. The desktop's
  P20 Viggo violet stays a desktop-theme concern; the phone wears lake green.
  The mockups' accent toggle defaults to it.

## 8. Owner decisions (consolidated)

1. ~~**Accent era**~~ **DECIDED 2026-07-22: lake green** (the CLAUDE.md law;
   desktop's Viggo violet is a desktop-theme concern).
2. **Phase-2 services ask**: additive `ImportItem::Task/Event/Scrap{source_id}`
   variants (test-first, wire-compatible, no FFI signature change).
3. **Media home**: `<root>/library/images/` (pre-positioned for 20j.8 — needs
   confirmation that 20j.8 adoption grandfathers sha-named files) vs
   `~/liv/attachments/` (safe, outside the vault story).
4. **Backlog retype gesture**: one bulk migration card vs clerk proposals.
5. **Snapshot privacy**: filter PRIVATE entities from `desk.json.gz`, encrypt
   it, or make the mirror opt-in (it lands in iCloud).
6. **Multi-desk policy**: single home desk in v1 vs N-day retention past first
   ack — must be decided before a Windows drainer exists.
7. **No-daemons boundary**: is a login-time helper that briefly drains + 
   refreshes the snapshot acceptable, or drain-at-open only (default)?
   Relatedly: an explicit ruling that shell-scheduled local notifications
   don't violate "nothing runs on a timer" (core never writes on one).
8. **Clerk on the phone**: does the deterministic at-open sweep run on-device
   (portable, proposals-only) or is triage desktop-only?
9. **Scrap fidelity**: accept note-typed quick captures in phase 1 (with
   `liv_kind:"idea"`), erased by the phase-2 `Scrap{source_id}` variant.
10. **Starved-batch escape hatch** (owner-gated UX): after N days stuck on one
    undownloaded photo, offer split-import with a sha-named placeholder that
    self-heals when bytes arrive.
11. **Provisioning**: iCloud container id, App Group id, entitlements.
12. Desktop drainer + snapshot exporter live in `shell/macos` — landed as a
    reviewed PR, never direct edits (boundary table); `shell/ios/` gets its own
    row in CLAUDE.md.

## 9. Build order (proposed)

- **M1 — the box on the phone**: build script; App Group box; Capture sheet +
  camera flow + share extension; Today/Tasks over the local box. *Ships value
  with zero sync.*
  **Status 2026-07-22: shell/ios/ exists and runs in the iPhone simulator**
  (hand-rolled `build.sh` in the macOS shell's style — staticlib + one swiftc
  + `simctl`; `./build.sh run`). Shipped: Box.swift (serial queue, throwing
  tolerant decoder, probe/backoff), BoxPath (App Group with sandbox + env
  fallbacks), lake-green Theme + Kit (frozen FNV-1a vectors verified), Today,
  Tasks, Capture sheet, Camera flow (PhotosPicker stand-in on simulator),
  Inbox Route lens, Search, minimal Detail, persistent PillBar. Verified
  end-to-end: app seeds its box; a CLI capture into the same box renders in
  the UI after relaunch. **Remaining for M1:** the share extension + App
  Group entitlements still need a real Xcode project (hand-rolled bundles
  can't carry them), and hands-on QA of the gesture wiring (swipes, chips,
  camera) which headless simctl can't drive.
  **Update 2026-08-02 — device builds work WITHOUT a project.**
  `./build.sh device run` builds for `aarch64-apple-ios`, signs, and
  installs on the owner's iPhone via `devicectl`. One-time bootstrap
  (done): a throwaway Xcode project with bundle id `app.liv.ios` +
  "Automatically manage signing" + one Run on the phone, which mints the
  Apple Development certificate (keychain) and the provisioning profile
  (`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`); the
  script finds both by itself and the throwaway project can be deleted.
  Lesson recorded in the script: link the Rust seam by explicit
  `libliv_ffi.a` path, never `-L … -lliv_ffi` — with both .a and .dylib
  in the target dir the linker silently picks the dylib, whose absolute
  Mac path is meaningless on the phone (launch crash: "Library not
  loaded"). The simulator never caught it because the simulator IS the
  Mac.
- **M2 — the funnel**: outbox projector, shipper, ack processor; desktop
  drainer + drain UX + snapshot exporter (PR); property-test gate. *P1
  complete.*
  **Delta 2026-07-26 (M2 start):** the drainer + snapshot exporter land as
  **CLI verbs** (`liv drain <satellite-root>`, `liv satellite-export`) —
  headless-testable today, desk-agnostic (works for the SwiftUI shell, the
  Tauri pivot, or bare CLI), and the shell's drain UX becomes a thin wrapper
  later. Transport v1 is a **plain folder** (`LIV_SATELLITE_PATH`); the
  iCloud ubiquity container is the same protocol at a different path once
  real entitlements exist. §8 defaults adopted pending owner word: media →
  `~/liv/attachments/`, single home desk, mirror privacy deferred while the
  transport is a local folder.
### Reordered 2026-07-26 (owner): the app first, sync last

The owner's ruling: **notes, workspaces and filters come before any more
sync.** "Sync comes last, when we have what I just listed in a somewhat
good working order." M2 stays shipped (it works), but the *rest* of the
sync programme — the read-back mirror, iCloud transport, phase-2 import
fidelity — moves behind the app itself. Rationale, stated plainly: a
phone that can capture a thought but cannot read it back is a dictation
box, not a notes app. That hole is bigger than notifications.

- **M3 — notes on the phone** *(next)*: read and edit note content in the
  phone's own box — `liv_content_at` / `liv_set_content_at` with the
  fingerprint compare-and-swap the core already provides (a stale save is
  refused, never forced). No sync needed for any of it. Then **templates**
  as a small follow-on (a template is an object you copy; the daily-note
  get-or-create is half of it already).
- **M4 — workspaces + filters**: the workspace hub becomes real (today it
  is a one-workspace placeholder). Design, per the owner 2026-07-26 and
  Viktor's D14/D22:

  **The data model (settled 2026-07-26, after reading the core).**
  A workspace is an entity carrying **one `query` cell** — core property
  id 9, `props::QUERY`, the same property saved views already use. The
  query is a search-DSL string, e.g. `area:Work project:Viggo`.

  That one cell is both halves of the owner's model:
  - **The lens** = run the query.
  - **The stamp** = the query's plain `key:value` equality terms, written
    as cells on objects created while the workspace is active. Terms that
    are not plain equality (`-tag:old`, `due<20260801`, `has:x`) filter
    but never stamp — they have no single value to write.

  Why this shape and not the obvious alternatives:
  - *Not* a hardcoded Area+Project pair: any property works, so "client X,
    tier 1" is a string edit, never a code change.
  - *Not* "the workspace's own user-property cells are its defaults" —
    that was the first design and it is **wrong**: `create_workspace`
    already writes `parent` and `order` as user-space properties
    (`services/src/content.rs`), so those structural cells would be
    mistaken for defaults and stamped onto every new object.
  - `query` is a **core** property (id < 4096), so it can never collide
    with a user property, and one parser serves both the lens and the
    stamp. No new FFI verbs: `liv_create_workspace_at` + one `liv_set_at`.
  - Saved filters are the same thing minus the stamp: view entities with
    a `query` cell (`liv_create_view_at` already writes exactly this).
    **A workspace is a saved view that also stamps** — one grammar, one
    parser, one mental model.
  - Defaults are stamped on new objects as a **visible, removable chip** —
    never a silent write (P12 §1.4 refuses silent capture-time stamping).
  - **The Inbox ignores the workspace filter, always.** Unfiled things are
    visible from everywhere. This is the safety valve against the classic
    "I captured it and it vanished" bug that hits every workspace system.
  - **One tab plane** whose *open set* is remembered per workspace (the
    owner's clarification: per-workspace tabs, never per-workspace tab
    *bars* — that was the old app's three-tab-system debt, and D18 kills
    it). Opening something from search or the inbox joins the current
    workspace's set.
  - Filters are saved view entities holding a query string (the core has
    them). **One filter grammar everywhere** — search, tasks, files.
- **M5 — P2 time**: notification scheduler; widgets + App Intents;
  Calendar surface.
  **Status 2026-07-28: scheduler + Calendar shipped** (commit b9593be —
  reminders fire and were delivered live; the clamp and the
  kinds-or-status predicate fixes rode along). Widgets + App Intents
  remain Xcode-gated, with the share extension.
- **M6 — sync, the rest of it**: the read-back "On the Mac" mirror; iCloud
  transport (needs the Xcode project's entitlements); phase-2
  `ImportItem` variants + the retype card; the provenance label ask
  (services, additive, test-first — see the M2 commit's known delta).
- **Later** — P4 note sync via vault mediation / oplog destination.
  (P3 messages: killed 2026-07-26, see §4.)

## 10. The furnishing (M5-furnish, owner thesis 2026-07-27)

The app arrives furnished (design/what-liv-is-for.md v2). The furniture is
the RESEARCHED convergence of proven systems (PARA, GTD, Things 3, Wheel
of Life, the Notion template canon — see the furnish-research pass), not
invention. All of it lands from the SHELL via existing verbs, idempotently,
per-item-guarded like the core seed; services stays untouched.

- **Six areas as workspaces** — Work 💼 · Health 💪 · Money 💰 · Home 🏠 ·
  Family & Friends ❤️ · Learning 📚 — each a workspace whose query is
  `area:<Name>` (quoted where spaced), so the M4 switcher IS the area
  switcher: one concept, lens + stamp. The protected builtin Home
  workspace BECOMES the Home area (gains query + emoji) — never a second
  "Home" beside it.
- **The `area` property** — select, exactly six options, no create-new in
  its picker. The one filing question is "which part of life?"
- **`project`, `subjects`, `people`** — text properties, created at
  furnish time. This also fixes a real fresh-box bug: the capture-sheet
  and camera chips currently write NOTHING on a fresh box (the properties
  don't exist; `set` refuses; the chip shows success anyway).
- **Values stay open where life varies**: project/tag/people pickers keep
  create-new, LAST. The Type picker is the six kinds, no create. The
  inspector's "+ property" (schema growth) moves behind the Settings door.
- **No trackers, no review ceremonies, no Someday list** — the research's
  documented failure modes (classification ambiguity, ritual burnout,
  property sprawl, graveyard lists) are honored by absence. Groceries and
  habits are recorded as proven candidates, deliberately deferred.
- Idempotence: presence-checked per item against the snapshot on every
  launch (the seed's own pattern) — reinstall-safe, existing boxes simply
  gain what's missing, nothing ever duplicates.

## 11. Two tab shapes: document vs record (rev 9, owner 2026-08-06)

The desk edited everything as a document. Opening a task gave you a
markdown buffer whose first line was the task's name, a keyboard
toolbar offering headings and dividers, and the due date hidden behind
a swipe. The owner: *"things that aren't documents should not be edited
like a document."*

**The rule.** `TabShape.of(row)` (Record.swift) is the single decision:

| kinds | shape | body |
|---|---|---|
| contains `note` | document | `NoteEditor` |
| empty (a scrap) | document | `NoteEditor` — its title IS its first line |
| anything else | record | `RecordBody` |

**A record is a name, its facts, and notes.** The name is a one-line
field that commits on return or blur — never line 1 of a buffer. The
facts are `EntityInspector(scrolls: false)`, the very same rows the (i)
panel shows: on a task the due date IS the content, so it belongs in
the body, not behind a door. Notes are **the note editor itself**,
embedded without its title line (rev 15, 2026-08-10).

> *Superseded:* notes used to be a plain `TextEditor` over
> `NoteEditorModel`, on the reasoning that the debounce, CAS guard and
> flush came for free while "the markdown apparatus deliberately does
> not". The owner asked why: *"There is already a note editor. Can this
> and other app mechanisms be reused?"* It can, and the old reasoning
> was wrong twice. A record's notes are content spans on the record
> entity — the SAME data a note's body is — so the plain field was not
> a different kind of thing, only a worse way of editing the same
> thing. And what it withheld is exactly what a task wants: a
> **checklist**, and a **[[link]]** to the note or project it belongs
> to. `MarkdownTextView(showsTitle:)` and `MarkdownEditor.embedded`
> carry the difference; the card supplies the name, the editor supplies
> everything else, and the second text editor is deleted.

**What follows from the rule.** On a record the (i) door and the
left-swipe are suppressed (they would open a copy of the screen), and
••• keeps only Duplicate and Move to Trash — you do not save a task as
a template, and exporting one as markdown yields a heading with nothing
under it.

**A record with no name cell** shows its derived title as the PROMPT,
not as text. It reads correctly and writes nothing; typing over it is
what mints the name cell.

**Naming happens where the thing lives.** Tapping an hour in the
calendar draws a draft block with a name field in it. The box learns
nothing until submit; an empty submit discards. This replaced
create-then-open-the-editor, which wrote an untitled event before
anyone had decided there would be one.

## 12. The type scale, dates, and what a row is for (rev 10, owner 2026-08-06)

**Type.** One recipe for every section header: 13pt semibold, letter
spacing 0.3, `text2`, uppercased (`SectionLabel`, Kit.swift). Nothing in
the app writes its own header. The floor stays 11pt and is now actually
held: the five 9.5pt copies and the two 9pt calendar labels are gone.

The quietest grey is #8E8E93, not #707078. The old value read at 3.7:1
against the canvas, under the 4.5:1 readability minimum, and it carried
text in 36 places including the sentence shown on an empty screen.

Screen titles are still absent by design — the top bar was deleted in
"the chrome retreats" and the feature window's whole 40pt header band is
the close control (§6). If screens ever get titles they go inside the
scroll content, never in that band.

**Dates.** Two questions, two groups. WHICH DAY: Today, Tomorrow and
"Choose a date", all three the same kind of row, because they answer the
same question — three different faces implied a grouping that did not
exist. "Choose a date" opens a month calendar under itself rather than a
small popup, so it is a real button like its neighbours. WHAT TIME: its
own group, always present.

**A due date carries a clock time, and the default is 09:00.** The old
"no time" state had to invent a time somewhere and it invented 09:00
inside the reminder code, where nobody could see or change it. Now one
constant says it out loud: `LivDue.defaultHHMM`. Reminders ring at the
due moment; there are no lead times.

**All-day belongs to EVENTS, not tasks** (`LivDue.carriesTime`). A
holiday is not due at 09:00, so an all-day event keeps its all-day-ness
when you change only its day; touching the clock is what gives it a
time. A task always gets a moment, because a task with no clock time
cannot ring, and ringing is most of what its date is for. A due with no
clock time schedules no reminder at all.

**A row is for something you can change.** The properties panel's rows
are editable fields and nothing else. The top line names the ITEM —
grey "Untitled" when it has no name — with the type as a chip below it.
Facts you cannot change (the type, the creation time) are a chip and a
quiet line, never a row: a row that looks like every other row and does
nothing when tapped is a lie about what the list is for.

## 13. Option C: a tab is a document (rev 11, owner 2026-08-08)

Supersedes §11's record TAB. The shape rule survives; where it opens
changed.

**A tab holds a document.** Notes and untyped captures. Nothing else,
ever.

**A record is edited where you stand.** Tapping a task or event anywhere
raises a card over the current surface and closes nothing. The card's
body is `RecordBody` — name field, the inspector's own rows, notes — at
medium height, because a record's facts fill a card and not a screen.

**A record is born where you stand.** The calendar names new events in
the grid; the quick-add rows name tasks in place. The create menu's
"New task" opens the card with the caret already in the name.

**The mechanics that matter.**

- `DeskModel.shapeOf` reads the live snapshot. Never cache the kind at
  open() time: `Box.actId` calls its completion before the snapshot
  refreshes, so a fresh record would look like a document for a frame.
- Exactly ONE surface may host the card (`recordCardHost(active:)`).
  UIKit gives a presenter one presentation; the desk raising a card
  while a full-screen view is up tears that view down, which is the
  context exit this whole change removes.
- A swiped-away card minimises to a pill, one at a time. It is pure
  navigation — every record edit writes immediately.
- Saved tab sets from before this change may hold records; they close
  quietly on the first snapshot.

**Vocabulary.** The word "scrap" was never the owner's. The concept — an
untyped capture the Inbox routes — stays, because it IS
capture-costs-nothing. The visible word is "capture".

## 14. Files (rev 12, owner 2026-08-09)

**A file of any format is an ordinary entity.** The bytes stay as a
file; the box records a reference — the path plus a hash of the content
— and the same six fields everything else carries. Filing a contract is
filing, not foldering: area, project, people, due, status, subjects, and
the workspace lens applies to it like anything else.

**Having a file crosscuts the six kinds.** There is no seventh "File"
kind. A scanned contract is a file AND can be a task. `TabShape.of`
checks for a file cell FIRST, because what you want to see is the
contract.

**A file keeps a tab.** §13 says a tab is a document; a file is a
document you work on. The tab law reads "things you work on" — records
are the exception, not files.

**Liv never writes foreign bytes.** It previews (Apple's own renderer
handles .docx, .xlsx, .pptx, .pdf and images offline and for free),
hands off with "Open in…", and re-hashes on open — a changed hash IS
the integration. No watcher, no timer, no sync engine. That means the
phone's loop is: open in Word, save, come back, and Liv notices. There
is no silent round-trip on iOS and pretending otherwise would be a lie.

**A phone import copies; the desktop references in place.** The picker
returns a path inside another app's container, readable only for the
length of that callback — recorded, it yields an entity whose file is
gone the next time you look (verified live before the copy was added).
So `FileStore.adopt` copies into Liv's own store, exactly as the camera
already does, and Liv's copy becomes the truth. The same core verb
serves both platforms; the difference lives in the shell.

**One glyph table**, keyed off the format for files. Two had drifted and
the same file wore different icons in two lists. It lives in `LivKind`
now (§15).

**No query is ever shown or typed** (owner, 2026-08-14). The Advanced
field is deleted from both forms; a workspace and a filter are made of
pickers — a name, an area, a subject. The grammar remains as the
invisible storage the core reads, and is due to be replaced.

**Markdown is not a foreign format** (owner, 2026-08-13). A .md added
through any door becomes a NOTE, with its words in the box; only formats
Liv cannot be is a file. `NoteBytes` (Files.swift) holds the list, which
is markdown and nothing else — `.txt`, `.tex` and `.bib` are somebody
else's text and stay files. This does not weaken "Liv never writes your
bytes": the words are copied in once, at the door, and nothing is ever
written back.

**A file tab is its NAME and its filing** (owner, 2026-08-13: the
preview "is absolutely useless"). No render of the bytes, in any format:
QuickLook, the extracted-text fallback and the empty-state hint are all
deleted. Reading a foreign file means opening the app that owns it,
••• → "Open in…". Its facts still live behind the (i) door like a
note's, and a property view still never renders file contents.

**The panel drag is a UIKit recognizer** (PanelDrag.swift; the
HourGridDrag recipe), and the drag-never-presses rule is enforced in
SwiftUI, not UIKit: the desk disables its whole tree while a drag is
latched, which cancels any in-flight press. This is the one mechanism
that works — touch cancellation, recognizer exclusion, and delayed
delivery were each tried and each failed to reach SwiftUI's buttons
(2026-08-09). A tap never latches, so taps are never disabled. The
recognizer refuses to start on horizontal scrollers and text-selection
chrome, allows the outer 24pt of either screen edge regardless (a file
tab is one full-bleed scroller), settles by where you stopped or a real
flick (700pt/s), and honours `-drag.off 1`.


## 25. Both panels are curtains (rev 28, owner 2026-08-16)

Owner: *"make library a curtain like before. i want to rethink what ive
told you today, more later."*

Rev 23's strip — the library pushing the desk a screen sideways — is
withdrawn. Both panels slide over a desk that does not move. Nothing
travels, so `deskShift`/`deskTravel` are deleted; the chrome painted
above the panels fades by the progress of the curtain that covers it
(`libraryCurtain`, `curtain`).

The rest of 2026-08-15's surface work is on hold at the owner's word,
pending a rethink.

## 24. The system's surface, until ours is earned (rev 27, owner 2026-08-16)

Owner: *"revert colors and faces to as system like as possible. we
should do the surface appearance last and thoroughly."*

**Colour is the system's semantic set.** `LivTheme` and `LivInk` resolve
to `systemBackground`, `secondarySystemBackground`, `label`,
`secondaryLabel`, `tertiaryLabel`, `separator`, `tintColor` and the
system hues. The icon-derived palette of rev 20 is withdrawn — not
wrong, early. The token NAMES stay: when the surface pass comes it
changes the right-hand side of those lines and nothing else, which is
what colour-in-a-type is for (standing rule 3).

**One panel recipe.** Rev 25's split (a card for the properties panel, a
place for the library) is withdrawn too: both are full-height panels on
the app's ground, both carry the same 56pt band. The distinction that
survives is MOTION — the library pushes the desk away, the properties
panel curtains over it — because it costs nothing and it is true.

**The contrast rule follows the palette.** Ink 4.5:1 on the ground; ink
on the tint 3:1; marks are not held to a contrast floor at all, but no
two kinds may LOOK ALIKE (a colour distance, both schemes). When the
palette is ours again, ink goes back to 7:1 and marks gain a 3:1 floor.

## 23. A view opens in the library (rev 26, owner 2026-08-15)

Owner: *"do the views opening inside the library."*

The five views were full-screen covers over the desk. They open INSIDE
the library now, which is what makes the library a place rather than a
menu of places: you are in it, looking at Today, with the desk parked
beside you. Consequences, all of them wanted:

- The desk keeps its state while you are in a view, and the swipe back
  to it is the same swipe as ever.
- `FeatureWindow` is deleted; the library's own top band carries the
  back chevron, and the root's record-card host draws cards raised from
  a view (verified: a task tapped in Today raises its card over the
  library).
- `deskInFront` no longer counts `featureShown` — a view is not a cover.
- `DeskModel.show(_:)` is the one door into a view: it opens the view
  AND the library, because going to a view means going to the library.

**The library's motion.** `setLibrary(_:)` mounts the place one beat
before it moves (`libraryDrawn` → `libraryShown`), because a view
inserted at its final offset has nowhere to travel from and SwiftUI
falls back to a fade — the rule the one menu learned in rev 19.

**The library door is always visible**, including under the properties
card, and always means "go to the library": with the card up it puts the
card away first, then slides.

**The workspace switcher hangs from its own button** (`livTopSheet`,
Menu.swift) rather than rising from the bottom as a sheet. Same motion,
scrim and card as the one menu; it hugs its content up to 72% of the
screen.

## 22. Two places, one layer (rev 25, owner 2026-08-15)

Owner: *"the left 'panel' is really a separate main place of the app,
the other being desk. how can we make it more like so and less visually
like the property panel, which really is a panel belonging to desk."*

The three-zone model of §6 rev 6 called both of them panels, and one
`SidePanel` recipe drew both. They are not the same kind of thing:

|  | the LIBRARY | the PROPERTIES panel |
|---|---|---|
| what it is | a PLACE, the desk's peer | a LAYER of the desk |
| ground | `canvas` — the floor the desk stands on | `surface` — a card on top |
| edges | corner to corner, no radius, no shadow | rounded leading corner (`radiusLg`), shadow |
| top | full height | starts below the desk's top band, which stays lit |
| motion | pushes the desk off screen (rev 23) | a curtain over a desk that does not move |
| leaving | swipe back, or the door | swipe back |

`LibraryPlace` and `SidePanel` are the two recipes (Panel.swift). The
rule to keep: **a place stands on the app's ground; a layer floats on
`surface` and never covers the chrome of what it belongs to.**

Still open, and the owner's to decide: whether a view (Today, Tasks,
Calendar…) should open INSIDE the library's cell rather than as a
full-screen cover over the desk. That is the version where the library
is fully a place — you would be in it, not visiting it — and it is a
structural change, not a paint one.

## 21. A frame of dragging moves one number (rev 24, owner 2026-08-15)

Owner: *"minicalendar lags when dragged."*

**The rule this leaves behind: what a finger changes must be the ONLY
thing that changes.** The mini calendar's drag offset was `@State` on
the whole calendar screen, so a touch-move rebuilt the day buckets, 126
day cells and the hour grid — 98 times in a 1.2-second drag, 12,348
cells (measured). Now:

- `MonthPagerView` owns the offset, so a frame re-runs one small body.
- `CalCell` / `CalMonth` are values decided when the month or the
  snapshot moves; `MonthGridView` is `Equatable` over them, so the grid
  is skipped entirely while the strip slides.
- The calendar self-check pins that shape, because the skip is only as
  true as the data model behind it.

**And a defect the measurement exposed.** The panel drag is a
recognizer on the WINDOW. Its installer already warned that it "would
otherwise drag panels invisibly behind a full-screen view", but it was
told only about the menu — so dragging the mini calendar was also
dragging the desk's panels behind the calendar window, 58 publishes
deep. `DeskModel.deskInFront` is now the one answer to "is the desk the
surface in front", read by that recognizer and by the record-card host.

## 20. The three surfaces are one strip (rev 23, owner 2026-08-15)

Owner: *"Now the left and right panels are like curtains. Better would
be if when you open them you 'swipe away' from the previous view, as if
it sits on the left / right off screen."*

**The two panels move differently, on purpose** (owner, same day:
"maybe having properties panel behave like a curtain though").

- The **LIBRARY is a different place.** It and the desk are one strip:
  opening it pushes the desk a full screen to the right, and the desk
  sits off screen for as long as the library is up. You swipe away from
  what you were looking at.
- The **PROPERTIES panel is about the note you are already looking at**,
  so it stays a CURTAIN: it slides over a desk that does not move. Push
  and pull cannot both be right for a surface that describes the thing
  underneath it.

One number does each. `DeskModel.panelProgress(_:)` (0 off screen, 1
home) drives the panel's own offset; `deskShift` is the library's
progress turned around, read by everything that belongs to the desk —
the body, the doors, the bottom bar, the minimised pill; `curtain` is
the properties' progress, read by everything drawn ABOVE the panels,
which the curtain cannot cover and which therefore fades by exactly how
far it has come down: the workspace button, the bar, the pill. The drag
moved from DeskHost's `@State` onto the model because the bar is drawn
by RootView, one level up.

Three things this change had to get right:

- **The workspace button does not travel.** It is the one control that
  belongs to the whole strip, and the 2026-08-13 ruling stands: it stays
  visible while you swipe into the library.
- **The doors fade over the first third of the journey** (`deskTravel`).
  They ride the desk, so their path crosses the pinned workspace button;
  fading early means a door never prints itself over the workspace name.
- **The bottom bar leaves with the desk instead of popping.** It used to
  be dropped from the hierarchy the moment a panel was shown — halfway
  through the desk's journey. Now it simply rides off screen, and only
  the keyboard and the one menu still take it away.

## 19. Nothing inert on screen (rev 22, owner 2026-08-15)

Owner: *"Irrelevant properties should be hidden from the user. General
rule: when user can't interact with something it shouldn't be there
unless it's locally dynamic or important for clarity."*

Three tests, in order. A piece of UI appears only if it passes one:

1. **Actable here.** The user can do something with it, in this state.
2. **Locally dynamic.** It cannot be acted on yet, but it becomes
   actable from something the user can do in this same view — the bar's
   ‹ › light up as soon as there is history to walk.
3. **Clarity.** It carries something the user wants to know: a value
   they filed, a date, an error, a count. A fact is allowed to be inert
   — the created line at the foot of the properties panel is deliberately
   not a row, because it cannot be changed.

Failing all three, it does not appear at all. The first casualty is the
properties panel's status row for a kind with no status vocabulary and
no status set: it used to say "none for this kind", which explains the
app to someone who asked about their note. A status already SET still
shows, read-only — that is the user's data, and hiding data is the
opposite mistake.

This is the same instinct as the older rulings it now generalises:
"facts you cannot change are not rows" (2026-08-06) and "a menu item
that does nothing is a lie" (the editor's `+` in an embedded card).

## 18. Templates left, and messages got their own band (rev 21, owner 2026-08-15)

Owner, over a screenshot of a template note whose pill printed itself
across the workspace name: *"the message is on top of each other. also
remove templates completely. it should be added later when we have
decided a good way to implement them."*

**Templates are gone from the shell.** Both files (Template.swift,
TemplateSheet.swift), the create menu's "From template…", the ••• menu's
"Save as template", the editor `+`'s "From template…", the template
pill, the `-template.selfcheck` suite (eight suites now, not nine), the
furnishing pass that seeded three built-in templates, and — because they
existed for nothing else — `LivKind.template`, its glyph, the whole
DASHED stroke pass in the icon language, and `LivTheme.gray`. The caret
leg of the focus request went too: `{{cursor}}` was its only caller, so
`consumeFocus` is a Bool again.

Nothing in `core/`, `services/`, `views/` or `ffi/` changed — there was
never a template verb in the C ABI; a template was a note wearing one
`template` cell, written with the ordinary verbs.

**What an older box keeps.** The three seeded notes (Daily note,
Meeting, Person) and anything saved as a template are now ORDINARY
notes, `{{date}}` and all. The marker cell survives on disk, stays
hidden in the properties panel, and is still skipped by Duplicate note,
so a copy never spreads it. Nothing is rewritten and nothing is trashed.

**One band for anything that speaks.** `LivRow.topChrome` (56pt) is the
band the two doors and the workspace button own; every message starts
below it. The template pill was one of THREE things that printed into
that band — the box-fault banner and the editor's own notices (conflict,
flattening, save-failed) did the same, and both survive templates. They
are fixed by the same constant, which is now a token instead of a
number repeated in prose (standing rule 3).

## 17. One menu (rev 19, owner 2026-08-14)

Every menu in the app is `LivMenu` + `.livMenu(_:active:)`
(Menu.swift). The only variation is the edge it comes from: `.bottom`
slides up (the create menu, the editor's insert menu), `.top` slides
down (the note's ••• verbs, from under its own button). A UIKit UIMenu,
a SwiftUI Menu and a full-screen New Tab page all died for it.

`active` follows RecordCardHost's rule — the surface in front draws the
menu — and the host lives at the ROOT, above the bottom bar.

**An empty desk is empty, and the bar's `+` is the way out of it** (rev
20, owner 2026-08-15, from the phone: "no it doesn't"). §6 rev 6's rule
5 above — "an EMPTY desk shows the same chooser as its body" — is
HISTORY: that page died with rev 19. The empty desk now shows a hint
that points at the `+`, so the `+` must always be live. It was disabled
whenever `desk.tabs.isEmpty` — correct while the body WAS the chooser,
and a dead end the moment it was not: a new workspace could not be given
a tab at all. The switcher's own `+` never carried that guard.

## 16. The link door (rev 18, owner 2026-08-13)

Creating a link opens SEARCH. The toolbar's Link key and typing `[[`
both lead to the same screen; picking writes the whole `[[id|Name]]`
where the caret is, over the `[[query` when one is being typed.
`SearchView(onPick:)` is the only search in the app — the old four-row
`[[` picker is deleted. "Create …" in that screen makes the thing and
links to it in one tap.

**Lists hang in one gutter** (rev 20, owner 2026-08-15: "do the list
gutter alignment"). Every list line's words start at the same left
edge — 23pt in, the width of the 15pt checkbox plus a space — and a
wrapped line carries on under those words. The marker is not moved: what
is still visible of it is measured and kerned out to the gutter's width
on its last character, so the drawn dot and box stay exactly where their
glyphs are. Nesting is one gutter per level (`firstLineHeadIndent`), and
the two source spaces that carry a level are collapsed to nothing so a
level is never indented twice.

Two things TextKit taught us here, both measured on the simulator:
`firstLineHeadIndent` is honoured only while a line's FIRST glyph is
real, so a task's leading `- ` is collapsed (ink cleared, width kerned
away) rather than hidden with null glyphs; and one negative kern for a
run collapses only its last character, because an advance clamps at
zero — each character pays for itself.

**Syntax is shown only on the caret's line** (rev 19, owner 2026-08-15).
Markers off that line are given NULL glyphs by LivLayoutManager's
delegate — present in the buffer, zero width on screen. What is drawn in
a marker's place (the bullet dot, the task box, the rule) keeps its
rect, and an ordered list's number keeps its width because the number is
the rendering. The reveal covers every paragraph the selection touches.

The keyboard toolbar is GROUPED, Notesnook's shape: a hairline between
runs of keys, most-used first — undo/redo · bold italic strike · link ·
heading task bullet numbered · indent outdent · quote code divider. The
`+` holds only what is NOT universal (Outline today; maths later).

The token is built in ONE place, `SpanText.token`. `EditOps.completeLink`
used to build its own and spaced only `]]`, which leaked a bracket per
save for any name ending in one.

## 15. The icon language (rev 17, owner 2026-08-13)

Owner: *"apply the kind colors everywhere, and i don't see the
blueprint's custom icons in the app."*

**The icons are DRAWN.** `Glyph.swift` holds the blueprints' own stroked
24×24 set (`design/mockups/blueprints/icon-style.html` for kinds and
furniture, `home-views.html` for places). SF Symbols are a different
language — filled, heavier, on their own grid — and using them was why
the approved icon system was invisible in the app. Apple's symbols stay
for chrome that is not about a thing: chevrons, the close cross, the
repeat mark, the search magnifier.

**One classifier.** `LivKind.of(row)` is the only answer to "what is
this?", and the enum carries the colour AND the glyph. Two tables had
disagreed — the colour asked `kinds.first`, the glyph asked
`kinds.contains` plus status — so a task filed as `["note","task"]` drew
a tick on a blue square. Priority: file > event > task-or-any-status >
person > link > note > capture.

**The library panel is the exception**: its rows are bare, colourless
and large (26pt, text2). A view is a place to go, not a thing you own,
and seven hues stacked in one column shouted louder than the content.

**Two ways an icon appears.** `IconChip` is the carved chip: a solid
square of the kind colour with the glyph punched through in the surface
BENEATH it — pass `on:` whatever the chip sits on, or the stencil stops
working. `LivIcon` is the bare stroked glyph, for rows where a solid
block would shout or where it shares a column with a status ring.

**Where the colour does NOT go** (both rejected on sight, 2026-08-12):
the create menu's verbs and the Inbox's routing buttons — they take the
shared glyph in plain ink, because colour marks what a thing IS, never
what a button would make; and property field rows, which wear a small
colour dot instead. A chip standing for a THING (a kind word, a
reference to another entity) takes the kind colour on its dot; every
other chip keeps the `Hue` hash.

**`livCanTick` is not the kind.** It asks whether a row has a status to
close, which an event can also have. The kind says what the row IS.
Keeping them apart is what stops an event losing its ring.

`-glyph.selfcheck 1` asserts all of it: one kind per row, colour and
glyph agreeing, no two kinds sharing a drawing, every path inside its
box.
