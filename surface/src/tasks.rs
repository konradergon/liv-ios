//! Tasks: every task, grouped by status.
//!
//! From `Tasks.swift`, which held nine collection operations and the rules
//! under them.

use liv_engine::{kind, model, prop, Engine, EntityId, LogError, Value};

use crate::{completes, day_of, row, statuses, visible, Lens, Row};

/// Which tasks — the chips above the list.
///
/// **The lens runs BEFORE this** (M4): the workspace scopes the surface,
/// the chips narrow inside it.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Filter {
    #[default]
    All,
    Status(EntityId),
    Project(EntityId),
}

/// One status band.
#[derive(Debug, Clone, PartialEq)]
pub struct Group {
    /// `None` is the "No status" band, which is not a status and never
    /// completes.
    pub status: Option<EntityId>,
    pub name: String,
    pub completes: bool,
    pub rows: Vec<Row>,
    /// **The lateness is the GROUP's fact, not each row's.** Measured
    /// 2026-08-30: this screen was 1.85% saturated pixels against
    /// Todoist's 0.58%, and 21,000 of those were a column of red dates —
    /// one per row, because in a real box every task is overdue. A colour
    /// on every row distinguishes nothing. Todoist says it once, in the
    /// heading, and leaves the rows grey; so the count is here and not on
    /// the row.
    pub late: usize,
}

pub fn tasks(
    e: &Engine,
    filter: Filter,
    lens: &Lens,
    today_day: i32,
) -> Result<Vec<Group>, LogError> {
    // Every task, by index seek. The shell scanned `snap.entities` and
    // tested `kinds.contains("task")` — a string compare per entity per
    // refresh.
    let mut rows = Vec::new();
    for id in e.of_kind(kind::TASK)? {
        let r = row(e, id)?;
        if !visible(&r, lens) || !matches(e, &r, filter)? {
            continue;
        }
        rows.push(r);
    }

    let mut groups = Vec::new();
    let mut used: Vec<EntityId> = Vec::new();
    for st in statuses(e)? {
        let mine: Vec<Row> = rows.iter().filter(|r| r.status == Some(st)).cloned().collect();
        used.extend(mine.iter().map(|r| r.id));
        groups.push(band(e, Some(st), mine, today_day)?);
    }
    // Everything the vocabulary did not claim — including a status that
    // has since been retired, so no task can fall off the screen.
    let rest: Vec<Row> = rows.into_iter().filter(|r| !used.contains(&r.id)).collect();
    groups.push(band(e, None, rest, today_day)?);

    // An empty group is not a group. Quick-add used to hold one open to
    // host itself; the add button is outside the list now.
    groups.retain(|g| !g.rows.is_empty());
    Ok(groups)
}

fn band(
    e: &Engine,
    st: Option<EntityId>,
    mut rows: Vec<Row>,
    today_day: i32,
) -> Result<Group, LogError> {
    sort(&mut rows);
    let completes = match st {
        Some(s) => completes(e, s)?,
        None => false,
    };
    let late = if completes {
        // A finished band has nothing late in it by definition, and
        // saying "3 late" over a list of done things is noise.
        0
    } else {
        rows.iter()
            .filter(|r| r.due_ms.map(|ms| day_of(ms) < today_day).unwrap_or(false))
            .count()
    };
    Ok(Group {
        status: st,
        name: match st {
            Some(s) => name_of(e, s)?,
            None => "No status".to_owned(),
        },
        completes,
        rows,
        late,
    })
}

/// Due ascending with undated last, then title, then id — stable across
/// refreshes, which a sort that ended at the title was not.
fn sort(rows: &mut [Row]) {
    rows.sort_by(|a, b| {
        let da = a.due_ms.unwrap_or(i64::MAX);
        let db = b.due_ms.unwrap_or(i64::MAX);
        (da, a.title.to_lowercase(), a.id).cmp(&(db, b.title.to_lowercase(), b.id))
    });
}

fn matches(e: &Engine, r: &Row, filter: Filter) -> Result<bool, LogError> {
    Ok(match filter {
        Filter::All => true,
        Filter::Status(s) => r.status == Some(s),
        Filter::Project(p) => matches!(e.one(r.id, prop::PROJECT)?, Some(Value::Ref(x)) if x == p),
    })
}

/// The word for a status — from the model for one of ours, from its name
/// cell for a minted one. **The only place these words exist**: the shell
/// carried the six area names as a Swift constant, which `one-core.md` §4
/// calls shell-side furnishing and a mistake.
/// **Public since 2026-09-19**, for the clerk's wire: a proposal whose
/// value is a `Ref` has to cross the ABI as the word a person reads, and
/// a second spelling of "the word for an id" is the drift this comment
/// already warns about.
pub fn name_of(e: &Engine, id: EntityId) -> Result<String, LogError> {
    if let Some(label) = model::label(id) {
        return Ok(label.to_owned());
    }
    Ok(e.name(id)?.unwrap_or_default())
}
