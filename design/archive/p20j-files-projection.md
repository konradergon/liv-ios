# P20j — the files projection (O14: "that folder IS the database")

> Three design angles (constitution-first · risk-first · fidelity-first) were
> drafted independently and judged through three lenses (crash-matrix
> correctness · constitutional law · cost-and-fidelity). All three converged
> on the pivotal call; the spine below is the risk-first proposal (top
> composite score) with the judges' must-keep grafts from the other two.
> Nothing here is code yet — this doc is the gate.

## 1 · The position (the fork, resolved)

**The box stays the ONE truth. The vault folder is a total, continuously
reconciled, rebuildable PROJECTION with an inbound ingest channel — and the
box itself moves INSIDE the folder** at `<Vault>/.liv/box/lotus.log` (+ its
`.pending`/`.declined` sidecars). Containment is what makes the Settings
copy literally honest: *"that folder IS the database"* — because the
database is in it — and *"moving the store moves your files; nothing else
changes"* — because they are one folder.

bp7's "DB as rebuildable overlay" is honored in the only direction the
constitution permits: the **projection + manifest are rebuildable from the
log at any time** (delete `library/` and `.liv/index.json`, run Rebuild —
everything returns, byte-identical). Rebuilding the *box* from files exists
only as explicit disaster recovery, honestly labeled an import: history,
provenance, proposals, and undo depth live in the log and are unrecoverable
from markdown.

**The honest cost account** (recorded, both ways): files-as-truth would buy
byte-perfect portability and no divergence window, and would cost four laws
at once — ⌘⌥Z-over-the-log dies (files have no history), one-gesture-one-
transaction dies (a save is an untyped blob diff), no-silent-writes dies
structurally (every external save is an unwitnessed mutation), and the FFI
cache's log-length-is-proof validator plus the single-writer lock lose
their meaning. Box-as-truth costs exactly one thing: **an external edit is
not truth until ingested** — a divergence window bounded by scan-at-open +
the debounce (seconds). That window is the design's one honest flag (F1).

**Law recording:** interface.md §0.3's "no .md mirror / no file watcher" is
formally superseded by O14 for the vault projection — recorded here, not
silently bent.

## 2 · The on-disk layout

```
MyVault/
  library/{inbox,notes,daily,tasks,links,contacts,events,pdf,images,sheets,word,canvas}/
  <any user folders — existing-folder mode indexes them in place, untouched>
  .liv/box/lotus.log(+.pending,.declined)   ← THE ENGINE, relocated
  .liv/index.json                            ← the manifest (a CACHE, atomic tmp+rename)
  .liv/views/<slug>.view|.base               ← saved views as real hidden files
  .liv/settings                              ← store-scope settings projection
  .liv/conflicts/                            ← parked conflicted copies
  .liv/tmp/                                  ← staging for large byte copies
  .trash/<original-rel-path>                 ← recoverable, undo restores exactly
```

Manifest rows: `{path, id, digest(blake3), mtime, pool, trash_from?,
verbatim?}` + `{generation, log_len}`. The manifest is a cache: corrupt or
missing ⇒ rebuilt from store + disk, never a data loss.

**Slug rules:** stem = entity NAME through the P15 sanitizer (diacritics
transliterated — `Åkesson → akesson`, the pack's own example; 200-byte
clamp; Windows-reserved stems suffixed — the port is coming); collisions
dedupe case-insensitively (the P15c macOS-clobber law) with " (2)"
suffixes — a USER-caused collision prompts with the candidate pre-filled
("collisions prompt, never overwrite"); a silent re-projection collision
auto-suffixes and records. **H1-is-title:** Liv-authored bodies open with
`# <name>`, no `title:` frontmatter; in-app rename = `fs::rename`; if an
external edit changes both H1 and filename, **H1 wins** and the file is
renamed to match on the next projection (recorded).

**Box-only (stated honestly in Settings):** the log itself, per-cell
authorship/provenance, proposals, WORKING plumbing, tabs/layers/pins, time
entries, habit check-in history, comms messages (v0), the option
definitions catalog (v0 — flagged), and span-level Ref identity (serialized
as `[[Name]]`, name-resolved on re-ingest). Scraps materialize **on route,
not on capture** (the inbox pool holds them; routing files them).

## 3 · The write path (order is law)

`services/src/projection.rs`, the export idiom generalized: a **pure
planner** `plan_projection(store, &manifest, touched: &[Id]) -> Vec<FsOp>`
and an **IO applier** behind a `VaultIo` trait (so the crash matrix is a
test harness, not a prayer).

1. **Log append + fsync FIRST** (already shipped) — the log never waits on
   files, and projection failure **never fails a commit** (surfaced as
   status, healed by reconcile).
2. Per-file **atomic writes**: tmp + fsync + rename, in `.liv/tmp/`.
3. **Manifest LAST**, atomic.

Projection is **incremental by the transaction's touched ids** —
O(changed entities) per gesture, never a sweep per keystroke — and **never
runs under the box lock**; large byte copies stage outside everything.
The **two-process materialization race** (app + CLI both reconciling after
releasing the box flock) is serialized by a separate short-lived
`.liv/projector.lock` held only across apply+manifest — IO-only, never the
box lock — and is self-healing anyway (manifest-last + rule 1 below); it
gets its own named kill-shot.

Trash: a trash txn ⇒ the file moves to `.trash/<original-rel-path>`
(`trash_from` stamped); **undo over the log IS undo on disk** — the next
projection delta moves it back exactly. Deletion never cascades.

## 4 · The read path (reconcile + the structurally read-only watcher)

**Scan-at-open is canonical**; FSEvents may only mark dirty and schedule
ONE debounced, coalescing scan — the watcher is structurally incapable of
writing, excludes `.liv/`, and the whole test suite passes with it off.

Reconcile decision table, in order:
1. **Clean-by-expected-content FIRST**: file bytes == render(store) ⇒
   clean; refresh the manifest row. Content-addressed echo suppression —
   the projector's own writes can never re-ingest, no timing games.
2. **Clean external edit** (file changed, entity unchanged since its sync
   point, parses, round-trips): ingest as **ONE batched, announced,
   undoable transaction** — `Author::User`, txn label "vault-edit", toast
   *"3 notes updated from disk — ⌘⌥Z undoes"*, provenance in History. The
   file door is an input device, not a silent writer.
3. **Conflict** (both sides moved, or a cloud conflicted-copy filename):
   never merged, never auto-applied — the editor's existing conflict
   grammar: keep app version (re-project; disk copy parked in
   `.liv/conflicts/`) / take disk version (ingest txn) / keep both.
4. **Destructive-shaped** (file deleted/moved out; >N files in one window —
   sync-client fingerprints): **always a card, never auto-applied**. A disk
   deletion NEVER deletes or trashes the entity — the row wears "file
   missing" with Restore (re-project) / Move to .trash verdicts.

**Log self-defense** (the day the log lives in a syncable folder): the FFI
fast path refuses on length-regression / inode change / header mismatch
with a surfaced recovery notice, and a synced-down `lotus.log (conflicted
copy)` raises a blocking card — never silent adoption.

## 5 · Round-trip fidelity

Frontmatter = the P15 exporter's schema (properties; no `title:`);
body = the spans codec. **The verbatim guard:** any body that fails
`render(parse(body))` byte-stability is flagged `verbatim` in the manifest
— Liv reads it, indexes it, and **never rewrites it** (existing-folder
adoption must not normalize a stranger's markdown). Binaries carry no
frontmatter; the file is truth for bytes only (hash-tracked by the P15
librarian).

## 6 · Modes + migration

- **Fresh vault:** create the skeleton; the box is born at
  `.liv/box/lotus.log`.
- **Existing box adoption (the Move… flow):** copy the log into the chosen
  folder's `.liv/box/`, verify replay, materialize, then retire the old
  path with a pointer file. Its own slice; never automatic.
- **Existing-folder mode:** index in place — add only `library/` + `.liv/`
  as siblings; nothing is moved or rewritten (the verbatim guard is the
  load-bearing promise here).
- **Vault discovery:** by `.liv`-ancestor of the box path — LOTUS_BOX_PATH
  and every existing test/harness keep working unchanged (boxless = legacy
  mode, projection off).

## 7 · Verbs (additive, with_box + Committed, tested, flagged)

`lotus_vault_status_at` (mode/paths/divergence count) ·
`lotus_vault_sync_at` (the scan→ingest txn; scan IO OUTSIDE the lock, the
ingest commit inside) · `lotus_vault_rebuild_at` (full re-materialize) ·
`lotus_vault_adopt_at` (existing-folder indexing, batched) — plus the CLI
`lotus vault status|sync|rebuild`. Import gains write-into-`library/<pool>/`
(LB1 superseded — by-reference survives for outside-the-vault files);
export gains **Move-out** (LB5 superseded; "index rows removed" reconciled
as trash + tombstone — the append-only law allows no literal removal;
typed arming, gated).

## 8 · Slices (every gate is a failing test first)

| Slice | Scope | Gate / kill-shot |
|---|---|---|
| **20j.1** | codec + plan, pure (vault.rs/projection.rs: renderer fixpoint, slugger, collision determinism, `expected_files`) | render∘parse fixpoint property test over generated span trees; diacritic/reserved/collision table |
| **20j.2** | materializer + manifest (VaultIo, tmp+fsync+rename, delta apply) | **KILL-SHOT A (crash matrix):** abort at EVERY step boundary (after-commit / after-tmp / after-rename / before-manifest) + injected disk-full ⇒ reconcile converges to files == expected(store), zero loss, zero dupes |
| **20j.3** | reconcile + ingest + echo suppression | **KILL-SHOT B:** own-write → sync ⇒ 0 commits (100× idempotence); clean-edit ingest = one undoable txn; conflict/destructive tiers never auto-apply |
| **20j.4** | the two-process race + log self-defense | **KILL-SHOT C:** app+CLI concurrent reconcile under the projector lock ⇒ convergent manifest; length-regression/conflicted-log refusal cards |
| **20j.5** | the verbs + CLI + scan-at-open wiring | FFI cache-parity + Committed-tag tests |
| **20j.6** | **the early fidelity flip**: breadcrumbs, editor footer path, Reveal-in-Finder, saves-to readouts, `Vault: <name>` switcher go REAL behind vault mode (the 20b–20i presentational list) | mockup-copy check per site |
| **20j.7** | watcher (read-only FSEvents → debounced scan) + divergence status UI | suite green with watcher OFF; storm test (10k events ⇒ 1 scan) |
| **20j.8** | import-writes-files + export Move-out + drag-out + drop-anywhere | one-batch-one-undo on real files; Move-out arming |
| **20j.9** | Move… + existing-folder adoption + the 5-step tour rebuild (the folder step now real) | adoption never rewrites (verbatim guard proof); tour kill-matrix |

## 9 · Recorded deltas + the owner flags

**Deltas:** LB1/LB5/LB6 superseded as above · LB4 sharpened (a pool is
STILL a saved filter; `library/<pool>/` is a *landing* folder — a file
moved elsewhere keeps its pool) · ingests are `Author::User` "vault-edit"
commits (no new Author variant) · H1-wins-over-filename · scraps
materialize on route · options catalog box-only v0 · interface.md §0.3
superseded for the vault projection.

**Owner flags (decide-before-code):**
1. **F1 — the divergence window**: an external edit becomes truth only at
   ingest (seconds). This is the price of keeping undo/history; the
   Settings copy will say it plainly.
2. **The log lives in a syncable folder** (containment honesty) — guarded
   as §4, but the residual risk class (a sync client mangling `.liv/box/`)
   is real; the alternative (log outside the vault) breaks the "moving the
   store moves your files" sentence. Recommendation: inside, guarded.
3. **Move-out = trash + tombstone**, not literal index-row removal.
4. **The default vault location** for fresh installs (`~/Liv`? iCloud
   Drive?) — the tour's folder step will ask; the migration default needs
   an owner call.
