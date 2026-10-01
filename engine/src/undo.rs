//! Undo, as a reading of the log.
//!
//! `Group.reverses` has been in the op format since Phase 2 with nothing
//! writing it. This writes it, with `core/`'s semantics — two undo buttons
//! that behave differently is a defect even while only one of them ships.
//!
//! **There is no undo stack.** `core/` keeps two `Vec<u64>` in memory and
//! rebuilds them on load; that is a second place for the truth to live,
//! and rebuilding costs a scan of the whole history at open — which is
//! exactly the property the engine was chosen for (0.3 ms and flat,
//! `rust-owns-the-mechanisms.md` §1). So the answer is computed instead,
//! by walking this device's groups BACKWARD and stopping at the first one
//! that is still in effect:
//!
//! * a group that a later group reverses is **cancelled**, and contributes
//!   nothing — not even the cancellation it was itself performing;
//! * a live group that reverses something cancels its target and the walk
//!   continues;
//! * the first live group that reverses nothing is what undo takes.
//!
//! In a box nobody has undone in, that walk reads ONE group. Its length is
//! bounded by how deep the user has undone, never by the size of the box.
//!
//! **Undo is what YOU did on THIS device.** `core/` never had to say so —
//! one device, one history. Here a box holds both ends of a sync, and
//! "take back the last thing that happened" would let either end undo the
//! other's write, and race while doing it.

use crate::engine::Engine;
use crate::id::{Dot, EntityId};
use crate::log::{self, LogError};
use crate::model::prop;
use crate::op::{Author, Op, Value};
use crate::write::{action, WriteError};

/// What the walk found at the tail of this device's history.
struct Tail {
    /// The newest live group that reverses nothing — what undo takes.
    undo: Option<Dot>,
    /// The newest live group, if it reverses a plain action — what redo
    /// takes. A redo reverses an UNDO, so the newest live group being a
    /// redo means there is nothing further forward to go to.
    redo: Option<Dot>,
}

impl Engine {
    /// The action undo would take back, if there is one.
    pub fn undoable(&self) -> Result<Option<Dot>, LogError> {
        Ok(self.tail()?.undo)
    }

    /// The action redo would put back, if there is one.
    pub fn redoable(&self) -> Result<Option<Dot>, LogError> {
        Ok(self.tail()?.redo)
    }

    /// Take back this device's last action.
    pub fn undo(&mut self, now_ms: u64) -> Result<Dot, WriteError> {
        let target = self.tail()?.undo.ok_or(WriteError::NothingToUndo)?;
        self.reverse(target, now_ms)
    }

    /// And put it back — the inverse of the inverse, appended again.
    pub fn redo(&mut self, now_ms: u64) -> Result<Dot, WriteError> {
        let target = self.tail()?.redo.ok_or(WriteError::NothingToRedo)?;
        self.reverse(target, now_ms)
    }

    fn tail(&self) -> Result<Tail, LogError> {
        let me = self.device();
        // Seqs a later, live group reverses. Small: it holds one entry per
        // step the user has undone, not one per group in the box.
        let mut cancelled: std::collections::HashSet<u64> = std::collections::HashSet::new();
        let mut newest_live: Option<(Dot, Option<Dot>)> = None;
        let mut undo: Option<Dot> = None;

        log::walk_back(self.conn(), me, |g| {
            if cancelled.contains(&g.first_seq) {
                // Reversed by something later, so it is not in effect —
                // and neither is the cancellation it was performing. This
                // is the whole of how redo works: a redo cancels an undo,
                // which puts the undo's target back in effect.
                return true;
            }
            let dot = Dot { device: g.device, seq: g.first_seq };
            if newest_live.is_none() {
                newest_live = Some((dot, g.reverses));
            }
            match g.reverses {
                Some(t) => {
                    if t.device == me {
                        cancelled.insert(t.seq);
                    }
                    true
                }
                None => {
                    undo = Some(dot);
                    false
                }
            }
        })?;

        // Redo is offered only when the newest live group is an UNDO —
        // that is, when it reverses a plain action. When it is itself a
        // redo there is nowhere further forward, and when it is a plain
        // write the branch it would have gone to has been written over.
        let redo = match newest_live {
            Some((dot, Some(target))) if self.is_plain(target)? => Some(dot),
            _ => None,
        };
        Ok(Tail { undo, redo })
    }

    /// Did that group reverse nothing — i.e. is it a thing the user did,
    /// rather than an undo or a redo of one?
    fn is_plain(&self, dot: Dot) -> Result<bool, LogError> {
        Ok(log::group_at(self.conn(), dot)?.map(|g| g.reverses.is_none()).unwrap_or(false))
    }

    /// Append the inverse of one group, pointing at it.
    fn reverse(&mut self, target: Dot, now_ms: u64) -> Result<Dot, WriteError> {
        // `tail` found this dot in the log a moment ago, so the only way
        // it is gone is a box truncated underneath us.
        let g = log::group_at(self.conn(), target)?.ok_or(WriteError::NothingToUndo)?;

        // **A created thing is undone by trashing it, and nothing else.**
        //
        // `create` is three ops (the entity, its kind, its name), and
        // reversing all three would leave a trashed row with no kind and
        // no name — unreadable in the Trash, which is where the user has
        // to find it to get it back. `op.rs` has no Delete precisely
        // because Create's inverse is Trash; the other two ops are moot
        // once the thing is not live, and keeping them is what makes the
        // trash entry still say what it was.
        let ops = if g.ops.iter().any(|o| matches!(o, Op::CreateEntity { .. })) {
            let entity = g.ops[0].entity();
            vec![Op::SetCell {
                entity,
                prop: prop::TRASHED,
                value: Value::Bool(true),
                replaces: self.dots_of(entity, prop::TRASHED)?,
            }]
        } else {
            // Reverse order, like `core/`: the ops of one action are
            // applied forward and taken back backward.
            let mut out = Vec::new();
            for o in g.ops.iter().rev() {
                out.extend(self.inverse(o)?);
            }
            out
        };

        let dot = self.commit_reversing(ops, action::UNDO, Author::User, now_ms, Some(target))?;
        Ok(dot)
    }

    /// The ops that take one op back.
    ///
    /// **Every one names what is LIVE, not what was.** An inverse is an
    /// ordinary write and obeys the ordinary rule — `set` and `remove`
    /// both name the dots they can see — so `replaces` comes from the
    /// cell as it stands, never from the op being undone. Naming the
    /// historical dot is the obvious thing and it is wrong: after one
    /// undo the value is live under the dot THAT undo wrote, so the
    /// second undo in a row would retire nothing and leave both values
    /// standing, which reads as a contended cell the user never caused.
    /// The undone op is consulted for one thing only — the value it
    /// replaced, which lives nowhere but the log.
    fn inverse(&self, o: &Op) -> Result<Vec<Op>, LogError> {
        Ok(match o {
            // Only reachable for a group that creates nothing else, which
            // `reverse` has already handled. Kept total rather than
            // unreachable!(): a panic in undo is worse than a trash.
            Op::CreateEntity { entity } => vec![Op::SetCell {
                entity: *entity,
                prop: prop::TRASHED,
                value: Value::Bool(true),
                replaces: self.dots_of(*entity, prop::TRASHED)?,
            }],

            Op::SetCell { entity, prop, value, replaces } => {
                let live = self.dots_of(*entity, *prop)?;
                let old: Vec<Value> =
                    replaces.iter().filter_map(|d| self.value_at(*d).ok().flatten()).collect();
                if old.is_empty() {
                    // Nothing was there before, so nothing is there
                    // afterwards — not "" and not a zero. A
                    // `RemoveFromSet` over the live dots retires the cell
                    // and puts nothing in its place, which is the only
                    // shape the four ops give for "unset".
                    //
                    // Also the honest answer when the replaced dots are
                    // gone from a truncated log: clearing beats leaving
                    // the new value standing as if the undo never ran.
                    vec![Op::RemoveFromSet {
                        entity: *entity,
                        prop: *prop,
                        value: value.clone(),
                        replaces: live,
                    }]
                } else {
                    // Put back every value this write named — ALL of
                    // them. A register with two live values is a
                    // contended cell, and collapsing it to one during an
                    // undo would decide a conflict the user was never
                    // shown. Only the first op retires what is live; the
                    // rest add alongside, which restores the contention.
                    old.into_iter()
                        .enumerate()
                        .map(|(n, v)| Op::SetCell {
                            entity: *entity,
                            prop: *prop,
                            value: v,
                            replaces: if n == 0 { live.clone() } else { vec![] },
                        })
                        .collect()
                }
            }

            Op::AddToSet { entity, prop, value } => vec![Op::RemoveFromSet {
                entity: *entity,
                prop: *prop,
                value: value.clone(),
                replaces: self.dots_carrying(*entity, *prop, value)?,
            }],

            // **What came back is what the removal RETIRED**, read out of
            // the log — not the op's own `value`.
            //
            // For a set removal the two are the same thing, and were the
            // only case when this said `value`. But `RemoveFromSet` is
            // also the only shape the four ops give for UNSET, and an
            // unset names the dots of whatever was there while carrying a
            // placeholder value that means nothing. Restoring that
            // placeholder put `Text("")` into a date cell — a blank where
            // a date had been, which is not what was there and not
            // nothing either.
            //
            // Distinct values, so ONE add however many dots the removal
            // retired: a set holds a value or it does not, and the row
            // count was an artifact of two devices adding the same thing.
            // Several DIFFERENT values means a contended register, and
            // all of them come back — collapsing it here would decide a
            // conflict the user was never shown.
            Op::RemoveFromSet { entity, prop, value, replaces } => {
                let mut old: Vec<Value> = Vec::new();
                for d in replaces {
                    if let Ok(Some(v)) = self.value_at(*d) {
                        if !old.contains(&v) {
                            old.push(v);
                        }
                    }
                }
                // Nothing readable — a truncated log, or a removal that
                // named no dots. The op's own value is the best guess
                // left, and it is what a set removal meant anyway.
                if old.is_empty() {
                    old.push(value.clone());
                }
                old.into_iter()
                    .map(|v| Op::AddToSet { entity: *entity, prop: *prop, value: v })
                    .collect()
            }
        })
    }

    /// The live dots of one cell carrying exactly this value — what
    /// `remove` names, and what taking an `add` back has to name.
    fn dots_carrying(
        &self,
        entity: EntityId,
        prop: EntityId,
        value: &Value,
    ) -> Result<Vec<Dot>, LogError> {
        Ok(self
            .cell(entity, prop)?
            .into_iter()
            .filter(|(_, v)| v == value)
            .map(|(d, _)| d)
            .collect())
    }

    /// The live dots of one cell — what a write has to name to replace.
    fn dots_of(&self, entity: EntityId, prop: EntityId) -> Result<Vec<Dot>, LogError> {
        Ok(self.cell(entity, prop)?.into_iter().map(|(d, _)| d).collect())
    }

    /// The value one op wrote, read back out of the log. Retired cells are
    /// deleted from the view (`view::retire`), so the log is the only
    /// place an overwritten value still exists — which is the point of
    /// there being a log.
    fn value_at(&self, dot: Dot) -> Result<Option<Value>, LogError> {
        let Some(g) = log::group_at(self.conn(), dot)? else { return Ok(None) };
        let Some(i) = dot.seq.checked_sub(g.first_seq) else { return Ok(None) };
        Ok(match g.ops.get(i as usize) {
            Some(Op::SetCell { value, .. }) | Some(Op::AddToSet { value, .. }) => {
                Some(value.clone())
            }
            _ => None,
        })
    }
}
