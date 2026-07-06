# Interface

> **Status:** 0.2 — the first mockup survived contact with its owner.
>
> This document is the interface companion to `productivity_app.md`.
> Where they disagree, the constitution wins.
>
> It exists so that design decisions are made once, in writing,
> and so that no mockup, tool, or model ever gets to improvise
> against silence.

---

# The Stance

One window. Native. Finished on arrival.

The calibration point is Things 3, not Obsidian:
calm, typographic, opinionated, zero configuration —
an interface whose absence of options reads as confidence,
not poverty.

The user never designs their system.
This document is where the designing happened.

---

# Materials

The platform's design system is the design system.

- SF Pro, at Apple's text styles only. No custom fonts, ever.
- SF Symbols for every icon. No icon font, no custom glyphs in v1.
- System materials: sidebar vibrancy, standard window chrome.
- System light and dark, following the OS. There is no theme.
- Standard controls unless a surface's one opinion demands otherwise.

Taste is spent only where the system has no opinion:
the layout of Today, the density of the calendar,
the shape of a proposal row.

Everything else is Apple's, taken wholesale and without apology.

---

# The Window

One window, three regions. No tabs — ever.
(Imported scar: Liv grew two coexisting tab systems.
Nothing grows from zero.)

```
┌─────────┬──────────────────────────┬──────────┐
│ sidebar │         content          │ inspector│
│         │     (the active lens)    │(optional)│
└─────────┴──────────────────────────┴──────────┘
```

**Sidebar** — navigation is a view of views, rendered literally:
Today, Calendar, Everything, and the inbox with its count —
then saved views, when bookmarks exist.
The inbox count is the only badge in the application.

**Content** — exactly one lens at a time.
Switching lenses is instant and stateless;
there is nothing to lose, so there is nothing to tab.

**Inspector** — metadata is not hidden:
the selected entity's cells, visible and editable,
in a right panel toggled with one key.
Closed by default in Today (calm), open by default in Table (work).

The capture panel stays what it already is:
a floating bar summoned from anywhere, owned by the hotkey,
never docked into the window.

---

# The Surfaces

Each surface has an intent and a density budget.
A surface may not borrow another's density.

## Today
Minutes, every morning. The calmest surface.
Generous spacing, typographic hierarchy, no chrome.
Sections in order: due now — captured, unstructured — one line
for proposals waiting. Empty sections vanish.
An empty Today says one quiet sentence, and that is a feature:
absence creates no debt.

## Inbox
One proposal, one row: reason, subject, author.
Single-key triage — accept, decline, next —
the keyboard never leaves home row.
Alike proposals group; a group opens and severs (constitution 1.3).
Empty state: "nothing waiting." Nothing nags.

## List / Table
The dense surface. Two densities, one renderer.
Table rows tight, list rows one line each,
column headers are property names, sorting is one click.

## Editor
The venue for thought itself.
A centered column, measure ~65 characters, body text style.
Embedded references render as inline pills;
an embedded task draws its live checkbox.
No formatting toolbar in v1 — keyboard formatting only.
(Imported scar: Liv's toolbar border rendered as a
partial-width rule across the writing column.)

## Calendar
Anything with a date, native dates only.
Month and week. Density between Today and Table.
Days are quiet unless occupied.

---

# Interaction Grammar

Uniform, or the window becomes several applications.

- Click selects. Enter opens. Escape closes or deselects.
  The same everywhere, including the calendar and the inbox.
- Every mutation is one undo step. ⌘Z always works,
  always undoes exactly one user action, on every surface.
- Editing a cell is the same gesture in the table,
  the inspector, and the editor.
- Creating anything named drops straight into renaming.
  (Imported keeper: Liv's create-then-rename flow.)
- A gesture translates into commands, or into nothing.

## The keyboard map

- **⌃⌥Space** — capture, from anywhere (the OS-level hotkey)
- **⌘1 ⌘2 ⌘3 ⌘4** — Today, Calendar, Everything, Inbox
- **⌘N** — capture, inside the app
- **⌘F** — search: one field, every entity; search is navigation
- **⌘I** — inspector
- **j / k or arrows** — move selection
- **a / r** — accept / decline, in the inbox only
- **⌘Z / ⇧⌘Z** — undo / redo, globally

No chord does different things on different surfaces.

---

# Typography and Space

- Apple text styles only: Title 2, Headline, Body, Callout,
  Caption. Nothing below 11 points, ever. (Imported scar.)
- Hierarchy comes from size, weight, and label color —
  never from boxes, backgrounds, or borders.
- An 8-point spacing grid; 4-point only inside a row.
- Dividers are full-width or absent. (Imported scar.)
- At most two background shades per surface, and adjacent
  panels never meet at a visible seam. (Imported scar.)

---

# Color

- Backgrounds, labels, separators: system semantic colors only.
- **One accent color**, chosen once (open decision below).
  It may mean exactly three things: selection,
  the clerk's affordances, and today's date in the calendar.
- System red for destructive, and nothing else is ever red.
- Status values render as text with a small tinted dot,
  from a fixed palette of five. No pill-shaped rainbow.
- Backstage entities, when deliberately revealed,
  render at secondary-label opacity. The plumbing looks like plumbing.

---

# What Is Banned

The negative space, stated so no tool can improvise into it:

- themes, font pickers, density or spacing settings
- tabs, split panes, detachable panels
- badges anywhere but the inbox count
- animation beyond the system's defaults
- text below 11 points; partial-width dividers; shade seams
- hover-only affordances for primary actions
- web idioms: bordered cards, chips as decoration, skeleton shimmer
- a settings window. The four budgeted settings live in the
  menu bar item, and they are the whole list.

---

# Lessons Imported from Liv

Named, so their price is not paid twice:

1. Chrome scatters unless gathered — lotus starts gathered:
   one sidebar, one search, one inbox.
2. Two tab systems coexisted because one tab system existed.
   Zero tab systems.
3. Panel shade steps and partial dividers read as defects,
   and they are found only after they ship. Banned up front.
4. Tiny text accumulates one exception at a time. Floor: 11pt.
5. Create-then-rename is the correct birth for every named thing.
6. Consistency work done late is archaeology.
   This document is the same work done early.

---

# The Loop

How this document grows:

1. For a surface, mockups propose two or three variants.
2. One is chosen, in writing, here.
3. The choice joins **Decided**, and is never re-argued
   unless daily use overrules it — the constitution's own rule.

## Decided

Decided in 0.2, from the first mockup (design/window.html):

- The base layout is adopted: sidebar / one lens / inspector,
  every lens swapping in place. All of lotus in one window;
  nothing floats free.
- The accent is **lake green** (#2f7d6b in the mockup; the SwiftUI
  token is the truth once it exists). The mark is **❧**.
- **Search lives at the top of the sidebar** (⌘F) — search is
  navigation, so it sits with navigation, and results render as
  the list lens in place. No palette, no overlay.
- **One capture affordance in-window**: Today's lead line (⌘N from
  any lens). The global panel remains the outside-the-app door;
  inside the window there is exactly one.
- Inspector defaults as mocked: open in Table, closed in Today —
  held loosely, daily use may overrule.

## Open decisions

- **Open-on-click vs. open-on-Enter** for list rows
  (Things opens inline; Finder selects then opens).
  Decided when the first list ships.
- **Window chrome tone** — standard titlebar vs. unified
  toolbar-in-titlebar. Decided with the first SwiftUI window.
