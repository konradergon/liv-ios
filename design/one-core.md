# One core — the log versus the SQLite engine

> **Status:** proposal, 2026-08-19. Written because the owner asked two
> questions: *"what do you think of liv-core in the tauri app vs current core
> the mobile app uses? I personally haven't understood why and how our core came
> about"* and *"we should really clean this up and make sure the ios app and
> tauri app share the same core."*
>
> **Nothing here is decided.** This records a recommendation, its evidence, and
> what it costs. It needs the owner's word before any of it happens.

---

## 0. The thing nobody had written down

There are two Rust crates named `liv-core`.

| | this repo | the desktop |
|---|---|---|
| where | `/Users/k/src/liv/core` | `/Users/k/src/lovable-notes-hub/core` |
| what | an append-only transaction log | a SQLite engine |
| size | 1,673 lines + 8,656 of services | 1,784 lines |
| tests | 332, across 32 files, incl. 4 cost tests | 29, inline in one file, correctness only |

They are **not in separate repositories.** Both working copies point at the same
GitHub remote, `Dahlaren/lovable-notes-hub`. They are two branch lines with no
common ancestor parked in one repo. `CLAUDE.md` says "separate repo" and is
wrong; fix that line.

---

## 1. How the log core came about

Asked directly, so answered directly.

**It was decided on paper, before any code, and it was not a reaction to the old
app.** The constitution (`productivity_app.md`) settled persistence somewhere
between drafts 0.3 and 1.0, in one line: a versioned append-only transaction
log. Those drafts were never in git, so the document is the only record.

On **2026-07-06 at 09:03**, the repository's first commit — `dd57594`,
*"Constitution 1.2 and milestones 1-2: core model and persistence log"* — landed
that document together with working code and 18 tests. Architecture and
implementation in one commit.

**The part that is easy to miss:** that morning the document does not mention
Liv anywhere. The old app became the target *the same afternoon* — an interface
brief at 13:01, a feature map at 15:15, and at 17:56 a commit recording the
directive *"Liv with a better core and native UI."*

So the order was: **pick the shape first, adopt the product second.**

**Why that shape.** The constitution demanded undo, redo, history, "why is this
here", and safe AI writes *up front*, and treated them as one thing rather than
five features — *"Undo is not a feature bolted on later; it is the shape of a
command."* If undo must survive a restart and never lose the mistake, then
reversing has to append an inverse record instead of editing the past. Once you
accept that, the file on disk is a list of changes and the things you see are
that list played back.

The "our log cures the old app's disease" story is true but was written
*afterwards*. The old app kept a note in three places — a browser-storage blob,
a `.md` file, and a SQLite row — and its own code carries a comment explaining
that its file watcher could not tell the app's writes from a human's, so every
save re-scanned the vault and froze the app. The fix was a 2.5-second window
where it ignores itself. That comparison was measured on 2026-08-08: one store
against three, one file touching the core against seventy.

---

## 2. Head to head, honestly

Where the SQLite engine is genuinely better — and it is, on four counts:

| | log | SQLite |
|---|---|---|
| **Full-text search** | no index at all; a full scan that rebuilds each entity's text per query, scored in five fixed tiers | FTS5 kept in step by five triggers, BM25 with title weighted 5×, snippets, prefix search |
| **Filtering** | AND only. Five operators, one sort key, no OR, no NOT, **no strict `<`/`>`** — only "at most", so a calendar date range is not expressible as a query | a recursive And/Or/Not tree, ten operators, compiled to parameterised SQL against real indexes |
| **Reading part of the box** | none. Every read returns the whole box as one JSON snapshot — 6.6 MB at 10,000 entities, rebuilt per read — and it carries **no note bodies**, so a desktop list is one extra call per note | `limit`/`offset`, bodies inline, snippets |
| **Two processes at once** | no. An exclusive file lock is taken before the first byte, on every call **including pure reads**. A second process is refused | WAL: outside readers never block |

Where the log is better:

| | log | SQLite |
|---|---|---|
| **"What did this say three weeks ago"** | yes, for free — a version is a walk backwards | **never.** Updates overwrite in place; delete is a hard DELETE with cascades. No versions table, no revision column |
| **Undo, and provenance** | one step, across every surface, surviving restart. Every change carries a typed author: User, Proposer, System | nothing. No undo, no author, no audit |
| **Live facet counts** | built in; the docs call it Liv's one great idea as a number | does not exist |
| **One clear model** | an entity is an id, a trashed flag, and a list of cells. Eight value kinds, closed | ten fixed columns plus four computed from an open JSON string the core never parses. Entity kind is free text with no constraint |
| **Tested** | 332 tests, four of them cost tests asserting shape | 29, correctness only, largest fixture four rows |

**Two rows were struck from an earlier draft of this table as padding.** "Does it
match what Liv promises" is circular — the promises describe the mechanism that
was already chosen, hours earlier. "What it would cost to delete" scores an
option nobody proposed.

**A dimension that was missing entirely: the log cannot erase.** There is no
Delete command; `Create`'s inverse is `Trash`. A pasted password, a client's
medical detail, a wrong name — permanent, in a file that only grows. SQLite wins
that outright, and for a desktop app over files the user owns, "delete this
permanently" is a normal expectation and a plausible legal one. **This has no
answer today.**

---

## 3. The recommendation

**Keep the append-only log as the one core. Delete the SQLite crate. Do not keep
two engines, and do not let each app use what suits it.**

Not because the log is technically superior — on search, filtering, paging and
concurrent reads it is plainly worse. The honest case is three things:

1. **Version history is not buildable on the SQLite core** without adding a
   second store — and two sources of truth is the disease that made the old app
   freeze.
2. **332 tests against 29**, including cost tests that catch the class of bug
   that hid a quadratic projection for weeks.
3. **One shell exists and the other does not.** The iOS app is 18,856 lines over
   the log core. The SQLite engine is reachable from 3 frontend files.

### What I would not do

- **Not adopt SQLite "just for the desktop"** because it has FTS5. Two cores
  means two data models, and §4 below is what that already looks like at
  one-tenth scale.
- **Not add SQLite as a second store beside the log.** If a measurement ever
  demands an index, build it as a cache *derived from* the log and rebuildable
  from it. The constitution already permits exactly that.
- **Not delete `core/schema.sql` and `core/src/migrations/` outright.** That is
  the FTS5 schema, the sync triggers and the BM25 weighting — the code you would
  otherwise rewrite when the derived index becomes a measured need. Keep them as
  seed material in the same change that deletes the engine.
- **Not start the desktop port before §4 is closed.** The whole point of one
  core is that a second shell opening a box made by the first sees the same
  thing. Today it would not.

### The honest costs, stated up front rather than discovered

**Log growth is the real gate, and it is not about entity count.** Measured: a
1,980-byte note body costs **4,215 bytes of log per save**, because every content
save appends the old whole body *and* the new one. The iOS editor flushes after
2 seconds of idle plus a 30-second checkpoint — dozens to hundreds of whole-body
writes per note per writing session. Against the desktop's own stated case, a
900-note vault at 50 lifetime saves each is roughly **270 MB of log**, at ~5 ms
of open cost and ~2.5 MB of RAM per megabyte, with nothing compacting it ever.
Counting *entities* (the real box has 104) says there is 100× headroom; the cost
tracks *saved bytes of history*, and the desktop is a writing app.

> **Compaction or a snapshot file is a design gate before the desktop port, not
> a "fix it when a number says so" item.**

**Overturning D01 is a product reversal.** The desktop's decision log rules that
the user's files are the truth and SQLite is a rebuildable index. The log takes
the opposite side: the box is the truth and the folder of files is a rebuildable
projection. You cannot have both. Overturn it in writing or the two documents
keep contradicting each other.

**Deleting the SQLite engine deletes shipped capability.** Its search is on by
default and the vault index is live; note reads through it are no longer
flag-gated, they are the only path. Going away with it: tag search, the typed
link graph (recursive queries to depth 50), workspace membership as links,
`source_key`/`reindex_vault`, path lookup, prefix search and snippets. Desktop
search will be **worse on day one**. That is an accepted cost, not an oversight —
and it is recoverable later as a derived index, whereas history built on SQLite
is not recoverable at all.

**The migration is the largest unplanned piece.** It is not 104 entities. Only 6
collections route to SQLite; workspaces, tabs, layouts, lists, bases, versions
and settings live in per-vault `state.json` **with no target model in liv at
all**. There are 264 direct storage calls from 69 files, 6 known vaults, and a
live divergence where the database holds 96 notes while the active vault's blob
holds 1. The existing mapping ledger fills 9 of the 24 metadata keys real notes
carry and drops 15. **There is no importer, no dry run, no per-note
verification, no rollback, and no rule for which store wins when they disagree.**

**Good news on verification.** An earlier draft claimed Cargo cannot load both
crates. That was tested and is **false** — the collision is name + version in the
lockfile, not the crate name. Renaming one and bumping a version links both
engines into one binary. That makes a **dual-run harness** possible: write to
both, diff the results. It is exactly the verification the migration lacks, and
it should be how the migration is proved.

---

## 4. Properties in Swift — the owner is right

> *"the properties is a core mechanism and having it partially implemented by
> the swift layer is probably an earlier mistake."*

**Yes, and the evidence is blunter than expected.** A fresh box made with the CLI
ends at entity #4154 and contains **no `area`, no `project`, no `subjects`, no
`people`, and no area options**. Those four filing fields do not exist in the
core. Swift creates them on every launch, as User-authored writes — so they even
carry different provenance from the core's System-authored seeds, and a second
shell can see the difference on the wire.

Ranked by how much each would hurt a second shell:

1. **The furnished vocabulary.** The six area names are a Swift constant
   (`Furnish.swift:20`), and `project` / `subjects` / `people` are minted at
   `Furnish.swift:27`. A Tauri shell opening a core-made box shows four filing
   fields, three of which do not exist and one of which is an empty picker. Two
   shells furnishing the same box both write their own definitions. There is
   also an unreconciled collision: `project` is a shell *property* and,
   separately, a core *type*, told apart only by an accident of id ordering.
2. **The query grammar, parsed twice.** `Workspace.swift:100` in Swift claims to
   be a verbatim port of `services/src/search.rs:83`. It is not — five proven
   differences, including `due<20260801` being a real constraint in Rust and
   silently dropped in Swift. Both parsers already run on one screen: Search
   sends the query to the core, then re-filters the core's answer in Swift.
   Standing rule 4 names this a defect.
3. **Stamping.** The rule that a workspace's terms get written onto anything made
   while it is active — the thing that makes filing happen without folders —
   lives in `Workspace.swift:417` and has no Rust word at all. A second shell
   creates unfiled items in the same workspace.
4. **The properties panel.** The core seeds five display attributes — `icon`,
   `digit-key`, `hide-on-kind`, `hide-when-empty`, `core-on-kind` — and ships all
   five on the wire. Swift decodes two and reads neither, driving its sections
   from a hardcoded list instead. **Caveat, and it matters:**
   `design/p11.5-grammar-kit.md:44-48` specifies the intended design as *shell
   constants with core-cell overrides* — so the Swift table is the spec, and only
   the override path is missing. And `core-on-kind` is a two-bucket rule while
   the panel has three sections, so this is not simply "read what the core
   already sends".
5. **Entry status for a new task.** The core answers it (`default-status` on the
   type) and `create_task` honours it; the Inbox's Route→Task and the Tasks
   checkbox both ignore it and guess. Nearly free to fix.
6. **Markdown blocks — this one loses data today.** Swift knows 7 block shapes,
   the core has 9. The shell's own self-check asserts that code fences and
   callouts come through as "other" and are flattened on save. **A code fence
   written by the CLI or an import is destroyed by an iOS edit.**
7. Smaller facts-about-values: which properties accumulate versus replace (Swift
   decides; the core has no cardinality concept), and the file-format taxonomy.

**Over-scoped, for balance.** Section *names and order* are presentation — only
membership is data. And document-versus-card derives purely from `kinds`, which
the core already ships; freezing a phone affordance into the ABI would be a
mistake.

**Already correct, and the model to copy:** the status vocabulary with its order,
hues and completes flag is fully core-owned and read off the wire; link-versus-
filing is core-owned; and every C-ABI call still lives in one file.

This was **a decision, not a slip.** `design/ios.md:711` says so on purpose —
*"All of it lands from the SHELL via existing verbs."* Reverse it in writing.

---

## 5. Sequence

Ordered so that nothing is built on something that has to move.

**0. Stop the bleeding.** Fix the markdown block loss — either teach the iOS
editor Code and Callout, or refuse to save a document whose blocks it flattened.
Then **audit whether damage has already happened**: walk the log for content
versions containing Code/Callout that a later version flattened. This destroys
content today and must not sit behind days of writing. *1–2 days.*

**1. Write the decisions down.** Overturn D01 in the desktop's decision log;
banner the two plan documents that still say SQLite is the source of truth;
amend `design/ios.md` §10 to move the furnishing into services; fix `CLAUDE.md`
(the old app is not a separate repo, and the pivot document it cites exists only
on an unpushed local branch). Also resolve **repo topology** — merge, subtree,
vendor or publish — because a `path = "../../liv/core"` across two working copies
of one remote is unclonable and un-CI-able. *Half a day of writing, plus one
real decision.*

**2. Move the furnishing into the core.** A sixteenth guarded seed pass in
`services/src/lib.rs`: an `area` select born with the six options, plus
`project`, `subjects`, `people`, all `Author::System`. Failing test first.
**The trap:** every existing iOS box already has these at ids #4155+, minted by
Swift. The seed must *adopt an existing definition by name*, never mint a
duplicate — with a test for exactly that case, verified against a copy of the
real box. Then delete the minting half of `Furnish.swift`. *~2 days.*

**3. The small data rules, as one batch.** Entry status; the tick predicate, once,
in Rust; cardinality as a cell on a property definition; the file-format
taxonomy. *~1 week.*

**4. One parser.** Port the five Swift-only behaviours into `search.rs` as
failing tests first — deciding each deliberately rather than letting Rust win by
default — then expose the lens as an additive verb and delete the Swift parser
and the post-filter. Capture the before-picture from the *running shell* first;
the CLI cannot evaluate the Swift lens. *1–2 weeks. The largest single item.*

**5. Stamping into the core**, as one compound verb (rule 8 permits it). *2 days.*

**6. The properties override path** — decode the remaining display attributes and
let core cells override the shell's table, per p11.5. Includes one additive ABI
bit marking a property user-facing, so Settings stops listing plumbing.
*~1 week.*

**7. Land the seam.** Rebase the pivot branch: rename the SQLite crate, add the
liv crates as path deps, add the Tauri command layer behind a flag. **Give it a
store cache immediately** — it deliberately has none, so every command replays
the whole log, and doing weeks of mapping on an uncached layer makes every
performance observation wrong in both directions. *1–2 days.*

**8. Compaction or a snapshot file**, with a cost test that builds a box with
deep edit *history* rather than many entities — none of the four existing cost
tests do. This is the gate from §3. *Size unknown; measure first.*

**9. The migration**, proved with the dual-run harness: write to both engines,
diff. Needs an importer, a dry run, per-note verification, a rollback, and a
written rule for which store wins on disagreement. Plus a target model for
workspaces, tabs, layouts, lists, bases and settings, which have none.

**10. Semantic mapping**, kind by kind — the pivot doc's own estimate is 2–4
weeks and that looks right, because the existing ledger drops 15 of 24 metadata
keys.

**11. Delete `old-sqlite-core`** and its dead wrappers, in the same change that
makes them unnecessary. Keep the FTS schema as seed material.

---

## 6. Open questions the owner must answer

1. Overturn D01 — is the box the truth, or are the files?
2. Repo topology: merge, subtree, vendor, or publish?
3. Is permanent erasure a requirement? The log has no answer today.
4. Is worse desktop search acceptable on day one?
5. What number triggers building a derived index? Decide it now, so it is not
   re-argued from taste later.
6. The pivot document gates on **seven** owner decisions. This records one.
