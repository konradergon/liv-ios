# Plan — the owner's list of 1 October

## Status (2 October)

The owner's answers (1 Oct): **1** "what do you mean 2-day trial?" —
answered, waiting on a yes or no; **2** `#` is a setting; **3** "scanning
only. files opened if they contain text, which is edited as a note";
**4** "no, whole area when keyboard is down and no scrolling as you swipe
and when panel is open".

- **Done** (changelog, 2 Oct): the title flash (4) and two editor bugs
  found with it; the panel (9, 10 — and "from anywhere" had never worked
  on a list); the search field (7, not reproducible here — the likely
  causes fixed); the smallest heading (2); the `#` setting (3); files and
  the camera (8).
- **Removing values (12)** — the owner, 2 Oct: "i thought more of
  deassigning values that an object belongs to, like 'this note isn't
  area Work'" — and "no area isn't 'None', it's just no area assigned".
  Done: an × beside a one-value field takes it off, and an empty field is
  blank. Deleting a value itself is "useful to have" and next: the
  critique's simpler Remove (the value goes to the Trash, a trashed value
  counts as no value everywhere; Put back brings every filing back).
- **Designed, waiting for the phone**: vibrations (11) — one `LivHaptic`
  with four feelings (pick, lift, done, refuse), "a write feels its
  answer"; the simulator cannot vibrate.
- **The editor (5) — answered, 2 Oct**: "think we iterate over problems
  with the current editor instead of codemirror for now". No trial. Folding
  (1) is the native kind, L, and waits until the owner asks for it.
- The drag model (6): the owner kept "from anywhere"; what was broken in
  it is fixed above.

Each item, what it turned out to be when we looked, and what to do.
**S** = an hour or two, **M** = about a day, **L** = several days.
**Decision** marks the four the owner has to settle first.

## 1. First, the editor (item 5) — Decision

**What we have.** The iPhone's own text view (TextKit 1) with about 5,000
lines of our code on top: our markdown reader, our drawing of checkboxes,
bullets, rules, code blocks and quote bars, and our own hiding of syntax
off the caret's line. On 1 Oct alone it gave up six bugs: headings jumping
18pt as the caret moved, code blocks read as markdown, the caret's size,
three heading sizes, bold-italic, the stray tint. It works, but every new
feature — folding is the next — is more of the same fragile code.

**The proven alternative is CodeMirror 6**, inside a web view in the app.
Obsidian's and Joplin's phone apps use it for exactly this kind of editor:
markdown that hides its syntax off the line you are on. It brings
selection, undo, other-language keyboards, a markdown parser that only
re-reads what changed, heading folding and search, all used by millions.
A desktop app could use the same editor unchanged.

What it costs: a web view (tens of MB of memory, a short load when a note
opens), a JavaScript build step in the repo, a bridge for saving, links,
checkboxes and the toolbar, and the look written as CSS — generated from
`Theme.swift`, so sizes and colours still live in one place. How a web
view handles the keyboard and scrolling on an iPhone is the known risk.

What it removes: about 4,000 lines of Swift (`EditorText`, `EditorStyle`,
most of `Editor.swift`). The converter between markdown and the stored
form would move into Rust — one reader for the app, the CLI and a desktop
(rule 1). The stored form does not change; notes keep their history.

Other options: **Runestone** (native, but made for code, not for hiding
syntax); **a TextKit 2 rewrite** (Apple's newer engine — still our own
code, and still young on iPhone); **keep fixing** (cheapest now; the
doubt is fair).

**Recommendation: a two-day trial.** One note in CodeMirror on the
simulator: headings with folding, tasks, links, code blocks, the toolbar
over the keyboard. Measure typing, scrolling, the keyboard, opening time
and memory, try it, then decide. Items 1 and 3 below wait for this.

## 2. Small — next batch, about a day

- **Title flashes (4).** Cause found: every save of the body makes the
  app forget the note's properties (`Box.setContent` → `forgetCells`), so
  for one refresh the name reads as empty and the title shows its grey
  prompt, then the name comes back. Fix: a body save keeps the name, and a
  name not yet loaded counts as unknown, not empty. Found with it: text
  typed in the body while a rename reloads the note can be overwritten
  (`load()` does not check for unsaved typing). S.
- **Selecting text slides the panel (9).** The panel's drag starts
  anywhere and does not care that the keyboard is up. Fix: no panel drag
  while the keyboard is up — one line. S.
- **The visible strip of the desk scrolls while the panel is open (10).**
  The swipe that opened the panel also reached the list under it, which
  keeps scrolling. Fix: when the panel takes a swipe, the list under it
  lets go; nothing under the panel's shade takes touches. S.
- **Keyboard over the search field (7).** Search asks for the keyboard
  while its screen is still sliding in, so the gap is measured against a
  moving frame; the card pill can also sit over the field. Fix: ask after
  the slide, as the properties card already does; hide the pill while
  typing. S.
- **Smallest heading = bold text (2).** It already has the same font; it
  still gets a heading's air (12pt above, 6 below). Fix: `######` drops
  the air and reads as a bold line. S.
- **Make `#` visible (3) — answered: a setting, done.** The hashes show only on the
  caret's line now. Showing them always, dimmed, also ends the shift when
  the caret enters a heading. Always, or a setting? S natively; a setting
  in CodeMirror is just as easy.

## 3. Medium

- **Remove areas, projects, statuses (12).** Nothing removes a value, and
  "Rename everywhere" refuses areas, projects and statuses (the engine
  renames only text and select options; an area is renamed by setting its
  name, which the sheet never does). Trashing an area half-removes it:
  things keep pointing at it and still show its name. Fix, tests first: a
  Rust verb that removes a value — clears it from everything filed under
  it and retires it, one undo — and rename that sets the value's name. In
  the picker, swipe a value for Rename and Remove. M.
- **Vibrations (11).** 21 places today, nearly all errors. One `LivHaptic`
  with four feelings — tap, lift, done, refuse — used for: ticking a task;
  making a note, task or event; holding `+` and other holds; swipe
  actions; filter chips and segments; the panel settling; lifting and
  dropping in the calendar; trash and undo. M. The simulator has no
  vibration, so this needs the phone (on hold until the developer account
  is back).
- **Images (8) — answered: scanning only, text files are notes; done.** Every file and photo shows "moved or
  deleted", and that is a bug: the app reads the file's fingerprint (eight
  hex characters) as its path. The real path is in the box. Paths are also
  stored whole, inside the app's own folder, so reinstalling the app loses
  them; they should be stored relative to the box's folder. The product
  question: the camera is used to scan text. Proposal — the camera is Scan
  text only (the photo shutter goes); a photo or file you add shows its
  name, size and an Open button, like any file, and there is no image
  viewer. M for the fix.

## 4. Large — after the editor decision

- **Fold headings (1).** Built into CodeMirror. Natively it means hiding
  whole ranges with the same mechanism that caused the jumping headings.
  S with CodeMirror, L natively. Folds remembered per note, on the phone.
- **Simplify the note window's dragging (6) — answered: kept from
  anywhere; what was broken in it is fixed.** There are five
  drag mechanisms with five sets of thresholds, and a list of exceptions
  that grew with each bug (the month pager, text selection handles,
  sideways scrollers, sheets behind which the panel could still be
  dragged). Proposal: the panel opens from the **left edge only** — this
  reverses the 8 Aug "from anywhere" — with one recogniser for sideways and
  pull-down, one set of thresholds, and nothing draggable while any card
  or sheet is up. That removes most of the exceptions, and the clashes
  with row swipes and text selection. M.

## 5. Order

1. The small batch: 4, 9, 10, 7, 2 (and 3 once decided).
2. Remove and rename values (12); the file path bug (8).
3. ~~The CodeMirror trial~~ — not now (owner, 2 Oct).
4. Folding (1), the drag model (6), vibrations (11, on the phone).

## 6. Decisions for the owner

1. Try CodeMirror for two days? — **no: keep the current editor and fix
   its problems** (2 Oct).
2. `#` always shown, or a setting? — **a setting** (done).
3. Camera for scanning only; photos and files shown as name, size, Open?
   — **scanning only; a file that holds text is edited as a note** (done).
4. The panel from the left edge only? — **no: from anywhere while the
   keyboard is down, nothing scrolls during the swipe or while it is
   open** (done; a row's own swipe wins on that row).
