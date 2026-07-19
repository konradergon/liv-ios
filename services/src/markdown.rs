//! Markdown ↔ the span model (P15a, D7). CommonMark maps almost 1:1 onto
//! `Span::{Text(marks), Break(Block), Ref(Id)}` + `Block::{Heading, Bullet,
//! Ordered, Task, Quote, Code, Rule, Body}`, so import parses a `.md` body into
//! rich content and export renders it back. The parser is `pulldown-cmark`
//! (vetted, not hand-rolled — the same call P7 made for `sha2`). Three bounded
//! limits, recorded as deltas in `design/p15-files-import.md`:
//!   - `[[Wikilink]]` needs name→id resolution, done in a second pass
//!     (`resolve_wikilinks`) once the import batch's entities exist; an
//!     unresolved name stays literal text.
//!   - inline `[text](url)` keeps its visible text (no href slot in the model).
//!   - YAML frontmatter is parsed flat (`key: value` + simple `[a, b]` / `- x`
//!     lists); nested YAML defers.

use lotus_core::{Block, Id, Marks, RichText, Span, TextSpan};
use pulldown_cmark::{CodeBlockKind, Event, Options, Parser, Tag, TagEnd};

/// CommonMark → the span model. Blocks become `Break`s that TYPE the paragraph
/// that follows (the model's one structure); inline emphasis becomes `Marks`;
/// links keep their text; `[[wikilinks]]` are left literal for `resolve_wikilinks`.
pub fn parse_markdown(raw: &str) -> RichText {
    let mut opts = Options::empty();
    opts.insert(Options::ENABLE_STRIKETHROUGH);
    opts.insert(Options::ENABLE_TASKLISTS);

    let mut spans: Vec<Span> = Vec::new();
    let mut marks: u8 = 0;
    let mut list_stack: Vec<Option<u64>> = Vec::new(); // Some = ordered, None = bullet
    let mut quote_depth: usize = 0;
    let mut in_code = false;
    let mut code_lang: Option<String> = None;
    let mut code_buf = String::new(); // buffered until End(CodeBlock), then line-split
    let mut suppress_para = false; // an item's own break already opened its block
    let mut last_item_break: Option<usize> = None;

    let push_text = |spans: &mut Vec<Span>, text: &str, marks: u8| {
        if !text.is_empty() {
            spans.push(Span::Text(TextSpan { text: text.to_string(), marks: Marks(marks) }));
        }
    };

    for event in Parser::new_ext(raw, opts) {
        match event {
            Event::Start(Tag::Paragraph) => {
                if suppress_para {
                    suppress_para = false;
                } else {
                    spans.push(Span::Break(if quote_depth > 0 { Block::Quote } else { Block::Body }));
                }
            }
            Event::Start(Tag::Heading { level, .. }) => {
                spans.push(Span::Break(Block::Heading(level as u8)));
            }
            Event::Start(Tag::BlockQuote(_)) => quote_depth += 1,
            Event::End(TagEnd::BlockQuote(_)) => quote_depth = quote_depth.saturating_sub(1),
            Event::Start(Tag::CodeBlock(kind)) => {
                code_lang = match kind {
                    CodeBlockKind::Fenced(lang) if !lang.is_empty() => Some(lang.to_string()),
                    _ => None,
                };
                in_code = true;
                code_buf.clear();
                spans.push(Span::Break(Block::Code { lang: code_lang.clone() }));
            }
            Event::End(TagEnd::CodeBlock) => {
                // Emit the buffered code as one Break(Code) per line (the model
                // forbids a newline inside a Text). Drop pulldown's single
                // fence-terminating trailing newline so no empty last line.
                let content = code_buf.strip_suffix('\n').unwrap_or(&code_buf);
                for (i, line) in content.split('\n').enumerate() {
                    if i > 0 {
                        spans.push(Span::Break(Block::Code { lang: code_lang.clone() }));
                    }
                    push_text(&mut spans, line, 0);
                }
                in_code = false;
                code_lang = None;
                code_buf.clear();
            }
            // A block of raw HTML starts its own paragraph (it is not inline).
            Event::Start(Tag::HtmlBlock) => spans.push(Span::Break(Block::Body)),
            Event::Start(Tag::List(start)) => list_stack.push(start),
            // A TIGHT item emits no Paragraph events, so its suppression
            // must die with the item — or the NEXT paragraph's break gets
            // swallowed and its text glues onto the item (the P20j.1
            // fixpoint gate's catch).
            Event::End(TagEnd::Item) => suppress_para = false,
            Event::End(TagEnd::List(_)) => {
                list_stack.pop();
            }
            Event::Start(Tag::Item) => {
                let depth = list_stack.len().saturating_sub(1) as u8;
                let ordered = matches!(list_stack.last(), Some(Some(_)));
                let block = if ordered {
                    Block::Ordered { depth }
                } else {
                    Block::Bullet { depth }
                };
                spans.push(Span::Break(block));
                last_item_break = Some(spans.len() - 1);
                suppress_para = true;
            }
            Event::TaskListMarker(done) => {
                if let Some(i) = last_item_break {
                    let depth = list_stack.len().saturating_sub(1) as u8;
                    spans[i] = Span::Break(Block::Task { depth, done });
                }
            }
            Event::Start(Tag::Emphasis) => marks |= Marks::ITALIC,
            Event::End(TagEnd::Emphasis) => marks &= !Marks::ITALIC,
            Event::Start(Tag::Strong) => marks |= Marks::BOLD,
            Event::End(TagEnd::Strong) => marks &= !Marks::BOLD,
            Event::Start(Tag::Strikethrough) => marks |= Marks::STRIKE,
            Event::End(TagEnd::Strikethrough) => marks &= !Marks::STRIKE,
            Event::Text(text) => {
                if in_code {
                    code_buf.push_str(&text);
                } else {
                    push_text(&mut spans, &text, marks);
                }
            }
            Event::Code(text) => push_text(&mut spans, &text, marks | Marks::CODE),
            Event::SoftBreak | Event::HardBreak => {
                if !in_code {
                    push_text(&mut spans, " ", marks);
                }
            }
            Event::Rule => spans.push(Span::Break(Block::Rule)),
            // Raw HTML has no first-class span home; keep its text, but never
            // a newline (the model's invariant) — collapse them to spaces.
            Event::Html(text) | Event::InlineHtml(text) => {
                push_text(&mut spans, &text.replace('\n', " "), marks)
            }
            // Links/images: keep the inner text (emitted as Text events); the
            // dest url has no slot in the model (D7). Everything else ignored.
            _ => {}
        }
    }

    RichText { spans }
}

/// `RichText` → markdown for export (D7). Marks become `**`/`*`/`` ` ``/`~~`;
/// blocks their line prefixes; a `Ref` its target's name as `[[Name]]`.
pub fn render_markdown(text: &RichText, name_of: &dyn Fn(Id) -> String) -> String {
    // Group the span stream into (block, inline-run) pairs. Runs stay
    // structured until the whole paragraph is known: the canonical inline
    // renderer needs the neighborhood (P20j.1 — the fixpoint gate).
    enum Run {
        Text(TextSpan),
        Ref(Id),
    }
    let mut blocks: Vec<(Block, Vec<Run>)> = Vec::new();
    let mut cur_block = Block::Body;
    let mut cur: Vec<Run> = Vec::new();
    let mut started = false;
    for span in &text.spans {
        match span {
            Span::Break(b) => {
                if started {
                    blocks.push((cur_block.clone(), std::mem::take(&mut cur)));
                }
                cur_block = b.clone();
                started = true;
            }
            Span::Text(ts) => {
                started = true;
                cur.push(Run::Text(ts.clone()));
            }
            Span::Ref(id) => {
                started = true;
                cur.push(Run::Ref(*id));
            }
        }
    }
    if started {
        blocks.push((cur_block, cur));
    }

    // The canonical inline form (the render∘parse fixpoint, P20j.1):
    // (1) adjacent text runs with IDENTICAL marks merge — two abutting code
    // spans would otherwise lex as one span with literal backticks, two
    // abutting strikes as a four-tilde run; (2) marks emit through a
    // nesting STACK (strike ⊃ bold ⊃ italic), so a mark shared by
    // neighbors never closes and reopens at the boundary — no ~~~~, ever.
    let render_inline = |runs: &[Run]| -> String {
        // Merge pass.
        let mut merged: Vec<Run> = Vec::new();
        for run in runs {
            // CODE renders literally — other bits on a code run are
            // unrenderable, so they normalize away (parse reality: a code
            // span comes back as code-only; normalizing here IS the
            // fixpoint).
            let normalized = |ts: &TextSpan| -> TextSpan {
                if ts.marks.0 & Marks::CODE != 0 {
                    TextSpan { text: ts.text.clone(), marks: Marks(Marks::CODE) }
                } else {
                    ts.clone()
                }
            };
            match (merged.last_mut(), run) {
                (Some(Run::Text(last)), Run::Text(ts))
                    if last.marks == normalized(ts).marks =>
                {
                    last.text.push_str(&ts.text);
                }
                (_, Run::Text(ts)) => merged.push(Run::Text(normalized(ts))),
                (_, Run::Ref(id)) => merged.push(Run::Ref(*id)),
            }
        }
        // Whitespace hoist: emphasis cannot wrap boundary whitespace
        // (a delimiter next to a space fails flanking) — leading/trailing
        // ws moves OUT of marked runs as plain runs, preserving bytes.
        let mut hoisted: Vec<Run> = Vec::new();
        for run in merged {
            match run {
                Run::Text(ts)
                    if ts.marks.0 != 0
                        && ts.marks.0 & Marks::CODE == 0
                        && (ts.text.starts_with(' ') || ts.text.ends_with(' ')) =>
                {
                    let core_start = ts.text.len() - ts.text.trim_start().len();
                    let core_end = ts.text.trim_end().len();
                    if core_start > 0 {
                        hoisted.push(Run::Text(TextSpan {
                            text: ts.text[..core_start].to_string(),
                            marks: Marks(0),
                        }));
                    }
                    if core_end > core_start {
                        hoisted.push(Run::Text(TextSpan {
                            text: ts.text[core_start..core_end].to_string(),
                            marks: ts.marks,
                        }));
                    }
                    if core_end < ts.text.len() {
                        hoisted.push(Run::Text(TextSpan {
                            text: ts.text[core_end..].to_string(),
                            marks: Marks(0),
                        }));
                    }
                }
                other => hoisted.push(other),
            }
        }
        let merged = hoisted;

        // Stack pass.
        // Distinct marker families — underscore italic can never fuse
        // with ** into an ambiguous ***; the price is the intraword
        // underscore rule: a no-space italic adjacency parses literal
        // (byte-STABLE, marks lost — the codec's one recorded lossy case).
        // Strike INNERMOST: a ~~ delimiter is then always word-flanked,
        // so GFM's flanking rules pair it deterministically — a closing
        // ~~ after punctuation ( **~~ ) fails right-flanking and re-pairs
        // as an opener, the exact instability the gate caught.
        const ORDER: [(u8, &str); 3] =
            [(Marks::BOLD, "**"), (Marks::ITALIC, "_"), (Marks::STRIKE, "~~")];
        let mut out = String::new();
        let mut active: Vec<(u8, &str)> = Vec::new();
        let close_to = |out: &mut String, active: &mut Vec<(u8, &str)>, keep: usize| {
            while active.len() > keep {
                let (_, marker) = active.pop().unwrap();
                out.push_str(marker);
            }
        };
        for run in &merged {
            match run {
                Run::Ref(id) => {
                    close_to(&mut out, &mut active, 0);
                    out.push_str(&format!("[[{}]]", name_of(*id)));
                }
                Run::Text(ts) if ts.text.is_empty() => {}
                Run::Text(ts) if ts.marks.0 & Marks::CODE != 0 => {
                    // Inline code is literal and closes everything; a
                    // backtick inside widens the fence.
                    close_to(&mut out, &mut active, 0);
                    if ts.text.contains('`') {
                        out.push_str(&format!("`` {} ``", ts.text));
                    } else {
                        out.push_str(&format!("`{}`", ts.text));
                    }
                }
                Run::Text(ts) => {
                    let want: Vec<(u8, &str)> = ORDER
                        .iter()
                        .filter(|(bit, _)| ts.marks.0 & bit != 0)
                        .copied()
                        .collect();
                    let common = active
                        .iter()
                        .zip(want.iter())
                        .take_while(|(a, w)| a == w)
                        .count();
                    close_to(&mut out, &mut active, common);
                    for entry in &want[common..] {
                        out.push_str(entry.1);
                        active.push(*entry);
                    }
                    out.push_str(&ts.text);
                }
            }
        }
        close_to(&mut out, &mut active, 0);
        out
    };
    let blocks: Vec<(Block, String)> =
        blocks.into_iter().map(|(b, runs)| (b, render_inline(&runs))).collect();

    // Consecutive Code blocks are one fence; every other block is a line.
    // List depths canonicalize against the CHAIN (P20j.1): an orphan depth
    // clamps to parent+1, and indentation is the cumulative parent marker
    // width ("- "=2, "1. "=3, "- [x] "=6) — anything shallower flattens on
    // reparse, anything orphaned is unrepresentable in markdown at all.
    let mut out: Vec<String> = Vec::new();
    let mut chain: Vec<usize> = Vec::new(); // parent content-column widths
    let mut i = 0;
    while i < blocks.len() {
        if let (Block::Code { lang }, _) = (&blocks[i].0, ()) {
            chain.clear();
            let lang = lang.clone().unwrap_or_default();
            let mut lines = Vec::new();
            while i < blocks.len() {
                if let Block::Code { .. } = blocks[i].0 {
                    lines.push(blocks[i].1.clone());
                    i += 1;
                } else {
                    break;
                }
            }
            out.push(format!("```{}\n{}\n```", lang, lines.join("\n")));
            continue;
        }
        let (block, inline) = (&blocks[i].0, &blocks[i].1);
        let marker_width = |b: &Block| -> usize {
            match b {
                Block::Bullet { .. } => 2,
                Block::Ordered { .. } => 3,
                // The [ ] is CONTENT per the tasklist ext — the item's
                // child column is the "- " width, and 6 would tip a
                // child into indented-code territory.
                Block::Task { .. } => 2,
                _ => 0,
            }
        };
        let depth_of = |b: &Block| -> Option<u8> {
            match b {
                Block::Bullet { depth } | Block::Ordered { depth }
                | Block::Task { depth, .. } => Some(*depth),
                _ => None,
            }
        };
        match depth_of(block) {
            Some(want) => {
                let eff = (want as usize).min(chain.len());
                chain.truncate(eff);
                let indent: usize = chain.iter().sum();
                out.push(format!(
                    "{}{}",
                    " ".repeat(indent),
                    render_block(block, inline)
                ));
                chain.push(marker_width(block));
            }
            None => {
                chain.clear();
                out.push(render_block(block, inline));
            }
        }
        i += 1;
    }
    out.join("\n\n")
}

fn render_block(block: &Block, inline: &str) -> String {
    match block {
        Block::Body => inline.to_string(),
        Block::Heading(n) => format!("{} {}", "#".repeat((*n).clamp(1, 6) as usize), inline),
        Block::Quote => format!("> {inline}"),
        Block::Bullet { .. } => format!("- {inline}"),
        Block::Ordered { .. } => format!("1. {inline}"),
        Block::Task { done, .. } => {
            format!("- [{}] {inline}", if *done { "x" } else { " " })
        }
        Block::Code { .. } => inline.to_string(), // handled by the fence grouping
        Block::Callout { .. } => format!("> {inline}"),
        Block::Rule => "---".to_string(),
    }
}


/// Split a leading `---` YAML frontmatter block off the body (D7). Flat scalars
/// and simple lists only. No frontmatter → `(empty, whole input)`.
pub fn split_frontmatter(raw: &str) -> (Vec<(String, String)>, String) {
    let mut lines = raw.lines();
    if lines.next().map(str::trim) != Some("---") {
        return (Vec::new(), raw.to_string());
    }
    let mut fm: Vec<String> = Vec::new();
    let mut closed = false;
    for line in lines.by_ref() {
        if line.trim() == "---" {
            closed = true;
            break;
        }
        fm.push(line.to_string());
    }
    if !closed {
        return (Vec::new(), raw.to_string()); // no terminator — not frontmatter
    }
    let body = lines.collect::<Vec<_>>().join("\n");

    let mut pairs: Vec<(String, String)> = Vec::new();
    let mut pending_key: Option<String> = None;
    for line in fm {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some(item) = trimmed.strip_prefix("- ") {
            if let Some(key) = &pending_key {
                pairs.push((key.clone(), unquote(item)));
            }
            continue;
        }
        if let Some((key, value)) = trimmed.split_once(':') {
            let key = key.trim().to_string();
            let value = value.trim();
            if value.is_empty() {
                pending_key = Some(key); // a following `- item` block
            } else if let Some(inner) = value.strip_prefix('[').and_then(|v| v.strip_suffix(']')) {
                pending_key = None;
                for item in inner.split(',') {
                    let item = item.trim();
                    if !item.is_empty() {
                        pairs.push((key.clone(), unquote(item)));
                    }
                }
            } else {
                pending_key = None;
                pairs.push((key, unquote(value)));
            }
        }
    }
    (pairs, body)
}

fn unquote(s: &str) -> String {
    let s = s.trim();
    let bytes = s.as_bytes();
    if s.len() >= 2 && bytes[0] == b'"' && bytes[s.len() - 1] == b'"' {
        // Double quotes: unescape \" and \\ (the export escaping, symmetric).
        let inner = &s[1..s.len() - 1];
        let mut out = String::with_capacity(inner.len());
        let mut chars = inner.chars();
        while let Some(c) = chars.next() {
            if c == '\\' {
                match chars.next() {
                    Some('"') => out.push('"'),
                    Some('\\') => out.push('\\'),
                    Some(other) => {
                        out.push('\\');
                        out.push(other);
                    }
                    None => out.push('\\'),
                }
            } else {
                out.push(c);
            }
        }
        out
    } else if s.len() >= 2 && bytes[0] == b'\'' && bytes[s.len() - 1] == b'\'' {
        s[1..s.len() - 1].to_string()
    } else {
        s.to_string()
    }
}

/// Second pass (P15a): rewrite literal `[[Name]]` text runs into `Span::Ref`s
/// once the batch's entities exist. `resolve` maps a name to an id; a miss
/// leaves the `[[Name]]` literal for the clerk/backlinks to reconcile later.
pub fn resolve_wikilinks(text: &mut RichText, resolve: &dyn Fn(&str) -> Option<Id>) {
    let mut out: Vec<Span> = Vec::with_capacity(text.spans.len());
    // A `[[Name]]` can arrive split across adjacent same-mark text runs
    // (pulldown emits the shortcut-link brackets separately), so coalesce a
    // same-mark run before scanning it. A Break or Ref ends the run — a
    // wikilink never spans a paragraph boundary.
    let mut run = String::new();
    let mut run_marks = Marks(0);
    let flush = |out: &mut Vec<Span>, run: &mut String, marks: Marks| {
        if run.is_empty() {
            return;
        }
        // Inline code is literal — `[[Foo]]` inside it is text, not a link.
        if marks.0 & Marks::CODE != 0 {
            out.push(Span::Text(TextSpan { text: std::mem::take(run), marks }));
        } else {
            out.extend(split_wikilinks(run, marks, resolve));
            run.clear();
        }
    };
    for span in text.spans.drain(..) {
        match span {
            Span::Text(ts) => {
                if !run.is_empty() && ts.marks != run_marks {
                    flush(&mut out, &mut run, run_marks);
                }
                run_marks = ts.marks;
                run.push_str(&ts.text);
            }
            other => {
                flush(&mut out, &mut run, run_marks);
                out.push(other);
            }
        }
    }
    flush(&mut out, &mut run, run_marks);
    text.spans = out;
}

fn split_wikilinks(text: &str, marks: Marks, resolve: &dyn Fn(&str) -> Option<Id>) -> Vec<Span> {
    let mut result: Vec<Span> = Vec::new();
    let mut lit = String::new();
    let mut s = text;
    loop {
        match s.find("[[") {
            None => {
                lit.push_str(s);
                break;
            }
            Some(p) => {
                let after = &s[p + 2..];
                if let Some(q) = after.find("]]") {
                    let name = after[..q].trim();
                    if let Some(id) = resolve(name) {
                        lit.push_str(&s[..p]);
                        if !lit.is_empty() {
                            result.push(Span::Text(TextSpan { text: std::mem::take(&mut lit), marks }));
                        }
                        result.push(Span::Ref(id));
                    } else {
                        lit.push_str(&s[..p + 2 + q + 2]); // keep "[[name]]" literal
                    }
                    s = &after[q + 2..];
                } else {
                    lit.push_str(s); // no closing ]] — the rest is literal
                    break;
                }
            }
        }
    }
    if !lit.is_empty() {
        result.push(Span::Text(TextSpan { text: lit, marks }));
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn no_names(_: Id) -> String {
        String::new()
    }

    fn text_at(rt: &RichText, i: usize) -> (&str, u8) {
        match &rt.spans[i] {
            Span::Text(ts) => (ts.text.as_str(), ts.marks.0),
            _ => panic!("span {i} is not text: {:?}", rt.spans[i]),
        }
    }

    #[test]
    fn headings_and_inline_marks() {
        let rt = parse_markdown("# Title\n\nHello **bold** and *it* and `co` and ~~no~~");
        assert_eq!(rt.spans[0], Span::Break(Block::Heading(1)));
        assert_eq!(text_at(&rt, 1).0, "Title");
        assert_eq!(rt.spans[2], Span::Break(Block::Body));
        // the run carrying "bold" has the BOLD bit; "it" the ITALIC bit; etc.
        let bold = rt.spans.iter().find_map(|s| match s {
            Span::Text(ts) if ts.text == "bold" => Some(ts.marks.0),
            _ => None,
        });
        assert_eq!(bold, Some(Marks::BOLD));
        let ital = rt.spans.iter().find_map(|s| match s {
            Span::Text(ts) if ts.text == "it" => Some(ts.marks.0),
            _ => None,
        });
        assert_eq!(ital, Some(Marks::ITALIC));
        let code = rt.spans.iter().find_map(|s| match s {
            Span::Text(ts) if ts.text == "co" => Some(ts.marks.0),
            _ => None,
        });
        assert_eq!(code, Some(Marks::CODE));
        let strike = rt.spans.iter().find_map(|s| match s {
            Span::Text(ts) if ts.text == "no" => Some(ts.marks.0),
            _ => None,
        });
        assert_eq!(strike, Some(Marks::STRIKE));
    }

    #[test]
    fn bullets_carry_depth() {
        let rt = parse_markdown("- a\n- b");
        assert_eq!(rt.spans[0], Span::Break(Block::Bullet { depth: 0 }));
        assert_eq!(text_at(&rt, 1).0, "a");
        assert_eq!(rt.spans[2], Span::Break(Block::Bullet { depth: 0 }));
        assert_eq!(text_at(&rt, 3).0, "b");
    }

    #[test]
    fn task_items_record_done() {
        let rt = parse_markdown("- [ ] todo\n- [x] done");
        assert_eq!(rt.spans[0], Span::Break(Block::Task { depth: 0, done: false }));
        assert_eq!(text_at(&rt, 1).0, "todo");
        assert_eq!(rt.spans[2], Span::Break(Block::Task { depth: 0, done: true }));
        assert_eq!(text_at(&rt, 3).0, "done");
    }

    #[test]
    fn round_trips_the_covered_subset() {
        let md = "# Title\n\nHello **bold** and *it*.\n\n- one\n- two\n\n- [x] did\n\n## Sub\n\nplain body";
        let once = parse_markdown(md);
        let rendered = render_markdown(&once, &no_names);
        let twice = parse_markdown(&rendered);
        assert_eq!(once, twice, "rendered:\n{rendered}");
    }

    #[test]
    fn frontmatter_scalars_and_lists() {
        let (pairs, body) =
            split_frontmatter("---\ntitle: Hello\ntags: [a, b]\nproject:\n- x\n- y\n---\nBody text");
        assert_eq!(
            pairs,
            vec![
                ("title".into(), "Hello".into()),
                ("tags".into(), "a".into()),
                ("tags".into(), "b".into()),
                ("project".into(), "x".into()),
                ("project".into(), "y".into()),
            ]
        );
        assert_eq!(body, "Body text");
    }

    #[test]
    fn no_frontmatter_returns_whole_body() {
        let (pairs, body) = split_frontmatter("Just a body\nwith two lines");
        assert!(pairs.is_empty());
        assert_eq!(body, "Just a body\nwith two lines");
    }

    #[test]
    fn html_block_never_puts_a_newline_in_a_text_span() {
        let rt = parse_markdown("para\n\n<div>\nhi\n</div>\n\nmore");
        for sp in &rt.spans {
            if let Span::Text(ts) = sp {
                assert!(!ts.text.contains('\n'), "text span holds a newline: {:?}", ts.text);
            }
        }
    }

    #[test]
    fn code_block_has_no_trailing_empty_line() {
        let rt = parse_markdown("```\na\nb\n```");
        let texts: Vec<&str> = rt.spans.iter().filter_map(|s| match s {
            Span::Text(ts) => Some(ts.text.as_str()),
            _ => None,
        }).collect();
        assert_eq!(texts, vec!["a", "b"]);
        // Exactly one Code break per line — no spurious trailing empty break.
        let code_breaks = rt.spans.iter().filter(|s| matches!(s, Span::Break(Block::Code { .. }))).count();
        assert_eq!(code_breaks, 2, "spurious trailing Code break: {:?}", rt.spans);
        // And it round-trips stably (no growing blank lines).
        let twice = parse_markdown(&render_markdown(&rt, &no_names));
        assert_eq!(rt, twice);
    }

    #[test]
    fn wikilink_inside_inline_code_stays_code() {
        let mut rt = parse_markdown("run `[[Foo]]` now");
        resolve_wikilinks(&mut rt, &|_| Some(7)); // resolver would match anything
        assert!(!rt.spans.iter().any(|s| matches!(s, Span::Ref(_))), "code wikilink became a ref: {:?}", rt.spans);
        assert!(rt.spans.iter().any(|s| matches!(s, Span::Text(ts) if ts.text == "[[Foo]]" && ts.marks.0 & Marks::CODE != 0)));
    }

    #[test]
    fn wikilinks_resolve_or_stay_literal() {
        let mut rt = parse_markdown("see [[Alpha]] and [[Zed]] end");
        resolve_wikilinks(&mut rt, &|name| if name == "Alpha" { Some(7) } else { None });
        // The body paragraph: "see " + Ref(7) + " and [[Zed]] end"
        let refs: Vec<Id> = rt.spans.iter().filter_map(|s| match s {
            Span::Ref(id) => Some(*id),
            _ => None,
        }).collect();
        assert_eq!(refs, vec![7]);
        let joined: String = rt.spans.iter().filter_map(|s| match s {
            Span::Text(ts) => Some(ts.text.clone()),
            _ => None,
        }).collect();
        assert!(joined.contains("[[Zed]]"), "unresolved link kept literal: {joined}");
        assert!(!joined.contains("[[Alpha]]"), "resolved link replaced: {joined}");
    }
}
