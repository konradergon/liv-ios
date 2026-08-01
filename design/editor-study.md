# The editor study — what the note editor becomes and how

> Owner directive, 2026-07-30: the note-taking experience is now the top
> priority. It must be on par with Obsidian's mobile editor, starting by
> copying Obsidian's interface and interaction patterns as a baseline. The
> second pillar is the desktop (Tauri) metadata model with a mobile-first
> interface. Templates must be dramatically easier than Obsidian's — zero
> extensions, zero setup. Polish these two pillars before any new features.
>
> This study sits beside `design/furnishing-study.md`. It digests a research
> pass over Obsidian's docs and forums, Bear/Craft/Apple Notes/Drafts, four
> template systems, six metadata UIs, and a full read of the current editor
> (`shell/ios/Sources/Editor.swift`), the desktop composer spec
> (`liv-ui-map.md` §2.14, `design/p4-editor-model.md`), and the desktop
> metadata code (`lovable-notes-hub`).

## 1. What we are building and why

The editor is the hole: today's phone editor is a plain text box with a
correct save engine underneath it, and writing in it is nowhere near
Obsidian. Obsidian's mobile editor is the baseline we copy — live rendering,
the keyboard toolbar, link autocomplete, tappable checkboxes — built on
Liv's native text stack instead of their web view. Metadata and templates
ride on that editor: property cells become editable where you write, and a
template is just a note plus pre-filled cells, so the second pillar and the
template pillar are mostly the first pillar done right.

## 2. The parity checklist — copied from Obsidian mobile

Each line: the behavior, then the source.

- **Live Preview as the default editing mode** — markdown renders in place
  while you type; a plain source mode stays as fallback
  (obsidian.md/help/edit-and-read).
- **Caret-element syntax reveal** — the element under the caret shows its
  raw markers; everything else stays rendered
  (thesweetsetup.com/how-live-preview-works-obsidian, cross-checked with the
  official help). One amendment from Obsidian's own bug pile: the reveal
  must not change line layout — see §3.
- **Toolbar above the keyboard** — a horizontally scrollable icon row,
  visible exactly while the keyboard is up (obsidian.md/help/mobile). Spec
  in §6; requires narrowing chrome rule 4.
- **`[[` autocomplete** — typing `[[` opens a ranked picker; optional
  display text (obsidian.md/help/links). Adapted: the pick inserts a
  reference span, never bracket grammar — see §5.
- **Tap follows a link, long-press edits it** — Obsidian's current shipped
  iOS behavior, after they scrapped a two-tap popover users hated
  (forum.obsidian.md thread 31729). We skip the intermediate design they
  already paid for.
- **Tappable checkboxes** — a rendered `- [ ]` line carries a real checkbox;
  the tap rewrites the two characters in the text, without stealing focus
  (obsidian.md/help/syntax; forum thread 40040 confirms tap-to-toggle is
  intended Live Preview behavior).
- **Outline navigation** — a tap-to-jump list of the note's headings
  (obsidian.md/help/plugins/outline). Delivered as a visible toolbar button
  presenting a sheet, not Obsidian's edge-swipe sidebar, which their own
  forum shows users cannot find on phones.
- **Quick find-or-create** — one field that opens a note by name or creates
  it on return (obsidian.md/help/plugins/quick-switcher). Liv's Search
  find-or-create (`design/ios.md`) already is this surface; the editor's
  `[[` picker reuses it.

Deferred parity, on purpose: interactive table editing (Obsidian's most
complex Live Preview feature, added only in 1.5) — pipe tables render
read-only-pretty, tap drops the block to raw text, full cell editing is a
later milestone. Section folding is parity, not an edge; it waits too.

## 3. What we refuse from Obsidian — and the complaint each refusal avoids

The pain research clusters around one root cause: Obsidian mobile is a
desktop web app in a wrapper. Every refusal below is a documented complaint.

- **No web view, no custom text engine.** Their CodeMirror-in-webview editor
  has recurring caret and selection regressions: tap-to-place-cursor jumping
  back (8+ users, regressed twice across 1.10.3–1.11), selections lost when
  a drag scrolls the view, spacebar-trackpad jumping into the title. Liv
  builds on UITextView/TextKit, so selection handles, the loupe, autocorrect
  and dictation come from the OS and cannot regress in an app update.
- **No boot work that scales with box size.** Verified Obsidian startups:
  30s to 1–2 min on big vaults; a 25,000-file vault never opened; users
  ship workaround plugins to defer loading. Budget: **under 1 second from
  cold start to typing, independent of box size** — render the last cached
  snapshot first, never block first paint on a full read or index build.
- **No plugins for basics.** Task rendering, templates, and a decent toolbar
  all require community plugins in Obsidian, ~30% of which don't run on
  mobile, and each taxes startup. In Liv these are core shell features.
- **No layout shift when the caret enters a styled line.** Obsidian's
  hide-then-reveal makes lines change width at the moment you tap them —
  worse on a phone where tap targets are imprecise (forum thread 64915). Liv
  styles stable text: bold the text, render the markers dimmed and small but
  present, so the line never reflows. Full marker concealment (Bear-style)
  only if it can be done without reflow — open decision 3.
- **No YAML frontmatter, no properties-as-text.** Obsidian stores metadata
  as YAML inside the note, and two UIs fight over the same bytes — with
  documented data loss (one note's frontmatter replaced by another's). Liv's
  cells already live outside the text; the boundary stays absolute.
- **No parsed `#tags`, no smart date recognition.** A token syntax is a
  type-picker in disguise (`feature-map.md:127-129`), and Todoist documents
  the failure: "monthly" in "Create monthly report" silently seized as a
  recurring date. Typed `#`, `due:`, `@name` stay literal text, by law.
- **No file-path attachments.** Broken image paths are Obsidian mobile's
  single most-cited complaint (paste location differs per device, iCloud
  renames break links). A photo in a Liv note is an entity referenced by id;
  the complaint class cannot exist.
- **No template scripting.** Templater is a programming environment inside
  notes — JS blocks, folder triggers, shell commands that don't run on
  mobile — and users report being overwhelmed into quitting. See §7.
- **No desktop chrome.** Sidebars, workspace tabs, graph, canvas — the part
  of Obsidian mobile the community scores 4/10. "On par with Obsidian's
  editor" means the editor.

Context for later, not now: when sync arrives it must merge at the
append-only-log level, never by putting the box file in iCloud Drive
(Obsidian's free-sync path produces 3–10 conflict files a week for some
users and startup hangs).

## 4. What we steal from Bear, Craft, Apple Notes, Drafts

Precise steals, each with its adaptation:

- **Bear's style keyboard.** One pinned `Aa` button at the toolbar's left
  swaps the system keyboard for a full-height formatting panel — headings,
  bold/italic/strike/code, lists, todo, quote, rule, all at full size — one
  tap back to typing (bear.app/faq/whats-new-in-bear-2). This fixes
  Obsidian's cramped one-row scroll without adding rows. The long-press-
  then-slide attachment button (photo library vs scan in one thumb motion)
  comes with it and pairs with Liv's Camera surface.
- **Craft's swipe-to-indent.** Horizontal pan on the line being edited:
  right indents, left outdents (support.craft.do gestures). Apple Notes
  ships the same gesture for checklists, so it is trained muscle memory.
- **Craft's insert sheet, without the `/`.** The categorized, searchable
  insert-anything sheet is good; the typed `/` trigger is token grammar.
  Liv puts the sheet behind a `+` toolbar button. A typed `/` stays literal.
- **Apple Notes checklist ergonomics.** Return continues the list; return on
  an empty item ends it; tap the circle toggles; swipe indents. All of it
  maps to `- [ ]` plain-text lines rendered natively
  (macrumors.com checklist guide).
- **Apple Notes inline photos.** Camera button in the toolbar; the picked
  photo lands inline at the cursor as a reference span to a photo entity;
  three display sizes (small/medium/large) are span metadata set from a
  tap-on-image menu — never pipe grammar like Obsidian's `|640`
  (support.apple.com/en-us/118442).
- **Bear's suggestion popup, without the `#`.** Type-to-filter list of
  existing values, narrowing per keystroke, tap commits the canonical value
  (bear.app tag autocomplete FAQ). In Liv it is triggered from a picker
  button and writes a tags cell; it never parses typed text.
- **Drafts' toolbar anchors.** A pinned keyboard-dismiss key at the far
  right of the toolbar (docs.getdrafts.com action-bar) — the most-missed
  control in Obsidian. The swipe-down-in-text dismissal stays as well.
- **Drafts' idle-timeout capture rule.** For the capture sheet, not the
  editor: reopen soon after leaving and you resume what you were writing;
  reopen stale and you get a fresh capture. The measurable bar is time from
  app-open to first typed character.

## 5. The two Liv deviations from Obsidian

**Links resolve to box entities, not files.** Typing `[[` opens the
find-or-create picker over the box (the Everything projection ranks
candidates; an unmatched query creates the entity, then links it — the
desktop's create-then-Ref rule, `p4-editor-model.md:167-171`). Picking
inserts a reference span whose payload is the **id**; the display name is
cosmetic and re-derived per load; names are never resolved back to ids
(`Editor.swift:20-21`). A typed-but-unpicked `[[something` stays literal
text forever — the `[[` characters are an input trigger, not stored grammar.
Tap on a rendered reference navigates (opens as a Desk tab); long-press
places the caret to edit — Obsidian's shipped iOS behavior.

One sharp edge to close: the current codec converts any well-formed
`[[digits]]` in the buffer into a Ref on save (`Editor.swift:196-212`), and
a Ref to a nonexistent entity makes the whole save Invalid
(`services/src/content.rs:86-93`) — a pasted markdown note containing
`[[123]]` can loop on "The box refused this save". Policy: before save,
validate ref tokens against the snapshot and **demote unknown-id tokens to
literal text** (open decision 5).

**Properties are cells with pickers, never frontmatter.** There is no YAML,
no raw mode, no text representation of metadata at all. The one metadata
editor lives behind the top-right collapse chevron (`design/ios.md:231-237`
— itself the Obsidian properties-chevron idiom) and edits property cells
with mobile-first pickers: select sheets where the core defines options,
type-to-filter autocomplete where the vocabulary is free, the native date
picker for dates. Details in §8.

## 6 rev 3. The toolbar returns, the chrome retreats (owner, 2026-07-31)

> Superseding rev 2. The owner used the hidden-`Aa` model and rejected it:
> formatting belongs in ONE horizontally scrollable row directly above the
> keyboard (the Bear shape, from the owner's own screenshot), with the
> keyboard covering the bottom bar. Everything else moved the other way:
> the persistent top bar is gone (Workspace/Settings behind the desk's
> floating `…`), the DETAILS row and meta line left the editing view, the
> editor is full-bleed with the bars hovering over it, explanatory
> micro-text is banned, the type scale went up one step, animations are
> slide-only (`LivMotion.nav`), and the lake-green theme is replaced by a
> generic dark theme (system-blue accent, forced dark). Rev 2's selection-
> menu formatting SURVIVES — it cost nothing and is still the fastest
> inline path. What rev 2 got wrong, for the record: "one effortless
> action away" read as one tap TOO MANY for block formatting, and a
> hidden-by-default toolbar traded real discoverability for a principle.

## 6 rev 2. Formatting chrome — the layered model (owner, 2026-07-30)

> Superseding §6 rev 1 below. The owner's principle: *hide everything that
> is not relevant to the current task, while making every tool instantly
> accessible when it becomes relevant.* A persistent toolbar row fails it —
> it is standing chrome for something roughly 95% of keystrokes do not need.
> Rev 1's spec (and the rule-4 narrowing it asked for) is kept below as the
> record of what was built and why it changed.

The reframe that makes this affordable: **typing a marker already formats.**
`#`, `- `, `- [ ] ` style live as you type, so the fast path needs no chrome
at all. That is the expert path, and it is faster than any toolbar. The
visible controls exist for people who do not know the markers — and controls
hidden one action away cost the expert nothing.

Four layers, each appearing exactly when it becomes relevant:

- **Layer 0 — the note.** While writing: text and keyboard. The advisory
  notices (flatten, save-refused) and the status line hide; the conflict
  banner does not, because it is about the words being typed right now.
- **Layer 1 — the markers.** Live styling, always. No chrome.
- **Layer 2 — the selection menu.** Bold / Italic / Strikethrough / Code
  join the system edit menu, inserted straight after Cut/Copy so they are
  on its first page. They exist exactly while there is a selection to
  format and leave with it. Inline formatting IS an act on a selection, so
  this is where it belongs; and the menu is a control every iOS user
  already knows, which answers the discoverability half of the principle.
- **Layer 3 — the `Aa`.** One quiet 36pt control floating over the note's
  bottom corner while writing (44pt hit target), gone when you stop. It
  swaps the keyboard for the full-height style panel: three rows —
  inline, blocks, then outdent / indent / undo / redo / hide-keyboard.
  Block formatting is occasional, so it gets a handle, not a residence.

**What this costs, honestly.** Checkbox and indent go from one tap to two
(swipe-to-indent, when it lands, makes indent a gesture; checkboxes are
mostly made by typing or by continuing a list). Block formatting is one
notch less discoverable — mitigated by the `Aa` being visible, just quiet.
And it deviates from Obsidian's persistent toolbar, which this study's own
§3 already lists among their documented complaints.

**Keyboard dismissal** is the swipe-down-in-text gesture (the Notes idiom,
already implemented) plus the pinned key in the style panel. If the gesture
proves undiscoverable in use, the fallback is a second floating control —
deliberately not built yet, because it doubles the standing chrome for
something the platform already trains.

---

## 6 rev 1 (superseded). The keyboard toolbar — spec, and the chrome-rule-4 narrowing it needs

**The rule as written** (`design/ios.md:225-229`, owner, 2026-07-29):

> **No keyboard accessory row.** The editor had a keyboard-toolbar "Done"
> that shoved the chip row and the bottom bar every time the caret entered
> the text. Dismissal is the swipe-down-in-text gesture instead
> (`.scrollDismissesKeyboard(.interactively)`). Nothing may appear above
> the keyboard and move a row.

As written, this bans the one thing every Obsidian-par mobile editor has.
But the recorded harm is narrower than the rule: the Done bar's crime was
**shoving other rows** — a layout jolt independent of the keyboard. An
`inputAccessoryView` rides the keyboard's own appear/disappear animation and
moves nothing else. The narrowing this study asks for (open decision 1):

> A row that appears and hides **as part of the keyboard's own animation**
> is allowed. Anything that moves a row independently of the keyboard stays
> banned.

The swipe-down dismissal gesture stays regardless.

**The toolbar itself**, if the narrowing is granted:

- One row, opaque theme colour (chrome rule 2), hairline top edge, lake
  green as the only accent, 44pt targets.
- **Fixed left anchor:** `Aa` — swaps in the Bear-style formatting keyboard
  (full-height panel: heading cycle, bold, italic, strike, code, bullet,
  ordered, todo, quote, rule; attachment button with long-press-slide).
- **Scrollable middle:** todo checkbox, indent, outdent, link (`[[` picker),
  photo, template-insert (§7), undo, redo.
- **Fixed right anchor:** dismiss-keyboard (Drafts' pinned key).
- Fixed default set, distinct icons, **no configuration screen** in v1 —
  Obsidian's own docs treat the default arrangement as unremarkable, and
  their Settings-buried customization is a documented pain point.
- No persistent bottom nav competes with it: while the keyboard is up the
  toolbar is the only chrome (Obsidian's 1.7 unremovable nav bar drew ~15
  forum users' complaints about accidental taps).

## 7. Templates — the zero-setup design

The research spread is a spectrum of setup burden: Bear has no system
(tag + duplicate + hand-fix dates), Craft has a pleasant system with zero
variables (so daily notes fail), Obsidian core needs a settings-mandated
folder and cannot create a note from a template without installing
Templater, and Templater is a scripting project. Notion has the best single
idea: a template pre-fills **property values**, and it is offered exactly
where things are created.

Liv already has half of this: the capture context stamps metadata (a note
created inside a project carries the project cell). Templates extend that
stamp to the body.

**The design:**

- **A template is a note.** "Save as template" on any note makes a copy
  carrying a `template` cell. Non-destructive — Craft's move-the-original
  footgun is explicitly avoided. The template list is a projection query.
  No folder, no setting, no registration.
- **Two verbs, both native.** *New-from-template* is offered at every
  creation point — the capture sheet, the `+` in a project, the New-tab verb
  stack. *Insert-at-cursor* lives behind the toolbar's template button. The
  core-Obsidian gap (insert-only; creation needs a plugin) is the hole we
  refuse to have.
- **Four variables, as pills.** Date, time, title, cursor-lands-here —
  inserted from a picker in the template editor, stored as structured spans,
  rendered as pills, resolved at instantiation (Notion's "date when
  duplicated" semantic). A hand-typed `{{date}}` stays literal text, by law.
  The research shows these four cover real use: Obsidian core survives on
  three of them; Templater's single most-cited feature is the fourth; Bear
  and Craft show zero variables forces users into external scripting.
  Nothing else — no prompts, no scripts, no web calls.
- **Pre-filled cells.** A template carries property cells (area, project,
  tags, status); instantiation copies them onto the new entity as visible
  chips. This is the Notion database-template trick, unlocked from Notion's
  per-database trap: Liv templates are global, filterable by context.
- **Optional default template per project or area** — a cell on the project
  entity, so creating a note inside it pre-offers that template.
  Deterministic and user-set, so it never collides with the amber law.
- **Ship three built-ins:** daily note, meeting, person. Day one, a fresh
  box has one-tap templates that Obsidian needs two plugins to match.

Any AI-assisted fill stays an amber-marked proposal; templates themselves
involve no AI.

## 8. Metadata while writing — mobile-first, inside the laws

The anti-pattern is Notion mobile: every property edit is a separate pushed
screen, users defer all field-setting to desktop, and a third-party app
economy exists to bypass it. The winning pattern across Reminders, Things
and Todoist is: field verbs one tap from the text, presets one tap inside
each verb, focus never leaves the note.

**What changes on the phone:**

- **The persistent chip row folds away.** `EntityChipRow` was born from the
  M1 eval (`design/ios-m1-eval.md:50,75`), not a spec, and it now stands in
  tension with the one-metadata-editor law (`design/ios.md:231-237`) while
  permanently taxing the writing surface. Properties live behind the
  top-right chevron — Obsidian's own properties idiom, which Desk already
  implements. The eval's real complaint (a sub-HIG affordance) stays fixed:
  the chevron target is ≥44pt. Owner sign-off needed (open decision 2).
- **Inspector rows become editors.** Today the general cell rows in
  `Detail.swift` are display-only. Each becomes tappable: select sheet for
  area and status (options from the core — `liv_status_options_at`, the
  furnished area options), type-to-filter autocomplete backed by
  `liv_distinct_values_at` for project, subjects, people, the native date
  picker for dates. The shipped due-shortcuts sheet (Today / Tonight /
  Tomorrow / Weekend above a calendar) is already the Things preset-first
  pattern; it becomes the template for the rest.
- **Every entity picker gets a create row.** "Create \"<typed text>\"" at
  the top of empty results — the piece whose absence provably pushes
  Anytype users back to desktop (community.anytype.io thread 10778).
- **Defaults come from context.** Capture inside a project pre-fills the
  project cell, shown as a removable chip — visible, mechanical, not a
  classification, so the amber law is untouched.
- **Zero fill pressure.** The desktop's D11 discipline ports: a small core
  of rows always visible even when empty, kind-relevant extras surfaced,
  everything else behind one fold. Two filled fields is a finished object.
- **Free-text-with-suggestions does not port** as the editing grammar for
  area, status or type — that is the desktop's tag-soup drift the owner
  already complained about (D15). Core select options where they exist;
  autocomplete only for the genuinely free fields.

Bear's suggestion-popup ergonomics apply inside every one of these pickers;
Fantastical's one transferable lesson applies to all of them: whatever sets
a field shows the resolved value next to the text at the moment it is set.

## 9. Constraints honored

**The wire format.** Verified: nothing on the write path strips or
normalizes content — `services/src/content.rs:63-113` stores the span vector
verbatim; `liv_set_content_at` is a pure decode (`ffi/src/lib.rs:1613-1642`).
So the editor can ship storing plain markdown text on day one with **zero
core change**, and later upgrade to real marks-and-blocks — D19's law that
markdown markers are never stored (`p4-editor-model.md:9-13`) — also with
zero core change, because the wire already carries Marks and Break blocks
and the phone already decodes them totally (`Editor.swift:42-97`). Only the
Swift encoder needs extending. Path B (marks-and-blocks) is the target: it
is the only path where a note reads the same on the phone and the Tauri
desktop, and it retires most of the flatten notice. Timing is open
decision 4.

**The laws.** No token grammar in text — markdown formatting types the look
of content, not cells, so Live Preview does not collide with the law; `#tag`,
`due:`, `@name` parsing stays refused. Amber marks AI only; AI is
proposals-only and stays out of the editor (no ghost text, no autocomplete).
One accent, lake green. Compact density, opaque chrome, full-screen surfaces
with the 40pt header-as-control (chrome rules 1–3).

**What survives from the current editor, verbatim:**

- The autosave loss budget — 2s idle + 30s checkpoint + flush on focus loss,
  scene change, and disappear; coalesced saves; the fingerprint rides with
  the payload (`Editor.swift:319-421`; cadence is constitutional,
  `interface.md:355-363`).
- The CAS save — whole value against a fingerprint, no force flag
  (`interface.md:368-372`).
- The moved-under-us conflict banner — box's truth shown, live buffer kept
  as draft, Re-apply / Keep this one (`Editor.swift:426-485`). Obsidian has
  no equivalent; this is Liv's own.
- The flatten notice (narrowing, not vanishing, as marks-and-blocks land),
  the save-refused notice, the status line, dirty-as-comparison.
- The `[[id|Name]]` ref codec, its never-lenient parsing, and its self-check
  (`Editor.swift:103-212, 634-709`) — green through any extension.
- The scrap title rule — first line is the title, no title row rendered
  (`Desk.swift:150-172`).
- Capture's draft rule — survives process death, clears only on confirmed
  commit (`CaptureSheet.swift:96-98, 295-328`).

The whole project is shell-only: core and services untouched, any FFI wants
purely additive, every new wire field optional in the decoder.

## 10. The four vocabulary divergences with the desktop

Each is an owner decision; the pivot doc (`docs/liv-core-pivot.md` §3) names
this class as the pivot's hard part.

1. **Area** — free text on desktop vs the six fixed select options on the
   phone; `what-liv-is-for.md` outranks and sides with the phone, so the
   desktop's area row becomes a six-option select and existing vault values
   need a mapping pass.
2. **Project** — desktop wraps a single string in structure (subproject row,
   `projects/` path tags, ActiveProject pin) vs the phone's plain text cell;
   cheapest one-meaning resolution is the phone's (one free-text cell,
   leaf-only, no nesting), anything richer implies box-level structure.
3. **Inbox membership** — desktop: placeholder type OR neither area nor
   project; phone: missing kind only; the app's most visible number needs
   one shared definition, probably computed in `liv-services` so both shells
   read the same count.
4. **Status scope** — desktop ships per-workspace StatusDef sets, but the
   core and the desktop's own BP-1 blueprint (e11) both say per-kind
   options; direction already implied, the work is mapping workspace
   StatusDefs into for-type-scoped option entities during the pivot.

## 11. Build plan

Editor first, metadata second, templates third, per the directive. Sizes
are rough; every phase is mockup-first and ends verified on the simulator
with a CLI cross-check against the box.

- **Phase 0 — rulings and mockups (days).** Owner decides §12 items 1–5;
  mockups for the editor surface, toolbar, and style keyboard; record the
  chrome-rule-4 delta in `design/ios.md`.
- **Phase 1 — the writing surface (2–3 weeks).** Replace the text view with
  UITextView/TextKit 2. Live markdown styling with caret-element reveal and
  zero layout shift; dimmed markers. Tappable checkboxes. Return-continues /
  empty-return-exits list behavior. Swipe-to-indent. The keyboard toolbar
  and the Bear-style formatting keyboard. Port `NoteEditorModel` intact —
  autosave, CAS, conflict banner, codec, self-check. Per-keystroke work
  stays incremental: restyle the dirty line's elements only, no whole-note
  rescans, no FFI reads on the typing path.
- **Phase 2 — links and structure. SHIPPED 2026-07-31** (except tables).
  `[[` opens a picker over the box that filters as you keep typing, with a
  find-or-create row; picking writes an id-based ref. Tapping a link opens
  its target as a desk tab; long-press still places the caret. Unknown ids
  demote to literal text at save time (ruling 5) instead of looping on a
  refusal the core will never accept. The outline follows §6 rev 2's
  principle rather than the toolbar button first sketched here: its control
  appears **only once a note has three or more headings**, which is the
  point at which jumping around is a real need.
  *Deferred:* read-only-pretty pipe tables with drop-to-source.
- **Phase 3 — metadata while writing. SHIPPED 2026-08-01.** The inspector's
  rows are editors. ONE sheet serves every property, because the
  differences between fields live in a descriptor read off the snapshot
  (`InspectorField`) rather than in branches in the view: whether the
  vocabulary is closed (a select — no create row, §10's fixed furniture),
  whether the field holds several values at once, and how a value is
  written. Tapping a value toggles it; a single-valued field answers its
  question and closes; an open vocabulary offers "Create …" last.
  Zero fill pressure is a row policy: area, project, subjects and people
  are always present even when empty, reading "—" rather than nagging, and
  every other property appears only once it holds a value. The chip row is
  already gone (the full-bleed pass), so nothing duplicates the inspector.
  *Deferred:* a date picker richer than the existing due sheet, and
  reference-typed fields (people-as-entities rather than text).
- **Phase 4 — templates (about 1 week).** The `template` cell and "Save as
  template"; new-from-template at every creation point; insert-at-cursor
  from the toolbar; the four variable pills resolved at instantiation;
  pre-filled cells; default-template-per-project; the three built-ins.
- **Phase 5 — marks-and-blocks storage (1–2 weeks, can slide).** Extend the
  Swift encoder to write Marks + Break spans (D19 path B); narrow the
  flatten notice to still-unsupported shapes; add the source-mode toggle.
  Zero core change; the codec self-check grows with it.

## 12. Open owner decisions

> **Ruled by the owner, 2026-07-30:** 1 yes · 2 yes · 3 A · 4 confirmed ·
> 5 yes · 6 confirmed · 7 deferred. Items 1–6 are settled; only §10's
> vocabulary divergences remain open, to be settled before the Tauri pivot.

1. **Narrow chrome rule 4** (`design/ios.md:225-229`) so a row that appears
   and hides as part of the keyboard's own animation is allowed; anything
   that moves a row independently of the keyboard stays banned. Blocks
   phase 1. The rule is one day older than the directive that collides with
   it, so this needs your word and a recorded delta.
2. **Fold the persistent chip row** behind the metadata chevron. It came
   from the M1 eval, not a spec; the eval's discoverability complaint stays
   fixed by the ≥44pt chevron target.
3. **Marker rendering:** dimmed-but-present markers (zero layout shift,
   this study's recommendation) vs Bear/Obsidian-style full concealment
   (reflows the line when the caret enters). Concealment could come later
   behind a setting if it can be built without reflow.
4. **Storage timing:** ship phase 1 storing plain markdown text (legal,
   wire-verified), with phase 5 converting to marks-and-blocks (D19) —
   confirm the target and whether phase 5 may slide past templates.
5. **The `[[digits]]` paste policy:** demote ref tokens with unknown ids to
   literal text before save, closing the refused-save loop.
6. **Template copy semantics:** "Save as template" copies the note and
   marks the copy; the original never moves. Confirm.
7. **The four vocabulary divergences** (§10: area, project, inbox rule,
   status scope) — each needs a ruling before the Tauri pivot's mapping
   pass; none blocks phases 1–4.
