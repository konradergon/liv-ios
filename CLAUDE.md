# Liv — project guide

> **Naming:** the product and the code are both **Liv** — crates (`liv-core`,
> `liv-ffi`, …), the `liv_*` FFI symbol prefix, `shell/macos/liv.h`, and the
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
shell/macos/   Swift/SwiftUI — the macOS shell; links the ffi staticlib via liv.h
shell/ios/     Swift/SwiftUI — the iPhone capture satellite (see design/ios.md)
shell/windows/ (TO BUILD) — WinUI 3 / C#; P/Invokes the ffi cdylib (liv_ffi.dll)
```

Everything above `ffi/` is **platform-agnostic Rust and already works on
Windows** (it compiles for `x86_64-pc-windows-msvc` today). A shell is a thin
native UI that (1) calls FFI verbs to mutate, (2) reads the snapshot JSON to
render. The macOS shell is the reference implementation for the Windows one.

## The shared/platform boundary — READ THIS BEFORE EDITING

The repo is shared between the macOS work and the Windows port. To keep the core
one source of truth, respect these zones:

| Zone | Windows-port Claude may… |
|---|---|
| `shell/windows/**` | **OWN it** — create, edit freely. This is the port. |
| `core/ **`, `services/**`, `views/**` | **READ ONLY.** Never change core behavior. |
| `ffi/**`, `shell/macos/liv.h` | **READ.** The C ABI is the contract. Adding a *new* `liv_*` verb is allowed ONLY if the Windows UI genuinely needs one that doesn't exist — and it must be **purely additive** (never change an existing signature or its meaning), mirror the `with_box` + `Committed` pattern, ship with a test, and be flagged to the owner in the PR. Prefer reusing an existing verb. |
| `shell/macos/**` | **DO NOT TOUCH.** The SwiftUI shell is another person's platform. |
| `design/**`, `*.md` specs | **READ** for the behavioral spec (see below). Don't rewrite them. |
| everything outside this repo | **NEVER.** Stay in this working tree. |

If a task seems to need a change outside `shell/windows/`, **stop and ask the
owner** rather than reaching across the boundary. The Rust core's behavior is
settled and reviewed; the Windows shell must match it, not reshape it.

## The specs are the source of truth

Port *behavior and layout*, don't invent them. In priority order:
1. `interface.md` — the constitution/laws (what the app is and refuses to be).
2. `feature-map.md` — every feature and its Liv reconciliation.
3. `liv-ui-map.md` — the original UI, surface by surface.
4. `design/p*.md` — the per-phase design docs (what shipped and why).
5. `shell/macos/Sources/*.swift` — the reference shell. The Windows shell should
   reproduce each surface 1:1 (layout, density, behavior), in the **Liv
   palette** (lake-green accent `#2f7d6b`, never blue/violet).

See `design/windows-port.md` for the WinUI 3 architecture + a surface-by-surface
port map.

## The FFI contract (how a shell talks to the core)

- **Mutations**: call a `liv_*_at(box_path, …)` verb. Each opens the box, runs
  one transaction, checks in. Returns an id / count / status. Never hold the box
  lock across long IO.
- **Reads**: `liv_snapshot_at` (or `liv_snapshot_window_at` for the calendar)
  returns a JSON `Snapshot` — decode it into your native models. Every wire field
  the shell adds must be **optional** in the decoder, or one missing key drops
  the whole snapshot (a real, recurring bug — see the macOS `applySnapshot`).
- Strings cross as UTF-8 C strings; free returned strings with `liv_string_free`.
- The full verb list + shapes live in `ffi/src/lib.rs` and `shell/macos/liv.h`.

## Build & test

```
cargo test                        # the whole Rust workspace (run before every PR)
cargo build --release -p liv-ffi  # produces the ffi lib (staticlib + cdylib)
./target/release/liv --log <box> list --all   # inspect a box from the CLI
```
macOS shell: `shell/macos/build.sh`. Windows shell: see `design/windows-port.md`.
Do not commit unless the owner asks. Branch off `main`; keep Windows work on a
`windows-port` branch and land it by PR so the owner reviews the boundary.

## House rules (apply to all shells)

- **Failing-test-first** for any `core`/`services`/`ffi` change; **mockup-first**
  for visible UI. Where a spec collides with the constitution, take the most
  faithful reconciliation and record the delta in the design doc.
- AI features are quarantined (proposals only); don't build them into a shell.
- Match the reference shell's density — this app is deliberately compact.
