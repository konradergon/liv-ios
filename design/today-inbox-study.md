# Today & Inbox, redefined (roadmap phase 5)

Status: **SHIPPED 2026-08-05** — all four questions approved by the
owner: build both, LATE means incomplete tasks only, sections not
segments, and routing to Event opens the date editor. Mockup:
`design/mockups/today-inbox.html` (cleaned on the owner's note: the
explanatory boxes are gone, and the file/camera card was removed — the
camera is for scanning, which is later work, and a generated image
filename is not information).

**One instruction beyond the two screens** — *"make sure you can pick an
arbitrary time everywhere like in the real world"* — turned up a real
gap: `CaptureDuePicker` offered Today/Tomorrow/Weekend and a DATE
picker, and wrote `dateOnly: true` with no time at all, so an event
created through the capture sheet could never carry one. It is deleted;
both of its call sites now open `DetailDueSheet`, which is the ONE date
editor in the app (date + opt-in time + Clear). Same editor now backs
Today's Pick swipe, the Inbox's Event routing, the Calendar and the
Properties panel.

The owner's verdicts, verbatim: Today — *"the overview concept is
interesting, but the implementation is extremely basic and hasn't been
validated."* Inbox — *"feels confusing and far from complete. What is
its intended purpose of this workflow?"*

## 1. What each screen is FOR (the answer to his question)

Both live in the library's **Global** band — they ignore the workspace
lens on purpose, because a thing you must decide about must not hide
behind the lens you happen to be wearing.

- **Today answers "what now?"** — what is late, what is happening, what
  is left. You open it in the morning and glance at it through the day.
  It is a *reading* surface with a few one-tap verbs.
- **Inbox answers "what needs a decision from me?"** — it is the
  **decision queue**, and that is the sentence the whole screen should
  be built around. Exactly two things belong: a capture you have not
  told the app anything about yet, and a suggestion the clerk is
  waiting on. Everything else is somewhere else. When both are empty,
  the app has no questions for you — which is a real, earnable state.

That single idea kills the current confusion: the Inbox is not "the
untyped list", it is "the list of open questions", and a proposal is
just another open question.

## 2. What is actually wrong today (read from the code, not guessed)

**Today** (`shell/ios/Sources/Today.swift`):

1. **Overdue is hidden behind a tap** — `showOverdue` starts false, so
   the first look never shows what is late. The roadmap asked for a
   strip; it is a toggle.
2. **"Overdue" is wrong for anything that is not a task.** Any dated row
   before today that is not `done` counts — and only tasks have a
   status, so last week's meeting and a note carrying an old `date`
   cell sit in red forever with no way out but trashing or re-dating.
3. **Archived rows are never filtered** (Tasks and Everything both
   filter them).
4. **Recurring items can never be overdue** — `dated` excludes
   recurrences and `occurrences` only covers today−1…+7.
5. **The Captured tile and the Captured section count different
   things** — the tile counts every undated content entity all-time
   (routinely three digits), the section counts today's. When nothing
   was captured today the section is not rendered at all, so the tile
   is a button that visibly does nothing.
6. **A row's one chip shows the row's own type** ("task"), because
   `type` is a reference cell and it is the first cell written. The
   project or person never reaches the row. Tasks.swift already does
   this right.
7. **A swipe-reschedule destroys a span** — it always writes `end: 0`
   and `dateOnly: true`, so "Tomorrow" on a 2-hour meeting drops both
   its end and its time.
8. **Trash is a full-swipe with no confirmation and no undo**, and it
   sits where the spec put the *status* verb.
9. **No sense of the current time** — no now, no dimming of what has
   passed, no way to hide what is done; a finished day still looks
   full.
10. **Event / task / dated-note are one glyph apart**, and Today ignores
    the colour language the Calendar already uses.

**Inbox** (`shell/ios/Sources/Inbox.swift`, 208 lines):

1. **The lens bar is fake.** "Route" and "Tidy" are `Text` in capsules —
   no button, no gesture, no state. It looks like a segmented control
   and answers nothing.
2. **The Tidy data has been on the wire all along** — `snapshot.inbox`
   carries the clerk's full pending list and `accept`/`reject` already
   ship (the per-note Suggested section uses them).
3. **The four type verbs are a trapdoor**: they write one `type` cell
   and abandon the entity. Route a capture to "Event" and it has no
   date, so the Calendar cannot show it; route it to "Task" and it has
   no status, so it lands in "No status".
4. **Cell-writing buttons at 24pt, four abreast, no confirmation, no
   feedback, no undo** — and a refused write is completely silent.
5. **The ✦ marker is on every row**, because capture never writes a
   name cell, so the mark means nothing.
6. **Its rule is known to be the wrong rule, in writing.**
   `Everything.swift` says so: "Unfiled means NO AREA — not 'no type'.
   The Inbox's rule keys on type, which is why a task you hesitated
   over was missing from every area AND from the Inbox."
7. **Contentless orphans are structurally invisible** — the rule needs
   a content cell, so an added FILE never appears.
8. **Two definitions of "waiting capture" run side by side** — Today's
   strip uses "content ∧ no due", the Inbox uses "no type ∧ content".

## 3. The proposal

### Today — one column, now-aware

- **Overdue is a strip at the top, always visible when it has rows**,
  and it means *only what can still be done*: incomplete TASKS whose
  date has passed. A past event is not overdue, it happened. Each row
  carries one-tap Today / Tomorrow, and the strip states its own rule
  in the header count, not in prose.
- **The day is one timeline**: all-day first, then the day in time
  order, tasks and events distinguished by the Calendar's own colours
  (purple task, blue event) rather than a glyph.
- **Now is visible**: what has passed is dimmed, the next thing up is
  emphasised, and finished items collapse behind one "N done" line
  instead of padding the day.
- **Chips carry context** (project, person) — the row's own type never
  appears; reuse the Tasks view's chip logic.
- **Captured becomes one honest line** at the bottom — "3 captured
  today · Route them" jumping to the Inbox — instead of a tile whose
  number disagrees with its own section.
- Reschedule **preserves the span** (keep `end` and the time of day)
  and Trash **asks once** and offers Undo, like the desk's trash chip.
- Archived rows are excluded, everywhere.

### Inbox — the decision queue

One scrolling list, **two sections, no modes** (the fake segments go):

- **"Route" — captures with no type yet.** Each card shows the text and
  four verbs, but a verb **finishes the object** instead of stamping a
  half one: Task lands with the first status, Event opens the due sheet
  (an event without a date is not an event), Note and Link write
  directly. Every routing shows a brief **Undo** chip, and a refused
  write says so instead of failing silently. Files with no content are
  included, so an added photo is routable too.
- **"Suggested" — the clerk's pending proposals, grouped by proposer**
  (dates · mentions · priority · promote · merge), each with its own
  ✓/✗ and the group's "Accept all". Same accept/reject verbs the
  Properties panel already uses. Rejecting says out loud that it is
  permanent, because it is — the clerk never re-asks.
- **Assist off** is its own state: "Suggestions are off" + a jump to
  Settings, never a silent empty list.
- **Inbox zero** is a real, earned screen when both sections are empty.

## 4. What it costs

Shell-only. Every field is already on the wire; no core, services or
FFI change is needed for either screen. Two knock-on notes:

- The **merge** proposals cannot be accepted today — that is the FFI
  `triage()` bug already filed as a chip. Until it lands, merges either
  stay out of the list or show disabled with the reason; the mockup
  assumes they are simply absent.
- There is **no group-reject verb** (`liv_accept_group_at` exists, no
  counterpart), so "Reject all" would be an N-call loop with N sidecar
  writes and no single undo. The mockup offers **Accept all** only.

## 5. Questions before the build

1. **Approve both mockups?**
2. **Overdue = incomplete tasks only** (my proposal), or should past
   events/notes appear too, with some way to dismiss them?
3. **Inbox sections vs segments** — my call is two sections in one
   list, no mode. Keep a segmented control instead?
4. **Should routing "Event" open the due sheet** (my proposal: yes — an
   event with no date is invisible in the Calendar), or write the type
   and leave the date for later?
