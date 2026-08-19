# Liv — project guide

> **Naming:** the product and the code are both **Liv** — crates (`liv-core`,
> `liv-ffi`, …), the `liv_*` FFI symbol prefix, `ffi/liv.h`, and the
> box file (`…/Application Support/liv/liv.log`). The old codename **`lotus`**
> was renamed away (2026-07-22); it survives in exactly two frozen places, on
> purpose: (1) codename-era boxes carry the on-disk header key `lotus_log` and
> legacy box paths — the core reads both and preserves the key on in-place
> upgrades (see `core/src/persist.rs` + `core/tests/versioning.rs`); (2) the
> historical spec/design docs (`design/p*.md`, `interface.md`, `feature-map.md`,
> …) still say `lotus_*` — read them as `liv_*`. Do not reintroduce `lotus`
> into code. (The *old* Tauri app in the separate `friend-fixes` repo is also
> called Liv — unrelated to this codebase; don't confuse the two.)

A native productivity app on a clean, append-only Rust core. It is a from-scratch
rewrite of an older Tauri/web app ("Liv", kept for reference in a **separate**
repo — not this one). The core is portable; each platform gets a **native**
shell over the same Rust FFI.

## Architecture — one core, many shells

```
core/       Rust — the append-only log, entities = property→value cells, commands
services/   Rust — projections, search, import/export, clerk, recurrence (pure fns)
views/      Rust — value display + rendering helpers (cross-platform)
ffi/        Rust — the ONE C ABI (56 `liv_*` fns); staticlib + cdylib + rlib
cli/        Rust — a headless CLI over the same core; the VERIFICATION tool
shell/ios/     Swift/SwiftUI — THE app (see design/ios.md, design/what-liv-is-for.md)
```

Everything above `ffi/` is **platform-agnostic Rust** (it compiles for iOS and
for `x86_64-pc-windows-msvc` today). A shell is a thin UI that (1) calls FFI
verbs to mutate, (2) reads the snapshot JSON to render.

**Platforms, as of 2026-08-19.** `shell/ios/` is THE app — the product, built
and shipped from this tree. The desktop is the **Tauri app** in the
`lovable-notes-hub` working copy, which links the same crates directly (no C
ABI needed); the iOS tree is expected to move there eventually.

**It is not a separate repository.** Both working copies point at the same
remote, `Dahlaren/lovable-notes-hub` — two branch lines with no common ancestor
in one repo. Resolving that topology (merge, subtree, vendor or publish) is an
open question; a `path = "../../liv/core"` across two checkouts of one remote is
unclonable and un-CI-able. The `docs/liv-core-pivot.md` that used to be cited
here exists only on an unpushed local branch.

**Two crates are named `liv-core`**: this one (the append-only log) and the
desktop's (a SQLite engine, 1,784 lines). They are not interchangeable, and only
one should survive — see `design/one-core.md` for the comparison, the
recommendation, the measured costs, and the six questions it needs answered.

The hand-built Mac shell and the planned WinUI port are **gone** (deleted
2026-08-19, owner's word). Tauri covers macOS, Windows and Linux, so neither
had a reason to exist. Git history still holds them — `git log --diff-filter=D
--name-only` finds the removal commit — but nothing in the working tree points
at them any more, and nothing should.

## The boundary — READ THIS BEFORE EDITING

| Zone | Rule |
|---|---|
| `shell/ios/**` | The app. Edit freely. |
| `core/**`, `services/**`, `views/**` | **Settled.** Change only with the owner's word, failing-test-first. Logic two shells would both need belongs HERE, not in a shell. |
| `ffi/**`, `ffi/liv.h` | The C ABI contract. Additions must be **purely additive** (never change an existing signature or meaning), mirror `with_box` + `Committed`, ship with a test, and be flagged to the owner. |
| `design/**`, `*.md` specs | **READ** for the behavioural spec. Amend deliberately; don't rewrite history. |
| `cli/**` | The verification tool. Keep every verb the shell has a way to reach. |
| everything outside this repo | Ask first. |

## The specs are the source of truth

Port *behavior and layout*, don't invent them. In priority order:
1. `interface.md` — the constitution/laws (what the app is and refuses to be).
2. `feature-map.md` — every feature and its Liv reconciliation.
3. `liv-ui-map.md` — the original UI, surface by surface.
4. `design/p*.md` — the per-phase design docs (what shipped and why). These
   still cite `shell/macos/...` line numbers for the deleted Mac shell: read
   them for BEHAVIOUR, and ignore the coordinates.

`design/what-liv-is-for.md` outranks all of these for **product** questions:
architecturally clean and product-wrong is still wrong.

## The FFI contract (how a shell talks to the core)

- **Mutations**: call a `liv_*_at(box_path, …)` verb. Each opens the box, runs
  one transaction, checks in. Returns an id / count / status. Never hold the box
  lock across long IO.
- **Reads**: `liv_snapshot` (or `liv_snapshot_window_at` for the calendar)
  returns a JSON `Snapshot` — decode it into your native models. Every wire field
  the shell adds must be **optional** in the decoder, or one missing key drops
  the whole snapshot (a real, recurring bug — see the macOS `applySnapshot`).
- Strings cross as UTF-8 C strings; free returned strings with `liv_string_free`.
- The full verb list + shapes live in `ffi/src/lib.rs` and `ffi/liv.h`.

## Build & test

```
cargo test                        # the whole Rust workspace (run before every PR)
cargo build --release -p liv-ffi  # produces the ffi lib (staticlib + cdylib)
./target/release/liv --log <box> list --all   # inspect a box from the CLI
```
iOS shell: `shell/ios/build.sh` (add `run` to boot it in a simulator).
Do not commit unless the owner asks.

## Standing rules that keep this from rotting

Measured 2026-08-08 against the app this replaces (134,695 lines, 3 data
stores, 275 direct storage calls from 70 files, 78 string-keyed events,
one test file). The rewrite avoided all of that. These rules are what
keeps it avoided — each one exists because its absence is visible in the
old codebase.

1. **Every `liv_*` call lives in `shell/ios/Sources/Box.swift`.** A
   second file calling the C ABI is a defect. (Today: 35 calls, one
   file, and every other Swift file has zero.)
2. **Anything on the snapshot path ships with a COST test**, not just a
   correctness one — see `services/tests/scale.rs`. The file projection
   was quadratic for weeks and 315 correctness tests could not see it.
   Assert the SHAPE (doubling the box roughly doubles the work), never a
   millisecond budget.
3. **A rule that matters lives in a type, not in prose.** Colours are
   tokenised in `Theme.swift` and have never drifted; type sizes are
   prose and have drifted 38 times.
4. **One grammar, one parser.** Two parsers for the same user-facing
   syntax is a defect. Same for a display helper, a row type, a glyph
   table.
5. **A user never types a query language.** Filters and workspaces are
   built from pickers over furniture that already exists; the text
   grammar is the storage format and an advanced escape hatch.
6. **When a decision makes code unnecessary, delete it in the same
   change.** No dead code (owner, 2026-08-07).
7. **No feature flag without a deletion date in the same change.**
8. **One user action gets one snapshot.** Refreshes coalesce
   (`Box.swift`); where the ABI forces a shell to hand-assemble several
   verbs, add one compound verb — purely additive, and permitted.
9. **A file past ~600 lines is a signal to look for the seam**, not a
   number to hit.

## House rules

- **Failing-test-first** for any `core`/`services`/`ffi` change; **mockup-first**
  for visible UI. Where a spec collides with the constitution, take the most
  faithful reconciliation and record the delta in the design doc.
- AI features are quarantined (proposals only); don't build them into a shell.
- Keep it dense — this app is deliberately compact. The density reference used
  to be the Mac shell; it is now `shell/ios/Sources/Theme.swift`, which is the
  only place a size or a colour may be defined.
- Verify on the simulator before claiming something works; cross-check writes
  against the box with the CLI. A builder's own report is not evidence.
