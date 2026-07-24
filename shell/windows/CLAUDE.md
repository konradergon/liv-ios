# Windows Shell — CLAUDE.md

You are building **shell/windows/**: the **WinUI 3 (C#/.NET)** native shell for **Liv**, a productivity app. This file is your standing brief — read it fully before you touch anything. For the project overview read the **root `CLAUDE.md`**; for the high-level port plan read **`design/windows-port.md`**. This file is the detailed, actionable seam.

---

## 1. Mission

Build the Windows shell of **Liv** as a **WinUI 3 app in C#/.NET 8** that P/Invokes the **shared Rust core** through its C ABI (`liv_ffi.dll`) and reproduces the existing **macOS SwiftUI shell 1:1** — same layouts, same density, same interactions, same keybindings (Cmd→Ctrl, Opt→Alt) — recolored only into the **liv palette** (accent is **lake green `#2F7D6B`**, never the OS accent). One core, many shells: you write **only** the presentation layer. Every piece of behavior — data model, recurrence, search, triage, undo — already lives in the core and is reached through FFI verbs. The prime directive: **copy the macOS shell exactly; do not invent UI, do not redesign, do not change core behavior.** When density or layout is ambiguous, the macOS Swift source is the ground truth — mirror it.

---

## 2. Hard rules (read first)

### Boundary zones
- **You OWN `shell/windows/`.** Create, edit, restructure freely here.
- **READ-ONLY reference — never edit:** `core/`, `services/`, `views/`, `ffi/`, and **`shell/macos/`**. You read these to learn the contract and to mirror behavior. You do not modify a single line.
- **Never touch `shell/macos/`.** It is the reference implementation. If your change "requires" a Swift edit, you are doing it wrong — stop.
- **Never leave the repo.** Do not reach into other directories on the machine, install global state beyond documented SDKs, or exfiltrate anything.

### FFI is additive-only, and gated
- The C ABI in `ffi/src/lib.rs` is the whole seam. You may **not** change existing verb signatures or behavior.
- If a port genuinely needs a new verb, that is a **core-team change, not yours**: **STOP and ask the owner.** Do not edit `ffi/` yourself. Any new verb must be **purely additive** (new symbol, never a change to an existing one) and land behind the owner's review.

### Naming
- The product and the code are both **Liv**: crates are `liv-*`, the FFI
  symbols are `liv_*`, the cdylib is `liv_ffi.dll`. (The former codename
  `lotus` was renamed away on 2026-07-22; historical design docs still say
  `lotus_*` — read them as `liv_*`. Never reintroduce `lotus` into code.)

### Git workflow
- Work on a **`windows-port`** branch. **Never commit to `main`. Never push without the owner explicitly asking.**
- Land work by **PR**. Keep PRs scoped to one surface / one coherent unit.
- **Run `cargo test` before every PR** (you consume the core; prove you didn't build against a broken tree) and build the WinUI app.
- Commit messages: end with the `Co-Authored-By` trailer per the repo convention.

### The escape hatch
> **When a task seems to need something outside `shell/windows/` — a core behavior change, a new FFI verb, a Swift edit, a schema change — STOP and ask the owner.** Do not work around it by editing read-only zones.

---

## 3. Architecture in 60 seconds

```
                       ┌───────────────────────────┐
                       │      Rust core (shared)     │
                       │  core / services / views    │
                       │        append-only log       │
                       └─────────────┬───────────────┘
                                     │  C ABI (liv_ffi)
                 ┌───────────────────┼────────────────────┐
                 │                   │                     │
        ┌────────┴────────┐  ┌───────┴────────┐   ┌────────┴────────┐
        │ shell/macos     │  │ shell/windows   │   │  (future shells) │
        │ SwiftUI (ref)   │  │ WinUI3 (YOU)    │   │                  │
        └─────────────────┘  └────────────────┘   └──────────────────┘
```

- **The shell holds no data model.** It holds a *snapshot* (read model) and posts *verbs* (writes).
- **To read:** call `liv_snapshot(path)` → a JSON `Snapshot` → decode into your row model. Re-snapshot after every write. There is **no incremental update**.
- **To mutate:** call a verb (`liv_set_at`, `liv_create_task_at`, …), check the return, then **`refresh()`** (re-snapshot). A *refused* write (returns `0`/`-1`) changed nothing — **do not refresh** on refusal.
- **Every call is open→act→close.** The shell never holds the box. The only state you pass across calls is the box `path` (a `const char*`).

---

## 4. Bootstrap — do these in order

### 4.1 Prerequisites
```bash
# Rust toolchain + the Windows MSVC target
rustup target add x86_64-pc-windows-msvc

# .NET 8 SDK  (dotnet --version → 8.x)
# Visual Studio 2022 with the ".NET Desktop" + "Windows App SDK / WinUI" workloads,
#   or the standalone Windows App SDK + WinUI 3 project templates.
```

### 4.2 Build the core DLL and place it next to the app
```bash
# From the repo root — builds cdylib liv_ffi.dll
cargo build --release -p liv-ffi --target x86_64-pc-windows-msvc
# Output: target/x86_64-pc-windows-msvc/release/liv_ffi.dll
```
Copy `liv_ffi.dll` into the WinUI app's output directory (add a post-build copy step / MSBuild `<Content>` item so it ships beside the `.exe`). The P/Invoke `DllImport("liv_ffi")` resolves it from there.

### 4.3 Scaffold the WinUI 3 project under `shell/windows/`
Suggested layout:
```
shell/windows/
  CLAUDE.md                 (this file)
  Liv.Windows.sln
  src/
    Interop/                 P/Invoke bridge (LivFfi.cs), string marshaling, free discipline
    Model/                   BoxModel, snapshot decode records, row types
    Design/                  Tokens.xaml (ThemeDictionaries), Hues.cs, KindIcons
    Controls/                RowKit UserControls: ValueChip, StatusDot, ObjectRow, ObjectCard, ObjectTile, SoftBadge, KbdChip, LensHeader…
    Chrome/                  Window, body3Pane grid, PaneDivider, SurfaceNav, ChromeModel, command dispatcher, nav history
    Surfaces/                Notes, Tasks, Calendar, Lists, Inbox, Contacts, Library, Search
    Inspector/               InspectorPane + editors + digit grammar + history
    Spaces/                  workspace tree
    Editor/                  the rich-text editor (LAST)
  assets/
    liv_ffi.dll            (copied post-build; do not commit binaries unless owner asks)
```

### 4.4 Wire the P/Invoke bridge
- Prefer **`csbindgen`** (generates C# P/Invoke from the Rust FFI) to stay in sync automatically. Otherwise hand-write from **§5** — **not** from `shell/macos/liv.h`, which is stale (see §5 header-drift note).
- **String IN:** UTF-8, NUL-terminated. Marshal with `[MarshalAs(UnmanagedType.LPUTF8Str)]` (never default ANSI/UTF-16).
- **String OUT:** declare the return as `IntPtr`; `Marshal.PtrToStringUTF8(ptr)`; then **`liv_string_free(ptr)` in a `finally`, exactly once**. Never `free()` yourself, never double-free. `NULL` return = box unavailable → skip the free (it's null-safe anyway).

### 4.5 BoxModel — the single-writer worker
- All FFI calls run **off the UI thread on one serial worker** (a `Channel`/`SemaphoreSlim`-guarded queue). **Never `Task.Run` fan-out** — the box admits one writer; concurrent calls just get the "busy" sentinel.
- Marshal results back with `DispatcherQueue.TryEnqueue`.
- After a successful write verb, call **`refresh()`** = re-snapshot on the worker, decode, publish to observable state. On a refused write, do **not** refresh.
- Prove the seam first: call `liv_probe(path)` (null = healthy) then `liv_snapshot(path)` and decode.

### 4.6 Decode the snapshot with nullable fields
- `System.Text.Json`, `PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower`.
- **THE LOAD-BEARING RULE:** model **every** optional / conditionally-emitted field as **nullable**. One unexpected-missing non-nullable key throws → the whole `Snapshot` decode fails → the window silently freezes on stale data (this exactly mirrors the macOS `try? decode`). See §6.

### 4.7 Then, in order
1. Drop in the **token `ResourceDictionary`** (§7) with Light/Dark ThemeDictionaries.
2. Build the **grammar-kit UserControls FIRST** (§7) — every surface reuses them.
3. Port surfaces in the **recommended build order** (§8).

---

## 5. FFI reference — `liv_ffi` C ABI

**36 verbs.** All are `extern "C"`; the cdylib exports them as plain C functions. All `*_at(path, …)` take the box path (UTF-8 `const char*`) first.

> **Header drift — do NOT trust `shell/macos/liv.h`.** It is missing two verbs that exist in `ffi/src/lib.rs`: **`liv_import_batch_at`** and **`liv_export_at`**. Declare your P/Invokes from *this* table, not from `liv.h`.

### Calling conventions (structural — hold for the whole seam)
1. **Strings in** — UTF-8, NUL-terminated. A null/invalid pointer makes the call return its failure value, never crash.
2. **Strings out** — heap `char*` you must copy then free with `liv_string_free` exactly once. `NULL` = box unavailable / failure (never free-required).
3. **`with_box` pattern** — every verb opens the log, `try_lock`s, runs one txn/read, drops the lock (ms). No session handle. `path` is the only state.
4. **Busy box** — if another writer holds the box, the verb returns its busy sentinel **immediately, no wait**: `0` (id/count/bool), `null` (`char*`), `-1` (i64 batch). Call `liv_probe` to learn *why*.
5. **Return conventions:**
   - `uint64_t` (create/capture): new id, or **`0`** on any failure (`0` is never a valid id).
   - `int32_t` (mutate): **`1` ok / `0` fail-or-busy**; a few use **`-1`** as a distinct third state.
   - `int64_t` (batch): a count **≥0**, or **`-1`** on parse/box/IO error.
   - `char*`: JSON / string, or **`NULL`** on failure.

### Group 1 — Reads (return `char*` JSON; never mutate)
| Verb | Signature | Purpose |
|---|---|---|
| `liv_snapshot` | `(path) -> char*` | Whole window as `Snapshot`. Occurrence window = current civil month. **Every refresh.** |
| `liv_snapshot_window_at` | `(path, from_civil:i64, to_civil:i64) -> char*` | Same `Snapshot`, but `occurrences` expanded over `[from,to]` (civil `YYYYMMDDHHMM`). Calendar uses this off the current month. Engine caps ~366 days. `dated` unchanged. |
| `liv_content_at` | `(path, id) -> char*` | One entity's editable content (`ContentDoc`: `spans`, `fingerprint`, `missing`). Editor load. |
| `liv_content_history_at` | `(path, id) -> char*` | Content versions, newest first. |
| `liv_search_at` | `(path, raw_query) -> char*` | Parsed DSL search: `{hits, facets, total}`. Debounced. Shell never re-parses the DSL. |
| `liv_distinct_values_at` | `(path, property) -> char*` | Distinct live values + counts, for pickers. |
| `liv_status_options_at` | `(path, kind) -> char*` | Status vocabulary for a kind, board-sorted. |
| `liv_extracted_text_at` | `(path, id) -> char*` | File entity's extracted plain text (read-only preview). NUL bytes → U+FFFD. |
| `liv_probe` | `(path) -> char*` | Why the box won't open: `{code,message}`; **`NULL` when it opens fine.** Codes: `locked`/`corrupt`/`version`/`io`. |

`liv_snapshot` is byte-identical to `liv_snapshot_window_at` with the current month's bounds. There is **no** symbol named `liv_snapshot_at`.

### Group 2 — Create verbs (return `uint64_t` new id, `0` on failure)
| Verb | Signature | Births |
|---|---|---|
| `liv_capture_at` | `(path, text) -> u64` | One untyped scrap (menu-bar capture). Whitespace-only → `0`. |
| `liv_create_note_at` | `(path) -> u64` | note + created. |
| `liv_create_task_at` | `(path) -> u64` | task + status:todo + created. |
| `liv_create_event_at` | `(path, due_civil:i64, date_only:i32) -> u64` | event + due (all-day when `date_only!=0`). |
| `liv_create_list_at` | `(path, name) -> u64` | list + name. |
| `liv_create_workspace_at` | `(path, name, parent:u64) -> u64` | workspace (+ parent; `0`=top level). Empty name → `0`. |
| `liv_open_daily_note_at` | `(path, date_civil:i64, workspace:u64) -> u64` | **Get-or-create** daily note for (day, workspace). Idempotent. `workspace==0`=global. |
| `liv_add_file_at` | `(path, file_path) -> u64` | Hash bytes, create `file` entity. Never moves/copies the file. `0` on unreadable. |
| `liv_add_status_option_at` | `(path, kind, name, hue:double) -> u64` | New status option (ordered last). `hue<0`=none. |
| `liv_add_property_at` | `(path, name, kind) -> u64` | New property definition. `0` on empty/duplicate name or unknown kind. |

### Group 3 — Mutate verbs (`int32_t`: `1` ok / `0` fail-busy; some `-1`)
| Verb | Signature | Notes |
|---|---|---|
| `liv_set_at` | `(path, id, property, value) -> i32` | Replace all cells of one property. **Unknown property name refuses** → `0`; birth it first. Checkbox/rename/status/priority. |
| `liv_unset_at` | `(path, id, property) -> i32` | Remove every cell of a property. Absent = success. |
| `liv_add_cell_at` | `(path, id, property, value) -> i32` | Add exactly one cell (multi-valued, e.g. list membership `("related","#<id>")`). Already-present = no-op `1`. |
| `liv_remove_cell_at` | `(path, id, property, value) -> i32` | Remove one cell. Never deletes the referenced entity. Absent = no-op `1`. |
| `liv_set_type_at` | `(path, id, type_name) -> i32` | Stamp the TYPE by name (Inbox Route). |
| `liv_set_span_at` | `(path, id, property, start_civil:i64, end_civil:i64, date_only:i32) -> i32` | One-command date/span write. `end==0`=plain date; end not strictly after start → refused `0`. |
| `liv_cycle_date_role_at` | `(path, id, property) -> char*` | Space-cycle a date row's role (due→date→valid-until→occurred→purchased-on→due). Returns **new property name** (`char*`, free it) or `NULL`. *(char* return, but a mutate.)* |
| `liv_set_content_at` | `(path, id, spans_json, base_fp:u64, out fresh_fp:u64*) -> i32` | Editor save. Empty array removes content. **`1` saved / `-1` stale / `0` busy-invalid.** `fresh_fp` may be null; pass `out ulong`/`ref ulong`/`IntPtr`. |
| `liv_resync_file_at` | `(path, id) -> i32` | Re-hash a file. **`1` changed / `0` unchanged / `-1` broken reference.** |
| `liv_trash_at` | `(path, id) -> i32` | Soft, reversible trash. |
| `liv_trash_workspace_at` | `(path, id) -> i32` | Trash one workspace, no cascade. |

### Group 4 — Triage & undo (`int32_t`)
| Verb | Signature | Notes |
|---|---|---|
| `liv_accept_at` | `(path, entity, ordinal:u32, fingerprint:u64) -> i32` | Accept clerk proposal (all three from snapshot `inbox`). Fingerprint must still match or refuse `0`. |
| `liv_reject_at` | `(path, entity, ordinal:u32, fingerprint:u64) -> i32` | Decline (remembered forever). |
| `liv_undo_at` | `(path) -> i32` | Undo last committed transaction. A decline is not a transaction. |

### Group 5 — Import / export (`int64_t` count, `-1` on error) — NOT in `liv.h`
| Verb | Signature | Notes |
|---|---|---|
| `liv_import_batch_at` | `(path, items_json, stamps_json) -> i64` | One txn/one undo. `items_json` = tagged `ImportItem`s (`link`/`file`/`note`/`scrap`). `stamps_json` = `[[prop:u64, target:u64],…]` (may be null; **malformed non-null = `-1`**). Returns count committed (deduped by external-id), or `-1`. |
| `liv_export_at` | `(path, ids_json, group_props_json, dest) -> i64` | **Copy-only** projection (log untouched). `ids_json`=`[u64,…]`; `group_props_json`=`[u64,…]` (≤2, may be null); `dest`=folder outside the box. Count written, or `-1`. |

### Group 6 — Memory / util
| Verb | Signature | Notes |
|---|---|---|
| `liv_string_free` | `(char* s) -> void` | Free any `char*` returned by a JSON/string verb. Null-safe; **free each pointer at most once.** Every `char*`-return wrapper must call this in a `finally` after copying. |

---

## 6. Snapshot / model shapes

**Global rules.** Wire keys are exactly the Rust snake_case field names (no serde renames anywhere). `Id` is `u64` → **`ulong`** (`0` = none), serialized as a bare number. **Every optional or conditionally-emitted field MUST be nullable in C#** — a single unexpected-missing non-nullable key fails the whole decode and freezes the window on stale data. Two "optional" flavors, both → nullable C#:
- Rust `Option<T>` always serialized → emits `null`.
- Rust `#[serde(skip_serializing_if …)]` → key **absent entirely**.

### `Snapshot` (top-level read)
Nine arrays, always present (never `null`, possibly `[]`):
| key | type | notes |
|---|---|---|
| `today`,`unstructured`,`everything`,`dated` | `[ulong]` | entity ids (lists are id arrays; you hold the entity pool and resolve locally) |
| `occurrences` | `[OccurrenceRow]` | recurrence expansion over the window |
| `inbox` | `[ProposalRow]` | pending proposals |
| `workspaces` | `[WorkspaceRow]` | full tree, archived included |
| `properties` | `[PropertyRow]` | inspector catalog |
| `entities` | `[EntityRow]` | one row per id in `everything` |

### `EntityRow`
`id:ulong`, `title:string`, `kinds:[string]`, `due:long?` (nullable, packed civil positioning date), `due_end:long?` (**absent** when none), `positioned_by:string?` (**absent** when none), `due_date_only:bool`, `status:string?` (nullable), `created:long?` (nullable), `trashed:bool`, `bookmarked:bool`, `archived:bool`, `content_print:ulong` (fingerprint, `0`=none — **`ulong`, never `long`**), `cells:[CellRow]`.

### `CellRow`
`property_id:ulong`, `property:string`, `kind:string` (`text`/`number`/`bool`/`datetime`/`select`/`reference`/`richtext`/`file`; **empty string** when no kind), `value:string` (the **display** string — see grammar below, not the raw value), `ref_target:ulong?` (nullable; the referenced id for select/reference — prefer this over parsing `value` when editing).

### `PropertyRow`
`id:ulong`, `name:string`, `kind:string`, `options:[OptionRow]`, `usage:int`, `icon:string?` (absent-when-none), `digit_key:string?` (absent), `hide_when_empty:bool?` (absent), `hide_on_kinds:[string]?` (absent-when-empty), `core_on_kinds:[string]?` (absent-when-empty).

### `OptionRow`
`id:ulong`, `name:string`, `order:double` (make it `double?` defensively), `hue:double?` (nullable, 0–360 degrees), `completes:bool` (terminal), `for_types:[string]` (`[]` = offered everywhere).

### `OccurrenceRow`
`series:ulong`, `civil:long` (packed civil day).

### `ProposalRow`
`entity:ulong`, `ordinal:uint` (1-based), `fingerprint:ulong` (**`ulong` — routinely exceeds Int64.MaxValue**; must be presented back on accept/reject), `reason:string`, `author:string` (a proposer / `"user"` / `"system"`).

### `WorkspaceRow`
`id:ulong`, `name:string`, `emoji:string?` (nullable), `favorite:bool`, `archived:bool`, `builtin:string` (`"home"` for the protected one, else empty), `parent:ulong` (`0`=top level), `order:double` (rows arrive pre-sorted).

### The `value` display-string grammar (what `CellRow.value` contains)
Pre-rendered by `liv_views::display`. Parse/recognize exactly:
- **Text** → verbatim. **RichText** → flattened plain text, paragraph breaks → single spaces.
- **Number** → Rust default `f64` (`3`, `3.5`).
- **Bool** → literally `"yes"` / `"no"` (NOT true/false).
- **DateTime** → date-only `"YYYY-MM-DD"`; with time `"YYYY-MM-DD HH:MM"`; span `"<start> -> <end>"` (display and parse are one grammar — writing it back is lossless).
- **Select/Reference** → target's `name`, else `#<id>`, else `#<id>!` (broken/missing). Prefer `ref_target` when editing.
- **File** → the file's `path`.

### Content / span model (for the editor only)
`liv_content_at` → **`ContentDoc`**: `id:ulong`, `name:string?`, `trashed:bool`, `missing:bool` (true = box opened but no such entity; distinct from a `NULL` return = box unavailable), `fingerprint:ulong` (present it back on save), `spans:[Span]`.
`liv_content_history_at` → `[ContentVersionRow]`: `seq:ulong`, `time:long`, `author:string`, `label:string`, `spans:[Span]`.

**`Span`** is serde's **externally-tagged enum** — `{"<Variant>": payload}`. These are enum variant names, **not** snake_case-affected:
- **`Text`** — polymorphic: an **unmarked** run is a bare string `{"Text":"hello"}`; a **marked** run is `{"Text":{"text":"bold code","marks":5}}`. Your C# converter must accept both (untagged `Bare(string)` | `Full{text,marks}`).
- **`Break(Block)`** — a paragraph boundary that **types the paragraph that FOLLOWS**: `{"Break": <Block>}`.
- **`Ref(Id)`** — inline entity pill: `{"Ref": 7}` (the only span contributing a backlink).

The span list read left-to-right **is** the document; `Break` is the only structure; a `Text` never contains a newline.

**`Block`** (externally-tagged; unit variants = bare strings): `"Body"`, `{"Heading":1}` (1–6), `"Quote"`, `{"Bullet":{"depth":0}}`, `{"Ordered":{"depth":0}}`, `{"Task":{"depth":0,"done":false}}`, `{"Code":{"lang":null}}` (lang nullable), `{"Callout":{"kind":"note"}}`, `"Rule"`.

**`Marks`** = raw `u8` bitfield: `BOLD=1`, `ITALIC=2`, `CODE=4`, `STRIKE=8` (OR-combined; bold+code=5). OR marks order-independently so fingerprints stay deterministic.

**`DateTime`** packing (`civil` = `((year*10000+month*100+day)*10000)+hour*100+minute` as `i64`; `date_only:bool`; `end:long?` — absent on pre-P11, a second civil strictly after `civil`; `end==start` is never stored).

### C# numeric cheat-sheet
`Id`/`u64` ids → `ulong` (`ulong?` where Option); **u64 fingerprints (`content_print`, `fingerprint`) → `ulong` (never `long`)**; i64 packed civil (`due`, `due_end`, `created`, `civil`, `time`) → `long`; `u32` (`ordinal`) → `uint`; `usize` (`usage`) → `int`; `f64` (`order`, `hue`) → `double`; `u8` (`marks`, `depth`, heading level) → `byte`/`int`.

---

## 7. Design system

Recreate as a WinUI `ResourceDictionary` with **Light/Dark ThemeDictionaries**. The accent goes in **both** dictionaries with the **same** value. **Accent is always lake green `#2F7D6B` — never the WinUI system accent.**

### Accent (mode-independent)
| Token | Hex | Use |
|---|---|---|
| `accent` / `primary` | **`#2F7D6B`** | THE accent, both modes |
| `accentDeep` | **`#276456`** | pressed/deep |
| `accentTint` | `#2F7D6B` @ **12%** | selection fill |

Lake green appears in exactly three jobs: selection, the one inbox badge, key affordances.

### Semantic tokens (light / dark)
| Token | Light | Dark | Role |
|---|---|---|---|
| `background` | `#FFFFFF` | `#1F1F1F` | page/editor |
| `foreground` | `#202124` | `#E8EAED` | primary ink |
| `surface1` | `#FFFFFF` | `#2D2E30` | cards |
| `surface2` | `#F1F3F4` | `#1B1B1B` | recessed |
| `popover` | `#FFFFFF` | `#292A2D` | menus/floaters (shadowed) |
| `panel` | `#F1F3F4` | `#1B1B1B` | sidebar/chrome |
| `secondary` | `#E6E8EA` | `#42474C` | neutral chip/keycap fills |
| `mutedFg` | `#4D5155` | `#B1B7BD` | secondary text, kind icons, timestamps |
| `border` | `#C2C6CC` | `#51565C` | hairlines, strokes, grid dividers |
| `destructive` | `#D93025` | `#F28B82` | delete/error |
| `warning` (amber) | `#E37400` | `#FDD663` | **reserved app-wide for AI presence only** |

Elevation is **tonal, not shadowed** (chrome darkest → page → cards lightest); shadows only for floaters.

### Radii & geometry
`radiusSm 4`, `radiusMd 6` (rows/small controls), `radius 8` (cards/default), `radiusXl 12` (panels). Chips/badges/keycaps are **pill/Capsule** (KbdChip r≈5.6). `railWidth 44`, `headerBandHeight 40`. **`trafficLightSpacer 72` is macOS-only — do NOT blindly reserve 72px on the left**; repurpose as a leading chrome inset for the caption buttons or drop it.

### Motion
Signature spring `cubic-bezier(0.32, 0.72, 0, 1)`: `spring 0.20s`, `springFast 0.14s`, `glide 0.32s`. WinUI: `KeySpline "0.32,0.72 0,1"` on storyboards. Settles, never overshoots.

### Value hues — reproduce **bit-exactly**
> **A hue ALWAYS means a metadata VALUE.** This is the single most important visual rule.

**Never-hue classes** render neutral (pass `hue: nil`): **dates/timestamps, recurrence, tier/priority** (tier = an accent **flag** icon, not a hue), **type/kind** (an **icon**, never a color), **objects/rows**. **Status** is the exception — its dot is colored by the option's own `hue` cell **in degrees** (not the value palette); `nil` hue → neutral.

**Value-hue palette (VALUE_HEX)** — 9 frozen seeds, index = **FNV-1a 64 hash mod 9**:
| # | hex | # | hex | # | hex |
|---|---|---|---|---|---|
| 0 | `#F43F5E` rose | 3 | `#8B5CF6` violet | 6 | `#3B82F6` blue |
| 1 | `#F59E0B` amber | 4 | `#F97316` orange | 7 | `#84CC16` lime |
| 2 | `#0EA5E9` sky | 5 | `#06B6D4` cyan | 8 | `#EC4899` pink |

**Hash:** FNV-1a 64 over the **NFC-normalized** (`string.Normalize(NormalizationForm.FormC)`) UTF-8 bytes of the display string exactly (no case-fold, no trim). Offset basis `0xCBF29CE484222325`, prime `0x100000001B3`, `unchecked` `ulong` arithmetic, `index = hash % 9`. **Frozen verification vectors — assert these in a test:** `"SSK"→5`, `"thesis"→7`, `"climbing"→0`, `"invoices"→2`, `"Steven"→5`, `"warranty"→1`, `"tournament"→6`, `"Anna"→0`, `"physics"→3`, `""→5`.

**Chip color mixes** on a seed H: **bg** = H @ 12% (light) / 16% (dark); **border** = H @ 32% (both); **ink** = H blended 62% (light) / 55% (dark) with theme label ink. **Neutral variant** (`hue==nil`): ink = secondaryLabel, bg = secondary @ 10%, border = secondary @ 30%. **Status-dot degree color:** HSB `hue=((deg%360)+360)%360/360`, `sat 0.55/0.45`, `bright 0.62/0.75`. **Override ladder:** per-option `hue` cell wins → else VALUE_HEX of the display string → else the caller renders neutral.

### Grammar-kit components — build these FIRST (as UserControls / DataTemplates)
Font sizes are SwiftUI pt ≈ CSS px. Row heights come from content + padding — **reproduce via padding, no hardcoded height.**

- **`ValueChip`** — THE chip. Capsule, H-pad 7 / V-pad 1.5, border 0.5px. Content (HStack spacing 4): optional 7×7 dot → optional 9.5px icon → 11px text, 1 line. Hue set → scheme-aware mixes; `nil` → neutral (dates/recurrence/tier **required** to pass nil). If `tap` set, the chip is its **own click target** — clicking filters, never selects the row. Tooltip = the filter it applies.
- **`StatusDot`** — 8×8. **Ring** (1.5px) while open-ish, **filled** when the option `completes`. Color = option `hue` via degrees; `nil` → tertiary neutral. Tap filters by status; expand the hit area. Render nothing if the row has no status.
- **`StatusChip`** — search variant: a neutral-framed `ValueChip` carrying the degree-colored dot + option name.
- **`Anchor` / `anchorChip`** — the ONE anchor per row: precedence **project → first subjects → people → role-date (`due`)**. First three are VALUE_HEX-hued with a click-filter; the **role-date leg is NEUTRAL, no filter** and suppresses the row's own trailing date. At most one anchor per row.
- **`ObjectRow`** (the BP7 standard list row) — HStack spacing 9, pad V7/H6 → ~32–34px. Left→right, **empty fields never render**: kind icon @13px (mutedFg) OR an interactive 15×15 checkbox (accent-filled + white check when done) when `toggle` is supplied · title @13px 1-line (done → secondary + strikethrough) · `Spacer(min 8)` · optional trailing · exactly one anchor chip · `StatusDot` (only if status ≠ null) · trailing timestamp @11px mono-digit secondary@80% — **hidden on hover, replaced by an ↗ open button.** Selection = `accentTint` bg + **2.5px accent inset bar** on the leading edge. **Manual double-tap:** first tap selects immediately, second tap within the system double-click interval opens. Don't use a real DoubleTapped handler (it stalls single-select); track last-tap time yourself.
- **`ObjectCard`** — gallery card. VStack pad 10, radius 8 border 0.5px, **no status dot**. Icon+title @12.5px medium, optional 2-line description clamp, ≤3 `ValueChip`s + "+N".
- **`ObjectTile`** — tightest; **no status parameter exists by construction** (the board column carries state). VStack pad 9, title @12px 2-line, chip row: person (VALUE_HEX) · date (neutral) · tier (neutral flag).
- **`LensHeader`** — title @21px bold · Spacer · subtitle @13px secondary, pad-bottom 18. `SectionLabel`: uppercase 11px semibold, kerning 0.5, secondary.
- **`SoftBadge`** — pill, min-w 20, 10.4px semibold mono-digit, primary ink on primary@14% bg, `99+` cap (the inbox count — the only badge). **`WarningBadge`** — same geometry, amber ink on warning@14% (AI-presence). **`KbdChip`** — mono keycap 10.5px mutedFg, r≈5.6, secondary@60% fill, 1px border with a 2px bottom edge.

Map SF Symbols → **Segoe Fluent Icons** (or bundled glyphs) via one `KindIcon` lookup table: task/event/person/project/list/file/note.

---

## 8. Surface port checklist

Decode with snake_case; every optional field nullable. Each verb runs on the single-writer worker; refresh after successful writes.

### Chrome / shell (`Chrome.swift`, `Window.swift` WindowChrome/body3Pane; `main.swift`)
- **Window** — 1100×740 default, min 980×620, `ExtendsContentIntoTitleBar=true`, custom drag regions via `SetTitleBar`/`InputNonClientPointerSource`. Caption-button inset replaces the 72px spacer.
- **body3Pane** — `sidebar | content | inspector` as a proportional `Grid`; store `leftPct`/`rightPct` (clamp left∈[8,55], right∈[8,48], center ≥30%), recompute on `SizeChanged`. **`PaneDivider`** 7px handles: left resizes only; right is **collapsible by drag** (past `minPct/2` → `rightOpen=false`, persist immediately). Reproduce the clamp math exactly.
- **ChromeModel** — persist to `ApplicationData.LocalSettings`: `surface`, `leftPct/rightPct`, `leftOpen/rightOpen`, `focusMode`, `isFullscreen`, `activeWorkspace`, `switcherOpen`, `searchOpen`, `pinnedProject`. `reconcilePanes()` at launch.
- **Sidebar** — persistent (hides only on manual collapse / focus). Header (collapse + search over the caption band, Back/Forward chevrons), **SurfaceNav** rows for `Surface.allCases` = **notes, ai-chat("Chats"), tasks, lists, library, inbox, contacts, calendar** (each = icon + label + optional `SoftBadge`; Inbox badge = orphans + inbox count; active = accent icon, semibold, primary@10% bg), **WorkspaceFooter** (workspace button → HomeHubPopover upward, appearance toggle, settings gear). Hand-rolled ListView matches the look better than `NavigationView`.
- **Focus mode** — stash `(leftOpen,rightOpen)`, hide panes + chrome, show "Exit focus" chip; Esc exits (only when focus on and no editor/dialog).
- **Nav history** — one merged `(surface, selection)` stack: consecutive-dedup, forward-truncation, replay-guarded, cap 200. Center surface swap keyed so it fully rebuilds.
- **Command dispatcher** — ONE global `CoreWindow.KeyDown` dispatcher, insertion-order precedence; bare keys suppressed while a text control has focus; a capture-scope allow-list (inspector digit grammar) suppresses everything else; overlays/dialogs swallow the map. **Do NOT use per-control `KeyboardAccelerator`s for the global set** (double-fire). **Match digits/punctuation by `VirtualKey`, not character** (layout-safe). Keybindings **Cmd→Ctrl, Opt→Alt** (see table below).

### Surfaces (build order & risk)
| # | Surface | macOS ref | FFI verbs | WinUI approach / notes |
|---|---|---|---|---|
| 1 | **FFI + BoxModel** | `main.swift`, `Window.swift` | `probe`, `snapshot`, `string_free` | Single-writer worker + refresh loop + decode. Everything depends on it — **test-drive it.** |
| 2 | **Tokens + RowKit** | `Tokens/Hues/RowKit.swift` | — | §7. The shared vocabulary. Verify the 9 hue vectors. |
| 3 | **Chrome shell** | `Chrome.swift`, `Window.swift` | `snapshot` | Grid + PaneDivider + persistence + SurfaceNav + command dispatcher. **Risk #4.** |
| 4 | **Contacts / Everything** | `ContactsView :2145`, `EverythingView :2523` | `snapshot` | Cheapest real surface: `ObjectRow` list + selection→Inspector. Proves RowKit. |
| 5 | **Inspector** | `Inspector*.swift` (~2470 ln) | `set_at`, `unset_at`, `add_cell`, `remove_cell`, `set_span_at`, `cycle_date_role_at`, `add_property_at`, `add_status_option_at`, `status_options_at`, `distinct_values_at`, `content_history_at`, `trash_at` | `ScrollViewer` + property rows; editors as anchored `Flyout`s. **Digit-jump grammar** (1–0 jump fields; N/M/H/D/P/R actions; F2 rename; ↑↓ move; Return edit; Esc close/leave; Alt+←/→) under a **capture scope**. Reused by Calendar + every list. |
| 6 | **Tasks** | `TasksView :3692` | `create_task`, `set_at`, `unset_at`, `add_status_option` | Four lenses (Ctrl+1–4): **List** (status-grouped, board-order, quick-add), **Schedule** (client-side bucket by `due`), **Cards** (`ObjectCard` adaptive grid), then **Board** (**Risk #3** — horizontal status columns; `ItemsRepeater`/`GridView` in an h-`ScrollViewer`; cross-column drag writes status via `"task:<id>"` payload + accent drop highlight; terminal columns fold; "+ New status" column). Done-ness = option's `completes`. |
| 7 | **Lists** | `ListsSurface :4226` | `create_list`, `remove_cell` | Index of `type=list`; open → ordered `related` members as read-only rows with hover-× (un-tags, never deletes). |
| 8 | **Inbox** | `InboxView :2249` | `set_type`, `accept_at`, `reject_at` | Two lenses: **Route** (orphans → `set_type` to classify) and **Tidy** (`snap.inbox` proposals → accept/reject with fingerprint). Feeds the SurfaceNav badge. |
| 9 | **Library** | `LibraryView :3624`, `BaseFileView :3511` | `add_file_at`, `resync_file_at`, `extracted_text_at` | `FileOpenPicker` (needs `WinRT.Interop` HWND init). Files are **read-only by law** — never open in the editor. |
| 10 | **Search** | `SearchPopup :2933` | `search_at` | A centered light-dismiss `Popup`/`ContentDialog` (not an in-place lens). Debounced `search_at`; render ranked `hits` (resolve ids locally), **facets** with live counts, removable query pills, `total`. Chip-clicks elsewhere seed it. |
| 11 | **Spaces tree** | `Spaces.swift` (1485 ln) | `create_workspace_at`, `trash_workspace_at` | `TreeView` (built-in drag-reorder). **Risk #6:** reproduce re-root + leaf-reorder DropDelegate semantics + inline rename. WorkspaceSwitcher (Ctrl+Shift+O modal), HomeHubPopover. |
| 12 | **Tabs + Notes scaffold** | `Tabs.swift`, `Window.swift notesBody :1317` | `create_note_at`, `open_daily_note_at` | `TabView` — but force **equal widths**, hide the strip at 1 tab, route double-click→rename, persist per-workspace to LocalSettings. Tab kinds: `desk` (Today/Everything/Capture via `Lens`), `blank` landing, `note(id)`, `file(id)`. Today IS the daily note (`open_daily_note_at`, ⌘⌥D→Ctrl+Alt+D, per-workspace, rolls at midnight). Ships without the editor. |
| 13 | **Calendar** | `Calendar.swift` | `snapshot_window_at`, `create_event_at`, `set_span_at` | **Risk #2 (grid geometry).** Month → Week → Day. Hand-built `Grid` (7×N month; 24-row time grid) with explicit 0.5px `Rectangle` hairlines. `buildByDay()` unions `dated` + virtual `occurrences`, all-day first then by time. Drive the occurrence window with `snapshot_window_at` as months change; `resetWindow()` on leave. Multi-day spans use the midnight-exclusive rule. **Fixed 320px right column (day panel OR embedded inspector) — same width is load-bearing: selection must never reflow the grid** (Calendar is the one surface that embeds its own inspector, excludes the global one). |
| 14 | **Editor** | `Editor.swift` (1852 ln) | `content_at`, `set_content_at`, `content_history_at` | **Risk #1 — the single hardest port; do it LAST, test-first.** `RichEditBox` (RTF) fights you — recommend a custom control. Behavioral contracts to reproduce exactly: **span JSON on the wire** (§6), **fingerprint optimistic-concurrency save** (`set_content_at` returns `-1` stale → "changed outside" banner: Keep mine / Take theirs), **markdown input rules** (`# `, `- `, `- [ ] `, `1. `, `> `, `> [!warn] `), **list continuation/exit on Enter**, **block-prefix demote on Backspace**, **inline entity pills** (`{"Ref":id}`) + block markers, ⌘B/I/E marks + ⌘⇧K strike, **draft journaling** (crash/quit safety, replayed on launch), and the **flush-before-navigate gate** (leaving/backgrounding flushes). |
| — | **Chats / AI** | `ExtensionStub` | — | Stub. "Coming soon." Amber (AI-presence) styling. |
| — | **Menu-bar / tray capture** | `main.swift` panel | `capture_at` | Independent; slot in any time after step 1. Global `Ctrl+Alt+Space` via `RegisterHotKey`. |

### Keybindings (Cmd→Ctrl, Opt→Alt)
| Action | Windows | Action | Windows |
|---|---|---|---|
| Search palette | Ctrl+F / Ctrl+O | New note | Ctrl+N |
| Toggle left sidebar | Ctrl+Shift+\` | Bookmark selection | Ctrl+Shift+B |
| Toggle right sidebar | Ctrl+Shift+' | Box undo | Ctrl+Alt+Z (Ctrl+Z routed) |
| Workspace switcher | Ctrl+Shift+O | Focus mode / exit | Ctrl+. / Esc |
| Add file… | Ctrl+Shift+I | Settings | Ctrl+, |
| New tab / Close tab | Ctrl+T / Ctrl+W | Back / Forward | Ctrl+[ / Ctrl+] |
| Today's daily note | Ctrl+Alt+D | Tasks lens switch | Ctrl+1–4 |
| Global capture | Ctrl+Alt+Space | Inspector focus / leave | Alt+→ / Alt+← |

---

## 9. How to work (the loop)

For each surface, in order:
1. **Read the spec.** The macOS Swift reference file is ground truth. Cross-check `design/liv-ui-map.md`, `design/feature-map.md`, and the relevant `design/p*.md` for intent. Consult root `CLAUDE.md` for zones.
2. **Match macOS behavior AND density.** Reproduce layouts 1:1 from the Swift source — same fields, same order, same padding, same empty-field-hiding. Do not invent novel layouts; density matters. Recolor into the liv palette only.
3. **Build** on the proven substrate (RowKit + BoxModel + dispatcher). Reuse the grammar-kit; don't re-roll one-off rows.
4. **VERIFY by driving the real app** — launch the WinUI app against a real box and exercise the flow against the macOS reference side-by-side. Compiling is not verifying. For core-touching behavior (fingerprint saves, span round-trips, hue vectors, occurrence windows) **write the failing test first** — plans have had real cache/behavior bugs; don't trust reasoning over a test.
5. **Open a PR** on `windows-port`. Run `cargo test` + build first. Never commit to `main`, never push unasked.

---

## 10. Do NOT

- **Do NOT** edit `shell/macos/`, `core/`, `services/`, `views/`, or `ffi/` — they are read-only reference.
- **Do NOT** change core behavior or add/alter an FFI verb yourself — new verbs are additive-only and owner-gated. **STOP and ask.**
- **Do NOT** rename `liv` crates/paths/`liv_*` symbols — the code is `liv`, the product is "Liv".
- **Do NOT** make any snapshot field non-nullable — one unexpected-missing key silently drops the whole decode and freezes the window.
- **Do NOT** use `long` for `content_print`/`fingerprint` — use `ulong` (they overflow Int64).
- **Do NOT** hold the box, `Task.Run` fan-out FFI calls, or refresh after a refused write.
- **Do NOT** leak returned `char*` — free each once with `liv_string_free`.
- **Do NOT** fall through to the OS system accent — accent is `#2F7D6B`, always.
- **Do NOT** hue dates / recurrence / tier / kind / rows — a hue always means a metadata value.
- **Do NOT** invent UI the macOS shell doesn't have, open files in the editor, or blindly reserve the 72px traffic-light inset on Windows.
- **Do NOT** commit to `main` or push without the owner asking; **do NOT** leave `shell/windows/` without asking.
