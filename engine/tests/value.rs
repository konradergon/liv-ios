//! Typing a value into a cell.
//!
//! The port of `services/src/content.rs`'s `parse_value`, which dies with
//! `core/`. Standing rule 4 — one grammar, one parser — so the strings a
//! user types today must mean the same things afterwards, and these are
//! the cases that say so.

use liv_engine::value::ValueError;
use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_789_257_600_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

#[test]
fn the_property_says_what_the_text_means() {
    let mut e = engine();
    let text = e.declare_field("client", "text", false, T0).unwrap();
    let count = e.declare_field("seats", "number", false, T0 + 1).unwrap();
    let flag = e.declare_field("billable", "bool", false, T0 + 2).unwrap();

    // The same shape of string, three different values, decided by the
    // property rather than by the sender.
    assert_eq!(e.parse_value(text, "12").unwrap(), Value::Text("12".into()));
    assert_eq!(e.parse_value(count, "12").unwrap(), Value::Number(12.0));
    assert_eq!(e.parse_value(flag, "yes").unwrap(), Value::Bool(true));
    assert_eq!(e.parse_value(flag, "NO").unwrap(), Value::Bool(false));
}

/// **A number must be FINITE**, and this is why.
///
/// Rust's f64 parser accepts `NaN` and `inf`. A knowledge log has no use
/// for either, and NaN's non-reflexive equality once made such a cell
/// impossible to REMOVE: the stored value would not compare equal to
/// itself, so nothing could name it to take it out. That is the
/// poison-pill repro `core/` carries, and it is why the filter exists.
#[test]
fn a_number_cell_refuses_nan_and_infinity() {
    let mut e = engine();
    let count = e.declare_field("seats", "number", false, T0).unwrap();

    for poison in ["NaN", "nan", "inf", "-inf", "infinity"] {
        assert!(
            matches!(e.parse_value(count, poison), Err(ValueError::Unreadable(_))),
            "{poison} got in"
        );
    }
    // And the reason it matters: a value that is not equal to itself
    // cannot be named, so the cell holding it could never be removed.
    let nan = f64::NAN;
    assert_ne!(nan, nan, "the property that made this unremovable");

    assert_eq!(e.parse_value(count, "-2.5").unwrap(), Value::Number(-2.5));
}

#[test]
fn a_date_is_a_floating_day_or_an_instant() {
    let mut e = engine();
    let when = e.declare_field("sent", "datetime", false, T0).unwrap();

    // A bare day floats: no zone, so it never shifts under a traveller.
    let Value::Date(DateSpec::Day(d)) = e.parse_value(when, "2026-09-13").unwrap() else {
        panic!("a bare day must stay a day")
    };
    assert_eq!(civil_from_days(d), (2026, 9, 13));

    // With a time it is an instant.
    assert!(matches!(
        e.parse_value(when, "2026-09-13 14:30").unwrap(),
        Value::Date(DateSpec::Instant { .. })
    ));

    for bad in ["13/09/2026", "2026-13-01", "2026-02-30", "-234-01-01", "tomorrow", "2026-09-13 25:00"] {
        assert!(e.parse_value(when, bad).is_err(), "{bad} got in");
    }
}

/// A date RANGE is refused rather than silently halved.
///
/// `core/` takes `"monday -> friday"` in one cell. `DateSpec` has no span
/// variant, so accepting the text and dropping the end would lose half of
/// what the user said — which is worse than saying no.
#[test]
fn a_date_range_is_refused_rather_than_half_kept() {
    let mut e = engine();
    let when = e.declare_field("sent", "datetime", false, T0).unwrap();
    assert!(matches!(
        e.parse_value(when, "2026-09-13 -> 2026-09-20"),
        Err(ValueError::NotTypeable(_))
    ));
}

/// **An option is matched by NAME and never minted.**
///
/// Naming a new option is a decision; typing a typo is not. Every area is
/// the user's own (owner, 2026-09-21 — there are no compiled-in areas),
/// and the same rule reaches one declared as vocabulary and one made as
/// an ordinary thing: "Work" is `declare`d, "Woodworking" is `create`d,
/// and both are typed the same way.
#[test]
fn an_option_is_found_by_name_and_never_invented() {
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let family = e.declare(kind::AREA, "Family & Friends", T0).unwrap();

    assert_eq!(e.parse_value(prop::AREA, "Work").unwrap(), Value::Ref(work));
    assert_eq!(e.parse_value(prop::AREA, "work").unwrap(), Value::Ref(work), "case");
    assert_eq!(
        e.parse_value(prop::AREA, "  Family & Friends ").unwrap(),
        Value::Ref(family),
        "trimmed, and the area's own name is the only place those words live"
    );

    // An area made the plain way is reached by the same rule.
    let mine = e.create(kind::AREA, Some("Woodworking"), T0).unwrap();
    assert_eq!(e.parse_value(prop::AREA, "woodworking").unwrap(), Value::Ref(mine));

    // A typo mints nothing.
    assert!(matches!(
        e.parse_value(prop::AREA, "Wrok"),
        Err(ValueError::NoSuchOption(_))
    ));
    // The three this test made itself, and not a fourth: the typo created
    // nothing trying.
    assert_eq!(e.of_kind(kind::AREA).unwrap().len(), 3, "and created nothing trying");
}

#[test]
fn an_id_is_the_escape_hatch_and_is_checked() {
    let mut e = engine();
    let mine = e.create(kind::AREA, Some("Woodworking"), T0).unwrap();

    assert_eq!(e.parse_value(prop::AREA, &mine.hex()).unwrap(), Value::Ref(mine));
    assert_eq!(e.parse_value(prop::AREA, &format!("#{}", mine.hex())).unwrap(), Value::Ref(mine));

    // A well-formed id for something that is not there is refused, so a
    // typo cannot leave a cell pointing at nothing.
    let ghost = EntityId::from_hex("99999999999999999999999999999999").unwrap();
    assert!(matches!(e.parse_value(prop::AREA, &ghost.hex()), Err(ValueError::NoSuchEntity)));
}

/// A file's cell holds a hash derived from bytes, which no typed string
/// can express. Files are born through `add_file`, which hashes.
#[test]
fn a_file_cell_cannot_be_typed_into() {
    let e = engine();
    assert!(matches!(
        e.parse_value(prop::FILE, "/home/me/invoice.pdf"),
        Err(ValueError::NotTypeable(_))
    ));
}

#[test]
fn a_property_nothing_declares_is_not_a_property() {
    let e = engine();
    let nobody = EntityId::from_hex("77777777777777777777777777777777").unwrap();
    assert!(matches!(e.parse_value(nobody, "anything"), Err(ValueError::UnknownProperty)));
}

/// What the parser produces must be what the cell accepts — or a value
/// could parse and then be refused at the door, which is a confusing
/// failure to show someone.
#[test]
fn everything_that_parses_is_a_value_the_cell_takes() {
    let mut e = engine();
    let work = e.declare(kind::AREA, "Work", T0).unwrap();
    let id = e.create(kind::TASK, Some("roof"), T0).unwrap();

    for (property, raw) in [
        (prop::NAME, "the roof"),
        (prop::AREA, "Work"),
        (prop::STATUS, "Doing"),
        (prop::DUE, "2026-09-13"),
        (prop::PRIVATE, "yes"),
        (prop::ORDER, "3"),
    ] {
        let value = e.parse_value(property, raw).unwrap_or_else(|err| panic!("{raw}: {err}"));
        e.set(id, property, value, T0 + 1)
            .unwrap_or_else(|err| panic!("{raw} parsed but the cell refused it: {err:?}"));
    }
    assert_eq!(e.one(id, prop::AREA).unwrap(), Some(Value::Ref(work)));
    assert_eq!(e.one(id, prop::STATUS).unwrap(), Some(Value::Ref(status::DOING)));
}
