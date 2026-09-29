# Clearer — a surface pass on `polish-pass-lmkl30`

> **Status: mockup approved, not built.** Owner, 2026-09-29: *"go with A.
> then make sure i can replicate this in the app in another session."*
> This file is that handoff. It was written against `polish-pass-lmkl30`
> at `becf7fd`; every name below is a name in that tree.
>
> **Look first:** `design/mockups/clearer.html` is a static copy of the
> approved boards. Open it in a browser. The live canvas, with the
> as-built "now" board beside each one, is
> https://claude.ai/artifact/UqAN168J2vxR5MQ1BZwkaN. It is private to the
> owner's claude.ai account, and a Claude session signed in as the owner
> can read it with the Artifact tool (the boards are `project/*.dc.html`).
>
> **CLAUDE.md still governs the build.** Mockup-first is what this is.
> Every size and colour goes through `Theme.swift`. Nothing counts as
> working until `suites.sh` and `drive.sh tour` say so on the simulator.
> Do not commit unless the owner asks.

## What was asked

The owner's words, in order (2026-09-24 → 29):

- "less crudeness"
- "i want everything to be clearer where things are more readable" · "i
  want a the most modern feel in a apple native way"
- "replace current icons with custom ones that makes it easy to tell what
  they represent… workspace icons · [n] in bar are open tabs holding
  notes · + in the bar makes a note when clicked but lets you create
  anything when held · should look as simple as now still"
- "somehow add subtleties that gives the app a personality and theme,
  consistently throughout"
- "settings should be a simple cogwheel. no color icons. letters are not
  in boxes"
- "change "All" icon… it doesn't fit in. "Areas" icon is ugly" · "the
  panel looks like an incomplete list of items since the bottom half is
  empty"
- "go with A" (the panel as a list, with the workspaces moved into it)
- "i thing the old open tabs "[n]" style was better. and the gear icon
  shouldn't have a circle in the middle and be less coggy"
- "improve the settings icon... should still look like a cogwheel"

## The rules

This is what "clearer" means here. Every surface below applies these
rules; none of them is a one-off.

1. **One big title per screen.** `LivScreenTitle` at 34 bold, ending in
   an accent full stop — the app's one signature mark — with an optional
   16pt secondary line under it (the date, a count). A NOTE's title gets
   no full stop: it is the user's own words.
2. **Rows live in cards.** Related rows sit on a `LivCard` (surface,
   radius 22, 16 from the screen edge) under a 20 semibold header. The
   gap between cards separates groups. Hairlines only separate rows
   inside one card.
3. **Two levels, never three.** Row title 18 regular in full ink, and at
   most one 16pt second line in secondary ink for where and who ("Work ·
   with Mira"). No chips under titles.
4. **Facts are readable.** Dates, times and counts on the right sit at 16
   in `text2`. `text3` is only for placeholders, the panel's counts and
   footnotes. Dates read the way Apple writes them: `09:41` today,
   `Yesterday`, the weekday within the week (`Tuesday`), otherwise
   `21 Sep`.
5. **Red means late, and nothing else.** The accent marks the present
   (the today disc, the now line), the one filled pill, links inside
   notes, and the title's full stop.
6. **Icons are ink.** One pen for every icon: a 24 grid, a 1.75 line,
   round caps and joins, corners at 3, and no colour. `LivKind.color`
   stops colouring glyphs. It survives as the schedule's event bar and
   the calendar's blocks.
7. **The dot is the signature.** A filled dot sits where an icon's meaning
   is: the full stop after a note's last line, the day on the calendar,
   the thing dropping into Unsorted, the sun's core, the value side of the
   properties mark. The same dot ends screen titles, starts the now line,
   and marks the days in the week strip that have something on.
8. **Tapping keeps its three shapes** (house rule, 2026-09-15): a
   full-width row, a hollow chip (`AddChip`), the one filled pill
   (`ConfirmPill`). Nothing here adds a fourth, and bare accent words
   stay banned.

## Tokens — `Theme.swift`

The palette does not change. The type the clearer screens use is 34
(`hero`), 26 (`display`), 20 (`strong`, headers), 18 (`body`), 16
(`label`) and 14 (`caption`), and no other size.

| Token | Now | Clearer | Why |
|---|---|---|---|
| `LivType.hero` | 32 | **34** | screen title and note title; Apple's large title |
| `LivType.Editor.body` | 16 | **18** | the editor sat a step below every list row that opens it |
| `LivType.Editor.h1 / h2 / h3` | 25 / 21 / 18 | **24 bold / 20 semibold / 18 semibold** | nothing in a note competes with its 34 title |
| editor line height | 16 + 2 spacing | **27** (18pt at ≈1.5) | reading comfort |
| `MarkdownTextView.gutter` | 15 | **20** | |
| `MarkdownTextView.titleGap` | 20 | **18** | |
| `EditorFont.listGutter` | 23 | **30** | the checkbox grew |
| `LivRow.height` | 56 | **52** one line · **64** with a second line | a row inside a card |
| `LivRow.glyph` | 19 | **22** | row icons, in `text2` |
| `LivRowFact` ink | `text3` | **`text2`** | rule 4 |
| `LivPanel.row` | 57 | **52** | the panel holds the views and the workspaces |
| `LivPanel.litHeight` | 49 | **46** | lit fill inset 3 top and bottom, 12 each side |
| `LivDay.disc` | 36 | **38** | |
| `GlyphShape.lineWidth(size)` | `size / 12` | **1.75 at ≥ 18pt, 1.6 below** | one pen weight at every size |
| `StatusRing` | 15, radius 5, 1.5 line, `text3` | **20, radius 6, 1.7 line, `text2`** | done: fill in the status hue (Done is green), white tick |
| `AddChip` | 24 (big 30), 14 `text3`, 0.5 outline | **32, label 16 `text2`, 1pt `border2` (#3A3A3A) outline** | the outline is the whole shape, so it has to show |
| `LivSegment` | 44, `radiusSm` thumb in `panel2` | **track in `panel2` (radius 20, 3 inset); capsule thumb in `border2` (#3A3A3A), 34 tall; label 16** | |

## Components

**`LivScreenTitle`** (Kit.swift) takes an optional `subtitle`. It draws
the title at `hero` bold in `text`, followed by a `"."` in
`LivTheme.accent`. The subtitle sits 2 below at `label` in `text2`.
Padding is 6 above, 14 below and 20 leading.

**Card header** is new: a `prominent` style on `SectionLabel`, or its own
view. It draws the title at 20 semibold in `text`, then an optional count
at 18 `text2`, then trailing content right-aligned (a red "2 late" at 16
medium, a fold chevron). It has 26 above (16 when it directly follows the
week strip), 10 below and 20 leading. `SectionLabel` itself stays as the
small label (16 medium `text2`) inside sheets and the panel.

**`LivCard`** (Rows.swift) is already the right shape (surface,
`radiusLg` 22, `cardInset` 16). Its label moves to the card header above.

**`LivListRow`** (Rows.swift):

- Gains `detail: String?`, a second line at 16 in `text2`, one line long.
- Layout inside a card: 16 padding, a 28 lead column, a 12 gap, so the
  text starts 56 into the card. The lead is the glyph at 22 in `text2`,
  or a `StatusRing`.
- Title is 18 regular in `text`. Trailing facts are 16 `text2`, 10 apart,
  with an optional chevron (14, `text3`) on rows that open something.
- The hairline between rows starts at the text (56 into the card) and
  runs to the card's edge. There is none after the last row.
- Wherever a row wore an anchor `ValueChip` under its title,
  `livAnchor(of:)`'s value becomes the detail line.

**`LivIcon`** (Glyph.swift) gains a fill layer. `GlyphShape` is strokes
only ("every glyph is STROKED, never filled"), and the dot is a fill. Add
the dots as their own list per glyph (`GlyphDots`, or `LivGlyph.dots:
[(x, y, r)]`) and draw them with `.fill` in the same frame and colour.

**`StatusRing`, `AddChip`, `LivSegment`** change as in the table.
`ConfirmPill` does not change.

## Glyphs — `Glyph.swift`

Everything below is drawn with the existing `Pen`, in the same 24 grid.
Dots are listed as comments because they belong to the new fill layer.

```swift
case .note:
    pen.box(5, 3.5, 14, 17, 3)
    pen.line(8.5, 8.5, 15.5, 8.5)
    pen.line(8.5, 12, 15.5, 12)
    pen.line(8.5, 15.5, 11.5, 15.5)
    // dot (14.3, 15.5) r 1.25 — the full stop after the short last line
case .task:                       // a thing: the box with a rule (same idea as now)
    pen.box(4.5, 4.5, 15, 15, 3.5)
    pen.line(9.5, 12, 14.5, 12)
case .tasks:                      // the place: the box with a tick
    pen.box(4.5, 4.5, 15, 15, 3.5)
    pen.shape([(8.6, 12.3, 0), (11, 14.7, 0), (15.5, 9.6, 0)], closed: false)
case .event, .calendar:
    pen.box(3.5, 5, 17, 15.5, 3)
    pen.line(8, 3, 8, 6.5)
    pen.line(16, 3, 16, 6.5)
    pen.line(3.5, 10, 20.5, 10)
    // dot (15.5, 15.2) r 1.7 — the day
case .today:
    pen.circle(12, 12, 4)
    pen.rays(12, 12, from: 7.2, to: 9.2, count: 8)
    // dot (12, 12) r 1.5 — the core
case .capture, .inbox:            // Unsorted: something dropping into a tray
    pen.shape([(3.5, 12.5, 0), (3.5, 20, 3), (20.5, 20, 3), (20.5, 12.5, 0)], closed: false)
    pen.shape([(3.5, 12.5, 0), (8.3, 12.5, 0), (9.8, 15, 0), (14.2, 15, 0),
               (15.7, 12.5, 0), (20.5, 12.5, 0)], closed: false)
    // dot (12, 8.3) r 1.7 — the thing dropping in
case .area:                       // a box your things are filed into (was four squares,
                                  // the same drawing as All workspaces)
    pen.shape([(12, 3, 1.6), (19.8, 7.5, 1.6), (19.8, 16.5, 1.6), (12, 21, 1.6),
               (4.2, 16.5, 1.6), (4.2, 7.5, 1.6)], closed: true)
    pen.shape([(4.46, 7.65, 0), (12, 12, 0), (19.54, 7.65, 0)], closed: false)
    pen.line(12, 12, 12, 20.7)
case .person:
    pen.circle(12, 8.3, 3.8)
    pen.shape([(4.8, 20, 0), (4.8, 14.5, 4.5), (19.2, 14.5, 4.5), (19.2, 20, 0)], closed: false)
case .trash:
    pen.line(4.5, 6.5, 19.5, 6.5)
    pen.shape([(9.5, 6.5, 0), (9.5, 4.5, 0), (14.5, 4.5, 0), (14.5, 6.5, 0)], closed: false)
    pen.shape([(6.5, 6.5, 0), (7.4, 20.2, 2), (16.6, 20.2, 2), (17.5, 6.5, 0)], closed: false)
case .settings:                   // a plain cog, and NO hub (owner, 2026-09-29: "shouldn't
                                  // have a circle in the middle and be less coggy", then
                                  // "should still look like a cogwheel")
    pen.gear(12, 12, root: 7.8, tip: 9.8, teeth: 8, rootHalf: 0.22, tipHalf: 0.15, round: 0.6)
    // Eight SQUARE teeth, narrower than today's (0.33 / 0.21 of the pitch)
    // so the gaps stay open at 22pt, with softer corners (0.45 today).
    // `Pen.gear` gains `rootHalf:`, `tipHalf:` and `round:`, defaulting to
    // today's values. The `pen.circle(12, 12, 3.1)` hub goes. Six round
    // teeth were tried first and read as a flower.
case .link:                       // UNCHANGED
    pen.link()
```

The tab key keeps `.day(n)`, the numbered box (owner, 2026-09-29: "the
old open tabs [n] style was better"). It keeps its drawing, `pen.box(3,
3.5, 18, 17, 3.5)`, and its count: centred, bold, 0.46 × size. The only
change is the pen weight every glyph takes.

New cases. The bar's other keys, the properties door and Scan text come
off SF Symbols:

```swift
case compose                      // the bar's +: a note with a plus. Tap makes a note.
    pen.shape([(11.5, 4, 0), (4, 4, 3), (4, 20, 3), (20, 20, 3), (20, 12.5, 0)], closed: false)
    pen.line(18, 2.8, 18, 9.2)
    pen.line(14.8, 6, 21.2, 6)
    pen.line(8, 12.5, 13, 12.5)
    pen.line(8, 16, 11, 16)
case back
    pen.shape([(14.5, 5.5, 0), (8, 12, 0), (14.5, 18.5, 0)], closed: false)
case forward
    pen.shape([(9.5, 5.5, 0), (16, 12, 0), (9.5, 18.5, 0)], closed: false)
case search
    pen.circle(10.5, 10.5, 6.3)
    pen.line(15.2, 15.2, 20, 20)
case properties                   // was slider.horizontal.3, which reads as "adjust"
    pen.box(3.5, 4.5, 17, 15, 3)
    pen.line(7, 9.5, 11, 9.5)
    pen.line(7, 14.5, 11, 14.5)
    // dots (15.5, 9.5) r 1.4 and (15.5, 14.5) r 1.4 — the values
case scan                         // was text.viewfinder
    pen.shape([(4, 8.5, 0), (4, 4, 2.5), (8.5, 4, 0)], closed: false)
    pen.shape([(15.5, 4, 0), (20, 4, 2.5), (20, 8.5, 0)], closed: false)
    pen.shape([(20, 15.5, 0), (20, 20, 2.5), (15.5, 20, 0)], closed: false)
    pen.shape([(8.5, 20, 0), (4, 20, 2.5), (4, 15.5, 0)], closed: false)
    pen.line(8, 10, 16, 10)
    pen.line(8, 14, 13, 14)
```

Workspaces are marked with type, not drawings:

- **A workspace** is its first letter: `Text` at 21 semibold in `text`,
  centred in the 24 column. There is no box and no colour.
- **All workspaces** (`.workspaces`) is four filled dots and no strokes:
  diameter 6, centred at (7.5, 7.5), (16.5, 7.5), (7.5, 16.5) and
  (16.5, 16.5). It was four squares, the same drawing `.area` had.
- **New workspace** is a `+` at 21 medium in `text2`, set like a letter.

**The hold tick.** The bar's `+` key (not the glyph) wears a 7pt filled
corner in `text2`, 6 from the key's right edge and 9 from its bottom. In
a 7×7 box its path is `M6 1 V4.5 A1.5 1.5 0 0 1 4.5 6 H1 Z`. It says
"hold for more" without a word.

## Surfaces

### Library panel — `Panel.swift` (option A)

1. **Views**, in `Feature.groups` order: Today · Unsorted, a 12 gap, then
   Notes · Tasks · Calendar.
   - Rows are `LivPanel.row` (52) tall. The glyph is 22 in `text`, the
     label 18 medium, the count 18 `text3`, and the current view is lit.
   - Tasks keeps the ticked box (`.tasks`).
2. **Workspaces**: `SectionLabel("Workspaces")` at the panel inset, 22
   above and 6 below.
   - One row per workspace: its letter and its name. The active one is
     lit with the same fill as the current view, so there are two lit
     rows, one per list.
   - Then **All workspaces** (four dots) and **New workspace** (a `+`,
     with its label in `text2`).
   - **No counts on workspace rows.** A count per workspace needs that
     workspace's id set from the core: a query per workspace per render
     (standing rule 2). The views keep their counts.
   - Long-pressing a workspace row gives the context menu the switcher
     rows carry today: Edit workspace · Trash workspace.
   - New workspace and Edit workspace open the existing form (see
     Deletions).
3. **Foot**, pinned to the bottom.
   - Left: Trash, as a trash glyph at 22 and "Trash" at 18 medium, both
     `text2`. Trash leaves the list.
   - Right: the Settings circle (46, `panel2`, the gear at 22 in `text2`).
   - The workspace block leaves the foot.

The list keeps its fade above the foot and scrolls if it outgrows the
panel.

### Today — `Today.swift`

- **Header**
  - `LivScreenTitle` shows the selected day's WEEKDAY ("Thursday").
  - Its subtitle is the long date followed by the existing area line:
    "24 September · Home 1 · Work 3".
- **Week strip** (`TodayDateStrip` / `LivDayMark`)
  - Weekday letter at 14 medium `text2` (was 16 `text3`).
  - Disc 38, number 18.
  - The selected-today disc is the accent with the number in `canvas`,
    as `LivDayMark` already draws it.
  - New: a 5pt `text3` dot under every day that has something dated on
    it. This reads the dated rows already in memory, in one pass for the
    seven days.
- **Late**
  - A card header: "Late", its count in red, and the fold chevron. The
    fold rule is unchanged (open at three or fewer).
  - Rows: `StatusRing`, title, the anchor as the detail line, and the due
    date as a red relative day ("Tuesday").
  - No per-row verb: the leading swipe moves a task, as now.
- **Schedule** is a new header over the timeline, and the timeline
  becomes one card.
  - All-day items become the first rows, with "All day" in the time
    column. The horizontal pill band goes.
  - The time column is 50 wide. The start time is 16 medium `text`
    (`text2` once passed); the end time, when there is one, sits under it
    at 14 `text2`.
  - Marks: an event wears a 4pt rounded bar in its kind colour, inset 4
    from the row's content edges. A task wears its `StatusRing`.
  - Repeats keep their kind mark. The repeat symbol goes, and "Every
    Thursday" moves into the detail line.
  - Title 18. The detail line is anchor · people ("Work · with Mira").
  - The hairline starts at the title column (78 into the card).
  - **Now line**: a 9pt accent dot at the time column's edge and a 1.5
    accent rule across the card at the current time. It was an accent
    time label and a 1pt rule.
  - Passed rows draw their title in `text2`.
- **What next**: a header, then a card of rows (`StatusRing`, title, the
  anchor as the detail line).
- **Done today and "N captured today"** stay, as rows in a last card.
  - "Done today": a filled done ring, the count and a chevron.
  - "2 captured today": the Unsorted glyph and a chevron, opening
    Unsorted. It was a footer with a "Route them" pill.
  - Both sit below the fold, so the mockup does not show them.
- An empty day keeps its `EmptyHint`.

### Unsorted — `Inbox.swift`

- `LivScreenTitle("Unsorted")`, with the subtitle "6 things without an
  area". It was a label row.
- The bulk verb sits under the title as an `AddChip` with a tick: **"File
  3 by their guesses"** (was "Accept 3 guesses").
- One card of rows, newest first:
  - The kind glyph at 22 `text2`, and the title at 18 over up to 2 lines.
  - The detail line is the kind word · the relative time ("Note · 09:41",
    "Task · Tuesday").
  - Trailing is the clerk's guess as an `AddChip` with the area cube:
    "Home?". Tapping it files the thing, as now. Rows with no guess have
    no trailing control.
- Tapping a row opens the route card, and the Trash swipe stays, both
  unchanged.
- Suggestions: a "Clerk suggests" header and a card, rows restyled to the
  one row. Their ✓ and ✕ controls are unchanged in this pass.

### Tasks — `Tasks.swift`

- `LivScreenTitle("Tasks")`, with the subtitle "6 open · 2 late".
- **Filters**
  - A `LivSegment` for status: All, then each status option (the default
    vocabulary has two or three).
  - Beside it, `AddChip("Project")` with a chevron. It opens a menu of the
    projects the chip row lists today (`distinctValues(property:
    "project")`), plus "All projects".
  - This replaces the `LivFilterChip` row.
- **The add row** becomes the first card: the compose glyph in `text2`,
  the "New task" field (18, placeholder `text3`), and
  `ConfirmPill("Add", compact:)` while typing, as now.
- **Groups**: a card header with the status name and its count (18
  `text2`), plus a red "2 late" on the right. Then a card of rows:
  `StatusRing`, title, the anchor as the detail line, and the due date as
  a relative day (red when late).
- **The completing group (Done)** becomes a one-row card: a filled done
  ring, "Done", the count and a chevron. Tapping it unfolds the rows, as
  the header toggle does now.
- **In notes**: a header with its count. Each row has a `StatusRing`, the
  line's text, and "In ⟨note title⟩" as the detail line, which replaces
  the ↗ source chip. The ring toggles the line; the row opens the note.

### A note — `EditorText.swift`, `Editor.swift`

- Gutter 20. The title is `hero` 34 bold, with 18 below it.
- The body is 18 on a 27 line.
  - A blank line is still a full line.
  - Headings: h1 24 bold, h2 20 semibold, h3 18 semibold, each with 6 of
    paragraph spacing above.
  - Markers keep today's behaviour: visible on the caret's line only.
- The checkbox is 20 (radius 6, 1.7 line in `text2`). When checked it
  fills green (the Done hue) with a white tick; today it fills with the
  accent. Checked text stays `text2` with a strikethrough.
- The list gutter is 30, and the bullet dot grows 5 → 6 (`text2`).
- Links stay accent: the only clickable text.
- The grabber and doors stay as now. The properties door wears
  `.properties`.

### Properties — `Detail.swift` (`EntityInspector` in its sheet)

- **Header**: the name at `display` 26, now **bold** (was semibold).
  Under it, a 16 `text2` line: the kind word · "edited today 21:04".
- **Rows** sit in Settings-style cards: `panel2` cards on the sheet's
  `surface`, radius 22, 16 inset.
  - The label is 18 regular in `text`, the value 18 in `text2`, then a
    chevron (14 `text3`).
  - An empty value reads "None" in `text3` (was "—").
  - Card 1 holds Due, and Status when the kind has one.
  - Card 2 holds Area · Project · Subject · People, using the
    `PROPS.reads` words. People's values wear the person glyph (16).
  - Values are plain text, with no `ValueChip(big:)` capsules.
- **Links**: `SectionLabel("Links")`, then a card.
  - Each link is a row: kind glyph in `text2`, title, a detail line
    ("Linked here" or "Typed in the note") and a chevron. The ✕ on a
    removable link stays as its trailing control.
  - The last row is "Add link" with a plus glyph. A row is the house
    rule's first shape.
  - "Show all N" stays an `AddChip`.
- **Footnote** under the cards: "Created Monday 14 September at 21:04" at
  14 `text3`.
- Suggested rows keep their behaviour and become rows in a card.

### The bar and the doors — `Bar.swift`, `Desk.swift`

- The three glass pieces stay. The keys draw with the app's pen:
  `.back`, `.forward`, `.search` and `.compose`. The tab key keeps
  `.day(n)`, the numbered box.
- `+`: a tap makes a note and a hold opens the create menu, both as now.
  The key wears the hold tick.
- The tab key's accessibility label is "N open notes".
- Document doors: Properties wears `.properties`. The ••• door is
  unchanged.

### Hold + — the create menu (`Desk.swift`)

- It is the same `LivMenu` card, rising from the bar, titled "New" at 16
  medium `text2`.
- Rows: Note, with the detail line "Tap + for this one"; Task; Event;
  File; Scan text, which takes `.scan`.
- Every glyph is in `text2`.

## Deletions (standing rule 6)

- **The list half of `WorkspaceSwitcher`** goes: the All row, a row per
  workspace, the "New workspace…" row and `choice`. The panel lists the
  workspaces now.
  - Keep the FORM: `composing`, the name field and the lens pickers.
    Present it straight from New workspace and Edit workspace; renaming
    it `WorkspaceForm` would say what it is.
  - `DeskModel.workspaceShown` then means "the form is up".
- The panel foot's workspace block, and `ViewCounts.foot`.
- `LivGlyph.workspace` (the r8 circle), if nothing else still draws it.
- `LivFilterChip`, whose only caller is Tasks.
- The timeline's anchor `ValueChip`s, Today's all-day pill band, and
  Tasks' ↗ source chip.
- The SF Symbols in the bar, in the properties door, and in the create
  menu's Scan text row.

## Not in this pass

Calendar (month and day), Search, Settings, Trash, the record card, the
tab switcher, the share extension, and light mode as its own review. The
rules above apply when each of these comes up.

## Open for the owner

1. **A workspace's emoji.** Workspaces can carry one. The mockup draws the
   letter, because icons are ink now. Keep the emoji field in the form, or
   drop it?
2. **The full stop on screen titles** is the boldest personality touch.
   It is easy to drop, and the dot in the icons and the now line would
   carry the signature alone.
3. **Rows at 52 / 64** (were 56). The cards want it. The owner has asked
   for both density and size.
4. **Status segments when a vocabulary has more than three statuses.** A
   segment gets cramped past four. A fallback could be the old chip row.

## Verify

- `shell/ios/build.sh`, then `shell/ios/suites.sh`.
  - The glyph suite (`livGlyphSelfCheck`, `GlyphSheet`) and
    `livPaletteSelfCheck` will need their fixtures updated for the new
    cases and the dot layer.
  - Break one assertion on purpose and watch it fail before trusting the
    green.
- `shell/ios/drive.sh`:
  - `tour`: every view still renders.
  - `panel`: both panels' geometry, since the rows and the foot changed.
  - `bar`.
- **`drive.sh workspace` must be rewritten.** It taps "Switch workspace"
  at the panel's foot and expects a card with a "New workspace" row.
  - The new check asserts that the panel itself lists the workspaces (a
    "New workspace" row is in the panel).
  - It then asserts that tapping that row raises the form
    (`LivOverlay.workspace`).
- Look at light mode with your own eyes. The palette pairs are unchanged,
  but the new shapes are not.
- Put each screen beside its board in `design/mockups/clearer.html`.

## Suggested order

1. Tokens, the `LivIcon` dot layer and the glyphs, as one slice. The
   glyph sheet shows them all at once.
2. `LivListRow` (the detail line), the card header, `LivScreenTitle`,
   `StatusRing`, `AddChip`, `LivSegment`.
3. Panel A, the workspace list and the form-only switcher, together with
   `drive.sh workspace`.
4. Today · Unsorted · Tasks.
5. The editor · Properties · the bar and doors · the create menu.

For each slice: build, run the suites, run the drive checks it touches,
and look at the simulator.
