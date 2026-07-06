use serde::{Deserialize, Serialize};

use crate::entity::Cell;
use crate::value::Id;

/// Provenance, typed. "Why does this entity have a due date?" always has an
/// answer, and it cannot be a typo. This is who authored the change, not
/// who consented to it — consent is which door a write came through, never
/// this value. Accepting a proposal preserves the proposer's Author.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Author {
    User,
    /// The name of the proposer that drafted it.
    Proposer(String),
    /// The system itself, for changes no user or proposer initiated.
    System,
}

/// The only door. Every command records enough to reverse itself:
/// undo is not a feature bolted on later, it is the shape of a command.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Command {
    Create {
        entity: Id,
    },
    /// Never cascades. Never silently edits other entities.
    Trash {
        entity: Id,
    },
    Restore {
        entity: Id,
    },
    /// Set a property, create a relationship, add a type.
    AddCell {
        entity: Id,
        cell: Cell,
    },
    /// The cell is the `before` — enough to reverse.
    RemoveCell {
        entity: Id,
        cell: Cell,
    },
    /// The forwarding record a merge leaves behind. `before` is the
    /// prior forward (0 = none), so a redirect reverses like any command.
    Redirect {
        entity: Id,
        to: Id,
        before: Id,
    },
}

impl Command {
    /// Identifiers are never reused, deletion is soft:
    /// the inverse of birth is the trash, not oblivion.
    pub fn inverse(&self) -> Command {
        match self {
            Command::Create { entity } => Command::Trash { entity: *entity },
            Command::Trash { entity } => Command::Restore { entity: *entity },
            Command::Restore { entity } => Command::Trash { entity: *entity },
            Command::AddCell { entity, cell } => Command::RemoveCell {
                entity: *entity,
                cell: cell.clone(),
            },
            Command::RemoveCell { entity, cell } => Command::AddCell {
                entity: *entity,
                cell: cell.clone(),
            },
            Command::Redirect { entity, to, before } => Command::Redirect {
                entity: *entity,
                to: *before,
                before: *to,
            },
        }
    }
}

/// Commands composed into one user action, one undo step, one author.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Transaction {
    /// Position in history; the log is append-only.
    pub seq: u64,
    pub commands: Vec<Command>,
    pub label: String,
    /// Provenance: who authored this transaction.
    pub author: Author,
    pub time: i64,
    /// Set on undo and redo: the transaction this one reverses.
    /// The truth is never rewritten; history shows both.
    pub reverses: Option<u64>,
}

/// A transaction in quarantine. Nothing lands unconfirmed.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Proposal {
    pub commands: Vec<Command>,
    pub label: String,
    /// The proposer that drafted it. Preserved when accepted.
    pub author: Author,
    /// "mentions the Alpha kickoff -> reference Project Alpha"
    pub reason: String,
}
