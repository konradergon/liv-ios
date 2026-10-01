# Liv UI Map — the replication spec for the lotus port

> **Status:** 1.0 — synthesized 2026-07-06 from eight area specs mined from the Liv
> source (`~/src/friend-fixes`, Tauri/React/TS/SQLite, ~130k lines), each verified
> against code, not docs. This document is the **interface spec of record** named by
> `interface.md` §0.3. It reports what the CODE does; where docs and code disagree,
> the disagreement is flagged inline and collected in §6.
>
> Owner's directive: *"replicate the entire Liv UI as closely as possible in SwiftUI,
> and all of the features (markdown editor, templates, daily note, calendar, all
> different metadata, everything) precisely."*
>
> Reading rules:
> - Source references are `path:line` inside `/Users/k/src/friend-fixes` — for
>   re-checking details, never for copying code.
> - Colors are given as Liv's token roles (`primary`, `panel`, `secondary`,
>   `destructive`, `warning`, …). The ONLY intended visual divergence: **accent →
>   lotus lake green `#2f7d6b`**; otherwise system materials, SF Pro, SF Symbols
>   (see §3). Structure, geometry, and behavior replicate exactly.
> - Sizes are px from Tailwind classes (`h-9` = 36px, `w-72` = 288px, etc.).
> - "Mod" = Cmd on macOS. Liv shortcut labels render as glyph runs on mac (⌘⇧B).
> - ⚠ marks decided-dead-but-still-shipping code and doc↔code deltas.
> - §4 states where the truth underneath changes (lotus core: append-only log,
>   entities+cells, commands, proposals) while the UI stays identical.

---

# 1 · WINDOW ANATOMY

The whole shell is composed in one file, `src/routes/__root.tsx` (2,978 lines).

## 1.1 The window

- Base window (`src-tauri/tauri.conf.json:14`): single window "main", title "Liv",
  **1100×740**, frameless (`decorations:false`), OS drag-drop disabled (HTML5 DnD
  in-page). **macOS override** (`tauri.macos.conf.json`): `decorations:true,
  titleBarStyle:"Overlay", hiddenTitle:true` — native traffic lights overlay the
  app's top-left; the app reserves a **72px** left spacer in the title row
  (`__root.tsx:2429–2431`), dropped when fullscreen (tracked via `window.onResized`
  → `isFullscreen`, `__root.tsx:800–825`). ⚠ A second code path (`:2492`) uses a
  28px spacer for the (dead) reorderable-rows branch; 72px is the live value.
- **Multi-window** (`src/lib/windowing.ts`): "Open in new window" (tab/workspace
  context menus) spawns a real OS window labeled `liv-<timestamp>-<n>`, 1100×760,
  native decorations, URL hash `#/?workspace=<id>&tab=<id>&extension=<id>`; boot
  reads `readWindowScope()` and pre-selects workspace/tab. All windows share the
  vault + localStorage; siblings showing the same workspace sync live over
  `BroadcastChannel("workspace-state")`.

## 1.2 Vertical structure (top → bottom, `__root.tsx:2420–2973`)

```
┌──────────────────────────────────────────────────────────────────────┐
│ TITLE ROW  h-9 (36px)  — menu · window-centered search · win ctrls   │ ← full window width
├───┬──────────────────────────────────────────────────────────────────┤
│ A │ DEPARTMENTS/TABS ROW h-9 — HomeHub · tab strip · (win controls)  │
│ c ├──────────────────────────────────────────────────────────────────┤
│ t │ BOOKMARKS ROW h-8 (32px) — SlotsBar chips                        │
│ i ├───────────────┬───────────────────────────────┬──────────────────┤
│ v │ LEFT SIDEBAR  ║  SurfaceHeaderSlot (portal)   ║                  │
│ i │ (AppSidebar)  ╟───────────────────────────────╢  RIGHT SIDEBAR   │
│ t │ 18% default   ║  CENTER: main pane [+ up to   ║  30% default     │
│ y │ min 8 max 60  ║  4 split panes side-by-side]  ║  min 10 max 50   │
│Bar│ collapsible→0 ║  center min 30%               ║  collapsible→0   │
│44px──────────────┴───────────────────────────────┴──────────────────┘
```

- **Title row** — h-9, `border-b border-border bg-background`, px-2; the whole row
  is an OS drag region (`data-tauri-drag-region`; Tauri checks the exact mousedown
  target, so every nested empty container repeats the attribute). Left→right: mac
  traffic-light spacer → **MenuBar** (in-window; on macOS replaced by
  `NativeAppMenu`, which renders nothing and installs system menus) →
  **HeaderSearch**, absolutely centered on the *window* (a pointer-events
  pass-through overlay, not flex leftover space, `__root.tsx:2437–2441`) → flex
  drag region → **WindowControls** (non-mac only).
- **Departments/tabs row** — h-9, `border-b border-border bg-panel`,
  `items-stretch`, drag region on empty pixels. Left: **HomeHub** (workspace hub,
  §2.7.2 — founder call: it lives on the tab row, not the title row). Then the tab
  strip: `GlobalTabBar` when the active workspace's `layoutMode === "unified"`,
  else `DepartmentNav`. On a vault-wide tool surface (`hideNoteChrome`) the strip
  is replaced by a bare drag region. ⚠ Intended "tab melt" (no border under the
  active tab, approved mockup 02) is NOT achieved — the shipped row still draws
  `border-b border-border` (§6).
- **Bookmarks row** — h-8, `border-b`, `bg-background`, px-2, hosts **SlotsBar**
  (§2.4). This row and the tabs row hide in **focus mode** and on any vault-wide
  tool (`__root.tsx:2567–2574`).
- ⚠ **Row order is hardwired** title → tabs → bookmarks. The user setting
  `layoutSettings.chromeRowOrder` (default `["search","bookmarks","departments"]`
  with a legacy migration, `src/lib/layoutSettings.ts:40,117,164–189`) is read into
  state (`__root.tsx:661–666`) and exposed in Settings → Layout as reorderable
  cards, but the render **ignores it**. Reconciliation: replicate the hardwired
  order; the setting is dead chrome (§6). The "whichever row renders first owns the
  window controls" machinery (`isFirst`, `__root.tsx:2472–2559`) exists for the
  dead branch.

## 1.3 Activity bar (left icon rail) — `src/components/shared/ActivityBar.tsx`

- **w-11 (44px)**, full height BELOW the title row (VS Code style), `border-r`,
  `bg-panel/90 backdrop-blur-sm`, `py-2.5`, 6px item gap.
- A single **GlidingIndicator** pill (`bg-primary/10 shadow-elev-1` rounded-lg + a
  2px×16px primary bar at the left edge) *slides* between icons on selection on
  the motion tokens instead of teleporting (ActivityBar.tsx:200–207).
- Top → bottom:
  1. **Back / Forward** chevrons (18px-wide buttons, h-6), tooltips "Back (Alt+←)"
     / "Forward (Alt+→)", disabled (`/20` opacity) when the merged history can't
     move (§2.6). Divider under them.
  2. **Notes** (altitude "focused" — inside a workspace).
  3. 1px divider — the "altitude seam", drawn wherever altitude changes
     (ActivityBar.tsx:239–244).
  4. **Chats** (`ai-chat`) — amber `warning` count badge = pending AI-Assist
     suggestion count (cap "99+"), same engine as the Assist panel.
  5. **Tasks**, **Library**, **Inbox** (primary count badge = vault-global
     unfiled/orphan count, cap "99+", tooltip "N unsorted objects in the inbox"),
     **Contacts**, **Calendar** — all altitude "ambient" (vault-wide tools).
     Badge spec: absolute top-right (−2px offsets), h-4 min-w-4 rounded-full,
     11px bold; counts refresh debounced 50ms on
     `workspace-change`/`notes-changed`/assist-changed.
     ⚠ *Messages* and *Finances* stubs were removed from the rail (IA-8) but stay
     in the `ExtensionId` type; `ExtensionStub` renders "Coming soon." if ever
     activated.
  6. Flexible spacer.
  7. **Project pin** (FolderOpen): lit `bg-primary/15 text-primary` + a bottom-
     right 8px primary dot when a project is pinned. Opens a portaled menu to the
     RIGHT of the rail, bottom-aligned (z-140/141): header "PIN PROJECT", an
     "× Show all" row, then the deduped project list from the active workspace's
     notes. A pin is explicit and survives workspace switches
     (`markManualProjectPin`); without a pin the active-project scope follows the
     workspace's projectTag/name (`WorkspaceScopeBridge`, `__root.tsx:140–172`).
  8. **Browse extensions** (Puzzle) — ⚠ visually present, does nothing.
  9. **Light/dark toggle** (Sun/Moon).
  10. **Settings** (gear) — dispatches `open-settings`.
- Button spec: 36×36 rounded-lg; rest `text-muted-foreground/70`, hover
  `bg-secondary/70` + foreground, active `text-primary` + icon scale-105.
- Icons: monochrome lucide-wrapped glyphs (`ACTIVITY_ICONS`,
  `src/components/icons/NavIcons.tsx`), inheriting `currentColor` (§3.5).

## 1.4 Extension (surface) model

- `ExtensionId` = notes | explorer(⚠ dead, migrates→notes) | capture | tasks |
  library | inbox | contacts | calendar | messages | finances | ai-chat. The
  active extension is **app-global, not per-workspace**, persisted at
  `app.activeExtension.v1`; switching workspace never changes the tool
  (`__root.tsx:687–689,937–991`).
- `GLOBAL_TOOL_EXTENSIONS` = {tasks, library, inbox, contacts, calendar, messages,
  finances, ai-chat} (`__root.tsx:314–323`). Entering one:
  - force-collapses the LEFT panel to 0 and hides `AppSidebar` entirely (the tool
    goes full-bleed with its own inner sidebar; `__root.tsx:782–796, 2684–2716`);
    the left drag handle hides too;
  - hides the tabs row + SlotsBar (`hideNoteChrome`) — EXCEPT in unified mode when
    the active global tab itself HOSTS that surface (a Tasks/Library container
    tab), where the strip stays (`__root.tsx:786–796`);
  - the right inspector stays;
  - the forced collapse is never recorded as the user's sidebar preference
    (`surfaceIsVaultWideRef` guard).
- Pane bodies (`__root.tsx:2786–2827`): notes → router `<Outlet/>`; capture →
  CaptureExtension; tasks/library/inbox(Processor)/contacts/calendar/ai-chat →
  lazy-loaded extensions; anything else → `ExtensionStub` (icon at 10% opacity,
  label, "Coming soon.").
- Switching extensions cross-fades via the View Transitions API (`flushSync`
  inside `startViewTransition`), instant under `prefers-reduced-motion`, with a
  rollback guard so a thrown transition can never wedge the surface
  (`__root.tsx:955–991`). The main pane container is keyed by
  `activeExtension:activeGlobalTabId` and replays a `.view-enter` fade + 4px rise
  on every switch.
- Right-click: the native WebView context menu is suppressed EVERYWHERE except
  inputs/textareas/contenteditable/`.cm-content` (`__root.tsx:1203–1213`).

## 1.5 Resizable panels & persistence

- Widths persist as percentages: `app.layout.panes.v4` `{left:18, right:30}`
  default; persisted clamps left ∈ [8,55], right ∈ [8,48], center ≥ 30
  (`src/lib/paneLayout.ts`); the live panels allow left maxSize=60, right
  minSize=10 maxSize=50 (both collapsible to 0). The right panel's live max is
  dynamically capped at `min(50, 100 − 30 − liveLeftWidth)` so a right-handle drag
  can never cascade into and shrink the left sidebar (`__root.tsx:744–763`).
  Split-pane widths persist per pane id in `app.layout.splitPanes.v1`.
- The **SurfaceHeaderSlot** sits full-width ABOVE the [center | right] pair:
  surfaces portal their own tab/control bar into it so the right inspector flanks
  only the object, never the surface's tab bar (`__root.tsx:2718–2730`,
  `SurfaceHeaderPortal`).
- Panel collapse state syncs two-way with `sidebarOpen`/`rightPanelOpen` booleans
  (`__root.tsx:831–848`); right-panel open state persists at
  `app.rightPanel.open.v1`; first-launch defaults from Settings → Layout
  (`leftSidebarCollapsedByDefault`, `rightSidebarCollapsedByDefault`). Any code
  can open the right panel by dispatching `toggle-right-panel {open:true}`.

## 1.6 Focus / Zen mode

- Toggle **Mod+.** (`app:toggle-focus`); Escape also exits when no overlay is open
  (`__root.tsx:1493–1519`).
- Hides: title row (→ an h-2 drag strip), activity bar, tabs row, SlotsBar, both
  sidebars (their prior open states are stashed and exactly restored on exit,
  `toggleFocus`, `__root.tsx:2377–2395`).
- A floating chip appears fixed top-right: rounded-full, `bg-panel/90` blur,
  Minimize2 icon + "Exit focus", tooltip "Exit focus mode (Ctrl+.)".

## 1.7 Canonical overlay z-stack (`__root.tsx:2403–2419`)

50 in-tree dropdowns · 60 quick switchers/launcher (+ suggestion toasts) ·
80 confirm modals · 99 Mission Control · 100 wizards/AddToListMenu (tab context
menus 100/101) · 120 command palette, ArchiveView, DriveBrowser · 140/141
tab-strip pickers (+ LinkSaveOverlay at 140) · 142/143 save-tab-group form ·
150/151 nested strip menus + toasts, WorkspaceSwitcher, QuickAddTask, Settings,
TemplateGenerator, MeetingNoteOverlay · 195 FirstRunWizard · 200 DialogHost /
NoteOverlay (always on top). Strip dropdowns must be fixed-positioned from
`getBoundingClientRect` anchors (or portaled to body) because the h-9/h-10 strip
lanes are overflow-clipped. Escape priority: Mission Control → other overlays →
focus mode.

---

# 2 · SURFACES

Ordered by Liv's own structure: chrome pieces first, then the left rail's
extensions in rail order, then right-panel content, then overlays and
cross-cutting interaction systems.

## 2.1 Title row pieces

### MenuBar (in-window; Windows/Linux/web) — `src/components/shared/MenuBar.tsx`
- Sits top-LEFT of the title row. Menu labels are 11.5px medium buttons (px-2.5,
  full row height); open state `bg-secondary/60`; **mousedown** (not click)
  toggles; hovering another label while one is open switches to it; Escape or
  outside-click closes. Dropdown: portaled fixed at label rect bottom+4, w-56
  rounded-md border `bg-popover` py-1 `shadow-elev-2`; items 12px rows (px-3
  py-1.5) with right-aligned faint shortcut text; separators `h-px bg-border/70`.
- **File**: New note (Ctrl+N → `file-explorer:new-file`) · Daily note (Ctrl+Alt+D
  → `daily:open-today`).
- **View**: Home (switch to built-in Home workspace) · Dashboard (Shift+Tab →
  dispatch `liv:toggle-dashboard`) · Inbox (switch extension) · ─ · Search
  (Ctrl+O → `switcher:open`) · Command palette (Ctrl+P → `command-palette:open`).

### Native macOS menu — `src/lib/nativeMenu.ts` (mounted by `NativeAppMenu.tsx`)
System menu bar: **Liv** (Hide / Hide Others / Show All / ─ / Quit — predefined
items, standard ⌘ accelerators) · **Edit** (Undo/Redo/─/Cut/Copy/Paste/Select All
— predefined) · **File** (New Note, Daily Note) · **View** (Home, Dashboard,
Inbox, ─, Search…, Command Palette…). Custom items deliberately carry **no
accelerators** — the app's own keydown handling owns shortcuts; a native
accelerator would double-fire.

### HeaderSearch — `src/components/shared/HeaderSearch.tsx`
A button styled as a field: h-7, max-w 560px, rounded-md,
`border-border/70 bg-secondary/40`, 12.5px text, leading Search glyph (14px,
tints primary on focus), label `Search {activeWorkspaceName}` (falls back to
"Search"), trailing kbd chip "Ctrl+O" (10.5px mono). Click runs `switcher:open`
(QuickSwitcher, search mode). Tooltip: "Search (Ctrl+O) — type > for commands".

### WindowControls (non-mac) — `src/components/shared/TitleBar.tsx`
Three borderless buttons, each **48px wide** (w-12), full row height, icons
20/17/20px, `text-muted-foreground/80`, hover `bg-secondary/60`: Minus
(minimize), Square (toggleMaximize), X (close; hover `bg-destructive` + white
glyph). Tauri window API; no-op on web.

## 2.2 Left sidebar (AppSidebar) — `src/components/shared/AppSidebar.tsx` (3,056 lines)

Rendered only on non-vault-wide surfaces. Fades opacity 0↔1 over 200ms as the
panel collapses/expands (width owned by the ResizablePanel). No right border —
the drag handle is the boundary.

### 2.2.1 View picker strip (AppSidebar.tsx:2755–2806)
Pinned **h-10** row of full-width segmented boxes (its bottom border aligns with
the center tab strip and the right rail's view tabs — one continuous rule).
**Five views** (icon above an 11px label; full name in tooltip):

| id | label | tooltip | body |
|---|---|---|---|
| `tree` | Spaces | Workspaces | workspace hierarchy (default) |
| `vault` | Vault | Vault | on-disk folder tree |
| `properties` | Props | Properties | property/tag browser |
| `bookmarks` | Saved | Bookmarks | vault-wide starred objects (`BookmarksPanel`, reads `metadata.bookmarked`) |
| `graph` | Graph | Vault graph | whole-vault metadata graph (`VaultGraphView`) |

The `SidebarView` type still contains `"tags"`; the dedicated Tags tab was folded
into Properties and a persisted `"tags"` default coerces to `properties`
(AppSidebar.tsx:2112–2124). Default view from Settings → Layout `defaultLeftView`
(default `tree`). ⚠ IA-2/IA-4 ("cut Props, fold Saved into Spaces" → 2 tabs) is
approved but NOT implemented — code ships 5. ⚠ Settings lists the options as
"Workspaces/tree · Vault · Tags · Properties" (stale: no Saved/Graph, dead Tags).

### 2.2.2 Spaces (tree) view
- **Filter box** at top: search glyph + "Filter…" input (border-b row). Filters
  tree nodes by name (self or child match); non-matching rows simply vanish (no
  message).
- **Groups**, top → bottom (AppSidebar.tsx:2838–3016):
  - **Favourites** — starred workspaces. Home is favourite BY DEFAULT
    (`favorite === undefined` on the home built-in counts as true). Rows are
    `WorkspaceListItem`s.
  - **Spaces** — top-level tree nodes (areas) with a live (non-archived)
    workspace anywhere in their subtree; expandable parents. The "Spaces" header
    is a drop target: dropping a flat workspace onto it promotes it to a
    standalone space.
  - **Boards** — standalone workspaces with no sub-spaces + legacy non-Home
    built-ins; separated from Spaces by a divider. The "Boards" header accepts a
    dropped tree node to pull it back to top level.
  - Inline `New workspace…` input row while creating.
  - **Archive** — collapsed-by-default group at the very bottom (chevron header
    "Archive · N"). Rows dimmed; click does NOT navigate; hover button +
    right-click menu = *Restore workspace*.
- Footer button (border-t): `+ New workspace` → inline input (`InlineInput`:
  Enter commits, Escape cancels, blur cancels on create / commits on rename) →
  `createBoundWorkspace` (§2.7.4).
- **VaultSwitcher** pinned at the very bottom (§2.7.5).
- ⚠ A `GlobalZone` component (Home / Today / Inbox jump buttons,
  AppSidebar.tsx:2069–2106) is **never rendered** — those jumps moved to the
  MenuBar View menu. Dead-but-shipping.

### 2.2.3 Tree rows (`TreeItem`, AppSidebar.tsx:502–926)
- Indent = depth×12px. Row anatomy: chevron (w-4; expand/collapse only; blank
  spacer if leaf) · glyph · name button (13px, flex-1, truncate; parents
  `font-medium`) · AI-Assist head · hover actions.
- Glyph rules: workspace emoji if set (opt-in override, 15px); else
  parent-with-children → colored `FolderGlyph` (open when expanded) tinted with a
  **stable per-workspace accent** (FNV hash of id into a 10-hue palette,
  AppSidebar.tsx:261–282); else leaf → duotone dashboard glyph in the accent.
- Click name = enter the workspace (activates + navigates to "/"); a tree node
  without a workspace **auto-creates one** on first click
  (AppSidebar.tsx:2395–2415). Active row = `nav-active`; the whole row shows a
  soft **amber attention ring** (`assist-attention-inset`) while AI suggestions
  target its workspace (§2.23.6).
- **AI-Assist head** (`WorkspaceAssistHead`, AppSidebar.tsx:336–411): an
  always-visible amber Bot glyph + count pill (cap "9+") when the workspace has
  pending suggestions. Click (doesn't bubble) jumps to the Assist view;
  hover/focus opens the shared attention popover (one-line WHY + "Show
  suggestion" expanding to real Assist cards).
- Hover actions (visible on hover, or while a menu/emoji picker is open): `+` add
  child (label follows hierarchy: area→"project"→"sub-project"→"folder"), `⋯`
  actions menu (portaled fixed, w-40, z-80): *Change emoji* (EmojiPicker with
  clear) · *Rename* · *Open in new window* (`openInNewWindow` with workspace
  scope) · *Archive workspace* (non-built-in) · *Delete workspace* (destructive;
  confirm warns "N child workspaces will also be deleted. This cannot be
  undone."). Right-click on the row opens this same menu.
- Rename keeps the bound workspace's `name` AND `projectTag` in lockstep
  (AppSidebar.tsx:2477–2505). Sibling names dedupe Obsidian-style ("Name 2",
  "Name 3").
- Creating a `project`/`subspace` node prompts *"Create a workspace for "X"?"* —
  yes mints a workspace with `projectTag = name` and opens it
  (AppSidebar.tsx:2432–2474).
- **Drag & drop** (whole row is the drag source; no grip): payload types
  `application/liv-tree-node-id` and `application/liv-workspace-id`. Drop zones
  by cursor Y: top 28% = before, bottom 28% = after (2px primary insertion line
  with a dot cap), middle = into (inset primary ring; re-parents, re-types the
  node to match its new parent, cycle-guarded). Dragged row dims to 40%. Dragging
  a flat workspace onto the tree lazily creates a node for it (promotion). Flat
  rows (`WorkspaceListItem`) drag-reorder the persisted workspaces array
  (before/after halves).
- `WorkspaceListItem` context menu (w-48): Open · Add/Remove favorites (star) ·
  ─ · Add child workspace · Make top-level space · Archive workspace · Delete
  workspace (destructive). Hover buttons mirror: promote (FolderTree), add child
  (+), archive, delete.

### 2.2.4 Vault view (`VaultView`, AppSidebar.tsx:1249–1664)
- Filter box, then a lazy folder tree of the REAL on-disk vault (children loaded
  per expand). Live-refreshes from the Rust vault watcher with 250ms
  per-directory debounce + a pathless `vault-files-flushed` fallback that
  re-reads every loaded dir. (§4: in lotus this becomes the import/export
  staging view — no watcher, no mirror.)
- Row: chevron (dirs only) · FolderGlyph / `FileTypeIcon` by extension · name.
  Empty dir shows an indented italic "empty"; empty vault → "Vault is empty."
- Opening a file: `.md/.markdown/.txt` → resolve or mint a Note (frontmatter
  parsed) and open in Composer; `.canvas` → a Composer canvas tab; `.base` → the
  Files surface's Base view (`files-open-base` → `lists-open-base`);
  `.url/.webloc` → extract URL → browser tab; other files → a Composer file tab
  typed by extension (spreadsheet/document/etc.).

### 2.2.5 Properties view (`PropertiesView`, AppSidebar.tsx:1759–2026)
- Filter box ("Filter properties…", debounced). Body lists every property key —
  built-ins (kind, project, area, type, tier, tags, people, active, source,
  sourceRef, date, "cal title", description) plus discovered custom keys — as
  clickable section headers `key (totalCount)`, each followed by value rows
  `value  count`, sorted by count desc, capped at 140 values ("N more values.
  Type to narrow."). Empty states: "No properties yet." / "No properties match."
- Clicking a key or value opens a **drilldown results section** at the panel
  bottom (max 45% height, border-t): header `key [value] (n)` + close ×; rows =
  object leaves (colored `KindIcon`, title, kind label right-aligned). Contract:
  **single-click focuses** (metadata in right rail), **double-click opens**,
  **Ctrl/Cmd-click opens in new tab**. Tags browsing lives here (the "tags"
  property). Drilldown empty state: "No objects."

## 2.3 Tab model — unified strip (the TARGET per D18)

Per D18/C3-C the `departments | unified` split is decided-dead: replicate
**unified** as the shipping model. ⚠ Code still defaults `layoutMode` to
`"departments"` (`__root.tsx:693,999`) and still renders `LayoutModeSwitcher`
(HomeHub + Home + per-workspace settings) — migration debris; §2.3.7 documents
departments mode since it is live.

### 2.3.1 Data model
- `GlobalTab` = `{id, name, deptType, subType?, groupId?, paneTabIds?}`
  (`src/lib/notes.ts:316`). Persisted per workspace (`globalTabs`,
  `activeGlobalTabId`, `tabGroups`, `splitTabIds`).
- `GlobalTabDeptType` = blank | composer | explorer(⚠ dead) | files | capture |
  dashboard | chat | tasks | library | processor | import | export.
- **DEPT_DEFS catalogue** (`GlobalTabBar.tsx:80–176`) — label / icon /
  defaultName / creatable sub-types:
  - Blank ("New view").
  - **Editor** (`composer`, default "Note") — Note, Canvas, Table (`excel`),
    Kanban, Word document, Web (`browser`).
  - **Files** (default "View") — View (`home`), Folder, List — mirrors the Files
    surface modes exactly.
  - Quick Capture; Dashboard; AI Chat ("New conversation"); **Tasks** (ONE
    creatable "Task list" — List/Board/Schedule are in-surface views, not tabs);
    Library; Note Processor; Import; Export.
- **Routing is data-driven** through `ObjectRef.kind` (`src/lib/tabObject.ts`
  `refFromGlobalDept` → `TAB_KIND_TARGET`, `__root.tsx:476–495`): each kind maps
  to {activity-bar extension, router route, optional split-pane component}.
  note→notes:"/", dashboard→"/dashboard", chat→"/chat", processor→"/processor",
  import→"/import", export→"/export", view/folder/list→"/files",
  capture/tasks/documents→their extensions + pane renderers. Activating a
  composer/blank tab fires `composer:ensure-blank-tab` (double-fired at 0ms/75ms,
  idempotent) carrying the subType; a files tab fires `files-open-mode` the same
  way (`activateGlobalTab`, `__root.tsx:498–547`).
- `tabObject.ts` also defines the universal dedup:
  `getTabObjectRef`/`findTabForObject` — "focus the tab already showing this
  object, else create one"; blank refs never dedup.

### 2.3.2 GlobalTabBar strip (`src/components/shared/GlobalTabBar.tsx:1015–2120`)
Layout: an h-10 lane; the scrollable strip (`overflow-x-auto`, no scrollbar,
gap-1, px-2, drag-region on empty space) holds **group bands → loose tabs → a
sticky trailing control cluster** that pins to the right wall when overflowing
(bg-panel so scrolled tabs pass behind).

**Tab pill anatomy** (`renderTab`, :1307–1499). Shared `TAB_BASE` spec
(`src/lib/tabStyles.ts`): h-9 flat square tab, `border-r border-border/40`,
px-2.5, 12px medium tracking-tight; ACTIVE = page-surface `bg-background` + an
inset 2px `primary` bar along the TOP edge (no layout shift; flows into content
— the "melt", see §1.2 ⚠); INACTIVE = `bg-secondary/25` quiet text, hover
`secondary/50`. Sizing: basis 200px, shrink to a 110px floor, never grow
(Chrome-style left-packing). Contents:
- subtype (or dept) icon 14px @80% opacity;
- name (truncate); double-click → inline rename input (Enter commit, Esc cancel,
  blur commits);
- a tiny uppercase 9px muted **department suffix** inside the pill for
  non-composer/non-blank tabs whose name isn't already the dept label (founder:
  containers must indicate their department, never as a free-floating label);
- **split button** (SplitSquareHorizontal, hover-only; lit primary when split) —
  only on non-active, pane-renderable tabs;
- **close ×** (hover-only; `data-tab-close`) — always present even on the last
  tab (closing the last mints a fresh blank tab, Chrome-style).
- Rings: multi-selected = inset `primary/70` ring; split = inset `primary/40`;
  AI-flagged = amber `assist-attention-inset` (yields to the other two). Hovering
  a flagged tab opens the shared Assist popover (why + "Show suggestion").
- Tooltip = "Group: {name}" when grouped.

**Click grammar** (:1261–1300): plain click = clear selection + activate; Shift =
range from last click (or the active tab) in VISUAL order; Ctrl/Cmd =
toggle-select. While ≥2 selected, a **"Group N"** button appears in the trailing
cluster → prompt "Name this group (N tabs)" → bands them.

**Drag-to-reorder**: HTML5 drag per pill; 2px primary insertion line on the
hovered half; drop emits the full id order (group membership rides on each tab,
so reordering never regroups).

**Chrome-style rapid-close width freeze** (`useFrozenTabStripWidths`, :193–365,
shared with every strip): on a close-button press each cell is pinned to its own
current width so the row doesn't reflow and the next × slides under the cursor;
thaws on real pointer-leave, window blur, or ~800ms after the last press; a
MutationObserver pins newly mounted cells while frozen; while frozen all close ×s
are force-revealed via a strip-level data attribute + CSS
(`[data-tabstrip-frozen] button[data-tab-close] { opacity:1 }`, styles.css:877).

**Trailing cluster** (:1710–1790): [Group N] · **+** (new tab → appends a BLANK
tab; founder-locked: + opens the empty new-tab landing, never instantly mints a
note) · **⌄** (fixed-position `ContainerPicker`: DEPARTMENTS ONLY, header "New
tab" — a pick mints a container named after the department with no subType and
immediately enters inline rename; object kinds deliberately absent — they belong
to the lower Composer strip/landing page) · **FolderPlus** (new **composer**: a
two-step picker — "Mixed · Stack any type under one tab" first, divider, then a
"Single department" list; picking prompts "Name this composer" then
`onCreateComposer` seeds the band + its first tab) · **Layers**
(SavedGroupsMenu).

**Blank-tab landing** (`BlankGlobalView`, `__root.tsx:388–448`; the Composer
renders the live equivalent): centered 80px circular icon, "New tab", three rows
— *Create new note (Ctrl+N)*, *Go to file (Ctrl+O)*, *Choose tab type (All
departments)* → full `DeptPicker` in a modal. A blank tab whose landing
materialises content converts in place to a composer tab (renamed once, never
rewritten after; `liv:global-tab-content`, `__root.tsx:1974–2000`).

**DeptPicker** (`GlobalTabBar.tsx:452–581`): default = flat TYPE-FIRST list
("New tab" header; every creatable subtype under faint department headers).
`scopeDeptType` restricts it to one department's kinds (typed containers).
Workspaces with `newTabMode:"flat"` get one flat list.

**Close semantics** (`closeGlobalTab`, `__root.tsx:2127–2163`): closing the
active tab focuses the RIGHT neighbour, then left (browser/Obsidian standard);
closed/dangling ids are scrubbed from splitTabIds; last-tab close mints a blank
tab and clears splits.

### 2.3.3 Tab groups & composers
- `TabGroup` = `{id, name, color, deptType?}` on the workspace; **8-hue muted
  palette** `GROUP_PALETTE` = #5e86b0 #4f9a94 #72a06a #bda15f #c78a63 #cc7d7d
  #bd82a6 #9287bf, cycled by creation index; legacy/foreign hexes
  deterministically fold into it at render (`displayGroupColor`,
  `src/lib/tabGroups.ts`).
- **Band render** (`renderBand`, GlobalTabBar.tsx:1507–1688): a soft tint band —
  `color-mix(group color 14%, transparent)` — rounded-t-[10px], wrapping a **name
  chip** (rounded-full pill at 90% color mix, dept icon or Layers for
  mixed/plain groups, max-w 120px) + member tabs + a scoped **+**. No
  borders/boxes (design: "colour, not lines"). Chip: click = jump to the band's
  active child; double-click = rename inline; right-click = band menu.
- **Composer** = a group with `deptType`: a named, department-scoped container;
  its + offers only that department's subtypes. `deptType:"composer"` or a plain
  colour group = type-AGNOSTIC parent; when it holds multiple types it renders
  **mixed**: children partitioned by type, each run prefixed by an icon-only type
  hint, Layers head icon.
- Empty composer bands still render (so the first tab can be added); empty plain
  colour groups hide.
- **Tab right-click menu** (:1974–2073): header "TAB GROUP"; every existing group
  with a color dot (check on current); *New group…* (prompt); *Remove from group*
  (if grouped); ─; *Save this group as a group… / Save these tabs as a group…* →
  **SaveTabGroupForm** (cursor-anchored w-64 form, z-142/143: name field,
  "Stashes … N tabs. Reopen them later from the Saved groups menu.", Cancel/Save)
  → toast `Saved group "name"`.
- **Band chip right-click menu** (:1885–1971): color dot + name + count header;
  *Rename…*; *New tab in group* (direct-adds when one subtype, else opens the
  scoped picker); ─; *Close N tabs* (destructive; closes one per macrotask to
  avoid state clobbering, `closeMany` :1174–1181).
- **SavedGroupsMenu** (:815–983): Layers button → portaled dropdown (w-72,
  z-150/151): "SAVED GROUPS" header; empty state "No saved groups yet.
  Right-click a tab — or open its menu — to stash the current tabs as a group.";
  rows = name + "N tabs · 3m ago" relative time, hover rename (pencil, inline
  input) + delete (trash). Clicking a row **merges** the snapshot's tabs into the
  current workspace (`restoreTabGroupSnapshot`, notes.ts:1842) and toasts
  "Restored N tabs". `TabGroupSnapshot` = `{id,name,createdAt,tabs,activeTabId}`
  (notes.ts:1773).
- Toast: fixed bottom-center primary pill with check, fades after ~1.8s.

### 2.3.4 Superspaces & layout snapshots
- `Superspace` = a named saved layout `{name, description?, tabs, activeTabId}`
  in localStorage `superspaces` (notes.ts:404–424). Loading one replaces the
  whole tab set, clears splits, activates its active tab (`superspace-load`,
  `__root.tsx:1949–1966`). The Load UI lives in SettingsModal
  (SettingsModal.tsx:3021–3038). ⚠ `SuperspaceSaveForm`
  (GlobalTabBar.tsx:626–704) is defined but **never rendered** — no in-strip save
  entry exists.
- `workspace:capture-layout` (Mod+Alt+S) saves a whole-workspace-set
  `SavedLayout` named "Workspace YYYY-MM-DD HH:MM" (`__root.tsx:1521–1530`,
  notes.ts:1736); managed in Settings → Saved layouts (§2.25).

### 2.3.5 Split panes (unified mode)
- `splitTabIds` — up to **4** extra panes right of the main pane
  (`MAX_SPLIT_PANES`, `__root.tsx:293`), persisted per workspace (mirrored to the
  deprecated scalar `splitTabId`). Only pane-renderable dept types may split:
  **capture, tasks, library** (`canRenderInPane`, GlobalTabBar.tsx:416–421);
  other ids persisted by older builds are skipped.
- Each split pane (`__root.tsx:2834–2936`): min 16%, default `100/(1+n)` or its
  persisted width; a **mini-tab-bar** header (h-10, bg-background, no border —
  same canvas as content): one pill per pane-renderable global tab (icon + name,
  max-w 100px, selected `bg-secondary/60` + medium) — clicking swaps which tab
  THIS pane shows; picking the main tab closes the pane; picking a tab already
  open in another pane is a no-op. Far right: a close-pane ×. Pane body
  cross-fades (`.tab-body-enter`) when swapped, and mounts the surface inside
  `EmbeddedSurfaceContext=true` so the surface suppresses its own inner tab strip
  (two-tab-row budget). Fallback body when content can't render: "Switch the main
  pane to *{name}* to use this view." + an "Open in main pane" button (promotes
  then closes the pane).
- Composer-internal note splits are separate (per-container
  `GlobalTab.paneTabIds`, notes.ts:316–333; `workspace:split-horizontal` =
  Mod+Alt+↓ lives in the Composer).

### 2.3.6 Inner (per-surface) tab strips
- **UnifiedTabBar** (`src/components/shared/UnifiedTabBar.tsx`) — the generic
  second-row strip used by Files/Tasks/Import etc.: same TAB_BASE pills; mode
  icon at tab start (click = mode menu to convert the tab), hover-only close
  (only when >1 tab), drag-reorder optional, `+` opens a searchable mode picker,
  listens for `liv:new-tab-request`. Renders NOTHING when
  `EmbeddedSurfaceContext` is true (two-tab-row budget: global strip + one
  sub-strip max).
- **ExtensionTabBar** (`src/components/shared/ExtensionTabBar.tsx`) — for
  extensions owning their own tabs (Capture, Dashboard, Library …). State per
  extension **per workspace** in localStorage `app.extTabs.<ext>.v1.<wsId>`.
  Every tab is lazily backed by a real vault Note (`noteId`) typed as the
  extension id, and switching tabs pushes that note into `useActiveObject` so
  the right-rail metadata follows tab focus. Its ⌄ opens the full DeptPicker and
  routes a foreign pick to the owning surface via `deptExtension()`.
- The Composer's own strip (Notes surface) shares TAB_BASE, groups, and the
  freeze hook; its tab/group context menus are in §2.27.

### 2.3.7 Departments mode (live default; ⚠ decided-dead per D18)
`DepartmentNav` (`src/components/shared/DepartmentNav.tsx:63–523`) replaces the
unified strip:
- Chrome-style bottom-aligned tabs (TAB_BASE, 14px icons). Built-ins (from
  `src/lib/departments.ts`): **Composer** "/", **Files** "/files", **Quick
  Capture** "/capture", **Dashboard** "/dashboard". Import/Export removed from
  the row (IA-10; routes still exist, reachable via menu/palette).
- Alignment from Settings → Layout `departmentAlignment` (left/center/right;
  default **center**) via flex spacers.
- Active logic: explicit `activeDeptId` override wins; custom tabs (all on "/")
  activate via a persisted `activeId`; built-ins by route prefix; a built-in on
  "/" never steals active from a selected custom tab.
- **Custom departments ARE bound workspaces**: clicking one persists its dept id,
  switches to Notes, switches to (or recreates + rebinds) its named workspace
  (`switchToDeptWorkspace`, :538–557). Double-click renames (and renames the
  bound workspace); hover **×** removes (custom only). Reconciliation clears the
  custom highlight when the active workspace no longer matches its binding.
- **+ menu** (fixed, w-56): *New department* → an inline **ghost tab** (recessed
  `bg-secondary/30` cell with a Plus icon + placeholder "New department"; typing
  names it; Enter/blur commits — creating a bound workspace via the canonical
  flow and selecting the new tab; Escape cancels); ─; "Show departments"
  checkbox list over ALL departments (hidden included; the last visible one is
  disabled so the bar can't empty).
- Drag-to-reorder with before/after 2px primary indicators; hidden ids keep a
  stable position relative to their previous visible anchor
  (`reorderDepartments`).
- Per-department content tabs render below in the content area
  (ExtensionTabBar/UnifiedTabBar).

## 2.4 SlotsBar — bookmarks strip (`src/components/shared/SlotsBar.tsx`)

A user-curated row of chips persisted at vault key `app.slots.v1`. Slot kinds
and activation:
- **link** — label + target: `/route` navigates in-app; `note:<id>` opens the
  note; anything else opens externally (bare domains get https://).
- **workspace** — dispatches `workspace-open`.
- **daily** — runs `daily:open-today` (chip labeled "Today", icon CalendarDays,
  tooltip "Open today's daily note").
- **memo** — an inline scratch note: chip shows a primary dot when non-empty;
  click opens a w-72 popover with an auto-focused 5-row textarea (auto-saves,
  Esc/click-away closes); the chip tooltip previews the text.
- **filter** — a pinned scope: replays a serialized `FilterState` into the
  shared activeFilter store field-by-field (missing keys reset), then switches to
  the **Library** (the surface that consumes the global scope).

Chip: h-6, max-w 140px, bordered rounded-md, kind icon 14px + truncated label;
hover reveals a floating **×** remove badge at the top-right corner. Trailing
**+** opens the adder popover (w-80): search box over workspaces + bookmarked
notes; fixed rows *Daily note (today)*, *Memory memo*, *Pin current scope* (only
when the live filter is non-empty; label auto-derived from top facet values),
*Important (bookmarked)* (preset tier:1 + #starred + archived-included); then
matching workspaces and bookmarks; footer form "Add link or /route" (label
optional + target + Add). Other surfaces can append a scope via
`addFilterSlotFromCurrent` + `slots-changed` event.

## 2.5 Center pane

- **Main pane** shows the active extension (departments mode) or the active
  global tab's surface (unified). min 18% (center column as a whole min 30%).
- Split panes: §2.3.5. Blank-tab landing: §2.3.2.

## 2.6 Navigation model (back/forward — no breadcrumbs)

Three cooperating histories:
1. **Location stack** (`__root.tsx:698–713,1218–1235`): browser-style snapshots
   of `{extension, routerPath, activeGlobalTabId}`; debounced 150ms per logical
   navigation; 100-entry cap; replays don't re-record.
2. **Object history** (`src/lib/navHistory.ts`): module-level stack of
   `{objectId, kind?}` — the object the user is LOOKING at (finer than routes; a
   task-row click records). 200 cap, forward-truncation, consecutive dedup,
   subscribable. Replaying (`replayNavTarget`, `__root.tsx:1263–1307`) opens
   notes in the Composer; other kinds switch their owning extension (task→tasks,
   contact→contacts, event→calendar, file→library, message→ai-chat, list→/lists)
   and dispatch `nav-history:focus` with the navigating guard raised.
3. **Composer note history** (`src/lib/composerHistory.ts`): per-pane
   back/forward through opened NOTES plus `route:` sentinels for notes-hosted
   surfaces `/files /dashboard /chat /processor /lists` — so "Files → open object
   → back" returns to Files (`__root.tsx:326–331,1253–1256,2345–2375`). Bound to
   **Mod+[** / **Mod+]** and the Composer pane-header arrows (`composer-nav`
   event; max 100, in-memory).

The shared arrows (ActivityBar) + **Alt+←/Alt+→** run `goNav`: prefer the object
history, fall back to the location stack (`__root.tsx:1343–1362`). Alt+Arrow is
claimed in CAPTURE phase with `stopImmediatePropagation` and an `e.repeat` guard
(`__root.tsx:1935–1946`). Enabled state = OR of both histories.

## 2.7 Workspaces / spaces switching

### 2.7.1 Model (`src/lib/notes.ts`)
`Workspace` = persisted record (id, name, builtIn `"home"|"recent"`, emoji?,
favorite?, archived?, projectTag/areaTag + `applyDefaults`, folderPath?) ∩ view
state (`WorkspaceView`, notes.ts:218–255: tabs, activeTabId, left/rightOpen,
rightPane, snapshots, capture settings, splitTabIds, layoutMode, globalTabs,
activeGlobalTabId, tabGroups, newTabMode). A separate `TreeNode` store (type
area|project|subspace|folder, parentId, order, workspaceId?, collapsed) builds
the hierarchy. Built-ins Home/Browsing are protected from archive/delete; per
D29 they have **no emoji** (clean glyphs). A new-workspace emoji suggestion
dictionary exists (notes.ts:171–210).

Switch protocol: persist `saveActiveWorkspaceId` → dispatch `workspace-change`
(data refresh; every listener re-reads) and `workspace-open` (the shell PERFORMS
the switch: persists if the sender didn't, switches to Notes, navigates "/", and
in unified workspaces realigns `activeGlobalTabId` to a composer/blank tab so
strip and pane agree — `__root.tsx:1149–1196`). Selecting a workspace always
lands you on the desk; the active TOOL is global and otherwise survives
switches.

### 2.7.2 HomeHub (`DepartmentNav.tsx:1164–1313`) — the ONE consolidated workspace control
Sits at the left of the tabs row. Button = active workspace **name only** (12px
semibold, max-w 140px) + chevron; reads "Liv" on a vault-wide tool. Popover
(fixed, w-72, z-50):
1. **Scope** section — workspace name/emoji · `area` and `project` chips showing
   the workspace's bound defaults (em-dash when unset), plus bordered "active
   filter" chips for any live activeFilter facets layered on top (never
   duplicating base values).
2. **Layout** row — the `LayoutModeSwitcher` (compact variant; ⚠ D18 kills it).
3. **WorkspaceList** (shared with the legacy `WorkspacePill`, ⚠ exported but
   unmounted): *Favorites* section → *Workspaces* header → built-ins → Area rows
   with indented project/subspace children under a faint "Subspaces" label →
   standalone workspaces. Each row: glyph (emoji / Home / Explorer / open-closed
   FolderGlyph) · name · right-aligned "N tabs" count · hover star (favorite
   toggle — list stays open) · hover archive. Active row = left 2px primary bar +
   tinted bg. Footer actions: *New workspace*, *Rename current* (disabled for
   built-ins), *Archive current* (disabled for built-ins; confirm "hidden from
   here and restorable in Settings → Archived workspaces"), ─, *View archived
   items* (opens ArchiveView overlay).
In a global tool the Scope/Layout sections hide and a header reads "Vault-wide
tool — open a workspace:".

### 2.7.3 WorkspaceSwitcher modal (`src/components/shared/WorkspaceSwitcher.tsx`)
**Mod+Shift+O** (`workspace:switch`). Centered max-w-md palette (z-150, blurred
scrim): filter input ("Switch workspace…"), arrow keys + hover highlight,
Enter/click dispatches `workspace-open`. Rows: emoji or Home/Compass glyph,
name, "current" tag on the active one. Empty state: `No workspace matches "q".`

### 2.7.4 Creation — `createBoundWorkspace` (`src/lib/workspaceActions.ts`)
The single entry point for EVERY "new workspace" button (sidebar, HomeHub,
dashboard, dept ghost tab, `workspace-add-request` event). Creates the record;
optionally opens the native folder picker to bind an on-disk folder inside the
vault (opt-in via Settings `promptForWorkspaceFolder`, default OFF — the picker
can pop behind the window; cancel = folderless); persists + activates (unless
`makeActive:false`); fires `workspace-open`/`workspace-change`; optionally
offers to back-fill area/project defaults across existing notes.

### 2.7.5 VaultSwitcher (`src/components/shared/VaultSwitcher.tsx`)
Pinned footer of the left sidebar (Obsidian pattern): Database chip + vault
folder basename over a "Vault" caption + up-down chevrons. Menu opens UPWARD:
"Vaults" header, known-vault rows (check on current; name + mono path; hover ×
"Remove from list (does not delete the folder)"), ─, *Open another vault…*
(native folder picker; switching re-points the vault root and reloads the whole
app). Errors render inline in a destructive-tinted box. Empty state: "No other
vaults yet." Known-vaults roster: `<appDataDir>/known-vaults.json`,
most-recent-first, {path, name=basename, lastOpened}.

## 2.8 Omnibox / QuickSwitcher — `src/components/shared/QuickSwitcher.tsx` (4,251 lines)

One overlay, two modes: **Search** and **Commands** (`SwitcherMode`).

### 2.8.1 Triggers & frame
- **Mod+O** = search mode (`switcher:open`, toggles) · **Mod+P** = commands mode
  (`command-palette:open`) · **Mod+Shift+F** = search (`global-search:open`) ·
  HeaderSearch click · `open-quick-switcher` event · typing **`>`** as the first
  char of the search input flips to Commands (the `>` is consumed, the rest
  carries over — VS Code Quick Open, :4077–4082).
- Fixed full-screen scrim (bg/70 + blur, click closes), panel at 10vh: **560px
  tall × 700px wide** (→ **880px** with the properties panel docked), rounded-xl,
  pop-in animation. Header row: hero search field (search glyph tints primary on
  focus, autofocus, clear ×) · a **Search | Commands** segmented control · close
  ×. Placeholders — name scope: `Search by name…  try #tag, tier:1, type:meeting`;
  content scope: `Search everything…  try #tag, tier:1, created:2025`; commands:
  `Run a command…`.
- The input owns its text; the query pipeline reads a **140ms-debounced committed
  copy** (typing never fights the filter pass). Open resets text/mode/selection;
  toggling scope/reach mid-session does NOT clear the query. Opening dispatches
  `quick-switcher-open`/`close` so the right sidebar blanks stale content.

### 2.8.2 Query DSL (`src/lib/query.ts`)
Free text + inline qualifiers, case-insensitive, parsed by successive regex
strips: `kind:note|task|file|contact|event|message` · `tier:N` (normalized) ·
`type:x` · `status:x` · `priority:x` · `area:x` · `project:x` (substring) ·
`#tag` · `@person` · `active:true` · `custom.<key>:<value>` · created windows
`created:2025`, `created:2025-03`, `created:2025-01-01..2025-06-30`,
`after:DATE`, `before:DATE` (partial dates pad to period start/end) · negations
`-kind: -tier: -type: -area: -project: -#tag -@person`. Multi-values OR within a
facet, AND across facets. `includeArchived`/`includeSubnotes` are store flags,
not tokens. The typed DSL merges **field-by-field** with the global activeFilter
store (never by re-parsing token strings — spaces in values broke that;
:3299–3334) — the same store the right-rail facet filters write, so a filter
dialed elsewhere pre-filters the palette.

### 2.8.3 The facet rail (one resting control row, `FavoriteRail`)
"Filter by" + chips. Chip order = the user's ★-pinned metadata fields that are
facetable, else default `object(kind), type, area, tags, tier`. Each chip:
PropertyIcon + label; when active shows values inline (`tier: 1, 2 · not 3` —
⚠ brief promised per-value counts; chips show selected values, not counts).
Click opens a **FacetPopover** (portal, fixed under the chip, 240px, clamped
on-screen):
- Header label + "Done"; filter input ("Filter tier… (or press /)"); value list
  of REAL vault values (tier always offers 1/2/3); footer kbd hints.
- **Keyboard-first value grammar** (captures the keyboard, scope
  `palette:facet`; §2.28.4): focus lands on the LIST; **1–9** pick/cycle the
  numbered value, **I** include, **X** exclude, **O** clear the highlighted
  value, ↑↓ move, **/** focuses the filter input, **Esc** closes (layered: Esc in
  the filter input first clears the query). Click cycles include → exclude →
  off. Include = primary tint + ✓; exclude = destructive tint + − + "NOT".
- `active` chip is a plain toggle (activeOnly). `created` chip opens a
  **DateRangePopover** (two native date inputs "Created after/before", drafts
  locally owned — writes through but never re-derives mid-edit; Clear/Done).
- "**+ properties**" dashed chip toggles the docked PropertyFilterPanel
  (§2.8.5).
- Right-aligned trailing chips: **SourceChip** "in: Vault ⌄" — ⚠ deliberately
  UI-only: popover lists "This vault ✓ (wired)", Google Drive/Web marked "SOON",
  plus a 2-col grid of coming connectors (Notion, Slack, GitHub, Gmail, Figma,
  Dropbox) with copy "Liv will search everything you connect, right alongside
  your vault." — and the **FiltersChip** "Filters (n)": a popover folding the old
  control rows into one — **Match** segmented Name|Content (persisted
  `app.switcher.scope.v1`, default name); **Reach** segmented
  Workspace|Everywhere (persisted, default everywhere; workspace scope = the
  active workspace's auto-stamped area/project, shown inline e.g. "= area: work ·
  project: liv", or a teaching hint if unstamped; affects non-note kinds only —
  notes are always vault-wide); **Results** toggle table: *Archived items*,
  *Subnotes*, *Smart rerank (AI)* (off/on; disabled "needs key" without an API
  key), *Quick filters* (footer of most-used metadata values,
  `ObsidianPalettePreview`); plus "Clear search & filters". Chip badge counts
  deviations from the calm default.
- Below the rail, **ActiveFilterChips**: every set filter as a removable pill
  (includes primary-tinted; excludes destructive-tinted with "−"; `#tag`,
  `@person`, `kind:`, `field: value`, custom `key: value`, created range, "incl.
  archived") + "Clear all".

### 2.8.4 Results pipeline
- **Data set**: liv-core notes + a forced fresh vault `.md` scan
  (frontmatter-only) merged & deduped by stable id; non-note objects per reach.
  Content scope re-scans with bodies (or frontmatter-only when Rust FTS is on),
  debounced 250ms.
- **Scope semantics**: *Name* = title match with rank + typo tolerance; on zero
  title hits it **SPILLS** into content search with an italic hint "No title
  match — also searching content". *Content* = SQLite **FTS5**
  (`searchVaultFts` → Rust `entity_search`, ranked, kind-scoped via
  `search_filtered`, debounced 120ms) unioned with in-memory matches, re-ranked
  as one list; per-hit FTS `snippet()` excerpts rendered with bolded segments;
  JS keyword ranking fallback when FTS is unavailable.
- **No text** (empty-open / qualifier-only): most-recently-edited order so
  Enter-on-open hits the last-touched object.
- **Ranking** (`src/lib/searchRanking.ts` weights): titleExact 1000 > titlePrefix
  600 > titleWordBoundary 400 > titleContains 250 > titleAllTerms 180 > metaExact
  120/term > fuzzyTitle 90 (Levenshtein ≤1 for q≤6 chars, ≤2 for ≤12, −20/edit,
  only if no direct hit) > bodyAllTerms 70 > metaContains 60 > bodyContains 40;
  + recency nudge ≤50 decaying linearly over 180 days. Stable sort; never drops
  rows; body capped at 4000 chars.
- **Smart rerank (AI)** — opt-in toggle: with key + free text, sends top-20
  {id, title, kind·area/project snippet} to the model after 500ms, cached per
  (scope, text, id-set); resolved order applied as a stable reorder (unranked
  tail keeps keyword order); pure permutation, silent keyword fallback
  (`rerankSearchResults`, anthropic.ts:285).
- **Subnote nesting**: when a note and its parent both match, children re-order
  directly under the parent — applied to the ORDER so keyboard nav matches the
  display; nested rows indent 24px with an L-guide + "subnote" pill.
- Results grouped by object KIND with uppercase headers (`KindIcon kind N`) —
  cosmetic; the flat selection index is preserved. Cap 30 shown; toolbar line
  reads `N results · showing 30` honestly. Archived rows (when included) dim 55%
  + "Archived" pill.

### 2.8.5 Result rows, display modes, panels, footer
- **Display modes** (persisted; icon toggles on the slim results-header line):
  **Compact** (dense rows: kind icon, title, relative time), **Context** (match
  count next to the title + up to 2 attributed excerpt lines
  "`BODY …around the [match]…`", per-field scan title/body/notes/tag/project/
  area, FTS fallback), **Preview** (44%/56% split: list | `ResultPreviewPane` =
  big title (click=open), FULL pivot-chip set, why-it-matched snippet stack,
  900-char body excerpt hydrated from disk for scan-only notes, path,
  edited/created, backlink count, Open button).
- **Object-lens pivot chips**: each row shows ≤4 metadata chips (status,
  area|project, first person, tier, first tag; "+N" overflow) — clicking a chip
  **pivots the whole search** by toggling that value in the shared filter store
  (lowercased canonical), lighting when active; row click still opens
  (stopPropagation splits targets).
- Rows are **drag sources** (`application/liv-object-id` + text/plain id) for the
  Lists drop zone. Tooltip "↵ open · ↑↓ move · drag into a list".
- **`+ properties` right panel** (docked, 320px, additive — never an alternative
  layout): "Filter by property" type-to-find over EVERY filterable property —
  built-in facets (type, tier, status, priority, area, project, tags, people;
  shown only when they have values, tier always), then a "Custom properties"
  divider with every discovered custom key. Expanding a property shows a
  `PropertyValuePicker`: typeahead value checklist + "Use "<typed>"" free-value
  row; clicks cycle include→exclude→clear (status/priority/custom have no
  exclude channel — plain toggle). Rows have hover **eye-off to hide** a property
  (shared `hiddenProperties` store, localStorage `app.hiddenProperties.v1`,
  cross-tab synced; hides the matching rail facet too); "Show hidden (N)"
  reveals with un-hide eyes. Footer explains the tri-state and typed
  equivalents.
- **Search-that-creates**: free text + zero results (debounce settled) → empty
  state "No matches / Nothing matches that. Try a different word, or switch the
  Name / Content scope." + primary button **Create note "query" ↵** which mints
  and opens a note titled by the query (:3599–3631).
- **Footer**: `↑↓ navigate · ↵ open/run · esc close`; right side: **Export N**
  (notes-only subset → Export modal, §2.18.6) · **Save** (prompt → writes
  `Library/Filters/<name>.base` — the live query materialized via
  `filtersToBaseFilterNode`, `src/lib/searchLens.ts`: one-of facets →
  `field == ["a","b"]`, substring facets → OR of `contains`, tags/people AND
  `contains`, free text → `file.name.contains`, excludes → `!=`, created →
  `file.ctime` bounds; kind "note" also matches unset `object`) · primary
  **Open in view →** (same materialization, auto name "Search: <query>", then
  closes → `/files` → Saved-View tab → `lists-open-base`). Both disabled until
  text or a filter exists ("Type a search or set a filter first").
- Optional **Quick filters** footer (opt-in): most-used metadata values as
  click-filters.

### 2.8.6 Autocomplete & keyboard
- **Metadata-guided autocomplete** under the input (:3143–3182, 3702–3746): for
  the token at the caret, offers operators (`#tag`, `area:`, `tier:`…) and live
  values from a vault catalog (`paletteMetadataGuides`); rows = PropertyIcon +
  label + hint. **Passive until engaged**: ArrowDown engages; while passive Enter
  searches (never silently inserts); Tab always completes the highlighted/first
  suggestion; Esc dismisses the dropdown (second Esc closes the palette);
  operator-picks keep the menu open for the value; picks splice token text and
  restore the caret.
- **List nav**: ↑/↓ and **Ctrl/Cmd+J/N (down), Ctrl/Cmd+K/P (up)**; Enter opens
  the selected object (notes hydrate body from disk first, open in Composer;
  task→Tasks, file→Library, message→Chat; contact/event just close) or runs the
  command; selected row auto-scrolls into view; Esc closes.

### 2.8.7 Commands mode
Commands come from the central registry (`src/lib/commands.tsx`) labelled
`Category: Label` + live keybinding chips (user overrides included), plus 4
inline navigation entries (Go to Notes/Capture/Tasks/Library — ⚠ advertised
Ctrl+1/3/4/5, labels only; those bindings aren't actually registered). A
**CommandFacetRail** filters by Category / Scope (Global/Composer/Editor/Search)
/ Acts-on (Note/Object/Tab/Workspace/App/Selection/Line) with the same
FacetPopover tri-state grammar, session-local; fuzzy match also hits per-command
keywords; rows carry pivotable metadata badges; grouped by category (one bucket
per category, first-appearance order). Empty state "No commands found / Try a
different word — or clear the search to see everything." Footer "N commands".

## 2.9 Right panel — shell & routing

### 2.9.1 View tabs (`src/components/shared/RightSidebar.tsx:104,362–380`)
`RightSidebarView = "metadata" | "snapshots" | "outline" | "graph" | "copilot"`.
Rendered as a **full-width segmented tab bar** pinned to 40px height (aligns
with the center tab strip + the left dock header — one continuous rule), each
tab an equal flex box of icon (15px, stroke 1.75) above a 12px label. Icons:
sliders (Metadata), history clock (Snapshots), list-tree (Outline), network
(Graph), sparkles (Copilot). Active tab `nav-active`; last-used view persists at
vault key `app.rightSidebar.view.v1`; first mount uses Settings → Layout
`defaultRightView` (default "metadata"; ⚠ the settings options list includes a
"Bookmarks" view that doesn't exist in the tab set). Switching plays a faint
cross-fade (`tab-body-enter`). ⚠ IA-5 renames "Snapshots" → "History" and moves
workspace snapshots to the tab bar's Layers menu — approved (D29), not
implemented.

### 2.9.2 Metadata-tab content routing (`RightSidebar.tsx:234–416`)
Priority order when the Metadata tab is active:
1. **Global search open** → calm placeholder ("Searching… Pick a result to see
   its details here").
2. **No focused object + Files surface context** (mode ≠ item) →
   `FilesContextPanel` (§2.9.3).
3. **No focused object + Tasks surface active** → `TasksFilterPanel` (§2.15.12).
4. Otherwise → the **MetadataEditor** inspector (§2.10), which shows its own
   "Nothing selected" empty state (inbox icon, "Click a note, task, file, or
   contact to view and edit its properties here").
Focus-clearing rules: navigating to a *different* files surface clears object
focus (the same surface re-announcing itself does not — `lastSurfaceKey`
compare); switching into a whole-surface tool (calendar, tasks, library, inbox,
contacts, messages, finances, ai-chat) clears focus so the panel never pins a
stale note. Entering Tasks snaps the rail to the Metadata tab once, on the
inactive→active transition only. Keyboard commands can force a view via the
`right-panel:set-view` event.

### 2.9.3 FilesContextPanel (Files surface, no item selected — `RightSidebar.tsx:497–825`)
Driven by `files-context` events (modes blank/home/folder/base/list/item).
Header: mode glyph (open folder / relation glyph for saved filters / list /
grid) + title + subtitle ("Search and browse every note" / "A folder in your
workspace" / "A saved search" / "Files"). Body = single hairline-divided
property sheet (`divide-y`), sections (home mode):
1. **View** — always-visible full-width segmented control Table · Cards · List ·
   Board (base view types table/gallery/folder/kanban), drives the center via
   `files-view-control {baseId, action:"setViewType"}`.
2. **Filters** (collapsible, count pill of leaf conditions) — hosts the same
   visual AND/OR `FilterBuilder` the base toolbar uses (`setFilter`).
3. **Properties** — show/hide columns checklist with live "N of M shown", a
   borderless filter input when >8 columns, PropertyIcon per column, `file.`
   prefix stripped, max-h-64 own scroll (`toggleColumn`).
4. **Sort & group** — two ghost "label … value ▾" rows: Sort by (+ ↑/↓ direction
   toggle) and Group by (`setSort`/`setGroupBy`).
5. **Quick filters** (default collapsed) — Scope readout card ("Filtering:
   {workspace} · {conditions}" + "View: … · path"), the configurable
   **FacetFilters**, and the Custom-property filter.
6. **Results** — Rows / Selected metric rows + active filter chips.
Folder/filter/list modes instead show a Scope/Filter-Objects/Collections section
(workspace + mono path, "Open folder tab"/"Open Filters"/"Open Lists" buttons)
and a "Selected item" hint section with a "Find object" button (opens the
QuickSwitcher).

**FacetFilters** (`RightSidebar.tsx:1757–2074`, shared by Files and Tasks
panels): user-configurable facet rail. "Configure" cog → search + checklist of
every property (built-ins `FACET_FIELDS` + discovered custom, labeled "custom");
selection persists (`app.rightSidebar.filterFacets.v1`). Each enabled facet
renders header (PropertyIcon + label) + value chips with **live would-match
counts**; on-state primary tint. All toggles flow through the ONE shared
`activeFilter` store (same `filterObjects` path as search). Notes-only "Include
subnotes" checkbox (default on). Ghost control tokens: h-7 rows, borderless
selects right-aligned, bottom-hairline inputs. Sections collapse individually;
open state persists per title (`liv.rail.panelOpen.v1`).

## 2.10 Metadata inspector (MetadataEditor) — `src/components/shared/MetadataEditor.tsx` (7,224 lines)

### 2.10.1 The data model it edits (`src/lib/core/objectModel.ts`)
Every entity is one `ObjectKind`: `note | task | file | contact | event |
message | list` (:16). All kinds share one `ObjectMetadata` spine (:23–124):

| Field | Type | Notes |
|---|---|---|
| `object` | kind discriminant | read-only "object" row in Details |
| `format` | string | on-disk extension ("md", "pdf", "canvas"…); empty = no disk file |
| `area` | string | single life-area |
| `project` | string | single project; optional `subproject` shown as a second row only when project/subproject set |
| `tags` | string[] | **displayed as "Subjects"** everywhere (founder-locked rename, `propertyRegistry.ts:104`); stored key stays `tags` |
| `tier` | string | "1"/"2"/"3"; `normalizeTier` accepts "tier 2"/"t2"/"2" → "2"; default "" (unset) |
| `people` | string[] | names; linked to contacts by case-insensitive name match at render time — never an id |
| `active` | boolean | default true |
| `bookmarked` | boolean? | header star |
| `calendarTitle` / `calendarDate` | string / ISO yyyy-mm-dd | puts the object on the calendar |
| `status`/`priority`/`dueDate`/`recurrence` | task projections | populated only for tasks |
| `created` / `lastEdited` | ISO strings | read-only |
| `description` | string? | one-liner annotation, multi-line textarea |
| `custom` | `Record<string, string\|string[]\|boolean\|number>` | free-form property bag (Liv: YAML frontmatter keys) |
| `related` | string[]? | ⚠ legacy title links; migrated once into `relations` (`relations.ts:427`) |
| `sources` | string[]? | flat multi-valued citations (D24) — coexists with note-only `source`/`sourceRef` (§6) |
| `relations` | `{id, type?, origin?}[]` | typed id-based links (§2.12) |
| `workspaceId` | string? | hard workspace binding |
| `linkUnfurl` | cached OG preview for link objects |

Note-only fields (`NoteMetadata`, :147–163): `type` (default "atomic"), `source`,
`sourceRef`, `folderId`, `customPath`. ⚠ D15's `form`+`type` split is
decided-but-not-built — exactly one single-select `type` ships.

**Property types** — two overlapping systems, both replicated:
- **Custom-property kinds** (per-key, user-pickable, 8 entries in menu order:
  `text · list · select · number · checkbox · date · datetime · hard-detail`).
  Persisted per property NAME at `app.metadata.customPropertyTypes.v1`; when
  absent, **inferred from the value** (`inferCustomPropertyKind`): array→list,
  boolean/"true"/"false"→checkbox, number→number, `^\d{4}-\d{2}-\d{2}$`→date,
  else text. Schema-on-read: a custom property exists because some object uses
  it (`customProperties.ts`); cardinality is "list" if ANY object stores an
  array for the key, never demoted.
- **TypeSchema property types** (per-kind schemas, `core/typeSchema.ts:19`):
  `text · email · tel · date · url · number · select`. Editable registry at
  vault key `app.typeSchemas.v1`, seeded from `DEFAULT_TYPE_SCHEMAS`
  (contact/task/event), edited in Settings → Object types.

**Seed vocabulary & value pools (D17)** — `src/lib/vocabulary.ts`. Three-layer
pickers: ① vault-used values → ② curated seed → ③ create-new. Axes: types,
areas, projects, people, subjects, sources (:103). Only `types` has a shipped
seed: **TYPE_POOL, 54 values** (:34–98) — atomic, idea, question, insight,
reflection, brainstorm, sketch note, running notes, journal, daily note, weekly
review, lecture/literature/book/article/podcast/video/research notes, reading
list, quote, definition, concept, glossary, summary, outline, draft, essay,
report, analysis, comparison, argument, counterargument, hypothesis, meeting
notes, interview notes, contact notes, decision, plan, roadmap, milestone,
strategy, business plan, pitch, retrospective, feedback, budget, instructions,
how-to, checklist, troubleshooting, recipe, reference, cheat sheet, snippet,
template, document, link (mirrors Rust `src-tauri/src/vocab.rs`). Grown terms
persist per-workspace at vault key `app.vocabulary.v1` as `{canonical, aliases[],
source: seed|profile|minted, uses, lastUsed}`. Dedup: case-fold + naive
plural-fold (drop trailing "s" unless "ss", words >3 chars) + alias check; a new
spelling of an existing term becomes an **alias**, never a second term. Ranking:
`habitScore = log1p(uses) + exp(-daysSinceUse/30)`, ties alphabetical.
`recordUse` bumps uses+lastUsed on every commit of a suggested value (tier
excepted; project/area-path-shaped tags `^(projects?|areas?)\//i` are never
learned as subjects). `mergeTerm`/`renameTerm` fold old spellings in as aliases.

### 2.10.2 Inspector scope & header
Works on ANY focused object; resolves via the full pool incl. archived
fallback, and can **synthesize** an object from a live composer tab that hasn't
been minted yet (empty note) so metadata is always editable; edits mirror back
onto the open tab so the composer never clobbers them (:1207–1296, 1445–1484).

**Header row** (:3134–3287) — top border-bottom strip, flex-wrap so actions drop
to a second row on narrow panels:
- **KindIcon** (colored — the only colored chrome in the inspector) 20px, then
  **title** (one-line truncate + tooltip, never wraps; italic "Untitled"
  fallback), with kind/type caption beneath (`displayKind(obj)`, e.g. "atomic",
  "pdf").
- Action icons (18px, right): **Wand2** "Suggest a name (AI)" — only when an API
  key is set and kind ∈ note/task/contact/list/event; proposes title chips
  inline under the title ("Rename to [chip] [chip] ✕") — click applies the
  rename per kind. **Sparkles** "Suggest metadata (Alt+M)" — toggles the Decide
  tray; tinted while active; pulses while suggesting. **Bookmark** toggle
  (filled when on). **Archive** toggle — archivable kinds only
  (note/contact/event/list). **Trash2** — notes: soft-delete to Trash via
  `object:trash`; contacts: confirmed **hard** delete (dialog says "Use Archive
  instead to keep it restorable"), clears focus first.

**Preset bar** (`PresetPicker.tsx`), under the header for every kind: star glyph
+ `<select>` "Apply preset…" (options = the active workspace's `presets`) +
"Save" button (prompts for a name; snapshots current metadata padded to full
NoteMetadata). Below: preset name pills that **delete on click** (confirm; trash
glyph on hover). Presets live in workspace state, never frontmatter.
`notApplicableNote` for non-notes: "Type & source apply to notes only — area,
project, tags, tier, people and active will be set." Applying merges:
area/project/tier/tags/people/active always; description only if the preset has
one; custom merged over; type/source only onto notes.

### 2.10.3 Panel modes
Settings → Layout `metadataPanelMode`: `flat | focused | hybrid | grouped`
(shipped default **grouped**); plus `showEmptyBuiltins` (flat-mode row gating; ⚠
default true in code, doc-comment claims false) and `metadataSuggestMode`
(`missing|reevaluate|ask`, default "missing").
- **flat** — every built-in row in hard-coded collapsible `FieldGroup`s:
  Classify(open) / Priority / People / Source / Schedule (default-closed), plus a
  separate collapsible "Inherited" tier at top (project/area/workspace), hover
  ↑/↓ per-row reorder within the built-in spine order (persisted
  `app.metadata.propertyOrder.v1`), Description at bottom. Rows hidden unless
  value set / `showEmptyBuiltins` / manually added.
- **focused** — only rows the note's **Type** cares about (TYPE_FACETS below) +
  type/tags always + filled + manually added.
- **hybrid** — focused plus an inline "Show all properties ▸" reveal.
- **grouped** (default; D11) — importance-first, below.

### 2.10.4 Grouped mode — importance-first layout (render order; flex `order` in brackets)
1. **Decide tray** [top, when open] — §2.11.
2. **Task block** [3] — task kind only (§2.15.10).
3. **Kind-schema block** [3] — contact only: `SchemaFields` renders the full
   typed profile, grouped Contact (Email `email`, Phone `tel`, Birthday
   date-as-text) / Work (Company, Role, Origin, Relationship) — **every schema
   field renders even when empty**; values live in `metadata.custom`
   (adapter-projected), round-trip to the contact record, and are excluded from
   the generic custom block so nothing renders twice. (Event has a Location
   schema field defined but the event schema block is deliberately not
   rendered, `typeSchema.ts:66–82`.)
4. **Core** [2] (`renderCore`, :2798–2854): section label "Core", rows: **type**,
   **subjects**, **project** (hint tooltip: "A note can sit in a project OR a
   life-area — or neither… don't be afraid to [add several]"), **subproject**
   (conditional), **area** (hint tooltip). Under them, when workspace-bound: a
   dim "★ in {Workspace / Subspace path}" line (path walks the TreeNode parent
   chain, cycle-guarded).
5. **Important built-ins** [4] — flat, no group headers. A movable built-in
   (`people, date, cal title, source, ref, related, sources, tier, active`) is
   "important" iff **pinned** (★) OR **type-relevant** (TYPE_FACETS) OR **has a
   non-default value** (`fieldHasValue`: tier counts only when ≠ "1"; active
   only when false). Each row gets a hover **★ pin button** (top-right,
   `right-7`): pinned = filled star always visible; pinning is **global across
   all notes**, persisted `app.metadata.pinnedFields.v1`, shared with Settings →
   Properties and the search facet rail (event `metadata-pins-change`).
6. **Description** [6] — own bordered block with label+icon, 3-row resizable
   textarea, placeholder "A short description — what is this, what's it for,
   why does it matter?"; draft-local; commits on blur / Esc / Ctrl+Enter.
7. **"More properties · N" expander** [7] — chevron button; count = hidden
   movable built-ins + custom keys. After an Alt+M commit that wrote into the
   hidden set, shows a filled primary badge "`N` new" until expanded. Expanded
   [8]: hidden fields grouped under the user's own group labels (only groups
   with a not-yet-surfaced member appear) + a flat "Other" tail; each row has
   the ★ pin.
8. **Details** [1050] — collapsible header (default closed): read-only
   provenance rows — **path** (mono; for notes a *button*: click opens a folder
   picker to **move the file** — picked folder must be inside the vault else
   alert "Pick a folder INSIDE the vault"; writes `customPath`; adjacent ↗
   "Reveal in folder"), **object** (kind), **format** (".md" mono; from
   metadata.format → file extension → path extension), **subnote of**
   (breadcrumb "Top / Mid" walking parentId chain, notes only), **created**
   (localized datetime). Then **user details**: editable mono key/value rows
   (value lives in `metadata.custom`; classification as a "detail" is just
   membership of the layout's `details` group) with hover ×, and a "+ add
   detail" inline name input (Enter commits, Esc cancels; rejects names
   colliding with built-in ids/system rows/internal keys).
9. **Connections** [1080] — §2.12.
10. **Custom properties block** [1000] — shown when More expanded / Arrange /
    non-grouped; §2.10.6.
11. **Toolbox footer** [1100] — "✎ Arrange" toggle (persisted
    `app.metadata.arrange.v1`, survives note switches); while on also "+ Group"
    and "Reset".
While the Decide tray is active, everything below it dims to 50% opacity and
becomes non-interactive (:3308–3313).

**TYPE_FACETS** (:630–661) — which fields a note type pre-surfaces:
`meeting note`/`meeting` → people,date,project; `1-on-1` → people,date;
`interview` → people,date,source; `person note`/`person` → people,area;
`pitch` → project,tier; `project doc`/`spec` → project,area; `document` →
area,project; `running notes` → project,active; `task`/`to-do`/`todo` →
active,date,tier; `shopping list`/`checklist`/`list` → date; `journal`/`daily`
→ date; `idea`/`insight` → area; `reference`/`how-to` → area,source; `book` →
source,people; `reading note`/`bookmark`/`link` → source. Unknown → nothing.

### 2.10.5 User-definable groups + Arrange mode
Group layout is DATA (`metadataProperties.ts:27–136`), localStorage
`app.metadata.groupLayout.v1`, never frontmatter. `GroupLayout = {groups:
FieldGroupDef[], fieldKinds: Record<id,FieldKind>}`. Default groups (id / label
/ order / open / members): inherited(system, 10, open, [project,area]) ·
people(30, closed, [people]) · schedule(40, closed, [date, cal title]) ·
source(50, closed, [source, ref, related]) · priority(60, closed, [tier,
active]) · properties(80, open, [] — the sink new custom props land in) ·
details(system, 90, closed, [path, object, subnote of, created, format]).
`CORE_FIELDS = [type, tags, description]` always render in the pinned Core
anchor, never inside a group. Normalization re-seeds missing system groups,
dedupes membership (a field lives in ≤1 group, first wins), strips
core/internal ids, re-homes orphans into `properties`. Internal key blocklist:
`livGlobalTabId`.

**Arrange mode**: shows the full grouped structure. Group headers gain: drag
grip (reorder groups; insertion line above target), ▲▼ move buttons, inline
rename (system groups show "System group — can be reordered but not renamed or
deleted"), × delete (fields become "Ungrouped", not force-re-homed). Field rows
gain: drag grip (drag between/within groups; a 2px primary insertion line shows
before/after by cursor half; drop on a group header/body appends) + a "move →"
`<select>` of other groups; groups get a "+ field…" dashed select to pull a
field in. An "Ungrouped — drag into a group" section [75] lists movable
built-ins in no group, each with an "into group →" select; the whole section is
a drop target (drop = ungroup). The whole panel is a catch-all dragover target
so the no-drop cursor never appears. Field drag works in **both** normal and
Arrange mode; group chrome is Arrange-only.

**Force-reveal after commit**: after an Alt+M commit, groups that received
values are force-opened (`revealLabels` + `revealNonce`) so a committed
person/source never hides behind a collapsed section.

### 2.10.6 Field-by-field control spec
Row chrome — `PropRow` (:6767–6831): 3-column grid `[24px icon | 80px label |
1fr control]`, row px-2 py-1.5, hover fill `bg-secondary/20`. Icon = monochrome
`PropertyIcon` 18px (§3.5). Label 12px muted, truncating; optional **hint**
(dotted underline, cursor-help, tooltip = teaching text); optional **provenance
✨** sparkle next to the label with tooltip "Why: {reason}" (§2.10.7). Built-in
rows wrap in `BuiltinRow`: hover reveals top-right controls — (flat mode only)
▲▼ reorder, and **×** "Remove this property" (clears the value, un-pins from
`manualBuiltins`, broadcasts `metadata-remove-builtin`).

Shared editor primitives:
- **AutocompleteInput** (:6835–6956): text input; focusing opens a portaled
  dropdown (fixed, anchored under the field, max-h-52, 12 items: prefix matches
  first then substring); typing writes through on every keystroke AND filters;
  ↑/↓ highlight, Enter picks highlighted (or commits typed text) and blurs, Esc
  closes then bubbles to field-nav; option click on mousedown. No explicit
  "create" row — typing new text IS creating (layer ③).
- **ChipInput** (:6960–7186): value chips + inline input. Chips: rounded-sm,
  `bg-primary/12 text-primary` (or hash-stable color per value when theme =
  "colorful", §3.6), × to remove. Combobox: focus opens ALL prior values for the
  property not already chosen; typing narrows by substring (8 max); ↑/↓
  highlight; **Enter adds and keeps the field focused + list open** (values
  chain, Obsidian-style); comma also commits; Tab commits highlighted (empty
  draft + Tab falls through to focus nav); **Backspace on empty draft removes
  the last chip**; Esc closes then leaves the field. Optional **linked values**:
  chips whose lowercase value is in `linkedValues` render as dotted-underline
  buttons — click opens the target (contact / note). Optional **create row**:
  when `onCreateValue` is set and the typed text isn't linked or already a chip,
  the list appends a primary-tinted "+ Create contact "X"" row.
- Keyboard field-nav (`handleMetadataKeyDown`, :568–602): **Alt/Ctrl/Cmd+↓/↑**
  move focus to next/previous metadata control (`[data-metadata-field]` /
  `[data-metadata-control]`, visible + enabled, DOM order; text inputs get
  select-all on arrive); **Esc or Ctrl/Cmd+Enter** commits, blurs, returns focus
  to the main surface (`.cm-content` → canvas → `[data-main-surface]`);
  **Enter** (non-multiline) commits + blurs, except native date/number inputs
  where Enter just blurs.

Per field:

| Row (label) | Control | Suggestions / picker | Notes |
|---|---|---|---|
| **type** | AutocompleteInput "What kind? (meeting, pitch, idea…)" | user note-type registry → seed TYPE_POOL → types in use vault-wide, deduped | note+task only; × clears |
| **subjects** (stored `tags`) | ChipInput "What's it about?" | all tags across kinds, minus project/area-path tags | provenance-capable |
| **project** | AutocompleteInput "Which project?" | distinct projects vault-wide | Core; hint tooltip; workspace-stamped on creation |
| **subproject** | AutocompleteInput "Sub-project?" | project pool | conditional row |
| **area** | AutocompleteInput "Which life-area?" | distinct areas | Core; hint tooltip |
| **tier** | `<input type=number min=0 step=1>` placeholder "1" | ↑/↓ increment/decrement (clamped ≥0) | normalized ("t2"→"2"); concept 1–3, input free numeric |
| **active** | pill toggle switch (h-5 w-9, primary when on) | — | role=switch |
| **people** | ChipInput "Who's involved?" | people vault-wide | linked chips open the matching contact (focus + switch to Contacts); create row "Create contact "X"" mints a contact and adds the chip; hidden for tasks (Task block owns it) |
| **source** | AutocompleteInput "Where's it from?" | note sources in use | notes only |
| **ref** (stored `sourceRef`) | plain text "Author, page, URL…" | — | notes only |
| **sources** | ChipInput "Cite a source…" | none | flat multi list (D24) |
| **related** | ChipInput "Link a note…" | note titles | linked chips open the note (`note-open`); ⚠ legacy — real linking is Connections |
| **date** (stored `calendarDate`) | `<input type=date>` | — | provenance-capable (calendar ✨); tasks render Due date instead |
| **cal title** (stored `calendarTitle`) | text input "None" | — | calendar event title override |
| **description** | `DescriptionRow` (§2.10.4 item 6) | — | |
| **custom `<key>`** | by kind: list→ChipInput ("add value…"); checkbox→toggle; number→number input; date→date input; datetime→`datetime-local`; select→AutocompleteInput ("select…") over values used for this key vault-wide; hard-detail→mono text ("reference detail"); text→AutocompleteInput ("value") | per-key vault value bank | leading icon is a **PropertyTypeMenu button**: click opens the 8-type popover to change the property's type with value coercion (list↔scalar, checkbox bool-coerce, number Number()). Hover controls: **icon picker** (grid of 12 named glyphs + "Reset to default"; override applies vault-wide per key), ▲▼ reorder (persisted `app.metadata.customPropertyOrder.v1`), × remove key from this note |

**"+ Add property"** (bottom of the custom block, :6252–6303): Layers icon +
"+ Add property" → inline row: name input with a **native datalist** of every
property name seen in the vault PLUS unset built-ins (users can pick
"tags"/"date" without knowing built-in vs custom); PropertyTypeMenu for the new
kind; "ADD" button. Enter/Tab commits, Esc cancels. Typing an unset built-in
name surfaces the built-in row instead of creating a shadow custom key; existing
keys aren't clobbered. Initial value: list→[], checkbox→false, number→0, else
"". `metadata-open-add-property` event opens it programmatically.

### 2.10.7 Cross-cutting metadata systems
- **Property registry** (`propertyRegistry.ts`, feeds Settings → Properties):
  enumerates EVERY property as one descriptor list — core spine (13 keys, order
  `type, area, project, tags, tier, active, people, source, ref, date, cal
  title, related, description`), task fields (status/priority/dueDate +
  TASK_SCHEMA extras like assignee), vault-discovered custom keys. Each row:
  label ("Subjects" for tags), sublabel ("is-a · single", "tags · is-about ·
  multi", "1–3", "inherited", "task", "custom · multi"), type badge
  (Text/List/Number/Date/Select/Checkbox — type & tier read as Select), ★ pin
  toggle (write-through to the shared `pinnedFields` store), shortcut tier
  (registry command vs property-binding overlay).
- **Field provenance** (`fieldProvenance.ts`): vault-KV side table `objectId →
  field → {reason, source: ai|calendar|inherited|user, at}` — explanation only,
  never in the data. Renders as the ✨ sparkle with hover "Why: {reason}".
  Written by the Alt+M commit (ai) and the calendar-date suggestion (calendar).
- **Chip color** (`chipColor.ts`): deterministic hash into a fixed 12-color
  palette (§3.6) so the same value gets the same color across chips, word cloud,
  graph, kanban. Chips only colorize when theme = "colorful"; default theme uses
  the flat primary tint.
- **UI-state persistence keys** (never object data):
  `app.metadata.propertyOrder.v1` · `app.metadata.customPropertyOrder.v1` ·
  `app.metadata.groupLayout.v1` · `app.metadata.pinnedFields.v1` ·
  `app.metadata.customPropertyTypes.v1` · `app.metadata.arrange.v1` ·
  `app.hiddenProperties.v1` · `app.rightSidebar.view.v1` ·
  `app.rightPanel.open.v1` · `liv.rail.panelOpen.v1` ·
  `app.rightSidebar.filterFacets.v1` · `app.tasks.quickFilterPins.v1` ·
  `app.localGraph.settings.v1`; vault keys: `app.vocabulary.v1`,
  `app.fieldProvenance.v1`, `app.objectVersions.v1`, `app.typeSchemas.v1`.

### 2.10.8 Per-kind differences
- **Note**: all fields; note-only type/source/ref, path-move, subnote-of
  breadcrumb, extraction blocks (§2.12.3), archive + trash. Decide axes: all.
- **Task**: suppresses generic people/date rows; dedicated Task block (§2.15.10);
  `type` ∈ action/decision/reminder via the shared type row; metadata patches
  map spine→task fields explicitly (people→assignee,
  status/priority/dueDate/recurrence round-trip). Decide: subjects, people. Not
  archivable/trashable from the header.
- **Contact**: kind-schema block (above); archive + hard delete; rename via
  `_contact.name`. Decide: subjects, people.
- **Event**: spine fields only; archivable. Decide: subjects, people.
- **File**: not renameable; path = `blobRef`; format from filename; no
  archive/trash header actions. Decide: subjects, people.
- **List**: `description` mirrors `_list.description`; shared fields nest under
  `_list.metadata`. Archivable, renameable. Decide: subjects.

## 2.11 Alt+M — the "Decide" commit tray (D09)

### 2.11.1 Trigger & modes
Commands: `metadata:suggest` = **Alt+M** (toggles — pressing again closes,
discarding), `metadata:reevaluate` = **Alt+Shift+M** (always forces
replacements); also the header Sparkles button ("The AI never appears on its own
— the user invokes it", MetadataEditor.tsx:3201). Setting `metadataSuggestMode`:
`missing` (default — only unset fields; single-pick fields already chosen are
not re-opened, except type=="atomic" counts as unchosen), `reevaluate`, `ask`
(behaves as missing for plain Alt+M). Opening also auto-expands "More" so the
whole property set is visible during review.

### 2.11.2 Suggestion engine — two layers
- **Deterministic** (`src/lib/metadataSuggest.ts`, always available): ranks the
  user's EXISTING vocabulary per axis. Axes per kind (`AXES_BY_KIND`): note →
  types+subjects+people+sources; task/file/contact/event → subjects+people;
  message/list → subjects. Score = `1·habitScore + 2.5·contentMatch +
  1.5·coOccurrence`; only positive scores surface; top-N per axis: types 5,
  subjects 4, people 4, sources 3. contentMatch = whole-phrase presence of
  canonical or alias in normalized (singularized, separator-folded) title+body;
  coOccurrence = fraction of same-project notes carrying the value. Reason
  strings (chip tooltips): "its name appears in this note" / "notes in this
  project usually get it" / "you use it often" / "it's in your vocabulary".
  **Never invents values** — pool = seed ∪ grown. Inherited area/project come
  from context, shown dim, not suggested. **suggestedDate**: rule-based calendar
  match — a non-archived event whose normalized title equals or cleanly
  contains/is-contained-by the note title proposes its day (exact match wins);
  skipped in missing mode when a date exists. Reason: `Matches calendar event
  "X" at HH:MM`.
- **AI layer** (`src/lib/aiSuggester.ts`): Haiku, temperature 0, JSON
  `{type:{value,why}|null, subjects:[{value,why}], people:[{value,why}],
  description|null}`. Conservative prompt; "thin note" (<12 body words) rule:
  type only if the TITLE makes it obvious, ≤1 subject / ≤2 people backstop.
  Validation before display: type must normalize-match the pool; subjects drop
  project-style path tags; **people must literally appear in the note text**;
  per-pick `why` (≤8 words) becomes the chip tooltip. AI chips score 1000 (rank
  above deterministic), merged+deduped by axis+value; in "missing" mode anything
  already on the note is filtered. Description proposed only when empty
  (missing) or always (reevaluate), collapsed to one line ≤200 chars. Any
  failure/no-key → silently falls back to deterministic.

### 2.11.3 Tray anatomy (:3339–3887, renders at the top of the inspector)
- Header: "✨ DECIDE" (uppercase, primary, pulses while loading) · "`{setCount}`
  set · `{commitCount}` to confirm" (setCount counts non-default type, tags,
  people, source, project, area, date, description, custom keys) · "close" link
  (tooltip "Close (Esc, or press Alt+M again)").
- States: loading "Reading your note…"; has-staged "Review — click to
  include/exclude, ✎ edit, × remove, + add — then Commit."; empty "No new
  suggestions — fill what's recommended below…" or "Already classified — add or
  change any field with + field, then Commit."
- **Axis rows** — one per axis with staged chips or pulled in via "+ field". Row
  = numbered kbd badge (1-based slot among visible rows; filled primary when the
  keyboard cursor is on it) + axis icon + label (min-w-16) + chips. Order: Type,
  Subjects, People, Source, Area, Project, Tier (types/sources omitted for
  non-notes). Focused row `bg-primary/10 ring-1`.
- **DecideChip** (:359–445): pill; selected = primary tint + ✓, unselected = dim
  outline. Click body toggles include/exclude; ✎ pencil → inline edit input
  (Enter saves+selects, Esc/blur reverts); × removes from batch.
  Keyboard-focused chip gets an outer ring. **Single-pick axes are radios**;
  multi axes stage all-selected, singles select only the top pick (:1789–1806).
  Tooltip: `<verb> "value" — <reason>. Click to include/exclude Commit.`
- **AxisAddInput**: dashed "+ add" pill per axis → input with a datalist of pool
  values (cap 30); Enter stages the typed value (reason "you added it";
  case-insensitive dedup; re-staging selects; honors radio), Esc/empty-blur
  closes. Auto-opens when an axis is pulled in empty or via the `a` shortcut.
- **Description row**: editable 2-row textarea of the AI draft; "✓ will
  save"/"include" toggle + "remove".
- **date row**: date input + reason line + include toggle + remove. Commit
  writes provenance `{source:"calendar"}` so the field shows ✨.
- **Extra fields** (`EXTRA_FIELD`, :278–326): non-chip built-ins reachable from
  the tray — Active (toggle), Date (date), Event/calendarTitle (text),
  Ref/sourceRef (url, note-only). Pre-filled from current values; per-row ×.
- **Custom draft**: inline name + kind select (text/number/date/check/list/
  hard-detail) + typed value control; list = comma-separated. Commit persists
  both the value and the name→kind mapping.
- **"Recommended for {kind}"**: dashed chips for TYPE_FACETS facets that are
  unset and not already in the tray — one tap pulls the field in.
- **"+ field" popover**: categorized picker — Classify / Topics & people /
  Context / Priority / Schedule, then "Custom property…". Lists hidden axes +
  hidden extra fields with icons; empty state "All built-in fields are already
  shown."
- **Commit button**: primary "Commit {n}" (disabled at 0) + caption "nothing is
  saved until you commit".
- **Hint bar**: `1–{n} jump · ←/→ pick · Space toggle · a add · Ctrl+Enter
  commit · Esc back`.
- After commit: green "✓ Committed — Type: pitch · Subjects: ai, pricing"
  confirmation for 4s.

### 2.11.4 Tray keyboard layer (:1034–1164)
Active only while the tray is open and the event target is not a text field;
the "+ field" popover owns its keys. **Ctrl/Cmd+Enter commits from anywhere,
even mid-typing.** `1–9` jump to the Nth visible property; `↑/↓` move between
properties (wrap; chip cursor resets); `←/→` pick among the focused axis's
chips (wrap); `Space`/`Enter` toggle the focused chip; `a`/`+` open the focused
axis's add-input; `Esc` steps back to tray level first, then closes. Cursor
defaults to the first visible axis on open; mousedown on a row syncs the
keyboard cursor; the focused row scrolls into view (`block:"nearest"`).

### 2.11.5 Commit semantics (`commitStaged`, :2026–2195)
One atomic pass over a working copy: chip axes (types/sources rewrite note-only
fields; subjects/people append-dedupe; area/project/tier replace), extras,
inline custom (also persists name→kind), description (only if changed),
suggested date (with calendar provenance). Per applied AI value: field
provenance `{source:"ai", reason}` for type/tags/people/source; `recordUse`
vocabulary bump (except tier and project-path subjects). Saves once, sets the
confirmation summary, force-opens receiving groups, records `committedIds` to
drive the "N new" badge on More. Stale-async guard: a suggest resolving after
the tray closed is dropped (`suggestReqId`). Closing the tray discards
everything un-committed.

## 2.12 Connections (relations, backlinks, extraction)

### 2.12.1 Data & rules (`src/lib/relations.ts`)
- All linking converges on id-based `metadata.relations` entries `{id, type?,
  origin}`. `origin`: **"manual"** (user-made: Add relation / Attach to… /
  Suggest / convert; legacy entries with no origin) vs **"wikilink"** (derived
  from `[[Title]]` in the note body). `syncWikilinkRelations` runs on every
  save: adds wikilink-origin relations for resolving `[[..]]`, removes those
  whose bracket is gone, **never touches manual ones**; a manual link to the
  same target wins (no dup, no downgrade). UI removal only works on manual rows
  (wikilink rows must be edited in the body); `{force:true}` exists for the
  reconciler.
- Resolution order for `[[payload]]`: literal id → `id:` suffix →
  case-insensitive title → customPath / filename / stem; then the precise
  `[[Title|context]]` composite (context = project → area → parent-note title)
  → bare head as title (Obsidian alias fallback) (`buildResolver`, :274–340).
- Backlinks are computed, never stored: every object storing a relation to the
  focused id (`getBacklinks`).
- **Suggest related** — local heuristics only: shared project +5, area +2, per
  shared tag +2 (cap 3), per shared person +2 (cap 3), title mention +4, single
  title-word overlap +1; threshold 2, limit 8, excludes anything already linked
  either direction; each signal recorded as a human reason chip
  (`suggestRelations`, :518–607).

### 2.12.2 UI (`ConnectionsSection`, MetadataEditor.tsx:4868–5243)
Collapsible "Connections" section (default closed) in every panel mode. Inside,
a "RELATED" card (network glyph header) with two header actions:
- **"✨ Suggest related"** → panel of suggestion cards: kind icon + title + ✓
  accept (creates the relation) + × dismiss, and up to 4 reason chips ("shared
  project: Liv", "tag: #ui", "title mention"). Empty state explains the signals.
- **"+ Attach to…"** → search-to-link: autofocused search input (same suggestion
  source + row style as the inline `[[` LinkPicker: kind icon, title, context
  breadcrumb, kind tag), token-AND filtering, 8 rows, excludes self +
  already-linked; a small right-aligned "type…" input for the optional relation
  label ("blocks", "parent"…); ↑/↓ + Enter keyboard-first; hint "↑↓ choose ·
  Enter link".
List body: **outgoing** rows (empty state "No relations yet. Use "+ Add
relation".") then a "LINKED FROM" subheader + **incoming** backlinks
(reciprocals already shown as outgoing are dropped). Each row: real KindIcon,
title, then: chain glyph 🔗 for wikilink-managed rows (tooltip "Linked from a
[[wiki-link]] in this note's body — edit the body to change it"; **no × for
these**), uppercase primary chip for the relation `type`, muted "↩" chip for
incoming rows. Click: notes open in the Composer; other kinds re-focus the
inspector onto themselves. Hover × removes manual outgoing relations only.
Re-adding an existing target replaces its `type`; a manual add over a wikilink
promotes it to manual.

### 2.12.3 Note-only extraction blocks (inside Connections)
- **Extract from selection** (:5258–5489): header "🪄 EXTRACT FROM SELECTION";
  copy "Highlight text in the note, then extract it as a new object (links back
  here). Nothing selected → uses the whole note." Three buttons **Task / Contact
  / Event** → AI reads the live `window.getSelection()` (fallback: whole body) →
  returns ONE `ProposedObject` (kind-specific JSON: task title/date/people/
  details; contact name/email/phone/company/role/details; event
  title/date/people/details; "NEVER invent a date or contact detail") →
  **preview card** (kind icon + title + pills: due/on date, @people, email,
  phone, company, role + details line) → primary "＋ Create task/contact/event"
  creates it, **auto-relates it back to the source note (manual origin)** and
  focuses it; de-dupe via `sourceNoteId` — if a task/event from this note
  already exists it links to that instead ("A task already exists from this note
  ("…"). Linked it."). Errors inline: "No AI key set. Add one in Settings → AI
  to extract." / "Couldn't find a usable object in the selection." Whole-note
  "Convert to…" was removed deliberately (owner direction B — notes stay notes).
- **Meeting notes → tasks** (:5498–5673): bordered card "☑ MEETING NOTES →
  TASKS". Idle: full-width "✨ Extract action items → tasks". Extracting:
  "Reading the note…". **Review** (nothing written until confirm): "Review N
  proposed tasks" + checkbox rows (all pre-selected; per-item title, "due
  YYYY-MM-DD" and "@assignee" pills; click toggles, deselected rows dim to 50%)
  + primary "＋ Create N tasks" (disabled at 0) + Cancel. Created: "✓ Created N
  tasks." + "Extract again". Lib (`meetingToTasks.ts`): temp-0 stream, JSON
  `{tasks:[{title,dueDate,assignee[]}]}`; strict ISO date validation (vague
  dates dropped); title-dedup; created via canonical `addTask` with
  `type:"action"`, inherited area/project/workspace, back-link `sourceNoteId`.

## 2.13 Right panel — remaining tabs

### 2.13.1 Snapshots tab (`SnapshotsAndVersionsView`, RightSidebar.tsx:2315–2696)
Header "Snapshots — Workspace layouts and focused document versions." Two
sections:
- **Workspace** — "Restores active workspace, department, tab groups, splits,
  and open tabs." + primary "＋ Save" (auto-named `Workspace YYYY-MM-DD HH:MM`;
  flushes the composer first via `workspace-flush-request`). Rows: history
  glyph, name, "{date} - N workspaces", hover-strengthened **Restore** (confirm:
  "Current open tabs and department state will be replaced.") and **Delete**
  (confirm, danger). Empty: "No workspace snapshots yet."
- **Document version** — bound to the focused object (subtitle = its title, or
  "Focus a note, task, file, or list to version it."); "＋ Save" captures an
  `ObjectVersion` (`objectVersions.ts`): full deep-cloned note (body hydrated
  from disk if needed) for notes, metadata-only for other kinds; auto-name
  `"{title} - YYYY-MM-DD HH:MM"`. List: search box (label/name/body), grouped
  under relative headers Today / Yesterday / Earlier this week / Earlier this
  month / Older; each row shows label-or-name, date, and an 80-char body excerpt
  / char count / "· metadata". Row actions: **Restore** (confirm "The current
  document content/properties will be replaced."; notes restore the full note
  with fresh lastEdited; other kinds patch metadata per kind; broadcasts
  `object-version-restored` so the composer reloads), **Preview** (notes only —
  inline `<pre>` up to 4,000 chars, toggle Hide), **Label** (inline input,
  Enter/✓ commit, Esc/✗ cancel; label displays instead of auto-name), **Delete**
  (confirm). Empty states: "Nothing selected — Click a document or note to save
  and restore versions here." / "No document versions yet." / `No versions
  match "q".`
- ⚠ A separate composer-side `VersionControlPanel`
  (`composer/VersionControlPanel.tsx`) also ships (§2.14.2, Snapshots pane):
  workspace-store per-tab text `Snapshot`s — a distinct system from
  `objectVersions`; both replicate. ⚠ Unrendered placeholders `SnapshotsView` /
  `WorkspaceSnapshotsView` (RightSidebar.tsx:2186–2313) — do not replicate.

### 2.13.2 Outline tab (RightSidebar.tsx:2754–2800)
Notes only: regex-parses `#`–`######` heading lines from the body; renders an
indented list (8 + (level−1)·10 px left padding), hover brightens. Empty
states: "Outline — Open a note to see its headings here." / "No headings — Add
an H1 — H6 to the note and it'll appear here." ⚠ Rows are NOT click-to-scroll
here (cursor-default) — the Composer's own OutlinePane (§2.14.14) is clickable.

### 2.13.3 Graph tab — local graph (RightSidebar.tsx:2802–3186)
Obsidian-style local graph, focused object = hub. BFS alternating node kinds:
hop 1 = the hub's metadata VALUES (area/project/tags/people), hop 2 = other
objects sharing those values, hop 3 = their values, up to depth. Header: "Local
graph" + cog → settings strip: Depth 1–3 segmented buttons, Max nodes range
5–150 step 5 (persisted `app.localGraph.settings.v1`). Layout: pure inline
radial (no graph lib) in a max-w 300px square — hub pill centered (primary bg),
ring nodes placed by index around the circle, radius 16–46% scaled by hop;
straight SVG edges stroke 0.4. **Object nodes** = neutral pills (click = focus,
and open in Composer if a note); **value nodes** = colored chips via `chipColor`
(click = apply that facet filter + open the QuickSwitcher). An isolated object
renders as a lone hub with copy "X has no connections yet — add an area,
project or tags to link it…"; else "How X connects — N nodes within D hops" +
footer "Click a note to open it · a value to filter the vault."

### 2.13.4 Copilot tab — §2.23.9.

## 2.14 Editor — the Composer's markdown surface

Stack in Liv: CodeMirror 6 + `@codemirror/lang-markdown` (GFM base,
`codeLanguages: languages` for fenced-block highlighting), a custom
live-preview decoration pipeline, and floated popups (slash menu, link picker,
AI bubbles). Primary sources: `src/components/composer/MarkdownEditor.tsx`
(2,226 ln), `src/lib/livePreview.ts` (2,232 ln),
`composer/editorCommands.ts`, `SlashMenu.tsx`, `LinkPicker.tsx`,
`EditorToolbar.tsx`, `PageRuler.tsx`, `blockEmbeds.ts`, `Composer.tsx`
(TabPaneContent ~ln 5390–6232). In lotus this whole surface sits over the
existing **editor-over-C-seam**; behaviors below are the contract.

### 2.14.1 Surface layout (inside one Composer tab pane)
Top→bottom inside a centered column capped at `max-w-[1000px]`, `px-12 pt-5
pb-6` (Composer.tsx:5930):
1. **Floating top-right buttons** (absolute, right-2 top-2): Reading-view toggle
   (Eye ↔ Pencil, per-pane, ephemeral) and a "Note actions" `⋯` button.
2. **Note header** (Composer.tsx:5977–6128): Title `<input>` (1.7rem bold,
   placeholder "Untitled", spellCheck off), an AI "Suggest a name" sparkle
   button, optional "Let AI name it later" pill, then a read-only context row:
   kind icon · subnote lineage `Parent / …` · workspace breadcrumb · project ·
   "Created …" · "Edited …" (12px muted). Metadata is NOT editable here — only
   in the right rail.
3. **Editor host** (`MarkdownEditor`, overflow-y-auto): in order —
   **sticky toolbar row** (sticky top-0 z-10, hidden in reading view):
   formatting toolbar (left, flex-1) + "Source" pill + "AI" pill
   (MarkdownEditor.tsx:1554–1607); then **the page**: `w-full px-4 pt-3 pb-10`
   wrapper → `bg-background` page (no card border — "calm page defined by
   whitespace") containing the **PageRuler** strip (px-5 pt-1, hidden in reading
   view) and the editor mount (`min-h-[60vh] px-5 pb-12 pt-3` so an empty note
   still looks like a page).
4. Right-click anywhere in the editor opens a **context menu** with one item:
   "Extract selection to new note — Ctrl+Shift+E" (Composer.tsx:6132–6228). Esc
   or click-outside dismisses.
The editor's DOM is keyed per tab; switching notes remounts the editor (fresh
undo history per note).

### 2.14.2 Save model (as the user experiences it)
- **No Save button, no dirty indicator.** Typing updates the tab in state; a
  debounced persist effect mirrors the active tab into the Note store on every
  body/title/project/area change (Composer.tsx:1806–1848); the store's disk
  writes debounce ~400ms — the `.md` at `Areas/<area>/<project>/<title>.md`
  rewrites when the user pauses. (§4: lotus replaces the disk mirror with
  commands into the log; the debounce cadence and no-save-button UX stay.)
- Switching tabs/workspaces **flushes the pending write first**
  (`flushPendingPersist`); closing a tab persists directly.
- A **bare fresh tab is never persisted**: default label + empty body ⇒ no note
  minted; junk "Untitled.md" explicitly guarded (`tabHasRealContent`,
  Composer.tsx:2913–2918).
- **External value sync**: the editor owns the buffer. A bounded set of every
  emitted doc string (`emittedRef`, 100–200 entries) distinguishes React echoes
  from genuine external changes (file watcher, restore); external changes
  replace the doc while carrying the caret (clamped) — never resetting it to 0
  (the historical caret-jump fix, MarkdownEditor.tsx:583, 1285–1301).
- **Ctrl/Cmd+Enter = "send"**: commits the note, downloads markdown, optionally
  snapshots; in unified layout it then opens a fresh editor tab; in capture mode
  it may clear title+body (`clearOnSend`) (Composer.tsx:2739–2776).
- **Snapshots** (right-rail Snapshots pane inside the Composer,
  `VersionControlPanel.tsx`): per-workspace list with search, "Save snapshot"
  button, settings cog (toggles: Clear editor on send / Snapshot on send /
  Prompt for snapshot name), two collapsible folders "Workspace history" and
  "Note history · <tab>", rows = commit icon + name + timestamp + `auto` badge +
  hover Rename/Restore/Delete. Restore replaces the ACTIVE tab's body+title.
- **Composer note history**: back/forward arrows over the visited-note-id stack
  (§2.6), tooltips "Back to previous note (Ctrl+[)" / "Forward … (Ctrl+])".

### 2.14.3 Title handling
- The title is an **explicit field**, never derived from the first line/heading
  (owner decision, Composer.tsx:5780–5798). It drives note `title`, tab-strip
  `name`, and the on-disk filename slug.
- The input holds a **local draft** while focused (external renames can't move
  the caret mid-type); resyncs on blur or tab switch.
- **New notes focus the TITLE first** (select-all); Enter or ArrowDown jumps
  into the body (Composer.tsx:5565–5586, 5990–5998).
- Renaming (tab rename or title edit) moves the `.md` file on disk with
  collision-safe unique-path resolution; Office-backed tabs (.docx/.xlsx) get
  their real file re-materialised at the new name. Rename never changes note
  identity (id stable — the rename-duplicate fix, Composer.tsx:2894–2938).
- **AI naming** (`src/lib/titleSuggest.ts`): sparkle button → up to 3 suggested
  titles (≤6 words, same language, per-kind hint: task = imperative verb phrase;
  contact = name/role; list = noun phrase; event = meeting name; Haiku, temp
  0.3) as clickable chips ("Name it: [chip][chip] ✕"); accept replaces the
  title, reject dismisses; never auto-applied. Calm hints when no API key ("Add
  an Anthropic API key in Settings → AI to suggest names.") / not enough content
  ("Write a little more, then try again — nothing to name yet."). **"Let AI name
  it later"** pill (shown while Untitled or flag on) sets
  `metadata.custom.livNameLater`; when such a note gains body content while
  still Untitled the sparkle auto-highlights primary (`nameLaterReady`); the
  flag is stripped on accepting a name.

### 2.14.4 View modes — three independent switches (replicate all three)
1. **Live Preview (default)**: Obsidian-style — markdown renders everywhere
   EXCEPT where you're editing; raw syntax reveals contextually (§2.14.5).
2. **Source mode** (toolbar "Source" pill, aria-pressed, persisted globally at
   `liv.editor.sourceMode`): ALL decorations suppressed — inline, line, and
   block widgets — raw markdown verbatim. Toggled via a compartment/facet so no
   remount; cursor/history/scroll preserved. Code/data blocks are edited here;
   tooltip "Source mode on — raw markdown; edit code blocks here".
3. **Reading view** (per-pane Eye toggle, ephemeral): editor becomes read-only;
   cursorLine = −1 so EVERY line renders; inline reveals disabled — markup never
   shows raw. Toolbar, ruler, and AI affordances hide.
Plus a global **reading mode** setting (`editor.readingMode`, theme.ts:229–243):
editor stays editable but syntax markers hide *even on the active line*
(`.cm-reading-mode` + `.cm-md-syntax-marker`, styles.css:533–546) — a Docs-like
clean surface, distinct from reading view.

### 2.14.5 Reveal rules (what happens to syntax at the caret)
- **Block markers** (`#`, `>`, list `-`/`1.`, task `[ ]`): **whole-line reveal**
  — hidden on every line except the cursor's (livePreview.ts:1661–1666). Heading
  text stays styled big even while editing (styling marks always apply; only
  marker tokens hide) — a heading never resizes as the caret enters/leaves.
- **Inline markers** (`**`, `*`, `~~`, `` ` ``, `[]()`, URL, sub/sup):
  **per-element reveal** — a marker stays hidden unless the selection actually
  touches THAT element's range (walk up to the enclosing
  Emphasis/Strong/InlineCode/Strikethrough/Sub/Sup/Link/Image). Editing one bold
  span doesn't flash other marks on the line. Caret exactly at an element edge
  still reveals (`selectionTouches` uses inclusive bounds).
- **Bare autolink URLs** with no Link parent are left visible (never hidden
  into nothing).
- **Block constructs** (tables, `$$` math, mermaid, data-view/habit/embed/chart
  fences) render as widgets replacing the whole block when the cursor is
  OUTSIDE; placing the cursor inside (or clicking the widget) flips it back to
  raw editable text. Block widgets MUST live in a StateField
  (`blockDecorationsField`), not the view plugin — documented crash otherwise
  (livePreview.ts:1996–2000).
- Decorations rebuild on every doc/selection/viewport change and source-mode
  flip; a build error disables decorations for that frame with a console warning
  instead of crashing (`safeBuildDecorations`).
- Docs >4000 lines: all whole-doc block scans (code fences, tables, math,
  mermaid, data-view, habit, embed, chart) are skipped for perf.

### 2.14.6 Per-syntax rendering catalogue (theme MarkdownEditor.tsx:870–1254 + livePreview widgets)
- **Body type**: 17px sans, line-height 1.65, kerning+ligatures; `.cm-line`
  0.1em vertical padding; no active-line highlight.
- **Headings** H1–H6: 1.6em/700 (H1, letter-spacing −0.01em), 1.35em/700,
  1.18em/600, 1.04em/600, 1em/600, 1em/600 muted (H6). `#` marks hidden
  off-line, faded (opacity 0.5, muted) on-line. Trailing `{#custom-id}` hidden
  off-line.
- **Bold/italic/strike/inline code**: `**`→700, `*`→italic, `~~`→line-through
  opacity 0.55, backticks→mono 0.92em on a muted pill (padding 0.05em 0.4em,
  radius 0.3em).
- **Highlight** `==text==`: yellow (#facc15 @32%) rounded background; `==`
  hidden off-line. **Comments** `%%text%%`: fully hidden off the active line.
- **Tags** `#tag` (word-boundary, after start/space/bracket): primary pill,
  radius 999px. **Footnotes** `[^ref]`: primary mono 0.85em (styled, not
  hidden).
- **Markdown links** `[text](url)`: text primary+underline; brackets/parens/URL
  hidden off-line. ⚠ Clicking an external `scheme:` URL does NOTHING (the open
  handler drops scheme-prefixed targets, Composer.tsx:614–616, 2029) — shipped
  behavior, likely a gap (§6).
- **Bullet lists**: marker replaced off-line by a depth-cycled glyph — depth%3:
  `•` (1em) / `◦` (0.95em) / `▪` (0.78em) — muted, 1.2em wide centered.
  **Ordered lists**: marker widget right-aligned, tabular-nums, min-width
  1.55em; supports `1.` and `1)`.
- **Indent guides**: indented non-blank lines get repeating 1px vertical guides
  every 2ch, up to 8 levels; blank lines deliberately excluded (stacked-guides
  fix).
- **Task lines** `- [ ] ` / `- [x]` (also `*`, `+`, `1.` prefixes; `x`/`X`):
  off-line the `- [x]` run is replaced by a **checkbox widget** — 0.95em
  rounded-3px box; checked = primary fill + white ✓. Click toggles by editing
  exactly one char in the source (`" "`↔`"x"` at markerStart+1, userEvent
  `input.task.toggle`), then refocuses. Checked line's text muted +
  line-through (`.cm-md-task-done`). **On the active line the checkbox is NOT
  rendered** — raw source shows (inline widgets on the composition line are
  jumpy, livePreview.ts:1747–1759). **State lives only in the note's text.**
- **Blockquotes**: `>` hidden off-line; content muted italic.
- **Callouts** `> [!type] Title` (Obsidian syntax; `+`/`-` fold suffix parsed
  but ignored): 3px left border + tinted background; warning/caution/attention
  = amber, danger/error/fail = red, success/check/done = green, everything else
  = primary. `[!type]` hidden off-line; title weight 650; continuation `>`
  lines inherit the callout line class. No icon, no collapse.
- **Horizontal rule** (`---`/`***`/`___`, 3+, spaces allowed): replaced off-line
  by a 1px hairline widget in a 1.6em-tall block.
- **Inline images** `![alt](src)`: replaced off-line by `<img>`, max-height
  320px, max-width 100%, radius 0.4em; http/data/blob/file/asset URLs load
  directly; vault-relative paths resolve async via the asset protocol.
- **Inline math** `$…$`: KaTeX span off-line; requires non-space just inside
  delimiters ("$5 and $7" is not math); escapes respected. **Block math**
  `$$…$$` (single- or multi-line): centered display widget; render failure
  falls back to raw source in red. (§4: native math rendering is one of the
  flagged gaps.)
- **GFM tables**: header + `|---|` separator + contiguous body rows → a real
  table widget with alignment from `:---:`, escaped-pipe support, per-cell
  minimal inline rendering (code/bold/italic/strike/links/wikilinks as spans).
  Header cells weight 650, muted background. Horizontal scroll wrapper.
  **Mousedown on the table drops the cursor at the block start**, flipping it
  raw for editing.
- **Fenced code blocks**: every fence line gets a mono tinted
  `.cm-md-codeblock` line style; nested language highlighting; fence
  lines/CodeInfo hide off-line; cursor inside = plain editable. Deep-edit
  story: render in live/read mode, edit in source mode.
- **Mermaid** fences: lazy-loads mermaid (theme from current scheme,
  securityLevel strict), renders SVG centered; "Rendering diagram…"
  placeholder; errors show `Mermaid error: …` + source in red mono. (§4 flagged
  gap.)
- **Sub/superscript** `~x~`/`^x^`: 0.75em. **Emoji** shortcodes: primary color.
  **Autolinks**: primary.

### 2.14.7 Wiki-links `[[…]]` — full lifecycle
- **Typing**: after `[`, a second `[` auto-closes to `[[]]` with the caret
  between. A caret inside an unclosed-to-caret `[[…]]` pair on one line opens a
  **wiki-link session** {from,to,query,anchor} (`detectWikiLinkSession`); the
  session re-emits on doc/selection/scroll (rAF-coalesced re-anchoring so the
  popup tracks the caret; closes if scrolled out).
- **LinkPicker popup** (LinkPicker.tsx; host-owned): fixed w-80 rounded-xl
  bordered popover, header "Link to note, file, task… · type / to drill into
  subnotes" (or "Link to <query>"), max-h-64 list, footer "↑↓ choose · Enter
  insert · / drills subnotes · Esc close". The **editor keeps focus**;
  ArrowUp/Down/Enter/Tab/Escape are consumed by a highest-precedence keymap only
  while a session is open (the fix for "Enter inserted a newline"). Hover moves
  the highlight; mousedown selects without stealing focus.
- **Suggestions** (buildSuggestions, LinkPicker.tsx:95–202): unified pool of
  local notes + scanned vault markdown + all other object kinds
  (task/file/list/contact/event). Row: real KindIcon (format-aware, e.g. red
  PDF page), title, full `Parent / Child` path line when it differs from the
  title, up to 3 metadata chips (area · project · first tag), right-aligned
  kind label (`note`/`task`/…/`new`). Rows sharing the current note's project
  (+2) or area (+1) float stably to the top. Cap 80.
- **Disambiguation**: duplicate titles insert `[[Title|context]]` (context =
  project/area/parent breadcrumb); unique titles insert bare `[[Title]]`. The
  durable relation is id-based (§2.12.1).
- **Path grammar** (decided model, `/` = separator): `Parent/leaf` drills into
  that parent's children (split on last `/`); leading `/leaf` = children of the
  CURRENT note; a non-matching leaf appends "➕ Create subnote *leaf*" — Enter
  materialises the child (inherits parent's project/area/tier/tags via
  `createSubnote`), inserts its title, but does **not** auto-open it (the user
  is mid-sentence; slash "New subnote" is the jump-in path).
- **Unresolved / forward links**: a plain query with no exact title match
  appends "Link to new note *query*" — Enter inserts `[[query]]` as a valid
  forward link (no note created). Empty picker: "No matches. Keep typing — add
  a `/` to create a subnote."
- **Insertion**: replaces the inner `[[…]]` range; caret lands **after** the
  closing `]]`.
- **Rendering off the active line**: if the payload resolves against the cached
  object pool (by id, `kind:id`, title, `title|context`, or note path/filename
  — `buildWikiResolver`, livePreview.ts:82–143; pool refreshed on
  `notes-changed`/`workspace-change`), the whole `[[…]]` is replaced by an
  inline **chip**: per-kind colored glyph (note #4a8bd4, task #1f9d57, file
  #8a94a6, contact #d4538e, event #e0533d, list #2b6cd4, message #7c5cd0) + the
  target's CURRENT (rename-safe) title in a pill (primary tint bg, 1px primary
  border, radius 0.45em; hover deepens). Hover tooltip "Title · context".
  **Click navigates**: notes dispatch `note-open`; other kinds record
  nav-history, focus in the inspector, open the right panel. Unresolved
  payloads fall back to styled `[[text]]` — primary, 1px bottom border,
  brackets hidden off-line, alias `|` head hidden (display shows the part after
  `|`). Active line: always raw editable text.
- **Embeds `![[…]]`** keep an inline pill treatment (`.cm-md-embed`), never
  chips.
- **Click-to-open**: a click resolves `[[..]]`/`[text](url)` at the click
  position and opens when it hits a styled link element, OR Ctrl/Cmd/Alt is
  held, OR the clicked line is not the focused active line. Note targets open
  in the current tab (replacing it), or focus an existing tab holding that
  note; a miss toasts `No note found for "target"`. Wiki alias/`#heading`
  suffixes are stripped for resolution.

### 2.14.8 Slash menu `/`
- **Trigger**: `/` at line start or after whitespace, caret within the unbroken
  `[^\s/]*` query run (space closes). Editor-owned session. Popup: fixed w-80,
  header "Insert a block…"/"Insert *query*", max-h-72, footer "↑↓ choose ·
  Enter insert · Esc close"; flips above the caret when <320px below.
  Filtering: every whitespace token must hit title+keywords. Enter/Tab inserts,
  Esc closes, click-outside closes; empty state "No blocks match. Press Esc to
  keep typing."
- **Catalogue** (SLASH_ITEMS order; insertion → caret landing,
  editorCommands.ts:316–363):

| id | inserts | caret |
|---|---|---|
| data-view | ```` ```data-view\nbase-id: ""\n``` ```` | inside the quotes |
| heading | `## ` | after `## ` |
| checklist | `- [ ] ` | after marker |
| code | ```` ```\n\n``` ```` | language slot after opening fence |
| callout | `> [!note] Title\n> ` | second-line body |
| divider | `---\n` | line after |
| quote | `> ` | after `> ` |
| new-subnote | *intercepted by the Composer* (below) | — |
| related | `Related: [[]]` | inside `[[ ]]` (hands off to the wiki picker) |
| habit | ```` ```habit\n``` ```` (defaults: 84-day heatmap) | fence body |
| chart | ```` ```chart\nfield: \n``` ```` | after `field: ` |
| embed | ```` ```embed\n\n``` ```` | empty body line (paste URL) |
| prompt:run:\<id\> | one dynamic "Run prompt…" entry per saved custom prompt, Wand icon + "AI" pill | — |

  Insertion replaces the `/query` range; if text precedes the trigger, a
  leading newline is prepended so block constructs sit on their own line. ⚠ A
  `soon` pill style ships with no item using it.
- **New subnote** (Composer.tsx:5889–5920): creates a child of the current note
  (title "Untitled"), replaces the trigger with `[[Untitled]]`, and opens the
  child via `note-open`. If the current tab isn't persisted yet, the trigger is
  silently removed.
- **Run prompt** (editorCommands.ts:374–490): operand = the selection if
  passed, else the current line with the `/query` stripped. Swaps the operand
  for a `⟳ PromptName…` placeholder and **streams the AI reply in place**,
  re-replacing the tracked span each chunk; on error/no-key restores the source
  (appending `⟵ no API key (Settings → AI)` for the key case). Nothing to run
  on ⇒ trigger dropped, no AI call.
- **Empty blocks stay raw**: an `embed` with no URL, a `chart` with no
  `field:`, an unresolved `data-view` id — all remain editable fenced text (or
  a "saved view not found" error card for data-view) rather than fake renders.

### 2.14.9 Fenced embed blocks (blockEmbeds.ts + livePreview widgets)
All render when the cursor is outside the fence; raw + editable inside; hosted
in `.cm-md-dataview` cards.
- ```` ```data-view ````: body `base-id: <id>` (+ optional `layout:`); resolves
  a saved .base and mounts the real `BaseFileView` — table layout uses the
  compact embedded render; non-table lenses (gallery/board/folder) mount the
  full view in a 420px (max 70vh) bordered frame, driven to the lens via
  `files-view-control`. Missing base ⇒ `Data-view: saved view "id" not found.`
  in red.
- ```` ```dataview ````: a literal Obsidian Dataview query (TABLE/LIST/TASK),
  parsed into a synthesized base; unparseable ⇒ left raw.
- ```` ```habit ````: optional `title:` / `days:` (clamped 7–365, default 84).
  Renders the live HabitWidget from daily-note `- [x] Habit (N)` checkbox
  points across local+vault notes. A muted one-line nudge above it: "Habit
  trackers live best on your Dashboard →" (click switches to Dashboard) — soft
  boundary, never blocks.
- ```` ```chart ````: `field:` (required; frontmatter prop or inline
  `field::`), optional `title:`/`days:` (2–3650)/`type: line|bar`. Renders
  MetricChart over every note carrying the field.
- ```` ```embed ````: single-line URL or vault path (bare line or
  `src:`/`url:`/`file:`/`path:` key). Routing safest→loosest: image extension →
  `<img>`; YouTube/Vimeo watch URL → `/embed/` 16:9 sandboxed player + "Open in
  browser ↗"; other http(s) → sandboxed iframe (no same-origin), 420px/max-70vh
  + fallback link; anything else → a labelled link (vault paths via asset URL).
  (§4 flagged gap: sandboxed web content has no native equivalent — see there.)

### 2.14.10 Toolbar (EditorToolbar.tsx)
Seven 28px round icon buttons, gap-0.5, on `bg-background/80`; every button and
the bar itself use `onMouseDown+preventDefault` so the selection never
collapses, then re-focus the editor. Each dispatches the same StateCommand as
its shortcut: Bold ("Bold (Ctrl+B)") · Italic (Ctrl+I) · Strikethrough · Inline
code (Ctrl+`) · Heading (=set H2) · Bullet list · Link (Ctrl+K). Right of it:
**Source** pill (Code2 + "Source", primary-tinted when on) and the **AI**
autocomplete pill (default OFF; tooltip "AI autocomplete on — Tab to accept,
Esc to dismiss"). Visible whenever not in reading view — always-on while
editing; no show-on-selection behavior (D19/IA-12: keep as-is).

### 2.14.11 Formatting command semantics (editorCommands.ts)
- **Heading toggle** `setHeading(n)`: applies to every line the selection
  touches; same level twice ⇒ strips; different level ⇒ switches; level 0 ⇒
  clears.
- **Inline wrap toggles** (bold `**`, italic `*`, strike `~~`, code `` ` ``):
  empty selection inserts a marker pair with the caret between (press again
  inside to unwrap); a selection already wrapped (inside or just outside its
  bounds) unwraps; otherwise wraps, keeping the text selected.
- **Insert link**: wraps selection (or "text") into `[text](https://)` with
  `https://` pre-selected for overtyping.
- **List toggles** (bullet `- `, numbered `n. `, task `- [ ] `): uniform
  apply/strip decided by the FIRST selected line; numbering increments across
  added lines; existing indentation preserved.
- **Swap line up/down**; **Mod+F** opens the in-editor search panel (beats the
  WebView find).

### 2.14.12 Editor keyboard map (complete, precedence order)
1. **Popup navigation** (highest; only while a slash or wiki session is open):
   ArrowUp/Down cycle (wrapping), Enter/Tab insert, Escape close. Slash menu
   wins over the wiki picker.
2. **Ghost text** (highest; only while a suggestion shows): Tab accept, Esc
   dismiss.
3. **Editor keymap** (before defaults, so Mod+B beats bracket-match and Mod+F
   beats native find): Alt+Shift+1…6 = toggle H1…H6; Alt+Shift+7 = clear
   heading; Mod+B bold · Mod+I italic · Mod+K link · Mod+` inline code ·
   Mod+Shift+X strike; Mod+Shift+8 bullet · Mod+Shift+7 numbered · Mod+Shift+L
   task list; Mod+Alt+Shift+↑/↓ swap line; Mod+F find in note.
4. **Base keymap** (MarkdownEditor.tsx:763–780): Enter =
   `insertNewlineContinueMarkup` (continues lists/quotes/tasks; Enter on an
   empty item terminates the list) falling back to newline-keep-indent;
   Shift+Enter = newline-keep-indent (no markup continuation); Tab = indent
   line(s) two spaces (multi-line aware, selection preserved); **Shift+Tab =
   outdent ONLY inside an indented list item; otherwise it dispatches
   `liv:toggle-dashboard` — opening Mission Control even mid-writing (owner
   decision; key-repeats swallowed)** (:1876–1951, 810–832). Then foldKeymap,
   markdownKeymap, defaultKeymap, historyKeymap (undo Mod+Z / redo
   Mod+Shift+Z).
5. **DOM keydown (after keymaps)**: `[` after `[` → auto `[[]]`; `]` completing
   `- [` → expands to `- [ ] ` (and `- [x` + `]` → `- [x] `) so half-typed
   checkboxes become real tasks; then the host handler: **Ctrl/Cmd+Enter =
   send**.
6. **Composer-scope commands** (registry): Mod+Shift+E extract selection;
   Alt+P/T/A/R/G focus project/type/area/tier/tags metadata fields; Alt+E focus
   editor; Alt+1/2/3 set tier; Alt+M / Alt+Shift+M metadata suggest;
   Mod+Shift+B bookmark; Mod-number tab jumps, new-tab, close, split. ⚠ The
   `editor:*` formatting entries in commands.tsx (786–922) exist as
   registry/palette metadata with default bindings, but no `useCommand` handler
   dispatches them — the REAL bindings live only inside the editor keymap; only
   `editor:extract-selection` is registered.

### 2.14.13 Folding, selection gestures, ghost text, paste, ruler
- **Folding**: heading sections fold (heading line → until the next heading of
  ≤ level); lang-markdown's default paragraph/blockquote folding is explicitly
  disabled — only headings, code blocks, tables fold. Fold gutter 1.5em,
  markers `⌄`/`›`, muted 0.9em; all other gutters hidden (no line numbers);
  fold placeholder = a clickable muted " ...".
- **AI selection bubble** (MarkdownEditor.tsx:395–478, 1678–1724;
  `aiSelectionActions.ts`): selecting a non-empty, non-whitespace, single-range
  span of prose (not read-only, not in a code fence) shows a compact floating
  toolbar just below the selection (flips above near the viewport bottom;
  z-9998): "✨ AI | Rephrase · Tighten · Expand · Explain". Suppressed while a
  slash/wiki popup or a preview is open, and whenever no API key is configured
  (graceful; re-enables live when a key is added; a runtime key error latches
  it off). Clicking an action opens the **accept-in-place preview popover**
  (340px, z-9999): header "✨ <Action> · thinking…", streamed suggestion text
  (max-h-44 scroll), footer Reject / Accept (Accept disabled until a non-empty
  result lands). Accept replaces the original selection in ONE transaction
  (bounds clamped against doc shrinkage) and selects the new text; Reject/Esc
  aborts the stream and refocuses. Contract: selection ≤4000 chars, ±600
  context, `<<<SELECTION>>>…<<<END>>>` markers, max 600 tokens, temp 0.3,
  reply sanitized. "We NEVER edit silently."
- **Extract selection to new note** (Ctrl+Shift+E / context menu / palette;
  Composer.tsx:2572–2634): title = first heading in the selection, else first
  non-empty line (≤60 chars), else "Untitled"; a new tab is created with the
  selected text as body (inheriting workspace project/area), the selection is
  replaced with `[[Title]]`, the new note persists immediately, the new tab
  activates. Empty selection ⇒ toast "Select some text first to extract it."
- **AI ghost autocomplete** (opt-in, default OFF; `.cm-ai-ghost`, opacity 0.55,
  non-selectable, own low-precedence StateField so it can never disturb
  live-preview layers): predictor (`aiAutocomplete.ts`) debounces 500ms,
  aborts in-flight per keystroke, ~1500 chars before / 200 after around a
  `<|CURSOR|>` marker, max 48 tokens, temp 0.2, fast fallback model.
  Suppression: <2 chars context; caret mid-word; last char not
  whitespace/punctuation; inside a code fence. Sanitisation strips
  quotes/fences, clips to one line, de-dupes echoed tails. Tab accepts, Esc
  dismisses, any edit/caret move clears; no key silently disables for the
  session. Toggle persists at `editor.aiAutocomplete` + broadcast event.
- **Paste**: no custom in-editor paste handler — plain-text paste; there is
  **no image-paste-to-attachment pipeline**. Images appear only via
  `![alt](src)` text or embed blocks. URL paste OUTSIDE editable surfaces →
  LinkSaveOverlay (§2.18.5).
- **Page ruler** (PageRuler.tsx): Google-Docs-style hover ruler at the page
  top — a barely-visible hairline at rest; hovering the 12px strip reveals two
  small neutral nub handles; dragging sets left/right margins as fractions of
  page width (single margin ≤0.4, column ≥0.25); double-click resets. Margins
  persist globally at `liv.editor.pageMargins` (default 4.5%/4.5%) and flow
  into the content as `--liv-page-margin-left/right` padding.

### 2.14.14 Adjacent panes & note-splitting
- **Outline** (`composer/OutlinePane.tsx`): ATX headings parsed from the body
  (skipping fenced code), indented per level; click dispatches
  `composer:goto-pos` → cursor set + scroll + focus. Empty: "No headings in
  this note yet."
- **Backlinks** pane: recomputed on demand from `[[..]]` bodies + `related`
  frontmatter across all objects, resolved by id / `kind:id` / title with
  `|`/`#` fallback splitting (`backlinks.ts`).
- Composer right-pane tab set: Metadata / Outline / Snapshots / Bookmarks /
  Backlinks / Graph / Copilot — Bookmarks/Graph/Copilot render a placeholder
  pane (Composer.tsx:6346–6398).
- **Subnotes via `[Name]`**: single-bracket refs in a body (outside code
  regions, not `[[..]]`/`[..](..)`; names ≤80 chars; code-ish chars rejected)
  materialise child notes (parentId = this note, first-parent-wins) on every
  persist (`subnotes.ts`); children inherit project/area/tier/tags.
- **AI note split** (`noteSplit.ts` + `processor/NoteSplitPanel.tsx`): proposes
  2–6 atomic notes as strict JSON {title, body, rationale}; panel = action bar
  "✂ Propose splits" (→ "Re-propose splits") + "Accept all (n)" + ✕; banner
  "Splitting <title> — the original note is kept intact."; proposal cards =
  title, italic rationale, 4-line body clamp, per-card Accept (immediately
  materializes THAT split) / Reject (dims, "Undo"). Materialization: child
  notes (`parentId = source.id`) inheriting metadata; the first child opens.
  Additive — source untouched. States: "Proposing splits…"; error + "Try
  again"; "This note looks already atomic…". ⚠ REACHABILITY: currently dead —
  rendered only inside the Processor's unreachable legacy `AutoView` (§2.24.5).

### 2.14.15 Non-markdown surfaces sharing the tab pane
`tab.mode` routing (Composer.tsx:5691–5767): blank → type picker; canvas →
CanvasView; excel/document → FilePreviewView; kanban (or Obsidian-Kanban
markdown: `kanban-plugin: board` / `%% kanban:settings`) → KanbanView;
capture/dashboard/chat/tasks kinds → embedded surfaces (never persisted as
notes). A markdown body starting with a `~~~plugin` fence (e.g. note-gallery)
falls back to a **plain mono `<textarea>`** so unknown plugin blocks can't
crash live preview (`needsPlainMarkdownFallback`). ⚠ `tab.mode === "note"`
renders `NoteView` — a sticky-note stub whose textarea text is never persisted
(ModeViews.tsx:1467–1484); real notes use mode "editor"; treat "note" mode as
vestigial.

### 2.14.16 Cross-note task list — code vs intent
- Note checkboxes are plain markdown; toggling edits the note text only. Tasks
  proper are a separate store (§2.15).
- ⚠ `parseChecklistItems(notes, project?)` (tasks.ts:707–727) builds a
  cross-note checklist model ({noteId, noteTitle, project, lineIndex, text,
  checked}) — exported, **zero call sites**; `CHECKLIST_OVERRIDES_KEY`
  (tasks.ts:228) likewise defined and never used. There is NO shipped
  cross-note task-list UI derived from note checkboxes (§6: revive or drop).
- The Tasks surface's Write mode round-trips the TASK STORE through a checkbox
  buffer (§2.15.8). Habit tracking reads daily-note checkboxes via the
  `- [x] Habit (N)` convention (§2.22).

## 2.15 Tasks surface — `src/components/tasks/TasksExtension.tsx`

Tasks is a global tool (activity rail), **cross-workspace**: it shows every
task in the vault; the active workspace only stamps *new* tasks
(TasksExtension.tsx:2127–2158).

### 2.15.1 Task data model (`src/lib/tasks.ts`)
- `Task` (:174–203): id, title, body (description), type, status, priority,
  project, subproject (displays as `"project / subproject"`), area, tags[],
  dueDate (ISO yyyy-mm-dd or ""), reminderAt (⚠ no UI consumer), recurrence,
  assignee[] (aliased to people), subtasks[] {id,title,done}, startDate?,
  sourceNoteId?, createdAt/updatedAt, plus unified-spine extras (object:"task",
  active, tier, calendarDate, calendarTitle, lastEdited, workspaceId).
  Defaults: type "action", status "inbox", priority "normal".
- **Types** (3): action / decision / reminder. Colors: action = primary tint,
  decision = warning tint, reminder = chip badge pair; kanban column accents
  `TASK_TYPE_COLORS`.
- **Priorities** (4): urgent / high / normal / low. Flag colors:
  urgent=destructive, high=warning, normal=primary/60, low=muted.
- **Recurrence**: none / daily / weekly / monthly ("Does not repeat"/"Daily"/…).
- **Status model — ClickUp-style, customizable per workspace** (:27–99,
  349–393): a status is `StatusDef {id, label, group, color(hex)}`; groups are
  fixed lifecycle buckets **not-started → active → done → closed**. Default
  set: `inbox`(#64748b, not-started), `today`(#0ea5e9), `scheduled`(#8b5cf6),
  `someday`(#71717a), `in-progress`(#f59e0b, active), `done`(#22c55e, done),
  `cancelled`(#9ca3af, closed). Each workspace may carry a custom set
  (`ws.taskStatuses`; edited in Settings → Tasks). Unknown ids render via a
  safe fallback def (label=id, grey, not-started) so chips/columns never blank.
  Legacy migrations: ready→today, back-burner→someday, waiting→scheduled,
  to-discuss/clarify→inbox, this-month→scheduled, later-someday→someday,
  unscheduled→inbox; bug/feature/research/meeting/review/milestone→action.
  "Done-ness"/"open" always resolve through the status GROUP (done|closed)
  against the *task's own* workspace set.
- **Derived urgency** (:522–538): `taskUrgency` ∈ [0,1] = 0.6·dueWeight +
  0.4·priorityWeight; done/cancelled = 0. dueWeight: overdue/today=1, ≤1d=.9,
  ≤3d=.7, ≤7d=.5, ≤30d=.3, else .15; priority urgent=1/high=.66/normal=.33/
  low=.15. Drives kanban card ordering and the "Suggest next actions" pick.
- **Recurrence semantics** (:455–518): completing a recurring task (status
  patched to done from non-done) **spawns the next occurrence** inside
  `updateTask`: fresh id, dueDate advanced one step (invalid date anchors to
  today), status = "scheduled" if it has a new due date else "today",
  calendarDate mirrors the new due, all subtasks reset un-done, fresh
  timestamps. `nextRecurringTask()` is exported so the right-rail save path
  spawns identically.
- Persistence: one array under vault key `app.tasks.v1`; every save broadcasts
  `tasks-changed`; `addTask()` re-reads + merges so cross-surface adds aren't
  clobbered; TasksExtension's persist does the same, honoring local deletes.

### 2.15.2 Overall layout
1. **UnifiedTabBar** (34px; Composer-identical pills: mode icon → name →
   hover-only close ✕ when >1 tab; `+` opens a mode picker; double-click
   renames; the leading mode icon click switches the tab's mode in place).
   Modes with hints (:1910–1941): **Task list** ("Fast triage, filters, and
   inline status cycling"), **Kanban board** ("ClickUp-style columns by task
   status"), **Cards** ("Gallery of task cards — the shared Files gallery"),
   **Schedule** ("Month calendar — tasks on their due dates, unscheduled
   beside"), **Write mode** ("Markdown-like task buffer for quick capture").
   Tab state persists globally under `app.tasks.tabs.v2` (⚠ first init keys on
   the workspace id but all load/save use key "global" — effectively global;
   replicate as global). Legacy `mode:"table"` tabs migrate to List, renaming
   only auto-generated "Table"/"Table N" names. Closing the active tab focuses
   the right neighbour, then left. A new tab of an existing kind gets a
   numbered suffix ("Board 2").
2. Below: **left rail | center | (optional) assist panel** inside
   `ResizableToolSidebar` (pixel-width sidebar, default 248px, min 170 / max
   460, drag handle, persisted `app.tool.tasks.sidebar.v1`).
3. The **global right sidebar** shows the Tasks View|AI config panel while
   Tasks is active and no task is selected (§2.15.12); selecting a task shows
   its MetadataEditor. TasksExtension auto-reveals the right panel on mount.

Selection model: single click selects a row/card (re-click toggles off), pushes
`{id, kind:"task"}` into the global focused-object and reveals the right panel.
**Double-click** anywhere (row, card, calendar chip) dispatches
`task:open-detail` → the detail modal (§2.15.6).

### 2.15.3 Left rail — `FilterSidebar` (:306–544)
"Navigate-then-refine": the rail sets SCOPE ONLY (a filter), never
view-type/grouping.
- Header: `ToolRailHeader` — CheckSquare icon + "Tasks".
- **Type-to-find box** ("Find a workspace or project…", debounced) narrows only
  the Workspaces + Projects lists; clear-✕ when non-empty. While searching the
  All-tasks/Smart-lists block hides; no matches → `No filters match "q".`
- **All tasks** row (ListChecks icon + total count) — default unscoped view,
  highlighted when scope is empty.
- **Smart lists** collapsible section: **Today** (Clock; open tasks with
  `dueDate <= today` — due today *or overdue*) and **Upcoming** (Calendar; open
  tasks due strictly after today). Both set `due` + `activeOnly:true`
  atomically; live counts use the same open-task definition (per-task workspace
  status group ≠ done/closed). Day boundary = **local midnight**.
- **Workspaces** section: only workspaces with ≥1 task, sorted by count desc,
  Compass icon, live count; click scopes.
- **Projects** section: distinct non-empty projects, alphabetical, live counts.
- Sections use Notion-style small-caps headers with hover-reveal chevron; rows
  13px, `nav-active` when selected.
- Footer: "**Refine in the right panel**" button (SlidersHorizontal) — clears
  selection, reveals the right panel, forces its view to metadata.

### 2.15.4 Center top bar (h-10, :2720–2907)
Left→right: active tab name (truncated, 12px semibold) · **live count pill** of
visible tasks · **removable filter chips** (max 4 + "+n" overflow with tooltip
listing the rest) covering BOTH shared facet filters
(status/priority/type/area/project/tier, `#tag`, `@person`) and the rail scope
(Today/Upcoming, Active only, workspace, project, area, tag, status, priority,
type) — each chip's ✕ removes exactly its condition; the Today/Upcoming chip
clears `due` AND `activeOnly` together. Then:
- **Display** button (board & list modes only): popover with **Show empty
  fields** checkbox and **Density** segmented control (Compact/Normal/
  Spacious).
- **Search** input ("Search tasks…", debounced, hidden in Write mode) matching
  title, body, or project; clear-✕.
- **Suggest next actions** button (Sparkles, right-aligned; hidden in Write
  mode): picks the explicitly selected open task if visible, else the most
  urgent open shown task; disabled with tooltip "No open tasks here to suggest
  actions for"; opens the TaskAssistPanel (§2.15.11) for the pick.
Visible-set pipeline: `visibleTasks = sortTasks(applyFilter(projectTasks,
railScope, search), taskSort)` where projectTasks = all tasks narrowed by the
global activeFilter store. Sort options: Default (store order) / Due date /
Priority / Created / Title, ASC|DESC; undated tasks always sort last on a due
sort regardless of direction.

### 2.15.5 List view (:546–865)
- **Quick-add row** pinned at top: bordered pill with Plus icon, placeholder
  "**Add a task… (Enter)**". Enter parses inline tokens (below) and creates
  `status:"inbox"` (project from the rail scope; workspace = active), selects
  it.
- **Inline token grammar** (`parseInlineMetadata`, tasks.ts:544–601), stripped
  from the typed title: `due:YYYY-MM-DD` → dueDate; `!urgent|!high|!normal|
  !low` → priority; `@word` → assignee (multiple; `\w+` only); `#word` → tag
  (multiple). Parses in: list quick-add, kanban column quick-add, Schedule
  day/unscheduled quick-add, Write-mode sync. Does NOT parse in the global
  QuickAddTask overlay or the detail modal.
- **Rows** (`TaskListRow`): 3px left accent stripe in the status hex
  (transparent when null — layout never shifts); **StatusDot** button (12px
  circle: filled for done/closed group, hollow ring otherwise, colored per
  StatusDef, tooltip = status label) — click **cycles the status** to the next
  id in the task's own workspace status order, wrapping; title (xs,
  line-through + muted when done; italic "Untitled" when empty); right-aligned
  metadata chips in the shared **MetaChip** vocabulary, gated by the Fields
  config: priority flag **only when ≠ normal**, type pill, project (≥sm
  screens, max-w 90px), area (≥sm, 80px), first 2 tags (≥md), subtask `n/m`
  (ListChecks, ≥md), recurrence Repeat icon (≥md), start date `MM-DD` (Clock,
  ≥md), due date `MM-DD` (Calendar, ≥md; **overdue** = destructive text on
  `bg-destructive/10`, tooltip "Overdue — was due …"), assignee avatars (up to
  3 colored initial circles via `chipColor(name)`, then "+n"). Hover-only
  actions: **Sparkles** ("Suggest steps with AI") and **Trash** (delete,
  immediate, no confirm).
- Row states: selected `border-primary/40 bg-primary/8`; hover border +
  `bg-secondary/30`.
- **Grouping** (right-panel Group): `none | status | priority | project | type
  | area | assignee` (`groupTasksForList`, tasks.ts:764–873). Multi-valued
  axis (assignee) lists a task under EVERY value. Section order: canonical
  first (status-set order / priority order / type order), remaining values
  alphabetical, "missing" bucket last ("No status/No project/No
  area/Unassigned"). Headers: chevron + uppercase label + count; click
  collapses. Default none; **not persisted** (session).
- **Keyboard nav** (`useListKeyboardNav`, §2.28.5): ↑/↓/Home/End over *visible*
  rows only, Enter opens the detail modal, selection auto-scrolls; inert while
  any input/textarea/contenteditable has focus.
- **Footer**: "{n} tasks shown".
- **Empty states**: zero tasks → "No tasks yet / Type in the box above and
  press Enter… New tasks land in Inbox — switch to the Board to drag them into
  Today, Scheduled, or Done."; filtered-to-zero → "No matching tasks / Nothing
  matches the current filter or search. Clear filters from the rail or pick
  "All tasks"."

### 2.15.6 Task detail modal (`TaskDetailModal`, :1011–1251)
Opened only deliberately: double-click a row/card/calendar chip
(`task:open-detail`) or Enter in the list. Centered modal `min(680px, 92vw)`,
max-h 80vh, backdrop blur; closes via ✕ / Esc / backdrop / "Back to board"
(ChevronLeft, header-left) / footer "Done" (primary). Header also shows the
type pill. Body: title input (lg semibold, commits on blur); 2-column grid —
**Status** (select over the *active workspace's* set), **Priority** (select),
**Start date** / **Due date** (native date inputs, immediate commit),
**Project** / **Area** (text, blur-commit), **Tags** / **Assignees**
(comma-separated text, blur-commit). (No recurrence field here — that lives in
the right-rail Task block.) **Description** textarea (min-h 100px,
blur-commit). **Subtasks** section `Subtasks · d/t`: checkbox list toggling
done (line-through when done); "No subtasks." placeholder; **no add/remove UI**
— subtasks arrive via AI breakdown or data. Footer: red "Delete task" (left,
deletes + closes) · "Done". Edits write through `updateTask` (so completing a
recurring task here spawns the next occurrence).

### 2.15.7 Kanban board (:867–1632; shared chrome `src/components/kanban/KanbanColumn.tsx`)
- **Group-by axes** (right panel): `status` (default) | priority | type | tags
  | project | workspace. Column construction (`buildKanbanColumns`): status →
  one column per status ordered by lifecycle group (Done AND Closed shown,
  never hidden), header dot + top accent in the status hex; priority/type →
  fixed canonical columns with token accents; tags → one column per distinct
  tag (sorted) + trailing "No tags" — a card appears in EVERY tag column it
  carries; workspace → per workspace + "No workspace"; project → distinct
  projects + "No project". Free-value columns get a stable per-value accent via
  `chipColor(value).border`.
- **Column chrome**: fixed **w-60 (240px)**, quiet `bg-secondary/35` rounded
  surface (no hard border — cards carry borders), header = accent dot (7px, or
  the StatusDot for status boards) + 12px medium label + plain count; card
  stack scrolls internally with density-driven gap; empty column shows centered
  "Empty" (→ "**Drop here**" while a drag hovers); footer "**+ Add task**"
  ghost button. Board scrolls horizontally (min-w-max, gap-3, p-3).
- **Cards** (`KanbanCard`): 3px left stripe = the task's **status** hex
  regardless of grouping axis; **overdue forces the stripe destructive**.
  Priority flag pinned top-right (every level when the field is on). Title row:
  optional StatusDot + xs medium title (line-through when done). Metadata chip
  row = enabled fields in canonical order; with **Show empty fields** on,
  missing values render faint same-geometry `EmptyChip` slots (dashed avatar
  circle for assignee) so toggling values never shifts layout. Hover reveals a
  bottom-right **⋯** → popover "**Move to**" listing every column (click
  applies the move patch) + ─ + red **Delete**.
- **Drag semantics**: HTML5 DnD, MIME `application/liv-task-id`. Drop on
  another column **sets that property** and persists: status/priority/type/
  project/workspace replace; **the tags axis ADDS** the column's tag keeping
  existing tags (dropping on "No tags" is a no-op). Same-column drop is a
  no-op. Drag-over highlights the column `ring-2 ring-primary/50` and swaps its
  empty label to "Drop here". **No card dimming during drag and no manual
  within-column ordering** — cards always sort by `taskUrgency` descending.
- **Per-column quick add**: "+ Add task" swaps to an inline input pinned at the
  column bottom ("Task title… Enter"); Enter parses tokens AND applies the
  column's group-by patch (a card created in "Done" lands done; in a tag column
  carries the tag); Esc cancels; blur-empty closes. New cards default
  `status:"inbox"` unless the column patch overrides.
- **Empty board** (zero rows after filtering): centered "No tasks here / Add a
  task from the List view's quick-add box, or clear the current filter/search…"
  instead of a strip of bare "Empty" columns.
- Other kanbans reusing this chrome: the Processor's read-only note-kanban
  (`processor/KanbanView.tsx` — groups queued notes by type/tier/area/project
  via an inline "Group by" toolbar; click opens the note, no drag; ungrouped
  bucket "—" sinks last) and the Base/View kanban lens (§2.18.3).

### 2.15.8 Write mode (`src/components/tasks/TaskWriteMode.tsx`)
A live plain-text buffer where every `- [ ] ` line IS a task:
- **Editor**: a transparent-text `<textarea>` stacked on a metrics-identical
  `<pre>` highlight layer (same 15px/1.65 metrics as the note editor, centered
  ~52rem measure, scroll-synced; caret/selection from the textarea, painted
  glyphs from the layer; the layer gets +10px right padding to match the
  scrollbar gutter so wrap widths never drift). Recognized tokens render as
  tinted pills **while typing** — `@person` & `due:` primary tint, `#tag`
  secondary, `!urgent/!high` destructive, `!normal/!low` muted; pill "padding"
  is a 2px same-color box-shadow ring so layout metrics stay byte-identical.
  The `- [ ]` machinery stays visible but recedes to 40% (60% primary when
  checked); non-checkbox lines render muted as a "won't sync" nudge. Token
  regex is kept in lock-step with `parseInlineMetadata`.
- **Keyboard**: Enter on a non-empty task line auto-continues with a new
  `- [ ] ` (preserving indent); Enter on an empty marker breaks out;
  **Ctrl/Cmd+Enter = Sync**. Placeholder teaches the grammar ("Write one task
  per line — @person #tag !priority due:2026-07-01"); a corner circled-**?**
  (tabIndex −1) carries the full grammar tooltip incl. `[x] = done`.
- **Preview column** (w-72, right; only when the pane is ≥520px wide via
  ResizeObserver): header "Preview · n"; each line parsed cosmetically into
  the card it will become — checkbox, title (struck when done, "Untitled task"
  italic when empty), MetaChips for !priority (destructive tint urgent/high),
  @assignees, #tags, due. Empty: ListTodo icon + "Nothing yet — each line
  becomes a task."
- **Footer** (single docked row): left — the **stamp readout**: "New tasks" +
  a pill per active-scope entry (project/area/workspace-name/tag/priority/
  status-label) that will be stamped onto NEW tasks on sync; right — "Unsaved"
  (primary) or "Synced HH:MM:SS", task count, "Ctrl+Enter" hint, primary
  **Sync to board**.
- **Sync semantics** (`parseWriteBuffer`, tasks.ts:630–692): the buffer seeds
  from `tasksToMarkdown(visibleTasks)` (title + `@a… #t… !prio due:` for
  non-defaults) and **re-seeds whenever the filtered view changes**; on sync
  each checkbox line matches an existing task by case-insensitive exact title
  (each existing task matched at most once) — matched tasks update
  title/checked state (checking sets done; unchecking a done task resets to
  inbox) and parsed tokens override; unmatched lines become **new tasks** with
  the rail-scope stamp applied first and inline tokens winning (tags union).
  Sync merges into allTasks, so tasks outside the current filter are never
  dropped. Deleting a line does NOT delete the task.

### 2.15.9 Schedule view (`src/components/tasks/TaskMonthCalendar.tsx`)
- **Header** (h-10): ‹ / › month, **Today**, "MMMM yyyy" label, right-aligned
  "{n} due this month · {m} unscheduled".
- **Weekday row** Mon–Sun (Monday-first, matching the Calendar tool); Sat/Sun
  dimmed. **Grid**: weeks × 7 pure-CSS grid filling the height. Day cell: day
  number in a 20px circle (today = filled primary bold; out-of-month dimmed on
  `bg-muted/30`; weekend faint wash; today cell `bg-primary/[0.06]`), a
  hover-reveal **+** ("Add task due this day") opening an inline quick-add
  ("Task title… Enter", Esc cancels, blur-empty closes), then up to **3 task
  chips** + "+n more" (tooltip lists hidden titles).
- **Chips**: 1.5px status-color dot + truncated title, 12px; selected =
  primary wash + inset ring; **overdue** (open + past-due) = destructive wash;
  done = struck-through muted. Click selects (right-panel metadata);
  double-click opens the detail modal.
- **Drag-to-reschedule**: chips draggable (`application/liv-task-id`); dropping
  on a day sets dueDate (mirrors calendarDate only if it was already set); drop
  target highlights `bg-primary/10` + ring; same-day drop no-op.
- **Unscheduled side list** (right, w-56, `bg-panel/40`): header CalendarOff +
  "Unscheduled" + count + its own **+**; lists all undated chips; also the drop
  target that **clears** a due date; empty state "Everything has a date. Drop a
  task here to unschedule it."
- Quick-add via a day creates `status:"scheduled"` + that dueDate; via
  Unscheduled creates `status:"inbox"` undated. Both parse tokens.

### 2.15.10 Cards view & right-rail task fields
- **Cards** (`tasks/TasksBaseView.tsx`): renders the already-filtered/sorted
  visibleTasks through the shared Files engine (`BaseFileView`, §2.18.3) as a
  **gallery** with columns `["file.name","status","priority","project","tags",
  "calendar date"]` ("calendar date" maps `calendarDate || dueDate`). Tasks are
  projected into synthetic read-only Note rows (id = task id; start date &
  subtask progress ride on `custom.*`). Read-only in this lens: inline cells
  render as chips, click routes to the task; per-view state key
  `tasks-gallery:{activeWorkspaceId}`.
- **Right-rail Task block** (MetadataEditor.tsx:3889–3976, for a focused task):
  "Task" section — **Status** select (⚠ iterates the DEFAULT status set, not
  the workspace's custom set — code inconsistency vs board/detail; the port
  should use the workspace set, §6), **Priority** select
  (Urgent/High/Normal/Low), **Assignees** ChipInput (contact-linked:
  suggestions, open-contact, "Create contact "X""), **Due date** date input,
  **Repeat** select (Does not repeat/Daily/Weekly/Monthly — the ONLY recurrence
  editor) — plus the generic metadata spine.

### 2.15.11 AI in the Tasks surface
- **TaskAssistPanel** (:1634–1899; `src/lib/taskAssist.ts`): a **272px (w-72)
  right-docked panel inside the Tasks surface** (left of the global sidebar),
  header "✨ Suggest steps" + ✕; Esc closes; opening kicks off one LLM call
  immediately (`suggestSteps` — the task's OWN context: title/type/priority/
  due/assignees/body ≤6000 chars + ≤12 related objects via `getRelated`; JSON
  `{steps:[{text, needsHuman, person}]}`, ≤8 steps, temp 0, dedup);
  close/task-swap aborts in flight. States: spinner "Thinking through the
  steps…"; no-key card ("Add an Anthropic API key in Settings → AI to let Liv
  suggest how to complete this task."); error + Retry; empty "No steps to
  suggest — this task looks ready to just do." Result = numbered ordered
  steps; `needsHuman` steps get an amber badge "Needs you → {person}" and a
  "**Draft message**" button → second LLM call (first-person, brief,
  `[bracketed placeholder]` for unknowns, temp 0.3) → editable textarea
  captioned "DRAFT — EDIT BEFORE SENDING" with **Copy** (✓ "Copied" 1.5s).
  **Nothing is ever sent or written back.** Footer: "AI suggestions — you
  decide what to act on." + ✨ Regenerate.
- **Board-assist "AI" tab** (right panel View | **AI**, count badge;
  `src/lib/taskBoardAssist.ts` + RightSidebar.tsx:1401–1496): LOCAL,
  deterministic, no network. Three generators over the currently visible
  board, in value order: (1) **Reschedule overdue** (≤6 oldest open overdue):
  diff preview "title: Jul 1 → Jul 9" — pushes each due date to today+3;
  (2) **Fill missing project** (≤6 open project-less tasks, only when a
  dominant project exists): diff "title → Project" — fill-only, never
  overwrites; (3) **Break down** (the highest-priority open task with no
  subtasks, no body, title ≥12 chars): adds the 3-step scaffold ["Outline the
  approach","Do the core work","Review and finalise"] and moves the task to the
  first active-group status when one exists. Card = icon
  (Wand2/ClipboardList/CalendarClock) + title + one-line why + left-accented
  preview (numbered steps or before→after rows) + plain-words note + **Apply**
  / **Dismiss**. Apply runs pre-serialized patches through `updateTask` (an
  applied suggestion stops matching and drops out); Dismiss is session-scoped.
  Footer: shield icon "Suggestions only — nothing changes until you Apply."
  Empty: "Your board's tidy — no suggestions right now."
- **Task agent in the Copilot pane** (`src/lib/taskAgent.ts` +
  CopilotPane.tsx:139–245): when the focused object is a task, a strip under
  the Copilot header shows "⚡ Suggest a next action". `proposeTaskAction` asks
  for ONE change expressed ONLY as an allow-listed patch
  (status/priority/dueDate), each value validated against enums/date regex and
  diffed against current (identical → dropped; empty → "The agent didn't find
  a useful change for this task."). Proposal card: "Proposed: <summary>"
  ("status → Today · priority → High") + rationale + **Approve** (commits) /
  **Reject**. Ephemeral — never persisted pending.
- Home/dashboard task suggestions (`src/lib/taskSuggestions.ts`): pure
  heuristic per-task next-action chips (open-link, draft-reply, schedule,
  attach-file, break-down; deterministic ids `sg:<taskId>:<kind>`);
  `AgentSuggestionProvider` is a ⚠ deliberate empty stub.

### 2.15.12 Right-panel view config — `TasksFilterPanel` (RightSidebar.tsx:827–1386)
Shown while Tasks is active with no task selected. Header: view name + "{n}
tasks · configure this view" (AI tab active: "{n} tasks · suggestions") + a
**View | AI** tab bar (inset accent underline; AI tab count pill). View-tab
sections (all drive the center over the `tasks-view-control` event bus):
1. **View** — segmented Write/List/Board/Cards/Schedule; changes the active
   tab's mode in place.
2. **Quick filters** — star-able pinned facet-value chips (fields priority/
   status/project/type/tags; defaults `priority:urgent`, `priority:high`).
   Chips toggle through the shared activeFilter store (identical path as the
   full checklist). The ＋ enters manage mode: every candidate value with ★/☆
   to pin/unpin; pins persist at `app.tasks.quickFilterPins.v1`.
3. **Fields** — toggle pills for the 11 card fields + a locked "Title" pill;
   counter "k/12 shown". Field config (`src/lib/taskCardDisplay.ts`): canonical
   order status, priority, type, project, area, due, start, tags, assignee,
   subtasks, recurrence; defaults ON: status, priority, type, project, due,
   tags, assignee, subtasks; plus showEmpty (default false) and density
   compact|normal|spacious (default normal; drives card padding p-1.5/2.5/3.5,
   column gap 1/2/3, row padding py-1/1.5/2.5, list/calendar gaps). Persisted
   globally at `app.tasks.cardDisplay.v1` (always stored/rendered in canonical
   order).
4. **Sort · group** — Sort select (Default/Due date/Priority/Created/Title) +
   ↑/↓ direction; Group select whose options depend on the active mode (board
   set vs list set; empty for write/schedule/cards).
5. **Saved** — searchable preset list ("Find a view or preset…"). Built-ins
   (tasks.ts:912–946): *Board by status* (kanban, group status, fields
   status/priority/due), *High priority list* (list, sort due ASC, facets
   priority∈{high,urgent}, fields status/priority/due/project), *By project*
   (list, grouped by project, fields status/due). "**Save current**" prompts a
   name ("e.g. Weekly triage") and captures view type + grouping + sort +
   enabled fields + active facet values; user presets persist at
   `app.tasks.viewPresets.v1`, hover-✕ deletable (built-ins aren't).
   **Applying is atomic**: every preset-able facet field is *replaced* (unset =
   cleared, never merged), then one `applyPreset` bus event lands
   view/group/sort/fields together; an empty `fields` array means "leave card
   display untouched"; unknown field ids are filtered against the canonical
   table.
6. **All filters** — the full shared FacetFilters checklist,
   `scopeKind="task"`, collapsed by default.
When the active mode is **Cards**, the panel hides Fields and Sort·group
(BaseFileView owns its own toolbar); Filters/Saved/count still apply.
**MetaChip** (`tasks/MetaChip.tsx`): THE single chip idiom shared by board
cards, list rows, and Write-mode preview — tiny rounded fill `bg-secondary/50`,
11px muted label, optional 2.5px leading icon; loud states pass token classes
(overdue `text-destructive` + `bg-destructive/10`). `EmptyChip` = same geometry
at /25–/30 opacity.

### 2.15.13 Global QuickAddTask overlay (`shared/QuickAddTask.tsx`)
**Mod+Shift+K** (`task:new`). Faded fullscreen scrim (z-150, top-aligned at
18vh), max-w-md card. Header: CheckSquare + "Quick-add task" + muted "→ Inbox"
+ ✕. Body: title input ("What needs doing?", autofocused), then a row with
optional **Project** text input + **priority** select (raw lowercase values).
Footer: hint "Enter to add · Shift+Enter to add another" + primary **Add task**
(disabled while empty). Enter adds & closes; Shift+Enter adds & clears &
refocuses; Esc/backdrop closes. Creates `status:"inbox"` in the active
workspace; **no token parsing**.

### 2.15.14 Time tracking (`src/lib/timeTracking.ts` + `widgets/TimeTrackingWidget.tsx`)
- Model: `TimeEntry` (closed interval: workspaceId, project ""=unfiled,
  optional taskId, startedAt/endedAt ISO, seconds clamped ≥0, optional note) +
  at most ONE `ActiveTimer` app-wide (starting a second timer folds the running
  one into an entry — never double-counts). One versioned store
  `app.timeTracking.v1`; mutations broadcast `time-tracking-changed`. API:
  start/stopTimer, logManual, totalsByProject / totalsByTask / totalForScope
  (scope = workspace → optional project → optional task; live totals include
  the running timer), formatDuration ("3h 5m"), formatClock ("MM:SS" /
  "H:MM:SS").
- UI = one dashboard widget only (**no timer UI inside the Tasks surface**; ⚠
  `totalsByTask`/taskId scoping has no UI consumer): big tabular clock (live
  stopwatch while tracking here, else total) + "Tracking · {scope}"/"Tracked on
  {scope}" caption + Start (primary wash, Play) / Stop (red wash, Square); a
  notice "Timer running on X — starting here stops it." when another scope's
  timer runs; below, top-5 projects by tracked seconds ("Unfiled" for "");
  empty state "No time tracked yet — hit Start to begin." Scope = the widget
  board's workspace + optional project pin. 1s tick only while running.

## 2.16 Lists — `src/lib/lists.ts`, `components/lists/ListsExtension.tsx`

Lists render as the `list` mode of the Files department's tab bar (not in the
activity rail); `ListsExtension` also supports `surface="bases"`/`"all"`.

### 2.16.1 Model & semantics
A **List** is a first-class collection object: `{id, title, description,
metadata (ObjectMetadata, object pinned "list"), templateMode, memberIds[]
(insertion order), createdAt, archived?}`. Lists are **not folders**:
membership is tagging — an object can be in many lists; removing a member never
deletes the object. The list's own metadata **doubles as a template** stamped
onto joining members.
- **Template modes** (`fill | overwrite | tag-only`), labels "Fill empty fields
  / Overwrite fields / Only union tags", each with a hint sentence.
  `applyListTemplate`: tag-only = union tags only; fill/overwrite operate on
  the string fields area/project/tier/calendarTitle/calendarDate (empty
  template value = "no opinion", never blanks the target; fill writes only
  empty targets; overwrite replaces), and BOTH modes union tags AND people;
  bumps lastEdited.
- Storage: JSON under vault key `app.lists.v1` is the source of truth; every
  save also mirrors each non-archived list as a derived `Lists/{title}.md`
  (YAML frontmatter incl. template_mode + a `## Members` section of `[[id]]`
  links) AND a `Lists/{title}.base` (Obsidian-Bases-compatible: `==` filters
  from project/area/tier + `tags.contains(...)`, one table view with columns
  file.name/type/area/project/tags/tier/file.mtime sorted mtime DESC, limit
  100). Broadcasts `lists-change`. (§4: the mirrors become export artifacts.)
- Lists are workspace-scoped for display (`getWorkspaceLists`); new lists bind
  to the active workspace.

### 2.16.2 Surface layout
Two columns:
- **Directory rail (w-72, fixed)**: ToolRailHeader "Lists" + `+` (New list →
  name prompt); search box ("Search lists…"/"Search bases…", debounced,
  clear-✕) matching title/description/tags (bases: title/path). Rows: List icon
  (primary when active) + title + member count, up to 2-line description, up to
  4 `#tag` pills + "+n", hover-only Trash (confirm: *"Delete list "X"? This
  won't delete its members — they stay where they are."*). Below Liv lists, a
  "**From vault**" section lists scanned standalone `.base` files (KindIcon +
  title + mono path + "n views" badge); the scan re-runs (600ms debounce) when
  any `.base` changes on disk. First item auto-selects when nothing is
  selected. Empty: icon + "No lists yet." + "New list" button / "No lists match
  your filter." / bases-only: "No .base files found in this vault."
- **Detail pane**. Selecting a list also sets it as the global focused object
  so the right sidebar's MetadataEditor follows (the list's description is
  edited THERE; round-trips via `lists-change`).

**List detail** (`ListDetail`):
- Header: List icon + inline-editable title (blur/Enter commit) + "{n}
  members".
- **Template mode** section: three toggle buttons with hover hints; the active
  mode's full hint sentence shown below.
- **Members** section header with a 3-way per-list persisted view toggle
  (`app.list.memberView.{listId}.v1`): **List** (compact rows: kind icon,
  title, kind chip, project, hover actions: ExternalLink "Reveal in
  Explorer/Finder — drag from there into Gmail…" + ✕ "Remove from list (does
  not delete the object)"; rows are drag sources carrying
  `application/liv-object-id` + best-effort file URI), **Keep** (responsive
  2–4-col card grid: kind icon + title + hover ✕, kind chip + project + first 2
  tags; also drag sources), **Base** (an Obsidian-Bases-style table generated
  live from the list's metadata template — every vault note matching all
  non-empty template fields appears, *no manual add required*; rendered via
  BaseFileView).
- **In-list search** (when members exist; placeholder "Search in this list
  (title, tags, project, area, type)…"): non-matching members are **DIMMED to
  30% opacity, not hidden** (keeps the list's shape); "k/n" match counter.
- **Drop zone**: the whole members area is a dashed-border target (hot =
  primary tint) accepting `application/liv-object-id` (fallback text/plain).
  Dropping applies the list's template to the object's metadata (kind-aware
  write-back for note/task/file/contact/event) then appends to memberIds
  (dupes ignored). Empty members: *"Drag any object here, or use Ctrl+O → "Add
  to list"."*
- Whole-pane empty state: "Lists are first-class objects." + a hint about
  templates/modes + "Create your first list".
**Vault-base detail** (`VaultBaseDetail`): header = title + mono path + ".base"
badge + "n notes scanned"/"Scanning vault…", body = BaseFileView over the
parsed base with store-over-scan note merging so in-view creation appears
immediately.

### 2.16.3 AddToListMenu (root overlay)
Opened via `lists:add-to-open` (from the `lists:add-to` command for the focused
object; deliberately unbound). Centered 420px popover: header "Add to list" +
✕; autofocused "Filter lists…" search (title/tags); rows = list title +
subtitle "{template mode label} · #tag #tag #tag"; already-member rows disabled
with "already in"; picking applies the template + adds the member + closes.
Footer: "Picking a list applies its metadata template to the focused object."
Esc/backdrop closes. Empty: "No lists yet — create one from the Lists
department first."

## 2.17 Library (Documents) & import pipeline

### 2.17.1 Library browser — `components/library/LibraryExtension.tsx`
A two-pane surface inside a tabbed extension shell (`ExtensionTabBar` on top:
renamable/reorderable/closable tabs, "+" adds). Also reachable as the Files
"Documents" tab mode (same component). Layout: left = resizable tool sidebar
(`ResizableToolSidebar`, width persisted `app.tool.library.sidebar.v1`),
right = viewer pane.

**Left rail, top→bottom:**
1. **Header** (`ToolRailHeader`): BookOpen icon + "Library" + right-aligned
   primary **Upload** button (hidden `<input type=file multiple>`).
2. **Search row**: magnifier + "Search files…" + clear ×. Filters by filename
   OR tag substring (case-insensitive).
3. **Filter toolbar**: **Unprocessed** toggle (Filter icon; active =
   `bg-amber-500/20 text-amber-400`) — only `processed:false` files.
   **Archive** toggle (Archive icon + count) — appears only when ≥1 archived
   file exists (or while open); ON = list shows ONLY archived files (dimmed
   60%); archived files never appear in the normal list. Right-aligned
   **project** `<select>` ("All projects" + distinct `file.project` values) —
   only when projects exist. The Library is explicitly global/cross-workspace;
   only an explicit pick narrows.
4. **"By type" strip** (`TypeCategoryStrip`): label "By type", then wrapped
   pill buttons, one per non-empty `FileTypeCategory` with count ("Markdown
   12", "PDF 5"…). Click toggles the filter; selected = `bg-primary/20
   text-primary`. Categories & order (`lib/fileTypes.ts`): markdown, base,
   canvas, pdf, word, spreadsheet, presentation, image, audio, video, text,
   code, archive, other. Categorisation = MIME regex first, then extension map.
   Tooltip "<Label> · N files".
5. **Tag strip**: all distinct tags as `#tag` pills, click toggles a single tag
   filter.
6. **File list**: rows (`FileListItem`) = disclosure chevron ▸/▾ (expands to
   indented tag chips), colored `FileTypeIcon` by extension, filename
   (truncate, selected = primary), sub-line "`1.2 MB · 3d ago`" + amber
   "unprocessed" badge if unviewed, hover trash button. Selected row:
   `border-primary/50 bg-primary/5`. **Right-click context menu** (fixed
   popover, closes on click/scroll): "Archive/Unarchive" + red "Remove". While
   dragging files over the rail: rail tints `bg-primary/5`, the list is
   replaced by centered "Drop to add" (Upload icon). Empty states: "Upload or
   drop files here" / "No matches" / "No archived files".
7. **Footer**: "N files" (+ "· M unprocessed" when the toggle is on) or "N
   archived files".
The global activeFilter store also intersects the list (any app-wide filter
runs the file objects through `filterObjects`).

**Center pane (viewer):**
- Nothing selected: `ToolEmptyState` (BookOpen, "Select a file to view it",
  hint "or drag and drop files into the left panel") + dashed "Upload files"
  button. Loading: spinner. Error: red message + "Retry".
- **PDF**: header bar (h-9, filename + "Open in browser" link `_blank`) over an
  `<iframe>` of a blob URL (IndexedDB blob store; previous object URL revoked).
  (Native port: PDFKit — strictly better.)
- **Non-PDF (incl. docx)**: centered metadata card — 64px FileTypeIcon,
  filename, "mimeType · size", project, tag chips, and an "**Open externally**"
  button (blob URL, `window.open`, revoked after 10s). There is NO in-app docx
  render.
- Selecting a file marks it `processed:true` on first view and writes the
  global focused object (`setFocused({id, kind:"file"})`) so the right rail
  shows its metadata.

**File-object model** (`lib/library.ts`): `LibraryFile = ObjectMetadata & {id,
filename, mimeType, size, blobRef, source, attachedTo[], processed,
bookSummary?, archived?}`, `object:"file"` pinned. `source ∈
upload|drop|phone|browser-ext|screenshot|download-watch`. `blobRef` =
IndexedDB key for in-app uploads, or a vault-relative path (e.g.
`Library/PDF/x.pdf`) for disk-ingested files. New files stamp `workspaceId`
from the active workspace. Storage key `app.library.files.v1` (one-way
migration from `app.library.pdfs.v1`).

### 2.17.2 Import extension — `import/ImportExtension.tsx`
Fixed five tab modes on a `UnifiedTabBar` (not closable/renamable), with a
session-wide **Defaults bar** underneath ("Defaults for this session:" project
input, area input, tag chips + add) applied to everything imported, and a right
288px column "**Imported this session**" log (✓/⚠ + label + source tag +
detail; max 25; "clear").
- **Watch**: header "Watching: <path>" (falls back to OS Downloads via
  `suggestDefaultWatchedFolder`) + "Open full Inbox →". Lists watched-folder
  files (Rust `notify` watcher emits `inbox-new-file`; relist debounced 300ms).
  Row action "Ingest". Empty: "Folder is clean".
- **Drop**: full-pane dashed drop zone ("Drop files here to import into the
  Library"; hot = primary tint) + "Or choose files…" picker; per-file busy
  counter.
- **URL**: form (URL, optional Title defaults-to-hostname, optional Note "Why
  are you saving this?"). Lenient URL check (auto-prefix https://). Creates a
  **link note**: `type:"link"`, `format:"url"`, `source:"url-import"`,
  `sourceRef=url`, body = `note\n\nurl` or just the url; defaults applied.
  Ctrl+Enter submits.
- **Bulk**: native multi-select file picker → sequential `ingestFromPath` with
  a progress bar done/total.
- **Triage**: mixed queue of dropped files AND pasted links; top add-bar "Paste
  a link to add it to the triage queue…" + "Add link" + "Clear all". Items are
  reviewed one-at-a-time in `BulkTriageQueue` (§2.24.4) — edit per-item
  metadata → **Keep** files it / **Skip** discards. Nothing imports until Keep.
  Session defaults seed NEW items only.

**Ingest mechanics** (`lib/inbox.ts:199–321`): copy bytes into
`<vault>/Library/<TypeLabel>/` per **folder rules** (`lib/folderRules.ts` —
`enableTypeSubfolders` default ON, per-type label overrides;
auto-metadata-from-folder-path was deliberately REMOVED: "metadata is
intentional"); name collisions resolved by silent `name (1).ext` suffixing (cap
50); MIME guessed from extension; LibraryFile created with
`source:"drop"|"download-watch"`, project defaulting to the active workspace's
projectTag/name. Duplicate-detection helper (`findDuplicates`: exact = same
name+size; similar = one of the two).

### 2.17.3 Create-and-handoff
No in-app office editing. Opening a `.docx/.xlsx` etc. from folder views
creates a Composer "file tab" (`mode: document/excel` via `fileKindFromPath`)
backed by a note stamped `customPath`, or reveals in Finder. AI department
scripts produce **real `.docx`** into the vault via the `docx` npm package
(`lib/departmentAgents.ts:252`); agent outputs are ordinary Library objects.

## 2.18 Files extension — `files/FilesExtension.tsx`

Tab-per-surface shell (`UnifiedTabBar`), tab state persisted per workspace
under `app.files.tabs.v1.<workspaceId>`. Ctrl+T / "+" opens the new-tab picker;
the mode chevron creates a specific surface. Closing the active tab focuses the
right neighbour then left. Modes:

| Mode id | Label | Creatable | Renders |
|---|---|---|---|
| `home` | **View** (default) | ✅ (regression guard #24: must stay creatable) | `FilesHomeView` — the pool surface |
| `folder` | Folder | ✅ | `WorkspaceFolderTree` (single-pane Explorer) |
| `browser` | Browser | ❌ (legacy open-only) | `FolderBrowser` (two-pane Explorer) |
| `base` | Saved View | ❌ (opened, not created) | `FilesHomeView` with `tab.filterId` pre-applied |
| `dataview` | Data view | ❌ | `DataViewBuilder` |
| `list` | List | ✅ | `ListsExtension` (§2.16) |
| `documents` | Documents | ❌ | `LibraryExtension` (§2.17) |
| `blank` | New tab | — | picker page listing creatable modes + "Go to file" (QuickSwitcher) |

Folder/Browser tabs persist `folderPath` on the tab and auto-name after the
folder basename; legacy tabs heal to the workspace folder. Events
`files-open-folder|list|base|mode` focus-or-create the mode tab. Each tab
broadcasts `files-context` so the right rail renders "<view> · <workspace> ·
<project>" and drives the view (§2.9.3).

### 2.18.1 The View surface — `files/FilesHomeView.tsx`
Top→bottom:
1. **VIEW lens bar**: full-width segmented row of 4 equal icon+label boxes —
   **Table / Folder / Gallery / Kanban** — driving BaseFileView's lens via
   `files-view-control {baseId, action:"setViewType"}` (this bar, the inline
   toolbar, and the right rail stay in sync).
2. **Filters chip row** (only when `Library/Filters/*.base` exist): label
   "Filters", up to 12 chips `F1 <title>`…; **F1–F12 keyboard toggles**; active
   chip primary-tinted; right "Clear filters". Saved filters AND-combine; each
   row's match reasons gain `filter:<title>`.
3. **Transient status banner** (primary tint, 2.4s) for saved/batch messages.
4. **Body**: empty state ("Nothing here yet — Notes you create or capture will
   show up here" / "No results" when a lens is active) or **BaseFileView** fed
   all pool items as notes with a default single Table view (columns
   `file.name, active, type, area, project, tags, tier, source, calendar date,
   file.mtime`, sort mtime DESC).

**Pool assembly** (:1258–1293): merge (a) Liv's own notes, (b) external vault
`.md` scan (frontmatter-only; body hydrated for content search), (c) all other
objects — deduped on stable note id, archived and `trashed` dropped, and
**scaffold notes hidden** (empty notes whose `type ∈
dashboard|capture|library` back extension tabs). Kind labels:
Notes/Tasks/Documents/Contacts/Events/Lists/Chats. Cap `MAX_ROWS = 140`.

**Selection & batch** (:1520–1832): a "Selection" popover button (stays open
while ticking; count badge). Checkboxes appear on every row/card;
**shift-click range-selects** over the displayed order; "Select visible/Clear
visible". Actions: Open selected (notes open in new tabs), Set workspace
(retags workspaceId+project; prompt lists workspace names), Set project / Set
area / Set tier (prompt), Add tag, Add to list (find-or-create list by title,
applies its template to each member), **Move files… (Ctrl+M)** — physically
rewrites `customPath` of selected notes into a prompted vault folder — and red
Delete (confirm; deletes files on disk). Selection clears on surface/workspace
switch. Each action flashes the status banner ("Set area applied to 3 selected
items").

**Item interaction**: single-click/focus = select + push to right-rail
metadata + open the right panel; double-click / Enter = open (notes → Composer
via `openObject`, hydrating body from disk if needed; task→Tasks, file→Library,
contact→Contacts, list→Lists tab). ↑/↓ + Enter list-nav across all lenses
(`useListKeyboardNav`, `data-nav-id` per row). Per-row reveal-in-Finder
buttons. Gallery cards show real image thumbnails for image extensions via
asset URLs.

**Save as Filter**: the `files-home-save-filter` event (fired from the right
rail) prompts a name and writes `Library/Filters/<name>.base` with the token
query translated to `.base` filter grammar (`filterNodeFromQuery`, :883–987 —
tag→`tags.contains`, type/project/area/tier/ext→`== ["v"]`, date tokens→
`file.ctime/mtime` ranges, `in:`→`file.inFolder(...)` or project, text→
`file.name.contains`); the new chip appears in row 2.

⚠ Decided-dead-but-shipping: FilesHomeView carries a complete search-query
subsystem (tokens `tag: type: in: is: list: ext: project: area: tier: created:
modified: after: before: on: when:` + `#tag`, suggestion dropdown, scoring with
"matched: title/tag/property/path/body" reasons, and result renderers
`ResultRow`/`FolderResultCard`/`KanbanResultColumn`/`GalleryResultCard`) whose
**search input is no longer rendered** — `query` state can only be cleared
(`files-home-clear`) or set via a suggestion-accept that can't fire. The F1–F12
saved-filter toggles and save-filter event still work. Treat the surface as:
lens bar + saved-filter chips + BaseFileView; the token grammar remains the
spec if the "View" search is ever re-surfaced.

### 2.18.2 BaseFileView — the `.base` renderer (`lists/BaseFileView.tsx`)
Renders a parsed Obsidian-compatible `.base` (`lib/baseFile.ts`) over a note
set. **One filtered+sorted row set, four lenses.**
- **Views**: a base can declare multiple named views; users add **local views**
  ("Add view", prompt-named, persisted per base id under
  `app.base.localViews.<id>.v1`) and rename (declared views rename as a local
  copy — the on-disk file is never mutated implicitly). View picker = dropdown
  with type-to-find, check on active, hover pencil rename, "Add view". Active
  view index persisted (`app.base.activeView.<id>.v1`).
- **Per-view overrides** (`app.base.viewOverrides.<id>.v1`): column order,
  sort, groupBy, filter, viewType. "edited" warning badge when overridden;
  **Reset** and (vault-backed bases only) **Save default** (writes the merged
  `.base` back, fires `vault-bases-changed`); **Save view** always available —
  saves current filter+columns+sort as a NEW `Library/Filters/<name>.base`
  (flash `Saved "name"`).
- **Toolbar** (one scrollable row): view-picker chip · row count · edited badge
  · **Controls** toggle (cluster hidden by default, persisted
  `app.base.toolbar.<id>`) → then: "Note view" select
  (table/folder/gallery/kanban), **Preview** toggle (right split pane,
  persisted `app.base.preview.<id>.v1`), **Search** (in-view Find bar:
  debounced 150ms free text over title+facets+path+body, match count, Esc/blur
  closes+clears), **Filter** popover (visual builder), **Group** select (any
  available column incl. custom props), **Properties** popover (type-to-find
  checklist toggling visible columns), Reset/Save default/Save view, host
  `toolbarSlot`.
- **Filter builder** (`FilterBuilder`, :2682–2953): AND/OR groups (nesting ≤
  depth 2), rows = field select (humanised: `file.name`→"name",
  `file.ctime`→"created", `file.mtime`→"modified") · op select (`is, is not,
  contains, is empty, is not empty, in folder, >, >=, <, <=`) · debounced
  (250ms) value input with echo-guards + unmount flush; "Add filter", "Add
  group", per-row trash, "Clear filter". Incomplete rows are pruned from
  evaluation so typing never blanks the table.
- **Table lens**: fixed-layout table, sticky blurred header; columns resizable
  (drag right edge, min 72px, defaults 168/288-for-name, persisted
  `app.base.colWidths.<id>.v1`), drag-to-reorder headers (grip on hover), click
  header cycles sort none→ASC→DESC→none (single primary sort; multi-sort only
  via YAML). Grouped mode: group header rows "<column> · <value> N"
  collapse/expand (▸/▾); the grouped column hides from body rows. **Inline
  editable cells** for `type, area, project, source, source_ref (text), tier
  (free number, normalized), active (✓ toggle), tags/people (chip + add
  input), status/priority (select over the canonical task enums, rendered as
  primary chips), calendar date (date input), calendar_title` —
  task-projection rows are read-only. `file.*` and `formula.<Name>` (computed
  via `evalFormula`) are read-only. The name cell leads with a kind icon;
  **link notes append their muted domain** "· calmtech.blog". Arrays render as
  ≤4 chips "+N"; ISO dates as locale short dates; booleans ✓/—.
- **"+ New row" / kanban "Add card"**: instant creation, no name prompt
  (duplicate titles fine — the file path gets a silent "(n)" suffix at save
  time); the new note is stamped with the metadata the base's filter implies
  (`baseFilterToMetadata`) + workspace defaults + the kanban column's group
  value; if the view's filter/search would hide it, toast "Note created —
  hidden by this view's filter or search". The add-card editor stays open after
  Enter for rapid entry; Esc/blur-empty closes.
- **Folder lens**: card grid `minmax(260px,1fr)`, one card per on-disk parent
  folder (unfiled → "(unfiled)"), header = folder glyph + name + count, compact
  note cards inside. **Gallery lens**: card grid `minmax(180px,1fr)` of note
  cards. **Kanban lens**: horizontal columns from groupBy values (hint "Tip:
  set Group to split the board into columns" when ungrouped), column accent
  dot = deterministic `stableGroupColor(label)`.
- **Row/card interactions**: single-click **focuses** (highlight `nav-active`,
  reveals the right rail, sets the global focused object — task rows focus AS
  tasks); double-click **opens**; rows/cards are **drag sources**
  (`setLivDragData` — object id + absolute file path, so notes drag out as
  files). Title tooltip: "Click to preview · double-click to open · drag to
  copy as file".
- **Preview pane** (toggle): right 40% (300–600px), header = kind icon + title
  + "Open" + ×, path line, read-only Markdown render of the body (hydrated on
  demand); empty → "Select a note to preview its content."
- **Drop-into-base**: dragging a Liv object or a URL over the base outlines it
  in primary and shows "Drop to tag with this base's filter"; dropping an
  object stamps the base-filter-implied metadata patch; dropping a URL
  **creates a link note** (`type:"link"` unless the filter implies a type,
  `format:"url"`, `source:"drop-into-base"`, title = hostname) that lands in
  the base immediately; toast confirms.
- **Embedded mode** (in-note `data-view` blocks): compact table only, header =
  view name + row count + "Show query" toggle revealing the humanised filter
  read-only, max-height 360px.
- **Right-rail parity**: `onSettingsChange` mirrors {viewName, viewType,
  groupBy, sortText, filterText, columns, rowCount, baseId, availableColumns,
  filterNode, sortProperty, sortDirection} up; inbound `files-view-control`
  events (setViewType/setGroupBy/setFilter/toggleColumn/setSort) let the right
  rail drive the same mutators.

### 2.18.3 Folder mode — `files/WorkspaceFolderTree.tsx`
Real on-disk Explorer of the tab's folder (default: the active workspace's
bound `folderPath`). Empty states: "No workspace active" / `"X" isn't bound to
a folder` + **Bind folder…** button. Toolbar: clickable breadcrumb-chip
"<basename> · <mono path> ⌄" opening a **folder picker popover** (Vault root +
every folder-bound workspace) · "New folder" (prompt; validates
`[^\\/:*?"<>|]`; creates a REAL folder) · Refresh · Reveal-in-Finder. The tree
body shows the root's *contents* (you're "inside" it). Rows (`FolderBranch`):
chevron, folder glyph / colored file-type icon, name; hover actions "+ new
folder inside" (dirs) and reveal. Empty dir → italic "empty". **Files drag
out** with MIME `application/liv-file-open` (+`liv-file-path`, text/plain) →
droppable on the editor to open as a tab. Refresh: vault watcher +
`vault-files-flushed`, debounced 250ms.
**Open routing** (:191–276): `.md` → matching indexed Note opens in Composer,
else raw body opens via `composer-open-file`; `.canvas` → Composer canvas tab;
`.url/.webloc` → browser tab (URL extracted from the shortcut format); other
extensions → Composer file tab typed by `fileKindFromPath` (document/excel/…)
— the tab is indexed as a note with `customPath` so it's searchable; failures
fall back to reveal-in-Finder.

### 2.18.4 Browser mode — `files/FolderBrowser.tsx`
Two-pane Explorer sharing one `useFolderChildren` store: left 256px tree
(header = root basename + refresh) | right pane with **breadcrumb bar** (Home
button = tree root; segments below root clickable; right side: "New folder",
"Set as root" (re-roots + persists in the tab, only when not at root), reveal)
and a **dirs-first flat list** of the selected folder (`ContentRow`: glyph/icon
+ name + hover reveal; click folder = navigate, click file = same open routing;
files draggable). Toggling a tree folder also selects it in the right pane.
Same empty/bind states as Folder mode.

### 2.18.5 Link objects & paste-URL capture
A link is a **note** with `type:"link"`, `format:"url"`, body = the URL,
`sourceRef` = the URL, optional cached `metadata.linkUnfurl
{title,image,description,favicon}`. Renders via `LinkEmbed`: YouTube/Vimeo →
responsive 16:9 player (`toEmbedUrl` handles watch/short/share forms), direct
images → the image, other pages → unfurl card (thumbnail + title + description
+ favicon; fetched on mount if not cached and bubbled up for persistence).
`detectLinkType` is pure/synchronous; `unfurl()` fetches HTML via the native
side (bypasses CORS) and scrapes `og:*`/`twitter:*`/`<title>`/`link[rel*=icon]`,
falling back to `<origin>/favicon.ico`; null on any failure
(`lib/linkUnfurl.ts`).
- **Paste-URL capture** (`hooks/useClipboardDetect.ts` + `shared/
  LinkSaveOverlay.tsx` + Composer.tsx:2636–2736): a window-level `paste`
  listener extracts the first http(s) URL (trailing punctuation trimmed).
  Pastes into editable surfaces (editor, inputs, textareas, contenteditable)
  are ignored. Debounce 500ms; one overlay at a time; the active **workspace id
  is frozen at paste time** so a later save lands where the paste happened.
- Manual path: `links:save-from-clipboard`, default **Mod+Shift+U** (reads the
  clipboard; toasts "Copy a link first…" / "Couldn't read the clipboard." on
  failure). Mod+Shift+L deliberately avoided (collides with toggle-task-list).
- **LinkSaveOverlay**: fixed bottom-right card, 380px, z-140, slide-up.
  Header: link icon + "Save link" + ×. Body: URL pill with a spinner while
  `unfurlEager` runs ("Fetching preview…" placeholder in the title field);
  invalid URL → red "Not a valid URL" + Save disabled; unfurl failure → hint
  "Preview unavailable — add a title and save." Fields: **Title** (autofocused;
  auto-filled from unfurl only if untouched), **Note** ("Why are you saving
  this?" 2-row textarea), Project | Area two-up inputs (pre-filled from
  workspace defaults), Tags (comma-separated). Footer: Dismiss / primary "Save
  link". **Esc dismisses, Mod+Enter saves.** Fallback title = unfurl title,
  else hostname.
- On save: mints a browser-mode Composer tab + note (shared id) with
  `type:"link"`, `format:"url"`, source/sourceRef = URL, description =
  annotation, unfurl persisted; switches to the frozen workspace, opens the tab
  (renders via LinkEmbed), toast `Saved link "label"`.
- Other creation paths: Import→URL tab, Import→Triage links,
  drop-URL-onto-base, drag-URL onto various targets. ⚠ Bulk browser-tab drag-in
  and bookmarks-HTML import: D25 design-only; **no code exists**.

### 2.18.6 Vault, export, archive search
- **Vault selection / Obsidian attach** (`lib/vault.ts`): first run → native
  folder picker; suggested default `<Desktop>/Liv`; path stored in
  `<appDataDir>/vault-config.json`. Only `Library/` is scaffolded
  (`ESSENTIAL_FOLDERS`) — an existing Obsidian folder structure is deliberately
  NOT reorganized. App state lives in `<vault>/.composer/state.json`; notes are
  ALSO mirrored to individual `.md` files (D05 write-through, per-vault,
  default ON). ⚠ Brief §3's on-disk layout (lowercase pools, `.liv/views/`,
  `.trash/`) is NOT implemented: code uses `Library/` capitalized, notes at
  `Library/Notes/<title>.md`, imports at `Library/<TypeLabel>/<file>`, saved
  views at **`Library/Filters/<name>.base` (visible)**, and trash is a
  `trashed` flag, not a folder. (§4: all of this becomes lotus import/export.)
- **Obsidian vault scan** (`lib/vaultBases.ts`): `scanVaultMarkdownNotes`
  (native scan command, JS DFS fallback; skips `.composer`/`.liv`/`.obsidian`/
  hidden; concurrency 24 meta / 8 body; frontmatter → NoteMetadata; note id =
  frontmatter id or an FNV hash of the relative path `vault-note:<hash>`; title
  = frontmatter title or filename; TTL cache 30s meta / 10s body; `force` on
  palette open) makes an attached vault searchable before any note is opened.
  `scanVaultBases()`: DFS for `*.base`, per-file errors swallowed; ids
  `vault-base:<relpath>`; surfaces in Lists ("From vault") and as saved-View
  chips when under `Library/Filters/`.
- **Export**: the search palette's **Export N** modal is the only working
  export — modal (580px) listing note results as **drag cards** (dragstart sets
  text/plain = rendered markdown, droppable into any text field) with hover
  per-card ".md download" and a header "Download all" (single file, or all
  concatenated with `\n\n---\n\n`). Markdown includes a metadata header block
  (Tags/Project/Area/Tier/Type then `---`). ⚠ The `/export` route is a stub
  ("Coming soon — export to PDF, Markdown bundle, Obsidian vault").
- **Archive search** (`shared/ArchiveView.tsx`): `view:open-archive` → z-120
  modal (max-w-2xl): header "Archive · N archived", autofocused search (title
  substring), kind pill row (All/Note/File/Contact/Event/List with counts;
  empty kinds hidden), rows = kind icon + title + kind label + hover "Restore"
  (flips archived/trashed false on the canonical per-kind store). Notes open
  directly from here. Archiving is a flag, never a move. Empty: "Nothing
  archived …" / "No matches".

### 2.18.7 Data view builder — `lists/DataViewBuilder.tsx`
No-code Dataview replacement: pick source (current workspace + kind
note/task/file/contact/event — recorded as a `kind ==` filter), FilterBuilder,
columns/sort/group/limit pickers offering built-ins + all discovered custom
property keys, layout (table/gallery/board/folder), live table preview via
BaseFileView, "Save view" → `Library/Filters/<name>.base` + a copyable
`/data-view` embed block (`encodeDataViewBlock`). v1 = table layout only,
single workspace.

## 2.19 Calendar — `components/calendar/CalendarExtension.tsx`

A global "ambient" tool (activity rail, after Contacts), full-bleed,
lazy-loaded, error-boundary-wrapped. Shows dated items from **every** workspace
(`loadAllObjects`).

### 2.19.1 Layout
1. **ToolRailHeader** — fixed 44px (h-11) row, bottom border: 24px rounded icon
   tile (`bg-primary/10 text-primary`, CalendarDays), 13px semibold "Calendar",
   11px muted subtitle = the dynamic period title, right-aligned action cluster.
2. **Body** — three columns: **left sidebar 224px (w-56)** (hidden below `md`,
   right border, `bg-panel/30`, p-8, scrollable: MiniMonthNav + the calendar
   checklist), **main grid** (flex-1; Month/Week/Day/Agenda per view mode),
   **right day-detail panel 288px (w-72)** (left border, `bg-panel/40`).

### 2.19.2 Header actions (left→right, :533–650)
- **View toggle**: segmented `month | week | day | agenda`, 12px capitalized in
  a `bg-secondary/40` pill; active `bg-primary text-primary-foreground` +
  shadow.
- **‹ prev**, **Today** (bordered 12px), **next ›** — view-aware stepping:
  month/agenda step the month; week ±7 days; day ±1 day off the selected day.
- **Project filter** `<select>` (only when any object has a project): "All
  projects" + sorted distinct; filters the whole pool; max-w 140px. New events
  created while a filter is active are stamped with that project so they don't
  vanish.
- **Sync** button (only when ≥1 *enabled* ICS feed): RotateCcw (spins while
  syncing), "Sync"/"Syncing…".
- **Google**: if OAuth connected → "Google sync" button (two-way pull+push;
  tooltip = last outcome message); else a dashed "Connect Google" hint opening
  Settings → Connections.
- **Sources** gear → popover (§2.19.7). **`+ Event`** primary button — creates
  an event on the selected day (title "New event", 09:00–10:00, auto-selected
  so the inline editor opens immediately).
- Header title: day view `EEEE d MMM yyyy`; week `d–d MMM yyyy` same-month,
  else `d MMM – d MMM yyyy`; month/agenda `MMMM yyyy`.

### 2.19.3 Data layer (`src/lib/calendarSources.ts`)
- A `CalendarItem {id, kind, date(yyyy-mm-dd), endDate?, time?(HH:mm), title,
  obj}` derives from **any object with a resolvable date**. Kinds: event, task,
  note, file, contact, list. Default date source = `metadata.calendarDate`
  (notes: calendar date; tasks: due date; events: startTime); default title =
  `calendarTitle || title || "Untitled"`.
- `CalendarConfig` (localStorage `app.calendar.config.v1`): `enabled` per kind
  (defaults: event/task/note ON, file/contact/list OFF) + per-kind `dateField`
  / `titleField` overrides that can point at `custom:<property>`. ⚠ Calendar
  view state is deliberately never written into note data — the Sources footer
  says "View-only settings — never written to your notes."
- Multi-day events (endDate > date) bucket onto **every day they span**.
  Within a day, timed items sort first by time, untimed after ("99:99"
  sentinel). Date parsing is **string-only** (`toDayKey` regex) — never
  `new Date` on the raw string; replicate to avoid TZ off-by-one.
- Kind colors: event=primary, task=warning, note=#0ea5e9 sky, file=#8b5cf6
  violet, contact=#ec4899 pink, list=#10b981 green. **Feed-imported events use
  their feed's hex instead** (per-calendar tinting, Google style).
- Refresh triggers: `workspace-change`, `notes-changed`, `events-changed`,
  `tasks-changed`; feed list refresh on `calendar-feeds-changed`.

### 2.19.4 Event chip (shared visual, `EventChip`, :88–155)
- **Compact** (month grid): rounded-5px pill, 3px colored left bar, background
  = 13% tint of the source color (color-mix), 11.5px text; optional bold
  tabular start time at 70% opacity, then truncated medium title. Tooltip
  "HH:mm  Title". Hover: brightness-110 + small shadow. Selected: 1px primary
  ring.
- **Row** (agenda + day panel): full-width, rounded-md, 3px left bar, 11% tint,
  contains the object's **kind icon** (format-aware, e.g. red PDF page for a
  dated .pdf), 12px time, 13px title.
- **Single click = select** (focuses the object in the right metadata sidebar
  AND selects its day). **Double-click = open**: notes open in the floating
  NoteOverlay (§2.20.3); events edit inline in the day panel.

### 2.19.5 Views
- **Month** (`MonthGrid`, :875–1005): weekday header row Mon…Sun (12px semibold
  uppercase tracking-wider, centered; Sat/Sun dimmed 45% vs 70% muted;
  `bg-panel/20`, bottom border). Grid: 7 × N whole weeks, each row an equal
  fraction of remaining height; every cell right+bottom `border-border/50`,
  padding ~6px. Cell states: selected `bg-primary/10` + inset 1px `primary/40`
  ring; today (unselected) `bg-primary/6`, hover /10; other cells hover
  `bg-secondary/30`; out-of-month `bg-muted/30`; weekend (in-month)
  `bg-muted/12`. Cell header: day number in a 22px round badge — **today =
  filled primary circle, bold, small shadow**; out-of-month 40% muted; else
  semibold. Right side: a **hover-revealed `+` add-event button** (18px;
  hover on it `bg-primary/15 text-primary`; tooltip "Add event"). Body: up to
  **3 compact chips**, 3px gaps; then **"+N more"** (12px medium muted, hover
  secondary bg) which selects the day — details go to the right panel; there
  is NO expanding popover. Clicking anywhere else selects the day.
- **Week & Day** (`WeekGrid.tsx`, `DayGrid.tsx`, `AllDayRail.tsx`): shared
  TimeGrid — hour rows `HOUR_HEIGHT = 44px` × 24, left time gutter 52px with
  right-aligned 11px tabular `HH:00` labels (00:00 blank); on mount scrolls to
  ≈08:00. The header + all-day band reserve the scrollbar's width so column
  separators align (ResizeObserver re-measure). **Week header**: 7 day-column
  buttons — 11px weekday abbrev (muted 50%) over a 24px day-number circle
  (today = filled primary); selected column `bg-primary/8`; click selects the
  day. **Day header**: 28px day circle + stacked "EEEE" 13px semibold /
  "MMMM yyyy" 12px muted. **All-day rail**: rendered only if any visible day
  has an item with no parseable HH:mm; left gutter cell "all-day" (11px
  uppercase muted 40%); per day column (min-h 28px) stacked flat pills —
  rounded-3px, 2px left bar, 12% tint, kind icon + truncated 12px title; click
  select / double-click open; multi-day events land here on every spanned day.
  Timeless items (dated notes, task due dates) ALWAYS land here, never in the
  hour grid. **Timed blocks** (`DayColumn`): absolutely positioned by minutes
  (top = startMin/60×44; height = duration, min 16px); end from the event's
  endTime; non-events default 60-min blocks; end ≤ start also falls back to 60.
  **Overlap layout = greedy lane-packing within overlap clusters** — equal
  side-by-side widths (`layoutDay`). Block: rounded-4px, 2px left bar, 15%
  tint, 10.5px medium title row with 12px kind icon; if height ≥30px a second
  11px line `HH:mm–HH:mm`. Tooltip "start–end  title". Selected = primary ring
  + z-raise; hover = shadow + z-raise. **Now indicator**: today's column only —
  a 2px destructive dot at the left edge + a 1px red line across the column at
  the current minute, ticking every 60s. **Double-click an hour slot** creates
  a 1-hour "New event" at that hour (capped 23:00) and selects it for inline
  editing.
- **Agenda** (`AgendaList`, :1009–1093): a plain chronological timeline of the
  current month off the same span-expanded byDay map (multi-day events show
  each covered day). Each day = a section: left 56px date rail (12px "EEE"
  muted, a 36px day-number circle — today filled primary — then 12px "MMM"),
  right column of row-variant chips separated by a 1px left border.
  Deliberately NO "today first" banner (that lives in Mission Control). Empty:
  `ToolEmptyState` "Nothing scheduled in {Month}".

### 2.19.6 Mini-month & calendar checklist (left sidebar)
- **MiniMonthNav**: header ‹ month+year (12px semibold) ›. The mini-month
  **browses independently** of the main grid (seeded once from viewMonth,
  drifts freely; a day click re-anchors both). Weekday row `M T W T F S S`
  (single letters, 40% muted). Day cells 24px tall, 10.5px; today = filled
  primary circle; selected (non-today) = `bg-primary/15` semibold primary;
  out-of-month 35% muted; hover secondary. Days with ≥1 item get a 2px
  under-dot (`bg-primary/60`) unless today. Clicking selects (in Week/Day views
  re-anchors the grid; in Month/Agenda just selects). Aria labels ("…, today,
  has items").
- **"My calendars"** (below, top border): small-caps label, then one **checkbox
  row per kind** (Events, Task due dates, Notes, Files, Contacts, Lists). Row =
  whole-row toggle (~28px, 13px): a 14px rounded tick-box filled with the kind
  color + white ✓ when shown, dimmed outline when hidden. Toggles
  `config.enabled[kind]` — the SAME flag as the Sources popover (write-through,
  never drift).
- **"Other calendars"** = subscribed ICS feeds, same rows in each feed's hex,
  toggling the feed's `enabled` flag (hides its events AND excludes it from
  Sync). A feed row with a lastError gets a tooltip "…— last sync error:
  {msg}". No feeds: a single quiet "+ Subscribe to a calendar" row → Settings →
  Connections.

### 2.19.7 Sources popover (`SourcesMenu`, :1303–1395)
320px popover, header "Calendar sources" + caption "Pick what appears, and
connect a metadata property to the date or name." One bordered card per kind:
checkbox + kind color dot + label. When enabled, an indented 2-row grid:
**Date** select → "Default (calendar date)" or any discovered custom property
whose values look like dates (`discoverCustomDateKeys`, `^\d{4}-\d{2}-\d{2}`);
**Name** select → "Default (title)" or any custom key. Footer (12px, 45% muted,
✕ icon): "View-only settings — never written to your notes."

### 2.19.8 Day detail panel (`DayPanel`, :1097–1195)
- Header (bottom border): weekday name (base semibold) + **"TODAY" pill** when
  applicable (`bg-primary/15`, uppercase 12px primary); under it "d MMMM yyyy"
  12px muted. Right: a CalendarPlus icon button (32px, primary, hover
  `bg-primary/10`, tooltip "Add event on this day").
- Body (scroll): row-variant chips for every item on the selected day; empty
  "Nothing on this day".
- **Inline event editor** (`EventEditor`, :1197–1299) below the list when the
  selection is an event: bordered card titled "EVENT" (12px bold uppercase
  widest-tracking 50% muted) with a trash button (hover destructive) top-right;
  title text input (autosaves per keystroke via patch); **Start** row =
  CalendarDays icon + date input + 74px time input; **End** row = "→" glyph +
  date + time (blank end date ⇒ single-day; handlers preserve untouched parts
  so a multi-day span survives edits); **Location** row (MapPin + input);
  **Notes / agenda…** 64px textarea. Every field patches immediately (persist →
  `events-changed` → grid refresh).
- Footer (only when the Notes kind is enabled): full-width quiet button,
  FileText + "**Open daily note**" → opens/creates the SELECTED day's daily
  note in the floating NoteOverlay (not by navigating). ⚠ IA-MAP's "today's
  cell IS the daily note" is not what ships — the cell is just highlighted.

### 2.19.9 Selection & keyboard (:408–437)
`←`/`→` step the current period (view-aware); `t`/`T` jumps to today (also
re-anchors the month); `Esc` clears the selection / closes the inline editor
(works even while typing — it also blurs the field). Keys ignored while typing
(input/textarea/select/contenteditable) or with any modifier held. Stepping
weeks/days keeps viewMonth following the selected day so mini-month + month
grid stay coherent. Selecting an item also focuses it globally
(`useActiveObject.setFocused`).

### 2.19.10 Event entity (`src/lib/events.ts`)
`Event = ObjectMetadata + {id, title, startTime (ISO local "yyyy-mm-ddTHH:mm"),
endTime ("" = all-day/open-ended), location, attendees: string[], notes,
sourceNoteId?, archived?, createdAt, external?, feedId?, externalUid?,
googleId?, etag?}`. `attendees` is separate from `metadata.people` on purpose
(external guests). `createEvent` mirrors startTime→calendarDate and
title→calendarTitle, stamps the active workspace. All date parsing is regex on
the string. Helpers: `eventTime`, `eventDayKey (calendarDate ||
startTime.slice(0,10))`, `getEventsOnDay`, `getUpcomingEvents` (timed,
non-archived, from now onward; feeds meeting suggestions). ⚠ Events are NOT
`.md` files in `library/events/` despite D25 — they are a document collection
under key `app.events.v1` (no markdown mirror). Port the entity-store behavior
(§4).

### 2.19.11 ICS feeds ("Other calendars")
**Setup UI — Settings → Calendars** (SettingsModal.tsx:3456–3650): intro copy
(one-way read-only import; points at Google Calendar's "Secret address in iCal
format"). "Add a calendar" card: Name ("e.g. Work, Personal"), mono URL input
(placeholder `https://calendar.google.com/calendar/ical/…/basic.ics`),
**"Add & sync"** primary (disabled without URL) — adds then immediately syncs.
"Subscribed calendars" list + **"Sync all"**: each feed card = color dot, name,
enable **toggle switch**, mono URL, status line (error in destructive red, else
"N events · last synced {locale datetime}", else "Not synced yet"), per-feed
Sync now (spinning) and Remove (confirm `Remove "X" and its imported events?`,
danger — removal also deletes the feed's imported events). Status toast line
under the list ("Synced — 3 added, 1 updated…"). Empty: dashed "No calendars
yet. Add one above to import its events."
**Feed model & sync** (`src/lib/calendarFeeds.ts`): `CalendarFeed {id, name,
url, color, enabled, lastSyncedAt, lastError, eventCount, workspaceId?}`;
colors round-robin from 8 Google-ish hexes #4285F4 #0F9D58 #DB4437 #F4B400
#AB47BC #00ACC1 #FF7043 #9E9D24. Sync: fetch (native, CORS-free) → parse ICS →
**expand recurrences into per-occurrence instances** over −60 days…+365 days →
upsert into the event store keyed by feedId+externalUid. Feed-owned fields
(title/times/location/notes) refresh; the user's own metadata
(area/project/tags/people/tier) on an imported event is **preserved**; events
the source dropped are removed. All enabled feeds auto-sync **on app launch**,
fire-and-forget (`__root.tsx:1064–1074`).
**ICS parser** (`src/lib/ics.ts`): minimal RFC-5545 — unfolds lines, reads
VEVENTs (UID/SUMMARY/DESCRIPTION/LOCATION/DTSTART/DTEND/RRULE), UTC `Z` →
local wall-clock, floating/TZID literal; all-day = date-only DTSTART. RRULE:
FREQ DAILY/WEEKLY/MONTHLY/YEARLY + INTERVAL + COUNT + UNTIL + BYDAY (weekly),
capped at 500 occurrences; each occurrence gets uid `<uid>::<yyyy-mm-dd>` so
deletions dedupe per-occurrence.

### 2.19.12 Google two-way sync (`src/lib/calendarSync.ts`)
OAuth in the native shell (loopback + PKCE; tokens never in the UI layer).
Surfaces: the Calendar header button + Settings → Connections.
`syncCalendarBothWays` = pull (Google → events, keyed googleId, etag
concurrency: a 412 on push re-pulls then retries) then push; outcome message
("Pulled 4 events from Google. Pushed 2 events to Google.") shown as the button
tooltip. Degrades to "not connected" hints.

### 2.19.13 AgendaWidget
Dashboard/Mission-Control widget "On the agenda · today": scrollable list —
events first (48px-wide 12px tabular time or "—", calendar icon, title; click →
switch to the Calendar extension) then today-dated notes (kind icon, click
opens the note). Empty: calendar icon + "Nothing on the agenda today" /
"Events and dated notes show up here".

## 2.20 Daily notes

### 2.20.1 Model (`src/lib/dailyNotes.ts`)
- Settings (`app.dailyNotes.settings.v1`): `{folder: "Library/notes/Daily
  Notes", titleFormat: "{{date}}", templateId: "tpl_daily", templateBody: "",
  openOnStartup: false}`.
- A daily note is a normal Note with `metadata.type = "daily-note"`,
  `calendarDate = yyyy-mm-dd`, `calendarTitle = title`, `customPath =
  <folder>/<safe-title>.md`, workspace defaults applied (`buildDailyNote`).
  Title = titleFormat expanded ({{date}}, {{year}}, {{month}}, {{day}},
  {{workspace}}…), fallback the date. Body = `settings.templateBody` if set,
  else the chosen template's body, variables expanded. Filename sanitizes
  `\/:*?"<>|` → `-`.
- `getOrCreateDailyNote(date, workspaceId?)` — **per-workspace**: finds an
  existing workspace note of type daily-note matching the calendarDate OR the
  derived path; creates + persists otherwise. Each workspace has its own
  "today". ⚠ There is NO carry-over behavior (no rollover of unfinished
  checkboxes/tasks) — aspirational if expected.

### 2.20.2 Entry points (all converge on getOrCreate)
1. Command `daily:open-today`, default **Mod+Alt+D** (⚠ not Ctrl+D as docs
   say); handler switches to Notes and opens the note as a normal editor tab.
2. Native/in-window menu "Daily Note".
3. SlotsBar "Today" slot (§2.4).
4. Calendar day-panel footer "Open daily note" — for the SELECTED day (any
   date), in the floating NoteOverlay.
5. Settings → Daily Notes "Open today's note" button (real editor tab).
6. **Open on startup** toggle: on boot creates/opens today's note in the
   editor; takes precedence over the "land on Home" setting.

### 2.20.3 NoteOverlay — the floating note editor (`shared/NoteOverlay.tsx`)
Summoned by `note-open-overlay` (Calendar → daily note; double-clicked dated
notes). Full-screen dim (`bg-background/60` + blur), centered card max-w 768px,
height 80vh, rounded-lg, elevated shadow. Header: borderless **title input**
(base semibold, editable) + ✕. Body: the **real markdown editor** (same
component as the Composer), autofocused, autosaving on a 600ms debounce
through `upsertNoteFast`. Close = ✕ / Esc / backdrop, flushing pending edits.
Notes hydrate from disk first if they have a customPath and empty body.
Related: **NotePreviewModal** (read-only peek via `note-preview`) and
**MeetingNoteOverlay** (§2.21.4) also ship as shell overlays.

## 2.21 Templates

### 2.21.1 Model (`src/lib/templates.ts`)
- `NoteTemplate {id, name, body, metadata? (type, area, project, tags, tier,
  people, description, custom), createdAt, updatedAt}`. Metadata is a
  **suggestion** seeded onto created notes, fully editable afterwards.
- Storage: vault KV `app.templates.v1`; `app.templates.defaultNoteId.v1` holds
  the **new-note default** template id. The loader merges: stored (or built-ins
  if none) + any missing built-ins + **folder templates** scanned from
  `<vault>/Library/templates/*.md` (id `file:<lowername>`, body = raw file;
  async, fail-safe, refires `templates-changed`). `saveTemplateToFolder(name,
  body)` writes a template as a real `.md` there.
- **Variables** (`applyTemplateVariables`): `{{title}} {{workspace}} {{date}}
  (yyyy-mm-dd) {{time}} (HH:mm) {{year}} {{month}} {{day}} {{weekday}}` —
  literal replaceAll, expanded **only when a template is used**, never while
  authoring.

### 2.21.2 Built-in templates (exact bodies)
1. **Daily note** (`tpl_daily`, meta `type: daily-note`): `# {{date}}` ␤␤
   `## Focus` / `- ` ␤␤ `## Notes` / `- ` ␤␤ `## Tasks` / `- [ ] `
2. **Blank note** (`tpl_blank`, `type: atomic`, empty body).
3. **Meeting note** (`tpl_meeting`, `type: meeting`): `# {{title}}` ␤␤
   `Date: {{date}}` ␤␤ `## Attendees` / `- ` ␤␤ `## Notes` / `- ` ␤␤
   `## Actions` / `- [ ] `
4. **Kanban board** (`tpl_kanban`, `type: kanban`, custom `kanban-plugin:
   board`): `%% kanban:settings` / `{"kanban-plugin":"board"}` / `%%` then
   `# Backlog`, `# In Progress`, `# Done` sections each with `- [ ] `.

### 2.21.3 Authoring & manager UI
- **Templates edit as real notes**: `openTemplateInEditor` persists, switches
  to Notes, fires `composer-open-template`; the Composer converts the template
  to a Note (note id **= template id** so reopening focuses the same tab; body
  keeps {{vars}} verbatim; metadata seeded + hidden marker `livTemplateId`) and
  opens it like any note. While such a tab is open, a **500ms-debounced
  mirror** folds title/body/metadata back into the template store
  (`noteToTemplatePatch` strips markers and drops empty fields).
- **Manager** (inside Settings → Daily Notes, SettingsModal.tsx:1510–1640):
  header "Templates" + caption ("Click a template to open and edit it as a
  real note in the full editor — the cramped little box is gone."), with
  "**+ New template**" (creates `# {{title}}\n\n`, type template, opens in
  editor) and "**Generate with AI**" (primary, Sparkles). Bordered list, one
  row per template: FileText icon, name (12px medium), optional type badge,
  plus status tags **"NEW-NOTE DEFAULT"** / **"DAILY DEFAULT"** (11px uppercase
  primary). Row actions: "Default · new", "Default · daily" (small bordered
  12px buttons setting the two default ids), delete (trash; confirm; disabled
  when only 1 template remains; clears either default if it pointed there).
  Clicking the name opens the template in the full editor. Selected row
  `bg-primary/5`.
- **AI template generator** (`shared/TemplateGenerator.tsx`): modal (z-150,
  dim + blur, 720px): header "Generate a template with AI" (Sparkles) + ✕.
  Body: description textarea (autofocus; **Mod+Enter generates**; placeholder
  "e.g. A contact template with phone, email and company fields, plus a
  meetings data view"), optional name input, **Generate / Regenerate** button
  (Sparkles→RotateCcw; spinner while streaming). The result streams live into
  a mono `<pre>` preview with a pulsing ▋ caret. Errors: missing key →
  destructive banner + "Open AI settings"; 401 → "Invalid API key…". Footer:
  **Reject** and **Accept & edit** (parses the draft — optional YAML
  frontmatter → suggested metadata, fences and {{vars}} preserved, outer
  markdown-fence wrapper stripped — saves, closes, opens in the full editor).

### 2.21.4 Apply flows
- **New editor tab**: seeds body + metadata from the new-note default template,
  with {{title}}={tab name}, {{workspace}}={workspace name}; a new **kanban**
  tab always uses tpl_kanban. Workspace defaults (project/area) win over
  template metadata.
- **Quick Capture & Capture extension**: a template picker attaches a template
  — the body seeds into the editor and is **sticky** (each send/capture
  re-seeds until detached via the empty choice); template metadata pre-fills
  type/area/project/tier/tags.
- **Daily note creation**: uses `settings.templateId` (default tpl_daily).
- **Meeting-note flow** (`shared/MeetingNoteOverlay.tsx`, event
  `open-meeting-composer`): summoned (z-150) from Welcome-screen suggestions
  ("Create a note for <meeting>") or the command "Create meeting note from next
  event" (`ai:create-meeting-note` — picks the next upcoming event without a
  sourceNoteId; alert "No upcoming meetings without a note." otherwise). Card
  (max-w 512px): header "New meeting note" / "Pre-filled from your calendar —
  review and create." Read-only context chips: date, time, location. Fields:
  **Title** (autofocus, = event title), **Template** select (defaults
  tpl_meeting), **Project / Area** (2-col), **People** (comma list; event
  people else attendees), **Tags**, **Note** body textarea (8 rows, mono)
  re-seeded from the template whenever the template changes (metadata edits
  survive). Footer: Cancel / **Create note**. On create: `type: meeting`,
  calendarDate = event day, event's workspace (fallback Home); the event is
  back-linked via sourceNoteId (stops the suggestion re-firing); field
  provenance recorded ("From calendar event "X" at HH:MM on yyyy-mm-dd").
  Esc/backdrop closes. Missing event → "That event no longer exists."

## 2.22 Habit tracking

### 2.22.1 Data convention (`src/lib/habitStats.ts:8–30`)
Habits live as **markdown checkboxes in daily-note bodies** — no separate
store: `- [x] Habit (3)` → 3 points; `- [x] Habit` → 1 point; unchecked →
pending, 0 points. Line-anchored regex; fenced code stripped first. A
`points: N` in the note's metadata overrides the day's summed total. Days keyed
by the note's calendarDate; multiple notes on one day sum. ⚠ D13 ("definition =
view-file; check-ins = DB rows") does not match — everything derives from
markdown at read time; there is no UI to check a habit outside editing the
daily note.

### 2.22.2 Derived stats (pure, injected "today")
Daily series (date, points, completed count); per-habit distribution (points +
days, desc); per-habit completion-date sets; **streaks**: the current streak
counts back from today *or yesterday* (doesn't break before you log today) —
overall and per-habit (only live streaks returned); trailing-7-day week
summary; heatmap window with intensity 0–4 bucketed against the series max
(>75% → 4, >50% → 3, >25% → 2, >0 → 1).

### 2.22.3 HabitWidget (`components/dashboard/HabitWidget.tsx`) — top→bottom
Card (rounded-lg border, bg-card, p-4): header "HABITS & POINTS" section label
+ right hint `"- [x] Habit (N)" = N pts · checked default 1`. **Empty state**:
"No habit points yet. Add checkboxes like `- [x] Read (2)` to your daily
notes." **Summary tiles** (2×2, 4-up wide): Flame "Current streak" N days ·
Trophy "Longest streak" · CalendarDays "This week" N pts · TrendingUp "Avg /
active day" (1 decimal). Tile = muted pill, icon, big bold tabular number +
small suffix, 12px label. **This week**: 7 dots (14px circles; filled primary
when active, 20% muted otherwise; today ringed `ring-primary/40`), weekday
initials, per-dot tooltip "date: N pts"; right "N**/7 days**". **Active
streaks**: pill chips per habit — Flame (primary), truncated label (max 10rem),
bold count. **Heatmap**: GitHub-style SVG — week columns × 7 rows, 12px cells
(16px large variant), 3px gap, 2px radius; fills muted → primary at
30/50/72/100% mix; today outlined 1.5px primary; hover tooltip "Jul 6 · 3 pts ·
2 done"; legend "Less ▢▢▢▢▢ More"; header "Last {N} days". **Points over
time**: 30-day line chart (monotone, primary stroke 2px, no dots, active dot
r4, horizontal grid only). **Points by habit**: horizontal bars of the top 8
labels (rounded right ends, primary fill).

### 2.22.4 Habits page (`src/routes/habits.tsx`)
Route `/habits`: centered max-w-4xl. Header: Activity icon (primary) + "Habits
& points" h1 + "Tracked from your daily notes' habit checkboxes." Right:
**Month / 12 weeks** toggle (heatmap window 28 vs 84 days). Body: the
HabitWidget in `large` mode. Notes fetched filtered to type = daily-note, then
workspace-scoped; refreshes on `workspace-change`/`notes-changed`. The widget
also ships as board widgets "Habits & points" and "Review scorecard" (weekly
points/completions summary).

## 2.23 AI surfaces

All AI in Liv goes browser→Anthropic directly. (§4: in lotus every AI WRITE
becomes a proposal through the core; the reads and every approval UI below
replicate as-is.)

### 2.23.1 Foundations
- **Client** (`src/lib/anthropic.ts`, 327 ln): ONE module for all calls.
  Exports `callAnthropic` (→ text), `streamAnthropic` (SSE onChunk),
  `runAnthropicTools` (tools; returns {stopReason, content, text, toolUses} —
  the Jarvis engine), `callAnthropicJSON` + `extractJson`,
  `MissingApiKeyError` (every caller catches it and shows a calm "Settings →
  AI" hint — never a crash/toast), `hasApiKey()`, `rerankSearchResults`
  (§2.8.4). Fallback model `claude-haiku-4-5`.
- **Key/model storage**: key at localStorage `app.chat.apiKey`, model at
  `app.chat.model`; `CHAT_MODELS` = Claude Opus 4.5 / Sonnet 4.5 / Haiku 4.5.
  Settings → AI is §2.25.2. ⚠ Settings' "Enable AI features" toggle, AI Level
  1–4 radio grid, auto-suggest triggers, and fields-to-suggest chips are read
  by NOTHING (`loadAIConfig` has no feature consumers) — fake UI.
- **Custom prompt library** (`src/lib/customPrompts.ts`): `CustomPrompt {id,
  name, template}` at `app.customPrompts.v1`; seeds 3 starters ("Rewrite
  clearer", "Summarize", "Make action items"). Run surfaces: slash-menu "Run
  prompt…" items + palette "Run prompt: <name>" (dynamic `prompt:run:<id>`
  commands). `runPrompt` substitutes `{{selection}}` (appends the selection if
  the placeholder is absent), streams with a "return ONLY the transformed
  result" system prompt. Managed in Settings → AI (`PromptsManager`: list rows
  with pencil/trash, "New prompt", empty state with "Add the starter prompts";
  editor = name + template textarea that must contain `{{selection}}`).
- **Ambient context** (`src/lib/ambientContext.ts`): event-sourced snapshot
  read lazily at AI send time — `activeSurface` (from `extension-switch`),
  `viewContext` (from `files-context`: view title, filter description, match
  count, ≤25 visible rows w/ type/area/project/tags), `captureDraft` (live
  quick-capture title/body via `capture-draft`; cleared on leave), plus a
  one-line vault overview (object counts by kind + 12 recently-edited titles).
  `describeAmbientContext()` = the system-prompt block consumed by AIChat and
  CopilotPane; `getAmbientHeadline()` = the honest "Seeing: …" header — the
  visible "can the AI see my vault?" indicator.

### 2.23.2 AI Chat department — `components/chat/AIChat.tsx` (1,060 ln)
One extension (`ai-chat`) hosting FOUR views via a centered segmented toggle:
**Chat | Agents | Jarvis | Assist**. (Naming note: "Agents" is the *script
runner*; the actual agent loop is "Jarvis".)
- **Top control bar** (portaled into the shared surface header; h-9, border-b):
  far left — model selector (current label + chevron; dropdown of CHAT_MODELS,
  selected bold/primary; persisted). Center (absolute overlay) — the 4-way pill
  toggle, icon+label each (MessageSquare Chat / Bot Agents / Sparkles Jarvis /
  Lightbulb Assist); active = `bg-background` + shadow. Tooltips: "Department
  agents & scripts", "Jarvis — vault-wide agent that takes actions you approve",
  "Assist — suggestions the AI spots while you work", "Conversation". Far
  right — red "⚠ No key" pill when keyless; gear toggles an **inline API-key
  editor strip** below the bar (password input `sk-ant-...`, Enter saves, Esc
  closes, Save, "Remove" when a key exists); BookOpen toggles the right
  Context & Prompt panel (chat view only).

**Chat view:**
- **Left sessions rail** (w-60, border-r; chat view only): ToolRailHeader
  "Chats" + "＋ New chat"; search ("Search chats…"); recency list (createdAt
  desc — sessions have no updatedAt, so edits don't re-bubble; accepted v1
  limitation). Row = MessageSquare + truncated name; active `bg-primary/10`.
  Hover pencil (rename) + trash (delete; hidden when only one session —
  at-least-one invariant). Double-click renames (inline input, Enter/blur
  commit, Esc cancel). Deleting the active session activates the last
  remaining. Store (`src/lib/chatStore.ts`): ONE vault-wide flat session list
  (workspaceId = provenance only); hydrated in one parse on open; all
  mutations write-through; opening never writes; empty store seeds "Chat 1".
- **Center transcript** (max-w-2xl centered): plain bubbles — user
  right-aligned `bg-secondary/50`, assistant left `bg-card`, both rounded-2xl
  bordered, whitespace-pre-wrap (NO markdown rendering, no citations). Loading
  = left bubble with spinner + "Thinking…". Auto-scrolls to end.
- **Empty states**: keyless + no messages → centered card "Add your API key"
  with inline key input + Save + "Get a key at console.anthropic.com"; keyed +
  empty → "Start a conversation / Type a message below to begin".
- **Input**: rounded-2xl pill, auto-growing textarea (max 5 lines, 24px each),
  Enter sends / Shift+Enter newline, circular primary ArrowUp send (spinner
  while loading). Placeholder "Message Claude…" or "Set up your API key
  first". **Draft persistence**: per-session draftInput, 400ms debounce,
  restored on session switch, cleared on send.
- **Send pipeline**: system prompt = session.systemPrompt + ambient-context
  block + pinned context-notes block; maxTokens 2048. Errors become readable
  assistant messages ("API error: no API key set (Settings → AI)." / "API
  error: Invalid API key." / message text / "Network error. Please check your
  connection.").
- **Right Context & Prompt panel** (w-60, toggle): "System prompt" textarea;
  "Context notes" — search input ("Add note as context…", vault-wide, top 8
  matches in a popover), pinned notes as removable rows (FileText, ✕), empty
  "No notes in context"; "Actions" — "Save chat as note" (materializes the
  transcript as `**You:**/**Claude:**` markdown in the active workspace) and
  destructive "Clear conversation"; both disabled when empty.
- The active chat session is a first-class object (kind `message`) published to
  the global inspector while view === "chat". ⚠ A `copilot-prompt` /
  `sessionStorage copilot.pendingPrompt` prefill listener ships with no
  dispatcher — replicate or drop deliberately.

### 2.23.3 Jarvis — the gated agent loop
**Engine** (`src/lib/jarvisAgent.ts`, 775 ln; pure TS): `runJarvis(history,
{model, signal})` = async generator, MAX 12 turns. Loop: `runAnthropicTools` →
no tool_use ⇒ yield `{kind:"assistant", text}`, stop; else resolve each tool in
order — **READ tools auto-run** (yield `{kind:"read", toolName, input,
result}`); **WRITE tools pause**: `const decision = yield {kind:"confirm",
request:{toolUseId, toolName, input, preview}}` — the generator suspends until
the UI resumes with `{approved}`. Approved → run handler, yield
`write-result approved:true`; rejected → tool_result "User REJECTED this
action. It was not performed." **STRUCTURAL INVARIANT: a write handler is only
reachable past this yield gate — preserve exactly** (jarvisAgent.ts:24–28,
729). Turn cap → error "Jarvis stopped after too many tool turns. Try a more
specific request."; MissingApiKeyError → `{kind:"error", missingKey:true}`;
abort → silent return.
**Tools** (:405): READ = `search_vault` (substring over active-workspace
objects, limit 12, one-line `describeObject` rows), `read_object` (metadata +
relations + body ≤4000), `list_project` (project or whole workspace, cap 40),
`summarize_project` (via `gatherProjectContext`), `list_workspaces` (marks
`[active]`), `open_note` (id-or-title → dispatches `extension-switch` to the
kind's surface; navigation counts as read; kinds without a surface politely
refuse). WRITE = `create_note`, `create_task`, `set_metadata` (patch merge),
`add_relation` (typed), `run_department_script`. Every write tool has a
`preview(input) → WritePreview {action, target, fields:[{label,value}]}` (e.g.
Create note → Project/Area/Tags/Body ≤280; Set metadata → one row per patch
key). System prompt: reads auto-run, writes require Approve, never assume a
write happened, ground in real ids, be concise.
**UI** (`shared/JarvisPanel.tsx`, 458 ln): full-width center pane (no session
rail; transcript per-mount, NOT persisted). Flat entry list: user/assistant
bubbles (user filled primary rounded-br-sm; assistant `bg-secondary/60`
rounded-bl-sm). **Read steps**: small collapsed pill per read tool — icon
(BookOpen for read_object, Search otherwise) + label ("Searched the vault",
"Read an object", "Listed a project", "Summarized a project", "Listed
workspaces", "Opened an object"); click toggles the raw result in a scrollable
`<pre>` (max-h-48). **PreviewCard** (the approval card; amber): warning header
= write-tool icon (create_note FilePlus, create_task ListPlus, set_metadata
Tags, add_relation Link2, run_department_script Play) + bold action + "—
target"; body = label/value rows (or "No additional details."); footer while
pending = primary **Approve** (✓) + destructive-text **Reject** (✕) +
right-aligned "Nothing changes until you approve". After the decision the
footer becomes a result strip: ✓ + result text (primary tint) or ⊘ "Rejected —
not performed." Buttons flip optimistically; the write-result event stamps the
real text. Busy: "Jarvis is working…" spinner bubble. Empty: Sparkles tile,
"Ask Jarvis", "Jarvis can search your vault and take actions — every change is
previewed for your approval first." No-key (transcript empty): "Jarvis needs
your API key" + "Add API key" (jumps to the chat key strip). Errors: red box,
"Add API key" link when missingKey. Input identical to chat, placeholder "Ask
Jarvis to find or do something…". History rebuilt from user/assistant entries
only.

### 2.23.4 "Agents" — department scripts
**Registry** (`src/lib/departmentAgents.ts`): pure-data `DEPARTMENT_AGENTS
{id, department, label, description, promptTemplate, output ∈
docx|note|tasks|text}`. Shipped: "Doc → polished draft" (text), "Outline →
Word document" (docx), "Inbox notes → tasks" (tasks — checklist `- [ ] action
(owner: …)`), "Meeting notes → agenda (Word)" (docx). `runDepartmentAgent`
streams the model then materializes: docx via `writeOfficeFile` into the vault
(returns the vault-relative path), note via `upsertNoteFast`, tasks parsed from
checklist lines, text as-is. ⚠ User-defined scripts: TODO, not built.
**UI** (`shared/AgentCreatorPanel.tsx`, the Agents view): centered max-w-2xl —
intro header (Sparkles tile, "Agents & Scripts"); two selects (**Department**,
**Script** — the script list keeps itself valid when department changes);
selected-script info box (output icon + description + "Produces: Word
document/Note/Action items/Text"). **Input**: label row with "Load a file"
(hidden file input, `.txt,.md,.markdown,.csv,.json,.pdf,text/*`; reads
`file.text()` — text-layer PDFs only, else hint "Try pasting the text
instead"; loaded filename shown, cleared on manual edit); resizable textarea
"Paste meeting notes, a brief, or the text of a document…". **Run** button
(Sparkles → "Running…" → "Run again" RotateCcw). Keyless → "No Anthropic API
key set. Add one in Settings → AI to run scripts." + "Add key". 401 → "Invalid
API key…". **Output**: live-streaming `<pre>` (mono, max-h-40vh, blinking ▋)
with Copy (✓ "Copied" 1.5s). On done, an artifact box: docx → "Saved Word
document to <path>" + **Reveal**; note → "Saved a note: <title>"; tasks →
"Extracted N action item(s)"; text → "Done — copy the text above."

### 2.23.5 Assist — the suggestion-only, no-LLM layer (`src/lib/assist/*`)
- **Model** (`assist/suggestion.ts`): `Suggestion {id, kind, title, rationale,
  targetIds[], confidence 0..1, destructive?, choices?, defaultValue?,
  apply(chosenValue?)}`. `id` is DETERMINISTIC (kind+targets+value) → dismiss +
  dedup survive rescans/reloads. `apply()` is a closure over an EXISTING seam
  only (the same code a user reaches by hand). Kinds (closed union):
  `tab-group | metadata-missing | reclassify | delete-empty | delete-dup` (⚠
  `reclassify` declared, no generator emits it).
- **Engine** (`assist/engine.ts`): `scanSuggestions(ctx?)` runs the generator
  table in order (tab-grouping, metadata-missing, declutter), each
  try/catch-isolated; dedup by id (first wins); drop dismissed; sort confidence
  desc. `AssistContext {tabs?, workspace?}` optional — badge callers pass
  nothing (the tab generator then no-ops). Mutations broadcast
  `assist-suggestions-changed`; every surface also rescans on `notes-changed` +
  `workspace-change`.
- **Generators**: **tabGrouping** — only when the strip has ≥8 tabs; buckets
  UNGROUPED non-blank tabs by deptType; a bucket ≥3 → "Group N <Notes/Tasks/…>
  tabs", rationale "You have N ungrouped … tabs open. Band them into one named
  group…", confidence `min(0.6 + n*0.05, 0.85)`, id
  `assist:tab-group:<dept>:<sorted member ids>`; apply mirrors the shell's
  createGlobalTabGroup (ONE save, then events). **metadataMissing** — walks
  non-archived/trashed notes that are `isUnfiled`; runs the SAME deterministic
  `suggestMetadata` as the Decide tray (mode "missing"); takes the top `types`
  candidate only when score ≥2.0 AND the reason is literally "its name appears
  in this note"; cap 6; `choices` = suggested value + other ranked types
  (dedup, cap 5); title `Set type "X" on "Title"`; confidence mapped to
  [0.6, 0.9]; id keyed on the DEFAULT value; apply(chosen) patches + saves.
  **declutter** — DESTRUCTIVE (soft-trash only, recoverable): (a) empty notes
  (no title AND no body AND still unfiled) → "Trash empty note", 0.7; (b)
  exact duplicates by normalized title+body: keep the OLDEST, propose trashing
  each newer copy → `Trash duplicate "Title"`, 0.75. Cap 8 total.
- **Dismiss store** (`assist/dismissStore.ts`): flat id set at vault key
  `assist.dismissed`. Accepting is NOT recorded (the world changes so the
  generator stops emitting); dismiss = "I saw it and don't want it". ⚠
  `clear()` exists with no UI. (§4: this becomes the declined sidecar.)
- **Shared cards** (`chat/AssistCards.tsx`, used identically by panel, chip
  popover, attention popover): **SuggestionCard** (non-destructive) —
  rounded-xl; kind icon in a primary-tint tile (tab-group Layers, metadata
  Tags, delete Trash2); title + rationale; optional **ChoiceRow** ("or set:" +
  value chips, selected filled; hidden when <2 choices); footer = primary
  **Accept** (busy spinner; label becomes `Set "value"` when the user swapped
  away from the default so the button never lies) + **Dismiss** +
  **JumpToButton** + right-aligned caption "You could do this yourself — this
  just offers it". **ApproveCard** (destructive) — amber idiom mirroring
  Jarvis: warning header (AlertTriangle + title), rationale, footer **Approve**
  / **Dismiss** / Jump, caption "Recoverable from Trash". **JumpToButton**:
  "Open" ↗ rendered only when targetIds[0] resolves to a non-trashed note;
  routes through `openObject`.
- **Assist view** (`chat/AssistPanel.tsx`): centered max-w-2xl list, header "N
  suggestion(s) — each is something you could do yourself." Accept awaits
  apply(chosenPick), clears the pick, emits+rescans; Dismiss persists +
  rescans. Needs no API key. Empty: Lightbulb tile, "Nothing to suggest", "As
  you capture and work, Assist flags tidy-ups it spots — grouping related
  tabs, filing unfiled notes, clearing duplicates — and offers to do them for
  you."

### 2.23.6 Assist presence: chip, rings, badges
- **AssistEntryIndicator** (`shared/AssistEntryIndicator.tsx`, 733 ln; mounted
  once at root): floating pill — Bot avatar in warning tint + "**N** things I
  can tidy" + chevron + tiny ✕. Count = vault-wide sum of
  `suggestionCountByWorkspace()`. Hidden in focus mode or when nothing
  pending. **Draggable/dockable**: pointer-drag (>4px threshold) snaps to the
  nearest allowed corner — bottom-left (default), top-left, top-right;
  **bottom-right is forbidden** (toasts own it). Dock persisted at vault key
  `assist.entryIndicator.dock`. A clean click (<4px) toggles the popover.
  **Expanded popover** (anchored above/below per dock; w-min(360px, vw−32),
  max-h min(60vh, 520px)): header "N suggestions — each is something you could
  do yourself.", top-5 cards (fully actionable), footer "See all in Assist →"
  (extension-switch to ai-chat). **Per-workspace dismissal**: ✕ stores
  `{workspaceId: countAtDismiss}` at `assist.entryIndicator.dismissed.v1`; the
  chip reappears when the active workspace's count GROWS past the dismissed-at
  count, or when other workspaces still have pending cleanup. Tooltip "Dismiss
  (re-appears when there's new cleanup)". Recompute debounced 150ms; z-60.
- **Attention primitive**: `.assist-attention` / `.assist-attention-inset` CSS
  = soft amber box-shadow ring (1px warning 60%) + a single 700ms settle pulse
  — box-shadow only, layout never moves — applied exactly while a suggestion
  targets a workspace row or tab (inset variant for overflow-clipped strips).
  `useAssistHoverAnchor(closeDelay 240ms)` = shared open/grace-close hover
  bookkeeping (one popover serves N anchors). **AssistAttentionPopover**
  (portal, fixed, z-80, warning-tinted, width 288 peek / 340 expanded, flips
  above when <200px below): **Peek** = Bot glyph + primary suggestion title +
  rationale + "+N more suggestions here" + footer "Show suggestion(s) →";
  click expands IN PLACE into up to 3 real cards + "+N more in Assist" + "See
  all in Assist". Hosts: (1) AppSidebar workspace rows (inset ring + the amber
  `WorkspaceAssistHead` count head); (2) GlobalTabBar tabs whose id appears in
  `suggestionsByTargetId`. (⚠ DESIGN-SYSTEM §8 claims these are missing —
  code has them; docs stale.)
- **Per-workspace resolution** (`assist/workspaceFlags.ts`):
  `suggestionsByWorkspace()` = one context-free scan; each suggestion resolves
  to a workspace via first targetId → repository → workspace id; unresolvable
  (tab-group) suggestions bucket under the ACTIVE workspace. All amber surfaces
  (rail head, ring, chip, ActivityBar badge) read this one seam.

### 2.23.7 Proactive suggestions, toasts, nudges
- **Engine** (`src/lib/suggestions.ts`): deterministic `getSuggestions()` (≤6,
  confidence-sorted): upcoming calendar events without a linked note → "Create
  a note for "X"" (action create-meeting-note, conf .92 today/.82); metadata
  near-duplicate clusters → "Review in Processor"; ≥3 notes with no
  project+area; ≥3 stale `active` notes (30d). `getAiSuggestions()` (async,
  ≤3, ✨-marked): sends TITLES+metadata of 40 recent notes only (bodies never
  leave), asks for ≤3 concrete actions, typically "Create "<synthesis note>"";
  [] on any failure. Action union: create-meeting-note / open-extension /
  open-route / run-command / create-note.
- **Toast layer** (`src/lib/suggestionNotifications.ts` +
  `shared/SuggestionToastManager.tsx`, mounted at root): idempotent poller —
  first scan 30s after start, then every 5min, skipped while document.hidden;
  ≤2 new toasts per scan; in-memory seen-set (reset on reload by design).
  Toasts stack fixed **bottom-right** (z-60, w-80, max 3 visible, oldest
  dropped), auto-dismiss 8s. Toast = rounded-xl border bg-popover
  shadow-elev-2; 32px rounded-lg primary/10 icon tile (calendar CalendarClock
  / cleanup Brush / metadata Tag / general Lightbulb), title (small Sparkles
  when AI-sourced), 2-line detail, primary action button (label + →, runs the
  same action table Home uses), ✕ dismiss. ⚠ IA-3 approved removing the
  floating tidy pill/toasts; still shipping.
- The same suggestion cards render on Home (`HomeDashboard.tsx`), the Launcher
  overlay, and the `SuggestionsWidget` board widget, with the identical
  `runSuggestion` dispatch.
- **Nudges** (`src/lib/nudges.ts` + `widgets/NudgesWidget.tsx` +
  `WhatNextWidget`): pure local queue (≤12): file-orphan ("File this") >
  add-area-project > link-orphan ("Link this to something") > revisit-task
  (overdue or 14d untouched, non-terminal). One nudge max per note; rows
  navigate to the object (suggester + navigator, never an editor).

### 2.23.8 Project status widget
`src/lib/aiProjectSummary.ts` + `widgets/ProjectSummaryWidget.tsx` (also feeds
Jarvis's summarize_project). `gatherProjectContext(workspaceId, project?)`
builds a capped snapshot (12 notes w/ 160-char snippets, 18 tasks with
status/due, 8 other objects). Widget: **Summarize** button (→ "Thinking…" →
"Refresh"); streams a "current state + what's done + suggested next actions"
read inline (pre-wrap). Idle: "A one-click AI read of where <scope> stands…";
no-key card with "Open AI settings" link; 401 → "Invalid API key — check it in
Settings → AI." Scope change aborts + resets.

### 2.23.9 Copilot pane (right rail) — `shared/CopilotPane.tsx` (340 ln)
The 5th RightSidebar tab. **Header** (Sparkles): "About <title> · <kind>" when
an object is focused; else "Seeing <ambient headline>" (e.g. "Projects · 14
items"); else "Ask about your vault or what you're looking at". Re-renders on
`extension-switch`/`files-context`/`capture-draft`. The transcript resets
whenever focus changes ("always about the thing in front of you"). Empty state
shows starter chips when focused: "Summarise this", "Suggest tags & type",
"What should I do next?". Send: system prompt = Copilot persona + full ambient
block + focused-object snapshot (`objectContext`: title/kind/type/area/project/
tier/tags/people + note body ≤4000 / task body ≤2000 / chat transcript ≤4000);
maxTokens 1024. Advisory only — never writes (except the task-agent Approve,
§2.15.11). Compact bubbles (user right `bg-primary/12`, assistant left
`bg-secondary/40`); "Thinking…" spinner; error line in red; persistent keyless
footer "🔑 Needs an API key (Settings → AI)". Input: 1-row autoresizing
textarea (max-h-28), Enter sends, primary Send square. Opened by **Mod+J**
(`copilot:open` — reveals the right panel → Copilot view).

### 2.23.10 Confirmed vs automatic — the table to preserve

| Surface | Automatic (no confirmation) | Requires explicit user action |
|---|---|---|
| Jarvis | READ tools + open_note navigation | EVERY write → amber PreviewCard Approve (structural gate) |
| Assist | scanning, badges, rings | Accept per card; destructive = amber Approve; Dismiss persisted |
| Alt+M Decide | suggestion fetch + staging | nothing saved until **Commit** |
| Inbox router / Triage | local heuristic pre-fill (≥0.6 confidence pre-accepts INTO THE DRAFT only) | AI chips Accept/Reject; **Commit & route** / **Commit accepted** writes |
| Selection rewrite / prompts / autocomplete | streaming preview / ghost text | Accept click / Tab; Reject/Esc discards |
| Meeting→tasks, Extract, Split | extraction/preview | checkbox review + Create / Accept |
| Task steps + drafts | suggestion fetch on panel open | drafts are copy-only, never sent |
| Task agent (Copilot) / board AI tab | proposal computation | Approve / Apply commits the validated patch |
| Naming | candidate fetch on click (auto-highlight for name-later notes) | click a chip to rename |
| Toasts/suggestions/nudges | surfacing | the primary button navigates/creates |
| Dept scripts / summaries / templates | — (user presses Run/Summarize) | docx/note materialization happens on Run (the one place output writes without a second confirm); template save behind Accept |

## 2.24 Processor — Inbox routing & batch triage (`processor/ProcessorExtension.tsx`, 3,413 ln)

Toolbar: batch name + count, debounced search, view tabs **Inbox | Triage |
Import | Merge**, Filter toggle (badge = active-filter count), "N excluded ×"
reset. ⚠ IA-3 wants this re-homed as Inbox Route+Tidy tabs — not done; this is
the shipping IA.

### 2.24.1 Inbox membership (`src/lib/processor.ts`)
`PLACEHOLDER_TYPES = {"", "atomic", "note"}`; `hasRealType` = not placeholder;
`isUnfiled(note)` = placeholder type OR (no area AND no project).
`getInboxNotes` = unfiled, non-excluded, newest first — workspace-wide.

### 2.24.2 Inbox view (`InboxView`, :1031)
- Left list w-72 "UNSORTED (n)": rows = FileText, title, 80-char body preview,
  and three **MissingChips** — grey `area/project/type` when present, amber
  `no area / no project / no type` when missing. Click selects (highlights,
  focuses the object into the right rail). **No auto-selection** — landing
  shows `InboxOverview` ("N objects to route — Pick one from the list…
  Nothing opens until you choose." or "Inbox zero / Everything has an area,
  project and type — it's all routed.").
- **"Later" sub-box** below the list: session-scoped deferred set (no
  persistence — a working decision); rows dimmed with Clock + "↺ Restore".
- **RouterPanel** (:1285) for the selected note:
  - Header: ← back, "✨ Route this object", right-aligned **"Suggest with AI"**
    (disabled keyless with tooltip; "Suggesting…" spinner), "→ Open", "✕
    Dismiss" (exclude without routing).
  - Always-on **local heuristics** (`LocalRoutingProvider`, processor.ts:373):
    area/project = the most frequent existing value mentioned in the text
    (confidence 0.5–0.85); type from keyword cues (meeting notes/checklist/
    idea/question/plan/summary/quote/how-to, 0.5–0.7); name from the first body
    line when the title is generic (0.6); tags = frequent content words that
    already exist as pool tags (≤5); relations = notes sharing the strongest
    tag (≤5, 0.4). ⚠ `AgentRoutingProvider` = deliberate empty stub.
  - **Draft seeding** (:930): fields with suggestion confidence ≥0.6 pre-fill;
    else the current value; else the active workspace's default area/project.
    Tags/relations start all-accepted.
  - Fields: Name (text), Area/Project (inputs + datalists of existing values),
    Type (select from the controlled pool, "—" option). Each `RouterField`
    header shows a pill "✨ <suggested> ✓" (only when it differs from the
    field; tooltip "Confidence NN%"); click = accept.
  - "Suggested tags" = toggle chips (#tag); "Suggested relations" = toggle rows
    (✓/＋, title, relation type, right-aligned).
  - **"Suggest with AI"** (`runAiSuggest`, :985): composes `aiSuggester`
    (reevaluate mode → type + tags), `suggestNames` (3 titles), and local
    `suggestRelations` into an **AI-suggestions tray** ("AI suggestions —
    accept or reject — nothing applies until you do"): grouped Accept/Reject
    chips (Name candidates / Type / Tags / Relations with hover reason).
    Accept writes into the same draft Commit reads and removes the chip;
    Reject hides it. Cancellable (abort on note switch/unmount); keyless →
    amber hint in the tray.
  - Footer action bar: amber warning "Needs area, project & a real type to
    leave the inbox" when the draft won't route (⚠ the WARNING requires area
    AND project AND real type — stricter than `isUnfiled`, which needs only
    one of area/project; the code comment claims they mirror; they don't —
    replicate as-is or reconcile deliberately, §6); "↺ Reset to suggestions";
    **Discard** (confirm `Move "X" to Trash?`, soft-trash); **Defer** (→ Later,
    no write); primary **Commit & route** (`commitRouting` merges
    tags/relations, overrides name/area/project/type, upsert → drops out of
    the inbox).

### 2.24.3 Triage view (batch, `TriageView`, :2864)
Same inbox pool. Action bar: "✨ Batch triage — P to triage · A accepted · R to
rework"; **Suggest for all** (disabled keyless/none-pending) runs the AI
suggest **sequentially** over pending items with a live "Cancel (done/total)"
progress; each finished item's proposals fold into a draft (headline name,
suggested type, ALL tags+relations) and the card auto-moves to **Accept**;
per-item errors send the card to **Rework** with the message. **Commit
accepted (N)** applies every Accept-box draft via commitRouting in one batched
upsert; Rework stays. Amber banner when some accepted drafts still won't leave
the inbox ("K accepted objects still need an area, project & real type — edit
them or they'll stay in the inbox after commit."). Three equal columns **To
triage / Accept / Rework** (Accept header primary, Rework amber), each with
count + empty-state copy. **TriageCard**: title (click opens), body preview;
pending = read-only MetaPills (type/area/project, amber when missing) or "No
suggestions yet — run "Suggest for all"."; Accept/Rework cards are editable
(debounced name/area/project inputs, type select, tag + relation-count pills);
per-card warnings; sort actions ✓ Accept / ↺ Rework / ← Back (back-to-pending
items are re-run by the next Suggest-for-all).

### 2.24.4 Import & Merge neighbors (non-AI)
- **Import** = `BulkTriageQueue` (`bulk/BulkTriageQueue.tsx`): three-box "tab
  hoarder" flow — pending+Later list with a drop/paste target for
  tabs/URLs/files; middle = the selected item's editable metadata + lazy link
  unfurl; **Commit** / **Decide later** / **Skip**. No model calls —
  deterministic ingest (`lib/bulkTriage.ts` → ingestFromBlob / link notes).
- **Merge** = `MergeWorkspace.tsx`: per-project merge-sets — search-add notes,
  reorder, combined-markdown preview, "Export .docx" and **"Copy for Claude"**
  (clipboard). Backed by `lib/mergeSets.ts` (parked deliberately — do not
  delete, D30).

### 2.24.5 ⚠ Dead-but-shipping in the Processor
`AutoView` (:1950 — the old "Consolidate": streaming AI overview +
consolidate-to-one-doc over filtered notes) and the legacy `MergeView` are
defined but unreachable — the tab set is inbox/triage/import/merge and unknown
persisted views fall back to Inbox. **NoteSplitPanel is thereby unreachable
too** (§2.14.14).

## 2.25 Settings window — `shared/SettingsModal.tsx` (5,563 ln)

### 2.25.1 Shell
Full-screen scrim `bg-background/70 backdrop-blur-sm animate-fade-in`,
click-outside closes. Modal: **940px × 82vh** (max-w 95vw), rounded-xl, border,
shadow-elev-3 + inset hairline ring, pop-in. Two columns:
- **Left sidebar w-64**, `border-r bg-panel/60`: a bordered **search field**
  ("Search by what it does…", icon turns primary on focus) above a scrollable
  **tree**. Tree rows: chevron (expandable only), 16px icon @80%, 12px label;
  active = `border-l-2 border-l-primary bg-secondary/40 text-primary
  font-medium`; depth indents 12px. Parents are expandable AND selectable.
  `workspaces`, `departments`, `plugins` start expanded. **"New" dot**: nodes
  carry `newSince` version tags; a glowing 6px primary dot shows until visited
  (seen-set `app.settings.seenNew.v1`). **Recent section**: items clicked ≥3
  times pin under a "Recent" header (top 5, `app.settings.recent.v1`).
  Last-visited section persists (`app.settings.lastSection.v1`, default
  "preferences").
- **Content**: header row (px-6 py-3, border-b) — active node label +
  description, a **Reset** button (clears the panel's overrides after confirm;
  dispatches `settings-reset`), X close. Body px-8 py-6, `max-w-2xl` centered.
- **Settings search / finder**: two layers — (a) sidebar tree filtering with
  auto-expand of matching parents; (b) a flat cross-section index
  (`settingsSearch.ts` — one entry per individual control: label, hint,
  keywords, owning sectionId) searched by intent; scoring label-prefix(0) >
  label(1) > hint(2) > keyword(3) > section(4). Focusing the search (even
  empty) turns the content area into a **faceted finder**: category chips
  (rounded-full, count badges) + result cards (label, hint, up to 6 keyword
  chips, chevron) grouped by owning section; clicking jumps to that panel.
  Empty: "Nothing matches — try a word for what the setting does — 'dark',
  'font', 'api key', 'shortcut'."
- **Row primitives**: `SettingRow` = label (13px medium) + description (12px
  muted/65) left, control right, `border-b border-border/30 py-3.5`. `Toggle` =
  36×20 pill (bg-primary on, 16px thumb). `SegmentedControl` = radiogroup in a
  bordered `bg-panel p-1` pill; active `bg-primary/15 text-primary`.
  `ComingSoon` = centered gear + label + "Coming soon".

### 2.25.2 Section tree & every panel (SETTING_TREE:309–609)
**App**: Preferences · Appearance · Layout (new-dot) · Search · Keyboard
shortcuts · AI. **Organisation**: Workspaces (children populated live; each
`workspace:<id>` gets a detail panel) · Object types · Properties · Saved
layouts · Tab groups · Superspaces · Library & folders · Departments (children:
Editor, Files & Links, Daily notes, Capture, Tasks, Library, Inbox, Contacts).
**Extensions**: Plugins (Core/Community) · Command palette. **Data**: Vault &
Storage · File recovery · Backlinks. **Account**: Calendars · Connections ·
Keychain · Collaboration. Placeholder panels rendering ComingSoon: dept-editor,
dept-capture, dept-library, dept-inbox, dept-contacts, core-plugins,
community-plugins, cmd-palette, file-recovery, backlinks, collaboration.

- **Preferences**: Auto-save toggle (⚠ local state only); Confirm before
  deleting (⚠ not persisted); Startup focus (Fixed workspace / Continue where I
  left off, + workspace picker); Open Welcome screen on startup (`landOnHome`);
  Language (English/Swedish — ⚠ inert); ⚠ Account card — hardcoded "Viktor
  Dahl (vikter456@gmail.com)" with inert Manage / Log out (fake).
- **Appearance**: card "Theme & type" — Mode (dark/light/system trio); Colour
  theme (Google Workspace / VS Code / Teal / Modus Green / Colorful / Custom);
  Shape (Google / Minimal / Soft); Font (System / Inter / Google Sans / Serif /
  Monospace); Font scale (Small 90% / Normal / Large 110% / X-Large 120%);
  Icons (Normal/Minimal/Off density). Card "Editor" — Reading mode toggle.
  Card "Custom theme" — paste Obsidian CSS (§3.7). ⚠ The IconTheme
  (calm/dimensional) API is not exposed anywhere — dead plumbing.
- **Layout** (:4206–4519): Reset; Department alignment (Left/Center/Right,
  default center); ⚠ Top bar row order (three reorderable cards — dead, §1.2);
  Show workspace pill (default on); Default left sidebar view; Default right
  sidebar view; Collapse left/right sidebar on launch (off); Notes subfolder
  inside bound workspaces (Visible `notes/` / Hidden `.liv/notes/`, default
  hidden); Prompt for folder when creating a workspace (default OFF); Metadata
  panel (Favorites/grouped default · All/flat · Hybrid · Focused); Show all
  built-in properties on every note (⚠ code default true vs doc-comment false);
  Suggest metadata Alt+M (Only missing default / Re-evaluate / Ask per run);
  Active-workspace "where new files land" (Library by type default / All in
  workspace — per-workspace `fileHome`).
- **Search** (⚠ mostly display stubs): Default mode (search/commands), Show
  metadata filter panel, Max results (15/30/50/100) — all local-only; static
  shortcut card (Ctrl+O, Ctrl+P); static "Inline filter syntax" legend
  (`tier:1`, `#tagname`, `type:atomic`, `area:dev`, `project:myproject`,
  `active:true`).
- **Keyboard shortcuts**: rendered live from the registry, grouped by category
  (Navigation, App, Layout, File, Tabs, Daily notes, Metadata, Object, Lists,
  Files, Format, Edit); rows = label (+ scope hint "(in editor)"/"(in
  notes)") + kbd chip or italic "unassigned". Read-only here; property-chord
  rebinding lives in Properties.
- **AI** (§2.23.1): API key card (password + Show/Hide, "Stored on this device
  only", green/grey dot "Key set" / "No key — AI features are inactive"); Model
  free-text (mono, placeholder `claude-sonnet-4-5`); ⚠ fake: Enable-AI toggle,
  AI Level 1–4 cards, auto-suggest triggers, fields-to-suggest chips; Prompts
  manager (real).
- **Workspaces**: global note-type vocabulary editor (add/remove chips, "Add a
  note type") + one collapsible card per workspace (active auto-expands):
  rename, project tag, default area, "AI suggested note types" chips,
  auto-delete-empty-notes threshold, apply-defaults-to-existing, archive/
  restore. Per-workspace drill-in: Name, Project tag, Default area, Apply
  workspace defaults (+ apply-to-existing), Layout mode (departments/unified),
  Built-in badge, open-tab count.
- **Object types** (§2.10.1 TypeSchemas): one card per schema — rename
  properties inline, type select from PROPERTY_TYPES, reorder ▲▼, remove, "New
  property…" + type + Add, per-card Reset to default.
- **Properties** (§2.10.7): search; a 4-column grid (Property 1.4fr / Type
  0.6fr / Shortcut 1fr / Pinned 0.4fr) grouped Core / Task / Custom. Rows:
  PropertyIcon in a 28×28 bordered holder, label + sublabel, type badge,
  **rebindable chord** — "Add shortcut" → capture button "Press a chord… (Esc
  cancels, ⌫ resets/clears)"; conflicts against ALL commands + other
  properties rejected inline ("Already used by X — try another"); ★ Pin
  toggle. Footnote: custom properties are auto-discovered from notes.
- **Saved layouts**: "Save current layout" card (name + Save; captures every
  workspace, its tabs, splits, active) ; rows (Layers icon, name, "N workspaces
  · saved date", Restore with confirm "Current tabs/splits will be replaced",
  Delete with confirm). Empty: "No saved layouts yet…"
- **Tab groups**: management list of TabGroupSnapshots — rows: Layers icon,
  click-to-rename inline, "N tabs · saved date", Rename, Delete (confirm).
  Empty state points at the tab-bar affordance and notes restore lives in the
  Layers menu.
- **Superspaces**: named whole-tab-layout snapshots; Load UI (§2.3.4).
- **Library & folders**: Reset; Auto-sort Library by file type toggle; callout
  "**Folder names no longer affect metadata**. Moving a file between folders
  doesn't change project/tags…"; per-type folder-name override table (zebra:
  category label, override input, "→ Library/<Effective>/" preview).
- **Departments**: ⚠ toggles for Notes, Capture, Tasks, Library (default on)
  and Calendar, Messages, Finances (default off) — pure local state, wired to
  nothing.
- **Daily notes** (§2.20–2.21): folder, title format, daily template select,
  open-on-startup, the Templates manager, "Open today's note".
- **Files & Links**: ⚠ Default file format (md/txt), Auto-link detection,
  Wiki-style links — local-only display stubs.
- **Tasks** (:3128–3360): the ClickUp-style per-workspace status editor —
  workspace picker, statuses grouped by lifecycle group with editable label,
  group select, color, add/remove (slugified ids).
- **Vault & Storage**: Storage location (⚠ chip claims "localStorage" — stale;
  the vault lives on disk); Storage used (KB estimate); "Set up workspaces from
  vault structure" (Scan vault… → `vaultScaffold`); ⚠ Export all data / Clear
  all data (inert).
- **Calendars** (§2.19.11). **Connections**: "Cloud integrations" — honest
  scaffold cards for Google Drive, two-way Calendar sync (OAuth credentials +
  connect/disconnect), semantic search (embeddings) — labeled not-configured;
  browsing Drive closes Settings underneath the DriveBrowser overlay.
  **Keychain**: Claude API key / OpenAI API key / Cloud sync token rows
  (OS-keychain seam).

## 2.26 Shell overlays

| Overlay | Trigger | Behavior |
|---|---|---|
| **Mission Control** (`MissionControlOverlay.tsx`) | Mod+Shift+M toggle; **Shift+Tab** when focus is non-interactive (the editor dispatches `liv:toggle-dashboard`; ordinary inputs/buttons keep native reverse-tab — `__root.tsx:1398–1447`); Esc closes first | z-99 full-screen `bg-background/60 backdrop-blur-xl` floating over the LIVE blurred app (survey + launch, never work). Top-right round close chip ("Esc"). Body: centered max-w-6xl "Mission Control" label + `DashboardViewsCarousel` — a widget board with saved views seeded "Today / Guidance / Review", layout persisted `missionControl.widgets.v1`. Default widget set: welcome, quick-actions, agenda, suggestions, resume, stats("By kind"), weather("Today"), vault-graph (`widgets/registry.tsx:361–370`; full catalog adds nudges/what-next/related/launcher/overview-stats/tasks-summary/project-ai-summary/next-actions/recent-activity/habits/review-scorecard/data-view/time-tracking). Card clicks dispatch the live app's events (note-open / extension-switch / command:run / mission-control:navigate) then close. |
| **Resume Launcher** (`widgets/LauncherOverlay.tsx`) | Ctrl+Shift+Tab; `liv:toggle-launcher` | z-60 centered 560px panel over a blurred scrim, header "Resume · next moves" + close. Body: the 6 most recently edited objects + up to 6 deduped deterministic+AI suggestions (`LauncherList`); selecting jumps (same dispatch table) and closes. |
| **QuickSwitcher** | §2.8 | z-50/60 band. |
| **WorkspaceSwitcher** | Mod+Shift+O | §2.7.3, z-150. |
| **QuickAddTask** | Mod+Shift+K | §2.15.13, z-150. |
| **Settings modal** | Mod+, / gear / `open-settings` | §2.25, lazy-loaded. |
| **ArchiveView / DriveBrowser** | `view:open-archive` / `drive:open` | z-120; Archive lists+restores every archived object (§2.18.6). |
| **NotePreviewModal / NoteOverlay / MeetingNoteOverlay** | `note-preview` / `note-open-overlay` / `open-meeting-composer` | read-only peek modal; editable floating overlay (§2.20.3, hydrates bodies first); meeting composer seeded from a calendar event (§2.21.4). |
| **LinkSaveOverlay** | URL paste / Mod+Shift+U | §2.18.5, z-140. |
| **DialogHost** | `showPrompt/showConfirm/showAlert` | below. |
| **SuggestionToastManager / AssistEntryIndicator** | self-starting | §2.23.6–2.23.7. |

**DialogHost** (`shared/DialogHost.tsx`): ONE themed replacement for native
prompt/confirm/alert. Promise API `showPrompt / showConfirm({danger}) /
showAlert`; mounted once at z-200; falls back to native dialogs if unmounted.
Visual: scrim `bg-background/70` + blur, card max-w-sm at 18vh from top,
rounded-xl bg-popover shadow-elev-3; title 14px semibold, message 12px; prompt
input focuses+selects; footer bar `bg-secondary/20 border-t` right-aligned —
Cancel (ghost) + confirm (primary; danger = bg-destructive white, default
label "Delete"). Enter accepts, Escape cancels, scrim-mousedown cancels. Every
prompt/confirm in this spec routes through it.

**Onboarding / first-run:**
1. **FirstRunWizard** (`FirstRunWizard.tsx`) — full-screen blocker (z-195) when
   no vault path is set: 520px card, LivLogo 56px, "Welcome to Liv / Pick a
   folder for your vault…", vault-location field + **Browse** (native
   directory picker), default-path hint, info card ("Liv stores its settings
   and library inside this folder, under `.composer` and `Library`"), a "Use
   existing data" card if legacy `<appData>/vault` is detected, error banner,
   primary "✓ Use this folder →" (busy "Setting up…").
2. **Welcome sample data** (`src/lib/seedWelcome.ts`): first run only (flag
   `liv.welcomeSeeded.v1`) seeds a fully-linked demo workspace — area "Getting
   Started", project "Welcome", tag `welcome`, 4 trailing days of demo daily
   notes (so habit streak + week activity light up), tasks + relations — using
   only real store APIs. Every object stamped `metadata.custom.seed="welcome"`
   and id-tracked, so `welcome:clear-samples` removes exactly what was seeded;
   `welcome:seed-samples` force-reseeds (both palette commands).
3. Settings "new since" dots continue feature discovery.

## 2.27 Context menus & drag-drop vocabulary

### 2.27.1 Context menus
Global: the WebView's native right-click menu is suppressed everywhere except
editable fields (§1.4); app menus call stopPropagation. All app context menus
share the pattern: full-screen invisible backdrop + fixed popover at the
cursor (`w-56/60, rounded-md, border, bg-popover, py-1, text-xs, shadow-elev-3
ring-inset-hairline animate-pop-in`), rows px-3 py-1.5 with 14px leading
icons, destructive rows in destructive color, separators `border-t
border-border/40`.
- **Composer note-tab right-click** (Composer.tsx:4354–4622), items in order:
  Open in default app · Show in system explorer · Copy vault path · Copy full
  path (file block hidden for non-note surface tabs) · ─ · "TAB GROUP" header,
  existing groups (color dot + name + check), New group… (prompt), Remove from
  group (if grouped) · ─ · Open in split view (disabled for
  active/already-split) · Open in new window · Rename · Hide tab (parks it) ·
  ─ · Close others (keeps parked) · Close (destructive, disabled on the last
  visible tab).
- **Composer group-chip right-click** (:4626+): header (color dot, label,
  count) then Collapse/Expand; manual groups add Rename / Recolor / Ungroup;
  metadata-derived clusters get collapse + close-all only.
- **GlobalTabBar** menus: §2.3.3. **AppSidebar** rows: §2.2.3.
  **LibraryExtension** rows: §2.17.1. Band chip tooltip: "Click to open ·
  double-click to rename · right-click for options".

### 2.27.2 Drag & drop
- **In-app MIME vocabulary** (all set by `setLivDragData`,
  `src/lib/dragSource.ts`): `application/liv-object-id` +
  `application/liv-object-kind` (any object row), `application/liv-file-path`
  (vault path), `application/liv-file-open` (folder-view files → editor),
  `application/liv-task-id` (task chips/cards), `application/liv-tree-node-id`
  + `application/liv-workspace-id` (sidebar tree), plus `text/plain`
  (title[+path]), `text/uri-list` (file:// for desktop targets), and Chromium
  `DownloadURL`. Drag-out to web apps (Gmail) is acknowledged-impossible;
  fallback is "Reveal in OS".
- **3-zone row drops** (sidebar tree & co.): cursor Y < 28% of row height =
  before, > 72% = after (2px primary insertion line at the row edge), else =
  into (inset 1px primary/50 ring); the dragged row dims to 40%; cursor
  grab/grabbing.
- Drop targets across regions: tab strips (reorder), kanban columns (property
  set), lists (membership + template), calendar days (reschedule), Schedule
  unscheduled rail (clear date), import drop zones, folder trees, bases
  (metadata stamp / URL→link note), editor (file-open), bulk triage.
- OS-level file drop is disabled at the Tauri layer; HTML5 events handle
  everything. (Native port: NSItemProvider/drag sessions replace the MIME
  vocabulary one-for-one.)

## 2.28 Keyboard system

### 2.28.1 Semantics (`src/lib/keybinding.ts`)
Hotkey shape mirrors Obsidian: `{modifiers: ("Mod"|"Ctrl"|"Shift"|"Alt"|
"Meta")[], key}`. "Mod" = Cmd on macOS, Ctrl elsewhere. Matching: all declared
modifiers pressed AND no extras; digit-row keys match `e.code === "Digit<n>"`
(layout-safe); single letters case-insensitive on `e.key`; named keys
(`ArrowUp`, `F2`, `` ` ``) exact. Labels: mac → glyph run, no separator (⌘⇧B);
others → "Ctrl+Shift+B".

### 2.28.2 Dispatch (`src/lib/commands.tsx`)
A single registry `Map<id, CommandDef>`; every command has `id, label, scope
("global"|"composer"|"editor"), category, defaultBinding?, meta` (palette
facets stamped data-driven). ONE window keydown listener walks the registry in
insertion order — **earlier defines win conflicts** (how the Composer's Ctrl+T
shadows the global `tab:new` fallback). Editor-scope commands dispatch from
inside the editor's own keymap, never the window listener. Unmodified hotkeys
are suppressed while focus is in input/textarea/editor. User overrides persist
at vault key `app.keymap.overrides.v1`; deleting an override revives the
default (registry rows can't be truly unbound). A programmatic bridge listens
for `CustomEvent("command:run", {detail:{id}})`.
**Keyboard scopes** (`src/lib/keyboardScope.ts`): a push/pop stack; a "capture"
scope (palette facet mode, Decide tray) suppresses the global dispatcher for
everything not on its allow-list, so bare I/X/O/1–9 don't double-fire.

### 2.28.3 Full default map (registry defaults; user-rebindable)

| Binding (Win form) | Command id | Label / effect | Scope |
|---|---|---|---|
| Ctrl+O | switcher:open | Quick switcher (search; toggles) | global |
| Ctrl+P | command-palette:open | Palette (commands) | global |
| — | switcher:commands | Palette straight into Commands (click alias) | global |
| Ctrl+Shift+F | global-search:open | Global search | global |
| Ctrl+Shift+` | app:toggle-left-sidebar | Left sidebar | global |
| Ctrl+Shift+' | app:toggle-right-sidebar | Right sidebar | global |
| Ctrl+. | app:toggle-focus | Focus/Zen mode | global |
| Ctrl+, | app:open-settings | Settings | global |
| Ctrl+N | file-explorer:new-file | New note (switch to Notes, mint + focus) | global |
| Ctrl+Alt+D | daily:open-today | Today's daily note | global |
| — | ai:create-meeting-note | Meeting note from next event | global |
| Ctrl+Shift+O | workspace:switch | Workspace switcher | global |
| Ctrl+Shift+K | task:new | Quick-add task | global |
| Ctrl+J | copilot:open | Right panel → Copilot | global |
| Alt+Shift+P / Alt+Shift+T | metadata:add-property / add-tag | Right panel → metadata, focus the field | global |
| Ctrl+Shift+U | links:save-from-clipboard | Link-save overlay | global |
| Ctrl+T | workspace:new-tab | New tab | composer |
| Ctrl+W | workspace:close | Close active tab | composer |
| Ctrl+Shift+T | workspace:undo-close-pane | Reopen closed tab | composer |
| Ctrl+1…8 / Ctrl+9 | workspace:goto-tab-N / goto-last-tab | Jump to tab N / last | composer |
| Ctrl+Alt+↓ | workspace:split-horizontal | Split active tab right | composer |
| Ctrl+Alt+S | workspace:capture-layout | Save workspace snapshot | global |
| Alt+P/T/A/R/G | composer:focus-project/-type/-area/-tier/-tags | Focus metadata field | composer |
| Alt+E | composer:focus-editor | Focus editor | composer |
| Alt+1/2/3 | metadata:set-tier-N | Tier on focused object | global |
| Alt+M / Alt+Shift+M | metadata:suggest / reevaluate | Decide tray | global |
| Alt+Shift+1…6 / Alt+Shift+7 | editor:set-heading-N / set-heading | Heading N / clear | editor |
| Ctrl+B / Ctrl+I | editor:toggle-bold / -italic | Bold / Italic | editor |
| Ctrl+Shift+X | editor:toggle-strike | Strikethrough | editor |
| Ctrl+` | editor:toggle-code | Inline code | editor |
| Ctrl+K | editor:insert-link | Insert link | editor |
| Ctrl+Shift+8 / Ctrl+Shift+7 | editor:toggle-bullet / -numbered | Bullet / numbered list | editor |
| Ctrl+Shift+L | editor:toggle-task | Task list | editor |
| Ctrl+Alt+Shift+↑/↓ | editor:swap-line-up/-down | Swap line | editor |
| Ctrl+F | editor:open-search | Find in note | editor |
| Ctrl+Shift+E | editor:extract-selection | Extract selection → new note | composer |
| Ctrl+Shift+B | object:toggle-bookmark | Bookmark focused object | global |
| Ctrl+Shift+A | object:toggle-archive | Archive/unarchive focused object (clears focus if it vanished) | global |
| — | object:trash, lists:new, lists:add-to, view:open-archive, drive:open, workspace:toggle-archive, vault:scaffold-workspaces, welcome:seed/clear-samples | palette-only | global |
| Ctrl+T | files:new-tab | Files: new tab (Files route active) | global |
| Ctrl+T / Ctrl+W | tab:new / tab:close | Global fallbacks, defined LAST so surface-specific win; fallback Ctrl+T goes to Notes + new-tab chooser; Ctrl+W closes the visible tabbed surface's tab (no-op on tab-less tools; `liv:close-tab-request`) | global |
| Alt+← / Alt+→ | nav:back / nav:forward | Global back/forward (§2.6) | global |
| Ctrl+[ / Ctrl+] | composer:nav-back / -forward | Composer note history | global |
| Ctrl+Shift+M | app:toggle-mission-control | Mission Control | global |
| (dynamic) | prompt:run:\<id\> | Run saved AI prompt | global |
| F1–F12 | — | saved-filter toggles (Files View surface) | surface |
| Ctrl+M | — | Move selected files (Files surface) | surface |

**Special non-registry keys** (`__root.tsx:1386–1447`): **Shift+Tab** outside
editor/inputs toggles Mission Control (the editor keeps Shift+Tab = outdent in
lists, else dispatches `liv:toggle-dashboard` itself); **Ctrl+Shift+Tab**
opens the Resume launcher.

### 2.28.4 Property chords & the value grammar (D21)
- **Level 1 — property-focus chords** (rebindable): the registry defaults
  above (Alt+P/T/A/R/G, Alt+1/2/3, Alt+M…) plus a per-property overlay
  `app.metadata.propertyBindings.v1` (`metadataKeymap.ts:146–213`) set from
  Settings → Properties: any property (people, status, due date, custom keys…)
  can get a chord; the editor listens globally and focuses
  `[data-metadata-field="<key>"]`. Capture rules: must include Ctrl/Meta
  ("Mod") or Alt (bare keys reserved; F-keys may bind unmodified); collision
  detection folds Ctrl/Meta→Mod.
- **Level 2 — value grammar** (fixed, NOT rebindable; shared verbatim by the
  search facet mode, the metadata editor, and the Decide tray —
  `metadataKeymap.ts:28–125`): while a property/facet is in value mode — `I`
  include · `X` exclude · `O` off/clear · `1..9` cycle the Nth listed value
  off→include→exclude→off (positional; the same digit walks the states) ·
  `Enter` include highlighted · `Esc` leave. While TYPING in a value input only
  Enter/Esc are claimed (so "2024"/"x-ray" stay typable). Legend printed by
  every surface: `1–9 cycle · I include · X exclude · O off · esc done`.

### 2.28.5 Shared list navigation (`src/lib/useListKeyboardNav.ts`)
One hook for every selectable list (Tasks list, Explorer, Files, Contacts,
search): ↑/↓ move selection (clamped), Home/End jump, Enter fires the open
action, selection scrolls into view via `data-nav-id` +
`scrollIntoView({block:"nearest"})`; default browser scroll suppressed;
completely inert while any input/textarea/contenteditable has focus; optional
DOM-order mode for grouped lists (the Tasks list passes visible-row ids
explicitly).

## 2.29 Empty states inventory (shell layer; per-surface states live in their sections)

- Blank global tab landing: circular icon, "New tab", Create new note / Go to
  file / Choose tab type.
- Split-pane non-renderable: "Switch the main pane to *X* to use this view." +
  Open in main pane.
- ExtensionStub: big faded icon, label, "Coming soon."
- Sidebar tree filter: rows simply vanish. Vault view: "Vault is empty." /
  per-folder italic "empty". Properties: "No properties yet." / "No properties
  match." / drilldown "No objects."
- QuickSwitcher search: "No matches … Try a different word, or switch the Name
  / Content scope." + Create-note CTA; commands: "No commands found…".
- SavedGroupsMenu: "No saved groups yet. Right-click a tab — or open its menu —
  to stash the current tabs as a group."
- VaultSwitcher: "No other vaults yet." WorkspaceSwitcher: `No workspace
  matches "q".`
- 404 route: "404 / Page not found / Go home" (`__root.tsx:197–217`).

---

# 3 · VISUAL SYSTEM

**The one intended divergence:** every place Liv uses an accent (`--primary`,
`--ring`, chip tints, the gliding indicator, active-tab bars, nav-active fills)
becomes **lotus lake green `#2f7d6b`**; otherwise the port uses **system
materials, SF Pro, SF Symbols** (per `interface.md` §0.3 — sidebar vibrancy,
system light/dark, standard controls). Liv's Google-Workspace skin (D28, the
shipped default) is the structural reference: keep its *relationships* (which
element gets which token, tint percentages, tonal elevation), swap the hue.
There is no theme system in lotus — Liv's named themes, shape flavors, font
options, and custom-CSS import (§3.7) are documented for completeness and
dropped in the port (§6).

## 3.1 Token vocabulary (single source: `src/styles.css`)
Semantic variables consumed app-wide (never per-component palettes):
`--background --foreground --surface-1 --surface-2 --card(-foreground)
--popover(-foreground) --primary(-foreground) --secondary(-foreground)
--muted(-foreground) --accent(-foreground) --destructive(-foreground)
--warning(-foreground) --border --input --ring --panel(-foreground)
--chip(-foreground)`. `--panel` = sidebar/activity-bar/title-bar chrome;
`--ring` is focus-only; chip = tag/badge pair. Reference values (Google skin):
light — bg/card/popover/surface-1/input `#ffffff`, fg `#202124`,
surface-2/muted/accent/panel `#f1f3f4`, primary/ring/chip-fg `#1a73e8` (→ lake
green), secondary `#e8eaed`, muted-fg `#5f6368`, destructive `#d93025`,
warning `#e37400`, border `#dadce0`, chip `#e8f0fe`; dark — bg `#1f1f1f`, fg
`#e8eaed`, surface-1/card/muted/input `#2d2e30`, surface-2/panel `#1b1b1b`,
popover `#292a2d`, primary/ring `#8ab4f8` (primary-fg `#202124`),
secondary/border `#3c4043`, muted-fg `#9aa0a6`, accent `#35363a`, destructive
`#f28b82`, warning `#fdd663`, chip `#1f3a5f`/`#8ab4f8`. Elevation is tonal
(chrome darkest < page < cards); `--elev-highlight` = white 42% light / 9%
dark lit-top-edge.

## 3.2 Type & spacing scale
- `.text-panel-title` 14px/600/−0.006em; `.text-section-label` 11px/700/+0.07em
  UPPERCASE muted; `.text-body` 14px lh 1.5 (the calm reading size);
  `.text-meta` 12px lh 1.4; `.text-secondary` = muted-fg; `.text-faint` =
  muted-fg mixed 60% toward background. Headings h1–h4: weight 600, tracking
  −0.011em.
- Density law (matches lotus's own 11pt floor): **nothing below 11px; 36px
  control height**. Editor body 17px/1.65; reading measure
  `--reading-measure: 40rem` (~68ch at 15px body).
- Row-height tokens seen throughout: chrome rows h-9/h-8; strip lanes h-10;
  tool headers h-11 (44px); list rows ~28px; chips h-6/h-7; kbd chips
  10.5–11.5px mono.
- Icon scale: `.icon-xs` 14px, `.icon-sm` 16px, `.icon-md` 18px (chrome uses
  icon-md). Chrome stroke width 1.75 everywhere.

## 3.3 Radii (shape system)
The whole radius scale derives from one `--radius` knob: radius-sm = r−4, md =
r−2, lg = r, xl = r+4, pill = 9999. Shipped default ("google" shape):
`--radius: 8px`, `--radius-control: pill` — pure action controls (primary
buttons, search bar, chips, toggles, badges) go pill. (Alternatives "minimal"
6px and "soft" 10px follow radius-md for controls — dropped in the port.)
Count badges (`.badge-soft`) are always pill.

## 3.4 Motion & elevation
- Easings: `--ease-spring: cubic-bezier(0.32,0.72,0,1)` (signature — settles,
  never overshoots; ⚠ NOT the docs' widget spring (.16,1,.3,1));
  `--ease-out: cubic-bezier(0.22,1,0.36,1)`. Durations `--dur-1` 140ms
  (hover/micro), `--dur-2` 200ms (slides/reveals), `--dur-3` 320ms (gliding
  indicators). All buttons/inputs get a uniform 140ms spring
  color/opacity/shadow/transform transition.
- Entry animations: `liv-fade-in` 180ms; `liv-pop-in` 220ms (scale .96 + 4px
  rise — modals); `liv-slide-up` 200ms; `.view-enter` (extension/route change:
  fade + 4px rise, backwards fill, will-change opacity only — a transform fill
  would clip fixed dropdowns); `.tab-body-enter` opacity-only 140ms;
  `liv-indicator-in` scaleX .4→1 for the active-tab indicator; View Transitions
  pane cross-fade at dur-2/ease-out. Full `prefers-reduced-motion` guard sets
  all durations to 0.001ms.
- **Elevation**: shadow-elev-0 none; **elev-1** (hover-lift/active nav) = inset
  1px `--elev-highlight` top edge + two tight low-alpha fg shadows; **elev-2**
  (menus/popovers/search dropdown); **elev-3** (modals/palette — the only
  strong shadow). `.ring-inset-hairline` = inset 1px fg-6%. Tonal-first:
  resting surfaces separate by tone, shadows reserved for floaters.
- **States**: `.nav-active` = primary 13% fill + primary text + inset 2px
  leading accent bar; `.row-hover` = secondary-70% fill at 120ms spring;
  `.badge-soft` = pill, min-w 20px, h 16.8px, 10.4px/600, primary-14% bg +
  primary text; `.pill` = uppercase 11.2px/600 chip in chip colors; `.kbd` =
  mono 11.5px, secondary bg, 1px border with 2px bottom (keycap), radius
  5.6px.
- **Focus**: `:focus-visible` = 2px ring of `--ring` at 30% (no outline,
  follows the element's own radius); text fields/contenteditable get NO focus
  ring (caret + container border suffice). **Selection**: primary at 30% mix.
  **Scrollbars**: 10px, transparent track, thumb muted-fg 22% (38% hover),
  pill, 2px transparent padding; `.no-scrollbar` opt-out for tab lanes (tabs
  squeeze, never scroll).

## 3.5 Iconography
Liv: lucide line icons, stroke 1.75, monochrome `currentColor` for all chrome —
color reserved for genuine identity (file types, kind icons) and workspace
glyph tints. Port: SF Symbols equivalents at the same optical sizes/weights.
- **Activity/extension** (`NavIcons.tsx` ACTIVITY_ICONS): notes=FileText,
  ai-chat=Bot, tasks=CheckSquare, library=Library, inbox=Inbox, contacts=Users,
  calendar=Calendar, messages=MessageSquare, finances=TrendingUp,
  explorer=Compass, capture=Zap. Dept-nav (NAV_ICONS): PencilLine, Folder, Zap,
  LayoutDashboard, MessageSquare, Network, Download, Upload, Home, List.
  Structural icons are never hidden by the density dial — "minimal"/"off" only
  dim them (opacity .70 + stroke 1.25).
- **File-type icons** (`FileTypeIcon.tsx`): glyph by format (FileText for
  pdf/doc/md/txt…, FileSpreadsheet, FileImage, FileAudio, FileVideo, Link2
  url/html, LayoutDashboard canvas, FileCode, File fallback) tinted with a
  **desaturated** per-type hue — reference hues muted 45% toward their own grey
  luminance: pdf `#e0533d`, sheets `#1f9d57`, word `#2b6cd4`, images
  `#7c5cd0`, md/txt `#4a8bd4`, canvas `#d08a2e`, link/html `#2f9bb5`, audio
  `#c4476f`, video `#9b59b6`, generic `#7a8290`. **KindIcon** for object
  kinds: task=CheckSquare `#1f9d57`, contact=User `#d4538e`, event=Calendar
  `#e0533d`, list=List `#2b6cd4`, message=MessageSquare `#7c5cd0`; notes/files
  defer to format. Density: off → nothing (pure-text rows); minimal → hue
  dropped, muted neutral.
- **Folder** (`FolderGlyph.tsx`): flat Folder/FolderOpen, monochrome unless an
  explicit color is passed; never hidden, dims like nav icons.
- **Property icons** (`PropertyIcon.tsx`) — "icon follows the function".
  Resolution: per-key user override (12-glyph palette:
  text/hash/calendar/checkbox/number/list/tag/people/link/flag/star/folder,
  persisted, live on `property-icons-change`) → semantic key (people=Users,
  tags=Tag, subjects=Tags, folder, workspace=LayoutGrid, sourceref/
  related=Link2, recurrence=Repeat, priority=Flag, status=CircleDot,
  bookmarked=Bookmark) → inferred TYPE glyph (text=Type "T", number=Hash,
  date=Calendar, datetime=CalendarClock, checkbox=CheckSquare, list=List;
  ~50-key normalization table: lowercase, strip `file.`, spaces, underscores)
  → structural key → SlidersHorizontal default. Density: off hides entirely;
  minimal = muted 50% + stroke 1.25 + scale-90. Same icon must appear in
  inspector, search facets, filters, and settings. No colored tiles.
- ⚠ `IconTheme` calm/dimensional plumbing + `DimensionalGlyph` are orphaned
  (no UI, no consumers) — skip; keep the density dial.

## 3.6 Color subsystems (keep, re-hued where they touch the accent)
- **workspaceAccent** (AppSidebar.tsx:275): FNV-1a hash of workspace id → one
  of 10 hues — tints the workspace's monochrome glyph; emoji is an opt-in
  override rendered as-is (built-ins have none, D29).
- **GROUP_PALETTE** (`tabGroups.ts:15`): 8 muted tab-group hues — #5e86b0
  #4f9a94 #72a06a #bda15f #c78a63 #cc7d7d #bd82a6 #9287bf.
  `displayGroupColor()` folds legacy/unknown hexes into the palette at render
  (via `stableGroupColor` hash) — no data migration. `pickGroupColor` cycles by
  count; `stableGroupColor(value)` = deterministic hue for metadata-derived
  clusters. Group chips render `color-mix(color 90%, background)`; bands 14%.
- **chipColor** (`chipColor.ts`): deterministic hash (`h*31+char`, lowercased/
  trimmed) into a fixed 12-color palette — rose, amber, slate, sky, violet,
  fuchsia, zinc, orange, cyan, blue, lime, pink — each with {bg `*-500/15`,
  text `*-600` light / `*-300` dark, border `*-500/40`, dot `*-500`}. Graph,
  chips, kanban accents, and assignee avatars must agree on a value's hue
  (they share this function). Chips colorize only under the "colorful" theme;
  the default uses the flat primary tint.
- Status hexes (§2.15.1), calendar kind colors + feed hexes (§2.19.3,
  §2.19.11), wiki-chip kind hexes (§2.14.7) are data-level color tables — keep.
- Amber `--warning` is reserved app-wide for AI presence (Assist badge, rings,
  heads, approval cards) — a deliberate second hue distinct from the accent.

## 3.7 Liv theming machinery (documented; dropped in the port)
Named themes via `data-theme` (google DEFAULT / default "VS Code" / teal /
modus-green / colorful / custom), shape flavors via `data-shape`, font options
(System/Inter/Google Sans/Serif/Mono stored as verbatim CSS stacks at
`app.font`), font scale 90–120% (`app.fontScale`), OpenType features
`"cv11","ss01","ss03","calt","kern"`, a pre-paint dark-class script in
index.html (named-theme flash risk acknowledged), and **custom Obsidian-CSS
import** (`customTheme.ts`: parses every `--name: value`, maps ~25 Obsidian
variables → Liv tokens by priority table, passes `--liv-*` through, injects on
`<html>`, raw CSS persisted at `theme.customCSS`). The port keeps ONLY: system
light/dark, the lake-green accent, and the reading-mode toggle. ⚠ D26's brand
palette (violet #6F5BE6 / Hanken Grotesk / Fraunces) was documentation-only —
never shipped; lake green supersedes.

---

# 4 · CORE MAPPING NOTES

The UI above stays identical; the truth underneath changes. Vocabulary is
`feature-map.md`'s: **property/cell · type+expectations · lens · saved view ·
clerk proposer · answerer · agent · service · shell**. Where this section and
`feature-map.md` disagree, the feature map and the constitution win. AI gets
two doors, no third: reads through queries, writes through proposals.

## 4.1 Persistence translation table

| Liv persistence | What the UI does with it | lotus mechanism |
|---|---|---|
| Notes/tasks/events/contacts/lists/files (`app.*.v1` stores, `.composer/state.json`) | every surface | **entities + cells**; the ObjectMetadata spine (§2.10.1) = property definitions; `custom` bag = dynamic properties (schema-on-read preserved: a property exists because some entity carries a cell) |
| `.md` file mirror + frontmatter write-through + Rust file watcher + vault `.md`/`.base` scans | Vault sidebar view, Files pool merge, search over an attached Obsidian vault, "path" rows, reveal-in-Finder | **import/export service** — no mirror, no watcher (constitution: no second truth). See §4.3(1) |
| `Library/Filters/*.base`, per-base local views/overrides, DataViewBuilder output | saved Views, F1–F12 chips, `data-view` embeds | **saved views** (query + lens + config as entities); `.base` becomes an export/import FORMAT, not the storage |
| Workspace snapshots, `objectVersions`, composer note snapshots, superspaces, saved layouts | Snapshots tab, VersionControlPanel, Settings lists | **append-only log**: version history is free; "Save snapshot/version" = a named marker on a log position; Restore = a new command that re-applies the old state (undoable, never rewrites history) |
| Alt+M commits, Assist `apply()`, Jarvis write tools, Processor routing commits, extraction (task/contact/event), meeting→tasks, AI naming, note split, selection rewrites | every approval UI in §2.11–2.24 | **proposals** (clerk proposer / agent). Each Accept/Approve/Commit = confirm-proposal → one transaction; each Reject/Dismiss → the **declined sidecar** (replaces `assist.dismissed` and per-session dismiss sets — and upgrades them: nothing asks again) |
| Deterministic suggestion engines (metadataSuggest, relations suggest, board assist, nudges, declutter, tab grouping) | suggestion cards everywhere | **clerk proposers** reading via queries; deterministic ids map 1:1 onto proposal identity |
| Chat / Copilot / ambient context | §2.23.2, §2.23.9 | **answerer** (read-only; queries + cited entities + deep links — Liv's chat has no citations; the answerer door adds them for free) |
| Jarvis loop | §2.23.3 | **agent**: the goal drafts transactions; each amber PreviewCard = one proposal confirmation; the yield-gate invariant maps exactly onto "writes only through confirmed proposals" |
| SQLite FTS5, vault scans, unfurl cache, habit stats, backlinks, custom-property discovery, duplicate detection | search, link cards, HabitWidget, Connections, pickers | **services** (projections / extraction caches; computed once, every view agrees). Backlinks stay derived-never-stored — already lotus-shaped |
| Templates (`app.templates.v1`, defaults, folder templates) | §2.21 | **type + expectations** (a template = a type's expected fields + body scaffold); "templates edit as real notes" keeps working — the template is an entity |
| ICS feeds + Google sync | §2.19.11–12 | **import service** writing through commands; feed-owned fields refresh, user-owned cells preserved (cell-level merge is exactly what the code already does) |
| Lists' derived `Lists/*.md` + `Lists/*.base` mirrors | Obsidian interop | **export artifacts** produced on demand, not write-through |
| Vocabulary (`app.vocabulary.v1`), provenance (`app.fieldProvenance.v1`), type schemas (`app.typeSchemas.v1`), pinned fields, hidden properties | pickers, ✨ badges, Settings | small **entities/sidecars** (they are data about data, must sync with the vault) — provenance stays explanation-only, never in cells' values |
| Pure UI state: pane widths, tab-strip state, right-panel view, collapse states, display modes, card display, dock corners, seen-new dots, recent settings (§2.10.7 key list) | layout memory | **shell preferences** (the shell owns no truth; losing these must never lose data) |
| localStorage `superspaces`, keymap overrides, slots, workspaces/views | layouts, shortcuts, bookmarks strip | shell preferences OR entities per feature-map; keymap overrides stay a flat map keyed by command id |

## 4.2 Behavioral consequences to preserve
- Liv's event-bus refresh grammar (`notes-changed`, `workspace-change`,
  `tasks-changed`, `assist-suggestions-changed`, …) becomes core
  change-notification: every listener re-reads through queries. The debounce
  cadences documented per surface (50ms badges, 140ms palette, 250ms FTS,
  400ms persist, 600ms overlay autosave) are UX contract, keep them.
- "No Save button" stays: the debounced persist becomes a debounced command
  emit; switching tabs flushes first; the never-mint-empty-notes guard stays.
- Optimistic single-write patterns (e.g. tab-group apply = ONE save then
  events) map to one transaction per user gesture — which is also the undo
  grain.
- The stale-write seam already in the lotus editor (re-read-then-save, refuse
  stale) replaces Liv's `emittedRef` echo-set for external-change sync.

## 4.3 The three places exact replication is impossible (without a second truth or a webview)
1. **Live Obsidian-vault interop** — the `.md` mirror written through on every
   pause, the file watcher, frontmatter round-trip, visible `.base` files, and
   the left rail's live "Vault" tree of a foreign folder. This IS a second
   source of truth; it is the disease lotus exists to cure. **Closest native
   equivalent:** an explicit import/export service — one-shot vault import
   (attach an Obsidian folder → import), on-demand/one-click export (notes →
   `.md`, saved views → `.base`, lists → `.md`+`.base`), and the sidebar
   "Vault" view repurposed as an **import staging browser** over a chosen
   folder (read-only until imported). "Path"/"Reveal in Finder" affordances
   apply to exported artifacts only.
2. **Embedded web content** — ```embed``` sandboxed iframes, YouTube/Vimeo
   players, the `browser` tab subtype (`.url`/`.webloc` open as in-app browser
   tabs), and the DriveBrowser overlay all require an embedded web engine,
   which the constitution bans. **Closest native equivalent:** LinkEmbed's
   card path goes native (unfurl metadata card via LPLinkMetadata-style
   service: thumbnail + title + description + favicon), images render
   natively, video links show a poster card, and everything web opens in the
   default browser; `browser` tabs become "link tabs" rendering the unfurl
   card + annotation. PDF iframes are strictly BETTER native (PDFKit).
3. **Mermaid diagrams** (and, mildly, KaTeX math and the custom-CSS theme
   import). Mermaid is a JS-only renderer; there is no native equivalent.
   **Closest native:** render ```mermaid``` fences as styled code blocks with
   an "Open preview" that exports via a service (or pre-renders SVG through a
   headless service later); math `$…$`/`$$…$$` can go native via a Swift
   LaTeX renderer (iosMath/SwiftMath-class) — keep the same reveal rules;
   custom Obsidian CSS import is simply dropped (no theming in lotus, §3.7).

## 4.4 Second-order UI consequences of the core swap (allowed, invisible)
- Search FTS = a core query/projection instead of SQLite-side FTS5 — same
  ranking table (§2.8.4), same snippet UX.
- "Move file" / customPath rows operate on export locations; internal identity
  never moves.
- The Import extension's Watch tab (folder watcher) survives as an *inbound*
  watcher on a designated import folder only — watching for NEW material to
  ingest is import, not a mirror.
- Every "hydrate body from disk first" step disappears (bodies live in the
  core); the UX (instant open) only improves.

---

# 5 · PORT PLAN — SwiftUI build phases

Each phase is independently shippable; sizes S/M/L/XL; "have" = what the lotus
shell already provides (a SwiftUI window with sidebar/lens/inspector — `shell/
macos/Sources/Window.swift` — an editor over the C seam — `Editor.swift` /
`lotus.h` — and snapshot-JSON rendering from `views/`).

- **P1 · Chrome skeleton (M)** — three chrome rows (title/tabs/bookmarks
  geometry, drag regions, traffic-light spacer), activity rail with gliding
  indicator + badges, panel geometry + persistence (18/30 defaults, clamps,
  collapse), focus mode, DialogHost equivalent (NSAlert-styled sheets per
  §2.26), the z-band discipline, command registry + keyboard dispatcher
  (§2.28.1–2.28.2). *Have:* the window + sidebar/lens/inspector split. *Deps:*
  none.
- **P2 · Workspaces & left sidebar (L)** — workspace/TreeNode entities, Spaces
  tree (rows, DnD, menus, favourites/boards/archive), HomeHub popover,
  WorkspaceSwitcher, createBoundWorkspace flow (minus folder binding),
  Properties view, Bookmarks view. *Deps:* P1.
- **P3 · Unified tab strip (XL)** — GlobalTab model + routing, TAB_BASE pills,
  click grammar, drag-reorder, width freeze, groups/composers/bands, saved
  groups, split panes, blank landing, DeptPicker, close semantics, superspaces
  /saved layouts (log markers). *Deps:* P1–P2. Departments mode is NOT built
  (D18); HomeHub keeps no LayoutModeSwitcher.
- **P4 · Editor (XL)** — the §2.14 contract over the C seam: live-preview
  reveal rules, syntax catalogue, three view modes, title header + save model,
  wikilinks + LinkPicker, slash menu, toolbar + command semantics, folding,
  page ruler, extract-selection, outline/backlinks/snapshot panes. Ship in
  slices: 4a core preview + formatting (L), 4b wikilinks/slash (M), 4c blocks
  (tables/math/callouts/embeds-as-cards) (M), 4d snapshots/history (S — log
  markers). *Deps:* P1; integrates with P3 tabs and P5 focus chords when they
  land.
- **P5 · Right panel & inspector (L)** — view tabs, focus routing,
  MetadataEditor grouped mode (then flat/focused/hybrid), field controls
  (AutocompleteInput/ChipInput equivalents), presets, pinning, groups+Arrange,
  Details, Connections (+ suggest/attach), property registry + Settings →
  Properties chords, Snapshots/Outline/Graph tabs. *Deps:* P2; P4 for
  focus-return.
- **P6 · Omnibox & filter store (L)** — the ONE activeFilter store,
  QuickSwitcher (frame, DSL, facet rail + value grammar, ranking, display
  modes, commands mode, search-that-creates, Save/Open-in-view), HeaderSearch.
  *Deps:* P1 registry, P2 entities; P7 consumes its saved views.
- **P7 · Files & BaseFileView (XL)** — Files tab shell, View surface (lens
  bar, F1–F12 chips, selection/batch), BaseFileView (four lenses, filter
  builder, per-view overrides, preview pane, inline edit, new-row semantics,
  drop-into-base), DataViewBuilder, saved-view entities + `.base`
  import/export, Folder/Browser as import-staging (§4.3.1). *Deps:* P5–P6.
- **P8 · Tasks (L)** — model incl. per-workspace statuses + recurrence, five
  views (List, Board, Schedule, Write, Cards-via-P7), detail modal, quick-adds
  + token grammar, TasksFilterPanel, QuickAddTask overlay, board-assist AI tab
  (deterministic). *Deps:* P5; Cards lens needs P7 (shippable without it).
- **P9 · Lists (M)** — model + template modes, directory + detail (List/Keep/
  Base member views), drop-membership, AddToListMenu. *Deps:* P7.
- **P10 · Calendar (L)** — CalendarItem derivation + config, four views +
  mini-month + checklist + day panel + inline event editor, event entities,
  ICS feed import service + Settings → Calendars, Google sync seam.
  *Deps:* P5.
- **P11 · Daily notes, templates, habits (M)** — dailyNotes settings + entry
  points, NoteOverlay, template entities + manager + generator + meeting-note
  flow, habit stats service + HabitWidget + /habits. *Deps:* P4, P10 (calendar
  hooks).
- **P12 · Library & import & links (M)** — Library browser (PDFKit viewer),
  file entities + ingest service, Import extension (Watch/Drop/URL/Bulk/
  Triage), link objects + unfurl service + LinkSaveOverlay + paste capture.
  *Deps:* P7 helpful, not required.
- **P13 · AI doors (L)** — proposals plumbing wired to: Decide tray (§2.11),
  Assist (engine/generators/cards/chip/rings), Chat + Copilot (answerer),
  Jarvis (agent), Agents scripts, project summary, editor AI (selection
  bubble, ghost text, prompts), AI naming, extraction blocks. Deterministic
  layers ship before model-backed ones. *Deps:* P5 (inspector), P4 (editor
  hooks); the approval-card idioms come from §2.23.
- **P14 · Processor (M)** — Inbox/RouterPanel/Triage over proposals, Import
  (BulkTriageQueue), Merge sets. *Deps:* P13.
- **P15 · Settings window (M)** — shell + tree + finder-search + the real
  panels (Appearance-reduced, Layout, Shortcuts, AI, Workspaces, Object types,
  Properties, Saved layouts/Tab groups, Library & folders, Daily notes, Tasks,
  Calendars, Import/Export). Grows incrementally alongside P2+. *Deps:* each
  panel's owning phase.
- **P16 · Overlays & dashboard (M)** — Mission Control + widget board (reduced
  catalog first: welcome/quick-actions/agenda/suggestions/resume/stats/habits/
  time-tracking), Resume Launcher, suggestion toasts + nudges, onboarding
  (first-run + welcome seeds). *Deps:* P10–P13 for widget data.
- **Cross-cutting, every phase:** context menus + DnD vocabulary (§2.27),
  empty states (§2.29 + per-surface), the visual tokens (§3), and the
  keyboard map rows a phase's surface owns (§2.28.3).

---

# 6 · OPEN DECISIONS for the owner

Grouped; each needs a written call before (or during) the owning phase.

**Where Liv disagrees with itself (code inconsistencies to resolve, not copy):**
1. Right-rail task **Status select uses the default status set** while
   board/list/detail use the workspace's custom set (§2.15.10) — port should
   use the workspace set. Confirm.
2. Processor router's "will route" warning requires area AND project AND real
   type; `isUnfiled` requires only one of area/project (§2.24.2). Reconcile or
   replicate as-is?
3. `showEmptyBuiltins` default: code true, doc-comment false (§2.10.3). Which?
4. Two custom-property type stores overlap (`customPropertyTypes` vs the group
   layout's `fieldKinds`, §2.10.1/§6-note in metadata spec). Port one store.
5. Left-sidebar defaults in Settings list stale options (Tags; missing
   Saved/Graph); right-sidebar default list includes a nonexistent "Bookmarks"
   view (§2.2.1, §2.9.1). Fix the option lists.
6. External `[text](url)` links don't open on click in the editor (§2.14.6) —
   shipped behavior, almost certainly a bug. Fix in the port?
7. Mac title-row spacer 72px vs 28px dead branch (§1.1) — 72px assumed.

**Decided-dead-but-still-shipping (default: do NOT port; confirm each):**
8. `departments|unified` layoutMode split — D18 says unified only; code still
   defaults to departments and renders LayoutModeSwitcher. Port unified only
   (P3 assumes this); keep department tabs as preset containers.
9. `chromeRowOrder` setting (dead render path) + Settings → Layout reorder
   cards (§1.2).
10. Left sidebar ships 5 tabs vs approved 2 (IA-2/IA-4); Vault graph as a
    cramped left tab vs IA-1's full-screen overlay. Port 5-as-shipped or jump
    to the approved 2?
11. "Snapshots" tab rename → "History" + workspace-snapshot relocation (IA-5,
    approved, unshipped).
12. Unmounted/unreachable components: GlobalZone, WorkspacePill,
    SuperspaceSaveForm (no in-strip superspace save!), MetadataPanel,
    SnapshotsView/WorkspaceSnapshotsView, Processor AutoView + legacy
    MergeView, **NoteSplitPanel (feature is finished but unreachable — re-home
    or drop?)**, `tab.mode:"note"` NoteView stub.
13. Dead model surface: `Task.reminderAt`, cross-note checklist plumbing
    (`parseChecklistItems` + overrides store, §2.14.16) — revive as a real
    cross-note checklist or delete; `Suggestion.kind:"reclassify"`;
    `AgentRoutingProvider`/`AgentSuggestionProvider` stubs;
    `dismissStore.clear()` (no UI); `explorer` extension/deptType;
    messages/finances types; IconTheme/DimensionalGlyph; Sonner (never
    mounted); `copilot-prompt` prefill listener (no dispatcher).
14. Visual stubs: Browse-extensions rail button; QuickSwitcher SourceChip
    connector grid (Drive/Slack/GitHub/Gmail/Figma/Dropbox/Notion); palette
    nav rows advertising unbound Ctrl+1/3/4/5.
15. Fake settings: Preferences Auto-save/Confirm-delete/Language/Account card
    ("Viktor Dahl"), Search panel, Files & Links panel, Departments toggles,
    Export/Clear-all-data buttons, AI Level grid + triggers + fields chips,
    Vault&Storage "localStorage" claim. Port as working controls, or drop the
    rows entirely? (Recommend: drop or wire — never ship dead switches.)
16. Suggestion toasts + the floating Assist chip: IA-3 approved
    removal/re-home; still shipping and speced (§2.23.6–7). Keep?

**Where docs promised what code never built (aspirational — schedule or drop):**
17. D15 form/type split (one `type` field ships). D24 single `sources` field
    (code ships `source`+`ref` AND `sources`). WP2 on-disk layout (lowercase
    pools, `.liv/views/`, `.trash/`) — mostly mooted by §4.3(1) but the
    EXPORT layout needs a decision. D25 events-as-.md — mooted (§4.1). D13
    habit model (definitions + check-in rows) vs shipped
    checkbox-derivation. D25 bulk browser-tab/bookmark import (spec only).
    Daily-note carry-over (doesn't exist). D26 brand palette (superseded by
    lake green).
18. "Tab melt" (no border under the active tab) — intended, never achieved
    (§1.2). The port CAN achieve it trivially; do we, or replicate the
    shipped seam?

**Where Liv's behavior conflicts with the lotus core (§4 already rules, owner
should ratify):**
19. The three impossibles (§4.3): import/export instead of live vault mirror;
    native link cards instead of web embeds/browser tabs; mermaid-as-code +
    native math. Ratify the equivalents.
20. Liv's per-write Jarvis gating vs lotus's "agent = one transaction, one
    confirmation, one undo step": keep per-write PreviewCards (more granular
    than the constitution requires) or collapse a Jarvis run into one drafted
    transaction? (P13 assumes per-write cards mapped to proposals.)
21. Multi-window with live BroadcastChannel sync (§1.1): in-scope for the
    port? (The log makes it easier, but it's real work; recommend deferring
    past P16.)
22. Web-only fallback paths (localStorage vault, no-Tauri guards) — drop
    entirely (macOS-native only)?
23. Theming (§3.7): confirmed drop — system light/dark + lake green only. The
    "colorful" chip-color mode (§3.6): keep as the always-on default for value
    chips, or keep Liv's default (primary-tint chips, colorful opt-in)?

**Naming/behavior confirmations:**
24. `tags` renders as "Subjects" everywhere (founder-locked) — keep in lotus?
25. Keep Liv's keyboard map verbatim (§2.28.3) including quirks (Shift+Tab →
    Mission Control from the editor; Alt+chords on macOS where Option types
    glyphs — needs explicit Option-key handling in AppKit)?
26. Tab-strip "department suffix" 9px uppercase labels — below the 11px floor
    lotus inherited (§3.2). Exception or bump to 11px? (Same question for the
    9px kbd digits in the Decide tray and 10.4px badge text.)

---

*End of map. Source of truth for re-verification: the `path:line` references
throughout point into `/Users/k/src/friend-fixes` as of 2026-07-06.*
