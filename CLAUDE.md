# Liv — project guide

Read `HANDOUT.md` first: what is true now, what the owner has decided,
and what is next. Then `design/how-its-built.md` (the code on one page)
and `design/what-liv-is-for.md` (the product).

## What this is

A note, task and calendar app for iPhone, on a Rust core.

```
engine/     the store: a ledger of every change, and the current state, in liv.db (SQLite)
surface/    what each screen shows — every product rule, with a test
ffi/        the one C door (ffi/liv.h): functions in, JSON out
cli/        `liv`: the same functions from a terminal, to seed and check a box
shell/ios/  the app (SwiftUI); ShareExtension/ is UIKit only, no Rust
```

The iPhone app is the only shell. A desktop app is wanted but not
chosen — don't start one unasked. The old Tauri desktop app lives outside
this repo and is dropped; don't change it. The deleted Mac and WinUI shells
stay deleted unless the owner says otherwise.

The old codename was `lotus`; archived docs say `lotus_*` for `liv_*`.
Don't bring it back into code.

## Rules

Few, and each one keeps the code from rotting — the app this replaced
broke every one of them.

1. **Rules live in Rust; Swift draws.** What a screen lists, in what
   order, what counts as late or unsorted: `surface/`, with a test. A shell
   gets answers, never the box. Nothing iPhone-specific goes into `engine/`
   or `surface/` — a desktop must be able to link them.
2. **One of each.** One rule, one parser, one helper, in one place. A
   second copy of a rule is a bug waiting to disagree.
3. **Every `liv_*` call is in `shell/ios/Sources/Box.swift`.**
4. **The door.** Adding a function to `ffi/` is fine — with a test, and
   told to the owner. Changing or removing one needs the owner's word. In
   Swift, every field decoded from the door is optional: one missing key
   must not drop the whole answer.
5. **Tests first** for `engine/`, `surface/` and `ffi/`. Anything on the
   refresh or write path also gets a cost test: doubling the box roughly
   doubles the work. Assert the shape, never milliseconds.
6. **Sizes and colours only in `Theme.swift`.**
7. **Delete what a change makes dead**, in the same change.
8. **See it work.** Check on the simulator before saying something works,
   and cross-check writes with the CLI (`liv --box … cells ID`, `history`).
   A check nobody has seen fail proves nothing — break it once. For a new
   screen or a big visual change, show a mockup first.
9. **Hands off**: don't commit unless asked; never touch simulator
   `00E539E0-…` (the owner's data — use `8E699FF6-…`); ask before touching
   anything outside this repo.

## Build and check

```
cargo test                  # all Rust
shell/ios/build.sh          # the app (dev, incremental); `run` boots a simulator; `release`, `device`
shell/ios/suites.sh         # the app's own self-checks
shell/ios/drive.sh tour     # drives the running app and asserts what is on screen
./target/debug/liv --box <dir>/liv.db list --all
```

- A test box: `liv --box <dir>/liv.db new task Pay rent --due 2026-09-30
  --area Home`, then launch with `SIMCTL_CHILD_LIV_BOX_PATH=<dir>/liv.db`.
- `suites.sh` asks the app's model, so it can pass while the screen is
  wrong; `drive.sh` checks the screen. It reads it through `axe`
  (`brew install cameroncooke/axe/axe`) — without it, nothing `drive.sh`
  prints is about the app. Both install the fresh build first.
- Never copy or delete a box's files (`liv.db`, `-wal`, `-shm`) while
  something has it open.

## Docs

- `HANDOUT.md` — now: the state, the owner's decisions, what is next.
- `design/what-liv-is-for.md` — the product. It wins product arguments.
- `design/how-its-built.md` — the code.
- `design/changelog.md` — what changed and why, newest first.
- `design/op-format.md` — the on-disk format, held by the codec tests.
- `design/testflight.md` — getting the app onto phones.
- `design/archive/` — history: the old specs, phase docs, studies,
  mockups, and this file's previous version with all its detailed rules.
  Read it to learn why something was done, not what to do.
