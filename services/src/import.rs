//! The import service (P15a): a bulk drop of links / files / markdown notes /
//! scraps becomes entities in ONE transaction, ONE undo (LB2). Binaries are
//! referenced, never copied (LB1); links and native content are ingested;
//! `external-id` dedupe makes re-import a literal no-op (LB3). AI classification
//! is quarantined to P16 — this service only writes what it is handed.

use std::collections::{HashMap, HashSet};

use liv_core::{
    props, Author, Cell, Command, DateTime, FileRef, Id, PersistError, RichText, Session, Span,
    Value,
};

use crate::content::find_type;
use crate::files::hash_file;
use crate::markdown::{parse_markdown, resolve_wikilinks};
use crate::{property_id, run, Constraint, Op, Query};

/// One thing to import. The shell parses a drop (OS files, tab urls, a
/// bookmarks.html, pasted text, a markdown vault) into these. The wire form is
/// internally tagged (`{"kind":"link","url":…}`) so the shell builds it plainly.
#[derive(serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum ImportItem {
    /// A url → a link entity (url + scraped title, #39). A provided title is
    /// never clobbered (LB8).
    Link { url: String, title: Option<String> },
    /// An OS file → a by-reference file entity (path + hash, bytes untouched).
    File { path: String },
    /// A markdown note → a native note entity: frontmatter keys become cells,
    /// the body parses to rich spans, `source_id` is the external-id.
    Note {
        frontmatter: Vec<(String, String)>,
        body: String,
        source_id: String,
    },
    /// Loose pasted text that is neither link nor file → a capture scrap.
    Scrap { text: String },
}

/// Reference cells stamped on every committed entity — the funnel's inherited
/// project/area/subject, as `(property, target)` pairs. The surface resolves
/// which property is "project"; the service stays agnostic.
#[derive(Default)]
pub struct ImportDefaults {
    pub stamps: Vec<(Id, Id)>,
}

/// Commit a batch. Returns the ids created, in order; deduped items are skipped
/// (not in the result). Everything rides ONE `session.commit`, so one undo
/// reverts the whole import.
pub fn commit_batch(
    session: &mut Session,
    items: &[ImportItem],
    created: DateTime,
    defaults: &ImportDefaults,
) -> Result<Vec<Id>, PersistError> {
    let note_type = find_type(session.store(), "note");
    let link_type = find_type(session.store(), "link");
    let url_prop = property_id(session.store(), "url");
    let file_prop = property_id(session.store(), "file");
    let format_prop = property_id(session.store(), "format");

    // Pass 1 — plan: dedupe, allocate ids, learn every new entity's name so
    // forward `[[wikilinks]]` inside the batch resolve.
    struct Planned<'a> {
        id: Id,
        item: &'a ImportItem,
        /// A File's hash, computed once in pass 1 and reused in pass 2 (never
        /// re-read from disk — a source removed between passes must not panic).
        hash: Option<[u8; 32]>,
    }
    let mut planned: Vec<Planned> = Vec::new();
    let mut name_map: HashMap<String, Id> = HashMap::new();
    let mut seen_ext: HashSet<String> = HashSet::new();
    let mut seen_hash: HashSet<[u8; 32]> = HashSet::new();

    for item in items {
        // Dedupe (LB3): links/notes by external-id, files by their referenced
        // hash (so a file already in the box however it arrived is skipped) —
        // BOTH within this batch (the seen sets) and against the store.
        let mut item_hash = None;
        match item {
            ImportItem::Link { url, .. } => {
                if seen_ext.contains(url) || external_id_exists(session.store(), url) {
                    continue;
                }
                seen_ext.insert(url.clone());
            }
            ImportItem::Note { source_id, .. } => {
                if seen_ext.contains(source_id) || external_id_exists(session.store(), source_id) {
                    continue;
                }
                seen_ext.insert(source_id.clone());
            }
            ImportItem::File { path } => {
                let Ok(hash) = hash_file(path) else { continue };
                if seen_hash.contains(&hash) {
                    continue;
                }
                if let Some(fp) = file_prop {
                    if file_hash_exists(session.store(), fp, hash) {
                        continue;
                    }
                }
                seen_hash.insert(hash);
                item_hash = Some(hash);
            }
            ImportItem::Scrap { .. } => {} // scraps never dedupe (no identity)
        }

        let id = session.allocate_id();
        if let Some(name) = item_name(item) {
            name_map.entry(name.to_lowercase()).or_insert(id);
        }
        planned.push(Planned { id, item, hash: item_hash });
    }

    // Pass 2 — build every command, then commit once.
    let mut commands: Vec<Command> = Vec::new();
    let mut new_props: HashMap<String, Id> = HashMap::new();
    let mut result: Vec<Id> = Vec::new();

    for Planned { id, item, hash } in &planned {
        let id = *id;
        commands.push(Command::Create { entity: id });

        match item {
            ImportItem::Link { url, title } => {
                if let Some(t) = link_type {
                    add(&mut commands, id, props::TYPE, Value::Reference(t));
                }
                let name = title.clone().unwrap_or_else(|| url.clone());
                add(&mut commands, id, props::NAME, Value::text(name));
                if let Some(up) = url_prop {
                    add(&mut commands, id, up, Value::text(url.clone()));
                }
                add(&mut commands, id, props::EXTERNAL_ID, Value::text(url.clone()));
            }
            ImportItem::File { path } => {
                // The hash was computed in pass 1 (in memory) — never re-read
                // the source, which may have vanished between the passes.
                let hash = hash.expect("a File is planned with its hash");
                let p = std::path::Path::new(path);
                let filename = p
                    .file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or(path)
                    .to_string();
                add(&mut commands, id, props::NAME, Value::text(filename));
                if let Some(fp) = file_prop {
                    add(
                        &mut commands,
                        id,
                        fp,
                        Value::File(FileRef { path: path.clone(), hash }),
                    );
                }
                let ext = p
                    .extension()
                    .and_then(|s| s.to_str())
                    .unwrap_or("")
                    .to_lowercase();
                if !ext.is_empty() {
                    if let Some(fmt) = format_prop {
                        add(&mut commands, id, fmt, Value::text(ext));
                    }
                }
            }
            ImportItem::Note { frontmatter, body, source_id } => {
                if let Some(t) = note_type {
                    add(&mut commands, id, props::TYPE, Value::Reference(t));
                }
                add(&mut commands, id, props::NAME, Value::text(note_name(item)));
                add(&mut commands, id, props::EXTERNAL_ID, Value::text(source_id.clone()));

                let mut content = parse_markdown(body);
                resolve_wikilinks(&mut content, &|name| {
                    name_map
                        .get(&name.to_lowercase())
                        .copied()
                        .or_else(|| entity_by_name(session.store(), name))
                });
                if !content.spans.is_empty() {
                    add(&mut commands, id, props::CONTENT, Value::RichText(content));
                }

                // Frontmatter keys → cells; "title" already became the name.
                for (key, value) in frontmatter {
                    if key.eq_ignore_ascii_case("title") {
                        continue;
                    }
                    if let Some((prop, cell)) =
                        frontmatter_cell(session, &mut commands, &mut new_props, key, value)
                    {
                        add(&mut commands, id, prop, cell);
                    }
                }
            }
            ImportItem::Scrap { text } => {
                add(
                    &mut commands,
                    id,
                    props::CONTENT,
                    Value::RichText(RichText { spans: vec![Span::text(text.clone())] }),
                );
            }
        }

        add(&mut commands, id, props::CREATED, Value::DateTime(created));
        for (prop, target) in &defaults.stamps {
            add(&mut commands, id, *prop, Value::Reference(*target));
        }
        result.push(id);
    }

    if !commands.is_empty() {
        session.commit(commands, "import", Author::User)?;
    }
    Ok(result)
}

fn add(commands: &mut Vec<Command>, entity: Id, property: Id, value: Value) {
    commands.push(Command::AddCell { entity, cell: Cell { property, value } });
}

/// The display name a batch item contributes to `[[wikilink]]` resolution.
fn item_name(item: &ImportItem) -> Option<String> {
    match item {
        ImportItem::Link { url, title } => Some(title.clone().unwrap_or_else(|| url.clone())),
        ImportItem::File { path } => std::path::Path::new(path)
            .file_name()
            .and_then(|s| s.to_str())
            .map(str::to_string),
        ImportItem::Note { .. } => Some(note_name(item)),
        ImportItem::Scrap { .. } => None,
    }
}

/// A note's name: the frontmatter `title`, else the source file's stem.
fn note_name(item: &ImportItem) -> String {
    if let ImportItem::Note { frontmatter, source_id, .. } = item {
        if let Some((_, title)) = frontmatter.iter().find(|(k, _)| k.eq_ignore_ascii_case("title")) {
            return title.clone();
        }
        return std::path::Path::new(source_id)
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or(source_id)
            .to_string();
    }
    String::new()
}

/// Resolve a frontmatter `key: value` to the (property, cell) to stamp, or
/// `None` to skip it. Three cases (the frontmatter-keys-become-cells rule,
/// hardened after the P15a review):
///   - an EXISTING user property → the value parsed by its declared kind, so a
///     `status: doing` becomes a `Select`, not a raw `Text` under a select
///     property; an unparseable value is skipped rather than stored malformed.
///   - a RESERVED core property (id < FIRST_USER_ID: name/type/created/…) →
///     skipped, so frontmatter can never overwrite plumbing with a wrong type.
///   - a NEW key → a text property minted on demand + a text value.
fn frontmatter_cell(
    session: &mut Session,
    commands: &mut Vec<Command>,
    new_props: &mut HashMap<String, Id>,
    key: &str,
    raw: &str,
) -> Option<(Id, Value)> {
    if let Some(prop) = property_id(session.store(), key) {
        if prop < props::FIRST_USER_ID {
            return None; // never stamp under core plumbing
        }
        let kind = match session.store().get(prop).and_then(|p| p.get(props::VALUE_KIND)) {
            Some(Value::Text(k)) => k.clone(),
            _ => return None,
        };
        let value = crate::content::parse_value(session.store(), prop, &kind, raw).ok()?;
        return Some((prop, value));
    }
    if let Some(&prop) = new_props.get(key) {
        return Some((prop, Value::text(raw)));
    }
    let id = session.allocate_id();
    commands.push(Command::Create { entity: id });
    add(commands, id, props::NAME, Value::text(key.to_string()));
    add(commands, id, props::VALUE_KIND, Value::text("text"));
    add(commands, id, props::WORKING, Value::Bool(true));
    new_props.insert(key.to_string(), id);
    Some((id, Value::text(raw)))
}

fn external_id_exists(store: &liv_core::Store, ext: &str) -> bool {
    !run(
        store,
        &Query {
            constraints: vec![Constraint {
                property: props::EXTERNAL_ID,
                op: Op::Equals(Value::text(ext)),
            }],
            include_working: true,
            ..Query::default()
        },
    )
    .is_empty()
}

fn file_hash_exists(store: &liv_core::Store, file_prop: Id, hash: [u8; 32]) -> bool {
    // FileRef equality is hash-only, so the path here is irrelevant.
    !run(
        store,
        &Query {
            constraints: vec![Constraint {
                property: file_prop,
                op: Op::Equals(Value::File(FileRef { path: String::new(), hash })),
            }],
            include_working: true,
            ..Query::default()
        },
    )
    .is_empty()
}

fn entity_by_name(store: &liv_core::Store, name: &str) -> Option<Id> {
    run(
        store,
        &Query {
            constraints: vec![Constraint {
                property: props::NAME,
                op: Op::Equals(Value::text(name)),
            }],
            ..Query::default()
        },
    )
    .first()
    .copied()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::seed_if_fresh;

    fn session(name: &str) -> Session {
        let dir = std::env::temp_dir().join(format!("liv_import_{name}"));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let mut s = Session::open(dir.join("box.log")).unwrap();
        seed_if_fresh(&mut s).unwrap();
        s
    }

    fn now() -> DateTime {
        DateTime::date(2026, 7, 12)
    }

    fn tempfile(name: &str, bytes: &[u8]) -> String {
        let dir = std::env::temp_dir().join("liv_import_files");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(name);
        std::fs::write(&path, bytes).unwrap();
        path.to_str().unwrap().to_string()
    }

    fn ext_count(session: &Session) -> usize {
        run(
            session.store(),
            &Query {
                constraints: vec![Constraint { property: props::EXTERNAL_ID, op: Op::Exists }],
                include_working: true,
                ..Query::default()
            },
        )
        .len()
    }

    #[test]
    fn one_transaction_one_undo() {
        let mut s = session("one_undo");
        let items = vec![
            ImportItem::Link { url: "https://a.example".into(), title: None },
            ImportItem::Link { url: "https://b.example".into(), title: None },
            ImportItem::Link { url: "https://c.example".into(), title: None },
        ];
        let ids = commit_batch(&mut s, &items, now(), &ImportDefaults::default()).unwrap();
        assert_eq!(ids.len(), 3);
        assert_eq!(ext_count(&s), 3);
        // ONE undo reverts ALL three (they rode one transaction).
        s.undo(Author::User).unwrap();
        assert_eq!(ext_count(&s), 0);
    }

    #[test]
    fn re_import_is_a_no_op() {
        let mut s = session("dedupe");
        let items = vec![
            ImportItem::Link { url: "https://a.example".into(), title: None },
            ImportItem::Link { url: "https://b.example".into(), title: None },
        ];
        commit_batch(&mut s, &items, now(), &ImportDefaults::default()).unwrap();
        assert_eq!(ext_count(&s), 2);
        // Same urls again → zero new entities.
        let again = commit_batch(&mut s, &items, now(), &ImportDefaults::default()).unwrap();
        assert!(again.is_empty());
        assert_eq!(ext_count(&s), 2);
    }

    #[test]
    fn file_is_referenced_not_copied() {
        let mut s = session("fileref");
        let path = tempfile("report.pdf", b"pretend pdf bytes");
        let before = std::fs::metadata(&path).unwrap().len();
        let ids = commit_batch(
            &mut s,
            &[ImportItem::File { path: path.clone() }],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        assert_eq!(ids.len(), 1);
        let entity = s.store().get(ids[0]).unwrap();
        let file_prop = property_id(s.store(), "file").unwrap();
        match entity.get(file_prop) {
            Some(Value::File(fr)) => assert_eq!(fr.path, path),
            other => panic!("no file cell: {other:?}"),
        }
        // The source bytes are untouched (never moved/copied — LB1).
        assert_eq!(std::fs::metadata(&path).unwrap().len(), before);
        assert_eq!(std::fs::read(&path).unwrap(), b"pretend pdf bytes");
    }

    #[test]
    fn link_title_survives() {
        let mut s = session("title");
        let ids = commit_batch(
            &mut s,
            &[ImportItem::Link {
                url: "https://x.example/page".into(),
                title: Some("The Real Title".into()),
            }],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        let name = s.store().get(ids[0]).unwrap().get(props::NAME).cloned();
        assert_eq!(name, Some(Value::text("The Real Title")));
    }

    #[test]
    fn note_gets_frontmatter_cells_and_rich_body() {
        let mut s = session("note");
        let ids = commit_batch(
            &mut s,
            &[ImportItem::Note {
                frontmatter: vec![
                    ("title".into(), "My Note".into()),
                    ("status".into(), "doing".into()),
                ],
                body: "# Heading\n\nHello **bold**".into(),
                source_id: "/vault/my-note.md".into(),
            }],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        let e = s.store().get(ids[0]).unwrap();
        assert_eq!(e.get(props::NAME).cloned(), Some(Value::text("My Note")));
        assert_eq!(e.get(props::EXTERNAL_ID).cloned(), Some(Value::text("/vault/my-note.md")));
        // "status" is a seeded SELECT property — the value is parsed by its
        // declared kind (resolved to the "doing" option), not stored as raw
        // Text under a select property (the P15a review's fidelity fix).
        let status_prop = property_id(s.store(), "status").unwrap();
        let doing = crate::content::find_option(s.store(), status_prop, "doing").unwrap();
        assert_eq!(e.get(status_prop).cloned(), Some(Value::Select(doing)));
        // The body parsed to rich spans (a heading break is present).
        match e.get(props::CONTENT) {
            Some(Value::RichText(rt)) => {
                assert!(rt.spans.iter().any(|sp| matches!(sp, Span::Break(liv_core::Block::Heading(1)))));
            }
            other => panic!("no rich content: {other:?}"),
        }
    }

    #[test]
    fn defaults_stamp_every_entity_and_empty_stamps_nothing() {
        let mut s = session("defaults");
        // A target entity + the `related` reference property to stamp under.
        let related = property_id(s.store(), "related").unwrap();
        let target = commit_batch(
            &mut s,
            &[ImportItem::Scrap { text: "target".into() }],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap()[0];

        let with = ImportDefaults { stamps: vec![(related, target)] };
        let ids = commit_batch(
            &mut s,
            &[
                ImportItem::Link { url: "https://d.example".into(), title: None },
                ImportItem::Scrap { text: "note".into() },
            ],
            now(),
            &with,
        )
        .unwrap();
        for id in &ids {
            let e = s.store().get(*id).unwrap();
            assert!(e.all(related).any(|v| *v == Value::Reference(target)), "stamp missing on {id}");
        }
        // The earlier default-less scrap carries no such cell.
        assert!(s.store().get(target).unwrap().all(related).next().is_none());
    }

    #[test]
    fn duplicate_files_in_one_batch_import_once() {
        let mut s = session("filedup");
        let path = tempfile("dup.txt", b"same bytes both times");
        let ids = commit_batch(
            &mut s,
            &[
                ImportItem::File { path: path.clone() },
                ImportItem::File { path: path.clone() },
            ],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        assert_eq!(ids.len(), 1, "identical files in one drop must import once");
    }

    #[test]
    fn frontmatter_never_overwrites_core_plumbing() {
        let mut s = session("fmcore");
        let ids = commit_batch(
            &mut s,
            &[ImportItem::Note {
                frontmatter: vec![
                    ("title".into(), "Doc".into()),
                    ("type".into(), "article".into()),      // collides with props::TYPE
                    ("created".into(), "not a date".into()), // collides with props::CREATED
                ],
                body: "body".into(),
                source_id: "/v/doc.md".into(),
            }],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        let e = s.store().get(ids[0]).unwrap();
        // type stayed the note-type reference (a Text "article" was NOT stamped).
        let note_type = crate::content::find_type(s.store(), "note").unwrap();
        assert_eq!(e.get(props::TYPE).cloned(), Some(Value::Reference(note_type)));
        assert!(e.all(props::TYPE).all(|v| matches!(v, Value::Reference(_))), "a text crept under type");
        // created stayed the real DateTime (a Text "not a date" was NOT stamped).
        assert!(matches!(e.get(props::CREATED), Some(Value::DateTime(_))));
        assert!(e.all(props::CREATED).all(|v| matches!(v, Value::DateTime(_))));
    }

    #[test]
    fn wikilinks_resolve_across_the_batch() {
        let mut s = session("wiki");
        let ids = commit_batch(
            &mut s,
            &[
                ImportItem::Note {
                    frontmatter: vec![("title".into(), "Alpha".into())],
                    body: "points to [[Beta]]".into(),
                    source_id: "/v/alpha.md".into(),
                },
                ImportItem::Note {
                    frontmatter: vec![("title".into(), "Beta".into())],
                    body: "the target".into(),
                    source_id: "/v/beta.md".into(),
                },
            ],
            now(),
            &ImportDefaults::default(),
        )
        .unwrap();
        // Alpha's body ref resolves to Beta's id (a forward ref within the batch).
        let beta = ids[1];
        let alpha = s.store().get(ids[0]).unwrap();
        match alpha.get(props::CONTENT) {
            Some(Value::RichText(rt)) => {
                assert!(rt.spans.iter().any(|sp| *sp == Span::Ref(beta)), "no ref to Beta: {:?}", rt.spans);
            }
            other => panic!("no content: {other:?}"),
        }
    }
}
