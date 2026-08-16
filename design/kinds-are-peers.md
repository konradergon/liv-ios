# Tasks and the calendar are not additions

> Owner, 2026-08-16: *"If notes, tasks, and calendar items are all
> first-class objects with properties, why should 'notes' live in the
> main workspace while tasks and calendar items are tucked away in a
> library… Calendar, Tasks, etc. should be like a central part of the
> app and not just 'additions' to an Obsidian clone."*
>
> Status: **proposal**. Nothing here is built. Written 2026-08-16.

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

## The recommendation: **a tab can hold a view**

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
