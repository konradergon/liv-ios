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

#[test]
fn renaming_the_automation_definition_keeps_the_gate() {
    // The P19 review's high: the automation DEFINITION rides the ordinary
    // definitions catalog, so an ordinary rename must not resurrect the
    // clerk over a recorded OFF (consent keys on the entity, not the name).
    let path = std::env::temp_dir().join("lotus_assist_rename.log");
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();

    let store = session.store();
    let automation_def = lotus_services::property_id(store, "automation").unwrap();
    let assist = store
        .entities()
        .find(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "assist")
                && e.get(automation_def).is_some()
        })
        .map(|e| e.id)
        .unwrap();

    lotus_services::content::set_property(&mut session, assist, "automation", "false").unwrap();
    lotus_services::capture(&mut session, "kickoff friday", DateTime::at(2026, 7, 15, 9, 0))
        .unwrap();
    assert!(clerk::sweep(session.store(), DateTime::at(2026, 7, 15, 9, 0)).is_empty());

    // Rename the definition through the ordinary door — the exact write the
    // shell's Rename… menu performs.
    session
        .commit(
            vec![
                Command::RemoveCell {
                    entity: automation_def,
                    cell: Cell { property: props::NAME, value: Value::text("automation") },
                },
                Command::AddCell {
                    entity: automation_def,
                    cell: Cell { property: props::NAME, value: Value::text("autopilot") },
                },
            ],
            "rename definition",
            Author::User,
        )
        .unwrap();
    assert!(
        !clerk::assist_enabled(session.store()),
        "renaming the automation definition re-enabled the clerk over an explicit OFF"
    );
    assert!(clerk::sweep(session.store(), DateTime::at(2026, 7, 15, 9, 0)).is_empty());

    // Retype has the same shape: the declared kind changes, the Bool cell
    // on the assist entity does not — the gate must keep reading it.
    session
        .commit(
            vec![
                Command::RemoveCell {
                    entity: automation_def,
                    cell: Cell { property: props::VALUE_KIND, value: Value::text("bool") },
                },
                Command::AddCell {
                    entity: automation_def,
                    cell: Cell { property: props::VALUE_KIND, value: Value::text("text") },
                },
            ],
            "retype definition",
            Author::User,
        )
        .unwrap();
    assert!(!clerk::assist_enabled(session.store()));

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn a_foreign_automation_property_does_not_starve_the_switch() {
    // A pre-P19 box can carry a user property named `automation` (imports
    // mint arbitrary frontmatter keys) — the seed must still ship the
    // switch: the guard keys on the assist ENTITY, never the name.
    let path = std::env::temp_dir().join("lotus_assist_foreign.log");
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::content::birth_property(&mut session, "automation", "text").unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();

    let store = session.store();
    let assists = store
        .entities()
        .filter(|e| {
            !e.trashed
                && e.has(props::WORKING, &Value::Bool(true))
                && matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "assist")
        })
        .count();
    assert_eq!(assists, 1, "the foreign automation property starved the assist switch");
    assert!(clerk::assist_enabled(store), "default ON");

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}
