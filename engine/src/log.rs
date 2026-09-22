//! The log: the truth, and the only thing that is.
//!
//! Groups are stored as the bytes `op::encode` produced, plus the few
//! columns needed to find them again. Storing the frame rather than
//! re-encoding on read is what makes "the same box produces the same
//! bytes" cheap, and it means a group that arrives from another device is
//! written down exactly as that device wrote it.
//!
//! **Two forms, one encoding.** Locally the log is a SQLite table, so a
//! write joins the view's transaction and either both land or neither
//! does. On the wire it is a flat stream of the same frames, which is what
//! `core-decisions.md` chose as the sync format — so a sync file is a log
//! and a log is a sync file, with no conversion between them.

use std::collections::{BTreeMap, HashMap};

use crate::id::{DeviceId, Dot};
use crate::op::{self, DecodeError, Group};

/// The box format this build writes and will open.
pub const BOX_FORMAT: u32 = 1;

#[derive(Debug)]
pub enum LogError {
    Sqlite(String),
    Decode(DecodeError),
    /// A box written by a newer build. Refused whole — there is
    /// deliberately no partial-view mode (core.md §13).
    UnsupportedBox { found: u32, supported: u32 },
}

impl std::fmt::Display for LogError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LogError::Sqlite(e) => write!(f, "sqlite: {e}"),
            LogError::Decode(e) => write!(f, "decode: {e:?}"),
            LogError::UnsupportedBox { found, supported } => {
                write!(f, "box format {found} is newer than {supported}")
            }
        }
    }
}

impl std::error::Error for LogError {}

impl From<rusqlite::Error> for LogError {
    fn from(e: rusqlite::Error) -> LogError {
        LogError::Sqlite(e.to_string())
    }
}

impl From<DecodeError> for LogError {
    fn from(e: DecodeError) -> LogError {
        LogError::Decode(e)
    }
}

/// What this box holds, per device: the highest seq it can apply without
/// a gap. This is what sync exchanges first — 16 bytes per device, so
/// three devices is 48.
pub type VersionVector = HashMap<DeviceId, u64>;

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS ops (
    device    BLOB    NOT NULL,
    first_seq INTEGER NOT NULL,
    op_count  INTEGER NOT NULL,
    hlc_wall  INTEGER NOT NULL,
    hlc_ctr   INTEGER NOT NULL,
    bytes     BLOB    NOT NULL,
    PRIMARY KEY (device, first_seq)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS ops_in_time ON ops(hlc_wall, hlc_ctr);
";

/// Groups that arrived before the ones they follow.
///
/// In memory on purpose: if the process dies, the version vector still
/// says we do not have them, so sync fetches them again. Persisting them
/// would buy one round trip and cost a second place for the truth to live.
#[derive(Default)]
pub struct Hold {
    by: BTreeMap<(DeviceId, u64), Group>,
}

impl Hold {
    /// How many groups are waiting for a gap to fill.
    pub fn len(&self) -> usize {
        self.by.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by.is_empty()
    }

    pub fn keep(&mut self, g: Group) {
        self.by.insert((g.device, g.first_seq), g);
    }

    /// The group that continues this device at `next`, if it is waiting.
    pub fn take(&mut self, device: DeviceId, next: u64) -> Option<Group> {
        self.by.remove(&(device, next))
    }
}

/// Open a box: pragmas, schema, and the version fence.
pub fn open(path: &std::path::Path) -> Result<rusqlite::Connection, LogError> {
    prepare(rusqlite::Connection::open(path)?)
}

pub fn open_in_memory() -> Result<rusqlite::Connection, LogError> {
    prepare(rusqlite::Connection::open_in_memory()?)
}

fn prepare(conn: rusqlite::Connection) -> Result<rusqlite::Connection, LogError> {
    // WAL is why an app extension can read while the app writes — the
    // reason SQLite was chosen over a hand-rolled file
    // (core-decisions.md §5).
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.execute_batch(SCHEMA)?;

    // The version fence, checked before a single byte is read.
    let found: Option<String> =
        conn.query_row("SELECT value FROM meta WHERE key = 'box_format'", [], |r| r.get(0)).ok();
    match found {
        None => {
            conn.execute(
                "INSERT INTO meta(key, value) VALUES ('box_format', ?1)",
                [BOX_FORMAT.to_string()],
            )?;
        }
        Some(v) => {
            let found: u32 = v.parse().unwrap_or(u32::MAX);
            if found > BOX_FORMAT {
                return Err(LogError::UnsupportedBox { found, supported: BOX_FORMAT });
            }
        }
    }
    Ok(conn)
}

/// **The box remembers which device it belongs to.**
///
/// A `DeviceId` names a WRITER and is never reused (`id.rs`), and a dot is
/// `(device, seq)` with seq counted per device. So a device id re-minted on
/// every open would restart that counter against history the box already
/// holds — every new op colliding with an old dot, which is the one thing
/// the design calls irreversible. It is written once, on the first open,
/// and read back after that.
///
/// It is stored in `meta`, which `drop_all` does not touch: the device is
/// not derived from the log and must survive a replay.
pub fn device(conn: &rusqlite::Connection) -> Result<DeviceId, LogError> {
    // Hex rather than raw bytes: `meta.value` is declared TEXT, and
    // SQLite's dynamic typing would have stored a blob there happily
    // while making the column's declaration a lie.
    let found: Option<String> =
        conn.query_row("SELECT value FROM meta WHERE key = 'device'", [], |r| r.get(0)).ok();
    if let Some(hex) = found {
        if let Some(id) = from_hex(&hex) {
            return Ok(DeviceId(id));
        }
    }
    let fresh = mint_device();
    let hex: String = fresh.0.iter().map(|b| format!("{b:02x}")).collect();
    conn.execute(
        "INSERT OR REPLACE INTO meta(key, value) VALUES ('device', ?1)",
        rusqlite::params![hex],
    )?;
    Ok(fresh)
}

fn from_hex(hex: &str) -> Option<[u8; 8]> {
    if hex.len() != 16 {
        return None;
    }
    let mut out = [0u8; 8];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(hex.get(i * 2..i * 2 + 2)?, 16).ok()?;
    }
    Some(out)
}

/// Eight bytes that will not collide with another install's.
///
/// `RandomState` is seeded by the OS, so hashing a constant with two fresh
/// ones yields entropy without the crate taking a dependency to get it —
/// and the crate having no dependencies but SQLite is a property worth
/// keeping. It is an identifier, not a secret: nothing here is a key.
fn mint_device() -> DeviceId {
    use std::hash::{BuildHasher, Hasher};
    let mut out = [0u8; 8];
    let mut h = std::collections::hash_map::RandomState::new().build_hasher();
    h.write_u64(0x4c49_5644_4556_0001);
    let a = h.finish();
    let mut h = std::collections::hash_map::RandomState::new().build_hasher();
    h.write_u64(a);
    let b = h.finish();
    out.copy_from_slice(&(a ^ b.rotate_left(17)).to_le_bytes());
    // All zeroes would read as "unset" to anything that checks; one bit
    // costs nothing and removes the case.
    if out == [0u8; 8] {
        out[0] = 1;
    }
    DeviceId(out)
}

    /// Append a group. The caller is responsible for its seq being the
    /// next one — `Engine::receive` is the door for groups from anywhere
    /// else.
pub fn append(conn: &rusqlite::Connection, g: &Group) -> Result<(), LogError> {
        let bytes = op::encode(g);
        conn.execute(
            "INSERT OR IGNORE INTO ops(device, first_seq, op_count, hlc_wall, hlc_ctr, bytes)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            rusqlite::params![
                &g.device.0[..],
                g.first_seq as i64,
                g.ops.len() as i64,
                g.hlc.wall_ms as i64,
                g.hlc.ctr as i64,
                bytes,
            ],
        )?;
        Ok(())
    }

    /// The seq this device should write next.
pub fn next_seq(conn: &rusqlite::Connection, device: DeviceId) -> Result<u64, LogError> {
    // THE LAST ROW, not an aggregate over an expression. `MAX(first_seq
    // + op_count)` cannot be answered from the (device, first_seq) index,
    // so SQLite scanned every row this device had ever written — on
    // every write, because a write asks for its own next seq first. The
    // cost test caught it at 6.03x on a box ten times the size, which is
    // exactly the shape standing rule 2 exists to see.
    //
    // Ordering by the key and taking one row is a descending index seek.
    let high: Option<(i64, i64)> = conn
        .query_row(
            "SELECT first_seq, op_count FROM ops WHERE device = ?1
             ORDER BY first_seq DESC LIMIT 1",
            [&device.0[..]],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .ok();
    Ok(high.map(|(seq, n)| (seq + n) as u64).unwrap_or(0))
}

    /// What this box holds, per device.
pub fn version_vector(conn: &rusqlite::Connection) -> Result<VersionVector, LogError> {
        let mut stmt = conn
            .prepare("SELECT device, MAX(first_seq + op_count) FROM ops GROUP BY device")?;
        let rows = stmt.query_map([], |r| {
            let d: Vec<u8> = r.get(0)?;
            let n: i64 = r.get(1)?;
            Ok((d, n))
        })?;
        let mut vv = VersionVector::new();
        for row in rows {
            let (d, n) = row?;
            if d.len() == 8 {
                let mut id = [0u8; 8];
                id.copy_from_slice(&d);
                vv.insert(DeviceId(id), n as u64);
            }
        }
        Ok(vv)
    }

    /// Everything one device wrote from `from` onward, in seq order —
    /// what sync sends when the other side says what it is missing.
pub fn range(
        conn: &rusqlite::Connection,
        device: DeviceId,
        from: u64,
    ) -> Result<Vec<Group>, LogError> {
        let mut stmt = conn.prepare(
            "SELECT bytes FROM ops WHERE device = ?1 AND first_seq >= ?2 ORDER BY first_seq",
        )?;
        let rows =
            stmt.query_map(rusqlite::params![&device.0[..], from as i64], |r| r.get::<_, Vec<u8>>(0))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(op::decode(&row?)?.0);
        }
        Ok(out)
    }

    /// This device's groups, NEWEST FIRST, until `f` says stop.
    ///
    /// Lazy on purpose: undo's reading of the tail (`undo.rs`) stops at
    /// the first group still in effect, which in a box nobody has undone
    /// in is the very first row. Loading the history to look at its last
    /// entry is what the engine exists not to do.
pub fn walk_back<F>(
        conn: &rusqlite::Connection,
        device: DeviceId,
        mut f: F,
    ) -> Result<(), LogError>
    where
        F: FnMut(&Group) -> bool,
    {
        let mut stmt = conn.prepare(
            "SELECT bytes FROM ops WHERE device = ?1 ORDER BY first_seq DESC",
        )?;
        let mut rows = stmt.query(rusqlite::params![&device.0[..]])?;
        while let Some(row) = rows.next()? {
            let bytes: Vec<u8> = row.get(0)?;
            let g = op::decode(&bytes)?.0;
            if !f(&g) {
                break;
            }
        }
        Ok(())
    }

    /// The group one dot names, if this box holds it.
    ///
    /// A dot names an OP, and a group's seqs are consecutive from
    /// `first_seq` — so the group is the newest one on that device whose
    /// first seq is not past it, and only if its ops reach that far.
pub fn group_at(conn: &rusqlite::Connection, dot: Dot) -> Result<Option<Group>, LogError> {
        let found: Option<(i64, Vec<u8>)> = conn
            .query_row(
                "SELECT op_count, bytes FROM ops
                 WHERE device = ?1 AND first_seq <= ?2
                 ORDER BY first_seq DESC LIMIT 1",
                rusqlite::params![&dot.device.0[..], dot.seq as i64],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .ok();
        let Some((count, bytes)) = found else { return Ok(None) };
        let g = op::decode(&bytes)?.0;
        Ok(if dot.seq < g.first_seq + count as u64 { Some(g) } else { None })
    }

    /// The whole log in causal order — what replay reads.
    ///
    /// Ordered by the clock, not by arrival: a note written on a train and
    /// synced a week later belongs where it was written, or two devices
    /// disagree about the user's own past (core.md §7).
pub fn all(conn: &rusqlite::Connection) -> Result<Vec<Group>, LogError> {
        let mut stmt = conn
            .prepare("SELECT bytes FROM ops ORDER BY hlc_wall, hlc_ctr, device, first_seq")?;
        let rows = stmt.query_map([], |r| r.get::<_, Vec<u8>>(0))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(op::decode(&row?)?.0);
        }
        Ok(out)
    }

pub fn count(conn: &rusqlite::Connection) -> Result<u64, LogError> {
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM ops", [], |r| r.get(0))?;
        Ok(n as u64)
    }

// ---- the wire form ----------------------------------------------------

/// A run of groups as one byte stream — a sync file, which is the same
/// bytes the table stores, concatenated.
pub fn encode_stream(groups: &[Group]) -> Vec<u8> {
    let mut out = Vec::new();
    for g in groups {
        out.extend_from_slice(&op::encode(g));
    }
    out
}

/// Read as many whole groups as the bytes actually contain.
///
/// **A torn tail is expected, not exceptional.** A file being appended to
/// by another device, or copied mid-write by a sync client, ends in a
/// partial group. Everything before it stands; the partial group is not
/// guessed at, not repaired, and not reported as corruption. The returned
/// count is how many bytes were whole, so a caller can resume there.
pub fn decode_stream(bytes: &[u8]) -> (Vec<Group>, usize) {
    let mut out = Vec::new();
    let mut at = 0usize;
    while at < bytes.len() {
        match op::decode(&bytes[at..]) {
            Ok((g, used)) => {
                out.push(g);
                at += used;
            }
            Err(_) => break,
        }
    }
    (out, at)
}
