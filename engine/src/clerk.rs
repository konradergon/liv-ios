//! The quarantine queue: nothing lands unconfirmed.
//!
//! `Author::Proposer` has been in the op format since Phase 2, with the
//! comment that explains it: *"a proposal is an operation that has not
//! been applied, carrying the proposer's name here instead of the user's
//! — which is what makes 'nothing lands unconfirmed' a property of the
//! type."* This is what uses it.
//!
//! **The pending drafts are not stored, and that is `core/`'s design.**
//! The sweep is a pure function of the box — `services/src/clerk.rs`:
//! *"every date the clerk proposes derives from the store alone, so the
//! sweep is identical in every process"* — so a draft is RECOMPUTED, not
//! kept. Keeping it would be a second copy of something derivable, which
//! is the defect this whole crate is arranged against.
//!
//! What must persist is the REFUSAL. Declining is not forgetting: the
//! refusal moves beside the queue so proposers drop duplicates of it, and
//! nothing asks twice.
//!
//! ## One open question, recorded rather than answered
//!
//! **A refusal does not sync.** It is device-local here, exactly as it is
//! in `core/` (which keeps it in `<log>.declined`, beside the log and not
//! in it). That means declining a suggestion on the laptop does not stop
//! the phone offering it. Making it travel is a real design decision —
//! it would put "the user said no" in the log, which is arguably where it
//! belongs — and it is the owner's to make, not one to slip in here.

use crate::engine::Engine;
use crate::log::LogError;
use crate::op::{Author, Op};
use crate::write::{action, WriteError};

/// A write that has not happened, and the case for it.
#[derive(Debug, Clone, PartialEq)]
pub struct Proposal {
    pub ops: Vec<Op>,
    /// Which proposer drafted it — `dates`, `mentions`, `area`, and the
    /// rest. Preserved when accepted, so the box can say afterwards whose
    /// suggestion was taken.
    pub proposer: String,
    /// "mentions the Alpha kickoff → reference Project Alpha". What the
    /// user reads before saying yes.
    pub reason: String,
}

impl Proposal {
    /// What makes this proposal THIS proposal.
    ///
    /// The sweep re-derives its drafts in every process, so a refusal has
    /// to recognise a recomputed proposal rather than a remembered object.
    /// Over the ops, the proposer and the REASON — refusing "because it
    /// mentions Alpha" is not refusing "because it is due Tuesday", and a
    /// proposer that finds the same write for a better reason is entitled
    /// to ask.
    pub fn fingerprint(&self) -> u64 {
        let mut bytes = Vec::new();
        for op in &self.ops {
            bytes.extend_from_slice(&crate::op::op_bytes(op));
        }
        bytes.push(0);
        bytes.extend_from_slice(self.proposer.as_bytes());
        bytes.push(0);
        bytes.extend_from_slice(self.reason.as_bytes());
        crate::content::fnv(&bytes)
    }
}

impl Engine {
    /// Say yes. The write lands under the PROPOSER's name, not the user's.
    ///
    /// Consent is not a bypass: the ops go through the same gate every
    /// write does. A clerk is a proposer, not an author.
    pub fn accept(&mut self, p: &Proposal, now_ms: u64) -> Result<crate::id::Dot, WriteError> {
        self.accept_all(std::slice::from_ref(p), now_ms)
    }

    /// Say yes to a set, as ONE action.
    ///
    /// **All or nothing.** Half a consent is worse than none: the user
    /// agreed to a set, and a set that half-landed is not what they
    /// agreed to. One group, so one undo takes the lot back.
    pub fn accept_all(
        &mut self,
        ps: &[Proposal],
        now_ms: u64,
    ) -> Result<crate::id::Dot, WriteError> {
        if ps.is_empty() {
            return Err(WriteError::Refused(crate::model::Refused::WrongKind));
        }
        let mut ops = Vec::new();
        for p in ps {
            for op in &p.ops {
                self.vet_op(op)?;
                ops.push(op.clone());
            }
        }
        // One author for one group, and a mixed set is the clerk speaking
        // as itself rather than as any one of its proposers.
        let author = match ps {
            [only] => Author::Proposer(only.proposer.clone()),
            _ if ps.iter().all(|p| p.proposer == ps[0].proposer) => {
                Author::Proposer(ps[0].proposer.clone())
            }
            _ => Author::Proposer("clerk".into()),
        };
        self.commit(ops, action::SET, author, now_ms)
            .map_err(WriteError::Log)
    }

    /// Say no. The refusal persists; nothing asks again.
    ///
    /// Not a ban — see `accept`, which still works on a declined
    /// proposal. It stops the CLERK offering it, and leaves the user free
    /// to change their mind.
    pub fn decline(&self, p: &Proposal) -> Result<(), LogError> {
        crate::view::decline(self.conn(), p.fingerprint())?;
        Ok(())
    }

    pub fn is_declined(&self, p: &Proposal) -> Result<bool, LogError> {
        Ok(crate::view::is_declined(self.conn(), p.fingerprint())?)
    }
}
