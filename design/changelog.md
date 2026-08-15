# Liv iOS — changelog (batch summaries; details in design/ios.md revs)

## 2026-08-15 — the library gets its own bands (and one broken door)

The second half of "a place stands on the floor", after a design pass
that proposed three treatments and judged them through the owner's eye,
the constitution and the builder's.

**The library owns its own chrome now.** It had a 52pt HOLE in its list,
reserved for the desk's floating workspace button — the thing a layer
does, not a place — and the rows slid under that button on unpainted
ground as soon as you scrolled. It has a real top band instead, the same
56pt the desk's chrome owns, closed with a full-width hairline. Its foot
is its own too: a solid band under Settings, deliberately not the desk's
floating capsule. Two places, two silhouettes.

**No lines between the rows.** A hairline between rows is what a FORM
does — it is what `DetailHairline` means one screen to the right — and
this is a list of places to go, held apart by its section labels. The
old ones were also inset 16pt on both sides, which `interface.md` bans
by name ("Dividers are full-width or absent").

**A broken door, mine, from this morning.** With the properties card up
the library door stayed lit in the band above it, and tapping it parked
the library invisibly behind the card while the desk slid out from under
both. It goes dark with the curtain now. The ••• stays live: its verbs
act on the very note the card describes.

**Light mode had no ground.** `canvas` and `surface` were both #FFFFFF,
so in light the library (which stands on the ground) and the properties
card (which floats above it) were the same white — the whole change was
invisible there. The ground is a grouped grey now, and because the light
inks had zero headroom left, five tokens moved a shade darker to keep
the 7:1 floor. The palette self-check is what caught it, on the first
launch after the change.

## 2026-08-15 — a place stands on the floor, a layer lies on the desk

Owner: *"the left 'panel' is really a separate main place of the app,
the other being desk. how can we make it more like so and less visually
like the property panel, which really is a panel belonging to desk."*

They looked identical because they WERE identical: one `SidePanel`
recipe drew both — full screen, `surface` fill, no edges. Two things
that mean different things cannot share one recipe (standing rule 4
cuts the other way here), so the recipe is now two.

**The library is a place.** `LibraryPlace`: the app's own ground
(`canvas`, the floor the desk stands on), corner to corner, no fill of
its own, no radius, no shadow. Two rooms on one floor. It already
arrives by pushing the desk off screen (rev 23) — the motion said this
first; now the surface says it too.

**The properties panel is the desk's layer.** `SidePanel`: a CARD.
`surface` fill, a rounded leading corner (`LivTheme.radiusLg`, the
menus' 22), a shadow, and — the strongest signal — it starts BELOW the
desk's top band, so the library door, the workspace name and the •••
stay lit above it and you can see the desk it is lying on. It arrives as
a curtain, which is the motion half of the same idea.

The workspace button no longer fades under it. It faded from when that
panel covered the screen edge to edge; the card does not reach that
band, so there is nothing to fade for.

## 2026-08-15 — the mini calendar stops rebuilding the world

Owner: *"minicalendar lags when dragged."* Measured before touching
anything, on one 1.2-second drag of the month grid:

| | before | after |
|---|---|---|
| CalendarView body rebuilds | 98 | **0** |
| day cells built | 12,348 | **0** |
| full snapshot passes (`itemsByDay`) | 98 | **0** |

**Two causes, both real.**

*The screen rebuilt itself on every touch-move.* The drag offset was
`@State` on CalendarView, so each frame re-ran the whole body: the day
buckets over the entire box, three month grids of 42 cells each, and the
hour grid below. The pager is its own view now and owns that offset, and
the grid is a value: `CalCell`/`CalMonth` are decided when the month or
the snapshot moves, and `MonthGridView` is `Equatable` over them, so
SwiftUI skips all 126 cells while only an offset is moving. The data
model is the fix; the skip is a consequence of it, not a trick.

*The desk was dragging its panels behind the calendar.* The panel drag
is a recognizer on the WINDOW, and its own installer warns that it
"would otherwise drag panels invisibly behind a full-screen view" — but
it was only ever told about the menu. A sideways drag of the mini
calendar latched a panel behind the calendar window and published 58
times, and the calendar re-rendered on every one. `DeskModel.deskInFront`
now answers "is the desk the surface in front" in one place, for the
recognizer and for the record card alike.

Five new assertions in the calendar self-check pin the shape the skip
depends on — six weeks, 31 days in August, no dots on an empty month,
same month equal, next month not. The instrumentation that produced the
numbers is deleted, as its own comment promised.

## 2026-08-15 — the panels stop being curtains

Owner: *"Now the left and right panels are like curtains. Better would
be if when you open them you 'swipe away' from the previous view, as if
it sits on the left / right off screen."*

The desk now travels with the LIBRARY — one screen to the right — so the
library and the desk read as one strip you scroll rather than a curtain
over a fixed stage. The PROPERTIES panel stays a curtain, by the owner's
second thought the same day ("maybe having properties panel behave like
a curtain though"), and it is the right split: the library is a
different place to be, the properties are about the note already under
them. The panel's own progress drives both the panel and the desk, so
they cannot disagree by a pixel; the drag moved onto DeskModel because
the bottom bar, which is the desk's furniture, is drawn one level up in
RootView.

Whatever is painted ABOVE the panels cannot be covered by a curtain, so
the workspace button, the bar and the pill fade by exactly how far the
curtain has come down — no more blinking out the instant a drag latches.

The details that make it read right: the workspace button stays pinned
(it belongs to the whole strip, and that ruling is a fortnight old); the
two doors fade over the first third of the journey, because their path
crosses that pinned button and two labels on one line is the defect from
the same morning; and the bottom bar rides off screen with the desk
rather than being dropped from the hierarchy halfway through the slide.

## 2026-08-15 — a row with nothing in it is not a row

Owner: *"Have all 'none for this kind' in properties out of view.
Irrelevant properties should be hidden from the user. General rule: when
user can't interact with something it shouldn't be there unless it's
locally dynamic or important for clarity."*

**The status row disappears when there is nothing in it.** A kind with
no status vocabulary and no status set had a full row that read "none
for this kind" — a sentence about the app, not about the note. It is
gone, and its hairline with it. A status that IS set still shows, as a
read-only chip: that is the user's own data, and hiding data is a
different mistake. A kind with a vocabulary is unchanged — the whole row
is still the menu.

**The rule is now written down** (design/ios.md §19), because it decides
more than this one row: three tests, in order — can you act on it here;
does it become actable from something you can do here; does it tell you
something you want to know. Anything failing all three does not appear.

**A sweep of the whole shell against the rule** found one more thing the
user sees and four dead things behind it. Seen: every tab card's preview
opened with `type · note`, spending its best line repeating the kind dot
beside it and the kind footer below it — `type` is skipped now, the way
Today and Everything already skipped it. Dead: `EntityDetailView`, a
73-line pushed wrapper nothing has pushed since the desk took the title;
`displayName`, no callers; the picker's "Nothing to choose from.", which
needs a closed vocabulary with zero options — not representable; and the
`StyleVerb.outline` key plumbing, orphaned when Outline moved into the
`+` menu. Eight candidates were argued down and kept, among them the
library's Filters heading (its band is never empty), the editor's `+`
(it opens a real menu), and the ••• door on a deleted note (Share and
Export are the last way to get that text out).

## 2026-08-15 — templates leave, and messages stop shouting over the workspace

Owner, over a screenshot of a template note: *"the message is on top of
each other. also remove templates completely. it should be added later
when we have decided a good way to implement them."*

**Templates are removed from the shell, whole.** Two files, three menu
rows, the pill, the picker, the `-template.selfcheck` suite (eight
suites now), the furnishing pass that seeded three built-ins, and
everything that existed only to serve them: `LivKind.template`, its
glyph, the entire DASHED stroke pass in the icon language, and
`LivTheme.gray`. `{{cursor}}` was the only reason a focus request
carried a caret, so `consumeFocus` is a plain Bool again. Five
mentions survive on purpose, all about OLD boxes.

Nothing in the Rust core moved. There was never a template verb in the C
ABI — a template was a note wearing one `template` cell, written with
the ordinary verbs — so the core keeps whatever it kept.

**What your box keeps.** The three seeded notes (Daily note, Meeting,
Person) and anything you saved as a template are ordinary notes now,
`{{date}}` and all. The marker cell stays on disk, stays hidden in the
properties panel, and is still skipped by Duplicate note so a copy
cannot spread it. Nothing was rewritten and nothing was trashed.

**The overlap was three bugs, not one.** The pill printed itself across
the workspace name because it was placed against the two door circles
back when nothing sat between them; the workspace button moved to the
top centre on 2026-08-13 and landed on it — and, being drawn later at a
higher z, it also swallowed the pill's taps. The pill dies with
templates, but the box-fault banner and the editor's own notices
(conflict, flattening, save-failed) do exactly the same thing and
survive. So the fix is a rule, not a deletion: `LivRow.topChrome` (56pt)
is the band the doors and the workspace button own, and everything that
speaks starts below it. The number was already there, written out by
hand in one place; it is a token now (standing rule 3).

## 2026-08-15 — the + works on an empty desk

Owner, from the phone, over a screenshot of a workspace with no tabs
reading "No tabs. The + below makes one.": *"no it doesn't."*

**The + was DISABLED whenever the desk had no tabs.** One argument in
BottomBar: `enabled: !desk.tabs.isEmpty`. A new workspace, or one whose
last tab you closed, could not be given a tab from the bar at all.

The guard was right when it was written (2026-08-04): back then an empty
desk's BODY was the New Tab page, so a + that summoned it was a second
door to the room you were standing in. That page was deleted on
2026-08-13 and its `guard !tabs.isEmpty` inside `newTab()` went with it —
but the button's own `enabled:` did not. The empty desk then started
pointing at the button, so the guard became exactly the lie it had been
written to prevent.

Everything downstream was already fine: the create menu builds on an
empty desk and its host is active there. Enabling the button is the
whole fix. The tab switcher's own + and its dashed New Tab card never
carried the guard, which is why the bug looked like "only that one
button is dead".

**The comments that hid it are corrected too.** Five files still said
the empty desk shows the New Tab chooser as its body. Prose that
describes a deleted screen is how a stale guard survives a deletion.

## 2026-08-15 — one gutter for every list

Owner: *"do the list gutter alignment."*

**Every list line's words start at the same left edge**, whatever hangs
in front of them — a dot, a checkbox, a number. The marker is not moved,
it is PADDED: whatever of it is still visible is measured and the
difference to the gutter (23pt, the width of a 15pt checkbox and a
space) is added as kerning on the marker's last character. A line that
wraps carries on under its own words, not under its marker.

**Nesting is one gutter per level**, so a nested item's marker hangs
exactly where its parent's words start. The two source spaces that carry
a level are collapsed to nothing, or every level would be indented
twice — once by the paragraph style and once by its own spaces.

**Why hiding could not do that collapsing.** Measured on the simulator:
TextKit honours a paragraph's `firstLineHeadIndent` only while the
line's first glyph is real. A task line starting with NULL glyphs (the
hidden `- `) was laid out against `headIndent` instead, and its text sat
one whole gutter right of its neighbours' — the "known and left" note
from the batch below, explained. So a task's `- ` is now COLLAPSED
rather than hidden: ink cleared, width kerned away, first glyph real.
`mark` still owns hiding; this is the one case it cannot serve.

Also measured: one negative kern for a whole run collapses only its last
character, because an advance is clamped at zero. Each character pays
for itself.

Numbers past 9 (`10. `) are wider than the gutter and push their own
text ~2pt right; left as is.

## 2026-08-15 — the syntax shows only where you are

Owner: *"have markdown syntax (like ~) hidden when out of focus, only
showing the rendering."*

**Markers get NO GLYPHS off the caret's line.** Not clear ink — that
leaves the width behind as a gap. `LivLayoutManager` is its own
`NSLayoutManagerDelegate` now and answers `shouldGenerateGlyphs` with
`.null` for anything carrying the new `.livHidden` attribute, so the
characters stay in the buffer and take no space at all. Put the caret on
the line and they come back, dimmed and editable: what you can type is
always what you can see.

Hidden: the inline pairs (`**`, `*`, `~~`, backtick), a heading's hash,
a quote's angle, a task's leading `- `, and a link's brackets and id —
`[[4102|Anna]]` reads as **Anna**.

KEPT, on purpose: a bullet's dash, a task's `[ ]` and a rule's dashes,
because the dot, the box and the line are DRAWN into those rects and a
rect with no glyphs has no size; and an ordered list's number, because
the number IS the rendering.

**The reveal generalised.** It already existed for one thing — a divider
swapped its drawn line for its dashes under the caret — and now every
marker does the same. It follows every paragraph the SELECTION touches,
not just its anchor, or dragging a selection handle upward re-flowed the
line you started from mid-gesture.

**Three real defects, caught by reading rather than by luck.** A review
pass over the plan found them and the first bit immediately:
- **The indent is not syntax.** Hiding a task's `- ` from offset 0 took
  the leading spaces with it, so an indented task snapped to the margin
  whenever the caret was elsewhere. It hides from `shape.indent` now.
- **A line that is ONLY a marker keeps it.** Tap Heading on an empty
  line and walk away and the hash would vanish into a 30pt blank band
  you could neither see nor explain — the exact failure the rule's own
  comment records. A marker with no content is the only thing left to
  show.
- **The reveal is asked for when focus ARRIVES too**, not only when it
  leaves. The one path that focuses without moving the selection would
  have left you typing into a line whose markers were hidden.

**And one crash, which named its own cause.** Invalidating glyphs from
inside the styler crashed on the first keystroke: "attempted layout
while textStorage is editing". Attributes alone do not rebuild glyphs,
so the invalidation is real work — it just belongs on the next runloop
hop, the same rule the reveal and the link picker already follow.

**Known and left**: a task's text and a bullet's text no longer share an
exact left edge (the task's `- ` is gone, the bullet's dash is still
holding the dot's rect). Making list markers hang in a common gutter is
a paragraph-indent change, not a colour or a glyph one. *(Done in the
batch above.)*

## 2026-08-15 — the palette comes from the icon, and it is measured

Owner, after a three-way side-by-side: *"i suggest you have a near black
background and use a violet like in one of the arms in the logo. i
thought of the modus themes because of their contrast, which is way
higher than you have made here."*

**The two top buttons are one button now.** They wore the system's
`.bordered` circle, which sizes itself to its LABEL — so the wide
hamburger came out a visibly bigger circle than the narrow ••• — and
fills itself from the tint, so both floated in a lighter grey than the
bar they belong with (owner, 2026-08-15: "should be made of the same
thing"). They are the bottom bar's own recipe now: `LivTheme.surface`, a
hairline, and a fixed 40pt circle around a fixed 22pt glyph. Measured
after: both fills 104px wide, and the fill is byte-identical to the
bar's.

**The colours are the app icon's.** It is three arms of dots, each one
hue running light to dark — VIOLET, PINK, AMBER — and the app now uses
them the same way: violet for chrome and notes, pink for tasks and
people, amber for events, files and captures. There is no blue and no
cyan anywhere, because there is none in the mark. The set it replaces
was Apple's system colours, which is the "generated" look in one line:
every phone owner reads them as the default.

**Built to a contrast FLOOR, which is what the Modus themes were brought
here for.** Ground `#08070A`, text `#FFFFFF` — 20:1. Every colour a
person reads clears **7:1 in both schemes**, most past 10: accent violet
10.0 (was 4.95 — the worst thing on screen), note violet 8.1, task pink
7.7, event amber 11.0, file gold 14.1, secondary text 9.2.

- **`livPaletteSelfCheck` measures it** (`-palette.selfcheck 1`), because
  a floor nobody measures is a wish. It walks every token and every kind
  against the ground it is read on, in dark AND light, and it caught a
  real mistake on its first run: the light accent and the light note
  violet were the same colour to within 6%.
- **Chrome and content stopped saying the same word.** A note used to BE
  the accent. It is now the violet arm one step down — the icon's own
  logic — and the check refuses to let them collapse together again.
- **Tints are colours now, not translucency.** `LivTheme.tint` mixes a
  hue into the ground once and returns an opaque colour. The Today pill,
  the calendar's blocks, the LATE band and the trash bar were
  `.opacity(0.14…0.36)` over whatever happened to be behind them — the
  hue drifted and nothing was ever chosen.
- **The value-dot set** was Apple's semantic five (purple, green, amber,
  red, blue). It is five steps around the icon's arms now.
- **Light mode was re-derived too**, not lightened by accident: white
  ground, the same three arms darkened until each clears 7:1.

## 2026-08-14 — Settings loses its drawer, and the app stops saying "box"

Owner: *"remove settings advanced drawer too"* and, asked in the same
breath: *"btw, what is box? why should users know about it?"*

- **The Advanced drawer is DELETED from Settings**, and everything it
  was the only door to went with it (rule 6): the handoff status card,
  the Pending/Shipped/Delivered ledger, "Ship now", the satellite path
  row, the entity count, "Copy path" and the version line — about 200
  lines, plus `OutboxStateChip` and the date formatter that only it
  used. Settings is Appearance · Suggestions · Reminders · Tabs · Fields.
- **What that costs:** nothing in the app can set a satellite path any
  more, so the phone→desk handoff is OFF until it gets a door someone
  would want to open. The Outbox model still tracks every write, so
  nothing is lost — it just has nowhere to go. Recoverable from git when
  the handoff is designed properly.
- **"box" and "entity" left the interface.** They are OUR words — the
  append-only log the app writes to, and a row in it — and they had
  leaked into eight strings a person actually reads. Now: "This was
  deleted." · "This file was deleted." · "Search everything you have." ·
  "Search" · "Deleted" · "Could not save. It will try again." · "The
  saved version is shown. Your edit is kept."

## 2026-08-14 — no query, anywhere a person can see one

Owner: *"remove all 'Query' functionality. we will replace it with
something better. for instance when creating new workspace, remove the
'advanced' section completely. we should not have advanced features
until the friendly features work as intended. it is supposed to be
primarily designed a user friendly app."*

- **The Advanced row is DELETED** from the new-workspace form and from
  the new-filter form, and with it the only field in the app that ever
  showed or accepted query text. `advancedShown` and the field helper's
  mono variant went too — the mono dress existed for that one field.
- **"Edit name + query" is now "Edit workspace"**, and it opens the same
  form: a name, an area, a subject.
- A workspace is made of pickers now and nothing else. Both forms are
  Name · Area · Subject · Cancel/Create.

**What is left, and why.** `LivQuery` survives as the invisible STORAGE
behind a workspace's lens — the cell the core reads to decide what a
workspace shows and what it stamps. Deleting it today would leave every
workspace filtering nothing, which is not the friendlier app; it is no
app. Nothing constructs it but the pickers, nothing displays it, and it
is ready to be replaced by whatever comes next.

Settings still has an Advanced drawer. That one is machinery — the box's
path on disk, the entity count, the phone-to-desk funnel — not a feature
with a grammar. Say the word if it should go too.

## 2026-08-14 — a caret stays a caret

Owner: *"Creating stuff with the toolbar (like boxes), still selects
them. It is broken since they get deleted as you start typing."*

**The block verbs handed back the whole rewritten line SELECTED.** Tap
"task list" on the line you are writing and `- [ ] ` arrived on screen
selected, so the next letter you typed replaced it — the box you had
just asked for vanished as you began writing. The same for bullet,
numbered, heading, quote and both indents: six verbs, one line of code.

`EditOps.landing(_:whole:newBlock:)` is now the one rule for where the
caret goes after a block rewrite. With an EMPTY caret the rewritten
block is one line and only its PREFIX changed, so the caret moves by
exactly what the marker added or took away and never leaves its own
line. With a real SELECTION the block still comes back selected, which
is what makes a second tap toggle the same lines off.

**A sweep found the same bug in two paths the first fix missed**, and
both are now covered by the one rule:

- **A SELECTION was still widened to the whole line**, marker included,
  so selecting one word and tapping "bulleted list" armed the next
  keystroke to wipe the line. It keeps the words you had now, carried by
  what the marker did in front of them. Widening was never needed for
  the toggle-back it was justified by: `setBlock` derives whole lines
  from `selection.location`, so a narrow selection toggles the same
  lines off — asserted.
- **A caret INSIDE the old marker landed inside the new one.** Put the
  caret at the start of `1. go` and tap "task list": it sat between `[`
  and the space, where the next letter turned the box back into a
  bullet. A point never lands inside a marker now, only at its far side.

**Assertions in `-editor.selfcheck 1`**, and they were checked the
only way that means anything: with the fix disabled they fail, five of
them, reporting exactly the reported bug (`{0, 6}` — the whole `- [ ] `
selected). With it in place they pass. Verified on the simulator too:
tapping the box key then typing "milk" leaves `- [ ] Box testmilk`,
where it used to leave `milk`.

**The separator landed one line too low.** The rule always inserted
BELOW the current line — right when you are standing on a line of text,
wrong in the ordinary way people ask for one: press Return, tap the key,
and the empty line you were standing on stayed above the rule while the
rule appeared a line further down. On a BLANK line the rule now TAKES
that line, terminator and all (replacing the line without its newline
left the newline behind as a second empty line — caught by an assertion
mid-fix). Four assertions cover it, and with the old code they fail
showing exactly the symptom: `a⏎⏎---⏎⏎b` where it should be `a⏎---⏎b`.

**Found in the same sweep, NOT fixed** (different defects, the owner's
call):
- The toolbar's "numbered list" always writes `1.`, even directly under
  a `2.` — it numbers from the line's index inside the rewritten block,
  while the Return key continues the list properly. One grammar, two
  answers.
- An inline verb (bold/italic/strike) over a selection that CROSSES a
  line has no unwrap: every tap adds another pair of markers instead of
  removing the ones it added.

## 2026-08-14 — the timeline gets its two gestures

Owner: *"Hold down (adds box), then drag the box, then release to create
and edit like you do now. Hold down on existing item should make it
possible to trash."*

- **Hold on empty grid places a BOX.** It appears at the quarter hour
  under the finger, follows the finger while it is down, and the event
  is written on RELEASE — with its properties up and the caret in the
  name. Nothing is written until you let go.
- **Hold on an existing block lifts it, and a BIN appears** at the foot
  of the timeline. Drop the block on it and the thing is trashed, soft
  and undoable; drop it anywhere else and it just lands at its new time,
  exactly as before. This is the timeline's delete, which it has never
  had — the question left open on 2026-08-13.
- The press recogniser now begins ANYWHERE on the grid rather than only
  on a block. That made one guard load-bearing, and it is new: the
  recognizer lives on the WINDOW, so it is offered every touch in the
  app, and a touch on the month grid (or on a sheet over the calendar)
  converts into the scrolled content's coordinates as some positive y
  deep inside a 24-hour column — where it would silently start placing a
  box. `scroll.bounds` IS the visible window into that content, so one
  containment test keeps the gesture inside the grid it belongs to. The
  same test closes the collision a review raised on 2026-08-13.

Driven on the simulator, against the box, every leg:
hold-on-empty draws the box · release writes `new event` at the placed
minute and raises the card focused · hold-on-block lifts it and the bin
appears ("17:30 – 18:30 · moving" over "Drop to trash") · dragging
elsewhere writes `set due` 17:30 → 18:30 · dropping on the bin writes
`{"Trash":{"entity":4311}}`. The drop test needed the drop point and the
bin's frame printed to be sure they were in the same coordinate space —
they are, both in window space.

## 2026-08-14 — one menu, three doors

Owner, pointing at Notesnook: *"implement one reusable slide-up menu
component and reuse it for all three, with variations for placement and
slide direction."*

`Menu.swift` is the component: a scrim, a panel, rows of glyph + label
(+ chevron, + destructive). `LivMenu` says where it comes from —
`.bottom` slides up, `.top` slides down — and `.livMenu(_:active:)`
draws it. `active` is the record card's own rule: only the surface in
FRONT draws it, so a menu asked for from inside a card does not appear
behind the card.

It replaced three different mechanisms that all looked different:

- **The toolbar's `+`** was a UIKit `UIMenu` — the one popup that could
  never follow the house motion. It slides up now, titled "Insert". The
  keyboard is resigned through UIKit first, or its accessory row stands
  over the menu sliding up underneath it.
- **The note's `•••`** was a SwiftUI `Menu`. It slides DOWN from the top
  now, from under the button that opened it.
- **New Tab was a whole PAGE.** It is deleted — `NewTabChooser`, its
  close band, its verb dress and `FileImportButton` with it. The three
  verbs are a menu that slides up from the bar that summoned them, and
  the empty desk is empty, with a line saying the + below makes a tab.
  `FileImport.adopt` is what survives of the file door: the picker is
  presented by whoever hosts the menu.

**It really slides**, and that took measuring. The first build used
`.transition(.move(edge:))` on an `if` and an `.animation(value:)` on
the modified content: the panel appeared and vanished with no travel at
all. Recording the simulator and pulling frames every 40ms showed the
card jumping between two positions in one frame. It is an OFFSET now —
the panel is mounted first, measures its own height, and is animated
home from exactly one panel off screen, with `withAnimation` asked for
explicitly at the state change rather than left to a modifier on a view
that does not move. The same frames now show it travelling through
2314 → 2133 → 1984 → 1972.

**The top row, final shape.** The two icon buttons wear the SYSTEM's
bordered circle — `.buttonStyle(.bordered)` with `.buttonBorderShape(
.circle)` and only the tint from the app (owner, 2026-08-14: "should not
be fully transparent / have a button shape … use default appkit look").
Hand-drawn discs, then nothing at all, then the platform's own.

**The (i) PROPERTIES door is DELETED.** The properties panel is dragged
in from the right edge, from anywhere, and dragged back out the same
way — a button beside that gesture was a second door to one room
(standing rule 4). Verified after removal: the drag still opens it on a
live note.

**The top row was uniform first**, and that was the second half of the ask
(I read it as the menu's rows first — wrong). The three floating
controls wore filled grey circles around a bare text button in the
middle: four controls in two dresses. They are PLAIN glyphs now, one
size, one ink, in 44pt targets, the way a navigation bar's are, and the
workspace button sits between them in the same ink at the same height
with a small chevron DOWN (it opens something below it, not to the
right). `on` is the accent glyph where it used to be a filled disc.

**The panels are uniform.** Same corner radius, same paddings, grabber
on the attached edge whichever way it comes from, and the safe area kept
as SPACE INSIDE the card — the top sheet's first row used to sit under
the clock.

`desk.newTabShown` is gone; `desk.menu` replaces it everywhere,
including the bottom bar's retire rule (the bar was drawn after the
desk, so a menu hosted inside DeskHost came up underneath it and lost
its last row — the host moved to the root view).

## 2026-08-13 — nothing between the month and the timeline

Owner: *"remove the 'ALL DAY' row in calendar. there should be no row
between timeline and mini calendar."*

- **The ALL DAY band is DELETED**, with `allDayBand`, `allDayPill` and
  `allDayTask`. The timeline starts where the month grid ends.
- **What it costs, plainly:** a thing with a DATE but no TIME — an
  all-day event, a task due today — is not drawn on this screen any
  more. It is still a coloured dot on its day in the month grid, and it
  is still in Today, in Tasks and in search. Restoring the band is one
  `git revert` away if a missing task turns out to bite.
- **The month grid's long-press now makes a TIMED event, at 09:00.** It
  used to make an all-day one, which only that band drew — so with the
  band gone it would have created something invisible. A door that makes
  a thing you cannot see is a defect. The properties are up a beat later
  and the time is the first row in them.

## 2026-08-13 — one workspace button, at the top of everything

Owner: *"workspace switch button should appear at the top in the center
in all places where that button now exists: global panel (delete current
button), new tab (move). it should also be where you view a note. it
should remain visible as you swipe into the global panel. style should be
same as it looks now in new tab. rearrange the global panel in a way that
fits having workspace at top center."*

- **`WorkspaceButton`** (Workspace.swift) is the one copy, in New Tab's
  own dress: the ring, the name, a chevron. It is drawn by DeskHost at
  the top CENTRE, between the library door and the properties door, with
  the highest z — so it stays put while the library panel slides in
  underneath it. It steps aside for one surface only: the PROPERTIES
  panel, which is about this note, and the workspace is not one of its
  facts.
- **Two copies deleted**: the row at the foot of the library panel and
  the row at the foot of New Tab.
- **The panel's bands say what they DO now.** "Views" and the workspace's
  own name became **"All workspaces"** (Today, Inbox — the two that
  ignore the lens) and **"This workspace"** (Calendar, Tasks,
  Everything). The name was in the label only to say which lens those
  three wear; the button above the panel says the name, and saying it
  twice on one screen is what the calendar's date row was doing.
- The bottom band is Settings alone, and the list starts 52pt down —
  clearance for the button floating over it.

## 2026-08-13 — the timeline places, the properties name

Owner: *"remove 'TODAY · THU 13 AUG' row completely … should be indicated
by the 'Today' button … the 'Today' button should work like a toggle …
naming of items should be done in properties … properties should open
with the cursor in the title field … only interaction in the timeline
will be dragging, creating and deleting items."*

- **The date heading is DELETED.** The month grid already says which day
  is selected, and the Today toggle says whether that day is today —
  three places said the same date.
- **The Today button is the day heading now.** Lit (accent fill, the
  word CARVED out in the canvas colour, the icon chips' stencil) when
  the day on screen is today; the soft tint otherwise. And it TOGGLES:
  the second tap puts you back on the day you left, which is what you
  want after a glance at today. It remembers ONE step, not a history.
- **No more inline naming.** `EventDraft`, `draftBlock` and
  `EventDraftField` are all deleted. Tap an hour and the event EXISTS at
  that minute; its properties rise with the caret already in the name
  (`desk.requestFocus` + the card's existing `autoFocus` channel). Same
  for the month grid's long-press, which makes an all-day one.
- **A record card can throw itself away.** One destructive "Move to
  Trash" row at the foot of the CARD — not the properties panel, which
  keeps only describing (owner, 2026-08-02) because the desk's •••
  sits two inches from it. A card has no such menu, so a task or event
  opened from Today, Tasks or the calendar had no way to be deleted at
  all. Soft and reversible like every trash here.

Verified on the simulator end to end: tapping 20:15 wrote `new event`
at `202608132015`, the card came up focused, typing "Team sync" and
swiping the card away wrote `set name`, and Move to Trash wrote
`{"Trash":{"entity":4299}}` with the block gone from the grid.

**Two gesture collisions were raised in review and did NOT reproduce.**
The drag recogniser lives on the WINDOW, so on paper it can preempt the
month cell's own long-press (0.28s vs 0.45s) and stay armed under the
record card. Driven on the simulator with blocks on screen: long-pressing
day 20 created its all-day event, and a long press inside the card gave
the normal iOS text callout with nothing moved underneath. One
configuration each — the mechanism is real, so if a lift haptic ever
fires where nothing should lift, this is where to look.

**Noticed, not fixed** (settled zone): `liv_trash_at` calls
`content::trash_workspace`, so EVERY trash in the app is logged with the
label "trash workspace" — a note, a task, an event, all of them.

## 2026-08-13 — the calendar loses its quick-add and gains its properties

Owner: *"'New for Tue 11 Aug…' in bottom in calendar is redundant since
users click where they want their items to be in the timeline. Also,
properties should slide up immediately when new calendar items are
created."*

- **The quick-add row at the foot of the calendar is DELETED**, and
  `CalendarQuickAddRow` with it. It made a date-only TASK from a screen
  whose whole point is pointing at an hour. A dated task is still made
  in Tasks and in Today, where the same row lives and means something.
- **The properties card rises the moment an event exists.** Naming the
  draft block writes it and `desk.open(id, as: .record)` raises the card
  over the calendar — which stays where it was, Option C's rule. The
  shape is passed explicitly: the entity is a heartbeat old and may not
  be in the snapshot `shapeOf` reads yet.

Verified on the simulator: tapping 21:15, typing "Dinner", Return —
`#4299 Dinner event 2026-08-13 21:15` in the box, and the card up with
due, status and the filing rows on it.

## 2026-08-13 — making a link opens SEARCH

Owner: *"Creating links will open search to select the thing you want to
link the currently opened thing with, and then insert the whole link for
you."*

- **One search screen, two endings.** `SearchView` takes an `onPick`: a
  result reports itself instead of opening as a tab. The editor presents
  it as the link door, and writes the whole `[[id|Name]]` for you.
- **Both doors lead there.** The toolbar's Link key no longer types
  `[[` into the note — it opens search directly. Typing `[[` opens the
  same screen, with what you had already typed carried in as the query.
  Dismissing without picking suppresses that token, so brackets you
  meant literally do not summon it again until the caret leaves them.
- **The toolbar is GROUPED** (owner, 2026-08-13, pointing at
  Notesnook): six runs of keys with a hairline between them, most-used
  first — undo/redo · bold italic strike · **link** · heading task
  bullet numbered · indent outdent · quote code divider. Fifteen
  identical squares in a row was a wall.
- **Link is IN the row**, not behind the `+`. The `+` now holds only
  what is not universal — Template and Outline today, and whatever
  advanced thing lands later (the owner named maths).
- **The four-row `[[` picker is DELETED** — its own search, its own
  create row, its own list style. A second search screen is a second
  thing to keep true (standing rule 4), and it showed four results where
  search shows all of them grouped by kind.
- **Find-or-create links too.** "Create …" in the link door makes the
  scrap and points the link at it, in one tap.
- **A bug this joined up.** `EditOps.completeLink` built the link token
  itself, spacing only `]]` where the codec spaces every `]`. So a link
  made in the editor to a name ending in a bracket — "Q3 [final]" —
  wrote `[[4155|Q3 [final]]]`, which the scanner closed early, leaking
  one bracket into the note per save. Exactly the defect fixed in the
  codec on 2026-08-11 and missed here, because there were two builders.
  There is one now, with its own checks.

The "LINK TO" header went with the picker; that string exists nowhere in
the app any more.

Verified on the simulator both ways, and against the box: the saved
content is `Text("Wire test ") · Ref(4184) · Text(" and ") · Ref(4295)`
— real references, not literal text.

## 2026-08-13 — a markdown file IS a note

Owner, opening a .md he had just added: *"Totally broken. It should open
any file in editing mode, and .md should work like any note. Completely
get rid of this kind of screen and behavior. 'Open in…' should be
removed. 'md' shouldn't be a type since notes are always 'md' anyways."*

**Markdown is not a foreign format.** It is what a note IS. Adding a .md
now creates a NOTE with the words in the box — editable, rendered,
searchable, versioned like everything else — instead of a file
reference showing a read-only preview of its own source. `NoteBytes`
(Files.swift) is the rule; the import door asks it before it copies
anything, and a markdown pick is never copied to disk at all.

- The name loses its extension: "Linux Installation.md" becomes a note
  called "Linux Installation". Every note is markdown, so saying so in
  the name — or in a `md` chip — is noise. There is no format cell, so
  no chip.
- **Markdown only.** `.txt` is somebody else's text file, and
  `.tex`/`.bib` are source for another program: swallowing a thesis into
  the box the first time it is added is the opposite of what files are
  for. They stay files.
- **UTF-8 only.** Bytes that are not UTF-8 are not text we can honestly
  claim to hold, so they stay a file.
- A markdown file added BEFORE this rule converts itself the first time
  it is opened — words in, file cell off, the tab redraws as the note it
  should have been. The log keeps every version and the file on disk is
  never written.

**This is not in-app editing of foreign bytes** — the thing the product
refuses, and still refuses. Nothing writes back to the file. The words
are copied in once, at the door, and the file goes its own way. A .docx
or a .pdf still cannot be edited in Liv: Word owns the words. That part
of the ask is not buildable, and is not built.

**The preview is DELETED.** Owner: *"preview should not be a
functionality since it is absolutely useless. Remove relevant code."*
Out went `QuickLookView` (Apple's renderer, embedded), the `previewable`
test, the extracted-text fallback, the "No preview for this format"
hint, and — because nothing displayed it any more — `Box.extractedText`
and its `liv_extracted_text_at` call (rule 6). The FFI verb stays: it is
the C ABI, and the core still extracts words for SEARCH, which is what
extraction is actually for.

A file tab is now its NAME and its filing, and nothing else. Reading a
Word file means opening Word. A read-only render inside Liv looked like
an editor and was not one — the same complaint that started this batch.

**"Open in…" left the file screen** and became a ••• menu item, where
every other secondary verb lives. Handing the bytes to the app that owns
the format is the file integration and had to survive; as the only
button on the screen it made a file look like something Liv could not
read.

Verified on the simulator end to end: added the same `Linux
Installation.md` through the picker, and the box holds `#4293 Linux
Installation  note` with no file cell and no format cell, while
`thesis.tex` and `live.txt` are untouched files.

## 2026-08-13 — the icons are DRAWN, and the kind colors reach everywhere

Owner: *"apply the kind colors everywhere, and i don't see the
blueprint's custom icons in the app."* Both were true, and the second
explains the first.

**Why no blueprint icons.** There never were any. The app drew Apple's
SF Symbols — filled, heavier, on their own grid — where the blueprints
draw their own stroked 24×24 set. Nothing had drifted; the drawings had
simply never been built. `Glyph.swift` now holds them, transcribed from
`design/mockups/blueprints/icon-style.html` and `home-views.html`:

- **Kinds** — note (a page with two lines), task (a rounded square with
  a tick), event (a calendar), person (a silhouette), link (two rings),
  capture (a tray), template (the note, dashed).
- **Files** — the page with a folded corner, narrowed by format: a grid
  for a spreadsheet, a screen for slides, a picture for an image, lines
  for text, a label block for a PDF. One file color, orange; the drawing
  carries the format. The old SF-symbol table in `FileFacts.Class` is
  gone.
- **Places** — a sun for Today, a tray for the Inbox, the calendar, the
  tick square for Tasks, an archive box for Everything, a funnel for a
  filter, a gear for Settings, a ring for a workspace, a grid for All.
- Drawn by a small pen that works in the blueprint's own 24-unit space,
  so a glyph is transcribed once and scales anywhere. No SVG parser: the
  only curves in the set are rounded corners between straight runs, and
  `addArc(tangent1End:…)` does those exactly.
- `PropertiesMark` is separate on purpose — three rings in three colors
  is the one mark that is not a single color, and it is never boxed.

**ONE classifier.** `LivKind` is now an enum with `of(row)` as the only
answer to "what is this?", and it carries both the color and the glyph.
It had been two tables that disagreed: the color read `kinds.first`, the
glyph read `kinds.contains(…)` in priority order plus status. A task
filed as `["note","task"]` therefore drew a tick on a BLUE square, and a
capture carrying a status drew a tick on a YELLOW one. Priority is now
file > template > event > task-or-any-status > person > link > note >
capture, once, for everyone.

- Four private copies of the same question folded into it: two
  `isTemplate` helpers (Desk, Detail), the tab card's `kind`, and
  Search's grouping key. `Record`'s two-symbol pill table went too.
- `livCanTick` (Kit.swift) replaces the two private `isTask` copies. It
  is deliberately NOT the kind: it asks whether there is a status to
  close, which an event can also have.
- `-glyph.selfcheck 1` is the eighth suite: one kind per row, color and
  glyph agreeing, every drawing inside its box. It caught a wrong test
  fixture of mine on its first run.

**Where the colors landed.** Search results (rows AND real kind groups,
so files finally get their own section — the `case "file"` sort key had
been dead), the [[ link picker, Today's agenda and all-day band, the
calendar's blocks and its month dots, the Inbox's waiting cards, tab
card footers, the minimised record pill, the template picker, a file's
own header, reference chips and the kind chips in the properties panel.

- **Calendar blocks wear the kind.** They were purple for a task and
  blue for everything else, so an event — the calendar's whole reason to
  exist — came out in the note color.
- **Month dots take the kind color**, reversing "the calendar says WHEN,
  never what kind". Three grey dots said only "busy"; the same three in
  teal, purple and yellow say what the day holds. On the SELECTED day
  they stay one ink — the cell is filled accent, and color on color is
  unreadable.
- **The agenda's leading slot is one mark in a fixed column**: the
  repeat glyph, or the ring, or the kind glyph — never two. The colored
  bar the owner killed on 2026-08-08 is not coming back.
- **Everything stops printing the type twice.** The word "note" beside a
  blue note icon is one fact said twice; Today had always skipped it.

**Held to the rules.** The create menu's verbs and the Inbox's four
routing buttons take the shared GLYPH but no color — color marks what a
thing is, never what a button would make. Property field rows still wear
a dot, not an icon. Search's "Create" row keeps its soft accent plus.

**Two bugs found on the way.** Search printed the core's `#417`
placeholder as a name (every other list turns it into "Untitled"), and
Everything's grey-the-nameless test compared against `"untitled"` while
the helper returns `"Untitled"`, so nameless rows drew at full strength
on the one screen built to show them quietly. `livRowIsUntitled` is now
the one question and both call it.

**Also fixed, on the owner's earlier ruling.** The workspace switcher
printed `area:Work project:Viggo` in mono under each name — the query
language showing through, which no user ever types. It reads as value
chips now; the raw text stays in the folded Advanced field.

**Build script.** `build.sh` puts the system tools first. This machine
has plan9 `grep`/`sed` earlier in PATH, and they have neither `grep -m`
nor `sed -E`, so a device build silently read an empty signing identity
and claimed the certificate was missing.

## 2026-08-12 — the blueprints start landing: kind colors + carved chips

Owner: *"start building the blueprints into the app. While you're at
it, make the icon in the box a bit larger, and the boxes slightly less
rounded."* Slice 1 of the approved visual blueprints, foundation first:

- **`LivKind`** (Theme.swift) — the one kind→color mapping: note blue,
  task purple, event teal, file/link orange, person pink, capture
  yellow, template gray. Five new color tokens (teal, orange, pink,
  yellow, gray) join the theme. Nothing else may hardcode a kind color.
- **`IconChip`** (Kit.swift) — the carved chip as ONE component: solid
  color square, glyph punched through in the canvas color. Built with
  the owner's tweak: 15pt glyph in a 28pt box (larger than the mockups),
  radius 6 (less round), both scaling with size. The reference sheet
  (icon-style.html) was updated to match.
- **Person is the silhouette** — `livRowGlyph` returns `person.fill`;
  no initial-based icon exists anywhere.
- Applied in slice 1: the library panel (each view in its own hue,
  filters and Settings gray, workspace blue) and Everything rows (kind
  chips).
- **The capture sheet is DELETED — 1,129 lines.** Owner: *"clicking on
  'event' in new tab takes you to the old Idea/Task/Event/Photo menu
  which should be completely gone. Also, task and event don't belong in
  new tab."* Both verbs left the create menu, which was the sheet's ONLY
  door, so `CaptureSheet.swift` went with them, plus `CaptureRequest`,
  `CaptureVerb`, `desk.captureRequest`, its presentation, `present()`,
  `createTask()` and the notification handler's dismiss-first line
  (rule 6). Checked first that nothing else used its pieces — the camera
  has its own chip editor.
  - The **one-tab-per-session latch** in `adoptCapture` went too: it
    existed so serial commits from that sheet reused one tab. With one
    entity per door there is nothing to reuse, so it is now
    close-the-chooser-and-open.
  - Tasks and events are still made where they belong: the Tasks and
    Today quick-add rows, and the calendar's tap-an-hour and
    long-press-a-day. The create menu is three verbs now — note,
    template, file.
- **The create menu keeps PLAIN glyphs** — carved kind chips were tried
  there and rejected within the hour (owner: *"color / boxed icons in
  new tab looks bad"*). It is a column of five verbs read by their
  words; five colored boxes made it a toy shelf. An intermediate fix —
  inverting the chip on the accent-filled primary, where a blue chip on
  a blue button vanished — went with it, and `IconChip`'s `carve`
  parameter was deleted since nothing overrode it any more (rule 6).
  The line the two rejections draw: **kind color marks what a THING is,
  in lists. It does not mark what a button would make.**
- **Property rows get a color DOT, not an icon** — reverted the same
  day on the owner's word: *"icons for properties are confusing, but
  color indication of some sort is ok."* A clock for "due" and a tag for
  "subjects" are pictures of the word beside them, which reads as noise.
  An 8pt dot in the field's hue says which family a field belongs to and
  claims nothing more; it is also the owner's own three-dots metaphor.
  Kind chips elsewhere keep their glyphs — there the icon says what a
  THING is, which the word does not.

Verified on the simulator: panel, Everything, create menu and a task's
record card all show the carved language. All seven suites and
`cargo test` green.

**Build queue for the next slices** (from the approved blueprints):
status rings that fill by state · Inbox stat tiles + routing verb chips
· the 44pt rounded search field · floating pill bottom bar + tab
switcher footer · month segment pills · [[ picker rows · workspace-ring
hues in the switcher · settings section chips · tab-card footer dots ·
search result kind rails. The capture sheet stays untouched pending its
redesign (the old verb menu is rejected).


## 2026-08-11 — workspaces and filters are picked, not typed

Owner: *"'Query' is not what I want whatever it is. Should let you choose
area and subject. 'Filter' button has the same problem, and I don't think
it should be there but rather accessed somehow in the global panel."*

This was standing rule 5 being broken in the one place it names: *a user
never types a query language; filters and workspaces are built from
pickers over furniture that already exists.*

- The **Query** box is gone from both forms. In its place: **Area** and
  **Subject** rows, showing the chosen value as a chip or "Any". Only
  those two — project and people were noise (owner's call).
- Each row opens **the picker the properties panel already uses**.
  `InspectorValueSheet` gained an `onPick` closure: given one, it reports
  the choice instead of writing a cell. One picker, not two (rule 4), so
  the options, the search and the create row behave identically.
- `LivQuery` gained `value(of:)` and `setting(_:to:)`. A picker edits
  only its own term and leaves every other token exactly as typed, so a
  hand-made query survives being looked at through the pickers.
- **Advanced** holds the raw query, folded shut. A workspace IS its
  query — that is how it is stored — so the text stays reachable, just
  not as the way in.
- **The stamp hint line is deleted.** "Stamps area:Work" was a grey
  sentence explaining a control, which is a design failure here (owner,
  2026-08-06). I had also put explanatory text in the mockup; that was
  my error and the mockup is corrected too.
- **Filters moved to the library panel**, under the views, with a dot on
  the one that is on. They are no longer in the workspace sheet — a
  filter is not a workspace. Only the FORM stayed behind, opened by the
  panel's "New filter…" through one model flag, so there is no second
  copy of it.
- Fixed on the way: `WorkspaceSwitcher` was presented without
  `DeskModel` injected. It worked only because a sheet inherits the
  environment; reading `desk` in it would have trapped the day that
  changed.

Checked on the simulator: the form shows Name / Area / Subject /
Advanced with no explanatory text; picking Area "Work" writes
`area:Work` (read back under Advanced); the panel shows the Filters band
and "New filter…" opens the same picker form. All seven suites and
`cargo test` green.


## 2026-08-11 — the bug list (Liv Bugs.md)

**Four markdown bugs were one line.** `dim()` — the helper that greys
every marker — also forced the marker to 12pt monospace. A line's height
follows its tallest font, so a marker did not merely look wrong, it
changed its LINE's metrics. A freshly generated `- [ ] ` is entirely
marker, so the line was 14.13pt tall instead of body's 18.84: it shrank
the moment the marker appeared, every line below jumped, the hyphen rode
a higher baseline, and the drawn checkbox — anchored to body metrics —
no longer matched it. Typing one character brought the body font back
and everything moved again. `dim` now keeps the line's font and changes
only the colour. That is the owner's #1, #2, #4 and #5 together.

- **#3, `- ` draws as a point.** A `livBullet` attribute clears the
  dash's ink and the layout manager fills a 5pt dot, the same trick the
  checkbox has always used. The trailing space keeps its width, so text
  still starts exactly where the source says.
- **#6, a new task lands in properties.** All three quick-add rows
  (Tasks, Today, Calendar) now open the record card — the owner's
  standard way, since a new task usually wants a date and a field or two
  next. `open` gained an `as:` hint because the box answers BEFORE the
  snapshot lands: `shapeOf` on a brand-new id read nil, guessed
  "document", and that is why the create menu's "New task" opened a
  markdown editor instead of the task's own card.
- **#7, the due sheet stops throwing you out.** Today/Tomorrow no longer
  dismiss. They also MOVE the sheet's own `date` — which is the half
  that mattered: every later write reads it, so removing the dismissal
  alone would have made the next time-change silently rewrite the day
  back to whatever the sheet opened on. The dismissal was hiding that.
- **#8, "erases everything" was a trap, not a write.** The sheet can
  only touch the due cell — never names or notes. What erased it was the
  red **Clear** row appearing directly under the time control the
  instant a date existed, exactly where a finger was already travelling;
  it unsets the whole value with no confirmation and no undo. Clear is
  now always rendered, disabled until there is something to clear, so
  the layout is fixed from the moment the sheet opens and nothing
  arrives under your thumb.

Verified on the simulator: quick-add opens the card with the typed name;
the due sheet stays open after Tomorrow and its "Choose a date" row then
reads Wed 12 Aug (proving `date` moved); Clear is present and greyed
before any date, red after; bullets, checkbox and `#` all render right.
NOT verified: driving the time WHEEL — synthetic input would not land a
new hour, so the day-preservation is shown by the sheet's own state
rather than by a completed time change.

**A third false alarm in `carriesFormatting`, found by looking at the
screen.** After the codec change every legacy note showed "this editor
can't keep your formatting" — a note reading `- [x] Slides` is not
losing anything, it is being promoted to a real Task block. The
principle (ask each piece whether it survives its own round trip) was
right; the ad-hoc rules bolted beside it were not. Both are gone: a
whole-document comparison cannot tell a promotion from a loss, and the
standalone newline rule flagged the one-Text-span-with-newlines shape
older writers produce (the CLI still writes it) — also a promotion, and
the genuine case, a newline inside a MARKED run, is caught by the round
trip without a rule of its own. Known and accepted: an escaped `\#`
from a vault import is indistinguishable from a legacy marker at this
layer and is promoted rather than flagged.


## 2026-08-11 — the codec writes the core's blocks (the deviation retires)

Owner: *"do this code structure change."* The phone stored `## Title`
as the characters `## Title` — every line a Body paragraph, every
marker literal text, the recorded deviation from D19 that the core's
own `services/src/tasks.rs` grew a second read-form to tolerate. The
codec now writes what the core stores. **Rendering is untouched** —
headings sized right and boxes drew as boxes before and after; only
the wire changed.

- `BlockJSON` grew from two cases (body, other) to the core's full
  vocabulary, with serde-exact Codable pinned against the JSON strings
  in `core/src/value.rs`'s own tests. `.other` remains for Code,
  Callout and future blocks — still flattened, still banner-gated.
- `textToSpans` derives each line's block through `MarkScan.shape` and
  each delimiter pair through `MarkScan.inline` — the SAME scanner the
  styler renders with, so screen and box can never disagree (rule 4;
  the codec's old regex ref-parser is deleted, rule 6).
- `spansToText` regenerates markers from blocks and delimiters from
  marks. Ordered numbers are presentation: renumbered per consecutive
  run per depth. Depth is one tab or two spaces per level
  (`EditOps.indentUnit`).
- `carriesFormatting` **rewritten to render and rescan**, not to reason
  about cases. The codec is a round trip; the only honest question is
  whether a value survives it, and the only authority is the codec
  itself. Two per-case rules I wrote first both leaked: `"a*"` in bold
  renders `**a***`, which rescans as bold-"a" plus a stray star; and a
  BODY paragraph whose text begins `# ` renders as `# …` and rescans as
  a heading — silently changing shape on the next save, with no banner.
  That second class is reachable: `parse_markdown("\\# escaped hash")`
  yields exactly `[Break(Body), Text("# escaped hash")]`, verified with
  a throwaway test against the importer, then removed. Both now flag by
  construction, and so will the next such edge. `.other` is still
  checked separately — Code and Callout have no buffer form at all.
  A leading Body break is normalised away first: it opens the first
  paragraph, which the buffer opens anyway.
- ~70 codec assertions now in `-spans.selfcheck 1` (was 22), including
  the pinned canonicalisations, the wire strings, the marker-as-body
  class and the bracket-in-a-name class; the 73 scanner assertions
  untouched and green.

**Open, flagged rather than silently changed:** a link to a TRASHED
entity is still demoted to literal text on save. Ruling 5 says a token
whose target is "not in this box" must stay text, but the shell tests
its SNAPSHOT (which filters trashed) while the core refuses only when
`store.get` finds nothing (which does not). So the shell demotes links
the core would have kept, and restoring the target does not restore the
link. The banner now fires for it; changing the demotion rule is the
owner's call, not a codec cleanup.

**Three defects the adversarial review found, all confirmed by test
before fixing:**

1. **A link whose target's name ends in "]" leaked a bracket into the
   note on every save, forever.** `token`'s sanitiser replaced "]]" with
   "] ]", which is non-overlapping — so "Q3 [final]" rendered
   `[[4279|Q3 [final]]]`, whose FIRST "]]" is the name's bracket plus
   the token's. The scanner closed there and the leftover "]" fell into
   the note as text. Measured: five cycles gave `]]]]] today`. Now every
   "]" is spaced, so none can sit beside another or beside the closer.
   Proven end to end on a real box — three edit cycles through such a
   link now store `[Text("See "), Ref(4279), Text(" today...")]`, clean.
   PRE-EXISTING, not introduced here.
2. **The banner rendered nameless and assumed every id was known**, so
   it tested a buffer the user never gets — and those are precisely the
   two ways this round trip loses data. It now takes the SAME `name` and
   `isKnown` closures the save uses.
3. **The Tasks view's checkbox rewrites the whole note with nobody
   looking**, so a code fence or callout elsewhere in it was destroyed
   by ticking an unrelated line. It now refuses and warns when the note
   carries something the buffer cannot hold — the editor says it
   properly when you open it.

Also: Share/Export rendered links as bare `[[4279]]`, naming nothing an
outside reader could resolve — it passes the display names now. And
four more canonicalisations are pinned (tab → two spaces, `* ` → `- `,
heading/quote indent dropped, depth clamps at 15) so the set cannot
widen unnoticed.

Verified live, not by reasoning: typed on the simulator, then read the
raw box log — `{"Break":{"Heading":1}}` and `{"text":"important",
"marks":1}` stored, no marker characters. Reload regenerated the
buffer pixel-identically. One checkbox toggle from the Tasks view
converted a whole seeded legacy note — 0 structural breaks before, 7
after, the tapped line `Task{done:true}`, every line 1:1, and a
mid-line `## ` correctly left as body text. Legacy notes convert
exactly this way: wholesale, on their first edit, never before.
`cargo test` 317 green — zero Rust changed.


## 2026-08-10 — the type scale becomes a type, and the panels get room

The owner: *"UI in the property panel is cramped towards the top when
almost half of the panel is empty. Text is too small. Whatever you change
to, mirror it logically in the global panel and throughout the
interface."*

It could not be done as a nudge. Type size was **prose**: 19 distinct
values across 253 call sites, every one a literal, including 7.5, 9.5,
10.5, 11.5, 12.5 and 13.5pt that nobody chose. **86 of the 253 were under
12pt** — a third of the app's text, against the owner's own standing
"no micro-text" rule. This is precisely the drift CLAUDE.md rule 3
predicts: *"colours are tokenised and have never drifted; type sizes are
prose and have drifted 38 times."*

- **`LivType`** now sits in Theme.swift beside the colours: micro 10.5,
  caption 12, label 13, body 15, strong 16, title 18, display 22, hero
  26. Each step names the old band it replaces. All 253 sites converted;
  **zero size literals remain in the shell.** "A notch bigger" is now
  five numbers, not 253.
- **`LivRow`** — 54pt ordinary, 58pt for a two-line row. Rows were 46
  when their text was 11–13; bigger text in the same box is just more
  cramped, which is exactly what the owner was looking at.
- Both panels got the same rhythm: air above the first section label,
  and space between the title block and the first band. The library
  panel mirrors the properties panel, as asked.
- **Document titles breathe.** `titleTop` 54 → 78 (the title sat ~8pt
  under the floating circles) and `titleGap` 6 → 20 (the note began
  almost against its own name). The literal `32` that appeared in both
  the initial inset and the height floor became one `titleFloor`, and
  the title font is `LivType.hero` rather than a second 26.

Checked on the simulator across the note, both panels, the calendar,
the tab switcher, Today and Tasks — nothing clipped or overflowed. The
calendar gutter fix from this morning still holds under the larger type,
measured: hour label ink ends at 36.3pt, the rule starts at 46.0pt,
9.7pt clear.

**Still empty, and not a layout problem:** roughly 40% of the library
panel remains blank because the things that belong there are built in
the core with no door — a Pinned band (`liv_pin_at` ships, the snapshot
carries an ordered `pins` array, nothing calls it) and a Filters band
(saved views exist, reachable only inside the workspace switcher). Both
are Batch A of design/blueprint-gap-2026-08-10.md.


## 2026-08-10 — the panels lose their collapse buttons entirely

The owner, in two steps: *"There's a whole row in both the left panel and
the property panel that only contains the collapse icon"*, then, once the
chevron had been moved onto the first row, *"the collapse '>' is almost
inside the title in properties. You probably should get rid of the
collapse buttons."* Both panels are one component (`SidePanel`), so one
change did it twice.

The 40pt band is gone and so is the button. **A panel is dragged back** —
the gesture the owner asked for on 2026-08-08, and the same one that
opens it. Worth knowing, because it was checked before removing the
button: panels are full screen width and drawn over everything, so ☰ and
(i) are covered while one is open, and there is no scrim to tap. The drag
is now the only way out for a finger; `.accessibilityAction(.escape)`
remains for anyone not using one. `title` went with the button — it
existed only to name it.

Also fixed, from the seam map's hazard list, all in the record card's new
embedded editor:
- **`.id(id)` on RecordCard.** Following a `[[link]]` from one record to
  another only reassigns `desk.recordCard`, so SwiftUI reused the view
  and the editor's model stayed attached to the record you LEFT — B's
  name and facts on screen, your typing going into A. This was the worst
  of them and it silently wrote to the wrong entity.
- **A dead `[[link]]` no longer opens a dead tab.** The desk's own call
  site has guarded this since ruling 5; the card's new one did not.
- **The card injects `WorkspaceModel`.** The `[[` picker's Create row
  reads it, and would have trapped the first time anyone used it.
- **`record.notes` is its own accessibility identifier.** A card sits
  over a live note tab, so two text views answered to `note.editor` and
  every scripted check of the editor was a coin flip.
- **Notes line up at 16pt** with the name field and every inspector row;
  they were landing at 20.
- **Outline and Template are dropped from the `+` menu when embedded** —
  Outline scrolls a view whose scrolling is off, and Template would land
  a document's boilerplate in a task. A menu item that does nothing is a
  lie.
- A card rising over a note tab now dismisses that note's live `[[`
  picker, which used to be left floating.
- Deleted: `keyboardDismissMode`/`alwaysBounceVertical` set in init and
  undone a moment later, and a whole-text scan computing a title prompt
  that embedded mode never draws.


## 2026-08-10 — the record card uses the REAL editor (stage one)

The owner: *"'Add notes...' in properties. There is already a note
editor. Can this and other app mechanisms be reused? Links for
example?"* Yes, and the old reasoning was wrong twice over.

A record's notes are content spans on the record entity — the SAME data
a note's body is. So the plain `TextEditor` was never a different KIND
of thing, only a worse way of editing the same thing. And what it
withheld is exactly what a task wants: a **checklist**, and a
**[[link]]** to the note or project it belongs to.

- `MarkdownTextView(showsTitle:)` — a note carries its title inside its
  own scroll view (the Obsidian layout); a record is named by the card
  above it, so a second name field would be a lie about what you were
  editing. The flag is `let`, because a view that could gain or lose a
  title mid-life would invite the inset mutation during layout that once
  blanked the whole document.
- `MarkdownEditor.embedded` — the text view stops scrolling itself and
  reports its height through `sizeThatFits`, so it lives inside the
  card's own ScrollView. Two nested scroll views is the fight this
  codebase already lost twice (HourGridDrag, PanelDrag); the answer is
  to have only one.
- `RecordBody` drops its own `NoteEditorModel` entirely and embeds
  `NoteEditor`. That deletes the second editor AND its whole plumbing —
  attach, flush, textChanged, snapshotArrived, the conflict line
  (standing rule 6).
- Checkboxes, markdown styling, `[[ ]]` links, the outline, template
  insertion and the keyboard toolbar all arrive with it. The toolbar is
  the text view's `inputAccessoryView`, so it came free.
- A tapped link opens as a tab, which closes the card on its way out —
  `openDocument` already clears `recordCard`.

Verified on the simulator, not by reasoning: the toolbar renders inside
the card; typing lands; the Task list verb draws a real checkbox;
**tapping that checkbox toggles it** (the nested-scroll risk, and the
one most likely to have broken); the box then reads
`#4255 Do things · task · todo · content "- [x] Slides"`. The
full-screen note editor still shows its title and derived prompt — no
regression.

design/ios.md §record card amended rather than silently contradicted.
Stage two (growing the card to full height while writing) is not built.


## 2026-08-10 — one verb face, because the copy drifted

The owner: *"'Add a file' in light mode New tab lacks the button shape
the others have."* Correct, and the cause is instructive.

`FileImportButton` was hand-dressed to match the create menu's verbs
(2026-08-09, centring it) and copied the fill but not the BORDER. In
dark mode nobody could tell: surface `#1E1E20` reads against canvas
`#161618`, so the fill alone draws the shape. **In light mode both are
`#FFFFFF`** — the border is the entire shape — so the button had none.

Fixed by making there be one recipe rather than adding the missing line
to a copy: `LivVerbFace` in Kit.swift, worn by both the chooser's
`verb()` and `FileImportButton`. Standing rule 4 covers display helpers,
not just parsers, and this is the second copy-drift of the day (the tab
card was the first). Checked in both appearances.

**Not a bug, recorded so it is not re-investigated:** while chasing this
I claimed the appearance setting was lost on cold launch. It is not. I
had written the preference with `simctl spawn defaults write`, which
does not reach a sandboxed app's own domain, and then read my own write
back. Instrumented: the app reads its stored value, finds the window at
`onAppear`, and applies it; Dark survives a cold relaunch. The
speculative scenePhase re-apply was reverted.

## 2026-08-10 — the bottom bar stays up on New Tab, and "Open…" goes

The owner: *"Bottom bar sometimes shown and sometimes not shown in New
tab. What is right?"* Measured before answering — the same screen was
furnished two ways. Summoned by `+` the bar was hidden; as the empty
desk's own body it was shown. Nothing chose that: the bar's condition
carried `!desk.newTabShown`, written when the concern was panels
sliding over it.

**Always shown is right.** The screen is identical either way, so its
furniture must not depend on how you arrived; the empty-desk case
already proved the two coexist without colliding; and without the bar
the summoned chooser's only exit was one small chevron, while the bar
carries the way back to your tabs and to search.

- **"Open…" deleted.** It ran `desk.searchShown = true` — the bar's
  search button, said twice. With the bar always up it is two doors to
  one room (standing rule 4), and rule 6 says the change that makes
  code unnecessary deletes it.
- **‹ › now dismiss the chooser.** They move the desk UNDERNEATH it, so
  left alone they would change a tab you cannot see. Asking for a tab
  means you want to look at it. Checked live: back arrow closes the
  chooser and lands on the tab.
- The minimised-record pill follows the bar, since it is positioned
  against it.

## 2026-08-10 — Inactive tabs (owner, pointing at Chrome for iOS)

A tab you have not touched in three weeks is not work in progress, it
is clutter. It now steps out of the grid onto a list of its own — still
open, still one tap away. This closes the hole `ios-m1-eval.md:49`
recorded and only half-fixed: serial-capture reuse stopped the app
MINTING junk tabs, and nothing until now cleared the ones already there.

- **The clock.** A `DeskTab` carries `lastUsed`, a packed civil stamp,
  set by one funnel (`touch`). Every activation path stamps, including
  ‹ ›, which assign `activeTabId` directly and would otherwise have let
  a tab age while you read it, and including a capture rewriting a tab
  it already owns.
- **One array, always.** Inactive is a PREDICATE over `tabs`, never a
  second collection — so closing, de-duplicating, the record prune, ‹ ›
  and the saved plane all still see every tab, and only the grid
  narrows. Two invariants hold it up and are asserted: the active tab is
  never inactive, and therefore the live set is never empty while any
  tab is open (which keeps "the empty desk IS the chooser" meaning "no
  tabs at all").
- **Persistence extends, never replaces.** A `used` map, keyed by entity
  id (a tab's UUID is minted fresh each launch), joins `ids` and
  `active` in the SAME UserDefaults record. The key is not bumped: a v2
  key would silently discard every open plane. A plane saved before
  today has no stamps and reads as "used now", so the first launch after
  the upgrade sweeps nothing. Verified on disk — the old `All` plane
  still has no `used` key.
- **What Chrome does that Liv does not.** Its grey subtitle under the
  row, its explanatory paragraph, and its blue inline "settings" link
  are all refused (owner, 2026-08-06: a sentence explaining a control is
  a design failure). The threshold rides as a chip on the row; each card
  carries its own age in the kind footer it already had. There is no
  navigation push either — this shell has no navigation stack, so the
  list wears the same 40pt band every full-screen surface wears.
- **Close all asks nothing and offers no undo**, deliberately: a tab is
  device state, so closing one writes NOTHING to the box. Every note and
  file stays in search, in Everything, in its workspace. The undo chip
  means "a transaction was written" and none was.
- **Per workspace for free** — planes were already stored per workspace,
  and the stamps ride in the same record.
- Settings gains one picker: 7 / 14 / 21 days / Never. Never is
  lossless both ways, since nothing was ever closed.
- `close()` now hands the desk the most recently used LIVE tab rather
  than the plain index neighbour, which could drop you on a three-week
  old note you never asked for.
- The tab count in the footer and on the bottom bar counts what the grid
  SHOWS; the inactive count lives on its own row.
- **Seams:** `TabSwitcher` moved out of Desk.swift (1,159 lines) into a
  new `Tabs.swift`, and `LivTabs` — the rule itself, in a type — lives
  there too. Desk.swift is 922. Chrome.swift is still 1,485 and remains
  the file most in need of a seam.
- `livTabsSelfCheck()` (`-tabs.selfcheck 1`), 22 assertions: the age
  arithmetic including month boundaries, a clock that moved BACKWARDS
  reading as 0 rather than sweeping everything, the >= boundary at the
  threshold, "Never", both invariants, and that the tab you are looking
  at survives Close all even at 90 days. It caught one wrong expectation
  of mine on the first run.
- `-desk.boot inactive` opens tabs and backdates them, because nobody
  can wait three weeks to look at a screen.

Checked live: revive (7 → 6, the card back in the grid), Close all (row
gone, two tabs left), and the persisted plane read off disk.

## 2026-08-10 (small) — seven owner notes

- **"Today" is dressed as a button now.** As plain accent text beside
  the month it read as a label announcing the selected day rather than
  a verb that takes you there. It is a 26pt tinted pill in a 40pt tap
  target, and its spoken name is "Go to today", not "Today".
- **The month grid pages by swipe.** Left for the next month, right for
  the previous — the same verb the ‹ › chevrons run, so there is one
  step() and one place the selection rule lives. The grid slides the
  way the finger went. Deliberately blunt (44pt of travel, clearly more
  sideways than vertical) so a finger sliding off a day cell never
  turns the page; day cells answer to taps and are untouched. Checked:
  swipe left → September, twice right → July, Today → back to August,
  and a plain tap on the 15th still selects it.

- **The calendar's blocks were see-through, so the hour rule was drawn
  across every event.** An event filled at 20% over the canvas; the
  grid behind it showed through. The fill is opaque now — the same tint
  laid ON the canvas rather than over whatever is behind — so a block
  covers the grid instead of tinting it. One recipe (`blockFill`) for a
  real event and a draft, so they cannot disagree. The colour is
  unchanged: `(20,44,70)` before and after.
- **The first hour of the day was sliced in half.** Each time sits 6pt
  above its own rule; at the top of the grid that 6pt fell outside the
  scroll, so "00:00" was cut through the middle under the TODAY
  heading. The rise is a named constant now, used both to lift the
  label and to reserve the room.

- **The calendar's hour rules were drawn through the clock.** Each hour
  line started at x=0 and ran under its own "09:00", crossing the text
  out. The time column now has ONE number — `CalClock.gutter` — and the
  rule, the now-line and the blocks all measure from it. There were four
  numbers before (0 for the rule, 16 for the label, 44 for the now-line,
  60 for the blocks, written twice), which is how they drifted apart.
  Verified by pixel: the rule's left edge is at 46.0pt and the last
  digit ends at 38pt, an 8pt clear gap.
- "Add a file" wears the create menu's own dress now — it sat
  left-aligned in a column of centred verbs.
- Todoist-style inline capture parsing REFUSED and recorded (owner:
  "too non-obvious, too much freedom"). Dates and filing stay as chips
  and Inbox suggestions, never live parsing of the typed line.


## 2026-08-09 (night) — four of the five data-model trims

Approved as T1-T4 + T6; T3 (table-driving the 18 seed functions) opens
the next batch with a pre-trim box fixture — it touches every
box-creation path and deserves its own verification matrix rather than
the tail of a long day.

- **T1 — the name index.** The store now keeps "who claims this name"
  beside the backlink index, maintained in the same two places cells
  change. `property_id` — the lookup behind ~197 call sites, and the
  cause of both quadratic scars — reads it instead of scanning. Failing
  test first: the same thousand lookups over a 4x bigger box; the scan
  failed at 3.2x, the index passes at ~1x, and re-inserting the scan
  makes the guard fail. Measured: 21 ms of lookups became 14 µs.
- **T2 — three dead bootstrap properties unseeded** (default-view,
  renderer, config). Their ids stay reserved forever; old boxes keep
  the rows harmlessly. The review had claimed FOUR were dead — `query`
  is load-bearing (workspaces store their lens in it) and stays. Trust
  but verify, even the auditors.
- **T4 — one "user entities" iterator** in the store: not trashed, not
  plumbing. The filter that, forgotten once, leaked starter types into
  Everything and damaged 9 of 20 early boxes can now not be forgotten.
  Four files' hand-rolled copies converted mechanically; the remaining
  sites keep their exact semantics and get audited with T3.
- **T6 — the one 5,785-line FFI file is three files**: the verbs
  (2,226), the snapshot types + builder (842), the tests (2,734). No
  wire change, no header change, 71 FFI tests green.

317 Rust tests, zero warnings, all six shell self-checks pass.


## 2026-08-09 (later) — the drag takes the touch back, and contents leave the facts

- **Dragging over a button no longer presses it** (owner). Getting
  there took four attempts, and the honest record matters: the panel
  drag became a real UIKit recognizer (PanelDrag.swift) that latches
  only on horizontal, deliberate movement — but UIKit's three levers
  for taking the touch away (touch cancellation, recognizer exclusion,
  delayed delivery) ALL failed to reach SwiftUI's buttons, each proven
  live by the row still firing. What works is SwiftUI's own mechanism:
  the desk disables its whole tree the instant a drag latches, which
  cancels any in-flight press. A tap never latches, so taps are never
  disabled. Verified: a drag starting ON a row moves the panel and
  fires nothing; a tap on the same row opens its view; a drag across
  the properties panel's due row opens no sheet. Also found while
  verifying: the let-go arithmetic was inverted for CLOSING drags (a
  57% pull away snapped back open); the flick threshold was low enough
  that a moderate release read as a flick; and a drag could not START
  over a file preview, fixed with a 24pt edge exemption — the screen's
  edges belong to the panels, whatever sits under them. `-drag.off 1`
  bisects the recognizer like the calendar's.
- **File contents never share a surface with properties** (owner). The
  file tab is the name and the BYTES, full bleed — the way a note tab
  is the note. The facts live behind the (i) door exactly as they do
  for a note.


## 2026-08-09 — files, and panels that follow your finger

**Panels are dragged, not flicked** (owner: "drag into properties and
global view instead of only swiping and letting go"). The library and
the properties panel now track the hand: push halfway and they sit
halfway; let go and they finish the journey or go back, decided by
where you stopped or how fast you threw. The old anti-flicker rule
survives as a LATCH — nothing moves until the gesture proves it is
horizontal and deliberate, and once it has, it owns the rest of that
drag. Verified: a 40pt drag snaps back, a vertical scroll starts
nothing, a full drag opens.

**Files: a file of any format is now an ordinary item.** The bytes stay
as a file; the box records a reference (path + a hash of the content)
and the same six fields everything else has, so a contract is filed by
area and project exactly like a note, and answers to the same
workspaces and searches. That is the whole answer to "a folder can only
hold a thing in one place".

- **A shipped bug is fixed.** A file had no kinds, so it fell through to
  "document" and opened as an EMPTY MARKDOWN EDITOR over a real file.
  `TabShape` checks for a file FIRST, because having a file crosscuts
  the six kinds — a scanned contract is a file and can also be a task.
  There is no seventh kind.
- **The file view**: the name (yours to change, and changing it never
  touches the file on disk), a class glyph and format chip, "Open in…",
  Apple's own renderer showing the bytes, then the same facts rows as
  every other item. A missing file says so plainly and keeps the entity
  — its filing is still real.
- **Three core verbs that had ZERO callers are wired**: add-by-reference,
  re-hash, and extracted text. Opening a file re-hashes it, so Liv
  learns that Word saved without a watcher or a timer.
- **A phone import COPIES.** Found live: the file picker hands back a
  path inside another app's container, readable only during that one
  callback, so recording it produced an entity whose file was "moved or
  deleted" the moment you looked again. Liv's copy becomes the truth,
  the way photos already work. On the desktop, where paths are stable,
  the same core verb records the path in place.
- **One glyph table** (owner: no two code bits solving the same
  problem). Two had drifted, so the same file showed a photo icon in one
  list and a document icon in another; a spreadsheet and a contract now
  look different, from the format alone.
- Liv never writes those bytes. Word owns the words.

Fixed while testing: the Option C tab prune was closing FILE tabs too —
a file is a document you work on and keeps its tab.


## 2026-08-08 (later) — the scalability answer, and three measured fixes

A three-lens review with two adversarial passes compared this app to the
Tauri app it replaces. Verdict: **not heading there** — one data store
against three, one file touching the core against seventy, one way to
open a thing against four, 316 model tests against one test file. But it
found one real, measured failure and two habits pointed the wrong way.

- **The snapshot was quadratic.** `vault::expected_files` resolved the
  `daily-note` property by scanning the whole store — once per entity —
  and it runs on every snapshot. Measured on the release build BEFORE:
  12 ms at 500 entities, 19 at 1,000, 62 at 2,000, 195 at 4,000. AFTER
  hoisting the lookup out of the loop: 2.3 / 3.8 / 6.2 / 11.0 ms —
  eighteen times faster at 4,000 and linear. Extrapolated at 10,000 that
  is ~28 ms instead of ~1.2 s, on a machine much faster than a phone.
  The field it computes, `vault_path`, is not read by the phone at all;
  it stays on the wire for the desktop, per the additive-ABI rule.
- **A cost test now guards it** (`services/tests/scale.rs`) — the first
  test in the project that measures price rather than correctness. It
  asserts the SHAPE, not a millisecond budget, so a slow machine cannot
  fail a build. Verified by putting the scan back: it fails with
  "doubling the box multiplied the work by 2.87x".
- **Refreshes coalesce.** One typed task fires four writes, each of
  which scheduled its own full re-read; only the last answer is ever
  seen. Now one read is in the air at a time and a request made during
  one is re-run when it lands — collapsing the burst without ever losing
  the final state.
- **Search stopped hiding results.** The core ranks everything, sends
  the first 200, and reports the true total; the shell decoded the page
  and threw the total away, so a query matching 1,800 things looked like
  it matched 200. It now says "Showing 200 of 1,800 — narrow the
  search".

Nine standing rules went into CLAUDE.md, each one derived from a
measured difference between the two codebases.

## 2026-08-08 — Option C: records are edited where you stand

**A tab is a document. Nothing else.** Notes, templates and untyped
captures land as tabs, exactly as before. A task or event now rises as a
CARD over whatever you are looking at, and closes nothing — tapping a
task inside Tasks used to throw you out of Tasks and leave an orphan tab
behind. Verified: Tasks stays fully up behind the card.

**One door decides.** `desk.open` branches on kind and every one of the
~23 call sites gets it for free. The kind is read from the live snapshot
at the moment of opening, never cached, so a freshly created record
cannot be mistaken for a document for a frame.

**A swiped-away card becomes a pill** above the bottom bar — one at a
time, like a mail draft — and tapping it restores the card. This answers
the owner's one reservation about cards: you can go read something else
and come back. Verified: card → swipe → pill → tap → card, with Tasks
intact throughout. Every record edit saves as you make it, so the pill
carries no unsaved work.

**The card presents from the frontmost surface, never the desk.** UIKit
gives one presentation per presenter, so the desk raising a card while a
full-screen view was up tore that view down — the exact context exit
this change exists to remove (found live). Each cover now hosts its own;
the desk hosts only when nothing covers it.

**Old tabs holding tasks close quietly on first launch** after the
change. Verified: 36 tabs → 17.

**Deleted, per "no dead code":** the record branch of the desk tab body,
the kind guards on the (i) door and the ••• menu, the kind test in the
left-swipe gesture, and "Photo" from the create menu (the camera is
reachable from the capture sheet, and scans are later work).

**The New Tab screen is a create menu now**, in honest order: documents
first (note, template), then records (task, event), then Open…. The word
"scrap" — which the owner never chose — is "capture" in the two places
it reached the interface.

## 2026-08-08 (earlier) — three fixes

- **Appearance now changes the sheet you are standing in.** It was set
  with SwiftUI's scheme preference, which only reaches the view tree it
  is attached to; a sheet is a separate presentation, so flipping the
  setting from inside Settings changed everything except Settings. It is
  set on the window now, which reaches every presentation there is.
- **The one vertical rule in the app is gone** — the coloured bar on
  Today's timed rows. It encoded "task or event" a third time (the
  status ring and repeat glyph already say it) and, being the only
  vertical line anywhere, read as random.
- Pushed to the owner's iPhone.


## 2026-08-08 — the owner's fourth note batch

- **Light mode** (owner: "add light mode button"). Every colour token is
  now a dark/light pair resolved by the system's appearance machinery —
  including the editor's, which draws through UIKit and picks the pair
  up at render time. Settings gained an Appearance control: Dark /
  Light / System. Dark remains the default. Verified in light: editor
  (divider drawn), calendar, Today, Settings.
- **The calendar grid is hourly; hands land on the quarter hour**
  (owner). The half-hour line — dimmer than every other line in the app
  for a reason nobody could state — is gone. Tapping empty space drafts
  the event at the nearest 15 minutes (verified: a mid-band tap wrote
  02:15); dragging already stepped by 15.
- **Separators follow one law now: a line sits BETWEEN two neighbours.**
  Rows used to draw a line under themselves even as the last row of a
  section, leaving lines floating over gaps (owner: "placement makes no
  sense"). The left panel and the whole properties panel (schedule,
  filing, other, suggestions, the due sheet) now draw dividers only
  between rows. The one "randomly dimmer" line was the calendar's
  half-hour rule — also gone. border2 survives only as the outline of
  the two dashed "add" affordances.
- **The revealed divider sits exactly where the drawn line sits.** Two
  causes: the revealed dashes rendered in the small marker font, which
  changed the line's height (the page jumped ~2pt on caret entry); and
  the drawn rule anchored at half the line height while a dash's ink
  centre sits higher. The dashes now keep the body font, and the rule's
  position is read off the font's own dash glyph. Measured: 0.17pt
  apart, invisible.
- **"switch" micro-text in the left panel's workspace row** — a purge
  survivor — deleted.
- Pushed to the owner's iPhone (build.sh device run).

## 2026-08-07 (later) — one title cleaner, a surviving draft, a divider you can edit

- **Syntax can no longer appear in a title, and exactly ONE code bit
  guarantees it** (owner: "no two code bits solving the same problem").
  The core's title cleaner now strips INLINE syntax too — bold, italic,
  strikethrough, code ticks, and [[…]] link tokens (a named token reads
  as its name) — with rules that mirror the editor's own scanner to the
  letter. Twelve new test cases, including the two the old greedy trim
  got wrong: a line STARTING with bold ("**Bold start** rest" used to
  come out "Bold start** rest") and a checked box keeping its brackets.
  The Swift side then stopped cleaning: `livRowTitle` shows what the
  core sends, full stop, and also maps the core's "#id" placeholder to
  "Untitled" so no list ever shows a hash-number. The panel's duplicate
  `displayName` was deleted. `livDisplayTitle` survives ONLY for text
  the core has not seen yet (the live typing preview, the capture
  sheet's draft, a template body) — different problem, same look.
- **A suggestion now survives typing.** Saving a note's text used to
  retract every pending suggestion on that note, assuming the automatic
  sweep would re-derive it. Only the sweep's own five proposers qualify
  — their drafts are pure functions of the words. Anything else (a
  model's suggested title, a draft from another device) cannot be
  rebuilt, so retracting it on a keystroke destroyed it silently. New
  `clerk::rederivable` is the one place that says who re-derives; the
  save retracts those and keeps the rest. This unblocks AI titles.
- **The divider shows its dashes under the caret** (owner: "putting the
  cursor on a separator should make it appear as ---"). The styling
  pass now takes one piece of caret state: the paragraph the caret is
  in. A rule line in that paragraph renders as dimmed literal dashes —
  the same treatment every other marker gets — and snaps back to a
  drawn line the moment the caret leaves. Verified in pixels both ways.

## 2026-08-07 — two de-duplications, ahead of any Android work

Both were already wrong; neither is speculative work for a port that
has no start date.

**One answer to "what is this called".** Eight files each had their own
version, with four different words for nothing ("Untitled", "untitled",
"#id", ""). Two of them still re-read the content cell to find a first
line — work the core has done since this morning. Now there is
`livRowTitle` in Kit.swift and nothing else.

It still runs `livDisplayTitle` on top, and that is deliberate: the core
strips BLOCK markers (`#`, `-`, `>`) but not INLINE ones, so a first line
reading `**Pack** the van` arrives with its asterisks. Mirroring that
scanner in Rust would create a second copy of the very thing this
removes. It stays in Swift until the whole scanner moves, which is a job
for when Android actually needs it.

**One gregorian calendar.** `Civil.date(ofDay:)` was `private`, so five
other files wrote the noon-anchor trick out again — Calendar, Capture,
Tasks, Today and the due sheet's own formatter. Five copies of a
daylight-saving workaround is how a real bug eventually arrives. `Civil`
now also owns `date(day:hhmm:)`, `day(of:)`, `hhmm(of:)`, `weekday(_:)`
and `daysBetween(_:_:)`, and the copies are gone.

Verified live rather than by reading: the month grid still starts on the
right Monday, stepping forward two months and back three lands on July
2026 with 1 July on a Wednesday, and the Tasks list correctly drops the
"Weekend" swipe today — because today is Friday, so the weekend already
is tomorrow. That last one exercises the shared weekday function
directly.

The shell went from 15,980 lines to 15,904 and lost nine private
calendars.

## 2026-08-07 — titles say what a thing is called

**One line of Rust.** The snapshot's `title` was filled by
`liv_views::summary`, which returns the name cell if there is one and
otherwise **the whole body flattened into one line, cut at 72
characters**. So a note reading "Trip planning / Ask Steven about the
rack. / ## Gear / - Boots" reached every list as
`Trip planning Ask Steven about the rack. ## Gear - Boots`.

It now calls `liv_services::content::display_name`: name cell, else the
first non-empty line with its block marker taken off, else `#id`. That
function is `source_name` from phase 3, promoted out of `tasks.rs` — the
one place that already got this right, because the note-task chips
needed it. Its checkbox-marker reader (`task_words`) is now shared with
the task projection instead of duplicated.

`summary` is unchanged and still used by the CLI's list lens. It means
what it says; it was simply never the answer to "what is this called".

Owner-authorised change of MEANING on an existing snapshot field
(CLAUDE.md's ffi rule says additions must be purely additive). Failing
test first: `services/tests/tasks.rs
display_name_is_the_first_line_not_the_whole_body`, six cases including
a heading, a blank first line, a `---` rule line, an explicit name, and
an empty note. `ffi/liv.h` documents the new meaning. 313 Rust tests
green, six shell self-checks green, verified on screen.

## 2026-08-06 (later) — the second fix batch

- **The divider stopped moving.** Every styled paragraph carries 2pt of
  line spacing, and iOS adds that 2pt to the bottom of a line only when
  another line follows it. The rule was painted at the middle of the
  text's box, so pressing Return under a `---` grew the box and dropped
  the rule 1pt. It is anchored to the top of the line now. Measured in
  the screenshot: identical pixel row before and after the Return. The
  checkbox had the same latent bug and got the same fix.
- **Headings got bigger and brighter.** One recipe serves 28 section
  headers; it went from 11pt bold at 6.5:1 contrast to 13pt semibold at
  11:1. The quietest grey (#707078) read at 3.7:1 — below the 4.5:1
  readability minimum — and carried text in 36 places; it is #8E8E93
  now, 5.5:1. Five hand-rolled 9.5pt headers and two 9pt calendar
  labels now use the shared recipe or clear the 11pt floor.
- **The date editor is two groups, not five rows.** Today, Tomorrow and
  "Choose a date" all answer the same question, so all three are now the
  same kind of row; "Choose a date" opens a month calendar under it
  instead of a small popup. Time is its own group.
- **A due date always carries a clock time now** (owner). The "Add a
  time" opt-in is gone and so is the hidden 09:00 the reminder code
  invented for dates without one. A due you set without thinking about
  the clock takes the time it is now. Verified: tapping Tomorrow wrote
  `202608072338, date_only:false` — the day tapped, at the current
  minute, in one transaction.
- **Reminders lost their lead times** (owner). The two "At time / 10 min
  / 1 hr" pickers were invented, never specified, and only ever affected
  dues that carried a clock time. Deleted, with their stored settings
  and the 09:00 constant. A reminder rings when the thing is due.
- **The event capture card can pick a real time.** It offered 24 whole
  hours and nothing else, against the standing rule that an arbitrary
  date AND time must be reachable wherever a date can be set. That rule
  was recorded on 2026-08-05 and this control was missed when the other
  one was fixed.
- **Properties says which item it is.** The panel's top line is the
  item's name — grey "Untitled" when it has none — with the type as a
  chip below it. It used to be the chip alone, so a panel swiped over a
  note announced "note" and never said which note, and the same type
  then appeared again as a row further down.
- **Only editable things get rows** (owner). "type" and "created" were
  rows that looked like every other row and did nothing when tapped.
  Type is the chip; created is one quiet line at the bottom.
- **An empty note's title line reads a grey "Untitled"** (owner),
  reversing design/ios.md's "no placeholder text at all".

### Then a review of the batch found ten more, nine of them fixed

Five reviewers read the change, each finding was then attacked by a
skeptic, and 18 of 33 reports survived — deduplicating to ten real
defects. Four were introduced by the batch itself.

- **The rule was drawn crooked.** Its left edge measured from the
  container while its width measured from the text column, so it poked
  3pt past the text on the left and stopped 7pt short on the right.
  Measured after the fix: equal 17pt gutters.
- **A separator longer than about 50 dashes wrapped**, and since its
  characters are now invisible the note showed the rule followed by a
  blank gap nobody could explain. The rule line no longer wraps.
- **The date sheet deleted every event's duration.** `write(day:)` always
  passed no end, so touching the time wheel on a 09:00–11:00 meeting
  threw away the 11:00. The end now moves with the start. The arithmetic
  moved into `CalClock` where the calendar's self-check covers it —
  nine new assertions.
- **Removing the 09:00 made ordinary tasks ring at midnight.** Three
  quick-add rows still write a bare date. A due with no clock time now
  rings not at all, which is what "a date reminder shouldn't be a thing"
  means; anything you date through the sheet has a time and still rings.
- **A due set to exactly 00:00 was re-read as having no time** and
  silently replaced on the next edit, and it showed up in the all-day
  strip. The stored flag decides now, not a guess at the digits.
- **Ticking a note's checkbox from the Tasks list could fail forever.**
  Re-encoding the note promoted a `[[…]]` pointing at nothing into a
  real link, which the core refuses outright — so the tick never landed,
  silently, every time. The editor has always passed the guard this
  path lacked.
- **Setting a due from the capture strip left no trace**: no chip, and
  "+ Due" kept offering itself. It reads the result back now.
- **"Untitled" appeared for notes starting with a hash** — the test for
  the core's `#id` placeholder matched any leading `#`.

### The default time became 09:00, and all-day belongs to events

Owner, 2026-08-07: the current time was the wrong default — a task typed
at 23:47 was due at 23:47. One constant now says what "no particular
time" means: `LivDue.defaultHHMM` = 09:00.

The rule about who keeps "no clock time" is `LivDue.carriesTime`, four
self-check assertions:

- an **all-day event** stays all-day when you change only its day. A
  holiday is not due at 09:00. Touching the clock is what gives it one.
- a **task** always gets a moment. A task with no clock time cannot ring,
  and ringing is most of what a task's date is for.

Three quick-add rows still wrote a bare date, which after the reminder
change meant they could never ring; they write 09:00 now. The Tasks
list's Tomorrow/Weekend swipes also used to wipe an existing time —
they keep it.

Verified in the saved data both ways: the all-day event "Dentist visit"
moved 4 Aug → 8 Aug and stayed all-day; a date-only task moved and came
back as `202608080900` with a real time.

## 2026-08-06 — the owner's fix batch (six notes)

- **A divider is a LINE now.** `---` was detected and then only dimmed —
  nothing ever drew anything, so the "divider" shipped in phase 2 was
  three grey dashes. The glyphs go clear and the layout manager paints a
  rule across the text container, the same mechanism the checkbox uses.
  Verified in pixels this time, not in the box log.
- **Non-documents stopped being edited like documents.** Every desk tab,
  of every kind, rendered `NoteEditor`, so a task's name was line 1 of a
  markdown buffer and its facts hid behind a swipe. New `TabShape` +
  `RecordBody`: a task or event opens as a NAME (one line), its
  properties AS the body (the inspector's own rows, embedded — one
  implementation, not two), and optional plain-text Notes. The (i) door
  disappears on a record because the panel would duplicate the screen;
  ••• drops the note-only verbs (template, share, export).
  Notes/scraps/templates are unchanged.
- **Calendar items are named in the calendar.** Tapping an hour used to
  create an untitled event and throw you into the note editor. It now
  draws a draft block at that hour with a name field in it; the box
  learns nothing until you submit. Verified: tap → 0 writes, submit →
  exactly 2 (`new event` at the tapped hour, `set name`).
- **Settings is a settings screen.** It opened with the raw container
  path, an entity count, and a wall of field names, then the whole
  phone→desk funnel. Now: Suggestions, Reminders, Fields (as chips) —
  and one **Advanced** row holding Handoff, the box facts and the
  version. The notification line only speaks when a reminder will NOT
  arrive.
- **Micro-text purge.** The stamp footnote was copy-pasted under five
  surfaces; the header's LensChip already said it, so all five are gone.
  Also: the workspace selector's monospace subtitles ("Everything — no
  lens, no stamp", "no query"), two grammar lectures under the query
  fields, "A filter only filters — it never stamps.", the Inbox's grey
  "shows every workspace" (a chip now), the Settings assist essay, and
  "Add your own field…" → "Add field".
- **The Properties panel lost its "Properties" title.**

- **The five calendar-block accessibility actions are gone** (owner).
  They were added in phase 4 without being asked for. The dead
  `CalendarDuePick` sheet they were the only caller of went with them.
  Tap-to-open and drag-to-move both re-verified after the removal (one
  `set due`, 22:00 → 21:00).

Found and fixed while verifying, not on the list:
- Tapping an existing calendar block created a NEW draft on top of it —
  the hour band's tap and the block's tap fought over the same point and
  the band won. One `SpatialTapGesture` owns the grid now and resolves
  blocks first.
- A record's name committed TWICE (Return, then blur, with the snapshot
  still stale) — one rename, two transactions in the box.

## 2026-08-06 — Phase 7: Share & Export

- The ••• menu earns its secondary actions: **Share** (markdown text to
  the system sheet) and **Export as Markdown** (a real `.md` file, so
  Save to Files produces markdown). Verified live: the sheet opened on
  "Roof project · 2 KB" with Copy / Save to Files.
- Both are READS — no box write. One flattener (`SpanText.spansToText`),
  an `# H1` title added only when the note's own first line does not
  already state it, and a filesystem-safe capped filename that is never
  empty. Sixth self-check suite: `-share.selfcheck 1`, 12 assertions.
- An empty note refuses to share instead of handing over a blank file.
- **Toolbar vertical lock, third attempt** (owner: "insertion menu is
  still not locked vertically"): the horizontal scroller now has a
  delegate that resets `contentOffset.y` to zero on every scroll event,
  plus `isDirectionalLockEnabled`. Constraint-level pinning and the two
  bounce flags were already in place and evidently not enough. A
  synthesized vertical drag on the row does not move it — but a
  synthesized drag is not a finger, so this needs the owner's eye.

## 2026-08-06 — Phase 6: the templates ruling

- **Templates stay, with the banner** (owner). No code change was
  needed — the safeguard shipped in rev 6 and became a floating pill in
  phase 4 — so this phase was verification: opening a template shows
  "Template · New note" in the doors' band, and tapping it created a
  fresh note with `{{date}}` resolved to today while writing NOTHING to
  the template (box log: 2 transactions, both on the new entity, zero
  on the source). The misuse the ruling was about is prevented.

## 2026-08-05 — Phase 5: Today & Inbox, redefined

- **Today answers "what now?"**: LATE is a strip you cannot miss and
  means only what can still be DONE (incomplete tasks — a past meeting
  is not late, it happened); the day is ONE now-aware timeline (passed
  dims, next is lit, done collapses to a line); task/event colour comes
  from the Calendar's own language; chips carry project/person instead
  of the row's own type; reschedule KEEPS the time of day and a span's
  end; archived rows are excluded at last.
- **The Inbox is the decision queue**: one list, two sections, no modes
  (the old Route/Tidy segments were `Text` in capsules — no button, no
  state, tappable by nobody). Route cards carry full-width verbs that
  FINISH the object — Task lands with its first status, Event opens the
  date editor — each with a 5s Undo chip that reverses every
  transaction it made (verified: 2 writes in, 2 undos out). Suggested
  shows the clerk's pending proposals grouped by proposer with ✓/✗ and
  Accept all; ✗ asks once because a decline is permanent; assist-off is
  its own line, not a silent empty list.
- **One date editor everywhere** (owner: arbitrary time everywhere):
  `CaptureDuePicker` wrote date-only with no time control at all, so an
  event captured through the sheet could never have one. Deleted; every
  call site now opens `DetailDueSheet`.

## 2026-08-05 — Phase 4: the day hour grid

- The day panel is Apple Calendar's shape now: all-day band (timeless
  tasks keep their ring), a 24-hour scrollable grid with timed items as
  positioned blocks, a red now-line, and the view opening at now.
- **Tap an empty hour → an event at that hour**, landing as a desk tab
  for naming. Verified three times against the box log (16:00, 15:00,
  19:00 — `date_only=false`, exactly the band tapped).
- New `CalClock` pure layer + a fifth self-check suite
  (`-calendar.selfcheck 1`, 15 assertions): minutes/HHMM round trips,
  quarter-hour snapping, duration from a real end vs none vs a
  cross-day end, and the range label. It caught one of my own wrong
  expectations before the device did.
- **Drag-to-move SHIPPED, in UIKit** (owner: "do the UIKit drag
  properly"). Press a block, move it, release: 15-minute steps, live
  preview, one `setSpan` — verified twice in the box log (15:00→16:00,
  16:00→17:00). SwiftUI could not do it; the recognizer lives on the
  WINDOW, hit-tests in the grid's content space, and suspends scrolling
  only while a block is in the air. Taps still open blocks and the grid
  still scrolls (both re-verified, the latter with a `-drag.off 1`
  bisect switch built for the purpose). [Five accessibility actions were
  added here unasked; removed 2026-08-06 on the owner's word.]
- **Overlapping blocks split into columns** (`CalLayout`, pure +
  6 self-checks) instead of stacking where the one underneath was
  unreachable.
- Fixed along the way: `-desk.boot <feature>` was silently wiped one
  frame after being set (broke headless feature verification), a
  container a11y label that hid a block's status ring, an iOS-18-only
  SF Symbol that drew nothing, and the scroll indicator sitting on top
  of in-block controls.

## 2026-08-05 — Phase 3: tasks that mean something

- **The checkbox↔task gap is closed.** Every open `- [ ]` line in a live
  note now appears in Tasks under "In notes", carrying a chip that names
  and opens its source note. Checking a row edits that note's text
  through the editor's own toggle op, CAS-guarded — verified in the box
  log (one line flipped, everything else byte-identical).
- New `services/src/tasks.rs` projection (stores nothing, creates
  nothing) + an additive optional `note_tasks` snapshot key; three new
  Rust tests, `liv.h` documented; whole workspace green (40 suites).
- Found while building: nondeterministic `entities()` order (now
  sorted), the flattened-title trap for the third time (the note's name
  is now computed in Rust where the content is), empty checkboxes
  projecting as noise, and a `lineStart` off-by-one the editor
  self-check caught. Details in `design/tasks-study.md`.

## 2026-08-05 — Phase 2: the editor's `+` insertion menu

- The toolbar is the Notesnook shape now: a short daily row (undo, redo,
  heading, bold, italic, task, bullet, indent, outdent) with `+` as the
  first key — a native pull-up menu holding Link, Template, Numbered
  list, Quote, Strikethrough, Code, Divider, Outline. Same verbs, only
  the door moved.
- Found live while verifying: the Divider verb parked the caret at the
  end of the inserted `---`, so typing corrupted it into `---text`. It
  now lands the caret on a fresh line below; two new editor self-checks
  pin the behavior.
- Verified on simulator + box log; on the owner's device.

## 2026-08-05 — Phase 1: hardening close-out

- All 23 audit findings now adjudicated (the quota-killed 14 re-run
  against post-fix code): 12 fixed, 9 refuted, 2 confirmed core-side
  and filed as owner-gated chips (assist-toggle name/id mismatch; FFI
  triage vs merge proposals).
- Capture sheet Undo now takes back the WHOLE capture (trash of the
  saved entity + the adopting tab closes) — verified in the box log.
- Duplicate note per the owner's ruling: copies the type, skips
  reference/file cells (display-value re-adds could mislink).
- Swipe gate verified (selection drags can't open panels); link picker
  dismisses when a panel slides over it, and its dismiss-suppression
  ordering bug died; notification taps now dismiss Settings/workspace
  sheets too (lifted into the model) and every in-hierarchy overlay
  animates out on open().
- Template banner became a floating pill in the doors' band (no more
  dead space); Everything's Unfiled slice hides when the active LENS
  forces an area; merge proposals render their verb chips; suggestion
  buttons 44pt with per-proposal VoiceOver labels; empty-desk `+`
  disabled.
- Properties rows at the library's density (46pt / 15pt type).

## 2026-08-04 — rev 6: the Notesnook/ClickUp restructure + hardening

- Both side panels full-screen, swiped into from anywhere (one
  simultaneous drag on the desk; flick-gated so selection drags never
  trigger it), with the house close band.
- Library rebuilt: Views (Today, Inbox) / the workspace's own band
  (Calendar, Tasks, Everything — all wearing its lens) / pinned bottom
  (workspace switcher, Settings). Camera row removed.
- Everything now applies the workspace lens (+ LensChip); Today's
  recurring-occurrence loop was the one lens gap — closed.
- New Tab is an overlay chooser (never a tab); the empty desk IS the
  chooser; serial captures still land in one tab (adoptCapture).
- "New task" creates directly into the editor — first line is the name;
  the CaptureSheet now serves only events.
- Top-right: Properties door + ••• (secondary only: Duplicate note,
  Save as template, Move to Trash). Duplicate note ships (properties,
  not body; due copied structurally).
- Template banner safeguard ("edits change every future copy" + New
  note button).
- Keyboard toolbar transparent (keyboard material), hairline gone.
- **Suggested** in Properties: the deterministic clerk's per-note
  proposals with per-proposal ✗/✓; accepts write exactly the proposal
  (verified against the box log); assist consent toggle appears in
  Settings when the box carries the switch.
- Hardening (adversarial audit, 5 confirmed): capture-tab latch
  (consecutive creations rewrote a tab), title-reseed guard (external
  renames froze), chooser VoiceOver escape, 44pt labeled suggestion
  buttons, notification tap vs live capture sheet / open panels;
  Settings sheet re-hung on DeskHost; chooser entry animated.

## 2026-08-02 — rev 5: describe vs act

- ••• menu; Properties panel describes only; box-level Undo removed.
- Due editor: Today / Tomorrow / date picker / opt-in time / Clear.
- Trash closes the tab + 5s Undo chip; editor flushed BEFORE trash so
  the chip undoes the right transaction (found live).
- Bottom bar retires under the keyboard; toolbar vertical scroll fixed.
- Device builds: `shell/ios/build.sh device run` (signing bootstrapped
  once via a throwaway Xcode project; static-lib link lesson recorded).

## 2026-08-01 — rev 4: the three-zone model

Three zones, two doors, one-row bottom bar, panels as slide-overs;
six audit fixes (a11y dismissal, sheet lifetimes, zIndex, template
acknowledgment).

## Earlier (rev 1–3, July 2026)

The desk-first chrome, the markdown editor (TextKit 1, checkbox
painting, link picker, outline), templates v1, capture funnel +
satellite outbox, notifications, workspaces + filters, furnishing.
