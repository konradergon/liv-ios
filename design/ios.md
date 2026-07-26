# iOS — the phone shell (proposal)

> Status: **M1 in progress** (accent decided: lake green; source renamed
> lotus→liv 2026-07-22 — this doc's verbs read `liv_*`). Produced 2026-07-21
> from a full read of the specs, core, FFI, and macOS shell, plus a
> three-architecture sync design pass judged through integrity / UX / cost
> lenses (unanimous verdict). Open owner decisions are collected in §8.
> Mockups: see the published artifact (phone frames, accent toggle).

## 0. What the phone is

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

**Bottom bar** (always the same, Obsidian's nav row under Liv law):

- Far left, always: the **features button** (`^`) — opens the floating
  feature grid (ClickUp "More" idiom): Today, Inbox, Tasks, Calendar,
  Capture, Camera. It carries the amber proposal-count badge (the app's
  only badge — Inbox lives behind this menu). **Selecting a feature opens
  it as a window covering everything**, dismissed by swipe-down or by
  opening a row (which lands as a Desk tab).
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

## 7. Visual design

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
  the UI after relaunch. **Remaining for M1:** the share extension + device
  builds need a real Xcode project with App Group entitlements + signing
  (owner's Xcode; hand-rolled bundles can't carry them), and hands-on QA of
  the gesture wiring (swipes, chips, camera) which headless simctl can't
  drive.
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
- **M3 — P2**: notification scheduler + mirror union; widgets + App Intents;
  Calendar surface. *P2 complete.*
- **M4 — phase-2 fidelity**: `ImportItem` variants land in services;
  drainer lowering flips; retype card. 
- **M5+** — P4 notes via vault mediation / oplog destination. (P3 messages:
  killed 2026-07-26, see §4.)
