//! Milestone 2: the disk truth is a versioned append-only log, and the store
//! is a materialization of it. These tests close and reopen the log to prove
//! state — including undo and merge — survives a restart.

use lotus_core::*;

fn cell(property: Id, value: Value) -> Cell {
    Cell { property, value }
}

/// A fresh log path per test; removed up front so each run starts empty.
fn temp_path(name: &str) -> std::path::PathBuf {
    let p = std::env::temp_dir().join(format!("lotus_persist_{name}.log"));
    let _ = std::fs::remove_file(&p);
    p
}

#[test]
fn log_roundtrips_state() {
    let path = temp_path("roundtrip");
    let (anna, meeting);
    {
        let mut s = Session::open(&path).unwrap();
        anna = s.allocate_id();
        meeting = s.allocate_id();
        s.commit(
            vec![
                Command::Create { entity: anna },
                Command::AddCell {
                    entity: anna,
                    cell: cell(props::NAME, Value::text("Anna")),
                },
                Command::Create { entity: meeting },
                Command::AddCell {
                    entity: meeting,
                    cell: cell(4401, Value::Reference(anna)),
                },
            ],
            "seed",
            Author::User,
        )
        .unwrap();
    } // session dropped, file closed

    // Reopen: the store is rebuilt purely by replaying the log.
    let mut s = Session::open(&path).unwrap();
    assert_eq!(
        s.store().get(anna).unwrap().get(props::NAME),
        Some(&Value::text("Anna"))
    );
    assert_eq!(s.store().backlinks(anna).len(), 1, "backlink rebuilt from log");
    // next_id was recovered from the Creates: a new id is past both.
    assert!(s.allocate_id() > meeting);

    let _ = std::fs::remove_file(&path);
}

#[test]
fn header_carries_version() {
    let path = temp_path("header");
    {
        Session::open(&path).unwrap();
    }
    let content = std::fs::read_to_string(&path).unwrap();
    let first = content.lines().next().unwrap();
    assert_eq!(first, r#"{"lotus_log":1}"#);
    assert_eq!(LOG_VERSION, 1);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn undo_survives_restart() {
    let path = temp_path("undo_restart");
    let note;
    {
        let mut s = Session::open(&path).unwrap();
        note = s.allocate_id();
        s.commit(vec![Command::Create { entity: note }], "create", Author::User)
            .unwrap();
        s.commit(
            vec![Command::AddCell {
                entity: note,
                cell: cell(props::NAME, Value::text("draft")),
            }],
            "name it",
            Author::User,
        )
        .unwrap();
    }

    // Cross-session undo: the cursor was rebuilt from the log's shape.
    let mut s = Session::open(&path).unwrap();
    assert_eq!(
        s.store().get(note).unwrap().get(props::NAME),
        Some(&Value::text("draft"))
    );
    s.undo(Author::User).unwrap();
    assert!(s.store().get(note).unwrap().get(props::NAME).is_none());
    drop(s);

    // The undo itself was appended, so it persists across another restart...
    let mut s = Session::open(&path).unwrap();
    assert!(s.store().get(note).unwrap().get(props::NAME).is_none());
    // ...and redo still works after the restart.
    s.redo(Author::User).unwrap();
    assert_eq!(
        s.store().get(note).unwrap().get(props::NAME),
        Some(&Value::text("draft"))
    );

    let _ = std::fs::remove_file(&path);
}

#[test]
fn torn_tail_is_tolerated() {
    use std::io::Write;
    let path = temp_path("torn");
    let a;
    {
        let mut s = Session::open(&path).unwrap();
        a = s.allocate_id();
        s.commit(vec![Command::Create { entity: a }], "create", Author::User)
            .unwrap();
    }

    // Simulate a crash mid-append: a partial record with no trailing newline.
    {
        let mut f = std::fs::OpenOptions::new().append(true).open(&path).unwrap();
        f.write_all(br#"{"seq":99,"commands":[{"Crea"#).unwrap();
        f.flush().unwrap();
    }

    // Reopen: the torn tail is dropped and truncated, state intact, healthy.
    let mut s = Session::open(&path).unwrap();
    assert!(s.store().get(a).is_some());
    assert_eq!(s.store().history().len(), 1);

    // A new commit appends cleanly onto the truncated log.
    let b = s.allocate_id();
    s.commit(vec![Command::Create { entity: b }], "after recovery", Author::User)
        .unwrap();
    drop(s);

    let s = Session::open(&path).unwrap();
    assert_eq!(s.store().history().len(), 2);
    assert!(s.store().get(b).is_some());

    let _ = std::fs::remove_file(&path);
}

#[test]
fn merge_and_redirect_survive_restart() {
    let path = temp_path("merge");
    let (survivor, loser, meeting);
    {
        let mut s = Session::open(&path).unwrap();
        survivor = s.allocate_id();
        loser = s.allocate_id();
        meeting = s.allocate_id();
        s.commit(
            vec![
                Command::Create { entity: survivor },
                Command::Create { entity: loser },
                Command::Create { entity: meeting },
                Command::AddCell {
                    entity: meeting,
                    cell: cell(4401, Value::Reference(loser)),
                },
            ],
            "seed",
            Author::User,
        )
        .unwrap();
        s.merge(survivor, loser, vec![], Author::User).unwrap();
    }

    let s = Session::open(&path).unwrap();
    // The redirect was replayed: the loser resolves to the survivor...
    assert_eq!(s.store().resolve(loser), survivor);
    // ...the meeting's bytes were never rewritten...
    assert_eq!(
        s.store().get(meeting).unwrap().get(4401),
        Some(&Value::Reference(loser))
    );
    // ...and the reference resolves onto the survivor.
    assert_eq!(s.store().backlinks(survivor).len(), 1);

    let _ = std::fs::remove_file(&path);
}
