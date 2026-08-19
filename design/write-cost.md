# The write path is quadratic — measured 2026-08-19

> **Status:** confirmed defect, not yet fixed. Numbers measured on this Mac
> (M1) against `konrad/rewrite-mac`, through the SHIPPED C ABI — the same
> `liv_set_at` the phone calls.

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

## What to do

1. A failing cost test for the write path, asserting shape: doubling a box of
   notes-with-bodies must not much more than double one edit. This is the gap
   in standing rule 2.
2. Sweep incrementally — the entity that changed, not the box.
3. Re-measure. Do not assume "assist off" numbers are the post-fix numbers:
   with assist off `sweep` returns on its first line, which is not what an
   incremental sweep does. It still has to build a gazetteer and bucket for
   duplicates unless those are made incremental too.

## What this does NOT say

It says nothing about whether the append-only log is the right data model.
Filtering in this core is healthy — about 4 ms at 50,000 entities. This is one
service running on the wrong schedule, and it is days of work, not a rewrite.
