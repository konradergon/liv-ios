//! The tour's scripted captures (P19c, H5): frozen strings that MUST each
//! fire at least one clerk proposer on a fresh seeded box — the assist
//! moment of the tour can never demo a dead wand.

use lotus_core::*;
use lotus_services::{clerk, TOUR_CAPTURES};

#[test]
fn every_frozen_tour_capture_fires_a_proposer() {
    let path = std::env::temp_dir().join("lotus_tour_strings.log");
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();

    for text in TOUR_CAPTURES {
        let id = lotus_services::capture(&mut session, text, DateTime::at(2026, 7, 15, 9, 0))
            .unwrap();
        let proposals = clerk::sweep(session.store(), DateTime::at(2026, 7, 15, 9, 0));
        let fired = proposals.iter().any(|p| {
            p.commands.iter().any(|c| match c {
                Command::AddCell { entity, .. } | Command::Create { entity } => *entity == id,
                _ => false,
            })
        });
        assert!(fired, "the frozen tour capture {text:?} fired no proposer — the tour would demo a dead wand");
    }

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}
