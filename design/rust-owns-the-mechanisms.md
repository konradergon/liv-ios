# Rust owns the mechanisms

> **Owner, 2026-09-13:** *"The rust side should handle all the app
> mechanisms: storage, sync, actions. in other words, everything besides
> the ui (what you don't see). […] The swift side should just implement an
> interface for the rust side (what you see). no logic."*
>
> And, removing the constraint that shaped every plan before this one:
> *"I don't use this app daily!!! it's all for testing! so nuke or change
> anything you want (except how the interface looks rn)."*

This supersedes `one-core.md` and rewrites `core-plan.md` from Phase 6 on.
The one thing it does not touch is what the app looks like.

---

## 1. Is the engine actually faster? Measured, not assumed

The owner's reading was *"the engine would be faster and more scalable
than the original core"*. Measured 2026-09-13 on this machine, release
build, same workload (a box of N notes, built both ways):

| entities | open, core → engine | one write, core → engine | snapshot (core) |
|---:|---|---|---|
| 100 | 0.50 ms → **0.27 ms** | 0.21 ms → 0.43 ms | 0.90 ms, 68 KB |
| 400 | 1.40 ms → **0.30 ms** | 0.21 ms → 0.46 ms | 2.41 ms, 229 KB |
| 1,600 | 4.67 ms → **0.32 ms** | 0.21 ms → 0.43 ms | 8.64 ms, 876 KB |
| 6,400 | 19.73 ms → **0.45 ms** | 0.20 ms → 0.54 ms | 39.01 ms, **3.5 MB** |

**Scalable: yes, and it is not close.** Opening a core box replays the
whole log — 64× the entities costs 40× the time. The engine opens a
database: 0.27 ms to 0.45 ms across the same range, essentially flat. That
gap has no ceiling; at 100,000 entities the core is reading and parsing
hundreds of milliseconds before the app can draw, and the engine is still
under a millisecond.

**Faster: not everywhere, and the exception is worth stating.** One write
costs the core ~0.2 ms and the engine ~0.5 ms. Appending a line to a file
beats a transactional database, and it always will. The engine is paying
for durability and for the view being updated in the same transaction.
Both are far under a frame; neither is a reason to choose either one.

**The real cost is neither.** It is the snapshot: 39 ms and 3.5 MB at
6,400 notes, rebuilt from scratch on every refresh, linear in the size of
the box and independent of what the screen is showing. A shell asking
"what is due today" is handed the entire box and made to search it. That
is the number §3 exists to kill.

So: the engine is the right store, for the reason the owner gave, with one
correction — it wins on **open** and on **what a read has to touch**, not
on write.

---

## 2. Furniture is a floor, not a ceiling

Phase 5 compiled the vocabulary into the binary: six kinds, six areas,
three statuses, ten properties, and *nowhere to write a seventh*. That is
why two fresh boxes agree about everything having exchanged nothing.

**It is also why the engine cannot hold the app.** Measured against a
fresh `core/` box:

- the box carries **51 property definitions** over 11 value-kinds; the
  engine knows **10 properties** over 6;
- the box's property definitions, types, options, workspaces and saved
  views are **entities** — the box describes its own schema;
- the product amended itself on 2026-08-29: **areas grow** ("a create row
  is cheaper than that trade"). The engine's six frozen areas are already
  behind the product.

**The fix keeps the argument and drops the wall.** The drift bug
`one-core.md` §4 records was never *declaring*; it was **seeding** — each
device minting its own "Work" on first launch, so two devices ended up
with two of them. Compiled-in ids fix that, and they keep fixing it for
everything Liv ships with.

A thing the user mints is different in kind: it is created **once**, on one
device, and syncs as itself. There is no second copy to disagree with.

So:

- **What Liv ships with stays compiled in** — the six areas, six kinds,
  three statuses, the six fields. Never seeded, never written, no drift.
- **What the box adds is an entity** — a user's seventh field, a seventh
  area, a status option, and every piece of backstage furniture the app
  already has (workspaces, saved views, layers, widgets, habits, pins).
- **Kinds stay ours.** The product says fields and kinds "do not grow in
  daily use"; kinds grow only when we add one, in a release.

`is_furniture` keeps its job — it answers "did this ship with the app",
which is still worth asking. It stops being the same question as "is this
allowed to exist".

---

## 3. The ABI answers questions; it does not ship the box

The current contract is one `liv_snapshot` returning every entity, every
projection and every piece of chrome as one JSON document, which the shell
decodes and then searches. At 6,400 notes that is 3.5 MB per refresh.

**The new contract is one verb per surface**, returning exactly that
surface's rows — already filtered by the workspace lens, already sorted,
already carrying the strings the row will draw:

```
liv_view_today(box, day, today, now_ms, lens, out)   the five piles, late, captured
liv_view_tasks(box, filter, id, today, lens, out)    the bands, with each one's late count
liv_view_everything(box, slice, today, lens, out)    the slice, already ordered
liv_view_day(box, day, lens, out)                    the timeline, overlap resolved
liv_search(box, query, lens, out)                    ranked hits — not built yet
```

**Built 2026-09-13**, all but search. Measured over the same 2,000-task
box: **one day is 2,268 bytes against the whole box's 448,891 — a factor
of 198**, and the ratio grows with the box rather than with the screen.

Three things are deliberately unlike the ABI above them:

1. **A real error channel.** Every verb returns `LIV_OK` or a negative
   code and delivers its answer through an out-pointer. The old ABI's `0`
   means both "no id" and "it broke", which is why a shell cannot tell an
   empty box from an unreadable one. Here an empty box is `LIV_OK` and an
   empty array.
2. **Sixteen-byte ids**, as 32 lowercase hex characters.
3. **No `with_box`.** That pattern exists because opening a core box
   replays its whole log, and it needs a five-field cache to avoid doing
   so. The engine is a database: opening is 0.3 ms and flat, SQLite locks
   itself in WAL mode, and the connection is simply held.

A box also learned to remember its own `DeviceId` (`Engine::open_local`).
A dot is `(device, seq)` with seq counted per device, so re-minting on
every open would restart that counter against history the box already
holds — every new op colliding with an old dot.

Payloads become proportional to the screen rather than to the box. The
projections run in Rust, where `cargo test` can reach them.

This also retires the "delta channel" from `core-plan.md`: it existed to
avoid re-sending 6.6 MB, and a verb that sends one screen has nothing to
diff.

---

## 4. What stays in Swift

Everything you can see, and nothing you cannot.

**Stays:** layout, colour, type, spacing, gestures, animation, navigation
state, and **locale-bound formatting** — "Tue 21 Jul" in the user's
language and calendar is a platform job, and doing it in Rust would mean
shipping ICU to say what the device already knows.

**Goes:** every projection, filter, sort, classification and product rule.

Measured today, the shell has ~100 `filter`/`sorted`/`compactMap`/`reduce`
sites across 22 view files. `Today.swift` alone has 21, and holds rules
like:

> `/// LATE = incomplete TASKS whose day has passed (owner ruling). Not`
> `/// events, not notes — a thing is late only if it can still be done.`

That is a product rule, written in a view file, reachable by no test in
the workspace and verifiable only on a simulator. It belongs in
`services/`, with a test.

`Box.swift` stays the one file that touches the C ABI (standing rule 1).
It gets smaller, not bigger: it stops decoding a snapshot and re-deriving
screens from it, and starts calling a verb per screen.

---

## 5. The order

Each stage is provable on its own, and nothing is deleted before its
replacement passes.

1. **The engine can hold a real box.** Declared properties, declared
   areas and options, the backstage kinds. Gate: *every property, type and
   entity a fresh `core/` box holds can be expressed by the engine, and
   replays.*
2. **Projections move to Rust, over the engine.** Today, Tasks,
   Everything, the day timeline, search. Each arrives with the product
   rule written as a test — including the ones that only exist in Swift
   comments today.
3. **The new FFI.** View verbs per §3, 16-byte ids from the start, a real
   error channel. Additive alongside the old ABI; nothing breaks while
   both exist.
4. **The shell moves.** `Box.swift` repointed one surface at a time; the
   logic deleted from each view file as its verb lands. The screens must
   look identical — that is the owner's one constraint, and `drive.sh` is
   how it is checked.
5. **Delete `core/`, the old FFI verbs, and the snapshot builder.** No
   feature flag, no parallel period beyond stage 4 (standing rule 7).
6. **Sync.** The engine was built for it: ops, dots, version vectors and
   the hold buffer are already there and tested.

**Byte-identical snapshot parity is no longer the gate.** It existed to
let 19,685 lines of Swift not change, and the owner has now asked for the
opposite. The gate is the screen: same pixels, fewer Swift lines, the
rules under test.
