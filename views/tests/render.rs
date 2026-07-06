//! The first lens. It renders anything with the configured properties —
//! it neither knows nor asks what the entities are.

use lotus_core::*;
use lotus_views::{render, Config, Density};

const DUE: Id = 4301;

fn cell(property: Id, value: Value) -> Cell {
    Cell { property, value }
}

fn fixture() -> (Store, Id, Id) {
    let mut store = Store::new();
    let project = store.allocate_id();
    let task = store.allocate_id();
    store
        .commit(
            vec![
                // The "due" property definition: an entity with a name.
                Command::Create { entity: DUE },
                Command::AddCell {
                    entity: DUE,
                    cell: cell(props::NAME, Value::text("due")),
                },
                Command::Create { entity: project },
                Command::AddCell {
                    entity: project,
                    cell: cell(props::NAME, Value::text("Alpha")),
                },
                Command::Create { entity: task },
                Command::AddCell {
                    entity: task,
                    cell: cell(props::NAME, Value::text("kickoff prep")),
                },
                Command::AddCell {
                    entity: task,
                    cell: cell(DUE, Value::DateTime(DateTime::date(2026, 7, 10))),
                },
                Command::AddCell {
                    entity: task,
                    cell: cell(4400, Value::Reference(project)),
                },
            ],
            "fixture",
            Author::User,
        )
        .unwrap();
    (store, task, project)
}

#[test]
fn table_draws_properties_as_columns() {
    let (store, task, _) = fixture();
    let rendered = render(
        &store,
        &[task],
        &Config {
            density: Density::Table,
            columns: vec![props::NAME, DUE, 4400],
        },
    );
    // Header: named property resolves, unnamed falls back to its id.
    assert_eq!(rendered.header, vec!["#1", "due", "#4400"]);
    assert_eq!(rendered.rows.len(), 1);
    // A date-only value renders without an invented 00:00; a reference
    // draws as its target's name.
    assert_eq!(
        rendered.rows[0].cells,
        vec!["kickoff prep", "2026-07-10", "Alpha"]
    );
}

#[test]
fn list_density_summarizes() {
    let (mut store, task, project) = fixture();
    let scrap = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: scrap },
                Command::AddCell {
                    entity: scrap,
                    cell: cell(
                        props::CONTENT,
                        Value::RichText(RichText {
                            spans: vec![
                                Span::Text("prepare the ".into()),
                                Span::Ref(project),
                                Span::Text(" kickoff".into()),
                            ],
                        }),
                    ),
                },
            ],
            "scrap",
            Author::User,
        )
        .unwrap();

    let rendered = render(
        &store,
        &[task, scrap],
        &Config {
            density: Density::List,
            columns: vec![],
        },
    );
    // Named entity shows its name; a scrap shows its content, with the
    // embedded reference drawn as the target's name.
    assert_eq!(rendered.rows[0].cells, vec!["kickoff prep"]);
    assert_eq!(rendered.rows[1].cells, vec!["prepare the Alpha kickoff"]);
}

#[test]
fn broken_references_render_broken() {
    let (mut store, task, project) = fixture();
    store
        .commit(vec![Command::Trash { entity: project }], "trash", Author::User)
        .unwrap();
    let rendered = render(
        &store,
        &[task],
        &Config {
            density: Density::Table,
            columns: vec![4400],
        },
    );
    // A reference to a trashed entity is a broken link — shown, not hidden,
    // and certainly not repaired. Deletion never cascades.
    assert_eq!(rendered.rows[0].cells, vec![format!("#{project}!")]);
}

#[test]
fn renderer_keys_on_properties_never_on_type() {
    // An entity with no type at all still renders anywhere its properties
    // fit: the table asks "does it have the column properties", not "what
    // is it".
    let mut store = Store::new();
    let untyped = store.allocate_id();
    store
        .commit(
            vec![
                Command::Create { entity: untyped },
                Command::AddCell {
                    entity: untyped,
                    cell: cell(props::NAME, Value::text("no type, no problem")),
                },
            ],
            "untyped",
            Author::User,
        )
        .unwrap();
    let rendered = render(
        &store,
        &[untyped],
        &Config {
            density: Density::Table,
            columns: vec![props::NAME],
        },
    );
    assert_eq!(rendered.rows[0].cells, vec!["no type, no problem"]);
}
