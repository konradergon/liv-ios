//! Recurrence — milestone 6. Worked example 2, executable:
//!
//! The series is one entity. Recurrence is a text cell holding the rule.
//! Occurrences are virtual — computed here, in one place, stored nowhere —
//! so "due this week" means the same thing on Today, the list and the
//! calendar. Editing one occurrence materializes an exception entity that
//! references the series and carries its own date; expansion skips what an
//! exception covers.
//!
//! The fenced decisions, made here:
//! - The grammar (v0, decided with the calendar): "every day",
//!   "every week", "every month", "every <weekday>". Weekly recurs on the
//!   anchor's weekday; monthly on the anchor's day, clamped to short
//!   months. The anchor is the series' own due date.
//! - The horizon: the asked window is the horizon. A caller states
//!   [from, to]; nothing expands past it, and a window is capped at a
//!   year — the calendar asks for months, and an endless series must not
//!   answer an unbounded question.
//! - Past occurrences of a series are not debts: nothing here accumulates
//!   what yesterday's expansion would have shown.

use lotus_core::{props, DateTime, Entity, Id, Store, Value};

use crate::dates::{add_days, day_of, days_in_month, parts, weekday, WEEKDAYS};
use crate::property_id;

/// One virtual occurrence of a series, in someone's asked window.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Occurrence {
    pub series: Id,
    pub date: DateTime,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Rule {
    Daily,
    /// Recurs on the anchor's weekday.
    Weekly,
    /// Recurs on a named weekday (0 = Sunday).
    OnWeekday(u32),
    /// Recurs on the anchor's day-of-month, clamped to short months.
    Monthly,
}

/// "every day" | "every week" | "every month" | "every friday" —
/// lowercase, whitespace-tolerant. Anything else is not a rule, and an
/// unparseable rule recurs never rather than wrongly.
fn parse(rule: &str) -> Option<Rule> {
    let mut words = rule.split_whitespace().map(str::to_lowercase);
    if words.next()? != "every" {
        return None;
    }
    let unit = words.next()?;
    if words.next().is_some() {
        return None;
    }
    match unit.as_str() {
        "day" => Some(Rule::Daily),
        "week" => Some(Rule::Weekly),
        "month" => Some(Rule::Monthly),
        _ => WEEKDAYS
            .iter()
            .position(|w| *w == unit)
            .map(|i| Rule::OnWeekday(i as u32)),
    }
}

/// The default expansion every lens reads: anchored on the positioning set
/// (`date` before `due`, P11/11c). Pre-P11 series carry only `due`, so the
/// due-anchored world is bit-identical through this wrapper.
pub fn occurrences(store: &Store, from: DateTime, to: DateTime) -> Vec<Occurrence> {
    occurrences_anchored(store, from, to, &crate::calendar_set(store))
}

/// Every occurrence of every live series inside [from, to], exceptions
/// already subtracted, ordered by date then series id. A series is any
/// live, non-working entity carrying a `recurrence` rule AND a dated cell
/// on one of `anchors` — the anchor is the FIRST anchor property present
/// (repeat is available on ANY dated object; nothing here reads a type). A
/// rule beside only lookup-role dates is inert by default, because lookup
/// roles are never in the positioning set — this parameterization is the
/// sanctioned escape hatch, not a behavior flag. A span-valued anchor
/// anchors on its start (day_of reads the start civil). Occurrences are
/// computed at render and stored nowhere; the window is the horizon,
/// capped at a year.
pub fn occurrences_anchored(
    store: &Store,
    from: DateTime,
    to: DateTime,
    anchors: &[Id],
) -> Vec<Occurrence> {
    let Some(recurrence_prop) = property_id(store, "recurrence") else {
        return Vec::new();
    };
    let exception_prop = property_id(store, "exception-of");

    let from = day_of(from);
    let cap = add_days(from, 366);
    let to = if day_of(to).civil > cap.civil { cap } else { day_of(to) };

    let mut series: Vec<(&Entity, Rule, DateTime, Id)> = store
        .entities()
        .filter(|e| !e.trashed && !e.has(props::WORKING, &Value::Bool(true)))
        .filter_map(|e| {
            let rule = match e.get(recurrence_prop)? {
                Value::Text(text) => parse(text)?,
                _ => return None,
            };
            let (anchor_prop, anchor) = anchors.iter().find_map(|&p| match e.get(p) {
                Some(Value::DateTime(d)) => Some((p, day_of(*d))),
                _ => None,
            })?;
            Some((e, rule, anchor, anchor_prop))
        })
        .collect();
    series.sort_by_key(|(e, _, _, _)| e.id);

    let mut out = Vec::new();
    for (entity, rule, anchor, _anchor_prop) in series {
        let exceptions = exception_dates(store, entity.id, exception_prop, anchors);
        let mut day = if from.civil >= anchor.civil { from } else { anchor };
        while day.civil <= to.civil {
            if occurs_on(rule, anchor, day) && !exceptions.contains(&day.civil) {
                out.push(Occurrence {
                    series: entity.id,
                    date: day,
                });
            }
            day = add_days(day, 1);
        }
    }
    out.sort_by_key(|o| (o.date.civil, o.series));
    out
}

fn occurs_on(rule: Rule, anchor: DateTime, day: DateTime) -> bool {
    match rule {
        Rule::Daily => true,
        Rule::Weekly => weekday(day) == weekday(anchor),
        Rule::OnWeekday(target) => weekday(day) == target,
        Rule::Monthly => {
            let (ay, am, anchor_dom) = parts(anchor);
            let _ = (ay, am);
            let (y, m, dom) = parts(day);
            dom == anchor_dom.min(days_in_month(y, m))
        }
    }
}

/// The dates an exception entity already covers: it references the series
/// and carries its own dated cell on ANY of the anchor properties — a real
/// entity holding one occurrence's truth, never a detached copy. Coverage
/// is deliberately role-agnostic (the P11 review's high finding): keying it
/// to the series' CURRENT anchor meant an ordinary anchor flip — a `date`
/// cell set beside `due`, or a Space-cycle of either row — silently
/// orphaned every exception and resurrected the occurrences they hid.
/// Pre-P11 exceptions carry `due`, which is in the set, so they keep
/// working verbatim (bp9 OQ-B, adopted).
fn exception_dates(
    store: &Store,
    series: Id,
    exception_prop: Option<Id>,
    anchors: &[Id],
) -> Vec<i64> {
    let Some(exception_prop) = exception_prop else {
        return Vec::new();
    };
    store
        .entities()
        .filter(|e| !e.trashed)
        .filter(|e| e.has(exception_prop, &Value::Reference(series)))
        .flat_map(|e| {
            anchors.iter().filter_map(move |p| match e.get(*p) {
                Some(Value::DateTime(d)) => Some(day_of(*d).civil),
                _ => None,
            })
        })
        .collect()
}
