//! A note's body: reading it, and saving it safely.
//!
//! **The contract is `core/`'s** (`services/src/content.rs`), because the
//! shell already speaks it and two save buttons that behave differently
//! is a defect even while only one of them ships: the editor holds the
//! fingerprint it last read, saves against it, and is refused if the
//! stored body moved. **There is no force flag** — a save that could
//! overwrite an edit it never saw is the one thing an editor must not do.
//!
//! The fingerprint is FNV-1a over this crate's OWN encoding of the value,
//! not over the text and not over serde bytes. Over the text, two
//! documents differing only in their marks would fingerprint the same,
//! and a save that dropped every bold would pass the compare-and-swap.
//! Over the encoding it is deterministic by construction — the same
//! property the replay gate and the digest exchange already need.

use crate::engine::Engine;
use crate::id::EntityId;
use crate::log::LogError;
use crate::model::prop;
use crate::op::{Author, Op, Value};
use crate::rich::{self, Span};
use crate::write::{action, WriteError};

#[derive(Debug)]
pub enum ContentError {
    /// The stored body moved since `base` was read. Re-read, then save.
    Stale,
    /// No such entity, or a span points at one.
    Invalid,
    Write(WriteError),
}

impl std::fmt::Display for ContentError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ContentError::Stale => write!(f, "the body moved; re-read it"),
            ContentError::Invalid => write!(f, "no such thing, or a link to nothing"),
            ContentError::Write(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for ContentError {}

impl From<WriteError> for ContentError {
    fn from(e: WriteError) -> ContentError {
        ContentError::Write(e)
    }
}

impl From<LogError> for ContentError {
    fn from(e: LogError) -> ContentError {
        ContentError::Write(WriteError::Log(e))
    }
}

/// FNV-1a. Deterministic across processes, cheap, and honest about what
/// it is: an identity check, not cryptography.
///
/// **A second copy of `core/`'s**, and that is standing rule 4's one
/// permitted shape of duplication rather than a breach: the two hash
/// different bytes (serde's there, this crate's encoding here), so they
/// are not two parsers for one grammar. When `core/` goes, so does the
/// other.
pub fn fnv(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// The identity of a stored body. **Zero when there is no cell** — zero is
/// never a real fingerprint, exactly as zero is never a real id, so a
/// first save needs no special case at the call site.
pub fn fingerprint(value: Option<&Value>) -> u64 {
    match value {
        None => 0,
        Some(v) => fnv(&crate::op::value_bytes(v)),
    }
}

impl Engine {
    /// One entity's body and its fingerprint.
    ///
    /// A contended body — two devices having saved concurrently without
    /// seeing each other — reads as the FIRST by dot order rather than as
    /// nothing, because a body is the one cell where showing the user
    /// something they wrote beats showing them a blank page. The
    /// fingerprint covers what is shown, so saving over it is still a
    /// compare-and-swap against a value that is really there.
    pub fn content(&self, entity: EntityId) -> Result<(Vec<Span>, u64), LogError> {
        let mut cells = self.cell(entity, prop::BODY)?;
        cells.sort_by_key(|(d, _)| (d.device.0, d.seq));
        let Some((_, value)) = cells.into_iter().next() else {
            return Ok((Vec::new(), 0));
        };
        let print = fingerprint(Some(&value));
        Ok(match value {
            Value::Rich(spans) => (spans, print),
            // A body that is not rich text cannot happen through `vet`,
            // and is not worth a panic if a peer sends one.
            _ => (Vec::new(), print),
        })
    }

    /// Replace one entity's whole body, compare-and-swap on `base`.
    ///
    /// Empty spans REMOVE the cell: a note whose body the user cleared has
    /// no body, not an empty one. (The format can tell those apart —
    /// `Value::Rich(vec![])` encodes differently from no cell at all — and
    /// this deliberately does not use that, because `core/` does not and
    /// the shell would have no way to ask for the difference.)
    pub fn set_content(
        &mut self,
        entity: EntityId,
        spans: Vec<Span>,
        base: u64,
        now_ms: u64,
    ) -> Result<u64, ContentError> {
        if !self.exists(entity)? {
            return Err(ContentError::Invalid);
        }
        let current = self.one(entity, prop::BODY)?;
        let new = (!spans.is_empty()).then(|| Value::Rich(spans));

        // **The no-op wins before the guard.** Writing what is already
        // there is never stale, whatever base the writer believed — its
        // intent is the log's state already, and refusing it would turn a
        // harmless keystroke into a conflict the user has to resolve.
        if current.as_ref() == new.as_ref() {
            return Ok(fingerprint(current.as_ref()));
        }
        if fingerprint(current.as_ref()) != base {
            return Err(ContentError::Stale);
        }
        // A reference to nothing is not content. A reference to something
        // TRASHED is: trash is reversible, and emptying a note's
        // neighbour must not be a reason this note's save fails.
        if let Some(Value::Rich(spans)) = &new {
            for target in rich::refs(spans) {
                if !self.exists(target)? {
                    return Err(ContentError::Invalid);
                }
            }
        }

        let replaces = self.cell(entity, prop::BODY)?.into_iter().map(|(d, _)| d).collect();
        let fresh = fingerprint(new.as_ref());
        let op = match new {
            Some(value) => Op::SetCell { entity, prop: prop::BODY, value, replaces },
            // The only shape the four ops give for "unset": retire the
            // live dots and put nothing back.
            None => Op::RemoveFromSet {
                entity,
                prop: prop::BODY,
                value: Value::Rich(Vec::new()),
                replaces,
            },
        };
        self.commit(vec![op], action::SET, Author::User, now_ms)?;
        Ok(fresh)
    }
}
