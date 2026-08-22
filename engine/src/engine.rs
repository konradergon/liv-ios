//! The box: the log, the view, and the one transaction that keeps them
//! honest.
//!
//! **One user action is one transaction.** The group is appended and the
//! view is folded inside it, so either both land or neither does. That is
//! the whole reason the log lives in the same file as the tables it
//! implies — a second store would need a second commit, and the window
//! between them is where the two truths start to differ.

use rusqlite::Connection;

use crate::id::{DeviceId, Dot, EntityId, Hlc, IdGen};
use crate::log::{self, Hold, LogError, VersionVector};
use crate::op::{Author, Group, Op};
use crate::view;

pub struct Engine {
    conn: Connection,
    hold: Hold,
    ids: IdGen,
}

impl Engine {
    pub fn open(path: &std::path::Path, device: DeviceId) -> Result<Engine, LogError> {
        Engine::wrap(log::open(path)?, device)
    }

    pub fn open_in_memory(device: DeviceId) -> Result<Engine, LogError> {
        Engine::wrap(log::open_in_memory()?, device)
    }

    fn wrap(conn: Connection, device: DeviceId) -> Result<Engine, LogError> {
        conn.execute_batch(view::SCHEMA)?;
        Ok(Engine { conn, hold: Hold::default(), ids: IdGen::new(device) })
    }

    pub fn device(&self) -> DeviceId {
        self.ids.device()
    }

    pub fn conn(&self) -> &Connection {
        &self.conn
    }

    /// A fresh entity id, minted on this device.
    pub fn mint(&mut self, now_ms: u64) -> EntityId {
        self.ids.mint(now_ms)
    }

    /// Write one user action.
    ///
    /// Returns the dot of its first op, which is what `reverses` points at
    /// and what history names.
    pub fn commit(
        &mut self,
        ops: Vec<Op>,
        action: u16,
        author: Author,
        now_ms: u64,
    ) -> Result<Dot, LogError> {
        let device = self.ids.device();
        let first_seq = log::next_seq(&self.conn, device)?;
        let hlc = self.ids.stamp(now_ms);
        let g = Group { device, first_seq, hlc, author, action, reverses: None, ops };

        let tx = self.conn.transaction()?;
        log::append(&tx, &g)?;
        view::apply(&tx, &g)?;
        tx.commit()?;
        Ok(Dot { device, seq: first_seq })
    }

    /// Take a group from anywhere — this device or another — and return
    /// the groups that became applicable, in order.
    ///
    /// **The hold buffer.** A group whose first op does not follow the
    /// last one we hold is kept aside until the gap fills, so an op is
    /// never applied before the one it replaces. Receiving the same group
    /// twice is a no-op: sync re-sending a range it already sent is
    /// normal, not an error.
    pub fn receive(&mut self, g: Group) -> Result<Vec<Group>, LogError> {
        let device = g.device;
        let mut next = log::next_seq(&self.conn, device)?;

        if g.first_seq < next {
            return Ok(Vec::new());
        }
        if g.first_seq > next {
            self.hold.keep(g);
            return Ok(Vec::new());
        }

        let mut landed = vec![g];
        next += landed[0].ops.len() as u64;
        while let Some(waiting) = self.hold.take(device, next) {
            next += waiting.ops.len() as u64;
            landed.push(waiting);
        }

        // Everything released by one arrival lands together: a run that
        // was split by the network is still one contiguous piece of that
        // device's history.
        let tx = self.conn.transaction()?;
        for g in &landed {
            log::append(&tx, g)?;
            view::apply(&tx, g)?;
        }
        tx.commit()?;
        Ok(landed)
    }

    /// Throw the view away and rebuild it from the log.
    ///
    /// **This is the button that makes a bug in the view repairable.** A
    /// state-first store cannot offer it: there, a wrong value written is
    /// permanent. Here the log is untouched and the tables are a
    /// consequence, so a fixed fold can simply be re-run.
    pub fn replay(&mut self) -> Result<(), LogError> {
        let groups = log::all(&self.conn)?;
        let tx = self.conn.transaction()?;
        view::drop_all(&tx)?;
        tx.execute_batch(view::SCHEMA)?;
        for g in &groups {
            view::apply(&tx, g)?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn digest(&self) -> Result<u64, LogError> {
        Ok(view::digest(&self.conn)?)
    }

    pub fn version_vector(&self) -> Result<VersionVector, LogError> {
        log::version_vector(&self.conn)
    }

    pub fn next_seq(&self, device: DeviceId) -> Result<u64, LogError> {
        log::next_seq(&self.conn, device)
    }

    pub fn range(&self, device: DeviceId, from: u64) -> Result<Vec<Group>, LogError> {
        log::range(&self.conn, device, from)
    }

    pub fn groups(&self) -> Result<Vec<Group>, LogError> {
        log::all(&self.conn)
    }

    pub fn group_count(&self) -> Result<u64, LogError> {
        log::count(&self.conn)
    }

    pub fn held(&self) -> usize {
        self.hold.len()
    }

    pub fn entity_count(&self) -> Result<u64, LogError> {
        Ok(view::entity_count(&self.conn)?)
    }

    /// Every live value of one property on one entity.
    ///
    /// **More than one is contended, not broken.** The caller shows the
    /// choice; nothing here picks a winner (core.md §5).
    pub fn cell(
        &self,
        entity: EntityId,
        prop: EntityId,
    ) -> Result<Vec<(Dot, crate::op::Value)>, LogError> {
        Ok(view::cell(&self.conn, entity, prop)?)
    }

    /// The clock reading a caller should use when it needs one without
    /// writing.
    pub fn stamp(&mut self, now_ms: u64) -> Hlc {
        self.ids.stamp(now_ms)
    }
}
