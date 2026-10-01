# The write path was quadratic — measured and fixed, 2026-08-19

> **Status:** FIXED. Numbers measured on this Mac (M1) against
> `konrad/rewrite-mac`, through the SHIPPED C ABI — the same `liv_set_at`
> the phone calls.

## What was measured

One ordinary property edit (`liv_set_at`, best of five) on boxes of notes that
each carry a **body**, which is what a real note has.

| notes with bodies | one `liv_set_at` |
|---|---|
| 500 | 39.7 ms |
| 1,000 | 152.5 ms |
| 2,000 | did not finish inside 10 minutes |

**3.8x the cost for 2x the box.** Quadratic. Extrapolated: ~600 ms at 2,000,
several seconds by 8,000.

## The control

The identical harness against notes with **no body** is flat:

| empty notes | one `liv_set_at` |
|---|---|
| 500 | 4.9 ms |
| 1,000 | 4.8 ms |
| 2,000 | 5.0 ms |
| 4,000 | 6.5 ms |
| 8,000 | 8.6 ms |

Same verb, same sizes, same machine. The only difference is whether entities
have content — and content is exactly what gates the clerk's proposers
(`services/src/clerk.rs`). That is the attribution.

## Why it happens

`ffi/src/lib.rs` `with_box` calls `checkin`, and `checkin` runs
`clerk::sweep` over the WHOLE BOX on every `Committed::Wrote`. The sweep
builds a gazetteer with a full pass over every named entity, then runs the
proposers over every entity that has content. So each write costs
O(entities-with-content x named-entities).

`Session::commit` underneath is flat — ~3 ms, an fsync. **The data model is
not the problem.** The core's own write is fine; the sweep on top of it is not.

## Why nobody noticed

- Assist is **on by default** on every fresh box (`services/src/lib.rs`
  `seed_assist` writes `Value::Bool(true)`), so every real user pays it.
- The real box on the phone has ~104 entities, where this is a few
  milliseconds.
- `services/tests/scale.rs` measures the file projection, name lookup and
  links — all READ paths. **No cost test covers a write.** The one rule that
  exists to catch exactly this class of bug does not point at it.

## The actual cause, after two wrong guesses

Worth recording, because both wrong guesses were plausible and one of them
came with a confident number attached.

**Wrong guess 1: "the sweep should not run on every write."** It should not,
but that is not what cost the time — moving it to the read path would have
bought nothing, because the shell reads a snapshot after every write anyway.

**Wrong guess 2: "`Session::propose` fsyncs per proposal."** It does —
`propose` rewrites the entire pending-queue file and fsyncs on every call, and
`checkin` called it once per proposal. That is genuinely wasteful and is now
batched (`Session::propose_all`). But fixing it moved the measured number by
nothing at all: 39.7 → 39.1 ms. Recorded so nobody re-derives the theory.

**The real cause** was one loop in `propose_mentions` (`services/src/clerk.rs`).
For every entity with content it walked EVERY named entity in the box, and
called `name.to_lowercase()` — an allocation — inside that inner loop, then
scanned the whole text for it. N entities x N names x a scan of the text.

## The fix

A word index, built once per sweep. `contains_word` demands a non-alphanumeric
boundary on both sides of a match, so a name can only appear in a text that
contains the name's FIRST WORD as a whole word. That makes a first-word lookup
a safe prefilter: it can never hide a match. Each entity now looks up only the
names its own words could possibly reach, instead of walking all of them.

Names are also lowercased ONCE per sweep instead of once per entity per name.

Order is preserved exactly. Candidate indices go into a `BTreeSet` and are
walked in gazetteer order, which is id order — so the proposals come out in the
same sequence as the old whole-gazetteer loop. That matters as much as the
speed: the inbox is re-derived by every process, and "accept 2" must mean the
proposal the user just read.

| notes with bodies | sweep before | sweep after |
|---|---|---|
| 250 | 8.9 ms | 0.6 ms |
| 500 | 35.4 ms | 1.2 ms |
| 1,000 | 141.7 ms | 2.2 ms |

Quadratic to linear, and 64x faster at 1,000. Same proposal count at every
size, and all 42 test binaries green.

End to end, one `liv_set_at`:

| notes with bodies | before | after |
|---|---|---|
| 500 | 39.7 ms | 8.0 ms |
| 1,000 | 152.5 ms | 7.9 ms |
| 2,000 | did not finish in 10 min | 11.8 ms |
| 4,000 | — | 17.0 ms |
| 8,000 | — | 15.6 ms |

## Guarded by

- `ffi/src/tests.rs` `one_write_stays_flat_as_the_box_grows` — the write-path
  cost test standing rule 2 was missing. It failed at 3.06x before the fix.
- `services/tests/scale.rs` `the_clerk_sweep_stays_flat_as_the_box_grows` —
  the sweep's own shape.

## The two loops that were missed (2026-08-20)

The fix above batched `checkin`. There were two more copies of the same
per-proposal loop, and they were worse, because they sit on the COLD path
where nothing is cached:

- `ffi/src/lib.rs` — the open path. Every proposal, a whole-file rewrite
  and an fsync. Measured 27.2 s for a 4,000-note box against 6.5 ms
  batched; the first `liv_snapshot` on such a box took 25.2 s.
- `cli/src/main.rs`, twice. The CLI has no cache, so EVERY invocation is
  a cold open and paid the whole loop.

All three now use `Session::propose_all`. Verified end to end through the
real CLI on a 2,000-note box: **a cold open went from ~11.8 s to 26 ms.**

This is also why `propose_all` looked useless when it landed: it was
measured on a WARM write, where the queue was already full and the sweep
returned almost nothing new. The cost was always on the cold path.

## Still open

**The sweep's closing filter is still superlinear.** Every fresh proposal
is compared by full command equality against everything pending and
everything ever declined. Measured 2.27x per doubling at 1,000 -> 2,000
notes, and 16.79 ms at 4,000 — real, but not yet worth fixing. It is
guarded by `the_sweep_stays_flat_when_the_queue_is_full`, which had to
prime the queue to see it at all; the earlier tests build boxes with an
empty queue and are blind to it. Note `declined` is append-only and never
pruned, so this term grows with the box's whole history, not its size.
The designed fix is to bucket pending and declined by (command count,
first command's entity) — equal command vectors necessarily agree on
both, so the key cannot hide a match.

The sweep still runs over the whole box on every write. It is now cheap enough
that this does not hurt (15.6 ms at 8,000 notes), but it is still O(box) per
write, and `propose_dedupe` remains quadratic *within a bucket* of
identically-named entities — 400 same-named notes were observed earlier to
produce ~400 merge proposals. Neither is urgent; both are worth a cost test
before they matter.

## What this does NOT say

It says nothing about whether the append-only log is the right data model.
Filtering in this core is healthy — about 4 ms at 50,000 entities. This is one
service running on the wrong schedule, and it is days of work, not a rewrite.
