//! Two surfaces the swap would otherwise take away.
//!
//! Mapping the engine's verbs against the app's screens found three
//! things the old snapshot serves and nothing here does. Two of them are
//! small and are here; the third — expanding a recurrence into its
//! occurrences — is a subsystem, and the calendar is missing it until
//! someone builds it.
//!
//! ## The trash
//!
//! `visible` drops trashed rows from every surface, which is right for
//! all of them except the one whose whole subject is the trash. It needs
//! the opposite filter, and nothing else does.
//!
//! ## Open lines inside notes
//!
//! A `- [ ]` written inside a note is a task the Tasks view lists under
//! "In notes". **It is a PROJECTION**: nothing is stored, no entity is
//! created, no cell is written. It is derived on read and thrown away,
//! which is exactly why it has to be derived somewhere — and Rust is
//! where the body already is.

use liv_engine::{prop, rich, Engine, EntityId, LogError, Value};

use crate::{row, visible, Lens, Row};

/// What is in the trash, newest first.
///
/// **The one surface that wants the rows `visible` throws away.** It
/// deliberately ignores the lens: the trash is the trash, and a workspace
/// filter hiding some of it would leave a person unable to find the thing
/// they are trying to get back.
///
/// Archived is NOT trashed and is not here. Archiving is filing something
/// away; trashing is throwing it out, and the two screens are different.
pub fn trash(e: &Engine) -> Result<Vec<Row>, LogError> {
    let mut rows = Vec::new();
    for id in e.with_value(prop::TRASHED, &Value::Bool(true))? {
        let r = row(e, id)?;
        if r.trashed {
            rows.push(r);
        }
    }
    // Newest first: the thing you just deleted is the thing you are most
    // likely to want back.
    rows.sort_by(|a, b| b.id.cmp(&a.id));
    Ok(rows)
}

/// One open checkbox line written inside a note.
pub struct NoteTask {
    /// The note that holds the line.
    pub note: EntityId,
    /// What that note is called — computed here, where the body is.
    pub source: String,
    /// Which block it is, counting from the top of the body. **The
    /// toggle's address**, so a shell can tick it without a second scan.
    pub line: usize,
    pub text: String,
    pub depth: u8,
}

/// Every unticked `- [ ]` line inside a live note.
///
/// **A projection: nothing here is stored.** No entity is created and no
/// cell is written, which is the whole point — a line in a note is a
/// thought, not a task someone has to file.
///
/// Notes only, and only ones that are not already a task or an event:
/// their own body lines would double-count in the view that already lists
/// them as things in their own right.
pub fn note_tasks(e: &Engine, lens: &Lens) -> Result<Vec<NoteTask>, LogError> {
    let mut out = Vec::new();
    let mut ids = e.all_entities()?;
    ids.sort();
    for note in ids {
        let r = row(e, note)?;
        if !visible(&r, lens) {
            continue;
        }
        // Something already typed as a task or an event is listed as
        // itself; its body lines would be the same work counted twice.
        if matches!(r.kind, Some(k) if k == liv_engine::kind::TASK || k == liv_engine::kind::EVENT)
        {
            continue;
        }
        let Some(Value::Rich(spans)) = e.one(note, prop::BODY)? else { continue };
        for (line, task) in open_lines(&spans) {
            out.push(NoteTask {
                note,
                source: r.title.clone(),
                line,
                text: task.0,
                depth: task.1,
            });
        }
    }
    Ok(out)
}

/// The open task lines of one body, with the block index of each.
///
/// A block owns the runs that follow it until the next block, so the text
/// of a line is everything between its own marker and the next one.
/// **Only unticked ones**: a done line is not something to do.
fn open_lines(spans: &[rich::Span]) -> Vec<(usize, (String, u8))> {
    let mut out = Vec::new();
    let mut block = 0usize;
    let mut open: Option<(usize, u8, String)> = None;
    for s in spans {
        match s {
            rich::Span::Break(b) => {
                if let Some((line, depth, text)) = open.take() {
                    push(&mut out, line, depth, text);
                }
                block += 1;
                if let rich::Block::Task { depth, done } = b {
                    if !done {
                        open = Some((block, *depth, String::new()));
                    }
                }
            }
            rich::Span::Text(t) => {
                if let Some((_, _, text)) = open.as_mut() {
                    text.push_str(&t.text);
                }
            }
            // A link inside a task line is part of the line's words as
            // far as a list is concerned; it renders as a chip in the
            // editor and has no text of its own here.
            rich::Span::Ref(_) => {}
        }
    }
    if let Some((line, depth, text)) = open.take() {
        push(&mut out, line, depth, text);
    }
    out
}

fn push(out: &mut Vec<(usize, (String, u8))>, line: usize, depth: u8, text: String) {
    let text = text.trim().to_owned();
    // An empty checkbox is someone mid-sentence, not a task.
    if !text.is_empty() {
        out.push((line, (text, depth)));
    }
}
