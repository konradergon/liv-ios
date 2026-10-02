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
use crate::model::{kind, prop};
use crate::op::{Author, Op, Value};
use crate::rich::{self, Span};
use crate::write::{action, WriteError};

#[derive(Debug)]
pub enum ContentError {
    /// The stored body moved since `base` was read. Re-read, then save.
    Stale,
    /// No such entity, not one this verb changes (`file_into_note` on
    /// something that is not a file), or a span points at nothing.
    Invalid,
    Write(WriteError),
}

impl std::fmt::Display for ContentError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ContentError::Stale => write!(f, "the body moved; re-read it"),
            ContentError::Invalid => write!(f, "no such thing, not one this changes, or a link to nothing"),
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

/// One past version of a body.
///
/// **The spans are read out of the log**, not stored beside it: the log IS
/// the history, and a second copy could disagree with it while the log
/// stayed right.
#[derive(Debug, Clone, PartialEq)]
pub struct ContentVersion {
    /// Which write this was — what `history` names and what a restore
    /// would be a restore OF.
    pub dot: crate::id::Dot,
    /// The group's wall clock, in milliseconds.
    pub at_ms: i64,
    pub author: Author,
    pub spans: Vec<Span>,
}

impl Engine {
    /// Every version of one entity's body, NEWEST FIRST.
    ///
    /// Newest first because that is the order the card lists them, and
    /// reversing a list in Swift is logic in the shell.
    ///
    /// **Restoring one is not a verb.** It is `set_content` of an old
    /// version's spans over a freshly read base, appended as a new
    /// version — the log is never rewritten.
    pub fn content_history(&self, entity: EntityId) -> Result<Vec<ContentVersion>, LogError> {
        let mut out = Vec::new();
        for (dot, at_ms) in crate::view::edits_of(self.conn(), entity, prop::BODY)? {
            let Some(g) = crate::log::group_at(self.conn(), dot)? else { continue };
            let Some(i) = dot.seq.checked_sub(g.first_seq) else { continue };
            let spans = match g.ops.get(i as usize) {
                Some(Op::SetCell { value: Value::Rich(spans), .. })
                | Some(Op::AddToSet { value: Value::Rich(spans), .. }) => spans.clone(),
                _ => continue,
            };
            out.push(ContentVersion { dot, at_ms, author: g.author.clone(), spans });
        }
        Ok(out)
    }

    /// What this thing's body points at, in reading order.
    pub fn links_from(&self, src: EntityId) -> Result<Vec<EntityId>, LogError> {
        Ok(crate::view::links_from(self.conn(), src)?)
    }

    /// And what points at it — the same index read the other way.
    pub fn links_to(&self, dst: EntityId) -> Result<Vec<EntityId>, LogError> {
        Ok(crate::view::links_to(self.conn(), dst)?)
    }

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
        if let Some(Value::Rich(spans)) = &new {
            self.links_resolve(spans)?;
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

    /// Make a note with its name and its body, in ONE action.
    ///
    /// What a text file handed to the phone becomes. `create` and then
    /// `set_content` would be two actions, and one undo would leave an
    /// empty note behind. A blank name writes no name cell and no spans
    /// write no body, as everywhere else.
    pub fn make_note(
        &mut self,
        name: Option<&str>,
        spans: Vec<Span>,
        now_ms: u64,
    ) -> Result<EntityId, ContentError> {
        self.links_resolve(&spans)?;
        let id = self.mint(now_ms);
        let mut ops = vec![
            Op::CreateEntity { entity: id },
            Op::SetCell { entity: id, prop: prop::KIND, value: Value::Ref(kind::NOTE), replaces: vec![] },
        ];
        if let Some(name) = name.map(str::trim).filter(|n| !n.is_empty()) {
            ops.push(Op::SetCell {
                entity: id,
                prop: prop::NAME,
                value: Value::Text(name.to_owned()),
                replaces: vec![],
            });
        }
        if !spans.is_empty() {
            ops.push(Op::SetCell { entity: id, prop: prop::BODY, value: Value::Rich(spans), replaces: vec![] });
        }
        self.commit(ops, action::CREATE, Author::User, now_ms)?;
        Ok(id)
    }

    /// Turn a file the box holds into a note of its words, in ONE action.
    ///
    /// The owner, 2026-10-01: a file that contains text is edited as a
    /// note. It keeps its id, so every link to it and every cell the user
    /// gave it stay; it stops being a file — kind NOTE, the spans as its
    /// body, no hash and no format. A name that ends in the file's own
    /// extension loses it: `Linux Installation.md` is a file's name, not a
    /// note's. A task or event carrying a file keeps its kind.
    ///
    /// The file on disk is never written, and its place is kept: one undo
    /// puts the hash back, and the hash is what finds the place.
    ///
    /// `SET`, not a code of its own — it changes cells of a thing that
    /// already exists, which is what `SET` has always meant.
    ///
    /// Refused, with nothing written, for anything that is not a file, a
    /// file in the trash, and a link to nothing.
    pub fn file_into_note(
        &mut self,
        id: EntityId,
        spans: Vec<Span>,
        now_ms: u64,
    ) -> Result<(), ContentError> {
        if self.cell(id, prop::FILE)?.is_empty() || self.is_trashed(id)? {
            return Err(ContentError::Invalid);
        }
        self.links_resolve(&spans)?;
        let format = match self.one(id, prop::FORMAT)? {
            Some(Value::Text(f)) => Some(f.clone()),
            _ => None,
        };

        // A FILE becomes a note; a task or an event that carries a file
        // keeps being what it is, and only its words move in.
        let mut ops = Vec::new();
        if matches!(self.kind_of(id)?, None | Some(kind::FILE)) {
            ops.push(Op::SetCell {
                entity: id,
                prop: prop::KIND,
                value: Value::Ref(kind::NOTE),
                replaces: self.dots_of(id, prop::KIND)?,
            });
        }
        if spans.is_empty() {
            ops.extend(self.unset_op(id, prop::BODY)?);
        } else {
            ops.push(Op::SetCell {
                entity: id,
                prop: prop::BODY,
                value: Value::Rich(spans),
                replaces: self.dots_of(id, prop::BODY)?,
            });
        }
        ops.extend(self.unset_op(id, prop::FILE)?);
        ops.extend(self.unset_op(id, prop::FORMAT)?);
        // ONLY THE FILE'S OWN EXTENSION comes off the name. A name someone
        // typed is theirs: "Letter to Dr. Who" is not "Letter to Dr".
        if let (Some(name), Some(format)) = (self.name(id)?, format) {
            let suffix = format!(".{format}");
            let cut = name.len().saturating_sub(suffix.len());
            if cut > 0
                && name.is_char_boundary(cut)
                && name[cut..].eq_ignore_ascii_case(&suffix)
            {
                ops.push(Op::SetCell {
                    entity: id,
                    prop: prop::NAME,
                    value: Value::Text(name[..cut].to_owned()),
                    replaces: self.dots_of(id, prop::NAME)?,
                });
            }
        }
        self.commit(ops, action::SET, Author::User, now_ms)?;
        Ok(())
    }

    /// Every link in these spans points at something the box holds.
    ///
    /// A reference to nothing is not content. A reference to something
    /// TRASHED is: trash is reversible, and emptying a note's neighbour
    /// must not be a reason this note's save fails.
    fn links_resolve(&self, spans: &[Span]) -> Result<(), ContentError> {
        for target in rich::refs(spans) {
            if !self.exists(target)? {
                return Err(ContentError::Invalid);
            }
        }
        Ok(())
    }
}
