//! Files, by reference — and the separation `core/` does not make.
//!
//! **A path is where; a hash is what.** `core/`'s `FileRef` carries both
//! in one value, in the log. `core.md` §14 records that as a model bug and
//! `op-format.md` §6 repeats it: a device-local path does not survive a
//! device boundary, so a file synced from a laptop arrives on a phone
//! carrying a path that resolves to nothing and looks perfectly valid.
//!
//! So they are two things here. The hash is a `Value::Blob` cell and
//! travels with everything else; the path is a row in a device-local
//! table that is not in the log, not in the digest, and not rebuilt by
//! replay — because nothing in the log could rebuild it. A file that
//! arrived by sync has a hash and no path on this device, and `path_of`
//! saying `None` is the honest answer to "where is it".
//!
//! **Nothing is copied or moved, ever.** The file is read to hash it and
//! otherwise left exactly where the user put it (`feature-map`: the
//! librarian, not the warehouse).

use sha2::{Digest, Sha256};
use std::io::Read;

use crate::engine::Engine;
use crate::id::EntityId;
use crate::log::LogError;
use crate::model::{kind, prop};
use crate::op::{Author, Op, Value};
use crate::write::action;

/// What re-hashing a file's path found.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Resync {
    /// The bytes are unchanged; the stored hash still holds.
    Unchanged,
    /// The bytes changed, and the cell now carries the new hash. **This is
    /// the whole integration** — it is how Liv learns Word saved a file.
    Changed([u8; 32]),
    /// The path no longer resolves, this device never had one, or the
    /// thing is not a file. A broken reference, which is not a change.
    Broken,
}

#[derive(Debug)]
pub enum FileError {
    /// The path could not be read. An unreadable file is an error, never a
    /// phantom entity with a hash of nothing.
    Unreadable(std::io::Error),
    Log(LogError),
}

impl std::fmt::Display for FileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FileError::Unreadable(e) => write!(f, "cannot read that file: {e}"),
            FileError::Log(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for FileError {}

impl From<LogError> for FileError {
    fn from(e: LogError) -> FileError {
        FileError::Log(e)
    }
}

impl From<crate::write::WriteError> for FileError {
    fn from(e: crate::write::WriteError) -> FileError {
        match e {
            crate::write::WriteError::Log(l) => FileError::Log(l),
            other => FileError::Log(LogError::Sqlite(other.to_string())),
        }
    }
}

/// SHA-256 over the bytes, streamed.
///
/// **Vetted, not hand-rolled**, and that is a decision this tree already
/// recorded once — `services/Cargo.toml` says so beside its own `sha2`:
/// *"A changed hash is the whole integration, so the digest must be
/// vetted, not hand-rolled."* It is the reason this crate has a second
/// dependency at all.
///
/// Streamed rather than read whole: a large PDF should not become a
/// large allocation.
pub fn hash_file(path: &str) -> std::io::Result<[u8; 32]> {
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buf)?;
        if read == 0 {
            break;
        }
        hasher.update(&buf[..read]);
    }
    Ok(hasher.finalize().into())
}

impl Engine {
    /// Take a file into the box, by reference.
    ///
    /// One action: the entity, its kind, the filename as its name, the
    /// hash, and the format. The path is remembered separately, on this
    /// device only.
    pub fn add_file(&mut self, path: &str, now_ms: u64) -> Result<EntityId, FileError> {
        let hash = hash_file(path).map_err(FileError::Unreadable)?;
        let p = std::path::Path::new(path);
        let filename = p.file_name().and_then(|s| s.to_str()).unwrap_or(path).to_owned();
        // Lowercased: a format is a kind of thing, and `.PDF` and `.pdf`
        // are the same kind of thing.
        let format = p
            .extension()
            .and_then(|s| s.to_str())
            .map(str::to_lowercase)
            .filter(|s| !s.is_empty());

        let id = self.mint(now_ms);
        let mut ops = vec![
            Op::CreateEntity { entity: id },
            Op::SetCell { entity: id, prop: prop::KIND, value: Value::Ref(kind::FILE), replaces: vec![] },
            Op::SetCell { entity: id, prop: prop::NAME, value: Value::Text(filename), replaces: vec![] },
            Op::SetCell { entity: id, prop: prop::FILE, value: Value::Blob(hash), replaces: vec![] },
        ];
        if let Some(format) = format {
            // No cell at all when there is no extension. An empty format
            // is a claim about the file, and we have none to make.
            ops.push(Op::SetCell {
                entity: id,
                prop: prop::FORMAT,
                value: Value::Text(format),
                replaces: vec![],
            });
        }
        self.commit(ops, action::CREATE, Author::User, now_ms)?;
        self.remember_path(id, path)?;
        Ok(id)
    }

    /// Re-hash what this file points at on THIS device.
    ///
    /// A changed hash is replaced in one action, so the change is one undo
    /// step. Called when a file is opened, never on a timer.
    pub fn resync_file(&mut self, id: EntityId, now_ms: u64) -> Result<Resync, LogError> {
        let Some(Value::Blob(stored)) = self.one(id, prop::FILE)? else {
            return Ok(Resync::Broken);
        };
        let Some(path) = self.path_of(id)? else {
            // A file that arrived by sync. Not broken in the sense of
            // "gone" — this device simply has no copy — but there is
            // nothing here to re-hash, and both answers are the same to a
            // caller deciding whether to refresh.
            return Ok(Resync::Broken);
        };
        let Ok(fresh) = hash_file(&path) else {
            return Ok(Resync::Broken);
        };
        if fresh == stored {
            return Ok(Resync::Unchanged);
        }
        let replaces = self.cell(id, prop::FILE)?.into_iter().map(|(d, _)| d).collect();
        self.commit(
            vec![Op::SetCell {
                entity: id,
                prop: prop::FILE,
                value: Value::Blob(fresh),
                replaces,
            }],
            action::SET,
            Author::User,
            now_ms,
        )?;
        // The same file, in the same place, holding different bytes.
        self.remember_path(id, &path)?;
        Ok(Resync::Changed(fresh))
    }

    /// Where this device keeps that file, if it keeps it at all.
    pub fn path_of(&self, id: EntityId) -> Result<Option<String>, LogError> {
        let Some(Value::Blob(hash)) = self.one(id, prop::FILE)? else {
            return Ok(None);
        };
        Ok(crate::view::path_of(self.conn(), &hash)?)
    }

    /// Say where a file is on this device — what `add_file` does, and what
    /// a shell does after finding a synced file the user has pointed it at.
    ///
    /// Keyed by the HASH, not the entity: two entities holding the same
    /// bytes are the same file, and the path answers "what", not "which".
    pub fn remember_path(&self, id: EntityId, path: &str) -> Result<(), LogError> {
        let Some(Value::Blob(hash)) = self.one(id, prop::FILE)? else {
            return Ok(());
        };
        self.remember_hash_path(&hash, path)
    }

    /// The same, by hash — for a caller that has the bytes' identity but
    /// not an entity to ask, which is what the converter has.
    pub fn remember_hash_path(&self, hash: &[u8; 32], path: &str) -> Result<(), LogError> {
        crate::view::remember_path(self.conn(), hash, path)?;
        Ok(())
    }
}
