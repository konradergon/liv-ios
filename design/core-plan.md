# Building the core — the phased plan

> **Status:** rewritten 2026-08-22, second direction. The design is `core.md`, the
> encoding is `op-format.md`, the decisions are `core-decisions.md`.
>
> **The owner reversed the central constraint:** *"don't worry too much about
> having the new core work with the tauri app as it is now, just that it will be
> relatively easy for others to integrate it later on. goal is a future shared core
> and that the mobile app works with it initially."*
>
> **What that changes.** The first plan grew the desktop's SQLite core in place, so
> every phase had to survive its schema, its generated columns, its UNIQUE
> constraints and its live data — which is where most of the risk and nearly all of
> the unpriced work lived. The new target is a **new crate the phone runs on**,
> built so the desktop can adopt it later.
>
> Gone with the old constraint: the genesis backfill, the `entity_cells` migration,
> the generated-column wall, the second `entities` rebuild, the three UNIQUE
> constraints, and the frontend change-notification channel. **Six phases of the
> old plan were about not disturbing something we are no longer disturbing.**
>
> **What replaces "do not break the Tauri app":** the engine has no iOS in it, no
> Swift assumptions, no phone-shaped verbs, and one documented on-disk format.
> Integrability is a property of the crate, not a promise about a schema.

---

## What is being built

A new crate, `engine/`, beside the existing `core/` rather than inside it. The
shipping app keeps working on `core/` until the engine can replace it, and the two
never have to agree.

```
engine/
├── id       EntityId (UUIDv7), DeviceId, Dot, Hlc
├── op       the six verbs, encode + decode, the version fence
├── log      append, read ranges, version vectors, torn tail
├── view     the SQLite schema, apply-op-to-view, the indexes
├── model    entities, cells, values, the furniture
└── api      what a shell calls
```

Rust only, no C ABI in the crate itself — the FFI stays a separate layer, so the
desktop can link the engine directly the way it links its own core today.

---

## Phase 1 — Prove the substrate · **DONE 2026-08-22**

*The one assumption that could have invalidated the design.*

`rusqlite` with `bundled` cross-compiles for `aarch64-apple-ios-sim` and
`aarch64-apple-ios`, and a `CREATE VIRTUAL TABLE … USING fts5` query returns the
right answer **when run inside the simulator** — not merely linked. 19.1 MB static
library before stripping.

The current core has no C dependency and this adds one. That is the price, and it
was measured before being accepted.

---

## Phase 2 — Ids and the op codec

*~1 week. Pure Rust, no storage, no IO.*

`EntityId`, `DeviceId`, `Dot`, `Hlc`, and the encoder and decoder from
`op-format.md` §4: group header, op records, the four op kinds, the value kinds.

Ships with:

- **round-trip property tests** — encode then decode is the identity, for every op
  kind and every value kind;
- **a hostile-bytes test** — truncated, trailing, non-minimal varints, bad UTF-8,
  `NaN`; the decoder returns a typed error and never panics;
- **the version fence test that does not exist today** — forge a newer version,
  assert the typed refusal and that nothing was written;
- **a monotonicity test on the v7 generator.** `core-decisions.md` says this must be
  verified rather than assumed, because 21 ordering sites depend on it.

---

## Phase 3 — The log · **DONE 2026-08-22**

*Eleven tests.*

Append a group, read a range, version vectors, and the torn tail. One user action is
one length-prefixed group with its own checksum: a reader that runs out of bytes
mid-group drops the whole group.

**The hold buffer ships here**, not with sync — so an op is never applied without the
one it follows. `core-decisions.md` says build it regardless of transport, because it
is cheap and it stops the transport choice from being load-bearing.

*(Renamed from "gap buffer" on 2026-08-22: it holds ops waiting on gaps in a sequence,
and in a codebase containing a text editor that name collides with the editing
structure of the same name. "Pending" was unavailable too — the proposal queue owns
that word.)*

**Two forms, one encoding.** Locally the log is a SQLite table, so a write can join
the view's transaction and either both land or neither does. On the wire it is a flat
stream of the same frames — so a sync file is a log and a log is a sync file, with no
conversion between them.

---

## Phase 4 — The view, and the replay gate · **DONE 2026-08-22**

*Twelve tests. The gate passed on its first run.*

The SQLite schema, and one function that applies an op to the view inside the same
transaction as the append.

> Drop every projected table, replay the log from zero, and they come back
> byte-identical.

Randomised writes, then the same test against a box built by the phone. **If this
cannot be made to pass, the design is wrong and everything after should stop.** It
is cheap here and expensive later, which is the whole reason it is Phase 4.

Cost test alongside, asserting shape rather than milliseconds — and it earned its
place immediately. One write was **6.03× slower on a box ten times the size**:
`next_seq` asked for `MAX(first_seq + op_count)`, an expression SQLite cannot answer
from the `(device, first_seq)` index, so every write scanned everything that device
had ever written. Taking the last row by key instead makes it a descending index
seek. **A correctness test could not have seen it** — the answer was right the whole
time.

**One table serves registers and sets both.** A cell row is keyed by the dot that
wrote it, so "one live value" and "many live values" are the same shape: a register
with two rows is contended and shows the user the choice, a set with two rows has two
members. The difference lives in the ops — `SetCell` names what it replaces,
`AddToSet` does not — and never in the schema.

---

## Phase 5 — The model · **DONE 2026-08-22**

*Twelve tests.*

The furniture — six areas, six fields, six kinds, three statuses — as compiled-in
constants with frozen ids. **Not seeded: there is nowhere to write them.** Two fresh
boxes on different devices agree about all of it having exchanged nothing and having
written zero ops, which is the whole answer to the drift `one-core.md` §4 records,
where the phone mints its own copy on every launch.

**A real discriminator, at last.** `core-decisions.md` flagged that `id <
FIRST_USER_ID` — the old "is this plumbing" trick — dies with UUIDv7, because v7
sorts by time rather than by namespace. Furniture ids are UUID version 8 with the
class in the low nibble and a readable marker in the tail, so the check is one nibble
and does not depend on ordering at all.

**Values are refused at the door.** A property declares what it holds, so a sentence
cannot land in a due date and an area cannot land in a status. A property the model
does not know is a user-created field, and the engine has no opinion about those
beyond storing them — which is what the product's "seventh kind of field behind a
door in Settings" requires.

**The write API owns the merge rule.** `set` reads what is live and names those dots,
so a caller never has to remember that a register write must say what it replaced —
and `remove` names only the adds it can see, which is what makes a set add-wins.
Renaming a person is one write, verified against forty notes that reference her.

---

## Phase 6 — Snapshot parity

*~2 weeks. Where the engine earns the phone.*

The engine emits the snapshot the shell already decodes — 152 fields across 19 types.

> The same box produces a byte-identical snapshot from the engine and from `core/`.

That test is the only thing that lets 19,685 lines of Swift not change, and it is
worth more than any amount of design review.

---

## Phase 7 — The phone moves

*~2 weeks.*

`Box.swift` — 955 lines, 33 verbs, the only shell file that touches the C ABI — is
repointed at a new FFI over the engine. **The ABI is designed for 16-byte ids from
the start**, with a real error channel rather than `0` meaning failure, so none of
the 39-of-57 retrofit cost in `core-decisions.md` applies.

Plus a one-way converter for the box already on the phone, gated on parity, run once,
original kept.

Gate: parity, plus the eight launch-flag self-checks.

---

## Phase 8 — Blocks

*~3 weeks.*

Bodies become addressable blocks with ids and fractional order keys, with a Markdown
round-trip test. Without this, `core.md` decision 2 has no implementation and Phase 10
has no subject.

---

## Phase 9 — History and undo

*~2 weeks.*

Replay to a moment, versions clustered at read time, "put it back" as a forward write.
One user action is one undo step, which the phone already assumes.

---

## Phase 10 — Merge rules, and the harness that tests them

*~2 weeks. Build the harness first.*

Two boxes in one process, a scriptable partition-and-reconnect script, and a
state-digest comparison — written against a `sync_apply` that does not exist yet. Of
everything here, this removes the most risk per day spent.

Then the per-property rules, **including the five cases `core.md` §5 says have no rule
yet** — entity existence first, because two devices, one deleting and one editing, is
the most likely real conflict there is.

---

## Phase 11 — Sync

*~3 weeks.*

Per-device append-only files in a synced folder, per `core-decisions.md`: iCloud Drive
on iOS and macOS, "point at any folder" on desktop. The same format a relay would
carry, so a server later is a client swap.

**The blob store is built here or earlier.** Content-addressed photo bytes exist in
neither tree, and `FileRef` carries a device-local path that cannot cross a device
boundary. It is a real subproject, not a detail.

**No encryption in the first version**, stated in the UI rather than implied.

---

## Phase 12 — Services

*4–8 weeks, and the least certain number here.*

The 8,729 lines of `services/` move onto the engine — projections, the clerk,
recurrence, import, export, search. The read seam is ten methods, but `Store::get`
returns `&Entity` and a disk-backed store cannot, so this is an ownership rewrite
across roughly 250 sites rather than ten.

The CLI moves with it: it is the verification tool, and the house rules name it as
the way to cross-check a divergence.

---

## Running in parallel, any time — the delta channel

*~1–2 weeks. Depends on nothing here.*

The core hands the shell **6.6 MB of JSON on every read** at 10,000 entities, rebuilt
each time. One action produces a handful of ops; sending those is under a kilobyte.

Buildable today against the current core, and it pays off again on the engine.

---

## What this adds up to

| | |
|---|---|
| Phase 1 | **done** |
| Phases 2–4 | ~4 weeks. Codec, log, view, and the gate that can stop everything |
| Phases 5–7 | ~6 weeks. Model, parity, and the phone running on it |
| Phases 8–11 | ~10 weeks. Blocks, history, merge, sync |
| Phase 12 | 4–8 weeks |

**Roughly five to seven months to the phone on the engine with sync**, one developer —
and about ten weeks to the phone simply running on it, which is the milestone that
matters, because everything after it ships against a real user.

**What makes it integrable later, concretely:** one documented on-disk format that is
not a derive macro; SQLite, which the desktop already uses; no iOS anywhere in the
engine; and the FFI as a separate layer the desktop does not have to use.

**What is deliberately not planned:** anything about the desktop's current schema. When
it adopts, its `file_path` index is dead code, its `tags.name` constraint is replaced by
the add-wins set, and `source_key` becomes a vault-indexer concern. Those are notes for
whoever does it, not phases here.
