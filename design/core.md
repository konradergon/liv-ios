# The core — what it should be

> **Status:** proposal, 2026-08-22. Written because the owner asked, in order:
> *"ignoring all cores, what is the ideal core architecture given what Liv is?"*,
> then *"is this model memory dependent? if so, it is probably not what we want"*,
> then *"measure a synthetic box at 50k and 500k entities"*.
>
> **Nothing here is decided.** It records a design, the measurements that shaped
> it, and what it costs. The build order lives in `core-plan.md`.
>
> **This document describes a PROPOSED model, not the code as it stands.** Where
> the two differ, the difference is called out inline. Every measured number is
> marked with what was measured and when; everything else is a proposal.
>
> **Two constraints the owner set, which this design obeys:**
> 1. *"we can't break or change how the tauri app works."*
> 2. *"both shells will share one core."*
>
> **Relationship to `one-core.md`** (2026-08-19): that document asked which of the
> two existing cores survives and recommended deleting the SQLite one. That
> recommendation is superseded by constraint 1. Its evidence, costs and open
> questions still stand. This document does not choose between the two cores; it
> describes a third thing both can become.
>
> **Reviewed adversarially on 2026-08-22** — 41 corrections applied, including a
> fabricated quotation in §0 and a self-contradicting phase order in the plan.
> Claims that survived are marked measured or verified; claims that could not be
> checked say so.

---

## 0. What forces the shape

Not taste. **Five** promises in `what-liv-is-for.md`, which is shipped copy, plus
the owner's own statement of the selling point.

| # | The promise (verbatim) | What it forces on the core |
|---|---|---|
| P1 | *"It comes furnished."* Six areas, six fields, six kinds — and a seventh kind of field is possible, *"behind a door in Settings"* | The default furniture is compiled-in so it cannot drift between devices. A **user-created** field is data, and needs a merge rule (§5) |
| P2 | *"It catches anything in two seconds."* | A write is one append. No schema decision at capture time |
| P3 | *"Sorting is a tap, not a project… It never decides for you and never asks twice."* | Proposals are first-class; a decline is remembered permanently and offline; **no merge may silently pick a winner** |
| P4 | *"Everything is kept, in your own files."* Every version still there; *"If Liv vanished tomorrow, your work wouldn't."* | History is not bolted on — every change is recorded, always — plus a complete export, including history, kept current and verifiable |
| P5 | *"It follows you."* Real sync being built | Merge must be deterministic per field, with no server to arbitrate |

And the owner, on what the product actually is:

> *"the most core thing (the app's selling point) is organisation and properties
> (metadata)."*

That sentence is why properties are the model rather than a column on a note.

**One line from the product doc constrains the model further:** *"The engine
underneath can hold any structure at all. We are choosing not to show that. It's
insurance, not a feature."* The model must be general; the UI must not be.

---

## 1. The answer, in one paragraph

**An append-only log of operations is the truth. A materialised view on disk
answers every question. Each property has one small merge rule chosen for what
that property means. Both live in one embedded database file, updated in a single
transaction per user action.** History and sync need the same artefact — a
durable, per-device, causally-stamped record of every change — so it is built
once, and undo, provenance, "go back", conflict detection and a rebuild button
all fall out of it.

**Sync does not force the log.** Delta-state CRDTs converge with no log at all.
Three other things force it: history is a measured success criterion; a bug in the
view is repairable by replay where a bug in a state-first store is permanent; and
once a log exists, sync is a range scan rather than a diffing protocol.

---

## 2. The data model

**A thing in Liv is an entity, and an entity is just an id.** It has no shape of
its own — no columns, no database type. A note and a person are the same kind of
nothing until something is said about them.

**Everything visible about a thing is held in a cell**: a property and a value.
`due = Friday` is a cell. `kind = Task` is a cell. A note is an id plus a bag of
cells. This is why a note can become a task without moving between tables — one
cell is written and it is a task now.

**The property half is a number, not a word.** *Proposed change:* the six the user
sees — due, status, area, project, people, tags — become compiled-in fixed ids, so
two devices can never seed slightly different versions of "Area". **Today they are
seeded entities at user-space ids**, which is exactly the drift this closes. §12
records that this particular choice is reversible.

**The value half is one of a closed set of kinds** — text, number, boolean, a date
specification, a reference to another entity, or a content hash. Closed means a
value that does not fit is refused at the door rather than discovered later.

**The reference is the mechanism that makes properties the product.** Projects,
tags and people are not words written on a note; they are entities, and the note
holds their id.

- **Rename** a project: one write to one cell. Every note follows, because none of
  them held the name.
- **Merge** two tags: one write saying *this one now means that one*. Cost is
  bounded by references, not by box size. History still says the old name, which
  remains true forever.
- **"Everything with Anna"**: a lookup by id, not a text search.

**A note's body is a list of blocks**, each with its own id and a fractional order
key. The block is the merge unit. *Blocks do not exist today* — the desktop stores
a body string and the log core stores spans carrying block kinds inside one value,
not addressable blocks. Building them is its own phase.

**A change is made through an operation.** The vocabulary must cover at least:
`set` a cell · `add` to a set · `remove` from a set · `create` an entity · `trash`
an entity · `redirect` (the merge mechanism) · and `insert` / `set` / `move` /
`delete` a block. Keeping it small is what makes "the op format is an API forever"
a cheap promise; the exact count matters less than that the list is complete and
closed.

**Every operation carries a dot** — `(device, seq)`: which device wrote it and that
device's own running count. That is the operation's name for as long as the box
exists: how a device knows what it is missing, how a remove names what it removed,
how two concurrent edits are told apart.

```
EntityId = 16 bytes    UUIDv7 — sortable, created-at readable from the id
                       (today: u64 here, INTEGER PRIMARY KEY on the desktop)
DeviceId = 8 bytes     random at install, never reused
Dot      = (DeviceId, u64)                    identity + causality
Hlc      = (wall_ms, ctr, DeviceId)           display order and tiebreak ONLY

op row = (version, device, seq, hlc, author, entity, prop, value, replaces)
```

**`author` is carried forward** from the existing `Author` type — §8 needs it to
tell a proposal from a user write. **`version` is a format discriminator**, because
§13 refuses a newer box outright and cannot do that without one. **The encoding
must be written down before the first op is written**; a decoder cannot be
promised forever for a format that was never specified.

**A wall clock never destroys a value.** A device three days ahead can mislabel a
history row and win a tiebreak on screen. It cannot make anything disappear.

---

## 3. Where the truth lives

One database file holds both halves. The distinction is which is derived.

```
liv.db
├── ops              THE TRUTH. append only, never updated
├── vv               per device: highest seq held
│
├── entities         ┐
├── cells            │ THE VIEW. derived, indexed, disposable,
├── blocks           │ rebuilt by replaying ops from zero
└── fts              ┘

blobs/               photos and files by content hash, outside the database
export/              one-way projection, never read back
```

**The store should be SQLite.** Not for its query planner — the in-memory core
scans 500,000 entities in 1.6 ms (§9a), and while that number does not transfer to
disk it says the workload is not planner-shaped — but for three specific things: it
runs on both platforms, WAL lets an app extension read while the app writes, and it
carries a text index, which is the one gap §9b found. It is also already the
desktop's store, so the ideal shape and the reachable shape are the same file.

**Photo and file bytes are never in the log.** They are content-addressed alongside
it; ops carry hashes. That is what keeps "just replay it" affordable.

**That store does not exist in either tree, and the model is wrong today.**
`FileRef` is `{ path: String, hash: [u8; 32] }` (`core/src/value.rs:152`) — it
carries a **device-local path**, which cannot survive a device boundary. The shell
also writes photos to `Application Support/liv/photos/` while the box lives in the
App Group container; the two are not in the same place. Lazy blob-by-hash is a real
subproject on the critical path for every sync transport.

---

## 4. The write path and the read path

**Write** — one user action:

1. Build the ops. Reads the view to fill `replaces`.
2. Open one transaction.
3. Append the ops. Update the view through the merge rules. Update the indexes.
4. Commit once.
5. Emit the ops to the shell as a delta.

**One user action is one group and one commit.** Not one op — one *action*. A crash
between two ops of the same action must not leave half of it, and grouping is also
what makes undo reverse what the user thinks they did.

**Read** — the view answers directly. Nothing is folded at launch. Opening reads the
version vector and applies any ops that arrived since.

---

## 5. Sync

**Exchanged:** version vectors first (48 bytes for three devices — a `(DeviceId,
u64)` pair is 16 bytes), then contiguous op ranges per device, then blobs by hash,
lazily.

**One transport rule deletes a subsystem:** each device's ops arrive in order or not
at all. Per-op dependency vectors and causal-delivery buffers are then empty in every
real execution. **This is a property of the transport, not a wish** — see §14.

**Merge, per field type:**

| Property type | Rule |
|---|---|
| Single-valued (due, status, area, project, kind, title, url) | Multi-value register. Union entries; drop any named in another's `replaces`; what remains is live. More than one entry = **contended** |
| Sets (tags, people) | Add-wins, observed-remove. Each add carries its own dot; a remove names the dots it saw |
| Declined fingerprints | Grow-only set. Union. Needs no coordination, which is why "never asks twice" works offline |
| Body blocks | Per-block register, plus the fractional order key |
| **User-created fields** (P1's Settings door) | **No rule yet.** Out of scope for v1; the plan must say what the UI does when one arrives from another device |

**"Six fields" is the product's count of what a user picks from.** The engineering
set is larger — seven single-valued registers, two sets, plus the system
properties — and the rule is chosen per property, not per user-visible field.

**P3 survives sync because nothing silently wins.** A contended register keeps both
values and shows the choice. Same mechanism for every field, including the body.

**Sync is not a second code path.** A record from the laptop is applied by the same
function as one you just typed. Only the device id differs.

**Five things this table does not yet cover** — the sharpest hole first:

1. **Entity existence.** Create, trash, and delete-versus-edit have no rule and no
   verb in §2's list beyond being named. Two devices, one deleting and one editing,
   is the most likely real conflict there is.
2. **The opaque `extra` cell** that carries unknown `content_json` keys. Two devices
   editing different unknown keys inside it produce a contended register on a field
   the user cannot see, name or resolve.
3. **Fractional order key ties.** Two devices inserting at the same position offline
   generate the same key. Breaking the tie by clock means a skewed clock **reorders
   the user's paragraphs**, which contradicts "a wall clock cannot make anything
   disappear". Ties must break on dot, not on HLC.
4. **Redirects / merges** — read-time id resolution has no merge rule.
5. **Blob cells** — two devices attaching different photos to one cell.

---

## 6. The note body

**No character-level CRDT.** Not Yjs, not Automerge, not Peritext. Character merge is
the one merge that can produce a sentence the user never wrote, which is exactly what
P3 forbids. It is also the hardest three weeks in any plan, and its output gets
flagged "merged — see history" anyway, which a block register gives for free.

**No whole-note last-writer-wins.** An afternoon of writing vanishes and nothing
notices.

**Said out loud rather than hidden:** merging paragraph 2 from the phone with
paragraph 3 from the laptop still produces a note nobody wrote as a whole. So a note
that merged from two devices is marked as such, and both parents are named versions
in its history.

**Commit granularity.** The editor holds a local buffer; a block commits on ~2 s idle,
on block exit, or on blur. Tell the user "every session is kept", not "every
keystroke".

**Markdown is a serialization for export and paste-in. Nothing in the live model is a
Markdown string.**

---

## 7. History

**"Show me this three weeks ago"** = replay this entity's ops with `hlc <= T`. Two
details matter:

- The view must index **entity → ops**, or the one read the product measures as
  success has no implementation.
- Replay by **logical clock, not arrival order**. A note written on a train and synced
  a week later must be present when the laptop is asked about last Tuesday, or two
  devices disagree about the user's own past.

**Versions are derived at read time, not sealed at write time.** Cluster consecutive
ops by device and entity with gaps under five minutes: "Today 09:12 · iPhone · +140
words". Granularity becomes a display policy; nothing on disk changes if it should
later be finer.

**"Put it back" is a new forward write**, never a rewrite. Restoring is itself undoable
and appears in history as a thing the user did.

**Five years, from measured per-entity sizes:** 3,000 notes, 300k words, ~8 body
sessions and ~15 property writes a day → log ≈ 25–30 MB. **This arithmetic omits at
least five terms**: op headers and dots, `replaces` lists, the block-per-revision cost
from §6, index overhead in the view, and anything imported in bulk. Treat 25–30 MB as
a floor, not a forecast.

**Even so: no compaction, no GC, no archive** at this scale. Revisit at 500 MB.

---

## 8. Proposals

**Proposals are pure functions of state**, computed rather than stored, and never
synced — regenerating is cheaper than replicating. A detector is
`(&Entity, &Vocab) -> Vec<Proposal>`.

**A pending proposal is an operation that has not been applied**, carrying the
proposer in the op's `author` field instead of the user. Accepting applies it.
Declining writes its fingerprint into the grow-only declined set. Unapplied and
applied are two states of one object, not two mechanisms — which is what makes
"nothing lands unconfirmed" a property of the type rather than a rule someone has to
remember.

---

## 9. What was measured

Real boxes, built and opened on the existing log core — a faithful instance of the
memory-resident version of this model. Release build, 8-core Mac, 8 GB RAM, log on
APFS. Harness kept out of the repo; tree unchanged.

### 9a. Scale (2026-08-21)

| | 5,070 | 50,070 | 500,070 |
|---|---|---|---|
| Log on disk | 2.7 MB | 27 MB | 276 MB |
| Bytes per entity | 570 | 572 | 579 |
| **Memory held (RSS)** | 15 MB | 126 MB | **668 MB** |
| **Cold open (fold)** | 15 ms | 114 ms | **1,317 ms** |
| Full scan, every cell | 0.01 ms | 0.09 ms | **1.6 ms** |
| **One write** | 8.4 ms | 8.1 ms | **8.9 ms** |

**What this settled:**

- **The measured write is flat** — 8 ms at every size, which is the fsync and nothing
  else. **The write this design proposes is not that write**: it also reads the view to
  fill `replaces` and updates indexes in the same transaction. Flatness must be
  re-measured, not inherited.
- **Scanning is free in memory.** Every cell of 500,000 entities in 1.6 ms. The
  workload is not planner-shaped.
- **Memory is the ceiling.** 3.0 KB per entity at 5k falling to 1.3 KB at 500k —
  sublinear per unit, but **668 MB in absolute terms**. This is the measurement that
  moved the view out of RAM and onto disk, and it is the whole of the correction.
  668 MB is fatal on a phone and hopeless in an app extension, where folding the box
  is the price of writing one row — and "catching things from other apps" is a stated
  near-term requirement.
- **Cold open grows faster than the data** — 7.6× from 5k to 50k, 11.6× from 50k to
  500k, being linear in history with a cache-miss penalty on top. It climbs even when
  the note count is flat.

### 9b. Search (2026-08-22)

Same boxes, selectivity held as the control.

| Term at 500k | Matches | `run()` alone | Full search |
|---|---|---|---|
| `zzzznone` | 0 | 85 ms | 345 ms |
| `tok7` | 500 | 44 ms | 240 ms |
| `about` | 500,000 | 39 ms | 289 ms |

**Search is not superlinear.** Per entity the cost is flat — 0.4 to 0.7 µs at every
size, with a ~1.3× per-unit penalty at 500k from cache misses at 668 MB resident. An
earlier 30× reading was the corpus, not the algorithm.

**A term matching nothing is no cheaper than a term matching everything** — 345 ms
against 289 ms — because `run()` returns all entities and the text term only scores
afterwards. There is no index; the query never narrows anything.

**Where the time goes** — 3,277 samples of a steady search loop at 500k:

| | share |
|---|---|
| `searchable()` — build the text | 32% |
| `views::display()` — render each value | 31% |
| String and Vec reallocation | 29% |
| `to_lowercase()` | 4% |

**~92% is rebuilding a lowercase searchable string for every entity, from scratch, on
every keystroke.** Separately, `store.recency()` walks the whole transaction history
and allocates a fresh 500,000-entry map on every search — 99 ms at 500k, identical
every time.

Steady state: **18.6 ms at 50k, 264 ms at 500k.** At the real box size of ~104
entities this is microseconds. A ceiling, not a bug hurting anyone today.

---

## 10. Four defects, one pattern

| Where | What | Found | Fixed |
|---|---|---|---|
| `services/src/projection.rs` | The file projection resolved a property by scanning the store, once per entity | 2026-08-09 | 2026-08-13 |
| `services/src/clerk.rs` | The mention sweep walked the whole box per write | 2026-08-19 | 2026-08-20 |
| `services/src/content.rs:1497` | `find_type` runs a full-box query on every note creation, while `store.named()` is an O(1) index beside it | 2026-08-21 | **open** |
| `services/src/search.rs` + `core/src/store.rs:206` | The searchable corpus and the recency map are rebuilt per query | 2026-08-22 | **open** |

**All four are the same mistake: rebuild on read instead of maintain on write.**

Measured for `find_type` — build rate, before and after a one-line change to use the
existing index:

| Box | Today | Using the index | |
|---|---|---|---|
| 10,000 | 6,557/s | 18,366/s | 2.8× |
| 20,000 | 4,494/s | 19,457/s | 4.3× |
| 40,000 | 1,354/s | 19,778/s | **15×** |

The write path is O(box) today and O(1) with the index. The patch was measured and
reverted; `core`/`services` change only on the owner's word, failing-test-first.

**This pattern is why the design maintains the view in the same transaction as the
write.** Two of the four dissolve into that. `recency()` does not — it is waste at any
size and is a monotonic counter that could be maintained on append.

---

## 11. What this is bad at

- **Bulk import.** Ten thousand mail messages are ten thousand ops. The comfort zone
  is human-typed volume.
- **Real erasure.** A password typed into a note lives in every device's log and every
  backup. A purge rewrites local bytes and cannot reach backups. Say so in the UI.
- **Sharing.** The sync unit is the whole box. One note shared with a friend is a
  redesign.
- **Live co-editing.** Block granularity means a prompt, not a second cursor.
  Deliberately closed.
- **Cross-entity invariants.** CRDTs converge; they do not constrain. "No two tags with
  the same name" cannot be enforced at the data layer and must be a proposal. **No
  UNIQUE constraint may sit in the merge path** — two devices typing the same tag
  offline is normal, and a constraint turns it into wedged sync. See §14.6: the
  desktop schema has three today.
- **Analytics over history.** The log is a journal. "How often did I move due dates last
  year" needs a second derived table, built on purpose.
- **Merge bugs are quiet.** They surface as drift weeks later. A digest exchange is a
  mitigation, not a cure.

---

## 12. The three decisions to make before writing code

1. **Write identity is `(device, seq)`, not a box-wide counter.** Change it after the
   box holds real data and every id in the log and the view is rewritten. Foreclosed by
   choosing it: nothing. Foreclosed by not choosing it: sync.
2. **The merge unit for a note body is the block.** Forecloses live co-editing and
   sub-paragraph merge, permanently, unless the wire format changes. Buys: no fabricated
   sentences, and one conflict mechanism for the entire app.
3. **The log is the truth; the view is derived.** Commits to a stable op vocabulary —
   every format ever written needs a decoder forever, which is why §2 requires the
   encoding and a version field to be written down first.

Deliberately **not** on this list, because it is reversible: whether the six fields are
compiled constants or entities. Ops carry an arbitrary property id either way.

---

## 13. Deliberately left out

- **Character CRDTs.** §6.
- **A query planner.** §9a.
- **Compaction, GC, archive, delta chains.** §7.
- **Per-op dependency vectors and causal-delivery buffers.** One transport rule replaces
  the subsystem — if the transport can guarantee it.
- **A forward-compatibility "partial view" mode.** One developer, two shells. Refuse a
  newer box outright, which the `version` field in §2 makes possible.
- **A syncing proposal stream.** Detectors are pure functions.
- **New UNIQUE constraints.** Constraints and eventual consistency do not compose.
- **A user-typed query language as the primary path.** Pickers over furniture that
  already exists.

---

## 14. Open questions

> **Four of these are now framed for decision in `design/core-decisions.md`** —
> entity identity, the three UNIQUE constraints, the sync transport, and undo
> granularity — each with its options, measured costs, a recommendation and what
> would change it. The op encoding this section demanded is written down in
> `design/op-format.md`.

1. **What is one undo step on the desktop?** The phone counts undo steps literally. The
   desktop's IPC is per statement and a note save is one whole-body replacement on a
   debounce, so "undo the due date I just set" is not currently expressible there.
   **Every estimate in `core-plan.md` swings on this.**
2. **Is permanent erasure a requirement?** §11. No answer today.
3. **What replaces "shorter than last time is impossible"?** The append-only file's
   corruption defence has no SQLite equivalent, and the box may live where a sync client
   can touch it.
4. **Repo topology.** The core lives in the desktop's tree; the phone is a branch line
   with no common ancestor. A `path = "../../liv/core"` across two checkouts of one
   remote — the obvious shape, and the reason it is not already wired — would not build
   for anyone who clones it. On the critical path immediately.
5. **What number triggers building a derived index?** Decide now, so it is not re-argued
   from taste.
6. **The three UNIQUE constraints.** §11 and §13 forbid a UNIQUE constraint in the merge
   path. The desktop schema has three — `tags.name`, `idx_entities_file_path`,
   `idx_entities_source_key` — one of them the exact tag case §11 names, and constraint 1
   forbids removing them. `idx_entities_source_key` is load-bearing: it is how external
   vault edits reach the app. Something has to give: either sync applies through a
   different path than a local write (which §5 denies), or the constraints go and
   `upsert_by_source_key` is rewritten, or the merge is allowed to reject. **On the
   critical path for sync, and unanswered.**
7. **Which sync transport?** CloudKit, an iCloud Drive file, a server, peer-to-peer —
   each is a different cost, auth story and failure mode, and §5's in-order guarantee is a
   property of whichever is chosen. **Encryption appears nowhere in this document**, for a
   product holding a person's whole life. Both need answering before Phase 8 is priced.
8. **Entity identity.** §2 specifies UUIDv7. Today it is a `u64` here and an integer
   primary key on the desktop. Two devices creating a note offline both take the next
   integer and collide on first sync. This is a separate decision from write identity and
   is currently unestimated.
