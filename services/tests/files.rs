//! P7/7a — the librarian: a file is added by reference (path + a byte hash),
//! never moved or copied; its bytes stay exactly where they are.

use lotus_core::*;
use lotus_services::{content, files, property_id, search, seed_if_fresh};

/// Each test gets its OWN directory so its cache (a sibling of the box) is
/// isolated — parallel tests must not share `temp/cache`.
fn fresh_session(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("lotus_t_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.log");
    let mut session = Session::open(&path).unwrap();
    seed_if_fresh(&mut session).unwrap();
    (path, session)
}

fn cleanup(path: &std::path::Path) {
    // Remove the whole per-test dir — box, sidecars, and cache.
    if let Some(dir) = path.parent() {
        let _ = std::fs::remove_dir_all(dir);
    }
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
fn extraction_is_a_rebuildable_cache_off_the_log() {
    let (boxpath, mut session) = fresh_session("lotus_files_extract.log");
    let doc = std::env::temp_dir().join("lotus_files_extract.md");
    std::fs::write(&doc, b"the quarterly telescope budget").unwrap();
    let id = files::add_file(&mut session, doc.to_str().unwrap(), DateTime::date(2026, 7, 7)).unwrap();

    let cache = files::cache_dir(boxpath.to_str().unwrap());
    let file_prop = property_id(session.store(), "file").unwrap();
    let file = match session.store().get(id).unwrap().get(file_prop) {
        Some(Value::File(f)) => f.clone(),
        _ => panic!("no file cell"),
    };

    // Miss → extracts the plain text and writes cache/<hex>/text.
    let text = files::extracted_text(&cache, &file, "md");
    assert_eq!(text, "the quarterly telescope budget");
    // Nothing was written to the log — no CONTENT cell appeared.
    assert!(session.store().get(id).unwrap().get(props::CONTENT).is_none());

    // Rebuildable: delete the whole cache dir; re-extraction is identical.
    std::fs::remove_dir_all(&cache).unwrap();
    assert_eq!(files::extracted_text(&cache, &file, "md"), "the quarterly telescope budget");

    // A deferred format (pdf) extracts to empty for now (the 7d stub) — a
    // distinct file so it's a cache miss, not the md hit above.
    let doc2 = std::env::temp_dir().join("lotus_files_extract2.bin");
    std::fs::write(&doc2, b"%PDF-1.4 not really parsed yet").unwrap();
    let file2 = FileRef {
        path: doc2.to_str().unwrap().to_string(),
        hash: files::hash_file(doc2.to_str().unwrap()).unwrap(),
    };
    assert_eq!(files::extracted_text(&cache, &file2, "pdf"), "");

    let _ = std::fs::remove_file(&doc);
    let _ = std::fs::remove_file(&doc2);
    let _ = std::fs::remove_dir_all(&cache);
    cleanup(&boxpath);
}

#[test]
fn same_bytes_different_format_do_not_share_a_cache_entry() {
    let (boxpath, _session) = fresh_session("lotus_files_collide.log");
    let cache = files::cache_dir(boxpath.to_str().unwrap());

    // Two byte-identical files with different extensions → the same hash.
    let md = std::env::temp_dir().join("lotus_files_x.md");
    let dat = std::env::temp_dir().join("lotus_files_x.dat");
    std::fs::write(&md, b"budget notes").unwrap();
    std::fs::write(&dat, b"budget notes").unwrap();
    let file_md = FileRef {
        path: md.to_str().unwrap().to_string(),
        hash: files::hash_file(md.to_str().unwrap()).unwrap(),
    };
    let file_dat = FileRef {
        path: dat.to_str().unwrap().to_string(),
        hash: files::hash_file(dat.to_str().unwrap()).unwrap(),
    };
    assert_eq!(file_md.hash, file_dat.hash, "identical bytes hash the same");

    // The .md extracts its text; the .dat (a stub format) is empty — the
    // md text must NOT leak into the dat entry (or vice-versa), even after
    // the md populates the cache first.
    assert_eq!(files::extracted_text(&cache, &file_md, "md"), "budget notes");
    assert_eq!(files::extracted_text(&cache, &file_dat, "dat"), "");
    assert_eq!(files::extracted_text(&cache, &file_md, "md"), "budget notes");

    let _ = std::fs::remove_file(&md);
    let _ = std::fs::remove_file(&dat);
    let _ = std::fs::remove_dir_all(&cache);
    cleanup(&boxpath);
}

#[test]
fn a_file_is_found_by_a_word_only_in_its_extracted_text() {
    let (boxpath, mut session) = fresh_session("lotus_files_findtext.log");
    let doc = std::env::temp_dir().join("lotus_files_findtext.md");
    std::fs::write(&doc, b"minutes about the telescope procurement").unwrap();
    let id = files::add_file(&mut session, doc.to_str().unwrap(), DateTime::date(2026, 7, 7)).unwrap();

    let cache = files::cache_dir(boxpath.to_str().unwrap());
    let file_prop = property_id(session.store(), "file").unwrap();
    let format_prop = property_id(session.store(), "format").unwrap();

    // "telescope" is nowhere in the name — only in the file's body.
    let sq = search::parse(session.store(), "telescope");
    let hits = search::search(session.store(), &sq, 50, |e: &Entity| match e.get(file_prop) {
        Some(Value::File(f)) => {
            let fmt = match e.get(format_prop) {
                Some(Value::Text(t)) => t.as_str(),
                _ => "",
            };
            files::extracted_text(&cache, f, fmt)
        }
        _ => String::new(),
    });
    assert!(hits.iter().any(|h| h.id == id), "found by a word in the extracted text");
    // And no cell was ever added — the log carries only the file reference.
    assert!(session.store().get(id).unwrap().get(props::CONTENT).is_none());

    let _ = std::fs::remove_file(&doc);
    let _ = std::fs::remove_dir_all(&cache);
    cleanup(&boxpath);
}

#[test]
fn resync_reports_unchanged_changed_and_broken() {
    let (boxpath, mut session) = fresh_session("lotus_files_resync.log");
    let doc = std::env::temp_dir().join("lotus_files_resync.txt");
    std::fs::write(&doc, b"version one").unwrap();
    let path = doc.to_str().unwrap().to_string();
    let id = files::add_file(&mut session, &path, DateTime::date(2026, 7, 7)).unwrap();

    // Untouched → Unchanged.
    assert_eq!(files::resync_file(&mut session, id).unwrap(), files::Resync::Unchanged);

    // Edited bytes → Changed, and the file cell now carries the new hash.
    std::fs::write(&doc, b"version two is different").unwrap();
    let fresh = files::hash_file(&path).unwrap();
    assert_eq!(files::resync_file(&mut session, id).unwrap(), files::Resync::Changed(fresh));
    let file_prop = property_id(session.store(), "file").unwrap();
    match session.store().get(id).unwrap().get(file_prop) {
        Some(Value::File(f)) => assert_eq!(f.hash, fresh),
        _ => panic!("no file cell"),
    }

    // Vanished path → Broken (distinct from a change), no re-extract.
    std::fs::remove_file(&doc).unwrap();
    assert_eq!(files::resync_file(&mut session, id).unwrap(), files::Resync::Broken);

    let _ = std::fs::remove_dir_all(files::cache_dir(boxpath.to_str().unwrap()));
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
