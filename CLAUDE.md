# Liv — project guide

> **Naming:** the product and the code are both **Liv** — crates (`liv-engine`,
> `liv-ffi`, …), the `liv_*` FFI symbol prefix, `ffi/liv.h`, and the
> box file (`…/Application Support/liv/liv.db`). The old codename **`lotus`**
> was renamed away (2026-07-22); it survives in one frozen place, on purpose:
> the historical spec/design docs (`design/p*.md`, `interface.md`,
> `feature-map.md`, …) still say `lotus_*` — read them as `liv_*`. (A second,
> the `lotus_log` header of codename-era core boxes, went with `core/` on
> 2026-09-29.) Do not reintroduce `lotus` into code. (The specs were ported from an OLDER Tauri app, also called Liv, that
> lived at `~/src/friend-fixes`. That checkout no longer exists on this
> machine, and it is NOT the desktop your team is building — see
> `design/spec-alignment.md`.)

A native productivity app on a clean, append-only Rust core. It is a from-scratch
rewrite of an older Tauri/web app ("Liv", kept for reference in a **separate**
repo — not this one). The core is portable; each platform gets a **native**
shell over the same Rust FFI.

## Architecture — one core, many shells

```
engine/     Rust — THE core the app runs on (since slice 5b, 2026-09-19): ops over
            SQLite in `liv.db`, built for sync.
surface/    Rust — what each screen asks the engine (Today, Tasks, Notes, the day,
            search, trash) and the clerk's proposers. Pure reads over the engine.
ffi/        Rust — the ONE C ABI; staticlib + cdylib + rlib. 48 exports, every
            verb over the engine (`ffi/src/{surfaces,basics,writes,finding}.rs`);
            the core-era verbs went in stage 5 (2026-09-29)
cli/        Rust — a headless CLI; the VERIFICATION tool. It calls the app's
            own verbs through the ffi rlib, on the app's `liv.db` (since
            2026-09-29), and seeds test boxes (`liv new task … --area Work`)
shell/ios/     Swift/SwiftUI — THE app (see design/ios.md, design/what-liv-is-for.md)
shell/ios/ShareExtension/   the share-sheet extension: UIKit + Foundation only, no Rust;
                            it spools text into the App Group and the app captures it
```

Everything above `ffi/` is **platform-agnostic Rust** (it compiles for iOS and
for `x86_64-pc-windows-msvc` today). A shell is a thin UI that (1) calls FFI
verbs to mutate, (2) reads the snapshot JSON to render.

**Platforms, as of 2026-08-29 — TAURI IS DROPPED (owner's word).** `shell/ios/`
is THE app: the product, built and shipped from this tree, and the only shell
that exists. The goal is still **one mobile app and one desktop app that mirror
each other**, but the desktop is no longer the Tauri app in the
`lovable-notes-hub` working copy. There is no desktop shell right now, and
picking what it will be is an open question — not a thing to start unasked.

What this reverses: from 2026-08-22 the ruling was *"we can't break or change
how the tauri app works"* and *"both shells will share one core"*, and a
convergence plan was written around it (`design/core.md`, `design/core-plan.md`,
and the superseded recommendation in `design/one-core.md`). That plan had one
purpose — to keep the Tauri app working while it moved onto this core. With the
app dropped, the purpose is gone. Read those three for the head-to-head evidence
and the honest costs; **do not read them as the plan of record**. Nothing in
them is scheduled.

What did NOT change: the Tauri working copy is still there and is still
**outside this repo**, so it is still "ask first" (and the owner has said
directly: don't change it). Dropping it means this tree stops aiming at it. It
does not mean going and deleting it.

**The desktop's SQLite engine is a crate named `liv-core`** (1,784 lines,
outside this repo). This repo had its own crate of that name — the append-only
log — until stage 5 deleted it (2026-09-29). The desktop's has no shell over it,
and nothing here should link, mirror or migrate to it — which is what
`design/one-core.md` §3 recommended on 2026-08-19, before the ruling that has
now itself been dropped.

The hand-built Mac shell and the planned WinUI port are **gone** (deleted
2026-08-19, owner's word, because Tauri covered macOS, Windows and Linux). That
reason has expired, and the deletion has NOT been reversed: there is still no
desktop shell in this tree, and reviving either one needs the owner's word
first. Git history holds them — `git log --diff-filter=D --name-only` finds the
removal commit.

**The engine is live work again (owner, 2026-09-13):** *"the 'engine' should
have been completed and the goal is to wire it completely with the app."* It was
built to Phase 5 on 2026-08-22 and then sat for three weeks. Phases 1–5 done, 55
tests, zero warnings, **zero dependents** — nothing links it, so none of it has
run on a phone. The plan, its measured state and the one fork that blocks Phase 6
are in `design/core-plan.md`; the design is `design/core.md`.

**Since then:** the plan of record is `design/rust-owns-the-mechanisms.md` §5,
which supersedes `one-core.md` and rewrites `core-plan.md` from Phase 6 on. Slice
5b is DONE (2026-09-19): the app runs entirely on the engine. Stage 5 is DONE
(2026-09-29, owner: *"work on deleting core/"*): `core/`, `services/`, `views/`,
`convert/` and the ABI's core-era half are deleted, and the workspace is four
crates — engine, surface, ffi, cli. Next is stage 6, sync. The owner's standing
word on data, 2026-09-13: *"it's all for testing! so nuke or change anything
you want (except how the interface looks rn)."*

## The boundary — READ THIS BEFORE EDITING

| Zone | Rule |
|---|---|
| `shell/ios/**` | The app. Edit freely. |
| `engine/**`, `surface/**` | **Open, and the active work** (owner, 2026-09-13). Failing-test-first, and no iOS, no Swift assumptions, no phone-shaped verbs — the desktop must be able to link it. Logic two shells would both need belongs HERE, not in a shell. NOT settled — but it has shipped since slice 5b (2026-09-19), so a wrong on-disk shape is no longer free to fix. Follow `design/rust-owns-the-mechanisms.md` §5. |
| `ffi/**`, `ffi/liv.h` | The C ABI contract. Additions must be **purely additive** (never change an existing signature or meaning), run over `with_engine` and answer through `deliver`, ship with a test, and be flagged to the owner. A removal needs the owner's word. |
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

- **Every verb takes the engine box's path** (`liv.db`) and runs over
  `with_engine`. Mutations (`liv_set`, `liv_add`, `liv_make`, `liv_trash`, …)
  run one transaction each. Never hold the box lock across long IO.
- **Reads are per screen**, already filtered and sorted: `liv_view_today`,
  `liv_view_tasks`, `liv_view_everything`, `liv_view_day`, `liv_view_trash`,
  `liv_cells`, `liv_search`, `liv_links`, … — JSON, decoded into native models.
  Every wire field must be **optional** in the decoder, or one missing key drops
  the whole answer (a real, recurring bug). A verb answers the value OR a fault,
  exactly one. Ids are 32 hex characters and are never shown to anyone.
- Strings cross as UTF-8 C strings; free returned strings with `liv_string_free`.
- The full verb list + shapes live in `ffi/src/{surfaces,basics,writes,finding}.rs`
  and `ffi/liv.h`; `ffi/tests/header.rs` checks the two name the same verbs.

## Build & test

```
cargo test                        # the whole Rust workspace (run before every PR)
cargo build --release -p liv-ffi  # produces the ffi lib (staticlib + cdylib)
./target/release/liv --box <dir>/liv.db list --all   # inspect a box from the CLI
```

The CLI answers with the same verbs, and the same JSON, the app decodes
(`liv help`). A test box is seeded with it —
`liv --box <dir>/liv.db new task Pay rent --due 2026-09-30 --area Home` — and
the app opens it through `LIV_BOX_PATH`
(`SIMCTL_CHILD_LIV_BOX_PATH=<dir>/liv.db`).

**The iOS shell has three of its own, and `cargo test` runs none of them.**

```
shell/ios/build.sh          # dev build: -Onone, incremental (seconds after the first); add `run` to boot a simulator
shell/ios/build.sh release  # -O, whole program, from scratch — what ships; `device` is always release
shell/ios/suites.sh         # the ten launch-flag self-checks (the shell's unit tests)
shell/ios/drive.sh          # drives the running app and asserts what is ON SCREEN
```

`suites.sh` replaces the recipe that used to be written here, which did not
work: the app does not exit after a self-check, so a bare `simctl launch
--console-pty` never returns, and bounding it with SIGALRM fails because
`xcrun` forks `simctl`. The script has the working form and the reason.

**`drive.sh` needs `axe` and `suites.sh` does not** — which is why the
suites can be green while `drive.sh` cannot see the screen at all. Every
reading it takes comes from `axe describe-ui`; without the binary, nothing
it prints is a statement about the app. It installs from a TAP, so a bare
`brew install axe` matches no formula:

```
brew install cameroncooke/axe/axe     # github.com/cameroncooke/AXe
```

`LIV_AXE` points at it if it lives off PATH. Written down here because on
2026-09-21 its absence read as "the app drew nothing" for a day.

Both scripts INSTALL `build/Liv.app` themselves and refuse to run against
a bundle older than the sources. Until 2026-08-27 they did not, and
launched whatever was already on the simulator — a deliberately broken
assertion still printed ten PASSes. When you change a check, break one
assertion on purpose and watch it fail before you trust the green.

**`suites.sh` is necessary and not sufficient.** It asks the MODEL, and on
2026-08-23 a day was lost to a rework where the model was right and the screen
never repainted — every suite passed while the app was visibly broken.
`drive.sh tour` is the answer: it walks all six views and asserts, from the
accessibility tree, which surface is actually rendered (`Surface.swift`). Run
it before claiming a UI change works. Its other checks are `panel` (BOTH
side panels — one body run twice, mirrored), `bar`, `grid`, `facets` and `vault`.

Every check asserts GEOMETRY or rendered text, never whether a view is
mounted: a closed panel stays in the view tree and simply moves off
screen, so "is its marker there" answers a different question than the
one being asked.

Do not commit unless the owner asks.

## Standing rules that keep this from rotting

Measured 2026-08-08 against the app this replaces (134,695 lines, 3 data
stores, 275 direct storage calls from 70 files, 78 string-keyed events,
one test file). The rewrite avoided all of that. These rules are what
keeps it avoided — each one exists because its absence is visible in the
old codebase.

1. **Every `liv_*` call lives in `shell/ios/Sources/Box.swift`.** A
   second file calling the C ABI is a defect. (Measured 2026-09-29: 42
   calls to 39 distinct verbs plus `liv_string_free`, one file; other Swift
   files mention a verb NAME in a comment, and none call one.) The share extension is a
   second BINARY and calls none either: it writes a file into the App
   Group spool and the app captures it (`Catch.swift`).
2. **Anything on the refresh path OR THE WRITE PATH ships with a COST
   test**, not just a correctness one — see `engine/tests/scale.rs`,
   `surface/tests/sweep_cost.rs`, and through the ABI
   `ffi/tests/basics.rs` (`one_write_through_the_abi_stays_flat_as_the_box_grows`)
   and `ffi/tests/surfaces.rs` (`one_refresh_stays_linear_in_the_box`, the
   eight reads one refresh makes). The
   write path was added on 2026-08-19 because every existing cost test
   covered a READ, which is exactly why a whole-box clerk sweep on every
   write went unseen for weeks (`design/write-cost.md`). The file projection
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

- **Failing-test-first** for any `engine`/`surface`/`ffi` change; **mockup-first**
  for visible UI. Where a spec collides with the constitution, take the most
  faithful reconciliation and record the delta in the design doc.
- AI features are quarantined (proposals only); don't build them into a shell.
- Keep it dense — this app is deliberately compact. The density reference used
  to be the Mac shell; it is now `shell/ios/Sources/Theme.swift`, which is the
  only place a size or a colour may be defined.
- **The only clickable TEXT in the app is a link inside a note** (owner,
  2026-09-15: *"Only clickable text in the app should be links inside notes…
  otherwise it should look like a button and be consistent"*). Everything else
  you can tap wears one of three shapes, and there is no fourth:
  a **full-width row** (`LivMenuRow`, the library panel's) for a door in a
  list; a **hollow chip** (`AddChip`) for a quiet or secondary verb; a
  **filled pill** (`ConfirmPill`, `compact:` at the end of a row) for the
  primary verb. A bare accent word is a hyperlink and is a defect.
  Swept 2026-09-16 and it cost twelve: `+ Link…`, `Show all 12`,
  `New workspace…`, Add (twice), Done, Close all, Put back, Restore,
  Accept all, Route them, Create — plus `SectionLabel`'s accent trailing
  verb, deleted. Each was written on its own day by someone who only had
  the one in front of them, which is what a missing shape costs.
- **A property has a token and a word, and they are not the same string.**
  `PROPS.name` is what the query grammar lexes and what is frozen on disk
  (`tags`); `PROPS.reads` is what a person sees (`Subject`, owner
  2026-09-16). `liv_properties` ships both — `word` and `name` — and a shell
  keys its rows off `word` and draws `name`. Matching on the shown name is
  how the area picker broke on 2026-09-14, and it is why `InspectorField`
  carries `property` and `shown` separately.
- Verify on the simulator before claiming something works; cross-check writes
  against the box with the CLI (`liv --box … cells ID`, `history`). A builder's
  own report is not evidence.
