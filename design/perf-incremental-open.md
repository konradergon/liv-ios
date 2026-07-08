# Perf: Incremental Open — cache the materialized `Store` per box, reuse it when the append-only log has not grown, and stop replaying all of history on every tab switch

Cutting against the shipped tree (`ffi/src/lib.rs`, `core/src/persist.rs`,
`core/src/store.rs`, `services/src/{lib,clerk}.rs`). **Every FFI call — every
mutation, every snapshot, every save, every tab switch — calls `open_swept`,
which calls `Session::open`, which `read_to_end`s the entire log, `parse()`s
every line, and `Store::replay`s every transaction from scratch, then runs
`seed_if_fresh` + `clerk::sweep`.** That is O(history) per interaction, and it
grows without bound. It is the tab-lag root cause. **The fix is to cache the
materialized `Store` per box path and reuse it when the log has not changed.**
The log is append-only, so **equal file length == no bytes changed since we
cached**; on that fast path we skip `read_to_end`/`parse`/`replay` entirely and
serve the cached store. We still open + `try_lock` the file every call, so
single-writer coexistence is untouched. Only when the length differs (first
open, or an external CLI append) do we pay the full read. **No on-disk format
change, no core model change, no new command variant.** One new module in the
FFI crate, one wrapper the 20 call sites route through, and a handful of
correctness guards the append-only log makes cheap.

## 1 · The load-bearing decisions

1. **The cache lives in the FFI crate, not the core.** The core stays pure —
   `Session`/`Store` know nothing about a process-global cache, exactly as they
   know nothing about the C boundary. The cache is a concern of *the seam that
   opens the box a thousand times a session*, so it lives beside `open_swept`
   in `ffi/src/lib.rs` (or a small `ffi/src/cache.rs`). This keeps the core's
   "the store is the log's consequence" invariant intact and keeps the cache a
   detachable optimization: delete the module and every call still opens the
   slow way.

2. **File length is the whole cache validator, because the log is append-only.**
   `Session::open` only ever *appends* to the log (and truncates a torn tail,
   handled below); it never rewrites earlier bytes. So a `stat` that returns the
   same byte length we recorded when we cached is a proof that no committed
   record changed. This is the one cheap, correct freshness check the format
   hands us for free — no hashing, no mtime races, no content compare. Length
   differs ⇒ something appended (or a tail was repaired) ⇒ full re-open.

3. **On a cache hit we do NOT delta-replay for v1 — a length change is a full
   re-open.** Delta-replay (parse only the bytes past `cached_len`, `apply` the
   new transactions onto the cached store) is a real future win for the
   external-CLI-append case, but it needs a public single-transaction apply the
   core does not expose today (`Store::replay` is the only entry; `apply` is
   private, `store.rs:396`). For v1, **any length change triggers the existing
   full `Session::open`.** The common case — the UI is the only writer — is a
   pure cache hit and never re-reads at all; the rare case — an external `lotus`
   CLI appended — pays one full re-read and self-heals. Defer delta-replay
   (§6) until a measurement says the CLI-append path hurts.

4. **`seed_if_fresh` and `clerk::sweep` run on a full open, never on a cache
   hit — and that is correct, not merely cheaper.** Both are **pure functions
   of the store**: `seed_if_fresh` is idempotent (every `seed_*` guards on the
   existence of what it would create — `lib.rs:78,113,151`, etc.), and
   `clerk::sweep` is deterministic in the store alone (its `_today` parameter is
   deliberately unused since the anchor fix, `clerk.rs:38-42`). A cache hit
   means *the store is byte-for-byte what we last swept*. Re-running sweep on it
   would re-derive the identical proposals, which the pending/declined dedup
   (`clerk.rs:83-90`) would then drop as already-queued. So skipping sweep on a
   cache hit changes nothing the user sees — the proposal a new note earned was
   enqueued on the open that *created* it (that open grew the log, so it was a
   full open that swept). **The gate is "did this open re-read the log," not
   "did the calendar day change."** This is simpler and strictly more correct
   than a civil-day gate: a same-day new note still gets its proposal, because
   the open that wrote the note was a full open.

   > Note on the adversarial "same-day new note" risk: it only bites a design
   > that gates sweep on the *clock* while serving a *stale* store. We gate on
   > "the store changed" instead. Every op that changes the store grows the log,
   > forces a full open on the *next* call, and that open sweeps. There is no
   > window where a store with a new note is served without having been swept.

5. **The cache holds the whole `Session`'s store, captured after the op, not a
   separately-tracked delta.** `Session::commit` applies to the in-memory store
   *first* (`store.rs:347-377`) and only then appends to disk (`persist.rs:271-272`),
   so the post-op store already reflects the mutation. We snapshot *that* store
   into the cache together with the *new* file length (re-`stat` after the
   append). `next_id`, redirects, undo/redo cursors and backlinks all ride along
   in the `Store` for free — they are exactly what a fresh replay would rebuild.

## 2 · The cache — shape, home, thread-safety

### 2.1 Where it lives and its type

A process-global, lazily-initialized map from box path to a cached entry,
behind a `Mutex`. `Store` is `Send` (only `HashMap`/`Vec`/`u64` primitives and
serde-derived value types — no `Rc`/`RefCell`/raw pointers), so a
`Mutex<HashMap<…>>` is sound across whatever threads the shell's `DispatchQueue`
runs FFI calls on.

```rust
// ffi/src/cache.rs (or a module block in lib.rs)
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;
use std::sync::OnceLock;

struct Cached {
    store: lotus_core::Store,
    /// The log's byte length at the moment we cached this store. Append-only
    /// ⇒ equal length on the next open proves no committed record changed.
    log_len: u64,
    /// Combined length of the two sidecars (.declined + .pending) at cache
    /// time. They are rewritten out of band (reject appends .declined;
    /// accept/propose/retract rewrite .pending), so the main-log length alone
    /// does not witness a sidecar change. Guard 2 in §4.
    sidecar_len: u64,
    /// Unix inode of the log at cache time. If the file was replaced (deleted
    /// and recreated at the same path with a coincidentally equal length),
    /// the inode differs and we refuse the fast path. Guard 3 in §4.
    inode: u64,
}

static CACHE: OnceLock<Mutex<HashMap<PathBuf, Cached>>> = OnceLock::new();

fn cache() -> &'static Mutex<HashMap<PathBuf, Cached>> {
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}
```

### 2.2 The entry shape — what we store and why

| field | why it is in the key/entry |
| --- | --- |
| `store: Store` | the materialized state we serve on a hit — the whole point |
| `log_len: u64` | the freshness validator (append-only ⇒ equal length == unchanged) |
| `sidecar_len: u64` | `.declined` + `.pending` are written off the main log; a length change there must also invalidate (Guard 2) |
| `inode: u64` | detects a same-length file *replacement* at the same path (Guard 3); on macOS from `MetadataExt::st_ino` |
| the `PathBuf` key | canonicalized once so `./box` and `/abs/box` don't split the entry |

**No `mtime`** — length + inode already witness every case we care about, and
mtime is a coarser, spoofable signal. **No stored `last_swept_day`** — §1.4
retires day-gating; sweep/seed are tied to full-open, which the cache already
tracks by construction. **No explicit `poisoned` flag in the entry** — a poison
is handled by *deleting* the entry (Guard 4), which is simpler than a flag: a
missing entry forces a full open, and a full open is the honest recovery.

### 2.3 Thread-safety

One `Mutex` guards the whole map. Contention is a non-issue: entries are held
only long enough to clone/take the store on a hit or insert on a miss, and the
box lock (`try_lock` on the file) already serializes real writers. The `Store`
we hand out of the cache on a hit is **moved out (taken), used for the call, and
moved back on success** — so a single box is never aliased across two concurrent
calls, and the file lock guarantees only one call holds a given box at a time
anyway. (Alternative: clone the store on hit and leave the cached copy in place;
taking-and-returning avoids the clone on the hot path and is preferred.)

## 3 · The open path — precise pseudocode

`open_swept` becomes the one place that consults the cache. Everything else in
the FFI keeps calling `open_swept` (or the `with_box` wrapper of §3.3) and is
unaware the cache exists.

```
fn open_box(path):                      // the new core of open_swept
    lockfile = OpenOptions{read, append, create}.open(path)     // ALWAYS
    match lockfile.try_lock():                                  // ALWAYS (Guard 5)
        WouldBlock -> return Locked      // never serve cache while a writer holds it
        Error(e)   -> return Io(e)
        Ok         -> continue

    meta      = stat(lockfile)           // len + inode from the SAME handle we locked
    cur_len   = meta.len
    cur_inode = meta.inode
    side_len  = stat_len(path.declined) + stat_len(path.pending)   // 0 if absent

    guard = cache().lock()
    hit = guard.get(path)
    if hit and hit.log_len == cur_len
           and hit.sidecar_len == side_len          // Guard 2
           and hit.inode == cur_inode:              // Guard 3
        store = guard.remove(path).store            // take it; return on success
        drop(guard)
        return FastSession{ store, log: lockfile, path, cur_len, dirty: false }
    drop(guard)

    // ---- slow path: the existing Session::open body ----
    session = Session::open_on(lockfile)     // read_to_end, parse (repairs torn
                                             // tail -> may LOWER len), replay,
                                             // reload .declined + .pending sidecars
    seed_if_fresh(session)                   // idempotent; only here, never on a hit (§1.4)
    for p in clerk::sweep(session.store()):  // deterministic; only here
        session.propose(p)                   // may rewrite .pending (grows side_len)

    // Re-stat AFTER torn-tail repair + seed/sweep may have written:
    final_len  = stat_len(path)
    final_side = stat_len(path.declined) + stat_len(path.pending)
    return FullSession{ session, path, final_len, final_side, cur_inode }
```

Two things the pseudocode makes explicit and load-bearing:

- **We `try_lock` on every path** (Guard 5). The fast path is *not* "skip the
  file entirely"; it is "skip the *parse/replay*." We still open and lock the
  file so a CLI holding the box makes us return `Locked`, never a stale snapshot.
- **We re-`stat` after the slow path**, because `parse()` may `set_len` down to
  drop a torn tail (`persist.rs:160-163`), and `seed_if_fresh`/`sweep` may append
  a seed transaction or rewrite `.pending`. Caching the *pre*-write length would
  make the very next open see a mismatch and needlessly re-read — or worse, cache
  a length the file no longer has.

### 3.1 Updating the cache after each op

The cache must be written back **only after the op's disk write succeeded**, and
**must be dropped if it failed** (Guard 4). Concretely, at the end of every FFI
call, once the `Session` is about to be dropped:

```
fn checkin(path, outcome):
    match outcome:
        Ok(session):                     // the op (or read) completed cleanly
            new_len  = stat_len(path)             // AFTER any append this call made
            new_side = stat_len(path.declined) + stat_len(path.pending)
            new_inode = stat_inode(path)
            cache().lock().insert(path, Cached{
                store: session.into_store(), log_len: new_len,
                sidecar_len: new_side, inode: new_inode,
            })
        Poisoned | WriteFailed:          // persist_last returned Io/Poisoned
            cache().lock().remove(path)          // Guard 4: never cache a phantom write
        Locked | Corrupt | Io(read):     // we never got a session; leave cache as-is
            ()
    // the file lock releases when `session` (and its FileLog handle) drops here
```

A read-only call (`snapshot`, `search`, `content`, `history`, `extracted_text`)
that hit the cache **can skip the write-back** — the store is unchanged, and its
`(len, side, inode)` still match — but writing it back is harmless and keeps the
logic uniform. A read-only call that took the *slow* path (first open) must write
back so the next call hits.

## 4 · The correctness guards (each an explicit rule)

Every guard below turns one adversarial failure mode into a checked condition.
None of them costs more than a `stat` on the hot path.

**Guard 1 — Torn-tail repair lowers the length; cache the repaired length, on a
full open only.** When `parse()` finds a torn final record it truncates the file
to `good_len` (`persist.rs:160-163`), *lowering* the length below what a previous
process may have cached. **Rule:** the torn-tail path is only reachable on a
*slow* open (we only `parse` on a miss), and we cache the **post-repair**
`stat_len`. So the entry always reflects the file as it is *after* repair; a
subsequent open sees the repaired length and hits cleanly. We never fast-path a
file we have not just parsed, so a torn tail can never be silently served.

**Guard 2 — Sidecar writes invalidate even when the log length is unchanged.**
`reject` appends to `.declined`; `accept`/`propose`/`retract` rewrite `.pending`
(`persist.rs:322-341, 236-257`). An external CLI can decline a proposal without
touching the main log. **Rule:** the entry stores `sidecar_len = len(.declined) +
len(.pending)`; the fast path requires `sidecar_len` to match too. A sidecar
change ⇒ mismatch ⇒ full open, which reloads both sidecars (`persist.rs:174-223`).
(A combined length can in principle mask a compensating +N/−N across the two
files; if that is ever a real concern, store the two lengths separately. For v1
the combined length is sufficient — the CLI never edits both sidecars in one
breath.)

**Guard 3 — Same-length file replacement is caught by inode.** A box deleted and
recreated at the same path with a coincidentally equal length would otherwise hit
a stale entry. **Rule:** the entry stores the log's `inode`; the fast path
requires it to match. A replaced file has a new inode ⇒ mismatch ⇒ full open.
(macOS/Unix: `std::os::unix::fs::MetadataExt::ino`.) Two *different* boxes never
collide because the map is keyed by canonicalized path, but inode additionally
defends the same path across a replace.

**Guard 4 — A poisoned / failed write invalidates the entry, mandatorily.**
`persist_last` sets `healthy = false` and returns on `append` failure
(`persist.rs:361-371`): the in-memory store is one transaction ahead of disk. If
we cached *that* store, a later call would serve a write that never hit disk — and
its burned `next_id` would diverge from what a real replay yields. **Rule:** any
op whose commit returns `PersistError::Poisoned` or an `Io` write error
**removes** the path's cache entry (§3.1). The next call takes the slow path,
replays only what actually reached disk, and re-derives `next_id` from the logged
`Create`s (`store.rs:402-404`). Poison heals by forgetting the cache.

**Guard 5 — The file lock is checked on every open, fast path included.** The
fast path skips `parse`, never the `open` + `try_lock`. **Rule:** we `try_lock`
the file *before* consulting the cache, and return `Locked` on `WouldBlock`
without serving anything. A CLI mid-append holds the lock ⇒ the shell gets
`Locked` (which it already retries), never a stale snapshot. The lock rides the
file handle for the call and releases when the `Session`/`FileLog` drops — exactly
as today.

**Guard 6 — `allocate_id` monotonicity survives caching.** `allocate_id` bumps
`next_id` in memory and logs nothing (`store.rs:111-114`, `persist.rs:346-348`);
a burned id that is never committed is fine (ids never reuse). The danger is
caching a store whose `next_id` advanced past what the *log* would replay to.
**Rule (two parts):** (a) We only ever cache the store *after* an op returns —
and every mutating FFI call that allocates an id does so as part of a `commit`
that logs the `Create` using it (`create_note`/`create_task`/`create_list`/
`create_workspace`/`add_file` all `allocate_id()` then `commit`). So a cached
`next_id` is always backed by a logged `Create` — a full replay would reach the
same `next_id` (`apply` bumps `next_id` past any `Create` id, `store.rs:402-404`).
(b) If a commit *fails* after `allocate_id`, Guard 4 removes the entry, so the
burned-but-unlogged id never persists in the cache. The one path that allocates
without committing is a caller that allocates and then errors before `commit`;
that path returns failure, and a failed mutating call should be treated like
Guard 4 (drop the entry) to be safe. **Simplest correct stance: on any mutating
call that did not return success, remove the cache entry.** Reads never allocate.

**Guard 7 — Canonicalize the key.** Two spellings of the same path
(`box.log` vs `/abs/box.log`) must share one entry, or a mutation through one
spelling leaves a stale entry under the other. **Rule:** the map key is the
canonicalized path (`std::fs::canonicalize`, or at minimum the absolute path the
shell always passes). The shell passes one canonical path today, so this is
cheap insurance.

## 5 · The API shape — `with_box(path, closure)`, the smallest correct diff

Three shapes were on the table: a `Drop`-guard proxy, a `with_box(path, |s| …)`
wrapper, and explicit check-in at every `return`. **Choose `with_box`.** It is
one semantic edit per call site, needs no new guard type or `Deref` proxying, and
routes *every* exit through one check-in point — which is exactly where Guards 4
and 6 must fire. Explicit check-in is rejected (each function has multiple early
returns — easy to miss one and leak a stale entry); the `Drop`-guard is rejected
(it must proxy `&mut Session` everywhere and cannot see the op's success/failure
to drive Guard 4 without extra plumbing).

### 5.1 The wrapper

```rust
/// Open the box (cache-fast when the log is unchanged), run `f` against the
/// session, and check the result back into the cache — dropping the entry if
/// the op failed to persist (Guards 4/6). Returns f's value, or `busy` when
/// the box could not be opened/locked.
unsafe fn with_box<T>(
    path: *const c_char,
    busy: T,
    f: impl FnOnce(&mut Session) -> (T, Committed),
) -> T {
    let Some(path) = c_path(path) else { return busy };
    let mut opened = match open_box(&path) {
        Ok(o) => o,
        Err(_) => return busy,          // Locked / Corrupt / Io -> caller's fail value
    };
    let (value, committed) = f(opened.session());
    checkin(&path, opened, committed);  // §3.1: cache-back on Ok, evict on failure
    value
}
```

`Committed` is a tiny signal (`enum Committed { Ok, Failed }`, or just a `bool`)
the closure returns alongside its value so `checkin` knows whether to cache the
store or evict the entry. For a read-only call the closure returns
`Committed::Ok` unconditionally.

### 5.2 How a typical FFI function changes

A mutating call today:

```rust
pub unsafe extern "C" fn lotus_set_at(path, id, property, value) -> i32 {
    // …CStr guards…
    let Some(mut session) = open_swept(path) else { return 0; };
    lotus_services::content::set_property(&mut session, id, property, value).is_ok() as i32
}
```

becomes:

```rust
pub unsafe extern "C" fn lotus_set_at(path, id, property, value) -> i32 {
    // …CStr guards unchanged…
    with_box(path, 0, |session| {
        let ok = content::set_property(session, id, property, value).is_ok();
        (ok as i32, if ok { Committed::Ok } else { Committed::Failed })
    })
}
```

The `&mut Session` the services want is exactly what the closure receives — no
signature change to any `lotus_services::*` function. The early `return 0` on a
busy box is now `with_box`'s `busy` argument. The body moves verbatim into the
closure; the only new code is the `Committed` tag on the return.

A read-only call:

```rust
pub unsafe extern "C" fn lotus_snapshot(path) -> *mut c_char {
    with_box(path, std::ptr::null_mut(), |session| {
        let snapshot = build_snapshot(session.store());
        // (serialize inside the closure so the box lock is still held; the
        //  string is what we return, so no borrow of session escapes)
        let out = serialize_or_null(&snapshot);
        (out, Committed::Ok)          // a read never fails the write-back
    })
}
```

Note the snapshot's `drop(session)` "release before handing JSON over" comment
is subsumed: the lock releases inside `checkin` after the closure returns the
already-serialized string. If holding the lock across serialization is ever
measured to matter, `with_box` can serialize after check-in — but the string is
built from the store, not the live session, so it is a pure ordering choice.

### 5.3 Scope of the churn

20 call sites, each a mechanical move-body-into-closure. The three `triage`
helpers share one private `triage` fn, so that is one edit, not three. No
service, no core, no `.h`, no Swift change — the C ABI is byte-identical.

## 6 · Slice plan (smallest safe first)

- **Slice A — the wrapper, no cache yet (the 10a-equivalent).** Land
  `with_box(path, busy, closure)` and route **all 20 call sites** through it,
  with `open_box` still calling the *unchanged* `open_swept`/`Session::open`
  every time (no cache read, no cache write). `checkin` is a no-op. This is a
  pure refactor: zero behavior change, the full test suite passes untouched, and
  it establishes the single choke point every later guard hangs off. **This
  slice ships alone and is the safe foundation** — exactly as P8/P9 land a
  substrate slice before the surface.

- **Slice B — the cache + fast path, fully guarded.** Add the `CACHE` map, the
  `Cached` entry, the fast-path check in `open_box` (Guards 2/3/5/7), the
  `checkin` write-back, and the failure eviction (Guards 4/6). Full re-open on
  any `(log_len, sidecar_len, inode)` mismatch. Sweep/seed stay in the slow path
  only (§1.4). This is where the O(history) cost disappears.

- **Slice C (deferred, measure first) — delta-replay on external append.** Only
  if the CLI-append path is measured to hurt: expose a public
  `Session::apply_appended(&new_bytes)` that parses bytes past `cached_len` and
  `apply`s only the new transactions onto the cached store, turning an external
  append from a full re-read into an incremental one. Needs a public
  single-transaction apply (`store.rs:396` is private today) and its own torn-tail
  handling on the appended slice. **Not in v1.**

### 6.1 Test list

Each is a Rust test in `ffi/src/lib.rs`'s `mod tests` (the harness already has
`fresh_box`/`cleanup`/`read_json`), driving the real FFI entry points so the
cache is exercised end to end.

1. **Incremental-open == full-open equivalence.** Capture a scrap, snapshot
   (populates cache), snapshot again (cache hit): the two snapshots are
   byte-identical to each other **and** to a snapshot taken after clearing the
   cache and forcing a full open. The cache never changes an answer.
2. **A mutation is visible on the next call.** `set_at` then `snapshot`: the
   snapshot reflects the set. (Proves check-in caches the *post*-op store and the
   grown length forces the read path where needed.)
3. **External append is picked up.** Open via FFI (caches). Then, from a second
   `Session::open` in the test (a stand-in for the CLI), append a transaction and
   drop it. The next FFI `snapshot` must show the externally-committed change —
   proving the length mismatch forces a full re-open, not a stale cache hit.
4. **Torn tail.** Hand-write a log whose final record lacks its newline; open via
   FFI twice. The first open repairs and caches the repaired length; the second
   hits cleanly and returns the same store; no record past the torn one leaks
   (Guard 1).
5. **Poisoned invalidation.** Force a `persist_last` failure (e.g. a read-only or
   full filesystem via a test seam, or inject an `Io` on append) on a mutating
   call; assert the cache entry for that path is gone afterward, and that the next
   open replays only what reached disk with a `next_id` consistent with the log
   (Guard 4/6).
6. **Two consecutive creates do not reuse an id.** `create_note` then
   `create_note` (each its own FFI call, so each hits the cache path): the two ids
   differ, and a subsequent full replay (cache cleared) yields the same two ids —
   proving `next_id` rides the cache correctly (Guard 6).
7. **Sweep runs on the open that changed the store, not on cache hits.** Capture
   "kickoff friday" (full open, sweeps, enqueues the date proposal); snapshot
   twice; assert the inbox shows exactly one proposal both times and the
   `.pending` sidecar was written once, not on the second (cache-hit) snapshot.
   Then capture a *second* dated scrap and assert its proposal appears on the very
   next snapshot — a same-"day" new note is swept because the capture was a full
   open (retires the "same-day new note lost its proposal" regression).
8. **Sidecar change without a log change invalidates (Guard 2).** Snapshot
   (caches). Externally `reject` a proposal (grows `.declined`, log length
   unchanged). The next FFI snapshot must reflect the decline — proving
   `sidecar_len` mismatch forces a full re-open.
9. **A locked box is never served from cache (Guard 5).** Snapshot (caches). Hold
   the box open in a second `Session` (grabs the lock). An FFI call must return its
   busy value (`Locked` → null/0), never a stale cached snapshot.

## 7 · What to defer

- **Delta-replay of an external append** (Slice C) — full re-open is correct and
  the CLI-append path is rare; defer until measured.
- **LRU / bounded eviction of the cache map.** Typical use is 1–2 open boxes.
  Unbounded growth only matters for a long-lived process that opens many distinct
  boxes; add an LRU cap only if that is observed. (The map holds one `Store` per
  path; a `Store` is proportional to live entities, not history length, once
  replayed.)
- **Splitting `sidecar_len` into two fields** to defeat a compensating ±N across
  `.declined`/`.pending` — a real but pathological external-edit case; the
  combined length is sufficient for v1.
- **A `poisoned` flag in the entry** — eviction (Guard 4) is simpler and equally
  correct; a flag only earns its place if we later want to *report* poison from
  the cache without re-opening.
- **mtime in the key** — length + inode witness every case; mtime is coarser and
  racier, and buys nothing here.
- **Caching across process restarts / on-disk cache** — out of scope; the cache
  is a live-process optimization, and a fresh process pays exactly one full open
  per box, which is the status quo.
```