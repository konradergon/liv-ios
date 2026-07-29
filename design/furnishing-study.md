# The furnishing study — how a fresh install should point the user

> A design investigation, 2026-07-29. Evidence-backed, adversarial about its
> own evidence. It does not change code. It answers one question: **on first
> open, what should be in the box, and what should the app ask?**
>
> Context that is settled and not re-litigated here: the six life-areas were
> shipped as six *workspaces* (M5-furnish); an architecture review found that
> makes filing an ambient mode you must be in *before* you type, and puts the
> most ambiguous axis in front as primary navigation. The owner has settled
> that the top-left workspace is a generic, user-made working-context switcher
> (preset fields + filter), that something recent-and-unfiled must stay visible
> regardless of filter, and that iOS is the only app being built.

---

## 0. The recommendation, up front

**Ship fixed TIME structure as the primary navigation, the six areas as an
optional FIELD, and nothing else. No area workspaces. No first-run interview.
No seeded fake content.**

Concretely, on first open the box contains: the `area` select with its six
values, the six kinds, the capture door, and four fixed views that are always
correct and never ambiguous — **Today**, **Upcoming**, **Everything**,
**Unfiled**. The workspace switcher exists but is empty (only "All"); the app
*offers* to make one once the user's own behaviour has earned it.

### The three things that changed my mind

1. **There is no browsable "everything" in the app at all** (§2.5). Four
   surfaces exist — Today, Inbox, Tasks, Calendar — and a typed, undated note
   falls out of every one of them after 24 hours. It is then reachable only by
   remembering a word in it. So the six areas were never really competing with
   a flat list; they were the *only* proposed route to anything old. That
   reframes the problem: filing feels like a gate because, without it, there is
   genuinely nowhere for a thing to live.
2. **Search is the retrieval mode people use least, and Liv's search is
   workspace-filtered** (§4.3, §2.6). People navigate to where they put things
   — 56–68% of retrievals versus 4–15% for search — and better search engines
   demonstrably do not change that. Meanwhile, searching "ear" from inside the
   Health workspace returns nothing and offers to create a duplicate. The safety
   net is both the wrong mechanism and holed.
3. **Choice overload is folklore** (§4.1). The jam study is 4 purchases versus
   31, non-randomized, with confounds its own authors flag; the pooled effect
   across N=5,036 is 0.02; Chernev's celebrated "rescue" paper contains its own
   unmoderated null. So the case against six workspaces cannot be "too many
   options". It has to be **ambiguity** (4 of 7 real captures had no defensible
   answer) and **gating** (you must be in the mode before you type). If we argue
   it on option-count we will lose the argument the first time someone counts.

The reasoning, the measurements, and the honest costs are below.

---

## 1. What I actually did

- Read `design/what-liv-is-for.md` (v2), `design/ios.md` §6 and §10,
  `shell/ios/Sources/Furnish.swift`, `Workspace.swift`, `CaptureSheet.swift`,
  `Inbox.swift`, `Today.swift`.
- Built the current shell (`shell/ios/build.sh`) and drove it on the iPhone Air
  simulator (`8E699FF6-…`) with `axe`, against **fresh boxes** created via
  `SIMCTL_CHILD_LIV_BOX_PATH`, with the app **uninstalled first** so device
  state (UserDefaults: active workspace, desk tabs) was also fresh.
- Walked **seven realistic captures** end to end, counting gestures, decisions,
  and — the core measurement — **moments where I could not confidently choose
  an area**.
- Cross-checked every write against the box with
  `cargo run -q -p liv-cli -- --log <box> list --all`.
- Ran two parallel web-research passes (app first-run behaviour; the empirical
  literature on choice overload and defaults).

Screenshots: `…/scratchpad/furnish2/`.

**Caveat on the first attempt.** My first "fresh box" run was contaminated:
a fresh box with a stale *install* shows ghost desk tabs and a stale active
workspace, because tab state and the active workspace live in UserDefaults, not
the box. Everything reported below is from a clean uninstall→install cycle.
That contamination is itself worth knowing: **"fresh box" ≠ "fresh install"**,
and any future first-run testing must uninstall.

---

## 2. What the current build does on first open — measured

### 2.1 The furnishing lands, and the user cannot see it

The furnishing pass works exactly as written. On a fresh box it creates the
`project` / `subjects` / `people` text properties, the `area` select with its
six options, and five area workspaces (Home re-aims the protected builtin):

```
#4155 project  #4156 subjects  #4157 people  #4158 area
#4159 Work (workspace, area:Work, 💼)      #4164 Work    (area option)
#4160 Health           …                   #4165 Health
#4161 Money            …                   #4166 Money
#4162 Family & Friends …                   #4167 Home
#4163 Learning         …                   #4168 Family & Friends
                                           #4169 Learning
```

**But the first screen shows none of it.** The workspace chip reads **"All"**.
The body is the verb stack (Capture an idea / New task / New event / Photo /
Open…) under the line *"A new tab holds one thing — capture it, then shape
it."* The six areas are one tap away, behind a chip whose label gives no hint
they exist.

> `01-first-open.png` — the whole promise of "arrives already organised" is
> invisible at the moment it is supposed to land.

Tapping the chip reveals the switcher (`02-workspace-switcher.png`): All ·
Home · Work · Health · Money · Family & Friends · Learning — each captioned
with its **raw query DSL** (`area:"Family & Friends"`). That caption is
engine-facing text in the most user-facing list in the app.

### 2.2 The default is "All", so the workspaces are dead weight

The active workspace defaults to `0` = All: no lens, no stamp. So in the
default state, **the six workspaces do nothing at all.** Every capture is
unstamped; every surface shows everything. The user encounters the six areas
only through the `+Area` chip after saving.

This is worth sitting with. **In its default state, the shipped build already
behaves like option (a) — six area *values*, no rooms.** The five workspaces
are a parallel copy of the same taxonomy that the default user never enters.
Removing them costs the default user nothing and removes the whole
mode-before-typing failure the review identified.

### 2.3 Seven chips, presented at once

After a save, the chip strip offers **Area · Status · Tag · Project · Person ·
Due · Type** (7 for a task, 6 for a note). "Sorting is a tap" is true only for
the first tap; the honest description is *choose one of seven doors, then one of
six values.* (`05-task-saved.png`)

I want to be careful here, because §4.1 disarms the obvious complaint: **there
is no evidence that seven options is "too many".** The problem with the strip is
not its length. It is that seven equal-weight offers say *nothing* about which
one matters, at the one moment the app has the user's attention and a concrete
thing in hand. The product doc says Area is "the one filing question"; the strip
does not.

### 2.4 The scenario walk

Seven captures, on a fresh install, counted honestly. "Gestures" = discrete
taps/toggles; one continuous typing burst counts as 1.

| # | What I captured | Verb | Gestures to capture | Gestures to file | Total | Could I confidently pick an area? |
|---|---|---|---|---|---|---|
| 1 | buy milk | Task | 3 | 2 | **5** | Mostly — *Home*, but *Money* defensible |
| 2 | call the accountant about the tax return | Task | 3 | 2 | **5** | **No** — Money vs Work |
| 3 | idea for the podcast: interview the guy who fixes church organs | Idea | 4 | (skipped) | **4** | **No** — Work vs Learning vs neither |
| 4 | dentist, 14:00 † | Event | 9 | 2 | **11** | Yes — Health |
| 5 | Anna's birthday present | Task | 4 | 2 | **6** | **No** — Family & Friends vs Money vs Home |
| 6 | book Viggo's doctor appointment about his ear | Task | 3 | (skipped) | **3** | **No** — Health vs Family & Friends |
| 7 | photo of the broken tap (caption + area + Done) | Photo | 5 | 3 | **8** | Yes — Home |

† I drove the time picker but left the date at today; the 9 includes a
conservative 3 gestures for the date picker I did not fully drive. Everything
else in the table was executed end to end.

**Ambiguity count: 4 of 7 (57%).** Two of those I refused to resolve at all,
which is exactly what a real user does.

Two of the four are not close calls, they are structural:

- **#6 is the canonical case.** Every canon Liv drew the six from (PARA, Wheel
  of Life, Things' own guide) means *your* health by "Health". A child's ear
  infection is your child's health, your family, and your Thursday. There is no
  right answer, and the app offers no way to say "both". *(§4.4 argues that
  allowing "both" would not help — given the option on their own data, people
  apply exactly one label 92% of the time and retrieve by two labels 0.1% of the
  time. The fix is to make the choice skippable, not multi-valued.)*
- **#1 and #5 are both "things to buy", and they land in different areas.**
  *buy milk* → Home; *Anna's birthday present* → Family & Friends. The one list
  a person actually wants when standing in a shop — "what do I need to buy" —
  cannot be built out of areas, because the area axis cross-cuts the action
  axis. This is not a taxonomy that needs tuning; it is the wrong axis for the
  most common retrieval.

Event capture (#4) is the expensive one: name → date chip → picker → Timed
toggle → time menu → hour → Save → +Area → value. Eleven gestures for "dentist
Tue 2pm", a phrase every competitor parses from typing.

### 2.5 There is no browsable "everything", so nothing can carry navigation

The finding that most changed my view, and the one I did not expect.

The feature grid holds exactly four surfaces: **Today · Inbox · Tasks ·
Calendar**. There is no flat list of everything. The snapshot carries an
`everything` section; no surface renders it as a browsable list. The verb
stack's "Open…" is the search overlay.

So I routed the podcast idea from the Inbox to **Note** (one tap, the intended
flow) and traced where it went:

- **Inbox** → now reads *"Inbox zero — captures wait here until routed."* It
  left, by design. (`31-inbox-after-route.png`)
- **Tasks** → not a task.
- **Calendar / Upcoming** → no date.
- **Today** → it appears in the "Captured today" strip, because
  `today_sections` defines *unstructured* as *has content ∧ no due*. But
  `capturedRows` filters `created == today`. **Tomorrow it is gone from Today
  as well.**
- **Everything** → does not exist.
- **Search** → yes, if you remember a word in it, and if you are in "All".

**A typed, undated note is browsable for exactly one day. After that it is
reachable only by recall.** That is precisely the failure
`what-liv-is-for.md` opens by naming as the enemy of simple tools: *"four
hundred notes and no way through them."*

And note the second predicate mismatch: `unstructured` is *content ∧ no due*,
but a task capture writes `name`, not `content` — so **tasks never appear in
"Captured today" at all**. Two different "unfiled" notions (Inbox: no kind;
Today: content ∧ no due), neither of which is *no area*, and neither of which
covers a named task.

This reframes the whole question. The six areas are not just an ambiguous
taxonomy — they are being asked to carry **all** of navigation, because no
surface offers navigation any other way. That is why filing feels like a gate:
if you don't classify, there is genuinely nowhere for the thing to live.

### 2.6 The safety net has a hole exactly where the ambiguity is

This is the second most important measured result.

`Inbox.swift` carries an explicit, correct, load-bearing comment:

> *"THE WORKSPACE LENS IS NOT APPLIED HERE, EVER … An unfiled thing must be
> reachable from every workspace, or a capture made under the wrong lens
> appears to vanish — the classic bug that hits every workspace system. This is
> a stated safety rule, not an oversight; do not 'fix' it."*

The rule is right. **The predicate is keyed on the wrong property.** The Inbox
shows rows where `kinds.isEmpty && contentPrint != 0` — i.e. **untyped** scraps.
Item #6 is a *task* with no area. It has a kind. So:

- **Inbox**: shows 1 unrouted item (the podcast idea). #6 is absent.
  (`23-inbox.png`)
- **Today → "Captured"**: counts `unstructured` (again: untyped) *and* applies
  the workspace lens. In Home it shows **0** despite seven captures that day.
  (`26-today-home.png`)
- **Tasks in "All"**: all four tasks, each with its area chip. This view is
  genuinely good. (`24-tasks-all.png`)
- **Tasks in "Home"**: one task. (`25-tasks-home.png`)
- **Search "ear" in "All"**: finds it. (`28-search.png`)
- **Search "ear" in "Health"**: **finds nothing**, and offers *Create "ear"* —
  inviting a duplicate. (`29-search-health.png`)

So an item you hesitated over is invisible in every area workspace, absent from
the Inbox, absent from "Captured today", and **not findable by search from
inside the very area you would most plausibly look in**. The stated safety rule
exists; it protects "no type", while the thing the app actually asks you to
decide is "which area".

### 2.7 Smaller things found in passing

- **Settings lists 44 fields**, including engine internals (`core-on-kind`,
  `digit-key`, `hide-when-empty`, `for-type`, `builtin`, `exception-of`),
  under a heading that the product doc promises will be six.
  (`30-settings.png`)
- The desk transiently rendered **"This entity is not in the box anymore."**
  immediately after a capture; a relaunch showed the entity fine. Snapshot
  timing, not data loss — but it is the first thing a new user sees after their
  first save.
- The **notification permission prompt** fires mid-capture, on saving the first
  timed event.
- Nested picker sheets take **>1.5 s** to settle — slow enough that the
  "sorting is a tap" feel is lost.
- The workspace switcher **resets the desk** to the empty verb stack (tab planes
  are per-workspace), so switching area loses your place.

---

## 3. What the field actually does (2025–2026)

Research pass; sources cited. Confidence grades: **(a)** verifiable primary,
**(b)** vendor-reported, **(c)** opinion/eyewitness, **(d)** measured but
uncontrolled.

### 3.1 The headline: nobody has published a controlled test

There is **no published A/B test isolating seeded sample content against an
empty state with a call-to-action.** What exists is design guidance, uncontrolled
before/after numbers, and a large volume of onboarding blog content built on
statistics that trace back to nothing. Two major design systems endorse seeding,
four don't. **Anyone quoting an activation lift for seeded content is repeating
an untraceable number.** Design this on judgement, and say so.

### 3.2 Things 3 — the most relevant precedent, and it cuts both ways

- Fixed time views (Inbox / Today / Upcoming / Anytime / Someday) are the
  product; **Areas and Projects are user-created and start empty.** Cultured
  Code state it plainly: to-dos are seen by *context*, "provided by areas and
  projects **that you create yourself**", or by *when*.
  ([support article 4001304](https://culturedcode.com/things/support/articles/4001304/)) **(a)**
- **Things does ship a tutorial project** — "Meet Things iOS" / "Meet Things
  Mac" — **offered, not forced**, per device, recreatable from the Help menu.
  ([Recreating the Tutorial Project](https://culturedcode.com/things/support/articles/2803553/)) **(a)**
  The design trick worth stealing: the sample content is *real work*. You
  complete it and it goes to the Logbook. **It disposes of itself through
  normal use** — no "delete demo data" button needed.
- The detail that should change how Liv reads its own six areas: **Cultured
  Code knows exactly which areas most people need, and ships that knowledge as
  a web page, not as app state.** The
  [Getting Started Guide](https://culturedcode.com/things/guide/) names
  *Family & Friends, Money, Health, School, Career* — four of Liv's six,
  near-verbatim — as **suggestions in prose**, while the app's Areas list stays
  empty. **(a)** Liv's six are well-researched; the strongest precedent for
  them declines to install them.

### 3.3 The rest of the field

| App | Fresh install shows | Grade |
|---|---|---|
| **Apple Reminders** | Six fixed Smart Lists (Today, Flagged, Scheduled, All, Completed, Assigned), hideable via View. Default user list "Reminders". **No wizard, no samples.** ([Apple](https://support.apple.com/guide/reminders/view-reminder-lists-remnd854fc47/mac)) | (a) |
| **Apple Notes** | Three auto-folders (All, Notes, Recently Deleted). **No sample notes documented.** True zero-furniture end. ([Apple](https://support.apple.com/en-asia/guide/notes/notc3b2d538b/4.7/mac)) | (a) |
| **Bear** | Welcome notes exist and double as the documentation. Count/titles **unverified** (the community thread is now 404). | (a) existence, rest unverified |
| **Todoist** | **Went backwards.** In 2019 a new account got a seeded "Welcome project". As of the [14 Jul 2026 help](https://www.todoist.com/help/articles/get-started-with-todoist-OgNNJR), step 1 is *"Create a project"* — **no seeded content**. What remains: Inbox + fixed Today/Upcoming/Priority views + ghost placeholder text in Quick Add that stops after 15 completed tasks. | (a) |
| **Todoist onboarding questions** | The use-case questionnaire is documented only in an **April 2023** capture; 2025–26 changelogs put onboarding investment into *team* flows. **Whether the personal interview still exists in 2026 is unverified.** | unverified |
| **Notion** | Long personalization flow → plan selection → an **interactive tutorial** (create to-do, mark done, create project, drag & drop). Notion's own help **never documents what a new workspace contains**. Only measured number anywhere: an undated, unattributable **"6% activation increase"** from [Statsig's customer story](https://www.statsig.com/customers/notion). **No public retention or churn data exists.** | (d) / unverified |
| **Notion critique** | Six years of consistent, independent, **entirely unmeasured** commentary: "a blank canvas that turns into digital landfill", "where information goes to die", "template economies exist because Notion is unnecessarily complex". | (c) |
| **Obsidian** | Literally nothing. Demo content is **quarantined into a separate Sandbox vault**. | (a) |
| **Capacities** | 11 built-in object types you cannot change (Page, Tag, Image, Weblink, …). Person/Meeting/Book are **not** built-in — they come from an opt-in gallery. Space creation offers use-case templates. | (a) |
| **Anytype** | Docs decline to enumerate defaults; space setup docs tell you to *"Set up Types and Properties — create your organization system"*. **No documented starter objects.** | (a) for the negative |
| **Linear** | Teaches ⌘K before you have content, then a task checklist; activation event is *resolving* the first issue. A screen-by-screen teardown finds **no** sample data. Built **without a single A/B test**. | (a)/(c) |
| **Sunsama** | Mandatory guided setup, then a seven-step daily planning ritual. **Seeds nothing fake — it imports your real calendar and real tasks.** | (a) |
| **Trello** | The Welcome Board *is* the tutorial: the first card tells you to drag it. Purely observational, no metrics. | (c) |
| **Superhuman** | The only comparative onboarding number that exists: **~2× activation** human-led vs self-serve, setup completion 30%→98%. Uncontrolled, and heavily confounded by waitlist + $30/mo self-selection. | (b)/(d) |

### 3.4 Design-system consensus splits 2–4

**For seeded starter content:** Google Material's
[Empty States](https://m1.material.io/patterns/empty-states.html) explicitly
names *"Starter content"* — but this is the M1 (2014–18) archive and Material 3
appears to have dropped the pattern. IBM Carbon's
[empty-states pattern](https://carbondesignsystem.com/patterns/empty-states-pattern/)
is live and endorses starter content, with the best scoping rule found anywhere:
**educational treatment for *primary* resources, a plain empty state for
*secondary* ones.**

**Against, or silent:** Shopify Polaris, GitHub Primer (illustration + one
primary CTA, no fake content), Atlassian (useful distinction: an *empty state*
is work you completed — celebrate it; a *blank slate* is a feature never tried —
promote it), and Apple HIG, which never recommends sample content and says
*"learning by doing is a lot more fun and effective than reading a list of
instructions"* and *"avoid asking for setup information up front"*. Apple's own
Reminders and Notes are consistent with their guidance.

**37signals reversed itself**, and most blog posts cite only the first half. In
2004 they recommended faded, explicitly-labelled "EXAMPLE" content; *Getting
Real* (2006) recommends *a screenshot* of a populated page, not seeded records;
by [2010](https://signalvnoise.com/posts/2322-design-decisions-new-basecamp-blank-slates)
they stripped it all to one button, Fried saying people *"skip over it. They
just want to get something done."*

### 3.5 The two pieces of real evidence about sample content

**For:** the **worked-example effect** from cognitive load theory — novices who
study a worked example outperform novices made to solve the equivalent problem.
This is a large, replicated literature — **but it is about learning tasks, not
software first-run.** It is an analogy, not evidence. Its companion, the
**expertise-reversal effect** (worked examples stop helping and start hurting
once the learner has prior knowledge), is the principled argument for making any
seeded content trivially removable and never shown twice.

**Against:** [HighLevel's "Delete Example Data with one button"](https://ideas.gohighlevel.com/contacts/p/delete-example-data-with-one-button),
filed 23 Apr 2025, 31 votes — sample data "creates chaos in the account" across
workflows, pipelines and templates. The vendor's fix, shipped 14 May 2025, was
**an off switch, not a bulk-delete button**. This is the one hard, dated,
primary-source datapoint on the cleanup burden. **(a)**

### 3.6 NN/g, and the finding most relevant to Liv

NN/g's canonical
[empty-states article](https://www.nngroup.com/articles/empty-state-interface-design/)
(2021, nothing newer through mid-2026) gives three guidelines — communicate
status, provide **learning cues**, offer **direct pathways** — and says *"do not
default to totally empty states."* It cites zero user studies; it reasons from
examples. Their
[2023 tutorials piece](https://www.nngroup.com/articles/onboarding-tutorials/)
finds upfront tutorials **don't improve task performance** and are frequently
skipped; "pull revelations" beat "push revelations".

The finding I would actually act on is from their
[2024 generative-AI onboarding study](https://www.nngroup.com/articles/new-AI-users-onboarding/)
(**n=6, qualitative — weak, and I am saying so**): broad, **generic** examples
above the input field beat **niche-specific** suggestions; users "felt confused
when these tools assumed users knew how they worked."

**If you seed, seed the shape, not someone else's content.**

### 3.7 Numbers you will meet that are fabricated

Flagged because they circulate widely and will be quoted at you: *"D1 retention
41%→67% from pre-populated sample data"* (source 404s, no company named);
*"38% activation lift from educational framing"*; *"15–30% lift from ghost rows
+ sample data"*; *"77% of users abandon an app within 3–7 days"*; *"80% of new
Todoist users create their first task in under 40 seconds"*. **All untraceable.**
The genuinely-measured public numbers (Candu/Make 3–5%; Mailist 33%→46%) are
before/after, not A/B, with no sample size and no significance testing. The
largest real dataset in the space (Chameleon's 550M-interaction benchmark) does
not break out empty states at all.

---

## 4. The evidence on choice, defaults, and filing

This section exists to stop us building on sand. Several arguments that get
made for and against furnishing turn out to be folklore. Grades: **(a)**
replicated controlled experiment · **(b)** single controlled experiment ·
**(c)** meta-analysis · **(d)** small-n qualitative · **(e)** industry datapoint
· **(f)** folklore.

### 4.1 Choice overload is folklore. Stop citing it.

**The jam study does not survive contact with its own numbers.** Iyengar &
Lepper (2000), *JPSP* 79(6):995–1006
([PDF](https://faculty.washington.edu/jdb/345/345%20Articles/Iyengar%20&%20Lepper%20(2000).pdf)).
The famous result is **4 purchases vs 31** — 35 jars of jam. Displays were
rotated hourly rather than randomized per shopper, and the authors themselves
flag self-selection: *"the display of 6 jams may have appealed to store
customers who were more serious about the purchasing of jam."* The 6 jams were
pre-selected by survey, with strawberry and raspberry removed from the 24 so
people couldn't use existing preferences. **(b), tiny, confounded.**

**Scheibehenne, Greifeneder & Todd (2010)**, *JCR* 37(3):409–425
([PDF](https://scheibehenne.de/ScheibehenneGreifenederTodd2010.pdf)) — 63
conditions, 50 experiments, **N = 5,036**: mean **D = 0.02, 95% CI −0.09 to
0.12**. Trimmed: **D = 0.001**. They also detect publication bias (published
work more likely to find the effect) and a "Prometheus effect" (more recent work
less likely to). The one robust moderator runs the *other* way: **people with
prior preferences or expertise benefit from more options.** **(c)**

**Chernev, Böckenholt & Goodman (2015)**, *JCP* 25(2):333–358
([PDF](https://chernev.com/wp-content/uploads/2017/02/ChoiceOverload_JCP_2015.pdf))
is usually cited as the rescue — 99 observations, N=7,202, four significant
moderators (decision goal .56, choice-set complexity .55, task difficulty .37,
preference uncertainty .32). But the line that gets dropped is in their own
paper: **"in the absence of the conceptual moderators, the mean effect of
assortment size on choice overload is nonsignificant (t(20) = −.10; p = .48)."**
Their unmoderated model replicates the null. **(c)**

**Barry Schwartz has not conceded**, and I could not find any sourced statement
that he has. His 2017 *Behavioural Public Policy* paper with Cheek cites
Scheibehenne et al. and maintains the framework. Treat "even Schwartz admits it"
as unsourced.

**Hick's Law does not apply here either.** By its own standard formulation it
"does not apply" to unordered menus, because finding a target in a random list
requires linear scanning. **(f) as normally invoked.**

**Consequence for Liv, stated bluntly:** *"six areas prevent the paralysis of
Notion's infinite options"* and *"seven chips is too many"* are **not
evidence-backed claims**. The number of options is close to irrelevant. What has
evidence behind it is **task difficulty** and **preference uncertainty** — and
"is my child's ear infection Health or Family?" is a preference-uncertainty
problem, not a count problem. **The argument against the six workspaces must be
ambiguity and gating, not choice overload.** If we win on the wrong argument we
will lose it again the first time someone counts the options.

### 4.2 Defaults move what people *pick*, much less what actually *happens*

**Jachimowicz, Duncan, Weber & Johnson (2019)**, *Behavioural Public Policy*
3(2):159–186
([Cambridge Core](https://www.cambridge.org/core/journals/behavioural-public-policy/article/when-and-why-defaults-influence-decisions-a-metaanalysis-of-default-effects/67AF6972CFB52698A60B6BD94B70C2C0)):
**d = 0.68, CI 0.53–0.83**, 58 datasets, **N = 73,675**; **27.2 percentage
points** for binary choices. Mechanisms: endorsement (the default reads as a
recommendation) and endowment. **Ease/effort was *not* significant** — defaults
are not mainly about saving taps. Carry the caveat: **I² = 98%**. **(c)**

**The asterisk that matters more.** Kalkstein et al. (2022), "Defaults are not a
panacea", *Behavioural Public Policy*
([PDF](https://bpb-us-e2.wpmucdn.com/sites.wustl.edu/dist/0/3761/files/2024/03/Kalkstein-et-al-2022-Defaults-are-not-a-panacea-Distinguishing-between-default-effects-on-choices-and-on-outcomes-110c71081b3f1712.pdf))
— field experiment, **N = 32,508** students, opt-in vs opt-out AP exam
registration:

| | Default | Control | |
|---|---|---|---|
| Registered | 91.5% | 90.0% | +1.5 pts, p<0.001 |
| **Actually sat the exam** | **76.9%** | **77.1%** | **p = 0.61 — nothing** |

Same paper on organ donation: opt-out raises *consent* 3–25×, and *actual
donations* only 1.16–1.56×. And Dallacker et al. (2024), *Public Health*
([Max Planck summary](https://www.mpg.de/23726833/1113-bild-organ-donation-opt-out-defaults-do-not-increase-donation-rates-149835-x)):
five countries that switched to opt-out saw **no increase** in deceased-donor
rates. **(a)**

**Consequence for Liv:** a default area, or a pre-selected workspace, would
reliably raise the *filing rate* and would tell us **nothing** about whether
people find things again. This is a direct warning about which metric to
believe — see §7.

**And the "95% never change defaults" claim is not a study.** It is
[Jared Spool's informal 2011 survey](https://archive.uie.com/brainsparks/2011/09/14/do-users-change-their-settings/):
"several hundred" self-mailed Word `config.ini` files, no sampling frame, no
n, no statistics. Spool calls it "a little experiment". **(e) at best, (f) as
usually cited.** The real evidence for software defaults is revealed preference
at scale — Google paying Apple ~$20bn/yr for default search placement; iOS ATT
collapsing tracking consent to ~15%/~6% when flipped from implicit-on to
explicit-opt-in.

### 4.3 The finding that should change Liv's mind: people navigate, they don't search

This is the best-supported thing in the whole brief, and it runs against the
"search is the safety net" assumption baked into the current build.

- **Bergman, Beyth-Marom, Nachmias, Gradovitch & Whittaker (2008)**, *ACM TOIS*
  26(4):20 ([DOI](https://doi.org/10.1145/1402256.1402259)): users retrieved
  files by **navigation 56–68%** of the time vs **search 4–15%**. Critically:
  **better search engines (Google Desktop, Spotlight) did not increase search
  use or cause folder abandonment.** Search is the fallback for when location
  memory fails. **(d), self-estimates, but replicated in direction.**
- **Teevan, Alvarado, Ackerman & Karger (2004)**, CHI
  ([PDF](https://groups.csail.mit.edu/haystack/papers/chi2004-perfectse.pdf)):
  keyword search used in only **39%** of searches; people "orienteer" in small
  contextual steps. **(d), n = 15** — the 39% is quoted everywhere as a hard
  number and is a count over 15 MIT grad students in 2003. Direction, not
  magnitude.
- **Barreau & Nardi (1995)**
  ([full text](https://homepages.cwi.nl/~steven/sigchi/bulletin/1995.3/barreau.html)):
  location-based browsing beat text search; files were positioned **to be
  seen**. **(d), n = 22.**

**Consequence for Liv:** the current build's only route to an old, undated,
typed item is search (§2.5). That is the retrieval mode people use least and
reach for last. **A browsable "Everything" is not a nice-to-have; it is the
mechanism people actually use.**

### 4.4 People use exactly one label, and most folders fail

Two findings that between them settle two open questions.

**Bergman, Gradovitch, Bar-Ilan & Beyth-Marom (2013)**, *JASIST*
([preprint](https://is.biu.ac.il/files/is/Folders%20vs%20Tags%20-%20Preprint%20version.pdf))
— the best-designed study in this literature: naturalistic, on participants'
**own** data, after explicitly teaching both folders and tags. **(b)**

- Gmail, n=75: of tag-labelled messages, **92% carried exactly one label; only
  8% carried two or more.** Retrieval by **multiple labels: 0.1%**. 79% wanted
  hierarchy back.
- Windows 7, n=23: after two weeks of *forced* tagging (2+ tags on 55% of
  files), given free choice for five weeks, **only 6 of 23 created any tags.**
  Reasons: "difficult to use", "time consuming" — not habit.
- Controlled retrieval: **tags 21.21 s vs folders 16.44 s**, p<.05. Multi-
  classification retrieval was *slower*.
- Google's own team (Rodden & Leggett, CHI EA 2010,
  [PDF](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/36334.pdf)):
  "Many users did not discover labels, and wondered why Gmail had no folders";
  **"Move to" — the single-destination action — is used almost twice as often as
  "Labels."** **(e)**

**Consequence for Liv:** the tempting fix for §2.4's ambiguity — *"let the
child's doctor appointment be both Health and Family"* — is the fix people
demonstrably do not use. **The single-valued `area` select is the right shape.
Keep it.** The ambiguity has to be solved by making the choice *optional and
non-blocking*, not by making it multi-valued.

**Whittaker & Sidner (1996)**, CHI ([DOI](https://doi.org/10.1145/238386.238530)):
on average **35% of folders contained only one or two items**; folder count
correlated with failure rate at **r = 0.75**. **(d), n = 18.** Fisher, Brush,
Gleave & Smith (2006), CSCW
([PDF](https://www.microsoft.com/en-us/research/wp-content/uploads/2006/11/p309-fisher.pdf)),
**n = 600 mailboxes**: failed folders down to 16%, but **only ~38% of folders
touched in the last 30 days**. **(d), large n.**

That same 600-mailbox study is worth knowing for a second reason: it **failed to
reproduce** Whittaker & Sidner's famous "no filers / spring cleaners / frequent
filers" typology — *"clear divisions among groups did not emerge. Rather… there
is a continuum."* The most-repeated typology in personal information management
came from n=18 and dissolved at n=600. A caution about how much of this
literature is safe to build on.

**Consequence for Liv:** a small fixed set of areas is better-supported than
letting users spawn containers early. It is also an argument for making the
workspace switcher *earned* rather than pre-populated — five workspaces created
before the user has any data is exactly the "folder that holds one item" shape.

### 4.5 Categorization ambiguity: universally asserted, never measured

The claim that items fitting several categories cause hesitation or abandonment
is the load-bearing premise of this whole investigation. **The honest position is
that nobody has measured it.**

- **Malone (1983)**, *ACM TOIS* 1(1):99–112
  ([PDF](http://simson.net/ref/1983/Malone_Desks.pdf)) — **(d), n = 10**, with
  the author's own disclaimer that it "is not intended to be a controlled
  experiment." The famous mechanism rests on **three respondent quotes**. The
  best one is still the best statement of the problem anyone has written:

  > *"it's almost like leaving them out means that I don't have to characterize
  > them… Leaving them out means that I defer for now having to decide — either
  > having to make use of, decide how to use them, or decide where to put
  > them."*

- **Lansdale (1988)**, who turned this into theory, was honest about it: on the
  claim that piling actually helps, **"No formal evidence exists to support this
  assertion."**
- **Kwasnik (1991)**, *Journal of Documentation* 47(4)
  ([DOI](https://doi.org/10.1108/eb026886)) — **(d), n = 8** — makes a stronger
  and more useful claim than "items have several topics": classification is
  driven by **situational context** (where it came from, what you intend to do
  with it, when), not by intrinsic document attributes. **The right category is
  not a property of the item at all.** That is exactly why "is this Health or
  Family?" has no answer: the answer depends on why you will next reach for it.
- **William Jones**' programme (Bruce, Jones & Dumais 2004,
  [Information Research 10(1) 207](https://informationr.net/ir/10-1/paper207.html),
  keeping n=24) supplies the "out of sight, out of mind" finding and the
  observation that "folders created today may prove ineffective or even an
  impediment" — but **no study anywhere measures filing latency or abandonment
  as a function of ambiguity.**

**Consequence for Liv, and for this document:** my own 4-of-7 ambiguity count in
§2.4 is **n=1 and it is me**. It is also, embarrassingly, about as much direct
evidence as exists on the question. I would not defend the *number*; I would
defend the *specific cases*, because #6 (child's health vs family) and the
milk/birthday-present split are structural, not marginal — they follow from the
taxonomy's shape, and anyone can reproduce them in ten seconds without an
experiment.

One more from Malone that argues against tidying things away: **~67% of his
piles were things-to-do.** Organization is as much about **reminding** as
finding. Filing something perfectly but out of sight trades a well-evidenced
function for a poorly-evidenced one — which is the argument for keeping unfiled
and recent material *visible on the main surface*, not tucked into an Inbox.

### 4.6 Onboarding: the rigorous studies are null, and the one that worked was humans

This is the thinnest evidence in the whole brief, and what little is rigorous is
discouraging. The good studies come from Wikipedia, which runs real large-scale
RCTs on newcomer onboarding.

- **Narayan, Orlowitz, Morgan, Hill & Shaw (CSCW 2017)**, "The Wikipedia
  Adventure" — a gamified interactive tutorial
  ([DOI](https://doi.org/10.1145/2998181.2998307)). **(a)**. Users "responded
  very positively"; and: **"We find no effect of either using the tutorial or of
  being invited to do so over a period of 180 days."** *Users loved the
  onboarding and it changed nothing.* **Subjective delight with an onboarding
  flow is not evidence that it works.**
- **Warncke-Wang, Ho, Miller & Johnson (CSCW 2023)**, the Newcomer Homepage —
  a purpose-built onboarding surface plus **guided starter tasks**, across 27
  Wikipedias ([arXiv:2308.09642](https://arxiv.org/abs/2308.09642)). **(a),
  gold standard.** Activation +0.036 (SE 0.012), **"roughly equivalent to a 1%
  increase in the odds of activation."** Retention: **null** (p = 0.31).
  Productivity: CrI spans zero. And the instrumented analysis is worse than
  null: **"Suggested edits appear to replace other contributions rather than
  augment them."**
- **Morgan & Halfaker (OpenSym 2018)**, the Teahouse — a *human* help venue
  ([DOI](https://doi.org/10.1145/3233391.3233544)). **(a)**. Newcomers invited
  to it **were retained at a higher rate.**

The pattern: the structured tutorial did nothing; the guided starter tasks
cannibalized real work; **access to humans was what moved retention.**

The one strong positive result in the onboarding literature argues for *less*:
**Ginns, Hollender & Reimann (2006)**, meta-analysis of the minimalist training
model ([ERIC ED491708](https://files.eric.ed.gov/fulltext/ED491708.pdf)) —
13 randomized effect sizes, n = 288, **weighted mean d = 1.12, CI [0.83,
1.41]**, homogeneous. Sub-effects: "support error recognition and recovery"
d = 0.59; **"slash the verbiage" d = 0.89**. **(c)**, small total n, DOS-era
studies, no publication-bias analysis — but it is the best thing there is, and
it says: cut the instructional text, put people on a real task immediately,
make errors unreachable.

**And the "IKEA effect" does not license a setup interview.** Norton, Mochon &
Ariely (2012) ([DOI](https://doi.org/10.1016/j.jcps.2011.08.002)) state their
own boundary condition: **"labor leads to love only when labor results in
successful completion of tasks; when participants… failed to complete them, the
IKEA effect dissipated."** An abandoned wizard produces no effect at all. And
the manipulation is physically building an object you keep — not answering
questions about yourself. **(b), misapplied is (f).**

### 4.7 Numbers to refuse

Both research passes independently hit a wall of fabricated statistics, several
falsely attributed to real sources. Flagged so nobody quotes them at us:

- **Every progressive-disclosure percentage.** "30–50% faster initial task
  completion", "70–90% feature discoverability", attributed to
  [Nielsen's 2006 NN/g article](https://www.nngroup.com/articles/progressive-disclosure/)
  — which contains **no citations, no data, and no numbers at all**. The same
  sites attribute invented percentages *and a fabricated participant quote* to
  "Carroll and Rosson (1987)". **There is no number for progressive disclosure.**
- **Every "aha moment" metric.** Facebook's "7 friends in 10 days" traces to a
  single 2013 conference talk, never published. Andrew Chen, who popularized the
  genre, on his own blog: *"I'm sure '10 friends in 12 days' works well too, as
  does '5 friends in 1 day' but you just pick something that makes sense and
  easily memorable."* Twitter's "30 follows", Slack's "2,000 messages",
  Dropbox's "1 file in 1 folder on 1 device" — **no primary source for any of
  them.**
- **"D1 retention 41%→67% from pre-populated sample data"**, **"38% activation
  lift from educational framing"**, **"77% of users abandon an app within 3–7
  days"**, **"80% of new Todoist users create their first task in under 40
  seconds"** — all untraceable.
- **The "fewer form fields → +120%" case study** is a sequential before/after on
  one agency's own contact form, six months apart, no control. And the
  counter-evidence is rarely cited: a 15-field form beat an 11-field form by
  109% in one MarketingExperiments test; Unbounce's Michael Aagaard *lost 14%*
  by cutting fields.

### 4.8 What is actually safe to lean on

1. **Defaults change what people select** (d ≈ 0.68, N=73,675) — but see (2).
2. **Defaults change outcomes much less, or not at all.** Measure retrieval, not
   filing rate.
3. **People retrieve by navigating to where they put it, not by querying** —
   and better search does not change that.
4. **Given free multi-classification on their own content, people use exactly
   one label** (92% single-label; multi-label retrieval 0.1%).
5. **A large share of user-created containers never earn back their cost**
   (35% held 1–2 items; only ~38% touched in 30 days at n=600).
6. **Minimalist instruction beats comprehensive instruction** (d = 1.12).
7. **Organization is as much reminding as finding** (~67% of piles were
   things-to-do).

And what is **not** safe: choice overload, "95% never change defaults", the
email filing typology, "ambiguity causes hesitation" as a *measured* claim,
tagging as a solution, every progressive-disclosure and aha-moment number, and
Hick's Law.

---

## 5. The options, laid out

For each: what the user sees on first open; what they must decide and when; how
it fails; what evidence supports it.

### (a) Fixed field VALUES only — six areas as an `area` select, no workspaces

*What shipped, minus the workspaces.*

- **First open:** the capture door plus one flat list of everything, newest
  first, each row wearing its area as a chip. Workspace switcher present but
  containing only "All".
- **Decides what, when:** nothing before typing. After saving, optionally one of
  six areas. Skippable with no penalty.
- **Fails when:** the flat list gets long and the area chips stop being enough
  to navigate by. Also: the six areas are *visible* only at the moment of
  filing, so the "arrives furnished" feeling is weaker on first open.
- **Evidence:** this is the majority pattern (Todoist 2026, Apple Reminders,
  Things minus its tutorial). Consistent with Polaris/Primer/Apple HIG. Directly
  supported by my own measurement: **the shipped build's default state already
  is this**, and its flat Tasks view (`24-tasks-all.png`) was the single most
  usable surface I saw. Also supported by §4.4: a **single-valued** area, chosen
  from a small fixed set, is exactly the shape people actually use (92%
  single-label), and a fixed set avoids the one-item-folder failure mode.

### (b) Fixed TIME structure only, everything else empty — Things' shape

- **First open:** Today / Upcoming / Anytime, all correctly empty, plus the
  capture door. No areas at all.
- **Decides what, when:** *when*, and only when the item actually has a when.
  Never *what kind of life-thing is this*.
- **Fails when:** the user has a lot of undated material — notes, ideas, photos,
  references. Time views hold nothing for them, and "Anytime" becomes the
  four-hundred-note pile that `what-liv-is-for.md` opens by naming as the
  failure of simple tools.
- **Evidence:** strongest single precedent (Things 3, Apple Reminders, Todoist's
  Today/Upcoming). Its weakness is exactly Liv's differentiator — Liv is not a
  to-do app, it holds notes and photos too.

### (c) A short first-run interview (3 questions) that generates a shape

- **First open:** three questions ("What will you use this for?" …), then a
  generated set of areas/projects.
- **Decides what, when:** everything, up front, before any value has been
  delivered — the worst possible moment, because the user has no basis to
  answer.
- **Fails when:** the answers are wrong (they usually are — people don't know
  their own system before they've used one), leaving furniture they didn't
  choose and can't evaluate. Also adds drop-off steps before first value.
- **Evidence:** **the weakest option, and the only one with a rigorous result
  against it.** The Wikipedia Adventure RCT (§4.6): users loved the tutorial and
  it produced **no effect over 180 days**. The Newcomer Homepage RCT: +1% odds
  of activation, **null retention**, and starter tasks that *replaced* real work
  rather than adding to it. Notion does it and has the loudest abandonment
  reputation in the category; the only number attached is an undated,
  unattributable 6%. Todoist *removed* its seeded output. Apple HIG: *"avoid
  asking for setup information up front."* NN/g: upfront tutorials don't improve
  task performance and get skipped. The IKEA effect does not rescue it (§4.6):
  an abandoned wizard produces no effect at all. Sunsama is the one success
  case, and it works precisely because it asks for **real data** (your calendar,
  your task tool), not for self-description — which is also what made
  Wikipedia's Teahouse work: humans and real context, not a form.

### (d) Worked-example content — a handful of real-looking items, deletable

- **First open:** 5–8 believable items across several areas, demonstrating the
  shape.
- **Decides what, when:** nothing — but the user must now decide what to do with
  someone else's data.
- **Fails when:** the examples are stale (dates rot fast in an app with a Today
  view), or when deleting them is a chore, or when the user cannot tell fake
  from real. HighLevel is the documented instance of exactly this.
- **Evidence:** the worked-example effect supports it *by analogy* only (it is
  about learning tasks, not software first-run), and its companion
  expertise-reversal effect says it stops helping and starts hurting the moment
  the user knows anything. Carbon and Material(M1) endorse starter content;
  Polaris, Primer, Atlassian and Apple don't. HighLevel is the documented
  failure. **The one hard experimental datapoint is negative**: Wikipedia's
  guided starter tasks *cannibalized* real contributions rather than adding to
  them (§4.6). **Things' variant is the only version with no known failure
  mode:** sample content that is *real work you complete*, offered rather than
  installed, which disposes of itself.

### (e) Progressive disclosure — start near-empty, offer structure when behaviour earns it

- **First open:** the capture door and the fixed views. No areas surfaced.
- **Decides what, when:** nothing, until the user's own data makes a suggestion
  concrete ("you've filed 5 things as Work — make Work a workspace?").
- **Fails when:** the trigger never fires (a user who never files sees no
  structure ever), or when the offers feel like nagging, or when a suggestion is
  wrong and the user has to decline repeatedly. Also: it needs the user to have
  *already* used the area field, so it can't be the only mechanism.
- **Evidence:** NN/g's "pull beats push" (opinion, not data — and note that
  **every quantitative claim about progressive disclosure in circulation is
  fabricated**, §4.7). Linear's checklist. Todoist's ghost placeholder text that
  stops after 15 completed tasks is a live, shipped example of a
  self-terminating hint. The indirect support is real, though: the minimalism
  meta-analysis (d = 1.12, §4.6) says cut the verbiage and get people onto a
  real task, and §4.4 says containers created before there is anything to put in
  them are the ones that fail. **No controlled data on the pattern itself. This
  is the best-reasoned option, not the best-evidenced one, and I am not going to
  pretend otherwise.**

### (f) Combinations

The real design space. The two that matter:

- **(a) + (b):** fixed time views *and* the area field. Time gives direction
  with zero ambiguity; area gives retrieval without gating capture. This is
  Things' shape plus Liv's researched values, with the values as a field rather
  than a place.
- **(a) + (b) + (e):** the above, plus earned structure. The workspace switcher
  the owner has settled on becomes the *destination* of progressive disclosure
  rather than the starting furniture.

---

## 6. Recommendation

**Ship (a) + (b) + (e). Explicitly do not ship (c). Ship at most a hollowed-out
(d) — a first-capture shape hint, not fake items.**

### 6.1 What is in the box on first open

1. **The six areas as an `area` select — kept exactly as researched.** Six
   values, no create-new. It is a **field**, not a place.
2. **No area workspaces.** Delete the five that `Furnish.swift` creates; leave
   the builtin Home workspace un-aimed (no `area:Home` query, no house emoji as
   an area marker). The workspace switcher stays — it is the owner's
   working-context switcher — but on day one it contains only **All** and
   **New workspace…**.
3. **Four fixed views as the primary navigation**, always present, never
   ambiguous, requiring zero decisions to use. (This is the part the evidence
   most directly supports: people retrieve by **navigating to where they put
   it**, not by querying, and better search does not change that — §4.3. The
   current build's only route to an old undated item is search, which is the
   mode people use least.)
   - **Today** — due/scheduled today, plus what you caught today
   - **Upcoming** — the next 7 days
   - **Everything** — the flat reverse-chronological list, area shown as a chip.
     **This surface does not exist yet and is the main net-new work in this
     recommendation.** Its shape already exists, though: the Tasks view in "All"
     (`24-tasks-all.png`) is exactly right — flat, newest-relevant-first, with
     kind / status / area as chips on the row. Generalise it from tasks to
     everything.
   - **Unfiled** — anything with **no `area`**, newest first
4. **`Unfiled` is lens-immune.** This is the owner's settled requirement
   ("something recent-and-unfiled should stay visible regardless of filter")
   and it is the fix for §2.6: change the predicate from *untyped* to
   *no area*, and keep the existing "never apply the workspace lens" rule.
5. **The six kinds and the six promised fields.** Settings should show the six
   the product doc promises, with the other 38 behind a disclosure. Today it
   shows all 44.

### 6.2 What the first five minutes look like

- Open. The body is the capture door, exactly as now. Under it, instead of the
  present line, an empty-state that teaches by naming what the four views will
  hold (NN/g's "learning cues"): *Today · Upcoming · Everything · Unfiled*, each
  with one line of what lands there. Generic, not niche-specific (the one thing
  the 2024 NN/g study supports).
- Type something. Save. **Zero decisions were required to get here.**
- The chip strip appears. **Area leads and is visually primary; the other six
  chips collapse behind a single `…` until used.** Not because seven is too many
  — that claim has no evidence (§4.1) — but because seven equal-weight offers
  fail to say which one matters, and the product has already decided that Area
  is the one filing question.
- Tap Area → six values, no create-new. This is where the furniture becomes
  visible, and it is the right moment: the user now has a real thing in hand to
  classify, not an abstraction.
- Skip it and nothing bad happens. The item is in **Everything**, in
  **Unfiled**, in **Today** if it has a when, and findable by search from
  anywhere.
- **After the third capture only**, and once, a single dismissible line under
  the capture door: *"Areas help you find things later — tap +Area on anything.
  Skip it whenever you like."* Then never again. (Todoist's ghost-text-until-15
  is the shipped precedent for a self-terminating hint.)
- **Once the user has filed five items into the same area**, one dismissible
  offer: *"You've put 5 things in Work. Make Work a workspace?"* Accepting
  creates the workspace with `area:Work` — the exact thing `Furnish.swift`
  creates today, but earned. Declining never asks again for that area.

### 6.3 What the user is never asked

- Never asked to design a system.
- Never asked "what will you use this for?" — **no first-run interview.**
- Never asked to choose a workspace, area, or folder **before typing**.
- Never asked to name a project, notebook, or list.
- Never asked to delete example data.
- Never *blocked* by a decision: every filing question is skippable and every
  skip is safe.

Secondary, and worth a separate decision: the **verb row** (Idea / Task / Event
/ Photo) is still a decision demanded *before* typing. Everything else in the
capture sheet was moved to after the save; this wasn't. Folding it into the
post-save chip strip (with the field defaulting to a plain scrap) would remove
the last pre-typing gate. Photo genuinely needs to stay up front — it opens a
different device.

### 6.4 The honest cost

- **The app looks emptier on day one.** "Arrives furnished" stops meaning "six
  rooms are already built" and starts meaning "a working system is already
  chosen for you": four fixed views, six named areas, six kinds, six fields, and
  no design work. That is a genuinely weaker *first impression* in exchange for
  a genuinely lower *first-week failure rate*. If the owner's priority is the
  demo, this is the wrong recommendation.
- **Users who genuinely do think in areas lose the one-tap area switcher** until
  the offer fires or they make one by hand. Five taps of setup, deferred.
- **The area field will be under-used at first**, and the Unfiled list will grow.
  That is the design working, not failing — but only if retrieval holds up
  (which is why §7's second metric is the real one).
- **Progressive disclosure has no controlled evidence behind it.** It is the
  best-reasoned option, not the best-evidenced one. Nothing in this space is
  well-evidenced; I would rather say that than dress it up.
- **This recommendation deliberately declines the easy win.** Defaulting the
  area — pre-selecting one, or auto-assigning by keyword — would raise the
  filing rate immediately and measurably (d ≈ 0.68 is a real effect). §4.2 is
  the reason not to: defaults reliably move what people *pick* and very often
  move outcomes by nothing at all. We would get a number that looks like
  success and a product that hasn't changed. If the owner wants that lever, it
  should be pulled *after* retrieval is instrumented, not before.
- **The strongest single result in the onboarding literature is that access to
  humans is what moved retention** (Wikipedia's Teahouse) while the tutorial and
  the guided task list did nothing. Nothing in this recommendation replicates
  that, and I don't know how a solo-user phone app could. It is the honest
  ceiling on how much any first-run design can be expected to do.
- **Deleting five workspaces from an existing box is a migration question.**
  `Furnish.swift` is presence-guarded, so simply removing the creation code
  leaves already-furnished boxes with five orphan workspaces. They must be
  either left alone (they're harmless once "All" is the default and the flat
  view is primary) or removed with an explicit, visible one-time migration. I
  would leave them: silently deleting user-visible things violates "never change
  anything without showing you first".

### 6.5 The bugs this depends on

These are not optional polish; the recommendation does not work without them.

1. **`Inbox.swift` scraps predicate** — key on *no `area`*, not *no kind*. The
   comment above it is already correct; the predicate under it isn't.
2. **Search must not be workspace-filtered** — or, if it stays filtered, it must
   say *"3 more outside Health"* and offer one tap to see them. Today it
   silently returns nothing and offers to create a duplicate.
3. **Today's "Captured" tile** — same predicate fix, and it should not apply the
   lens (or should show both counts).
4. **Settings' field list** — show the six, disclose the rest.
5. The transient **"This entity is not in the box anymore."** after a capture.
6. The **notification prompt** should not fire mid-capture.

---

## 7. What to measure later

The owner's three tests in `what-liv-is-for.md` stay the top-level criteria.
These are the instrumented proxies that would tell us whether this worked,
listed with what a *failure* looks like so they can't be read as vanity.

**The ordering matters, and §4.2 is why.** Filing rate is the easy metric and
the misleading one: a default would move it 20+ points and might move retrieval
by zero, exactly as the AP-exam default moved registration and not exam-sitting.
**Retrieval is the metric. Everything else is diagnostic.**

1. **Retrieval rate** — share of sessions in which the user *opens* an item
   created more than three days ago. This is the whole product thesis in one
   number. If this doesn't climb, nothing else matters and no other number
   should be allowed to substitute for it.
2. **Unfiled ratio at day 7 / day 30** — share of items with no `area`.
   *A high number is not a failure by itself.* It is only a failure if (1) also
   fails. If unfiled is high and retrieval is fine, areas were never needed.
3. **Filing latency** — at capture / later / never. If "later" is near zero,
   "sorting is a tap, not a project" is not being believed, and filing has
   silently become a gate again.
4. **Area re-assignment rate** — how often an area is changed after being set.
   High means the six are wrong, or ambiguous, or both. This is the direct
   empirical test of the taxonomy, it is cheap to collect, and — per §4.5 — it
   would be **more evidence than the published literature currently contains**
   on whether categorization ambiguity actually costs anything. Worth
   instrumenting for that reason alone.
5. **Navigation-vs-search mix** — what fraction of opens come from a browsable
   view versus the search overlay. §4.3 predicts navigation should dominate once
   "Everything" exists. If search still dominates after it ships, the browsable
   views are not carrying their weight and the diagnosis in §2.5 was wrong.
6. **Duplicate-creation-after-failed-search** — how often "Create '<query>'" is
   taken within seconds of a search that returned nothing. This is the §2.6
   hole, measured.
7. **Offer acceptance** — what fraction of "make Work a workspace?" offers are
   accepted. If it's near zero, the working-context switcher is a feature nobody
   wanted and can be cut. If it's high, the areas *should* have been rooms after
   all and this study was wrong.

---

## 8. What I could not test

Stated plainly, because the recommendation leans on some of it.

- **No real users.** Every ambiguity judgement in §2.4 is mine. **n = 1, and it
  is me.** One person's hesitation is a hypothesis, not a measurement. The
  uncomfortable part (§4.5) is that this is roughly as much direct evidence as
  the published literature contains on whether categorization ambiguity costs
  anything — the claim is universally asserted and, as far as I can find, never
  measured. I would not defend the *ratio*; I would defend the *cases*, because
  the child's-health-vs-family collision and the milk/birthday-present split
  follow from the taxonomy's shape and anyone can reproduce them in ten seconds.
- **I did not build any alternative.** Options (b)–(f) were reasoned about, not
  prototyped. The only one I have direct evidence about is (a), because the
  shipped build's default state already is it.
- **I could not test time.** Every failure mode that matters — the pile
  building, the abandonment at week three, the "I can't find it" moment — takes
  weeks. Seven captures in one session cannot see any of it.
- **The date/time pickers** were driven partially; the 11-gesture count for the
  event includes a reasonable (not measured) 3 gestures for the date picker.
- **The `axe` toggle interaction** needed touch-down/up rather than tap, which
  is a harness artifact, not an app bug.
- **The camera path** was exercised through the simulator's photo-picker
  stand-in, not a real shutter.
- **Reddit and archived pages** were unreachable from the research environment,
  so user sentiment about empty Areas lists in Things, and about default-type
  overload in Anytype/Capacities, is inference rather than user voice. That is
  the biggest hole in §3.
- **Bear's welcome-note count, Todoist's current personal onboarding questions,
  Notion's current default page, and whether Linear seeds an example issue** are
  all explicitly unverified. Don't cite them.
