//! Habit stats (P18b, D13): streaks, points, and the 84-day chain — computed
//! on read from the check-in records, stored nowhere. A trashed habit's
//! records go dark (skipped, never a panic); deletion never cascades.

use liv_core::{props, Id, Store, Value};
use serde::Serialize;

use crate::content::find_type;
use crate::dates::days_in_month;
use crate::property_id;

/// One habit's line on the board: identity + today's toggle state.
#[derive(Serialize, Clone, Debug)]
pub struct HabitLine {
    pub id: Id,
    pub name: String,
    /// The habit's `points` cell; 1 when absent.
    pub points: f64,
    pub cadence: Option<String>,
    /// Today's check-in row, if checked — the uncheck (trash) target.
    pub today_check_in: Option<Id>,
}

/// One window check-in — the heatmap's day-click popover (uncheck = trash
/// this exact row).
#[derive(Serialize, Clone, Debug)]
pub struct CheckInDay {
    pub id: Id,
    pub habit: Id,
    /// Civil YMD.
    pub day: i64,
}

/// The whole card, derived in one pass.
#[derive(Serialize, Clone, Debug)]
pub struct HabitsSummary {
    pub habits: Vec<HabitLine>,
    /// Consecutive days with ≥1 check-in, ending today — or yesterday: an
    /// unchecked today does not break the run until the day passes.
    pub streak: u32,
    pub longest: u32,
    /// Points earned in the last 7 days (today inclusive).
    pub week_points: f64,
    /// Points per active day over the 84-day window.
    pub avg_active: f64,
    /// Check-ins per day for the last 84 days, oldest → today.
    pub heat: Vec<u32>,
    /// POINTS per day over the same window (the sparkline), oldest → today.
    pub points_heat: Vec<f64>,
    /// The window's raw check-ins — the day-click popover's rows.
    pub check_ins: Vec<CheckInDay>,
}

/// Rata Die ordinal from a civil YMD — consecutive days differ by one.
fn day_ordinal(ymd: i64) -> i64 {
    let (mut y, mut m, d) = (ymd / 10_000, (ymd / 100) % 100, ymd % 100);
    if m <= 2 {
        y -= 1;
        m += 12;
    }
    365 * y + y / 4 - y / 100 + y / 400 + (153 * (m - 3) + 2) / 5 + d
}

fn day_before(ymd: i64) -> i64 {
    let (mut y, mut m, mut d) = ((ymd / 10_000) as i32, ((ymd / 100) % 100) as u32, (ymd % 100) as u32);
    if d > 1 {
        d -= 1;
    } else {
        if m == 1 {
            m = 12;
            y -= 1;
        } else {
            m -= 1;
        }
        d = days_in_month(y, m);
    }
    (y as i64) * 10_000 + (m as i64) * 100 + d as i64
}

pub fn habit_stats(store: &Store, today: i64) -> HabitsSummary {
    let empty = HabitsSummary {
        habits: Vec::new(),
        streak: 0,
        longest: 0,
        week_points: 0.0,
        avg_active: 0.0,
        heat: vec![0; 84],
        points_heat: vec![0.0; 84],
        check_ins: Vec::new(),
    };
    let (Some(habit_type), Some(checkin_type), Some(habit_prop)) = (
        find_type(store, "habit"),
        find_type(store, "check-in"),
        property_id(store, "habit"),
    ) else {
        return empty;
    };
    let points_prop = property_id(store, "points");
    let cadence_prop = property_id(store, "cadence");
    let date_prop = property_id(store, "date");

    // The live habits, in id order (stable render).
    let mut habits: Vec<HabitLine> = store
        .entities()
        .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(habit_type)))
        .map(|e| HabitLine {
            id: e.id,
            name: match e.get(props::NAME) {
                Some(Value::Text(name)) => name.clone(),
                _ => format!("#{}", e.id),
            },
            points: match points_prop.and_then(|p| e.get(p)) {
                Some(Value::Number(n)) => *n,
                _ => 1.0,
            },
            cadence: match cadence_prop.and_then(|p| e.get(p)) {
                Some(Value::Text(t)) => Some(t.clone()),
                _ => None,
            },
            today_check_in: None,
        })
        .collect();
    habits.sort_by_key(|h| h.id);
    let live: std::collections::HashMap<Id, f64> =
        habits.iter().map(|h| (h.id, h.points)).collect();

    // The live check-ins whose habit still lives: (day, habit, row id).
    let checkins: Vec<(i64, Id, Id)> = store
        .entities()
        .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(checkin_type)))
        .filter_map(|e| {
            let habit = match e.get(habit_prop) {
                Some(Value::Reference(h)) => store.resolve(*h),
                _ => return None,
            };
            if !live.contains_key(&habit) {
                return None; // dangling: the habit is gone — skip, never panic
            }
            let day = match date_prop.and_then(|p| e.get(p)) {
                Some(Value::DateTime(dt)) => dt.civil / 10_000,
                _ => return None,
            };
            Some((day, habit, e.id))
        })
        .collect();

    for (day, habit, row) in &checkins {
        if *day == today {
            if let Some(line) = habits.iter_mut().find(|h| h.id == *habit) {
                line.today_check_in = Some(*row);
            }
        }
    }

    // Per-day counts + points.
    let mut by_day: std::collections::HashMap<i64, (u32, f64)> = std::collections::HashMap::new();
    for (day, habit, _) in &checkins {
        let entry = by_day.entry(*day).or_insert((0, 0.0));
        entry.0 += 1;
        entry.1 += live.get(habit).copied().unwrap_or(1.0);
    }

    // The 84-day chain + week points + active days, walking back from today.
    let mut heat = vec![0u32; 84];
    let mut points_heat = vec![0.0f64; 84];
    let mut week_points = 0.0;
    let mut window_points = 0.0;
    let mut active_days = 0u32;
    let mut window_days: std::collections::HashMap<i64, usize> = std::collections::HashMap::new();
    let mut day = today;
    for offset in 0..84 {
        window_days.insert(day, 83 - offset);
        if let Some((count, points)) = by_day.get(&day) {
            heat[83 - offset] = *count;
            points_heat[83 - offset] = *points;
            window_points += points;
            active_days += 1;
            if offset < 7 {
                week_points += points;
            }
        }
        day = day_before(day);
    }
    let window_check_ins: Vec<CheckInDay> = checkins
        .iter()
        .filter(|(day, _, _)| window_days.contains_key(day))
        .map(|(day, habit, id)| CheckInDay { id: *id, habit: *habit, day: *day })
        .collect();

    // Streak: today, or yesterday if today is still unchecked.
    let mut streak = 0u32;
    let mut cursor = if by_day.contains_key(&today) { today } else { day_before(today) };
    while by_day.contains_key(&cursor) {
        streak += 1;
        cursor = day_before(cursor);
    }

    // Longest run anywhere in the record: sort the day ordinals once and
    // count consecutive stretches — O(n log n), never a per-step key scan
    // (this runs on EVERY snapshot read; the review's finding).
    let mut ordinals: Vec<i64> = by_day.keys().map(|d| day_ordinal(*d)).collect();
    ordinals.sort_unstable();
    let mut longest = 0u32;
    let mut run = 0u32;
    let mut previous: Option<i64> = None;
    for ordinal in ordinals {
        run = match previous {
            Some(p) if ordinal == p + 1 => run + 1,
            _ => 1,
        };
        longest = longest.max(run);
        previous = Some(ordinal);
    }

    HabitsSummary {
        habits,
        streak,
        longest,
        week_points,
        avg_active: if active_days > 0 { window_points / active_days as f64 } else { 0.0 },
        heat,
        points_heat,
        check_ins: window_check_ins,
    }
}
