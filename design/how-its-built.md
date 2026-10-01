# How Liv is built

One page, written from the code on 30 Sep 2026. When this page and the
code disagree, the code is right and this page needs fixing.

## The shape

```
 the iPhone app         shell/ios/   Swift. Draws the screens, handles touch.
        │
 the door               ffi/         49 functions. Text in, JSON out.
        │
 the screens' answers   surface/     Rust. What Today, Tasks, Notes … show.
 the store              engine/      Rust. The ledger and the current state.
        │
 liv.db                              One SQLite file on the phone.

 cli/   `liv` — the same functions from the terminal, to seed and check a box.
```

Nothing below the door knows about the iPhone, so a desktop app could use
the same core unchanged.

## The data: things and cells

- Everything is a **thing**: a note, task, event, file, area, workspace,
  even a property. A thing's id is 16 bytes, written as 32 hex
  characters, and is never shown to anyone.
- A thing has **cells**, one per property: `name`, `body`, `due`,
  `status`, `area`, `project`, `people`, `tags` (shown as "Subject"), and
  so on. Its kind is a cell too.
- **A property has a token and a shown name**, and they differ: `tags` is
  what is stored and what the query grammar reads; "Subject" is what a
  person sees. `liv_properties` sends both (`word`, `name`); code keys off
  the token and draws the name. Keying off the shown name is how the area
  picker broke once.
- A cell holds one of seven kinds of value: text, number, yes/no, date, a
  pointer to another thing, a file's fingerprint, or a note body.
- **Pointers are how things relate.** A task's area is a pointer to the
  area, so renaming an area is one change.
- The basic vocabulary (properties, kinds, the three statuses) is built
  into the app, not written into the box, so two devices can never
  disagree about it. Areas, extra fields and workspaces are things the
  user makes.

## The store: a ledger and the current state

`engine/`. `liv.db` holds two parts.

1. **The ledger** (the `ops` table). Every change is added as a new entry,
   and no entry is ever edited or removed. One user action is one entry.
   It holds one or more of four operations: make a thing, set a cell, add
   to a list, remove from a list. Each entry records which device wrote it
   and when.
2. **The current state** (`entities`, `cells`, `links`, `edits`). It is
   worked out from each entry in the same transaction that adds it, and
   exists only to make reading fast. Throw it away and it rebuilds from the
   ledger byte for byte (a test checks this).

What the ledger gives for free:

- **Undo** adds an entry that reverses an earlier one. It only takes back
  what this device did.
- **Trash** is a cell (`trashed`). Nothing is ever deleted for good.
- **A note's history** is the list of entries that saved its body.
- **Sync** (not built) will be two devices swapping entries. The parts it
  needs are built and tested, and unused: device ids, a counter per device,
  and holding an entry back until the one before it arrives.

Files are known by fingerprint. Where a file sits on this phone is a
separate table that never syncs, because a path means nothing on another
device. Suggestions ("Work?") are worked out fresh each time. Only a
refusal is written, as a cell, so it syncs.

## The screens' answers

`surface/`. Rust functions that take the store and return what one screen
draws, already filtered, grouped and sorted: `today`, `tasks`, `calendar`,
`search_screen`, the clerk's suggestions, `reminders` (what rings, and
when), and `library` — every row the app
looks things up in, the Notes and Unsorted lists, and the count beside
each view in the library panel, in one pass over the box. Every rule in
them has a test, and a count and the list it counts come from the same
answer, so they cannot disagree.

**An answer carries everything its screen's controls can pick.** Today's
holds all seven days of the strip, and Tasks' holds every status group, so
tapping a day or a segment redraws in the same frame without asking again.
Only a change of who is on the screen asks again: the workspace, the Tasks
project filter, the Calendar's month.

**What Swift still decides:**

- Where a calendar block sits and how wide it is when things clash. It
  moves with the finger on every frame of a drag, so it stays in
  `Calendar.swift`.
- Which icon a row wears, and so how Search groups its hits (`LivKind`
  in `Glyph.swift`).
- The phone's half of a reminder (`Notify.swift`): asking permission,
  turning a wall-clock due into an alarm, and iOS's cap of 64 pending.
  Which things ring is Rust's.

## The door

`ffi/`, declared in `ffi/liv.h`. 49 C functions in four files:

- `surfaces.rs`: one read per screen.
- `basics.rs`: make, set, trash, restore. What every tap uses.
- `writes.rs`: note bodies, links, history, undo, accepting suggestions.
- `finding.rs`: search, workspaces, the trash list.

Every function takes the path to `liv.db`. A write is one transaction. An
answer is JSON or an error code, never both, and the returned string is
freed with `liv_string_free`. The door keeps each box open between calls.

## The app

`shell/ios/Sources/`, 46 files.

- **`Box.swift` is the only file that calls the door.** `BoxModel` runs
  every read and write on one background queue, so the app never races
  itself.
- **After every write, the app reads again.** Seven reads always — the
  library (every row, Notes, Unsorted and the panel's counts), the
  reminders, the trash, workspaces, the suggestions switch, the properties
  and the kinds — plus
  the answer of the ONE screen you are looking at: Today, Tasks, the
  Calendar, or Unsorted's suggestions (`BoxModel.screenChanged`, which
  `DeskHost` calls). A screen is read again as it comes back into view; a
  note laid over it hides it, a record's card does not. A thing's
  properties card asks for its own suggestions while it is open. Search
  asks on its own, as you type. Refreshes asked for while one is running
  collapse into one.
- **Where you are** lives in `DeskModel` (`Chrome.swift`): which view,
  which document, and whether the panel, search or a menu is up. `Desk`,
  `Panel`, `Bar`, `Navigate`, `Tabs`, `Plane`, `Positions` and
  `PanelDrag` draw and move it.
- **One file per screen**: `Today`, `Inbox` (Unsorted), `Everything`
  (Notes), `Tasks`, `Calendar` with `Month`, `Search`, `Trash`,
  `Settings`, `WorkspaceForm`.
- **Documents**: a note opens in the editor (`Editor`, `EditorText`,
  `EditorStyle`: markdown whose marks show only on the caret's line). A
  task or event opens as a card (`Record`). Properties are a card of their
  own (`Detail`).
- **The look** is defined in one place: `Theme.swift`, for every size and
  colour. `Kit.swift` has the shared controls, `Rows.swift` the rows and
  cards, `Glyph.swift` the icons.
- **Coming in from outside**: the Share extension (`ShareExtension/`, no
  Rust) drops text into a shared folder and `Catch.swift` picks it up.
  `liv://` links arrive through `Routes.swift`. Scanning text is
  `Camera.swift` and `Scan.swift`. `Notify.swift` sets reminders as local
  notifications.

## One tap, start to finish

Ticking a task on Tasks:

1. `Tasks.swift` calls `model.set(task, "status", "Done")`.
2. `Box.swift` calls `liv_set` on its background queue.
3. The engine checks the value fits (`write.rs`), adds one ledger entry
   and updates the current state, in one transaction.
4. `Box.swift` refreshes: the reads come back, the Tasks answer among
   them, and `BoxModel` publishes them.
5. SwiftUI redraws Tasks from the new answer: the task is in the Done
   group and the count under the title is one lower. Undo would add a
   second entry that reverses the first.

## How it is checked

- `cargo test`: about 370 Rust tests, across the engine, the screens'
  answers and the door. The cost tests check that doubling the box
  roughly doubles the work, and never more.
- `shell/ios/suites.sh`: 13 self-checks built into the app, run on the
  simulator by launch flag.
- `shell/ios/drive.sh`: taps through the running app and reads what is
  actually on screen from the accessibility tree (needs `axe`). `tour`
  visits every view.
- `liv`, the CLI: seed a test box, then check what a tap wrote with
  `liv --box … cells ID` or `history`.

## Not built

- Sync, and the desktop app.
- Repeating events: the property exists, and nothing expands it.
- Removed with the old core on 29 Sep and not rebuilt: import/export,
  habits, time tracking, pins, daily notes, widgets, file-content search,
  and the phone-to-desktop handoff.

## Where to change what

| To change … | Edit |
|---|---|
| a size, colour or spacing | `Theme.swift` |
| an icon | `Glyph.swift` |
| a button, chip or row | `Kit.swift`, `Rows.swift` |
| what a screen lists, or its order | `surface/src/<screen>.rs` (Notes and Unsorted: `library.rs`) |
| what a cell may hold, or a new property | `engine/src/model.rs` |
| something new the app can do to the box | `engine/`, then one function in `ffi/` (added, never changed), one call in `Box.swift`, one verb in `cli/` |
| how you move around | `Chrome.swift` (`DeskModel`) |
