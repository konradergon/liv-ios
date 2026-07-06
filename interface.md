# Interface

> **Status:** 0.3 — the Liv pivot.
>
> This document is the interface companion to `productivity_app.md`.
> Where they disagree, the constitution wins.
>
> It exists so that design decisions are made once, in writing,
> and so that no mockup, tool, or model ever gets to improvise
> against silence.

---

# 0.4 — Native look, Liv's substance (owner directive, 2026-07-07)

Refines the pivot: *"copy everything except theming and preserve the
clean native look."* Port Liv's **features, structure, and workflows**
exactly — but **render them native**, not as a pixel-copy of Liv's web
chrome. Where Liv draws a web idiom (flat square tabs with an accent
bar, bordered cards, chips-as-decoration), lotus draws the macOS
equivalent (rounded segmented tabs, system materials, tonal elevation).
The theme is lotus's (lake green); the *look and feel* is the
platform's. Two consequences already applied:

- **Chrome sits in the traffic-light band.** The content runs under the
  titlebar (`NSHostingController.safeAreaRegions = []`), so the sidebar
  header controls and the tab strip are at the very top, right of the
  traffic lights — one band, Claude-style, not a row below.
- **Tabs are native.** Rounded pills, the active one a raised tonal
  segment (no green accent bar, no square edges) — Safari/Arc idiom, not
  Liv's `TAB_BASE`.

When liv-ui-map.md specifies exact web-chrome pixels (§3 tokens, tab
melt, borders), treat them as the *structure* to honour and render the
native equivalent. Substance from Liv; surface from macOS.

---

# 0.3 — The Liv Pivot (supersedes most of what follows)

Decided by the owner, 2026-07-06, in his own words: *"we shall port
the interface and feature set Liv has (exactly, not just vaguely) …
replicate the entire Liv UI as closely as possible in SwiftUI
(preserve our colors only), and all of the features … precisely.
The thing I want this to end up as is Liv with a better core and
native UI."*

The new law:

- **The interface is Liv's, ported natively.** `liv-ui-map.md`
  (mined from the Liv source) is the interface spec of record;
  this document remains only for what survives below.
- **What survives:** the materials (SF Pro, SF Symbols, system
  controls and vibrancy, system light/dark), the lotus accent —
  lake green #2f7d6b replacing Liv's palette wherever Liv used an
  accent — the ❧ mark, create-then-rename, the 11pt floor, and
  the loop (decisions made once, in writing).
- **What is annulled:** the one-window/one-lens stance, the tabs
  ban, the palette ban, the settings-surface ban, the badge budget,
  the density budgets — every refusal that was taste, not
  architecture. Liv's shell is the taste now.
- **What still cannot enter,** because it is Liv's disease and the
  reason lotus exists: a second source of truth (no .md mirror, no
  file watcher, no write-through — import/export instead), silent
  mutation (every AI write stays a proposal), and embedded web
  engines (the port is native; web-rendered surfaces get native
  equivalents). Where Liv's UI assumes one of these, the UI stays
  and the truth underneath changes.

The calibration point is no longer Things 3. It is Liv itself,
with lotus's core and macOS-native craft.

---

# The Stance (0.2 — superseded by the pivot above)

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

# What Is Banned (0.2 — mostly annulled by the pivot; see 0.3)

Of this list, only the architectural items survive (stated in 0.3).
Kept for the record:

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
- Window chrome (decided with the first SwiftUI window): unified —
  transparent titlebar, no title text, the traffic lights floating
  over the sidebar, exactly as the mockup drew it.

Decided before P3 — the Claude-style chrome (owner's call, superseding
liv-ui-map.md §1's three-row anatomy for lotus specifically):

- **No chrome rows.** Liv's title row, tabs row, and bookmarks row are
  gone. The window is three regions only: the persistent left panel,
  the content, and the right inspector. The traffic lights float over
  the panel's top.
- **The panel header** carries two small controls beside the lights —
  collapse and search — replacing the drag-to-collapse gesture and the
  window-centred fake search field. Back/forward sit at the header's
  trailing edge. When the panel is collapsed (or in focus mode) those
  controls float top-left over the content, the only way back.
- **The rail is a labeled nav list** inside the panel: icon + name (a
  trailing slot for a badge, or a keycap once a surface earns one),
  the Claude sidebar idiom — not a 44pt icon strip.
- **The sidebar is persistent.** Every surface — Notes, Tasks,
  Calendar, the tools — renders in the content pane beside it; nav is
  always reachable. This drops Liv's "tools go full-bleed and hide the
  sidebar" rule deliberately.
- **The workspace switcher is a footer** at the panel's bottom (where
  the account row sits in Claude), its popover rising above; this
  retires the HomeHub tab row.
- **The bookmarks strip is dropped.** Bookmarked objects live in the
  "Saved" view of the sidebar view-picker, and will fold into the
  search palette (P6). No dedicated row.
- The tab strip (P3) will land as the content pane's own top bar, not
  a full-width chrome row.

The reference stays liv-ui-map.md; where this list and §1 disagree,
this list wins for lotus.

Decided with the first editor:

- **The editor is the one renderer that holds state** — exactly one
  draft of one entity. The loss budget is the current typing burst:
  two seconds of idle commits it, a thirty-second checkpoint bounds
  it under unbroken typing, and every close, lens switch, and quit
  flushes. A journal file exists only on the failure path (a quit
  the box refused) and is replayed through the same guarded save.
  This is the stated exception to "a renderer holds no state,"
  amended here rather than argued around.
- **Click selects, Enter opens, Escape closes** — the editor obeys
  the grammar: Enter on a selected row opens it as the editor lens,
  Esc flushes and returns. This also settles the open decision
  below: lists select on click and open on Enter.
- **Pills are monochrome.** Embedded references draw in label
  colors on a faint label-tinted fill. The accent keeps its
  exactly-three jobs; the editor uses none of them.
- **A save is to a value, never a moment**: every content save
  presents the fingerprint of the content it started from, and the
  seam refuses a stale write. Overwrite is re-read-then-save; there
  is no force flag.

## Open decisions

- ~~**Open-on-click vs. open-on-Enter** for list rows~~ — decided
  with the first editor (above): select on click, open on Enter.
