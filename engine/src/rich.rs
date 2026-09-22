//! Rich text: what a note's body IS.
//!
//! **The same grammar as `core/src/value.rs`, deliberately** — standing
//! rule 4 says one grammar and one parser for a user-facing shape, and a
//! note written on the engine has to read as the same document `core/`
//! wrote. The types are re-declared rather than imported because the
//! engine depends on nothing above it (`lib.rs`), and because these get
//! a hand-written encoding: `core/`'s are `#[derive(Serialize)]`, which
//! is exactly the arrangement `op-format.md` §1 records as the first of
//! its two lessons.
//!
//! **The span list, read left to right, IS the document.** `Break` is the
//! only structure, so there is no parallel array to desync — which is why
//! content is one value in one cell rather than a text cell with a
//! separate table of marks and links beside it.

/// The closed set of inline marks a run may carry. A bitflag set: order
/// is meaningless and duplicates impossible, so one mark set has exactly
/// one encoding — which the replay gate requires.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Marks(pub u8);

impl Marks {
    pub const BOLD: u8 = 1 << 0;
    pub const ITALIC: u8 = 1 << 1;
    pub const CODE: u8 = 1 << 2;
    pub const STRIKE: u8 = 1 << 3;

    /// Bits 4–7. `op-format.md` §2: reserved bits must be zero, and are
    /// checked — so a byte with one set is refused rather than silently
    /// meaning "no mark", which would make two byte sequences decode to
    /// the same value and break the digest.
    pub const RESERVED: u8 = 0xf0;

    pub fn is_empty(self) -> bool {
        self.0 == 0
    }
}

/// One text run and its marks. **One `Text` shape, not two** — a plain
/// run is a run with no marks, so the closed set never grows a second
/// way to say "unmarked text".
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct TextSpan {
    pub text: String,
    pub marks: Marks,
}

impl TextSpan {
    pub fn plain(text: impl Into<String>) -> TextSpan {
        TextSpan { text: text.into(), marks: Marks::default() }
    }
}

/// The block kind of one paragraph. Closed set. `list`/`ordered`/`task`
/// carry a depth; `task` its done-ness; `code` an optional language tag
/// (highlighting is cosmetic, never structural).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Block {
    Body,
    /// 1–6. Anything else is refused on decode: there is no seventh
    /// heading level to render, and accepting one would put a value in
    /// the log that no reader agrees about.
    Heading(u8),
    Quote,
    Bullet { depth: u8 },
    Ordered { depth: u8 },
    Task { depth: u8, done: bool },
    Code { lang: Option<String> },
    Callout { kind: String },
    Rule,
}

/// A text run, a paragraph boundary, or an embedded reference.
///
/// Markdown markers are never stored — they are input conventions the
/// editor turns into marks and blocks. A `Text` never contains a newline;
/// a paragraph boundary is always a `Break`, and the break's payload types
/// the paragraph that FOLLOWS it.
#[derive(Debug, Clone, PartialEq)]
pub enum Span {
    Text(TextSpan),
    Break(Block),
    Ref(crate::id::EntityId),
}

impl Span {
    pub fn text(s: impl Into<String>) -> Span {
        Span::Text(TextSpan::plain(s))
    }
}

/// Every entity this document points at, in reading order, with repeats.
///
/// The fold indexes these so that "what links here" is a seek rather than
/// a scan of every body in the box — `core/` rebuilt that index on read,
/// which is the defect `scale.rs` names four times over.
pub fn refs(spans: &[Span]) -> Vec<crate::id::EntityId> {
    spans
        .iter()
        .filter_map(|s| match s {
            Span::Ref(id) => Some(*id),
            _ => None,
        })
        .collect()
}

/// The document as plain text, for search and for a one-line preview.
///
/// A `Break` becomes a newline and a `Ref` contributes nothing — a link's
/// text is the target's name, which lives on the target, not here.
pub fn plain(spans: &[Span]) -> String {
    let mut out = String::new();
    for s in spans {
        match s {
            Span::Text(t) => out.push_str(&t.text),
            Span::Break(_) => out.push('\n'),
            Span::Ref(_) => {}
        }
    }
    out
}
