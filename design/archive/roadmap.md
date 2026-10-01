# Liv iOS — roadmap (per "Liv iOS Proposal.md", owner 2026-08-04)

Awaiting owner approval. No phase starts until this document is approved;
after that, one phase per response unless more is asked. Project memory
lives in `decision-log.md`, `changelog.md`, `next-batch.md` (all in
`design/`), updated after every phase.

**Where we stand.** Most of the proposal's structural asks are already
built, verified on the simulator, and (pending one phone unlock)
installed on the device — see `changelog.md`. What remains is hardening,
the editor's insertion menu, and the product depth (tasks, calendar,
Today/Inbox) the proposal points at. This roadmap orders that remainder.

---

## Phase 1 — Hardening close-out

**Goal:** the rev-6 build is trustworthy everywhere, not just on the
paths already verified.

- Re-run the 14 audit findings whose adversarial verification was cut
  off (subagent session limit); fix whatever survives scrutiny. Known
  candidates: duplicate-note's handling of reference/file cells,
  merge-proposal rendering in Suggested, template-banner spacing,
  Everything's Unfiled slice under an area workspace, chooser `+`
  no-op on an empty desk.
- Fix the capture sheet's Undo (undoes one transaction, not the whole
  capture — task chip already filed).
- Properties panel visual pass: grouping styled like the left panel
  (proposal: "make the grouping UI akin to how the left panel looks").

**Deliverables:** fixed build on device; updated `design/ios.md`,
`changelog.md`, `next-batch.md`.
**Needs approval:** nothing beyond the questions below.

## Phase 2 — Editor: the `+` insertion menu

**Goal:** the Notesnook editor shape — a minimal always-there toolbar,
with a `+` opening the insertion menu for everything else.

- `+` as the toolbar's first key; menu hosts: insert template, link,
  photo, divider, task list, code block — the advanced set leaves the
  scrolling row, the daily set (bold/italic/heading/lists/undo) stays.
- Sweep the deferred editor items and pick with the owner: `_underscore_`
  italics, fenced code blocks, tables (probably not phone v1).

**Deliverables:** build; `design/editor-study.md` rev.
**Needs approval:** which advanced items make the menu.

## Phase 3 — Tasks that mean something

**Goal:** close the gap the owner named: "- [ ] lines and the Tasks view
are not connected."

- Design first (mockup + short doc): how a checkbox line in a note
  relates to task entities — likely a projection (the view lists
  checkbox lines alongside task entities; checking either side updates
  the note text), because typed text is never parsed into meaning
  without consent. May need a services/ projection — owner's word
  before any core-adjacent change.
- Task rows get quick verbs (status, due) in the ClickUp direction,
  kept simpler.

**Deliverables:** design doc + mockups first, then build.
**Needs approval:** the checkbox↔task model, before building.

## Phase 4 — Calendar & dates

**Goal:** Apple-Calendar-grade day interactions; ClickUp's date sheet
ideas where they fit.

- Tap an hour to create there; drag to move an event's time.
- Due sheet: consider start→due spans and the month grid (the core
  already stores spans; recurrence exists in services).

**Deliverables:** build; `design/ios.md` rev.
**Needs approval:** scope (which interactions are worth the phone v1).

## Phase 5 — Today & Inbox, redefined

**Goal:** the two "unclear direction" views earn their place.

- Today: the day's agenda + overdue strip (ClickUp Today shape) —
  mockup-first.
- Inbox: triage home — untyped scraps AND the clerk's suggestions in
  one place, accept/reject inline (the Properties panel's Suggested
  section already ships; Inbox becomes the cross-note surface).

**Deliverables:** mockups for sign-off, then build.
**Needs approval:** the mockups.

## Phase 6 — Templates ruling — CLOSED 2026-08-06

**Ruling: keep templates, with the banner safeguard** (option 1).
Verified live: a template on the desk wears the pill, and its "New
note" minted a copy with variables resolved while leaving the template
untouched. Nothing further to build.

### (original)
## Phase 6 — Templates ruling (small, can run any time)

**Goal:** resolve the owner's "maybe not have them at all?".
Options, with my read:
1. Keep, with the shipped banner safeguard.
2. Replace with Duplicate note (shipped) as the ONLY mechanism —
   covers most template value with zero template objects to misuse.
3. Drop templates and the built-ins entirely.

**Deliverables:** the ruling recorded; small build either way.
**Needs approval:** the ruling itself.

## Phase 7 — ••• residents: Share / Export

**Goal:** the overflow menu earns its secondary actions — share a note
as text/markdown via the system sheet; export lives with it.

## Phase 8 — Future (gated; not yet, per the proposal)

OCR scanning (the camera's real purpose), Graph view, Filter button,
ClickUp-style task relationships. Thinking starts only when the owner
says so; nothing here ships before phases 1–7 make the base useful.

---

## Questions needing the owner's word (can be answered piecemeal)

1. **Approve this phase order?** (Reordering is cheap now.)
2. **Everything now wears the workspace lens** (its old "never hides"
   rule retired per the proposal's consistency principle; All = the
   complete view). Confirm — or revert to always-complete?
3. **Camera left the sidebar** (Photo remains in the New-Tab chooser).
   Confirm?
4. **Properties dual access: answered NO** — its own door + the swipe;
   not in •••. Confirm?
5. **Duplicate note details:** a duplicated task currently becomes a
   NOTE that still carries the status cell. Should the duplicate copy
   the type too? And reference/file cells: copy or skip? (Currently
   copied by display value, which can mislink — my proposal: skip.)
6. **Suggestions default:** with no consent switch in the box, the
   clerk is ON by core semantics (suggest-only; never writes without
   your tap). The phone cannot mint the switch itself. Accept
   default-ON, or authorize a small core-side furnish so it defaults
   OFF with a Settings toggle?
