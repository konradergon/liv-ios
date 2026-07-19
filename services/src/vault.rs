//! P20j.1 — the files projection's PURE layer (design/p20j-files-projection.md
//! §2, §5). The vault slugger (the pack's breadcrumb is the spec:
//! `Steven Åkesson` → `library/contacts/steven-akesson.md`), deterministic
//! case-insensitive collision suffixing, pool classification, and the
//! H1-is-title vault rendering (no `title:` frontmatter — the H1 IS the
//! title; export.rs keeps its `title:` form for hand-offs). No IO lives
//! here: `expected_files` is a pure function of the store, which is what
//! makes the 20j.2 materializer's echo suppressor content-addressed and the
//! crash matrix testable.

use crate::markdown::{parse_markdown, render_markdown, split_frontmatter};
use crate::property_id;
use lotus_core::*;
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VaultClass {
    Markdown,
    /// The file is truth for BYTES only — cells stay box-side; the
    /// materializer copies from the librarian's source.
    Binary,
}

#[derive(Debug, Clone)]
pub struct VaultFile {
    pub id: Id,
    /// Vault-relative, always forward slashes: `library/<pool>/<slug>.md`.
    pub rel_path: String,
    pub class: VaultClass,
    /// Rendered markdown for `Markdown`; None for `Binary`.
    pub content: Option<String>,
}

// ---- the slugger ----

/// ASCII-fold the Latin diacritics the pack's own names carry. Anything
/// that doesn't fold to ASCII drops (never percent-encoding, never a
/// mojibake filename); an all-dropped name falls back to `untitled-<id>`.
fn fold(c: char) -> Option<&'static str> {
    Some(match c {
        'å' | 'à' | 'á' | 'â' | 'ã' | 'ā' | 'ă' => "a",
        'ä' | 'æ' => "a",
        'ç' | 'ć' | 'č' => "c",
        'é' | 'è' | 'ê' | 'ë' | 'ē' | 'ė' => "e",
        'í' | 'ì' | 'î' | 'ï' => "i",
        'ñ' | 'ń' => "n",
        'ö' | 'ø' | 'ó' | 'ò' | 'ô' | 'õ' | 'ő' => "o",
        'ü' | 'ú' | 'ù' | 'û' | 'ű' => "u",
        'ý' | 'ÿ' => "y",
        'ß' => "ss",
        'ż' | 'ź' | 'ž' => "z",
        'ł' => "l",
        'ś' | 'š' => "s",
        'đ' => "d",
        'þ' => "th",
        _ => return None,
    })
}

/// Stems Windows refuses (the port is coming) — suffixed, never emitted bare.
const RESERVED: &[&str] = &[
    "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
    "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
];

pub fn vault_slug(name: &str, id: Id) -> String {
    let mut out = String::new();
    let mut last_hyphen = true; // suppress leading hyphens
    for c in name.to_lowercase().chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c);
            last_hyphen = false;
        } else if let Some(folded) = fold(c) {
            out.push_str(folded);
            last_hyphen = false;
        } else if !last_hyphen {
            // Every separator/unknown collapses into ONE hyphen.
            out.push('-');
            last_hyphen = true;
        }
    }
    while out.ends_with('-') {
        out.pop();
    }
    // The 200-byte clamp, on a char boundary (ASCII here by construction).
    if out.len() > 200 {
        out.truncate(200);
        while out.ends_with('-') {
            out.pop();
        }
    }
    if out.is_empty() {
        return format!("untitled-{id}");
    }
    if RESERVED.contains(&out.as_str()) {
        return format!("{out}-file");
    }
    out
}

// ---- pool classification (design §2; a pool is a saved filter — the
// folder is only the LANDING spot) ----

fn type_name(store: &Store, entity: &Entity) -> Option<String> {
    match entity.get(props::TYPE) {
        Some(Value::Reference(target)) => match store.get(*target)?.get(props::NAME) {
            Some(Value::Text(name)) => Some(name.clone()),
            _ => None,
        },
        _ => None,
    }
}

fn binary_pool(title: &str) -> Option<&'static str> {
    let ext = title.rsplit('.').next().unwrap_or("").to_lowercase();
    match ext.as_str() {
        "doc" | "docx" | "rtf" | "pages" => Some("word"),
        "xls" | "xlsx" | "csv" | "numbers" => Some("sheets"),
        "pdf" => Some("pdf"),
        "png" | "jpg" | "jpeg" | "gif" | "heic" | "webp" => Some("images"),
        "canvas" => Some("canvas"),
        // Unknown binaries stay box-only v0 (recorded — the pack draws no
        // catch-all pool).
        _ => None,
    }
}

/// Which landing pool an entity projects into — None = box-only (WORKING
/// plumbing, workspaces, unrouted scraps, messages v0, unknown binaries).
pub fn pool_of(store: &Store, entity: &Entity) -> Option<&'static str> {
    if entity.trashed || entity.has(props::WORKING, &Value::Bool(true)) {
        return None;
    }
    // A daily note beats its `note` type — it has its own landing folder.
    if let Some(daily) = property_id(store, "daily-note") {
        if entity.get(daily).is_some() {
            return Some("daily");
        }
    }
    if entity.cells.iter().any(|c| matches!(c.value, Value::File(_))) {
        let title = match entity.get(props::NAME) {
            Some(Value::Text(name)) => name.clone(),
            _ => String::new(),
        };
        return binary_pool(&title);
    }
    match type_name(store, entity)?.as_str() {
        "note" => Some("notes"),
        "list" => Some("notes"),
        "person" | "contact" => Some("contacts"),
        "event" => Some("events"),
        "task" => Some("tasks"),
        "link" => Some("links"),
        // messages, ious, workspaces, habits, … : box-only v0 (recorded).
        _ => None,
    }
}

// ---- the H1-is-title vault rendering ----

fn fm_escape(raw: &str) -> String {
    raw.replace('\n', " ").replace('\r', " ")
}

/// Render one entity as its vault .md: frontmatter (every non-plumbing
/// cell; NO `title:` — the H1 is the title) + `# <name>` + the body.
pub fn render_vault_entity(store: &Store, id: Id) -> Option<String> {
    let entity = store.get(id)?;
    let name = match entity.get(props::NAME) {
        Some(Value::Text(name)) => name.clone(),
        _ => String::new(),
    };

    let mut fm: Vec<(String, String)> = Vec::new();
    let mut seen: HashSet<Id> = HashSet::new();
    for cell in &entity.cells {
        let prop = cell.property;
        if prop == props::NAME || prop == props::CONTENT || prop == props::WORKING
            || prop == props::TYPE
        {
            continue;
        }
        if !seen.insert(prop) {
            continue;
        }
        let key = match store.get(prop).and_then(|p| p.get(props::NAME)) {
            Some(Value::Text(n)) => n.clone(),
            _ => format!("p{prop}"),
        };
        for value in entity.all(prop) {
            fm.push((key.clone(), lotus_views::display(store, value)));
        }
    }
    if let Some(kind) = type_name(store, entity) {
        fm.insert(0, ("type".into(), kind));
    }

    let mut out = String::new();
    if !fm.is_empty() {
        out.push_str("---\n");
        for (k, v) in &fm {
            out.push_str(&format!("{}: {}\n", fm_escape(k), fm_escape(v)));
        }
        out.push_str("---\n\n");
    }
    if !name.is_empty() {
        out.push_str(&format!("# {name}\n\n"));
    }
    match entity.get(props::CONTENT) {
        Some(Value::RichText(rich)) => {
            let body = render_markdown(rich, &|target| {
                store
                    .get(target)
                    .and_then(|e| e.get(props::NAME))
                    .map(|v| lotus_views::display(store, v))
                    .unwrap_or_else(|| format!("#{target}"))
            });
            out.push_str(&body);
        }
        Some(Value::Text(text)) => out.push_str(text),
        _ => {}
    }
    Some(out)
}

pub struct ParsedVaultNote {
    /// From the first H1 — the title lives in the flow, never frontmatter.
    pub name: Option<String>,
    pub frontmatter: Vec<(String, String)>,
    pub body: RichText,
}

/// Parse a vault .md back: frontmatter block, the H1-as-name, the body.
pub fn parse_vault_note(raw: &str) -> ParsedVaultNote {
    let (frontmatter, body_raw) = split_frontmatter(raw);
    let mut name = None;
    let mut rest = body_raw.as_str();
    for line in body_raw.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some(title) = trimmed.strip_prefix("# ") {
            name = Some(title.trim().to_string());
            let at = body_raw.find(line).unwrap_or(0) + line.len();
            rest = body_raw[at..].trim_start_matches('\n');
        }
        break;
    }
    ParsedVaultNote { name, frontmatter, body: parse_markdown(rest) }
}

// ---- expected_files: the pure plan target ----

/// Every file the vault SHOULD contain — deterministic (id order; the
/// first taker keeps the bare stem, collisions suffix " (2)", " (3)" on a
/// case-insensitive key). Stickiness against the live manifest is the
/// 20j.2 planner's job; this is the fixpoint it converges to.
pub fn expected_files(store: &Store) -> Vec<VaultFile> {
    let mut entities: Vec<&Entity> = store.entities().collect();
    entities.sort_by_key(|e| e.id);

    let mut used: HashMap<String, u32> = HashMap::new();
    let mut out = Vec::new();
    for entity in entities {
        let Some(pool) = pool_of(store, entity) else { continue };
        let title = match entity.get(props::NAME) {
            Some(Value::Text(name)) => name.clone(),
            _ => String::new(),
        };
        let is_binary = entity.cells.iter().any(|c| matches!(c.value, Value::File(_)));
        let (stem_src, ext) = if is_binary {
            match title.rsplit_once('.') {
                Some((stem, ext)) => (stem.to_string(), ext.to_lowercase()),
                None => (title.clone(), String::new()),
            }
        } else {
            (title.clone(), "md".to_string())
        };
        let slug = vault_slug(&stem_src, entity.id);
        let key_base = format!("{pool}/{slug}.{ext}");
        let n = used.entry(key_base.clone()).or_insert(0);
        *n += 1;
        let stem = if *n == 1 { slug.clone() } else { format!("{slug} ({n})") };
        let rel_path = if ext.is_empty() {
            format!("library/{pool}/{stem}")
        } else {
            format!("library/{pool}/{stem}.{ext}")
        };
        let (class, content) = if is_binary {
            (VaultClass::Binary, None)
        } else {
            (VaultClass::Markdown, render_vault_entity(store, entity.id))
        };
        out.push(VaultFile { id: entity.id, rel_path, class, content });
    }
    out
}
