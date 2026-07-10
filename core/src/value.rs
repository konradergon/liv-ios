use serde::de::{self, Deserializer};
use serde::ser::{SerializeStruct, Serializer};
use serde::{Deserialize, Serialize};

/// Stable, monotonic, never reused. 0 = none.
pub type Id = u64;

pub const NONE: Id = 0;

/// The closed set of inline marks a text run may carry (D19). A bitflag
/// set: order is meaningless and duplicates impossible, so a mark set
/// has one canonical serialization and the whole-value fingerprint stays
/// deterministic. New marks are added rarely and stated — four bits spare.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Marks(pub u8);

impl Marks {
    pub const BOLD: u8 = 1 << 0;
    pub const ITALIC: u8 = 1 << 1;
    pub const CODE: u8 = 1 << 2; // inline code, monospace
    pub const STRIKE: u8 = 1 << 3;

    pub fn is_empty(self) -> bool {
        self.0 == 0
    }
}

/// A literal text run carrying a mark set. One `Text` shape, not two —
/// a bare, unmarked run and a marked run are the same kind, so the closed
/// set never grows a second way to say "plain text".
///
/// Serialization is legacy-compatible by construction: an unmarked run
/// encodes as the bare string it always was (`"foo"`), so every span in
/// the log decodes and re-encodes identically and no fingerprint moves
/// until the user actually formats something. A marked run encodes as
/// `{"text":…,"marks":N}`.
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

impl From<&str> for TextSpan {
    fn from(text: &str) -> TextSpan {
        TextSpan::plain(text)
    }
}

impl From<String> for TextSpan {
    fn from(text: String) -> TextSpan {
        TextSpan::plain(text)
    }
}

impl Serialize for TextSpan {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        if self.marks.is_empty() {
            serializer.serialize_str(&self.text)
        } else {
            let mut state = serializer.serialize_struct("TextSpan", 2)?;
            state.serialize_field("text", &self.text)?;
            state.serialize_field("marks", &self.marks.0)?;
            state.end()
        }
    }
}

impl<'de> Deserialize<'de> for TextSpan {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        // A bare string (legacy, and every unmarked run) or an object.
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Repr {
            Bare(String),
            Full {
                text: String,
                #[serde(default)]
                marks: u8,
            },
        }
        match Repr::deserialize(deserializer)? {
            Repr::Bare(text) => Ok(TextSpan { text, marks: Marks::default() }),
            Repr::Full { text, marks } => Ok(TextSpan { text, marks: Marks(marks) }),
        }
        .map_err(|_: D::Error| de::Error::custom("invalid text span"))
    }
}

/// The block kind of one paragraph (D19). Closed set. list/ordered/task
/// carry a depth; task its done-ness; code an optional language tag
/// (highlighting is cosmetic, never structural — "table"/"math" drive
/// widgets over otherwise-plain text).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Block {
    Body,
    Heading(u8), // 1..=6
    Quote,
    Bullet { depth: u8 },
    Ordered { depth: u8 },
    Task { depth: u8, done: bool },
    Code { lang: Option<String> },
    Callout { kind: String },
    Rule,
}

/// One piece of rich text: a text run with marks, a paragraph break
/// carrying the following paragraph's block kind, or an embedded
/// reference. Markdown markers are never stored — they are input
/// conventions the editor converts to marks and blocks (D19). The span
/// list, read left to right, IS the document; `Break` is the only
/// structure, so there is no parallel array to desync.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Span {
    Text(TextSpan),
    /// The break's payload types the paragraph that FOLLOWS it. A `Text`
    /// never contains a newline; a paragraph boundary is always a Break.
    Break(Block),
    Ref(Id),
}

impl Span {
    /// A plain, unmarked text run — the common constructor.
    pub fn text(s: impl Into<String>) -> Span {
        Span::Text(TextSpan::plain(s))
    }
}

/// Equality is by spans.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct RichText {
    pub spans: Vec<Span>,
}

impl RichText {
    /// Unchanged: a reference yields its target, text and breaks yield
    /// nothing — so backlinks stay automatic and no content is parsed.
    pub fn targets(&self) -> impl Iterator<Item = Id> + '_ {
        self.spans.iter().filter_map(|s| match s {
            Span::Ref(id) => Some(*id),
            Span::Text(_) | Span::Break(_) => None,
        })
    }
}

/// The file owns the bytes; the entity owns the meaning.
#[derive(Debug, Clone, Eq, Serialize, Deserialize)]
pub struct FileRef {
    pub path: String,
    /// A changed hash is the entire integration.
    pub hash: [u8; 32],
}

/// Files are equal by hash: the path is where, not what.
impl PartialEq for FileRef {
    fn eq(&self, other: &Self) -> bool {
        self.hash == other.hash
    }
}

/// Civil wall-clock time, never a bare instant. No timezone is stored;
/// that question belongs to multi-device sync and stays fenced with it.
///
/// `civil` packs yyyymmddhhmm, so date-only values sort beside full
/// datetimes without an invented 00:00 leaking into display.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct DateTime {
    pub civil: i64,
    /// "friday" vs "friday 10:00" — different values.
    pub date_only: bool,
}

impl DateTime {
    pub fn date(year: i32, month: u32, day: u32) -> Self {
        DateTime {
            civil: Self::pack(year, month, day, 0, 0),
            date_only: true,
        }
    }

    pub fn at(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> Self {
        DateTime {
            civil: Self::pack(year, month, day, hour, minute),
            date_only: false,
        }
    }

    fn pack(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> i64 {
        (year as i64 * 10_000 + month as i64 * 100 + day as i64) * 10_000
            + hour as i64 * 100
            + minute as i64
    }
}

/// The closed set. New kinds are added rarely and deliberately:
/// every kind multiplies the complexity of queries and renderers.
///
/// Equality is defined per kind — text by content, rich text by spans,
/// files by hash, references by identifier. Removing a cell and
/// deduplicating an import both depend on it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Value {
    Text(String),
    RichText(RichText),
    Number(f64),
    Bool(bool),
    DateTime(DateTime),
    /// Select options are entities.
    Select(Id),
    /// The only relationship mechanism.
    Reference(Id),
    File(FileRef),
}

/// Hand-written so equality is REFLEXIVE for every value: the derived impl
/// made Number(NaN) != Number(NaN), which turned a NaN cell into a poison
/// pill — addable, but never matchable by the RemoveCell that names it.
/// The seam refuses non-finite numbers at parse; this guards any that ever
/// entered another way, so every cell in the log stays removable. (0.0 and
/// -0.0 stay equal, as under the derived impl.)
impl PartialEq for Value {
    fn eq(&self, other: &Value) -> bool {
        match (self, other) {
            (Value::Text(a), Value::Text(b)) => a == b,
            (Value::RichText(a), Value::RichText(b)) => a == b,
            (Value::Number(a), Value::Number(b)) => a == b || (a.is_nan() && b.is_nan()),
            (Value::Bool(a), Value::Bool(b)) => a == b,
            (Value::DateTime(a), Value::DateTime(b)) => a == b,
            (Value::Select(a), Value::Select(b)) => a == b,
            (Value::Reference(a), Value::Reference(b)) => a == b,
            (Value::File(a), Value::File(b)) => a == b,
            _ => false,
        }
    }
}

impl Value {
    pub fn text(s: impl Into<String>) -> Value {
        Value::Text(s.into())
    }

    /// Every entity this value points at, for the backlink index.
    pub fn targets(&self) -> Vec<Id> {
        match self {
            Value::Reference(id) => vec![*id],
            Value::RichText(rt) => rt.targets().collect(),
            _ => Vec::new(),
        }
    }
}

#[cfg(test)]
mod span_tests {
    use super::*;

    /// Legacy compat: an unmarked run is the bare string it always was,
    /// so every span in the log decodes and re-encodes byte-identically.
    #[test]
    fn unmarked_text_is_the_bare_string() {
        let span = Span::text("hello");
        let json = serde_json::to_string(&span).unwrap();
        assert_eq!(json, r#"{"Text":"hello"}"#);
        // And the historical form still decodes.
        let back: Span = serde_json::from_str(r#"{"Text":"hello"}"#).unwrap();
        assert_eq!(back, span);
    }

    /// A marked run encodes as an object; the mark set round-trips.
    #[test]
    fn marked_text_round_trips() {
        let span = Span::Text(TextSpan {
            text: "bold code".into(),
            marks: Marks(Marks::BOLD | Marks::CODE),
        });
        let json = serde_json::to_string(&span).unwrap();
        assert_eq!(json, r#"{"Text":{"text":"bold code","marks":5}}"#);
        let back: Span = serde_json::from_str(&json).unwrap();
        assert_eq!(back, span);
    }

    /// Blocks ride the span stream; the whole doc round-trips.
    #[test]
    fn blocks_round_trip() {
        let doc = RichText {
            spans: vec![
                Span::Break(Block::Heading(1)),
                Span::text("Title"),
                Span::Break(Block::Body),
                Span::text("see "),
                Span::Ref(7),
                Span::Break(Block::Task { depth: 0, done: false }),
                Span::text("ship 4a"),
            ],
        };
        let json = serde_json::to_string(&doc).unwrap();
        let back: RichText = serde_json::from_str(&json).unwrap();
        assert_eq!(back, doc);
        // Backlinks stay automatic — only the Ref contributes a target.
        assert_eq!(doc.targets().collect::<Vec<_>>(), vec![7]);
    }

    /// Fingerprint determinism: the same marks always encode one way, so
    /// the whole-value fingerprint never wobbles. (Marks is a bitset —
    /// order and duplicates are impossible by construction.)
    #[test]
    fn marks_have_one_canonical_encoding() {
        let a = Span::Text(TextSpan { text: "x".into(), marks: Marks(Marks::BOLD | Marks::ITALIC) });
        let b = Span::Text(TextSpan { text: "x".into(), marks: Marks(Marks::ITALIC | Marks::BOLD) });
        assert_eq!(serde_json::to_string(&a).unwrap(), serde_json::to_string(&b).unwrap());
    }
}
