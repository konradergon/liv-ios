# Tasks that mean something — the checkbox↔task model (roadmap phase 3)

Status: **SHIPPED 2026-08-05** — all three questions approved by the
owner (projection model + additive wire field; separate section;
indented sub-lines included). Mockup:
`design/mockups/tasks-in-notes.html`.

**What shipped**, and the deltas found while building it:

- `services/src/tasks.rs` — `note_tasks(store)`, a pure projection; two
  failing-tests-first in `services/tests/tasks.rs`, plus an ffi wire
  test. `liv.h` documents the key.
- **Two authored forms, not one.** The core's own shape is
  `Span::Break(Block::Task { done })` (D19: "markdown markers are never
  stored") — the desktop writes that; the iOS editor writes literal
  `- [ ] ` text in Body paragraphs, a recorded deviation. The
  projection reads BOTH, so it is not parsing-only-because-iOS: form 1
  needs no parsing at all. Convergence (iOS writing Block::Task) is a
  bigger editor change — recorded, not attempted.
- **`source` rides the wire.** The note's display name is computed in
  Rust, where the content is: `EntityRow.title` is a whole-body summary
  and a chip read "Roof project - [ ] call the surveyor - [x] paid…".
  Third surface bitten by that flattening; first one to fix it at the
  source.
- **Determinism.** `store.entities()` has no defined order, so the raw
  sweep reshuffled between refreshes (and would have flaked the
  byte-wise snapshot-parity test). Output sorts by (entity, line).
- **Empty checkboxes do not project.** The editor's return-key
  continuation mints `- [ ] ` lines by the handful; they were showing
  as "empty line" rows naming nothing.
- **`EditOps.lineStart`** maps the wire's line index to a buffer
  location, so the Tasks view toggles through the SAME `toggleTask` the
  editor uses — no second implementation. Its first version answered
  with a location for a line that did not exist; the self-check caught
  it before the device did.

## 1. The gap, in the owner's words

"The `- [ ]` checkboxes you write in notes and the Tasks view are not
connected." A task typed inside a note is real to the person who wrote
it, invisible to the one view whose job is tasks.

## 2. The law, and why a projection is lawful

The constitution: typed text is never parsed into meaning. The
precedent that sharpens what that MEANS: the editor already parses
`- [ ]` — it draws a checkbox, and tapping it edits the text. That is
display-level parsing plus an explicit user write. What the law
actually forbids is parsing that CHANGES state or mints meaning on its
own (a scan that creates entities, stamps cells, moves things).

A projection is the first kind. It derives a VIEW of checkbox lines;
it stores nothing, creates nothing, and writes only when the user taps
— and the write is exactly the edit the same tap makes in the editor.

## 3. The model: project, don't promote

**Every open `- [ ]` line in a live note appears in the Tasks view,**
in its own "In notes" section, each row carrying its source note.
Checking a row edits THAT NOTE's text (the same toggle the editor
does); tapping the row's source opens the note as a desk tab.

Considered and set aside:

- **B — promotion** (a line becomes a task entity on explicit action):
  duplication risk, a Ref-span dance, and it still misses every
  unpromoted line — the original complaint survives it. If a line
  needs dates/status, the cheap path already exists: make it a task
  (`New task`) and delete the line. Revisit only if real use demands
  per-line scheduling.
- **C — hybrid** (project + promote): B's cost on top of A. Later, if
  ever.

## 4. The exact surface (what the build would touch)

**services/ + ffi/ — one additive projection, no new write verbs:**

- A pure services fn scanning live notes' content for open task lines.
  Excluded: trashed, archived, TEMPLATE-marked notes (their bodies are
  scaffolding: `- [ ] {{cursor}}`), and task/event-typed entities
  (their body lines would double-count against themselves in the same
  view).
- The snapshot gains an OPTIONAL field, e.g.
  `note_tasks: [{entity, line, text, indent}]` — open lines only
  (checked lines are visible in the note itself; projecting them would
  bloat the wire for a list nobody asked to see). `line` is the line
  index within the note's CURRENT content; it is stable per
  content_print, which the snapshot already carries.
- Purely additive, mirrors `with_box`, ships with a failing-test-first
  services test + an ffi snapshot test. This is the owner-gated part.

**shell — zero new verbs:**

- Tasks view: an "In notes" section after the status groups. Row =
  checkbox glyph + line text + source-note chip. Check = fetch content
  (`liv_content_at`), verify print matches the snapshot, toggle that
  line (`EditOps.toggleTask` — already self-checked), save with the
  existing CAS base. A stale print = the save refuses, the view
  refreshes, nothing mis-lands — the same conflict discipline the
  editor already lives by.
- The workspace lens applies to the SOURCE NOTE's cells (consistency
  principle: the workspace band filters whole).

## 5. Verification plan

- services test: projection over a hand-built store (open/checked/
  indented lines; trashed/template exclusions).
- ffi test: snapshot carries the field; empty when assist... (no —
  this is NOT clerk-gated: it is display derivation, no consent
  needed, same as the editor's checkboxes. Recorded deliberately.)
- shell: box-log cross-check that a Tasks-view toggle writes the same
  RemoveCell/AddCell content transaction the editor's toggle writes.

## 6. Open questions for the owner (blocking the build)

1. **Approve the projection model** (§3) and the additive snapshot
   field (§4)? services/ffi are settled zones — your word required.
2. **Placement**: "In notes" after the status groups (mockup shows
   this) — or interleaved into "To do"? My call: separate section;
   these lines have no status, and pretending they are "To do" muddies
   what status means.
3. **Indented sub-lines**: include flattened with a slight inset
   (mockup), or top-level lines only?
