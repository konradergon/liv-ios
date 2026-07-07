# P7 Files Model — the librarian: reference + content-hash, a read-only ladder, a rebuildable cache

Building on the shipped tree (`core/src/value.rs`, `services/src/content.rs`,
`services/src/search.rs`, `services/src/lib.rs`, `ffi/src/lib.rs`,
`shell/macos/Sources/{Window,Chrome,Tabs}.swift`). Files is **the one
sanctioned integration** (constitution: "at most ONE integration until the
core is proven — local files first, by reference"). A file entity is an
**ordinary entity carrying a `File`-valued cell** — the core model already
exists (`Value::File(FileRef{ path, hash:[u8;32] })`, equal by hash, rendered
as its path by `views::display`). P7 wires that primitive through a new
`files` service, one dedicated FFI verb, a hash-keyed sidecar cache, and a
read-only native shell. **No core model change.** Liv's 6-mode document shell
is **not ported**; its one genuine idea — extraction is a cheap disposable
cache, not a store — is honored by construction.

## 1 · The five load-bearing decisions

1. **The file entity is a normal entity; identity is the hash, the path is
   metadata.** Add-by-reference creates one entity in one transaction:
   `Create` + `type=file` + a `file`-kind cell holding `Value::File(FileRef)`
   + a `format` text cell (the lowercased extension) + `name` = the filename.
   Nothing else. `FileRef` equality is hash-only already
   (`core/src/value.rs:160`), so "the path is where, not what" is enforced at
   the type level. **We never move, copy, or rename the user's bytes** — the
   only outbound action is "open externally" (`NSWorkspace.open`).

2. **The hash is a byte-SHA-256, computed only in the shell (and the add
   verb), never in `run`/`display`.** The core stores 32 bytes but computes
   them nowhere. P7 adds *one* byte-hashing helper. It is distinct from the
   FNV `content_fingerprint` (`content.rs:19`, an identity check over a serde
   value); a file hash is a cryptographic-strength digest over raw bytes so a
   one-byte edit reliably misses the cache. See §6 for the crate decision.

3. **Extraction and thumbnails are a sidecar cache keyed by hex(hash), off
   the log, rebuildable — never a cell.** This is constitutional law
   ("Extracted text and thumbnails are caches, not cells. Delete the cache;
   nothing is lost."). The cache lives next to `lotus.log` at
   `~/Library/Application Support/lotus/cache/<hex-hash>/{text,thumb.png}`.
   A cache miss (first sight or a changed hash) triggers re-extraction.
   Deleting the whole `cache/` dir loses nothing derivable.

4. **A changed hash IS the integration — change detection at open, no
   watcher, no timer.** When a file entity is opened (rung climb), the shell
   re-hashes the referenced path. If the new hash differs from the stored
   `FileRef.hash`, that is a real user-meaning event: commit an `AddCell`
   replacing the `File` cell (replace-the-cell, one undo step), then the old
   cache entry is simply orphaned and the new hash's entry misses and
   re-extracts. **Nothing runs on a timer.** A path that no longer resolves
   is a distinct *broken* state (path shown struck-through, no re-extract), not
   a hash change.

5. **Search reads the extraction cache as an out-of-log text source, passed
   in — `searchable()` stays a pure service function.** The cache feeds the
   corpus *without any cell being written to the log*. `searchable()` grows
   one optional parameter: extracted text for this entity's file hash, folded
   into the CONTENT tier so a PDF is findable by its words. The cache is a
   service concern; `search.rs` never touches the filesystem.

## 2 · The file-entity model (data-model first)

A file entity, e.g. `report.pdf`:

```
Create #4200
name    = "report.pdf"               (props::NAME, text)
type    = →file                      (props::TYPE, reference to the seeded "file" type)
file    = File{ path:"/Users/k/report.pdf", hash:[u8;32] }   (a "file"-kind property)
format  = "pdf"                       (a "format" text property)
created = 2026-07-07 14:30            (props::CREATED)
```

Two new seeded entities in `seed_starter_library` (`services/src/lib.rs:281`),
both additive (an older box gains them on open; the guard becomes
`property_id(store,"file").is_some()` so re-seed is idempotent):

- **A `file` property** — `new_property(…, "file", "file")`. Its VALUE_KIND is
  the string `"file"`, which is exactly what the new `parse_value` arm and the
  snapshot's `kind` field key on. It is **working: true** like every other
  definition, so it never appears in Everything.
- **A `format` property** — `new_property(…, "format", "text")`. Free text,
  not a select: formats are open-ended and #35 only needs it queryable
  (`format:pdf` already works through the existing search DSL, no new code).
- **A `file` type** — added to the `expectations` table with
  `("file", &[file_prop])` so a file entity is typed from birth and expects
  its `file` cell, exactly as "note" expects CONTENT.

No reserved id — these are ordinary allocated entities, author System, like
the rest of the starter library. Nothing keys on their ids.

## 3 · The extraction / thumbnail cache (rebuildable, never cells)

**Location.** `~/Library/Application Support/lotus/cache/` — a sibling of
`lotus.log` (`shell/macos/Sources/main.swift:29`). One subdirectory per
content hash:

```
cache/
  a1b2…ef/                 hex(FileRef.hash)
    text                   extracted plain text (UTF-8), absent until extracted
    thumb.png              optional (rung 3), absent in 7a–7c
```

**Keyed by hash, not path.** Two entities referencing byte-identical files
share one cache entry (matches FileRef's hash-only equality). A file edited
in Word gets a new hash → a new dir → a guaranteed miss → re-extraction. The
old dir is orphaned, harmless, and swept by a trivial future GC (not P7).

**Who writes it.** The extraction service (Rust, §4) given `(hash, path,
format)`: on a miss, read the bytes, extract text per format, write
`cache/<hex>/text`. This is the *only* place bytes are read for extraction,
and it writes **only inside `cache/`** — never near the user's file. A read
failure (file gone) writes nothing and returns empty; the entity is a broken
reference, searchable as such but never crashing.

**Off the log by construction.** Nothing in the cache is ever a `Cell` or a
`Value`. `set_content`/`set_property` are never called with extracted text.
The log carries only the `FileRef` (path + hash) the user chose; everything
derivable from the bytes lives in `cache/` and can be deleted wholesale.

## 4 · The Rust `files` service — `services/src/files.rs`

A new module beside `content.rs` and `search.rs`, re-exported from
`services/src/lib.rs`.

```rust
//! Files — the librarian. A file entity references bytes by path + a
//! 32-byte content hash; the entity owns the meaning, the file owns the
//! bytes. Reading is a strictly read-only ladder; extraction is a cache
//! keyed by hash, off the log, rebuildable and disposable.

use lotus_core::{props, Author, Cell, Command, DateTime, FileRef, Id, PersistError, Session, Value};

/// SHA-256 of the file's bytes → [u8;32]. The one place a file hash is
/// computed. Distinct from content_fingerprint (FNV over a serde value):
/// this is over raw bytes, strength enough that a one-byte edit misses.
pub fn hash_file(path: &str) -> std::io::Result<[u8; 32]>;

/// Birth of a file entity by reference: Create + type=file + a File cell
/// (path + freshly computed hash) + format (lowercased extension) + name
/// (filename) + created, one transaction. NEVER copies or moves the file.
/// Returns the new id. `path` must resolve and be readable (to hash it);
/// an unreadable path is an error, not a phantom entity.
pub fn add_file(session: &mut Session, path: &str, created: DateTime)
    -> Result<Id, PersistError>;

/// Re-hash the referenced path and, if it differs from the stored FileRef,
/// replace the File cell in one transaction (the hash change IS the
/// integration). Returns the current hash (new or unchanged), or None when
/// the path no longer resolves — a broken reference, distinct from a change.
pub fn resync_file(session: &mut Session, id: Id) -> Result<Option<[u8; 32]>, PersistError>;

/// The extraction cache root for one box: `<box_dir>/cache`.
pub fn cache_dir(box_path: &str) -> std::path::PathBuf;

/// Extracted plain text for a file, cached by hash. On a miss, read the
/// bytes and extract per format, writing `cache/<hex>/text`; on a hit,
/// read the cached file. A read/extract failure yields empty (a broken or
/// unextractable file is searchable by name only, never a crash). This is
/// the ONLY place bytes are read for extraction, and it writes ONLY under
/// `cache/`.
pub fn extracted_text(cache_dir: &Path, file: &FileRef, format: &str) -> String;

/// Format → extractor. 7b ships plain text only; the rest are stubs that
/// return empty and are filled in a later slice.
fn extract(bytes: &[u8], format: &str) -> String {
    match format {
        "txt" | "md" | "markdown" | "text" | "csv" | "log" => String::from_utf8_lossy(bytes).into_owned(),
        // "pdf" | "docx" => deferred (see §8); empty until then.
        _ => String::new(),
    }
}
```

### 4.1 The `parse_value` "file" arm

`content.rs:413` currently falls through to
`other => Err("cannot parse a {other} value yet")`. Add a `file` arm so a
file cell can be *read back* through the generic path and so `format:` and
kind-routing behave — but it does **not** become the add door:

```rust
"file" => {
    // A raw path alone cannot honestly carry the bytes-derived hash, so
    // a hand-typed set is refused: file entities are born through
    // add_file (which hashes), never through set_property's string seam.
    Err("a file is added by reference, not typed".into())
}
```

Rationale: a `File` value carries a hash the raw string cannot express.
Making the arm *error explicitly* (rather than fall through) documents the
decision and keeps the inspector treating a `file` cell as **read-only**
(path shown, hash never hand-edited) — the same posture the ladder demands.

### 4.2 How `searchable()` reads the cache

`search.rs:285` `searchable()` gains extracted text folded into the CONTENT
tier. The cache read stays out of `search.rs`: the caller (`build_search` in
the FFI, which knows the box path) resolves each file entity's extracted text
and passes a lookup in.

```rust
// signature grows one param: a closure/map from entity id → extracted text
fn searchable(store: &Store, entity: &Entity, extracted: &str) -> Searchable { … }
// content field becomes: entity CONTENT display  +  " "  +  extracted
```

`build_search` (`ffi/src/lib.rs:492`), for each candidate that is a file
entity, calls `files::extracted_text(cache_dir, file_ref, format)` and hands
the string in. A non-file entity passes `""`. So a PDF's words score at the
CONTENT tier (weight 10, `score_term` unchanged) — findable, never
overweighted, and **no cell is ever added**. This realizes feature-map
"extend the corpus over extracted foreign text later."

## 5 · The FFI seam(s) — `ffi/src/lib.rs`

One new mutation verb, mirroring `lotus_create_note_at` (`ffi/src/lib.rs:839`)
and the `open_swept → mutate → drop` pattern:

```c
// Add a file by reference: hash it, create the entity + File cell +
// format + name, one transaction. NEVER copies/moves the file. Returns
// the new id, or 0 (unreadable path, busy box, or failure).
uint64_t lotus_add_file_at(const char *path, const char *file_path);
```

Implementation: `open_swept`, then `files::add_file(&mut session, file_path,
now)`, `unwrap_or(0)`. The box `path` and the `file_path` are separate
arguments (the box is where the log lives; `file_path` is the user's file).

**Resync** rides existing seams, not a new verb in 7a: when the shell opens a
file entity it already calls the read seam; add a companion:

```c
// Re-hash the file entity's referenced path; if it changed, replace the
// File cell (one transaction). Returns 1 if changed & rewritten, 0 if
// unchanged, -1 if the path no longer resolves (broken reference).
int32_t lotus_resync_file_at(const char *path, uint64_t id);
```

The **snapshot already carries file cells** — `CellRow.kind` lists `"file"`
in its doc-comment (`ffi/src/lib.rs:76`), `display` renders the path, and
`build_snapshot` needs no change to emit a file entity's row. The shell reads
a file entity from the ordinary snapshot; `lotus_search_at` unchanged on the
wire (only `build_search` internally folds in extracted text).

## 6 · The hash crate decision

No hashing crate is in the tree today. Two honest options:

- **Add `sha2` to `services/Cargo.toml`** (`sha2 = "0.10"`) — the boring,
  correct choice; `[u8;32]` is exactly SHA-256's output. Recommended.
- Hand-roll, to match the "keep Liv's hand-rolled parser instinct" tone.
  Rejected: a hash is not a parser; a wrong hash silently corrupts change
  detection. Use the vetted crate; save the hand-rolling budget for the PDF
  extractor where the instinct actually applies.

The FNV `content_fingerprint` stays exactly as it is — it guards content
edits, a different job. `hash_file` is the file's identity.

## 7 · The SwiftUI shell (native, read-only ladder)

### 7.1 Add-file flow (NSOpenPanel)

A "+ Add file" affordance in the Library surface (and a `⌘⇧O` menu item)
opens `NSOpenPanel` (`canChooseFiles`, `allowsMultipleSelection` later).
On selection, `BoxModel.addFile(path:)` mirrors `createNote`
(`Window.swift:268`):

```swift
func addFile(_ filePath: String, done: @escaping (UInt64?) -> Void) {
    boxQueue.async {
        let id = lotus_add_file_at(self.path, filePath)
        DispatchQueue.main.async {
            if id == 0 { NSSound.beep() }
            done(id == 0 ? nil : id); self.refresh()
        }
    }
}
```

**Sandbox note (open question surfaced):** a sandboxed app needs a
**security-scoped bookmark** to re-read (and thus re-hash / re-extract) the
file after the panel closes. P7 stores the bookmark blob in the shell's own
defaults keyed by hex(hash) — *shell state, not the log* — and
`startAccessingSecurityScopedResource()` around every re-hash and extraction.
If the app ships non-sandboxed for now, this is deferred but named.

### 7.2 `TabKind.file` and `BaseFileView` — the read-only ladder

Add `case file(UInt64)` to `TabKind` (`Tabs.swift:19`), alongside `.note`.
`activeTabContent` (`Window.swift:848`) routes a `.file` tab to a
**`BaseFileView`**, never `EditorView` — read-only-by-decision is law, so a
file entity **never opens the P4 markdown editor**. When a list row's entity
is of type `file`, the open path routes to a file tab, not `openEditor`.

`BaseFileView` renders the ladder, every rung read-only:

- **Rung 1 — icon / filename / properties.** `NSWorkspace.icon(forFile:)`,
  the name, the `format`, the path (struck-through if the file no longer
  resolves), and the ordinary property list (reusing the inspector's
  read-only rendering). On appear, fire `lotus_resync_file_at` on `boxQueue`;
  a `1` (changed) triggers `refresh()` so the new hash and re-extracted text
  land.
- **Rung 2 — extracted text.** A read-only scrollable text view of
  `cache/<hex>/text` (a tiny `lotus_extracted_text_at(path,id) -> *char` read
  seam, or read the cache file directly from Swift — prefer the seam so the
  cache path stays a Rust concern). Absent → "no preview available".
- **Rung 3 — thumbnail.** Optional; folded/deferred (§8).
- **Rung 4 — "Open externally"** — a button calling `NSWorkspace.shared.open`.
  This is the *only* outbound seam. **There is no rung five.**

### 7.3 Library surface — saved views of file entities

The `.library` case (`Chrome.swift:16`) currently falls to `ExtensionStub`
(`Window.swift:825`). Replace it with a `LibraryView` that is a **saved view
filtering file entities**, reusing the existing list lens (`EntityLine` /
`model.rows`) — *not* Liv's Data-view/Folder/Browser modes. The default view
is `type:file`; format facets (`format:pdf`, `format:png`) come **free** from
the existing search DSL + facet chips (P6) — `format` is a property, so
faceting already works with zero new Rust. The **image grid (Gallery
renderer) is a candidate that must justify itself** (#35) — not built
speculatively; the list lens ships first.

## 8 · Slice plan (each an independent commit: build → tests → review → fix)

- **7a — add a file by reference (rung 1 + open externally).** `files.rs`
  with `hash_file` (sha2) + `add_file`; the `file`/`format` properties and
  `file` type in `seed_starter_library` (idempotent guard); the `parse_value`
  `file` arm (explicit refusal); `lotus_add_file_at`. Shell: `TabKind.file`,
  `BaseFileView` rungs 1 + 4 (icon/name/format/path/properties + Open
  externally), the NSOpenPanel add flow, route file-typed entities to a file
  tab. Tests: `add_file` creates exactly one entity with type=file + File
  cell (hash matches `hash_file`) + format + name, and **no bytes moved**;
  seed is idempotent across two opens; `parse_value("file",…)` errors; FFI
  round-trip (`lotus_add_file_at` → snapshot shows a `file`-kind cell whose
  display is the path). No extraction yet.

- **7b — the extraction cache + search (plain text first).** `cache_dir`,
  `extracted_text` (hash-keyed sidecar, `extract` = UTF-8 for
  txt/md/csv/log, empty otherwise); `resync_file` + `lotus_resync_file_at`;
  `searchable()` grows the `extracted` param; `build_search` folds cached text
  into the corpus. Shell: `BaseFileView` rung 2 (extracted-text view via a
  read seam), resync-on-open. Tests: a `.md` file's words are found by search
  (CONTENT tier) with **no cell added** to the log; deleting `cache/` and
  re-searching re-extracts identically (rebuildable); a changed hash misses
  the old cache dir and re-extracts; `resync_file` replaces the File cell on a
  changed hash and reports broken on a missing path; **PDF/Word return empty
  (documented stub)**.

- **7c — the Library surface (saved views).** Replace `.library`
  `ExtensionStub` with `LibraryView`: the list lens over `type:file`, format
  facet chips (free from P6), the "+ Add file" affordance wired to 7a. Tests
  are shell-level (snapshot/manual): file entities list; a `format:pdf` facet
  narrows; opening a row opens a file tab (not the editor). No new Rust.

- **7d — PDF/Word extraction + thumbnails (or explicit deferral).** Fill the
  `extract` stubs: a **hand-rolled** PDF text extractor first (the sanctioned
  instinct), then `.docx` (unzip → `word/document.xml` text runs); rung-3
  thumbnails (`QLThumbnailGenerator` → `cache/<hex>/thumb.png`). This slice is
  the hard part and is **explicitly scoped as last**; if the port timeline
  demands, 7d ships as a documented deferral with the stubs from 7b left in
  place — plain-text extraction already proves the whole cache + search
  pattern end to end.

## 9 · Deferred (named, not built in P7)

`#38` minimal-create (writes bytes — violates never-copy in spirit) ·
`#40`/`#41` import pipelines (bulk link / Obsidian) · `#42` export ·
`#43` ICS feeds (fenced: "only after files prove the pattern") · Liv's
Data-view / Kanban / Folder-tree / Browser modes · the LibraryExtension full
editor (rung five — refused, forever) · the Gallery image grid (a candidate
that must justify itself, #35) · dual-write mirrors / file watchers / sync
engines (change detection only) · AI file classification (proposals door,
later) · cache GC of orphaned hash dirs (trivial, not P7) · multi-file add
(NSOpenPanel multiselect — a fast-follow once single-add lands).