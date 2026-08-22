//! Identity: who wrote it, when, and what it is about.
//!
//! Three kinds, and they are not interchangeable (design/core.md §2):
//!
//! * [`EntityId`] names a THING. UUIDv7, so id order is creation order —
//!   twenty-one sites in the current tree sort by id and mean "oldest
//!   first", and v4 would shuffle them silently.
//! * [`DeviceId`] names a WRITER. Eight bytes, generated once at install,
//!   never reused.
//! * [`Dot`] names one WRITE: `(device, seq)`. It is the operation's name
//!   for as long as the box exists — how a device knows what it is
//!   missing, how a remove names what it removed, how two concurrent
//!   edits are told apart. `core-decisions.md` calls this the one
//!   irreversible decision.
//!
//! [`Hlc`] is separate and weaker on purpose: display order and tiebreaks
//! only. **A wall clock never destroys a value.** A device three days
//! ahead can mislabel a history row and win a tiebreak on screen; it
//! cannot make anything disappear.

/// A thing. 16 bytes, UUIDv7 layout.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub struct EntityId(pub [u8; 16]);

impl EntityId {
    pub const NONE: EntityId = EntityId([0; 16]);

    pub fn is_none(&self) -> bool {
        self.0 == [0; 16]
    }

    /// The 48-bit millisecond stamp v7 puts in the high bytes. This is
    /// what makes id order creation order, and it is readable without a
    /// lookup — the reason v7 was chosen over v4.
    pub fn millis(&self) -> u64 {
        let b = &self.0;
        ((b[0] as u64) << 40)
            | ((b[1] as u64) << 32)
            | ((b[2] as u64) << 24)
            | ((b[3] as u64) << 16)
            | ((b[4] as u64) << 8)
            | (b[5] as u64)
    }

    /// Lowercase hex, 32 characters. For logs and tests — never for the
    /// user, and never in a note's buffer: `core-decisions.md` decides
    /// that the editor's `[[…]]` token stops carrying a raw id.
    pub fn hex(&self) -> String {
        self.0.iter().map(|b| format!("{b:02x}")).collect()
    }

    pub fn from_hex(s: &str) -> Option<EntityId> {
        if s.len() != 32 {
            return None;
        }
        let mut out = [0u8; 16];
        for (i, byte) in out.iter_mut().enumerate() {
            *byte = u8::from_str_radix(s.get(i * 2..i * 2 + 2)?, 16).ok()?;
        }
        Some(EntityId(out))
    }
}

/// A writer. Eight bytes, generated once at install, never reused.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub struct DeviceId(pub [u8; 8]);

impl DeviceId {
    pub fn hex(&self) -> String {
        self.0.iter().map(|b| format!("{b:02x}")).collect()
    }
}

/// One write, named forever.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Dot {
    pub device: DeviceId,
    pub seq: u64,
}

/// Display order and tiebreaks. Never a merge input.
///
/// The third component of a hybrid logical clock is the device, and it
/// always equals the group header's, so it is not stored on the wire
/// (op-format.md §4).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Default)]
pub struct Hlc {
    /// Milliseconds since the Unix epoch.48 bits on the wire, which is
    /// good to the year 10889.
    pub wall_ms: u64,
    /// Ticks within one millisecond, so two writes in the same
    /// millisecond still have an order.
    pub ctr: u32,
}

/// Mints entity ids, and the clock that stamps them.
///
/// **Seeded from the device, not from the operating system.** The engine
/// has no randomness dependency and wants none: two devices never
/// collide because their seeds differ, and a test can mint a known
/// sequence by construction. The eight bytes of a `DeviceId` are the only
/// place real entropy is needed, and that is the caller's job, once, at
/// install.
///
/// **Monotonic within a millisecond**, which `core-decisions.md` says
/// must be verified rather than assumed: twenty-one ordering sites break
/// silently if two ids minted in the same millisecond come back out of
/// order.
pub struct IdGen {
    device: DeviceId,
    state: u64,
    last_ms: u64,
    /// The 12 bits v7 reserves next to the timestamp, used here as a
    /// within-millisecond counter rather than as noise.
    tick: u16,
}

impl IdGen {
    pub fn new(device: DeviceId) -> IdGen {
        // Mix the device bytes so two devices with adjacent ids do not
        // produce adjacent streams.
        let seed = u64::from_le_bytes(device.0);
        IdGen { device, state: splitmix(seed ^ 0x9e37_79b9_7f4a_7c15), last_ms: 0, tick: 0 }
    }

    pub fn device(&self) -> DeviceId {
        self.device
    }

    fn next_random(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9e37_79b9_7f4a_7c15);
        splitmix(self.state)
    }

    /// Advance the clock by one step and return where it landed.
    ///
    /// Two rules, and the second is the one a test caught:
    ///
    /// * **Never go backwards.** A clock that jumps back — a time-zone
    ///   change, an NTP correction — would otherwise mint ids that sort
    ///   before things created earlier.
    /// * **Borrow from the future rather than saturate.** v7 reserves
    ///   twelve bits beside the timestamp, so the 4,097th id in one
    ///   millisecond has nowhere left to count. Saturating there made two
    ///   ids compare equal on their ordered prefix and the sequence
    ///   stopped being monotonic — which is exactly what the twenty-one
    ///   ordering sites depend on. Stepping the millisecond instead keeps
    ///   the property at the cost of running microscopically ahead of the
    ///   wall clock under a burst, which is what a hybrid clock is for.
    fn advance(&mut self, now_ms: u64) -> (u64, u16) {
        let ms = now_ms.max(self.last_ms);
        if ms == self.last_ms {
            if self.tick >= 0x0fff {
                self.last_ms += 1;
                self.tick = 0;
            } else {
                self.tick += 1;
            }
        } else {
            self.last_ms = ms;
            self.tick = 0;
        }
        (self.last_ms, self.tick)
    }

    /// One id, stamped `now_ms`. The caller supplies the clock so the
    /// engine stays free of `SystemTime` and a test can drive it.
    pub fn mint(&mut self, now_ms: u64) -> EntityId {
        let (ms, tick) = self.advance(now_ms);

        let mut out = [0u8; 16];
        out[0] = (ms >> 40) as u8;
        out[1] = (ms >> 32) as u8;
        out[2] = (ms >> 24) as u8;
        out[3] = (ms >> 16) as u8;
        out[4] = (ms >> 8) as u8;
        out[5] = ms as u8;
        // version 7 in the high nibble, then 12 bits of counter
        out[6] = 0x70 | ((tick >> 8) & 0x0f) as u8;
        out[7] = (tick & 0xff) as u8;
        let r = self.next_random();
        out[8..16].copy_from_slice(&r.to_be_bytes());
        // RFC 4122 variant in the top two bits of byte 8
        out[8] = (out[8] & 0x3f) | 0x80;
        EntityId(out)
    }

    /// The clock reading to stamp a group with, given the wall time.
    pub fn stamp(&mut self, now_ms: u64) -> Hlc {
        let (ms, tick) = self.advance(now_ms);
        Hlc { wall_ms: ms, ctr: tick as u32 }
    }
}

fn splitmix(mut x: u64) -> u64 {
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    x ^ (x >> 31)
}
