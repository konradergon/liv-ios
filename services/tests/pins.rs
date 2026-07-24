//! Pins (P17g): a small backstage entity — target + order — that puts an
//! object on the Favourites shelf. Authored curation that travels with the
//! box; never in Everything (WORKING), one pin per target, trash to unpin.

use liv_core::*;
use liv_services::{content, property_id};

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("liv_pins_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    liv_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn cleanup(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

fn capture(session: &mut Session, text: &str) -> Id {
    liv_services::capture(session, text, DateTime::at(2026, 7, 14, 9, 0)).unwrap()
}

#[test]
fn pin_births_a_backstage_entity_with_target_and_order() {
    let (mut session, path) = boxed("birth");
    let note = capture(&mut session, "pin me");

    let pin = content::create_pin(&mut session, note, DateTime::at(2026, 7, 14, 9, 0)).unwrap();
    assert_ne!(pin, 0);

    let store = session.store();
    let entity = store.get(pin).expect("pin exists");
    // Backstage: WORKING keeps it out of Everything (the workspace rule).
    assert!(entity.has(props::WORKING, &Value::Bool(true)));
    // Typed `pin`, targeting the note, with a float order key.
    let pin_type = content::find_type(store, "pin").expect("pin type seeded");
    assert!(entity.has(props::TYPE, &Value::Reference(pin_type)));
    let target_prop = property_id(store, "target").expect("target property");
    assert!(entity.has(target_prop, &Value::Reference(note)));
    let order_prop = property_id(store, "order").expect("order property");
    assert!(matches!(entity.get(order_prop), Some(Value::Number(n)) if *n > 0.0));

    cleanup(&path);
}

#[test]
fn pinning_twice_is_idempotent_and_orders_stack() {
    let (mut session, path) = boxed("idem");
    let a = capture(&mut session, "first");
    let b = capture(&mut session, "second");

    let pin_a = content::create_pin(&mut session, a, DateTime::at(2026, 7, 14, 9, 0)).unwrap();
    let again = content::create_pin(&mut session, a, DateTime::at(2026, 7, 14, 9, 1)).unwrap();
    assert_eq!(pin_a, again, "one pin per target — re-pinning returns the existing pin");

    let pin_b = content::create_pin(&mut session, b, DateTime::at(2026, 7, 14, 9, 2)).unwrap();
    assert_ne!(pin_a, pin_b);

    let store = session.store();
    let order_prop = property_id(store, "order").unwrap();
    let order = |id: Id| match store.get(id).unwrap().get(order_prop) {
        Some(Value::Number(n)) => *n,
        _ => panic!("pin without order"),
    };
    assert!(order(pin_b) > order(pin_a), "a new pin lands after the last");

    cleanup(&path);
}

#[test]
fn unpin_trashes_the_pin_for_a_target() {
    let (mut session, path) = boxed("unpin");
    let note = capture(&mut session, "pin me");

    let pin = content::create_pin(&mut session, note, DateTime::at(2026, 7, 14, 9, 0)).unwrap();
    assert!(content::remove_pin(&mut session, note).unwrap(), "unpin reports work done");
    assert!(session.store().get(pin).unwrap().trashed, "the pin is trashed (soft)");

    // Unpinning a target with no pin is a quiet no-op, not an error.
    assert!(!content::remove_pin(&mut session, note).unwrap());

    // Re-pinning after an unpin births a FRESH pin.
    let fresh = content::create_pin(&mut session, note, DateTime::at(2026, 7, 14, 9, 5)).unwrap();
    assert_ne!(fresh, pin);

    cleanup(&path);
}
