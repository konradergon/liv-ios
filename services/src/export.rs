//! The export service (P15c, #42/LB5): a resolved set of entity ids → a
//! metadata-grouped folder of files written OUTSIDE the box. Native entities
//! render to markdown (content spans → md, cells → a frontmatter block); file
//! entities copy their referenced bytes. COPY-ONLY — a projection, never a
//! mirror: the log records nothing and keeps no back-reference. `export_plan`
//! is pure (computes the bp14-a30 tree preview); `export_write` does the IO.

use std::collections::HashSet;
use std::io;
use std::path::{Path, PathBuf};

use lotus_core::{props, Id, Store, Value};

use crate::markdown::render_markdown;

/// What one output file is: a byte-copy of a referenced file, or rendered
/// markdown for a native entity.
pub enum ExportKind {
    CopyFrom(String),
    Markdown(String),
}

pub struct ExportFile {
    /// Path relative to the destination root (group dirs + filename).
    pub rel_path: PathBuf,
    pub kind: ExportKind,
}

/// The computed projection — exactly what `export_write` will land (the a30
/// preview reads `rel_path`s without any IO).
pub struct ExportTree {
    pub files: Vec<ExportFile>,
}

/// Plan the export: group each entity by up to TWO properties (a29 — a third
/// level is clamped away), pick its filename, and pre-render native content.
/// Pure and read-only.
pub fn export_plan(store: &Store, ids: &[Id], group_by: &[Id]) -> ExportTree {
    let mut files = Vec::new();
    let mut used: HashSet<PathBuf> = HashSet::new();

    for &id in ids {
        let Some(entity) = store.get(id) else { continue };

        // Group path — the first ≤2 group properties, each rendered + sanitized.
        let mut dir = PathBuf::new();
        for &prop in group_by.iter().take(2) {
            let seg = match entity.get(prop) {
                Some(v) => sanitize(&lotus_views::display(store, v)),
                None => "ungrouped".to_string(),
            };
            dir.push(seg);
        }

        // A file entity copies its bytes as themselves; anything else is a
        // native entity rendered to markdown.
        let name = entity
            .get(props::NAME)
            .map(|v| lotus_views::display(store, v))
            .unwrap_or_default();
        let (stem, ext, kind) = match file_ref(entity) {
            Some(path) => {
                let p = Path::new(&path);
                let filename = p.file_name().and_then(|s| s.to_str()).unwrap_or(&name);
                let stem = Path::new(filename)
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or(filename)
                    .to_string();
                let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("").to_string();
                (stem, ext, ExportKind::CopyFrom(path))
            }
            None => (name.clone(), "md".to_string(), ExportKind::Markdown(render_entity(store, id))),
        };

        let rel = unique(&mut used, &dir, &sanitize_stem(&stem, id), &ext);
        files.push(ExportFile { rel_path: rel, kind });
    }

    ExportTree { files }
}

/// Write the plan under `dest`. Copy-only; reads originals, mutates nothing in
/// the store. Returns the count written. Per-file errors abort with the io error
/// (never a silent partial success).
pub fn export_write(store: &Store, plan: &ExportTree, dest: &Path) -> io::Result<u64> {
    let _ = store; // read-only; the plan already carries rendered content
    let mut written = 0u64;
    for file in &plan.files {
        let full = dest.join(&file.rel_path);
        if let Some(parent) = full.parent() {
            std::fs::create_dir_all(parent)?;
        }
        match &file.kind {
            ExportKind::CopyFrom(src) => {
                std::fs::copy(src, &full)?;
            }
            ExportKind::Markdown(text) => {
                std::fs::write(&full, text)?;
            }
        }
        written += 1;
    }
    Ok(written)
}

/// A native entity → markdown: a `---` frontmatter block (title + its other
/// non-plumbing cells) then the content body rendered from spans.
fn render_entity(store: &Store, id: Id) -> String {
    let Some(entity) = store.get(id) else { return String::new() };

    let mut fm: Vec<(String, String)> = Vec::new();
    // title first, from NAME.
    if let Some(v) = entity.get(props::NAME) {
        fm.push(("title".to_string(), lotus_views::display(store, v)));
    }
    // Every other cell except the body + backstage plumbing, grouped by property.
    let mut seen: HashSet<Id> = HashSet::new();
    for cell in &entity.cells {
        let prop = cell.property;
        if prop == props::NAME || prop == props::CONTENT || prop == props::WORKING {
            continue;
        }
        if !seen.insert(prop) {
            continue; // handled the whole (possibly multi-valued) property already
        }
        let values: Vec<String> =
            entity.all(prop).map(|v| lotus_views::display(store, v)).collect();
        if values.is_empty() {
            continue;
        }
        let key = prop_name(store, prop);
        let value = if values.len() == 1 {
            values[0].clone()
        } else {
            format!("[{}]", values.join(", "))
        };
        fm.push((key, value));
    }

    let mut out = String::new();
    if !fm.is_empty() {
        out.push_str("---\n");
        for (k, v) in &fm {
            out.push_str(&format!("{k}: {v}\n"));
        }
        out.push_str("---\n\n");
    }
    if let Some(Value::RichText(rich)) = entity.get(props::CONTENT) {
        let body = render_markdown(rich, &|target| {
            store
                .get(target)
                .and_then(|e| e.get(props::NAME))
                .map(|v| lotus_views::display(store, v))
                .unwrap_or_else(|| format!("#{target}"))
        });
        out.push_str(&body);
    }
    out
}

/// The referenced file path of a file entity (a `File`-valued cell), if any.
fn file_ref(entity: &lotus_core::Entity) -> Option<String> {
    entity.cells.iter().find_map(|c| match &c.value {
        Value::File(fr) => Some(fr.path.clone()),
        _ => None,
    })
}

/// A property's export key: NAME reads as "title" for frontmatter; otherwise
/// its own name, else a stable fallback.
fn prop_name(store: &Store, prop: Id) -> String {
    if prop == props::NAME {
        return "title".to_string();
    }
    match store.get(prop).and_then(|p| p.get(props::NAME)) {
        Some(Value::Text(name)) => name.clone(),
        _ => format!("prop{prop}"),
    }
}

/// Filesystem-safe path segment: strip separators and control chars.
fn sanitize(seg: &str) -> String {
    let cleaned: String = seg
        .chars()
        .map(|c| if c == '/' || c == '\\' || c == ':' || c.is_control() { '-' } else { c })
        .collect();
    let trimmed = cleaned.trim().trim_matches('.').trim();
    if trimmed.is_empty() {
        "untitled".to_string()
    } else {
        trimmed.to_string()
    }
}

/// A filename stem falls back to the entity id when it sanitizes to nothing, so
/// an unnamed entity still gets a distinct file.
fn sanitize_stem(stem: &str, id: Id) -> String {
    let s = sanitize(stem);
    if s == "untitled" {
        format!("untitled-{id}")
    } else {
        s
    }
}

/// A path unique within this export — names are not unique in lotus, so a
/// collision disambiguates with " (2)", " (3)", … before the extension.
fn unique(used: &mut HashSet<PathBuf>, dir: &Path, stem: &str, ext: &str) -> PathBuf {
    let build = |stem: &str| -> PathBuf {
        let filename = if ext.is_empty() {
            stem.to_string()
        } else {
            format!("{stem}.{ext}")
        };
        dir.join(filename)
    };
    let mut candidate = build(stem);
    let mut n = 2;
    while used.contains(&candidate) {
        candidate = build(&format!("{stem} ({n})"));
        n += 1;
    }
    used.insert(candidate.clone());
    candidate
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::import::{commit_batch, ImportDefaults, ImportItem};
    use crate::{property_id, seed_if_fresh};
    use lotus_core::{DateTime, Session};

    fn session(name: &str) -> Session {
        let dir = std::env::temp_dir().join(format!("lotus_export_{name}"));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let mut s = Session::open(dir.join("box.log")).unwrap();
        seed_if_fresh(&mut s).unwrap();
        s
    }

    fn dest(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("lotus_export_out_{name}"));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    fn now() -> DateTime {
        DateTime::date(2026, 7, 12)
    }

    #[test]
    fn writes_a_file_per_entity_and_leaves_the_store_untouched() {
        let mut s = session("count");
        let ids = commit_batch(
            &mut s,
            &[
                ImportItem::Note { frontmatter: vec![("title".into(), "A".into())], body: "one".into(), source_id: "/a".into() },
                ImportItem::Note { frontmatter: vec![("title".into(), "B".into())], body: "two".into(), source_id: "/b".into() },
            ],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        let before = s.store().entities().count();
        let plan = export_plan(s.store(), &ids, &[]);
        let d = dest("count");
        let n = export_write(s.store(), &plan, &d).unwrap();
        assert_eq!(n, 2);
        assert!(d.join("A.md").exists());
        assert!(d.join("B.md").exists());
        // Read-only: the store gained nothing.
        assert_eq!(s.store().entities().count(), before);
    }

    #[test]
    fn groups_by_two_levels_and_clamps_a_third() {
        let mut s = session("group");
        // Two notes with a `status` (seeded select) so we can group on it.
        let ids = commit_batch(
            &mut s,
            &[ImportItem::Note {
                frontmatter: vec![("title".into(), "Doc".into()), ("status".into(), "doing".into())],
                body: "b".into(),
                source_id: "/g".into(),
            }],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        let status = property_id(s.store(), "status").unwrap();
        let ty = props::TYPE;
        // Three group props → only the first two nest.
        let plan = export_plan(s.store(), &ids, &[ty, status, status]);
        let rel = &plan.files[0].rel_path;
        assert_eq!(rel.components().count(), 3, "two group dirs + filename: {rel:?}");
    }

    #[test]
    fn file_entity_bytes_are_copied_verbatim_and_source_untouched() {
        let mut s = session("filecopy");
        let src_dir = std::env::temp_dir().join("lotus_export_src");
        std::fs::create_dir_all(&src_dir).unwrap();
        let src = src_dir.join("report.pdf");
        std::fs::write(&src, b"the real bytes").unwrap();
        let ids = commit_batch(
            &mut s,
            &[ImportItem::File { path: src.to_str().unwrap().to_string() }],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        let plan = export_plan(s.store(), &ids, &[]);
        let d = dest("filecopy");
        export_write(s.store(), &plan, &d).unwrap();
        let out = d.join("report.pdf");
        assert_eq!(std::fs::read(&out).unwrap(), b"the real bytes");
        // Source untouched (copy, not move — LB5).
        assert_eq!(std::fs::read(&src).unwrap(), b"the real bytes");
    }

    #[test]
    fn native_note_exports_frontmatter_and_a_round_trippable_body() {
        let mut s = session("md");
        let ids = commit_batch(
            &mut s,
            &[ImportItem::Note {
                frontmatter: vec![("title".into(), "My Note".into())],
                body: "# Heading\n\nHello **bold**".into(),
                source_id: "/m".into(),
            }],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        let md = render_entity(s.store(), ids[0]);
        assert!(md.starts_with("---\n"), "no frontmatter block: {md}");
        assert!(md.contains("title: My Note"));
        // The body parses back to a heading + a bold run.
        let after = md.split("---\n\n").nth(1).unwrap_or(&md);
        let rt = crate::markdown::parse_markdown(after);
        assert!(rt.spans.iter().any(|sp| matches!(sp, lotus_core::Span::Break(lotus_core::Block::Heading(1)))));
    }

    #[test]
    fn colliding_names_disambiguate() {
        let mut s = session("collide");
        // Two notes with the SAME title (names are not unique in lotus).
        let ids = commit_batch(
            &mut s,
            &[
                ImportItem::Note { frontmatter: vec![("title".into(), "Same".into())], body: "x".into(), source_id: "/1".into() },
                ImportItem::Note { frontmatter: vec![("title".into(), "Same".into())], body: "y".into(), source_id: "/2".into() },
            ],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        let plan = export_plan(s.store(), &ids, &[]);
        let d = dest("collide");
        let n = export_write(s.store(), &plan, &d).unwrap();
        assert_eq!(n, 2);
        assert!(d.join("Same.md").exists());
        assert!(d.join("Same (2).md").exists(), "collision not disambiguated");
    }
}
