//! P7/7a — the librarian: a file is added by reference (path + a byte hash),
//! never moved or copied; its bytes stay exactly where they are.

use lotus_core::*;
use lotus_services::{content, files, property_id, seed_if_fresh};

fn fresh_session(name: &str) -> (std::path::PathBuf, Session) {
    let path = std::env::temp_dir().join(name);
    cleanup(&path);
    let mut session = Session::open(&path).unwrap();
    seed_if_fresh(&mut session).unwrap();
    (path, session)
}

fn cleanup(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
}

#[test]
fn add_file_references_the_bytes_without_moving_them() {
    let (boxpath, mut session) = fresh_session("lotus_files_add.log");
    let doc = std::env::temp_dir().join("lotus_files_sample.md");
    std::fs::write(&doc, b"the quarterly report is late").unwrap();
    let docpath = doc.to_str().unwrap();

    let id = files::add_file(&mut session, docpath, DateTime::date(2026, 7, 7)).unwrap();
    assert_ne!(id, 0);

    let store = session.store();
    let e = store.get(id).unwrap();
    assert_eq!(e.get(props::NAME), Some(&Value::text("lotus_files_sample.md")));

    let file_prop = property_id(store, "file").unwrap();
    match e.get(file_prop) {
        Some(Value::File(f)) => {
            assert_eq!(f.path, docpath);
            assert_eq!(f.hash, files::hash_file(docpath).unwrap());
        }
        other => panic!("expected a file cell, got {other:?}"),
    }
    let format_prop = property_id(store, "format").unwrap();
    assert_eq!(e.get(format_prop), Some(&Value::text("md")));

    // The bytes were never moved or altered — the file still reads the same.
    assert_eq!(std::fs::read(&doc).unwrap(), b"the quarterly report is late");

    let _ = std::fs::remove_file(&doc);
    cleanup(&boxpath);
}

#[test]
fn a_one_byte_edit_changes_the_hash() {
    let a = std::env::temp_dir().join("lotus_files_h1.txt");
    let b = std::env::temp_dir().join("lotus_files_h2.txt");
    std::fs::write(&a, b"alpha").unwrap();
    std::fs::write(&b, b"alphb").unwrap();
    let ha = files::hash_file(a.to_str().unwrap()).unwrap();
    let hb = files::hash_file(b.to_str().unwrap()).unwrap();
    assert_ne!(ha, hb, "a changed byte must miss the cache");
    // and stable for the same bytes
    assert_eq!(ha, files::hash_file(a.to_str().unwrap()).unwrap());
    let _ = std::fs::remove_file(&a);
    let _ = std::fs::remove_file(&b);
}

#[test]
fn an_unreadable_path_is_an_error_not_a_phantom_entity() {
    let (boxpath, mut session) = fresh_session("lotus_files_missing.log");
    let before = session.store().entities().count();
    let r = files::add_file(&mut session, "/no/such/file.pdf", DateTime::date(2026, 7, 7));
    assert!(r.is_err());
    assert_eq!(session.store().entities().count(), before, "no entity on failure");
    cleanup(&boxpath);
}

#[test]
fn a_file_cell_is_never_hand_typed() {
    let (boxpath, mut session) = fresh_session("lotus_files_settype.log");
    let note = content::create_note(&mut session, DateTime::date(2026, 7, 7)).unwrap();
    // set through the string seam is refused — a file is added by reference.
    let r = content::set_property(&mut session, note, "file", "/Users/k/report.pdf");
    assert!(r.is_err());
    cleanup(&boxpath);
}

#[test]
fn seed_files_is_idempotent() {
    let (boxpath, mut session) = fresh_session("lotus_files_seed.log");
    let file_prop = property_id(session.store(), "file").unwrap();
    // Re-running the seed (as every open does) must not duplicate it.
    seed_if_fresh(&mut session).unwrap();
    assert_eq!(property_id(session.store(), "file"), Some(file_prop));
    let defs = session
        .store()
        .entities()
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "file")
                && e.get(props::VALUE_KIND).is_some()
        })
        .count();
    assert_eq!(defs, 1, "exactly one file property definition");
    cleanup(&boxpath);
}
