//! P11/11b — the span end: one optional second civil INSIDE the DateTime
//! value. One cell, one fact, one drag target; absent on every value written
//! before P11, so old logs replay unchanged.

use lotus_core::*;

#[test]
fn an_old_log_datetime_deserializes_with_no_end() {
    // The load-bearing compat test, written BEFORE the field landed: a log
    // line serialized by the old struct carries no `end` key and must
    // deserialize as a plain date. Old boxes replay unchanged.
    let old = r#"{"civil":202607110900,"date_only":false}"#;
    let d: DateTime = serde_json::from_str(old).unwrap();
    assert_eq!(d.civil, 202607110900);
    assert!(!d.date_only);
    assert_eq!(d.end, None, "an old value is never a span");

    // And a pre-P11 round trip stays byte-stable in meaning: a plain date
    // re-serializes and re-reads as a plain date.
    let again: DateTime = serde_json::from_str(&serde_json::to_string(&d).unwrap()).unwrap();
    assert_eq!(again, d);
}

#[test]
fn a_zero_length_span_equals_a_plain_date() {
    // end == start is not a span: the constructor collapses it to None
    // (clearing the end collapses to a single day, bp9 #17)…
    let plain = DateTime::at(2026, 7, 11, 9, 0);
    let collapsed = DateTime::span(plain, plain.civil);
    assert_eq!(collapsed, plain);
    assert_eq!(collapsed.end, None);

    // …and end <= start likewise refuses to be a span.
    let backwards = DateTime::span(plain, plain.civil - 10_000);
    assert_eq!(backwards.end, None);

    // A real span is NOT its start-only twin under per-kind equality —
    // RemoveCell and dedup must tell them apart.
    let span = DateTime::span(plain, DateTime::at(2026, 7, 13, 9, 0).civil);
    assert!(span.end.is_some());
    assert_ne!(span, plain);
    assert_ne!(Value::DateTime(span), Value::DateTime(plain));
}

#[test]
fn spans_sort_by_start_among_plain_dates() {
    // `civil` stays the first field, so derived Ord sorts by start — every
    // existing due-sort is stable whether or not values carry ends.
    let a = DateTime::date(2026, 7, 10);
    let b = DateTime::span(DateTime::date(2026, 7, 11), DateTime::date(2026, 7, 20).civil);
    let c = DateTime::date(2026, 7, 12);
    let mut v = vec![c, b, a];
    v.sort();
    assert_eq!(v.iter().map(|d| d.civil).collect::<Vec<_>>(), vec![a.civil, b.civil, c.civil]);
}
