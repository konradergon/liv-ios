# P10 Calendar Model — the calendar is a projection, not a store: it draws the entities that already carry `due`, plus the recurrence engine's virtual occurrences, on a grid; the one genuine gap is a *window* the shell can steer (month navigation), and `create_event`

Building on the shipped tree (`services/src/{lib,content,recurrence,search}.rs`,
`ffi/src/lib.rs`, `shell/macos/Sources/{Window,Chrome,Spaces}.swift`) and the
substrate P1–P9 laid down. **A calendar is not a kind of thing; it is a *view* of
the things that already have a date.** The `event` type is seeded
(`lib.rs:427-433`, `("event", &[due])`), `due` is a `datetime` property whose
`date_only` bit already separates all-day from timed (`ffi/src/lib.rs:302-307`),
the recurrence engine already expands every live series into **virtual
occurrences** computed in one place and stored nowhere (`recurrence.rs:71-117`),
and the snapshot already carries both `dated` (every non-recurring entity with a
`due`, sorted, `ffi/src/lib.rs:267-283`) and `occurrences` (this month's
expansion, `:293-296`). **A month grid over this data already exists and renders**
— `CalendarView` at `Window.swift:2078-2141` draws a real 7-column month, merges
`dated` + `occurrences` by day, highlights today, and shows "+N more" overflow.
P10 does **not** invent a calendar store, an event store, a per-occurrence row, or
a new snapshot projection.

The one thing the shipped calendar **cannot** do is leave the current month: the
snapshot window is hardcoded to `[month_first, month_last]` of `Local::now()`
(`ffi/src/lib.rs:286-296`), and `CalendarView` recomputes that same current month
on every render (`Window.swift:2085-2091`). Month/week navigation, the mini-month
nav, and a week grid all need the **same primitive: a snapshot the shell can ask
for a chosen date-window**. That is the single genuine core addition. The second
is a birth verb — **`create_event`** — so the "+ Event" affordance and the
quick-add on a day cell make a real typed event (not an untyped scrap the clerk
quarantines, `ffi/src/lib.rs:1631-1649`). Everything else — month view, week view,
day selection, the right-panel day detail, inline event editing, item selection —
is **assembly of existing seams** (`EntityLine`, the inspector, `lotus_set_at`,
`openEntityTab`).

Liv's calendar (liv-ui-map §2.19, ~200 lines) is a global ambient tool with four
views (month/week/day/agenda), a three-column shell (mini-month + "My calendars"
checklist + "Other calendars" ICS feeds | grid | day-detail panel), per-kind
enable/disable config, ICS one-way feeds, and two-way Google sync. lotus keeps the
**durable core** — a vault-wide grid over anything with a date, month + week, a
day-detail panel, inline event edit — and **fences the rest**: ICS feeds stay
deferred behind the files pattern (feature-map #43), Google sync is out of scope,
the "My calendars" per-kind checklist becomes a **later config slice** (view state,
never cells), and day/agenda are **deferred pending month+week validation**
(feature-map #23 explicitly waits on day-view). No color system: the color budget
law holds — one accent (lake green #2f7d6b) for the today marker only, and the
five status dots; **no per-kind rainbow pills** (Liv's event=primary/task=warning/
note=sky/… is dropped, resolving that against interface.md's color budget).

## 1 · The load-bearing decisions

1. **The calendar is a projection over `due`, not a store.** Nothing on the
   calendar is a "calendar item" record. A day cell's contents are
   `entities where day_of(due) == cell` unioned with `occurrences where date ==
   cell`. This is already how the shipped `CalendarView` works
   (`Window.swift:2092-2102`): it groups `model.rows(snap.dated)` by
   `due / 10_000` (the civil YMD) and appends each occurrence's series entity to
   the day its rule names. P10 keeps this exactly. **Property-based positioning is
   law** (feature-map #24): an entity appears on the calendar because it has a
   `due` cell, *never* because of its type — a `note` with a `due`, a `task` with
   a `due`, and an `event` all land on the grid identically. (Which property
   positions which kind — the configurable `dateField` of Liv — is a **later
   config slice**, §8; v1 positions everything by `due`, the one dated property
   seeded.)

2. **All-day vs. timed is already in the data — `date_only`.** The snapshot's
   `EntityRow` carries `dueDateOnly` (`ffi/src/lib.rs:302-307`, from the
   `DateTime`'s `date_only` bit), and `Civil.text(due, dateOnly:)` already renders
   a date with or without `HH:mm` (`Window.swift:557-573`). An event created with
   a time is timed; one with only a date is all-day. The week grid's all-day rail
   vs. hourly-block distinction reads this bit — **no `isAllDay` heuristic, no
   string-parsing of the start time** (Liv parses `startTime` for an `HH:mm`;
   lotus has the fact structurally). This resolves "how does the week grid know
   which band an item belongs in": `row.dueDateOnly == true` → all-day rail;
   `false` → hourly block at `due % 10_000`.

3. **THE ONE GENUINE CORE GAP: the snapshot window is fixed to the current
   month.** `dated` is every dated entity (fine — the shell filters by day), but
   `occurrences` is expanded only over `[month_first, month_last]` of *now*
   (`ffi/src/lib.rs:286-296`). A calendar that navigates to next month, or a week
   grid straddling a month boundary, would show **no recurring occurrences**
   outside the current month. P10 adds a **windowed snapshot FFI**,
   `lotus_snapshot_window_at(path, from_civil, to_civil)`, that runs the identical
   projection but expands `recurrence::occurrences(store, from, to)` over the
   asked window (the engine already takes `[from, to]` and caps it at a year,
   `recurrence.rs:71-82` — the window *is* the horizon, by its own design). The
   shell holds the viewed period as **transient view state** (never a cell) and
   asks for the matching window. `dated` needs no windowing (it is already the
   full sorted set; the shell buckets by day), so the only behavioral change is
   which `[from, to]` feeds `recurrence::occurrences`. **No new snapshot field, no
   new projection shape** — same `Snapshot` struct, a caller-chosen window.

4. **`create_event` is the only new birth verb — a `create_task` twin.** The
   "+ Event" button and double-click-a-day-to-create both need a real typed event
   born with a `due`. Capture makes an untyped scrap the clerk quarantines
   (`ffi/src/lib.rs:1631-1649`) — wrong for a deliberate event. So P10 adds
   `content::create_event(session, due, created)` (Create + `type=event` + a `due`
   cell + `created`), `lotus_create_event_at(path, due_civil, date_only)`, and
   `BoxModel.createEvent`. It is a strict twin of `create_task`
   (`content.rs:236-264`) — the only difference is it writes a `due` at birth
   (from the clicked day/time) instead of a `status`. **No location/attendees/notes
   cell at birth** (§5.2): those are set after birth through the inspector, exactly
   as a task's priority/due are. This resolves "does create_event write the rich
   Liv event fields": **no** — birth is minimal, the rest is post-birth `set`.

5. **The surface is a *steerable* version of the shipped `CalendarView`, plus a
   week renderer — no new UI primitive for month.** Month already ships. P10 makes
   its period navigable (prev/next/today, driven by view state and the windowed
   snapshot), adds a **day-selection** state that drives a **right-panel day
   detail** (the entities on the selected day as `EntityLine` rows — reusing the
   Today/Library row), and adds a **week grid** (the "same renderer at a different
   density" the feature-map names, #23). Inline event editing reuses the
   **inspector** (an event opened selects it; its `due`/`location`/`notes` cells
   edit through the ordinary property UI) — **no bespoke EventEditor panel** for
   v1; Liv's inline day-panel editor is a **visible design change flagged for a
   mockup** (§6.4) before it is built, because it is a new editing affordance, not
   a reuse of the inspector.

6. **Deferred, and explicitly so: day view, agenda view, per-kind config /
   "My calendars", drag-to-reschedule, ICS feeds, Google sync, per-kind colors.**
   Each is named in §8. Month + week is the ship (feature-map #23: "week is same
   renderer at different density; day view deferred").

## 2 · The calendar's data — nothing new, read three ways

An event, e.g. `Standup`:

```
Create #6200
name     = "Standup"                    (props::NAME, text)
type     = →event                       (props::TYPE, reference to the seeded "event" type)
due      = 2026-07-09 09:00             (props::… "due" datetime; date_only=false → timed)
created  = 2026-07-08 …                 (props::CREATED)
location = "Room 4"                     (props::… "location" text; set after birth, optional)
```

A recurring series is one entity carrying a `recurrence` text cell
(`recurrence.rs:1-8`); its occurrences are **virtual**, computed by
`recurrence::occurrences`, stored nowhere. An all-day event is the same shape with
`date_only=true` on its `due`. **The calendar reads exactly three things already
in the snapshot**:

- `snap.dated` — `Vec<Id>`, every non-recurring entity with a `due`, sorted
  ascending (`ffi/src/lib.rs:267-283`). The grid buckets these by
  `row.due / 10_000` (civil YMD).
- `snap.occurrences` — `Vec<OccurrenceRow{ series, civil }>`, the window's
  expansion of every live series (`ffi/src/lib.rs:293-296`). The grid draws the
  **series entity** on each occurrence's day (`Window.swift:2098-2102`).
- each `EntityRow`'s `due` (`Int64` civil), `dueDateOnly` (all-day bit), `title`,
  `kinds`, `status` — already populated for every entity.

**No calendar-specific snapshot field, no `events` list, no `CalendarItem`
record.** The union of `dated` + `occurrences`, bucketed by day, *is* the calendar.

## 3 · The steerable window — the one genuine Rust addition

### 3.1 The gap, precisely

`lotus_snapshot_at` (`ffi/src/lib.rs`, the current snapshot entry) computes
`month_first`/`month_last` from `Local::now()` and passes them to
`recurrence::occurrences` (`:286-296`). Navigate the calendar to August and August's
recurring occurrences are simply absent — `dated` still carries August's one-off
events (it is the full set), but every "every week" series stops at the current
month's edge. A week grid crossing into next month has the same hole. The engine is
**not** the limitation — `recurrence::occurrences(store, from, to)` already accepts
an arbitrary window and caps it at 366 days (`recurrence.rs:71-82`). The limitation
is that **only the FFI names the window, and it names one fixed window**.

### 3.2 FFI — `lotus_snapshot_window_at(path, from_civil, to_civil)`

Factor the current snapshot body into a `fn snapshot_windowed(store, from, to) ->
Snapshot` and give it two callers:

```c
/* The default snapshot — the current month's window, unchanged behavior.
   Every existing caller keeps working; this is now a thin wrapper. */
char *lotus_snapshot_at(const char *path);

/* The same snapshot over a caller-chosen date window: `dated` is unchanged
   (the full sorted set; the shell buckets by day), but `occurrences` is the
   engine's expansion over [from_civil, to_civil]. Civil dates are the Int64
   YYYYMMDD0000 form. The window is the horizon; the engine caps it at a year.
   Returns the same JSON shape as lotus_snapshot_at. */
char *lotus_snapshot_window_at(const char *path, int64_t from_civil, int64_t to_civil);
```

`lotus_snapshot_at` becomes `snapshot_windowed(store, current_month_first,
current_month_last)` — **byte-identical output to today**, so nothing downstream
(TodayView, EverythingView, the existing `CalendarView`) changes. **Declare both in
`shell/macos/lotus.h`** beside the current snapshot decl — the Swift side links the
hand-maintained header; an export without its `.h` line is unresolved.

**Why a window arg, not a whole new projection.** The alternative (a `calendar`
field on the snapshot pre-bucketed by day) would (a) duplicate `dated`/`occurrences`
the snapshot already carries, (b) bake the current-month assumption deeper, and
(c) force every snapshot — including Today's — to pay for calendar bucketing. The
window arg is the minimal honest shape: the shell already decides what period it
shows; it should say so when it asks. This mirrors P8's decision to **not** add a
`tasks` projection when a client-side filter over the existing snapshot suffices —
here the client-side buckets suffice, only the *occurrence window* must be steerable.

### 3.3 Shell — `BoxModel.snapshotWindow` (view-state-driven refresh)

The shell holds the viewed period as **transient `@State`** (never a cell —
interface.md 0.5: view settings live in transient state, never entity data):
`viewMonth` (for month/agenda), `selectedDay` (drives week grid + day panel),
`viewMode` (`.month | .week`). When the period changes, `BoxModel` refreshes from
the windowed FFI:

```swift
// The window the current view needs: the visible month's grid extent
// (month view) or the selected week's Mon–Sun (week view). Held in view
// state, never persisted; recomputed on navigation.
func snapshotWindow(from: Int64, to: Int64) {
    boxQueue.async {
        let json = lotus_snapshot_window_at(self.path, from, to)
        // parse into self.snap exactly as the default refresh does
        ...
    }
}
```

The existing `refresh()` (default month window) stays for every other surface;
`CalendarView` calls `snapshotWindow` with its viewed extent on navigation.

## 4 · `create_event` — a birth verb, a `create_task` twin

### 4.1 Service — `content::create_event`

Beside `create_task` (`content.rs:236-264`), differing only in what it writes at
birth (a `due` from the clicked day/time instead of a `status`):

```rust
/// Birth of an event: Create + type=event + a due cell + created, one
/// transaction. Born with the clicked day/time as its due (all-day if
/// `due.date_only`), typed `event` so it lands on the calendar (property-based
/// positioning: it appears because it has a `due`). Named later (born nameless
/// like create_task, so the caller drops into renaming). Location, notes, and
/// attendees are set after birth via the inspector — never at birth. Distinct
/// from capture, which makes an untyped scrap the clerk quarantines.
pub fn create_event(
    session: &mut Session,
    due: DateTime,
    created: DateTime,
) -> Result<Id, PersistError> {
    let event_type = find_type(session.store(), "event");
    let due_prop = property_id(session.store(), "due");
    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    if let Some(event_type) = event_type {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: props::TYPE, value: Value::Reference(event_type) },
        });
    }
    if let Some(due_prop) = due_prop {
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell { property: due_prop, value: Value::DateTime(due) },
        });
    }
    commands.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::CREATED, value: Value::DateTime(created) },
    });
    session.commit(commands, "new event", Author::User)?;
    Ok(id)
}
```

The `event` type already exists (`lib.rs:430`) — **no seeding needed for the
verb**. `due` already exists. `create_event` invents nothing.

### 4.2 FFI — `lotus_create_event_at(path, due_civil, date_only)`

Mirror `lotus_create_task_at` (`ffi/src/lib.rs:1006-1012`), threading the clicked
day/time and the all-day bit:

```c
/* Create an event by hand (the "+ Event" button, or double-click a day/hour).
   One transaction: type=event + due(from due_civil, all-day if date_only) +
   created. Returns the new id, or 0 (busy box / failure). Distinct from
   capture, which makes an untyped scrap the clerk quarantines. */
uint64_t lotus_create_event_at(const char *path, int64_t due_civil, int32_t date_only);
```

Reconstruct the `DateTime` from `due_civil` + `date_only` the same way the seam
parses a datetime `set` (the datetime branch of `parse_value`). **Declare in
`lotus.h`** beside `lotus_create_task_at` (`:87`).

### 4.3 Shell — `BoxModel.createEvent`

A twin of `createTask` (`Window.swift:288-296`), returning the new id so the
caller can select it and drop into renaming:

```swift
func createEvent(dueCivil: Int64, allDay: Bool, done: @escaping (UInt64?) -> Void = { _ in }) {
    boxQueue.async {
        let id = lotus_create_event_at(self.path, dueCivil, allDay ? 1 : 0)
        DispatchQueue.main.async {
            if id == 0 { NSSound.beep() }
            done(id == 0 ? nil : id)
            self.refresh()
        }
    }
}
```

## 5 · The event's rich fields — set after birth, not at birth

### 5.1 What Liv's event carries vs. what lotus needs

Liv's `Event` (events.ts) carries `location`, `attendees[]`, `notes`,
`sourceNoteId`, plus sync fields (`feedId`, `externalUid`, `googleId`, `etag`).
lotus keeps the **three that are real content** — location, attendees, notes — and
drops the sync fields (ICS/Google deferred, §8). Per feature-map #26: "Events with
location, attendees (a reference, distinct from people-links), agenda, linked-note."

### 5.2 Two new properties, each on its OWN additive guard

`location` (text) and `attendees` (reference — a real reference to person
entities, feature-map #26 "distinct from people-links") are **not seeded today**.
They arrive through the **P8/P9-proven discipline: a separately-guarded additive
pass, NOT an edit inside `seed_starter_library`**. `seed_starter_library` returns
early when `due` exists (`lib.rs:382-383`), so an edit inside it never runs on a
shipped box. So P10 adds:

```rust
/// Event fields the calendar offers: `location` (text) and `attendees`
/// (reference to person entities — feature-map #26, distinct from a note's
/// people-links). Additive and idempotent on its OWN guard (not the
/// starter-library `due` guard, which short-circuits on every existing box):
/// an older box that already has `due` — every shipped box — gains these on
/// open. Offered, never expected: an event is valid without either, so the
/// `event` type's expectations ([due]) are left untouched.
fn seed_event_fields(session: &mut Session) -> Result<(), PersistError> {
    if property_id(session.store(), "location").is_some() {
        return Ok(());
    }
    let mut commands = Vec::new();
    // one text property + one reference property, mirroring the P8 priority /
    // P9 recurrence additive passes (lib.rs:112, :240)
    new_property(&mut commands, session, "location", "text");
    new_property(&mut commands, session, "attendees", "reference");
    session.commit(commands, "seed event fields", Author::System)?;
    Ok(())
}
```

Called from the open-time seeding sequence after `seed_starter_library`
(`lib.rs:65-68`), beside `seed_recurrence` and `seed_priority` — the exact place
the additive passes already live. **The `event` type's `expectations` ([due]) are
untouched** — location/attendees are *offered by the calendar surface*, not
*expected by the type* (a location-less event is valid), matching P8's
"offered-not-expected" for priority and P9's "not expected" for `related`.

- **The agenda / linked-note** (feature-map #26) reuses `props::CONTENT` (an
  event's body is its agenda) or `related` (the linked note) — **no new property**;
  the inspector already edits both.
- **Notes** on the event = `props::CONTENT`. So of the four rich fields, **two are
  new** (`location`, `attendees`), two reuse existing substrate.

### 5.3 Editing them — through the inspector, no new panel (v1)

Selecting an event on the calendar opens/selects it; its `location`, `attendees`,
`due`, and `content` cells edit through the **ordinary property inspector**
(`FieldRow` dispatches on `cell.kind` — datetime, text, reference — at
`Window.swift:2949`; the datetime cell already round-trips through `lotus_set_at`).
This is the whole edit path for v1. Liv's **inline day-panel EventEditor** (a
bespoke title/start/end/location/notes form in the right panel) is a **visible
design change** — flagged for a mockup before building (§6.4), because it is a new
editing surface, not a reuse of the inspector.

## 6 · The native surface (assembly, mostly shipped)

### 6.1 Surface + router — already wired

`Surface.calendar` already exists (`Chrome.swift:20`, label "Calendar", symbol
"calendar", `isGlobalTool == true`), routed in the center switch to
`CalendarView(model:)` (`Window.swift:975-976`), and rendered in the nav rail
(`SurfaceNav` iterates all cases). **No enum or router change** — the surface slot
is done. The work is inside `CalendarView`.

### 6.2 Month view — make the shipped grid steerable

The shipped `CalendarView` (`Window.swift:2078-2141`) draws a correct current-month
grid. P10 adds:

- **View state** — `@State viewMonth: (year, month)`, initialized to now; the grid
  computes `first`/`range`/`lead` from `viewMonth` instead of `Date()`
  (`Window.swift:2085-2091`).
- **Prev / Today / Next** — a header control (mirroring existing `LensHeader`
  trailing controls) stepping `viewMonth` by ±1 month, "Today" resetting it; on
  change, call `model.snapshotWindow(from: monthFirst, to: monthLast)` (§3.3) so
  occurrences follow.
- **Day selection** — `@State selectedDay: Int64?`; tapping a `DayCell` sets it
  and drives the day-detail panel (§6.5). The selected cell gets a soft fill (a
  neutral, not the accent — the accent is the today circle's only job, per the
  color budget and the shipped comment at `Window.swift:2160-2162`).
- **Item tap** — tapping an event/occurrence chip in a cell selects that entity
  (drives selection → inspector); double-tap opens it (`openEntityTab`). The chips
  are already plain-text primary-color rows (`Window.swift:2163-2168`) — no color
  change.
- **Quick-create** — hover a day cell → a "+" that calls
  `model.createEvent(dueCivil: dayAt0900, allDay: false)` then selects+renames
  (create-then-rename, exactly as TasksView quick-add, §4.3).

Everything here is **view state + existing seams**; the only new *visual* is the
selected-cell fill and the hover-"+", both small and within the established grammar.

### 6.3 Week view — the same renderer at a different density

A `WeekGrid` sub-view (feature-map #23: "week is the same renderer at a different
density"): seven day columns for the `selectedDay`'s Mon–Sun, an **all-day rail**
across the top (items with `dueDateOnly == true`, §2.2), and an **hourly grid**
below (timed items — `dueDateOnly == false` — positioned at `due % 10_000`). The
all-day/timed split reads the `date_only` bit directly (no string parsing). The
window feeding it is the visible week's `[Mon, Sun]` civil range → `snapshotWindow`.

**This is the largest new renderer and the place a mockup earns its keep** (§6.4):
the hourly grid (44px/hour in Liv), the all-day rail, lane-packing for overlapping
timed events, and the "now" indicator are all **new visual structure** with no
existing lotus analog. It should be **specced with a mockup** against the lotus
palette before building, and it is the natural **10c** slice (month ships first).

### 6.4 Visible design changes needing a mockup before building

Called out explicitly, per the brief:

- **The week grid** (§6.3) — hourly rows, all-day rail, timed blocks, lane-packing,
  "now" line. New structure; mock against the lotus palette first.
- **An inline day-panel EventEditor** (Liv's right-panel title/start/end/location/
  notes form) — **v1 does NOT build this**; editing goes through the inspector
  (§5.3). If owner wants the inline editor, it needs a mockup (it is a second
  editing surface competing with the inspector — a real design question).
- **Per-kind "My calendars" checklist** (Liv's left-panel event/task/note/… toggle
  with colored dots) — deferred to a config slice (§8); the colored dots violate
  the color budget as-drawn and need a palette-faithful redesign (likely a plain
  checklist, no dots) before building.

### 6.5 The day-detail panel — reuse `EntityLine`, no new primitive

A right-hand panel showing the `selectedDay`'s items as `EntityLine` rows (the same
row Today and Library draw): filter `snap.dated` + `snap.occurrences` to the
selected day, resolve each to its `EntityRow`, render as `EntityLine` with
`open(id)` → `openEntityTab`. A header shows the day's name/date (with a "Today"
badge if today, reusing the Today surface's badge). A "+ Event" button at the head
calls `createEvent` for that day. **No new UI** — it is the Library list scoped to
one day, plus a create button. (This is the smallest faithful port of Liv's
right-panel DayPanel, minus the inline editor.)

### 6.6 Mini-month navigator — deferred to a polish slice

Liv's left-sidebar mini-month (a compact grid with under-dots on days with items,
click-to-jump) is a **navigation convenience, not a data path**. It is a thin
`DayCell`-at-6px reuse driven by the same view state, and lands as **10d polish or
is deferred** — month prev/next + week are sufficient to navigate for v1.

## 7 · Slice plan (each an independent commit: build → tests → review → fix)

- **10a — the steerable window + `create_event` + a navigable month.**
  *Rust/FFI:* factor `snapshot_windowed(store, from, to)`; `lotus_snapshot_at`
  becomes the current-month wrapper (byte-identical output);
  `lotus_snapshot_window_at(path, from_civil, to_civil)` + its `lotus.h` decl
  (§3.2); `content::create_event` (§4.1); `lotus_create_event_at(path, due_civil,
  date_only)` + its `lotus.h` decl (§4.2); `BoxModel.snapshotWindow` +
  `BoxModel.createEvent` (§3.3, §4.3). *Shell:* give `CalendarView` a `viewMonth`
  state, prev/today/next stepping it, and a windowed refresh on navigation (§6.2);
  a hover-"+" quick-create-event on a day cell. *Tests:* `lotus_snapshot_at` output
  is unchanged (the wrapper is byte-identical — the load-bearing regression guard);
  `lotus_snapshot_window_at` over a **future** month returns that month's recurring
  occurrences (proving the window steers the engine) and over a window `> 366 days`
  is capped (the engine's own cap, `recurrence.rs:82`); `create_event` makes exactly
  one `type=event` entity with a `due` (all-day when `date_only=1`) + `created` and
  **no location/attendees/status** cell; the event type's expectations are unchanged;
  FFI round-trip (`lotus_create_event_at` → snapshot shows an `event`-kind entity on
  the asked day).

- **10b — day selection + the day-detail panel + `seed_event_fields`.**
  *Rust/FFI:* `seed_event_fields` (`location` text + `attendees` reference, its own
  idempotent guard, offered-not-expected, §5.2); call it in the open-time sequence
  after `seed_starter_library`. *Shell (mostly no Rust):* `selectedDay` state; the
  right-hand day-detail panel of `EntityLine` rows for the selected day, with a
  "+ Event" head button and item tap → select / double-tap → open (§6.5); the
  selected-cell fill and item-tap selection in the month grid (§6.2). Event editing
  goes through the existing inspector — confirm `location`/`attendees`/`due` round-trip
  (§5.3). *Tests:* `seed_event_fields` creates exactly `location`+`attendees` and is
  idempotent across two opens (**and lands on a box that already has `due`** — the
  guard-bypass is the load-bearing assertion, as in P8/P9); the event type's
  expectations still equal `[due]` (fields offered, not expected); setting
  `location` on an event via `lotus_set_at` round-trips in the snapshot; the day
  panel lists exactly the entities whose `due` (or occurrence) falls on the selected
  day.

- **10c — the week grid (needs a mockup first, §6.4).** *Shell only, no Rust* (the
  windowed FFI from 10a already feeds it): a `WeekGrid` for `selectedDay`'s Mon–Sun
  — an all-day rail (items with `dueDateOnly`), an hourly grid (timed items at
  `due % 10_000`), a "now" indicator, lane-packing for overlaps; a month/week view
  toggle; navigation steps by ±7 days in week mode, and the window follows. **Gated
  on a palette-faithful mockup** of the hourly grid before building. *Tests*
  (shell/manual + a Rust round-trip): a timed event renders in the hourly band at
  its hour and an all-day event in the rail (the `date_only` split); a week
  straddling a month boundary shows recurring occurrences on **both** sides (proving
  the window, not the fixed month, feeds it); creating an event by double-clicking
  an hour cell births it at that day+time.

- **10d — mini-month nav + polish (or fold/defer).** The left-sidebar mini-month
  (§6.6), keyboard nav (←/→ period, T for today, Esc to clear selection — ported
  from Liv if the owner wants it, open question below), empty-state copy, the
  quick-create rename flow. **Thin and foldable** — if 10a–c land clean, this rides
  along; nothing here is new substrate.

## 8 · Deferred (named, not built in P10)

**Day view** and **agenda view** (feature-map #23 defers day pending month+week
validation; agenda is a list rendering that overlaps the day panel) · the **inline
day-panel EventEditor** (v1 edits through the inspector, §5.3; the inline form needs
a mockup and a real answer to "two editing surfaces?") · **per-kind config /
"My calendars"** — the configurable `dateField`/`titleField` per kind (feature-map
#24's "connect an arbitrary property to the date position") and the enable/disable
checklist, all **view state never cells** (interface.md), a **later config slice**;
v1 positions everything by `due` · **per-kind colors** (event/task/note rainbow
pills — dropped, color-budget law; the calendar's only green is the today circle) ·
**drag-to-reschedule** (Liv doesn't drag events either; needs `set(due)` on drop —
a gesture, not substrate; deferred with the tasks board's drag, feature-map #18) ·
**ICS one-way feeds** (feature-map #43, fenced behind the files pattern; VEVENT UID
→ `external-id`, feed-owned fields refreshed while user cells preserved) ·
**two-way Google sync** (out of scope; OAuth + push/pull is a separate track) ·
**multiple calendars as saved views** (feature-map #25 — saved calendar queries,
distinguished by view not color; rides the saved-search / query-list track, P9 §7 /
feature-map #28) · **the mini-month navigator** (§6.6, 10d or deferred) ·
**recurrence-editing UI** (creating/editing a series' rule from the calendar — the
engine exists; a rule-editor affordance is later; v1 shows occurrences read-only) ·
**editing one occurrence** (the exception-materialization path exists in the core,
`recurrence.rs:135-153`; surfacing "edit just this one" is a later gesture) ·
**timezone handling beyond local civil dates** (lotus is local-civil throughout,
`recurrence.rs`/`Civil`; matches Liv's local-string model).

## 9 · Open questions for the owner (Konrad)

1. **Default view — month or week?** Feature-map #23 leads with month; Liv defaults
   to whatever was last used (view state). Recommendation: **month** as the initial
   default (it ships in 10a; week is 10c). Confirm.

2. **Does v1 need the inline day-panel EventEditor, or is inspector-editing enough?**
   §5.3 ships inspector-editing (no new panel). Liv's inline editor is a second
   editing surface. Recommendation: **inspector only for v1**, revisit with a mockup
   if editing-in-place proves necessary. Confirm before 10b.

3. **Do timed events need an hour-grid with drag in v1, or is a read-position-only
   week grid enough?** §6.3/§8 defer drag-to-reschedule. Recommendation: **week grid
   positions timed events read-only in v1; drag is deferred** (a `set(due)`-on-drop
   gesture, not substrate). Confirm.

4. **Port Liv's keyboard nav (←/→ step period, T = today, Esc = clear selection)?**
   Cheap to add in 10d, matches Liv. Recommendation: **yes, port it** (it is
   view-state stepping, no new substrate). Confirm.

5. **`attendees` as a reference to person entities vs. free text?** Feature-map #26
   says "a reference, distinct from people-links." §5.2 seeds it as `reference`.
   Confirm that attendees should resolve to real `person` entities (enabling the
   reference picker, deferred) rather than a text list for v1.

6. **When an entity has both a `due` and a future custom date property, which
   positions it on the calendar?** v1 has only `due`, so moot for now — but the
   config slice (§8) will need a priority rule. Flagging it as the config slice's
   first decision, not a P10 blocker.
