//! The one C seam the macOS shell crosses — milestone 4.
//!
//! Three functions: open, capture, close. The shell holds an opaque
//! pointer and never sees an entity, a command, or a byte of the log.
//! Everything below this seam is platform-free.

use std::ffi::{c_char, CStr};
use std::ptr;

use chrono::{Datelike, Local, Timelike};

use lotus_core::{DateTime, Session};

/// Opaque to the shell.
pub struct LotusSession(Session);

/// Open (or create) the box at `path`, seeded if fresh.
/// Returns null on failure.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_open(path: *const c_char) -> *mut LotusSession {
    if path.is_null() {
        return ptr::null_mut();
    }
    let Ok(path) = CStr::from_ptr(path).to_str() else {
        return ptr::null_mut();
    };
    if let Some(dir) = std::path::Path::new(path).parent() {
        if std::fs::create_dir_all(dir).is_err() {
            return ptr::null_mut();
        }
    }
    let Ok(mut session) = Session::open(path) else {
        return ptr::null_mut();
    };
    if lotus_services::seed_if_fresh(&mut session).is_err() {
        return ptr::null_mut();
    }
    Box::into_raw(Box::new(LotusSession(session)))
}

/// Capture one scrap. Returns the new entity's id, or 0 on failure —
/// 0 is never a valid id. Whitespace-only text is a failure, not a scrap.
///
/// # Safety
/// `session` must be a pointer returned by `lotus_open` and not yet closed;
/// `text` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn lotus_capture(session: *mut LotusSession, text: *const c_char) -> u64 {
    let Some(session) = session.as_mut() else {
        return 0;
    };
    if text.is_null() {
        return 0;
    }
    let Ok(text) = CStr::from_ptr(text).to_str() else {
        return 0;
    };
    let text = text.trim();
    if text.is_empty() {
        return 0;
    }
    let now = Local::now();
    let created = DateTime::at(
        now.year(),
        now.month(),
        now.day(),
        now.hour(),
        now.minute(),
    );
    lotus_services::capture(&mut session.0, text, created).unwrap_or(0)
}

/// Close the session. Passing null is a no-op. The pointer must not be
/// used again.
///
/// # Safety
/// `session` must be null or a pointer returned by `lotus_open`,
/// closed at most once.
#[no_mangle]
pub unsafe extern "C" fn lotus_close(session: *mut LotusSession) {
    if !session.is_null() {
        drop(Box::from_raw(session));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn the_seam_roundtrips() {
        let path = std::env::temp_dir().join("lotus_ffi_roundtrip.log");
        let _ = std::fs::remove_file(&path);
        let c_path = CString::new(path.to_str().unwrap()).unwrap();

        let session = unsafe { lotus_open(c_path.as_ptr()) };
        assert!(!session.is_null());

        let text = CString::new("Call Anna Friday").unwrap();
        let id = unsafe { lotus_capture(session, text.as_ptr()) };
        assert_ne!(id, 0);

        // Whitespace is not a thought.
        let blank = CString::new("   ").unwrap();
        assert_eq!(unsafe { lotus_capture(session, blank.as_ptr()) }, 0);

        unsafe { lotus_close(session) };

        // What the shell wrote, the rest of the system reads.
        let session = Session::open(&path).unwrap();
        let entity = session.store().get(id).unwrap();
        assert!(entity.get(lotus_core::props::CONTENT).is_some());
        assert!(entity.get(lotus_core::props::CREATED).is_some());
        let _ = std::fs::remove_file(&path);
    }
}
