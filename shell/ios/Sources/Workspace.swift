// liv iOS — workspaces + filters (design/ios.md, M4). The model layer:
// pure, testable, no SwiftUI in the parser.
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
// The lens runs CLIENT-SIDE against the snapshot rows the phone already
// holds — no search round-trip per surface, per keystroke, or per refresh.

import Combine
import Foundation
import SwiftUI

// MARK: - the grammar

/// One parsed token. Everything the parser does not understand becomes
/// `.ignored`: it never filters (a typo must never empty every list) and it
/// never stamps (a guess must never become a cell).
enum LivTerm: Equatable {
    /// `key:value` — the ONE stamping shape.
    case equals(property: String, value: String)
    /// `-key:value` — excludes; vacuously true where the cell is absent
    /// (the core's Op::NotEquals, same semantics).
    case notEquals(property: String, value: String)
    /// `has:key` — the property is present with a non-empty value.
    case missingNot(property: String)
    /// `no:key` — the property is absent (or empty).
    case missing(property: String)
    /// `is:archived` / `is:trashed` / `is:bookmarked` — the row's own flags.
    case flag(String)
    /// Free text, `due<20260801`, `is:nonsense`, a bare word — kept for the
    /// summary line, inert for both matching and stamping.
    case ignored(String)
}

/// A parsed workspace / filter query.
struct LivQuery: Equatable {
    let raw: String
    let terms: [LivTerm]

    static let empty = LivQuery(raw: "", terms: [])

    /// The value a picker shows for one property — the first `key:value`
    /// term naming it, or nil for "Any". Only `equals` counts: a lens
    /// built from pickers is made of the one stamping shape.
    func value(of property: String) -> String? {
        for term in terms {
            if case .equals(let p, let v) = term,
                p.compare(property, options: .caseInsensitive) == .orderedSame
            {
                return v
            }
        }
        return nil
    }

    /// Put a picked value back into the raw text, replacing whatever that
    /// property said before and leaving every other term exactly as it
    /// was typed. Editing through the pickers therefore never rewrites
    /// an advanced query someone hand-made — it only touches its own row.
    func setting(_ property: String, to value: String?) -> String {
        var kept = LivQuery.tokenize(raw).filter { token in
            guard let (key, _) = LivQuery.splitQualifier(token) else { return true }
            return key.compare(property, options: .caseInsensitive) != .orderedSame
        }
        if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
            kept.append(LivQuery.term(property, value))
        }
        return kept.joined(separator: " ")
    }

    /// `key:value`, quoted when the value has a space — the spelling the
    /// core's DSL and `parse` above both already understand.
    static func term(_ property: String, _ value: String) -> String {
        let needsQuotes = value.contains(" ") || value.contains("\"")
        let clean = value.replacingOccurrences(of: "\"", with: "")
        return needsQuotes ? "\(property):\"\(clean)\"" : "\(property):\(clean)"
    }

    /// The five understood shapes, quote-aware, in the core DSL's spelling:
    ///
    ///   key:value          equality (STAMPS)
    ///   -key:value         exclusion
    ///   has:key            presence
    ///   no:key             absence
    ///   is:flag            archived | trashed | bookmarked
    ///   key:"two words"    quoted value
    ///
    /// Anything else is `.ignored` — never a filter, never a stamp.
    static func parse(_ s: String) -> LivQuery {
        var terms: [LivTerm] = []
        for token in tokenize(s) {
            guard let (key, value) = splitQualifier(token) else {
                terms.append(.ignored(token))
                continue
            }
            switch key.lowercased() {
            case "is":
                let flag = value.lowercased()
                if ["archived", "trashed", "bookmarked"].contains(flag) {
                    terms.append(.flag(flag))
                } else {
                    terms.append(.ignored(token))  // is:working etc — inert here
                }
            case "has":
                terms.append(.missingNot(property: value))
            case "no":
                terms.append(.missing(property: value))
            default:
                if key.hasPrefix("-") {
                    let bare = String(key.dropFirst())
                    if bare.isEmpty {
                        terms.append(.ignored(token))
                    } else {
                        terms.append(.notEquals(property: bare, value: value))
                    }
                } else {
                    terms.append(.equals(property: key, value: value))
                }
            }
        }
        return LivQuery(raw: s, terms: terms)
    }

    /// The stamp: equality terms ONLY, in written order, exact duplicates
    /// dropped. Two values for one property is a contradiction the user
    /// typed — both are kept and the last write wins, exactly as `set` does.
    var stampCells: [(property: String, value: String)] {
        var out: [(property: String, value: String)] = []
        for term in terms {
            guard case .equals(let property, let value) = term else { continue }
            guard !out.contains(where: { $0.property == property && $0.value == value })
            else { continue }
            out.append((property: property, value: value))
        }
        return out
    }

    /// True when nothing in this query can filter anything out — an empty
    /// query, or one made only of tokens the parser refused to guess at.
    var isInert: Bool {
        !terms.contains { term in
            if case .ignored = term { return false }
            return true
        }
    }

    /// "stamps area:Work" — the one-line honesty hint on the new-workspace
    /// form. Empty when the query stamps nothing.
    var stampSummary: String {
        let cells = stampCells
        guard !cells.isEmpty else { return "" }
        let parts = cells.map { cell -> String in
            cell.value.contains(" ")
                ? "\(cell.property):\"\(cell.value)\"" : "\(cell.property):\(cell.value)"
        }
        return "stamps " + parts.joined(separator: " ")
    }

    /// Conjunction — a saved filter chosen inside a workspace ANDs onto it.
    func and(_ other: LivQuery) -> LivQuery {
        if other.terms.isEmpty { return self }
        if terms.isEmpty { return other }
        return LivQuery(
            raw: [raw, other.raw].filter { !$0.isEmpty }.joined(separator: " "),
            terms: terms + other.terms)
    }

    // MARK: matching (client-side, against one snapshot row)

    /// Every understood term must hold (a conjunction). Ignored terms are
    /// skipped — an unknown token shrinks nothing.
    func matches(_ row: EntityRow) -> Bool {
        for term in terms {
            switch term {
            case .equals(let property, let value):
                if !LivQuery.has(row, property, value) { return false }
            case .notEquals(let property, let value):
                if LivQuery.has(row, property, value) { return false }
            case .missingNot(let property):
                if !LivQuery.carries(row, property) { return false }
            case .missing(let property):
                if LivQuery.carries(row, property) { return false }
            case .flag(let flag):
                switch flag {
                case "archived": if row.archived != true { return false }
                case "trashed": if row.trashed != true { return false }
                case "bookmarked": if row.bookmarked != true { return false }
                default: break
                }
            case .ignored:
                continue
            }
        }
        return true
    }

    /// One cell of `property` displays as `value`. Property names and values
    /// compare case-insensitively — the phone is a typing surface, not a
    /// terminal. `type`/`status`/`name` also consult the row's flattened
    /// wire fields, which is where the snapshot puts them.
    private static func has(_ row: EntityRow, _ property: String, _ value: String) -> Bool {
        if (row.cells ?? []).contains(where: {
            same($0.property, property) && same($0.value, value)
        }) { return true }
        switch property.lowercased() {
        case "type":
            return (row.kinds ?? []).contains { same($0, value) }
        case "status":
            return same(row.status, value)
        case "name":
            return same(row.title, value)
        default:
            return false
        }
    }

    private static func carries(_ row: EntityRow, _ property: String) -> Bool {
        if (row.cells ?? []).contains(where: {
            same($0.property, property) && !($0.value ?? "").isEmpty
        }) { return true }
        switch property.lowercased() {
        case "type": return !(row.kinds ?? []).isEmpty
        case "status": return !(row.status ?? "").isEmpty
        case "name": return !(row.title ?? "").isEmpty
        default: return false
        }
    }

    private static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return a.compare(b, options: .caseInsensitive) == .orderedSame
    }

    // MARK: tokenizer (the core's, ported verbatim)

    /// A `"` toggles quoting; whitespace splits only outside quotes. So
    /// `project:"Big Thing"` is ONE token whose value keeps its space.
    static func tokenize(_ raw: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quoted = false
        for c in raw {
            if c == "\"" {
                quoted.toggle()
            } else if c.isWhitespace && !quoted {
                if !current.isEmpty { out.append(current) }
                current = ""
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Split on the FIRST colon. An empty key or value is not a qualifier —
    /// `:x`, `x:`, and a bare word all fall through to `.ignored`.
    static func splitQualifier(_ token: String) -> (String, String)? {
        guard let i = token.firstIndex(of: ":") else { return nil }
        let key = String(token[token.startIndex..<i])
        let value = String(token[token.index(after: i)...])
        if key.isEmpty || value.isEmpty { return nil }
        return (key, value)
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

    /// The lens actually applied to Today / Tasks / Search: the workspace's
    /// query ANDed with any chosen saved filter.
    var activeQuery: LivQuery {
        var q = LivQuery.parse(query(of: activeId) ?? "")
        if let f = activeFilterId,
            let raw = filters.first(where: { $0.id == f })?.query
        {
            q = q.and(LivQuery.parse(raw))
        }
        return q
    }

    /// True when some lens is on — the surfaces show the chip only then.
    var lensOn: Bool {
        activeId != 0 || activeFilterId != nil
    }

    /// What a capture made right now inherits. Filters never stamp — only a
    /// workspace does.
    var stampCells: [(property: String, value: String)] {
        LivQuery.parse(query(of: activeId) ?? "").stampCells
    }

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

    /// "stamps area:Work" for the doors that have no post-save chip strip
    /// to show it in — the promise is made before the write, not after.
    var stampHint: String {
        LivQuery.parse(query(of: activeId) ?? "").stampSummary
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

    /// One tab plane, remembered per workspace (never a second tab BAR).
    static func tabsKey(_ workspace: UInt64) -> String {
        "desk.tabs.v1.\(workspace)"
    }
}

// MARK: - the lens chip

/// The workspace you are standing in, and the door to change it. ONE
/// button, at the top centre of everything (owner, 2026-08-13): the desk,
/// full or empty, and — drawn over it — the library panel, because the
/// panel is exactly where you go to change what you are looking at and
/// watching the name vanish as you swipe in was backwards.
///
/// It used to be a row at the foot of the panel and another at the foot
/// of the New Tab page; both are gone, this is the one.
struct WorkspaceButton: View {
    @EnvironmentObject var workspaces: WorkspaceModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // One ink and one height with the glyphs either side of it,
            // so the top row reads as ONE row of controls rather than a
            // text button between two pairs of blobs.
            HStack(spacing: 7) {
                LivIcon(
                    glyph: workspaces.activeId == 0 ? .workspaces : .workspace,
                    color: LivTheme.text2, size: 18)
                Text(workspaces.activeName)
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text2)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: LivType.micro, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
            }
            .padding(.horizontal, 12)
            // Capped so a long name never reaches the doors either side.
            .frame(maxWidth: 170)
            // The doors' own height, because they are one row of
            // controls: three pieces of the same glass (owner,
            // 2026-08-17).
            .frame(height: 40)
        }
        .buttonStyle(.plain)
        .livGlass(in: Capsule())
        .contentShape(Capsule())
        .accessibilityLabel("Workspace: \(workspaces.activeName). Switch")
    }
}

/// The quiet indicator every FILTERED surface wears, so a short list is
/// never a mystery. The Inbox never shows it — the Inbox is never filtered.
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

// MARK: - the parser's self-check (pure in, pure out; no test target here)

/// Run with `simctl launch … app.liv.ios -workspace.selfcheck 1`; an empty
/// result is a pass. Same shape as `livSpanCodecSelfCheck`.
func livWorkspaceSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }
    func row(_ cells: [(String, String)], kinds: [String] = []) -> EntityRow {
        EntityRow(
            id: 1, title: "a row", kinds: kinds,
            cells: cells.map { CellRow(property: $0.0, value: $0.1) })
    }
    func stamps(_ q: LivQuery) -> String {
        q.stampCells.map { "\($0.property)=\($0.value)" }.joined(separator: ",")
    }

    let work = row([("area", "Work")])
    let home = row([("area", "Home")])
    let bare = row([])

    // 1. Equality parses, filters AND stamps.
    let eq = LivQuery.parse("area:Work")
    check("equality parses", eq.terms == [.equals(property: "area", value: "Work")],
        "\(eq.terms)")
    check("equality stamps", stamps(eq) == "area=Work", stamps(eq))
    check("equality matches", eq.matches(work))
    check("equality excludes the other value", !eq.matches(home))
    check("equality excludes the cell-less row", !eq.matches(bare))
    check("equality is case-insensitive", LivQuery.parse("Area:work").matches(work))

    // 2. `-key:value` filters but NEVER stamps.
    let neg = LivQuery.parse("-tag:old")
    check("negation parses", neg.terms == [.notEquals(property: "tag", value: "old")],
        "\(neg.terms)")
    check("negation never stamps", neg.stampCells.isEmpty, stamps(neg))
    check("negation excludes a carrier", !neg.matches(row([("tag", "old")])))
    check("negation keeps a non-carrier", neg.matches(row([("tag", "new")])))
    check("negation is vacuously true when absent", neg.matches(bare))

    // 3. Quoted values survive the space, and stamp whole.
    let quoted = LivQuery.parse("project:\"Big Thing\"")
    check("quoted parses whole",
        quoted.terms == [.equals(property: "project", value: "Big Thing")], "\(quoted.terms)")
    check("quoted stamps whole", stamps(quoted) == "project=Big Thing", stamps(quoted))
    check("quoted matches", quoted.matches(row([("project", "Big Thing")])))
    check("quoted summary re-quotes",
        quoted.stampSummary == "stamps project:\"Big Thing\"", quoted.stampSummary)

    // 4. An unknown token neither stamps nor excludes everything.
    for junk in ["wibble", "due<20260801", "is:nonsense", ":x", "x:", "-:y"] {
        let q = LivQuery.parse(junk)
        check("\(junk) never stamps", q.stampCells.isEmpty, stamps(q))
        check("\(junk) excludes nothing", q.matches(work) && q.matches(bare))
        check("\(junk) is inert", q.isInert)
    }
    // …and it does not poison the terms beside it.
    let mixed = LivQuery.parse("area:Work wibble due<20260801")
    check("mixed stamps only the equality", stamps(mixed) == "area=Work", stamps(mixed))
    check("mixed still filters", mixed.matches(work) && !mixed.matches(home))

    // 5. has: / no: filter, never stamp.
    let has = LivQuery.parse("has:project")
    check("has parses", has.terms == [.missingNot(property: "project")], "\(has.terms)")
    check("has never stamps", has.stampCells.isEmpty)
    check("has matches a carrier", has.matches(row([("project", "Viggo")])))
    check("has rejects the empty", !has.matches(row([("project", "")])))
    let no = LivQuery.parse("no:project")
    check("no parses", no.terms == [.missing(property: "project")], "\(no.terms)")
    check("no never stamps", no.stampCells.isEmpty)
    check("no matches the bare row", no.matches(bare))
    check("no rejects a carrier", !no.matches(row([("project", "Viggo")])))

    // 6. is:flag reads the row's own flags, never stamps.
    let arch = LivQuery.parse("is:archived")
    check("is:archived parses", arch.terms == [.flag("archived")], "\(arch.terms)")
    check("is:archived never stamps", arch.stampCells.isEmpty)
    check("is:archived excludes a live row", !arch.matches(work))

    // 7. Conjunction: every understood term must hold.
    let both = LivQuery.parse("area:Work -tag:old")
    check("conjunction stamps only equality", stamps(both) == "area=Work", stamps(both))
    check("conjunction keeps the clean carrier", both.matches(work))
    check("conjunction drops the excluded",
        !both.matches(row([("area", "Work"), ("tag", "old")])))
    check("conjunction drops the wrong area", !both.matches(home))

    // 8. `type:` reads the row's kinds (the wire flattens them off cells).
    let typed = LivQuery.parse("type:task")
    check("type matches a kind", typed.matches(row([], kinds: ["task"])))
    check("type rejects another kind", !typed.matches(row([], kinds: ["note"])))

    // 9. An empty query is inert and matches everything.
    let none = LivQuery.parse("   ")
    check("empty is inert", none.isInert && none.stampCells.isEmpty)
    check("empty matches everything", none.matches(work) && none.matches(bare))

    // 10. AND of two queries keeps both sides' terms; only the workspace
    //     side is ever asked for a stamp (the caller's rule, pinned here).
    let anded = LivQuery.parse("area:Work").and(LivQuery.parse("-tag:old"))
    check("and keeps both", anded.terms.count == 2, "\(anded.terms)")
    check("and matches like the written pair", anded.matches(work))

    return failures
}
