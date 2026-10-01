# Liv — handout (1 October 2026)

Start a fresh session with this file. It says what is true **now**. When
it disagrees with an archived doc, this file wins; when it disagrees with
the code, the code wins. `CLAUDE.md` holds the rules and is read
automatically; `design/how-its-built.md` is the code on one page.

## 1. What Liv is

A note, task and calendar app for iPhone that arrives already organised:
you put anything in within two seconds and still find it later. The
product page is `design/what-liv-is-for.md`.

## 2. Where things stand

- **Branch** `polish-pass-lmkl30`, pushed. Everything up to 30 Sep is
  committed (`02af0ac`, merged with the clearer spec's four commits from
  GitHub as `b304932`). Uncommitted: the doc clean-up of 1 Oct (this
  file, `CLAUDE.md`, `design/archive/`).
- **Every screen reads Rust's answers**; Swift draws. A refresh reads the
  library and the screen on show, nothing else. The clerk's sweep is
  linear again. Reminders are Rust's too (`liv_view_reminders`). The
  door (`ffi/liv.h`) has 49 functions.
- **Checks**: `cargo test` 375. `suites.sh` 13/13. Every `drive.sh` check
  passes (1 Oct); `cycles` is a report, not a check. Checks that need
  something on screen make it through the CLI (`seed`) and trash it after.
- **Gone with `core/` on 29 Sep, not rebuilt**: repeating events,
  import/export, the folder "vault", habits, time tracking, pins, daily
  notes, widgets, file-content search, the phone→desktop handoff. All in
  git at `fd7acd8^`.

## 3. Build, run, check

The commands are in `CLAUDE.md`. What else helps:

- **Simulator** `8E699FF6-03A1-433B-A602-C51A30B14E87` (iPhone Air).
  Never `00E539E0-…` — the owner's data lives there.
- **Launch on a test box**: `SIMCTL_CHILD_LIV_BOX_PATH=<dir>/liv.db xcrun
  simctl launch --terminate-running-process <udid> app.liv.ios -desk.boot
  tasks`. `-desk.boot` takes today, tasks, inbox, notes, calendar,
  library, trash, search, create, … (`App.swift`). `LIV_NOW_MS=<ms>`
  makes the CLI write as if at another time, to seed "yesterday".
- **Motion bugs need video**, not screenshots: `xcrun simctl io <udid>
  recordVideo`, then look frame by frame. Most UI bugs this month lived
  for two or three frames.
- **The owner's phone**: the developer membership has lapsed. The owner
  is sorting it out and will report back; until then, simulator only.
  How-to is in `design/testflight.md`.

## 4. How a list of cards works (read before touching one)

The four card lists (Notes, Tasks, Today, Unsorted) are **inset-grouped
SwiftUI Lists** (`livCardList()`), so each cell is the card's width and
clips its row. Each screen is one section; its title is the first cell
and `LivCardListEnd()` the last, so the system never rounds a real row
itself. Rows draw their own piece of the card (`livCardRow(position:)`).

- **Rows are keyed by id AND position** (`livCardSlots`): the List redraws
  a row that changed place a couple of frames late, so a row whose place
  changes is made a new row instead.
- **Swipe**: iOS puts a swipe button's word under its icon only on rows
  60pt or taller, so every row that swipes is 64 (`LivCards.swipeRow`).
  While swiped, only that row rounds and loses its line.
- **Inside List cells every coordinate space reads as the screen's**, so
  a row finds out it is swiped by comparing its x with the List's own
  (`LivCardListFrame`), and not while the library panel moves.
- **Changes land in one frame.** Segment switches, the day strip and folds
  do not animate the list — only the control that was touched moves.

## 5. Working with the owner

- The owner is a designer. Short, plain, concrete: numbers and names, no
  abstractions. Ask when a choice is theirs, with a recommendation.
- **Big picture first** (owner, 1 Oct): many of the old rules were
  details that crowded out the whole — "the three tappable shapes" among
  them. They are in the archive (`design/archive/CLAUDE-until-2026-10-01.md`),
  not in force. Use judgement; keep the few rules in `CLAUDE.md`.

## 6. What the owner has decided (still in force)

**Product.** Launches on Today. Areas are made by the user; none are
built in. The clerk only suggests ("Work?"), one tap accepts, and never
acts on its own. No templates, no typed-query language (filters are
picked, never typed), no "advanced" features, no Quick Capture sheet, no
parsing of typed text, no file preview (a `.md` file is a note; other
files show name, size and path, and open elsewhere). No explaining text
in the app: labels say what things are, empty states are a few words.
The box's data is all test data (13 Sep) — change anything but how the
interface looks.

**The desk.** Five views: Today, Unsorted, Notes, Tasks, Calendar. An open
document is separate from the view you are in; `‹` lands on the list. The
bar is three glass pieces — `‹ ›`, search, `+` with the numbered tab box.
`+` makes a note; holding it offers Note, Task, Event, File, Scan text.
Tasks and events open as a card where you stand. The undo chip sits at
the foot.

**Library panel.** Not full screen. Views, then Workspaces, All
workspaces, New workspace; Trash and Settings at the foot. Saved filters
are gone.

**Today.** Today's weekday, the date and a count per area; late items
(folded when more than three); the day as one schedule card with a red
now line; "What next", up to five undated tasks.

**Tasks.** A status filter plus a Project menu, an add row first, swipe
right to reschedule (Tonight, Tomorrow, Weekend, Pick). Red only when
late. Due times default to 09:00; reminders ring at the due time.

**Unsorted.** Anything a person files that has no area, empty notes
included. Filing asks where first; other kinds sit behind "Not a note…".
It ignores the workspace, so nothing made in the wrong one vanishes.

**Notes and the editor.** Markdown syntax shows only on the caret's line;
links show as their name. Making a link opens Search. A nameless thing
reads as its kind and time ("Note · 29 Sep 17:26"). History has Restore.

**Calendar.** The timeline is the screen, the month is a jump card. Hold
to place, drag, release to create; hold a block to move it or drop it on
the bin. Quarter-hour times.

**Search.** The field at the foot holds only your words; picked filters
are chips.

**Properties.** A card of its own, Settings-style; `tags` reads
"Subject".

**Trash.** Newest thrown away first; put back one or many as one undo.
Nothing is ever deleted for good.

**Workspaces.** Made from pickers: Name, Area, Subject.

**Settings.** Appearance, Suggestions, Reminders.

**Look.** Minimal, quiet, clear hierarchy, nothing system-looking: a dark
ground, one accent, nothing loud, marks bold enough to see. Five type
sizes, one icon pen, glass for controls. The numbers live in
`Theme.swift`. Tried and refused: serif or bundled fonts, textures,
gradients, area tiles, bottom fades.

## 7. Open, or waiting on the owner

- **There is no way out of the app for your writing** — export went with
  `core/` on 29 Sep; only the CLI reads the box. The product page says so
  and keeps "will not lock your writing in" as the promise.
- The test simulator (`8E699FF6`) has notifications denied for Liv, so
  a reminder never reaches the screen there; the pipeline was checked up to
  iOS (1 Oct). Allow them in its Settings to watch one ring.
- Light mode renders faintly; nobody has drawn it.
- A `- [ ]` inside a code block gets a live checkbox. A link to a trashed
  thing turns into plain text on save and does not come back.
- Pages scanned sideways are read rotated.
- Deferred by name: templates, a replacement for filters, the desktop
  shell, and everything in §2 gone with `core/`.

## 8. What is next

The clean-up (owner's order, 30 Sep): **1** screens read Rust's answers —
done. **2** `design/` cut to the living docs — done (1 Oct). **3** shorten
the history comments in each file as it is touched — ongoing, never as a
sweep.

Then **sync**, the next stage of the engine plan.
The engine already has ops, dots, version vectors and a hold buffer, all
tested and unused. Ask the owner before starting sync.

## 9. The docs

- **Read**: `CLAUDE.md`, this file, `design/what-liv-is-for.md`,
  `design/how-its-built.md`, and the top of `design/changelog.md`.
- **Reference**: `design/op-format.md` (the on-disk format),
  `design/testflight.md` (phones).
- **History**: `design/archive/` — the old specs, phase docs, studies,
  mockups and the old rules. Code comments still cite some of them by
  name.
