# Windows port — a WinUI 3 shell over the same Rust core

The Windows app is a **new native shell**, `shell/windows/`, built with **WinUI 3
(Windows App SDK, C#/.NET)**. It reuses the entire Rust stack unchanged
(`core` / `services` / `views` / `ffi`) and reproduces the macOS SwiftUI shell's
surfaces 1:1. Nothing about the core, the log, or the FFI changes for Windows —
the seam is the same C ABI the macOS shell already uses.

**Naming:** the product is **Liv** — the WinUI app's display name, window title,
and About say "Liv". The code stays `lotus` (namespace, DLL `lotus_ffi.dll`, the
`lotus_*` verbs, box path). See the root `CLAUDE.md`.

> Scope + guardrails for the Claude doing this port live in the root
> `CLAUDE.md`. In short: **own `shell/windows/`; treat everything else as
> read-only reference; never touch `shell/macos/`; keep FFI changes additive and
> flagged.**

## 1 · The bridge — C# ↔ the Rust FFI

The `ffi` crate now builds a **cdylib** (`lotus_ffi.dll`) alongside the macOS
staticlib (`ffi/Cargo.toml`, `crate-type = ["staticlib", "cdylib", "rlib"]`).
The 36 `lotus_*` functions (see `ffi/src/lib.rs` / `shell/macos/lotus.h`) are the
whole surface.

1. **Build the DLL** for the MSVC target:
   ```
   rustup target add x86_64-pc-windows-msvc
   cargo build --release -p lotus-ffi --target x86_64-pc-windows-msvc
   # → target/x86_64-pc-windows-msvc/release/lotus_ffi.dll
   ```
   Copy the DLL next to the .NET output (or a post-build step). An
   `aarch64-pc-windows-msvc` target covers Arm devices.

2. **Generate the P/Invoke signatures.** Either hand-write `[DllImport("lotus_ffi")]`
   externs from `lotus.h`, or generate them with **csbindgen** (a Rust build-dep
   that emits C# bindings from the `extern "C"` fns) — recommended, so the
   bindings never drift from the ABI. Marshal strings as UTF-8:
   `[DllImport("lotus_ffi", CharSet = CharSet.Ansi)]` with `[MarshalAs(UnmanagedType.LPUTF8Str)]`
   on `string` params; returned `char*` come back as `IntPtr` → copy to a C#
   string, then call `lotus_string_free` on the pointer.

3. **Reads = decode the snapshot JSON.** `lotus_snapshot_at(box)` (or
   `lotus_snapshot_window_at` for the calendar) returns a JSON `Snapshot`. Model
   it in C# with `System.Text.Json`, `JsonNamingPolicy.SnakeCaseLower`, and make
   **every added field nullable** (a missing key must not drop the snapshot — the
   exact rule the macOS `applySnapshot` follows). The shapes to mirror
   (`ffi/src/lib.rs`): `Snapshot { today, unstructured, everything, dated,
   occurrences, inbox, workspaces, properties, entities }`, `EntityRow { id,
   title, kinds[], due?, dueEnd?, positionedBy?, dueDateOnly, status?, created?,
   trashed, bookmarked, archived, contentPrint, cells[] }`, `CellRow { propertyId,
   property, kind, value, refTarget? }`.

4. **A `BoxModel` equivalent.** Mirror the macOS `BoxModel` (Window.swift): hold
   the decoded `Snapshot`, run FFI calls on a background thread/queue, and
   `refresh()` (re-snapshot) after every mutation. Bind it to XAML via
   `INotifyPropertyChanged` / an `ObservableObject` (CommunityToolkit.Mvvm). The
   box path is fixed like macOS: `%APPDATA%\lotus\lotus.log`.

## 2 · The design system → WinUI

Port the tokens verbatim (`shell/macos/Sources/Tokens.swift`) into a WinUI
`ResourceDictionary` with light/dark `ThemeDictionaries`:

- Accent **lake green** `#2f7d6b` (never the OS blue). Grounds `#ffffff`/`#1f1f1f`;
  panel `#f1f3f4`/`#1b1b1b`; border `#c2c6cc`/`#51565c`; mutedFg `#4d5155`/`#b1b7bd`;
  amber `#e37400` reserved for AI presence; radii 4/6/8/12.
- The **panel-card** look (rounded, layered on a Mica/material base) maps to WinUI
  `Border` cards with `CornerRadius="10"` over a `MicaBackdrop` — the same intent
  as the macOS `panelCard()` + `SidebarMaterial`.
- The **grammar kit** (`RowKit.swift`: ObjectRow / ObjectCard / ObjectTile /
  ValueChip / StatusDot / anchorChip) becomes a set of reusable WinUI
  `UserControl`s / `DataTemplate`s. Build these FIRST — every surface consumes
  them, exactly as macOS does. Keep the 32–36px row budget and the "never-hue"
  set (status/priority/tier/type render text + a small dot, not the value hue).

## 3 · Surfaces — the port map (macOS → WinUI)

Reproduce each surface's layout/behavior from its Swift source. Suggested order
(cheapest, most foundational first):

| Surface | macOS reference | Notes |
|---|---|---|
| **Shell chrome** | `Window.swift` (body3Pane), `Chrome.swift` | 3-pane: sidebar · content · inspector, resizable panes, panel cards. `NavigationView`/custom `Grid` + `GridSplitter`. |
| **Grammar kit** | `RowKit.swift` | The shared row/card/chip controls. Do first. |
| **Inspector** | `Inspector.swift` | The V3 property inspector (digit-jump, editors, MORE). Shared right pane. |
| **Editor** | `Editor.swift` | Rich-text over the span model (`RichText`/`Block`/`Marks`); markdown as an input convention. The biggest single control. |
| **Tasks** | `Window.swift` TasksView | List / Board / Schedule / Cards lenses; drag = `set(status)`. |
| **Calendar** | `Calendar.swift` | Month/Week/Day; `snapshot_window` for occurrences; day panel + daily-note footer. |
| **Search** | `Window.swift` SearchPopup | The one filter engine (⌘F → Ctrl+F). |
| **Lists / Inbox / Contacts / Library** | respective views | Thinner surfaces over the kit. |
| **Import / Export** | (P15 — services shipped, surfaces pending) | Coordinate: the macOS surfaces aren't built yet either. |

Keybindings: translate ⌘ → Ctrl, ⌥ → Alt (e.g. ⌘F → Ctrl+F, ⌘⌥D → Ctrl+Alt+D).

## 4 · Project setup (`shell/windows/`)

- A **WinUI 3** app (Windows App SDK 1.x), C#/.NET 8, `CommunityToolkit.Mvvm`,
  `System.Text.Json`, `csbindgen` (build-time bindings). x64 + Arm64.
- Suggested layout: `shell/windows/Lotus/` (the app), `.../Interop/` (P/Invoke +
  snapshot models), `.../Controls/` (the grammar kit), `.../Surfaces/` (one per
  surface), `.../Theme/` (the token ResourceDictionary).
- A build step runs `cargo build -p lotus-ffi --target …-msvc` and copies the DLL.
- CI later: a Windows runner building the DLL + the .NET app; the existing
  `cargo test` stays the core's gate on every platform.

## 5 · What NOT to do (recap of the guardrails)

- Don't change `core`/`services`/`views` behavior — if a snapshot lacks data the
  UI needs, the fix is almost always in the shell (decode/render), not the core.
- Don't edit `shell/macos/**`.
- Don't rename `lotus` code identifiers — the product is branded **Liv**, but
  `lotus` is the codename (crates, paths, `lotus_*`, DLL, box path). Only the
  app's *display* name / user-facing strings say "Liv".
- FFI additions: additive only, mirror `with_box` + `Committed`, ship a test,
  flag in the PR. Prefer reusing a verb.
- Land by PR on a `windows-port` branch so the owner reviews the boundary.
