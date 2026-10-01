//! THE ONE C SEAM. Every shell crosses here and nowhere else.
//!
//! **Every verb runs over the engine** (`surfaces::with_engine`) and
//! answers through `surfaces::deliver`: JSON out through an out-pointer,
//! or a code saying which thing went wrong — the value OR the fault,
//! exactly one. Ids cross as 32 hex characters. The verbs live by what
//! they are for:
//!
//! - `surfaces` — one read per screen: Today, Tasks, Notes, the day, the
//!   pool of open boxes, and the error codes;
//! - `basics` — the verbs every tap uses: make a thing, change a cell,
//!   throw it away, name the vocabulary;
//! - `writes` — bodies, links, history, undo, the clerk's consent;
//! - `finding` — search, the query grammar, workspaces, the trash.
//!
//! The core-era half of this crate — 58 verbs over `core/`'s log, the
//! snapshot builder they fed, and the converter's door — went in stage 5
//! of `design/rust-owns-the-mechanisms.md` (2026-09-29), with `core/`.
//! Nothing called them: the app moved onto the verbs above at slice 5b.

use std::ffi::{c_char, CString};

/// A body on the wire, in the shape the shell writes.
mod spans;

/// One read per screen, the pool of open boxes, and the error codes.
pub mod surfaces;

/// Bodies, links, history, undo, and the clerk's consent.
pub mod writes;

/// The verbs every tap uses: make a thing, change a cell, throw it away.
pub mod basics;

/// Finding things: search, the query grammar, workspaces, the trash.
pub mod finding;

/// Free a string a verb handed back through its out-pointer.
///
/// # Safety
/// `s` must be a pointer a `liv_*` verb returned, freed at most once.
#[no_mangle]
pub unsafe extern "C" fn liv_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}
