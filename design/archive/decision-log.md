# Liv iOS — decision log

Owner rulings are law; PENDING items are proposals awaiting the owner's
word. Newest first. Details live in `design/ios.md` (revs) and
`design/editor-study.md`.

## Approved (owner)

- **2026-08-09 — Todoist-style inline capture parsing REFUSED** (owner:
  "too non-obvious how to use it and too much freedom"). Dates and
  filing stay as chips and Inbox suggestions, never as live parsing of
  the typed line. Do not propose it again.
- **2026-08-09 — data-model trims T1-T4, T6 approved and (except T3)
  shipped.** T3 next, with an old-box fixture. Also the owner:
  "'markdown as storage' seems like an outdated law" — see the
  recorded position in next-batch.md: the honest state is a hybrid
  (structural breaks + literal markdown markers in text), the LAW that
  matters is one-parser-per-grammar, and the storage wording should be
  revisited as its own decision, not smuggled in.
- **2026-08-09 — two interface laws.** (1) A drag never presses what it
  crosses: the gesture that moves panels must take the touch back from
  every control under the finger the moment it becomes a drag. (2)
  Contents and properties never share a surface: a property view shows
  facts, never the bytes; the file tab shows the bytes, and its facts
  live behind the (i) door.
- **2026-08-09 — files, decided while building** (owner: "go ahead with
  files"). (a) Has-a-file CROSSCUTS the six kinds; there is no seventh
  "File" kind, and `TabShape` checks for a file first. (b) A file is a
  document you work on, so it keeps a TAB — the tab law reads "things
  you work on". (c) Liv never writes foreign bytes: preview, hand off,
  and re-hash on open. (d) A PHONE import copies the bytes into Liv's
  own store and says so; the desktop records the path in place. This is
  not a preference — a picked file's path is unreadable afterwards, and
  it was verified failing live before the copy was added.
- **2026-08-08 — Option C approvals.** (1) YES: opening splits by kind —
  a note opens as a tab, a task/event opens as a card over where you
  stand. (2) "Bad but maybe" on records losing tab permanence — his
  stated fear is losing jump-away-and-come-back; ANSWER BUILT INTO THE
  DESIGN: a swiped-down record card MINIMISES to a pill above the bottom
  bar (one at a time, like Mail drafts) and restores on tap; every
  record edit also writes immediately, so nothing is ever lost with the
  card. (3) Pruning explained and accepted: old saved tabs that hold
  task ids are closed quietly on first launch after the change. (4) "I
  guess": the tab system may learn entity kinds.
- **2026-08-08 — THIS repo's suggestion system survives.** The Rust
  proposal queue is the one mechanism for anything AI proposes, on every
  platform. The desktop repo's TypeScript suggestion stack
  (staged-suggestion tray, validator, reframe plan) is condemned; its
  deletion happens in that repo. AI titles remain blocked only on the
  cloud-vs-on-device question.
- **2026-08-08 — no time estimates.** Never tell the owner how long a
  change will take. Size things small/medium/large if needed.
- **2026-08-07 — standing rules.** (1) Syntax (#, **, `, [[]]) must
  NEVER appear in a title — enforced in the core, tested, one
  implementation. (2) No two code bits solving the same problem.
  (3) When a decision makes code unnecessary, delete all of it — no
  dead code. (4) Portability comes from the Rust core, but the iOS app
  comes FIRST; no pre-emptive rewrites for Android.
- **2026-08-07 — a foreign draft survives a content save.** Only the
  sweep's own proposers (dates, mentions, priority, promotion, dedupe)
  are retracted when a note's text changes, because only they re-derive.
  Settled-zone change, ordered by the owner, failing-test-first.
- **2026-08-07 — the snapshot's `title` means DISPLAY NAME** (owner:
  "Start with Level 1"). It was a whole-body summary. This CHANGES the
  meaning of an existing field, which CLAUDE.md's ffi rule normally
  forbids; the owner authorised it explicitly after being shown the
  before and after. Shipped failing-test-first with `liv.h` updated.
- **2026-08-07 — the default time is 09:00, and all-day belongs to
  events.** The current time was wrong: a task typed at 23:47 was due at
  23:47. An all-day event keeps its all-day-ness when only its day
  changes; a task always gets a moment, because a task with no clock
  time cannot ring. `LivDue.defaultHHMM` and `LivDue.carriesTime` are
  the only two places that say so.
- **2026-08-07 — smarter title RULES (level 2) are skipped for now**
  (owner). First line is the floor and it is enough until there is
  something better.
- **2026-08-06 — the second fix batch.** (1) Headings, interface text
  and buttons are too subtle or small; raise clarity throughout, panels
  first. (2) Today, Tomorrow and the arbitrary date all set a date, so
  all three wear the same face; date is separated from time. (3) A due
  date always has a clock time — when you do not pick one it takes the
  current time; there is no such thing as a "date reminder", and the
  reminder lead-time settings are deleted. (4) The properties panel's
  top line names the ITEM; rows are for things you can EDIT, and static
  facts do not get rows. (5) An empty note's title line shows a grey
  "Untitled" — this REVERSES design/ios.md §"no placeholder text at
  all" for the title line only; the body still shows nothing.
- **2026-08-06 — records open as sheets, not tabs** (owner: "Sheet?
  Sure"). A task or event is edited over the surface that owns it —
  Tasks, Today, Calendar, Inbox, Search — never as a desk tab. Tabs hold
  documents. NOT YET BUILT: this is the next phase.
- **2026-08-06 — the AI refusal is lifted in principle** (owner: "If the
  spec strictly refuses AI, it shouldn't. We should be open to
  implementing AI everywhere it is the right tool"). This overturns
  design/p16-ai.md's blanket REFUSE on the naming family. It does NOT
  by itself authorise any build: the app has no model, no network path
  and no proposal verb for a generated name, and the standing quarantine
  (proposals only, never automatic writes) is untouched. Scope and
  mechanism are still open.
- **2026-08-06 — no unrequested accessibility work.** The owner: *"When
  did I tell you to implement VoiceOver and Voice Control? Stop
  hallucinating."* The five calendar-block actions were removed on his
  word. Standing rule: accessibility affordances beyond correct labels
  are a FEATURE, and features are asked for.
- **2026-08-06 — six fix notes.** (1) The Properties panel needs no
  "Properties" title. (2) Settings needs real work. (3) No small
  explanatory text under buttons — "keep UI clean overall". (4) Names of
  calendar items are set IN the calendar. (5) Things that aren't
  documents must not be edited like documents. (6) The divider does not
  render. Standing consequence of (5): the desk has TWO tab shapes —
  document and record — and `TabShape.of(row)` is the only place that
  decides which. Standing consequence of (3): a grey sentence explaining
  a control is a design failure; say it with the app's own chips, or
  don't say it.
- **2026-08-06 — templates STAY, with the banner** (roadmap phase 6).
  The misuse the owner feared — editing the template when you meant a
  copy — is answered by the pill a template wears on the desk
  ("Template · New note"), verified live: the button minted a fresh
  note with `{{date}}` resolved and wrote NOTHING to the template
  itself. Duplicate note remains the other, lighter path. Neither is
  removed.
- **2026-08-05 — phase 5 rulings.** Build both screens; LATE means
  incomplete TASKS only (a past event is not late); the Inbox is two
  sections in one list, not segments; routing to Event opens the date
  editor. Plus a standing instruction: an arbitrary date AND time must
  be reachable wherever a date can be set.

- **2026-08-05 — the roadmap and all six questions** ("all six yes"):
  the phase order stands; Everything wears the workspace lens; Camera
  stays out of the sidebar; Properties is NOT in ••• (own door + swipe
  only); Duplicate note copies the TYPE and skips reference/file cells;
  suggestions default-ON when the box carries no consent switch.
- **2026-08-04 — the proposal process.** Roadmap first, approval-gated;
  one phase per response; `.md` files are the project's memory
  (roadmap / decision-log / changelog / next-batch).
- **2026-08-03 — rev 6 directive** (with reference screenshots):
  full-screen swipe-in side panels; Notesnook sidebar as the library
  model (global band / workspace band / bottom band); workspace filters
  apply consistently (Calendar, Tasks, Notes, new content); New Tab is
  an overlay, never a tab; frequent actions get dedicated UI — ••• is
  secondary-only; transparent, never-vertically-scrolling keyboard
  toolbar; simpler new-task flow; Duplicate note (properties, not
  body); AI suggests only with explicit approval; ClickUp / Notesnook /
  Apple Calendar as visual references; OCR etc. deferred.
- **2026-08-02 — rev 5.** Top-right is a ••• menu; the right panel
  describes (renamed Properties) and its verbs moved to the menu; the
  box-level Undo left the panel; due editor = Today / Tomorrow / date
  picker / opt-in time / Clear; bottom bar retires under the keyboard.
- **2026-08-01 — rev 4.** Three zones (library / desk / item panel);
  tabs hold editable content only; one-row bottom bar; `^` features
  menu deleted.
- **2026-07-31.** Lake green dead; generic dark theme; toolbar above
  keyboard (hidden-Aa model tried and rejected); full-bleed note; title
  is part of the note (Obsidian), derived title never written to the
  box; new note focuses the BODY; slide-only motion.
- **2026-07-29.** Feature windows and the tab view take the whole
  screen; no translucency anywhere (delta 2026-08-03: the keyboard
  toolbar is now deliberately transparent — owner's explicit ask).

## Pending owner approval

- **Templates:** keep-with-banner vs duplicate-only vs drop
  (roadmap phase 6).
- **Two core/ffi fixes** (task chips filed, failing-test-first per the
  boundary rules): the assist toggle writes the consent switch by NAME
  while the clerk reads it by ID (wrong-property write in a box with a
  foreign `automation` definition); FFI `triage()` cannot accept/reject
  merge proposals whose first command is Trash, and their presence
  shifts later proposals' ordinals on the same note.
