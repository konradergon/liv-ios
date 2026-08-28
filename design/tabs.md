# Back to tabs

> **Status:** 2026-08-22. The team ruled that the single-surface model goes and
> a tab-centric one returns. The owner's instruction is quoted in full below.
>
> **This does not touch the engine.** `engine/` is a separate workspace member
> and the iOS app does not link it. Every phase here changes
> `shell/ios/Sources/**` and nothing else, so the two tracks cannot collide —
> the gate is `git diff --name-only` showing nothing outside the shell.

## The instruction

> Revert to tab centric UI model.
>
> **Side panel**
> * Views: Selecting one influences what tabs contain. Initially every view will
>   be opened in their respective tab system like we had it before. Selecting
>   "Notes", means tabs hold notes. See Notesnook screenshot for view buttons.
>   Remember surface style will be like Obsidian (sizes, text, color except
>   their purple).
> * Filter button. Get look influence by Obsidian screenshot.
> * Workspace and Settings at the bottom. Se my Obsidian screenshot. Replicate
>   the style.
>
> **Tab systems**
> * Revert if possible to how tabs looked for notes before.
> * What tabs contain is controlled by which View highlighted in side panel.
> * Also restore inactive tabs.
> * In every tab system, the bottom bar should be restored to how it was when we
>   only had a tab system of notes. Good if we now keep global search and global
>   create though... yet also have new tab and search tab nicely put in.
>
> But don't drop our core work!!!

The references: **Notesnook** for the view list — a row per view, monochrome
glyph, label, count on the right, the selected one wearing a soft filled
rounded rect. **Obsidian** for the surface — quiet type, small sizes, no colour,
and at the very foot a workspace name with a count line under it and a settings
gear beside it.

---

## What was deleted, and what survives

Commit `0aa2af3`, 2026-08-18, *"tabs are gone: Docs is a list, and one document
at a time"*.

**`Tabs.swift` comes back verbatim.** 605 lines, untouched by the 39 commits
since, and every symbol it needs still exists at HEAD. `build.sh` compiles
`Sources/*.swift` by glob and there is no Xcode project, so **dropping the file
in is the whole integration step**.

It contains: `LivTabs` (the inactive-after rule, one place), `TabSwitcher` (the
grid), `InactiveTabs` (the shelf), `TabCard`, and a 97-line self-check.

**`git revert 0aa2af3` is forbidden.** It would drag back four things that have
nothing to do with tabs — see the risks below. The revert is a hand-graft, file
by file.

---

## The one thing that never existed

A tab held **one document**. `DeskTabContent` had exactly one case,
`.entity(UInt64)`, and a tab plane rendered one markdown editor.

*"Selecting Notes means tabs hold notes"* therefore has two readings, and they
cost very differently:

**Reading A — a tab holds an entity of the view's kind.** Tasks give task tabs,
Calendar gives event tabs. This **reverses two of the owner's own recorded
rulings**:

- 2026-08-07: a record card is half-height because *"a tab that just contains
  the properties view feels broken."*
- 2026-08-08: opening a task as a tab *"threw you out of Tasks on every tap and
  left an orphan tab behind."* That is why records became cards.

**Reading B — each view owns a tab strip, and a tab is a saved position inside
that view.** Notes gives a note; Tasks gives a filter and its expanded groups;
Calendar gives a month. This is the Obsidian model the instruction cites for
style, it satisfies "selecting a view changes what tabs contain", and it
reverses nothing.

**Recommended: B, with Notes keeping A's behaviour**, because a note tab is what
already worked and is what "how tabs looked for notes before" names.

**DECIDED 2026-08-22, owner: Reading B.** Each view owns a tab strip, and a tab
is a saved position inside that view. **Notes keeps a note per tab**, because
that is what already worked and what "how tabs looked for notes before" names.
Nothing the owner previously ruled is reversed: in Tasks a tab is a task *list*,
and tapping a task still raises a card.

---

## The bottom bar

**Before:** one glass capsule, four equal keys — `‹ › 🔍 +`.

**The back and forward keys do not come back.** They stepped through per-launch
tab UUIDs, greyed out as tabs closed, and were never persisted. Their
replacement — the labelled `‹ Notes` at the top of a document, over a durable
`returns` stack — is better and already ships.

**Moving Views into the side panel frees the state key's slot**, which is exactly
the room a tab key needs. Nothing else moves:

```
[ ◫3 | 🔍 ]                    ( + )
```

- **Tab key** replaces the state key in place: the view's glyph, the count of
  open tabs, a chevron. Tap opens the current view's switcher.
- **Search stays** — global search, as instructed.
- **`+` stays** — global create, as instructed. What it creates now lands in a
  new tab, which is how "new tab" gets its door without a fifth key.

**New tab** existed only inside the switcher — a dashed card and a footer `+` —
and comes back there.

**"Search tab" never existed** and has two readings: a field that filters the
open tabs, or a tab whose content is a search. The first is ~20 lines; the
second needs a non-modal search surface and a new tab case. Taking the first;
the second is a separate feature if it is wanted.

---

## Order of work

Every phase: shell only, and the gate is the eight launch-flag self-checks.

| | | |
|---|---|---|
| **1** | Views return to the side panel, Notesnook-style, with the Obsidian foot | **done** |
| **2** | Tabs return for Notes — the exact pre-deletion model, `Tabs.swift` verbatim | **done**, ninth suite restored |
| **3** | The bar: tab key, `+` lands in a new tab, new-tab card and tab search in the switcher | **done** |
| **4** | Per-view planes, Reading B — one plane per view | **done**, tenth suite added |
| **5** | Inactive tabs across every plane | **done** |

---

## What phase 4 decided

**A plane per view, and a view with no plane shows its root.** No tabs has
always meant "you are looking at the list" in Notes; it means the same
everywhere now, so nobody boots into five empty tabs they did not ask for.
**Moving is what mints the tab** — pick a different day, a different filter, a
different slice, and a tab appears in the strip saying where you are parked.

**What a position IS, per view** (`shell/ios/Sources/Positions.swift`, one
file, because the card, the switcher's filter, the accessibility label and the
view itself all need the same words — standing rule 4):

| view | a tab holds | still `@State` |
|---|---|---|
| Notes | a document — what a tab always was | — |
| Everything | the slice (All / Upcoming / Unfiled) | — |
| Inbox | Route or Tidy | the orphan being routed |
| Tasks | the filter chip + the groups you unfolded | the due-pick sheet |
| Today | the day + the LATE and Done piles | the status vocabulary |
| Calendar | the month + the day selected in it | the block in the air, the bin's frame, the page request, the learned width |

**A token is on disk.** Single-field positions store their raw value
(`"upcoming"`, `"tidy"`); Tasks, Today and the Calendar store JSON with
`.sortedKeys`. That flag is the format, not tidiness: without it Swift's
per-process dictionary ordering spells the same position differently on
different launches, so a token read back from disk never equals a freshly built
one and `park` sees a move where nothing moved. The five-run flake that found
it is why the suite asserts it.

**A token this build cannot read falls back to the view's root**, and the card
falls back to the view's name. Saved planes outlive the code that wrote them.

## What phase 5 decided

**One attic, not six.** The switcher grid is the view you are standing in; the
Inactive shelf is every view at once, grouped by view in `Feature.inOrder` with
a count per group. A shelf that showed only the current plane would hide five —
a Calendar tab you stopped using in July would be invisible until you happened
to open the Calendar again, which is the opposite of what a shelf is for.

- The switcher's Inactive row counts **every** plane, so it appears in a view
  that has nothing parked of its own. That is the point: it is the door to the
  attic, not to this room's corner of it.
- **"Close all" closes every view's**, which is what the screen now shows. Still
  no confirmation and still no undo chip: a tab is device state, so closing one
  writes nothing to the box.
- **Reviving a tab from another view changes view first.** Focusing it where you
  stand would put it somewhere you cannot see.
- `TabCard` now takes the view its tab belongs to instead of reading
  `desk.state`. It had to: the shelf draws cards from several planes at once,
  and a position token has no meaning without the view that wrote it.
- `-desk.boot inactive` ages **every** plane, or the rehearsal would show a
  screen no user will ever see.

### Two defects phase 4 surfaced

1. **`-tabs.selfcheck` was rearranging real tabs.** It built a plain
   `DeskModel()`, which is bound to the live workspace, and every plane verb
   writes through to UserDefaults. It had done this since the day it was
   written; with one plane the fakes landed where the app already was and
   nothing looked wrong. With a plane per view they landed on **Today** — three
   phantom tabs on a real device, visible in the tab key. Both suites now build
   `DeskModel.scratchForSelfCheck()`, a desk on workspace `UInt64.max`, and
   clear its keys on the way out.
2. **`persist()` wrote a key for an empty plane**, so a view that once had a
   tab never looked untouched again. "No plane" and "a plane with no tabs" are
   one state and must not become two.

---

## Risks, ranked

**1. Three silent-data-loss fixes the deletion commit made on its way out, and
tabs make all three more frequent.**

- `stop()` passes a completion to `flush()`. Without it, a flush with a save
  already in flight queues nothing and the keystrokes typed during that save die
  with the teardown. **Under tabs, `stop()` runs on every tab switch.**
- Every leave calls `endEditing()` first, so a rename commits on resign. Tabs
  mean more leaves.
- The caret is remembered per note.

*Mitigation: graft files, never revert the commit, and put `-editor.selfcheck`
in every phase gate.*

**2. The Rust that commit carried** — the `recency` wire field the notes list
sorts on, and the proposal ordinal that was quadratic (430 ms of a 450 ms
snapshot at 400 proposals). A blanket revert restores both defects and would
dirty `ffi/`, turning `cargo test` red and blocking the engine work on a UI
change.

**3. `-places.selfcheck` encodes the single-surface model** in nine assertions —
*"a state has nothing beneath it"*, *"the second document replaces the first"*.
It has to be rewritten when tabs return, not deleted.

**4. Two persistence keys on real devices.** Any device launched since 18 August
holds a stale `desk.tabs.v1.<workspace>` **and** a live `desk.doc.v1.<workspace>`.
Restoring the plane naively brings back a four-day-old tab set and silently drops
the document actually in use. First launch must load the old plane *and* ensure
the live document is present and focused.

**5. Two `Feature` orderings that disagree.** `allCases` is one order and the
Go-to menu hard-codes another. Only the menu's is visible today; putting views in
the panel makes the other one visible for the first time. Declare one order.
