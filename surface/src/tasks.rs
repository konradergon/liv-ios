//! Tasks: every task, grouped by status, and what the screen says about
//! them.
//!
//! From `Tasks.swift`, which held nine collection operations and the rules
//! under them.

use liv_engine::{kind, model, prop, Engine, EntityId, LogError, Value};

use crate::salvage::{note_tasks, NoteTask};
use crate::{completes, dated, row, statuses, visible, Lens, Row};

/// How many projects the Project segment offers: a menu, not a directory.
pub const PROJECTS_OFFERED: usize = 6;

/// The Tasks screen.
///
/// **Everything its controls can pick is already in here.** A status
/// segment picks one of `groups` by name, so switching segments redraws
/// in the same frame without asking again. Only the project, which
/// changes who is on the screen, is a parameter.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Tasks {
    pub groups: Vec<Group>,
    /// Open tasks the lens admits, plus the open lines in its notes —
    /// the size of the SCREEN, whatever the project filter shows.
    pub open: usize,
    /// Open tasks the lens admits whose day has passed, whatever the
    /// project filter shows.
    pub late: usize,
    /// Every open `- [ ]` line inside a note the lens admits.
    pub in_notes: Vec<NoteTask>,
    /// What the Project segment offers: the projects in use, commonest
    /// first, then by name.
    pub projects: Vec<(EntityId, String)>,
}

/// One status band.
#[derive(Debug, Clone, PartialEq)]
pub struct Group {
    /// `None` is the "No status" band, which is not a status and never
    /// completes.
    pub status: Option<EntityId>,
    pub name: String,
    pub completes: bool,
    /// The status option's colour, in degrees, when it has one.
    pub hue: Option<i64>,
    pub rows: Vec<Row>,
    /// How many rows in the band are late. A finished band has none.
    pub late: usize,
}

pub fn tasks(
    e: &Engine,
    project: Option<EntityId>,
    lens: &Lens,
    today_day: i32,
) -> Result<Tasks, LogError> {
    // Every task the lens admits, by index seek.
    let mut all = Vec::new();
    for id in e.of_kind(kind::TASK)? {
        let r = row(e, id)?;
        if visible(&r, lens) {
            all.push(dated(r, today_day));
        }
    }
    let in_notes = note_tasks(e, lens)?;
    let open = all.iter().filter(|r| !r.done).count() + in_notes.len();
    let late = all.iter().filter(|r| r.late).count();

    // The project narrows inside the lens; the counts above do not move.
    let mut rows = Vec::new();
    for r in all {
        let keep = match project {
            None => true,
            Some(p) => matches!(e.one(r.id, prop::PROJECT)?, Some(Value::Ref(x)) if x == p),
        };
        if keep {
            rows.push(r);
        }
    }

    let mut groups = Vec::new();
    let mut used: Vec<EntityId> = Vec::new();
    for (st, name) in statuses(e)? {
        let mine: Vec<Row> = rows.iter().filter(|r| r.status == Some(st)).cloned().collect();
        used.extend(mine.iter().map(|r| r.id));
        groups.push(band(e, Some(st), name, mine)?);
    }
    // Everything the vocabulary did not claim — including a status that
    // has since been retired, so no task can fall off the screen.
    let rest: Vec<Row> = rows.into_iter().filter(|r| !used.contains(&r.id)).collect();
    groups.push(band(e, None, "No status".to_owned(), rest)?);

    // An empty group is not a group.
    groups.retain(|g| !g.rows.is_empty());

    let projects = e
        .values_in_use(prop::PROJECT)?
        .into_iter()
        .filter_map(|v| v.target.map(|id| (id, v.label)))
        .take(PROJECTS_OFFERED)
        .collect();

    Ok(Tasks { groups, open, late, in_notes, projects })
}

fn band(
    e: &Engine,
    st: Option<EntityId>,
    name: String,
    mut rows: Vec<Row>,
) -> Result<Group, LogError> {
    sort(&mut rows);
    let completes = match st {
        Some(s) => completes(e, s)?,
        None => false,
    };
    let hue = match st {
        Some(s) => match e.one(s, prop::HUE)? {
            Some(Value::Number(n)) => Some(n as i64),
            _ => None,
        },
        None => None,
    };
    // A finished band has nothing late in it by definition — its rows are
    // done — so this is 0 there without saying so.
    let late = rows.iter().filter(|r| r.late).count();
    Ok(Group { status: st, name, completes, hue, rows, late })
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
