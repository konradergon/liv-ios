//! The number seam accepts finite numbers only: Rust's f64 parser happily
//! reads "NaN" and "inf", but a NaN cell was a poison pill (non-reflexive
//! equality made it unremovable) and infinity has no meaning in the log.

use liv_core::*;
use liv_services::{content, seed_if_fresh};

fn fresh(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("liv_num_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.log");
    let mut session = Session::open(&path).unwrap();
    seed_if_fresh(&mut session).unwrap();
    (path, session)
}

#[test]
fn the_number_seam_refuses_non_finite_values() {
    let (path, mut session) = fresh("finite");
    let id = content::create_note(&mut session, DateTime::date(2026, 7, 10)).unwrap();

    // `order` is the seeded number property.
    for bad in ["NaN", "nan", "inf", "-inf", "infinity"] {
        assert!(
            content::set_property(&mut session, id, "order", bad).is_err(),
            "{bad} must be refused by the number seam"
        );
    }
    assert!(content::set_property(&mut session, id, "order", "42.5").is_ok());

    if let Some(dir) = path.parent() {
        let _ = std::fs::remove_dir_all(dir);
    }
}
