# The phone against the blueprints — audit, 2026-08-10

Owner's ask, verbatim: *"Remember the app should be a mobile version of
Liv. Look at the Liv blueprints and see what is missing and what is
different in our app. Where views are, how they look, workflow,
everything… Where are there room for improvement and mobile
optimization without breaking compatibility? Then give me a summary and
plan proposal for future app work."*

Method: two readers mapped the blueprints (`interface.md`,
`feature-map.md`, `liv-ui-map.md` — 4,578 lines — and the original app's
own docs in `lovable-notes-hub/docs/`) against all 29 Swift files.
Three lenses ran over that map — what is MISSING, what is DIFFERENT, and
where the phone can beat the desk. 58 findings were raised; each was
sent to a separate reader told to refute it. 37 survived. What follows
is only what survived.

## 0. The governing rule, first — because it changes the answer

`interface.md`'s pivot (2026-07-06) makes **`liv-ui-map.md` the interface
spec of record**: "the interface is Liv's, ported natively." It
*annulled* every earlier refusal that was taste rather than architecture
— the one-window stance, the tabs ban, the badge budget, the
settings-surface ban. So tabs, workspaces, panels, badges and pinned
rows are all IN scope, and a few things `feature-map.md` lists under
"explicitly refused" (the favourites shelf, for one) are refused no
longer. Several gaps below only exist because of that annulment.

## 1. The headline

**The phone is faithful where it counts and hollow in one specific
place: verbs that exist in the core with no door in the app.**

Nothing structural has drifted. The information architecture, the
editor, capture, Today, Inbox, tasks, the calendar, files, templates,
search and workspaces are all present and behave the way the blueprints
describe, allowing for phone width. What the audit found is not drift —
it is **eleven finished machines with no handle**: the Rust core, the C
functions and the snapshot fields all shipped, and no Swift file calls
them. In blueprint terms the app is missing features; in engineering
terms it is missing *buttons*.

## 2. Missing — verb built, no door (the cheap half)

Each of these is shell-only work. No box format change, no new C
function, no settled-zone edit.

| What | Already shipped | Missing |
|---|---|---|
| **Daily note** | `liv_open_daily_note_at` (get-or-create in one transaction, so two doors can't double-create) | No door. The only route is the "Daily note" template, buried in the chooser. |
| **Version history** | `liv_content_history_at`; the header itself documents restore as an ordinary `liv_set_content_at` of the old spans | No History pane. Restore needs no new verb. |
| **Pinned rows** (the SlotsBar successor) | `liv_pin_at` / `liv_unpin_at`; the snapshot already carries an ordered `pins` array | Zero calls; `Box.swift` does not even decode `pins`. |
| **Archive** | The `archived` bool is seeded, projected on every row, and already decoded — six surfaces filter on it | Nothing ever *sets* it. The only route to an archived item is typing `is:archived` into a raw query field, which standing rule 5 forbids as primary UI. |
| **Saved searches** | `liv_create_view_at`, wired in `Box.swift` | No "save this search" row; saved filters are visible only inside the workspace switcher sheet, not in the library panel where the blueprint puts saved views. |
| **Vault export** | `liv_export_at` (query-scoped, copy-only) | Unused. The phone exports one note's markdown from the ••• menu. `interface.md` leans on export as the answer to "no second source of truth". |
| **Whole-app badge** | Notification plumbing exists | `design/ios.md` declares "one badge, by law: the proposal count" and no code sets it. |
| **Habits** | Core, both verbs, and a `HabitsSummary` on every snapshot | Zero UI. Deferred **on purpose** (`ios.md:691`) — but the remaining price is now pure Swift, and the summary is computed on every snapshot with no consumer. |
| **Time tracking** | `timeviews.rs`, `liv_log_time_at`, `TimeSummary` on the snapshot | Zero UI. Correctly deferred — the rule is "build when the owner asks twice", and he has not asked once. |

## 3. Missing — real work, not just a door

- **Backlinks.** The inspector shows forward references only. The
  archived Mac shell had a Connections band and built the reverse index
  by inverting the cells of one snapshot — about 30 lines, shell-side,
  no ABI change. This also unblocks the graph lens, which stays
  deferred until backlinks earn it.
- **Recurrence is read-only.** The phone renders the repeat glyph and
  refuses to drag an occurrence, and no surface writes a rule. The
  original's whole recurrence editor was a four-option select. One
  grammar already exists in `services/src/recurrence.rs` ("every day",
  "every week", "every month", "every &lt;weekday&gt;"); a preset sheet
  writing those exact strings is the faithful port.
- **Extract selection.** Founder-locked in the original: select text in
  a note, make it a task, leave the note alone but for a back-reference.
  The iOS selection menu offers Bold/Italic/Strike/Code and nothing
  else. Honouring "one transaction, one undo step" wants one additive
  C function.
- **Priority.** Seeded in the core, proposed by the clerk from a closed
  word list, and offered by no UI at all. A whole-shell search for
  "priority" hits a layout call and a comment.
- **Link capture.** Routing a capture as "Link" writes the type and
  nothing else — no URL detection, no one-time title fetch. The clerk's
  duplicate detection keys on the `url` cell, so a link without one is
  invisible to it.
- **People.** The `person` kind exists as a glyph, a template and a
  capture chip. There is no list of people.

## 4. Different — and mostly right

Four deliberate departures. All four are correct for a phone; three are
unrecorded, which is the actual defect.

1. **Rail + three simultaneous panes → library panel + full-screen
   covers.** Owner-directed, recorded. A 44px rail and three panes
   cannot exist at phone width. Keep.
2. **Every kind in the tab strip → documents in tabs, records as
   cards.** A genuine improvement over the blueprint, not a compromise:
   editing a task no longer costs you your place.
3. **Month/Week/Day → month grid + day panel.** Right pair; a 7-column
   hour grid is unreadable on a phone. The week view should be written
   down as deliberately omitted rather than silently absent.
4. **Single-field capture with no token grammar.** Blueprint-faithful,
   and now doubly settled by the 2026-08-09 refusal of Todoist-style
   parsing.

One genuine regression: **search hit rows are thinner than the app's own
list grammar.** Everything's rows carry a kind glyph and up to three
chips; search results are title plus due date. The original carried the
glyph, a relative time and up to four chips. Search should match its own
app.

## 5. Mobile — where the phone can beat the desk

Ordered by value per unit of work, and none of it breaks compatibility.

1. **The share extension.** The mobile equivalent of the original's
   link-save overlay, and the single biggest capture lever. Designed
   already; it needs the Xcode project work, and it has no dependency
   on deep links.
2. **Notification actions.** Complete or defer a task straight from the
   reminder. Reminders already fire; the actions are the missing half.
3. **`liv://` deep links.** Designed, unbuilt, no recorded blocker. Two
   plist entries and one handler. This is also what an App Shortcut or
   a lock-screen widget would call.
4. **A hardware keyboard map.** The blueprint specifies accelerators;
   the phone has none, and undo is reachable only through a chip that
   disappears after five seconds. iPads and keyboard cases exist.
5. **Codify the haptics.** Feedback is currently chosen call-site by
   call-site. Standing rule 3: a rule that matters lives in a type.

## 6. What the audit did NOT find

No architectural drift. No violated standing rule. No place where the
shell talks to the core outside `Box.swift`. No snapshot field decoded
non-optionally. The two prior audits' open items are either shipped or
still correctly open. **The gap between this app and the blueprints is a
list of doors, not a rebuild.**

---

# Plan proposal — five batches

Nothing starts without the owner's word. Ordered so each batch ships
something usable on its own.

**Batch A — the doors (all shell-only, no new C functions).**
Daily-note door on Today · archive verb plus an Archived lens · pinned
band in the library panel · save-this-search plus a Filters band ·
history pane in Properties · search rows matching the app's own row
grammar · the proposal badge. Seven finished machines get handles.

**Batch B — the two real holes.** Backlinks in the inspector (rebuild
the reverse index per snapshot, as the Mac shell did) and a recurrence
preset sheet writing the one existing grammar. Both are shell-only;
recurrence needs its parser tested against the sheet's exact strings.

**Batch C — mobile leverage.** Share extension, notification actions,
`liv://` routes. This is the batch that makes the phone better than the
desk at the one thing phones are better at: catching things.

**Batch D — the smaller blueprint items.** Priority row · link capture
with a one-time title fetch · a people list · extract-selection (the
only item here needing one additive C function, flagged before it is
written).

**Batch E — decisions, not code.** Habits (the price dropped to pure
Swift; keep deferring or build) · vault export scope, phone or desk ·
the week view, formally deferred · the three open file questions
already on the table · the hardware keyboard map.

Files work and AI titles keep their agreed slots: files first, AI after.
Batch A can run alongside either — it touches no file the files work
touches.
