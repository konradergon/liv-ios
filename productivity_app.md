# Architecture

> **Status:** 1.4
>
> This document is the constitution of the project.
> It defines architectural principles rather than implementation details.
>
> Whenever implementation and this document disagree, this document takes precedence.
>
> 1.0 folds in the pressure test of the core model and its amendments
> (merge, dates, projections, the promotion pattern),
> and adds the chapters the draft lacked:
> how the system lives beside other programs,
> how foreign content is treated,
> how automation and agents are admitted,
> the reference data model, and the build order.
>
> 1.1 closes the gaps milestone 1 would have hit first:
> undo in an append-only log, the modification time,
> the notation of the reference model, the recurrence rule's value kind,
> and when the clerk reads.
>
> 1.2 admits the calendar lens for native dates,
> names the three surfaces of the first release —
> notes, agenda, calendar —
> and keeps the integration fence closed.
>
> 1.3 answers where metadata comes from:
> the clerk files the schema too — learned per user, add-only,
> refusals remembered — the starter library gets a floor and a fence,
> and triage is bound to scale sublinearly.
>
> 1.4 makes the opinionation explicit:
> the system arrives designed — workflow chosen, views built,
> settings budgeted by rule, the first run asking nothing —
> the straitjacket is named beside the toolkit trap,
> and upgrades propose, never overwrite.
>
> The foundation is ready. Implementation may begin.

---

# Vision

Modern desktops fragment information across many specialized applications:

- Notes
- Documents
- Calendar
- Tasks
- Contacts
- Files
- Bookmarks
- Images
- Projects

This forces users to think about **where** information belongs instead of **what** they are working on.

The goal of this project is to replace application-centric organization with entity-centric organization.

Users should not need to ask:

> "Should I put this in Notes or Calendar?"

Instead they should simply create an entity.

The same information should naturally appear wherever it is relevant.

The system does not compete with the applications beside it.
Word makes the document good;
this system makes it findable, relatable, and actionable.

> Applications win inside their silos.
> This system wins at the seams between them.

One warning, stated up front:

The question "where does this go?" must not be reincarnated as "what type is this?".

Neither question deserves an answer at the moment of capture.

---

# Philosophy

This project values:

- Simplicity over feature count
- Uniformity over specialization
- Composition over inheritance
- Generalization over special cases
- Predictability over cleverness
- Capture over classification
- Long-term coherence over short-term convenience
- Structural enforcement over promised discipline
- Reversibility over friction
- Opinions over options

Every architectural decision should move the system toward a smaller set of more powerful concepts.

---

# Core Concepts

The system consists of only a few fundamental concepts.

## Summary

Everything the user works with is an Entity. Everything the system does is a Command. Everything the system suggests is a Proposal. Everything the user sees is a View. Everything begins as a scrap.

## Entity

> An entity is a stable identifier plus a set of property values.
> A value is either a literal or a reference to another entity.
> There is nothing else.

Examples:

- note
- task
- document
- project
- person
- meeting
- photo
- email
- recipe
- invoice
- location
- link

These are not fundamentally different object types.

They are different uses of the same abstraction.

An entity's meaning comes entirely from its properties, its references, and its types.

---

## Property

Entities have properties.

Examples:

- title
- created
- due date
- author
- status
- priority
- rating
- location

Properties describe entities.

Every value has one of a small, closed set of value types:

- text
- rich text
- number
- boolean
- date / datetime
- select
- reference (another entity)
- file

New value types are added rarely and deliberately.

Every value type multiplies the complexity of queries and renderers.

Dates are civil:

> A date value is wall-clock time plus a date-only flag.
> "Friday" and "Friday 10:00" are different values, and neither is a bare instant.

No timezone is stored.
That question belongs to multi-device sync and stays fenced with it.

Every value type defines equality —
text by content, rich text by spans, files by hash, references by identifier.
Removing a cell and deduplicating an import both depend on it.

Property definitions are themselves entities.

Property names form a single global namespace.

"Due date" is one property, shared by tasks, invoices and meetings.

This is what makes cross-type queries possible:

> everything due this week

Adding a property should rarely require changing application code.

One name with many uses is the power and the hazard.
When a shared select property's options diverge by use,
split-or-union is decided once (see Open Decisions).

---

## Relationship

A relationship is not a separate mechanism.

> A relationship is a property whose value is a reference to another entity.

Meeting → Project means:
the meeting has a property `project` whose value references the project.

The system indexes references in both directions.

Backlinks are automatic and free.

If a relationship itself needs data, it is promoted to an entity:

Person attends Meeting *as organizer*
becomes an Attendance entity referencing both the person and the meeting.

There is never a second relationship mechanism.

Relationships are first-class citizens.

Hierarchy is only one possible relationship.

---

## Content

Content is not a separate mechanism.

> Content is a property whose value type is rich text or file.

Content is optional.

Many entities have no editable content.

Rich text may embed references to other entities.

Embedded references are indexed like any other reference.

Editing content replaces the whole value:
one user action, one command, however many keystrokes it coalesces.
Finer-grained edits are added only when a measured document hurts,
and that decision is entangled with sync (see Open Decisions).

---

## Type

Types are entities.

`type` is a multi-valued reference property.

An entity may have several types.

> An email can also be a task.

An entity may change type.

> A note becomes a task by adding the type.

A type carries expectations, not enforcement:

- which properties an entity of this type typically has
- their default values
- its default view

Expectations give the system templates and forms without a class hierarchy.

A default is an expectation carrying data,
so it is promoted like any relationship carrying data:
an Expectation entity referencing the type and the property,
holding the value (worked example 9).

The expected list itself is one multi-valued cell on the type.
The Expectation entity decorates a member with its default;
it never asserts membership alone.
One fact, one place.

A type never gates behavior.

Renderers key on properties (see Principles).

---

## Lifecycle

Identifiers are stable and never reused.

Deletion is soft: deleted entities go to the trash.

References to deleted entities render as broken links.

Deletion never cascades.

Deletion never silently edits other entities.

Merge is a first-class action, not a primitive.

It is an ordinary transaction of primitive commands:
copy cells to the survivor, resolve conflicts once,
trash the loser, record one redirect.

Redirects are followed at read time.

Merge never rewrites another entity:
a person referenced by three hundred meetings
merges with zero writes to any meeting.

The merged-away identifier permanently redirects to the survivor.
Permanent means identifiers always resolve —
not that a merge cannot be undone.
Being made of ordinary commands, it is one undo step like everything else.

Entities imported from outside carry an `external-id` property.

Re-import never duplicates.

---

## Query

Queries describe collections of entities.

Examples:

```
type = task
status != done
```

```
tag = work
```

```
related to Project Alpha
```

Views display query results.

Saved queries are entities.

`related to Project Alpha` at depth one is a single backlink lookup.
Deeper traversal is an index question, not a schema question (see Open Decisions).

Recurring entities are expanded into their occurrences here,
in the query layer —
so every view gives the same answer (see Principles).

---

## View

Views are renderers.

Views never own data.

Examples:

- List
- Table
- Calendar
- Timeline
- Gallery
- Graph
- Board
- Editor

A view answers:

> "How should these entities be presented?"

Never:

> "How should these entities be stored?"

A saved view is an entity:

- a query
- a renderer
- renderer configuration

The configuration maps properties to visual dimensions:

- which date property places entities on the calendar
- which select property defines the board columns
- which properties become table columns

Navigation is a view of views.

The sidebar is not a special subsystem.

---

# Architectural Principles

## Everything is an Entity

Avoid introducing specialized object models.

If a feature requires a completely new type hierarchy,
the abstraction should be questioned.

---

## Not Everything Is an Entity

The abstraction has limits.

The following are never entities:

- command history — it lives in the persistence layer, so undo never pollutes queries
- pending and declined proposals — they live beside history, so an agent's drafts never pollute queries or search, and a refusal is remembered without becoming a thing
- transient UI state — selection, scroll position, window layout
- caches and indexes — including extracted text and thumbnails of foreign files; all rebuildable

If it is not information the user works with,
it is not an entity.

---

## Capture Comes First

Everything starts as a scrap:

> an untyped entity with content and a creation date. Nothing else.

Structure is always optional and always later.

No dialog. No type picker. No destination.

The capture surface is a global hotkey and a small popup.
The main window need not open.
Capture works from inside every other program,
because that is where thoughts happen.

An unstructured scrap is a first-class citizen,
not a failure to file.

If capturing a thought is slower than typing the thought,
it is an architectural bug.

---

## Behavior Hangs on Properties, Never on Types

The calendar renders anything with a date.

The board renders anything with a status.

The gallery renders anything with an image.

Type is a property like any other and may be filtered like any other.

But renderers key on properties.

Types provide templates and defaults.

They never gate behavior.

There are no typed drawers. Only perspectives.

---

## Working Entities Stay Backstage

Promotion — Attendance, Placement, Expectation —
fills the box with entities that are plumbing, not thoughts.

They carry `working: true`.

Default views and search filter `working != true`.

A filter, not a type wall: the invariant holds.
Renderers key on properties,
and the curious user can always look backstage.

---

## Projections Are Computed Once

Some things every view must agree on are stored nowhere:

- the Tuesdays of a recurring series
- an exception overlaid on its series
- an entity's modification time — the timestamp of the last transaction
  that touched it, read from history, never written as a cell

These are expanded and composited in Services, in one place,
never inside a renderer.

A modified cell would need a bookkeeping command on every edit:
history polluted, or the one door bypassed.
Derived, it costs nothing and is always true.

Created stays a cell — written once at birth, never maintained.

If the calendar knew something the board did not,
the system would fall back apart into applications.

---

## The System Is the Clerk

The semantic desktop failed because metadata entry is toil,
and users do not perform toil.

Structuring is therefore the system's job.

The automation layer reads captures and proposes structure:

- types
- properties
- references

> "This mentions the Alpha kickoff → relate to Project Alpha."
> "This contains Friday → due date Friday?"

Proposals are commands awaiting confirmation.

Automation never mutates silently.

The user works. The clerk files.

The clerk is only the first agent.
Automation and agents have a chapter of their own.

---

## The System Arrives Designed

Org-mode and Obsidian made the user the systems architect:
months of assembly before the first productive day,
and the assembly never ends.
Their power users are their builders. This system has no builders.

The trade is explicit:
efficiency and ease of use,
paid for with rigidity and missing knobs.

The workflow is chosen:
capture from anywhere, the clerk proposes,
Today orients, work launches outward (see How It Is Used).
The views are built. The types arrive opinionated and learn quietly.
There is no view builder, no plugin gallery,
no formula field, no themes.

Settings are governed by a rule, not a count:
a setting exists only where observation cannot reach
and the operating system does not already answer —
the capture hotkey, the store's location,
the automation switch (a consent boundary the user must own).
Locale answers the calendar's week; behavior answers the rest.
Every setting beyond that budget
is a decision the product refused to make.

The first run asks nothing.
The box arrives seeded — types, views, defaults,
all ordinary transactions, author system.
(What the operating system demands for a global hotkey
is its question, not ours.)

Personalization is the clerk's job, not the user's.
The system adapts by noticing, and asks only in triage —
one optional keystroke of consent,
never a setup wizard, never a question at capture
(see The Clerk Files the Schema Too).

The generality underneath — views as data, types as entities,
one query language — is the substrate's power, deliberately unexposed.
The system's own surfaces are made of it:
Today, the calendar, the navigation itself are saved views
the system authored — seeded like the starter library,
ordinary, discoverable, offers never fixtures.
Only the inbox is shell, not view:
quarantine is drawn, never queried.

The curious can look, and even edit —
the same uniform cell editing that reaches every entity,
the query a raw text value, unassisted.
No lock, no support.
The kit is reachable; it is never the pitch.

When a newer version holds a better opinion, it proposes it —
through the proposal queue, like any agent.
Nothing re-seeds and nothing overwrites:
provenance knows whose hand last touched a view,
and a silent upgrade of an edited surface
would be the silent assistant wearing the product's own face.

A construction kit cannot be retrofitted into a product.
A product can, someday, open its kit.
The order is forced, and this document chooses it.

---

## Views Never Own State

Views are projections.

Changing a view must never change the underlying model.

Views render.

Commands modify.

---

## Commands Modify State

Every mutation occurs through commands.

The primitives:

- Create
- Trash
- Restore
- Add Cell — set a property, create a relationship, add a type
- Remove Cell
- Redirect — the forwarding record a merge leaves behind

Every command records enough to reverse itself.
Undo is not a feature bolted on later; it is the shape of a command.

Merge is not a primitive.
It is a composite of these (see Lifecycle).

Commands compose into transactions.

One user action is one undo step,
no matter how many entities it touches.

Every transaction records its author —
the user, or the name of the proposer that drafted it.
"Why does this entity have a due date?" always has an answer.

This enables:

- Undo
- Redo
- History
- Automation (a proposal is a transaction awaiting confirmation)
- Audit (provenance on every change)

---

## Search Is Navigation

Searching is a primary interaction.

Everything should be searchable.

Everything should be filterable.

Everything should be linkable.

---

## Relationships Over Hierarchies

Folders solve only one organizational problem.

Relationships solve many.

Always prefer relationships.

---

## Metadata Is Not Hidden

Properties are part of the interface.

Metadata should be easy to:

- see
- edit
- search
- filter
- sort
- query

---

## Uniform Interaction

The interaction model should remain consistent.

Selection behaves the same everywhere.

Editing behaves the same everywhere.

Commands behave the same everywhere.

Keyboard shortcuts behave the same everywhere.

Users should not feel they are switching applications.

---
# Layers

```
Shell

↓

Views

↓

Services

↓

Core Model

↓

Persistence
```

Dependencies only point downward.

---

## Persistence

Responsible for:

- storage
- indexing
- serialization

Decided: the disk truth is a versioned, append-only log of transactions.

History and persistence were always the same thing;
the log makes them one file.
The in-memory entity table is a materialization of the log.
Snapshots come later, if replay is ever measured to hurt.
The version number in the header costs one integer
and buys every future migration.

The encoding lives behind the persistence seam: the core never sees bytes,
only transactions. The first backend is the simplest that is correct —
a version-header line, then one transaction per line, human-readable and
recoverable by hand if the program ever dies. A hardened store (SQLite the
obvious candidate) can replace the file with no change above it, the day
durability or concurrency is *measured* to need it — not before.

Undo appends.

Reversing a transaction writes its inverse to the log;
the truth is never rewritten.
Redo is the inverse of the inverse, appended again.

An undo is a transaction like any other:
it records its author — whoever pressed the key —
and it references the transaction it reverses.
History shows both.
The mistake and its correction are both facts.

Contains no UI.

Contains no business rules.

---

## Core Model

Responsible for:

- entities
- properties
- relationships
- commands
- history

Independent of UI.

Independent of persistence.

---

## Services

Responsible for:

- querying
- search
- indexing
- recurrence expansion and exception compositing
- preview and text-extraction caches for foreign files
- automation — the clerk and every other agent
- the proposal queue
- import/export
- synchronization

No rendering.

No widgets.

Automation is a service.
Dependencies point downward,
so everything below works with automation switched off.

---

## Views

Responsible only for presentation.

Views never:

- perform database writes
- contain business logic
- define commands

---

## Shell

Responsible for:

- windows
- navigation
- menus
- shortcuts
- layout
- the global capture hotkey and its popup
- the proposal inbox
- deep links in (`app://entity/4211`)

The shell orchestrates.

It does not own data.

---

# Renderers

Every renderer competes with a dedicated application.

The calendar view will be compared to a real calendar.
The board will be compared to a real task board.

A unified system with many mediocre views
loses to many excellent silos.

That is the status quo, and it wins by default.

A renderer is the only code in a lens.
The rest of a saved view — query, renderer name, configuration — is data.

Every renderer is the same move twice:

> Position entities by one property.
> Draw an entity as a few properties.

The list positions by nothing.
The calendar positions by a date.
The board positions by a select.
The gallery draws an image property large.
The editor draws one entity's content —
and when that content embeds a task,
it peeks at the task's status to draw the checkbox.

A renderer holds no state.
If it crashes mid-gesture nothing is lost;
reopening the view re-runs the query and everything is right.

Gestures translate into commands, or into nothing.
Opening a file externally mutates no entity,
so there is nothing to record and nothing to undo.

The first release has exactly four renderers:

- List / Table — one renderer, two densities
- Editor
- Today — the orientation surface of the first workflow;
  whether it is a board or a dedicated list is chosen inside milestone 5 (see Build Order)
- Calendar — admitted in 1.2, justified by the first workflow.
  It renders native dates only; what it may show is fenced with
  the external world, not with this list (see The External World)

Candidates that must justify their existence later:

- Timeline
- Gallery
- Graph
- Tree
- whichever of board and list Today did not take

Every future renderer must justify its existence.

---

# The External World

Email, calendar subscriptions and files live elsewhere and change elsewhere.

Every integration is one of two things:

- a copy — which becomes a stale mirror
- a live reference — which becomes a sync engine

Sync engines are where unified information systems go to die.

## The Librarian, Not the Editor

For foreign formats the system is a librarian.
The entity is *about* the document, not the document.

> The entity owns the meaning.
> The file owns the bytes.

Title, due date, project, status — the system's.
The words inside contract.docx — Word's, permanently.

A lens meeting a foreign file climbs a ladder.
Every rung is read-only:

1. icon, filename, properties — free; the entity already works on every view
2. extracted plain text, cached — cheap, and it feeds full-text search
3. a thumbnail — optional vanity
4. editing — never; "edit" asks the operating system to open the default application

There is no rung five.
No embedded editors, ever.
An embedded Word is the worst renderer competing with the best application.

Images are the one foreign format cheap enough to render natively.
The gallery just works.

## The Hash Is the Integration

Worked example 5 stands: a path plus a content hash.

The round trip: the user edits in Word, saves, returns.
The hash no longer matches — that mismatch is the entire integration.
Re-extract the text, refresh the thumbnail, done.

No sync engine. Change detection only.

Extracted text and thumbnails are caches, not cells.
Delete the cache; nothing is lost.

## Websites

A link entity: a url, plus a title scraped once at capture.

Open launches the browser.

No embedded webview in the first release —
the heaviest possible dependency,
to imitate something one keystroke away.

No page snapshots either:
an archived page is a stale mirror by definition.

## Seams

The system earns its keep at the borders:

- a global capture hotkey — inbound, from anywhere
- drag-and-drop and paste — entities created by reference, never copied, never moved
- open-externally — outbound, to every silo
- deep links (`app://entity/4211`) — so other programs can point back in;
  paste one into an email or a Word comment and it resolves for years

The first release integrates exactly one external source —
local files, by reference with a content hash (worked example 5).

Email and calendar subscriptions stay behind the Open Decisions fence
until the core has proven itself on native entities.

The calendar lens changes what the fence means, not whether it holds.

Appointments the user captures are native entities
and render like any other date.
Appointments living in a foreign calendar stay there —
no subscription, no import, until files prove the pattern.

Two calendars coexist honestly:
the real calendar holds the appointments the world sends;
this one holds the dates the user makes —
deadlines, plans, and the work around the meetings:
the preparation, the follow-ups, the decisions.

An incomplete calendar posing as complete would be a stale mirror
wearing a lens as a disguise.
The native calendar never poses:
it shows what was captured, and only that.

Complementary, not competing, until the core has earned more.

---

# How It Is Used

The system is not lived in. It is touched.

The thick hours of a day belong to other programs —
the document in Word, the reading in the browser, the meeting.
By its own non-goals this system refuses to host them.

Four kinds of touch, four budgets:

- **Capture** — seconds, many times a day. Hotkey, type, enter, gone. The main window never opens.
- **Orientation** — minutes, at the start of a session. Open Today, see what is live, launch outward.
- **Retrieval** — seconds, unpredictably. Search, find, open.
- **Triage** — five optional minutes. Sweep the clerk's proposals. Skippable without harm.

Fifteen minutes a day inside the system.
Every hour of the day touched by it.

## Triage Scales Sublinearly

Alike proposals group: twelve dates found this week is one card.
Alike means one proposer, one pattern —
the merged transaction still records its author truthfully,
and every folded reason rides into history.

A group opens, and any member severs,
accepted or declined alone.
Accept commits the remaining members as one ordinary transaction:
one user action, one undo step, no third door.
The severed stay in the queue, unjudged.

Consent to a summary is never consent to a member unseen.

The inbox that shows all this is the shell's one surface
that is not a view:
proposals are not entities, no query returns them,
and the inbox draws the quarantine directly (see Shell).

A queue that must be cleared one key at a time
is the obligation machine wearing a helpful face.

## Absence Creates No Debt

Ignore the system for a week and nothing rots.

Scraps are already captured and searchable.
Proposals queue silently.
Nothing nags. Nothing must be filed. Nothing expires.

Email punishes absence; this system must not.
The moment it generates obligation,
it has become one more silo demanding attention.

## The First Workflow

Decided:

> Capture from anywhere in three seconds.
> Every morning, Today has everything waiting, structured.

The loop: capture → the clerk proposes → Today orients → work launches outward → done.

The first release serves this loop end to end,
across the three surfaces the workflow names:

- the editor, for thought — note-taking
- Today, for orientation — the agenda
- the calendar, for the shape of the week — native dates only

These three are the product.
Everything beneath them — entities, commands, the clerk —
is how they stay one system instead of three more silos.

---

# Automation and Agents

The constitution's oldest rule was written for a rule engine
and turns out to be the agent boundary:

> Automation never mutates without confirmation.

An agent is a second user whose keystrokes are quarantined.

## Two Doors

AI gets two doors, and only two.

It reads through the query service — the same door as every view.

It writes through commands — the same door as the user —
except its commands wait in the proposal queue
for one keystroke of consent.

There is never a third mechanism,
in the same spirit as:
there is never a second relationship mechanism.

Two doors make the whole surface auditable.
One choke point for privacy:
what queries may return to a model —
a `private` cell excludes an entity from machine context,
and a single switch turns the layer off entirely.
One choke point for safety:
nothing lands unconfirmed.

Enforcement is structural, not policy:
the proposer interface cannot express a write.

## Three Roles, One Socket

**The answerer** — read-only.
A question becomes a query; the top entities are serialized;
the model answers, citing entity identifiers;
citations render as deep links.
Zero mutation risk. Built first.

**The clerk** — the proposer.
Ships first as regex — dates in text, mentions of known names.
The language model is a brain swap behind the same socket, not surgery.
It is fed the gazetteer — existing names and property definitions —
so it reuses the global namespace
instead of inventing "deadline" beside "due date".
When vocabulary pollution slips through anyway,
merge repairs property definitions like it repairs people.

**The agent** — a goal becomes a batch.
"Plan the offsite" drafts one transaction of many commands.
One transaction is one confirmation and one undo step.
The atomicity built for ctrl-z is agent-work atomicity.

## When the Clerk Reads

Proposers run behind the write:
every committed transaction is offered to them,
asynchronously, entity by entity.
A sweep at startup catches what changed while the system was closed —
including foreign files whose hashes no longer match.

Nothing runs on a timer.
A clock that ticks is a nag waiting to happen,
and absence creates no debt.

Automation lagging or switched off changes nothing below it;
proposals are the only output, and the queue can wait forever.

---

## The Safety Story Is the Invariants

Nothing new was invented:

- proposals gate entry
- transactions make any accepted batch reversible in one step
- soft deletion and never-cascade bound the blast radius
- stable identifiers mean no agent can corrupt a reference
- provenance: every transaction records its author

The one addition is the author field.

## The Flywheel

Every accepted proposal adds structure.
Richer structure is richer context.
Richer context makes better proposals.

The system gets smarter about this user's life
with zero training.

## The Clerk Files the Schema Too

"What metadata belongs to a meeting?" is toil too,
and the user answers it at most once —
per pattern, never per entity.

Types, expectations and property definitions are entities,
and commands are generic,
so a proposal may target them like anything else.

Set a location on enough meetings,
and the clerk proposes it once:

> "Most meetings have a location → should meetings expect one?"

The clerk counts through the query service —
the same door as every view.
The proposal is ordinary commands:
one Add Cell — expected → location — on the meeting type;
a default would add one Expectation entity holding the value.

Accept, and every future meeting offers the field —
an affordance on the entity, never a question at capture.
Blank costs nothing.

Decline, and the declined shape is kept beside history,
where pending proposals already live.
Proposers see it with the gazetteer:
a duplicate of anything pending or declined
is dropped before it reaches the queue.
Nothing asks again, because the refusal is data, not mood.

Schema proposals only add.
The clerk never proposes removing structure the user accepted;
pruning is the user's act,
and deleting an expectation changes no existing entity —
nothing ever cascaded.
They are rare by construction — one per learned pattern —
and they queue, group and triage like any other.

The flywheel turns twice:
proposals structure the entities,
and the structure of the entities reshapes the schema.
The system learns what metadata belongs to each kind of thing —
for this user, with zero training, through the same two doors.

Expectations stay expectations.
A learned schema offers harder; it never gates.

## Three Refusals

**No silent mutation.**
Even the obviously-right fix waits for a key.
Auto-accept, if it ever exists, is an explicit per-proposer setting,
applies with notification, is one undo step —
and stays fenced for now.

**No chat silo.**
An ask-anything surface is welcome,
but its answers are made of cited entities
and its actions are proposals.
A chat pane with its own memory
is a silo inside the anti-silo application.

**No model marriage.**
Proposer and answerer are model-agnostic sockets.
A local model, a cloud API,
or an external agent over a local socket all fit,
because the only write any of them can reach is quarantine.
Models churn yearly. The queue never has to.

---

# Invariants

These rules should never be violated.

- Every entity has a stable identifier.
- Every entity may have arbitrary properties.
- Every entity may participate in relationships.
- Every entity may appear in multiple views.
- Views never own data.
- Views never modify data directly.
- Commands are the only way to mutate state.
- Every command records enough to reverse itself.
- Every transaction records its author.
- The log is append-only; undo appends an inverse, never erases.
- Search indexes entities.
- Relationships are first-class.
- Properties are first-class.
- References are indexed in both directions.
- Deletion never cascades.
- Merge never rewrites another entity; redirects are followed at read time.
- Identifiers are never reused.
- Capture never requires structure.
- Renderers key on properties, never on types.
- Computed projections come from one place; every view agrees.
- Caches are rebuildable; nothing user-owned lives only in a cache.
- Foreign bytes are never edited in-system; foreign content opens in its own application.
- AI reads only through queries and writes only through proposals.
- The system works with automation switched off.
- Automation never mutates without confirmation.
- Absence creates no debt.

---

# Non-Goals

This project is NOT:

- a note-taking application
- a task manager
- a calendar
- a file manager
- a database
- an email client
- a sync engine
- an editor for foreign formats
- a chatbot with a database attached
- a toolkit for building your own system

It is a unified information system.

Those capabilities should emerge from common abstractions rather than separate subsystems.

---

# Known Failure Modes

Every predecessor of this project died of a product mistake,
not a model mistake.

This section names the enemies.

## The toolkit trap

A universal abstraction naturally produces a database construction kit.

Users of construction kits build systems instead of working.

*(Notion has this disease. Chandler died of it.)*

Defense: opinionated built-in types with excellent defaults.
The generic machinery is the substrate, not the pitch.

The starter library is data in the box, never code,
and the clerk tunes it to its owner through the same two doors,
one accepted proposal at a time, never by drift
(see The Clerk Files the Schema Too).

---

## The straitjacket

The opposite ditch.
Opinions so rigid that real work cannot flow around them.

*(Every "simple" todo app, abandoned the week life stopped fitting it.)*

Defense: structure is always optional —
a scrap that fits no type still captures, searches and links
like everything else, and appears in every view its properties reach.

The substrate stays general beneath the opinions,
so a wrong opinion is a changed default, never a rearchitecture.
A life the floor does not fit teaches the clerk new types —
the same two doors, one proposal at a time.

And the wall has a door (see The System Arrives Designed).
The doorknob is plain text; that is the price of having no builder.
But the door cannot maim:
commands are the only mutation,
so a wrong turn backstage is one transaction —
one undo step home.

---

## Capture friction

Entity systems reincarnate "where does this go?"
as "what type is this?" — at the worst possible moment.

*(This killed adoption of every semantic desktop.)*

Defense: untyped capture, structure later, the clerk proposes.

---

## The stale mirror and the sync engine

Every external integration drifts toward one or the other.

*(This is where unified PIMs historically drowned.)*

Defense: at most one integration until the core is proven.

---

## Substrate without product

Years of elegant model, no workflow anyone can live in.

*(Chandler, again.)*

Defense: from the first release, the architecture must serve
one real daily workflow end to end.
The workflow is now named (see How It Is Used).

---

## The embedded editor

Rebuilding Word inside a renderer.

*(Compound documents — OLE, OpenDoc — died proving this.)*

Defense: the librarian ladder.
Rung four is "open externally," and there is no rung five.

---

## The obligation machine

A system whose absence accumulates debt
trains the user to dread it.

*(Email.)*

Defense: absence creates no debt is an invariant, not a hope.

---

## The silent assistant

One unconfirmed "helpful" change, and trust never returns.

*(Nobody forgave Clippy. Nobody trusts autocorrect.)*

Defense: two doors, proposals, provenance —
enforced by construction, not by policy.

---

## The model marriage

Hardwiring one vendor's model into the product's identity.

*(The wrapper graveyard of 2023–2025.)*

Defense: sockets, not wires.
The proposal queue outlives every model.

---

# Architectural Smells

The following are warning signs.

## New object hierarchy

If a feature introduces many new classes,
ask whether it should instead be another Entity.

---

## New interaction model

If a feature needs different editing,
selection,
search,
or navigation,

the architecture should be reconsidered.

---

## Feature-specific storage

If a feature requires its own persistence model,

it is likely violating the entity model.

---

## Feature-specific commands

Commands should be generic whenever possible.

---

## A renderer that remembers

If a view needs to persist anything,
a Placement-style entity or a configuration cell is missing.

---

## A gesture that writes

Gestures translate into commands, or into nothing.
Never into writes.

---

## A default that became behavior

If a type's convenience now gates what a renderer does,
the central invariant broke.

---

## A third door

Any AI capability that needs a new way in or out
is wrong by construction.

---

# Decision Checklist

Before implementing anything, ask:

1. Can this be represented as an Entity?

2. Can this be represented as Properties?

3. Can this be represented as Relationships?

4. Can an existing Command perform this?

5. Can an existing View render this?

6. Does this introduce a special case?

7. Does this make the system simpler or more complicated?

8. Does this slow down capture?

9. Could the clerk propose this, instead of the user performing it?

10. Does this still work with automation switched off?

11. Does this create obligation — does absence now accumulate debt?

12. Could this be a default instead of a setting?
    Could the clerk learn it instead of the user configuring it?

Only introduce new abstractions when existing ones genuinely fail.

---

# Open Decisions

Decided since 0.3, recorded where they land:

- persistence: a versioned append-only transaction log (Layers)
- dates: civil wall-clock plus a date-only flag; no stored timezone (Property)
- merge: a composite of primitives with read-time redirects (Lifecycle)
- projections: recurrence expansion and exception compositing live in Services (Principles)
- the first workflow (How It Is Used)
- automation: agents enter through proposals only (Automation and Agents)

Decided in 1.1, likewise recorded where they land:

- undo appends its inverse; the log is never rewritten (Persistence)
- modification time is a projection from history, not a cell (Principles)
- the reference model's C is notation; the language is chosen at milestone 1 (Reference Data Model)
- recurrence rules are text values; the grammar waits for the calendar (worked example 2)
- proposers run behind the write and sweep at startup, never on a timer (Automation and Agents)

Decided in 1.2, likewise recorded where they land:

- the first release's product is three surfaces: notes, agenda, calendar (How It Is Used)
- the calendar renderer joins the first release, justified by the named workflow (Renderers, Build Order)
- calendar entries are native entities only; foreign calendars stay behind the fence (The External World)
- the recurrence-expansion horizon is decided at milestone 6, with the calendar (Build Order)

Decided in 1.3, likewise recorded where they land:

- the clerk proposes schema, not just structure: expectations learned per user,
  add-only, through the same two doors (Automation and Agents)
- the expected cell is the one fact of expectation; an Expectation entity
  only decorates it with a default (Type, worked example 9)
- declined proposals are kept beside history; proposers drop duplicates of
  anything pending or declined (Automation and Agents, Not Everything Is an Entity)
- triage scales sublinearly: one-proposer groups, severable before accept,
  committed as one ordinary transaction (How It Is Used)
- the proposal inbox is a shell surface, not a view (How It Is Used, Shell)
- the starter library's floor and seeding are fixed; its contents wait
  for milestone 5 (Open Decisions, Known Failure Modes)

Decided in 1.4, likewise recorded where they land:

- opinions over options: the system arrives designed — no view builder,
  no plugin gallery, no formula fields; the kit stays unexposed (Principles)
- settings are budgeted by rule: only where observation cannot reach and
  the operating system does not answer (The System Arrives Designed)
- the first run asks nothing; the box arrives seeded, author system
  (The System Arrives Designed)
- system surfaces are ordinary system-authored view entities; upgrades
  propose changes, never re-seed or overwrite (The System Arrives Designed)
- the straitjacket is named beside the toolkit trap; clerk-taught types
  and the backstage door are its defenses (Known Failure Modes)
- authoring surfaces are fenced, but saving the query on screen is a
  bookmark, not a builder (Build Order)

Still deliberately undecided.
Each is decided when its feature is built, not before:

- Query language syntax and expressive limits — traversal depth and aggregation.
  V0 is a plain conjunction of (property, operator, value).
  The horizon for expanding an endless series moved to milestone 6,
  where the calendar forces it.
- Shared select vocabularies — when one property's options diverge by use
  (task status vs invoice status): split, or union.
  The global namespace's one hard bill, paid once.
- The Today surface — board or dedicated list, chosen inside milestone 5.
- Platform and UI toolkit — the first question of implementation.
  The capture hotkey and its background process are where the operating system bites first.
  The implementation language was decided at milestone 1: Rust (Reference Data Model, Build Order).
- Sync and multi-device — eventual scope, or permanent non-goal.
  Entangled with: timezone storage, content-edit granularity, identifier allocation.
- The starter library — the built-in types and their expectations.
  Its floor is fixed by the first workflow: note, task, event —
  Today and the calendar cannot render a life without them.
  The rest (person, project, meeting, ...) is decided at milestone 5,
  where the clerk first needs a gazetteer worth feeding.
  Starter types are seeded by ordinary transactions in a fresh box,
  author "system", with no reserved identifiers —
  discoverable only the way user-made types are,
  so no code can ever key on them.
  Being ordinary entities they can be edited or trashed:
  the box's opinions are offers, never fixtures.
- Automation policy — auto-accept, and the external agent socket.
- Email and calendar integration — only after files have proven the pattern.

---

# Guiding Principle

The application should feel like a single coherent environment.

Users should never experience:

> "Now I am using the calendar."

Instead they should experience:

> "I am looking at my information from another perspective."

They should also never experience:

> "I have to go deal with my system."

The system is the index of the work, not the venue of the work —
except for thought itself.

---

# Glossary

- **Entity** — a stable identifier plus a set of cells. Informally: a card.
- **Cell** — one property instance on one entity; a repeated property id is a multi-valued property.
- **Property** — a named value on an entity, typed from a small closed set.
- **Reference** — a property value that points at another entity.
- **Relationship** — a reference, seen from either side.
- **Type** — an entity carrying expectations (properties, defaults, template). Never behavior.
- **Expectation** — an entity giving a type a default value for one property.
- **Content** — a rich text or file property.
- **Scrap** — a freshly captured entity with no structure yet. The most common entity in the system.
- **Command** — the only way to mutate state. Self-inverting. Informally: a slip.
- **Transaction** — commands composed into one user action, one undo step, one author.
- **Proposal** — a transaction awaiting confirmation, with a reason and an author.
- **Redirect** — the forwarding record a merge leaves; followed at read time.
- **Provenance** — the author recorded on every transaction.
- **Query** — a stored description of a set of entities.
- **View** — a saved entity: query + renderer + configuration.
- **Renderer** — the only code in a lens. Keys on properties.
- **Working entity** — promoted plumbing (Attendance, Placement, Expectation); filtered from default views.
- **Placement** — an entity giving another entity a manual position in one view.
- **Today** — the orientation surface of the first workflow.
- **The clerk** — the automation layer that proposes structure so the user never files.
- **Answerer** — a read-only model capability: question in, cited entities out.
- **Agent** — a proposer with a goal; drafts batches, confirmed as one.
- **Gazetteer** — existing names and property definitions fed to proposers, so the namespace is reused rather than polluted.
- **Deep link** — `app://entity/4211`; how the outside world points back in.
- **Preview cache** — extracted text and thumbnails of foreign files; rebuildable, never truth.
- **The box** — informal name for the store.

---

# Appendix: Worked Examples

The entity model is only as good as its worst case.

These are the cases that break naive models.
Each is worked out here so the answer is decided once.

## 1. A thought, captured

The user presses one key and types a sentence.

That creates an entity with content and a creation date. Nothing else.

The clerk proposes:

> "This mentions the Alpha kickoff → reference Project Alpha."
> "This contains Friday → due date Friday?"

The user accepts with one key, or ignores the proposals forever.

Either way the thought is already captured, searchable, and safe.

## 2. A recurring meeting

The series is one entity.

Recurrence is a property holding the rule ("every Tuesday 10:00").

The rule is a text value.
Its grammar is decided when the calendar justifies its existence;
a ninth value kind is not.

Occurrences are virtual: computed in the query layer, not stored —
so "due this week" means the same thing
on the board, the list and the calendar.

Editing one occurrence materializes an exception entity
that references the series and overrides its properties for that date.
Queries match against the composite of series and exception.

One series, few exceptions, no duplication.

The horizon for expanding an endless series
is decided at milestone 6, where the calendar forces it (see Build Order).

## 3. A task inside a note

The task is a real entity.

The note's content embeds a reference to it.
The note does not contain the task; it displays it.

Checking the checkbox in the note edits the task entity.
The same task appears in every task view.

Deleting the note does not delete the task.
It removes one place where the task was displayed.

A plain text checkbox without a reference is just text.
Promotion to an entity is an explicit act — or a clerk proposal.

## 4. An email

Import copies the message.
The copy is immutable content on a new entity.

`external-id` holds the message id.
Re-import finds the existing entity and does nothing.

The thread is a reference: each message references the message it replies to.
The thread view is a query, not a container.

An email becomes actionable by giving it a status or a due date.
It appears on the board and the calendar like any other entity.

No "convert to task" step. Same entity, one more property.

Adding the task type is optional: it brings the template, never the behavior.

## 5. A file on disk

The entity references the file path and stores a content hash.

The file is the source of truth for its bytes.
The entity is the source of truth for its metadata and relationships.

A changed hash means the file was modified outside the system.
A missing file renders as a broken reference,
exactly like a reference to a deleted entity.

The system never silently copies or moves user files.

A lens meeting the file climbs the ladder:
icon and properties for free,
extracted text cached for search,
a thumbnail if vanity demands.
Editing opens the default application;
the changed hash on return triggers re-extraction.
The caches are rebuildable and are not cells.

## 6. Two entities for the same person

Merge is a composite action, not a magic move.

One transaction:
cells copied to the survivor with ordinary Add Cell commands,
conflicts resolved by the user once and recorded as commands,
the loser trashed,
one Redirect written.

All inbound references now resolve to the survivor —
followed at read time, so no meeting, note or task was edited.
Three hundred references, zero writes to any of them.

The losing identifier redirects permanently:
permanently meaning it always resolves,
not that the merge cannot be undone.
It is one undo step, like everything else.

## 7. A date with no time

"Call Anna Friday."

The due value is civil: Friday's date, date-only flag set.

It sorts and filters beside full datetimes.
It renders without an invented 00:00.

No timezone is stored.
The value means Friday wherever the machine is —
which is the truth of what the user typed.

## 8. A card dragged to the top of a board

Manual order is data about (entity, view) —
a relationship carrying data, so it is promoted:

a Placement entity referencing the task and the view,
holding a rank (a fractional index in text).

Reordering is one small command pair on one small entity.

The same task sits at position two on one board
and position nine on another, without contradiction.

Placement carries `working: true`,
so search and default lists never show the plumbing.

## 9. A default status for new tasks

"Tasks start as todo" pairs a type, a property, and a value —
data on an expectation, so it is promoted:

an Expectation entity referencing the task type and the status definition,
holding the default.

The expectation itself is one cell on the type — expected → status.
The Expectation entity decorates that cell with the value;
it never asserts expectation alone.

Creating a task through the type's template reads expectations.

Deleting the expectation changes no existing task.
Nothing cascades. Nothing ever did.

## 10. An agent plans the offsite

The goal produces one drafted transaction:
six creates, a dozen cells, references to the project.

The inbox shows one proposal with a reason.

One key accepts all of it.
One undo removes all of it.

History answers for it forever:
author, offsite-agent; accepted, Tuesday.

## 11. A week of absence

The user does not open the system for a week.

The hotkey kept working; scraps piled up, already searchable.
The clerk kept reading; proposals queued silently.

On return, Today is current.
Triage is five minutes, or zero.

Nothing expired. Nothing nags. No debt.

---

# Appendix: Reference Data Model

The constitution in struct form.
Data and interfaces only; no logic.
Where prose and structs disagree, the prose wins and the structs get fixed.

`Map`, `MultiMap`, `TextIndex` and `Event` are stand-ins,
chosen during the first milestones.

The C is notation, not a commitment.
The implementation language was chosen at milestone 1: Rust.
The closed set of value kinds becomes an exhaustive enum the compiler checks;
the platform fence stays open, because a Rust core
binds to any shell the milestone-4 decision picks.

```c
// ---- identity ----

typedef uint64_t Id;    // stable, monotonic, never reused; 0 = none

// ---- values: the closed set ----

typedef enum
{
    VALUE_TEXT,
    VALUE_RICHTEXT,
    VALUE_NUMBER,
    VALUE_BOOL,
    VALUE_DATETIME,
    VALUE_SELECT,
    VALUE_REFERENCE,    // the only relationship mechanism
    VALUE_FILE,
} ValueKind;

typedef struct
{
    enum
    {
        SPAN_TEXT,
        SPAN_REF,
    } kind;
    char *text;         // SPAN_TEXT
    Id target;          // SPAN_REF: indexed like any reference
} Span;

typedef struct
{
    Span *spans;
    int span_count;
} RichText;

typedef struct
{
    char *path;         // the file owns the bytes
    uint8_t hash[32];   // a changed hash is the entire integration
} FileRef;

typedef struct
{
    int64_t civil;      // local wall-clock, packed; never a bare instant
    bool date_only;     // "friday" vs "friday 10:00"
} DateTime;

typedef struct
{
    ValueKind kind;
    union
    {
        char *text;
        RichText richtext;
        double number;
        bool boolean;
        DateTime datetime;
        Id option;      // select options are entities
        Id reference;
        FileRef file;
    };
} Value;                // equality defined per kind; removal and dedup depend on it

// ---- the one object ----

typedef struct
{
    Id property;        // references a property definition entity
    Value value;
} Cell;                 // repeated property id = multi-valued property

typedef struct
{
    Id id;
    bool trashed;       // soft; references render as broken links
    Cell *cells;
    int cell_count;
} Entity;

// ---- bootstrap: the ids the system needs to describe itself ----

enum
{
    PROP_NAME = 1,
    PROP_TYPE,          // multi-valued reference
    PROP_CREATED,       // written once at birth; modification time is derived from history
    PROP_CONTENT,
    PROP_VALUE_KIND,    // on property definitions
    PROP_OPTIONS,       // on select property definitions
    PROP_EXPECTED,      // on types
    PROP_DEFAULT_VIEW,  // on types
    PROP_QUERY,         // on saved queries and views
    PROP_RENDERER,      // on views
    PROP_CONFIG,        // on views: property -> visual dimension
    PROP_EXTERNAL_ID,   // import dedup
    PROP_WORKING,       // backstage plumbing, filtered by default
    PROP_PRIVATE,       // excluded from machine context

    FIRST_USER_ID = 4096,
};

// ---- mutation: the only door ----

typedef enum
{
    CMD_CREATE,
    CMD_TRASH,          // never cascades
    CMD_RESTORE,
    CMD_ADD_CELL,       // set a property / create a relationship / add a type
    CMD_REMOVE_CELL,
    CMD_REDIRECT,       // loser id -> survivor id; merge is a composite
} CommandKind;

typedef struct
{
    CommandKind kind;
    Id entity;
    Cell before;        // enough to reverse; empty for ADD
    Cell after;         // empty for REMOVE
    Id redirect_to;     // CMD_REDIRECT only
} Command;

typedef struct
{
    Command *commands;
    int command_count;
    char *label;        // one user action, one undo step
    char *author;       // "user" | proposer name -- provenance
    int64_t time;
} Transaction;

typedef struct
{
    Transaction tx;     // a proposal is a transaction in quarantine
    char *reason;       // "mentions the Alpha kickoff -> reference Project Alpha"
} Proposal;

// ---- the store ----

typedef struct
{
    Id source;          // who points
    Id property;        // through which property (or richtext span)
} Backlink;

typedef struct
{
    // materialized from the log; the log is the disk truth
    Map entities;       // Id -> Entity
    Map redirects;      // merged-away Id -> survivor; chased at read time
    Id next_id;

    // derived -- rebuildable from truth at any time
    MultiMap backlinks; // target Id -> Backlink list
    TextIndex fulltext;

    // beside entities, never among them
    Transaction *history;
    int history_count;
    Proposal *pending;  // an agent's drafts never pollute queries
    int pending_count;
    Proposal *declined; // refusals remembered; proposers drop duplicates of both
    int declined_count;
} Store;

// ---- the only code in a lens ----

typedef struct
{
    char *name;         // "list", "board", "editor"

    // read-only: paint the matching entities using the view's config
    void (*draw)(Entity **results, int count, Entity *view);

    // translate a gesture into commands, or into nothing; never a write
    Transaction (*gesture)(Event ev, Entity *view);
} Renderer;

// ---- ai: sockets, never wires ----

typedef struct
{
    char *name;         // "dates", "mentions", "llm-clerk"
    int (*propose)(Entity *subject, Proposal *out, int max);
} Proposer;             // cannot express a write, by construction

typedef struct
{
    char *name;         // "librarian"
    char *(*answer)(char *question, Entity **context, int count);
} Answerer;             // read-only; answers cite entity ids
```

---

# Appendix: Build Order

One thin vertical slice.
Each milestone forces the minimum version of exactly one fenced decision.

1. **Core model, in memory** — Entity, Cell, Value, commands, transactions, undo.
   No UI, no disk. Testable alone.
   The implementation language was chosen here: Rust.
2. **Persistence** — the versioned append-only transaction log.
   The version number goes in the header on day one.
3. **List / Table** — the first lens,
   and the v0 query: a conjunction of (property, operator, value).
4. **Capture** — the global hotkey, the popup, the scrap.
   The feature the pitch stands on precedes everything clever.
   Platform reality bites here first.
5. **Clerk v0** — regex-grade proposers (dates in text, known names)
   and the proposal inbox.
   Today is chosen here, by the workflow,
   and the author starts living in the system daily.
6. **Calendar** — the calendar lens over native dates.
   Forces the minimum recurrence expansion in Services
   and the v0 horizon for endless series
   (fenced with the query language until here).
7. **Provenance** — the author field, and the proposal queue persisted.
8. **The answerer** — read-only questions, answers made of cited entities.
9. **The brain swap** — the language model behind the milestone-5 clerk socket.
10. **Agents** — goals become batches; one confirmation, one undo step.

Fenced beyond the horizon:
auto-accept policy, the external agent socket, email and calendar —
and every dedicated authoring surface:
view builders, type editors,
and the settings their existence would imply.
The entities beneath stay editable the uniform way, as they always were.

The fence stops at the verb save.
Naming the query on the screen — this filter, this lens, keep it —
is a bookmark, not a builder,
and a filter re-typed every morning is the obligation machine.

From milestone 5 onward, the daily workflow —
not this document — chooses what is built next.
