# P8 Tasks Model — the task surface: a seeded priority, a create-task twin, a checkbox that writes, and a cross-workspace list (board deferred)

Building on the shipped tree (`services/src/{lib,content,search}.rs`,
`ffi/src/lib.rs`, `shell/macos/Sources/{Window,Chrome,Tabs}.swift`) and the
substrate the earlier phases already laid down. **A task is an ordinary
entity of `type=task` carrying a `status` select + a `due` datetime** — that
model already exists and is seeded (`services/src/lib.rs:356`,
`("task", &[status, due])`). P8 does **not** invent a task store, a board, or
per-workspace status sets. It seeds **one more select (`priority`)**, adds
**one create verb (`create_task`, a twin of `create_note`)**, makes the
**checkbox actually write** through the seam that already exists
(`lotus_set_at` → `set_property`), and replaces the `.tasks` `ExtensionStub`
with a native **cross-workspace list** grouped by status. **No new read FFI,
no new mutation FFI beyond create, no core model change.** Liv's rich task
model (types action/decision/reminder, ClickUp status groups, subtasks,
assignees, projects, recurrence) is **not ported**; its one durable idea — a
single cross-vault task list the active workspace only stamps on *new* tasks —
is honored, and the board is left a **deferred candidate that must justify
itself with real task volume** (feature-map #18), exactly as Today shipped a
list before earning a calendar.

## 1 · The load-bearing decisions

1. **The task entity already exists; P8 adds no new kind of thing.** A task is
   `Create` + `type=→task` + a `status` cell + (optionally) `due`, `priority`.
   The type expects `[status, due]` from birth (`lib.rs:356`). Toggling done,
   setting priority, setting a due date are **all `set_property` on cells of an
   existing entity** — the same door the inspector and the editor's live
   checkbox already use. There is **exactly one genuinely new Rust seam in P8:
   the birth verb `create_task`**, because capture makes an *untyped scrap the
   clerk quarantines* (`ffi/src/lib.rs:1631-1649`) and would land quick-add
   tasks in the inbox as proposals, not in the list.

2. **`priority` is one more seeded select — additive, idempotent, and it must
   survive the existing seed guard.** `seed_starter_library` returns early when
   `property_id("due").is_some()` (`lib.rs:310`). Because `due` already exists
   on every shipped box, **adding a `priority` block inside that function would
   never run for an existing box** — the guard short-circuits before it. So
   P8 seeds priority through a **second, separately-guarded additive pass**
   (its own `if property_id(store,"priority").is_none()` gate) that runs after
   `seed_starter_library`, mirroring the "an older box gains it on open"
   contract in the P7 files model. The pass creates one `priority` select
   property plus its option entities (author System, `working:true`) in one
   transaction. It never touches the `task` type's `expectations` — priority
   is **offered, not expected** (a task is valid without one), matching the
   brief's "seed or let the clerk learn it" and keeping the type's expectation
   set honestly minimal.

3. **The surface is driven by a client-side filter over the existing snapshot,
   not a new `tasks` list or a query.** The snapshot already carries every live
   entity with `kinds:[String]` and `status:String?` populated
   (`ffi/src/lib.rs:298-350`); `model.rows(snap.everything)` returns them all.
   The task list is `model.rows(snap.everything).filter { $0.kinds.contains("task") }`
   — the **exact idiom LibraryView already uses** for files
   (`Window.swift:2131-2133`). This is cross-workspace by construction (the
   snapshot is vault-wide), which is precisely Liv's semantics. **No `tasks`
   field is added to the snapshot and no query routes the surface** — a
   dedicated list would duplicate state the snapshot already holds, and routing
   through the search DSL (`type:task`) returns ranked hit ids without
   status-grouping and re-runs a query on every keystroke. The search palette
   keeps the DSL; the Tasks surface reads the loaded snapshot. (If task volume
   ever makes the client-side filter measurably slow, *that* is when a snapshot
   `tasks` projection justifies itself — named, not pre-built.)

4. **Done-toggle, priority, and due all reuse `lotus_set_at`. No new mutation
   verb.** The checkbox tap is `model.set(row.id, property:"status", value: row.status=="done" ? "todo" : "done")`
   (`Window.swift:262` → `lotus_set_at` `ffi/src/lib.rs:861` →
   `content::set_property`, whose select branch lowercases the raw string and
   resolves it to the seeded `todo/doing/done` option by name,
   `content.rs:396-404`). Setting priority is the identical call with
   `property:"priority"`; setting due is `property:"due"` with a datetime
   string. **The whole write side of P8 is already built** — the only missing
   piece on the write path is the SwiftUI gesture on the checkbox.

5. **The board stays deferred; the list ships first.** No board renderer, no
   `Placement` order entities, no drag-to-set-status in P8 (feature-map #18).
   No per-workspace custom status vocabularies (the split-or-union decision is
   deferred until it bites, per the brief) — P8 uses the single seeded
   `todo/doing/done` set for every task, vault-wide.

## 2 · The task-entity model (data-model first)

A task, e.g. `Draft the P8 review`:

```
Create #5100
name     = "Draft the P8 review"      (props::NAME, text)
type     = →task                      (props::TYPE, reference to the seeded "task" type)
status   = →todo                      (the seeded "status" select; born todo)
created  = 2026-07-07 14:30           (props::CREATED)
due      = 2026-07-09                 (props::… "due" datetime; set later, optional)
priority = →high                      (the seeded "priority" select; optional, set later)
```

Only `type`, `status`, `created`, and `name` are written at birth (§4). `due`
and `priority` are **set through the inspector / list affordances after
birth** via `lotus_set_at` — a task is valid the instant it exists, nameless
or named, with no due and no priority, exactly as `create_note` births a
typed-but-empty note.

## 3 · Seeding `priority` — additive, idempotent, offered-not-expected

A new seed pass beside `seed_starter_library` (called from the same open-time
seeding sequence, after it), guarded independently so it lands on **already-
shipped boxes** despite the `due`-based short-circuit:

```rust
/// Priority is one more select the task surface offers. Additive and
/// idempotent on its own guard (NOT the starter-library `due` guard, which
/// short-circuits on every existing box): an older box gains priority on
/// open. Offered, never expected — a task is valid without one, so the
/// `task` type's expectations are left untouched.
fn seed_priority(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "priority").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    // one select property, mirroring the status block (lib.rs:331-349)
    let priority = new_property(&mut commands, session, "priority", "select");
    for option in ["low", "medium", "high"] {          // §3.1 — 3, not 4
        let id = session.allocate_id();
        commands.push(Command::Create { entity: id });
        for cell in [
            Cell { property: props::NAME, value: Value::text(option) },
            Cell { property: props::WORKING, value: Value::Bool(true) },
        ] { commands.push(Command::AddCell { entity: id, cell }); }
        commands.push(Command::AddCell {
            entity: priority,
            cell: Cell { property: props::OPTIONS, value: Value::Reference(id) },
        });
    }
    session.commit(commands, "seed priority", Author::System)?;
    Ok(())
}
```

(`new_property` is currently a closure local to `seed_starter_library`;
lift it to a module-level `fn` or inline the three `AddCell`s here — a trivial
refactor. The option-loop is a verbatim copy of the status loop at
`lib.rs:336-349`.)

### 3.1 Priority vocabulary: **three options (low / medium / high)** — resolving the open question

Liv ships four priorities. lotus takes **three** for v1, and this is a
deliberate simplification, not an oversight:

- Three maps cleanly to the visual grammar the list already has (a low / mid /
  high dot, mirroring the `statusColor` done/doing/todo triad, §6), needing no
  fourth colour.
- The brief explicitly leaves priority to "seed or let the clerk learn it" and
  warns against pre-building vocabularies before they bite. Three is the
  smallest set that is still useful; a fourth (Liv's "urgent") can arrive
  **additively as a proposal or a later seed pass** the same way priority
  itself arrives here — the select is open-ended, so growing it is one more
  option entity, never a migration.
- **No default priority at birth.** Unlike `status` (born `todo` because the
  type expects it and the checkbox needs a concrete state), an unset priority
  is a meaningful "not yet triaged" state, so `create_task` writes no priority
  cell. The list renders a priority affordance only for tasks that have one.

## 4 · The `create_task` seam (a twin of `create_note`)

### 4.1 Service — `content::create_task`

Mirror `create_note` (`content.rs:195-211`), adding a `status=todo` cell so
the task is born in a concrete, checkbox-ready state:

```rust
/// Birth of a task: Create + type=task + a status=todo cell + created, one
/// transaction. Born nameless (like create_note) so the caller drops into
/// renaming, but typed and already `todo` so the list's checkbox has a
/// concrete state from the first frame. Priority and due are set later,
/// never at birth.
pub fn create_task(session: &mut Session, created: DateTime) -> Result<Id, PersistError> {
    let store = session.store();
    let task_type = find_type(store, "task");
    let status_prop = property_id(store, "status");
    let todo = /* find the "todo" option entity by name among status's OPTIONS */;
    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    if let Some(t) = task_type {
        commands.push(Command::AddCell { entity: id,
            cell: Cell { property: props::TYPE, value: Value::Reference(t) } });
    }
    if let (Some(sp), Some(opt)) = (status_prop, todo) {
        commands.push(Command::AddCell { entity: id,
            cell: Cell { property: sp, value: Value::Reference(opt) } });
    }
    commands.push(Command::AddCell { entity: id,
        cell: Cell { property: props::CREATED, value: Value::DateTime(created) } });
    session.commit(commands, "new task", Author::User)?;
    Ok(id)
}
```

The `todo` option is resolved the same way `set_property`'s select branch
does — walk `status`'s `props::OPTIONS` for the entity whose `NAME` is
`"todo"` (`content.rs:401-404`). Factor that walk into a small
`find_option(store, prop, name) -> Option<Id>` helper reused by both.

### 4.2 FFI — `lotus_create_task_at`

Mirror `lotus_create_note_at` (`ffi/src/lib.rs:933-940`) verbatim, swapping
`create_note` for `create_task`:

```c
// Create a task by hand (quick-add). One transaction: type=task + status=todo
// + created. Returns the new id, or 0 (busy box / failure). Distinct from
// capture, which makes an untyped scrap the clerk quarantines.
uint64_t lotus_create_task_at(const char *path);
```

**Declare it in the hand-maintained header** `shell/macos/lotus.h` next to
`lotus_create_note_at` (line 82) — the Swift side links against this header,
not a generated one; a Rust export without the matching `.h` line leaves the
call unresolved.

### 4.3 Shell — `BoxModel.createTask`

A verbatim copy of `createNote` (`Window.swift:266-275`), calling the new verb
(creates return a `u64` id, so use the direct `boxQueue.async` form, not the
boolean `act` helper):

```swift
func createTask(_ done: @escaping (UInt64?) -> Void = { _ in }) {
    boxQueue.async {
        let id = lotus_create_task_at(self.path)
        DispatchQueue.main.async {
            if id == 0 { NSSound.beep() }
            done(id == 0 ? nil : id)
            self.refresh()
        }
    }
}
```

### 4.4 Workspace stamping — resolved: **do not stamp** (open question)

Liv stamps the active workspace onto *new* tasks. lotus has **no per-task
workspace-membership property** in the snapshot or the seed — tasks are
vault-wide. P8 **does not invent one**: `create_task` writes no workspace cell,
matching the fact that no such property is seeded and honoring "don't
pre-build." A future `workspace`/`area` reference on tasks is named and
deferred; when membership actually bites, it arrives as a seeded reference
property plus a stamp in `create_task`, additively.

## 5 · The native `TasksView` (assembly of existing primitives)

Replace the `.tasks` `ExtensionStub` at `Window.swift:869-870` (default case)
with `case .tasks: TasksView(model:, selection:$selection, createTask:{…}, open:{ id in openEntityTab(id) })`.
`.tasks` is already a reachable Surface (label "Tasks", symbol
`checkmark.square`, `Chrome.swift:15,28,41`). `TasksView` is modeled on
`LibraryView` (`Window.swift:2124-2180`) and **introduces no new UI
primitive** — `LensHeader`, the Today-style quick-add field
(`Window.swift:1447-1475`), `SectionLabel` (`1387-1396`), `EntityLine`, and the
empty state all already exist.

Structure, top to bottom:

- **Header** — `LensHeader(title:"Tasks", subtitle: live count)` with a
  trailing filter control (§5.3). Cross-workspace: the count is over the whole
  vault's tasks.
- **Quick-add** — the Today capture field (plus icon + `TextField` +
  `.onSubmit`): trim whitespace; if non-empty, `model.createTask { id in … }`,
  then on success set the name via `model.set(id, property:"name", value: text)`
  (create births nameless, so quick-add is create-then-rename, one extra
  `set_property`), and clear the draft only after the box confirms. (Optionally
  fold naming into `create_task(title:)` later, mirroring `create_workspace`'s
  inline name at `content.rs:216`; v1 can create-then-rename to keep the verb a
  strict `create_note` twin.)
- **Status-grouped rows** — the filtered tasks grouped into `todo` / `doing` /
  `done` sections in **seeded option order** (`lib.rs:336`), each under a
  `SectionLabel`, sorted **by `due` ascending with nil-due last** within a
  group. Each row is an `EntityLine` with a **working checkbox** (§5.1) and an
  `open(row.id)` row-tap.
- **Empty state** — the LibraryView pattern (an SF Symbol, "No tasks yet.", a
  one-line hint, and focus into quick-add).

### 5.1 The working checkbox — `EntityLine` gains an opt-in toggle

`EntityLine`'s checkbox is today a **dead static glyph**: a stroked
`RoundedRectangle` drawn when `row.kinds.contains("task") || row.status != nil`,
with no tap and no checked/`done` variant (`Window.swift:1407-1411`); the whole
row is one `Button` calling `select`. `EntityLine` is **shared by TodayView and
LibraryView**, so the change must be opt-in to avoid regressing them:

- Add `var toggle: (() -> Void)? = nil` to `EntityLine`.
- When `toggle != nil`, render the checkbox as its **own `.plain` Button**
  nested in the row (a filled box + `checkmark` SF Symbol when `row.status ==
  "done"`, an empty stroked box otherwise), so tapping the box toggles status
  **without triggering row selection** (the two gestures no longer collide).
- When `toggle == nil` (Today, Library), the checkbox stays the current static
  glyph — those surfaces pass no toggle and are untouched.

TasksView wires it to
`model.set(row.id, property:"status", value: row.status == "done" ? "todo" : "done")`.
This is the entire write path; it works through existing infrastructure (§1.4).

### 5.2 Priority on the row — conditional, never hardcoded

Render a priority affordance (a small coloured dot or a compact menu) **only
when the priority property exists** — gate on `model.property(named:"priority") != nil`
(`Window.swift:343-345`) and read the task's priority off its cells. Do **not**
hardcode `low/medium/high` in the shell; read the option names from the
snapshot. Setting priority from the row (a right-click menu or an inspector
field) is `model.set(row.id, property:"priority", value: name)` — same seam.
For v1 this can live in the **inspector only** (the row shows the dot if set),
with the row-level setter as a 8c polish item.

### 5.3 Simple filters — in-shell segments over the loaded snapshot

A segmented control in the header, filtering the **already-loaded** client-side
list (no DSL round-trip):

- **All** — every task, all three groups.
- **Open** (default) — `status != done`; hides the Done group. Liv hides
  completed tasks by default; matching that, **Open is the default filter**, so
  a checked task collapses out of view on the next `refresh()`.
- **Done** — only completed.

(Optionally a **Today** segment: `due` is today or overdue — cheap over the
loaded rows.) These are simple in-shell segments over the snapshot; the search
DSL (`type:task status:done`) stays reserved for the search palette, which
already resolves options identically (`content.rs:396`) but returns ungrouped
ranked hits.

### 5.4 Opening a task

Clicking a row calls the parent's `openEntityTab(id)` (`Window.swift:1005-1011`),
already passed to LibraryView as `open:`. A task has no `file` cell, so it opens
as an **editable note tab** (editor + inspector), where `status`, `due`, and
`priority` are edited through the ordinary property UI. **No new tab logic** —
reuse the LibraryView open plumbing verbatim.

## 6 · The status/priority colour mapping — lift it to a shared helper

`EverythingView` maps status → colour (done=green, doing=amber, else grey) but
`statusColor(_:)` is **private to EverythingView** (`Window.swift:1651-1657`).
TasksView needs the same mapping for its group headers / status dots. **Lift
`statusColor` to a shared free function or a `Theme` helper** so the mapping is
single-source and TasksView doesn't duplicate RGB literals. A parallel
`priorityColor(_:)` (low/med/high → e.g. grey/amber/red) lives beside it, used
by §5.2's dot.

## 7 · Slice plan (each an independent commit: build → tests → review → fix)

- **8a — seed + create + the read-only list.** *Rust/FFI:* `seed_priority`
  (its own idempotent guard, low/medium/high, offered-not-expected, §3);
  `content::create_task` + the `find_option` helper (§4.1);
  `lotus_create_task_at` + the `lotus.h` decl (§4.2); `BoxModel.createTask`
  (§4.3). *Shell:* replace the `.tasks` `ExtensionStub` with a `TasksView` that
  is, for this slice, a **read-only** cross-workspace list — `LensHeader` +
  status-grouped `EntityLine` rows (static checkbox, sorted by due), empty
  state — modeled on LibraryView. Lift `statusColor` to shared (§6). *Tests:*
  `seed_priority` creates exactly one `priority` select with three options and
  is idempotent across two opens (**and lands on a box that already has `due`**
  — the guard-bypass is the load-bearing assertion); `create_task` creates
  exactly one entity with `type=task` + `status=todo` + `created` and **no
  priority/due** cell; the task type's expectations are unchanged (priority not
  added); FFI round-trip (`lotus_create_task_at` → snapshot shows a
  `task`-kind entity with `status="todo"`).

- **8b — the working checkbox, quick-add, filters + grouping.** *Shell only,
  no Rust:* give `EntityLine` the opt-in `toggle:` param and the
  filled/checkmark `done` variant as a nested `.plain` Button (§5.1); wire
  TasksView's toggle to `model.set(status)`; add the Today-style quick-add
  field calling `createTask` then rename (§5); add the All/Open/Done segmented
  filter with **Open as default** (§5.3); confirm status grouping in seeded
  order + due-ascending sort. *Tests* (shell/manual + a Rust round-trip for the
  toggle write): tapping a todo row's checkbox flips it to `done` via
  `lotus_set_at` and it re-groups under Done on refresh (and collapses out
  under the default Open filter); quick-add creates a named task that appears
  in the Todo group and **not** in the inbox (proving it used `create_task`,
  not capture); Today and Library are visually unchanged (they pass no
  `toggle`).

- **8c — priority surfacing + polish (or fold into 8b).** Conditional priority
  dot on the row and a priority setter (inspector field, optionally a row
  right-click menu), gated on `model.property(named:"priority") != nil` (§5.2);
  a `priorityColor` helper beside `statusColor`; optional Today/overdue filter
  segment; empty-state copy. This slice is **thin and foldable** — if 8b lands
  clean, priority surfacing can ride along and 8c collapses into it. Nothing
  here is new substrate; it is presentation over cells that already exist.

## 8 · Deferred (named, not built in P8)

The **kanban / board renderer** (a candidate that must justify itself with real
task volume — feature-map #18; no `Placement` order entities, no drag-to-set-
status) · Liv's **per-workspace custom status groups** (the split-or-union
decision, deferred until it bites) · task **types** action/decision/reminder
(lotus has one `task` type) · **subtasks** tree · **assignees** ·
**projects/areas** as first-class task membership (references/later; the
workspace-stamp open question, §4.4) · **recurrence** UI (P11) · **reminders** ·
the **Decide tray** (P13) · a fourth **"urgent"** priority (additive later,
§3.1) · a dedicated **`tasks` snapshot projection** (only if the client-side
filter measurably slows, §1.3) · **routing the surface through the search DSL**
(reserved for the search palette).