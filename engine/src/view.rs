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
-- No `trashed` column. Trash is a `SetCell` on `prop::TRASHED` like any
-- other value (op.rs keeps the vocabulary at four that way), so a column
-- here would be a second answer to the same question — and it was: no op
-- ever wrote it, every row held 0 forever, and it fed a constant into the
-- digest while `is_trashed` read the cell and answered correctly. When
-- Phase 6 wants trash indexed for the snapshot's arrays, the column comes
-- back MAINTAINED BY THE FOLD, which is a different thing from this one.
CREATE TABLE IF NOT EXISTS entities (
    id         BLOB    NOT NULL PRIMARY KEY,
    created_ms INTEGER NOT NULL,
    -- WHEN THIS WAS LAST TOUCHED: what you were just working on.
    --
    -- The group's HLC, which `id.rs` keeps deliberately weak: display
    -- order and tiebreaks only, never destroying a value. Ordering a list
    -- is exactly that job.
    --
    -- Maintained by the fold and never lowered, so an op arriving late
    -- from a device with a slow clock cannot make a note look older than
    -- an edit that already landed. `core/` recomputed this by walking the
    -- whole history on every call — 99 ms per search at 500,000 entities,
    -- identical every time — until T3 indexed it. Same lesson, paid once.
    touched_ms INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS entities_by_touch ON entities(touched_ms);

CREATE TABLE IF NOT EXISTS cells (
    entity BLOB    NOT NULL,
    prop   BLOB    NOT NULL,
    device BLOB    NOT NULL,
    seq    INTEGER NOT NULL,
    value  BLOB    NOT NULL,
    -- WHEN this value is, in milliseconds, when it is a time at all.
    --
    -- The encoded `value` cannot answer a range: it is a tag byte then
    -- little-endian bytes, and memcmp over that is not date order. So the
    -- fold MAINTAINS this beside it (standing rule 2: maintain on write,
    -- never rebuild on read) and 'what is due this week' is an index seek.
    --
    -- NULL for everything that has no order worth asking about. Numbers
    -- have one and do not get a column, because no surface asks for a
    -- number range yet; when one does it is the same move again.
    at_ms  INTEGER,
    PRIMARY KEY (entity, prop, device, seq)
) WITHOUT ROWID;

-- Everything with a given value: the lookup that makes 'everything with
-- Anna' a reference join rather than a text search (core.md §2). It is
-- also how 'every task' is answered — kind is a cell like any other.
CREATE INDEX IF NOT EXISTS cells_by_value ON cells(prop, value);
CREATE INDEX IF NOT EXISTS cells_by_entity ON cells(entity);
-- Partial: only dated cells are in it, so a box of undated notes pays
-- nothing for the calendar's index.
CREATE INDEX IF NOT EXISTS cells_by_time ON cells(prop, at_ms)
    WHERE at_ms IS NOT NULL;
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
                ensure_entity(tx, *entity)?;
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
                ensure_entity(tx, *entity)?;
                retire(tx, *entity, *prop, replaces)?;
            }
        }
        touch(tx, o.entity(), g.hlc.wall_ms as i64)?;
    }
    Ok(())
}

/// Raise the last-touched stamp, never lower it.
///
/// `MAX` rather than assignment: replay feeds groups in log order but sync
/// does not, and a late op from a device whose clock is behind must not
/// make an entity look older than an edit that already landed.
fn touch(tx: &Transaction, id: EntityId, wall_ms: i64) -> Result<(), rusqlite::Error> {
    tx.execute(
        "UPDATE entities SET touched_ms = MAX(touched_ms, ?2) WHERE id = ?1",
        rusqlite::params![&id.0[..], wall_ms],
    )?;
    Ok(())
}

/// A cell can arrive before the create that made its entity — sync
/// delivers one device's stream in order, not the whole mesh's. The row
/// is created from the id, which carries its own timestamp, so nothing is
/// invented.
fn ensure_entity(tx: &Transaction, id: EntityId) -> Result<(), rusqlite::Error> {
    tx.execute(
        "INSERT OR IGNORE INTO entities(id, created_ms, touched_ms) VALUES (?1, ?2, 0)",
        rusqlite::params![&id.0[..], id.millis() as i64],
    )?;
    Ok(())
}

/// When a value is, in milliseconds — the sort key behind `at_ms`.
///
/// **A floating day and a real instant are put on one line here, and that
/// is an approximation.** `DateSpec::Day` is deliberately zone-free (op.rs:
/// a day that shifts when the device changes zone is the most common quiet
/// corruption in a personal app), so calling it midnight-UTC to compare it
/// with an instant is a reading, not a fact. It is the right reading for
/// what this column is for — ordering a list and cutting a range — and a
/// caller that needs the day itself reads the value, which still holds it
/// exactly.
pub fn at_ms(value: &op::Value) -> Option<i64> {
    match value {
        op::Value::Date(op::DateSpec::Day(d)) => Some(*d as i64 * 86_400_000),
        op::Value::Date(op::DateSpec::Instant { ms, .. }) => Some(*ms),
        _ => None,
    }
}

fn put(
    tx: &Transaction,
    entity: EntityId,
    prop: EntityId,
    dot: Dot,
    value: &op::Value,
) -> Result<(), rusqlite::Error> {
    tx.execute(
        "INSERT OR REPLACE INTO cells(entity, prop, device, seq, value, at_ms)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![
            &entity.0[..],
            &prop.0[..],
            &dot.device.0[..],
            dot.seq as i64,
            op::encode_value(value),
            at_ms(value),
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
    let eat = |bytes: &[u8], h: &mut u64| {
        for b in bytes {
            *h ^= *b as u64;
            *h = h.wrapping_mul(0x0000_0100_0000_01b3);
        }
    };

    let mut stmt =
        conn.prepare("SELECT id, created_ms, touched_ms FROM entities ORDER BY id")?;
    let rows = stmt.query_map([], |r| {
        Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?))
    })?;
    for row in rows {
        let (id, created, touched) = row?;
        eat(&id, &mut h);
        eat(&created.to_le_bytes(), &mut h);
        eat(&touched.to_le_bytes(), &mut h);
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

/// Does the box hold this thing at all?
///
/// Not "is it live" — a trashed entity exists. This is the question
/// `set_content` asks of a `[[link]]`'s target: a link to something in
/// the trash is a link to something that still exists, and emptying a
/// note's neighbour must not be a reason this note's save fails.
pub fn exists(conn: &Connection, id: EntityId) -> Result<bool, rusqlite::Error> {
    let n: i64 = conn.query_row(
        "SELECT COUNT(*) FROM entities WHERE id = ?1",
        rusqlite::params![&id.0[..]],
        |r| r.get(0),
    )?;
    Ok(n > 0)
}

pub fn entity_count(conn: &Connection) -> Result<u64, rusqlite::Error> {
    let n: i64 = conn.query_row("SELECT COUNT(*) FROM entities", [], |r| r.get(0))?;
    Ok(n as u64)
}

// ---- the reads a surface makes ----------------------------------------
//
// **Every one of these is an index seek, and that is the whole point.**
// The core answers questions by handing a shell the entire box and letting
// it search — 3.5 MB and 39 ms at 6,400 notes, on every refresh, whatever
// is on screen. A question asked here costs what its ANSWER costs.

fn ids(rows: impl Iterator<Item = Result<Vec<u8>, rusqlite::Error>>) -> Result<Vec<EntityId>, rusqlite::Error> {
    let mut out = Vec::new();
    for row in rows {
        let bytes = row?;
        if bytes.len() == 16 {
            let mut id = [0u8; 16];
            id.copy_from_slice(&bytes);
            out.push(EntityId(id));
        }
    }
    Ok(out)
}

/// Everything whose `prop` cell holds exactly this value — every task,
/// everything in Work, every note mentioning Anna.
///
/// **One live value is not assumed.** A contended register has two rows
/// and this returns the entity once per matching row, so callers that
/// care de-duplicate; `DISTINCT` here would hide contention rather than
/// report it.
pub fn with_value(
    conn: &Connection,
    prop: EntityId,
    value: &op::Value,
) -> Result<Vec<EntityId>, rusqlite::Error> {
    let mut stmt = conn.prepare(
        "SELECT DISTINCT entity FROM cells WHERE prop = ?1 AND value = ?2 ORDER BY entity",
    )?;
    let rows = stmt.query_map(
        rusqlite::params![&prop.0[..], op::encode_value(value)],
        |r| r.get::<_, Vec<u8>>(0),
    )?;
    ids(rows)
}

/// Everything whose `prop` is a time inside `[from_ms, to_ms]`, soonest
/// first. The calendar's window, Today's agenda and "due this week" are
/// all this one query.
pub fn in_window(
    conn: &Connection,
    prop: EntityId,
    from_ms: i64,
    to_ms: i64,
) -> Result<Vec<(EntityId, i64)>, rusqlite::Error> {
    let mut stmt = conn.prepare(
        "SELECT entity, at_ms FROM cells
         WHERE prop = ?1 AND at_ms IS NOT NULL AND at_ms >= ?2 AND at_ms <= ?3
         ORDER BY at_ms, entity",
    )?;
    let rows = stmt.query_map(rusqlite::params![&prop.0[..], from_ms, to_ms], |r| {
        Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, i64>(1)?))
    })?;
    let mut out = Vec::new();
    for row in rows {
        let (bytes, at) = row?;
        if bytes.len() == 16 {
            let mut id = [0u8; 16];
            id.copy_from_slice(&bytes);
            out.push((EntityId(id), at));
        }
    }
    Ok(out)
}

/// Everything this entity holds, in one query.
///
/// **The N+1 this exists to stop** is the shape that made the core's file
/// projection quadratic: a loop over entities, each asking for one cell.
/// A surface builds a row from many properties, so it asks once.
pub fn cells_of(
    conn: &Connection,
    entity: EntityId,
) -> Result<Vec<(EntityId, Dot, op::Value)>, rusqlite::Error> {
    let mut stmt = conn.prepare(
        "SELECT prop, device, seq, value FROM cells WHERE entity = ?1 ORDER BY prop, device, seq",
    )?;
    let rows = stmt.query_map(rusqlite::params![&entity.0[..]], |r| {
        Ok((
            r.get::<_, Vec<u8>>(0)?,
            r.get::<_, Vec<u8>>(1)?,
            r.get::<_, i64>(2)?,
            r.get::<_, Vec<u8>>(3)?,
        ))
    })?;
    let mut out = Vec::new();
    for row in rows {
        let (p, d, s, v) = row?;
        if p.len() != 16 || d.len() != 8 {
            continue;
        }
        let mut prop = [0u8; 16];
        prop.copy_from_slice(&p);
        let mut device = [0u8; 8];
        device.copy_from_slice(&d);
        if let Some(value) = op::decode_value(&v) {
            out.push((
                EntityId(prop),
                Dot { device: crate::id::DeviceId(device), seq: s as u64 },
                value,
            ));
        }
    }
    Ok(out)
}

/// Every entity, oldest first — which is id order, because v7 ids carry
/// their own timestamp (`id.rs`).
pub fn all_entities(conn: &Connection) -> Result<Vec<EntityId>, rusqlite::Error> {
    let mut stmt = conn.prepare("SELECT id FROM entities ORDER BY id")?;
    let rows = stmt.query_map([], |r| r.get::<_, Vec<u8>>(0))?;
    ids(rows)
}

/// Every entity, most recently touched first — the order that makes a
/// list of notes useful: the one you were editing ten minutes ago is the
/// first row. It deliberately does not track OPENING: reading a note
/// without changing it does not bump it, because no op writes a visit and
/// a device-side one would disagree with every other surface.
pub fn by_touch(conn: &Connection) -> Result<Vec<EntityId>, rusqlite::Error> {
    let mut stmt =
        conn.prepare("SELECT id FROM entities ORDER BY touched_ms DESC, id DESC")?;
    let rows = stmt.query_map([], |r| r.get::<_, Vec<u8>>(0))?;
    ids(rows)
}

/// When this entity was last touched.
pub fn touched(conn: &Connection, id: EntityId) -> Result<i64, rusqlite::Error> {
    conn.query_row(
        "SELECT touched_ms FROM entities WHERE id = ?1",
        rusqlite::params![&id.0[..]],
        |r| r.get(0),
    )
    .or(Ok(0))
}
