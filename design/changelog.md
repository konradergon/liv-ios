# Liv iOS — changelog (batch summaries; details in design/ios.md revs)

## 2026-09-05 — the bottom fade: built, then removed

Owner: *"remove the bottom fade. just ugh."*

Built on 2026-09-02 in the look pass, fixed on 2026-09-03, gone on
2026-09-05. Recorded because the two faults it hit on the way in outlast
it.

**What it was.** `LivBottomScrim` — the ground fading in under the
floating bottom bar, the same device `LivTopScrim` uses at the other end.
The reason it was built: the bar does not float, it ghosts. Sampled where
nothing is behind it, the capsule's interior is `#1A1A1A`, bit-identical
to the page, and its whole definition is a one-device-pixel rim. With a
list behind it, rows read straight through the glass.

**Fault one: a fixed-height view does not move into the unsafe area.**
The scrim faded the list down to the bar and then stopped — measured on
the Notes list, ground (26) all the way to the capsule and a row at 164
BELOW it (owner: *"the fade is stopping below bar"*). It was a
fixed-height child of a bottom-aligned ZStack, and that ZStack's bottom
is the SAFE AREA's bottom, so it ended about 34pt above the screen.
`.ignoresSafeArea` was already on it and does not fix that: it lets a
view DRAW into the unsafe region, it does not MOVE a fixed-height one
there.

**Fault two, worse: it ate the bar's taps.** Pulling the bottom edge past
the inset fixed the fade and stopped the numbered box on Notes from
opening the switcher at all. `.allowsHitTesting(false)` did not save it.
Found by bisection — removing the scrim brought the box back — after
first chasing it into `Tabs.swift` and the bar itself, both innocent. The
real fault was where it lived: as a sibling of `BottomBar` in RootView's
ZStack it was competing with chrome for the same touches. **A scrim that
fades a surface's content belongs TO that surface**, which is exactly
where `LivTopScrim` already sits. Moved to an overlay on the desk, beside
its twin, it inherits the desk's own travel for free. Measured after:
884pt reads 26, the ground.

**Why it went.** The owner looked at it and said no. The type and its
comment go with it (standing rule 6). `LivTopScrim` stays: words
genuinely run under the clock at that end, and the bar has no such
problem to solve.

## 2026-09-03 — a door back to the list, and the desk starts at the thumb

Owner: *"you can't access note list without closing all note tabs"*, and
*"tabs should begin at bottom where thumb is"* (both 2026-08-31).

**Two ways into Notes, and one of them did not exist.** Notes' root is
the list; a document is a tab on the desk, and the desk went app-wide on
2026-08-28 — so once any note was open, Notes always drew the document,
and the list could not be reached without closing every tab. `showList()`
had one caller, the rehearsal flag.

Tapping the view you are already in now goes to its root. That is the
phone's own idiom, and it keeps the other half working: arriving at Notes
from another view still restores the document you left, and the bar's
numbered box is still the way back to it from the list.

**The desk starts at the thumb.** The switcher filled from the top of the
screen down and is opened by the numbered box on the BOTTOM bar, so the
motion was: reach to the bottom, then reach back to the top for the thing
you just asked for. On a tall phone the first card sat about 700pt from
where the finger already was. Two halves to the fix: a SHORT desk sinks —
the content takes the container's height, aligned bottom — and a LONG one
starts at the bottom and scrolls up, which is also where "New note"
lives. The footer stays at the foot, under the grid: it is the way out,
and it must not move when the cards do.

(The footer went missing for one build while that was being wired, which
would have left the switcher with no way out. Caught before it ran.)

## 2026-09-02 — the look pass: a second voice in every row

Owner: *"screw all the rules i set weeks ago. do whatever you think is
best to make this app look pretty."*

Screenshots of all eight surfaces went to six independent design
readings; every proposal was put to a skeptic, 39 of 47 survived, and
this is what was worth doing.

**Say the date once.** Everything drew fourteen consecutive rows reading
"Mon 31 Aug", right-aligned and monospaced, in the same ink as the titles
beside them — and since most titles are the placeholder "Untitled", the
screen was two ragged columns of near-identical grey. A date that is true
of every row on screen tells you nothing about any of them, so
`livNewFact` draws a fact only when it CHANGES, on all four list
surfaces. It compares the rendered STRING, never the day: both `tasksDue`
and `whenLabel` return a time for today's rows, so comparing days would
delete the second of two things due at 09:00 and 20:00. That is data
loss, not a repeat.

Not day-group headers, which two of the readings proposed: a header is
honest only where the printed key is the SORT key, and Notes sorts on
`recency` while printing `created`.

**The row gets its second voice back.** `LivRowFact` was `label` (16) in
text2 — one step under an 18pt title in the SAME ink — and the glyph was
text2 too, so three things on a row spoke at one strength. A fact is
caption (14) in text3 now, and the glyph is text3.

**And the shared row joins the grid it was given.** `LivListRow` drew its
own 22/12/2 numbers inside containers padding 18, so its words landed at
54 by coincidence while its hairline — which asks for `LivRow.hairline`,
measured from the SCREEN — was applied inside that inset frame and landed
at 72. Measured on `notes.png`: every line in the app missed the words it
divides by eighteen points. That miss was introduced on 2026-08-30, by
the pass that derived the hairline in the first place.

**The task mark stopped lying.** `.task` and `.tasks` shared one drawing
— a box with a TICK — and `StatusRing` draws a ticked box to mean DONE.
So every open task in a mixed list wore the done mark: Everything showed
four ticked tasks that Tasks drew as empty rings, same app, same moment.
A PLACE keeps the tick ("Tasks" is a place, and a ticked box is what the
word looks like); a THING gets a rule.

**No stock controls left.** Settings' segmented thumb was `#6D6D72`, a
grey with a blue cast that appears in no palette here, and its two system
switches were most of that screen's 0.74% saturated pixels, against
0.05–0.19% everywhere else. `LivSegment` and `LivSwitch` replace them in
the app's own language — a quiet fill and full ink for "this is the one
you are on", the accent at a quarter strength in a switch's track rather
than filling it — and stand 44 and 40pt tall, because a control is a
touch target before it is a shape.

**The bar got a floor**, which lasted three days — see the 2026-09-05
entry.

Also: Notes, Everything and Tasks had no name at the top, and a list that
starts at its first row reads as a fragment of a screen rather than a
screen; the Reminders card showed a switch ON directly above the words
"Turned off for Liv in iOS Settings", so the switch shows the PERMISSION
now, which is the thing that decides whether anything happens; the
calendar's 08:00 was sliced by the viewport, because `scrollTo(anchor:
.top)` parks the RULE, not the label; and the panel's shadow never drew
at all — sampled across `library.png` at y=500, the panel holds `#232323`
to x=319.67 and the desk's `#1A1A1A` starts at x=320.0, so the app's
largest depth event was a hard one-pixel step at 1.07:1. It has a 0.5pt
hairline now (1.50:1, no saturation), and the dead shadow tokens are
gone.

**Harness.** `panel_count` matched any element carrying the right label,
so the new "Everything" title — a StaticText — answered instead of the
panel's row, and `lens` reported a working filter as broken. Third label
collision in two days; it asks for the element TYPE now.

## 2026-09-01 — a card comes from the edge its button is on

Owner: *"some menus are popping up top down when the button is not at the
top"* (2026-08-31).

The workspace and filter cards fell from the top of the screen while the
buttons that opened them sat at the foot of the library panel — the
workspace button drawing a `chevron.down` the whole time.

**The rule was never wrong; the furniture moved.** The owner asked for a
top card on 2026-08-15 BECAUSE the workspace button was at the top then
(*"since the button is on top it would be more convenient have it
appearing at top also"*), and the button moved to the panel's foot a week
later with settings (team, 2026-08-22). The direction stayed behind,
hard-coded in the host's name.

So the edge is a parameter: `livTopSheet` is `livSheet(from:)`.
**Hard-coding a direction records an answer; taking it as a parameter
records the rule**, and the rule survives the furniture moving again. The
card squares itself against whichever edge it hangs from, puts its
grabber on that edge, and keeps that edge's safe area as space INSIDE it.
The note's ••• menu still comes from the top, because its button is
still up there: checked, not assumed.

**Harness.** `axe tap --label` REFUSES a label matching more than one
element, which is correct of it and left `open_first_note` with nothing
to aim at: every note in this box is "Untitled, <date>" and the create
check adds one per run, so three now share today's. It taps the centre of
the frame the tree just reported instead. That is not the coordinate ban
being broken — that ban is on GUESSED coordinates — it is the same
exception the library sliver already takes, and every attempt is still
checked by whether a document actually opened.

## 2026-08-31 — the calendar takes Notion's layout, and the month grid stops fighting

Owner: *"the calendar and especially day picker lags a lot… swiping right
opens the panel instead"*, and *"maybe replacing the current layout with
the notion layout would be better. also getting rid of the day picker or
doing it another way."*

**The gesture fight, first, because it was a real bug.** `startAllowed`
already vetoes a panel drag over a horizontally scrollable UIScrollView —
the right idea, and it missed the one place in the app that needed it:
the month pager is a SwiftUI HStack with an `.offset`, not a scroll view,
so nothing saw it. Every sideways swipe on the grid was claimed by the
window recognizer, which is why it opened the library, and why it felt
slow — both gestures ran on every touch move, and latching a panel
disables DeskHost's whole tree mid-drag. The calendar publishes its
pager's frame and the recognizer refuses to start inside it. Verified:
swiping right on the grid turns August to July with the panel shut. **A
frame rather than a view type, because the thing to exclude is a REGION
the calendar knows about and `PanelDrag.swift` cannot name.**

**The layout, second, and it dissolves that problem rather than patching
it.** Notion Calendar — read frame by frame from the recording — has no
month grid on its main screen at all: the title carries a chevron and
everything under it is the timeline. Ours took about 40% of the phone to
do the job you do least often. The grid is behind the title now, as a
card that closes the moment you pick a day, and the timeline went from
six visible hours to thirteen. **The grid is how you JUMP; the timeline
is what you READ**, and reading happens far more often.

The title says the DAY, because nothing else on the screen would
otherwise name it, and the chevron says the title is a way in. ‹ › step a
DAY rather than a month: on a one-day timeline "tomorrow" is the motion
you want, and without it tomorrow would mean opening the picker.

Also: the hour labels were clipped at the top of the scroll view. Half a
line is about 9pt at the new type scale and `labelRise` was still 6, so
"08:00" came out with its top sliced off; it is 9 now.

**Harness.** `simctl io screenshot` wedged the same way `axe` did the day
before, with the app at 0% CPU — the simulator's own services, cleared by
a restart. Written down because it is the second instrument in two days
to hang rather than answer.

## 2026-08-31 — the rest of the polish audit, and a harness that cannot hang

The remainder of the second surface pass, on the same brief: one mark per
meaning, one recipe per shape, and no control wearing a colour nobody
chose.

**The calendar.** The hour labels wrapped onto two lines the moment the
type scale went up — "18:00" no longer fitted the 38pt it was given
(`gutter - 8`) — so `CalClock.gutter` is 56 (was 46) and everything that
measures from it follows. **A column sized for text has to be sized WITH
the text.** The month grid drew up to sixty saturated dots in six kind
colours under its day numbers; at 4pt across a month nobody reads a hue,
so the dots say how BUSY in ink, and the kind language stays on the rows,
where a glyph is big enough to tell apart. A timeline block was a tinted
fill AND a stroke made by an opacity on the kind's colour — two devices
saying one thing, one of them a hue divided by hand where `tint()`
exists. It is Notion Calendar's shape now: a washed body with a 3pt bar
down its leading edge.

**Deleted outright.** `IconChip`, which filled a rounded square with the
kind's colour and stencilled the glyph out of it, one per row in three
lists — the references draw the glyph itself, which is `LivIcon`, which
this app already had. `PropertiesMark`, three overlapping rings with no
caller anywhere. And the 40x44 `text.quote` column in Links: a glyph you
could not press, standing in the space every other row gives its ✕.

**One recipe where there were two:** `LivGrabber` and `ConfirmPill` were
each drawn twice, byte for byte, in different types (standing rule 4).
And the grabber now tells the truth — every card in the app drew the
capsule that means "drag me away" and none of them could be dragged. They
can.

**One tint per family of verbs.** Tasks' swipe tray wore four saturated
colours for four ways of saying "move this to another day". Search's
facet chip is the last chip to stop filling itself with the accent.
Detail's status row, whose own comment said "display-only", stops wearing
the capsule this app uses for values you can act on.

**The harness cannot hang.** `axe` talks to the simulator's accessibility
server, and that server stalls: a describe-ui that takes 1.7s blocked for
over ten minutes while the app sat at 0% CPU with a healthy tree. Nothing
here had a time limit, so one stalled call took the whole run with it and
reported nothing — no pass, no fail, no clue, **which is the same fault
as a check that lies, in different clothes**. Every `axe` call is bounded
at 20s now. So is `open_first_note`, which retries the read-then-tap
pair: the label is read from one snapshot of the tree and used against
another, and twice a check failed on that race and passed on a re-run.

## 2026-08-31 — the second surface pass: a palette of our own, and an inbox you can empty

Owner: *"avoid gradients, default/system-looking colors, arbitrary
colors"* (2026-08-30), and *"things are too small in general"*
(2026-08-31) — the third time, after 2026-08-10 (*"text is too small…
could in places be a notch bigger"*) and 2026-08-18 (*"ui text is just
too small throughout"*).

Measured against three recordings in `~/Desktop/Throwaway/new` (Todoist,
Notion Calendar, Anytype) by counting pixels rather than by eye. The
number that carries the whole change: **saturated pixels are 0.58% of a
Todoist screen, 0.31% of Notion Calendar's, 0.01% of Anytype's. Liv's
Today was 1.05% and Tasks 1.85%** — two to six times as loud — and every
colour in the app was at 100% saturation, where the loudest routine
colour in any reference is Todoist's red at 57%. Today and Tasks are now
0.00% and 0.05%.

**The palette is ours.** This is the surface appearance rev 27 deferred
on 2026-08-16 (*"we should do the surface appearance last and
thoroughly"*), and `Theme.swift` predicted it twice — "when the surface
pass comes it changes the right-hand side of these lines and nothing
else", and the self-check's own promise that its floors would rise with
it. Both are kept.

- **Ground `#1A1A1A`, and it is NEUTRAL.** The references are all neutral
  and all lifted off black (Todoist `#1D1D1D`, Anytype `#1A1A1C`, Notion
  `#222222`); the system's dark ground is `#1C1C1E`, whose blue sits two
  points over its red and tinted every grey in the app.
- **Three elevation steps, about +9 per channel** (`#1A1A1A` → `#232323`
  → `#2C2C2C`), no shadow and no gradient — a step of tone does it, flat.
- **Three ink tiers and no more.** `#F5F5F5` (15.96:1 dark / 18.10:1
  light), `#A5A5A5` (7.07 / 7.23), `#828282` (4.53 / 4.61). Todoist's
  secondary text is `#9D9D9D` and Anytype's `#8D8D8F`; ours is one notch
  up, which is what 7:1 on this ground costs.
- **One accent, and it is not the device tint** (`#5B8BC2` dark,
  `#3167A5` light). Nothing exceeds 62% saturation and the marks are
  drawn small.
- **The floors went up with the palette**, as promised: `livPaletteSelfCheck`
  now requires every ink to clear 4.5:1 on its ground, the two read tiers
  7:1, every mark 3:1 for the first time, and no two marks to sit within
  0.12 of each other in RGB. That last search is why a task is
  violet-blue rather than sitting on top of the accent.

**One step above the platform.** Twice the answer to "too small" was to
move UP to Apple's own scale — body 15 → 17, the system's body — and it
still read small, so matching the platform is no longer the answer. Every
step goes one notch past iOS: caption 14, label 16, body 18, hero 32.
Measured against the references first, so this is not
bigger-because-asked: Todoist's row title is 17–18 and its screen title
34. The rows went up with the text (`LivRow.height` 56, `LivPanel.row`
57), because this file's own lesson from 2026-08-10 is that a bigger type
in the same box is simply more cramped.

**The Inbox is rebuilt on Todoist's geometry**, measured off a 3x crop:
an 18pt screen margin, a 24pt circle, 15pt of air, the words at 57, a
17pt title with a 13pt line under it. Ours is that shape at this app's
own 16pt margin — `LivRow.margin` 16, `.mark` 24, `.markGap` 14, and
`.text` 54, which is also `.hairline`. **The detail that does the work is
that the hairline starts at the WORDS, not at the screen edge**, which is
what makes the mark column read as a spine down the list rather than as
an indent. `LivRow.hairline` is derived from `LivRow.text` now, so they
cannot drift; it was 36 while no row's text began at 36.

- **The leading circle IS the accept.** The row carried two 44pt buttons
  on the right, so nine suggestions meant eighteen controls and a column
  of ticks down the edge. Todoist empties its inbox by ticking a circle
  on the left, and agreeing with a suggestion is the same motion.
  Accepting is not destructive so it acts at once; dismissing IS a
  discard, so it keeps its own control and still asks first. Drawn at 21,
  tapped at 24 wide by 44 tall.
- **Routing and dismissing both ask in the app's own bottom card.**
  Tapping a capture used to push four buttons INTO the list under the
  row, shoving everything below it down the screen; dismissing was a
  `.confirmationDialog`, which SwiftUI drew as an anchored popover lying
  across the bottom bar. `LivMenu` has supported `from: .bottom` since it
  was written (standing rule 4), and the card can say WHICH capture it is
  asking about, which four inline buttons never could.
- Route's rows measured 40pt — under Apple's 44 touch minimum, and the
  tightest list in the app, which is part of why they read as small.

**"Nothing springs" is lifted** (owner: *"i said somewhere that
animations should be used little. ignore that now. modern apps have
animations"*). The navigation rule stands — a surface replacing a surface
is still one easing, because a spring on a full-screen move reads as
wobble. What the lift buys is `LivMotion.list`, for things that arrive
and leave INSIDE a surface: ticking a suggestion used to make it vanish
and the rows below jump up a notch, and the motion is what tells you the
tick landed on the row you aimed at.

**Also:** six shadows in five recipes down to one token (`LivTheme.lift`,
for a block a finger has picked up), and three dead dot mechanisms,
`Hue.dot` among them — it hashed a property's NAME to one of five
colours, and its own comment admitted that meant nothing beyond "these
two say the same thing", so five hues down a settings list read as a code
with nothing to decode.

## 2026-08-31 — the properties become a card, and 57 cycles go with the panel

Owner, 2026-08-29: *"maybe card everywhere. start with one."*

**The properties panel is a sheet.** It was a full-height panel on the
trailing edge, the mirror image of the library on the leading one. It is
a card now — `.medium` and `.large` detents, a grabber, `LivTheme.surface`
behind it — which is the container a task's and an event's record card
already used. The app had two containers for one idea.

**Its door is the note's `•••` → Properties**, which is rev 5's door
(2026-08-02) doing its original job again; the edge gesture that used to
summon it is gone, so the `•••` is now the only way in. Anytype for iOS,
doing the same job at the same size, opens an object's properties the
same way: from the `•••`, as a sheet from the bottom with a grabber.

**What the old reference was, and why it is dropped.** A metadata panel
on the right was right while the desktop's own metadata lived in a right
rail. That is very early to be copying, and the goal is one mobile and
one desktop app that mirror each other rather than this one chasing that
one.

**One panel left, so the mirror code goes** (standing rule 6).
`PanelDrag.Which` had two cases and every member of the struct carried a
`which == .library ? … : …` for the mirror; the enum had one case left
and every ternary one live branch. Deleted with it: `toward`, the two-way
`claimPanel`, the two-way `closePanel`, the desk push that subtracted one
panel's progress from the other's, and `anyPanel`, which is now just
`libraryShown`. A card lies OVER the desk, so nothing pushes the desk but
the library.

**57 AttributeGraph cycles on every note open, all through one line.**
`updateUIView` runs while SwiftUI is part-way through its own update
pass; taking first responder from inside it calls UIKit back into
SwiftUI synchronously (`_UIHostingView._didChange(toFirstResponder:)` →
`runTransaction` → the graph), and the graph is asked for a value it is
already computing. Measured with a breakpoint on
`AG::Graph::print_cycle`: 57 backtraces, all carrying the same six
frames. A cycle wedges that subtree's update loop — bodies keep
evaluating with the right values while the pixels stop moving — which is
the failure this app has now been bitten by three times. The fix is one
hop of the main queue, with the guards re-checked on arrival so a note
closed in that hop cannot pull the keyboard back up.

**It gets a check, not a warning.** `drive.sh quiet` boots into Notes,
opens the first note, and fails if the cycle count moved at all. It
measures ONE action deliberately: the app boots with two cycles of its
own and has for as long as anyone has looked, so asserting the total
would make the check about that instead. `drive.sh check` only warned
about growth, and a warning is a thing you learn to scroll past.

**Also, in the same surface:** the kind chip under the note's title is
gone — a pill of 11pt lowercase with a dot in it, "• note", saying what
the surface around it already says (owner, 2026-08-18: *"eliminate
unnecessary small text and labels"*). You opened the panel from a note;
it is a note. The kind survives everywhere two kinds sit side by side:
the card's label in the switcher, a calendar block's colour, and the hue
of a chip that links to another entity.

## 2026-08-31 — areas grow

Owner, 2026-08-29: *"make sure areas are not fixed anymore."*

`design/what-liv-is-for.md` said in as many words that "Areas, fields and
kinds are ours, and they don't grow", and areas shipped as a select a
user could not add to. They can now: the value picker offers a create row
for a select, and minting the option is one verb the core already had. A
select needs its option to EXIST before a value can be written — the core
refuses a value with no matching option, and that refusal is right,
because a select's values are entities, not strings — so the picker
mints, then writes, and lets the write wait for the mint.

**The six remain what the app arrives with, and that was always the
load-bearing half**: you open Liv and do not have to design a system.
What goes is the refusal. The cost paragraph in that doc already admitted
the walls ("someone whose life doesn't divide into these six areas will
feel the walls"), and a create row is cheaper than that trade. The
desktop had gone further and stores `area` as free text with no list at
all, which is why its own query code carries a note about "clicking
'work' while 'Work' is included"; a named set you can extend sits between
the two.

**Fields and kinds are unchanged**: they still do not grow in daily use.
`what-liv-is-for.md` carries the amendment, dated and reasoned, rather
than being rewritten.

## 2026-08-31 — Tauri is dropped: this tree stops aiming at it

Owner, 2026-08-29: *"1. drop Tauri."*

`shell/ios/` is the only shell, and the desktop is no longer the app in
the `lovable-notes-hub` working copy. The goal of one mobile and one
desktop app that mirror each other stands; what the desktop WILL be is an
open question, and not open work.

**What this reverses** is the 2026-08-22 ruling — *"we can't break or
change how the tauri app works"*, *"both shells will share one core"* —
and the convergence plan written around it. That plan had one purpose: to
keep the Tauri app working while it moved onto this core. With the app
dropped the purpose is gone. `design/core.md` and `design/core-plan.md`
now carry a banner saying read the argument, not the schedule, and
`design/one-core.md` records that its own supersession has itself
expired.

**What did NOT change.** That working copy is still outside this repo, so
it is still ask-first, and the owner has said not to touch it. Dropping
it means this tree stops aiming at it, not that anyone goes and deletes
it. The deleted Mac shell and the planned WinUI port are still deleted;
reviving either needs the owner's word.

CLAUDE.md and the architecture-reviewer agent are corrected to say all of
this.

## 2026-08-29 — one desk: tools lose their planes

Every view had its own plane of tabs, so the bar's tab key counted "tabs
open in Calendar" — a number about a place there is one of. The switcher
over Today really did show two Todays beside a third card.

**A document is plural; a tool is singular.** You keep several documents
open and come back to them, so documents live on ONE desk that follows
you into every view. What a tool needs remembered is where you left it,
which is one token, not a list of them. The split was already there and
undeclared: `open(entity:)` was called with `.notes` at both of its call
sites, `park` only ever wrote positions, and the sweep read
`byFeature[.notes]` under a comment saying "only Notes holds entities".
Declaring it is the whole change. `openRoot` goes with the branch that
called it — it was the method that minted a second Today — and `newTab()`
no longer asks which view you are in. This amends phase 4 of
`design/tabs.md`, which is where the per-view planes were decided a week
earlier.

**Nothing saved was thrown away.** Measured on the device before and
after: five v2 planes holding 22 tabs — 12 distinct documents and 10
positions — became one desk of 12 documents and four tools remembering
their spot. Only the position you were ON in each view survives; the rest
were duplicates of a place there is one of. The v2 keys are left
readable, the same courtesy the 2026-08-22 migration paid v1.

**Two bugs this introduced, both caught before shipping.** `openDoc`
ignored `state` — free while each view had its own plane (Today's held
positions and never an entity) and wrong the moment one desk keeps its
active tab everywhere: `goBack()` from a note into Today reported the
note as still open. `-places.selfcheck` found it. And the desk
resurrected itself: the per-plane rule was "no key for an empty plane",
because "no plane" and "a plane with no tabs" had to be one state.
Carried over, an absent desk key means NOT YET MIGRATED — so emptying the
desk sent the next launch back through the v2 fold and brought back every
tab you had just closed. An empty desk now writes an empty key and says
so.

**The `+` makes what the place holds.** One tap, checked against the box
rather than the screen: a task in Tasks, an event on the day Calendar is
showing, a note in Notes, Inbox and Everything. Today and Tasks route
through `createRecord`, which already dated a task from
`desk.contextDay`, so this needed to know nothing about dates. The
five-item menu moved to a long press. Note creation cost two taps by
every route before this, including the thing you do most.

`axe` cannot generate a long press — a known-good shipping gesture
(Calendar's day cell) does not fire through it either — so that half was
verified with the simulator's own touch path: the menu came up and the
tap did not fire. `cmd_create` says so rather than leaving a silent gap.

**Also:** Calendar asks for `livHidesChrome` now. It is the one view that
never did, and it is the one the owner named for the bar always taking up
space — but the bar is not observably retiring there yet, so this is
wiring, not a fix.

**The harness.** `drive.sh desk` walks all six views asserting the count
on the bar does not move. It opens nothing: opening a note raises the
keyboard and the bar retires under one, so there would be no count to
read. The tour needed a real correction, not a relaxation — arriving at
Notes now lands on the DOCUMENT you had open, because the desk keeps its
active tab, which is the point of a tab. 404 Rust tests, ten suites, nine
drive checks.

## 2026-08-29 — the surface pass, and Notes gets its notes back

Seven annoyances the owner listed, the two side panels made one recipe,
and the first step of `design/tabs.md`'s correction. They arrived
together because they touch the same files.

**Notes' root is the list again.** From 2026-08-24 it was the tab grid,
on *"make sure it replaces notes list"*. Measured on the simulator four
days later, that arrangement hid the box: the grid draws `desk.liveTabs`,
so Notes showed EIGHT of the 134 notes in it and offered no route at all
to the other 126. A surface named after a thing has to contain it.
`NotesList` is restored from the commit that deleted it, with two changes
— the lens comes from `workspaces.admits` (the Swift parser it used to
filter through went to the core on 2026-08-27), and its bottom margin is
`LivBar.room` rather than a literal 88, which is why the bar sat on the
last row. The grid keeps its real job: it is the switcher the numbered
box opens. One is the shelf, the other is what is on the desk.

**Two things fell out of that.** The numbered box was dead on Notes' root
for one reason — you cannot open the grid on top of itself. With a list
underneath, the rule has no cause and is deleted rather than handled.
`TabSwitcher.asSurface` then had no `true` caller, so it and the four
branches it gated go too (standing rule 6). Which surfaced a gap: the
switcher NEVER had a marker except at that one call site, so the grid
opened from Today or Calendar was invisible to `drive.sh`. It carries
`LivOverlay.tabs` now — an overlay, because it covers a surface rather
than replacing one.

**The two panels are one panel.** The properties panel was a full-screen
curtain over a still desk; the library stopped short and pushed the desk
aside. They now differ in nothing but which edge they stand on:
`SidePanel` takes a `side`, both travel `LivPanel.width`, and the desk's
mask, its shadow and the wash that swallows touches all answer to
whichever is out. One `closePanel` serves the sliver's tap and its drag,
so neither decides for itself. `curtain` goes with it — it existed so the
bar and the pill could fade under a full-screen panel, and nothing fades
any more. (This is the recipe the 2026-08-31 properties card then cuts in
half, two days later.)

**The seven.**

1. The top doors wear the bar's glass in a 44pt circle. Bare, they read
   as loose icons rather than controls — which reverses 2026-08-18's
   "fewer giant rounded buttons", on the owner's word.
2. The library door says it is open by WIDENING its column instead of
   turning blue. A tint says "selected", and a door standing open is not
   a selection.
3. `PanelMark`'s corner radius drops to 0.20 of its size, because 0.30
   drew a squircle.
4. The desk's leading corners go square while a panel is out: a curve
   there pulls away from the seam and leaves a wedge of panel showing,
   which is the gap the owner saw in light mode.
5. `LivTopScrim` was one fixed height doing two jobs. The panel reserved
   a 52pt chrome row it has no chrome for; the tab grid reserved the same
   band AND painted over its own first row. The grid's first card moved
   from y=187 to y=68.
6. `New tab` in the grid makes a note. It used to open the create menu,
   which is the `+` key's job and a different question.
7. The numbered box glyph: `pen.box(3.5, 4.5, 17, 16)` centred at y=12.5
   on a canvas whose centre is 12, with a `.offset(y: size * 0.04)`
   overshooting the correction. Box re-centred at 18x17, offset deleted —
   measured off the pixels at +0.0 on both axes.

**And dark mode takes the next rung of the system's own ramp** (#000 →
#1C1C1E → #2C2C2E) rather than a mixed value, so the steps between
surfaces are unchanged. Light is untouched. (Two days later the second
surface pass replaces this ground entirely with `#1A1A1A`.)

**The harness.** `drive.sh grid` asserted the arrangement this change
reverses. Rewritten to guard the hole instead: Notes must list MORE rows
than there are open tabs. Calibrated — restoring the grid as root gives
"Notes lists 0 rows while 9 tabs are open". `drive.sh panel` now runs one
body twice, mirrored, so the panel that only just became testable is
tested. Everything it asserts is geometry: a closed panel stays mounted
and moves off screen, so "is its marker there" answers a different
question. 404 Rust tests, ten suites, seven drive checks.

## 2026-08-28 — a harness that cannot lie about a green run

`suites.sh` runs the ten launch-flag self-checks; `drive.sh` drives the
running app and asserts what is ON SCREEN. Both existed in the working
tree already. What this records is what had to be fixed before either was
worth believing.

**They launched whatever was already installed.** `./build.sh` with no
argument only COMPILES, and neither script installed, so both tested
whatever build happened to be on the simulator. Proved by breaking one
assertion on purpose: all ten suites still printed PASS. Both now install
`build/Liv.app` and refuse to run against a bundle older than the
sources. Break an assertion and watch it fail before trusting a green run
— every check here was calibrated that way.

**Four more ways it could report on something it never measured.**

- `scan()` swallowed every Python exception, so a typo in a reader was
  indistinguishable from an empty screen. It lets tracebacks through now.
- `bar_keys` prints ONE line of JSON and the boot gate counted its LINES
  — 1 for a full bar, 1 for an empty one. `bar_count` counts the array.
- `panel_open` detected the library by the word "Trash". The settings
  sheet carries that word too, so any check that left settings open told
  every later check the panel was up. Panels now carry `.livOverlay(…)` —
  the same invisible identifier `.livSurface()` uses, a different prefix
  so the one-surface rule still holds. Ask the structure, never the
  content.
- `suites.sh`'s "no verdict — the suite did not run at all" could never
  print: a pipeline's status is `sed`'s, and `sed` succeeds on empty
  input. The one case it exists for showed a bare FAIL instead.

**Boot means the whole screen.** Three separate "flaky" failures were
checks inheriting the screen the previous check walked away from. Every
asserting check now starts from a launch; `boot` waits for the BAR, not
just the surface marker, and refuses to proceed if any overlay is still
up. `cmd_tap` retries for three seconds before calling a label absent —
"not on screen yet" and "not on screen" are different answers.

**New check: `drive.sh lens`.** Turn a saved filter on, assert the count
moves. It is the only thing that can see whether the shell asks the core
for a lens and does anything with the answer; `cargo test` proves the
core is right and stops at the ABI.

**CLAUDE.md's own numbers had drifted**: 56 FFI verbs where there are 59,
and standing rule 1 quoting 38 calls over 32 verbs where it is 53 over
41. The architecture-reviewer agent carried a third, differently wrong
count, and still called the macOS shell "parked" nine days after it was
deleted.

**Also, the same kind of untrue claim, in `.gitignore`.** The "built
binaries — artifacts, not source" comment had no pattern under it: the
`/shell/macos/build/` line went out with the macOS shell on 2026-08-19
and the comment stayed, which reads as a rule being enforced. It was not.
708MB of compiled `shell/macos/build/lotus` is in this history at ~10MB
per commit, and nothing can remove it without rewriting every hash, so
restoring the line only stops the next one — the iOS rule below it is
what does real work now. Found while extracting one file into a
standalone repo, where stripping that path took the pack from 87 MiB to
2.8 MiB.

## 2026-08-28 — tabs are the container, and the core answers the queries

Phases 4 and 5 of `design/tabs.md` (per-view planes, and one Inactive
shelf across all of them — that doc carries what each phase decided), the
reversal the owner asked for after sending the Notesnook and Obsidian
recordings, and the Swift parser's deletion. They arrived together
because they touch the same files; the build does not bisect below this
point.

**The tab view is the container, not a pane.** Owner, 2026-08-24: *"make
sure it replaces notes list."* `Notes.swift` is gone. The grid IS Notes'
root, drawn as the surface rather than laid over it, so the grid can no
longer be opened on top of itself and the old "‹ Notes" back has nothing
to point at. One plane per VIEW per workspace (`planeKey` v2); the
pre-2026-08-22 single-plane key is read once, to become the Notes plane.
(Reversed the next day — see 2026-08-29. Notes' root is the list again;
the grid stays as the switcher.)

**The panel is not full screen.** Owner: *"Panel should not be full
screen!"* The library stops at `LivPanel.width` and leaves a sliver of
the desk: `peek` is a fixed 100pt, so 330 of a 430pt screen, which is
what the reference measures. The sliver blocks touches and takes both a
tap and a drag to close — an overlay swallows the window recognizer's
touch, so the drag has to be its own gesture, not the host's. The desk
travels again with it.

**The bar is a browser's, literally.** Five keys, one row: back, forward,
search, new, tabs. Disabled keys are drawn disabled rather than hidden,
so the row never reflows under a thumb.

**One parser, and it is not here** (standing rule 4). `LivQuery`,
`LivTerm`, `parse`, `matches`, `tokenize`, `splitQualifier` and
`stampSummary` are deleted. What survives is `LivTerms`: spell a term,
read one back, replace one, build the stamp — text only, never meaning.
The lens is `liv_query_ids_at`; a draft query is `liv_lex`;
`Workspace.admits` reads the answer and decides nothing. The self-check
could not simply shrink — an empty failure list prints PASS — so it was
rewritten against what the shell still owns. All forty-one of its old
assertions tested the parser that left.

**Subjects is tags.** Owner: *"rename subjects to tags."* The engine
already said `tags`; the shell said `subjects`, which made three names
for one field. The property migrates, and so do saved queries —
`renameInQueries` rewrites qualifier KEYS only, leaving the word as free
text alone. Without it the `foo` filter kept `subjects:psychopathy`, and
an unresolvable property used to become a required word: the filter
silently matched nothing.

**Wired, not written.** Facets were computed by the core on every search
since 2026-08-26 and nothing decoded them. Five `liv_vault_*` verbs
backed the folder promise and no client called one. Both now reach the
screen.

**The panel counts follow the lens.** With "Work" active the panel said
"Notes 127" over a list showing only Work's notes. It counts through the
same `admits` gate every surface uses — and once per render, not once per
row, which its own comment always claimed and never did.

Ten suites and seven `drive.sh` checks pass. Nothing outside
`shell/ios`.

## 2026-08-19 — Scan text: a page becomes a note

Owner: *"do the ocr on the camera door"*, then — after being shown that
storing words on the photo makes them searchable but unreadable —
*"Actually don't know who is going to care about the photo itself. You
probably want the best presentation of what you've scanned"*, and
finally *"scan into a note, drop the photo."*

That is **Apple Notes' Scan Text**, exactly: camera → the characters
cross over → no image asset is kept. Keep and Google Docs keep the
picture and append the words beside it; OneNote only fills the
clipboard. Nobody keeps a photo you took in order to read it.

**The shape.** `Scan text` sits beside the shutter in the camera tray —
two intents in one row: the shutter KEEPS a photo, Scan text keeps the
WORDS and files nothing. Vision reads the frame on the device, a note is
born holding what it read, and you land in the editor. No file is
written, no photo entity exists, and the note titles itself from its
first line, which is the core's own rule for anything unnamed (and the
one first-party precedent for content-derived naming — Apple titles a
note by its first line, and renames no image ever).

**The camera had no door.** Nothing has set `cameraShown` since the tab
plane that used to hold the button was deleted, so the whole flow was
unreachable dead UI. `Scan text` is now a row in the `+` menu, which is
also how plain photo capture became reachable again.

**Three defects found before shipping, not after.**

1. *Orientation.* `VNImageRequestHandler(cgImage:)` has no orientation
   and treats every buffer as upright, while `UIImage(...)?.cgImage`
   hands back the RAW sensor pixels — so a page photographed in portrait
   arrives sideways, loses its small glyphs, and comes back as gibberish
   for the mirrored EXIF values. The reverted August 18 code had exactly
   this bug. The fix is `VNImageRequestHandler(data:)`, which reads the
   EXIF tag itself; passing an explicit `orientation:` would be WORSE,
   because it supersedes the tag rather than combining with it. Measured
   on the simulator across all eight EXIF values: the data handler
   matches an upright reference every time, the naive form fails seven
   times out of eight.
2. *Language.* The reverted code asked for `sv-SE`, which does not exist
   on an iOS 17 target — and Vision neither throws nor warns for an
   unsupported language, it just runs a model you did not choose. The
   list is now intersected with `supportedRecognitionLanguages()` at
   runtime, so Swedish arrives when the OS has it and nothing breaks
   when it does not. `revision` is pinned to 3 for the same class of
   reason: the default follows the SDK you LINK against, not the phone.
3. *The wrong parser.* `SpanText.textToSpans` is the markdown grammar for
   what a person typed. It DELETES a line of three or more dashes (the
   marker IS the line) — the separator on every receipt, form and
   letterhead — and turns a printed `- [ ]` into a real task in your
   Tasks list. Recognised characters are not markdown. `SpanText.
   plainSpans` is the literal reader, the exact mirror of the core's
   `content::plain_spans`; it is not a second grammar but the absence of
   one. Verified against a photographed receipt: every line stored as
   typed, all Body blocks, no phantom task.

Also: a refused content write used to leave a blank note behind. It now
trashes it.

**Known limit, not fixed here.** `CameraEngine` never sets the capture
connection's rotation, and the app is portrait-locked — so a page shot
with the phone turned sideways gets an upright EXIF tag and Vision reads
it rotated. Scanning a page in portrait, which is the normal posture, is
unaffected. The fix belongs at capture and would change the existing
photo path too, which cannot be verified without a device; left for a
batch that can test it.


## 2026-08-18 — Today: the late pile folds

Owner: *"so much LATE stuff i can't see what's for today."* Thirteen late
rows at 44pt is 570pt — the whole phone — so the day itself started below
the fold and Today answered the wrong question.

LATE is now a FOLD. It keeps its red dot and its count, so nothing is
hidden and the number is still the headline; the rows are one tap
behind it. It arrives folded above three late tasks and open at or below
that, because a couple of late things are worth seeing and a pile of
them is a wall. Your tap wins for the rest of the session. Same collapse
control the done-today row on this screen already used (standing rule 4).

Precedent, found after the fact: **Google Calendar does exactly this** —
overdue tasks collapse into one row showing the count, expandable, on by
default. The known failure mode is Todoist's: a collapsed section reads
as an EMPTY section, and people stop finding their overdue work. The red
dot and the count are what guard against that, so if the pile ever stops
being noticed, that is the thing to make louder — not a reason to unfold
it. Owner is testing before anything else changes here.

## 2026-08-18 — Quick Capture: built, then reverted

Built and taken out the same day. Recorded so nobody builds it again
without knowing why it went.

**What it was.** The `+` stopped opening the four-kind create menu and
opened a sheet instead: one multi-line field with the keyboard already
up, a bottom row of `[camera] [paperclip] … Capture ⌄ [Save]`, and a
kind control defaulting to **Capture** — an untyped scrap that lands
unrouted for the Inbox's Route lens to give an address later. The camera
ran on-device Vision OCR into the body and linked the photo back with a
`related` cell.

**Why it went.** Owner: *"I don't like the capture addition. Does
ClickUp have anything like it?"* — and then, decisively, *"I just don't
understand what you do with a capture later?"*

The research answered the first question against it. ClickUp mobile's
`+` is a **menu of kinds** (Task, Doc, Reminder, Note, Chat message,
Channel): you pick what the thing is before you can type a word, which
is exactly what Liv already had. ClickUp's task form requires a name
**and a location** — the List name sits at the top — and their docs state
plainly that a task cannot exist outside a List. Their Inbox is a
notification centre, not a bin for captures. The one genuinely unfiled
thing is a Reminder, and the docs describe no way to promote one into a
task: a capture channel with no drain. The nearest real precedent is
**Notepad** — a private scratchpad with "Convert to task" — but it is a
separate tool reached from the avatar or the More menu, never the `+`.

The owner's own reason is the sharper one, and it is about this app, not
about ClickUp: *"the capture editor is limiting and duplicated for notes.
we should test if people actually struggle without capture."* A cramped
`TextEditor` inside a sheet is a worse editor than the editor, and it sat
in front of the app's most-used button. And the evidence was already on
screen: **25 items in Route**. An inbox only pays for itself if it gets
emptied.

**What went:** `Capture.swift` (the sheet, `CaptureKind`, `CaptureOCR`),
`DeskModel.captureShown`, the App-level sheet, and the camera's
`scanning`/`onShot` additions. Restored: `createMenu()`, `createNote()`,
`createRecord(event:)` and the desk's file importer, exactly as they
were.

**What stayed, on purpose:** the `services` fix the sheet exposed.
`capture()` had stored its whole text as ONE flat span, so a multi-line
capture named itself with its entire body in every list.
`content::plain_spans` is now the one text→spans grammar and `capture`
uses it. That verb is still live — the CLI's `liv add`, the share
extension, and search's create row all go through it — so the fix
outlives the sheet that found it.

**Not re-landed, and worth a decision later:** the on-device OCR. The
owner had said the camera's only use is *"ocr scanning"*, and it worked.
But the shape it shipped in was wrong, and the research says so: **no
first-party app reads a photo into a body silently.** Apple Notes makes
you invoke Scan Text, select the text, then Insert; Google Keep needs a
per-image "Grab image text"; Todoist's image capture shows a draft you
edit before anything is created. (The one counterexample is a community
Obsidian plugin, not a shipping first-party app.) Three shipped models
to choose between if it comes back: insert on an explicit command,
index for search only, or a reviewable draft before it commits. Its home
is the camera door either way, not a capture.

**Evidence caveat, recorded honestly.** `help.clickup.com` returned 403
to one researcher, so the claim about the MOBILE plus menu specifically
rests on ClickUp's own prose rather than screenshots; other findings did
fetch official help screenshots and shipped web-bundle strings. Two
things soften the "ClickUp does not do this" line without overturning
it: ClickUp's WEB create modal does open on a kind tab bar (Task | Doc |
Reminder | Whiteboard | Dashboard) inside the sheet, and its mobile task
modal has a lower-left button that sets status and task type next to
Create at lower-right. So a kind control inside a create sheet is not
foreign to ClickUp — it is just not what their phone's `+` does.

## 2026-08-18 — four surfaces, laid out from the blueprints

Owner: *"take inspiration from blueprints regarding layout of today,
inbox, tasks, and everything"* — and, before that: *"I should do layout →
app functions → UI polish."* So this is layout only; nothing here is
paint, and the functions the blueprints describe but the app does not
have (a widget board, the capture panel, task lenses, saved views) are
named at the end rather than half-built.

**Inbox — the blueprint's two questions** (BP-5 B1). Route and Tidy are
tabs now, counted, instead of two section labels stacked in one scroll —
a long Route list used to bury the clerk's suggestions under it. And the
orphan row is one line again: icon, title, age. **The four verbs left
every row**: BP-5 puts the routing question on the row you PICKED, and
eight captures × four buttons was thirty-two controls on one screen.
Tapping a row opens Task · Event · Note · Link underneath it, one row at
a time. Empty state is the blueprint's own words: "Inbox zero — nothing
waiting."

**Today — "What next"** (BP-8's widget of that name). Under the
timeline: open tasks carrying NO date, five at most, each with its
anchor. The timeline answers *when*; this answers *what*, which is the
object-based ordering the owner asked for — and without it an undated
commitment was invisible until you went hunting in Tasks.

**Everything and Tasks — the row budget.** BP-3 states it: "type icon ·
title · anchor chip · status dot · modified", and "empty fields do not
render". Everything's rows carried three chips before the surface pass
and none after it; they carry ONE now — project → subject → people →
area, the blueprint's order, and nothing when there is none. Tasks was
showing up to three; BP-6 caps it at one for the same reason ("never a
status chip — the column already carries status").

**Not built, deliberately** (function, not layout): the dashboard widget
board and its gallery, the Quick Capture panel with its destination line,
the merge suggestion and commit bar in Route, Tasks' other lenses
(Cards/Board/Schedule) and the saved-view object, and the count badge on
the bar's Inbox key.

## 2026-08-18 — the day is the home, and the app stops whispering

Owner: *"do the menu reorder and launch on today… the left panel
button's 'hamburger' icon is just ugly… ui text is just too small
throughout, and dimmed."*

**Today leads, and the app opens on it.** The Go-to menu is ordered like
a day — Today, Docs, Inbox, Calendar, Tasks, Everything — and launch
lands on Today instead of resuming the last document. Resuming a
document is what a notes app does; planning is what this one is for.
Nothing is lost: the document you were in is still loaded and is the
first row of Docs.

Note what did NOT need building: coming back from a note to Today. The
labelled back has said "‹ Today" since the tabs went, because opening a
document pushes the place you came from — that is the whole reason the
bar's ‹ › could be deleted.

**The type scale is the platform's.** `body` was 15, which is iOS's
*subheadline*, and every row, value and button sat on it; the app read
as a dense desktop tool shrunk onto a phone. It is 17 now, with the rest
of the scale moved up a step behind it (label 15, caption 13, title 20,
display 24). Rows grew with the text: 48 → 52.

**And it stops dimming what you have to read.** Titles, the bar's keys,
the workspace, the panel's rows and the way-back are all at full
strength; secondary ink is for facts beside the words, and the tertiary
tier is furniture only. One layout bug fell out of the bigger digits and
is fixed: the agenda's time column was cut for 15pt and wrapped "09:00"
onto two lines.

**The panel door is DRAWN, not borrowed** (`PanelMark`, Glyph.swift).
Three stacked bars was the generic web hamburger; `sidebar.left` was the
right idea carrying decoration; `rectangle.leftthird.inset.filled` was
plain but a WINDOW — wide, squarish corners, a Mac's proportions (owner,
2026-08-18: "a bit rounder. it looks like a desktop icon"). This is the
same idea at a phone's proportions and a phone's radius: a nearly square
plate, generously rounded, one rounded bar inside its left edge, and
nothing else. Drawing it is also the only way to control the radius —
which was the whole ask.

## 2026-08-18 — the surface pass, second half: lists, the bar, the wide controls

Owner: *"the surface design still feels very unpolished and overly
AI-generated… clean, modern, cohesive… Take inspiration—match their
level of restraint and polish"*, with ClickUp, Linear, Notion and Safari
named, and: *"Don't add UI to make things feel more polished. The
opposite: remove anything unnecessary."*

Four decisions were the owner's, asked before building: colour only in
mixed lists, no repeated view titles, the bar split like ClickUp's, and
the workspace as plain text.

**One row for every list** (`Rows.swift`). One line of text at ordinary
size, a 19pt glyph, the quietest possible fact on the right, and a
hairline that starts where the text starts. No chevrons, no counts, no
second line of chips. **Colour only where it tells things apart**: Docs
is all documents, so its glyph is monochrome; Everything, Today and the
calendar mix kinds, so the kind colour stays there. The filled 26pt
carved chips are gone from every list — a column of bright squares was
the loudest thing on screen.

**No view repeats its own name.** Docs, Everything, Tasks and the Inbox
lost their headings and counts (the bar names the state); Today keeps
its DATE and the calendar its month, because those are facts, not
labels. Today also lost the second day heading under the strip.

**The bar is two objects**, ClickUp's arrangement: a glass capsule
holding the state key and search, and the `+` as its own round button
beside it. Create is the only key there that is not navigation.

**The wide controls are gone.** The workspace is plain text with a small
chevron; the way out of a document is a plain "‹ Docs". Both wore glass
capsules that read as buttons-about-nothing. Icon controls keep their
glass circles — those were never the problem.

**Everything's slice picker** is three outlined pills instead of a
segmented control inside a filled well, and Today's reschedule verb is
plain accent text instead of eleven filled capsules down a column.

**Not in this pass**, and the honest list of what still looks unfinished:
the properties panel and the record card, the search screen, the Inbox's
route cards, and the editor's own chrome.

## 2026-08-18 — tabs are gone: Docs is a list, and one document at a time

Owner: *"what should we do about document tabs to fit the new model? what
do we do about the bottom bar looking like it's for regular tab
management?"* — and, on the answer: *"build it."*

**Docs is a list of your notes, ordered by what you touched last.** That
ordering is the whole reason it can beat a grid of open tabs: the note
you were editing ten minutes ago is row one, so "get me back to that
one" is the same two taps the switcher cost — and unlike the grid it
also reaches the note you did not leave open. The signal is the log's
own: a new `recency` field on the wire (the seq of the last transaction
that touched the entity), which is the same key search already tiebreaks
with, so the two orders can never disagree. Purely additive, with a test
and a cost test at the seam.

**One document at a time.** Opening a note replaces what was open; the
id is remembered per workspace, so a relaunch resumes where you were,
and the first launch after this takes that id out of the old tab plane
so nobody boots empty. Deleted with the tabs: the switcher grid, the
Inactive shelf and its Settings picker, the per-workspace tab planes,
saved layouts' only door, `DeskTab`, `LivTabs`, and 605 lines of
Tabs.swift. The core's layer verbs stay — the ABI is additive-only —
but nothing calls them now.

**The bar is three keys: where you are · search · +.** The first NAMES
the state and opens the Go-to menu (Docs · Today · Inbox · Calendar ·
Tasks · Everything, the current one ticked). The history keys went with
the tabs they stepped through — they were a stack of tab UUIDs, alive
only while their tab was open, which is nothing once tabs are gone.

**A document's own chrome is "‹ Docs" and the •••.** The back is
labelled with where it goes — the list, or Today, or the note you
followed a link out of — which is an ordinary list→detail stack and
makes "a document is inside Docs" a fact of the navigation rather than a
highlight in a menu. The library door and the workspace button belong to
a state's ROOT, so they step aside inside a document.

**Three hazards the change made routine, fixed in the same batch.** The
editor is now torn down every time you leave a document, so: `stop()`
passes a completion to `flush()` (without one, a save already in flight
queued nothing and the keystrokes typed during it went with the
teardown); every leave calls `endEditing()` first (the title commits on
resign, so a rename typed a second earlier used to die with the
surface); and the caret is remembered per note for the session and
restored on the way back, with the note scrolled to it. The caret, not a
scroll offset in points — the text arrives asynchronously and the
title's inset is written a frame later, so a remembered offset lands
somewhere else.

**Found while measuring, fixed:** the snapshot's proposal ordinal was
quadratic in the pending queue (a Vec rescanned per proposal). On a box
whose clerk had proposed 400 times it was 430ms of a 450ms snapshot. It
is a counter now, and the cost test that caught it lives at the seam.
Worth the owner's attention separately: 400 notes with the SAME name
make the clerk propose ~400 merges, and that queue is what made the box
slow — the assist sweep, not the snapshot.

**Also:** `-tabs.selfcheck` becomes `-places.selfcheck` (where you are,
how you got there, and that the way-back stack is capped); the tab
suite's day-arithmetic checks moved into the calendar suite, where
`Civil.daysBetween` still has a caller.

## 2026-08-17 — every state opens on the right, and Docs is one of them

Owner: *"Some views still open above the notes and then slide down, which
makes the different states in the left panel feel inconsistent. Each
state should be treated equally as something opening on the right, and
the notes should remain separate."* — and: the status-bar corners beside
the camera should not be grey.

**There is no closing a view any more.** A view was a lid: it arrived
over the notes and slid down off them, which made Docs the ground and
the other five states things stacked on it. Now every state is one of
the menu's rows and the way out of one is to pick another — including
Docs. The glass chevron and the drag-down band are both gone, so the top
row over a view is the library door and the workspace, and nothing else;
the ••• belongs to Docs, which is the only state with a document in it.

**The transition is lateral in both directions** (`.move(edge:
.trailing)`). Picked from the menu, the strip's own travel is still the
whole motion — this layer is not animated then — so what is left is the
case with no panel open: a notification or a boot flag, which now slides
in from the right like everything else.

**The corners.** Verified on the simulator in all six states — desk,
menu, Today, calendar, search, tab grid: the pixel beside the camera is
the same as the body's, so every surface already reaches into that band
after yesterday's `ignoresSafeArea` work. The grey the owner is seeing is
the build on the phone, which is three commits behind (the device has
been unreachable to `devicectl` since the links batch); if it survives
this build, it is a device-only difference and needs a screenshot.

**Kept, deliberately:** the notes stay mounted behind an open view
rather than being swapped out. It costs nothing on screen — nothing
slides over or off them now — and it keeps the editor's caret and scroll
where you left them.

## 2026-08-17 — the menu is one list, under the same fading top

Owner: *"in the left sidebar it is opaque at the top (do the same as you
did for views here). Settings being fixed when you scroll and the bar
inside here means something hasn't been thought through here."*

**The panels get a view's top.** Both of them: 56pt of empty band with a
hairline under it is gone, and in its place the same fading scrim a view
uses — the list runs under the clock and fades out behind it. That band
was drawing a line that read as a bar which was not one.

**One fixed thing at the foot, not two.** Settings was pinned below the
scroll while the global bar floated over it — two layers stacked at the
bottom of one list, and the pinned one was the app's smallest door.
Settings is now the last ROW of the menu, under an "App" heading, and
the list keeps 58pt of room for the bar, exactly as a view does. The
bar is the one thing that belongs to the whole app, so it is the one
thing that stays.

The properties panel inherits both, which fixes something nobody had
reported: its last rows used to sit under the bar.

## 2026-08-17 — the whole screen, with the controls floating on it

Owner: *"make all top buttons have a liquid glass style like the bar.
The screen should also extend to the very top where time and battery
indicators are and all the top buttons should float above."*

**One glass, everywhere.** `LivGlass` takes any shape, so the bar's
capsule, the two door circles and the workspace button are now the same
surface — Liquid Glass on iOS 26, a material capsule below it. The
workspace button had no ground at all before; it is a control like the
others, so it wears one. The library door's ON state is tinted glass
rather than a flat accent fill.

**Every surface runs to the very top.** The desk, the views and both
panels ignore the top safe area, so words and rows pass under the clock
and the battery. What must clear the floating controls keeps
`LivRow.topInset` — the status bar plus the 56pt band — and that is one
token, not a number spread over five files.

**The soft edge.** Content under a clock is unreadable without one, so
the top band fades from the ground colour to nothing: solid where the
time is, gone by the bottom of the controls. It belongs to the SURFACE
(a view hands it to `safeAreaInset`, which is also what reserves the
room; the desk overlays it on the words) — as its own layer in the
desk's stack it swallowed the library door's taps, whatever
`allowsHitTesting` said. Found live, and the reason is recorded in
`LivTopScrim`.

**The view's band is gone.** Closing a view is a glass chevron in the
top row, in the corner the ••• uses on the desk — one place for the way
out, whichever surface is in front — and a drag down in that band still
closes.

Also found live: `.glassEffect(.regular.interactive())` on a button
stops it firing. The plain variant is what ships.

## 2026-08-17 — one row for every card

Owner: *"The slide-in workspace card has a different style from the
'New' card for example. Like the latter more since it has bigger text
and looks simpler."*

There were two row styles for the same job. The `+` menu drew its list
at title size with a 24pt glyph and a hairline inset past it; the
workspace card drew its own at body size with an 18pt glyph, chips under
each name and a hairline under every line. One list of things to choose
from, drawn two ways, is what standing rule 4 exists to stop — so there
is **one row now** (`LivMenuRow`) and **one title** (`LivMenuTitle`),
and the plainer, larger one won.

The workspace card is that row throughout: "Workspace" in the menu's own
title, All and each workspace with its emoji or ring, a checkmark on the
one you are in, "New workspace…" in the accent. The two cards differ in
exactly one thing now, which is the edge they hang from — the workspace
card from the top, where its button is, and the create menu from the
bottom, where its key is.

**Gone with the smaller type:** the lens chips under each workspace
name. A workspace's lens is still on screen where it acts — the filter
chip in every view's header, and the filters in the menu — but if you
want to see at a glance what each workspace keeps to, say so and it
comes back as a second line.

## 2026-08-17 — one strip: the menu on the left, everything else to its right

Owner: *"Have it so that you move from the bar to the right and into the
view. Might be fitting to now make the left panel parked on the right
and have you move to / from it. Instead of a dot, it is clearer to have
a highlighted row."*

**The library pushes again.** It is a PLACE — the app's primary menu —
so it and the surface in front are one horizontal strip: the menu is
parked off the left edge, the surface waits off screen to the right
while you choose, and going between them is travel. `deskShift` and
`deskTravel` are back, exactly as they were on 2026-08-15 before the
strip was withdrawn with the surface work it arrived in. The PROPERTIES
panel is unchanged — it is about the note you are looking at, so it
stays a curtain over a surface that does not move.

**A view arrives from the right, and that move is the strip's own.**
Picking a row sets the view without animating this layer, because the
surface travelling back in from the right already IS the motion — a
slide inside a slide would have shown the desk arriving first and the
view catching up at the end. A view summoned with no panel open (a
notification, a boot flag) still animates itself in from the right, and
every view leaves DOWNWARDS, the way the band's drag sends it.

**The bar does not travel.** It is four global actions, so it stays
where it is while the world moves under it — Safari's bar over a page
that slides away. The menu's pinned Settings row keeps its own room
under it.

**A lit row, not a dot.** Where you are is the row itself: filled
ground, semibold label, its icon at full strength. Saved filters use the
same mark for "this lens is on". The accent dot is gone — a dot is a
mark you have to learn.

## 2026-08-17 — global actions below, the whole app in the sidebar

Owner: *"The ultimate goal is to clearly separate global actions from
global navigation/state, while keeping the individual views focused on
their own content."* — and: *"the main problem with our first layout was
treating Docs as the primary view."*

**The bar is four keys: ‹ › search +.** The views key is gone from it.
It is Safari's bar now — a floating capsule of Liquid Glass (iOS 26's
`glassEffect`, a material capsule below that), which reverses
2026-08-01's "solid, never a blur": the reason then was that a body
reading through the bar looked like a bug, and Liquid Glass is the
platform's own answer to exactly that. It still steps aside while the
keyboard is up.

**The sidebar is the app's primary menu.** Views · Docs (with the count
the tab square used to carry) · Today · Inbox, then This workspace ·
Calendar · Tasks · Everything, then Filters, then Settings at the foot.
A dot marks where you are. This is the deliberate reversal of yesterday
— the views were briefly a key on the bar — and the split is now the one
the owner drew: **global ACTIONS below, global STATE and view selection
on the left.**

**Docs is a view like the others**, first in the list because it is
where the words are. Pressed from another view it takes you back to the
desk; pressed while you are already on the desk it opens the grid of
what you have open — the list that row counts.

**A view now lives inside the desk, under the doors.** It used to be a
layer above everything, which was fine while the bar could reach every
view; with the menu on the left, a view that covered the library door
was a cul-de-sac. So the library door and the workspace button float
over a view exactly as they do over a note, in the same place, and the
view's band keeps only the way out. The ••• is a document's menu, so it
stays hidden over a view.

**Answering the owner's question — no per-view create shortcut.** All
creation goes through the one `+`. The tab grid's "New tab" tile is not
a second door: it summons that same create menu. `LivAddButton`, the
floating key Today and Tasks carried for one day, is deleted.

**Open:** the grid still says "3 tabs" while the sidebar row says "Docs
3" — one thing, two words, and the owner's word is Docs.

## 2026-08-17 — one link mechanism, two doors, both directions

Owner: *"'Add notes…' in properties (as with tasks). There is already an
editor. I think links should achieve this. Speaking of which, we should
have a link property as an alternative to inline `[[]]` links. Both
methods should use the same link mechanism and under properties it
should be possible to view back/forward links."*

**The mechanism was already one.** A `[[ ]]` typed in a body is a `Ref`
span inside the content cell; a link picked in properties is a `related`
cell. Both are `Value::targets()`, so the core has indexed both, in both
directions, since the beginning — `Store::backlinks` (core/src/store.rs).
Nothing about the data model changed. What was missing was a reader and
a way to see it: nothing above the core had ever called that index, and
no `liv_*` verb exposed it.

**New: `services::links::links(store, id)`** — the one reader, with the
rules in one place. Outgoing = `related` cells then body refs in reading
order, deduped (a target picked AND typed is one row, and the removable
one wins). Incoming = one index lookup. Filing is not a link: `area`,
`project`, `people` and `type` are references too, and a "linked from"
list that swallowed every filed note would say nothing. Backstage
furniture is not a link either — a saved layout holds its tabs as
`related` cells and must never read as "linked from". 10 tests, plus a
COST test: a 4x box must not make one entity's link read 4x slower
(the first version of that test failed at 7x and found its own bug).

**New FFI verb (purely additive, flagged): `liv_links_at(path, id)`** →
`{"out":[…],"in":[…]}`, each row `{id,name,kinds,property,from_body}`.

**Properties gains a Links section**, on notes and records alike (one
component, both homes). Rows carry the target's own kind chip and title —
the same helpers every other list uses, so a nameless note reads
"Untitled" here too. A picked link has a ✕; a body link has none, and
wears a small mark instead, because the brackets ARE the link and the
words are where it is removed. Below the rows, "+ Link…" — which opens
SEARCH, the same screen `[[` opens, with the same find-or-create row.
Then "Linked from", when anything points back. Long lists show 8 and say
"Show all N" rather than turning the panel into one thing.

**"Add notes" is gone from a record.** The embedded editor stays for a
record that already carries notes — nothing became unreachable — but
there is no door that starts one. Prose about a task is a note, and the
Links section puts one there in two taps: `+ Link…`, type a title,
"Create". This reverses part of 2026-08-10 (a record's notes reused the
real editor); the owner's reason is that the real editor already exists,
one screen up.

**Also, because the new cost test found it:** the three tests in
`services/tests/scale.rs` measured their two box sizes at different
moments, so a scheduler hiccup — or the other tests in the same file —
could move a ratio without anything being slower. Reproduced on a clean
tree: one run in three failed. They now build both boxes once and
measure them in interleaved rounds, taking the best round. Same bounds,
same guarantees, no random failures in five full-workspace runs.

**Open, flagged not decided:** whether "Links" is the right word when
`link` is also a KIND (a URL bookmark) in this app; and whether a link
to a trashed thing should come back when the thing is restored (today it
drops from both lists, and a body link demotes to text on save).

## 2026-08-17 — one create key, and it never leaves

Owner: *"don't have the create dynamically disappear. later on we should
make these things appear in the same place as notes (i think)."*

**The bar's `+` is always there.** It was stepping aside whenever a view
was open, so the app's create key came and went with the surface — a key
you cannot learn is worse than a key in an odd place. It only vanished
to avoid a second `+` on screen, and that is now solved the other way:
the floating create keys in Today and Tasks are deleted, along with the
two `addTask` verbs behind them. One create door in the whole app.

**It inherits the day you are looking at.** That was the one thing the
floating keys knew that the bar's did not. Today and the calendar
publish their selected day (`DeskModel.contextDay`); a task or event
made from the bar is due that day at 09:00, and today's day when no
surface has one. Verified against the box: with Thu 20 Aug selected,
`+` → Task wrote `due 2026-08-20 09:00`.

**A found bug behind it.** `+` was closing the open view before showing
its menu, which destroyed the very day it was about to inherit — a task
made while looking at Thursday came out due today. The create menu now
leaves the surface alone; opening the new record closes it a moment
later anyway.

**Recorded, not built.** The owner's second sentence is a direction for
later: a new task or event should eventually open *where a note opens* —
in the desk, as a tab — rather than in the record card. Nothing in this
batch moves toward it.

## 2026-08-17 — a view opens where you stand, and the bar stays

Owner: *"idk how the views should open. one idea is to have it open
where you stand. if the bar should be visible or not is the question."*

Both answered, and they answer each other.

**Where you stand.** A view covers what you were looking at, in place,
and leaves by the chevron at its top or by pressing its own row again
(the row is ticked while you are in it). It used to travel into the
library — which was odd the moment the library became filters and
Settings: you pressed a key at the bottom and a panel arrived from the
left carrying something that had nothing to do with the panel.

**The bar stays.** A view with no bar under it is a cul-de-sac: you must
close it before you can go anywhere, and the app's one navigation
surface disappears at exactly the moment you are navigating. With the
bar there, the next place is one key away. The view keeps 58pt of room
for it, so no row hides under it.

**One `+` at a time.** A view has its own create key, bottom right,
which knows the day you are looking at; the bar's `+` steps aside while
one is open. Two plus signs on one screen was the confusion the owner
named on the floor. *(Superseded the same day — see the entry above: the
bar's key stays and the floating ones are gone.)*

## 2026-08-16 — the library is for filters, the workspace and Settings

Owner, settling yesterday's flag: *"library is for filters, workspace
and settings."*

The five view rows are gone from the library. They are the bar's own key
now — Go to: Today · Inbox · Calendar · Tasks · Everything · Docs — and
two doors to one room is what standing rule 4 exists to stop. What is
left behind the left door is what the owner named: the saved filters and
their form, and Settings at the foot.

The WORKSPACE has no row there either: the pinned button at the top
centre has been its one door since 2026-08-13, and adding a second one
would be the same mistake in the same panel. The library is where its
filters live.

## 2026-08-16 — the bar's fourth key becomes "where you look"

Owner: *"Maybe the tab view button should be replaced with a menu for
different views like calendar… and also 'docs' or 'notes', bringing up
the tabs."*

The tab-count square is gone. In its place, a key that opens ONE menu —
**Go to**: Today · Inbox · Calendar · Tasks · Everything · **Docs (n)**.
The count did not disappear with the square; it moved onto the Docs row,
which is what the square counted: the things you have open.

The bar now reads ‹ › search, views, +.

**One thing to settle.** The library's left door lists the same five
views. Two doors to one room is the thing standing rule 4 exists to
stop, so one of the lists should go: either the library keeps only the
filters, the workspace and Settings, or this menu drops the five views
and stays a Docs key. Not decided here — flagged for the owner.

## 2026-08-16 — the + moves right and makes anything

Owner: *"maybe have the + button at far right and make it support adding
any object with properties. tabs still hold documents though."*

On the reverted shape — desk, library, one bar — two small changes.

**The + is the last key in the bar**, in the corner where a thumb goes
and where every app puts its create key. Order is now ‹ › search, tabs,
+.

**It makes any object**: Note · Task · Event · File. Where each one
LANDS is decided by what it is, which is the owner's own second clause:
a note and a file become TABS, because a tab holds a document; a task
and an event rise as CARDS with the caret in the name, because a
record's facts fill a card and not a screen (the 2026-08-07 ruling,
untouched). One door, two landings.

A task or event made here is dated TODAY at 09:00 — the bar has no day
of its own to inherit, and a task with no clock time has no moment to
ring at. The card's due row is one tap away for anything else.

This supersedes 2026-08-12's "task and event don't belong in new tab":
that was aimed at the full-screen New Tab page and its four-way chooser,
both long deleted, and neither is what this is.

## 2026-08-16 — the floor was built, tried, and reverted

Owner: *"the app is a mess now. revert the whole thing."*

Both floor commits are reverted (`0cad7a4`, `4a729b6`). The app is back
to the desk and the library, in the system palette, exactly as it was
before the experiment: the bar is ‹ › search + tabs, the views live
behind the left door, and the tab plane is the desk.

What was tried, in order, and what the owner said to each:

1. **Four floors** — Today · Calendar · Tasks · Find · Open (n) on the
   bar, notes lying over them, the library deleted. *"the ux is kind of
   confusing… it overall feels like a precursor to a sloppy version of
   clickup."*
2. **One page, three arrangements** — Things (Date · Status · All),
   Calendar, Find, Desk; the create key made the page's own kind.
   *"the app is a mess now."*

The design note (design/kinds-are-peers.md) and the mockups
(design/mockups/the-floor.html) are kept, marked REJECTED. The question
they were written for is still open and still good: a task and a note
are the same kind of object, and the app does not show that. Two answers
have now been tried and rejected — that is worth more than the code was.

## 2026-08-16 — the divider stops flashing under Bold

Owner: *"Toolbar insertion of '\*\*\*\*' has a separator flash briefly.
Should only make a separator show if you literally type '\*\*\*\*' and set
cursor elsewhere."*

Bold on an empty line writes `****`, and four asterisks ARE a thematic
break. It should still have been shown as text, because the caret was
sitting in it — syntax shows on the caret's line. Two things stopped
that:

- **A zero-length reveal revealed nothing.** `paragraphRange(for:)`
  hands back an empty range for an empty LAST line, and
  `NSLocationInRange` says an empty range contains nothing. So the one
  line the caret was certainly on counted as un-revealed. `reveals(_:
  line:)` is now its own function with seven assertions in the editor
  self-check.
- **The styling ran before the caret moved.** A toolbar edit replaces
  the text and then sets the selection, so the restyle inside the
  replace judged the new line by where the caret used to be. It is told
  where the caret is GOING, first.

Typing `****` and putting the cursor elsewhere still draws a divider —
that is the half the owner asked to keep.

## 2026-08-16 — one add button, bottom right

Owner: *"The row for adding items in Tasks and Today should be a button
towards bottom right very similar to the screenshot i added."* (The
screenshot did not arrive in the message; this is the ordinary
bottom-right round key, and it is easy to reshape once it does.)

Today and Tasks each carried an inline "type a name here" row — a row
that looked like a list item, sat wherever the list happened to put it
(Tasks' hung inside whichever group came first, and held that group open
even when empty), and asked for a name before the thing existed. Both
are gone. `LivAddButton` is the one key: 56pt, accent, bottom right, and
pressing it makes the thing and opens its properties with the caret in
the title — the app's one create rule since 2026-08-13.

In Today it makes a task DUE on the day you are looking at, at 09:00. In
Tasks it sets no status: that list is grouped BY status, and choosing
one for you would file the task before you had said anything about it.

## 2026-08-16 — both panels are curtains again

Owner: *"make library a curtain like before. i want to rethink what ive
told you today, more later."*

The strip is withdrawn: the library slides over a desk that stays
exactly where it is, the same as the properties panel. Nothing travels
any more — not the desk, not the doors, not the bar, not the pill — so
`deskShift` and `deskTravel` are gone. What is painted ABOVE the panels
(the two doors, the workspace name, the bar, the pill) fades by how far
the curtain over it has come down; the doors watch the library's, the
workspace name the properties panel's.

Held here for the rethink.

## 2026-08-16 — the surface goes back to the system's

Owner: *"maybe we should keep properties stalled on the right not as a
card for simplification's sake, and have the base appearance same as
library. revert colors and faces to as system like as possible. we
should do the surface appearance last and thoroughly."*

**One panel recipe again.** The properties panel stands on the right,
full height, on the same ground as the library — no card, no radius, no
shadow, no top inset. `LibraryPlace` is gone; `SidePanel` draws both,
and both carry the same 56pt top band so nothing they draw lands under
the workspace name floating above them. The two still differ in MOTION,
which costs nothing.

**The palette is the system's.** Every token now resolves to a system
semantic colour: `systemBackground`, `secondarySystemBackground`,
`label`/`secondaryLabel`/`tertiaryLabel`, `separator`, the app tint, and
the system hues for the kind language. What it replaces — a palette
derived from the app icon, measured to a 7:1 floor — was not wrong, it
was EARLY: a bespoke surface pays off once the shapes have settled, and
until then it is a second thing to keep true on every screen. The names
stay, so the surface pass changes the right-hand side of those lines and
nothing else.

**The palette self-check changed with it.** INK is read, so 4.5:1 (WCAG
AA) on the ground; ink on the tint 3:1 (Apple's own white-on-blue is
3.5:1); MARKS — dots, chips, glyph tints — are not read but told apart,
so no two kinds may look alike, measured as a colour distance in both
schemes. A file and a link share one colour on purpose and are exempted
by name.

**The library door is pinned now**, beside the workspace button, so it
stays reachable with the properties panel open even though that panel
covers the screen again.

## 2026-08-15 — the views move into the library

Owner: *"do the views opening inside the library. also, clicking on the
library button doesn't literally move in quickly like it should but
rather fades in. that button should be visible with the property card
open. also, clicking on workspace has a card come in at the bottom, but
since the button is on top it would be more convenient have it appearing
at top also."*

**A view is a thing you look at IN the library.** Today, Inbox,
Calendar, Tasks and Everything opened as full-screen covers over the
desk; now they open inside the library, which is a place. The desk stays
parked to the right exactly where you left it, and swiping back to it
leaves the view where IT was. The library's top band grows a back
chevron while a view is open. `FeatureWindow` — the cover and its
header — is deleted.

**The door slides, it does not fade.** The library was mounted and
offset in the same frame, and a view inserted at its final position has
nowhere to travel from, so SwiftUI fell back to a fade. It is mounted
one beat BEFORE it moves now (`libraryDrawn`, then `libraryShown`), the
same rule the one menu learned in rev 19. `setLibrary(_:)` is the single
door: the button, a settled drag and every internal jump all go through
it, so the mount and the motion cannot disagree.

**The door stays visible with the properties card up**, and it means one
thing wherever you press it: go to the library. With the card up that
now puts the card away first — it is a layer of the desk, and the desk
is about to leave — and then slides. This morning's fix hid the button
instead; hiding a door is a worse answer than making it work.

**The workspace card comes from the top**, from under the button that
opens it. A `.sheet` cannot do that on iPhone, so it is drawn in the
hierarchy with the same motion, scrim and card the one menu wears
(`livTopSheet`). It hugs its content and scrolls only past 72% of the
screen — four rows hanging down 86% of the screen is a wall, not a card.

## 2026-08-15 — the library gets its own bands (and one broken door)

The second half of "a place stands on the floor", after a design pass
that proposed three treatments and judged them through the owner's eye,
the constitution and the builder's.

*(The bottom band's grey fill was removed the same evening — "what is
the grey area towards the bottom in library? looks off". It was a slab
of tone around one row, saying nothing; the hairline already says
Settings is pinned.)*

**The library owns its own chrome now.** It had a 52pt HOLE in its list,
reserved for the desk's floating workspace button — the thing a layer
does, not a place — and the rows slid under that button on unpainted
ground as soon as you scrolled. It has a real top band instead, the same
56pt the desk's chrome owns, closed with a full-width hairline. Its foot
is its own too: a solid band under Settings, deliberately not the desk's
floating capsule. Two places, two silhouettes.

**No lines between the rows.** A hairline between rows is what a FORM
does — it is what `DetailHairline` means one screen to the right — and
this is a list of places to go, held apart by its section labels. The
old ones were also inset 16pt on both sides, which `interface.md` bans
by name ("Dividers are full-width or absent").

**A broken door, mine, from this morning.** With the properties card up
the library door stayed lit in the band above it, and tapping it parked
the library invisibly behind the card while the desk slid out from under
both. It goes dark with the curtain now. The ••• stays live: its verbs
act on the very note the card describes.

**Light mode had no ground.** `canvas` and `surface` were both #FFFFFF,
so in light the library (which stands on the ground) and the properties
card (which floats above it) were the same white — the whole change was
invisible there. The ground is a grouped grey now, and because the light
inks had zero headroom left, five tokens moved a shade darker to keep
the 7:1 floor. The palette self-check is what caught it, on the first
launch after the change.

## 2026-08-15 — a place stands on the floor, a layer lies on the desk

Owner: *"the left 'panel' is really a separate main place of the app,
the other being desk. how can we make it more like so and less visually
like the property panel, which really is a panel belonging to desk."*

They looked identical because they WERE identical: one `SidePanel`
recipe drew both — full screen, `surface` fill, no edges. Two things
that mean different things cannot share one recipe (standing rule 4
cuts the other way here), so the recipe is now two.

**The library is a place.** `LibraryPlace`: the app's own ground
(`canvas`, the floor the desk stands on), corner to corner, no fill of
its own, no radius, no shadow. Two rooms on one floor. It already
arrives by pushing the desk off screen (rev 23) — the motion said this
first; now the surface says it too.

**The properties panel is the desk's layer.** `SidePanel`: a CARD.
`surface` fill, a rounded leading corner (`LivTheme.radiusLg`, the
menus' 22), a shadow, and — the strongest signal — it starts BELOW the
desk's top band, so the library door, the workspace name and the •••
stay lit above it and you can see the desk it is lying on. It arrives as
a curtain, which is the motion half of the same idea.

The workspace button no longer fades under it. It faded from when that
panel covered the screen edge to edge; the card does not reach that
band, so there is nothing to fade for.

## 2026-08-15 — the mini calendar stops rebuilding the world

Owner: *"minicalendar lags when dragged."* Measured before touching
anything, on one 1.2-second drag of the month grid:

| | before | after |
|---|---|---|
| CalendarView body rebuilds | 98 | **0** |
| day cells built | 12,348 | **0** |
| full snapshot passes (`itemsByDay`) | 98 | **0** |

**Two causes, both real.**

*The screen rebuilt itself on every touch-move.* The drag offset was
`@State` on CalendarView, so each frame re-ran the whole body: the day
buckets over the entire box, three month grids of 42 cells each, and the
hour grid below. The pager is its own view now and owns that offset, and
the grid is a value: `CalCell`/`CalMonth` are decided when the month or
the snapshot moves, and `MonthGridView` is `Equatable` over them, so
SwiftUI skips all 126 cells while only an offset is moving. The data
model is the fix; the skip is a consequence of it, not a trick.

*The desk was dragging its panels behind the calendar.* The panel drag
is a recognizer on the WINDOW, and its own installer warns that it
"would otherwise drag panels invisibly behind a full-screen view" — but
it was only ever told about the menu. A sideways drag of the mini
calendar latched a panel behind the calendar window and published 58
times, and the calendar re-rendered on every one. `DeskModel.deskInFront`
now answers "is the desk the surface in front" in one place, for the
recognizer and for the record card alike.

Five new assertions in the calendar self-check pin the shape the skip
depends on — six weeks, 31 days in August, no dots on an empty month,
same month equal, next month not. The instrumentation that produced the
numbers is deleted, as its own comment promised.

## 2026-08-15 — the panels stop being curtains

Owner: *"Now the left and right panels are like curtains. Better would
be if when you open them you 'swipe away' from the previous view, as if
it sits on the left / right off screen."*

The desk now travels with the LIBRARY — one screen to the right — so the
library and the desk read as one strip you scroll rather than a curtain
over a fixed stage. The PROPERTIES panel stays a curtain, by the owner's
second thought the same day ("maybe having properties panel behave like
a curtain though"), and it is the right split: the library is a
different place to be, the properties are about the note already under
them. The panel's own progress drives both the panel and the desk, so
they cannot disagree by a pixel; the drag moved onto DeskModel because
the bottom bar, which is the desk's furniture, is drawn one level up in
RootView.

Whatever is painted ABOVE the panels cannot be covered by a curtain, so
the workspace button, the bar and the pill fade by exactly how far the
curtain has come down — no more blinking out the instant a drag latches.

The details that make it read right: the workspace button stays pinned
(it belongs to the whole strip, and that ruling is a fortnight old); the
two doors fade over the first third of the journey, because their path
crosses that pinned button and two labels on one line is the defect from
the same morning; and the bottom bar rides off screen with the desk
rather than being dropped from the hierarchy halfway through the slide.

## 2026-08-15 — a row with nothing in it is not a row

Owner: *"Have all 'none for this kind' in properties out of view.
Irrelevant properties should be hidden from the user. General rule: when
user can't interact with something it shouldn't be there unless it's
locally dynamic or important for clarity."*

**The status row disappears when there is nothing in it.** A kind with
no status vocabulary and no status set had a full row that read "none
for this kind" — a sentence about the app, not about the note. It is
gone, and its hairline with it. A status that IS set still shows, as a
read-only chip: that is the user's own data, and hiding data is a
different mistake. A kind with a vocabulary is unchanged — the whole row
is still the menu.

**The rule is now written down** (design/ios.md §19), because it decides
more than this one row: three tests, in order — can you act on it here;
does it become actable from something you can do here; does it tell you
something you want to know. Anything failing all three does not appear.

**A sweep of the whole shell against the rule** found one more thing the
user sees and four dead things behind it. Seen: every tab card's preview
opened with `type · note`, spending its best line repeating the kind dot
beside it and the kind footer below it — `type` is skipped now, the way
Today and Everything already skipped it. Dead: `EntityDetailView`, a
73-line pushed wrapper nothing has pushed since the desk took the title;
`displayName`, no callers; the picker's "Nothing to choose from.", which
needs a closed vocabulary with zero options — not representable; and the
`StyleVerb.outline` key plumbing, orphaned when Outline moved into the
`+` menu. Eight candidates were argued down and kept, among them the
library's Filters heading (its band is never empty), the editor's `+`
(it opens a real menu), and the ••• door on a deleted note (Share and
Export are the last way to get that text out).

## 2026-08-15 — templates leave, and messages stop shouting over the workspace

Owner, over a screenshot of a template note: *"the message is on top of
each other. also remove templates completely. it should be added later
when we have decided a good way to implement them."*

**Templates are removed from the shell, whole.** Two files, three menu
rows, the pill, the picker, the `-template.selfcheck` suite (eight
suites now), the furnishing pass that seeded three built-ins, and
everything that existed only to serve them: `LivKind.template`, its
glyph, the entire DASHED stroke pass in the icon language, and
`LivTheme.gray`. `{{cursor}}` was the only reason a focus request
carried a caret, so `consumeFocus` is a plain Bool again. Five
mentions survive on purpose, all about OLD boxes.

Nothing in the Rust core moved. There was never a template verb in the C
ABI — a template was a note wearing one `template` cell, written with
the ordinary verbs — so the core keeps whatever it kept.

**What your box keeps.** The three seeded notes (Daily note, Meeting,
Person) and anything you saved as a template are ordinary notes now,
`{{date}}` and all. The marker cell stays on disk, stays hidden in the
properties panel, and is still skipped by Duplicate note so a copy
cannot spread it. Nothing was rewritten and nothing was trashed.

**The overlap was three bugs, not one.** The pill printed itself across
the workspace name because it was placed against the two door circles
back when nothing sat between them; the workspace button moved to the
top centre on 2026-08-13 and landed on it — and, being drawn later at a
higher z, it also swallowed the pill's taps. The pill dies with
templates, but the box-fault banner and the editor's own notices
(conflict, flattening, save-failed) do exactly the same thing and
survive. So the fix is a rule, not a deletion: `LivRow.topChrome` (56pt)
is the band the doors and the workspace button own, and everything that
speaks starts below it. The number was already there, written out by
hand in one place; it is a token now (standing rule 3).

## 2026-08-15 — the + works on an empty desk

Owner, from the phone, over a screenshot of a workspace with no tabs
reading "No tabs. The + below makes one.": *"no it doesn't."*

**The + was DISABLED whenever the desk had no tabs.** One argument in
BottomBar: `enabled: !desk.tabs.isEmpty`. A new workspace, or one whose
last tab you closed, could not be given a tab from the bar at all.

The guard was right when it was written (2026-08-04): back then an empty
desk's BODY was the New Tab page, so a + that summoned it was a second
door to the room you were standing in. That page was deleted on
2026-08-13 and its `guard !tabs.isEmpty` inside `newTab()` went with it —
but the button's own `enabled:` did not. The empty desk then started
pointing at the button, so the guard became exactly the lie it had been
written to prevent.

Everything downstream was already fine: the create menu builds on an
empty desk and its host is active there. Enabling the button is the
whole fix. The tab switcher's own + and its dashed New Tab card never
carried the guard, which is why the bug looked like "only that one
button is dead".

**The comments that hid it are corrected too.** Five files still said
the empty desk shows the New Tab chooser as its body. Prose that
describes a deleted screen is how a stale guard survives a deletion.

## 2026-08-15 — one gutter for every list

Owner: *"do the list gutter alignment."*

**Every list line's words start at the same left edge**, whatever hangs
in front of them — a dot, a checkbox, a number. The marker is not moved,
it is PADDED: whatever of it is still visible is measured and the
difference to the gutter (23pt, the width of a 15pt checkbox and a
space) is added as kerning on the marker's last character. A line that
wraps carries on under its own words, not under its marker.

**Nesting is one gutter per level**, so a nested item's marker hangs
exactly where its parent's words start. The two source spaces that carry
a level are collapsed to nothing, or every level would be indented
twice — once by the paragraph style and once by its own spaces.

**Why hiding could not do that collapsing.** Measured on the simulator:
TextKit honours a paragraph's `firstLineHeadIndent` only while the
line's first glyph is real. A task line starting with NULL glyphs (the
hidden `- `) was laid out against `headIndent` instead, and its text sat
one whole gutter right of its neighbours' — the "known and left" note
from the batch below, explained. So a task's `- ` is now COLLAPSED
rather than hidden: ink cleared, width kerned away, first glyph real.
`mark` still owns hiding; this is the one case it cannot serve.

Also measured: one negative kern for a whole run collapses only its last
character, because an advance is clamped at zero. Each character pays
for itself.

Numbers past 9 (`10. `) are wider than the gutter and push their own
text ~2pt right; left as is.

## 2026-08-15 — the syntax shows only where you are

Owner: *"have markdown syntax (like ~) hidden when out of focus, only
showing the rendering."*

**Markers get NO GLYPHS off the caret's line.** Not clear ink — that
leaves the width behind as a gap. `LivLayoutManager` is its own
`NSLayoutManagerDelegate` now and answers `shouldGenerateGlyphs` with
`.null` for anything carrying the new `.livHidden` attribute, so the
characters stay in the buffer and take no space at all. Put the caret on
the line and they come back, dimmed and editable: what you can type is
always what you can see.

Hidden: the inline pairs (`**`, `*`, `~~`, backtick), a heading's hash,
a quote's angle, a task's leading `- `, and a link's brackets and id —
`[[4102|Anna]]` reads as **Anna**.

KEPT, on purpose: a bullet's dash, a task's `[ ]` and a rule's dashes,
because the dot, the box and the line are DRAWN into those rects and a
rect with no glyphs has no size; and an ordered list's number, because
the number IS the rendering.

**The reveal generalised.** It already existed for one thing — a divider
swapped its drawn line for its dashes under the caret — and now every
marker does the same. It follows every paragraph the SELECTION touches,
not just its anchor, or dragging a selection handle upward re-flowed the
line you started from mid-gesture.

**Three real defects, caught by reading rather than by luck.** A review
pass over the plan found them and the first bit immediately:
- **The indent is not syntax.** Hiding a task's `- ` from offset 0 took
  the leading spaces with it, so an indented task snapped to the margin
  whenever the caret was elsewhere. It hides from `shape.indent` now.
- **A line that is ONLY a marker keeps it.** Tap Heading on an empty
  line and walk away and the hash would vanish into a 30pt blank band
  you could neither see nor explain — the exact failure the rule's own
  comment records. A marker with no content is the only thing left to
  show.
- **The reveal is asked for when focus ARRIVES too**, not only when it
  leaves. The one path that focuses without moving the selection would
  have left you typing into a line whose markers were hidden.

**And one crash, which named its own cause.** Invalidating glyphs from
inside the styler crashed on the first keystroke: "attempted layout
while textStorage is editing". Attributes alone do not rebuild glyphs,
so the invalidation is real work — it just belongs on the next runloop
hop, the same rule the reveal and the link picker already follow.

**Known and left**: a task's text and a bullet's text no longer share an
exact left edge (the task's `- ` is gone, the bullet's dash is still
holding the dot's rect). Making list markers hang in a common gutter is
a paragraph-indent change, not a colour or a glyph one. *(Done in the
batch above.)*

## 2026-08-15 — the palette comes from the icon, and it is measured

Owner, after a three-way side-by-side: *"i suggest you have a near black
background and use a violet like in one of the arms in the logo. i
thought of the modus themes because of their contrast, which is way
higher than you have made here."*

**The two top buttons are one button now.** They wore the system's
`.bordered` circle, which sizes itself to its LABEL — so the wide
hamburger came out a visibly bigger circle than the narrow ••• — and
fills itself from the tint, so both floated in a lighter grey than the
bar they belong with (owner, 2026-08-15: "should be made of the same
thing"). They are the bottom bar's own recipe now: `LivTheme.surface`, a
hairline, and a fixed 40pt circle around a fixed 22pt glyph. Measured
after: both fills 104px wide, and the fill is byte-identical to the
bar's.

**The colours are the app icon's.** It is three arms of dots, each one
hue running light to dark — VIOLET, PINK, AMBER — and the app now uses
them the same way: violet for chrome and notes, pink for tasks and
people, amber for events, files and captures. There is no blue and no
cyan anywhere, because there is none in the mark. The set it replaces
was Apple's system colours, which is the "generated" look in one line:
every phone owner reads them as the default.

**Built to a contrast FLOOR, which is what the Modus themes were brought
here for.** Ground `#08070A`, text `#FFFFFF` — 20:1. Every colour a
person reads clears **7:1 in both schemes**, most past 10: accent violet
10.0 (was 4.95 — the worst thing on screen), note violet 8.1, task pink
7.7, event amber 11.0, file gold 14.1, secondary text 9.2.

- **`livPaletteSelfCheck` measures it** (`-palette.selfcheck 1`), because
  a floor nobody measures is a wish. It walks every token and every kind
  against the ground it is read on, in dark AND light, and it caught a
  real mistake on its first run: the light accent and the light note
  violet were the same colour to within 6%.
- **Chrome and content stopped saying the same word.** A note used to BE
  the accent. It is now the violet arm one step down — the icon's own
  logic — and the check refuses to let them collapse together again.
- **Tints are colours now, not translucency.** `LivTheme.tint` mixes a
  hue into the ground once and returns an opaque colour. The Today pill,
  the calendar's blocks, the LATE band and the trash bar were
  `.opacity(0.14…0.36)` over whatever happened to be behind them — the
  hue drifted and nothing was ever chosen.
- **The value-dot set** was Apple's semantic five (purple, green, amber,
  red, blue). It is five steps around the icon's arms now.
- **Light mode was re-derived too**, not lightened by accident: white
  ground, the same three arms darkened until each clears 7:1.

## 2026-08-14 — Settings loses its drawer, and the app stops saying "box"

Owner: *"remove settings advanced drawer too"* and, asked in the same
breath: *"btw, what is box? why should users know about it?"*

- **The Advanced drawer is DELETED from Settings**, and everything it
  was the only door to went with it (rule 6): the handoff status card,
  the Pending/Shipped/Delivered ledger, "Ship now", the satellite path
  row, the entity count, "Copy path" and the version line — about 200
  lines, plus `OutboxStateChip` and the date formatter that only it
  used. Settings is Appearance · Suggestions · Reminders · Tabs · Fields.
- **What that costs:** nothing in the app can set a satellite path any
  more, so the phone→desk handoff is OFF until it gets a door someone
  would want to open. The Outbox model still tracks every write, so
  nothing is lost — it just has nowhere to go. Recoverable from git when
  the handoff is designed properly.
- **"box" and "entity" left the interface.** They are OUR words — the
  append-only log the app writes to, and a row in it — and they had
  leaked into eight strings a person actually reads. Now: "This was
  deleted." · "This file was deleted." · "Search everything you have." ·
  "Search" · "Deleted" · "Could not save. It will try again." · "The
  saved version is shown. Your edit is kept."

## 2026-08-14 — no query, anywhere a person can see one

Owner: *"remove all 'Query' functionality. we will replace it with
something better. for instance when creating new workspace, remove the
'advanced' section completely. we should not have advanced features
until the friendly features work as intended. it is supposed to be
primarily designed a user friendly app."*

- **The Advanced row is DELETED** from the new-workspace form and from
  the new-filter form, and with it the only field in the app that ever
  showed or accepted query text. `advancedShown` and the field helper's
  mono variant went too — the mono dress existed for that one field.
- **"Edit name + query" is now "Edit workspace"**, and it opens the same
  form: a name, an area, a subject.
- A workspace is made of pickers now and nothing else. Both forms are
  Name · Area · Subject · Cancel/Create.

**What is left, and why.** `LivQuery` survives as the invisible STORAGE
behind a workspace's lens — the cell the core reads to decide what a
workspace shows and what it stamps. Deleting it today would leave every
workspace filtering nothing, which is not the friendlier app; it is no
app. Nothing constructs it but the pickers, nothing displays it, and it
is ready to be replaced by whatever comes next.

Settings still has an Advanced drawer. That one is machinery — the box's
path on disk, the entity count, the phone-to-desk funnel — not a feature
with a grammar. Say the word if it should go too.

## 2026-08-14 — a caret stays a caret

Owner: *"Creating stuff with the toolbar (like boxes), still selects
them. It is broken since they get deleted as you start typing."*

**The block verbs handed back the whole rewritten line SELECTED.** Tap
"task list" on the line you are writing and `- [ ] ` arrived on screen
selected, so the next letter you typed replaced it — the box you had
just asked for vanished as you began writing. The same for bullet,
numbered, heading, quote and both indents: six verbs, one line of code.

`EditOps.landing(_:whole:newBlock:)` is now the one rule for where the
caret goes after a block rewrite. With an EMPTY caret the rewritten
block is one line and only its PREFIX changed, so the caret moves by
exactly what the marker added or took away and never leaves its own
line. With a real SELECTION the block still comes back selected, which
is what makes a second tap toggle the same lines off.

**A sweep found the same bug in two paths the first fix missed**, and
both are now covered by the one rule:

- **A SELECTION was still widened to the whole line**, marker included,
  so selecting one word and tapping "bulleted list" armed the next
  keystroke to wipe the line. It keeps the words you had now, carried by
  what the marker did in front of them. Widening was never needed for
  the toggle-back it was justified by: `setBlock` derives whole lines
  from `selection.location`, so a narrow selection toggles the same
  lines off — asserted.
- **A caret INSIDE the old marker landed inside the new one.** Put the
  caret at the start of `1. go` and tap "task list": it sat between `[`
  and the space, where the next letter turned the box back into a
  bullet. A point never lands inside a marker now, only at its far side.

**Assertions in `-editor.selfcheck 1`**, and they were checked the
only way that means anything: with the fix disabled they fail, five of
them, reporting exactly the reported bug (`{0, 6}` — the whole `- [ ] `
selected). With it in place they pass. Verified on the simulator too:
tapping the box key then typing "milk" leaves `- [ ] Box testmilk`,
where it used to leave `milk`.

**The separator landed one line too low.** The rule always inserted
BELOW the current line — right when you are standing on a line of text,
wrong in the ordinary way people ask for one: press Return, tap the key,
and the empty line you were standing on stayed above the rule while the
rule appeared a line further down. On a BLANK line the rule now TAKES
that line, terminator and all (replacing the line without its newline
left the newline behind as a second empty line — caught by an assertion
mid-fix). Four assertions cover it, and with the old code they fail
showing exactly the symptom: `a⏎⏎---⏎⏎b` where it should be `a⏎---⏎b`.

**Found in the same sweep, NOT fixed** (different defects, the owner's
call):
- The toolbar's "numbered list" always writes `1.`, even directly under
  a `2.` — it numbers from the line's index inside the rewritten block,
  while the Return key continues the list properly. One grammar, two
  answers.
- An inline verb (bold/italic/strike) over a selection that CROSSES a
  line has no unwrap: every tap adds another pair of markers instead of
  removing the ones it added.

## 2026-08-14 — the timeline gets its two gestures

Owner: *"Hold down (adds box), then drag the box, then release to create
and edit like you do now. Hold down on existing item should make it
possible to trash."*

- **Hold on empty grid places a BOX.** It appears at the quarter hour
  under the finger, follows the finger while it is down, and the event
  is written on RELEASE — with its properties up and the caret in the
  name. Nothing is written until you let go.
- **Hold on an existing block lifts it, and a BIN appears** at the foot
  of the timeline. Drop the block on it and the thing is trashed, soft
  and undoable; drop it anywhere else and it just lands at its new time,
  exactly as before. This is the timeline's delete, which it has never
  had — the question left open on 2026-08-13.
- The press recogniser now begins ANYWHERE on the grid rather than only
  on a block. That made one guard load-bearing, and it is new: the
  recognizer lives on the WINDOW, so it is offered every touch in the
  app, and a touch on the month grid (or on a sheet over the calendar)
  converts into the scrolled content's coordinates as some positive y
  deep inside a 24-hour column — where it would silently start placing a
  box. `scroll.bounds` IS the visible window into that content, so one
  containment test keeps the gesture inside the grid it belongs to. The
  same test closes the collision a review raised on 2026-08-13.

Driven on the simulator, against the box, every leg:
hold-on-empty draws the box · release writes `new event` at the placed
minute and raises the card focused · hold-on-block lifts it and the bin
appears ("17:30 – 18:30 · moving" over "Drop to trash") · dragging
elsewhere writes `set due` 17:30 → 18:30 · dropping on the bin writes
`{"Trash":{"entity":4311}}`. The drop test needed the drop point and the
bin's frame printed to be sure they were in the same coordinate space —
they are, both in window space.

## 2026-08-14 — one menu, three doors

Owner, pointing at Notesnook: *"implement one reusable slide-up menu
component and reuse it for all three, with variations for placement and
slide direction."*

`Menu.swift` is the component: a scrim, a panel, rows of glyph + label
(+ chevron, + destructive). `LivMenu` says where it comes from —
`.bottom` slides up, `.top` slides down — and `.livMenu(_:active:)`
draws it. `active` is the record card's own rule: only the surface in
FRONT draws it, so a menu asked for from inside a card does not appear
behind the card.

It replaced three different mechanisms that all looked different:

- **The toolbar's `+`** was a UIKit `UIMenu` — the one popup that could
  never follow the house motion. It slides up now, titled "Insert". The
  keyboard is resigned through UIKit first, or its accessory row stands
  over the menu sliding up underneath it.
- **The note's `•••`** was a SwiftUI `Menu`. It slides DOWN from the top
  now, from under the button that opened it.
- **New Tab was a whole PAGE.** It is deleted — `NewTabChooser`, its
  close band, its verb dress and `FileImportButton` with it. The three
  verbs are a menu that slides up from the bar that summoned them, and
  the empty desk is empty, with a line saying the + below makes a tab.
  `FileImport.adopt` is what survives of the file door: the picker is
  presented by whoever hosts the menu.

**It really slides**, and that took measuring. The first build used
`.transition(.move(edge:))` on an `if` and an `.animation(value:)` on
the modified content: the panel appeared and vanished with no travel at
all. Recording the simulator and pulling frames every 40ms showed the
card jumping between two positions in one frame. It is an OFFSET now —
the panel is mounted first, measures its own height, and is animated
home from exactly one panel off screen, with `withAnimation` asked for
explicitly at the state change rather than left to a modifier on a view
that does not move. The same frames now show it travelling through
2314 → 2133 → 1984 → 1972.

**The top row, final shape.** The two icon buttons wear the SYSTEM's
bordered circle — `.buttonStyle(.bordered)` with `.buttonBorderShape(
.circle)` and only the tint from the app (owner, 2026-08-14: "should not
be fully transparent / have a button shape … use default appkit look").
Hand-drawn discs, then nothing at all, then the platform's own.

**The (i) PROPERTIES door is DELETED.** The properties panel is dragged
in from the right edge, from anywhere, and dragged back out the same
way — a button beside that gesture was a second door to one room
(standing rule 4). Verified after removal: the drag still opens it on a
live note.

**The top row was uniform first**, and that was the second half of the ask
(I read it as the menu's rows first — wrong). The three floating
controls wore filled grey circles around a bare text button in the
middle: four controls in two dresses. They are PLAIN glyphs now, one
size, one ink, in 44pt targets, the way a navigation bar's are, and the
workspace button sits between them in the same ink at the same height
with a small chevron DOWN (it opens something below it, not to the
right). `on` is the accent glyph where it used to be a filled disc.

**The panels are uniform.** Same corner radius, same paddings, grabber
on the attached edge whichever way it comes from, and the safe area kept
as SPACE INSIDE the card — the top sheet's first row used to sit under
the clock.

`desk.newTabShown` is gone; `desk.menu` replaces it everywhere,
including the bottom bar's retire rule (the bar was drawn after the
desk, so a menu hosted inside DeskHost came up underneath it and lost
its last row — the host moved to the root view).

## 2026-08-13 — nothing between the month and the timeline

Owner: *"remove the 'ALL DAY' row in calendar. there should be no row
between timeline and mini calendar."*

- **The ALL DAY band is DELETED**, with `allDayBand`, `allDayPill` and
  `allDayTask`. The timeline starts where the month grid ends.
- **What it costs, plainly:** a thing with a DATE but no TIME — an
  all-day event, a task due today — is not drawn on this screen any
  more. It is still a coloured dot on its day in the month grid, and it
  is still in Today, in Tasks and in search. Restoring the band is one
  `git revert` away if a missing task turns out to bite.
- **The month grid's long-press now makes a TIMED event, at 09:00.** It
  used to make an all-day one, which only that band drew — so with the
  band gone it would have created something invisible. A door that makes
  a thing you cannot see is a defect. The properties are up a beat later
  and the time is the first row in them.

## 2026-08-13 — one workspace button, at the top of everything

Owner: *"workspace switch button should appear at the top in the center
in all places where that button now exists: global panel (delete current
button), new tab (move). it should also be where you view a note. it
should remain visible as you swipe into the global panel. style should be
same as it looks now in new tab. rearrange the global panel in a way that
fits having workspace at top center."*

- **`WorkspaceButton`** (Workspace.swift) is the one copy, in New Tab's
  own dress: the ring, the name, a chevron. It is drawn by DeskHost at
  the top CENTRE, between the library door and the properties door, with
  the highest z — so it stays put while the library panel slides in
  underneath it. It steps aside for one surface only: the PROPERTIES
  panel, which is about this note, and the workspace is not one of its
  facts.
- **Two copies deleted**: the row at the foot of the library panel and
  the row at the foot of New Tab.
- **The panel's bands say what they DO now.** "Views" and the workspace's
  own name became **"All workspaces"** (Today, Inbox — the two that
  ignore the lens) and **"This workspace"** (Calendar, Tasks,
  Everything). The name was in the label only to say which lens those
  three wear; the button above the panel says the name, and saying it
  twice on one screen is what the calendar's date row was doing.
- The bottom band is Settings alone, and the list starts 52pt down —
  clearance for the button floating over it.

## 2026-08-13 — the timeline places, the properties name

Owner: *"remove 'TODAY · THU 13 AUG' row completely … should be indicated
by the 'Today' button … the 'Today' button should work like a toggle …
naming of items should be done in properties … properties should open
with the cursor in the title field … only interaction in the timeline
will be dragging, creating and deleting items."*

- **The date heading is DELETED.** The month grid already says which day
  is selected, and the Today toggle says whether that day is today —
  three places said the same date.
- **The Today button is the day heading now.** Lit (accent fill, the
  word CARVED out in the canvas colour, the icon chips' stencil) when
  the day on screen is today; the soft tint otherwise. And it TOGGLES:
  the second tap puts you back on the day you left, which is what you
  want after a glance at today. It remembers ONE step, not a history.
- **No more inline naming.** `EventDraft`, `draftBlock` and
  `EventDraftField` are all deleted. Tap an hour and the event EXISTS at
  that minute; its properties rise with the caret already in the name
  (`desk.requestFocus` + the card's existing `autoFocus` channel). Same
  for the month grid's long-press, which makes an all-day one.
- **A record card can throw itself away.** One destructive "Move to
  Trash" row at the foot of the CARD — not the properties panel, which
  keeps only describing (owner, 2026-08-02) because the desk's •••
  sits two inches from it. A card has no such menu, so a task or event
  opened from Today, Tasks or the calendar had no way to be deleted at
  all. Soft and reversible like every trash here.

Verified on the simulator end to end: tapping 20:15 wrote `new event`
at `202608132015`, the card came up focused, typing "Team sync" and
swiping the card away wrote `set name`, and Move to Trash wrote
`{"Trash":{"entity":4299}}` with the block gone from the grid.

**Two gesture collisions were raised in review and did NOT reproduce.**
The drag recogniser lives on the WINDOW, so on paper it can preempt the
month cell's own long-press (0.28s vs 0.45s) and stay armed under the
record card. Driven on the simulator with blocks on screen: long-pressing
day 20 created its all-day event, and a long press inside the card gave
the normal iOS text callout with nothing moved underneath. One
configuration each — the mechanism is real, so if a lift haptic ever
fires where nothing should lift, this is where to look.

**Noticed, not fixed** (settled zone): `liv_trash_at` calls
`content::trash_workspace`, so EVERY trash in the app is logged with the
label "trash workspace" — a note, a task, an event, all of them.

## 2026-08-13 — the calendar loses its quick-add and gains its properties

Owner: *"'New for Tue 11 Aug…' in bottom in calendar is redundant since
users click where they want their items to be in the timeline. Also,
properties should slide up immediately when new calendar items are
created."*

- **The quick-add row at the foot of the calendar is DELETED**, and
  `CalendarQuickAddRow` with it. It made a date-only TASK from a screen
  whose whole point is pointing at an hour. A dated task is still made
  in Tasks and in Today, where the same row lives and means something.
- **The properties card rises the moment an event exists.** Naming the
  draft block writes it and `desk.open(id, as: .record)` raises the card
  over the calendar — which stays where it was, Option C's rule. The
  shape is passed explicitly: the entity is a heartbeat old and may not
  be in the snapshot `shapeOf` reads yet.

Verified on the simulator: tapping 21:15, typing "Dinner", Return —
`#4299 Dinner event 2026-08-13 21:15` in the box, and the card up with
due, status and the filing rows on it.

## 2026-08-13 — making a link opens SEARCH

Owner: *"Creating links will open search to select the thing you want to
link the currently opened thing with, and then insert the whole link for
you."*

- **One search screen, two endings.** `SearchView` takes an `onPick`: a
  result reports itself instead of opening as a tab. The editor presents
  it as the link door, and writes the whole `[[id|Name]]` for you.
- **Both doors lead there.** The toolbar's Link key no longer types
  `[[` into the note — it opens search directly. Typing `[[` opens the
  same screen, with what you had already typed carried in as the query.
  Dismissing without picking suppresses that token, so brackets you
  meant literally do not summon it again until the caret leaves them.
- **The toolbar is GROUPED** (owner, 2026-08-13, pointing at
  Notesnook): six runs of keys with a hairline between them, most-used
  first — undo/redo · bold italic strike · **link** · heading task
  bullet numbered · indent outdent · quote code divider. Fifteen
  identical squares in a row was a wall.
- **Link is IN the row**, not behind the `+`. The `+` now holds only
  what is not universal — Template and Outline today, and whatever
  advanced thing lands later (the owner named maths).
- **The four-row `[[` picker is DELETED** — its own search, its own
  create row, its own list style. A second search screen is a second
  thing to keep true (standing rule 4), and it showed four results where
  search shows all of them grouped by kind.
- **Find-or-create links too.** "Create …" in the link door makes the
  scrap and points the link at it, in one tap.
- **A bug this joined up.** `EditOps.completeLink` built the link token
  itself, spacing only `]]` where the codec spaces every `]`. So a link
  made in the editor to a name ending in a bracket — "Q3 [final]" —
  wrote `[[4155|Q3 [final]]]`, which the scanner closed early, leaking
  one bracket into the note per save. Exactly the defect fixed in the
  codec on 2026-08-11 and missed here, because there were two builders.
  There is one now, with its own checks.

The "LINK TO" header went with the picker; that string exists nowhere in
the app any more.

Verified on the simulator both ways, and against the box: the saved
content is `Text("Wire test ") · Ref(4184) · Text(" and ") · Ref(4295)`
— real references, not literal text.

## 2026-08-13 — a markdown file IS a note

Owner, opening a .md he had just added: *"Totally broken. It should open
any file in editing mode, and .md should work like any note. Completely
get rid of this kind of screen and behavior. 'Open in…' should be
removed. 'md' shouldn't be a type since notes are always 'md' anyways."*

**Markdown is not a foreign format.** It is what a note IS. Adding a .md
now creates a NOTE with the words in the box — editable, rendered,
searchable, versioned like everything else — instead of a file
reference showing a read-only preview of its own source. `NoteBytes`
(Files.swift) is the rule; the import door asks it before it copies
anything, and a markdown pick is never copied to disk at all.

- The name loses its extension: "Linux Installation.md" becomes a note
  called "Linux Installation". Every note is markdown, so saying so in
  the name — or in a `md` chip — is noise. There is no format cell, so
  no chip.
- **Markdown only.** `.txt` is somebody else's text file, and
  `.tex`/`.bib` are source for another program: swallowing a thesis into
  the box the first time it is added is the opposite of what files are
  for. They stay files.
- **UTF-8 only.** Bytes that are not UTF-8 are not text we can honestly
  claim to hold, so they stay a file.
- A markdown file added BEFORE this rule converts itself the first time
  it is opened — words in, file cell off, the tab redraws as the note it
  should have been. The log keeps every version and the file on disk is
  never written.

**This is not in-app editing of foreign bytes** — the thing the product
refuses, and still refuses. Nothing writes back to the file. The words
are copied in once, at the door, and the file goes its own way. A .docx
or a .pdf still cannot be edited in Liv: Word owns the words. That part
of the ask is not buildable, and is not built.

**The preview is DELETED.** Owner: *"preview should not be a
functionality since it is absolutely useless. Remove relevant code."*
Out went `QuickLookView` (Apple's renderer, embedded), the `previewable`
test, the extracted-text fallback, the "No preview for this format"
hint, and — because nothing displayed it any more — `Box.extractedText`
and its `liv_extracted_text_at` call (rule 6). The FFI verb stays: it is
the C ABI, and the core still extracts words for SEARCH, which is what
extraction is actually for.

A file tab is now its NAME and its filing, and nothing else. Reading a
Word file means opening Word. A read-only render inside Liv looked like
an editor and was not one — the same complaint that started this batch.

**"Open in…" left the file screen** and became a ••• menu item, where
every other secondary verb lives. Handing the bytes to the app that owns
the format is the file integration and had to survive; as the only
button on the screen it made a file look like something Liv could not
read.

Verified on the simulator end to end: added the same `Linux
Installation.md` through the picker, and the box holds `#4293 Linux
Installation  note` with no file cell and no format cell, while
`thesis.tex` and `live.txt` are untouched files.

## 2026-08-13 — the icons are DRAWN, and the kind colors reach everywhere

Owner: *"apply the kind colors everywhere, and i don't see the
blueprint's custom icons in the app."* Both were true, and the second
explains the first.

**Why no blueprint icons.** There never were any. The app drew Apple's
SF Symbols — filled, heavier, on their own grid — where the blueprints
draw their own stroked 24×24 set. Nothing had drifted; the drawings had
simply never been built. `Glyph.swift` now holds them, transcribed from
`design/mockups/blueprints/icon-style.html` and `home-views.html`:

- **Kinds** — note (a page with two lines), task (a rounded square with
  a tick), event (a calendar), person (a silhouette), link (two rings),
  capture (a tray), template (the note, dashed).
- **Files** — the page with a folded corner, narrowed by format: a grid
  for a spreadsheet, a screen for slides, a picture for an image, lines
  for text, a label block for a PDF. One file color, orange; the drawing
  carries the format. The old SF-symbol table in `FileFacts.Class` is
  gone.
- **Places** — a sun for Today, a tray for the Inbox, the calendar, the
  tick square for Tasks, an archive box for Everything, a funnel for a
  filter, a gear for Settings, a ring for a workspace, a grid for All.
- Drawn by a small pen that works in the blueprint's own 24-unit space,
  so a glyph is transcribed once and scales anywhere. No SVG parser: the
  only curves in the set are rounded corners between straight runs, and
  `addArc(tangent1End:…)` does those exactly.
- `PropertiesMark` is separate on purpose — three rings in three colors
  is the one mark that is not a single color, and it is never boxed.

**ONE classifier.** `LivKind` is now an enum with `of(row)` as the only
answer to "what is this?", and it carries both the color and the glyph.
It had been two tables that disagreed: the color read `kinds.first`, the
glyph read `kinds.contains(…)` in priority order plus status. A task
filed as `["note","task"]` therefore drew a tick on a BLUE square, and a
capture carrying a status drew a tick on a YELLOW one. Priority is now
file > template > event > task-or-any-status > person > link > note >
capture, once, for everyone.

- Four private copies of the same question folded into it: two
  `isTemplate` helpers (Desk, Detail), the tab card's `kind`, and
  Search's grouping key. `Record`'s two-symbol pill table went too.
- `livCanTick` (Kit.swift) replaces the two private `isTask` copies. It
  is deliberately NOT the kind: it asks whether there is a status to
  close, which an event can also have.
- `-glyph.selfcheck 1` is the eighth suite: one kind per row, color and
  glyph agreeing, every drawing inside its box. It caught a wrong test
  fixture of mine on its first run.

**Where the colors landed.** Search results (rows AND real kind groups,
so files finally get their own section — the `case "file"` sort key had
been dead), the [[ link picker, Today's agenda and all-day band, the
calendar's blocks and its month dots, the Inbox's waiting cards, tab
card footers, the minimised record pill, the template picker, a file's
own header, reference chips and the kind chips in the properties panel.

- **Calendar blocks wear the kind.** They were purple for a task and
  blue for everything else, so an event — the calendar's whole reason to
  exist — came out in the note color.
- **Month dots take the kind color**, reversing "the calendar says WHEN,
  never what kind". Three grey dots said only "busy"; the same three in
  teal, purple and yellow say what the day holds. On the SELECTED day
  they stay one ink — the cell is filled accent, and color on color is
  unreadable.
- **The agenda's leading slot is one mark in a fixed column**: the
  repeat glyph, or the ring, or the kind glyph — never two. The colored
  bar the owner killed on 2026-08-08 is not coming back.
- **Everything stops printing the type twice.** The word "note" beside a
  blue note icon is one fact said twice; Today had always skipped it.

**Held to the rules.** The create menu's verbs and the Inbox's four
routing buttons take the shared GLYPH but no color — color marks what a
thing is, never what a button would make. Property field rows still wear
a dot, not an icon. Search's "Create" row keeps its soft accent plus.

**Two bugs found on the way.** Search printed the core's `#417`
placeholder as a name (every other list turns it into "Untitled"), and
Everything's grey-the-nameless test compared against `"untitled"` while
the helper returns `"Untitled"`, so nameless rows drew at full strength
on the one screen built to show them quietly. `livRowIsUntitled` is now
the one question and both call it.

**Also fixed, on the owner's earlier ruling.** The workspace switcher
printed `area:Work project:Viggo` in mono under each name — the query
language showing through, which no user ever types. It reads as value
chips now; the raw text stays in the folded Advanced field.

**Build script.** `build.sh` puts the system tools first. This machine
has plan9 `grep`/`sed` earlier in PATH, and they have neither `grep -m`
nor `sed -E`, so a device build silently read an empty signing identity
and claimed the certificate was missing.

## 2026-08-12 — the blueprints start landing: kind colors + carved chips

Owner: *"start building the blueprints into the app. While you're at
it, make the icon in the box a bit larger, and the boxes slightly less
rounded."* Slice 1 of the approved visual blueprints, foundation first:

- **`LivKind`** (Theme.swift) — the one kind→color mapping: note blue,
  task purple, event teal, file/link orange, person pink, capture
  yellow, template gray. Five new color tokens (teal, orange, pink,
  yellow, gray) join the theme. Nothing else may hardcode a kind color.
- **`IconChip`** (Kit.swift) — the carved chip as ONE component: solid
  color square, glyph punched through in the canvas color. Built with
  the owner's tweak: 15pt glyph in a 28pt box (larger than the mockups),
  radius 6 (less round), both scaling with size. The reference sheet
  (icon-style.html) was updated to match.
- **Person is the silhouette** — `livRowGlyph` returns `person.fill`;
  no initial-based icon exists anywhere.
- Applied in slice 1: the library panel (each view in its own hue,
  filters and Settings gray, workspace blue) and Everything rows (kind
  chips).
- **The capture sheet is DELETED — 1,129 lines.** Owner: *"clicking on
  'event' in new tab takes you to the old Idea/Task/Event/Photo menu
  which should be completely gone. Also, task and event don't belong in
  new tab."* Both verbs left the create menu, which was the sheet's ONLY
  door, so `CaptureSheet.swift` went with them, plus `CaptureRequest`,
  `CaptureVerb`, `desk.captureRequest`, its presentation, `present()`,
  `createTask()` and the notification handler's dismiss-first line
  (rule 6). Checked first that nothing else used its pieces — the camera
  has its own chip editor.
  - The **one-tab-per-session latch** in `adoptCapture` went too: it
    existed so serial commits from that sheet reused one tab. With one
    entity per door there is nothing to reuse, so it is now
    close-the-chooser-and-open.
  - Tasks and events are still made where they belong: the Tasks and
    Today quick-add rows, and the calendar's tap-an-hour and
    long-press-a-day. The create menu is three verbs now — note,
    template, file.
- **The create menu keeps PLAIN glyphs** — carved kind chips were tried
  there and rejected within the hour (owner: *"color / boxed icons in
  new tab looks bad"*). It is a column of five verbs read by their
  words; five colored boxes made it a toy shelf. An intermediate fix —
  inverting the chip on the accent-filled primary, where a blue chip on
  a blue button vanished — went with it, and `IconChip`'s `carve`
  parameter was deleted since nothing overrode it any more (rule 6).
  The line the two rejections draw: **kind color marks what a THING is,
  in lists. It does not mark what a button would make.**
- **Property rows get a color DOT, not an icon** — reverted the same
  day on the owner's word: *"icons for properties are confusing, but
  color indication of some sort is ok."* A clock for "due" and a tag for
  "subjects" are pictures of the word beside them, which reads as noise.
  An 8pt dot in the field's hue says which family a field belongs to and
  claims nothing more; it is also the owner's own three-dots metaphor.
  Kind chips elsewhere keep their glyphs — there the icon says what a
  THING is, which the word does not.

Verified on the simulator: panel, Everything, create menu and a task's
record card all show the carved language. All seven suites and
`cargo test` green.

**Build queue for the next slices** (from the approved blueprints):
status rings that fill by state · Inbox stat tiles + routing verb chips
· the 44pt rounded search field · floating pill bottom bar + tab
switcher footer · month segment pills · [[ picker rows · workspace-ring
hues in the switcher · settings section chips · tab-card footer dots ·
search result kind rails. The capture sheet stays untouched pending its
redesign (the old verb menu is rejected).


## 2026-08-11 — workspaces and filters are picked, not typed

Owner: *"'Query' is not what I want whatever it is. Should let you choose
area and subject. 'Filter' button has the same problem, and I don't think
it should be there but rather accessed somehow in the global panel."*

This was standing rule 5 being broken in the one place it names: *a user
never types a query language; filters and workspaces are built from
pickers over furniture that already exists.*

- The **Query** box is gone from both forms. In its place: **Area** and
  **Subject** rows, showing the chosen value as a chip or "Any". Only
  those two — project and people were noise (owner's call).
- Each row opens **the picker the properties panel already uses**.
  `InspectorValueSheet` gained an `onPick` closure: given one, it reports
  the choice instead of writing a cell. One picker, not two (rule 4), so
  the options, the search and the create row behave identically.
- `LivQuery` gained `value(of:)` and `setting(_:to:)`. A picker edits
  only its own term and leaves every other token exactly as typed, so a
  hand-made query survives being looked at through the pickers.
- **Advanced** holds the raw query, folded shut. A workspace IS its
  query — that is how it is stored — so the text stays reachable, just
  not as the way in.
- **The stamp hint line is deleted.** "Stamps area:Work" was a grey
  sentence explaining a control, which is a design failure here (owner,
  2026-08-06). I had also put explanatory text in the mockup; that was
  my error and the mockup is corrected too.
- **Filters moved to the library panel**, under the views, with a dot on
  the one that is on. They are no longer in the workspace sheet — a
  filter is not a workspace. Only the FORM stayed behind, opened by the
  panel's "New filter…" through one model flag, so there is no second
  copy of it.
- Fixed on the way: `WorkspaceSwitcher` was presented without
  `DeskModel` injected. It worked only because a sheet inherits the
  environment; reading `desk` in it would have trapped the day that
  changed.

Checked on the simulator: the form shows Name / Area / Subject /
Advanced with no explanatory text; picking Area "Work" writes
`area:Work` (read back under Advanced); the panel shows the Filters band
and "New filter…" opens the same picker form. All seven suites and
`cargo test` green.


## 2026-08-11 — the bug list (Liv Bugs.md)

**Four markdown bugs were one line.** `dim()` — the helper that greys
every marker — also forced the marker to 12pt monospace. A line's height
follows its tallest font, so a marker did not merely look wrong, it
changed its LINE's metrics. A freshly generated `- [ ] ` is entirely
marker, so the line was 14.13pt tall instead of body's 18.84: it shrank
the moment the marker appeared, every line below jumped, the hyphen rode
a higher baseline, and the drawn checkbox — anchored to body metrics —
no longer matched it. Typing one character brought the body font back
and everything moved again. `dim` now keeps the line's font and changes
only the colour. That is the owner's #1, #2, #4 and #5 together.

- **#3, `- ` draws as a point.** A `livBullet` attribute clears the
  dash's ink and the layout manager fills a 5pt dot, the same trick the
  checkbox has always used. The trailing space keeps its width, so text
  still starts exactly where the source says.
- **#6, a new task lands in properties.** All three quick-add rows
  (Tasks, Today, Calendar) now open the record card — the owner's
  standard way, since a new task usually wants a date and a field or two
  next. `open` gained an `as:` hint because the box answers BEFORE the
  snapshot lands: `shapeOf` on a brand-new id read nil, guessed
  "document", and that is why the create menu's "New task" opened a
  markdown editor instead of the task's own card.
- **#7, the due sheet stops throwing you out.** Today/Tomorrow no longer
  dismiss. They also MOVE the sheet's own `date` — which is the half
  that mattered: every later write reads it, so removing the dismissal
  alone would have made the next time-change silently rewrite the day
  back to whatever the sheet opened on. The dismissal was hiding that.
- **#8, "erases everything" was a trap, not a write.** The sheet can
  only touch the due cell — never names or notes. What erased it was the
  red **Clear** row appearing directly under the time control the
  instant a date existed, exactly where a finger was already travelling;
  it unsets the whole value with no confirmation and no undo. Clear is
  now always rendered, disabled until there is something to clear, so
  the layout is fixed from the moment the sheet opens and nothing
  arrives under your thumb.

Verified on the simulator: quick-add opens the card with the typed name;
the due sheet stays open after Tomorrow and its "Choose a date" row then
reads Wed 12 Aug (proving `date` moved); Clear is present and greyed
before any date, red after; bullets, checkbox and `#` all render right.
NOT verified: driving the time WHEEL — synthetic input would not land a
new hour, so the day-preservation is shown by the sheet's own state
rather than by a completed time change.

**A third false alarm in `carriesFormatting`, found by looking at the
screen.** After the codec change every legacy note showed "this editor
can't keep your formatting" — a note reading `- [x] Slides` is not
losing anything, it is being promoted to a real Task block. The
principle (ask each piece whether it survives its own round trip) was
right; the ad-hoc rules bolted beside it were not. Both are gone: a
whole-document comparison cannot tell a promotion from a loss, and the
standalone newline rule flagged the one-Text-span-with-newlines shape
older writers produce (the CLI still writes it) — also a promotion, and
the genuine case, a newline inside a MARKED run, is caught by the round
trip without a rule of its own. Known and accepted: an escaped `\#`
from a vault import is indistinguishable from a legacy marker at this
layer and is promoted rather than flagged.


## 2026-08-11 — the codec writes the core's blocks (the deviation retires)

Owner: *"do this code structure change."* The phone stored `## Title`
as the characters `## Title` — every line a Body paragraph, every
marker literal text, the recorded deviation from D19 that the core's
own `services/src/tasks.rs` grew a second read-form to tolerate. The
codec now writes what the core stores. **Rendering is untouched** —
headings sized right and boxes drew as boxes before and after; only
the wire changed.

- `BlockJSON` grew from two cases (body, other) to the core's full
  vocabulary, with serde-exact Codable pinned against the JSON strings
  in `core/src/value.rs`'s own tests. `.other` remains for Code,
  Callout and future blocks — still flattened, still banner-gated.
- `textToSpans` derives each line's block through `MarkScan.shape` and
  each delimiter pair through `MarkScan.inline` — the SAME scanner the
  styler renders with, so screen and box can never disagree (rule 4;
  the codec's old regex ref-parser is deleted, rule 6).
- `spansToText` regenerates markers from blocks and delimiters from
  marks. Ordered numbers are presentation: renumbered per consecutive
  run per depth. Depth is one tab or two spaces per level
  (`EditOps.indentUnit`).
- `carriesFormatting` **rewritten to render and rescan**, not to reason
  about cases. The codec is a round trip; the only honest question is
  whether a value survives it, and the only authority is the codec
  itself. Two per-case rules I wrote first both leaked: `"a*"` in bold
  renders `**a***`, which rescans as bold-"a" plus a stray star; and a
  BODY paragraph whose text begins `# ` renders as `# …` and rescans as
  a heading — silently changing shape on the next save, with no banner.
  That second class is reachable: `parse_markdown("\\# escaped hash")`
  yields exactly `[Break(Body), Text("# escaped hash")]`, verified with
  a throwaway test against the importer, then removed. Both now flag by
  construction, and so will the next such edge. `.other` is still
  checked separately — Code and Callout have no buffer form at all.
  A leading Body break is normalised away first: it opens the first
  paragraph, which the buffer opens anyway.
- ~70 codec assertions now in `-spans.selfcheck 1` (was 22), including
  the pinned canonicalisations, the wire strings, the marker-as-body
  class and the bracket-in-a-name class; the 73 scanner assertions
  untouched and green.

**Open, flagged rather than silently changed:** a link to a TRASHED
entity is still demoted to literal text on save. Ruling 5 says a token
whose target is "not in this box" must stay text, but the shell tests
its SNAPSHOT (which filters trashed) while the core refuses only when
`store.get` finds nothing (which does not). So the shell demotes links
the core would have kept, and restoring the target does not restore the
link. The banner now fires for it; changing the demotion rule is the
owner's call, not a codec cleanup.

**Three defects the adversarial review found, all confirmed by test
before fixing:**

1. **A link whose target's name ends in "]" leaked a bracket into the
   note on every save, forever.** `token`'s sanitiser replaced "]]" with
   "] ]", which is non-overlapping — so "Q3 [final]" rendered
   `[[4279|Q3 [final]]]`, whose FIRST "]]" is the name's bracket plus
   the token's. The scanner closed there and the leftover "]" fell into
   the note as text. Measured: five cycles gave `]]]]] today`. Now every
   "]" is spaced, so none can sit beside another or beside the closer.
   Proven end to end on a real box — three edit cycles through such a
   link now store `[Text("See "), Ref(4279), Text(" today...")]`, clean.
   PRE-EXISTING, not introduced here.
2. **The banner rendered nameless and assumed every id was known**, so
   it tested a buffer the user never gets — and those are precisely the
   two ways this round trip loses data. It now takes the SAME `name` and
   `isKnown` closures the save uses.
3. **The Tasks view's checkbox rewrites the whole note with nobody
   looking**, so a code fence or callout elsewhere in it was destroyed
   by ticking an unrelated line. It now refuses and warns when the note
   carries something the buffer cannot hold — the editor says it
   properly when you open it.

Also: Share/Export rendered links as bare `[[4279]]`, naming nothing an
outside reader could resolve — it passes the display names now. And
four more canonicalisations are pinned (tab → two spaces, `* ` → `- `,
heading/quote indent dropped, depth clamps at 15) so the set cannot
widen unnoticed.

Verified live, not by reasoning: typed on the simulator, then read the
raw box log — `{"Break":{"Heading":1}}` and `{"text":"important",
"marks":1}` stored, no marker characters. Reload regenerated the
buffer pixel-identically. One checkbox toggle from the Tasks view
converted a whole seeded legacy note — 0 structural breaks before, 7
after, the tapped line `Task{done:true}`, every line 1:1, and a
mid-line `## ` correctly left as body text. Legacy notes convert
exactly this way: wholesale, on their first edit, never before.
`cargo test` 317 green — zero Rust changed.


## 2026-08-10 — the type scale becomes a type, and the panels get room

The owner: *"UI in the property panel is cramped towards the top when
almost half of the panel is empty. Text is too small. Whatever you change
to, mirror it logically in the global panel and throughout the
interface."*

It could not be done as a nudge. Type size was **prose**: 19 distinct
values across 253 call sites, every one a literal, including 7.5, 9.5,
10.5, 11.5, 12.5 and 13.5pt that nobody chose. **86 of the 253 were under
12pt** — a third of the app's text, against the owner's own standing
"no micro-text" rule. This is precisely the drift CLAUDE.md rule 3
predicts: *"colours are tokenised and have never drifted; type sizes are
prose and have drifted 38 times."*

- **`LivType`** now sits in Theme.swift beside the colours: micro 10.5,
  caption 12, label 13, body 15, strong 16, title 18, display 22, hero
  26. Each step names the old band it replaces. All 253 sites converted;
  **zero size literals remain in the shell.** "A notch bigger" is now
  five numbers, not 253.
- **`LivRow`** — 54pt ordinary, 58pt for a two-line row. Rows were 46
  when their text was 11–13; bigger text in the same box is just more
  cramped, which is exactly what the owner was looking at.
- Both panels got the same rhythm: air above the first section label,
  and space between the title block and the first band. The library
  panel mirrors the properties panel, as asked.
- **Document titles breathe.** `titleTop` 54 → 78 (the title sat ~8pt
  under the floating circles) and `titleGap` 6 → 20 (the note began
  almost against its own name). The literal `32` that appeared in both
  the initial inset and the height floor became one `titleFloor`, and
  the title font is `LivType.hero` rather than a second 26.

Checked on the simulator across the note, both panels, the calendar,
the tab switcher, Today and Tasks — nothing clipped or overflowed. The
calendar gutter fix from this morning still holds under the larger type,
measured: hour label ink ends at 36.3pt, the rule starts at 46.0pt,
9.7pt clear.

**Still empty, and not a layout problem:** roughly 40% of the library
panel remains blank because the things that belong there are built in
the core with no door — a Pinned band (`liv_pin_at` ships, the snapshot
carries an ordered `pins` array, nothing calls it) and a Filters band
(saved views exist, reachable only inside the workspace switcher). Both
are Batch A of design/blueprint-gap-2026-08-10.md.


## 2026-08-10 — the panels lose their collapse buttons entirely

The owner, in two steps: *"There's a whole row in both the left panel and
the property panel that only contains the collapse icon"*, then, once the
chevron had been moved onto the first row, *"the collapse '>' is almost
inside the title in properties. You probably should get rid of the
collapse buttons."* Both panels are one component (`SidePanel`), so one
change did it twice.

The 40pt band is gone and so is the button. **A panel is dragged back** —
the gesture the owner asked for on 2026-08-08, and the same one that
opens it. Worth knowing, because it was checked before removing the
button: panels are full screen width and drawn over everything, so ☰ and
(i) are covered while one is open, and there is no scrim to tap. The drag
is now the only way out for a finger; `.accessibilityAction(.escape)`
remains for anyone not using one. `title` went with the button — it
existed only to name it.

Also fixed, from the seam map's hazard list, all in the record card's new
embedded editor:
- **`.id(id)` on RecordCard.** Following a `[[link]]` from one record to
  another only reassigns `desk.recordCard`, so SwiftUI reused the view
  and the editor's model stayed attached to the record you LEFT — B's
  name and facts on screen, your typing going into A. This was the worst
  of them and it silently wrote to the wrong entity.
- **A dead `[[link]]` no longer opens a dead tab.** The desk's own call
  site has guarded this since ruling 5; the card's new one did not.
- **The card injects `WorkspaceModel`.** The `[[` picker's Create row
  reads it, and would have trapped the first time anyone used it.
- **`record.notes` is its own accessibility identifier.** A card sits
  over a live note tab, so two text views answered to `note.editor` and
  every scripted check of the editor was a coin flip.
- **Notes line up at 16pt** with the name field and every inspector row;
  they were landing at 20.
- **Outline and Template are dropped from the `+` menu when embedded** —
  Outline scrolls a view whose scrolling is off, and Template would land
  a document's boilerplate in a task. A menu item that does nothing is a
  lie.
- A card rising over a note tab now dismisses that note's live `[[`
  picker, which used to be left floating.
- Deleted: `keyboardDismissMode`/`alwaysBounceVertical` set in init and
  undone a moment later, and a whole-text scan computing a title prompt
  that embedded mode never draws.


## 2026-08-10 — the record card uses the REAL editor (stage one)

The owner: *"'Add notes...' in properties. There is already a note
editor. Can this and other app mechanisms be reused? Links for
example?"* Yes, and the old reasoning was wrong twice over.

A record's notes are content spans on the record entity — the SAME data
a note's body is. So the plain `TextEditor` was never a different KIND
of thing, only a worse way of editing the same thing. And what it
withheld is exactly what a task wants: a **checklist**, and a
**[[link]]** to the note or project it belongs to.

- `MarkdownTextView(showsTitle:)` — a note carries its title inside its
  own scroll view (the Obsidian layout); a record is named by the card
  above it, so a second name field would be a lie about what you were
  editing. The flag is `let`, because a view that could gain or lose a
  title mid-life would invite the inset mutation during layout that once
  blanked the whole document.
- `MarkdownEditor.embedded` — the text view stops scrolling itself and
  reports its height through `sizeThatFits`, so it lives inside the
  card's own ScrollView. Two nested scroll views is the fight this
  codebase already lost twice (HourGridDrag, PanelDrag); the answer is
  to have only one.
- `RecordBody` drops its own `NoteEditorModel` entirely and embeds
  `NoteEditor`. That deletes the second editor AND its whole plumbing —
  attach, flush, textChanged, snapshotArrived, the conflict line
  (standing rule 6).
- Checkboxes, markdown styling, `[[ ]]` links, the outline, template
  insertion and the keyboard toolbar all arrive with it. The toolbar is
  the text view's `inputAccessoryView`, so it came free.
- A tapped link opens as a tab, which closes the card on its way out —
  `openDocument` already clears `recordCard`.

Verified on the simulator, not by reasoning: the toolbar renders inside
the card; typing lands; the Task list verb draws a real checkbox;
**tapping that checkbox toggles it** (the nested-scroll risk, and the
one most likely to have broken); the box then reads
`#4255 Do things · task · todo · content "- [x] Slides"`. The
full-screen note editor still shows its title and derived prompt — no
regression.

design/ios.md §record card amended rather than silently contradicted.
Stage two (growing the card to full height while writing) is not built.


## 2026-08-10 — one verb face, because the copy drifted

The owner: *"'Add a file' in light mode New tab lacks the button shape
the others have."* Correct, and the cause is instructive.

`FileImportButton` was hand-dressed to match the create menu's verbs
(2026-08-09, centring it) and copied the fill but not the BORDER. In
dark mode nobody could tell: surface `#1E1E20` reads against canvas
`#161618`, so the fill alone draws the shape. **In light mode both are
`#FFFFFF`** — the border is the entire shape — so the button had none.

Fixed by making there be one recipe rather than adding the missing line
to a copy: `LivVerbFace` in Kit.swift, worn by both the chooser's
`verb()` and `FileImportButton`. Standing rule 4 covers display helpers,
not just parsers, and this is the second copy-drift of the day (the tab
card was the first). Checked in both appearances.

**Not a bug, recorded so it is not re-investigated:** while chasing this
I claimed the appearance setting was lost on cold launch. It is not. I
had written the preference with `simctl spawn defaults write`, which
does not reach a sandboxed app's own domain, and then read my own write
back. Instrumented: the app reads its stored value, finds the window at
`onAppear`, and applies it; Dark survives a cold relaunch. The
speculative scenePhase re-apply was reverted.

## 2026-08-10 — the bottom bar stays up on New Tab, and "Open…" goes

The owner: *"Bottom bar sometimes shown and sometimes not shown in New
tab. What is right?"* Measured before answering — the same screen was
furnished two ways. Summoned by `+` the bar was hidden; as the empty
desk's own body it was shown. Nothing chose that: the bar's condition
carried `!desk.newTabShown`, written when the concern was panels
sliding over it.

**Always shown is right.** The screen is identical either way, so its
furniture must not depend on how you arrived; the empty-desk case
already proved the two coexist without colliding; and without the bar
the summoned chooser's only exit was one small chevron, while the bar
carries the way back to your tabs and to search.

- **"Open…" deleted.** It ran `desk.searchShown = true` — the bar's
  search button, said twice. With the bar always up it is two doors to
  one room (standing rule 4), and rule 6 says the change that makes
  code unnecessary deletes it.
- **‹ › now dismiss the chooser.** They move the desk UNDERNEATH it, so
  left alone they would change a tab you cannot see. Asking for a tab
  means you want to look at it. Checked live: back arrow closes the
  chooser and lands on the tab.
- The minimised-record pill follows the bar, since it is positioned
  against it.

## 2026-08-10 — Inactive tabs (owner, pointing at Chrome for iOS)

A tab you have not touched in three weeks is not work in progress, it
is clutter. It now steps out of the grid onto a list of its own — still
open, still one tap away. This closes the hole `ios-m1-eval.md:49`
recorded and only half-fixed: serial-capture reuse stopped the app
MINTING junk tabs, and nothing until now cleared the ones already there.

- **The clock.** A `DeskTab` carries `lastUsed`, a packed civil stamp,
  set by one funnel (`touch`). Every activation path stamps, including
  ‹ ›, which assign `activeTabId` directly and would otherwise have let
  a tab age while you read it, and including a capture rewriting a tab
  it already owns.
- **One array, always.** Inactive is a PREDICATE over `tabs`, never a
  second collection — so closing, de-duplicating, the record prune, ‹ ›
  and the saved plane all still see every tab, and only the grid
  narrows. Two invariants hold it up and are asserted: the active tab is
  never inactive, and therefore the live set is never empty while any
  tab is open (which keeps "the empty desk IS the chooser" meaning "no
  tabs at all").
- **Persistence extends, never replaces.** A `used` map, keyed by entity
  id (a tab's UUID is minted fresh each launch), joins `ids` and
  `active` in the SAME UserDefaults record. The key is not bumped: a v2
  key would silently discard every open plane. A plane saved before
  today has no stamps and reads as "used now", so the first launch after
  the upgrade sweeps nothing. Verified on disk — the old `All` plane
  still has no `used` key.
- **What Chrome does that Liv does not.** Its grey subtitle under the
  row, its explanatory paragraph, and its blue inline "settings" link
  are all refused (owner, 2026-08-06: a sentence explaining a control is
  a design failure). The threshold rides as a chip on the row; each card
  carries its own age in the kind footer it already had. There is no
  navigation push either — this shell has no navigation stack, so the
  list wears the same 40pt band every full-screen surface wears.
- **Close all asks nothing and offers no undo**, deliberately: a tab is
  device state, so closing one writes NOTHING to the box. Every note and
  file stays in search, in Everything, in its workspace. The undo chip
  means "a transaction was written" and none was.
- **Per workspace for free** — planes were already stored per workspace,
  and the stamps ride in the same record.
- Settings gains one picker: 7 / 14 / 21 days / Never. Never is
  lossless both ways, since nothing was ever closed.
- `close()` now hands the desk the most recently used LIVE tab rather
  than the plain index neighbour, which could drop you on a three-week
  old note you never asked for.
- The tab count in the footer and on the bottom bar counts what the grid
  SHOWS; the inactive count lives on its own row.
- **Seams:** `TabSwitcher` moved out of Desk.swift (1,159 lines) into a
  new `Tabs.swift`, and `LivTabs` — the rule itself, in a type — lives
  there too. Desk.swift is 922. Chrome.swift is still 1,485 and remains
  the file most in need of a seam.
- `livTabsSelfCheck()` (`-tabs.selfcheck 1`), 22 assertions: the age
  arithmetic including month boundaries, a clock that moved BACKWARDS
  reading as 0 rather than sweeping everything, the >= boundary at the
  threshold, "Never", both invariants, and that the tab you are looking
  at survives Close all even at 90 days. It caught one wrong expectation
  of mine on the first run.
- `-desk.boot inactive` opens tabs and backdates them, because nobody
  can wait three weeks to look at a screen.

Checked live: revive (7 → 6, the card back in the grid), Close all (row
gone, two tabs left), and the persisted plane read off disk.

## 2026-08-10 (small) — seven owner notes

- **"Today" is dressed as a button now.** As plain accent text beside
  the month it read as a label announcing the selected day rather than
  a verb that takes you there. It is a 26pt tinted pill in a 40pt tap
  target, and its spoken name is "Go to today", not "Today".
- **The month grid pages by swipe.** Left for the next month, right for
  the previous — the same verb the ‹ › chevrons run, so there is one
  step() and one place the selection rule lives. The grid slides the
  way the finger went. Deliberately blunt (44pt of travel, clearly more
  sideways than vertical) so a finger sliding off a day cell never
  turns the page; day cells answer to taps and are untouched. Checked:
  swipe left → September, twice right → July, Today → back to August,
  and a plain tap on the 15th still selects it.

- **The calendar's blocks were see-through, so the hour rule was drawn
  across every event.** An event filled at 20% over the canvas; the
  grid behind it showed through. The fill is opaque now — the same tint
  laid ON the canvas rather than over whatever is behind — so a block
  covers the grid instead of tinting it. One recipe (`blockFill`) for a
  real event and a draft, so they cannot disagree. The colour is
  unchanged: `(20,44,70)` before and after.
- **The first hour of the day was sliced in half.** Each time sits 6pt
  above its own rule; at the top of the grid that 6pt fell outside the
  scroll, so "00:00" was cut through the middle under the TODAY
  heading. The rise is a named constant now, used both to lift the
  label and to reserve the room.

- **The calendar's hour rules were drawn through the clock.** Each hour
  line started at x=0 and ran under its own "09:00", crossing the text
  out. The time column now has ONE number — `CalClock.gutter` — and the
  rule, the now-line and the blocks all measure from it. There were four
  numbers before (0 for the rule, 16 for the label, 44 for the now-line,
  60 for the blocks, written twice), which is how they drifted apart.
  Verified by pixel: the rule's left edge is at 46.0pt and the last
  digit ends at 38pt, an 8pt clear gap.
- "Add a file" wears the create menu's own dress now — it sat
  left-aligned in a column of centred verbs.
- Todoist-style inline capture parsing REFUSED and recorded (owner:
  "too non-obvious, too much freedom"). Dates and filing stay as chips
  and Inbox suggestions, never live parsing of the typed line.


## 2026-08-09 (night) — four of the five data-model trims

Approved as T1-T4 + T6; T3 (table-driving the 18 seed functions) opens
the next batch with a pre-trim box fixture — it touches every
box-creation path and deserves its own verification matrix rather than
the tail of a long day.

- **T1 — the name index.** The store now keeps "who claims this name"
  beside the backlink index, maintained in the same two places cells
  change. `property_id` — the lookup behind ~197 call sites, and the
  cause of both quadratic scars — reads it instead of scanning. Failing
  test first: the same thousand lookups over a 4x bigger box; the scan
  failed at 3.2x, the index passes at ~1x, and re-inserting the scan
  makes the guard fail. Measured: 21 ms of lookups became 14 µs.
- **T2 — three dead bootstrap properties unseeded** (default-view,
  renderer, config). Their ids stay reserved forever; old boxes keep
  the rows harmlessly. The review had claimed FOUR were dead — `query`
  is load-bearing (workspaces store their lens in it) and stays. Trust
  but verify, even the auditors.
- **T4 — one "user entities" iterator** in the store: not trashed, not
  plumbing. The filter that, forgotten once, leaked starter types into
  Everything and damaged 9 of 20 early boxes can now not be forgotten.
  Four files' hand-rolled copies converted mechanically; the remaining
  sites keep their exact semantics and get audited with T3.
- **T6 — the one 5,785-line FFI file is three files**: the verbs
  (2,226), the snapshot types + builder (842), the tests (2,734). No
  wire change, no header change, 71 FFI tests green.

317 Rust tests, zero warnings, all six shell self-checks pass.


## 2026-08-09 (later) — the drag takes the touch back, and contents leave the facts

- **Dragging over a button no longer presses it** (owner). Getting
  there took four attempts, and the honest record matters: the panel
  drag became a real UIKit recognizer (PanelDrag.swift) that latches
  only on horizontal, deliberate movement — but UIKit's three levers
  for taking the touch away (touch cancellation, recognizer exclusion,
  delayed delivery) ALL failed to reach SwiftUI's buttons, each proven
  live by the row still firing. What works is SwiftUI's own mechanism:
  the desk disables its whole tree the instant a drag latches, which
  cancels any in-flight press. A tap never latches, so taps are never
  disabled. Verified: a drag starting ON a row moves the panel and
  fires nothing; a tap on the same row opens its view; a drag across
  the properties panel's due row opens no sheet. Also found while
  verifying: the let-go arithmetic was inverted for CLOSING drags (a
  57% pull away snapped back open); the flick threshold was low enough
  that a moderate release read as a flick; and a drag could not START
  over a file preview, fixed with a 24pt edge exemption — the screen's
  edges belong to the panels, whatever sits under them. `-drag.off 1`
  bisects the recognizer like the calendar's.
- **File contents never share a surface with properties** (owner). The
  file tab is the name and the BYTES, full bleed — the way a note tab
  is the note. The facts live behind the (i) door exactly as they do
  for a note.


## 2026-08-09 — files, and panels that follow your finger

**Panels are dragged, not flicked** (owner: "drag into properties and
global view instead of only swiping and letting go"). The library and
the properties panel now track the hand: push halfway and they sit
halfway; let go and they finish the journey or go back, decided by
where you stopped or how fast you threw. The old anti-flicker rule
survives as a LATCH — nothing moves until the gesture proves it is
horizontal and deliberate, and once it has, it owns the rest of that
drag. Verified: a 40pt drag snaps back, a vertical scroll starts
nothing, a full drag opens.

**Files: a file of any format is now an ordinary item.** The bytes stay
as a file; the box records a reference (path + a hash of the content)
and the same six fields everything else has, so a contract is filed by
area and project exactly like a note, and answers to the same
workspaces and searches. That is the whole answer to "a folder can only
hold a thing in one place".

- **A shipped bug is fixed.** A file had no kinds, so it fell through to
  "document" and opened as an EMPTY MARKDOWN EDITOR over a real file.
  `TabShape` checks for a file FIRST, because having a file crosscuts
  the six kinds — a scanned contract is a file and can also be a task.
  There is no seventh kind.
- **The file view**: the name (yours to change, and changing it never
  touches the file on disk), a class glyph and format chip, "Open in…",
  Apple's own renderer showing the bytes, then the same facts rows as
  every other item. A missing file says so plainly and keeps the entity
  — its filing is still real.
- **Three core verbs that had ZERO callers are wired**: add-by-reference,
  re-hash, and extracted text. Opening a file re-hashes it, so Liv
  learns that Word saved without a watcher or a timer.
- **A phone import COPIES.** Found live: the file picker hands back a
  path inside another app's container, readable only during that one
  callback, so recording it produced an entity whose file was "moved or
  deleted" the moment you looked again. Liv's copy becomes the truth,
  the way photos already work. On the desktop, where paths are stable,
  the same core verb records the path in place.
- **One glyph table** (owner: no two code bits solving the same
  problem). Two had drifted, so the same file showed a photo icon in one
  list and a document icon in another; a spreadsheet and a contract now
  look different, from the format alone.
- Liv never writes those bytes. Word owns the words.

Fixed while testing: the Option C tab prune was closing FILE tabs too —
a file is a document you work on and keeps its tab.


## 2026-08-08 (later) — the scalability answer, and three measured fixes

A three-lens review with two adversarial passes compared this app to the
Tauri app it replaces. Verdict: **not heading there** — one data store
against three, one file touching the core against seventy, one way to
open a thing against four, 316 model tests against one test file. But it
found one real, measured failure and two habits pointed the wrong way.

- **The snapshot was quadratic.** `vault::expected_files` resolved the
  `daily-note` property by scanning the whole store — once per entity —
  and it runs on every snapshot. Measured on the release build BEFORE:
  12 ms at 500 entities, 19 at 1,000, 62 at 2,000, 195 at 4,000. AFTER
  hoisting the lookup out of the loop: 2.3 / 3.8 / 6.2 / 11.0 ms —
  eighteen times faster at 4,000 and linear. Extrapolated at 10,000 that
  is ~28 ms instead of ~1.2 s, on a machine much faster than a phone.
  The field it computes, `vault_path`, is not read by the phone at all;
  it stays on the wire for the desktop, per the additive-ABI rule.
- **A cost test now guards it** (`services/tests/scale.rs`) — the first
  test in the project that measures price rather than correctness. It
  asserts the SHAPE, not a millisecond budget, so a slow machine cannot
  fail a build. Verified by putting the scan back: it fails with
  "doubling the box multiplied the work by 2.87x".
- **Refreshes coalesce.** One typed task fires four writes, each of
  which scheduled its own full re-read; only the last answer is ever
  seen. Now one read is in the air at a time and a request made during
  one is re-run when it lands — collapsing the burst without ever losing
  the final state.
- **Search stopped hiding results.** The core ranks everything, sends
  the first 200, and reports the true total; the shell decoded the page
  and threw the total away, so a query matching 1,800 things looked like
  it matched 200. It now says "Showing 200 of 1,800 — narrow the
  search".

Nine standing rules went into CLAUDE.md, each one derived from a
measured difference between the two codebases.

## 2026-08-08 — Option C: records are edited where you stand

**A tab is a document. Nothing else.** Notes, templates and untyped
captures land as tabs, exactly as before. A task or event now rises as a
CARD over whatever you are looking at, and closes nothing — tapping a
task inside Tasks used to throw you out of Tasks and leave an orphan tab
behind. Verified: Tasks stays fully up behind the card.

**One door decides.** `desk.open` branches on kind and every one of the
~23 call sites gets it for free. The kind is read from the live snapshot
at the moment of opening, never cached, so a freshly created record
cannot be mistaken for a document for a frame.

**A swiped-away card becomes a pill** above the bottom bar — one at a
time, like a mail draft — and tapping it restores the card. This answers
the owner's one reservation about cards: you can go read something else
and come back. Verified: card → swipe → pill → tap → card, with Tasks
intact throughout. Every record edit saves as you make it, so the pill
carries no unsaved work.

**The card presents from the frontmost surface, never the desk.** UIKit
gives one presentation per presenter, so the desk raising a card while a
full-screen view was up tore that view down — the exact context exit
this change exists to remove (found live). Each cover now hosts its own;
the desk hosts only when nothing covers it.

**Old tabs holding tasks close quietly on first launch** after the
change. Verified: 36 tabs → 17.

**Deleted, per "no dead code":** the record branch of the desk tab body,
the kind guards on the (i) door and the ••• menu, the kind test in the
left-swipe gesture, and "Photo" from the create menu (the camera is
reachable from the capture sheet, and scans are later work).

**The New Tab screen is a create menu now**, in honest order: documents
first (note, template), then records (task, event), then Open…. The word
"scrap" — which the owner never chose — is "capture" in the two places
it reached the interface.

## 2026-08-08 (earlier) — three fixes

- **Appearance now changes the sheet you are standing in.** It was set
  with SwiftUI's scheme preference, which only reaches the view tree it
  is attached to; a sheet is a separate presentation, so flipping the
  setting from inside Settings changed everything except Settings. It is
  set on the window now, which reaches every presentation there is.
- **The one vertical rule in the app is gone** — the coloured bar on
  Today's timed rows. It encoded "task or event" a third time (the
  status ring and repeat glyph already say it) and, being the only
  vertical line anywhere, read as random.
- Pushed to the owner's iPhone.


## 2026-08-08 — the owner's fourth note batch

- **Light mode** (owner: "add light mode button"). Every colour token is
  now a dark/light pair resolved by the system's appearance machinery —
  including the editor's, which draws through UIKit and picks the pair
  up at render time. Settings gained an Appearance control: Dark /
  Light / System. Dark remains the default. Verified in light: editor
  (divider drawn), calendar, Today, Settings.
- **The calendar grid is hourly; hands land on the quarter hour**
  (owner). The half-hour line — dimmer than every other line in the app
  for a reason nobody could state — is gone. Tapping empty space drafts
  the event at the nearest 15 minutes (verified: a mid-band tap wrote
  02:15); dragging already stepped by 15.
- **Separators follow one law now: a line sits BETWEEN two neighbours.**
  Rows used to draw a line under themselves even as the last row of a
  section, leaving lines floating over gaps (owner: "placement makes no
  sense"). The left panel and the whole properties panel (schedule,
  filing, other, suggestions, the due sheet) now draw dividers only
  between rows. The one "randomly dimmer" line was the calendar's
  half-hour rule — also gone. border2 survives only as the outline of
  the two dashed "add" affordances.
- **The revealed divider sits exactly where the drawn line sits.** Two
  causes: the revealed dashes rendered in the small marker font, which
  changed the line's height (the page jumped ~2pt on caret entry); and
  the drawn rule anchored at half the line height while a dash's ink
  centre sits higher. The dashes now keep the body font, and the rule's
  position is read off the font's own dash glyph. Measured: 0.17pt
  apart, invisible.
- **"switch" micro-text in the left panel's workspace row** — a purge
  survivor — deleted.
- Pushed to the owner's iPhone (build.sh device run).

## 2026-08-07 (later) — one title cleaner, a surviving draft, a divider you can edit

- **Syntax can no longer appear in a title, and exactly ONE code bit
  guarantees it** (owner: "no two code bits solving the same problem").
  The core's title cleaner now strips INLINE syntax too — bold, italic,
  strikethrough, code ticks, and [[…]] link tokens (a named token reads
  as its name) — with rules that mirror the editor's own scanner to the
  letter. Twelve new test cases, including the two the old greedy trim
  got wrong: a line STARTING with bold ("**Bold start** rest" used to
  come out "Bold start** rest") and a checked box keeping its brackets.
  The Swift side then stopped cleaning: `livRowTitle` shows what the
  core sends, full stop, and also maps the core's "#id" placeholder to
  "Untitled" so no list ever shows a hash-number. The panel's duplicate
  `displayName` was deleted. `livDisplayTitle` survives ONLY for text
  the core has not seen yet (the live typing preview, the capture
  sheet's draft, a template body) — different problem, same look.
- **A suggestion now survives typing.** Saving a note's text used to
  retract every pending suggestion on that note, assuming the automatic
  sweep would re-derive it. Only the sweep's own five proposers qualify
  — their drafts are pure functions of the words. Anything else (a
  model's suggested title, a draft from another device) cannot be
  rebuilt, so retracting it on a keystroke destroyed it silently. New
  `clerk::rederivable` is the one place that says who re-derives; the
  save retracts those and keeps the rest. This unblocks AI titles.
- **The divider shows its dashes under the caret** (owner: "putting the
  cursor on a separator should make it appear as ---"). The styling
  pass now takes one piece of caret state: the paragraph the caret is
  in. A rule line in that paragraph renders as dimmed literal dashes —
  the same treatment every other marker gets — and snaps back to a
  drawn line the moment the caret leaves. Verified in pixels both ways.

## 2026-08-07 — two de-duplications, ahead of any Android work

Both were already wrong; neither is speculative work for a port that
has no start date.

**One answer to "what is this called".** Eight files each had their own
version, with four different words for nothing ("Untitled", "untitled",
"#id", ""). Two of them still re-read the content cell to find a first
line — work the core has done since this morning. Now there is
`livRowTitle` in Kit.swift and nothing else.

It still runs `livDisplayTitle` on top, and that is deliberate: the core
strips BLOCK markers (`#`, `-`, `>`) but not INLINE ones, so a first line
reading `**Pack** the van` arrives with its asterisks. Mirroring that
scanner in Rust would create a second copy of the very thing this
removes. It stays in Swift until the whole scanner moves, which is a job
for when Android actually needs it.

**One gregorian calendar.** `Civil.date(ofDay:)` was `private`, so five
other files wrote the noon-anchor trick out again — Calendar, Capture,
Tasks, Today and the due sheet's own formatter. Five copies of a
daylight-saving workaround is how a real bug eventually arrives. `Civil`
now also owns `date(day:hhmm:)`, `day(of:)`, `hhmm(of:)`, `weekday(_:)`
and `daysBetween(_:_:)`, and the copies are gone.

Verified live rather than by reading: the month grid still starts on the
right Monday, stepping forward two months and back three lands on July
2026 with 1 July on a Wednesday, and the Tasks list correctly drops the
"Weekend" swipe today — because today is Friday, so the weekend already
is tomorrow. That last one exercises the shared weekday function
directly.

The shell went from 15,980 lines to 15,904 and lost nine private
calendars.

## 2026-08-07 — titles say what a thing is called

**One line of Rust.** The snapshot's `title` was filled by
`liv_views::summary`, which returns the name cell if there is one and
otherwise **the whole body flattened into one line, cut at 72
characters**. So a note reading "Trip planning / Ask Steven about the
rack. / ## Gear / - Boots" reached every list as
`Trip planning Ask Steven about the rack. ## Gear - Boots`.

It now calls `liv_services::content::display_name`: name cell, else the
first non-empty line with its block marker taken off, else `#id`. That
function is `source_name` from phase 3, promoted out of `tasks.rs` — the
one place that already got this right, because the note-task chips
needed it. Its checkbox-marker reader (`task_words`) is now shared with
the task projection instead of duplicated.

`summary` is unchanged and still used by the CLI's list lens. It means
what it says; it was simply never the answer to "what is this called".

Owner-authorised change of MEANING on an existing snapshot field
(CLAUDE.md's ffi rule says additions must be purely additive). Failing
test first: `services/tests/tasks.rs
display_name_is_the_first_line_not_the_whole_body`, six cases including
a heading, a blank first line, a `---` rule line, an explicit name, and
an empty note. `ffi/liv.h` documents the new meaning. 313 Rust tests
green, six shell self-checks green, verified on screen.

## 2026-08-06 (later) — the second fix batch

- **The divider stopped moving.** Every styled paragraph carries 2pt of
  line spacing, and iOS adds that 2pt to the bottom of a line only when
  another line follows it. The rule was painted at the middle of the
  text's box, so pressing Return under a `---` grew the box and dropped
  the rule 1pt. It is anchored to the top of the line now. Measured in
  the screenshot: identical pixel row before and after the Return. The
  checkbox had the same latent bug and got the same fix.
- **Headings got bigger and brighter.** One recipe serves 28 section
  headers; it went from 11pt bold at 6.5:1 contrast to 13pt semibold at
  11:1. The quietest grey (#707078) read at 3.7:1 — below the 4.5:1
  readability minimum — and carried text in 36 places; it is #8E8E93
  now, 5.5:1. Five hand-rolled 9.5pt headers and two 9pt calendar
  labels now use the shared recipe or clear the 11pt floor.
- **The date editor is two groups, not five rows.** Today, Tomorrow and
  "Choose a date" all answer the same question, so all three are now the
  same kind of row; "Choose a date" opens a month calendar under it
  instead of a small popup. Time is its own group.
- **A due date always carries a clock time now** (owner). The "Add a
  time" opt-in is gone and so is the hidden 09:00 the reminder code
  invented for dates without one. A due you set without thinking about
  the clock takes the time it is now. Verified: tapping Tomorrow wrote
  `202608072338, date_only:false` — the day tapped, at the current
  minute, in one transaction.
- **Reminders lost their lead times** (owner). The two "At time / 10 min
  / 1 hr" pickers were invented, never specified, and only ever affected
  dues that carried a clock time. Deleted, with their stored settings
  and the 09:00 constant. A reminder rings when the thing is due.
- **The event capture card can pick a real time.** It offered 24 whole
  hours and nothing else, against the standing rule that an arbitrary
  date AND time must be reachable wherever a date can be set. That rule
  was recorded on 2026-08-05 and this control was missed when the other
  one was fixed.
- **Properties says which item it is.** The panel's top line is the
  item's name — grey "Untitled" when it has none — with the type as a
  chip below it. It used to be the chip alone, so a panel swiped over a
  note announced "note" and never said which note, and the same type
  then appeared again as a row further down.
- **Only editable things get rows** (owner). "type" and "created" were
  rows that looked like every other row and did nothing when tapped.
  Type is the chip; created is one quiet line at the bottom.
- **An empty note's title line reads a grey "Untitled"** (owner),
  reversing design/ios.md's "no placeholder text at all".

### Then a review of the batch found ten more, nine of them fixed

Five reviewers read the change, each finding was then attacked by a
skeptic, and 18 of 33 reports survived — deduplicating to ten real
defects. Four were introduced by the batch itself.

- **The rule was drawn crooked.** Its left edge measured from the
  container while its width measured from the text column, so it poked
  3pt past the text on the left and stopped 7pt short on the right.
  Measured after the fix: equal 17pt gutters.
- **A separator longer than about 50 dashes wrapped**, and since its
  characters are now invisible the note showed the rule followed by a
  blank gap nobody could explain. The rule line no longer wraps.
- **The date sheet deleted every event's duration.** `write(day:)` always
  passed no end, so touching the time wheel on a 09:00–11:00 meeting
  threw away the 11:00. The end now moves with the start. The arithmetic
  moved into `CalClock` where the calendar's self-check covers it —
  nine new assertions.
- **Removing the 09:00 made ordinary tasks ring at midnight.** Three
  quick-add rows still write a bare date. A due with no clock time now
  rings not at all, which is what "a date reminder shouldn't be a thing"
  means; anything you date through the sheet has a time and still rings.
- **A due set to exactly 00:00 was re-read as having no time** and
  silently replaced on the next edit, and it showed up in the all-day
  strip. The stored flag decides now, not a guess at the digits.
- **Ticking a note's checkbox from the Tasks list could fail forever.**
  Re-encoding the note promoted a `[[…]]` pointing at nothing into a
  real link, which the core refuses outright — so the tick never landed,
  silently, every time. The editor has always passed the guard this
  path lacked.
- **Setting a due from the capture strip left no trace**: no chip, and
  "+ Due" kept offering itself. It reads the result back now.
- **"Untitled" appeared for notes starting with a hash** — the test for
  the core's `#id` placeholder matched any leading `#`.

### The default time became 09:00, and all-day belongs to events

Owner, 2026-08-07: the current time was the wrong default — a task typed
at 23:47 was due at 23:47. One constant now says what "no particular
time" means: `LivDue.defaultHHMM` = 09:00.

The rule about who keeps "no clock time" is `LivDue.carriesTime`, four
self-check assertions:

- an **all-day event** stays all-day when you change only its day. A
  holiday is not due at 09:00. Touching the clock is what gives it one.
- a **task** always gets a moment. A task with no clock time cannot ring,
  and ringing is most of what a task's date is for.

Three quick-add rows still wrote a bare date, which after the reminder
change meant they could never ring; they write 09:00 now. The Tasks
list's Tomorrow/Weekend swipes also used to wipe an existing time —
they keep it.

Verified in the saved data both ways: the all-day event "Dentist visit"
moved 4 Aug → 8 Aug and stayed all-day; a date-only task moved and came
back as `202608080900` with a real time.

## 2026-08-06 — the owner's fix batch (six notes)

- **A divider is a LINE now.** `---` was detected and then only dimmed —
  nothing ever drew anything, so the "divider" shipped in phase 2 was
  three grey dashes. The glyphs go clear and the layout manager paints a
  rule across the text container, the same mechanism the checkbox uses.
  Verified in pixels this time, not in the box log.
- **Non-documents stopped being edited like documents.** Every desk tab,
  of every kind, rendered `NoteEditor`, so a task's name was line 1 of a
  markdown buffer and its facts hid behind a swipe. New `TabShape` +
  `RecordBody`: a task or event opens as a NAME (one line), its
  properties AS the body (the inspector's own rows, embedded — one
  implementation, not two), and optional plain-text Notes. The (i) door
  disappears on a record because the panel would duplicate the screen;
  ••• drops the note-only verbs (template, share, export).
  Notes/scraps/templates are unchanged.
- **Calendar items are named in the calendar.** Tapping an hour used to
  create an untitled event and throw you into the note editor. It now
  draws a draft block at that hour with a name field in it; the box
  learns nothing until you submit. Verified: tap → 0 writes, submit →
  exactly 2 (`new event` at the tapped hour, `set name`).
- **Settings is a settings screen.** It opened with the raw container
  path, an entity count, and a wall of field names, then the whole
  phone→desk funnel. Now: Suggestions, Reminders, Fields (as chips) —
  and one **Advanced** row holding Handoff, the box facts and the
  version. The notification line only speaks when a reminder will NOT
  arrive.
- **Micro-text purge.** The stamp footnote was copy-pasted under five
  surfaces; the header's LensChip already said it, so all five are gone.
  Also: the workspace selector's monospace subtitles ("Everything — no
  lens, no stamp", "no query"), two grammar lectures under the query
  fields, "A filter only filters — it never stamps.", the Inbox's grey
  "shows every workspace" (a chip now), the Settings assist essay, and
  "Add your own field…" → "Add field".
- **The Properties panel lost its "Properties" title.**

- **The five calendar-block accessibility actions are gone** (owner).
  They were added in phase 4 without being asked for. The dead
  `CalendarDuePick` sheet they were the only caller of went with them.
  Tap-to-open and drag-to-move both re-verified after the removal (one
  `set due`, 22:00 → 21:00).

Found and fixed while verifying, not on the list:
- Tapping an existing calendar block created a NEW draft on top of it —
  the hour band's tap and the block's tap fought over the same point and
  the band won. One `SpatialTapGesture` owns the grid now and resolves
  blocks first.
- A record's name committed TWICE (Return, then blur, with the snapshot
  still stale) — one rename, two transactions in the box.

## 2026-08-06 — Phase 7: Share & Export

- The ••• menu earns its secondary actions: **Share** (markdown text to
  the system sheet) and **Export as Markdown** (a real `.md` file, so
  Save to Files produces markdown). Verified live: the sheet opened on
  "Roof project · 2 KB" with Copy / Save to Files.
- Both are READS — no box write. One flattener (`SpanText.spansToText`),
  an `# H1` title added only when the note's own first line does not
  already state it, and a filesystem-safe capped filename that is never
  empty. Sixth self-check suite: `-share.selfcheck 1`, 12 assertions.
- An empty note refuses to share instead of handing over a blank file.
- **Toolbar vertical lock, third attempt** (owner: "insertion menu is
  still not locked vertically"): the horizontal scroller now has a
  delegate that resets `contentOffset.y` to zero on every scroll event,
  plus `isDirectionalLockEnabled`. Constraint-level pinning and the two
  bounce flags were already in place and evidently not enough. A
  synthesized vertical drag on the row does not move it — but a
  synthesized drag is not a finger, so this needs the owner's eye.

## 2026-08-06 — Phase 6: the templates ruling

- **Templates stay, with the banner** (owner). No code change was
  needed — the safeguard shipped in rev 6 and became a floating pill in
  phase 4 — so this phase was verification: opening a template shows
  "Template · New note" in the doors' band, and tapping it created a
  fresh note with `{{date}}` resolved to today while writing NOTHING to
  the template (box log: 2 transactions, both on the new entity, zero
  on the source). The misuse the ruling was about is prevented.

## 2026-08-05 — Phase 5: Today & Inbox, redefined

- **Today answers "what now?"**: LATE is a strip you cannot miss and
  means only what can still be DONE (incomplete tasks — a past meeting
  is not late, it happened); the day is ONE now-aware timeline (passed
  dims, next is lit, done collapses to a line); task/event colour comes
  from the Calendar's own language; chips carry project/person instead
  of the row's own type; reschedule KEEPS the time of day and a span's
  end; archived rows are excluded at last.
- **The Inbox is the decision queue**: one list, two sections, no modes
  (the old Route/Tidy segments were `Text` in capsules — no button, no
  state, tappable by nobody). Route cards carry full-width verbs that
  FINISH the object — Task lands with its first status, Event opens the
  date editor — each with a 5s Undo chip that reverses every
  transaction it made (verified: 2 writes in, 2 undos out). Suggested
  shows the clerk's pending proposals grouped by proposer with ✓/✗ and
  Accept all; ✗ asks once because a decline is permanent; assist-off is
  its own line, not a silent empty list.
- **One date editor everywhere** (owner: arbitrary time everywhere):
  `CaptureDuePicker` wrote date-only with no time control at all, so an
  event captured through the sheet could never have one. Deleted; every
  call site now opens `DetailDueSheet`.

## 2026-08-05 — Phase 4: the day hour grid

- The day panel is Apple Calendar's shape now: all-day band (timeless
  tasks keep their ring), a 24-hour scrollable grid with timed items as
  positioned blocks, a red now-line, and the view opening at now.
- **Tap an empty hour → an event at that hour**, landing as a desk tab
  for naming. Verified three times against the box log (16:00, 15:00,
  19:00 — `date_only=false`, exactly the band tapped).
- New `CalClock` pure layer + a fifth self-check suite
  (`-calendar.selfcheck 1`, 15 assertions): minutes/HHMM round trips,
  quarter-hour snapping, duration from a real end vs none vs a
  cross-day end, and the range label. It caught one of my own wrong
  expectations before the device did.
- **Drag-to-move SHIPPED, in UIKit** (owner: "do the UIKit drag
  properly"). Press a block, move it, release: 15-minute steps, live
  preview, one `setSpan` — verified twice in the box log (15:00→16:00,
  16:00→17:00). SwiftUI could not do it; the recognizer lives on the
  WINDOW, hit-tests in the grid's content space, and suspends scrolling
  only while a block is in the air. Taps still open blocks and the grid
  still scrolls (both re-verified, the latter with a `-drag.off 1`
  bisect switch built for the purpose). [Five accessibility actions were
  added here unasked; removed 2026-08-06 on the owner's word.]
- **Overlapping blocks split into columns** (`CalLayout`, pure +
  6 self-checks) instead of stacking where the one underneath was
  unreachable.
- Fixed along the way: `-desk.boot <feature>` was silently wiped one
  frame after being set (broke headless feature verification), a
  container a11y label that hid a block's status ring, an iOS-18-only
  SF Symbol that drew nothing, and the scroll indicator sitting on top
  of in-block controls.

## 2026-08-05 — Phase 3: tasks that mean something

- **The checkbox↔task gap is closed.** Every open `- [ ]` line in a live
  note now appears in Tasks under "In notes", carrying a chip that names
  and opens its source note. Checking a row edits that note's text
  through the editor's own toggle op, CAS-guarded — verified in the box
  log (one line flipped, everything else byte-identical).
- New `services/src/tasks.rs` projection (stores nothing, creates
  nothing) + an additive optional `note_tasks` snapshot key; three new
  Rust tests, `liv.h` documented; whole workspace green (40 suites).
- Found while building: nondeterministic `entities()` order (now
  sorted), the flattened-title trap for the third time (the note's name
  is now computed in Rust where the content is), empty checkboxes
  projecting as noise, and a `lineStart` off-by-one the editor
  self-check caught. Details in `design/tasks-study.md`.

## 2026-08-05 — Phase 2: the editor's `+` insertion menu

- The toolbar is the Notesnook shape now: a short daily row (undo, redo,
  heading, bold, italic, task, bullet, indent, outdent) with `+` as the
  first key — a native pull-up menu holding Link, Template, Numbered
  list, Quote, Strikethrough, Code, Divider, Outline. Same verbs, only
  the door moved.
- Found live while verifying: the Divider verb parked the caret at the
  end of the inserted `---`, so typing corrupted it into `---text`. It
  now lands the caret on a fresh line below; two new editor self-checks
  pin the behavior.
- Verified on simulator + box log; on the owner's device.

## 2026-08-05 — Phase 1: hardening close-out

- All 23 audit findings now adjudicated (the quota-killed 14 re-run
  against post-fix code): 12 fixed, 9 refuted, 2 confirmed core-side
  and filed as owner-gated chips (assist-toggle name/id mismatch; FFI
  triage vs merge proposals).
- Capture sheet Undo now takes back the WHOLE capture (trash of the
  saved entity + the adopting tab closes) — verified in the box log.
- Duplicate note per the owner's ruling: copies the type, skips
  reference/file cells (display-value re-adds could mislink).
- Swipe gate verified (selection drags can't open panels); link picker
  dismisses when a panel slides over it, and its dismiss-suppression
  ordering bug died; notification taps now dismiss Settings/workspace
  sheets too (lifted into the model) and every in-hierarchy overlay
  animates out on open().
- Template banner became a floating pill in the doors' band (no more
  dead space); Everything's Unfiled slice hides when the active LENS
  forces an area; merge proposals render their verb chips; suggestion
  buttons 44pt with per-proposal VoiceOver labels; empty-desk `+`
  disabled.
- Properties rows at the library's density (46pt / 15pt type).

## 2026-08-04 — rev 6: the Notesnook/ClickUp restructure + hardening

- Both side panels full-screen, swiped into from anywhere (one
  simultaneous drag on the desk; flick-gated so selection drags never
  trigger it), with the house close band.
- Library rebuilt: Views (Today, Inbox) / the workspace's own band
  (Calendar, Tasks, Everything — all wearing its lens) / pinned bottom
  (workspace switcher, Settings). Camera row removed.
- Everything now applies the workspace lens (+ LensChip); Today's
  recurring-occurrence loop was the one lens gap — closed.
- New Tab is an overlay chooser (never a tab); the empty desk IS the
  chooser; serial captures still land in one tab (adoptCapture).
- "New task" creates directly into the editor — first line is the name;
  the CaptureSheet now serves only events.
- Top-right: Properties door + ••• (secondary only: Duplicate note,
  Save as template, Move to Trash). Duplicate note ships (properties,
  not body; due copied structurally).
- Template banner safeguard ("edits change every future copy" + New
  note button).
- Keyboard toolbar transparent (keyboard material), hairline gone.
- **Suggested** in Properties: the deterministic clerk's per-note
  proposals with per-proposal ✗/✓; accepts write exactly the proposal
  (verified against the box log); assist consent toggle appears in
  Settings when the box carries the switch.
- Hardening (adversarial audit, 5 confirmed): capture-tab latch
  (consecutive creations rewrote a tab), title-reseed guard (external
  renames froze), chooser VoiceOver escape, 44pt labeled suggestion
  buttons, notification tap vs live capture sheet / open panels;
  Settings sheet re-hung on DeskHost; chooser entry animated.

## 2026-08-02 — rev 5: describe vs act

- ••• menu; Properties panel describes only; box-level Undo removed.
- Due editor: Today / Tomorrow / date picker / opt-in time / Clear.
- Trash closes the tab + 5s Undo chip; editor flushed BEFORE trash so
  the chip undoes the right transaction (found live).
- Bottom bar retires under the keyboard; toolbar vertical scroll fixed.
- Device builds: `shell/ios/build.sh device run` (signing bootstrapped
  once via a throwaway Xcode project; static-lib link lesson recorded).

## 2026-08-01 — rev 4: the three-zone model

Three zones, two doors, one-row bottom bar, panels as slide-overs;
six audit fixes (a11y dismissal, sheet lifetimes, zIndex, template
acknowledgment).

## Earlier (rev 1–3, July 2026)

The desk-first chrome, the markdown editor (TextKit 1, checkbox
painting, link picker, outline), templates v1, capture funnel +
satellite outbox, notifications, workspaces + filters, furnishing.
