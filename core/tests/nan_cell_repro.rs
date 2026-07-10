//! The NaN poison-pill, fixed. The derived PartialEq once made
//! Number(NaN) != Number(NaN), so a NaN cell could be ADDED but the
//! RemoveCell naming it could never match — a permanently stuck cell.
//! Value's equality is now hand-written and reflexive for every value
//! (and the services seam refuses non-finite numbers at parse), so every
//! cell that is in the log stays removable.

use lotus_core::*;

#[test]
fn a_nan_cell_is_removable() {
    let mut s = Store::new();
    let e = s.allocate_id();
    let c = Cell {
        property: 4401,
        value: Value::Number(f64::NAN),
    };
    s.commit(
        vec![
            Command::Create { entity: e },
            Command::AddCell {
                entity: e,
                cell: c.clone(),
            },
        ],
        "add nan",
        Author::User,
    )
    .unwrap();
    assert_eq!(s.get(e).unwrap().cells.len(), 1);

    // Equality is reflexive, so the RemoveCell that names the cell matches it.
    s.commit(
        vec![Command::RemoveCell {
            entity: e,
            cell: c.clone(),
        }],
        "remove nan",
        Author::User,
    )
    .unwrap();
    assert_eq!(s.get(e).unwrap().cells.len(), 0, "the NaN cell is gone");
}

#[test]
fn zero_and_negative_zero_stay_equal() {
    // The hand-written impl must not change ordinary float equality:
    // 0.0 == -0.0 exactly as under the derived impl, so a RemoveCell
    // naming 0 still matches a cell stored as -0.
    assert_eq!(Value::Number(0.0), Value::Number(-0.0));
    assert_ne!(Value::Number(1.0), Value::Number(2.0));
}
