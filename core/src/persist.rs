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

use crate::command::{Author, Command, Proposal, Transaction};
use crate::store::{Store, StoreError};
use crate::value::Id;

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
        // One buffer, one write: the torn-tail window between record and
        // newline should be as narrow as the syscall allows.
        let mut line = serde_json::to_string(tx)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        line.push('\n');
        self.file.write_all(line.as_bytes())?;
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
    /// Refusals live beside the log: `<log>.declined`, one JSON line per
    /// refusal. A refusal is user intent and must survive a restart —
    /// nothing asks again.
    declined_path: std::path::PathBuf,
    /// The queue itself lives beside the log too (milestone 7): the sweep
    /// still re-derives what regex can re-derive, but an agent's draft
    /// cannot be re-derived, so the whole queue is rewritten — atomically,
    /// temp-then-rename — on every change.
    pending_path: std::path::PathBuf,
}

impl Session {
    /// Open the log at `path`, replaying it into a live store. Creates the
    /// file with a version header if it does not exist. A torn final record
    /// (a crash mid-append) is dropped and truncated away; corruption before
    /// the final record is an error.
    pub fn open(path: impl AsRef<Path>) -> Result<Session, PersistError> {
        let path = path.as_ref();
        let file = OpenOptions::new()
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

        Session::open_on(file, path)
    }

    /// Replay an already-opened, already-`try_lock`ed log handle into a
    /// session. `open` does the open + lock, then calls this; the FFI store
    /// cache also calls it on a miss, having locked the handle itself — so it
    /// can lock once, decide hit-vs-miss, and hand the same handle here with no
    /// second open and no lock-release TOCTOU window.
    pub fn open_on(mut file: File, path: &Path) -> Result<Session, PersistError> {
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

        let mut store = Store::replay(transactions)?;

        // Appended, never substituted: "box.db" pairs with "box.db.declined",
        // so two boxes sharing a stem can never share refusals.
        let declined_path = {
            let mut name = path.as_os_str().to_owned();
            name.push(".declined");
            std::path::PathBuf::from(name)
        };
        match std::fs::read(&declined_path) {
            Ok(bytes) => {
                // Refusals are independent records: a torn final fragment
                // is truncated away (like the log's torn tail), and a
                // complete line that will not parse is skipped, never
                // fatal — the worst outcome is one repeated question.
                let mut declined = Vec::new();
                let mut good_len = 0usize;
                while let Some(nl) = bytes[good_len..].iter().position(|b| *b == b'\n') {
                    let record = &bytes[good_len..good_len + nl];
                    if let Ok(text) = std::str::from_utf8(record) {
                        if let Ok(p) = serde_json::from_str::<Proposal>(text) {
                            declined.push(p);
                        }
                    }
                    good_len += nl + 1;
                }
                if good_len < bytes.len() {
                    let repair = OpenOptions::new().write(true).open(&declined_path)?;
                    repair.set_len(good_len as u64)?;
                }
                store.restore_declined(declined);
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.into()),
        }

        let pending_path = {
            let mut name = path.as_os_str().to_owned();
            name.push(".pending");
            std::path::PathBuf::from(name)
        };
        match std::fs::read(&pending_path) {
            Ok(bytes) => {
                // Tolerant like the declined loader: refusing to open over
                // one bad line would hold the whole box hostage.
                for line in bytes.split(|b| *b == b'\n') {
                    if line.is_empty() {
                        continue;
                    }
                    if let Ok(text) = std::str::from_utf8(line) {
                        if let Ok(p) = serde_json::from_str::<Proposal>(text) {
                            store.propose(p);
                        }
                    }
                }
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.into()),
        }

        Ok(Session {
            store,
            log: FileLog { file },
            healthy: true,
            declined_path,
            pending_path,
        })
    }

    /// Rewrite the queue file to match memory, atomically: a crash
    /// mid-write leaves the old file, never a torn one.
    fn persist_pending(&self) -> Result<(), PersistError> {
        let mut buffer = String::new();
        for proposal in self.store.pending() {
            buffer.push_str(
                &serde_json::to_string(proposal)
                    .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?,
            );
            buffer.push('\n');
        }
        let temp = {
            let mut name = self.pending_path.as_os_str().to_owned();
            name.push(".tmp");
            std::path::PathBuf::from(name)
        };
        {
            let mut file = File::create(&temp)?;
            file.write_all(buffer.as_bytes())?;
            file.sync_all()?;
        }
        std::fs::rename(&temp, &self.pending_path)?;
        Ok(())
    }

    /// Read access to the materialized store.
    pub fn store(&self) -> &Store {
        &self.store
    }

    /// Build a session around an already-cached store and an already-opened,
    /// already-locked log handle — the FFI cache's fast path, when the log
    /// length proves nothing was appended since the store was cached. No read,
    /// no replay: the store IS the log's consequence, and it is already in hand.
    pub fn from_cached(store: Store, file: File, path: &Path) -> Session {
        let mut declined = path.as_os_str().to_owned();
        declined.push(".declined");
        let mut pending = path.as_os_str().to_owned();
        pending.push(".pending");
        Session {
            store,
            log: FileLog { file },
            healthy: true,
            declined_path: std::path::PathBuf::from(declined),
            pending_path: std::path::PathBuf::from(pending),
        }
    }

    /// Consume the session, returning its materialized store for the cache to
    /// hold until the next open. The `FileLog` (and its file lock) drops here.
    pub fn into_store(self) -> Store {
        self.store
    }

    /// The log file's metadata, read from the HELD handle (not a fresh path
    /// stat), so the FFI cache reads length + inode from the very file whose
    /// store it is about to cache — an external replace of the path can never
    /// be mistaken for it.
    pub fn log_file_meta(&self) -> io::Result<std::fs::Metadata> {
        self.log.file.metadata()
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
        survivor: Id,
        loser: Id,
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
        self.persist_pending()?;
        Ok(seq)
    }

    /// Quarantine, durable: the proposal lands in memory and the queue
    /// file is rewritten before the call returns. What a sweep can
    /// re-derive costs a few redundant bytes; what it cannot — an agent's
    /// draft — survives a restart.
    pub fn propose(&mut self, proposal: Proposal) -> Result<(), PersistError> {
        self.store.propose(proposal);
        self.persist_pending()
    }

    /// Decline and remember: the refusal is appended to the sidecar before
    /// the call returns, so nothing asks again — across restarts too.
    pub fn reject(&mut self, index: usize) -> Result<(), PersistError> {
        let refused = self.store.reject(index)?;
        let mut line = serde_json::to_string(refused)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        line.push('\n');
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.declined_path)?;
        file.write_all(line.as_bytes())?;
        file.sync_all()?;
        self.persist_pending()?;
        Ok(())
    }

    /// Retract a stale proposal — no refusal recorded, queue file rewritten.
    pub fn retract(&mut self, index: usize) -> Result<(), PersistError> {
        self.store.retract(index)?;
        self.persist_pending()
    }

    /// Id allocation is the one mutation that is not a command (an id must be
    /// minted before the Create that uses it). It writes nothing to the log —
    /// a burned id is not user data, and gaps are fine since ids never reuse.
    pub fn allocate_id(&mut self) -> Id {
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
