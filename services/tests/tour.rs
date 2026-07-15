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

#[test]
fn the_automation_switch_gates_every_proposal() {
    let path = std::env::temp_dir().join("lotus_assist_switch.log");
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();

    // The seed ships EXACTLY ONE assist entity, automation ON by default.
    let store = session.store();
    let automation = lotus_services::property_id(store, "automation").expect("automation prop");
    let assists: Vec<Id> = store
        .entities()
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "assist")
                && e.get(automation).is_some()
        })
        .map(|e| e.id)
        .collect();
    assert_eq!(assists.len(), 1, "exactly one assist entity");
    let assist = assists[0];

    // ON (the default): the frozen strings propose — today's behavior.
    let id = lotus_services::capture(&mut session, "kickoff friday", DateTime::at(2026, 7, 15, 9, 0))
        .unwrap();
    assert!(!clerk::sweep(session.store(), DateTime::at(2026, 7, 15, 9, 0)).is_empty());

    // OFF: zero proposals — every door (FFI, CLI) inherits this consent.
    lotus_services::content::set_property(&mut session, assist, "automation", "false").unwrap();
    assert!(clerk::sweep(session.store(), DateTime::at(2026, 7, 15, 9, 0)).is_empty());

    // Back ON: byte-for-byte today's behavior returns.
    lotus_services::content::set_property(&mut session, assist, "automation", "true").unwrap();
    assert!(clerk::sweep(session.store(), DateTime::at(2026, 7, 15, 9, 0))
        .iter()
        .any(|p| p.commands.iter().any(|c| matches!(c, Command::AddCell { entity, .. } if *entity == id))));

    // Open-seed-open: the guard holds — still exactly one assist entity.
    drop(session);
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    let store = session.store();
    let count = store
        .entities()
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "assist")
                && e.get(automation).is_some()
        })
        .count();
    assert_eq!(count, 1);

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}
