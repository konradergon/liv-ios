//! A body on the wire, in the shape the shell already writes.
//!
//! **The shell's span JSON does not change, and that is the point.**
//! `Editor.swift`'s `SpanJSON` encodes and decodes serde's external
//! tagging of `core/`'s `Span` enum — `{"Text":"words"}`,
//! `{"Break":"Body"}`, `{"Break":{"Heading":3}}` — and it has a comment
//! saying it is pinned against the JSON strings in `core/src/value.rs`'s
//! own tests. Standing rule 4 says one grammar for one user-facing shape;
//! a second span encoding would be two.
//!
//! So this layer writes exactly that, by hand. The engine has no serde
//! (`op.rs`: a derive macro must not decide what anything looks like from
//! outside), and every other wire shape in this crate is written out the
//! same way.
//!
//! **One thing differs, and the shell already handles it.** A `Ref` in
//! the old ABI is a JSON number, because a `core/` id is a `u64`; here it
//! is 32 hex characters. `LivID`'s decoder was built in slice 4 to accept
//! both, and its encoder writes hex — so the editor round-trips through
//! these verbs with no Swift change at all.

use liv_engine::{Block, Marks, Span, TextSpan};
use serde_json::{json, Map, Value as J};

use crate::surfaces::parse_id;

/// Spans as the shell reads them.
pub fn to_json(spans: &[Span]) -> J {
    J::Array(spans.iter().map(one_out).collect())
}

fn one_out(s: &Span) -> J {
    match s {
        // An unmarked run stays the BARE STRING it has always been, so no
        // fingerprint moves on untouched text and an older decoder still
        // reads it.
        Span::Text(t) if t.marks.is_empty() => json!({ "Text": t.text }),
        Span::Text(t) => json!({ "Text": { "text": t.text, "marks": t.marks.0 } }),
        Span::Break(b) => json!({ "Break": block_out(b) }),
        Span::Ref(id) => json!({ "Ref": id.hex() }),
    }
}

fn block_out(b: &Block) -> J {
    match b {
        // serde's external tagging: a unit variant rides as a bare string,
        // a payload variant as a one-key object.
        Block::Body => json!("Body"),
        Block::Quote => json!("Quote"),
        Block::Rule => json!("Rule"),
        Block::Heading(n) => json!({ "Heading": n }),
        Block::Bullet { depth } => json!({ "Bullet": { "depth": depth } }),
        Block::Ordered { depth } => json!({ "Ordered": { "depth": depth } }),
        Block::Task { depth, done } => json!({ "Task": { "depth": depth, "done": done } }),
        Block::Code { lang } => json!({ "Code": { "lang": lang } }),
        Block::Callout { kind } => json!({ "Callout": { "kind": kind } }),
    }
}

/// And back. `None` when the payload is not an array of spans at all —
/// which is a caller bug, and the error channel says so rather than
/// saving half a document.
///
/// **A span this build does not understand is REFUSED, not dropped.** The
/// old codec kept an unknown block as `.other` and flattened it on save,
/// which is a decision about someone's writing that a wire decoder should
/// not be making. Here the save fails and the editor still holds the text.
pub fn from_json(raw: &str) -> Option<Vec<Span>> {
    let J::Array(items) = serde_json::from_str::<J>(raw).ok()? else { return None };
    items.iter().map(one_in).collect()
}

fn one_in(v: &J) -> Option<Span> {
    let o = v.as_object()?;
    if let Some(t) = o.get("Text") {
        return Some(match t {
            J::String(s) => Span::text(s.clone()),
            J::Object(m) => Span::Text(TextSpan {
                text: m.get("text")?.as_str()?.to_owned(),
                // A mark bit this build does not know is refused by the
                // encoder anyway (`op.rs` checks the reserved bits), so
                // catching it here makes the failure the caller's rather
                // than a decode error three layers down.
                marks: marks(m.get("marks"))?,
            }),
            _ => return None,
        });
    }
    if let Some(b) = o.get("Break") {
        return Some(Span::Break(block_in(b)?));
    }
    if let Some(r) = o.get("Ref") {
        return Some(Span::Ref(parse_id(r.as_str()?)?));
    }
    None
}

fn marks(v: Option<&J>) -> Option<Marks> {
    let n = match v {
        None | Some(J::Null) => 0,
        Some(x) => u8::try_from(x.as_u64()?).ok()?,
    };
    if n & Marks::RESERVED != 0 {
        return None;
    }
    Some(Marks(n))
}

fn block_in(v: &J) -> Option<Block> {
    if let J::String(s) = v {
        return Some(match s.as_str() {
            "Body" => Block::Body,
            "Quote" => Block::Quote,
            "Rule" => Block::Rule,
            _ => return None,
        });
    }
    let o: &Map<String, J> = v.as_object()?;
    if let Some(n) = o.get("Heading") {
        let n = u8::try_from(n.as_u64()?).ok()?;
        // The engine's decoder refuses anything outside 1–6, so refusing
        // it here means the caller hears about it instead of the box.
        return (1..=6).contains(&n).then_some(Block::Heading(n));
    }
    if let Some(b) = o.get("Bullet") {
        return Some(Block::Bullet { depth: depth(b)? });
    }
    if let Some(b) = o.get("Ordered") {
        return Some(Block::Ordered { depth: depth(b)? });
    }
    if let Some(b) = o.get("Task") {
        let m = b.as_object()?;
        return Some(Block::Task {
            depth: depth(b)?,
            done: m.get("done").and_then(J::as_bool).unwrap_or(false),
        });
    }
    if let Some(b) = o.get("Code") {
        // `null` and a missing key both mean no language — and `Some("")`
        // is a different document from `None`, so an empty string is kept
        // as an empty string rather than folded away.
        return Some(Block::Code {
            lang: b.as_object()?.get("lang").and_then(J::as_str).map(str::to_owned),
        });
    }
    if let Some(b) = o.get("Callout") {
        return Some(Block::Callout {
            kind: b.as_object()?.get("kind")?.as_str()?.to_owned(),
        });
    }
    None
}

fn depth(v: &J) -> Option<u8> {
    match v.as_object()?.get("depth") {
        None | Some(J::Null) => Some(0),
        Some(n) => u8::try_from(n.as_u64()?).ok(),
    }
}
