//! The calendar's day: one timeline, laid out.
//!
//! From `Calendar.swift`, which held eight collection operations. The
//! layout arithmetic — where a block sits and how tall it is — is here
//! rather than in the view, because it is arithmetic and the same two
//! numbers have to come out on every shell.

use liv_engine::{Engine, LogError};

use crate::{agenda, Lens, Row};

/// One block on the timeline.
#[derive(Debug, Clone, PartialEq)]
pub struct Block {
    pub row: Row,
    /// Minutes from midnight — what the block's top is measured in. The
    /// shell multiplies by its own points-per-hour and adds its own
    /// insets; it is not told pixels, because those are its business.
    pub start_min: i32,
    /// How long, in minutes. **Never zero**: a thing with no duration
    /// still has to be tappable, so it gets `MIN_MINUTES` and the shell
    /// does not have to know that.
    pub minutes: i32,
    /// Which of the overlapping blocks this is, and how many overlap —
    /// the two numbers a column layout needs. Computed here because
    /// "these three things clash" is a fact about the day, not about the
    /// screen it is drawn on.
    pub column: usize,
    pub columns: usize,
}

/// The floor a block is given so it can still be hit with a finger.
pub const MIN_MINUTES: i32 = 30;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Day {
    /// Things that belong to the day rather than to an hour — the strip
    /// above the timeline.
    pub all_day: Vec<Row>,
    pub blocks: Vec<Block>,
}

pub fn day(e: &Engine, day_num: i32, lens: &Lens) -> Result<Day, LogError> {
    let mut out = Day::default();
    let mut timed: Vec<Row> = Vec::new();
    for r in agenda(e, day_num, lens)? {
        if r.all_day {
            out.all_day.push(r);
        } else {
            timed.push(r);
        }
    }

    let midnight = crate::day_start(day_num);
    let mut blocks: Vec<Block> = timed
        .into_iter()
        .map(|r| {
            let start = ((r.due_ms.unwrap_or(midnight) - midnight) / 60_000) as i32;
            Block {
                row: r,
                // Clamped into the day: a value that drifted outside it
                // would otherwise be drawn off the top or below the
                // bottom, where nobody can reach it.
                start_min: start.clamp(0, 24 * 60 - 1),
                minutes: MIN_MINUTES,
                column: 0,
                columns: 1,
            }
        })
        .collect();

    lay_out(&mut blocks);
    out.blocks = blocks;
    Ok(out)
}

/// Give overlapping blocks their columns.
///
/// **A cluster, not a pair.** Two blocks that do not touch each other can
/// still both touch a third, and all three have to share the width or the
/// middle one is drawn over. So the sweep grows a run while anything in it
/// is still open, and every block in that run gets the run's width.
fn lay_out(blocks: &mut [Block]) {
    // `agenda` already sorted by start; this only needs the runs.
    let mut i = 0;
    while i < blocks.len() {
        let mut end = blocks[i].start_min + blocks[i].minutes;
        let mut j = i + 1;
        while j < blocks.len() && blocks[j].start_min < end {
            end = end.max(blocks[j].start_min + blocks[j].minutes);
            j += 1;
        }
        let width = j - i;
        for (n, b) in blocks[i..j].iter_mut().enumerate() {
            b.column = n;
            b.columns = width;
        }
        i = j;
    }
}
