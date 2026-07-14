//! Habits (P18b): `habit` = an ordinary front-of-house type; `check-in` = a
//! WORKING backstage record (date + habit reference). Stats — streaks, week
//! points, the 84-day chain — are computed on read, stored nowhere (D13).

use lotus_core::*;
use lotus_services::{content, habits, property_id};

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("lotus_habits_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn cleanup(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

fn at(day: i64) -> DateTime {
    DateTime::at((day / 10_000) as i32, ((day / 100) % 100) as u32, (day % 100) as u32, 9, 0)
}

#[test]
fn habit_is_front_of_house_and_check_in_is_backstage_and_idempotent() {
    let (mut session, path) = boxed("shapes");

    let habit = content::create_habit(
        &mut session,
        "Climb",
        Some(2.0),
        Some("3×/wk"),
        at(20260714),
    )
    .unwrap();
    let store = session.store();
    let entity = store.get(habit).unwrap();
    // Front of house: a habit belongs in Everything — NOT a working entity.
    assert!(!entity.has(props::WORKING, &Value::Bool(true)));
    let habit_type = content::find_type(store, "habit").expect("habit type seeded");
    assert!(entity.has(props::TYPE, &Value::Reference(habit_type)));
    assert!(matches!(entity.get(props::NAME), Some(Value::Text(n)) if n == "Climb"));
    let points = property_id(store, "points").expect("points property");
    assert!(entity.has(points, &Value::Number(2.0)));
    let cadence = property_id(store, "cadence").expect("cadence property");
    assert!(entity.has(cadence, &Value::text("3×/wk")));

    // Check-in: WORKING backstage, habit reference + date; idempotent per day.
    let first = content::check_in(&mut session, habit, 20260714, at(20260714)).unwrap();
    let again = content::check_in(&mut session, habit, 20260714, at(20260714)).unwrap();
    assert_eq!(first, again, "one check-in per habit per day");
    let other_day = content::check_in(&mut session, habit, 20260715, at(20260715)).unwrap();
    assert_ne!(first, other_day);

    let store = session.store();
    let row = store.get(first).unwrap();
    assert!(row.has(props::WORKING, &Value::Bool(true)), "records are backstage");
    let habit_prop = property_id(store, "habit").expect("habit property");
    assert!(row.has(habit_prop, &Value::Reference(habit)));

    cleanup(&path);
}

#[test]
fn stats_compute_streaks_points_and_the_chain() {
    let (mut session, path) = boxed("stats");
    let a = content::create_habit(&mut session, "Mobility", None, None, at(20260710)).unwrap();
    let b = content::create_habit(&mut session, "Thesis words", Some(3.0), None, at(20260710))
        .unwrap();

    for day in [20260712_i64, 20260713, 20260714] {
        content::check_in(&mut session, a, day, at(day)).unwrap();
    }
    let b_today = content::check_in(&mut session, b, 20260714, at(20260714)).unwrap();

    let stats = habits::habit_stats(session.store(), 20260714);
    assert_eq!(stats.habits.len(), 2);
    let line_a = stats.habits.iter().find(|h| h.id == a).unwrap();
    let line_b = stats.habits.iter().find(|h| h.id == b).unwrap();
    assert_eq!(line_a.points, 1.0, "points default to 1");
    assert_eq!(line_b.points, 3.0);
    assert!(line_a.today_check_in.is_some());
    assert_eq!(line_b.today_check_in, Some(b_today));

    // Streak: three consecutive days with at least one check-in, ending today.
    assert_eq!(stats.streak, 3);
    assert_eq!(stats.longest, 3);
    // Week points: 3×1 (a) + 1×3 (b).
    assert_eq!(stats.week_points, 6.0);
    // The 84-day chain, oldest → today.
    assert_eq!(stats.heat.len(), 84);
    assert_eq!(stats.heat[83], 2, "today: a + b");
    assert_eq!(stats.heat[82], 1);
    assert_eq!(stats.heat[81], 1);
    assert_eq!(stats.heat[80], 0);
    // Avg per active day over the window: 6 points / 3 active days.
    assert!((stats.avg_active - 2.0).abs() < 1e-9);

    // An unchecked TODAY does not break the run until the day passes:
    // seen from the 15th (nothing yet), the streak still reads 3 …
    assert_eq!(habits::habit_stats(session.store(), 20260715).streak, 3);
    // … but a full missed day ends it.
    assert_eq!(habits::habit_stats(session.store(), 20260716).streak, 0);

    // Uncheck = trash the exact row; the projection follows.
    session
        .commit(vec![Command::Trash { entity: b_today }], "uncheck", Author::User)
        .unwrap();
    let stats = habits::habit_stats(session.store(), 20260714);
    assert_eq!(stats.habits.iter().find(|h| h.id == b).unwrap().today_check_in, None);
    assert_eq!(stats.week_points, 3.0);
    assert_eq!(stats.heat[83], 1);

    cleanup(&path);
}

#[test]
fn a_trashed_habit_never_panics_the_projection() {
    let (mut session, path) = boxed("dangling");
    let habit = content::create_habit(&mut session, "Doomed", None, None, at(20260714)).unwrap();
    content::check_in(&mut session, habit, 20260714, at(20260714)).unwrap();
    session
        .commit(vec![Command::Trash { entity: habit }], "trash habit", Author::User)
        .unwrap();

    // Deletion never cascades: the check-in survives in the log, but the
    // projection skips both the trashed habit and its dangling records.
    let stats = habits::habit_stats(session.store(), 20260714);
    assert!(stats.habits.is_empty());
    assert_eq!(stats.heat[83], 0);
    assert_eq!(stats.week_points, 0.0);

    cleanup(&path);
}

#[test]
fn open_seed_open_births_one_type_set() {
    let (session, path) = boxed("idem_seed");
    drop(session);
    // Reopen + reseed: the guard must hold — exactly one habit type.
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    let store = session.store();
    let habit_types = store
        .entities()
        .filter(|e| {
            matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "habit")
                && e.get(props::EXPECTED).is_some()
        })
        .count();
    assert_eq!(habit_types, 1);
    cleanup(&path);
}
