//! Persistence — milestone 2. The disk truth is a versioned, append-only log
//! of transactions; the in-memory store is a materialization of it. History
//! and persistence are the same thing, so the log is one file.
//!
//! The on-disk encoding lives entirely behind this module: a version-header
//! line, then one JSON transaction per line. It is deliberately swappable —
//! if durability or concurrency is ever *measured* to need it, a hardened
//! backend (e.g. SQLite) can replace the file with no change to the core,
//! because the core never sees bytes, only `Transaction`s.

use std::fs::{File, OpenOptions, TryLockError};
use std::io::{self, Read as _, Write as _};
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::command::{Author, Command, Transaction};
use crate::store::{Store, StoreError};

/// The log format version. It goes in the header on day one; one integer
/// buys every future migration.
pub const LOG_VERSION: u32 = 1;

#[derive(Serialize, Deserialize)]
struct Header {
    lotus_log: u32,
}

#[derive(Debug)]
pub enum PersistError {
    Io(io::Error),
    Store(StoreError),
    /// The log was written by a newer version than this build understands.
    UnsupportedVersion(u32),
    /// The log is malformed before its final record — real corruption, not
    /// a torn tail from a crash mid-append.
    Corrupt(String),
    /// Another process holds the box open. One writer at a time: a second
    /// session would fork the id space from its own stale snapshot.
    Locked,
    /// A prior write to disk failed. The session is fail-stopped so it can
    /// never append a later record onto a gap and corrupt the log.
    Poisoned,
}

impl std::fmt::Display for PersistError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PersistError::Io(e) => write!(f, "io: {e}"),
            PersistError::Store(e) => write!(f, "store: {e}"),
            PersistError::UnsupportedVersion(v) => {
                write!(f, "log version {v} is newer than {LOG_VERSION}")
            }
            PersistError::Corrupt(m) => write!(f, "corrupt log: {m}"),
            PersistError::Locked => write!(f, "the box is open in another process"),
            PersistError::Poisoned => write!(f, "session poisoned by an earlier write failure"),
        }
    }
}

impl std::error::Error for PersistError {}

impl From<io::Error> for PersistError {
    fn from(e: io::Error) -> Self {
        PersistError::Io(e)
    }
}

impl From<StoreError> for PersistError {
    fn from(e: StoreError) -> Self {
        PersistError::Store(e)
    }
}

/// The append-only log file, opened for appending. Owns nothing but the
/// handle and the guarantee that every `append` is on disk before it returns.
#[derive(Debug)]
struct FileLog {
    file: File,
}

impl FileLog {
    fn append(&mut self, tx: &Transaction) -> io::Result<()> {
        let line = serde_json::to_string(tx)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        self.file.write_all(line.as_bytes())?;
        self.file.write_all(b"\n")?;
        self.file.flush()?;
        // The log is the user's data forever; pay the fsync so a returned Ok
        // means it is truly on disk. Relax only if this is measured to hurt.
        self.file.sync_all()?;
        Ok(())
    }
}

/// A store wired to its log. Reads go to the store; every write goes through
/// here so the transaction it produces is appended to disk before the call
/// returns. This is the whole persistence seam: the core stays pure, and the
/// wiring that makes it durable lives in exactly one place.
#[derive(Debug)]
pub struct Session {
    store: Store,
    log: FileLog,
    healthy: bool,
}

impl Session {
    /// Open the log at `path`, replaying it into a live store. Creates the
    /// file with a version header if it does not exist. A torn final record
    /// (a crash mid-append) is dropped and truncated away; corruption before
    /// the final record is an error.
    pub fn open(path: impl AsRef<Path>) -> Result<Session, PersistError> {
        let path = path.as_ref();
        let mut file = OpenOptions::new()
            .create(true)
            .read(true)
            .append(true)
            .open(path)?;

        // One writer at a time, enforced before the first byte is read:
        // everything in memory is a snapshot of the log at open, so a
        // second session would allocate the same ids and seqs from its own
        // stale copy and brick the log for every future launch. The lock
        // rides the file and releases when the session drops.
        match file.try_lock() {
            Ok(()) => {}
            Err(TryLockError::WouldBlock) => return Err(PersistError::Locked),
            Err(TryLockError::Error(e)) => return Err(e.into()),
        }

        let mut bytes = Vec::new();
        file.read_to_end(&mut bytes)?;

        let fresh = bytes.is_empty();
        let (transactions, good_len) = if fresh {
            (Vec::new(), 0)
        } else {
            parse(&bytes)?
        };

        if fresh {
            let header = serde_json::to_string(&Header { lotus_log: LOG_VERSION })
                .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
            file.write_all(header.as_bytes())?;
            file.write_all(b"\n")?;
            file.flush()?;
            file.sync_all()?;
        } else if good_len < bytes.len() as u64 {
            // Drop a torn trailing record so the next append starts clean.
            file.set_len(good_len)?;
        }

        let store = Store::replay(transactions)?;
        Ok(Session {
            store,
            log: FileLog { file },
            healthy: true,
        })
    }

    /// Read access to the materialized store.
    pub fn store(&self) -> &Store {
        &self.store
    }

    pub fn commit(
        &mut self,
        commands: Vec<Command>,
        label: impl Into<String>,
        author: Author,
    ) -> Result<u64, PersistError> {
        self.ensure_healthy()?;
        let seq = self.store.commit(commands, label, author)?;
        self.persist_last()?;
        Ok(seq)
    }

    pub fn undo(&mut self, author: Author) -> Result<u64, PersistError> {
        self.ensure_healthy()?;
        let seq = self.store.undo(author)?;
        self.persist_last()?;
        Ok(seq)
    }

    pub fn redo(&mut self, author: Author) -> Result<u64, PersistError> {
        self.ensure_healthy()?;
        let seq = self.store.redo(author)?;
        self.persist_last()?;
        Ok(seq)
    }

    pub fn merge(
        &mut self,
        survivor: crate::value::Id,
        loser: crate::value::Id,
        resolutions: Vec<Command>,
        author: Author,
    ) -> Result<u64, PersistError> {
        self.ensure_healthy()?;
        let seq = self.store.merge(survivor, loser, resolutions, author)?;
        self.persist_last()?;
        Ok(seq)
    }

    pub fn accept(&mut self, index: usize) -> Result<u64, PersistError> {
        self.ensure_healthy()?;
        let seq = self.store.accept(index)?;
        self.persist_last()?;
        Ok(seq)
    }

    /// Id allocation is the one mutation that is not a command (an id must be
    /// minted before the Create that uses it). It writes nothing to the log —
    /// a burned id is not user data, and gaps are fine since ids never reuse.
    pub fn allocate_id(&mut self) -> crate::value::Id {
        self.store.allocate_id()
    }

    fn ensure_healthy(&self) -> Result<(), PersistError> {
        if self.healthy {
            Ok(())
        } else {
            Err(PersistError::Poisoned)
        }
    }

    /// Append the transaction the store just recorded. On disk failure the
    /// session is poisoned: memory is one transaction ahead of disk, and we
    /// refuse further writes rather than append onto the gap.
    fn persist_last(&mut self) -> Result<(), PersistError> {
        let tx = self
            .store
            .history()
            .last()
            .expect("a successful write records a transaction");
        if let Err(e) = self.log.append(tx) {
            self.healthy = false;
            return Err(PersistError::Io(e));
        }
        Ok(())
    }
}

/// Parse the header and every complete transaction line, returning the
/// transactions and the byte length of the good prefix. A final line without
/// a trailing newline is treated as a torn append and dropped; a complete but
/// unparseable line is corruption.
fn parse(bytes: &[u8]) -> Result<(Vec<Transaction>, u64), PersistError> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| PersistError::Corrupt("log is not valid utf-8".into()))?;

    let lines: Vec<&str> = text.split_inclusive('\n').collect();
    let header_line = lines
        .first()
        .ok_or_else(|| PersistError::Corrupt("empty log".into()))?;
    let header: Header = serde_json::from_str(header_line.trim_end())
        .map_err(|e| PersistError::Corrupt(format!("bad header: {e}")))?;
    if header.lotus_log > LOG_VERSION {
        return Err(PersistError::UnsupportedVersion(header.lotus_log));
    }

    let mut good_len = header_line.len() as u64;
    let mut transactions = Vec::new();
    for (i, line) in lines.iter().enumerate().skip(1) {
        let record = line.trim_end_matches('\n');
        if record.is_empty() {
            good_len += line.len() as u64;
            continue;
        }
        match serde_json::from_str::<Transaction>(record) {
            Ok(tx) => {
                // A record without its newline never finished its append —
                // the commit never returned. Torn at the boundary, dropped
                // like any torn tail; keeping it would merge it with the
                // next append into one unparseable line.
                if i == lines.len() - 1 && !line.ends_with('\n') {
                    break;
                }
                transactions.push(tx);
                good_len += line.len() as u64;
            }
            Err(e) => {
                let torn_tail = i == lines.len() - 1 && !line.ends_with('\n');
                if torn_tail {
                    break;
                }
                return Err(PersistError::Corrupt(format!("record {i}: {e}")));
            }
        }
    }
    Ok((transactions, good_len))
}
