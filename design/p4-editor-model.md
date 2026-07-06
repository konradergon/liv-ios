# P4 Content-Representation Model — THE SPEC (marks-and-blocks hybrid)

Decided against the shipped code (`core/src/value.rs`, `services/src/content.rs`, `services/src/clerk.rs`, `ffi/src/lib.rs`, `shell/macos/Sources/Editor.swift`). Every "unchanged" claim below is verified, not asserted.

---

## 1. THE DECISION

lotus stores formatted content as a **flat span stream that carries its own formatting** — never a markdown string, never a nested tree, never a parallel block array. `Span::Text` gains a closed 4-bit `Marks` set (bold/italic/code/strike); a new `Span::Break(Block)` carries the *next* paragraph's block kind (heading/quote/list/task/code/callout/rule); `Span::Ref` is untouched. **Markdown markers are never stored** — `#`, `**`, `- [ ]`, `[[…]]` are input gestures the NSTextView converts on keystroke, so D18 is honored as written (input convention, not storage), not reversed (Model A's fatal). **Marks are a flat bitset, not a nested `Marked{spans}` subtree**, so the shipped flat `enumerateAttribute` inverse walk *extends* rather than gets replaced (Model B's fatal — no tree serializer, round-trip stays lossless by construction). **Wiki-links collapse into the one `Ref` mechanism** (`@` and `[[` both insert a `Ref` pill): backlinks stay automatic through the byte-identical `targets()`, and Liv's `.md`-mirror reconciliation apparatus is *deleted*, not reproduced. Tables/math/code are `Block::Code{lang}` text rendered by a native widget — no new value kind, door left open for a measured future promotion. `Value` stays exactly 8 kinds; `RichText` keeps `{spans}`; legacy content decodes unchanged via `#[serde(default)]` with zero migration and preserved fingerprints. This is the smallest change that ports Liv's §2.14 behaviors onto the native surface and survives all six constitutional lenses.

**Constitutional amendment (fold into `productivity_app.md`, amending D18 and the Content law):**

> **D19 — Rich text carries a bounded, closed notion of formatting.** A `Text` span carries, besides its string, a closed set of inline *marks* (bold, italic, code, strike — a 4-bit set); the span stream carries `Break` markers whose payload is a closed *block* kind (body, heading 1–6, quote, bullet, ordered, task, code, callout, rule) that types the following paragraph. Marks and block kinds are the entire formatting vocabulary. Markdown markers, `[[…]]`, and per-block syntax remain **input conventions only and are never stored** — D18 ("markdown syntax is at most an input convention") now reads as *an input convention over marks-and-blocks*. References remain the **sole** relationship mechanism: a wiki-link inserts a `Ref` span and unifies with @-mentions, so backlinks stay automatic and **no content is ever parsed to find them**. Tables and math are `Code`-kind paragraphs holding raw text, rendered by a native widget, not new value kinds; promoting them to structured values is deferred to a measured need and a future amendment. Content stays **one whole value in the log, replaced whole and fingerprinted whole**; the closed set of Value *kinds* is unchanged (`RichText` is refined in its interior, not multiplied). New marks or block kinds are added rarely and stated, closed by the same rule as value kinds — and the compiler enforces the closure at every `match` on `Span`. This ports Liv's editor behaviors onto the native surface and **deletes** Liv's `.md`-mirror machinery rather than reproducing it.

---

## 2. THE RUST REPRESENTATION

`core/src/value.rs` — `Value` unchanged (8 kinds), `RichText { spans }` unchanged, `Span` extended:

```rust
/// A closed set of inline marks. A bitflag set — order is meaningless and
/// duplicates impossible, so a mark set has ONE canonical serialization and
/// the whole-value fingerprint stays deterministic. 4 bits spare; adding one
/// is itself a (small, stated) amendment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct Marks(pub u8);

impl Marks {
    pub const BOLD:   u8 = 1 << 0;
    pub const ITALIC: u8 = 1 << 1;
    pub const CODE:   u8 = 1 << 2;   // inline code, monospace
    pub const STRIKE: u8 = 1 << 3;
    pub fn is_empty(self) -> bool { self.0 == 0 }
}

/// One piece of rich text.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Span {
    /// Literal text carrying a mark set. `#[serde(default, skip_if=is_empty)]`
    /// so every span already in the log — `{"Text":"foo"}` — still decodes
    /// (empty marks) and re-encodes IDENTICALLY. Legacy fingerprints preserved,
    /// zero migration.
    Text {
        text: String,
        #[serde(default, skip_serializing_if = "Marks::is_empty")]
        marks: Marks,
    },
    /// A paragraph break carrying the FOLLOWING paragraph's block kind. The
    /// span list read left-to-right IS the document; Break is the only
    /// structure. A `Text` never contains '\n'; a paragraph boundary is
    /// always a Break. First paragraph is Body unless a leading Break says
    /// otherwise (a doc never starts with Break). One canonical encoding —
    /// no trailing-newline-vs-Break ambiguity — so the fingerprint is stable.
    Break(Block),
    /// Unchanged. The one relationship mechanism; pills; @-mentions AND
    /// wiki-links both land here.
    Ref(Id),
}

/// The block kind of one paragraph. Closed set. list/ordered/task carry a
/// depth; task carries done-ness; code carries an optional language tag
/// (highlighting is cosmetic, never structural).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Block {
    Body,
    Heading(u8),              // 1..=6
    Quote,
    Bullet { depth: u8 },
    Ordered { depth: u8 },
    Task { depth: u8, done: bool },
    Code { lang: Option<String> },   // lang "table"/"math" drive widgets; text-only
    Callout { kind: String },        // "note"|"warning"|… cosmetic
    Rule,                            // empty paragraph, drawn as a hairline
}

impl RichText {
    // UNCHANGED in behavior — Break and Text yield nothing, Ref yields id.
    pub fn targets(&self) -> impl Iterator<Item = Id> + '_ {
        self.spans.iter().filter_map(|s| match s {
            Span::Ref(id) => Some(*id),
            Span::Text { .. } | Span::Break(_) => None,
        })
    }
}
```

**Why `Text` becomes a struct variant, not a new `MarkedText` variant:** a separate variant leaves `Text(String)` a distinct shape forever — two ways to say "plain text," the closed-set erosion the constitution warns against. One `Text` shape with defaulted marks is *one* way.

**Why `Break(Block)` in-stream, not a parallel `Vec<Block>`:** a parallel array is a second source of truth that can desync from the spans; inline `Break` keeps the editor's existing invariant ("the span list IS the document") and gives one canonical encoding for the fingerprint.

**Closed-set enforcement (verified — the compiler does it):** every `match` on `Span` in the tree gets a compile error on the new variants and must be updated deliberately:
- `core/src/value.rs:24` `targets()` — updated above.
- `services/src/content.rs:44` (`content_spans` legacy upcast) → `Span::Text { text: text.clone(), marks: Marks::default() }`; `:88` (ref validation) — `Break`/`Text` skip the loop, unchanged in effect.
- `services/src/clerk.rs:133` (`plain_content`, feeds clerk date/name proposals + search) → `Span::Text { text, .. } => Some(text.as_str())`, `Break`/`Ref` → `None`. **The clerk keeps clean prose — no markdown noise (Model A poisons this; C does not).**
- `services/src/lib.rs:490` (`plain`) → same extraction.
- `services/src/lib.rs:39` and `content.rs:318` (`parse_value` "richtext") → `Span::Text { text, marks: default }`.

**Migration:** none. Legacy `Value::Text` still upcasts to one `Text` span (`content_spans`). Legacy `{"Text":"foo"}` JSON decodes to `Text{text:"foo", marks:0}` and re-encodes byte-identically (serde default + skip_if). **A pre-P4 note opens, edits, and saves with an unchanged fingerprint until the user actually formats something** — verified against `content_fingerprint` being FNV over serde bytes (content.rs:31-35).

---

## 3. THE C SEAM

**Signatures unchanged.** `lotus_content_at` → `{id,name,trashed,missing,fingerprint,spans}`. `lotus_set_content_at(path,id,spans_json,base_fingerprint,out fresh)` — decode is `serde_json::from_str::<Vec<Span>>` (ffi:584), which absorbs the richer variants for free. No new function, no new argument, no changed return (`1/-1/0`).

**Exact JSON the wire carries** (serde-derived; `marks` omitted when empty, `Break` and struct-`Text` are new shapes):

```json
{ "id": 42, "name": "Design", "trashed": false, "missing": false,
  "fingerprint": 17632…,
  "spans": [
    { "Break": { "Heading": 1 } },
    { "Text": { "text": "P4 model" } },
    { "Break": "Body" },
    { "Text": { "text": "The truth is " } },
    { "Text": { "text": "spans", "marks": 5 } },       // BOLD|CODE = 1|4
    { "Text": { "text": ", see " } },
    { "Ref": 7 },
    { "Break": { "Task": { "depth": 0, "done": false } } },
    { "Text": { "text": "ship 4a" } }
  ] }
```

**Whole-value replace + fingerprint (verified UNCHANGED — `set_content` never inspects a span's interior):** no-op-wins → fingerprint guard (`content_fingerprint(current) != base` → `Stale`) → ref validation (only `Span::Ref` inspected, content.rs:88) → `RemoveCell(old) + AddCell(RichText{spans})` in one commit → return fresh fingerprint. Marks/breaks live *inside* the FNV'd serde bytes, so a bold toggle or heading change moves the fingerprint exactly like a keystroke — flush-gate, 2s/30s clocks, stale banner, quit journal all fire identically. One user action → one whole-value replace, unchanged.

**Backlinks (verified UNCHANGED):** `targets()` yields nothing for `Text`/`Break`, the id for `Ref` — byte-for-byte what shipped and was reviewed. Wiki-links are `Ref` spans, so they index automatically both directions with **zero content parsing**. `set_content`'s ref-target validation (content.rs:86-93) still refuses a `Ref` to a nonexistent entity, so every stored reference is live.

**C sketch in `productivity_app.md` (§1937+):** the `SPAN_TEXT` case gains a `uint8_t marks`; add a `SPAN_BREAK` kind carrying a small `Block` tag (a byte + optional depth/level/done/lang). The amendment writes this into the sketch. Swift's `SpanJSON` grows two cases (below).

---

## 4. SWIFT EDITOR ARCHITECTURE (NSTextView, TextKit 1)

### Content ⇄ attributed string, lossless by construction

`SpanJSON` (Editor.swift:15) grows to three cases: `.text(String, Marks)`, `.break(Block)`, `.ref(UInt64)`. `SpanCodec.attributed` (Editor.swift:70) becomes a walk that tracks the current block as it consumes `Break`s and applies marks per `Text` run:

- **Marks → attributes** (the cheap win — flat, composable):
  - `BOLD`/`ITALIC` → font traits via `NSFontManager.convert(_,toHaveTrait:)` (compose freely).
  - `STRIKE` → `.strikethroughStyle`. `CODE` → monospaced `.font` + `label@6%` `.backgroundColor` (matches the pill tint).
  A marked run becomes **one attributed run**; marks compose because they're independent traits/attributes.
- **Block → paragraph style + line-lead attachment:**
  - `Heading(n)` → larger `.font` + heading `NSParagraphStyle`. **Never resizes on caret entry** — size is the stored block's attribute, not the caret's (§2.14.5, achieved natively because no marker is present to hide/reveal).
  - `Quote` → indent paragraph style + leading hairline via the text view's `drawBackground(forGlyphRange:)`.
  - `Bullet`/`Ordered{depth}` → hanging-indent style + a **list-marker attachment** at line start (same `NSTextAttachmentCell` family as the shipped `RefAttachmentCell`).
  - `Task{done}` → a `TaskMarkerCell` attachment (`square`/`checkmark.square.fill`) that toggles the **paragraph's** `done` bit in the draft (local edit → autosave) — distinct from a task-*entity* `Ref` pill, which edits the referenced entity's `status`. Both coexist: a task *line* is formatting; a task *pill* is a reference.
  - `Rule` → 1px hairline attachment filling an empty paragraph. `Callout{kind}` → tinted paragraph run + left border.
  - `Code`/table/math → **block widget** (below).
- **Ref → `RefAttachmentCell` pill** — unchanged, live from snapshot, monochrome, checkbox when the target is a task.

### The inverse walk (extends the shipped code — this is why C fits)

`spans(from:)` (Editor.swift:97) stays a single `enumerateAttribute` pass. It already coalesces adjacent text runs and turns cells into `.ref(id)`; the change is: **coalesce only when marks are equal**, read the paragraph's carried `Block` back from the paragraph attribute, and emit a `.break(block)` at each paragraph boundary. **No display attribute drives structure that isn't recoverable** — the marker was never a buffer character, so the inverse reads paragraphs by their carried `Block`, not by re-parsing glyphs. Round-trip is `spans(from: attributed(spans)) == spans`, proven as the 4a acceptance test (extend the FFI content round-trip test).

### Live-preview reveal — where we DIVERGE from Liv, and why it's acceptable

lotus stores **no markers**, so there is nothing to reveal. Both divergences are improvements under interface.md 0.4 (render native; native rich text does not show its own markup) and both dodge cautionary-tale #7 (the caret never traverses a hidden glyph):

1. **Block "reveal" = the block style simply stays applied on the caret line.** A heading looks like a heading whether or not the caret is in it (no reflow crossing a line boundary — *better* than Liv's flash-to-raw). What changes is the editable affordance: on the caret's paragraph the list-marker/checkbox attachment becomes transparent-but-selectable so **backspace-at-line-start demotes** the block (Task→Bullet→Body), reproducing the muscle memory of deleting a `- ` prefix with no literal `- ` to delete.
2. **Inline "reveal" = native affordance, not literal `**`.** Bold is a font trait; toggle with ⌘B or type `**x**` (input rule, converted on keystroke). Caret in a bold run shows ⌘B checked; the selection shows the trait. **We deliberately drop "see the literal asterisks"** — that was Liv's webview compromise, not a feature.

### Widgets (tables / math / code) — the paragraph-widget flip

`Block::Code{lang}` paragraphs are **text-only** (no `Ref` spans inside code/table/math — one rule). Caret **outside** the block → a widget attachment replaces the block's glyph range (native `NSTableView`-lite grid for `lang:"table"`; platform math typesetter for `lang:"math"` — **never KaTeX-in-a-webview**; syntax-tinted mono frame for code). Caret **inside** (click widget / arrow in) → raw editable text shows; caret-leave re-renders. Source stays verbatim in the `Text` spans → round-trip lossless. Widgets ride the same TextKit-1 attachment mechanism the `RefAttachmentCell` pill already proves; per-block degrade-to-raw is the safety net.

### Wiki-links — the unification (with B's alias grafted in)

Typing `[[` or `@` opens the same picker. On accept → insert a **`Ref` span** (the exact `insertCompletion` path). **No `[[…]]` is ever stored; no content is ever parsed for backlinks.** A rename is a chip redraw, not a body rewrite. Liv's `syncWikilinkRelations`, echo-ring, and `[[Title|context]]` reconciliation **evaporate** — they existed only to reconcile the `.md` mirror.
- **Alias display (grafted from Model B, resolving C's alias-loss):** the picker's path-drill (`Parent / Child`) is a *pure render concern* — the `RefAttachmentCell` already draws the live title and can draw a picker-chosen display label held in the draft's cell context. No stored alias is needed for disambiguation because the id already disambiguates; the label is a redraw hint, never a second truth.
- **Forward links (resolving C's dropped gesture):** "Link to a note that doesn't exist yet" **creates the entity then inserts its `Ref`** in one transaction (like `create_note`), so there is never a dangling `[[query]]` in the log and never an unresolved `Ref`. Honest and better linking hygiene: no silent-failing `[[typos]]`.

---

## 5. P4 SLICE PLAN (each independently shippable)

- **4a — core amendment + inline formatting (the spine; biggest slice, ships value alone).** Land `Marks` + `Block` + struct-`Text` + `Break` in `value.rs`; serde defaults; update the 5 `Span` match sites (targets, content_spans, clerk plain_content, lib plain, parse_value). Seam JSON rides through (no signature change). **Fingerprint-determinism test** (bitflag canonicalization; one canonical span stream — coalesce equal-mark adjacents, no trailing-newline ambiguity) + **round-trip property test through the real FFI seam** (extend the existing content round-trip test) as the 4a gate. Swift: `SpanJSON` three cases; marks→attributes (⌘B/⌘I/⌘⇧K/⌘E + markdown input rules); block kinds heading/quote/bullet/ordered via paragraph style + marker attachments; backspace-at-line-start demotion; live checkbox (`TaskMarkerCell`, paragraph-local `done`); source-mode + reading-view toggles (one boolean each, no remount). *No FFI signature change, bounded core change.*
- **4b — wiki-links + slash menu.** `[[` opens the shipped picker; accept inserts a `Ref` pill (reuse `insertCompletion`); forward-link = create-then-ref; alias as a draw-time label. Slash `/` inserts a `Break(Block)` of the chosen kind at the caret paragraph. Backlink integration test: a wiki-link creates a bidirectional backlink with **no core change** (through the untouched `targets()`).
- **4c — blocks: code / table / math / callout / rule (hardest slice).** `Block::Code{lang}` text-only paragraphs; caret-outside widget, caret-inside raw; mousedown-drops-caret-at-block-start; per-block degrade-to-raw. Native math typesetting (Core Text/MathML, **no webview**), GFM grid widget with alignment, syntax-tinted code frame, callout tint, hairline rule. Round-trip test extended to every block kind.
- **4d — history / snapshots.** No new core work — every save is already a whole-value command in the log under a fingerprint. Snapshots pane (§2.14.2) reads this entity's content commits and diffs span streams; **restore = a whole-value `set_content` of the historical spans** through the shipped guarded-save path. Journal/undo untouched. (If a dedicated snapshot-list read is wanted, it is a *read-only* seam addition — never a new value shape.)

---

## 6. OPEN DECISIONS FOR THE OWNER

1. **Forward-link semantics (mild fork).** Spec picks **create-then-ref** (no dangling `[[query]]` ever). The only alternative that keeps a *literal unresolved* forward link would reintroduce parse-for-backlinks and a non-`Ref` reference shape — rejected as un-constitutional. **Confirm** create-on-accept is the desired UX for "link to a note that doesn't exist yet" (it changes Liv's park-a-string behavior; judges rated it an improvement).
2. **The v1 mark/block long tail.** Dropped from v1, each a one-line future amendment if measured: highlight `==`, comment `%%`, sub/sup, footnotes, mermaid, inline images. **`#tag` is resolved: a tag is an entity → a `Ref` pill**, unifying with everything else (no new shape). Confirm you want highlight/comment excluded from 4a rather than spending two of the 4 spare `Marks` bits now.
3. **Table promotion trigger.** Tables/math ship as `Code{lang}` rendered text (no queryable cells). The door is open for a future `Block::Table{cols}` amendment. **Decide the bar:** promote only on a *measured* need to query cells (recommended), or never.

**Key files:** `/Users/k/src/lotus/core/src/value.rs` (Span/Marks/Block), `/Users/k/src/lotus/services/src/content.rs` (match sites :44/:88/:318, save frozen), `/Users/k/src/lotus/services/src/clerk.rs:133` and `/Users/k/src/lotus/services/src/lib.rs:39,490` (match sites), `/Users/k/src/lotus/ffi/src/lib.rs:571-600` (decode frozen, signature unchanged), `/Users/k/src/lotus/shell/macos/Sources/Editor.swift` (`SpanJSON`:15, `SpanCodec`:62-122, inverse walk :97-116, `RefAttachmentCell`:130 — all P4 rendering work here), `/Users/k/src/lotus/productivity_app.md` (D18 + Content law §157/§242 + C sketch §1937 — amend to D19), `/Users/k/src/lotus/liv-ui-map.md` §2.14.5-2.14.8.