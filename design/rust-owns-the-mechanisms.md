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

## 3a. An id is never a name

> **Owner, 2026-09-13:** *"LivID shouldn't be read by the user. something
> ive forgotten to say clearly. Unnamed task/event/note should get a
> sensible name."*

Two sentences, one rule, and it was broken in **fifteen places**.

`views::summary`, `content::source_name`, `tasks::name_of` and eleven
siblings all ended the same way: `format!("#{}", id)`. That string is a
NAME — it became the snapshot's `title`, a reference chip, a search
result, the `title:` front-matter of an exported file, the workspace
switcher, the outbox ledger. The shell mapped it away on exactly one
surface (lists) and showed it on the rest.

**A made name, not a number.** The kind's word and when: `Task · 13 Sep
14:32`. This amends the 2026-09-06 ruling that a nameless row says what it
IS — "Task", "Note" — which was right and not enough: fourteen rows
reading "Task" distinguish each other no better than fourteen reading
"Untitled", and the harness had already tripped over exactly that, unable
to aim at one of three notes sharing a label.

**The words are Rust's**, including the month abbreviations. A shell
carrying its own copy of the app's vocabulary is the mistake
`one-core.md` §4 records, and a made name is vocabulary. This is the one
place `§4`'s "locale formatting stays in Swift" does not reach: a date the
user reads AS a date is the shell's, a name is not.

**And the core says whether a name was made.** `untitled` rides the
snapshot now. The shell had inferred it from the string twice and been
wrong twice — once comparing against `"untitled"` in lower case, which
never matched, and once against `"#<id>"`, which the core has now stopped
sending. A fact about a thing is not recoverable from how it reads.

One case survives, and it self-heals: a bare `[[4155]]` already written
into a note's text still renders its digits, because the editor only hides
the id when the token carries a name. Every token is rewritten with a name
on the next save of that note, now that the resolver can always find one.

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

   **It is gated on the id type, and that was not foreseen.** An engine id
   is 16 bytes; `EntityRow.id` is a `UInt64`, and `UInt64` appears **236
   times across 22 Swift files**. A repointed surface hands the navigation
   chain — `desk.open`, `box.entity`, the editor, the tab plane — ids it
   cannot use, so "one surface at a time" is not available: the type moves
   first, or nothing does.

   That is a mechanical refactor and a large one, and it wants a compiler.
   So stage 4 landed in two pieces:

   * **4a, done and PROVEN ON A DEVICE, 2026-09-13:** the converter
     (§below), the plumbing in `Box.swift` (the wire types, the verbs,
     `Civil.epochDay`), and **one card in Settings** that converts the box
     and reads Today out of the engine.

     On the owner's simulator, iPhone 17 Pro / iOS 26.5: *25 converted,
     74 resolved onto built-in, 3 minted, 2 things on the day.* So the
     whole chain runs — Rust, bundled SQLite linked into the staticlib,
     the new ABI, a Swift decode, pixels — and `build.sh` needed no link
     flag for SQLite, as predicted from the Linux archive's undefined
     symbols. The refactor below is now a refactor, not a gamble.
   * **4b, in slices** (owner: *"do it in slices"*), each one building
     before the next:
     1. `LivID` exists, used on the engine path only.
     2. **Name the ids.** 225 sites said `UInt64`; about fourteen of them
        meant a content fingerprint, the log's seq, a recency key or a
        wall clock. A pure rename onto an alias, so it compiles by
        construction — and the distinction is worth having whatever
        happens next.
     3. **Name the written form.** THE ID IS NOT INTERNAL, and nothing in
        the tree said so. It leaves memory in NINE places a compiler
        cannot see, each a string interpolation that stays valid whatever
        the format becomes: the editor's `[[123]]` token **inside a
        note's own text**; a `related` cell's `#123` **inside the box**;
        five `UserDefaults` keys holding every saved plane; the outbox
        ledger's JSON keys; a shared note's filename. One function now,
        not twenty interpolations.
     4. **Flip the alias**, so `LivEntityID` IS sixteen bytes in all 22
        files, and answer what the compiler then asks. `LivID` grows a
        transitional `core` half — `init(core:)`, `.core`, an integer
        literal, and a decoder that takes a JSON number as well as hex —
        so every `liv_*_at` verb and the snapshot still take it; all of
        it has slice 5 as its deletion date (standing rule 7). The
        `UInt64` → `LivID` conversion happens in ONE place, `actId`.

        This is where the rename pays: slice 2 had renamed two things
        wrongly, both onto the word rather than the meaning, and both
        would have been silent before the flip. `setContent`'s `base` is
        a content fingerprint for a compare-and-swap, and History's
        `restoring`/`refused` hold the LOG'S SEQ. Slice 4 also found a
        SIXTH written form that slice 3 missed — the active workspace is
        a `UserDefaults` integer VALUE, not a key — and `UserDefaults`
        returns 0 for a missing key, a key holding a string and a key
        holding an unreadable number alike, so a format change there
        would have read as "you are on All", not as a fault.

        And the flip found FOUR MORE WRITTEN FORMS, all the same shape:
        slice 3 had moved a `LivIDText.read` and left its writing half
        raw, in a different function. The plane's tab token, the outbox
        ledger's keys, the desk's live-document integer — and a
        scheduled reminder's notification identifier, which is the one
        that matters. That last one COMPILED, as hex, against a tap
        handler that parses it with `LivIDText.read`: every reminder
        would have opened nothing, with no error, no warning and no
        test. It was found only because the `userInfo` line two rows
        above it happened not to build.

        So `LivID` is **not** `CustomStringConvertible`. `\`\\(id)\`` is a
        compile error now, and the only ways to write an id down are
        `LivIDText.written` and `.hex`. Standing rule 3 — the prose
        saying this had been at the top of `LivID.swift` since slice 3,
        and prose is what let four sites through.

        One more thing changed shape on evidence: the sentinel for "no
        id" is `.absent`, not `.none`, because `Optional` already has a
        `.none` and `entity ?? .none` would have resolved to that one.
     5. Swap the data source. **This is two, not one**, and the reason
        is that reads and writes have to hit the same box: if Today reads
        from the engine while ticking a task writes to `core/`, the
        engine box is stale the moment anything happens. So "one surface
        at a time" is not available for the swap either — every write
        path moves first, or none does.

        * **5a, the write ABI.** The engine has the primitives
          (`create`/`set`/`add`/`remove`/`trash`/`restore`/`declare`) and
          no FFI verb reaches any of them. Gaps, measured 2026-09-13:
          **undo** (`Group.reverses` had been in the op format since
          Phase 2 with nothing writing it — **done**,
          `engine/src/undo.rs`); **content, with its history and its
          backlinks** (done); **`rename_value`** (done); **files** (done
          — and the converter stopped dropping them); **the clerk's
          queue** (done). What is left is the clerk's SWEEP — six
          proposers reading the words, ~800 lines in `services/` against
          `core::Store` — and **query/lex/search**, which is the
          grammar.
        * **5b, the swap.** `Box.swift` stops decoding a snapshot, the
          core box is converted once and becomes history, and `LivID`'s
          `core` half goes with it.

        Undo landed without a stack. `core/` keeps two `Vec<u64>` in
        memory and rebuilds them by scanning the whole log at open, which
        is the one property the engine was chosen for. Here the answer is
        a backward walk over this device's groups that stops at the first
        one still in effect — one row read in a box nobody has undone in,
        and bounded by the undo depth rather than the box. Three cost
        tests hold that shape (`engine/tests/scale.rs`); made eager on
        purpose, all three fail at 7.5x.

        **Content is a value kind, not JSON in a text cell.**
        `Value::Rich(Vec<Span>)`, hand-encoded like the rest of the
        format: a serde document nested inside it would be the
        derive-drift defect of `op-format.md` §1 one layer down and out
        of sight, and the fold could not see the refs a body carries.
        The converter stopped flattening bodies to markdown in the same
        change — with blocks that is a downgrade, not a conversion, and
        it turned a link into its target's name in brackets.

        The save is `core/`'s contract exactly, compare-and-swap on a
        fingerprint with no force flag, because the shell already speaks
        it. The fingerprint is FNV over this crate's own encoding rather
        than over the text: two documents differing only in their marks
        would otherwise fingerprint alike, and a save that dropped every
        bold would pass the guard.

        **A path is where, a hash is what.** `core/`'s `FileRef` carries
        both in one value in the log, which `core.md` §14 already calls a
        model bug: a path does not survive a device boundary, so a file
        synced from a laptop arrives on a phone pointing at nothing and
        looking valid. They are two things here — the hash travels, the
        path is a device-local row that is not in the log, not dropped by
        replay, and not in the digest. The converter stopped dropping
        files in the same change, because there is finally somewhere to
        put each half.

        **The clerk's queue is not the clerk.** The sweep is a pure
        function of the box, so a pending draft is recomputed rather than
        stored — what persists is the REFUSAL, because declining is not
        forgetting. One open question is recorded rather than answered:
        a refusal is device-local, as it is in `core/`, so declining on
        the laptop does not stop the phone asking. Making it travel would
        put "the user said no" in the log, which is arguably where it
        belongs, and that is the owner's call.

        It also has a rule `core/` never needed: **undo is what you did
        on this device.** One history made the question moot; a box
        holding both ends of a sync would otherwise let either end take
        back the other's last write.
5. **Delete `core/`, the old FFI verbs, and the snapshot builder.** No
   feature flag, no parallel period beyond stage 4 (standing rule 7).
6. **Sync.** The engine was built for it: ops, dots, version vectors and
   the hold buffer are already there and tested.

**Byte-identical snapshot parity is no longer the gate.** It existed to
let 19,685 lines of Swift not change, and the owner has now asked for the
opposite. The gate is the screen: same pixels, fewer Swift lines, the
rules under test.
