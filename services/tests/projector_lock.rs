//! P20j.4 — KILL-SHOT C: the two-process materialization race. App and
//! CLI both reconcile AFTER releasing the box lock; without a serializer,
//! two whole-manifest writes interleave and the last writer silently
//! discards the other's rows. The projector lock (.liv/projector.lock, a
//! blocking flock held across load→plan→apply only — IO-only, NEVER the
//! box lock) serializes them; convergence is asserted over racing threads
//! on a REAL directory (RealVaultIo: tmp+fsync+rename).

use lotus_core::*;
use lotus_services::content;
use lotus_services::projection::{self, RealVaultIo, VaultIo};

#[test]
fn kill_shot_c_racing_projectors_converge() {
    let box_path = std::env::temp_dir().join("lotus_lock_race.log");
    let _ = std::fs::remove_file(&box_path);
    let _ = std::fs::remove_file(format!("{}.declined", box_path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", box_path.display()));
    let mut session = Session::open(&box_path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    let stamp = DateTime::at(2026, 7, 15, 9, 0);
    for i in 0..8 {
        let id = content::create_note(&mut session, stamp).unwrap();
        content::set_type(&mut session, id, "note").unwrap();
        content::set_property(&mut session, id, "name", &format!("Race {i}")).unwrap();
    }

    let root = std::env::temp_dir().join("lotus_lock_race_vault");
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();

    let store = session.store();
    std::thread::scope(|scope| {
        for _worker in 0..2 {
            scope.spawn(|| {
                for _round in 0..10 {
                    projection::project_locked(&root, store).unwrap();
                }
            });
        }
    });

    // Converged: every expected file on disk with exact bytes, the
    // manifest parses (never torn), and a fresh plan is empty.
    let io = RealVaultIo::new(&root);
    for file in lotus_services::vault::expected_files(store) {
        if let Some(content) = &file.content {
            let bytes = io.read(&file.rel_path).unwrap_or_else(|_| {
                panic!("missing {}", file.rel_path)
            });
            assert_eq!(bytes, content.as_bytes(), "bytes at {}", file.rel_path);
        }
    }
    let manifest = projection::load_manifest(&io);
    assert!(!manifest.rows.is_empty(), "the manifest survived the race intact");
    let (ops, _) = projection::plan_projection(store, &manifest);
    assert!(ops.is_empty(), "the race settled — a fresh plan is empty, got {ops:?}");

    let _ = std::fs::remove_dir_all(&root);
    let _ = std::fs::remove_file(&box_path);
    let _ = std::fs::remove_file(format!("{}.declined", box_path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", box_path.display()));
}
