# Tasks and the calendar are not additions

> Owner, 2026-08-16: *"If notes, tasks, and calendar items are all
> first-class objects with properties, why should 'notes' live in the
> main workspace while tasks and calendar items are tucked away in a
> library… Calendar, Tasks, etc. should be like a central part of the
> app and not just 'additions' to an Obsidian clone."*
>
> Status: **proposal**. Nothing here is built. Written 2026-08-16.

## Mockups

Eight phone frames of the floor, drawn 2026-08-16: today's shape, the
three floors, a note lying over one, a task's card, and the create key's
menu, ending with the three decisions.

- In the repo: `design/mockups/the-floor.html` (open it in a browser).
- Published (private): https://claude.ai/code/artifact/59aa7414-a021-46be-8a51-434d5b08e98e

## The floor — the design pass's answer, and the one I now recommend

*Produced 2026-08-16 by four independent architectures judged through
four lenses. Scores were close (6.5 / 6.25 / 6.0 / 5.75), so read the
reasoning rather than the numbers; the synthesis below takes the
strongest shape and grafts the best of the losers into it.*

*Read from the code on `konrad/rewrite-mac`, not run on the simulator. Nothing below changes the core, a verb, or the snapshot.*

## What is wrong

In the model a note and a task are the same thing: an object with properties. On screen a note is somewhere you **stand** and a task is something you **fetch** — you open a door, pick a room from a list, and only then can you see one or make one. The bar proves it: the `+` offers "Create a note" and "Add a file" and nothing else (`Desk.swift:390-401`), so a task can only be born inside the room that lists it (`Today.swift:150`, `Tasks.swift:388`) and an event only by tapping an hour in the calendar (`Calendar.swift:345`).

## The answer: **the floor**

Three nouns, each with exactly one home.

**The floor.** One view is always under you: **Today, Calendar, Tasks, Find**. It is the ground, not a room. It keeps its day, its scroll and its filter. You never "go to" the calendar — you are on it, or you are standing on something else. This is not a new mode: there is no toggle and no way to be off it. The Inbox stops being a place and becomes a band at the top of Today, drawn only when it has something, still ignoring the workspace filter (Today already links to it, `Today.swift:245`).

**Open things.** Notes, captures, files. They lie over the floor as tabs, exactly as today. Close the last one and you land on the floor. There is no empty desk any more.

**Records.** Tasks, events, people. A card over wherever you stand, exactly as today. The card is not a lesser container, it is the right size: a task's content is six facts and a decision, a note's content is the thing itself. That difference is real and should stay. What was wrong was never the card — it was having to travel to a room to reach a task at all.

**The bar becomes the floors:** Today · Calendar · Tasks · Find · Open (n). Back and forward go. They are browser furniture and the most Obsidian thing in the app.

**One create key.** One round accent key, bottom right, on every surface — the button you asked for on Saturday, promoted to the root. Its menu is Note · Task · Event · File. It fills in from where you stand: on Today, due that day at 09:00; on a calendar day, that day; inside a note, just the workspace. Whatever you make lands in its properties with the caret in the name — the app's one create rule since 13 August.

**The library is deleted**, not shrunk. Once the views are the ground, it is a list of doors to rooms you are already in.

## Why not the other three

**Views become tabs beside your notes.** That makes them equal, not central. Reaching the calendar becomes hunting a card in a grid that also holds your notes; a view can be closed and then has to be recovered from a menu; each workspace grows its own Calendar with its own remembered week. It is also Obsidian's own model — panes that hold anything — which is the direction you are steering away from.

**One list with three arrangements (Date / Status / Everything).** The idea underneath is right and I am stealing it below. As an architecture it deletes the words "Calendar" and "Tasks" and replaces them with a rule the user has to learn. You asked for those two to be central; dissolving them is not the same move. Its first shippable step is also the failure it warns about — three screens under a shared header.

**A task gets a full screen like a note.** This is the one you rejected on 7 August, and the code still quotes you (`Record.swift:57`). A fresh task has no notes, so that screen is a name, six rows, an "Add notes" button and two thirds of nothing. It also fills the plane you use for hour-long notes with ten-second things.

## What I am taking from them

1. **"A list shows the things that carry what it arranges by."** The calendar already works this way — it keys on `due` with no kind filter (`Calendar.swift:789`), so a note you gave a due date is already on it. Tasks is the last real drawer in the app: `kinds.contains("task")` at `Tasks.swift:161`. Step 4 removes it.
2. **Hoist the views' state.** `selectedDay`, `monthFirst`, the Tasks filter, Everything's lens are all local to the view, and the library throws them away every time it closes — a live defect today. The floor needs them anyway. Keep them off the published model, or the mini-calendar's drag lag comes straight back.
3. **The minimised pill is a second tab plane, one item deep.** It goes. With a floor under everything, a card you swipe away leaves you on the list you tapped it in, with the row still there.
4. **The resting state must be a view, never an empty notes plane.**

## Shipping order

**Step 1 — one create key. One day.**
One 56pt accent key, bottom right, on every surface. Menu: Note · Task · Event · File, context filled. Every verb already exists in `Box.swift`.
*Deletes:* the bar's `+` slot and the words "new tab" with it (this is a create key, not a tab door); `newTab()`; the two per-view add buttons at `Today.swift:133` and `Tasks.swift:75`, which become the one key in the same corner.
*After this you can make a task or an event from inside a note, without leaving it.* That alone answers most of your question.

**Step 2 — Find replaces Everything and search.**
One surface: a field with, when empty, everything newest first. It exists to free the bar slot the floor needs, and it deletes a view. Ships inside today's library, so it stands alone.
*Deletes:* `EverythingView` and its All / Upcoming / Unfiled picker; the bar's separate magnifier. "Upcoming" is what Today and the calendar are for; "Unfiled" comes back as a seeded saved filter.

**Step 3 — the floor.** The big one, two to three days.
Bar becomes Today · Calendar · Tasks · Find · Open (n). One floor is always mounted and keeps its state. The left-edge swipe, freed by the library, opens **Open** — a button and a swipe to one place, the way the library door already worked. If making it follow the finger costs more than a day, ship it snapping and fix it after.
*Deletes:* `LibraryPanel` and its list; `featureShown`, `show(_:)`, `setLibrary`, `libraryShown`, `libraryDrawn`, `libraryCurtain`, the library arm of `claimPanel`; the top-left door; ‹ › and `backIds`/`forwardIds`/`goBack`/`goForward`/`leaveChooser`; `EmptyHint("No tabs…")` and the empty-desk state; `minimisedRecord`, `restoreRecord`, `dropMinimised`, `MinimisedRecordPill`; the "All workspaces" / "This workspace" labels; `featureShown = nil` inside `adopt(workspace:)`, so switching workspace stops evicting you; the four per-view lens chips, because the workspace button at top centre says it once.

**Step 4 — Tasks stops being a drawer.**
Tasks lists anything with a status. The calendar already lists anything with a date. Then a note you gave a due date and a status is in all three places, because of what you put on it — the model showing through on screen, which is the whole point.
*Deletes:* the kind filter at `Tasks.swift:161`.

## Five situations, after step 3

1. **Make a task while reading a note.** Press the key, Task, type the name. The card is over your note. Swipe it down and you are in the same sentence. No travel at all.
2. **Check what is due today.** Tap Today. One tap from anywhere, and it opens on the day you left it, scrolled where you left it.
3. **Put an event in a slot.** Tap Calendar, tap the hour. The block is already in the slot behind the card, and the caret is in the name. Unchanged from today, one tap closer.
4. **Find a note from three weeks ago.** Tap Find, type. Empty field is everything, newest first.
5. **Work a project.** Pick the lens at top centre. All four floors narrow to it: Today its due things, Calendar its dates, Tasks its tasks, Find its notes. One lens, four views, no query typed.

## Three decisions only you can make

**1. The one key costs a tap on Today and Tasks. Take it?**
Today the key makes a task in one press. With four verbs it is press, Task, type. *Recommended: yes.* One key with one behaviour everywhere is worth one tap on two screens, and it buys a create door that works from every screen including inside a note. It also touches your 12 August word — *"task and event don't belong in new tab"*. That was aimed at the full-screen New Tab page and the old Idea/Task/Event/Photo chooser, both since deleted, and §13 already says the create menu's New task should open the card with the caret in the name. But it is your ruling, so say it. If you'd rather not spend the tap, keep the per-view key and the complaint stays half fixed.

**2. Should Tasks show anything with a status, not just tasks?**
*Recommended: yes.* A note you marked "In progress" is work in progress. The calendar has always worked this way and nobody has complained. Say no and Tasks stays the one screen in the app that sorts by type instead of by what you filed.

**3. Where do saved filters live once the library is gone?**
*Recommended: under the workspace button at top centre, as a second band in the sheet that is already there.* That button is the one thing on screen that says what you are looking at, which is exactly what a filter changes. This reverses your 11 August placement ("a filter is not a workspace"), and the reason you gave then — "this is where you already come to change what you are looking at" — now points at the top-centre button instead of the library. Needs your word.

---

## The diagnosis, in one paragraph

In the model every entity is the same thing: cells. On screen it is not.
The **desk** — the app's main surface, the thing you look at, the thing
that remembers what you had open — can hold exactly one kind: a note (or
a file, or an unshaped capture). Everything else lives inside a **view**,
and every view lives behind the library's door. So a note is somewhere
you ARE, and a task is somewhere you VISIT. That is what makes the
library read as Obsidian's file sidebar, and the calendar read as a
feature bolted to a notes app.

It is not the object model that is wrong. It is that one kind got the
main surface and the rest got a drawer.

## SUPERSEDED, 2026-08-16 — read §"The floor" below first

A four-architecture design pass (four proposals, sixteen judgements
through the owner's eye, the constitution, the builder and a sceptic)
came back AFTER this note was written and argued the recommendation
below is the weakest of the four. Its argument, which I accept:

> Views as tabs beside your notes makes them **equal, not central**.
> Reaching the calendar becomes hunting a card in a grid that also holds
> your notes; a view can be closed and then has to be recovered; each
> workspace grows its own Calendar with its own remembered week. It is
> also Obsidian's own model — panes that hold anything — which is the
> direction the owner is steering away from.

The rest of this section is kept as written, because the reasoning that
led to it is worth reading beside the thing that beat it.

## The first recommendation (superseded): **a tab can hold a view**

Today, Tasks, Calendar, Everything and any saved filter open as TABS,
beside your notes, in the same plane, remembered per workspace like
everything else. Nothing else about the app changes shape.

What that buys, in the owner's own terms:

- The calendar is not behind a navigation layer. It is open, beside the
  note you were reading, and the bar's tab count counts it.
- Switching between "the note I am writing" and "what is due today" is
  the same gesture as switching between two notes — one tap in the tab
  switcher, or the back arrow.
- The library stops being where half the app lives and becomes what it
  actually is: a **launcher** — the list of things you can open, plus
  filters and Settings. Small, and honest about being small.
- Nothing new to learn. A tab is already the app's one idea for "a thing
  I have open".

### What a tab holds, after this

| | today | proposed |
|---|---|---|
| note, capture | tab | tab |
| file | tab | tab |
| **view** (Today, Tasks, Calendar, Everything, a filter) | behind the library | **tab** |
| task, event (a record) | card over what you were looking at | unchanged — card |

Records stay cards. That is a settled owner ruling (2026-08-07: *"a tab
that just contains the properties view feels broken"*), and it is right:
a task's facts fill a card, not a screen. A card raised over a VIEW tab
is exactly what happens today when you tap a task in Tasks.

## Why not the other two shapes

**"A tab holds anything, including a task."** The most literal reading of
the complaint, and it reopens the 2026-08-07 ruling above. It also makes
the tab plane heavier: a task is a thing you touch for ten seconds, and
giving it the same weight as a note you write for an hour is the wrong
trade. What is worth stealing from it: a record card should be able to
BECOME a tab when it has notes worth writing (a "open as tab" verb in
the card's own menu), so the ruling stops being a ceiling.

**"Time and state are lenses, not places."** The most elegant: there are
no view screens at all, only one list of the workspace's things, arranged
by time, by status, or by name. It is probably where this ends up. But it
is a rewrite of five surfaces at once, and it answers a question the
owner has not asked yet — he asked why the calendar is behind a door, not
what a calendar is. Worth stealing now: **the views should share one row
recipe and one empty state**, so that when they do merge, they merge.

## Shipping order

Each step leaves the app coherent on its own.

1. **A view is a tab.** `DeskTabContent` gains `case view(Feature)`; the
   desk body renders a view when the active tab holds one; the tab plane
   persists it as `view:calendar`. Opening a row in the library opens a
   TAB and closes the library. One day's work, and after it the calendar
   is a peer.
   *Deletes*: the "a view opens inside the library" mechanism (rev 26).
2. **The library shrinks to a launcher.** With views living on the desk,
   the library is: the five views, the saved filters, Settings. That is a
   short list — it can move into the `+` menu's own sheet, or stay as a
   panel that is now honestly small.
   *Deletes*: the library's top band and back chevron; possibly the
   library panel itself.
3. **One tab, one thing you are working on.** A view tab can be pinned
   (Calendar always open) or opened twice; decide one and only one.
   *Deletes*: nothing; this is a rule, not a screen.
4. **Later, if it still itches**: the arrangements idea — Calendar,
   Tasks and Today become three arrangements of one list rather than
   three screens.

## The decisions only the owner can make

1. **Does tapping Calendar twice open a second Calendar tab, or focus the
   one you have?** *Recommended: focus the one you have.* A view is a
   place, not a document; two of them is a bug, not a feature.
2. **Does the library survive step 2, or fold into the `+` menu?**
   *Recommended: it survives, shrunken.* Settings and filters need a
   home, and the left edge is muscle memory now.
3. **Should a record be able to become a tab on demand?**
   *Recommended: yes, from the card's own menu, later.* It keeps the
   2026-08-07 ruling (a record is a card by default) while removing the
   ceiling the owner is feeling.
