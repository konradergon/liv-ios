//! Note task lines — a PROJECTION (roadmap phase 3, owner-approved
//! 2026-08-05; design/tasks-study.md).
//!
//! The gap it closes: a checkbox typed inside a note was real to the
//! person who wrote it and invisible to the one view whose job is tasks.
//!
//! Why this is lawful under "typed text is never parsed into meaning":
//! it derives a VIEW and stores nothing. It creates no entity, writes no
//! cell, mints no meaning — the only write in the whole feature is the
//! user's own tap, which performs exactly the text edit the editor's
//! checkbox already performs. Computed on read, stored nowhere, same
//! answer in every process (the timeviews rule).
//!
//! TWO authored forms exist in the wild and both are seen here:
//!
//!   1. `Span::Break(Block::Task { done })` — the core's own shape (D19:
//!      "markdown markers are never stored"). Nothing is parsed at all;
//!      the paragraph IS a task because the data says so.
//!   2. A literal `- [ ] ` prefix in a `Block::Body` paragraph — the iOS
//!      editor's recorded deviation until it converts to marks-and-blocks
//!      (shell/ios/Sources/EditorStyle.swift). Recognising it is the same
//!      display-level read the editor performs to draw the checkbox.
//!
//! Only OPEN lines project: a checked line is visible in the note that
//! owns it, and a task list nobody asked for is not a list.

use liv_core::*;
use serde::Serialize;

/// One open checkbox line inside a note.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct NoteTask {
    /// The note that holds the line.
    pub entity: Id,
    /// What to CALL that note: its name cell, else its own first
    /// non-empty line with markers off. Computed here, where the content
    /// actually is — `EntityRow.title` is a whole-body summary that
    /// flattens every paragraph into one string, and a chip showing
    /// "Roof project - [ ] call the surveyor - [x] paid…" names nothing
    /// (the same trap caught the editor's title prompt and the template
    /// namer before it).
    pub source: String,
    /// Line index in the note's buffer — the SHELL's line numbering
    /// (paragraph breaks are newlines; a leading break is not one), so a
    /// toggle can address the line without a second scan.
    pub line: u32,
    /// The line's words, marker stripped, references rendered as their
    /// target's name — what a human reads.
    pub text: String,
    /// Leading spaces/tabs (form 2) or block depth (form 1).
    pub indent: u32,
}

/// Every open checkbox line in every live note, document order.
///
/// Skipped, deliberately: trashed and archived entities; TEMPLATES (a
/// template's body is scaffolding — `- [ ] {{cursor}}` is not work); and
/// task/event-TYPED entities, whose own body lines would double-count
/// against themselves in the very view that already lists them.
pub fn note_tasks(store: &Store) -> Vec<NoteTask> {
    let template = crate::property_id(store, "template");
    let archived = crate::property_id(store, "archived");
    let task_type = crate::content::find_type(store, "task");
    let event_type = crate::content::find_type(store, "event");
    let mut out = Vec::new();
    for entity in store.entities() {
        if entity.trashed {
            continue;
        }
        if archived.is_some_and(|p| entity.has(p, &Value::Bool(true))) {
            continue;
        }
        if template.is_some_and(|p| {
            entity.all(p).any(|v| !matches!(v, Value::Text(t) if t.is_empty()))
        }) {
            continue;
        }
        // A task's or event's OWN body lines would double-count against
        // itself in the very view that already lists it. Every other type
        // (note, person, area…) projects: a note is where checkboxes live.
        if entity.all(props::TYPE).any(|v| {
            matches!(v, Value::Reference(t) if Some(*t) == task_type || Some(*t) == event_type)
        }) {
            continue;
        }
        let Some(Value::RichText(rich)) = entity.get(props::CONTENT) else {
            continue;
        };
        let source = crate::content::source_name(store, entity, rich);
        out.extend(open_lines(store, entity.id, &source, rich));
    }
    // `store.entities()` has no defined order, so the raw sweep is
    // nondeterministic: the list would reshuffle between refreshes, and
    // the snapshot cache-parity test (which compares byte-wise) would
    // flake. One note's lines stay in document order; notes order by id.
    out.sort_by_key(|t| (t.entity, t.line));
    out
}

/// The lines of one note's content, in the shell's own numbering.
fn open_lines(store: &Store, entity: Id, source: &str, rich: &RichText) -> Vec<NoteTask> {
    let mut out = Vec::new();
    // `line` counts the same way the editor's buffer does: a Break is a
    // newline UNLESS nothing has been emitted yet (a leading break opens
    // no line). `block` types the paragraph the break introduces.
    let mut line: u32 = 0;
    let mut text = String::new();
    let mut block = Block::Body;
    let mut started = false;
    let flush = |line: u32, block: &Block, text: &str, out: &mut Vec<NoteTask>| {
        if let Some(task) = task_of(line, block, text) {
            out.push(NoteTask { entity, source: source.to_string(), ..task });
        }
    };
    for span in &rich.spans {
        match span {
            Span::Break(next) => {
                if started {
                    flush(line, &block, &text, &mut out);
                    line += 1;
                    text.clear();
                }
                block = next.clone();
                started = true;
            }
            Span::Text(t) => {
                text.push_str(&t.text);
                started = true;
            }
            Span::Ref(target) => {
                text.push_str(&name_of(store, *target));
                started = true;
            }
        }
    }
    if started {
        flush(line, &block, &text, &mut out);
    }
    out
}

/// Is this paragraph an OPEN task WITH WORDS, and what does it say?
/// `entity` is the caller's to fill in.
///
/// An empty checkbox is not work — it is a line the writer has not
/// written yet (the editor's return-key continuation makes them by the
/// handful). Projecting them filled the view with "empty line" rows
/// naming nothing (found live, 2026-08-05).
fn task_of(line: u32, block: &Block, text: &str) -> Option<NoteTask> {
    // Form 1: the data says so.
    if let Block::Task { depth, done } = block {
        if text.trim().is_empty() {
            return None;
        }
        return (!done).then(|| NoteTask {
            entity: 0,
            source: String::new(),
            line,
            text: text.trim().to_string(),
            indent: *depth as u32,
        });
    }
    // Form 2: the iOS editor's literal marker.
    let indent =
        text.as_bytes().iter().take_while(|b| **b == b' ' || **b == b'\t').count();
    task_words(block, text).map(|words| NoteTask {
        entity: 0,
        source: String::new(),
        line,
        text: words,
        indent: indent as u32,
    })
}

/// A reference reads as its target's name — the token is plumbing.
pub(crate) fn name_of(store: &Store, target: Id) -> String {
    match store.get(target).and_then(|e| e.get(props::NAME)) {
        Some(Value::Text(name)) if !name.is_empty() => name.clone(),
        _ => format!("#{target}"),
    }
}

/// The WORDS of an open checkbox line, in either authored form, or None
/// when this paragraph is not one. Mirrors MarkScan.shape exactly — a
/// hyphen, one space, "[", the box, "]", one space — so the two shells
/// never disagree about what a checkbox is. Shared with the display-name
/// reader, which must call a checkbox line by its words.
pub(crate) fn task_words(block: &Block, text: &str) -> Option<String> {
    if let Block::Task { done, .. } = block {
        let words = text.trim();
        return (!done && !words.is_empty()).then(|| words.to_string());
    }
    let bytes = text.as_bytes();
    let indent = bytes.iter().take_while(|b| **b == b' ' || **b == b'\t').count();
    let rest = &bytes[indent..];
    if rest.len() < 6 || rest[0] != b'-' || rest[1] != b' ' || rest[2] != b'[' || rest[4] != b']'
        || rest[5] != b' '
    {
        return None;
    }
    match rest[3] {
        // A done box is not offered; anything else is not a box at all.
        b' ' if !text[indent + 6..].trim().is_empty() => {
            Some(text[indent + 6..].trim().to_string())
        }
        _ => None,
    }
}

