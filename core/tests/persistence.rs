//! Milestone 2: the disk truth is a versioned append-only log, and the store
//! is a materialization of it. These tests close and reopen the log to prove
//! state — including undo and merge — survives a restart.

use liv_core::*;

fn cell(property: Id, value: Value) -> Cell {
    Cell { property, value }
}

/// A fresh log path per test; removed up front so each run starts empty.
fn temp_path(name: &str) -> std::path::PathBuf {
    let p = std::env::temp_dir().join(format!("liv_persist_{name}.log"));
    let _ = std::fs::remove_file(format!("{}.declined", p.display()));
    let _ = std::fs::remove_file(format!("{}.pending", p.display()));
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
    // A fresh box is BORN at v1 — the oldest format its (empty) content
    // needs, so older binaries keep working with it — while this build
    // understands up to LOG_VERSION. The header bumps in place only when a
    // newer-format value (a span, v2) actually lands: core/tests/versioning.rs.
    let path = temp_path("header");
    {
        Session::open(&path).unwrap();
    }
    let content = std::fs::read_to_string(&path).unwrap();
    let first = content.lines().next().unwrap();
    assert_eq!(first, r#"{"liv_log":1}"#);
    assert_eq!(LOG_VERSION, 2);
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
fn the_box_admits_one_writer() {
    let path = temp_path("locked");
    let first = Session::open(&path).unwrap();

    // A second opener is refused outright: it would snapshot the same log
    // and fork the id space. This is the agent + CLI case.
    match Session::open(&path) {
        Err(PersistError::Locked) => {}
        other => panic!("expected Locked, got {other:?}"),
    }

    // The lock rides the session: dropping it frees the box.
    drop(first);
    assert!(Session::open(&path).is_ok());

    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_tail_torn_at_the_newline_is_dropped() {
    let path = temp_path("newline_torn");
    let (a, b);
    {
        let mut s = Session::open(&path).unwrap();
        a = s.allocate_id();
        b = s.allocate_id();
        s.commit(vec![Command::Create { entity: a }], "first", Author::User)
            .unwrap();
        s.commit(vec![Command::Create { entity: b }], "second", Author::User)
            .unwrap();
    }

    // Simulate a crash between the record write and the newline write:
    // the last record is complete JSON but the newline never landed.
    let bytes = std::fs::read(&path).unwrap();
    assert_eq!(bytes.last(), Some(&b'\n'));
    std::fs::write(&path, &bytes[..bytes.len() - 1]).unwrap();

    // The commit for `b` never returned, so dropping it is the contract.
    // Keeping it would merge it with the next append into one line.
    let mut s = Session::open(&path).unwrap();
    assert_eq!(s.store().history().len(), 1);
    assert!(s.store().get(b).is_none());

    // And the log heals: the next append starts on a clean boundary.
    let c = s.allocate_id();
    s.commit(vec![Command::Create { entity: c }], "after", Author::User)
        .unwrap();
    drop(s);
    let s = Session::open(&path).unwrap();
    assert_eq!(s.store().history().len(), 2);
    assert!(s.store().get(c).is_some());

    let _ = std::fs::remove_file(&path);
}

#[test]
fn the_queue_survives_a_restart() {
    let path = temp_path("pending");

    // An agent's draft: no sweep can re-derive this.
    let draft = Proposal {
        commands: vec![Command::Create { entity: 9100 }],
        label: "plan the offsite".into(),
        author: Author::Proposer("offsite-agent".into()),
        reason: "goal: plan the offsite".into(),
    };

    {
        let mut s = Session::open(&path).unwrap();
        s.propose(draft.clone()).unwrap();
    }

    // Reopen: the draft is still in quarantine.
    {
        let mut s = Session::open(&path).unwrap();
        assert_eq!(s.store().pending(), std::slice::from_ref(&draft));
        // Accepting empties the queue file too.
        s.accept(0).unwrap();
    }
    let s = Session::open(&path).unwrap();
    assert!(s.store().pending().is_empty());
    assert!(s.store().get(9100).is_some());

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn a_torn_sidecar_heals_and_later_refusals_survive() {
    use std::io::Write;
    let path = temp_path("sidecar_torn");
    let sidecar = format!("{}.declined", path.display());
    let _ = std::fs::remove_file(&sidecar);

    let proposal = |label: &str| Proposal {
        commands: vec![Command::Create { entity: 9000 }],
        label: label.into(),
        author: Author::Proposer("dates".into()),
        reason: label.into(),
    };

    {
        let mut s = Session::open(&path).unwrap();
        s.propose(proposal("first")).unwrap();
        s.reject(0).unwrap();
    }

    // Crash mid-reject: a fragment with no newline lands after the record.
    {
        let mut f = std::fs::OpenOptions::new().append(true).open(&sidecar).unwrap();
        f.write_all(br#"{"commands":[{"Cre"#).unwrap();
    }

    // Reopen: the fragment is truncated away, the good refusal loads,
    // and the next reject appends onto a clean boundary.
    {
        let mut s = Session::open(&path).unwrap();
        assert_eq!(s.store().declined().len(), 1);
        s.propose(proposal("second")).unwrap();
        s.reject(0).unwrap();
    }

    // Nothing was buried behind a scar: both refusals load.
    let s = Session::open(&path).unwrap();
    assert_eq!(s.store().declined().len(), 2);

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(&sidecar);
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

/// Restore, which had no test anywhere in the workspace until 2026-08-20.
///
/// `Command::Restore` is the documented inverse of `Trash` and the only way
/// a trashed thing can come back. It shipped untested, and the C ABI exports
/// no verb for it — so on the phone, trash has been one-way after the next
/// write. This proves the foundation the new verb stands on: restore works,
/// it survives a reopen, and it refuses the two cases it should.
#[test]
fn restore_brings_a_trashed_entity_back_and_survives_a_reopen() {
    let path = temp_path("restore");
    let id;
    {
        let mut session = Session::open(&path).unwrap();
        id = session.allocate_id();
        session
            .commit(vec![Command::Create { entity: id }], "create", Author::User)
            .unwrap();
        session
            .commit(vec![Command::Trash { entity: id }], "trash", Author::User)
            .unwrap();
        assert!(session.store().get(id).unwrap().trashed, "trashed in memory");

        // Trashing twice is refused — the guard that makes Trash/Restore a
        // reversible PAIR rather than a toggle that can drift.
        assert!(session
            .commit(vec![Command::Trash { entity: id }], "again", Author::User)
            .is_err());

        session
            .commit(vec![Command::Restore { entity: id }], "restore", Author::User)
            .unwrap();
        assert!(!session.store().get(id).unwrap().trashed, "restored in memory");

        // And restoring something live is refused for the same reason.
        assert!(session
            .commit(vec![Command::Restore { entity: id }], "again", Author::User)
            .is_err());
    }
    {
        // The whole point: the restore is IN THE LOG, not just in memory.
        let session = Session::open(&path).unwrap();
        assert!(
            !session.store().get(id).unwrap().trashed,
            "a restore must survive a restart, or the trash is one-way on disk too"
        );
    }
    let _ = std::fs::remove_file(&path);
}

/// A trashed entity is still THERE — `get` resolves it, which is why the
/// core accepts a link pointing at one. The iOS editor demotes such a link
/// to plain text because the snapshot hides trashed rows and the shell
/// cannot tell "in the trash" from "never existed". This pins the core's
/// half of that contract so a future change cannot quietly break the fix.
#[test]
fn a_trashed_entity_is_still_reachable_by_id() {
    let path = temp_path("trashed_get");
    let mut session = Session::open(&path).unwrap();
    let id = session.allocate_id();
    session
        .commit(vec![Command::Create { entity: id }], "create", Author::User)
        .unwrap();
    session
        .commit(vec![Command::Trash { entity: id }], "trash", Author::User)
        .unwrap();

    assert!(session.store().get(id).is_some(), "trash is soft: get still resolves");
    assert!(session.store().get(id).unwrap().trashed);
    let _ = std::fs::remove_file(&path);
}

/// T3 (owner, 2026-08-22): `recency` is maintained on append rather than
/// recomputed per read. This pins the maintained map against the walk it
/// replaces, across the two cases that can move an entry — a MERGE, which
/// redirects one id onto another, and an UNDO, which appends an inverse.
///
/// It also reopens the log, because `replay` builds the map on a different
/// path from `commit` and a divergence there would only show after a restart.
#[test]
fn recency_matches_the_history_walk_it_replaces() {
    // The formula this replaced: last transaction to touch each entity,
    // resolved at read time.
    fn walked(store: &Store) -> std::collections::HashMap<Id, u64> {
        let mut map = std::collections::HashMap::new();
        for tx in store.history() {
            for command in &tx.commands {
                let id = match command {
                    Command::Create { entity }
                    | Command::Trash { entity }
                    | Command::Restore { entity }
                    | Command::AddCell { entity, .. }
                    | Command::RemoveCell { entity, .. }
                    | Command::Redirect { entity, .. } => *entity,
                };
                map.insert(store.resolve(id), tx.seq);
            }
        }
        map
    }

    // Compared in full, not weakened to what a reader happens to reach:
    // a redirect folds an id's past onto its target, so the maintained
    // map and the walk agree key for key.
    fn sorted(map: &std::collections::HashMap<Id, u64>) -> std::collections::BTreeMap<Id, u64> {
        map.iter().map(|(id, seq)| (*id, *seq)).collect()
    }

    let path = temp_path("recency_walk");
    let mut session = Session::open(&path).unwrap();

    let a = session.allocate_id();
    let b = session.allocate_id();
    session
        .commit(vec![Command::Create { entity: a }], "a", Author::User)
        .unwrap();
    session
        .commit(vec![Command::Create { entity: b }], "b", Author::User)
        .unwrap();
    session
        .commit(
            vec![Command::AddCell { entity: a, cell: cell(props::NAME, Value::text("one")) }],
            "name a",
            Author::User,
        )
        .unwrap();
    session
        .commit(
            vec![Command::AddCell { entity: b, cell: cell(props::NAME, Value::text("two")) }],
            "name b",
            Author::User,
        )
        .unwrap();

    let live = sorted(session.store().recency());
    assert_eq!(live, sorted(&walked(session.store())), "after plain writes");

    // A merge: b is trashed and redirected onto a.
    session.merge(a, b, Vec::new(), Author::User).unwrap();
    assert_eq!(
        sorted(session.store().recency()),
        sorted(&walked(session.store())),
        "after a merge, which redirects one id onto another"
    );

    // And an undo, which appends the inverse rather than rewriting.
    session.undo(Author::User).unwrap();
    assert_eq!(
        sorted(session.store().recency()),
        sorted(&walked(session.store())),
        "after an undo, which appends an inverse transaction"
    );

    // Reopen: `replay` builds the map on its own path.
    let before = sorted(session.store().recency());
    drop(session);
    let reopened = Session::open(&path).unwrap();
    assert_eq!(
        sorted(reopened.store().recency()),
        before,
        "the map survives a restart — replay maintains it too"
    );
    let _ = std::fs::remove_file(&path);
}
