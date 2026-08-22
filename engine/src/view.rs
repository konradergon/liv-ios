//! The view: everything the log implies, kept in tables you can query.
//!
//! **Derived, indexed, disposable.** Nothing here is the truth. Every row
//! is a consequence of an op, and the replay gate proves it: drop all of
//! this, rebuild from the log, and get the same bytes back. That property
//! is what makes a bug in this file repairable rather than permanent —
//! which `core.md` §1 gives as one of the three reasons the log exists at
//! all.
//!
//! **One table does registers and sets both.** A cell row is keyed by the
//! DOT that wrote it, so "one live value" and "many live values" are the
//! same shape. A register with two rows is contended and shows the user
//! the choice; a set with two rows has two members. The difference lives
//! in the ops — `SetCell` names what it replaces, `AddToSet` does not —
//! and never in the schema.

use rusqlite::{Connection, Transaction};

use crate::id::{Dot, EntityId};
use crate::op::{self, Group, Op};

pub const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS entities (
    id         BLOB    NOT NULL PRIMARY KEY,
    created_ms INTEGER NOT NULL,
    trashed    INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS cells (
    entity BLOB    NOT NULL,
    prop   BLOB    NOT NULL,
    device BLOB    NOT NULL,
    seq    INTEGER NOT NULL,
    value  BLOB    NOT NULL,
    PRIMARY KEY (entity, prop, device, seq)
) WITHOUT ROWID;

-- Everything with a given value: the lookup that makes 'everything with
-- Anna' a reference join rather than a text search (core.md §2).
CREATE INDEX IF NOT EXISTS cells_by_value ON cells(prop, value);
CREATE INDEX IF NOT EXISTS cells_by_entity ON cells(entity);
";

/// Every table this module owns, newest dependency last. `rebuild` drops
/// them in this order and the schema recreates them.
const TABLES: &[&str] = &["cells", "entities"];

/// Fold one group into the view, inside the caller's transaction.
///
/// The caller holds the transaction because the append and the apply must
/// land together or not at all — that is the whole reason the log lives
/// in the same file (core.md §4).
pub fn apply(tx: &Transaction, g: &Group) -> Result<(), rusqlite::Error> {
    for (i, o) in g.ops.iter().enumerate() {
        let dot = g.dot(i);
        match o {
            Op::CreateEntity { entity } => {
                tx.execute(
                    "INSERT OR IGNORE INTO entities(id, created_ms, trashed) VALUES (?1, ?2, 0)",
                    rusqlite::params![&entity.0[..], entity.millis() as i64],
                )?;
            }
            Op::SetCell { entity, prop, value, replaces } => {
                ensure_entity(tx, *entity)?;
                retire(tx, *entity, *prop, replaces)?;
                put(tx, *entity, *prop, dot, value)?;
            }
            Op::AddToSet { entity, prop, value } => {
                ensure_entity(tx, *entity)?;
                put(tx, *entity, *prop, dot, value)?;
            }
            Op::RemoveFromSet { entity, prop, replaces, .. } => {
                retire(tx, *entity, *prop, replaces)?;
            }
        }
    }
    Ok(())
}

/// A cell can arrive before the create that made its entity — sync
/// delivers one device's stream in order, not the whole mesh's. The row
/// is created from the id, which carries its own timestamp, so nothing is
/// invented.
fn ensure_entity(tx: &Transaction, id: EntityId) -> Result<(), rusqlite::Error> {
    tx.execute(
        "INSERT OR IGNORE INTO entities(id, created_ms, trashed) VALUES (?1, ?2, 0)",
        rusqlite::params![&id.0[..], id.millis() as i64],
    )?;
    Ok(())
}

fn put(
    tx: &Transaction,
    entity: EntityId,
    prop: EntityId,
    dot: Dot,
    value: &op::Value,
) -> Result<(), rusqlite::Error> {
    tx.execute(
        "INSERT OR REPLACE INTO cells(entity, prop, device, seq, value)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        rusqlite::params![
            &entity.0[..],
            &prop.0[..],
            &dot.device.0[..],
            dot.seq as i64,
            op::encode_value(value),
        ],
    )?;
    Ok(())
}

/// Drop exactly the values this writer had seen.
///
/// **Named, never inferred.** A writer says which dots it was replacing,
/// so a value written concurrently — one this writer never saw — survives
/// and the cell becomes contended. That is the whole of the register
/// merge rule, and it is why nothing silently wins (core.md §5).
fn retire(
    tx: &Transaction,
    entity: EntityId,
    prop: EntityId,
    replaces: &[Dot],
) -> Result<(), rusqlite::Error> {
    for d in replaces {
        tx.execute(
            "DELETE FROM cells WHERE entity = ?1 AND prop = ?2 AND device = ?3 AND seq = ?4",
            rusqlite::params![&entity.0[..], &prop.0[..], &d.device.0[..], d.seq as i64],
        )?;
    }
    Ok(())
}

/// Throw the view away. The log is untouched.
pub fn drop_all(tx: &Transaction) -> Result<(), rusqlite::Error> {
    for t in TABLES {
        tx.execute_batch(&format!("DROP TABLE IF EXISTS {t};"))?;
    }
    Ok(())
}

/// A fingerprint of everything the view holds.
///
/// Rows in a canonical order, hashed. Comparing digests is how the replay
/// gate asks "are these the same view" without dumping two databases, and
/// it is the same mechanism two devices would use to notice drift — which
/// `core.md` §11 names as the only mitigation for a quiet merge bug.
///
/// FNV-1a, the same function the shell already uses for value hues, so
/// the crate still has no hashing dependency.
pub fn digest(conn: &Connection) -> Result<u64, rusqlite::Error> {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    let mut eat = |bytes: &[u8], h: &mut u64| {
        for b in bytes {
            *h ^= *b as u64;
            *h = h.wrapping_mul(0x0000_0100_0000_01b3);
        }
    };

    let mut stmt =
        conn.prepare("SELECT id, created_ms, trashed FROM entities ORDER BY id")?;
    let rows = stmt.query_map([], |r| {
        Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?))
    })?;
    for row in rows {
        let (id, created, trashed) = row?;
        eat(&id, &mut h);
        eat(&created.to_le_bytes(), &mut h);
        eat(&trashed.to_le_bytes(), &mut h);
    }

    let mut stmt = conn.prepare(
        "SELECT entity, prop, device, seq, value FROM cells
         ORDER BY entity, prop, device, seq",
    )?;
    let rows = stmt.query_map([], |r| {
        Ok((
            r.get::<_, Vec<u8>>(0)?,
            r.get::<_, Vec<u8>>(1)?,
            r.get::<_, Vec<u8>>(2)?,
            r.get::<_, i64>(3)?,
            r.get::<_, Vec<u8>>(4)?,
        ))
    })?;
    for row in rows {
        let (e, p, d, s, v) = row?;
        eat(&e, &mut h);
        eat(&p, &mut h);
        eat(&d, &mut h);
        eat(&s.to_le_bytes(), &mut h);
        eat(&v, &mut h);
    }
    Ok(h)
}

/// Every live value of one property on one entity, with the dot that
/// wrote it. **More than one is contended, not broken** — the caller
/// shows the choice rather than picking.
pub fn cell(
    conn: &Connection,
    entity: EntityId,
    prop: EntityId,
) -> Result<Vec<(Dot, op::Value)>, rusqlite::Error> {
    let mut stmt = conn.prepare(
        "SELECT device, seq, value FROM cells
         WHERE entity = ?1 AND prop = ?2 ORDER BY device, seq",
    )?;
    let rows = stmt.query_map(rusqlite::params![&entity.0[..], &prop.0[..]], |r| {
        Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, i64>(1)?, r.get::<_, Vec<u8>>(2)?))
    })?;
    let mut out = Vec::new();
    for row in rows {
        let (d, s, v) = row?;
        let mut device = [0u8; 8];
        if d.len() == 8 {
            device.copy_from_slice(&d);
        }
        if let Some(value) = op::decode_value(&v) {
            out.push((Dot { device: crate::id::DeviceId(device), seq: s as u64 }, value));
        }
    }
    Ok(out)
}

pub fn entity_count(conn: &Connection) -> Result<u64, rusqlite::Error> {
    let n: i64 = conn.query_row("SELECT COUNT(*) FROM entities", [], |r| r.get(0))?;
    Ok(n as u64)
}
