use serde::{Deserialize, Serialize};

/// Stable, monotonic, never reused. 0 = none.
pub type Id = u64;

pub const NONE: Id = 0;

/// One piece of rich text: literal text, or an embedded reference.
/// Embedded references are indexed like any other reference.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Span {
    Text(String),
    Ref(Id),
}

/// Equality is by spans.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct RichText {
    pub spans: Vec<Span>,
}

impl RichText {
    pub fn targets(&self) -> impl Iterator<Item = Id> + '_ {
        self.spans.iter().filter_map(|s| match s {
            Span::Ref(id) => Some(*id),
            Span::Text(_) => None,
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
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
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
