//! lotus-core — milestone 1 of the build order in `productivity_app.md`.
//!
//! The core model, in memory: Entity, Cell, Value, commands, transactions,
//! undo. No UI, no disk. Where this code and the constitution disagree,
//! the constitution wins and this code gets fixed.

mod command;
mod entity;
mod persist;
mod store;
mod value;

pub use command::{Author, Command, Proposal, Transaction};
pub use entity::{props, Cell, Entity};
pub use persist::{PersistError, Session, LOG_VERSION};
pub use store::{Backlink, Store, StoreError};
pub use value::{Block, DateTime, FileRef, Id, Marks, RichText, Span, TextSpan, Value, NONE};
