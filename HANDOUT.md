# Liv — handout (30 September 2026)

Start a fresh session with this file. It says what is true **now**, from
August onward, and nothing else. When it disagrees with an older design
doc, this file wins; when it disagrees with the code, the code wins.
`CLAUDE.md` still holds the house rules and is read automatically.

## 1. What Liv is

A note, task and calendar app for iPhone that arrives already organised:
you put anything in within two seconds and still find it later. The
product page is `design/what-liv-is-for.md` (one page, worth reading).

## 2. Where things stand

- **Branch** `polish-pass-lmkl30`. Last commit `53027d8` (29 Sep).
- **A lot is uncommitted** — everything from the 29th and 30th. The owner
  commits; do not commit unless asked. It is, by theme:
  - **Trash**: newest-thrown-away first, Today / Yesterday / Earlier,
    search, "Put back all", Select. Several come back as one write and one
    undo (`Engine::restore_many`, `liv_restore_many` — an additive FFI verb,
    with tests; the CLI takes `liv restore ID ID…`). `Trash.swift` also has
    edits from outside this session; read its diff before touching it.
  - **No explaining text** anywhere in the app.
  - **Unsorted** lists empty, untitled notes too.
  - **Card lists** (Notes, Tasks, Today, Unsorted) rebuilt so a swipe looks
    right — see §5.
  - **One hairline** for every separator (1 pixel, `#383838`).
  - **Clearer steps 1–3** from `design/clearer.md`: the new glyphs, the 16pt
    second line, the new chips and segment control, and the panel's
    "option A" (below). **Steps 4 and 5 are dropped** (owner, 30 Sep).
  - **Every screen reads Rust's answers** (30 Sep, evening; the two top
    changelog entries): Today, Tasks and Calendar (`liv_view_today`,
    `liv_view_tasks`, `liv_view_day`, reshaped in place on the owner's
    word), then Notes, Unsorted and the library panel's counts (one new
    `liv_view_library`) and Search (new `liv_view_search`).
    `surface/src/day.rs` became `calendar.rs`; `library.rs` is new.
    Filing a scrap from Unsorted was broken and is fixed.
  - **A refresh reads only the screen you are looking at** (30 Sep,
    night, owner's word): Today, Tasks, the Calendar or Unsorted's
    suggestions, read again as the screen comes back. The clerk's sweep
    is linear in the box again (5,052 → 332 ms at 5,000 things). A
    thing's properties card asks for its own suggestions through
    `liv_sweep_one` (new, additive); `liv inbox ID` reads the same.
  - Untracked and meant to stay: `design/clearer.md`,
    `design/mockups/clearer.html`, `design/testflight.md`,
    `design/how-its-built.md`, `surface/src/calendar.rs`,
    `surface/src/library.rs`, `surface/tests/library.rs`,
    `shell/ios/Icon/`, `shell/ios/Sources/WorkspaceForm.swift` (it replaced
    `WorkspaceSwitch.swift`).
- **Checks**: `cargo test` 375 pass. `suites.sh` 13/13. `drive.sh tour`,
  `facets`, `settings`, `workspace` pass. `drive.sh panel` and `routes`
  fail, and failed before this work too.

## 3. The code

```
engine/    Rust. The store: ops over SQLite in liv.db, built for sync.
surface/   Rust. What each screen asks: Today, Tasks, Notes, day, search,
           trash, and the clerk's suggestions.
ffi/       Rust. The one C ABI (ffi/liv.h), ~50 liv_* verbs.
cli/       Rust. `liv` — seeds and inspects a box with the app's own verbs.
shell/ios/ Swift/SwiftUI. THE app, and the only shell.
```

`core/`, `services/`, `views/` and `convert/` were deleted on 29 Sep
(stage 5). What went with them and is not rebuilt: recurrence expansion,
import/export, the folder "vault", habits, time tracking, pins, daily
notes, widgets, file-content search, the phone→desktop handoff. All in git
at `fd7acd8^`.

Swift files that matter most: `Box.swift` (the only file that calls
`liv_*`), `Theme.swift` (the only place a size or colour is defined),
`Rows.swift` (cards and rows), `Kit.swift` (shared controls), `Glyph.swift`
(the icon set), `Panel.swift`, `Desk.swift`/`Chrome.swift` (the desk and its
state), one file per screen (`Today`, `Tasks`, `Inbox` = Unsorted,
`Everything` = Notes, `Calendar`, `Search`, `Trash`, `Settings`).

## 4. Build, run, check

```
cargo test                                   # all Rust
shell/ios/build.sh                           # the app; `build.sh run` boots a simulator
shell/ios/suites.sh                          # the app's self-checks (13)
shell/ios/drive.sh tour                      # drives the app, asserts what is on screen
cargo build -p liv-cli && target/debug/liv --box <dir>/liv.db list --all
```

- **Simulator**: use `8E699FF6-03A1-433B-A602-C51A30B14E87` (iPhone Air).
  **Never** `00E539E0-…` — the owner's data lives there.
- **A test box**: `liv --box <dir>/liv.db new task Pay rent --due 2026-09-30 --area Home`,
  then launch with `SIMCTL_CHILD_LIV_BOX_PATH=<dir>/liv.db xcrun simctl launch
  --terminate-running-process <udid> app.liv.ios -desk.boot tasks`.
  `-desk.boot` takes today, tasks, inbox, notes, calendar, library, trash,
  search, create, … (`App.swift`). `LIV_NOW_MS=<ms>` makes the CLI write as
  if at another time, to seed "yesterday".
- **`drive.sh` needs `axe`** (`brew install cameroncooke/axe/axe`).
- **Motion bugs need video**, not screenshots: `xcrun simctl io <udid>
  recordVideo`, then look frame by frame. Most UI bugs this month lived for
  two or three frames.
- **The owner's phone**: standing wish is to push there after building
  (`build.sh device run`). The developer membership has lapsed — read
  `design/testflight.md` first.

## 5. How a list of cards works (read before touching one)

The four card lists are **inset-grouped SwiftUI Lists** (`livCardList()`),
so each cell is the card's width and clips its row. Each screen is one
section; its title is the first cell and `LivCardListEnd()` the last, so
the system never rounds a real row with its own radius. Rows draw their
own piece of the card (`livCardRow(position:)`, radius 22).

- **Rows are keyed by id AND position** (`livCardSlots`): the List redraws
  a row that changed place a couple of frames late, so a row whose place
  changes is made a new row instead. A fold header is a different row open
  and shut (`livFoldRow`).
- **Swipe**: iOS only puts a swipe button's word under its icon on rows
  60pt or taller, so every row that swipes is 64 (`LivCards.swipeRow`).
  Swipe buttons draw the app's own glyphs (`livSwipeLabel`). While swiped,
  only that row rounds and loses its line, slowly (`LivMotion.lift`), and
  squares off as you let go.
- **How a row knows it is swiped**: inside List cells every coordinate
  space reads as the screen's, so a row compares its screen x with the
  List's own (`LivCardListFrame`), and the check is off while the library
  panel is drawn or dragged (`livSwipesLive`).
- **Changes land in one frame.** Segment switches, the day strip, folds
  and area counts do not animate the list — only the control that was
  touched moves. The owner calls this "two states".

## 6. House rules that bite

- The full rules are in `CLAUDE.md`. The ones that come up daily:
  failing test first for `engine`/`surface`/`ffi`; FFI changes additive,
  with a test, and **told to the owner**; every `liv_*` call in
  `Box.swift`; delete code a change makes dead; mockup first for visible
  UI; verify on the simulator, and break a check once before trusting it.
- **Tappable things have three shapes only**: a full-width row, a hollow
  chip (`AddChip`), a filled pill (`ConfirmPill`). The only tappable text
  is a link inside a note.
- **No explaining text.** Labels say what things are ("Inactive", never
  "Parked"). Empty states are one to three words.
- **Talking to the owner**: short, plain, concrete. Two paragraphs,
  numbers and names, no abstractions. He decides; ask when a choice is
  his, with a recommendation.

## 7. What the owner has decided (still in force)

**Product.** Launches on Today. Areas are made by the user; none are
built in. The clerk only suggests ("Work?"), one tap accepts. No
templates, no typed-query language, no "advanced" features, no Quick
Capture sheet, no parsing of typed text, no file preview (a `.md` file is
a note; other files show name, size and path, and open elsewhere).

**The desk.** Five views in two groups: Today, Unsorted / Notes, Tasks,
Calendar. An open document is separate from the view you are in; `‹`
lands on the list. A panel row always lands on its view's root. The bar
is three glass pieces — `‹ ›`, search, `+` with the numbered tab box — no
words. `+` makes a note; holding it offers Note, Task, Event, File, Scan
text. Tasks and events open as a card where you stand. Menus are cards
that grow from what opened them. The undo chip sits at the foot. After
a write only the view on screen is read again, not one under a note, and
a view is read again as it comes back.

**Library panel.** Not full screen. Views, then Workspaces (each its first
letter, or its name's first character if it has no letter), All
workspaces, New workspace. The foot: Trash and Settings circles, the bar's
size, level with its keys. Saved filters are gone. A rejected try:
"Areas + Recent".

**Today.** Title is today's weekday; under it the date and a count per
area. Late items fold (folded when more than three). The schedule is one
card with a time column; the now line is red. "What next" lists up to
five undated tasks. No add row.

**Tasks.** Segmented filter (every status, plus a Project menu). An add row
first, with a plain `+`. Swipe right: Tonight, Tomorrow, Weekend, Pick.
Red only when late. Due times default to 09:00; reminders ring at the due
time.

**Unsorted.** Means "no area", for any kind, empty notes included.
Routing asks where (areas first); other kinds sit behind "Not a note…".
Things caught from other apps get no workspace stamp; things made inside
get the workspace's area.

**Notes and the editor.** Markdown syntax shows only on the caret's line;
links always show as their name. One toolbar above the keyboard, which
stays. Making a link opens Search. A nameless thing reads as its kind
("Note · 29 Sep 17:26"), never "Untitled". History has Restore.

**Calendar.** Notion's layout: the timeline is the screen, the month is a
jump card. Hold to place, drag, release to create; hold a block to lift
it, a bin appears. No all-day row. Quarter-hour times.

**Search.** Field at the foot. Only your words go in the field; picked
filters are chips (Only / Hide / Any).

**Properties.** A sheet card from its own key. Settings-style cards,
"None" for empty. Name editable in the header; no "edited" line, no kind
row, no field icons. `tags` reads as "Subject". Hide what can't be used.

**Trash.** As in §2. Nothing is ever deleted for good; the log only grows.

**Workspaces.** Made from pickers only: Name, Area, Subject. The card that
listed them is now only the form (New / Edit workspace).

**Settings.** Appearance, Suggestions, Reminders. Nothing else.

**Look.** The brief of 30 Aug: minimal, quiet, clear hierarchy, nothing
system-looking. Dark ground `#1A1A1A`, one accent `#5B8BC2`, nothing over
62% saturation, and bold-but-small marks rather than faint ones ("You have
a tendency to make UI elements tiny and subtle"). Type: titles 34, card
headers 20, row titles 18, second lines and facts 16, footnotes 14 —
nothing else. Rows 52, or 64 with a second line or a swipe. Icons are one
monochrome pen (24 grid, 1.75 line); the dot is the signature (title full
stop, the now line, dots in icons). Six-tooth gear. Glass for controls,
system spring for motion (0.30s, no bounce). Refused so far: serif or
bundled fonts, textures, gradients, area tiles, bottom fades.

## 8. Open, known broken, or waiting on the owner

- `drive.sh panel` ("could not open a note from the list") and `routes`
  (`liv://capture` lands on a document under Tasks) fail.
- Today's late rows carry a blue "Today" word — tappable text, against the
  rule. He has not ruled.
- Light mode renders faintly; nobody has drawn it.
- A `- [ ]` inside a code block gets a live checkbox. A link to a trashed
  thing turns into plain text on save and does not come back.
- Pages scanned sideways are read rotated.
- The Share extension on a real device needs a provisioning profile for
  `app.liv.ios.share`.
- Deferred by name: templates, a replacement for filters, new tasks/events
  opening where a note opens, the desktop shell, and everything listed in
  §3 as gone with `core/`.

## 9. What is next

**The clean-up, in the owner's order (30 Sep):**

1. **Screens read Rust's answers, and Swift only draws.** Done for every
   screen. Left in Swift: reminders (`Notify.swift` decides what rings —
   a rule, the next to move), a row's icon (`LivKind`), and the
   calendar's block layout (on purpose). `liv_view_everything`,
   `liv_search` and `liv_note_tasks` are removed (owner, 30 Sep).
2. **Cut `design/` to four living docs** — `what-liv-is-for.md`,
   `how-its-built.md`, this handout, the changelog — and move the rest to
   `design/archive/`. Not started.
3. **Shorten the history comments** in each file as it is touched, not in
   one sweep.
4. Then sync, below.

**Sync** is the next stage of the engine plan
(`design/rust-owns-the-mechanisms.md` §5, item 6): the engine already has
ops, dots, version vectors and a hold buffer, all tested, and nothing
uses them yet. Ask the owner before starting it — he last steered the
work toward the look of the app.

## 10. Which docs to trust

- **Read**: `CLAUDE.md`, this file, `design/what-liv-is-for.md`,
  `design/how-its-built.md` (the code on one page),
  `design/clearer.md` (the look, with its mockup), and the top of
  `design/changelog.md` (newest first; each entry says why).
- **Only for a specific question**: `design/rust-owns-the-mechanisms.md`
  (engine plan and measurements), `design/ios.md` (numbered revisions of
  the app; long), `design/testflight.md`.
- **History, not guidance**: `interface.md`, `feature-map.md`,
  `liv-ui-map.md`, the `design/p*.md` phase docs, `core.md`,
  `core-plan.md`, `one-core.md`, and the studies. They describe older
  apps and older plans, say `lotus_*` for `liv_*`, and cite a Mac shell
  that no longer exists.
