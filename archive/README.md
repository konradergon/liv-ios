# archive

Work that is no longer the product, kept because the log is not the only
history worth having.

## macos-shell (archived 2026-07-28)

The hand-built SwiftUI Mac app — the first shell over the liv core, and the
reference implementation the iOS shell was drawn from. Superseded: the phone
is the product, and the desktop will be the Tauri app (see
`docs/liv-core-pivot.md` in the lovable-notes-hub repo). Nothing depends on
it; the C header it used to own now lives at `ffi/liv.h`, where it belongs.

Read it for the design tokens, the density decisions, and the surface
layouts — they were carefully made and the iOS shell still honours them. Do
not build on it.
