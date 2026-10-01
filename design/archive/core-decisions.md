# Four decisions the core is waiting on

> **Status:** 2026-08-22. Phase 0 of `core-plan.md`. These are the owner's calls,
> not the builder's. Each one is framed to be answerable: the question, the real
> options, what each costs, a recommendation with its reason, and what evidence
> would change it.
>
> Answers go in this file, dated, so the reasoning survives the decision.

---

## 1 — Entity identity

**Does an entity's id become a 16-byte UUIDv7 minted on the device, and does that
happen before the journal holds months of data?**

### Options

**(a) Keep integers, add `AUTOINCREMENT` on the desktop.** Fixes one local bug —
without it SQLite reuses `max(rowid)+1`, so deleting the newest note lets the next
one take its id, which alone makes a journal name the wrong note. **Fixes nothing
about sync.** Two devices creating a note offline both take the next integer and
collide on first contact. Forecloses sync outright, or forces a per-device
translation table that every op, every foreign key and every history row passes
through forever.

**(b) UUIDv7 everywhere.** Measured with a real compile probe — `Id` changed to
`[u8;16]`, `cargo check --workspace --all-targets`:

- **~145 compile errors, 80 of them in `ffi/src/lib.rs` alone.** The `Id` alias
  absorbs nearly everything else: 19 in core (15 of those a bootstrap constant
  table), 3 in services, 0 in views, 0 in the CLI.
- **39 of 57 C functions carry an id in their signature.** There is no portable
  128-bit C integer, so each becomes a struct, a string or a pair — **and `0` is the
  failure return for ten creator verbs**, which a struct return cannot carry. Each
  needs a new error channel.
- **`CLAUDE.md` forbids the shape of that change.** ABI additions must be purely
  additive. So either 39 parallel verbs ship beside the old ones — 96 total, each
  with a deletion date under rule 7 — or the contract is broken deliberately, on
  your word. There is no third option.
- **SQLite says no in one place.** FTS5's `content_rowid` must be an integer rowid,
  so `entities` keeps an integer surrogate alongside the UUID forever, five triggers
  carry both, and every existing database needs an FTS rebuild.
- **Wire cost, measured on a real 702-line box:** the log grows ×1.47 and a snapshot
  ×1.41 with canonical UUID strings (×1.2 compact). The new op format removes the log
  half; the snapshot half stays until the delta channel ships.
- **~×1.6 on hash-map build, lookup and memory** at 500k. Synthetic, on a Mac, not a
  phone.
- **68 sites compile clean and change behaviour** — 61 Rust `format!("#…")` lines, 7
  Swift, 7 CLI parsers. The sharpest: the shell decides a row is untitled by
  string-comparing its title against the decimal id, in two languages, with no shared
  code and no test asserting they agree.
- **It must be v7, not v4.** Fourteen Rust sites and seven desktop `ORDER BY e.id`
  tiebreaks assume id order is creation order. v7 preserves that; v4 shuffles
  "Everything" into random order.
- **Namespace ordering breaks either way.** `id < FIRST_USER_ID` means *is this
  plumbing* at three sites. v7 sorts by time, not namespace, so that needs a real
  discriminator — a data-model change wearing a type-change costume.

**(c) 16-byte ids, but the user never sees one.** The editor stores `[[4155|Kitchen
rebuild]]` in the buffer you are typing in, parsed by four independent scanners of
one grammar — which standing rule 4 already calls a defect. A 32-hex token visually
dominates the sentence it sits in.

**(d) `(device, counter)` as the id.** Same 16 bytes, no collisions, reuses the dot
you already need. But it sorts by device, not by time, so all 21 ordering sites break
the way v4 breaks them.

### Recommendation

**(b) and (c) together, and before the journal accumulates.** Break the C ABI once,
on your word, rather than shipping 96 verbs — the shell is written by the same
person, ships the same day, and has no third-party consumer.

Because nothing else makes offline creation on two devices safe; because §12 already
committed to the same argument one level up; and because **it is the only
irreversible step in the first half of the plan** — it gets more expensive every week
the journal grows.

### What would change it

- **A before/after run of the existing cost tests on a device.** If ×1.6 on hashing
  plus ×1.41 on the snapshot crosses a threshold that matters on a phone, the answer
  becomes two id spaces — UUID in the log, a dense integer as the view's key, plus a
  translation table. More code, and only measurement justifies it. **This cannot be
  read off the source.**
- **Whether the chosen v7 generator is monotonic within a millisecond.** If it is not,
  21 ordering sites shuffle silently. `Outbox.swift` already implements a ULID for
  satellite sync — a precedent the codebase may not know it has.
- **Repo topology.** If the trees never merge and the phone keeps its own core, one of
  the two scoping exercises is wasted.

---

## 2 — The three UNIQUE constraints

**When two devices independently produce the same tag name, file path or source key,
does the merge reject, does the constraint go, or does sync write through a different
path than a local write?**

**They are three decisions with three different answers, and treating them as one is
the mistake.**

### `idx_entities_file_path` — drop it now, for free

**Nothing in the shipping app writes a non-NULL `file_path`.** `captureFile` is
defined and called from nowhere; the keyed write path never populates the column; the
files collection keeps paths inside `content_json`. The index covers zero production
rows, and the one test touching it asserts lookup rather than uniqueness.

This is not an architecture question. It is cleanup, and the dead command goes with it
under standing rule 6.

### `tags.name UNIQUE` — replace it, and the code gets simpler

Make the name the key and drop the surrogate integer, so `entity_tags(entity_id, name)`
is a plain add-wins set with an idempotent insert — exactly the set rule in `core.md`
§5. "No two tags with the same name" then becomes true by construction rather than by
constraint.

**Measured consequence of naively dropping it *without* the rewrite**, reproduced in a
scratch database: a third `work` row appears, `entities_by_tag` returns the same entity
twice, `list_tags` splits one tag into three, and `tags_text` becomes `"work work"`,
double-weighting it in the ranking. **Nothing throws.** That is `core.md` §11's "merge
bugs are quiet", demonstrated.

### `idx_entities_source_key` — the real decision

This one is load-bearing: `upsert_by_source_key`'s `ON CONFLICT … DO UPDATE` and
`reindex_vault` both require it, and the vault indexer is how external edits reach the
app. Two devices indexing the same vault file independently is not an edge case — it
is the normal case.

The three options in `core.md` §14.6 apply here and only here, and this is the one
that is genuinely blocked.

### Recommendation

Drop the first, rewrite the second, and **treat the third as the actual open
question** rather than carrying all three as one.

---

## 3 — Sync transport

**Which transport carries op ranges between devices, and is it end-to-end encrypted
on day one?**

### A framing correction first

`core.md` §5's *"each device's ops arrive in order or not at all"* is **two
properties, not one**, and §13 banks a whole subsystem on conflating them:

- **No gaps** — never apply `(D,7)` without `(D,6)`. Every op carries a dot, so **any**
  transport can satisfy this with one integer per device and a holding table. Roughly
  fifty lines, not the subsystem §13 deletes.
- **Prefix atomicity** — whatever B sees of D's stream is always some prefix. **Only one
  of the four gives this for free.**

**Build the hold buffer regardless of what is chosen below.** It is cheaper than betting
on a transport.

### Options

**Per-device append-only files in a synced folder.** One writer per file, so there are
no conflicts to resolve; an append-only file's every visible version is a prefix of the
final one. Blobs are `blobs/<hash>`, immutable and write-once. $0 to run, nothing to
operate, smallest build, and it matches P4 — your work sits in an ordinary folder.
**Costs:** you do not own the transport, so *why hasn't my phone synced* has no
diagnosis; e2e means encrypting the files yourself (AEAD plus a pairing UI, 1–2 weeks);
the box must become per-device op files rather than one file; and **on iOS it needs an
iCloud ubiquity container**, where the app writes to an App Group container today.

**Self-hosted relay.** The only option where you define the guarantee — the server
rejects a gap. Works everywhere because it is HTTP, lives in the Rust core so both
shells get one implementation, is the only one deterministically testable, and the only
one with real push. Genuine e2e even on a rented box. €4.35/month. **The cost is not
money — it makes you an operator.** TLS, backups, upgrades and a 3am outage all have
exactly one person to fix them. 2–4 weeks.

**CloudKit.** Best auth and best encryption of the four, both free. **Disqualified by
one line:** the desktop ships Windows and Linux, and CloudKit's private database is
unreachable from a non-Apple client without interactive Apple ID auth — which breaks
under Advanced Data Protection anyway. Bear ships exactly this and says plainly that
its web client will not work with ADP on. Also **does not deliver in order**: Apple's
own guidance says no ordering guarantee on fetched changes.

**Local-network peer-to-peer.** Right properties, wrong product. No store-and-forward,
and no iOS app runs continuously in the background, so it syncs only while both devices
are awake, unlocked and in the same room. Against "It follows you", that is a product
failure.

### Recommendation

**Per-device append-only files in a user-chosen synced folder.** iCloud Drive on
iOS/macOS/Windows, "point at any folder" on desktop for the Linux or Syncthing user —
**the same file format either way**, which is the point.

**And make that file format the relay's wire format**, so moving to a relay later is a
client swap rather than a rewrite.

**Encryption: not on day one, and say so out loud.** It appears nowhere in `core.md`,
for a product holding a person's whole life. The honest v1 answer is provider-held keys
plus a written statement of what that means.

### What would change it

- **Desktop drops Windows and Linux** → CloudKit first, immediately.
- **You are willing to run a server** → relay first. Testable, debuggable, honest about
  its own failures.
- **E2E required on day one** → relay first. The folder option's cost rises by exactly
  the relay's crypto work, and the relay's other advantages come free.
- **"Share one note with someone" ever appears** → files and CloudKit both die.

### Regardless of the answer

1. `(device, seq)` must be **plaintext metadata** in every transport.
2. **Build the hold buffer anyway.**
3. **The blob store does not exist in either tree**, and `FileRef` carries a
   device-local path that cannot survive a device boundary. The shell writes photos to
   one directory while the box lives in another. Lazy blob-by-hash is a real subproject
   on the critical path for all four options.

**Unverified, and worth ten minutes before committing:** whether an iOS app's
document-scope-public folder is visible to iCloud for Windows. No authoritative
statement was found either way.

---

## 4 — Undo granularity on the desktop

**What is one undo step, when the core boundary sees a whole-note replacement 450 ms
after you stop typing?**

### The facts

- Every note save routes through `upsert_by_source_key` carrying the **whole** title,
  body and `content_json`, on a 450 ms debounce, and it is the only path now.
- **The coarse path is exactly one command.** Of ~34 Tauri commands, tag add/remove and
  link create/remove are already fine-grained; it is the note save specifically that
  collapses everything into one blob.

So "undo the due date I just set" is not expressible today, because the frontend never
told the backend which field changed. **This is a frontend decision wearing a core
question's clothes.**

### The shape of the answer

Either the desktop's save path learns to say what changed — which makes property-level
undo possible on both shells and is the honest fix — or undo on the desktop is
note-level only, and the phone's finer undo becomes a platform difference that has to
be stated rather than discovered.

**Everything in `core-plan.md` Phase 8 swings by weeks on which.**

---

## Answers — 2026-08-22

> **Delegated by the owner:** *"for now make all required decisions yourself and
> continue with the phases. don't worry too much about having the new core work
> with the tauri app as it is now, just that it will be relatively easy for others
> to integrate it later on. goal is a future shared core and that the mobile app
> works with it initially."*
>
> **That reverses the plan's central constraint** and removes most of what made
> these decisions hard. The old plan grew the desktop's SQLite core in place, so
> every answer had to survive its schema, its generated columns, its UNIQUE
> constraints and its live data. The new target is a NEW core that the phone runs
> on first, built so the desktop can adopt it later.
>
> Three of the four questions were hard only because of the constraint that is now
> lifted. They are answered accordingly, and cheaply.

### The three decisions in `core.md` §12

1. **Write identity is `(device, seq)`.** No downside, and sync is impossible
   without it.
2. **The body's merge unit is the block.** Forecloses live co-editing, which the
   product does not want.
3. **The log is the truth; the view is derived.** With the op format now written
   down, the vocabulary promise is cheap to keep.

### 1 — Entity identity: **UUIDv7**

Was expensive because it meant migrating the desktop's integer primary keys through
FTS5 external-content wiring and 39 of 57 existing C functions. **A new core does
not inherit any of that.** Ids are 16 bytes from the first line of code, and the C
ABI is designed for them rather than retrofitted — a by-value struct, and a real
error channel instead of `0` meaning failure.

v7 rather than v4, because id order must remain creation order. **Monotonicity
within a millisecond must be verified in the generator**, not assumed.

The view keeps an integer surrogate rowid alongside the UUID, because FTS5's
`content_rowid` requires one. That is a local detail of the view, not of the model.

### 2 — UNIQUE constraints: **none in the merge path, by construction**

Mostly moot for a new schema. The rule is now a property of the design rather than a
negotiation with an existing one:

- **No UNIQUE constraint may sit on anything sync writes.** Convergence and
  constraints do not compose.
- **Tags are keyed by name** as an add-wins set, so "no two tags with the same name"
  is true by construction rather than enforced.
- The desktop's three constraints stop being this core's problem. When the desktop
  adopts, `file_path` is dead code and can go, `tags.name` is replaced by the above,
  and `source_key` becomes a vault-indexer concern — a projection detail, not a
  merge one.

### 3 — Sync transport: **per-device append-only files in a synced folder**

iCloud Drive on iOS and macOS, "point at any folder" on desktop for Linux and
Syncthing. **The same file format either way**, and that format is also what a relay
would carry — so moving to a server later is a client swap, not a rewrite.

One writer per file means no conflicts to resolve, and an append-only file's every
visible state is a prefix of its final one, which is the prefix atomicity the merge
rules assume.

**Build the hold buffer regardless** — one integer per device and a holding table,
roughly fifty lines. It is cheaper than betting on any transport.

**Encryption: not in the first version, and stated in the UI rather than implied.**
Recorded as a known gap, not an oversight.

### 4 — Undo granularity: **one user action is one group is one undo step**

The desktop's 450 ms whole-note debounce was the only thing making this hard, and the
desktop is no longer the constraint. The phone already counts undo steps this way.
When the desktop adopts, its save path either learns to say what changed, or it gets
note-level undo and that becomes a stated platform difference.

### 5 — The store: **SQLite, via rusqlite, bundled**

Not for its query planner — a full scan of 500,000 entities is 1.6 ms — but because
it runs on both platforms, WAL lets an app extension read while the app writes, it
carries the text index the measurements found missing, and **the desktop already uses
it**, which is most of what "easy for others to integrate later" means.

**Proven before being chosen**, 2026-08-22: `rusqlite` with `bundled` cross-compiles
for `aarch64-apple-ios-sim` and `aarch64-apple-ios`, and a `CREATE VIRTUAL TABLE …
USING fts5` query returns the right answer when run inside the simulator. 19.1 MB
static library before stripping. The current core has no C dependency and this adds
one; that is the price, and it was measured rather than assumed.
