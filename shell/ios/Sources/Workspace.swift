// liv iOS — workspaces + filters (design/ios.md, M4). The workspace and
// filter model, the snapshot row decoders, the term-spelling helpers and
// the lens chip. The query PARSER is not here: it moved to the core on
// 2026-08-27.
//
// THE DATA MODEL (settled 2026-07-26, restated so nothing drifts):
// a workspace is an entity carrying ONE `query` cell — a search-DSL string
// like `area:Work project:Viggo`. That single cell is both halves:
//
//   LENS  = run the query.
//   STAMP = the query's plain `key:value` equality terms, written as cells
//           on objects created while the workspace is active.
//
// Terms that are not plain equality (`-tag:old`, `has:x`, `no:x`, `is:x`)
// FILTER but never stamp — they have no single value to write. A saved
// filter is the same thing minus the stamp: a view entity with a `query`
// cell. One grammar, one parser, one mental model.
//
// The lens is answered by the CORE. `refreshLens` sends the combined
// workspace-and-filter query to `liv_query_ids_at` and keeps the id set it
// returns; `admits` only reads that set. One round-trip per lens change
// and one per snapshot — not one per surface, and not one per keystroke:
// editing a draft query lexes it with `liv_lex`, which opens no box.

import Combine
import Foundation
import SwiftUI

// MARK: - the grammar

/// SPELLING a term, and rewriting the text around it.
///
/// What is left of the shell's query handling after the parser went to the
/// core on 2026-08-27. Nothing here decides what a query MEANS — it only
/// produces and edits text, which is the half a shell legitimately owns.
enum LivTerms {
    /// `key:value`, or `-key:value` to exclude.
    ///
    /// The VALUE is quoted when it carries a space — `people:"Anna
    /// Karlsson"` — and the WHOLE term when the key does. Same rule as
    /// `services::search::spell`, and it has to stay the same rule: the
    /// core respells every term it hands back, so a difference here would
    /// rewrite a hand-typed query the first time a picker touched it.
    static func term(_ property: String, _ value: String, exclude: Bool = false) -> String {
        let minus = exclude ? "-" : ""
        let clean = value.replacingOccurrences(of: "\"", with: "")
        if property.contains(" ") { return "\"\(minus)\(property):\(clean)\"" }
        if clean.contains(" ") { return "\(minus)\(property):\"\(clean)\"" }
        return "\(minus)\(property):\(clean)"
    }

    /// What a picker row shows for one property, or nil for "Any". Only an
    /// equality counts: a lens built from pickers is made of the one
    /// stamping shape.
    static func value(of property: String, in terms: [BoxModel.LivQueryTerm]) -> String? {
        terms.first {
            $0.op == "equals"
                && $0.key.compare(property, options: .caseInsensitive) == .orderedSame
        }?.value
    }

    /// Put a picked value back, replacing whatever that property said and
    /// leaving every other term exactly as the core respelled it. Editing
    /// through a picker therefore never rewrites an advanced query someone
    /// hand-made — it only touches its own row.
    static func setting(
        _ property: String, to value: String?, in terms: [BoxModel.LivQueryTerm]
    ) -> String {
        var kept = terms
            .filter { $0.key.compare(property, options: .caseInsensitive) != .orderedSame }
            .map(\.raw)
        if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
            kept.append(term(property, value))
        }
        return kept.joined(separator: " ")
    }

    /// The stamp: the equality terms, in written order, exact duplicates
    /// dropped.
    static func stamps(_ terms: [BoxModel.LivQueryTerm]) -> [(property: String, value: String)] {
        var out: [(property: String, value: String)] = []
        for t in terms where t.op == "equals" {
            guard !out.contains(where: { $0.property == t.key && $0.value == t.value })
            else { continue }
            out.append((property: t.key, value: t.value))
        }
        return out
    }
}

// MARK: - snapshot rows (mirror ffi/src/lib.rs — every field Optional)

/// One workspace from the snapshot's `workspaces` section. `query` is the
/// lens — the box is its only home (the wire carries it since the M4 ffi
/// addition; no device-side copy, no second source of truth).
struct WorkspaceRow: Decodable, Identifiable {
    var wsId: UInt64?
    var name: String?
    var emoji: String?
    var favorite: Bool?
    var archived: Bool?
    var builtin: String?
    var parent: UInt64?
    var order: Double?
    var query: String?

    var id: UInt64 { wsId ?? 0 }
    var display: String { (name ?? "").isEmpty ? "#\(id)" : (name ?? "") }

    private enum CodingKeys: String, CodingKey {
        case wsId = "id", name, emoji, favorite, archived, builtin, parent, order,
            query
    }
}

/// One saved filter: a view entity with a `query` cell — the same shape a
/// workspace has, minus the stamp.
struct SavedViewRow: Decodable, Identifiable {
    var viewId: UInt64?
    var name: String?
    var query: String?

    var id: UInt64 { viewId ?? 0 }
    var display: String { (name ?? "").isEmpty ? "#\(id)" : (name ?? "") }

    private enum CodingKeys: String, CodingKey {
        case viewId = "id", name, query
    }
}

// MARK: - the model

/// The active lens + the workspace roster. Shell state on top of box truth:
/// the workspace list and every saved filter come from the snapshot; the
/// active choice is device state (UserDefaults), like the desk's tabs.
final class WorkspaceModel: ObservableObject {
    /// 0 = "All" — no lens, no stamp. Persisted; drives the desk's tab set.
    @Published private(set) var activeId: UInt64 = 0
    /// A saved filter ANDed on top of the workspace lens. Transient by
    /// design: a filter narrows a session, a workspace IS the session.
    @Published var activeFilterId: UInt64?
    @Published private(set) var workspaces: [WorkspaceRow] = []
    @Published private(set) var filters: [SavedViewRow] = []

    static let activeKey = "workspace.active"

    init() {
        activeId = UInt64(UserDefaults.standard.integer(forKey: Self.activeKey))
    }

    /// Fold a fresh snapshot in. An active workspace that left the box falls
    /// back to All rather than filtering against a ghost — but ONLY on the
    /// evidence of a real `workspaces` section. A nil snapshot (the state at
    /// launch, before the box has opened) and a wire without the section are
    /// silence, not a claim that the workspace is gone; treating them as
    /// evidence resets the user's workspace on every cold start, and it is
    /// a PERSISTED reset, so the loss survives the launch. Found live.
    func apply(_ snap: Snapshot?) {
        guard let snap else { return }
        if let rows = snap.workspaces {
            workspaces = rows.filter { $0.id != 0 }
            if activeId != 0, !workspaces.contains(where: { $0.id == activeId }) {
                setActive(0)
            }
        }
        if let rows = snap.views {
            filters = rows.filter { $0.id != 0 }
            if let f = activeFilterId, !filters.contains(where: { $0.id == f }) {
                activeFilterId = nil
            }
        }
    }

    var active: WorkspaceRow? {
        workspaces.first { $0.id == activeId }
    }

    /// The chip's text and the switcher's label.
    var activeName: String {
        active?.display ?? "All"
    }

    /// The name the lens chip shows — workspace, filter, or both.
    var lensLabel: String {
        let filter = filters.first { $0.id == activeFilterId }?.display
        switch (active?.display, filter) {
        case (let w?, let f?): return "\(w) · \(f)"
        case (let w?, nil): return w
        case (nil, let f?): return f
        default: return ""
        }
    }

    /// The lens as RAW TEXT: the workspace's query and any chosen filter,
    /// joined with a space. There is nothing to AND — a query is already a
    /// conjunction, so concatenation is the whole operation, and the core
    /// parses the result exactly as it would if a person had typed it.
    var activeRaw: String {
        [query(of: activeId) ?? "", activeFilterId.flatMap { f in
            filters.first(where: { $0.id == f })?.query
        } ?? ""]
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    /// WHICH ENTITIES THE LENS ADMITS, answered by the core.
    ///
    /// `nil` means no lens is on and every row passes. A Set rather than a
    /// predicate because the answer arrives once per lens change and once
    /// per snapshot, not once per row per render.
    @Published private(set) var lensIds: Set<UInt64>?

    /// Does this row pass the lens?
    ///
    /// It READS the core's answer; it does not decide anything. No lens on
    /// means every row passes, which is why the optional is not defaulted
    /// to an empty set — an empty set is "the lens admits nothing", and
    /// those are opposite screens.
    func admits(_ row: EntityRow) -> Bool {
        guard let lensIds else { return true }
        return lensIds.contains(row.id)
    }

    /// Re-ask the core. Call when the lens changes and on every snapshot —
    /// a note created a moment ago has to enter a filtered view, and only
    /// the box knows whether it belongs.
    func refreshLens(_ box: BoxModel) {
        // The STAMP is workspace-only and needs no box, so it is set here
        // and now — synchronously, off `liv_lex`. Waiting for the lens's
        // round-trip would leave a capture made in the first moments of a
        // workspace unstamped.
        workspaceTerms = box.lex(query(of: activeId) ?? "")
        let raw = activeRaw
        guard !raw.isEmpty else {
            lensIds = nil
            return
        }
        box.query(raw) { [weak self] ids, _ in
            guard let self, raw == self.activeRaw else { return }
            self.lensIds = ids
        }
    }

    /// True when some lens is on — the surfaces show the chip only then.
    var lensOn: Bool {
        activeId != 0 || activeFilterId != nil
    }

    /// The cells a new entity inherits from the WORKSPACE. Read off the
    /// terms the core lexed, not off the text.
    ///
    /// The workspace only — never the saved filter. A filter narrows what
    /// you are looking at; it does not say what you are making.
    var stampCells: [(property: String, value: String)] {
        LivTerms.stamps(workspaceTerms)
    }

    /// The active WORKSPACE's terms, lexed separately from the lens: the
    /// lens is workspace-and-filter, the stamp is workspace-only.
    @Published private(set) var workspaceTerms: [BoxModel.LivQueryTerm] = []

    /// Write the active workspace's stamp onto something just created.
    /// The ONE implementation — every creation door calls this, so a task
    /// typed into a filtered Today inherits exactly what the capture sheet
    /// would have given it. Returns what it wrote (empty when there is no
    /// active workspace, or its query has no equality term).
    ///
    /// Not stamping in a filtered surface is the worse bug: you add a task
    /// while looking at Work, it does not get `area:Work`, and it vanishes
    /// from the list you are staring at.
    /// `landed` reports what the box ACCEPTED, one call per cell. A verb can
    /// refuse — a select value with no matching option, a property that does
    /// not exist — and a refusal must never be drawn as an applied chip. The
    /// return value is the intent; only `landed` is evidence.
    @discardableResult
    func stamp(
        _ id: UInt64, in box: BoxModel,
        landed: (((property: String, value: String)) -> Void)? = nil
    ) -> [(property: String, value: String)] {
        let cells = stampCells
        guard id != 0, !cells.isEmpty else { return [] }
        for cell in cells {
            let done: (Bool) -> Void = { ok in if ok { landed?(cell) } }
            if cell.property == "type" {
                box.setType(id, cell.value, done: done)
            } else {
                box.set(id, cell.property, cell.value, done: done)
            }
        }
        return cells
    }

    func setActive(_ id: UInt64) {
        activeId = id
        activeFilterId = nil
        UserDefaults.standard.set(Int(id), forKey: Self.activeKey)
    }

    /// The lens, straight off the wire — the box is the only source.
    /// nil = this workspace has no query cell (an unfiltered workspace).
    func query(of id: UInt64) -> String? {
        guard id != 0 else { return nil }
        let q = workspaces.first { $0.id == id }?.query
        return (q?.isEmpty ?? true) ? nil : q
    }

    /// The write already went to the box; the next snapshot carries it.
    /// Kept as a no-op seam so call sites read as intent, not plumbing.
    func rememberQuery(_ id: UInt64, _ query: String) {
        objectWillChange.send()
    }

    func forgetQuery(_ id: UInt64) {}

    /// The pre-2026-08-22 key: ONE plane per workspace, holding the Notes
    /// tabs. READ-ONLY — nothing writes it. `DeskPlanes.load` (Plane.swift)
    /// reads it once, to become the Notes plane of v2.
    static func tabsKey(_ workspace: UInt64) -> String {
        "desk.tabs.v1.\(workspace)"
    }

    /// One plane per VIEW per workspace — the 2026-08-22 shape.
    /// READ-ONLY since 2026-08-28:  folds these into the
    /// one desk and leaves them where they are.
    static func planeKey(_ workspace: UInt64, _ view: String) -> String {
        "desk.tabs.v2.\(workspace).\(view)"
    }

    /// THE DESK: the documents open in one workspace. One key, because
    /// there is one desk (2026-08-28).
    static func deskKey(_ workspace: UInt64) -> String {
        "desk.v3.\(workspace)"
    }

    /// Where each tool was left, view name to position token. One small
    /// map beside the desk, because a place is singular.
    static func spotsKey(_ workspace: UInt64) -> String {
        "desk.spots.v3.\(workspace)"
    }

    /// The one open document, per workspace.
    static func docKey(_ workspace: UInt64) -> String {
        "desk.doc.v1.\(workspace)"
    }
}

// MARK: - the lens chip

/// The quiet indicator SEARCH wears, so a short result list is never a
/// mystery. The other surfaces named their lens in prose instead and lost
/// their chips on 2026-08-18 ("the workspace button at top centre says it
/// once"); the panel foot names the workspace. The Inbox never shows it —
/// the Inbox is never filtered.
struct LensChip: View {
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            LivIcon(glyph: .filter, color: LivTheme.accent, size: 12)
            Text(label)
                .font(.system(size: LivType.caption, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(LivTheme.accent)
        .padding(.horizontal, 7)
        .frame(height: 17)
        .background(Capsule().fill(LivTheme.accentSoft))
        .accessibilityLabel("Filtered by \(label)")
    }
}

// MARK: - the self-check (pure in, pure out; no test target here)

/// `-workspace.selfcheck 1`.
///
/// WHAT IT USED TO CHECK IS GONE, on purpose. All forty-one of its
/// assertions exercised a query parser written in Swift, which was
/// retired on 2026-08-27 because it disagreed with the core's in sixteen
/// visible ways. Those semantics are pinned in Rust now
/// (`services/tests/search.rs`), where there is one answer.
///
/// This checks what the shell still owns: SPELLING a term, and rewriting
/// the text around one without disturbing the rest. It must not simply
/// shrink to nothing — an empty failure list prints PASS, and a suite that
/// checks nothing while reporting success is worse than no suite.
func livWorkspaceSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }

    // ---- spelling ----
    check("plain", LivTerms.term("area", "Work") == "area:Work")
    check("exclusion", LivTerms.term("tags", "old", exclude: true) == "-tags:old")
    // The VALUE is quoted, matching `services::search::spell`. If these two
    // ever disagree, a picker rewrites a hand-typed query the first time it
    // is touched.
    check(
        "a spaced value quotes the value",
        LivTerms.term("people", "Anna Karlsson") == "people:\"Anna Karlsson\"",
        LivTerms.term("people", "Anna Karlsson"))
    check(
        "a spaced key quotes the whole term",
        LivTerms.term("valid until", "friday") == "\"valid until:friday\"",
        LivTerms.term("valid until", "friday"))
    check(
        "an excluded spaced value keeps the minus outside the quotes",
        LivTerms.term("people", "Anna Karlsson", exclude: true)
            == "-people:\"Anna Karlsson\"",
        LivTerms.term("people", "Anna Karlsson", exclude: true))
    check("a stray quote is dropped, never doubled", LivTerms.term("a", "b\"c") == "a:bc")

    // ---- reading a value back, and rewriting ----
    func t(_ op: String, _ key: String, _ value: String, _ raw: String)
        -> BoxModel.LivQueryTerm
    {
        BoxModel.LivQueryTerm(op: op, key: key, value: value, raw: raw)
    }
    let terms = [
        t("equals", "area", "Work", "area:Work"),
        t("notequals", "tags", "old", "-tags:old"),
        t("text", "", "wibble", "wibble"),
    ]
    check("reads its own value", LivTerms.value(of: "area", in: terms) == "Work")
    check("case-insensitive on the key", LivTerms.value(of: "AREA", in: terms) == "Work")
    check("nil for a property with no equality", LivTerms.value(of: "tags", in: terms) == nil)
    check("nil for a property not there", LivTerms.value(of: "project", in: terms) == nil)

    // Replacing one row leaves every other term exactly as the core spelled
    // it — including the free text, which a picker must never eat.
    check(
        "replacing keeps the rest",
        LivTerms.setting("area", to: "Home", in: terms) == "-tags:old wibble area:Home",
        LivTerms.setting("area", to: "Home", in: terms))
    check(
        "clearing removes only its own row",
        LivTerms.setting("area", to: nil, in: terms) == "-tags:old wibble",
        LivTerms.setting("area", to: nil, in: terms))
    check(
        "clearing with blank is the same as nil",
        LivTerms.setting("area", to: "   ", in: terms) == "-tags:old wibble")
    check(
        "setting a property that was not there appends it",
        LivTerms.setting("project", to: "Roof", in: terms)
            == "area:Work -tags:old wibble project:Roof",
        LivTerms.setting("project", to: "Roof", in: terms))

    // ---- the stamp ----
    let stamps = LivTerms.stamps(terms)
    check("stamps only equalities", stamps.count == 1, "\(stamps.count)")
    check("stamps the right cell", stamps.first?.property == "area" && stamps.first?.value == "Work")
    let dupes = [
        t("equals", "area", "Work", "area:Work"),
        t("equals", "area", "Work", "area:Work"),
    ]
    check("an exact duplicate stamps once", LivTerms.stamps(dupes).count == 1)

    return failures
}
