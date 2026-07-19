//! P20j.1 — the files projection's PURE layer: the vault slugger (the
//! pack's own breadcrumb is the spec: Steven Åkesson →
//! library/contacts/steven-akesson.md), deterministic collision suffixing,
//! pool classification, H1-is-title rendering (no `title:` frontmatter),
//! and the render∘parse fixpoint over generated span trees. No IO here —
//! the materializer (20j.2) builds on these gates.

use lotus_core::*;
use lotus_services::content;
use lotus_services::vault;

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("lotus_vault_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn cleanup(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn the_slug_table() {
    // The pack's own example — diacritics transliterate, never percent-
    // encode, never drop.
    assert_eq!(vault::vault_slug("Steven Åkesson", 1), "steven-akesson");
    assert_eq!(vault::vault_slug("Thesis draft v3", 1), "thesis-draft-v3");
    // Punctuation collapses to single hyphens; nothing leading/trailing.
    assert_eq!(
        vault::vault_slug("SSK — counterargument, rhetoric motion", 1),
        "ssk-counterargument-rhetoric-motion"
    );
    // Windows-reserved stems are suffixed (the port is coming).
    assert_eq!(vault::vault_slug("CON", 1), "con-file");
    assert_eq!(vault::vault_slug("aux", 1), "aux-file");
    // Dot-prefix refusal (no hidden files from names).
    assert_eq!(vault::vault_slug("..hidden", 1), "hidden");
    // Empty → the id fallback.
    assert_eq!(vault::vault_slug("", 42), "untitled-42");
    assert_eq!(vault::vault_slug("→→→", 7), "untitled-7");
    // The 200-byte clamp lands on a char boundary.
    let long = "å".repeat(300);
    let clamped = vault::vault_slug(&long, 1);
    assert!(clamped.len() <= 200);
    assert!(clamped.chars().all(|c| c == 'a'));
}

#[test]
fn collision_suffixing_is_deterministic_and_case_insensitive() {
    let (mut session, path) = boxed("collide");
    let stamp = DateTime::at(2026, 7, 15, 9, 0);
    let mut ids = Vec::new();
    for name in ["Note", "note", "NOTE"] {
        let id = content::create_note(&mut session, stamp).unwrap();
        content::set_type(&mut session, id, "note").unwrap();
        content::set_property(&mut session, id, "name", name).unwrap();
        ids.push(id);
    }
    let files = vault::expected_files(session.store());
    let paths: Vec<&str> = ids
        .iter()
        .map(|id| {
            files.iter().find(|f| f.id == *id).map(|f| f.rel_path.as_str()).unwrap()
        })
        .collect();
    // Id order keeps the bare stem; later ids suffix — deterministically.
    assert_eq!(
        paths,
        ["library/notes/note.md", "library/notes/note (2).md", "library/notes/note (3).md"]
    );
    cleanup(&path);
}

#[test]
fn pools_classify_and_scraps_stay_box_only() {
    let (mut session, path) = boxed("pools");
    let stamp = DateTime::at(2026, 7, 15, 9, 0);

    let note = content::create_note(&mut session, stamp).unwrap();
    content::set_type(&mut session, note, "note").unwrap();
    content::set_property(&mut session, note, "name", "Methodology").unwrap();

    let person = content::create_note(&mut session, stamp).unwrap();
    content::set_type(&mut session, person, "person").unwrap();
    content::set_property(&mut session, person, "name", "Steven Åkesson").unwrap();

    let task = content::create_task(&mut session, stamp).unwrap();
    content::set_property(&mut session, task, "name", "Email David").unwrap();

    // A typeless scrap: captured, unrouted — materializes on ROUTE, not on
    // capture (the recorded delta).
    let scrap = lotus_services::capture(&mut session, "a loose thought", stamp).unwrap();

    let files = vault::expected_files(session.store());
    let path_of = |id: Id| files.iter().find(|f| f.id == id).map(|f| f.rel_path.clone());

    assert_eq!(path_of(note).as_deref(), Some("library/notes/methodology.md"));
    assert_eq!(path_of(person).as_deref(), Some("library/contacts/steven-akesson.md"));
    assert_eq!(path_of(task).as_deref(), Some("library/tasks/email-david.md"));
    assert_eq!(path_of(scrap), None, "unrouted scraps are box-only");
    // No WORKING plumbing ever projects.
    assert!(files.iter().all(|f| {
        let e = session.store().get(f.id).unwrap();
        !e.has(props::WORKING, &Value::Bool(true))
    }));
    cleanup(&path);
}

#[test]
fn h1_is_the_title_and_round_trips() {
    let (mut session, path) = boxed("h1");
    let stamp = DateTime::at(2026, 7, 15, 9, 0);
    let note = content::create_note(&mut session, stamp).unwrap();
    content::set_type(&mut session, note, "note").unwrap();
    content::set_property(&mut session, note, "name", "Regression setup").unwrap();
    content::birth_property(&mut session, "topic", "text").unwrap();
    content::set_property(&mut session, note, "topic", "draft").unwrap();

    let rendered = vault::render_vault_entity(session.store(), note).unwrap();
    // The H1 IS the title; no `title:` frontmatter key exists.
    assert!(rendered.contains("# Regression setup"), "{rendered}");
    assert!(!rendered.contains("title:"), "{rendered}");
    assert!(rendered.contains("topic: draft"), "{rendered}");

    let parsed = vault::parse_vault_note(&rendered);
    assert_eq!(parsed.name.as_deref(), Some("Regression setup"));
    assert!(parsed.frontmatter.iter().any(|(k, v)| k == "topic" && v == "draft"));
    cleanup(&path);
}

/// The generator both gates share: a deterministic LCG over the whole
/// block/mark vocabulary. `spaced` pads runs the way human text does;
/// unspaced runs are the adversarial marker-adjacency torture.
fn generated_document(seed0: u64, spaced: bool) -> RichText {
    let mut seed = seed0;
    let mut next = move || {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        (seed >> 33) as usize
    };
    let mut spans: Vec<Span> = Vec::new();
    let paragraphs = 1 + next() % 6;
    for _p in 0..paragraphs {
        let block = match next() % 7 {
            0 => Block::Heading(1 + (next() % 3) as u8),
            1 => Block::Bullet { depth: (next() % 2) as u8 },
            2 => Block::Task { depth: 0, done: next() % 2 == 0 },
            3 => Block::Quote,
            4 => Block::Ordered { depth: 0 },
            _ => Block::Body,
        };
        spans.push(Span::Break(block));
        let runs = 1 + next() % 3;
        for run in 0..runs {
            let words = ["alpha", "beta", "gamma", "delta", "epsilon"];
            let mut text = words[next() % words.len()].to_string();
            if spaced && run + 1 < runs {
                text.push(' ');
            }
            let marks = (next() % 16) as u8;
            spans.push(Span::Text(TextSpan { text, marks: Marks(marks) }));
        }
    }
    RichText { spans }
}

#[test]
fn realistic_documents_render_byte_stable() {
    // Human-shaped text (runs bounded by spaces): render∘parse must be a
    // strict fixpoint — the echo suppressor compares bytes.
    let names = |_: Id| -> String { "target".into() };
    for case in 0..200u64 {
        let doc = generated_document(0x5eed_cafe ^ case, true);
        let once = lotus_services::markdown::render_markdown(&doc, &names);
        let reparsed = lotus_services::markdown::parse_markdown(&once);
        let twice = lotus_services::markdown::render_markdown(&reparsed, &names);
        assert_eq!(once, twice, "spaced documents must be byte-stable");
    }
}

#[test]
fn adversarial_documents_converge_in_one_round_trip() {
    // No-space marker adjacencies hit CommonMark's flanking limits — an
    // outer closer preceded by an inner marker's punctuation cannot close
    // reliably in ANY nesting order. The projector's contract is
    // CONVERGENCE: a parsed-then-rendered document is canonical and
    // byte-stable from then on (each external ingest re-projects once and
    // the file settles). Recorded as the codec's known lossy edge.
    let names = |_: Id| -> String { "target".into() };
    for case in 0..200u64 {
        let doc = generated_document(0xdead_beef ^ case, false);
        let r1 = lotus_services::markdown::render_markdown(&doc, &names);
        let p1 = lotus_services::markdown::parse_markdown(&r1);
        let r2 = lotus_services::markdown::render_markdown(&p1, &names);
        let p2 = lotus_services::markdown::parse_markdown(&r2);
        let r3 = lotus_services::markdown::render_markdown(&p2, &names);
        assert_eq!(r2, r3, "one round trip must reach the fixpoint");
    }
}
