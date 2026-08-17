//! The snapshot: the one JSON document a shell renders from. Types and
//! builder, split out of lib.rs (T6, owner 2026-08-09). Everything here
//! is pub(crate) — the wire's shape is the contract, not these types.

use super::*;

// ---- the window's read: one JSON snapshot ----
// The shell renders from a snapshot and never holds the box: every call
// opens, reads (or writes), closes. The lock lives for milliseconds.

#[derive(Serialize)]
pub(crate) struct CellRow {
    /// The property definition's id — the inspector keys the catalog off
    /// it to render the right control and pick options.
    property_id: Id,
    property: String,
    /// The value-kind of the property: text/number/bool/datetime/select/
    /// reference/richtext/file — empty when the property has no kind.
    kind: String,
    value: String,
    /// For select/reference cells, the referenced entity's id — so the
    /// picker pre-selects and edits by id.
    ref_target: Option<Id>,
}

#[derive(Serialize)]
pub(crate) struct OptionRow {
    id: Id,
    name: String,
    /// Board/picker order (P11/11d) — 0 when the option predates ordering.
    order: f64,
    /// Live carriers of this option (the shelves' provenance, P19c).
    count: usize,
    /// Seed-born AND still unused — the "seeded" shelf; flips to the vault
    /// shelf the moment count > 0.
    seeded: bool,
    /// The hide convention: a `hidden` bool cell on the option entity.
    hidden: bool,
    /// The option's dot hue, 0–360, absent when unset.
    hue: Option<f64>,
    /// The terminal state a checkbox writes and a board folds.
    completes: bool,
    /// The kind names this option is offered to; empty = offered everywhere
    /// (the pre-scoping legacy shape).
    for_types: Vec<String>,
}

/// One property definition — the inspector's catalog: its kind, and for
/// a select, its option entities.
#[derive(Serialize)]
pub(crate) struct PropertyRow {
    id: Id,
    name: String,
    kind: String,
    options: Vec<OptionRow>,
    /// Live-carrier count (P11/11e) — the picker's "on 12 objects".
    usage: usize,
    /// Display attributes, absent when unset (P11.5 reads them; Swift's
    /// decoder ignores unknown keys until then).
    #[serde(skip_serializing_if = "Option::is_none")]
    icon: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    digit_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    hide_when_empty: Option<bool>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    hide_on_kinds: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    core_on_kinds: Vec<String>,
    /// Seed-born (Author::System birthed the definition) — the shelves'
    /// provenance tag (P19c).
    seeded: bool,
}

/// One kind (type) entity on the wire (P19c) — the id seam hide-on-kind /
/// core-on-kinds writers need to mint #<id> references.
#[derive(Serialize)]
pub(crate) struct KindRow {
    id: Id,
    name: String,
}

/// The assist switch (P19h): the consent that gates every clerk proposal.
#[derive(Serialize)]
pub(crate) struct AssistRow {
    id: Id,
    on: bool,
    /// The switch property's CURRENT name — the toggle's write target even
    /// after the definition is renamed (the P19 review; decode Optional).
    prop: String,
}

#[derive(Serialize)]
pub(crate) struct EntityRow {
    id: Id,
    title: String,
    kinds: Vec<String>,
    /// The POSITIONING date (P11/11f): the first calendar-set property with
    /// a DateTime cell — `date` before `due`, the same one order that
    /// anchors recurrence, so what renders and what anchors never drift.
    due: Option<i64>,
    /// The positioning cell's span end (P11/11f, additive — the P14 span
    /// bar reads it). Absent for a plain date.
    #[serde(skip_serializing_if = "Option::is_none")]
    due_end: Option<i64>,
    /// The positioning property's name ("due"/"date"), absent when undated
    /// (additive — the P14 grid draws the task checkbox on `due` rows
    /// without re-deriving).
    #[serde(skip_serializing_if = "Option::is_none")]
    positioned_by: Option<String>,
    due_date_only: bool,
    status: Option<String>,
    created: Option<i64>,
    trashed: bool,
    bookmarked: bool,
    archived: bool,
    /// Fingerprint of the stored content value, 0 when none — the editor
    /// learns from every snapshot whether its base moved, for free.
    content_print: u64,
    /// The seq of the newest transaction that touched this entity: a
    /// MONOTONIC recency key, not a wall clock (2026-08-18). It is what
    /// "the note I was editing earlier" means, and the shell's Docs list
    /// sorts on it — the same signal search already tiebreaks with
    /// (services/src/search.rs), so the two orders can never disagree.
    /// Wall-clock `modified` ties across rapid edits and cannot order
    /// recents. 0 for an entity no transaction touched.
    recency: u64,
    /// The entity's projected vault path (P20j.6) — `library/<pool>/<slug>`,
    /// exactly what materializes on disk, or absent for box-only entities.
    /// The shell shows it only in vault mode; Reveal opens root+this.
    #[serde(skip_serializing_if = "Option::is_none")]
    vault_path: Option<String>,
    cells: Vec<CellRow>,
}

#[derive(Serialize)]
pub(crate) struct OccurrenceRow {
    series: Id,
    civil: i64,
}

#[derive(Serialize)]
pub(crate) struct ProposalRow {
    entity: Id,
    /// 1-based position among this entity's proposals, in sweep order —
    /// the same addressing the CLI uses, stable across processes.
    ordinal: u32,
    /// Deterministic hash of the proposal's commands. Triage must present
    /// it back and it must still match: a consent is to a proposal, never
    /// to a position that may have shifted since the snapshot.
    fingerprint: u64,
    reason: String,
    author: String,
    /// The structured writes this proposal would make — the honest source for
    /// the shell's +/- diff card (P16), one entry per command. Never a
    /// string-parse of `reason`.
    commands: Vec<ProposalCommand>,
}

/// One command of a proposal, rendered for the diff card.
#[derive(Serialize)]
pub(crate) struct ProposalCommand {
    /// "add" | "trash" | "redirect" | "create" | "remove" | "restore".
    kind: String,
    property: Option<String>,
    /// The proposed value in display form (the `+` side; the `-` is the row's
    /// current value, derived shell-side).
    value: Option<String>,
    value_kind: Option<String>,
    /// The id a select/reference value points at (for chip rendering).
    ref_target: Option<Id>,
}

/// FNV-1a over the serialized commands — deterministic across processes,
/// because the sweep is deterministic.
pub(crate) fn fingerprint(proposal: &liv_core::Proposal) -> u64 {
    liv_services::content::fnv(&serde_json::to_vec(&proposal.commands).unwrap_or_default())
}

/// A proposal's commands rendered for the diff card (P16).
fn proposal_commands(store: &Store, proposal: &liv_core::Proposal) -> Vec<ProposalCommand> {
    use liv_core::Command;
    proposal
        .commands
        .iter()
        .map(|command| match command {
            Command::AddCell { cell, .. } => ProposalCommand {
                kind: "add".into(),
                property: Some(reference_name(store, cell.property)),
                value: Some(liv_views::display(store, &cell.value)),
                value_kind: property_kind(store, cell.property),
                ref_target: cell_target(store, &cell.value),
            },
            Command::RemoveCell { cell, .. } => ProposalCommand {
                kind: "remove".into(),
                property: Some(reference_name(store, cell.property)),
                value: Some(liv_views::display(store, &cell.value)),
                value_kind: property_kind(store, cell.property),
                ref_target: cell_target(store, &cell.value),
            },
            Command::Redirect { to, .. } => ProposalCommand {
                kind: "redirect".into(),
                property: None,
                value: None,
                value_kind: None,
                ref_target: Some(*to),
            },
            Command::Trash { .. } => command_kind("trash"),
            Command::Create { .. } => command_kind("create"),
            Command::Restore { .. } => command_kind("restore"),
        })
        .collect()
}

fn command_kind(kind: &str) -> ProposalCommand {
    ProposalCommand {
        kind: kind.into(),
        property: None,
        value: None,
        value_kind: None,
        ref_target: None,
    }
}

#[derive(Serialize)]
pub(crate) struct WorkspaceRow {
    id: Id,
    name: String,
    emoji: Option<String>,
    favorite: bool,
    archived: bool,
    /// "home" for the protected built-in; empty otherwise.
    builtin: String,
    /// 0 = top level; the tree is parent references, nothing else.
    parent: Id,
    order: f64,
    /// The lens: a search-DSL string (`props::QUERY`, the property saved
    /// views already use). A shell runs it to filter and reads its plain
    /// `key:value` terms to stamp new objects. Absent when unset — without
    /// it on the wire a shell must keep its own copy of the query, which
    /// is the second source of truth the constitution refuses.
    #[serde(skip_serializing_if = "Option::is_none")]
    query: Option<String>,
}

/// One pin on the Favourites shelf (P17g): a backstage entity pointing at
/// an object, ordered by a float key. A pin whose target is trashed drops
/// out of the projection (dangling tolerated), never out of the log.
#[derive(Serialize)]
pub(crate) struct PinRow {
    id: Id,
    target: Id,
    order: f64,
}

/// One layout layer (P17i): a named backstage entity whose ordered members
/// are the tabs to reopen. A trashed member drops from the row (dangling
/// tolerated); restore is pure shell — no verb exists for it.
#[derive(Serialize)]
pub(crate) struct LayerRow {
    id: Id,
    name: String,
    /// 0 = the built-in Home scope.
    workspace: Id,
    members: Vec<Id>,
}

#[derive(Serialize)]
pub(crate) struct Snapshot {
    today: Vec<Id>,
    unstructured: Vec<Id>,
    everything: Vec<Id>,
    dated: Vec<Id>,
    /// Virtual: this month's expansion of every recurring series,
    /// computed in services — never stored, same answer for every view.
    occurrences: Vec<OccurrenceRow>,
    inbox: Vec<ProposalRow>,
    /// Navigation chrome: working entities of type workspace, whole
    /// tree, archived included (the shell draws the Archive group).
    workspaces: Vec<WorkspaceRow>,
    /// The Favourites shelf, in order. The shell decodes this OPTIONAL —
    /// a missing key must never drop the snapshot (the H1 rule).
    pins: Vec<PinRow>,
    /// Saved layout layers (P17i). OPTIONAL shell-side, like pins.
    layers: Vec<LayerRow>,
    /// The habit card (P18b): lines + streaks + the 84-day chain, computed
    /// on read (D13). OPTIONAL shell-side.
    habits: liv_services::habits::HabitsSummary,
    /// Time totals + the 7-day window's entries (P18d). OPTIONAL shell-side.
    time_entries: liv_services::timeviews::TimeSummary,
    /// Saved views — the one filter engine's bookmarks (P18d). OPTIONAL.
    views: Vec<liv_services::timeviews::ViewRow>,
    /// The board's widgets, float-key ordered (P18d). OPTIONAL.
    widgets: Vec<liv_services::timeviews::WidgetRow>,
    /// The kind-id seam (P19c). OPTIONAL shell-side.
    kinds: Vec<KindRow>,
    /// The assist switch (P19h): the entity id (the toggle's write target)
    /// + its state. OPTIONAL shell-side.
    assist: Option<AssistRow>,
    /// Every property definition — the inspector's catalog.
    properties: Vec<PropertyRow>,
    /// Open checkbox lines inside notes (phase 3, owner 2026-08-05) — a
    /// PROJECTION: derived on read, stored nowhere, created never. The
    /// Tasks view's "In notes" section. OPTIONAL shell-side, like pins.
    note_tasks: Vec<liv_services::tasks::NoteTask>,
    entities: Vec<EntityRow>,
}

/// Open the box, seed if fresh, and fill the queue with the clerk's sweep —
/// the same ritual every shell performs.
// ---- the per-box store cache: skip re-reading an unchanged append-only log ----
//

fn property_kind(store: &Store, property: Id) -> Option<String> {
    match store.get(property).and_then(|p| p.get(props::VALUE_KIND)) {
        Some(Value::Text(kind)) => Some(kind.clone()),
        _ => None,
    }
}

/// The id a select/reference cell points at, for the picker.
/// The id a select/reference cell points at — resolved through redirects
/// (the read-time-resolution law; the P11.5 review's finding): a cell may
/// still STORE a merged-away id, but every read serves the survivor, so
/// the shell's backlink index and pickers agree with display().
fn cell_target(store: &Store, value: &Value) -> Option<Id> {
    match value {
        Value::Select(id) | Value::Reference(id) => Some(store.resolve(*id)),
        _ => None,
    }
}

/// The user-facing property definitions, with each select's options —
/// the catalog the inspector renders controls from. The core's own
/// schema vocabulary (name, type, working, private, value-kind, options,
/// expected, …) lives at the reserved ids below FIRST_USER_ID and is
/// plumbing, never something a hand sets on a note, so it is excluded:
/// offering `working` would let an edit silently hide the entity from
/// every view.
/// Every entity BORN by an Author::System transaction — the seed layer's
/// provenance, derived from the log (stored nowhere, P19c).
fn seed_born(store: &Store) -> std::collections::HashSet<Id> {
    let mut born = std::collections::HashSet::new();
    for tx in store.history() {
        if !matches!(tx.author, Author::System) {
            continue;
        }
        for command in &tx.commands {
            if let liv_core::Command::Create { entity } = command {
                born.insert(*entity);
            }
        }
    }
    born
}

/// Live carriers per select-option id, one global pass (P19c).
fn option_counts(store: &Store) -> std::collections::HashMap<Id, usize> {
    let mut counts: std::collections::HashMap<Id, usize> = std::collections::HashMap::new();
    for entity in store.entities().filter(|e| !e.trashed) {
        for cell in &entity.cells {
            if let Value::Select(option) = &cell.value {
                *counts.entry(store.resolve(*option)).or_insert(0) += 1;
            }
        }
    }
    counts
}

fn build_properties(store: &Store) -> Vec<PropertyRow> {
    let usage: std::collections::HashMap<Id, usize> =
        liv_services::search::usage_counts(store).into_iter().collect();
    let born = seed_born(store);
    let counts = option_counts(store);
    let hidden_prop = property_id(store, "hidden");
    let icon_prop = property_id(store, "icon");
    let digit_prop = property_id(store, "digit-key");
    let hide_empty_prop = property_id(store, "hide-when-empty");
    let hide_on_prop = property_id(store, "hide-on-kind");
    let core_on_prop = property_id(store, "core-on-kind");
    let text_of = |e: &Entity, p: Option<Id>| match p.and_then(|p| e.get(p)) {
        Some(Value::Text(t)) => Some(t.clone()),
        _ => None,
    };
    let kinds_of = |e: &Entity, p: Option<Id>| -> Vec<String> {
        p.map(|p| {
            e.all(p)
                .filter_map(|v| match v {
                    Value::Reference(t) => Some(reference_name(store, *t)),
                    _ => None,
                })
                .collect()
        })
        .unwrap_or_default()
    };
    let mut rows: Vec<PropertyRow> = store
        .entities()
        .filter(|e| !e.trashed && e.id >= props::FIRST_USER_ID)
        .filter_map(|e| {
            let kind = property_kind(store, e.id)?;
            let name = match e.get(props::NAME) {
                Some(Value::Text(n)) => n.clone(),
                _ => return None,
            };
            let options = if kind == "select" {
                let order_prop = property_id(store, "order");
                let hue_prop = property_id(store, "hue");
                let completes_prop = property_id(store, "completes");
                let for_type_prop = property_id(store, "for-type");
                let number = |id: Id, p: Option<Id>| match p
                    .and_then(|p| store.get(id).and_then(|e| e.get(p)))
                {
                    Some(Value::Number(n)) => Some(*n),
                    _ => None,
                };
                e.all(props::OPTIONS)
                    .filter_map(|v| match v {
                        Value::Reference(id) => Some(OptionRow {
                            id: *id,
                            name: reference_name(store, *id),
                            order: number(*id, order_prop).unwrap_or(0.0),
                            count: counts.get(id).copied().unwrap_or(0),
                            seeded: born.contains(id)
                                && counts.get(id).copied().unwrap_or(0) == 0,
                            hidden: matches!(
                                hidden_prop
                                    .and_then(|p| store.get(*id).and_then(|e| e.get(p))),
                                Some(Value::Bool(true))
                            ),
                            hue: number(*id, hue_prop),
                            completes: matches!(
                                completes_prop
                                    .and_then(|p| store.get(*id).and_then(|e| e.get(p))),
                                Some(Value::Bool(true))
                            ),
                            for_types: for_type_prop
                                .and_then(|p| store.get(*id).map(|e| (p, e)))
                                .map(|(p, e)| {
                                    e.all(p)
                                        .filter_map(|v| match v {
                                            Value::Reference(t) => {
                                                Some(reference_name(store, *t))
                                            }
                                            _ => None,
                                        })
                                        .collect()
                                })
                                .unwrap_or_default(),
                        }),
                        _ => None,
                    })
                    .collect()
            } else {
                Vec::new()
            };
            Some(PropertyRow {
                id: e.id,
                name,
                kind,
                options,
                usage: usage.get(&e.id).copied().unwrap_or(0),
                icon: text_of(e, icon_prop),
                digit_key: text_of(e, digit_prop),
                hide_when_empty: match hide_empty_prop.and_then(|p| e.get(p)) {
                    Some(Value::Bool(b)) => Some(*b),
                    _ => None,
                },
                hide_on_kinds: kinds_of(e, hide_on_prop),
                core_on_kinds: kinds_of(e, core_on_prop),
                seeded: born.contains(&e.id),
            })
        })
        .collect();
    rows.sort_by(|a, b| a.name.cmp(&b.name));
    rows
}

/// The default snapshot: the current civil month's occurrence window. A thin
/// wrapper so `liv_snapshot_at` is byte-identical to before — every existing
/// caller keeps working. The calendar asks for other windows through
/// `build_snapshot_windowed`.
pub(crate) fn build_snapshot(store: &Store) -> Snapshot {
    let now = Local::now();
    let from = DateTime::date(now.year(), now.month(), 1);
    let to = DateTime::date(
        now.year(),
        now.month(),
        last_day_of_month(now.year(), now.month()),
    );
    build_snapshot_windowed(store, from, to)
}

/// The snapshot over a caller-chosen occurrence window. `dated` is the full
/// sorted set regardless (the shell buckets it by day); only `occurrences` —
/// the recurrence engine's expansion — follows `[from, to]`, which the engine
/// caps at a year. Same `Snapshot` shape, a caller-chosen horizon.
pub(crate) fn build_snapshot_windowed(store: &Store, from: DateTime, to: DateTime) -> Snapshot {
    let status_prop = property_id(store, "status");
    let bookmarked_prop = property_id(store, "bookmarked");
    let archived_prop = property_id(store, "archived");

    let everything = run(store, &Query::default());

    let sections = liv_services::today_sections(store, civil_today());
    let (today, unstructured) = (sections.due, sections.unstructured);

    // The calendar's plain dates (P11/11f): everything with a cell on ANY
    // positioning property that is not a recurring series — those arrive as
    // occurrences instead. Per-role queries, merged, deduped, sorted by
    // positioning date then id. Lookup-role-only entities stay out
    // structurally — their absence from the set IS the off-calendar rule.
    let positioning = liv_services::calendar_set(store);
    let positioning_date = |id: Id| -> i64 {
        positioning
            .iter()
            .find_map(|p| match store.get(id).and_then(|e| e.get(*p)) {
                Some(Value::DateTime(d)) => Some(d.civil),
                _ => None,
            })
            .unwrap_or(0)
    };
    let dated = {
        let recurrence = property_id(store, "recurrence");
        let mut seen = std::collections::HashSet::new();
        let mut ids: Vec<Id> = Vec::new();
        for p in &positioning {
            let mut constraints = vec![Constraint { property: *p, op: Op::Exists }];
            if let Some(recurrence) = recurrence {
                constraints.push(Constraint { property: recurrence, op: Op::Missing });
            }
            for id in run(store, &Query { constraints, ..Query::default() }) {
                if seen.insert(id) {
                    ids.push(id);
                }
            }
        }
        // Cached key: the positioning walk runs once per id, never per
        // comparison (this is the per-refresh hot path).
        ids.sort_by_cached_key(|id| (positioning_date(*id), *id));
        ids
    };

    // The caller's window is the horizon the calendar asks for.
    let occurrences = liv_services::recurrence::occurrences(store, from, to)
        .into_iter()
        .map(|o| OccurrenceRow { series: o.series, civil: o.date.civil })
        .collect();

    // Backstage WIDGETS join the ROW STORE only (P18e): the standard
    // Inspector must resolve a selected widget's cells. entities[] is the
    // shell's id→row index; every surface iterates the ID LISTS
    // (everything/dated/…), so a backstage row here leaks nowhere.
    let mut projected: Vec<Id> = everything.clone();
    if let Some(widget_type) = liv_services::content::find_type(store, "widget") {
        projected.extend(
            store
                .entities()
                .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(widget_type)))
                .map(|e| e.id),
        );
    }
    // P20j.6: the projected path per entity (a pure store function — the
    // same expected_files the materializer plans from), joined by id.
    let vault_paths: std::collections::HashMap<Id, String> =
        liv_services::vault::expected_files(store)
            .into_iter()
            .map(|f| (f.id, f.rel_path))
            .collect();
    // Recency: ONE O(history) pass for the whole snapshot, not a lookup
    // per entity — `Store::modified` walks history each time it is asked,
    // which is the shape the file projection was punished for (2026-08-08).
    let recency = store.recency();
    let entities = projected
        .iter()
        .filter_map(|id| store.get(*id))
        .map(|entity| {
            // The positioning date: the FIRST calendar-set property with a
            // DateTime cell (`date` before `due` — the design's §2.2 order;
            // §7.3's due-first wording contradicted it and lost: ONE order
            // rules both the recurrence anchor and the rendered row, or the
            // calendar bucket and the occurrence day drift apart).
            let positioned = positioning.iter().find_map(|p| match entity.get(*p) {
                Some(Value::DateTime(d)) => Some((*d, reference_name(store, *p))),
                _ => None,
            });
            let (due, due_date_only, due_end, positioned_by) = match positioned {
                Some((d, name)) => (Some(d.civil), d.date_only, d.end, Some(name)),
                None => (None, false, None, None),
            };
            EntityRow {
                id: entity.id,
                // What a LIST calls this. NOT `liv_views::summary`,
                // which flattens the whole body into one line — a daily
                // note reached every shell surface as
                // "Thu 6 Aug ## Today - [ ] milk ## Notes" (owner,
                // 2026-08-07; test: services/tests/tasks.rs
                // display_name_is_the_first_line_not_the_whole_body).
                title: liv_services::content::display_name(store, entity),
                kinds: entity
                    .all(props::TYPE)
                    .filter_map(|v| match v {
                        Value::Reference(t) => Some(reference_name(store, *t)),
                        _ => None,
                    })
                    .collect(),
                due,
                due_end,
                positioned_by,
                due_date_only,
                status: status_prop.and_then(|p| {
                    entity.get(p).map(|v| liv_views::display(store, v))
                }),
                created: match entity.get(props::CREATED) {
                    Some(Value::DateTime(d)) => Some(d.civil),
                    _ => None,
                },
                trashed: entity.trashed,
                bookmarked: bookmarked_prop
                    .map(|p| entity.has(p, &Value::Bool(true)))
                    .unwrap_or(false),
                archived: archived_prop
                    .map(|p| entity.has(p, &Value::Bool(true)))
                    .unwrap_or(false),
                content_print: liv_services::content::content_fingerprint(
                    entity.get(props::CONTENT),
                ),
                recency: recency.get(&entity.id).copied().unwrap_or(0),
                vault_path: vault_paths.get(&entity.id).cloned(),
                cells: entity
                    .cells
                    .iter()
                    .map(|cell| CellRow {
                        property_id: cell.property,
                        property: reference_name(store, cell.property),
                        kind: property_kind(store, cell.property).unwrap_or_default(),
                        value: liv_views::display(store, &cell.value),
                        ref_target: cell_target(store, &cell.value),
                    })
                    .collect(),
            }
        })
        .collect();

    // The workspace tree: type by name, then every untrashed carrier.
    let workspaces = match liv_services::content::find_type(store, "workspace") {
        None => Vec::new(),
        Some(workspace_type) => {
            let text = |entity: &liv_core::Entity, prop: Option<Id>| -> Option<String> {
                match prop.and_then(|p| entity.get(p)) {
                    Some(Value::Text(t)) => Some(t.clone()),
                    _ => None,
                }
            };
            let flag = |entity: &liv_core::Entity, prop: Option<Id>| -> bool {
                matches!(prop.and_then(|p| entity.get(p)), Some(Value::Bool(true)))
            };
            let emoji_prop = property_id(store, "emoji");
            let favorite_prop = property_id(store, "favorite");
            let archived_prop = property_id(store, "archived");
            let builtin_prop = property_id(store, "builtin");
            let parent_prop = property_id(store, "parent");
            let order_prop = property_id(store, "order");
            let mut rows: Vec<WorkspaceRow> = store
                .entities()
                .filter(|e| {
                    !e.trashed && e.has(props::TYPE, &Value::Reference(workspace_type))
                })
                .map(|e| WorkspaceRow {
                    id: e.id,
                    name: match e.get(props::NAME) {
                        Some(Value::Text(name)) => name.clone(),
                        _ => format!("#{}", e.id),
                    },
                    emoji: text(e, emoji_prop),
                    favorite: flag(e, favorite_prop),
                    archived: flag(e, archived_prop),
                    builtin: text(e, builtin_prop).unwrap_or_default(),
                    parent: match parent_prop.and_then(|p| e.get(p)) {
                        Some(Value::Reference(target)) => *target,
                        _ => 0,
                    },
                    order: match order_prop.and_then(|p| e.get(p)) {
                        Some(Value::Number(n)) => *n,
                        _ => 0.0,
                    },
                    query: match e.get(props::QUERY) {
                        Some(Value::Text(q)) if !q.is_empty() => Some(q.clone()),
                        _ => None,
                    },
                })
                .collect();
            rows.sort_by(|a, b| {
                a.order.partial_cmp(&b.order).unwrap_or(std::cmp::Ordering::Equal)
            });
            rows
        }
    };

    // How many proposals so far target this entity — a COUNTER, not a
    // rescan of everything seen (2026-08-18). It was a Vec walked with
    // `filter().count()` per proposal, which made every snapshot
    // quadratic in the queue: a box whose clerk had proposed 400 times
    // spent 430ms of a 450ms snapshot right here (found by the cost test
    // at the seam, ffi/src/tests.rs).
    let mut seen: std::collections::HashMap<Id, u32> = std::collections::HashMap::new();
    // The consent gate covers the READ too (P19 review): the sweep goes
    // quiet when the switch is off, but the .pending sidecar persists —
    // yesterday's queue must not keep proposing over a recorded opt-out.
    let inbox = if !liv_services::clerk::assist_enabled(store) {
        Vec::new()
    } else {
        store
        .pending()
        .iter()
        .filter_map(|p| {
            let entity = match p.commands.first() {
                Some(liv_core::Command::AddCell { entity, .. })
                | Some(liv_core::Command::Create { entity })
                | Some(liv_core::Command::Trash { entity })
                | Some(liv_core::Command::Restore { entity })
                | Some(liv_core::Command::RemoveCell { entity, .. })
                | Some(liv_core::Command::Redirect { entity, .. }) => *entity,
                None => return None,
            };
            let ordinal = {
                let n = seen.entry(entity).or_insert(0);
                *n += 1;
                *n
            };
            Some(ProposalRow {
                entity,
                ordinal,
                fingerprint: fingerprint(p),
                reason: p.reason.clone(),
                author: match &p.author {
                    Author::Proposer(name) => name.clone(),
                    Author::User => "user".into(),
                    Author::System => "system".into(),
                },
                commands: proposal_commands(store, p),
            })
        })
        .collect()
    };

    let properties = build_properties(store);

    // The Favourites shelf (P17g): live pins in float-key order; a pin whose
    // target is trashed/missing drops out of the ROW set (dangling tolerated),
    // never out of the log.
    let pins = match (
        liv_services::content::find_type(store, "pin"),
        property_id(store, "target"),
        property_id(store, "order"),
    ) {
        (Some(pin_type), Some(target_prop), order_prop) => {
            let mut rows: Vec<PinRow> = store
                .entities()
                .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(pin_type)))
                .filter_map(|e| {
                    let target = match e.get(target_prop) {
                        Some(Value::Reference(t)) => store.resolve(*t),
                        _ => return None,
                    };
                    // Dangling target → no row.
                    if store.get(target).map(|t| t.trashed) != Some(false) {
                        return None;
                    }
                    let order = match order_prop.and_then(|p| e.get(p)) {
                        Some(Value::Number(n)) => *n,
                        _ => 0.0,
                    };
                    Some(PinRow { id: e.id, target, order })
                })
                .collect();
            rows.sort_by(|a, b| a.order.partial_cmp(&b.order).unwrap_or(std::cmp::Ordering::Equal));
            rows
        }
        _ => Vec::new(),
    };

    // Layout layers (P17i): named, workspace-scoped, ordered members; a
    // trashed member drops from the row, never the row from the snapshot.
    let layers = match (
        liv_services::content::find_type(store, "layer"),
        property_id(store, "related"),
    ) {
        (Some(layer_type), Some(related)) => {
            let ws_prop = property_id(store, "workspace");
            store
                .entities()
                .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(layer_type)))
                .map(|e| LayerRow {
                    id: e.id,
                    name: match e.get(props::NAME) {
                        Some(Value::Text(name)) => name.clone(),
                        _ => format!("#{}", e.id),
                    },
                    workspace: match ws_prop.and_then(|p| e.get(p)) {
                        Some(Value::Reference(w)) => *w,
                        _ => 0,
                    },
                    members: e
                        .cells
                        .iter()
                        .filter(|c| c.property == related)
                        .filter_map(|c| match &c.value {
                            Value::Reference(id) => {
                                let id = store.resolve(*id);
                                (store.get(id).map(|t| t.trashed) == Some(false)).then_some(id)
                            }
                            _ => None,
                        })
                        .collect(),
                })
                .collect()
        }
        _ => Vec::new(),
    };

    let now = Local::now();
    let today_ymd = (now.year() as i64) * 10_000 + (now.month() as i64) * 100 + now.day() as i64;
    let habits = liv_services::habits::habit_stats(store, today_ymd);
    let time_entries = liv_services::timeviews::time_totals(store, today_ymd);
    let views = liv_services::timeviews::saved_views(store);
    let widgets = liv_services::timeviews::board_widgets(store);
    // The kind-id seam (P19c): every find-able type (an EXPECTED cell is what
    // makes a type a type — the P9 rule).
    let mut kinds: Vec<KindRow> = store
        .entities()
        .filter(|e| !e.trashed && e.get(props::EXPECTED).is_some())
        .filter_map(|e| match e.get(props::NAME) {
            Some(Value::Text(name)) => Some(KindRow { id: e.id, name: name.clone() }),
            _ => None,
        })
        .collect();
    // Deterministic order — the cache-parity test compares snapshots byte-wise.
    kinds.sort_by_key(|k| k.id);
    let assist = liv_services::clerk::assist_switch(store).map(|(entity, prop, on)| {
        AssistRow { id: entity, on, prop: reference_name(store, prop) }
    });

    Snapshot {
        today,
        unstructured,
        everything,
        dated,
        occurrences,
        inbox,
        workspaces,
        pins,
        layers,
        habits,
        time_entries,
        views,
        widgets,
        kinds,
        assist,
        properties,
        note_tasks: liv_services::tasks::note_tasks(store),
        entities,
    }
}

