//! Time totals, saved views, and board widgets (P18d) — projections over the
//! WORKING backstage records, computed on read, stored nowhere. Totals
//! tolerate overlapping entries (single-active is a SHELL invariant, not a
//! core law); a trashed target's entries go dark, never a panic.

use lotus_core::{props, Id, Store, Value};
use serde::Serialize;

use crate::content::find_type;
use crate::property_id;

#[derive(Serialize, Clone, Debug)]
pub struct TimeTotal {
    pub target: Id,
    pub name: String,
    /// Minutes in the 7-day window ending today.
    pub minutes: i64,
}

#[derive(Serialize, Clone, Debug)]
pub struct TimeEntryRow {
    pub id: Id,
    pub target: Id,
    /// Full civil stamps (YYYYMMDDHHMM).
    pub start: i64,
    pub end: i64,
}

#[derive(Serialize, Clone, Debug)]
pub struct TimeSummary {
    pub totals: Vec<TimeTotal>,
    pub entries: Vec<TimeEntryRow>,
}

#[derive(Serialize, Clone, Debug)]
pub struct ViewRow {
    pub id: Id,
    pub name: String,
    pub query: String,
}

#[derive(Serialize, Clone, Debug)]
pub struct WidgetRow {
    pub id: Id,
    pub kind: String,
    /// 0 = the Home scope.
    pub workspace: Id,
    pub span: f64,
    pub order: f64,
    /// A saved view the widget is aimed at, when re-aimed.
    pub view: Option<Id>,
    pub range: Option<String>,
}

/// Rata Die day number from a civil YMD — cross-midnight intervals need
/// real day arithmetic, not string math.
fn day_number(ymd: i64) -> i64 {
    let (mut y, mut m, d) = (ymd / 10_000, (ymd / 100) % 100, ymd % 100);
    if m <= 2 {
        y -= 1;
        m += 12;
    }
    365 * y + y / 4 - y / 100 + y / 400 + (153 * (m - 3) + 2) / 5 + d
}

fn civil_minutes(civil: i64) -> i64 {
    let (ymd, hhmm) = (civil / 10_000, civil % 10_000);
    day_number(ymd) * 1440 + (hhmm / 100) * 60 + (hhmm % 100)
}

/// The last-7-days card: per-target minutes + the window's raw entries.
pub fn time_totals(store: &Store, today: i64) -> TimeSummary {
    let empty = TimeSummary { totals: Vec::new(), entries: Vec::new() };
    let (Some(entry_type), Some(target_prop), Some(start_prop), Some(end_prop)) = (
        find_type(store, "time-entry"),
        property_id(store, "target"),
        property_id(store, "start"),
        property_id(store, "end"),
    ) else {
        return empty;
    };
    let window_start = day_number(today) - 6;

    let mut entries: Vec<TimeEntryRow> = store
        .entities()
        .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(entry_type)))
        .filter_map(|e| {
            let target = match e.get(target_prop) {
                Some(Value::Reference(t)) => store.resolve(*t),
                _ => return None,
            };
            // Dangling target → dark.
            if store.get(target).map(|t| t.trashed) != Some(false) {
                return None;
            }
            let start = match e.get(start_prop) {
                Some(Value::DateTime(dt)) => dt.civil,
                _ => return None,
            };
            let end = match e.get(end_prop) {
                Some(Value::DateTime(dt)) => dt.civil,
                _ => return None,
            };
            (day_number(start / 10_000) >= window_start)
                .then_some(TimeEntryRow { id: e.id, target, start, end })
        })
        .collect();
    entries.sort_by_key(|e| e.start);

    let mut order: Vec<Id> = Vec::new();
    let mut minutes: std::collections::HashMap<Id, i64> = std::collections::HashMap::new();
    for entry in &entries {
        let length = (civil_minutes(entry.end) - civil_minutes(entry.start)).max(0);
        if !minutes.contains_key(&entry.target) {
            order.push(entry.target);
        }
        *minutes.entry(entry.target).or_insert(0) += length;
    }
    let totals = order
        .into_iter()
        .map(|target| TimeTotal {
            target,
            name: match store.get(target).and_then(|e| e.get(props::NAME)) {
                Some(Value::Text(name)) => name.clone(),
                _ => format!("#{target}"),
            },
            minutes: minutes[&target],
        })
        .collect();
    TimeSummary { totals, entries }
}

/// Every live saved view, in id order (creation order).
pub fn saved_views(store: &Store) -> Vec<ViewRow> {
    let (Some(view_type), Some(query_prop)) =
        (find_type(store, "view"), property_id(store, "query"))
    else {
        return Vec::new();
    };
    let mut rows: Vec<ViewRow> = store
        .entities()
        .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(view_type)))
        .map(|e| ViewRow {
            id: e.id,
            name: match e.get(props::NAME) {
                Some(Value::Text(name)) => name.clone(),
                _ => format!("#{}", e.id),
            },
            query: match e.get(query_prop) {
                Some(Value::Text(q)) => q.clone(),
                _ => String::new(),
            },
        })
        .collect();
    rows.sort_by_key(|v| v.id);
    rows
}

/// The board's widgets, float-key ordered (the pins pattern).
pub fn board_widgets(store: &Store) -> Vec<WidgetRow> {
    let (Some(widget_type), Some(kind_prop)) =
        (find_type(store, "widget"), property_id(store, "widget-kind"))
    else {
        return Vec::new();
    };
    let span_prop = property_id(store, "span");
    let order_prop = property_id(store, "order");
    let range_prop = property_id(store, "range");
    let ws_prop = property_id(store, "workspace");
    let target_prop = property_id(store, "target");

    let mut rows: Vec<WidgetRow> = store
        .entities()
        .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(widget_type)))
        .filter_map(|e| {
            let kind = match e.get(kind_prop) {
                Some(Value::Text(kind)) => kind.clone(),
                _ => return None,
            };
            Some(WidgetRow {
                id: e.id,
                kind,
                workspace: match ws_prop.and_then(|p| e.get(p)) {
                    Some(Value::Reference(w)) => *w,
                    _ => 0,
                },
                span: match span_prop.and_then(|p| e.get(p)) {
                    Some(Value::Number(n)) => *n,
                    _ => 2.0,
                },
                order: match order_prop.and_then(|p| e.get(p)) {
                    Some(Value::Number(n)) => *n,
                    _ => 0.0,
                },
                view: match target_prop.and_then(|p| e.get(p)) {
                    Some(Value::Reference(v)) => Some(store.resolve(*v)),
                    _ => None,
                },
                range: match range_prop.and_then(|p| e.get(p)) {
                    Some(Value::Text(r)) => Some(r.clone()),
                    _ => None,
                },
            })
        })
        .collect();
    rows.sort_by(|a, b| a.order.partial_cmp(&b.order).unwrap_or(std::cmp::Ordering::Equal));
    rows
}
