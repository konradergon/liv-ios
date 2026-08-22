# Building the core — the phased plan

> **Status:** proposal, 2026-08-22. The design is `core.md`; this is the order.
> **Reviewed adversarially the same day**; the phase order below is the corrected
> one. The first draft had Phase 2 writing journal rows before Phase 4 created the
> identity those rows require — eleven lines apart.
>
> **The rule every phase obeys:** the Tauri app keeps working. Nothing here changes
> a command signature, removes a column, or asks the frontend to change — with one
> exception, named in Phase 6, which the design requires and this plan must own.
> Verified: nothing outside `core/src/lib.rs` in the desktop tree executes SQL, and
> no SQL text crosses the IPC boundary.
>
> **Two trees, meeting once.** The store lives in the desktop's tree. The phone stays
> on `konrad/ios`, untouched, until Phase 10. They meet at one gate: the same box
> producing a byte-identical snapshot from both cores.
>
> **Estimates are for one developer**, and several phases are explicitly unpriced
> rather than guessed at.

---

## Phase 0 — Decide, and sweep what survives regardless

*~1 week. No architecture. Blocks everything after it.*

**Three decisions, written down** (`core.md` §12).

**Five questions answered, because estimates depend on them** (`core.md` §14):
undo granularity on the desktop; repo topology; the three UNIQUE constraints;
which sync transport, and whether it is encrypted; and entity identity — the
UUIDv7 switch that §14.8 leaves unestimated. **Scope that last one here**; Phase 8
cannot exist without it.

**Write down the op encoding and its version field** before any op is written.
`core.md` promises a decoder forever; that is not promisable for a format nobody
has specified.

**And fix the two open rebuild-on-read defects**, because they live in code that
survives whichever direction this goes:

| Fix | Payoff | Status |
|---|---|---|
| `find_type` uses the existing name index | build rate flat at ~19,500/s instead of collapsing to 1,354/s — 15× at 40k | **done**, 2026-08-22 |
| `recency()` maintained on append | 99 ms → 0.0 ms per search at 500k; a search 264 → 183 ms steady state | **done**, 2026-08-22 |

Both landed failing-test-first with cost tests asserting shape, per standing rule 2.
343 tests pass.

### Phase 0 status

| Item | Status |
|---|---|
| The two defects | **done** |
| The op encoding and its version field | **drafted** — `design/op-format.md` |
| Entity identity, scoped | **done** — measured by compile probe, in `core-decisions.md` |
| The four decisions, framed to be answerable | **done** — `design/core-decisions.md` |
| The three decisions in `core.md` §12 | **waiting on the owner** |
| The five open questions | **four framed, all waiting on the owner** |

---

## Phase 1 — One write choke point

*~1 week. Desktop tree. Worth shipping even if the rest is cancelled.*

One private `Db::write` helper. All ten write methods routed through it, each in one
explicit transaction. No journal, no new table, no schema change, no signature change.

**The shape matters, because the lock is not reentrant.** `Db` holds
`conn: Mutex<Connection>` and `Connection::transaction` needs `&mut`. `reindex_vault`
already takes the lock and opens its own transaction. So `Db::write` takes the lock
once and hands a transaction to a closure, and `reindex_vault` becomes a *caller* of
the helper rather than nesting inside it. Getting this backwards is a deadlock.

**It fixes a real bug on the way.** `add_tag` (`core/src/lib.rs:574`) runs two
`INSERT`s with no transaction and can leave a tag row with no entity attached. Write
the failing test, watch it go green. **But the real reason for this phase is the
journal:** eight of the ten methods are single statements and already atomic under
SQLite's implicit transaction. Nothing can be journalled until there is one place to
journal from.

---

## Phase 2 — Write identity

*~1 week. Writes no ops, reads no ops, changes no behaviour. Must precede the journal.*

A device id generated at install and never reused. A per-device counter, persisted,
never reused. The HLC. Nothing uses them yet.

There is no cost to doing this early and it removes the plan's only self-contradiction:
a journal row cannot carry a dot that does not exist, and an op without a dot is
structurally unmergeable forever.

---

## Phase 3 — The journal

*~1.5 weeks. Desktop tree. Additive, but this is where real data starts accumulating.*

Migration `0005_journal.sql` adds `ops` and `vv`. The database is at `user_version = 4`
with a working migration runner and idempotent column checks, so this is that mechanism
doing its job.

Every write appends its ops inside the same transaction as the mutation. **One user
action is one group**, not one op per statement.

**Genesis ops, or the log is not the truth.** The migration writes one synthesis
op-group per existing row, from its current state, stamped with the device id and a
genesis HLC. Without it, replay reconstructs only what happened since Tuesday, and
Phase 4's gate proves nothing about real data.

**Every op carries explicit `created_at` / `updated_at`.** The schema defaults to
`datetime('now')` and every upsert re-stamps it, so replay would re-run those at replay
time and byte-identical becomes unachievable. This is a schema requirement of *this*
phase, not a discovery for the next one.

Ships with a cost test asserting shape — doubling the box roughly doubles one write's
work — because the journal adds work to the exact path that has no instrument today.

**Watch:** make the vault upsert a no-op when a row is unchanged, or one external
Obsidian save journals hundreds of rows.

---

## Phase 4 — Replay proves itself

*~1.5 weeks. The gate for everything after.*

> Drop the projected tables, replay `ops` from zero into an empty database, and they
> come back byte-identical.

Run it two ways: N randomised writes through the command layer, **and against a copy of
the owner's real box**. The synthetic case is the one where the test cannot fail.

**Three traps, not one.** The FTS index and `tags_text` are trigger side effects, so
replay must run through the same triggers in the same order or finish with an explicit
rebuild. Timestamps are handled by Phase 3. And `delete_entity` relies on FK cascade, so
replay must either record the cascade in ops or depend on FK ordering — decide which.

**If this cannot be made to pass, the design is wrong and everything after should stop.**

---

## Phase 5 — Entity identity

*Unestimated. Scoped in Phase 0. Phase 9 cannot exist without it.*

The switch to UUIDv7 that `core.md` §2 requires. Touches every foreign key, the FTS
`content_rowid`, and both shells' id decoding.

**`AUTOINCREMENT` is not a substitute.** It is a local-only patch: without it SQLite
assigns `max(rowid) + 1`, so deleting the newest note lets the next one take its id
back — enough on its own to make a journal name the wrong note. But two devices creating
a note offline both take the next integer and collide on first sync, and no integer
scheme fixes that. Doing `AUTOINCREMENT` alone makes the sync problem invisible until
Phase 9.

**Either way it is a full `entities` rebuild** — SQLite cannot `ALTER TABLE` into a new
id scheme, and `entities` is the `content=` backing store for the FTS5 external-content
index, the parent of two `ON DELETE CASCADE` children, and the owner of four generated
columns and five indexes. Budget the rebuild and the FTS rebuild explicitly. **This is
the only irreversible step in the first half of the plan.**

---

## Phase 6 — Cells become the truth

*4–6 weeks plus a backfill. Desktop tree. **The first phase that can break the app for
the user.***

`entity_cells` **does not exist**. This phase creates it and backfills it from every
existing `content_json`, then makes it the truth. Price the backfill migration separately
from the projection work.

The `entities` columns become a projection maintained from the cells, in the same
transaction — honouring the desktop's own rule that queryable fields are real columns,
one level down.

**And here is the wall this phase must climb.** `status`, `priority`, `due` and
`start_at` are `GENERATED ALWAYS AS (json_extract(content_json, …)) VIRTUAL`. **A
generated column cannot be written.** So the core cannot maintain them from cells. Either
`content_json` stays the truth for due and status — the two most important properties in
the whole design — or those four columns and their indexes are dropped and rebuilt, which
is a *second* full `entities` rebuild after Phase 5's. **Choose before starting; it is
most of the estimate.**

**Ships with the round-trip test:** any `content_json` in, the same `content_json` out,
including keys the core does not understand.

**Verify with the CLI**, per the house rule that a builder's own report is not evidence.

**The risk, named:** if the frontend keeps writing blobs while the core reads cells, there
is no rule for which wins. Not hypothetical — `one-core.md` records a live divergence
where the database holds 96 notes and the active vault's blob holds 1.

---

## Phase 7 — Blocks

*~3–4 weeks. Without it, decision 2 has no implementation.*

Bodies become addressable blocks with ids and fractional order keys, with a Markdown
round-trip test. The desktop stores `body TEXT`; the log core stores spans carrying block
kinds inside one value. Neither is an addressable block.

Phase 9's per-block register tests have no subject until this exists, and it carries an
editor-side dependency on both shells.

---

## Phase 8 — Undo and redo

*~2 weeks, ±weeks on Phase 0's answer. No UI binding.*

Over the journal, exposed as a new command, provable from the CLI before any pixel moves.

**The frontend change this plan owns.** The desktop has no way to learn the database
changed underneath it. Two backend events exist — `vault-changed` and `inbox-new-file` —
and both come from filesystem watchers; neither fires on a write. An undo that mutates
SQLite behind the app puts two truths on one screen, so this phase adds an event and one
listener. That is the single exception to "nothing here asks the frontend to change".

`Cmd+Z` stays bound to the OS text undo until someone asks otherwise.

---

## Phase 9 — Merge rules, and the harness that tests them

*~2 weeks. Build the harness first.*

**The harness comes before the sync it tests:** two boxes in one process, a scriptable
partition-and-reconnect script, and a state-digest comparison — written against a
`sync_apply` that does not exist yet. Of everything in this plan, this removes the most
risk per day spent.

Then the per-property merge rules from `core.md` §5 — including the **five cases §5 says
have no rule yet**, of which entity existence is the sharpest: two devices, one deleting
and one editing, is the most likely real conflict there is.

**Scenarios the harness must script:** same field on both, tag added here and removed
there, body edited on both, entity deleted on one while edited on the other, a device
offline for a month, a clock skewed by hours.

---

## Phase 10 — Sync

*Unpriced until Phase 0 names a transport.*

Version vectors, contiguous op ranges per device, blobs by hash lazily. By now the harness
proves convergence, so this is transport and scheduling.

**But "transport" is not a detail.** CloudKit, an iCloud Drive file, a server and
peer-to-peer are four different projects with four different auth stories, and `core.md`
§5's in-order guarantee is a property of whichever is chosen rather than something this
phase can assume. Encryption is unaddressed in both documents. **This phase cannot be
estimated before those answers exist.**

**The blob store is built here or earlier** — content-addressed photo and file bytes exist
in neither tree today, and `core.md` calls them what keeps replay affordable.

---

## Phase 11 — Port `services/`

*6–10 weeks, and this estimate is the least trustworthy number in the document. Where the
two trees meet.*

**8,729 lines across seventeen files** move onto the new store.

**The read seam is ten methods, not the eight a first count suggested** —
`rustfmt` wraps long chains, which hid a third of the call sites:

| Method | Call sites in `services/` |
|---|---|
| `store.get` | 59 |
| `store.entities` | 23 |
| `store.resolve` | 26 |
| `store.user_entities` | 5 |
| `store.named` | 1 |
| `recency`, `pending`, `history`, `declined`, `backlinks` | 1 each |

`named` is the index Phase 0 uses to fix `find_type`; `user_entities` carries the
system/user id split. Leaving either out breaks this phase on day one.

**Two seams the read trait does not cover, and they carry the cost.** `services` also
reaches persistence through `Session` — `store()` ×79, `allocate_id()` ×54, `commit()`
×35, `retract()` ×2 — which is the entire write path. And `Store::get` returns
`Option<&Entity>` while `entities()` returns an iterator of `&Entity`; `services` then
calls `&Entity` accessors 85+ times. **A store reading from disk cannot hand back
`&Entity`**, so this is a lifetime and ownership rewrite across roughly 250 call sites,
not ten.

**The `cli/` moves with it.** It is the verification tool, it sits on the same store, and
the house rules name it as the way to cross-check a Phase 6 divergence.

**The gate, and the only thing that lets 19,685 lines of Swift not change:**

> The same box produces a byte-identical snapshot from both cores.

**If the first implementation loads per call rather than streaming, say so out loud** —
with `store.entities` at 23 sites that reintroduces the 668 MB profile this whole redesign
exists to remove. Either those 23 become bounded queries in this phase, or the parity gate
runs at 50k with the RSS recorded.

---

## Phase 12 — The phone moves

*3–4 weeks plus a converter. Phone tree.*

`Box.swift` — 955 lines, 33 verbs, the only shell file touching the C ABI — is repointed at
the new core. The other 18,730 lines do not know which core they are on.

**A one-way converter for the existing box.** `~/Library/Application Support/liv/liv.log`
is the owner's real data; nothing else in this plan migrates it. Gated on the parity test,
run once per box, with the original kept.

Gate: parity, plus the eight launch-flag self-checks.

---

## Running in parallel, any time — the delta channel

*~1–2 weeks. Phone tree. Depends on nothing in this plan.*

**The highest value-per-week item in this document, and it is not part of the core rewrite
at all.** Measured: the core hands the shell **6.6 MB of JSON on every read** at 10,000
entities, rebuilt each time. One user action produces a handful of ops; sending those is
**under a kilobyte**.

No amount of core speed survives a 6.6 MB boundary. Buildable today against the current
core, and it pays off again on the new one.

---

## What this adds up to

| | |
|---|---|
| Phases 0–4 | ~5 weeks. Additive; Phase 3 begins accumulating data that Phase 2 must precede |
| Phase 5 | Unestimated. A full `entities` rebuild. The only irreversible step in the first half |
| Phase 6 | 4–6 weeks + backfill. The first phase that can break the app for the user |
| Phases 7–9 | ~7–8 weeks. Blocks, undo, merge rules |
| Phase 10 | Unpriced until a transport is chosen |
| Phase 11 | 6–10 weeks, and the least trustworthy number here |
| Phase 12 | 3–4 weeks + a converter |

**A total is not offered.** Three phases are unpriced by design rather than by omission,
and the eight-to-ten method miscount in the first draft is a reminder of what happens when
a number is stated before it is checked.

**What can be cut without breaking the rest:** Phase 8 (undo needs a channel that does not
exist), Phase 10 (the harness in Phase 9 is the hard part), and all of Phase 11 if the
phone stays on its own core longer than planned.

**What cannot be cut:** Phases 1–4, and Phase 5 before any sync.

**Not in this plan, deliberately:** the desktop frontend's 75 files touching `localStorage`
and `state.json`, and `objectVersions.ts` — a second history mechanism no phase retires.
Nothing above needs them to move. Until they do, "one core" is true and "one source of
truth for the whole desktop" is not. Say which is being claimed.

**Export has no phase.** P4 requires a complete export including history. It stays on the
current `services/src/export.rs` path until Phase 11, and history is not in it. That is a
gap, recorded rather than hidden.
