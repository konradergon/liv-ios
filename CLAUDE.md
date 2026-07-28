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
ffi/        Rust — the ONE C ABI (55 `liv_*` fns); staticlib + cdylib + rlib
cli/        Rust — a headless CLI over the same core (handy for inspecting a box)
shell/ios/     Swift/SwiftUI — THE app (see design/ios.md, design/what-liv-is-for.md)
archive/       superseded work, kept for reference — see archive/README.md
```

Everything above `ffi/` is **platform-agnostic Rust** (it compiles for iOS and
for `x86_64-pc-windows-msvc` today). A shell is a thin UI that (1) calls FFI
verbs to mutate, (2) reads the snapshot JSON to render.

**Platforms, as of 2026-07-28.** `shell/ios/` is THE app — the product, built
and shipped from this tree. The desktop will be the **Tauri app** in the
separate `lovable-notes-hub` repo, which links the same crates directly (no C
ABI needed; see its `docs/liv-core-pivot.md`); the iOS tree is expected to move
into that repo eventually. The hand-built Mac shell and the planned WinUI port
are both **superseded** — the Mac shell is in `archive/`, and Tauri covers
Windows and Linux for free.

## The boundary — READ THIS BEFORE EDITING

| Zone | Rule |
|---|---|
| `shell/ios/**` | The app. Edit freely. |
| `core/**`, `services/**`, `views/**` | **Settled.** Change only with the owner's word, failing-test-first. Logic two shells would both need belongs HERE, not in a shell. |
| `ffi/**`, `ffi/liv.h` | The C ABI contract. Additions must be **purely additive** (never change an existing signature or meaning), mirror `with_box` + `Committed`, ship with a test, and be flagged to the owner. |
| `design/**`, `*.md` specs | **READ** for the behavioural spec. Amend deliberately; don't rewrite history. |
| `archive/**` | Read-only reference. Never build on it. |
| everything outside this repo | Ask first. |

## The specs are the source of truth

Port *behavior and layout*, don't invent them. In priority order:
1. `interface.md` — the constitution/laws (what the app is and refuses to be).
2. `feature-map.md` — every feature and its Liv reconciliation.
3. `liv-ui-map.md` — the original UI, surface by surface.
4. `design/p*.md` — the per-phase design docs (what shipped and why).
5. `archive/macos-shell/Sources/*.swift` — the archived Mac shell. Read-only
   reference for tokens, density and layout; never build on it.

`design/what-liv-is-for.md` outranks all of these for **product** questions:
architecturally clean and product-wrong is still wrong.

## The FFI contract (how a shell talks to the core)

- **Mutations**: call a `liv_*_at(box_path, …)` verb. Each opens the box, runs
  one transaction, checks in. Returns an id / count / status. Never hold the box
  lock across long IO.
- **Reads**: `liv_snapshot_at` (or `liv_snapshot_window_at` for the calendar)
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

## House rules

- **Failing-test-first** for any `core`/`services`/`ffi` change; **mockup-first**
  for visible UI. Where a spec collides with the constitution, take the most
  faithful reconciliation and record the delta in the design doc.
- AI features are quarantined (proposals only); don't build them into a shell.
- Match the archived shell's density — this app is deliberately compact.
- Verify on the simulator before claiming something works; cross-check writes
  against the box with the CLI. A builder's own report is not evidence.
