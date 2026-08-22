//! The operations, and the bytes they become.
//!
//! **This module is the format** (design/op-format.md). Not a derive
//! macro: the current log is `#[derive(Serialize)]` on a Rust type, which
//! means renaming a field silently changes what is on disk forever, and
//! `core.md` promises a decoder forever. A promise cannot rest on a
//! macro's output, so the layout is written by hand, byte by byte, and
//! the document and this file are checked against each other by tests.
//!
//! Four op kinds. Trash, restore and redirect are `SetCell` on reserved
//! properties rather than kinds of their own — which keeps the vocabulary
//! at four and gives them merge rules for free.

use crate::id::{DeviceId, Dot, EntityId, Hlc};

/// The record grammar this build writes.
pub const RECORD_VERSION: u8 = 1;

/// What one write does.
#[derive(Debug, Clone, PartialEq)]
pub enum Op {
    /// A thing begins to exist.
    CreateEntity { entity: EntityId },
    /// A single-valued property takes a value. `replaces` names the dots
    /// this write saw, which is what lets the register merge drop the
    /// entries a writer had already accounted for.
    SetCell { entity: EntityId, prop: EntityId, value: Value, replaces: Vec<Dot> },
    /// A multi-valued property gains one.
    AddToSet { entity: EntityId, prop: EntityId, value: Value },
    /// A multi-valued property loses the adds this writer could see.
    RemoveFromSet { entity: EntityId, prop: EntityId, value: Value, replaces: Vec<Dot> },
}

impl Op {
    pub fn entity(&self) -> EntityId {
        match self {
            Op::CreateEntity { entity }
            | Op::SetCell { entity, .. }
            | Op::AddToSet { entity, .. }
            | Op::RemoveFromSet { entity, .. } => *entity,
        }
    }

    fn tag(&self) -> u8 {
        match self {
            Op::CreateEntity { .. } => 0x01,
            Op::SetCell { .. } => 0x02,
            Op::AddToSet { .. } => 0x03,
            Op::RemoveFromSet { .. } => 0x04,
        }
    }
}

/// The closed value set. Closed means a value that does not fit is
/// refused at the door rather than discovered later.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Text(String),
    Number(f64),
    Bool(bool),
    Date(DateSpec),
    /// The only relationship mechanism, and the reason renaming a project
    /// is one write.
    Ref(EntityId),
    /// Photo and file bytes live outside the log, content-addressed. The
    /// cell holds the hash, never a path — a path is device-local and
    /// cannot cross a device boundary.
    Blob([u8; 32]),
}

/// A day is not an instant. "Due Friday" and "starts 14:00" are different
/// things, and a floating day that shifts when the device changes time
/// zone is the most common quiet corruption in a personal app.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DateSpec {
    /// Days since the Unix epoch. Floating: no zone, never shifts.
    Day(i32),
    /// A real instant, with the zone it was written in kept for display.
    Instant { ms: i64, tz: u16 },
}

/// Who wrote it. A proposal is an operation that has not been applied,
/// carrying the proposer's name here instead of the user's — which is
/// what makes "nothing lands unconfirmed" a property of the type.
#[derive(Debug, Clone, PartialEq)]
pub enum Author {
    User,
    Proposer(String),
}

/// One user action: the unit that lands whole or not at all, and the unit
/// undo reverses.
///
/// Device, clock and author are stored once per group rather than once
/// per op, because a group has exactly one of each by construction and
/// its ops have consecutive seqs.
#[derive(Debug, Clone, PartialEq)]
pub struct Group {
    pub device: DeviceId,
    pub first_seq: u64,
    pub hlc: Hlc,
    pub author: Author,
    /// A code from the frozen action table — what the user did, for
    /// history's sake ("new note", "set due").
    pub action: u16,
    /// The group this one undoes, if it is an undo.
    pub reverses: Option<Dot>,
    pub ops: Vec<Op>,
}

impl Group {
    /// The dot of op `i`. Seqs within a group are consecutive, so only
    /// the first is stored.
    pub fn dot(&self, i: usize) -> Dot {
        Dot { device: self.device, seq: self.first_seq + i as u64 }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecodeError {
    /// Ran out of bytes. On the last group in a log this is a torn tail,
    /// not corruption.
    Truncated,
    /// Bytes left over after a complete record.
    Trailing,
    /// A varint that could have been written shorter. Rejected so that
    /// one logical op has exactly one byte sequence — the replay gate
    /// asserts byte-identical, and a digest exchange detects drift.
    NonMinimalVarint,
    BadUtf8,
    /// NaN or an infinity. Neither has a defined ordering, and both would
    /// make two stores disagree about the same value.
    NotFinite,
    UnknownTag(u8),
    /// A record written by a newer build. The box is refused outright —
    /// there is deliberately no partial-view mode.
    UnsupportedVersion { found: u8, supported: u8 },
    /// The group's own checksum did not match its bytes.
    Checksum,
}

// ---- primitives -------------------------------------------------------

fn put_varint(out: &mut Vec<u8>, mut v: u64) {
    loop {
        let byte = (v & 0x7f) as u8;
        v >>= 7;
        if v == 0 {
            out.push(byte);
            return;
        }
        out.push(byte | 0x80);
    }
}

struct Reader<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Reader<'a> {
    fn new(b: &'a [u8]) -> Reader<'a> {
        Reader { b, i: 0 }
    }

    fn byte(&mut self) -> Result<u8, DecodeError> {
        let v = *self.b.get(self.i).ok_or(DecodeError::Truncated)?;
        self.i += 1;
        Ok(v)
    }

    fn take(&mut self, n: usize) -> Result<&'a [u8], DecodeError> {
        let end = self.i.checked_add(n).ok_or(DecodeError::Truncated)?;
        let s = self.b.get(self.i..end).ok_or(DecodeError::Truncated)?;
        self.i = end;
        Ok(s)
    }

    fn varint(&mut self) -> Result<u64, DecodeError> {
        let mut v: u64 = 0;
        let mut shift = 0;
        loop {
            let byte = self.byte()?;
            let payload = (byte & 0x7f) as u64;
            v |= payload << shift;
            if byte & 0x80 == 0 {
                // Minimality: a multi-byte varint whose last group is
                // zero could have been written shorter.
                if shift > 0 && payload == 0 {
                    return Err(DecodeError::NonMinimalVarint);
                }
                return Ok(v);
            }
            shift += 7;
            if shift >= 64 {
                return Err(DecodeError::NonMinimalVarint);
            }
        }
    }

    fn entity(&mut self) -> Result<EntityId, DecodeError> {
        let mut out = [0u8; 16];
        out.copy_from_slice(self.take(16)?);
        Ok(EntityId(out))
    }

    fn device(&mut self) -> Result<DeviceId, DecodeError> {
        let mut out = [0u8; 8];
        out.copy_from_slice(self.take(8)?);
        Ok(DeviceId(out))
    }

    fn text(&mut self) -> Result<String, DecodeError> {
        let n = self.varint()? as usize;
        let s = self.take(n)?;
        std::str::from_utf8(s).map(str::to_owned).map_err(|_| DecodeError::BadUtf8)
    }
}

// ---- values -----------------------------------------------------------

fn put_value(out: &mut Vec<u8>, v: &Value) {
    match v {
        Value::Text(s) => {
            out.push(0x01);
            put_varint(out, s.len() as u64);
            out.extend_from_slice(s.as_bytes());
        }
        Value::Number(n) => {
            out.push(0x02);
            out.extend_from_slice(&n.to_bits().to_le_bytes());
        }
        Value::Bool(b) => {
            out.push(0x03);
            out.push(u8::from(*b));
        }
        Value::Date(DateSpec::Day(d)) => {
            out.push(0x04);
            out.extend_from_slice(&d.to_le_bytes());
        }
        Value::Date(DateSpec::Instant { ms, tz }) => {
            out.push(0x05);
            out.extend_from_slice(&ms.to_le_bytes());
            out.extend_from_slice(&tz.to_le_bytes());
        }
        Value::Ref(id) => {
            out.push(0x06);
            out.extend_from_slice(&id.0);
        }
        Value::Blob(h) => {
            out.push(0x07);
            out.extend_from_slice(h);
        }
    }
}

fn get_value(r: &mut Reader) -> Result<Value, DecodeError> {
    Ok(match r.byte()? {
        0x01 => Value::Text(r.text()?),
        0x02 => {
            let mut b = [0u8; 8];
            b.copy_from_slice(r.take(8)?);
            let n = f64::from_bits(u64::from_le_bytes(b));
            if !n.is_finite() {
                return Err(DecodeError::NotFinite);
            }
            Value::Number(n)
        }
        0x03 => Value::Bool(r.byte()? != 0),
        0x04 => {
            let mut b = [0u8; 4];
            b.copy_from_slice(r.take(4)?);
            Value::Date(DateSpec::Day(i32::from_le_bytes(b)))
        }
        0x05 => {
            let mut m = [0u8; 8];
            m.copy_from_slice(r.take(8)?);
            let mut t = [0u8; 2];
            t.copy_from_slice(r.take(2)?);
            Value::Date(DateSpec::Instant {
                ms: i64::from_le_bytes(m),
                tz: u16::from_le_bytes(t),
            })
        }
        0x06 => Value::Ref(r.entity()?),
        0x07 => {
            let mut h = [0u8; 32];
            h.copy_from_slice(r.take(32)?);
            Value::Blob(h)
        }
        other => return Err(DecodeError::UnknownTag(other)),
    })
}

fn put_dots(out: &mut Vec<u8>, dots: &[Dot]) {
    put_varint(out, dots.len() as u64);
    for d in dots {
        out.extend_from_slice(&d.device.0);
        put_varint(out, d.seq);
    }
}

fn get_dots(r: &mut Reader) -> Result<Vec<Dot>, DecodeError> {
    let n = r.varint()? as usize;
    // A dot is at least 9 bytes, so a length larger than what remains is
    // a truncation rather than an allocation request.
    if n > r.b.len() {
        return Err(DecodeError::Truncated);
    }
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        let device = r.device()?;
        let seq = r.varint()?;
        out.push(Dot { device, seq });
    }
    Ok(out)
}

// ---- the group --------------------------------------------------------

/// The payload of one group, without its frame.
fn put_body(out: &mut Vec<u8>, g: &Group) {
    out.push(RECORD_VERSION);
    out.extend_from_slice(&g.device.0);
    put_varint(out, g.first_seq);
    put_varint(out, g.ops.len() as u64);
    // 48-bit wall clock, little endian: good to the year 10889.
    out.extend_from_slice(&g.hlc.wall_ms.to_le_bytes()[..6]);
    put_varint(out, g.hlc.ctr as u64);
    match &g.author {
        Author::User => out.push(0),
        Author::Proposer(name) => {
            out.push(1);
            put_varint(out, name.len() as u64);
            out.extend_from_slice(name.as_bytes());
        }
    }
    put_varint(out, g.action as u64);
    match g.reverses {
        // One byte when absent, where the JSON it replaces spent
        // seventeen on `"reverses":null` for every line that did not
        // use it.
        None => out.push(0),
        Some(d) => {
            out.push(1);
            out.extend_from_slice(&d.device.0);
            put_varint(out, d.seq);
        }
    }
    for op in &g.ops {
        out.push(op.tag());
        match op {
            Op::CreateEntity { entity } => out.extend_from_slice(&entity.0),
            Op::SetCell { entity, prop, value, replaces } => {
                out.extend_from_slice(&entity.0);
                out.extend_from_slice(&prop.0);
                put_value(out, value);
                put_dots(out, replaces);
            }
            Op::AddToSet { entity, prop, value } => {
                out.extend_from_slice(&entity.0);
                out.extend_from_slice(&prop.0);
                put_value(out, value);
            }
            Op::RemoveFromSet { entity, prop, value, replaces } => {
                out.extend_from_slice(&entity.0);
                out.extend_from_slice(&prop.0);
                put_value(out, value);
                put_dots(out, replaces);
            }
        }
    }
}

fn get_body(r: &mut Reader) -> Result<Group, DecodeError> {
    let version = r.byte()?;
    if version > RECORD_VERSION {
        return Err(DecodeError::UnsupportedVersion { found: version, supported: RECORD_VERSION });
    }
    let device = r.device()?;
    let first_seq = r.varint()?;
    let op_count = r.varint()? as usize;
    if op_count > r.b.len() {
        return Err(DecodeError::Truncated);
    }
    let w = r.take(6)?;
    let wall_ms = (w[0] as u64)
        | ((w[1] as u64) << 8)
        | ((w[2] as u64) << 16)
        | ((w[3] as u64) << 24)
        | ((w[4] as u64) << 32)
        | ((w[5] as u64) << 40);
    let ctr = r.varint()? as u32;
    let author = match r.byte()? {
        0 => Author::User,
        1 => Author::Proposer(r.text()?),
        other => return Err(DecodeError::UnknownTag(other)),
    };
    let action = r.varint()? as u16;
    let reverses = match r.byte()? {
        0 => None,
        1 => {
            let device = r.device()?;
            let seq = r.varint()?;
            Some(Dot { device, seq })
        }
        other => return Err(DecodeError::UnknownTag(other)),
    };

    let mut ops = Vec::with_capacity(op_count.min(64));
    for _ in 0..op_count {
        ops.push(match r.byte()? {
            0x01 => Op::CreateEntity { entity: r.entity()? },
            0x02 => Op::SetCell {
                entity: r.entity()?,
                prop: r.entity()?,
                value: get_value(r)?,
                replaces: get_dots(r)?,
            },
            0x03 => Op::AddToSet {
                entity: r.entity()?,
                prop: r.entity()?,
                value: get_value(r)?,
            },
            0x04 => Op::RemoveFromSet {
                entity: r.entity()?,
                prop: r.entity()?,
                value: get_value(r)?,
                replaces: get_dots(r)?,
            },
            other => return Err(DecodeError::UnknownTag(other)),
        });
    }

    Ok(Group { device, first_seq, hlc: Hlc { wall_ms, ctr }, author, action, reverses, ops })
}

/// One framed group: `varint length · body · crc32`.
///
/// The frame is what makes a torn tail drop the WHOLE action rather than
/// the last half of it. A reader that runs out of bytes mid-group, or
/// whose checksum does not match, stops there — everything before it
/// stands, and nothing is guessed at or repaired.
pub fn encode(g: &Group) -> Vec<u8> {
    let mut body = Vec::with_capacity(64);
    put_body(&mut body, g);
    let mut out = Vec::with_capacity(body.len() + 8);
    put_varint(&mut out, body.len() as u64);
    out.extend_from_slice(&body);
    out.extend_from_slice(&crc32(&body).to_le_bytes());
    out
}

/// Decode one framed group, returning it and how many bytes it used.
pub fn decode(bytes: &[u8]) -> Result<(Group, usize), DecodeError> {
    let mut frame = Reader::new(bytes);
    let len = frame.varint()? as usize;
    let body = frame.take(len)?;
    let mut sum = [0u8; 4];
    sum.copy_from_slice(frame.take(4)?);
    if u32::from_le_bytes(sum) != crc32(body) {
        return Err(DecodeError::Checksum);
    }
    let mut r = Reader::new(body);
    let g = get_body(&mut r)?;
    if r.i != body.len() {
        return Err(DecodeError::Trailing);
    }
    Ok((g, frame.i))
}

/// CRC-32/ISO-HDLC, computed without a table so the crate keeps its
/// promise of no dependencies. Fast enough: this runs once per user
/// action, over tens of bytes.
fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            let mask = (crc & 1).wrapping_neg();
            crc = (crc >> 1) ^ (0xedb8_8320 & mask);
        }
    }
    !crc
}
