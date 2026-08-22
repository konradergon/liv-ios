//! The Liv engine.
//!
//! An append-only log of operations is the truth; a materialised view
//! answers every question. Both live in one file, updated in a single
//! transaction per user action.
//!
//! The design is `design/core.md`, the on-disk encoding is
//! `design/op-format.md`, and the decisions that shaped both are recorded
//! in `design/core-decisions.md`. Where this crate and those documents
//! disagree, the documents are the specification and this is the bug.
//!
//! **Built beside `core/`, not inside it.** The shipping app keeps
//! running on `core/` until the engine can replace it, and the two never
//! have to agree. Nothing in here knows about iOS, and the C ABI lives in
//! a separate layer — so the desktop can link this crate directly, the
//! way it links its own core today.

pub mod id;
pub mod op;

pub use id::{DeviceId, Dot, EntityId, Hlc, IdGen};
pub use op::{Author, DateSpec, DecodeError, Group, Op, Value, RECORD_VERSION};
