// lotus — the main window. One window, three regions: sidebar, one lens,
// inspector. Every lens swaps in place; nothing floats free. The window
// renders one JSON snapshot from the seam and never holds the box.
//
// interface.md is the law here: system materials, Apple text styles,
// lake green in exactly three jobs, the inbox count as the only badge.

import Combine
import SwiftUI

// MARK: - theme

enum Theme {
    /// The accent. Decided in interface.md 0.2: lake green.
    static let accent = Color(red: 47 / 255, green: 125 / 255, blue: 107 / 255)
    static let accentDeep = Color(red: 39 / 255, green: 100 / 255, blue: 86 / 255)
    static let accentTint = Color(red: 47 / 255, green: 125 / 255, blue: 107 / 255).opacity(0.12)
}

// MARK: - snapshot rows (mirror ffi/src/lib.rs, decoded from snake_case)

struct CellRow: Codable, Hashable {
    let propertyId: UInt64
    let property: String
    /// text/number/bool/datetime/select/reference/richtext/file — the
    /// inspector renders a control by this.
    let kind: String
    let value: String
    /// For select/reference cells, the referenced entity's id.
    let refTarget: UInt64?
}

struct OptionRow: Codable, Hashable, Identifiable {
    let id: UInt64
    let name: String
    /// P11 catalog enrichment (wire: snake_case; every field Optional —
    /// applySnapshot decodes with try?, so one missing key would silently
    /// drop the whole snapshot. Optionality is resilience, not politeness.)
    let order: Double?
    let hue: Double?
    let completes: Bool?
    let forTypes: [String]?
    var boardOrder: Double { order ?? 0 }
    var isTerminal: Bool { completes ?? false }
}

/// A property definition — the inspector's catalog entry. `id` is the
/// definition ENTITY id: the row menu writes display-attribute cells to it
/// through the ordinary set seams.
struct PropertyRow: Codable, Identifiable, Hashable {
    let id: UInt64
    let name: String
    let kind: String
    let options: [OptionRow]
    /// Live-carrier count (P11) — the add-property picker's "on N objects".
    let usage: Int?
    /// Display attributes (P11): absent when unset on the definition.
    let icon: String?
    let digitKey: String?
    let hideWhenEmpty: Bool?
    let hideOnKinds: [String]?
    let coreOnKinds: [String]?
    var carrierCount: Int { usage ?? 0 }
    /// nil defaults ON — hide-when-empty is what keeps the resting panel short.
    var hidesWhenEmpty: Bool { hideWhenEmpty ?? true }
}

struct EntityRow: Codable, Identifiable, Hashable {
    let id: UInt64
    let title: String
    let kinds: [String]
    let due: Int64?
    /// The positioning cell's span end (P11) — absent for plain dates.
    let dueEnd: Int64?
    /// The positioning property's name ("due"/"date"), absent when undated.
    let positionedBy: String?
    let dueDateOnly: Bool
    let status: String?
    let created: Int64?
    let trashed: Bool
    let bookmarked: Bool
    let archived: Bool
    /// Fingerprint of the stored content, 0 when none — the editor reads
    /// "did my base move?" off every snapshot for free.
    let contentPrint: UInt64
    let cells: [CellRow]
}

struct ProposalRow: Codable, Identifiable, Hashable {
    var id: String { "\(entity).\(fingerprint)" }
    let entity: UInt64
    let ordinal: UInt32
    /// Carried back on accept/decline: the seam refuses a stale click.
    let fingerprint: UInt64
    let reason: String
    let author: String
    /// The structured writes this proposal makes — the diff card's source
    /// (P16c). Optional per the decoder rule: a missing key must not drop the
    /// whole snapshot.
    let commands: [ProposalCommandRow]?
}

/// One command of a proposal, for the +/- diff (P16c).
struct ProposalCommandRow: Codable, Hashable {
    let kind: String  // add | trash | redirect | create | remove | restore
    let property: String?
    let value: String?
    let valueKind: String?
    let refTarget: UInt64?
}

struct OccurrenceRow: Codable, Hashable {
    let series: UInt64
    let civil: Int64
}

struct WorkspaceRow: Codable, Identifiable, Hashable {
    let id: UInt64
    let name: String
    let emoji: String?
    let favorite: Bool
    let archived: Bool
    /// "home" for the protected built-in; empty otherwise.
    let builtin: String
    /// 0 = top level; the tree is parent references, nothing else.
    let parent: UInt64
    let order: Double
}

struct Snapshot: Codable {
    let today: [UInt64]
    let unstructured: [UInt64]
    let everything: [UInt64]
    let dated: [UInt64]
    let occurrences: [OccurrenceRow]
    let inbox: [ProposalRow]
    let workspaces: [WorkspaceRow]
    /// OPTIONAL (the decoder rule): a missing key must never drop the
    /// whole snapshot.
    let pins: [PinRow]?
    /// OPTIONAL, like pins.
    let layers: [LayerRow]?
    /// The habit card (P18b) — lands dark until the widget mounts (18g).
    /// OPTIONAL: a missing key must never drop the snapshot.
    let habits: HabitsSection?
    /// Time totals + the week's entries (P18d). OPTIONAL.
    let timeEntries: TimeSection?
    /// Saved views — the filter engine's bookmarks (P18d). OPTIONAL.
    let views: [SavedViewRow]?
    /// The board's widgets, ordered (P18d). OPTIONAL.
    let widgets: [BoardWidgetRow]?
    let properties: [PropertyRow]
    let entities: [EntityRow]
}

struct TimeSection: Codable, Hashable {
    let totals: [TimeTotalRow]
    let entries: [TimeEntryWireRow]
}

struct TimeTotalRow: Codable, Hashable, Identifiable {
    var id: UInt64 { target }
    let target: UInt64
    let name: String
    let minutes: Int64
}

struct TimeEntryWireRow: Codable, Hashable, Identifiable {
    let id: UInt64
    let target: UInt64
    /// Full civil stamps (YYYYMMDDHHMM).
    let start: Int64
    let end: Int64
}

struct SavedViewRow: Codable, Hashable, Identifiable {
    let id: UInt64
    let name: String
    let query: String
}

struct BoardWidgetRow: Codable, Hashable, Identifiable {
    let id: UInt64
    let kind: String
    let workspace: UInt64
    let span: Double
    let order: Double
    let view: UInt64?
    let range: String?
}

/// The habit projection (P18b, D13): computed on read, stored nowhere.
struct HabitsSection: Codable, Hashable {
    let habits: [HabitLine]
    let streak: UInt32
    let longest: UInt32
    let weekPoints: Double
    let avgActive: Double
    /// Check-ins per day, 84 days, oldest → today.
    let heat: [UInt32]
}

struct HabitLine: Codable, Identifiable, Hashable {
    let id: UInt64
    let name: String
    let points: Double
    let cadence: String?
    /// Today's check-in row when checked — the uncheck (trash) target.
    let todayCheckIn: UInt64?
}

/// One Favourites pin (P17g): a backstage entity pointing at an object,
/// ordered by a float key.
struct PinRow: Codable, Identifiable, Hashable {
    let id: UInt64
    let target: UInt64
    let order: Double
}

/// One layout layer (P17i): a named tab-set snapshot, workspace-scoped
/// (0 = Home). Members are live ids in saved order.
struct LayerRow: Codable, Identifiable, Hashable {
    let id: UInt64
    let name: String
    let workspace: UInt64
    let members: [UInt64]
}

// MARK: - search (its own seam, its own rank order)

/// One ranked hit: a bare id (the shell already holds the entity from the
/// snapshot), a score, and where it matched.
struct SearchHit: Codable, Identifiable {
    let id: UInt64
    let score: Double
    let field: String
}

/// One facet value: how many results it *would* yield under the current
/// filter (Liv's one great idea), its rendered label, and whether the query
/// already constrains this facet to it. The raw serde Value is not decoded —
/// the shell pivots by name, not by id.
struct SearchFacetValue: Codable, Identifiable {
    let label: String
    let count: Int
    let active: Bool
    /// The query EXCLUDES this value (Op::NotEquals) — renders red +
    /// strikethrough (P13; Optional so an older wire still decodes).
    let excluded: Bool?
    var id: String { label }
    var isExcluded: Bool { excluded ?? false }
}

/// One facetable property and its candidate values, count-descending.
struct SearchFacet: Codable, Identifiable {
    let property: UInt64
    let label: String
    let values: [SearchFacetValue]
    var id: UInt64 { property }
}

/// The lotus_search_at payload — ranked hits + facet counts.
struct SearchResult: Codable {
    var hits: [SearchHit] = []
    var facets: [SearchFacet] = []
    /// The TRUE match count (bp3 a12) — `hits` is the first page, `total`
    /// the whole set, so the count line never reads a silently-capped number
    /// (Optional so an older wire still decodes).
    var total: Int? = nil

    static let empty = SearchResult()
    /// The count to show: the true total when present, else the page size.
    var matchCount: Int { total ?? hits.count }
}

/// One status option as the kind's board/picker sees it —
/// the lotus_status_options_at payload (P11.5a). A new seam with no legacy
/// payloads, so required is safe.
struct StatusOption: Codable, Identifiable, Hashable {
    let id: UInt64
    let name: String
    let order: Double
    let hue: Double?
    let completes: Bool
}

/// One value-pool row — the lotus_distinct_values_at payload (P11.5a).
struct DistinctValue: Codable, Hashable {
    let value: String
    let count: Int
}

// MARK: - the model: refresh-after-every-act, never hold the box

struct BoxFault: Codable {
    let code: String
    let message: String
}

final class BoxModel: ObservableObject {
    let path: String
    @Published var snap: Snapshot? { didSet { rebuildEntityIndex(); orphanCache = nil } }
    /// Memoized orphan set (P12) — recomputed once per snapshot, reused by
    /// the rail badge and the Inbox/Capture lenses instead of materializing
    /// the whole box on every render (the review's finding).
    private var orphanCache: [EntityRow]?
    @Published var boxBusy = false

    /// id -> row, rebuilt once when a snapshot lands. entity()/rows() are hit
    /// per-row on every surface render; a linear scan made them O(n²), which
    /// is a real share of the general sluggishness. The index makes them O(1).
    private var entityIndex: [UInt64: EntityRow] = [:]
    private var backlinkIndex: [UInt64: [UInt64]] = [:]
    private func rebuildEntityIndex() {
        let all = snap?.entities ?? []
        var idx = [UInt64: EntityRow](minimumCapacity: all.count)
        for e in all { idx[e.id] = e }
        entityIndex = idx
        // The reverse-reference index (P11.5a): target -> the entities whose
        // reference/select cells point at it — CONNECTIONS' backlinks
        // stratum, derived once per snapshot, stored nowhere.
        var back: [UInt64: [UInt64]] = [:]
        for e in all {
            var seen = Set<UInt64>()
            for cell in e.cells {
                guard let target = cell.refTarget, target != e.id else { continue }
                if seen.insert(target).inserted {
                    back[target, default: []].append(e.id)
                }
            }
        }
        backlinkIndex = back
    }

    /// Entities pointing AT `id` through any reference/select cell, sorted
    /// for stable rendering.
    func backlinks(of id: UInt64) -> [EntityRow] {
        rows((backlinkIndex[id] ?? []).sorted())
    }
    /// A box that cannot open for a reason retrying will not fix —
    /// corrupt, wrong version, io. Rendered as a blocking notice.
    @Published var fault: BoxFault?
    /// The latest search hits, in rank order. Its own seam, off the
    /// snapshot: search is query-driven and carries a rank the snapshot's
    /// section arrays cannot. `searchedFor` is the query these answered, so
    /// the results view never renders one query's hits under another.
    @Published var searchResult = SearchResult.empty
    @Published var searchedFor = ""

    /// One serial lane to the box: the app must never race its own lock.
    /// The CLI can still hold the box; that is what retry is for.
    private let boxQueue = DispatchQueue(label: "lotus.box", qos: .userInitiated)
    private var retryScheduled = false
    private var retryDelay = 0.2

    init(path: String) {
        self.path = path
    }

    func entity(_ id: UInt64?) -> EntityRow? {
        guard let id = id else { return nil }
        return entityIndex[id]
    }

    func rows(_ ids: [UInt64]) -> [EntityRow] {
        ids.compactMap { entity($0) }
    }

    /// The active occurrence window — the calendar's viewed period while it is
    /// on screen; nil means the default current month for every other surface.
    /// Held HERE (not only in the calendar's view state) so that ANY refresh —
    /// a rename, a set, an accept — reloads the window the calendar is showing
    /// instead of snapping its occurrences back to the current month. Main-
    /// thread only (set from the calendar, read at the start of refresh).
    private var occurrenceWindow: (from: Int64, to: Int64)?

    func refresh() {
        let path = self.path
        let window = self.occurrenceWindow
        boxQueue.async {
            let raw: UnsafeMutablePointer<CChar>?
            if let window = window {
                raw = lotus_snapshot_window_at(path, window.from, window.to)
            } else {
                raw = lotus_snapshot(path)
            }
            guard let raw = raw else {
                self.probeAndRetry()
                return
            }
            self.applySnapshot(raw)
        }
    }

    /// Point the shared snapshot at a caller-chosen occurrence window (the
    /// calendar's viewed month) and reload. Same snapshot; only the recurring
    /// `occurrences` follow [from, to] (civil YYYYMMDDHHMM). The window sticks
    /// across later refreshes until resetWindow().
    func snapshotWindow(from: Int64, to: Int64) {
        occurrenceWindow = (from, to)
        refresh()
    }

    /// Drop back to the default current-month window — the calendar calls this
    /// as it leaves, so no other surface is left rendering its window.
    func resetWindow() {
        occurrenceWindow = nil
        refresh()
    }

    /// Decode a snapshot JSON pointer into `snap`, on the main thread — shared
    /// by the default refresh and the calendar's windowed refresh.
    private func applySnapshot(_ raw: UnsafeMutablePointer<CChar>) {
        let json = String(cString: raw)
        lotus_string_free(raw)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snap = try? decoder.decode(Snapshot.self, from: Data(json.utf8))
        DispatchQueue.main.async {
            self.boxBusy = false
            self.fault = nil
            self.retryDelay = 0.2
            if let snap = snap { self.snap = snap }
        }
    }

    /// Search the box through its own seam (debounced by the caller). The
    /// raw DSL string is parsed in Rust — the shell never re-parses it.
    /// Publishes the ranked hits and the query they answered.
    func search(_ raw: String) {
        let path = self.path
        boxQueue.async {
            guard let ptr = lotus_search_at(path, raw) else { return }
            let json = String(cString: ptr)
            lotus_string_free(ptr)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = (try? decoder.decode(SearchResult.self, from: Data(json.utf8))) ?? .empty
            DispatchQueue.main.async {
                self.searchResult = result
                self.searchedFor = raw
            }
        }
    }

    /// The snapshot said no. Locked means retry (and mean it); anything
    /// else is a fault the user must see, not a spinner.
    private func probeAndRetry() {
        var fault: BoxFault?
        if let raw = lotus_probe(path) {
            let json = String(cString: raw)
            lotus_string_free(raw)
            fault = try? JSONDecoder().decode(BoxFault.self, from: Data(json.utf8))
        }
        DispatchQueue.main.async {
            if let fault = fault, fault.code != "locked" {
                self.fault = fault
                self.boxBusy = false
                return
            }
            self.boxBusy = true
            guard !self.retryScheduled else { return }
            self.retryScheduled = true
            let delay = self.retryDelay
            self.retryDelay = min(delay * 2, 2.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.retryScheduled = false
                self.refresh()
            }
        }
    }

    func capture(_ text: String, done: @escaping (Bool) -> Void = { _ in }) {
        act(done) { lotus_capture_at(self.path, text) != 0 }
    }

    func accept(_ proposal: ProposalRow) {
        act { lotus_accept_at(self.path, proposal.entity, proposal.ordinal, proposal.fingerprint) == 1 }
    }

    func reject(_ proposal: ProposalRow) {
        act { lotus_reject_at(self.path, proposal.entity, proposal.ordinal, proposal.fingerprint) == 1 }
    }

    /// Accept a whole group as ONE transaction, one undo (P16b) — the members'
    /// fingerprints through lotus_accept_group_at.
    func acceptGroup(_ fingerprints: [UInt64]) {
        let json = (try? String(data: JSONEncoder().encode(fingerprints), encoding: .utf8)) ?? "[]"
        act { lotus_accept_group_at(self.path, json) == 1 }
    }

    /// How many pending proposals point at this entity — the in-place ✦ halo
    /// count (P16f). Same queue, same fingerprints as Inbox › Tidy.
    func proposalCount(_ entity: UInt64) -> Int {
        (snap?.inbox ?? []).filter { $0.entity == entity }.count
    }

    func undo() {
        act { lotus_undo_at(self.path) == 1 }
    }

    // ---- pins (P17g): the ONE pin source ----

    func pin(_ target: UInt64) {
        act { lotus_pin_at(self.path, target) != 0 }
    }

    func unpin(_ target: UInt64) {
        act { lotus_unpin_at(self.path, target) == 1 }
    }

    func isPinned(_ target: UInt64) -> Bool {
        (snap?.pins ?? []).contains { $0.target == target }
    }

    /// Reorder one pin — a single set on its float `order` key (one
    /// transaction, one undo).
    func reorderPin(_ pinId: UInt64, order: Double) {
        set(pinId, property: "order", value: String(order))
    }

    // ---- layers (P17i): layout snapshots ----

    func saveLayer(name: String, workspace: UInt64, members: [UInt64]) {
        let json = (try? String(data: JSONEncoder().encode(members), encoding: .utf8)) ?? "[]"
        act { lotus_layer_save_at(self.path, name, workspace, json) != 0 }
    }

    /// The current workspace's saved layouts (0 = Home).
    func layers(for workspace: UInt64) -> [LayerRow] {
        (snap?.layers ?? []).filter { $0.workspace == workspace }
    }

    // ---- P18d: saved views + time ----

    func saveView(name: String, query: String) {
        act { lotus_create_view_at(self.path, name, query) != 0 }
    }

    /// Log a closed interval (full civil stamps) — the timer's stop writes
    /// exactly one entity.
    func logTime(target: UInt64, start: Int64, end: Int64) {
        act { lotus_log_time_at(self.path, target, start, end) != 0 }
    }

    func set(_ id: UInt64, property: String, value: String, done: @escaping (Bool) -> Void = { _ in }) {
        act(done) { lotus_set_at(self.path, id, property, value) == 1 }
    }

    // ---- the P11 spine seams (P11.5a) — thin wrappers on the box queue ----

    /// The status vocabulary offered to a kind, in board order. A read.
    func statusOptions(kind: String, done: @escaping ([StatusOption]) -> Void) {
        boxQueue.async {
            var options: [StatusOption] = []
            if let raw = lotus_status_options_at(self.path, kind) {
                let json = String(cString: raw)
                lotus_string_free(raw)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                options = (try? decoder.decode([StatusOption].self, from: Data(json.utf8))) ?? []
            }
            DispatchQueue.main.async { done(options) }
        }
    }

    /// A new status option for a kind — one commit, ordered last. hue nil = none.
    func addStatusOption(
        kind: String, name: String, hue: Double? = nil,
        done: @escaping (UInt64?) -> Void = { _ in }
    ) {
        boxQueue.async {
            let id = lotus_add_status_option_at(self.path, kind, name, hue ?? -1.0)
            DispatchQueue.main.async {
                if id == 0 { NSSound.beep() }
                done(id == 0 ? nil : id)
                self.refresh()
            }
        }
    }

    /// Layer ① of the value pool: a property's distinct live values with
    /// usage counts. A read; fetched once per editor open, never per keystroke.
    func distinctValues(property: String, done: @escaping ([DistinctValue]) -> Void) {
        boxQueue.async {
            var values: [DistinctValue] = []
            if let raw = lotus_distinct_values_at(self.path, property) {
                let json = String(cString: raw)
                lotus_string_free(raw)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                values = (try? decoder.decode([DistinctValue].self, from: Data(json.utf8))) ?? []
            }
            DispatchQueue.main.async { done(values) }
        }
    }

    /// Space-cycles a date row's role; `done` receives the NEW role name
    /// (nil on refusal — the caller shakes, nothing else changes).
    func cycleDateRole(id: UInt64, property: String, done: @escaping (String?) -> Void = { _ in }) {
        boxQueue.async {
            var next: String?
            if let raw = lotus_cycle_date_role_at(self.path, id, property) {
                next = String(cString: raw)
                lotus_string_free(raw)
            }
            DispatchQueue.main.async {
                if next == nil { NSSound.beep() }
                done(next)
                self.refresh()
            }
        }
    }

    /// One date/span write — the mirror contract's single seam (inspector
    /// row, calendar drag, span grips are all THIS). end 0 = a plain date.
    func setSpan(
        id: UInt64, property: String, start: Int64, end: Int64, dateOnly: Bool,
        done: @escaping (Bool) -> Void = { _ in }
    ) {
        act(done) {
            lotus_set_span_at(self.path, id, property, start, end, dateOnly ? 1 : 0) == 1
        }
    }

    /// One cell onto a multi-valued property — the value pool's add leg.
    func addCell(
        _ id: UInt64, property: String, value: String,
        done: @escaping (Bool) -> Void = { _ in }
    ) {
        act(done) { lotus_add_cell_at(self.path, id, property, value) == 1 }
    }

    /// Birth a property definition (P11.5g add-property create leg) — the
    /// one seam the failing test forced out of the core. nil on refusal.
    func addProperty(
        name: String, kind: String, done: @escaping (UInt64?) -> Void = { _ in }
    ) {
        boxQueue.async {
            let id = lotus_add_property_at(self.path, name, kind)
            DispatchQueue.main.async {
                if id == 0 { NSSound.beep() }
                done(id == 0 ? nil : id)
                self.refresh()
            }
        }
    }

    /// Get-or-create today's (or any day's) daily note for a workspace
    /// (P12 12a). `dateCivil` is a packed civil in the day; workspace 0 =
    /// none. Idempotent per (date, workspace) — the atomic seam.
    func openDailyNote(
        dateCivil: Int64, workspace: UInt64,
        done: @escaping (UInt64?) -> Void = { _ in }
    ) {
        boxQueue.async {
            let id = lotus_open_daily_note_at(self.path, dateCivil, workspace)
            DispatchQueue.main.async {
                if id == 0 { NSSound.beep() }
                done(id == 0 ? nil : id)
                self.refresh()
            }
        }
    }

    /// The Route/Capture orphan set (P12): content ∧ ¬type — a captured
    /// scrap that has words but no classification. `everything` already
    /// excludes working plumbing, so no definitions/types leak.
    func orphans() -> [EntityRow] {
        if let orphanCache { return orphanCache }
        let result = rows(snap?.everything ?? [])
            .filter { !$0.trashed && $0.kinds.isEmpty && $0.contentPrint != 0 }
        orphanCache = result
        return result
    }

    /// Stamp an entity's TYPE by name (P12 12d — the Inbox Route commit).
    func setType(_ id: UInt64, _ typeName: String, done: @escaping (Bool) -> Void = { _ in }) {
        act(done) { lotus_set_type_at(self.path, id, typeName) == 1 }
    }

    func createNote(_ done: @escaping (UInt64?) -> Void) {
        boxQueue.async {
            let id = lotus_create_note_at(self.path)
            DispatchQueue.main.async {
                if id == 0 { NSSound.beep() }
                done(id == 0 ? nil : id)
                self.refresh()
            }
        }
    }

    /// Create a task by hand (the Tasks quick-add) — typed and born `todo`,
    /// distinct from a capture. Returns the new id, nil on failure.
    func createTask(_ done: @escaping (UInt64?) -> Void = { _ in }) {
        boxQueue.async {
            let id = lotus_create_task_at(self.path)
            DispatchQueue.main.async {
                if id == 0 { NSSound.beep() }
                done(id == 0 ? nil : id)
                self.refresh()
            }
        }
    }

    /// Birth of an event for a clicked day/time — a create_task twin that writes
    /// a `due` at birth, so it lands on the calendar by property-based
    /// positioning. Returns the new id, nil on failure. NO default refresh: the
    /// caller (the calendar) reloads its OWN window, so creating while viewing
    /// another month never clobbers that month's occurrences with this month's.
    func createEvent(dueCivil: Int64, allDay: Bool, done: @escaping (UInt64?) -> Void = { _ in }) {
        boxQueue.async {
            let id = lotus_create_event_at(self.path, dueCivil, allDay ? 1 : 0)
            DispatchQueue.main.async {
                if id == 0 { NSSound.beep() }
                done(id == 0 ? nil : id)
            }
        }
    }

    /// Birth of a list — named at birth (you name it before adding to it).
    func createList(_ name: String, done: @escaping (UInt64?) -> Void = { _ in }) {
        boxQueue.async {
            let id = lotus_create_list_at(self.path, name)
            DispatchQueue.main.async {
                if id == 0 { NSSound.beep() }
                done(id == 0 ? nil : id)
                self.refresh()
            }
        }
    }

    /// Add / remove ONE member of a list (a `related` reference) — tagging,
    /// never a delete of the member. Idempotent (add-present / remove-absent
    /// are no-ops).
    func addMember(_ list: UInt64, _ member: UInt64, done: @escaping (Bool) -> Void = { _ in }) {
        act(done) { lotus_add_cell_at(self.path, list, "related", "#\(member)") == 1 }
    }
    func removeMember(_ list: UInt64, _ member: UInt64, done: @escaping (Bool) -> Void = { _ in }) {
        act(done) { lotus_remove_cell_at(self.path, list, "related", "#\(member)") == 1 }
    }

    /// Add a file by reference — the librarian hashes it and creates the
    /// entity; the bytes are never moved. Returns the new id, nil on failure.
    func addFile(_ filePath: String, done: @escaping (UInt64?) -> Void = { _ in }) {
        boxQueue.async {
            let id = lotus_add_file_at(self.path, filePath)
            DispatchQueue.main.async {
                if id == 0 { NSSound.beep() }
                done(id == 0 ? nil : id)
                self.refresh()
            }
        }
    }

    /// Import a batch (P15e) — one transaction, one undo. `itemsJSON` is the
    /// tagged wire array; `stampsJSON` is [[prop,target]...] (empty for now).
    /// Returns the count committed (-1 on error).
    func importBatch(
        _ itemsJSON: String, stamps stampsJSON: String = "[]",
        done: @escaping (Int) -> Void = { _ in }
    ) {
        boxQueue.async {
            let n = lotus_import_batch_at(self.path, itemsJSON, stampsJSON)
            DispatchQueue.main.async {
                if n < 0 { NSSound.beep() }
                done(Int(n))
                self.refresh()
            }
        }
    }

    /// Export a resolved id set to a folder (P15f) — copy-only, the log
    /// untouched. Returns the count written (-1 on error).
    func exportBatch(
        ids: [UInt64], groupProps: [UInt64], dest: String,
        done: @escaping (Int) -> Void = { _ in }
    ) {
        let idsJSON = (try? String(data: JSONEncoder().encode(ids), encoding: .utf8)) ?? "[]"
        let groupsJSON =
            (try? String(data: JSONEncoder().encode(groupProps), encoding: .utf8)) ?? "[]"
        boxQueue.async {
            let n = lotus_export_at(self.path, idsJSON, groupsJSON, dest)
            DispatchQueue.main.async {
                if n < 0 { NSSound.beep() }
                done(Int(n))
            }
        }
    }

    /// Re-hash a file's referenced path (on open, never a timer). A changed
    /// hash is rewritten and the snapshot refreshed; `done(true)` on a change.
    func resyncFile(_ id: UInt64, done: @escaping (Bool) -> Void = { _ in }) {
        boxQueue.async {
            let changed = lotus_resync_file_at(self.path, id) == 1
            DispatchQueue.main.async {
                if changed { self.refresh() }
                done(changed)
            }
        }
    }

    /// A file entity's extracted plain text (rung 2), from the hash-keyed
    /// cache (extracting on a miss). Empty when there's no extractable text.
    func extractedText(_ id: UInt64, done: @escaping (String) -> Void) {
        boxQueue.async {
            let text: String
            if let ptr = lotus_extracted_text_at(self.path, id) {
                text = String(cString: ptr)
                lotus_string_free(ptr)
            } else {
                text = ""
            }
            DispatchQueue.main.async { done(text) }
        }
    }

    func createWorkspace(name: String, parent: UInt64, done: @escaping (UInt64?) -> Void) {
        boxQueue.async {
            let id = lotus_create_workspace_at(self.path, name, parent)
            DispatchQueue.main.async {
                if id == 0 { NSSound.beep() }
                done(id == 0 ? nil : id)
                self.refresh()
            }
        }
    }

    func trashWorkspace(_ id: UInt64, done: @escaping (Bool) -> Void = { _ in }) {
        act(done) { lotus_trash_workspace_at(self.path, id) == 1 }
    }

    func unset(_ id: UInt64, property: String, done: @escaping (Bool) -> Void = { _ in }) {
        act(done) { lotus_unset_at(self.path, id, property) == 1 }
    }

    func trash(_ id: UInt64, done: @escaping (Bool) -> Void = { _ in }) {
        act(done) { lotus_trash_at(self.path, id) == 1 }
    }

    /// The property catalog for the inspector — by name, with each
    /// select's options.
    func properties() -> [PropertyRow] { snap?.properties ?? [] }
    func property(named name: String) -> PropertyRow? {
        snap?.properties.first { $0.name == name }
    }

    // MARK: the editor's reads and writes

    enum ContentRead {
        case doc(ContentDoc)
        /// The box opened fine; the entity is genuinely not there.
        case missing
        /// The box would not open (still locked after retries, or a
        /// fault) — says nothing about the entity.
        case unavailable
    }

    /// One entity's content, fresh from the box. A locked box retries on
    /// the caller's behalf; "missing" comes from the seam itself, read
    /// under the flock, never inferred from a failure to open.
    func content(_ id: UInt64, retries: Int = 20, done: @escaping (ContentRead) -> Void) {
        boxQueue.async {
            if let raw = lotus_content_at(self.path, id) {
                let json = String(cString: raw)
                lotus_string_free(raw)
                guard
                    let doc = try? JSONDecoder().decode(ContentDoc.self, from: Data(json.utf8))
                else {
                    DispatchQueue.main.async { done(.unavailable) }
                    return
                }
                DispatchQueue.main.async { done(doc.missing ? .missing : .doc(doc)) }
                return
            }
            DispatchQueue.main.async {
                if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.content(id, retries: retries - 1, done: done)
                    }
                } else {
                    done(.unavailable)
                }
            }
        }
    }

    enum SaveResult {
        case saved(UInt64)
        case stale
        case busy
    }

    /// The editor's save: whole content, one transaction, guarded by the
    /// base fingerprint. No beep here — autosave failure is a dot and a
    /// retry, not a noise.
    func saveContent(
        id: UInt64, spansJSON: String, base: UInt64, done: @escaping (SaveResult) -> Void
    ) {
        boxQueue.async {
            var fresh: UInt64 = 0
            let result = lotus_set_content_at(self.path, id, spansJSON, base, &fresh)
            DispatchQueue.main.async {
                switch result {
                case 1: done(.saved(fresh))
                case -1: done(.stale)
                default: done(.busy)
                }
                // No full-box refresh here. Content saving fires on every
                // autosave tick, checkpoint, and dirty tab close/switch; a
                // whole-box lotus_snapshot decode + @Published republish on
                // each was the tab-close/select lag and a drag while typing.
                // The saving editor gets its fresh fingerprint via .saved, and
                // no list/row field is derived from content (only contentPrint,
                // which the editor consumes directly) — so nothing goes stale.
                // A title change routes through renameIfNeeded, which refreshes.
            }
        }
    }

    /// Every past version of a note's content, newest first (P4/4d).
    func contentHistory(_ id: UInt64, done: @escaping ([HistoryVersion]) -> Void) {
        boxQueue.async {
            var versions: [HistoryVersion] = []
            if let raw = lotus_content_history_at(self.path, id) {
                let json = String(cString: raw)
                lotus_string_free(raw)
                versions =
                    (try? JSONDecoder().decode([HistoryVersion].self, from: Data(json.utf8))) ?? []
            }
            DispatchQueue.main.async { done(versions) }
        }
    }

    /// Restore a past version: re-read the current fingerprint, then save
    /// the old spans as a NEW version through the guarded door — the log
    /// is never rewritten, and a stale race is refused like any save.
    func restoreContent(_ id: UInt64, spans: [SpanJSON], done: @escaping (Bool) -> Void = { _ in }) {
        content(id) { read in
            guard case .doc(let doc) = read else {
                done(false)
                return
            }
            self.saveContent(id: id, spansJSON: SpanCodec.json(spans), base: doc.fingerprint) {
                result in
                if case .saved = result { done(true) } else {
                    NSSound.beep()
                    done(false)
                }
            }
        }
    }

    /// Complete any quit flush that failed: replay each journaled draft
    /// through the same fingerprinted door as every save. Success deletes
    /// the journal; stale or invalid surfaces in an open editor — a
    /// journaled draft is never silently orphaned; a genuinely busy box
    /// waits for the next launch.
    func replayDrafts(onUnresolved: @escaping (DraftFile) -> Void) {
        for draft in DraftJournal.all(box: path) {
            boxQueue.async {
                var fresh: UInt64 = 0
                let result = lotus_set_content_at(
                    self.path, draft.entity, SpanCodec.json(draft.spans), draft.base, &fresh)
                if result == 1 {
                    DispatchQueue.main.async {
                        DraftJournal.delete(box: self.path, id: draft.entity)
                        self.refresh()
                    }
                    return
                }
                if result == -1 {
                    DispatchQueue.main.async { onUnresolved(draft) }
                    return
                }
                // 0 is busy or invalid; only the probe can tell. Busy
                // keeps the journal for the next launch; anything else
                // (entity gone, box reset) must surface, not rot.
                var locked = false
                if let raw = lotus_probe(self.path) {
                    let json = String(cString: raw)
                    lotus_string_free(raw)
                    let fault = try? JSONDecoder().decode(BoxFault.self, from: Data(json.utf8))
                    locked = fault?.code == "locked"
                }
                DispatchQueue.main.async {
                    if !locked { onUnresolved(draft) }
                }
            }
        }
    }

    private func act(_ done: @escaping (Bool) -> Void = { _ in }, _ work: @escaping () -> Bool) {
        boxQueue.async {
            let ok = work()
            DispatchQueue.main.async {
                if !ok { NSSound.beep() }
                done(ok)
                self.refresh()
            }
        }
    }
}

// MARK: - civil date display (one formatter for the whole shell)

enum Civil {
    /// The core's civil dates are Gregorian by construction; the user's
    /// system calendar (Buddhist, Hebrew, Japanese…) is display-only.
    static let gregorian = Calendar(identifier: .gregorian)

    static func text(_ civil: Int64, dateOnly: Bool) -> String {
        let ymd = civil / 10_000
        let hm = civil % 10_000
        var parts = DateComponents()
        parts.year = Int(ymd / 10_000)
        parts.month = Int((ymd / 100) % 100)
        parts.day = Int(ymd % 100)
        guard let date = gregorian.date(from: parts) else { return "\(civil)" }
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.dateFormat = "EEE, MMM d"
        var out = formatter.string(from: date)
        if !dateOnly {
            out += String(format: " %02d:%02d", hm / 100, hm % 100)
        }
        return out
    }

    static var todayYMD: Int64 {
        let now = gregorian.dateComponents([.year, .month, .day], from: Date())
        return Int64((now.year ?? 1970) * 10_000 + (now.month ?? 1) * 100 + (now.day ?? 1))
    }
}

extension Notification.Name {
    static let lotusFocusSearch = Notification.Name("lotus.focusSearch")
    /// Open the palette prefilled with a query (object = the query string) —
    /// the chip-click filter (P11.5c).
    static let lotusSearchFor = Notification.Name("lotus.searchFor")
    static let lotusFocusCapture = Notification.Name("lotus.focusCapture")
    /// The File → Daily Note menu item (P12 12b) — opens today's daily note.
    static let lotusOpenDailyNote = Notification.Name("lotus.openDailyNote")
    static let lotusNewNote = Notification.Name("lotus.newNote")
    static let lotusNewTab = Notification.Name("lotus.newTab")
    static let lotusOpenStaleDraft = Notification.Name("lotus.openStaleDraft")
    /// Open the Import funnel (P15e) / Export composer (P15f) sheets — ⌘⇧I / ⌘⇧E.
    static let lotusOpenImport = Notification.Name("lotus.openImport")
    static let lotusOpenExport = Notification.Name("lotus.openExport")
    /// Jump to Inbox › Tidy (P16f): the Agents doorway + row-halo taps.
    static let lotusGoTidy = Notification.Name("lotus.goTidy")
    static let lotusSaveLayer = Notification.Name("lotus.saveLayer")
    static let lotusRestoreLayer = Notification.Name("lotus.restoreLayer")
}

// MARK: - lenses

enum Lens: String, CaseIterable, Identifiable {
    case today = "Today"
    case capture = "Capture"
    case calendar = "Calendar"
    case everything = "Everything"
    case inbox = "Inbox"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: return "sparkles"
        case .capture: return "square.and.pencil"
        case .calendar: return "calendar"
        case .everything: return "line.3.horizontal"
        case .inbox: return "tray"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .today: return "1"
        case .capture: return "2"
        case .calendar: return "3"
        case .everything: return "4"
        case .inbox: return "5"
        }
    }
}

// MARK: - the window

struct WindowChrome: View {
    @ObservedObject var model: BoxModel
    @StateObject private var chrome = ChromeModel()
    @ObservedObject private var dialogs = Dialogs.shared
    @State private var lens: Lens = .today
    @State private var query = ""
    /// The chip-click filter waiting for the palette to open (P11.5c).
    @State private var pendingSearch: String? = nil
    @State private var selection: UInt64?
    /// The editor of the active note tab, when one is active.
    @State private var editor: EditorModel?
    /// Today IS the daily note (P12 12b, D1): the id of today's daily note,
    /// hosted in `editor` on the desk's Today lens.
    @State private var dailyNoteId: UInt64?
    /// The day dailyNoteId belongs to (yyyymmdd) — so a rollover past
    /// midnight re-opens the new day's note (the review's finding).
    @State private var dailyNoteDay: Int64 = 0
    /// The working set of the active workspace, as the Notes top bar.
    @StateObject private var tabs = TabsModel()
    /// The Import funnel (P15e) — a transient sheet, its pool pure shell scratch.
    @State private var importOpen = false
    @StateObject private var importFunnel = ImportFunnelModel()
    /// The Export composer (P15f) — a transient sheet; copy-only, a projection.
    @State private var exportOpen = false
    @StateObject private var exportComposer = ExportComposerModel()
    /// The Inbox lens lives HERE, not inside InboxView, so a `.lotusGoTidy`
    /// posted from another surface (the Tasks ✦ badge, the Agents doorway)
    /// survives InboxView being mounted lazily: the window sets .tidy BEFORE
    /// navigating, and the binding delivers it whether InboxView is already up
    /// or freshly created. A notification can't reach a subscriber that doesn't
    /// exist yet — the binding can.
    @State private var inboxLens: InboxLens = .route
    /// Which left-panel view is showing — the Spaces|Vault two-tab pref, now
    /// read by the panel's own segmented control (BP-4 · P17a). Shares the key
    /// the old content-bar SidebarViewToggle wrote, so state carries over.
    @AppStorage("app.leftView.v1") private var leftViewRaw = SidebarView.tree.rawValue
    /// The pre-restore arrangement (P17i): one-step undo for a layout
    /// restore — pure shell state, cleared when the toast retires.
    @State private var layerStash: (tabs: [WorkspaceTab], activeId: UUID?)?
    @State private var layerToastVisible = false
    @State private var returnMonitor: Any?
    @State private var commandsRegistered = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        chromeStack
            .frame(minWidth: 980, minHeight: 620)
            .background(Theme.background)
            .overlay(alignment: .topTrailing) {
                if chrome.focusMode { FocusChip(chrome: chrome) }
            }
            // The top-right Spaces/files popover is retired (BP-4 · P17a): the
            // Spaces|Vault content lives in the left panel now, not a popover.
            .overlay(switcherOverlay)
            .overlay(searchOverlay)
            .overlay(faultNotice)
            .overlay(DialogHost())
            .overlay(alignment: .bottom) {
                // The layout-restore toast (P17i): the sanctioned undo pattern —
                // transient, one action, self-retiring.
                if layerToastVisible {
                    HStack(spacing: 10) {
                        Text("Layout restored").font(.system(size: 12))
                        Button("Undo") { undoLayerRestore() }
                            .buttonStyle(.link)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.popover))
                    .overlay(Capsule().strokeBorder(Theme.border))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                    .padding(.bottom, 18)
                    .transition(.opacity)
                }
            }
            .background(eventHandlers)
            .sheet(isPresented: $importOpen) {
                ImportFunnelView(
                    model: model, funnel: importFunnel,
                    dismiss: { importOpen = false },
                    onImported: { navigate(to: .inbox) })
            }
            .sheet(isPresented: $exportOpen) {
                ExportComposerView(
                    model: model, composer: exportComposer,
                    dismiss: { exportOpen = false })
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusOpenImport)) { _ in
                importFunnel.reset()  // fresh each open — no re-import of committed items
                importOpen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusOpenExport)) { _ in
                exportComposer.reset()
                exportOpen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusGoTidy)) { _ in
                inboxLens = .tidy
                navigate(to: .inbox)
            }
            .onAppear {
                model.refresh()
                installReturnMonitor()
                registerCommands()
                // Seed the history with the launch location, or the
                // first Back has nothing to return to.
                chrome.recordNav(.init(workspace: chrome.activeWorkspace, surface: chrome.surface, selection: nil))
                // An open palette (workspace switcher or search) owns the
                // keyboard, so global hotkeys don't fire behind it.
                CommandRegistry.shared.overlayActive = { chrome.switcherOpen || chrome.searchOpen }
                // A stored left+right that fit an old Notes layout must
                // not launch a tool surface into a negative center.
                chrome.reconcilePanes()
                tabs.load(workspace: chrome.activeWorkspace ?? 0)
                syncEditorToActiveTab()
            }
    }

    /// No chrome rows: the whole window is sidebar · content · inspector.
    /// (Decided divergence — the Claude-style chrome, interface.md 0.3.)
    private var chromeStack: some View {
        // BP-4 frame (P17a rev): a top band (traffic lights · workspace hub)
        // over the card row — the rail + panels are cards that sit BELOW the
        // band, not up against the lights. The window material runs behind the
        // whole thing so the cards read as floating on one face.
        VStack(spacing: 0) {
            topBand
            body3Pane
        }
        .background(SidebarMaterial().ignoresSafeArea())
        // No floating collapsed-controls: the top band's sidebar toggle + search
        // are always present, so nothing pops in from nowhere when collapsed.
    }

    /// The top band (BP-4 title/global row, P17a): traffic-light room on the
    /// left, then the workspace hub — lifted up out of the panel footer to
    /// sit ABOVE the side panels. The global tab lane joins it in 17b.
    private var topBand: some View {
        HStack(spacing: 6) {
            // Room for the traffic lights — but they vanish in fullscreen, so the
            // band would otherwise carry 64pt of dead space that shifts everything.
            Color.clear.frame(width: chrome.isFullscreen ? 0 : Theme.trafficLightSpacer - 8)
            // The ONE panel toggle — the macOS-standard sidebar chevron, always
            // in the band (collapse when open, expand when closed). No floating
            // control that pops in from nowhere, no button buried in the panel.
            bandButton("sidebar.left", "Toggle the panel") {
                chrome.leftOpen.toggle()
                chrome.persistPanes()
            }
            if !chrome.focusMode {
                WorkspaceFooter(model: model, chrome: chrome, actions: workspaceActions)
                    .fixedSize()
            }
            // Search sits right of the workspace hub (owner's call) — a quiet
            // icon, never the blueprint's full-width search-bar-as-a-button.
            bandButton("magnifyingglass", "Search (⌘O)") { chrome.searchOpen = true }
            // The note tabs live in the band's middle now (the owner's idea).
            // The lane fills from just past the search (a small gap keeps it off
            // the button) all the way to the inspector toggle, so the + is pinned
            // far right for maximum tab space; the tabs share the lane, shrinking
            // to fit as more are added.
            if chrome.surface == .notes {
                TabStrip(
                    tabs: tabs, model: model, chrome: chrome,
                    activate: { tab in activateTab(tab) },
                    close: { tab in closeTab(tab) },
                    openNew: { openBlankTab() },
                    rename: { id in renameEntity(id) })
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 12)
            } else {
                Spacer(minLength: 0)
                // The + is a constant of the band, not a Notes privilege: from
                // any surface it opens a fresh tab (openBlankTab hops to Notes
                // itself). Same far-right position the tab lane pins it to.
                bandButton("plus", "New tab (⌘T)") { openBlankTab() }
            }
            // The RIGHT panel's toggle — mirrors the left one, in the band, over
            // the inspector. One grammar for both sides; the calendar's bespoke
            // edge chevron is gone (it now rides this same chrome.rightOpen).
            if !chrome.focusMode {
                bandButton("sidebar.right", "Toggle the inspector") {
                    chrome.rightOpen.toggle()
                    chrome.persistPanes()
                }
            }
        }
        .frame(height: Theme.headerBandHeight)
        .padding(.horizontal, 8)
    }

    private func bandButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(Theme.mutedFg)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// What the non-inspector lenses look at: the selection, else the open
    /// tab's entity on Notes. The inspector keeps its own selection binding.
    private var rightFocusId: UInt64? {
        if let sel = selection { return sel }
        if chrome.surface == .notes {
            switch tabs.active?.kind {
            case .note(let id), .file(let id): return id
            default: return nil
            }
        }
        return nil
    }

    /// The lens bar (bp4: active = accent underline; ✦ Assist is amber — the
    /// one AI hue — with a live count pip).
    private var lensBar: some View {
        HStack(spacing: 2) {
            ForEach(RightLens.allCases, id: \.rawValue) { lens in
                let on = chrome.rightLens == lens
                let tint: Color = lens == .assist ? Theme.warning : Theme.accent
                Button { chrome.rightLens = lens } label: {
                    ZStack {
                        Image(systemName: lens.symbol)
                            .font(.system(size: 12.5))
                            .foregroundColor(on ? tint : Theme.mutedFg)
                        if lens == .assist {
                            let count = (model.snap?.inbox ?? [])
                                .filter { $0.entity == rightFocusId }.count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color(red: 0.22, green: 0.14, blue: 0))
                                    .padding(.horizontal, 3)
                                    .frame(minWidth: 11, minHeight: 11)
                                    .background(Capsule().fill(Theme.warning))
                                    .offset(x: 10, y: -8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if on {
                        RoundedRectangle(cornerRadius: 1).fill(tint)
                            .frame(height: 2).padding(.horizontal, 14)
                    }
                }
                .help(lens.label)
            }
        }
        .overlay(Divider(), alignment: .bottom)
    }

    /// The Spaces|Vault panel body (BP-4 · P17a): the two-tab control + the
    /// tree/vault content. The rail is now its OWN card beside this one, and
    /// the workspace hub moved up to the top band — so the panel is pure
    /// navigation, no footer.
    private var leftPanelBody: some View {
        VStack(spacing: 0) {
            leftViewTabs
            AppSidebar(
                model: model, chrome: chrome, lens: $lens, query: $query,
                selection: $selection, searchFocused: $searchFocused,
                willNavigate: { onSuccess in
                    closeEditor { ok in
                        guard ok else { return }
                        selection = nil
                        onSuccess()
                    }
                },
                openEntity: { id in openEntityTab(id) },
                showDesk: { lensValue in showDesk(lensValue) })
        }
        .frame(maxWidth: .infinity)
    }

    /// The Spaces | Vault two-tab control — a compact segmented pill, in the
    /// panel. Collapse lives in the top band's sidebar toggle now (one place,
    /// not a button buried here); no search box (⌘O owns search).
    private var leftViewTabs: some View {
        HStack(spacing: 5) {
            ForEach(SidebarView.allCases, id: \.rawValue) { v in
                let on = leftViewRaw == v.rawValue
                Button { leftViewRaw = v.rawValue } label: {
                    Text(v == .tree ? "Spaces" : "Vault")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(on ? Theme.accent : Theme.mutedFg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(on ? Theme.accent.opacity(0.12) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// The workspace switcher (§2.7.3), above the content, below the
    /// dialogs.
    @ViewBuilder
    private var switcherOverlay: some View {
        if chrome.switcherOpen {
            WorkspaceSwitcher(
                model: model, chrome: chrome, actions: workspaceActions
            ) {
                chrome.switcherOpen = false
            }
        }
    }

    /// The search palette: a centered popup (⌘F / the magnifier), reusing
    /// the core search seam. Selecting a hit opens it and closes the palette.
    @ViewBuilder
    private var searchOverlay: some View {
        if chrome.searchOpen {
            SearchPopup(
                model: model,
                open: { id in openEntityTab(id) },
                dismiss: {
                    chrome.searchOpen = false
                    pendingSearch = nil
                },
                initialQuery: pendingSearch
            )
        }
    }

    private var workspaceActions: WorkspaceActions {
        WorkspaceActions(
            model: model, chrome: chrome,
            tree: WorkspaceTree(model.snap?.workspaces ?? [])
        ) { onSuccess in
            closeEditor { ok in
                guard ok else { return }
                onSuccess()
                if chrome.surface != .notes { chrome.surface = .notes }
                query = ""
                lens = .today
            }
        }
    }

    /// The one door for surface switches: an open editor flushes before
    /// its view unmounts — a refused flush cancels the switch, exactly
    /// like a lens change. Re-selecting the active surface is a no-op,
    /// not a history entry.
    private func navigate(to target: Surface) {
        guard target != chrome.surface else { return }
        closeEditor { ok in
            guard ok else { return }
            chrome.surface = target
            chrome.recordNav(.init(workspace: chrome.activeWorkspace, surface: target, selection: nil))
        }
    }

    // ---- layers (P17i): save/restore a layout ----

    /// The layer notification seam — its own zero-size listener, off the big
    /// receiver chain (which the type-checker already strains under).
    private var layerHandlers: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .lotusSaveLayer)) { _ in
                saveLayerFlow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusRestoreLayer)) { note in
                guard let layer = note.object as? LayerRow else { return }
                restoreLayer(layer)
            }
    }

    /// Save the current arrangement as a named layer: the content tabs (in
    /// order) as ONE entity write, the pane geometry as a shell-pref blob
    /// keyed by the layer id.
    private func saveLayerFlow() {
        let members: [UInt64] = tabs.tabs.compactMap { tab in
            switch tab.kind {
            case .note(let id), .file(let id): return id
            default: return nil
            }
        }
        Dialogs.shared.prompt(
            "Save layout", placeholder: "Name", confirmLabel: "Save"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                return
            }
            model.saveLayer(
                name: name, workspace: chrome.activeWorkspace ?? 0, members: members)
            // The geometry blob rides beside the NEWEST layer once the
            // snapshot lands — keyed by name until then would race, so it
            // keys off the refreshed snapshot's row.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let layer = model.layers(for: chrome.activeWorkspace ?? 0)
                    .first(where: { $0.name == name })
                {
                    UserDefaults.standard.set(
                        [
                            "left": chrome.leftPct, "right": chrome.rightPct,
                            "leftOpen": chrome.leftOpen, "rightOpen": chrome.rightOpen,
                        ] as [String: Any],
                        forKey: "app.layer.geo.\(layer.id)")
                }
            }
        }
    }

    /// Restore a layer: replace the tab set with its live members and apply
    /// its geometry blob. MUTATES NOTHING IN THE LOG — the one-step undo is
    /// the stashed previous arrangement (the toast).
    private func restoreLayer(_ layer: LayerRow) {
        closeEditor { ok in
            guard ok else { return }
            if chrome.surface != .notes { chrome.surface = .notes }
            layerStash = (tabs.tabs, tabs.activeId)
            let set: [WorkspaceTab] = layer.members.compactMap { id in
                guard let row = model.entity(id) else { return nil }  // dangling: skip
                let isFile = row.cells.contains { $0.kind == "file" }
                return WorkspaceTab(kind: isFile ? .file(id) : .note(id))
            }
            let active = tabs.adopt(set)
            if let geo = UserDefaults.standard.dictionary(forKey: "app.layer.geo.\(layer.id)") {
                chrome.leftPct = geo["left"] as? Double ?? chrome.leftPct
                chrome.rightPct = geo["right"] as? Double ?? chrome.rightPct
                chrome.leftOpen = geo["leftOpen"] as? Bool ?? chrome.leftOpen
                chrome.rightOpen = geo["rightOpen"] as? Bool ?? chrome.rightOpen
                chrome.persistPanes()
            }
            if editor != nil {
                editor?.closed()
                editor = nil
            }
            activateTabAfterAdopt(active)
            withAnimation(.easeOut(duration: 0.15)) { layerToastVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                withAnimation(.easeOut(duration: 0.2)) { layerToastVisible = false }
            }
        }
    }

    private func activateTabAfterAdopt(_ tab: WorkspaceTab) {
        tabs.setActive(tab.id)
        syncEditorToActiveTab()
    }

    /// Put the pre-restore arrangement back (the toast's Undo) — shell
    /// state only, like the restore itself.
    private func undoLayerRestore() {
        guard let stash = layerStash else { return }
        layerStash = nil
        layerToastVisible = false
        closeEditor { ok in
            guard ok else { return }
            tabs.adopt(stash.tabs)
            if let active = stash.activeId { tabs.setActive(active) }
            if editor != nil {
                editor?.closed()
                editor = nil
            }
            syncEditorToActiveTab()
        }
    }

    /// Complete a chevron/⌥-arrow replay (P17f): restore the PLACE —
    /// workspace, then surface, then the object's tab, then selection.
    /// A trashed target is pruned from the ring and the step continues in
    /// the same direction (bounded by the ring), never a crash.
    private func performReplay(_ replay: NavReplay) {
        let entry = replay.entry
        if let id = entry.selection, model.entity(id) == nil {
            chrome.nav.pruneCurrent(forward: replay.forward)
            if replay.forward { chrome.goForward() } else { chrome.goBack() }
            return
        }
        let land = {
            chrome.nav.replay {
                if chrome.surface != entry.surface { chrome.surface = entry.surface }
            }
            if let id = entry.selection, entry.surface == .notes {
                // An object-open place: bring its tab back (browser back).
                openEntityTab(id)
            } else {
                selection = entry.selection
            }
        }
        if entry.workspace != chrome.activeWorkspace {
            closeEditor { ok in
                guard ok else { return }
                chrome.activeWorkspace = entry.workspace
                // The workspace's tab set reloads on the change; land after
                // that pass so the tab open works against the NEW set.
                DispatchQueue.main.async { land() }
            }
        } else {
            land()
        }
    }

    /// The notification seams, off the layout expression: a zero-size
    /// background that only listens.
    private var eventHandlers: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .lotusFocusSearch)) { _ in
                // ⌘F: open the centered search palette.
                if chrome.focusMode { chrome.toggleFocus() }
                pendingSearch = nil
                chrome.searchOpen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusSearchFor)) { note in
                // A chip click anywhere: the palette opens on that filter.
                if chrome.focusMode { chrome.toggleFocus() }
                pendingSearch = note.object as? String
                chrome.searchOpen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusOpenEntity)) { note in
                // CONNECTIONS' Ctrl/⌘-click: the entity opens in a tab.
                if let id = note.object as? UInt64 { openEntityTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusOpenDailyNote)) { _ in
                showDesk(.today)
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusFocusCapture)) { _ in
                closeEditor()
                chrome.surface = .notes
                query = ""
                lens = .today
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusNewNote)) { _ in
                newNoteInTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusNewTab)) { _ in
                openBlankTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusOpenStaleDraft)) { note in
                guard let draft = note.object as? DraftFile else { return }
                chrome.surface = .notes
                closeEditor { ok in
                    guard ok else { return }  // the journal file survives
                    let tab = tabs.openNote(draft.entity)
                    tabs.setActive(tab.id)
                    openEditor(id: draft.entity, adopt: draft)
                    selection = draft.entity
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusNavReplay)) { note in
                guard let replay = note.object as? NavReplay else { return }
                performReplay(replay)
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusGoHome)) { _ in
                // The Home hub surface (bp4 ⑥): the desk tab on Today — the
                // full landing, not just a surface switch (the old receiver
                // never activated the desk tab).
                showDesk(.today)
            }
            .background(layerHandlers)
            .onReceive(NotificationCenter.default.publisher(for: .lotusGoInbox)) { _ in
                navigate(to: .inbox)
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusOpenSettings)) { _ in
                CommandRegistry.shared.run("app:open-settings")
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSWindow.willEnterFullScreenNotification)
            ) { _ in
                chrome.isFullscreen = true
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSWindow.willExitFullScreenNotification)
            ) { _ in
                chrome.isFullscreen = false
            }
            .background(stateHandlers)
    }

    /// State-driven seams, split off the notification seams so neither
    /// modifier chain outgrows the SwiftUI type-checker.
    private var stateHandlers: some View {
        Color.clear
            .onChange(of: query) {
                // New results, new world: a selection from the old one
                // must not linger where Enter could open it sight unseen.
                selection = nil
            }
            .onChange(of: selection) {
                if let id = selection {
                    chrome.recordNav(.init(workspace: chrome.activeWorkspace, surface: chrome.surface, selection: id))
                }
            }
            .onReceive(model.$snap) { snap in
                // A workspace can vanish under the active scope (trashed
                // here or by the CLI): keep the scope resolvable.
                chrome.reconcileActive(snap?.workspaces ?? [])
                // A note tab whose entity vanished must not strand — drop
                // it, and follow the reactivated tab if it was active.
                let live = Set((snap?.entities ?? []).map(\.id))
                if tabs.reconcile(liveIds: live) != nil {
                    syncEditorToActiveTab()
                }
            }
            .onChange(of: chrome.activeWorkspace) {
                // Each workspace keeps its own working set. The gated
                // enter path already flushed; the ungated paths (archive/
                // trash of the active workspace, CLI reconcile) had not —
                // syncEditorToActiveTab retires the editor safely either
                // way, so the draft is never dropped.
                tabs.load(workspace: chrome.activeWorkspace ?? 0)
                syncEditorToActiveTab()
            }
    }

    /// sidebar · content · inspector. The sidebar is persistent across
    /// every surface (nav lives in it); it hides only on manual collapse
    /// or focus mode. The divider resizes width but no longer collapses
    /// by drag — that is the header button's job now.
    private var body3Pane: some View {
        GeometryReader { geo in
            let total = geo.size.width
            HStack(spacing: 0) {
                // The rail is PINNED (17b): always present outside the collapse,
                // its own fixed card — only the Spaces|Vault panel hides with
                // chrome.leftOpen. Focus mode is the one thing that clears it.
                if !chrome.focusMode {
                    LeftRail(chrome: chrome, model: model) { target in navigate(to: target) }
                        .background(Theme.panel)
                        .panelCard()
                    if chrome.leftOpen {
                        leftPanelBody
                            // leftPct still means the whole left region, so the
                            // panel is that minus the rail's fixed footprint —
                            // the persisted value keeps its old meaning.
                            .frame(width: max(total * chrome.leftPct / 100 - 52, 150))
                            .background(Theme.panel)
                            .panelCard()
                            .padding(.leading, 8)
                        PaneDivider(
                            pct: $chrome.leftPct, total: total,
                            minPct: 16, maxPct: chrome.leftLiveMax, leadingEdge: true,
                            collapsible: false
                        ) { chrome.persistPanes() }
                    } else {
                        Color.clear.frame(width: 8)
                    }
                }
                center
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // The middle is the bare face — NO fill of its own. The window
                    // material (body3Pane's SidebarMaterial) shows straight through,
                    // and only the side panels (sidebar + inspector) are cards on it.
                // The right divider outlives its panel: a drag-collapsed
                // inspector must stay reopenable by mouse (§1.5).
                if !chrome.focusMode {
                    PaneDivider(
                        pct: $chrome.rightPct, open: $chrome.rightOpen, total: total,
                        minPct: 10, maxPct: chrome.rightLiveMax, leadingEdge: false
                    ) { chrome.persistPanes() }
                }
                // ONE right card for every surface — same width, same toggle,
                // same shape. On the Calendar with nothing selected its content
                // is the day panel; any selection swaps in the same InspectorPane
                // as everywhere else. Content swaps INSIDE the constant-width
                // card, so selection never reflows the grid (the double-tap
                // guarantee, now structural).
                if chrome.rightOpen && !chrome.focusMode {
                    VStack(spacing: 0) {
                        // The five-lens bar (bp4 · P17; Graph waits for P18 —
                        // no dead buttons). Hidden while the calendar's day
                        // panel owns the card.
                        if !(chrome.surface == .calendar && selection == nil) {
                            lensBar
                        }
                        Group {
                            if chrome.surface == .calendar && selection == nil {
                                CalendarDayPanel(
                                    model: model, selection: $selection,
                                    day: chrome.calendarDay,
                                    open: { id in openEntityTab(id) },
                                    openDaily: { day in openDailyNote(forDay: day) })
                            } else {
                                switch chrome.rightLens {
                                case .metadata:
                                    InspectorPane(model: model, selection: $selection, topPadding: 0)
                                case .assist:
                                    AssistLensPane(model: model, focus: rightFocusId)
                                case .outline:
                                    OutlineLensPane(editor: editor)
                                case .history:
                                    HistoryLensPane(model: model, focus: rightFocusId)
                                case .graph:
                                    GraphLensPane(
                                        model: model, focus: rightFocusId,
                                        select: { id in selection = id },
                                        searchFor: { q in
                                            NotificationCenter.default.post(
                                                name: .lotusSearchFor, object: q)
                                        })
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(Theme.panel)
                    .frame(width: max(total * chrome.rightPct / 100, 0))
                    .panelCard()
                }
            }
            .coordinateSpace(name: "chrome.body")
            // The cards float on the material below the top band: an outer inset
            // all round (the lights live in the band now, not on the sidebar) +
            // a small top gap so nothing rides up against the band.
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var center: some View {
        Group {
            switch chrome.surface {
            case .notes:
                notesBody
            case .tasks:
                TasksView(
                    model: model, selection: $selection,
                    open: { id in openEntityTab(id) })
            case .lists:
                ListsSurface(
                    model: model, selection: $selection,
                    open: { id in openEntityTab(id) })
            case .inbox:
                InboxView(
                    model: model, selection: $selection,
                    lens: $inboxLens,
                    open: { id in openEntityTab(id) })
            case .calendar:
                CalendarView(
                    model: model, selection: $selection,
                    selectedDay: $chrome.calendarDay,
                    open: { id in openEntityTab(id) },
                    openDaily: { day in openDailyNote(forDay: day) })
                    // No leadingInset: the traffic lights + toggles live in the
                    // top band now, so nothing floats over the calendar's corner.
            case .library:
                LibraryView(
                    model: model, selection: $selection,
                    addFile: { addFileFlow() },
                    open: { id in openEntityTab(id) })
            case .contacts:
                ContactsView(
                    model: model, selection: $selection,
                    open: { id in openEntityTab(id) })
            default:
                ExtensionStub(surface: chrome.surface)
            }
        }
        .id(chrome.surface)
    }

    /// The Notes surface: the tab strip over the active tab's content.
    private var notesBody: some View {
        // The tabs moved UP to the top band (P17) — the midsection is just the
        // active tab's content now, no strip of its own.
        activeTabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch tabs.active?.kind {
        case .note:
            if let editing = editor {
                EditorView(model: editing).id(editing.id)
            } else {
                // Between flush and the fresh EditorModel: nothing to lose.
                Color.clear
            }
        case .file(let id):
            BaseFileView(model: model, id: id)
        case .blank:
            BlankTabLanding(
                createNote: { NotificationCenter.default.post(name: .lotusNewNote, object: nil) },
                search: { chrome.searchOpen = true })
        default:  // .desk (or an unset tab, treated as the desk)
            deskContent
        }
    }

    @ViewBuilder
    private var deskContent: some View {
        // The desk shows Everything (the full list) or, on the Today lens,
        // today's daily note itself (D1: "Today IS the daily note").
        switch lens {
        case .everything:
            EverythingView(model: model, selection: $selection)
        case .capture:
            QuickCaptureView(model: model, selection: $selection) {
                navigate(to: .inbox)
            }
        default:
            dailyNoteDesk
        }
    }

    /// The Today lens (D1): today's daily note, hosted in the window editor
    /// so it rides the exact same flush machinery as any note tab — every
    /// navigation exit already flushes `editor`. Get-or-created on appear
    /// and on a workspace switch (each workspace has its own today, D3).
    @ViewBuilder
    private var dailyNoteDesk: some View {
        Group {
            if let editor, editor.id == dailyNoteId {
                EditorView(model: editor).id(editor.id)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { ensureDailyNote() }
        .onChange(of: chrome.activeWorkspace) { ensureDailyNote() }
        // The first snapshot is what resolves nil-workspace → Home; until it
        // lands, ensureDailyNote defers, so the note is never born global-
        // then-reborn Home (the duplication the review's high describes).
        .onChange(of: model.snap != nil) { ensureDailyNote() }
        // A rollover past midnight re-opens the new day's note; the day
        // guard makes the tick a no-op within one day (no box churn).
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            if Civil.todayYMD != dailyNoteDay { ensureDailyNote() }
        }
    }

    /// The active workspace as a concrete id — nil resolves to the built-in
    /// Home so the daily-note seam never uses its workspace-less global
    /// bucket, which would duplicate across the nil<->Home boundary (the
    /// review's high).
    private func activeWorkspaceId() -> UInt64 {
        if let ws = chrome.activeWorkspace { return ws }
        return (model.snap?.workspaces.first { $0.builtin == "home" }?.id) ?? 0
    }

    /// Open (or create) a SPECIFIC day's daily note as a note tab (P14h —
    /// the calendar's daily-note doorway). Reuses the P12 seam + the active-
    /// workspace resolution; the note opens through the ordinary tab path.
    private func openDailyNote(forDay dayYMD: Int64) {
        model.openDailyNote(dateCivil: dayYMD * 10_000, workspace: activeWorkspaceId()) { id in
            if let id { openNoteTab(id) }
        }
    }

    private func ensureDailyNote() {
        // Defer until the first snapshot: it is what resolves a nil active
        // workspace to Home. Creating before it lands would use the global
        // (workspace-less) bucket, then re-create Home-scoped when snap
        // arrives — two notes for one day (the review's high).
        guard model.snap != nil else { return }
        let civil = Civil.todayYMD * 10_000
        dailyNoteDay = Civil.todayYMD
        let workspace = activeWorkspaceId()
        model.openDailyNote(dateCivil: civil, workspace: workspace) { id in
            guard let id else { return }
            dailyNoteId = id
            if editor?.id != id {
                // Retire whatever the editor last held (flushing it), then
                // host today's note — openEditor is guarded on editor == nil.
                retireEditor { openEditor(id: id) }
            }
        }
    }

    // MARK: tab orchestration (flush-gated, like every nav)

    /// Switch tabs: flush the current editor first; a refused flush
    /// cancels the switch. On success, activate and sync the editor to
    /// the new active tab.
    private func activateTab(_ tab: WorkspaceTab) {
        guard tabs.activeId != tab.id else { return }
        closeEditor { ok in
            guard ok else { return }
            tabs.setActive(tab.id)
            syncEditorToActiveTab()
        }
    }

    /// Tear the editor down without losing words: flush its draft, or
    /// journal it if the flush is refused (the box gone, stale, or the
    /// note trashed under it). The ungated paths — a note trashed by
    /// the CLI, an externally-changed active workspace — go through here
    /// so no teardown ever drops a dirty draft.
    private func retireEditor(_ done: @escaping () -> Void) {
        guard let leaving = editor else {
            done()
            return
        }
        leaving.flushForQuit {
            leaving.closed()
            if editor === leaving { editor = nil }
            done()
        }
    }

    /// The editor follows the active tab. Callers pre-flush (closeEditor
    /// or retireEditor) so the editor is already nil or clean here; the
    /// note branch opens the active note, anything else stays empty.
    private func syncEditorToActiveTab() {
        if case .note(let id) = tabs.active?.kind {
            if editor?.id != id {
                retireEditor {
                    openEditor(id: id)
                    selection = id
                }
            } else {
                selection = id
            }
        } else if case .desk? = tabs.active?.kind, lens == .today {
            // The desk's Today lens legitimately hosts today's daily note in
            // `editor`; re-ensure instead of retiring, so closing a sibling
            // tab (or any non-.note sync) never blanks Today (the review).
            ensureDailyNote()
        } else {
            retireEditor {}
        }
    }

    /// Open (or focus) a note in a tab — the dedup door for Enter, the
    /// sidebar, and deep links.
    private func openNoteTab(_ id: UInt64, bornBlank: Bool = false) {
        closeEditor { ok in
            guard ok else { return }
            if chrome.surface != .notes { chrome.surface = .notes }
            let tab = tabs.openNote(id)
            tabs.setActive(tab.id)
            if editor?.id != id {
                openEditor(id: id, bornBlank: bornBlank)
            }
            selection = id
        }
    }

    /// Open (or focus) a FILE entity in a read-only file tab — never the
    /// editor (read-only-by-decision). Flush-gated like every tab switch.
    private func openFileTab(_ id: UInt64) {
        closeEditor { ok in
            guard ok else { return }
            if chrome.surface != .notes { chrome.surface = .notes }
            let tab = tabs.openFile(id)
            tabs.setActive(tab.id)
            if editor != nil { editor?.closed(); editor = nil }
            selection = id
        }
    }

    /// The one open door: a file entity (one carrying a `file` cell) opens
    /// read-only in a file tab; everything else opens in the editor.
    private func openEntityTab(_ id: UInt64) {
        if model.entity(id)?.cells.contains(where: { $0.kind == "file" }) == true {
            openFileTab(id)
        } else {
            openNoteTab(id)
        }
    }

    /// Add a file by reference: pick it, the librarian hashes it (never
    /// copies), then open it read-only. The one place a file enters lotus.
    private func addFileFlow() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Add a file by reference — lotus links it, never copies or moves it."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.addFile(url.path) { id in
                if let id { openFileTab(id) }
            }
        }
    }

    /// New note: flush the current draft, mint the note, and land it in
    /// the active blank tab if there is one, else a fresh tab. A refused
    /// flush cancels the birth.
    private func newNoteInTab() {
        if chrome.surface != .notes { chrome.surface = .notes }
        let blankTarget: UUID? = (tabs.active?.kind == .blank) ? tabs.active?.id : nil
        closeEditor { ok in
            guard ok else { return }
            model.createNote { newId in
                guard let newId = newId else { return }
                let tabId: UUID
                if let blankTarget = blankTarget {
                    tabs.convert(blankTarget, to: .note(newId))
                    tabId = blankTarget
                } else {
                    tabId = tabs.openNote(newId).id
                }
                tabs.setActive(tabId)
                // createNote round-tripped the box; the user may have
                // opened another note tab meanwhile. Retire whatever
                // editor is live before opening the newborn, or its
                // openEditor(guard editor==nil) would silently no-op and
                // leave a note tab with no editor.
                retireEditor {
                    openEditor(id: newId, bornBlank: true)
                    selection = newId
                }
            }
        }
    }

    /// The desk lens buttons: flush, land on the desk tab (minting one
    /// if the user closed it), set the lens.
    private func showDesk(_ lensValue: Lens, clearQuery: Bool = true) {
        closeEditor { ok in
            guard ok else { return }
            if chrome.surface != .notes { chrome.surface = .notes }
            let desk = tabs.openDesk()
            tabs.setActive(desk.id)
            if editor != nil { editor?.closed(); editor = nil }
            if clearQuery { query = "" }
            lens = lensValue
            selection = nil
            // Re-entering Today while already on it won't re-fire the lens's
            // onAppear, and closeEditor just nilled `editor` — so reopen the
            // daily note explicitly, else Today goes blank (the review's high).
            if lensValue == .today { ensureDailyNote() }
        }
    }


    private func openBlankTab() {
        closeEditor { ok in
            guard ok else { return }
            if chrome.surface != .notes { chrome.surface = .notes }
            let tab = tabs.openBlank()
            tabs.setActive(tab.id)
            if editor != nil { editor?.closed(); editor = nil }
        }
    }

    /// Close a tab (its editor flushed first if it is the active note),
    /// then follow the tab that close() activated in its place.
    private func closeTab(_ tab: WorkspaceTab) {
        let finish = {
            tabs.close(tab.id)
            syncEditorToActiveTab()
        }
        if tab.id == tabs.activeId, case .note = tab.kind {
            closeEditor { ok in
                guard ok else { return }
                finish()
            }
        } else {
            finish()
        }
    }

    private func renameEntity(_ id: UInt64) {
        let current = model.entity(id)?.title ?? ""
        Dialogs.shared.prompt(
            "Rename note", initial: current, confirmLabel: "Rename"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                return
            }
            model.set(id, property: "name", value: name)
        }
    }

    /// The P1 slice of the registry: what exists, bound to Liv's map
    /// (§2.28.3). Surfaces to come register their own rows.
    private func registerCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let registry = CommandRegistry.shared
        registry.register(
            CommandDef(
                id: "switcher:open", label: "Quick switcher", scope: .global,
                category: "Navigate", binding: Hotkey(modifiers: [.mod], key: "o")
            ) {
                // The interim search field lives in the sidebar, which
                // focus mode hides: search exits focus first.
                if chrome.focusMode { chrome.toggleFocus() }
                NotificationCenter.default.post(name: .lotusFocusSearch, object: nil)
            })
        registry.register(
            // ⌘F is the CANONICAL search-palette chord (P13, owner-confirmed:
            // the blessed native-Find law, interface.md 0.5); ⌘O above stays
            // the alias (the shipped code + bp3's Ctrl+O). Both open the one
            // palette — no chord means two things.
            CommandDef(
                id: "search:open", label: "Search", scope: .global,
                category: "Navigate", binding: Hotkey(modifiers: [.mod], key: "f")
            ) {
                if chrome.focusMode { chrome.toggleFocus() }
                NotificationCenter.default.post(name: .lotusFocusSearch, object: nil)
            })
        registry.register(
            CommandDef(
                id: "app:toggle-left-sidebar", label: "Toggle left sidebar", scope: .global,
                category: "View", binding: Hotkey(modifiers: [.mod, .shift], key: "`"),
                enabled: { !chrome.focusMode }  // or the stash restores a lie
            ) {
                chrome.leftOpen.toggle()
                chrome.persistPanes()
            })
        registry.register(
            CommandDef(
                id: "app:toggle-right-sidebar", label: "Toggle right sidebar", scope: .global,
                category: "View", binding: Hotkey(modifiers: [.mod, .shift], key: "'"),
                enabled: { !chrome.focusMode }
            ) {
                chrome.rightOpen.toggle()
                chrome.persistPanes()
            })
        registry.register(
            CommandDef(
                id: "workspace:switch", label: "Workspace switcher", scope: .global,
                category: "Navigate", binding: Hotkey(modifiers: [.mod, .shift], key: "o")
            ) {
                if chrome.focusMode { chrome.toggleFocus() }
                chrome.switcherOpen = true
            })
        registry.register(
            CommandDef(
                id: "file:add", label: "Add file…", scope: .global,
                category: "File", binding: nil  // ⌘⇧I now opens Import (the umbrella); Add file lives on the Library button + palette
            ) {
                addFileFlow()
            })
        registry.register(
            CommandDef(
                id: "import:open", label: "Import…", scope: .global,
                category: "File", binding: Hotkey(modifiers: [.mod, .shift], key: "i")
            ) {
                NotificationCenter.default.post(name: .lotusOpenImport, object: nil)
            })
        registry.register(
            CommandDef(
                id: "export:open", label: "Export…", scope: .global,
                category: "File", binding: Hotkey(modifiers: [.mod, .shift], key: "e")
            ) {
                NotificationCenter.default.post(name: .lotusOpenExport, object: nil)
            })
        registry.register(
            CommandDef(
                id: "tab:new", label: "New tab", scope: .global,
                category: "Navigate", binding: Hotkey(modifiers: [.mod], key: "t")
            ) {
                NotificationCenter.default.post(name: .lotusNewTab, object: nil)
            })
        registry.register(
            CommandDef(
                id: "object:toggle-bookmark", label: "Pin to Favourites", scope: .global,
                category: "Object", binding: Hotkey(modifiers: [.mod, .shift], key: "b"),
                enabled: { selection != nil }
            ) {
                guard let id = selection else { return }
                // ⌘⇧B = pin/unpin (P17g) — the same one pin source the
                // inspector's 🔖 and Spaces › Favourites use.
                if model.isPinned(id) { model.unpin(id) } else { model.pin(id) }
            })
        registry.register(
            CommandDef(
                id: "workspace:new-tab", label: "New tab", scope: .global,
                category: "Tabs", binding: Hotkey(modifiers: [.mod], key: "t"),
                enabled: { chrome.surface == .notes }
            ) {
                openBlankTab()
            })
        registry.register(
            CommandDef(
                id: "workspace:close", label: "Close tab", scope: .global,
                category: "Tabs", binding: Hotkey(modifiers: [.mod], key: "w"),
                enabled: { chrome.surface == .notes }
            ) {
                if let active = tabs.active { closeTab(active) }
            })
        registry.register(
            CommandDef(
                id: "workspace:reopen-tab", label: "Reopen closed tab", scope: .global,
                category: "Tabs", binding: Hotkey(modifiers: [.mod, .shift], key: "t"),
                enabled: { chrome.surface == .notes && !tabs.closed.isEmpty }
            ) {
                if let tab = tabs.reopen() { activateTab(tab) }
            })
        registry.register(
            CommandDef(
                id: "lotus:undo-last-change", label: "Undo last change", scope: .global,
                category: "Edit", binding: Hotkey(modifiers: [.mod, .alt], key: "z")
            ) {
                // The box's undo, reachable whatever has focus — the
                // modified chord passes the text-focus suppression.
                if let active = EditorRegistry.shared.active {
                    active.flushThenBoxUndo()
                } else {
                    model.undo()
                }
            })
        registry.register(
            CommandDef(
                id: "app:toggle-focus", label: "Focus mode", scope: .global,
                category: "View", binding: Hotkey(modifiers: [.mod], key: ".")
            ) {
                chrome.toggleFocus()
            })
        registry.register(
            CommandDef(
                id: "app:open-settings", label: "Settings", scope: .global,
                category: "App", binding: Hotkey(modifiers: [.mod], key: ",")
            ) {
                Dialogs.shared.alert(
                    "Settings", message: "Settings panels arrive with their surfaces.")
            })
        registry.register(
            CommandDef(
                id: "file-explorer:new-file", label: "New note", scope: .global,
                category: "File", binding: Hotkey(modifiers: [.mod], key: "n")
            ) {
                NotificationCenter.default.post(name: .lotusNewNote, object: nil)
            })
        registry.register(
            CommandDef(
                // ⌘[ — Alt+←/→ went to the inspector (bp1 badge 32:
                // panel/doc focus; the blueprint outranks the Liv chord).
                id: "nav:back", label: "Back", scope: .global, category: "Navigate",
                binding: Hotkey(modifiers: [.mod], key: "[")
            ) {
                chrome.goBack()
            })
        registry.register(
            CommandDef(
                id: "nav:forward", label: "Forward", scope: .global, category: "Navigate",
                binding: Hotkey(modifiers: [.mod], key: "]")
            ) {
                chrome.goForward()
            })
        registry.register(
            // Today IS the daily note (P12 12b, D2): ⌘⌥D lands on the Today
            // lens, which get-or-creates and opens today's note. (bp9 cited
            // Ctrl+D; the owner chose the shipped-Liv ⌘⌥D chord — verified
            // free: ⌘[ /⌘] are nav history, Alt+←/→ are inspector focus.)
            CommandDef(
                id: "daily:open-today", label: "Open today\u{2019}s daily note",
                scope: .global, category: "Navigate",
                binding: Hotkey(modifiers: [.mod, .alt], key: "d")
            ) {
                showDesk(.today)
            })
        registry.register(
            CommandDef(
                id: "app:exit-focus", label: "Exit focus mode", scope: .global,
                category: "View", binding: Hotkey(modifiers: [], key: "Escape"),
                enabled: { Dialogs.shared.current == nil && chrome.focusMode && editor == nil }
            ) {
                chrome.toggleFocus()
            })
        CommandRegistry.shared.install()
    }

    // MARK: the editor's door

    /// Enter opens the selected row — but never steals Return from a
    /// focused text field or the editor itself.
    private func installReturnMonitor() {
        guard returnMonitor == nil else { return }
        returnMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 36,
                event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                Dialogs.shared.current == nil,  // a dialog owns Return
                !chrome.switcherOpen,  // so does the switcher
                !InspectorFocus.shared.active,  // a focused inspector owns ⏎ (its 'edit')
                chrome.surface == .notes,
                editor == nil,
                let id = selection,
                model.entity(id) != nil
            else { return event }
            if let responder = NSApp.keyWindow?.firstResponder,
                responder is NSTextView || responder is NSText
            {
                return event
            }
            openEntityTab(id)
            return nil
        }
    }

    /// Never over a live editor: every opener goes through closeEditor's
    /// gate first, so a dirty draft can never be replaced unsaved.
    private func openEditor(id: UInt64, bornBlank: Bool = false, adopt: DraftFile? = nil) {
        guard editor == nil else {
            NSSound.beep()
            return
        }
        let opened = EditorModel(box: model, id: id, bornBlank: bornBlank)
        if let draft = adopt {
            opened.adopt(draft)
        }
        opened.onSelect = { target in selection = target }
        opened.onCloseRequest = { closeEditor() }
        editor = opened
        selection = id
    }

    /// Closing flushes first; no path drops a dirty draft. A refused
    /// flush leaves the editor open with its banner or busy dot — the
    /// pending navigation lands the moment the draft is safe. The
    /// continuation runs with `true` only once the editor is gone.
    private func closeEditor(then: @escaping (Bool) -> Void = { _ in }) {
        guard let closing = editor else {
            then(true)
            return
        }
        if closing.missing {
            // The banner said so: closing a gone note resolves its
            // draft — journaled while it still holds unseen words,
            // discarded once they have been shown.
            closing.resolveMissingClose()
            closing.closed()
            editor = nil
            then(true)
            return
        }
        // The typed title goes with the words: the view is torn down
        // before any focus-change callback could commit it.
        closing.renameIfNeeded()
        closing.flush { outcome in
            switch outcome {
            case .clean, .saved:
                closing.closed()
                if editor === closing {
                    editor = nil
                    selection = closing.id
                }
                then(true)
            case .stale, .busy, .invalid:
                NSSound.beep()
                then(false)
            }
        }
    }

    /// Corrupt / wrong-version / io: a truth the user must see, blocking,
    /// with the Rust diagnostic verbatim. Locked never lands here.
    @ViewBuilder
    private var faultNotice: some View {
        if let fault = model.fault {
            VStack(spacing: 10) {
                Text("The box cannot open")
                    .font(.system(size: 16, weight: .semibold))
                Text(fault.message)
                    .font(.system(size: 13).monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 12).fill(.thickMaterial))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.25))
        }
    }

}

// MARK: - sidebar material

/// The native sidebar material, since SwiftUI alone won't hand it to us
/// inside a plain NSWindow.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    /// A pane rendered as a rounded, layered card (Calendar / Claude style): a
    /// continuous-radius clip + a hairline edge, so an opaque pane reads as
    /// floating on the window material showing through the gaps between panes.
    @ViewBuilder
    func panelCard(if enabled: Bool = true) -> some View {
        if enabled {
            clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.border.opacity(0.55), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
        } else {
            self
        }
    }
}

// MARK: - shared lens scaffolding

struct LensHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 21, weight: .bold))
            Spacer()
            Text(subtitle).font(.system(size: 13)).foregroundColor(.secondary)
        }
        .padding(.bottom, 18)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.5)
            .foregroundColor(.secondary)
            .padding(.bottom, 6)
    }
}

struct EntityLine: View {
    let row: EntityRow
    var showWhen = true
    var selected = false
    /// Opt-in: when set, the checkbox is a live button that toggles the
    /// task (Tasks surface). nil keeps the old static glyph, so Today and
    /// Library are unchanged.
    var toggle: (() -> Void)? = nil
    /// Opt-in trailing accessory (the Tasks priority flag), left of the due.
    var accessory: AnyView? = nil
    var select: () -> Void = {}

    private var isTask: Bool { row.kinds.contains("task") || row.status != nil }

    var body: some View {
        // Done-state visuals only when interactive (the Tasks surface); the
        // static glyph in Today / Library is left exactly as it was.
        let showDone = toggle != nil && row.status == "done"
        // The row is NOT an outer Button — a Button/Menu nested in a Button
        // never gets the tap on macOS (the outer one swallows it). Row-select
        // is a tap gesture on the background, so the checkbox button and the
        // priority menu each capture their own taps.
        return HStack(spacing: 12) {
            if let toggle {
                Button(action: toggle) { checkbox(filled: showDone) }
                    .buttonStyle(.plain)
            } else if isTask {
                checkbox(filled: false)
            }
            Text(row.title)
                .font(.system(size: 14))
                .lineLimit(1)
                .foregroundColor(showDone ? .secondary : .primary)
                .strikethrough(showDone, color: .secondary)
            Spacer()
            if let accessory { accessory }
            if showWhen, let due = row.due {
                Text(Civil.text(due, dateOnly: row.dueDateOnly))
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accentTint : .clear))
        .overlay(Divider(), alignment: .bottom)
    }

    private func checkbox(filled: Bool) -> some View {
        Group {
            if filled {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.accent)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Quick Capture (P12 12c) — the wall of orphan captures (a desk lens)

/// bp5 panel A, reconciled to the lotus IA: the take box writes a bare scrap
/// through `lotus_capture_at` (capture asks nothing, never blocks — the
/// silent workspace-stamp is REFUSED, design delta a4), and the wall is the
/// debut mount of the BP-7 V2 `ObjectCard` over the client-side orphan set
/// (content ∧ ¬type). The global ⌃⌥Space popup is the other doorway; this
/// lens is where you browse and route what you have not typed yet.
struct QuickCaptureView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    var openInbox: () -> Void = {}

    @State private var draft = ""
    @FocusState private var captureFocused: Bool

    /// content ∧ ¬type (§3.2): a scrap has content and no classification.
    /// `everything`/`entities[]` already exclude working plumbing, so no
    /// definitions or types leak into the wall.
    private var orphans: [EntityRow] { model.orphans() }

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 11)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LensHeader(
                    title: "Capture",
                    subtitle: orphans.isEmpty
                        ? "nothing unrouted"
                        : "\(orphans.count) unrouted")

                takeBox

                if orphans.isEmpty {
                    Text("Nothing waiting. Jot a thought above, or from anywhere with ⌃⌥Space.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 11) {
                        ForEach(orphans) { row in
                            ObjectCard(
                                row: row,
                                chips: anchorChip(for: row).map { [$0] } ?? []
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selection == row.id ? Theme.accentTint : Color.clear))
                            .contentShape(Rectangle())
                            .onTapGesture { selection = row.id }
                        }
                    }
                    HStack(spacing: 4) {
                        Text("\(orphans.count) unrouted —")
                            .foregroundColor(.secondary)
                        Button("open the Inbox to route") { openInbox() }
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.accent)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 13))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The frictionless take box: text → bare scrap, clears only on a
    /// log-confirmed save (never lose a thought), focus stays put so five
    /// captures land in a row (bp5 a1/a7).
    private var takeBox: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            TextField("Capture a thought…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($captureFocused)
                .onSubmit { commit() }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
        .onReceive(NotificationCenter.default.publisher(for: .lotusFocusCapture)) { _ in
            captureFocused = true
        }
    }

    private func commit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.capture(text) { ok in if ok { draft = "" } }
    }
}

// MARK: - Contacts (P14i)

/// bp9's thin Contacts surface: a person-filtered ObjectRow list + a
/// type-to-filter box + the shared right-pane inspector on selection.
/// A "New contact" births a person (createNote + setType, the P13 seam).
/// The groups rail, in-body card block, vCard, and Google sync all defer.
struct ContactsView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    var open: (UInt64) -> Void = { _ in }

    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    private var people: [EntityRow] {
        let needle = filter.lowercased()
        return model.rows(model.snap?.everything ?? [])
            .filter { $0.kinds.contains("person") && !$0.trashed }
            .filter { row in
                needle.isEmpty
                    || row.title.lowercased().contains(needle)
                    || row.cells.contains { $0.value.lowercased().contains(needle) }
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                LensHeader(
                    title: "Contacts",
                    subtitle: people.count == 1 ? "1 contact" : "\(people.count) contacts")
                Spacer()
                Button(action: newContact) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.badge.plus").font(.system(size: 11))
                        Text("New contact").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accentTint))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32).padding(.top, 16).padding(.bottom, 8)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("Filter contacts…", text: $filter)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($filterFocused)
                    .onSubmit { if let one = people.first, people.count == 1 { open(one.id) } }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08)))
            .padding(.horizontal, 32).padding(.bottom, 6)

            if people.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "person.2")
                        .font(.system(size: 28)).foregroundColor(Theme.foreground.opacity(0.12))
                    Text(filter.isEmpty ? "No contacts yet." : "No contact matches “\(filter)”.")
                        .font(.system(size: 12.5)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(people) { row in
                            ObjectRow(
                                row: row,
                                selected: selection == row.id,
                                chipTap: { f in
                                    NotificationCenter.default.post(name: .lotusSearchFor, object: f)
                                },
                                select: { selection = row.id },
                                openRow: { open(row.id) })
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The middle is the bare face: the window material shows through, so the
        // side panels are the only cards floating on it (owner's model). The
        // content (rows, cards, the editor page) carries its own surface.
    }

    /// New contact = a note born as a person (createNote + the P13 setType
    /// seam), then selected so the inspector opens its empty profile rows.
    private func newContact() {
        model.createNote { id in
            guard let id else { return }
            model.setType(id, "person") { _ in selection = id }
        }
    }
}

// MARK: - Inbox

enum InboxLens: String, CaseIterable, Identifiable {
    case route = "Route"
    case tidy = "Tidy"
    var id: String { rawValue }
}

/// bp5 panel B (P12 12d/12e): ONE inbox, two LENSES (never two cleanup
/// surfaces — a13/a14). Route = orphan scraps → give each a type and it
/// leaves the set. Tidy = the clerk's live assist proposals. The shared V3
/// inspector is the app's RIGHT pane (this surface shows it, bound to
/// selection) — lotus's mapping of bp5's inline inspector, not a duplicate.
struct InboxView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    /// Owned by the window so a cross-surface `.lotusGoTidy` lands on Tidy even
    /// when InboxView was not yet mounted at post time (see WindowChrome).
    @Binding var lens: InboxLens
    var open: (UInt64) -> Void = { _ in }
    @FocusState private var surfaceFocused: Bool
    /// The Tidy cursor — a FINGERPRINT, so it re-anchors across a refresh even
    /// as ordinals shift (P16e). nil = the first proposal.
    @State private var cursor: UInt64?
    /// The queue index we last triaged from the keyboard — re-anchored against
    /// the refreshed queue (reAnchor), not a pre-computed fingerprint that a
    /// cascading accept may itself retract.
    @State private var lastActedIndex: Int?

    private var orphans: [EntityRow] { model.orphans() }
    private var proposals: [ProposalRow] { model.snap?.inbox ?? [] }

    /// Proposals grouped by author, in first-seen order (alike proposals group —
    /// constitution 1.3). Deterministic because the sweep yields entity-id order.
    private var proposalGroups: [(author: String, items: [ProposalRow])] {
        var order: [String] = []
        var byAuthor: [String: [ProposalRow]] = [:]
        for p in proposals {
            if byAuthor[p.author] == nil { order.append(p.author) }
            byAuthor[p.author, default: []].append(p)
        }
        return order.map { (author: $0, items: byAuthor[$0] ?? []) }
    }

    /// The proposal the cursor points at (by fingerprint), else the first.
    private var focused: ProposalRow? {
        proposals.first { $0.fingerprint == cursor } ?? proposals.first
    }

    private func moveCursor(_ delta: Int) {
        guard !proposals.isEmpty else { return }
        let i = proposals.firstIndex { $0.fingerprint == focused?.fingerprint } ?? 0
        cursor = proposals[(i + delta + proposals.count) % proposals.count].fingerprint
    }

    private func actFocused(accept: Bool) {
        guard let p = focused else { return }
        // Record WHERE we acted; reAnchor lands the cursor once the refreshed
        // queue arrives. Pre-computing "the next fingerprint" bounced the cursor
        // to the top when an accept cascade-retracted that sibling (a dedupe
        // merge) — the review's finding.
        lastActedIndex = proposals.firstIndex { $0.fingerprint == p.fingerprint }
        if accept { model.accept(p) } else { model.reject(p) }
    }

    /// Land the Tidy cursor on whatever now occupies the slot we acted from,
    /// clamped to the new last — mirrors Route's advance, so triaging the last
    /// proposal stays put instead of jumping to the first.
    private func reAnchor() {
        guard let i = lastActedIndex else { return }
        lastActedIndex = nil
        cursor = proposals.isEmpty ? nil : proposals[min(i, proposals.count - 1)].fingerprint
    }

    private func actGroup(accept: Bool) {
        guard let author = focused?.author,
            let group = proposalGroups.first(where: { $0.author == author })
        else { return }
        cursor = nil
        if accept {
            model.acceptGroup(group.items.map(\.fingerprint))
        } else {
            group.items.forEach { model.reject($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            switch lens {
            case .route: routeLens
            case .tidy: tidyLens
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // [ ] cycles the lens (digits stay reserved for the D21 map, a14).
        // The surface takes focus on appear so the chord fires without a
        // prior click (the review's finding); onKeyPress needs a focused
        // view in its subtree.
        .focusable()
        .focusEffectDisabled()
        .focused($surfaceFocused)
        .onAppear { surfaceFocused = true }
        .onKeyPress { handleInboxKey($0) }
    }

    /// [ ] cycle the lens; in Tidy, j/k move the cursor and a/r (A/R) accept or
    /// reject the focused proposal (or its whole group) — the home-row triage.
    private func handleInboxKey(_ press: KeyPress) -> KeyPress.Result {
        // Chords (⌘/⌥/⌃) must PASS THROUGH, never read as a bare letter: ⌘R must
        // not become "r" and silently reject an AI proposal (the review's
        // finding — the quarantine forbids a silent write). Shift stays, so the
        // A/R group keys still work.
        guard press.modifiers.intersection([.command, .option, .control]).isEmpty else {
            return .ignored
        }
        switch press.characters {
        case "[": cycleLens(-1); return .handled
        case "]": cycleLens(1); return .handled
        default: break
        }
        guard lens == .tidy else { return .ignored }
        // ⏎ accepts the focused card (the label promises it) — safe because an
        // accept is one undoable transaction. Esc is deliberately NOT bound to
        // dismiss: a dismissal is permanent (declines never hit the undo stack),
        // so it stays on the explicit `r`, never the reflexive Escape.
        if press.key == .return {
            actFocused(accept: true)
            return .handled
        }
        switch press.characters {
        case "j": moveCursor(1)
        case "k": moveCursor(-1)
        case "a": actFocused(accept: true)
        case "r": actFocused(accept: false)
        case "A": actGroup(accept: true)
        case "R": actGroup(accept: false)
        default: return .ignored
        }
        return .handled
    }

    private func cycleLens(_ delta: Int) {
        let all = InboxLens.allCases
        let at = all.firstIndex(of: lens) ?? 0
        lens = all[(at + delta + all.count) % all.count]
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Inbox").font(.system(size: 21, weight: .bold))
            let badge = orphans.count + proposals.count
            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(nsColor: .black).opacity(0.75))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.warning))
            }
            Picker("", selection: $lens) {
                Text("Route · \(orphans.count)").tag(InboxLens.route)
                Text("Tidy · \(proposals.count)").tag(InboxLens.tidy)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            Text("one cleanup home · cycle [ ]")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 32).padding(.top, 16).padding(.bottom, 14)
    }

    // MARK: Route — orphans → a type

    @ViewBuilder
    private var routeLens: some View {
        if orphans.isEmpty {
            inboxZero
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(orphans) { row in
                            ObjectRow(
                                row: row,
                                selected: selection == row.id,
                                chipTap: { f in
                                    NotificationCenter.default.post(name: .lotusSearchFor, object: f)
                                },
                                select: { selection = row.id },
                                openRow: { open(row.id) })
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 8)
                }
                Divider()
                routeBar
            }
        }
    }

    /// The routing question + commit (a16/a21). "New note" stamps type=note
    /// so the scrap leaves the orphan set — NO folder move (design §1.2).
    /// "Suggest a merge" is static (proposer + execution defer to P16, §1.7).
    /// The routing bar rides the bare face now — no boxed dark fill, and when
    /// nothing is selected it simply isn't there (the empty box that said
    /// "Select a capture to route it." was chrome with no job).
    @ViewBuilder
    private var routeBar: some View {
        if let target = selection.flatMap({ id in orphans.first { $0.id == id } }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Which note should this go in?")
                    .font(.system(size: 12.5, weight: .semibold))
                HStack(spacing: 8) {
                    Button { commit(target) } label: {
                        Label("New note", systemImage: "1.square")
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    Button { NSSound.beep() } label: {
                        Label("Suggest a merge", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .help("The merge proposer arrives with the AI pass (P16)")
                    Spacer()
                    Button("Later") { advance(after: target) }
                        .buttonStyle(.bordered)
                    Button { commit(target) } label: {
                        Text("Commit").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
                Text("Commit stamps the type cell — the scrap leaves the inbox. No file move.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 32).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Divider(), alignment: .top)
        }
    }

    private func commit(_ row: EntityRow) {
        model.setType(row.id, "note") { ok in
            if ok { advance(after: row) }
        }
    }

    /// After Commit/Later, select the next orphan (a21: auto-advance).
    private func advance(after row: EntityRow) {
        let remaining = model.orphans().filter { $0.id != row.id }
        guard !remaining.isEmpty else { selection = nil; return }
        let at = orphans.firstIndex { $0.id == row.id } ?? 0
        // Clamp so committing the LAST orphan lands on the new last (not a
        // bounce to the first — the review's finding).
        selection = remaining[min(at, remaining.count - 1)].id
    }

    private var inboxZero: some View {
        VStack(spacing: 9) {
            Image(systemName: "tray")
                .font(.system(size: 30)).foregroundColor(.secondary.opacity(0.4))
            Text("Inbox zero — nothing waiting.")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            Text("New captures land here. Jot one from anywhere with ⌃⌥Space.")
                .font(.system(size: 11.5)).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: Tidy — the clerk's assist proposals (12e polishes into cards)

    @ViewBuilder
    private var tidyLens: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Assist queue — the clerk’s live proposals, grouped; nothing here was applied")
                    .font(.system(size: 11.5)).foregroundColor(.secondary)
                if proposals.isEmpty {
                    Text("Nothing to tidy. Assist re-scans at open; the amber badge only counts what is actionable.")
                        .font(.system(size: 12.5)).foregroundColor(.secondary)
                        .padding(.top, 4)
                } else {
                    ForEach(proposalGroups, id: \.author) { group in
                        groupBlock(group)
                    }
                }
                Text("Accept is one undo — ⌘Z never expires. Dismiss is remembered by a deterministic id: never re-asked, and not reversed by ⌘Z.")
                    .font(.system(size: 11)).foregroundColor(Color.secondary.opacity(0.8))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 32).padding(.top, 14).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if cursor == nil { cursor = proposals.first?.fingerprint } }
        .onChange(of: proposals.map(\.fingerprint)) { reAnchor() }
    }

    private func groupBlock(_ group: (author: String, items: [ProposalRow])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("✦ \(group.author.uppercased())")
                    .font(.system(size: 11, weight: .bold)).kerning(0.3).foregroundColor(Theme.warning)
                Text("· \(group.items.count)").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button("Accept all · A") { model.acceptGroup(group.items.map(\.fingerprint)) }
                    .buttonStyle(.bordered).controlSize(.small).tint(Theme.warning)
                Button("Reject all · R") { group.items.forEach { model.reject($0) } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            ForEach(group.items) { proposal in
                SuggestionCard(model: model, proposal: proposal)
                    .overlay(alignment: .leading) {
                        if proposal.fingerprint == focused?.fingerprint {
                            RoundedRectangle(cornerRadius: 2).fill(Theme.warning)
                                .frame(width: 3).padding(.vertical, 3)
                        }
                    }
                    .onTapGesture { cursor = proposal.fingerprint }
            }
        }
    }

}

// MARK: - Everything

struct EverythingView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LensHeader(
                title: "Everything",
                subtitle: model.snap.map { "\($0.everything.count) items" } ?? "…"
            )
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Table(model.rows(model.snap?.everything ?? []), selection: $selection) {
                TableColumn("Title") { row in
                    Text(row.title).font(.system(size: 13.5, weight: .medium))
                }
                TableColumn("Type") { row in
                    Text(row.kinds.joined(separator: ", "))
                        .foregroundColor(.secondary)
                }
                .width(90)
                TableColumn("Due") { row in
                    if let due = row.due {
                        Text(Civil.text(due, dateOnly: row.dueDateOnly))
                            .font(.system(size: 13).monospacedDigit())
                    } else {
                        Text("—").foregroundColor(Color.secondary.opacity(0.5))
                    }
                }
                .width(120)
                TableColumn("Status") { row in
                    if let status = row.status {
                        HStack(spacing: 7) {
                            Circle().fill(statusColor(status)).frame(width: 8, height: 8)
                            Text(status)
                        }
                    } else {
                        Text("—").foregroundColor(Color.secondary.opacity(0.5))
                    }
                }
                .width(90)
            }
            .tableStyle(.inset)
        }
    }

}

/// The status dot colour, shared across the lens surfaces (Everything,
/// Tasks). Lake-green for done, amber for doing, muted otherwise.
func statusColor(_ status: String) -> Color {
    switch status {
    case "done": return Color(red: 74 / 255, green: 158 / 255, blue: 134 / 255)
    case "doing": return Color(red: 207 / 255, green: 154 / 255, blue: 63 / 255)
    default: return Color.secondary.opacity(0.6)
    }
}

/// The EntityLine checkbox toggle for a task row — flips status done ⇄ todo
/// through the existing `set` seam. Returns nil for a non-task row, since a
/// non-nil toggle is what makes EntityLine draw (and light up) the checkbox;
/// a plain note must not sprout one. One definition so every surface that
/// shows tasks (Today, Tasks, Lists) checks them off the same way.
/// A DSL qualifier value, quoted when it needs to survive tokenizing —
/// the chip-click contract (the P11.5 review's high: unquoted multi-word
/// values split into a half-qualifier plus junk terms).
func searchQualifier(_ property: String, _ value: String) -> String {
    let needsQuotes = value.contains(where: \.isWhitespace)
    return needsQuotes ? "\(property):\"\(value)\"" : "\(property):\(value)"
}

/// Split a raw DSL string into tokens, quote-aware: a double-quoted run is
/// one token (spaces preserved, quotes kept). Mirrors the Rust tokenizer so
/// the shell edits the same query the core parses (P11.5 quoting law).
func searchTokens(_ query: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var quoted = false
    for c in query {
        if c == "\"" { quoted.toggle(); current.append(c) }
        else if c == " " && !quoted {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else { current.append(c) }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

/// The include→exclude→off three-state cycle for one facet value (bp3 a19):
/// off → `key:value` (include) → `-key:value` (exclude) → off. Quote-aware,
/// case-insensitive; rewrites the raw query the field shows and the core
/// parses — one query, two views (chips and pills).
func cycleFacetValue(_ query: inout String, key: String, value: String) {
    let inc = searchQualifier(key, value)
    let exc = "-" + inc
    var tokens = searchTokens(query)
    let hasInc = tokens.contains { $0.caseInsensitiveCompare(inc) == .orderedSame }
    let hasExc = tokens.contains { $0.caseInsensitiveCompare(exc) == .orderedSame }
    tokens.removeAll {
        $0.caseInsensitiveCompare(inc) == .orderedSame
            || $0.caseInsensitiveCompare(exc) == .orderedSame
    }
    if hasInc {
        tokens.append(exc)  // include → exclude
    } else if !hasExc {
        tokens.append(inc)  // off → include
    }  // else exclude → off (removed above, add nothing)
    query = tokens.joined(separator: " ")
}

/// Does a token read as a qualifier (key:value / -key:value / key<value with
/// a non-empty value)? Used to split the input's free text from the pills —
/// a display-only parse; the Rust `parse` stays the single search parser.
func isSearchQualifier(_ token: String) -> Bool {
    let body = token.hasPrefix("-") ? String(token.dropFirst()) : token
    for sep in [":", "<"] as [Character] {
        if let at = body.firstIndex(of: sep) {
            let key = body[..<at]
            let val = body[body.index(after: at)...]
            if !key.isEmpty && !val.isEmpty { return true }
        }
    }
    return false
}

/// The parsed-qualifier pill row (bp3 a2/a17): each qualifier token as a
/// removable pill — include = accent, exclude (`-` prefix) = red "not".
/// Pills and the facet chips are two views of the ONE query string.
struct QueryPillRow: View {
    let pills: [String]
    var remove: (String) -> Void
    var clearAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pills, id: \.self) { token in
                    QueryPill(token: token, remove: { remove(token) })
                }
                Button("Clear all", action: clearAll)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
        }
    }
}

struct QueryPill: View {
    let token: String
    var remove: () -> Void

    var body: some View {
        let excluded = token.hasPrefix("-")
        let body = excluded ? String(token.dropFirst()) : token
        let tint = excluded ? Theme.destructive : Theme.accent
        HStack(spacing: 5) {
            Text(pillText(body, excluded: excluded))
                .font(.system(size: 11.5, weight: .semibold))
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain).opacity(0.55)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 9).frame(height: 24)
        .background(Capsule().fill(tint.opacity(0.14)))
    }

    private func pillText(_ body: String, excluded: Bool) -> String {
        for sep in [":", "<"] as [Character] {
            if let at = body.firstIndex(of: sep) {
                let key = body[..<at]
                let val = body[body.index(after: at)...].replacingOccurrences(of: "\"", with: "")
                return excluded ? "\(key): not \(val)" : "\(key): \(val)"
            }
        }
        return body
    }
}

/// The checkbox toggle, vocabulary-aware (the review's diverged-laws
/// finding): display derives done-ness from the option's `completes`, so
/// the WRITE must too — toggling moves between the kind's first terminal
/// option and its first open option, falling back to done/todo only when
/// the vocabulary is silent.
func taskStatusToggle(_ model: BoxModel, _ row: EntityRow) -> (() -> Void)? {
    guard row.kinds.contains("task") || row.status != nil else { return nil }
    return {
        let vocabulary = statusVocabulary(model, kind: row.kinds.first ?? "task")
        let current = vocabulary.first { $0.name == row.status }
        let isDone = current?.isTerminal ?? (row.status == "done")
        let target: String
        if isDone {
            target = vocabulary.first { !$0.isTerminal }?.name ?? "todo"
        } else {
            target = vocabulary.first { $0.isTerminal }?.name ?? "done"
        }
        model.set(row.id, property: "status", value: target)
    }
}

/// The priority flag colour — amber for high/medium, muted for low, faint
/// for unset. Names come from the seeded `priority` options, never hardcoded.
func priorityColor(_ priority: String) -> Color {
    switch priority {
    case "high": return Color(red: 186 / 255, green: 117 / 255, blue: 23 / 255)
    case "medium": return Color(red: 239 / 255, green: 159 / 255, blue: 39 / 255)
    case "low": return Color(red: 136 / 255, green: 135 / 255, blue: 128 / 255)
    default: return Color.secondary.opacity(0.3)
    }
}

// MARK: - Results (search is navigation)

/// The facet chips above the results: each value shows its hypothetical
/// count under the current filter, and clicking it pivots the search by
/// splicing its `key:value` token into the query string — the field and the
/// chips are one source of truth (parse-first, ported from Liv). Native
/// pills, lake-green when active — not Liv's rainbow chrome.
/// The bp3 v2 facet rail (a6/a7): one chip PER PROPERTY (name + distinct-
/// value count + its D21 digit), not per value. Clicking a chip opens the
/// FacetValuePopover; the property's digit opens it from anywhere. Reshaped
/// from the P11.5d per-value chip row.
struct FacetBar: View {
    @ObservedObject var model: BoxModel
    let facets: [SearchFacet]
    @Binding var query: String

    @State private var openFacet: UInt64?

    private var keys: [String: String] { DigitMap.resolve(model.properties()) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Text("Quick filter")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                ForEach(facets) { facet in
                    PropertyFacetChip(
                        facet: facet,
                        digit: keys[facet.label.lowercased()],
                        open: openFacet == facet.id,
                        toggleOpen: { openFacet = openFacet == facet.id ? nil : facet.id },
                        query: $query,
                        close: { openFacet = nil })
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.bottom, 8)
    }
}

/// One property chip in the rail; its popover floats below when open.
struct PropertyFacetChip: View {
    let facet: SearchFacet
    var digit: String?
    let open: Bool
    var toggleOpen: () -> Void
    @Binding var query: String
    var close: () -> Void

    /// A property is "engaged" when any of its values is in the query.
    private var engaged: (inc: Int, exc: Int) {
        (facet.values.filter(\.active).count,
         facet.values.filter(\.isExcluded).count)
    }

    var body: some View {
        let e = engaged
        let anyInc = e.inc > 0, anyExc = e.exc > 0
        Button(action: toggleOpen) {
            HStack(spacing: 5) {
                Text(facet.label.capitalized).font(.system(size: 12, weight: .medium))
                Text(countLabel(e)).font(.system(size: 11)).foregroundColor(.secondary)
                if let digit {
                    Text(digit)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.75))
                }
            }
            .foregroundColor(anyExc ? Theme.destructive : anyInc ? Theme.accent : .primary)
            .padding(.horizontal, 11).frame(height: 28)
            .background(Capsule().fill(
                anyExc ? Theme.destructive.opacity(0.12)
                    : anyInc ? Theme.accentTint : Color.secondary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { open }, set: { if !$0 { close() } }),
                 arrowEdge: .bottom) {
            FacetValuePopover(facet: facet, query: $query, onClose: close)
        }
    }

    private func countLabel(_ e: (inc: Int, exc: Int)) -> String {
        if e.inc > 0 && e.exc > 0 { return "· \(e.inc) in · \(e.exc) out" }
        if e.inc > 0 { return "· \(e.inc) in" }
        if e.exc > 0 { return "· \(e.exc) out" }
        return "· \(facet.values.count)"
    }
}

/// The facet value popover (bp3 a8/a18/a19): the P11.5 value-pool chrome —
/// a type-to-filter field over the counted value list — plus the
/// include→exclude→off tri-state. Digits 1–9 cycle a value; I/X/O set it
/// directly; Esc closes. Include renders accent, exclude red + strikethrough.
struct FacetValuePopover: View {
    let facet: SearchFacet
    @Binding var query: String
    var onClose: () -> Void

    @State private var filter = ""
    @FocusState private var fieldFocused: Bool

    /// status/tier/priority/type never take VALUE_HEX (the frozen budget).
    private var neutral: Bool {
        ["status", "priority", "tier", "type", "object"].contains(facet.label.lowercased())
    }

    private var shown: [SearchFacetValue] {
        let needle = filter.lowercased()
        return needle.isEmpty
            ? facet.values
            : facet.values.filter { $0.label.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(facet.label) · counts are live")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(Theme.mutedFg)
                .textCase(.uppercase)
                .padding(.init(top: 8, leading: 10, bottom: 4, trailing: 10))
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                TextField("filter…", text: $filter)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($fieldFocused)
                    .onExitCommand { onClose() }
            }
            .padding(.init(top: 2, leading: 10, bottom: 6, trailing: 10))
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(shown.prefix(40).enumerated()), id: \.element.id) { at, v in
                        valueRow(v, index: at)
                    }
                }
            }
            .frame(maxHeight: 240)
            Text("click cycles in→out→off · type to filter · Esc done")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                .padding(.init(top: 5, leading: 10, bottom: 8, trailing: 10))
        }
        .frame(width: 244)
        .onAppear { fieldFocused = true }
    }

    private func valueRow(_ v: SearchFacetValue, index: Int) -> some View {
        let dot = neutral ? Color(nsColor: .tertiaryLabelColor)
            : Color(nsColor: Hues.valueHex(v.label))
        _ = index
        return Button { cycle(v) } label: {
            HStack(spacing: 8) {
                // A leading state glyph: red − for exclude, else the hue dot.
                if v.isExcluded {
                    Image(systemName: "minus").font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.destructive).frame(width: 7)
                } else {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(v.label).font(.system(size: 12.5))
                    .strikethrough(v.isExcluded, color: Theme.destructive)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(v.count)").font(.system(size: 11)).foregroundColor(Theme.mutedFg)
                if v.active {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
            }
            .foregroundColor(v.active ? Theme.accent : v.isExcluded ? Theme.destructive : .primary)
            .padding(.horizontal, 9).frame(minHeight: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(v.active ? Theme.accentTint
                : v.isExcluded ? Theme.destructive.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cycle(_ v: SearchFacetValue) {
        cycleFacetValue(&query, key: facet.label.lowercased(), value: v.label.lowercased())
    }
}

/// The one search field: top of the sidebar, ⌘F focuses it, its text is the
/// query the results lens renders in place. Native rounded field, lake-green
/// focus ring — search is navigation, not an overlay.
/// The search palette: a centered popup (⌘F / the magnifier) over a scrim,
/// reusing the core search seam. Type to rank hits; ↑↓ move, Enter opens,
/// Esc closes. Facet chips pivot the query in place. An empty query lists
/// the most recent (the seam ranks empty terms by recency).
struct SearchPopup: View {
    @ObservedObject var model: BoxModel
    let open: (UInt64) -> Void
    let dismiss: () -> Void
    /// A prefilled query — the chip-click filter lands here (P11.5c:
    /// clicking a value chip anywhere navigates to Results with
    /// "<property>:<value>", the existing search seam).
    var initialQuery: String? = nil

    @State private var query = ""
    @State private var highlighted = 0
    @State private var keyMonitor: Any?
    @FocusState private var fieldFocused: Bool
    /// The result display mode, remembered across sessions (bp3 a21).
    @AppStorage("app.search.displayMode.v1") private var displayModeRaw = SearchDisplayMode.compact.rawValue
    /// Collapsed kind groups (bp3 a22 — the header toggles).
    @State private var collapsed: Set<String> = []
    /// The Filters panel (bp3 a20) — pushes results down, never covers them.
    @State private var filtersOpen = false

    /// The hits resolved against the snapshot, always fresh (computed) so
    /// keyboard nav and Enter never read a stale count.
    private var rows: [EntityRow] {
        model.rows(model.searchResult.hits.map(\.id))
    }

    /// The qualifier tokens rendered as pills (bp3 a2) — the is:/has:/no:
    /// GATES are managed in the Filters panel, not shown as value pills.
    private var pills: [String] {
        searchTokens(query).filter { isSearchQualifier($0) && !isGateToken($0) }
    }

    private func isGateToken(_ token: String) -> Bool {
        let l = token.lowercased()
        return l.hasPrefix("is:") || l.hasPrefix("has:") || l.hasPrefix("no:")
    }

    /// The Filters "Include archived" toggle (bp3 a20) — splices the existing
    /// is:archived gate the DSL already honors (P6 §4.3, zero new work).
    private var includeArchived: Bool {
        searchTokens(query).contains { $0.lowercased() == "is:archived" }
    }
    private func setArchived(_ on: Bool) {
        var toks = searchTokens(query)
        toks.removeAll { $0.lowercased() == "is:archived" }
        if on { toks.append("is:archived") }
        query = toks.joined(separator: " ")
    }

    private func removePill(_ token: String) {
        var toks = searchTokens(query)
        toks.removeAll { $0.caseInsensitiveCompare(token) == .orderedSame }
        query = toks.joined(separator: " ")
    }

    /// Chip clicks in the palette ADD an include qualifier (bp3 a24: pills
    /// coexist), not the old single-select pivot.
    private func addQualifier(_ token: String) {
        // Adding an INCLUDE drops any contradicting EXCLUDE of the same value
        // (the review: a chip click over an excluded value built both pills).
        let contradiction = "-" + token
        var toks = searchTokens(query)
        toks.removeAll { $0.caseInsensitiveCompare(contradiction) == .orderedSame }
        if !toks.contains(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) {
            toks.append(token)
        }
        query = toks.joined(separator: " ")
    }

    // MARK: display modes + kind grouping (13d)

    private var displayMode: SearchDisplayMode {
        SearchDisplayMode(rawValue: displayModeRaw) ?? .compact
    }
    private var isEmptyQuery: Bool { searchTokens(query).isEmpty }

    /// The MatchField per hit (Name/Cell/Content) — Context mode shows it.
    private var fieldFor: [UInt64: String] {
        Dictionary(model.searchResult.hits.map { ($0.id, $0.field) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Kind-grouped display (bp3 a22): fixed order tasks→events→notes→files→
    /// contacts, rank preserved WITHIN each group (client-side over the
    /// ranked ids). The empty-query recents stay one "Recent" group.
    private var grouped: [(name: String, rows: [EntityRow])] {
        if isEmptyQuery { return [("Recent", rows)] }
        var buckets: [Int: [EntityRow]] = [:]
        for row in rows { buckets[Self.groupOrder(row), default: []].append(row) }
        return buckets.keys.sorted().map { (Self.groupNames[$0] ?? "Other", buckets[$0]!) }
    }

    /// The flat display order (grouped, minus collapsed) — keyboard nav and
    /// Enter follow THIS, not the pure-rank list, so the highlight tracks
    /// what the eye sees.
    private var displayRows: [EntityRow] {
        grouped.flatMap { collapsed.contains($0.name) ? [] : $0.rows }
    }

    private static let groupNames = [0: "Tasks", 1: "Events", 2: "Notes", 3: "Files", 4: "Contacts"]
    private static func groupOrder(_ row: EntityRow) -> Int {
        if row.kinds.contains("task") || row.status != nil { return 0 }
        if row.kinds.contains("event") { return 1 }
        if row.cells.contains(where: { $0.kind == "file" }) { return 3 }
        if row.kinds.contains("person") { return 4 }
        return 2  // notes + everything else
    }

    private var countLine: String {
        let total = model.searchResult.matchCount
        if isEmptyQuery {
            return "\(total) object\(total == 1 ? "" : "s") · showing \(rows.count) recent"
        }
        return "\(total) match\(total == 1 ? "" : "es")"
    }

    var body: some View {
        let rows = self.rows
        let fresh = model.searchedFor == query
        return ZStack {
            Theme.background.opacity(0.6)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    TextField("Search or jump to anything…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($fieldFocused)
                        .onSubmit {
                            let ordered = displayRows
                            if ordered.indices.contains(highlighted) {
                                open(ordered[highlighted].id)
                                dismiss()
                            }
                        }
                        .onExitCommand { dismiss() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if !pills.isEmpty {
                    QueryPillRow(
                        pills: pills,
                        remove: { removePill($0) },
                        clearAll: { query = "" })
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }

                // The scope row (bp3 a4): one static "This vault" tile — one
                // box is one scope; Drive/Web/connectors + "add source" defer.
                HStack(spacing: 7) {
                    Text("Search in").font(.system(size: 11)).foregroundColor(.secondary)
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        Text("This vault").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(Theme.accentTint))
                }
                .padding(.horizontal, 14).padding(.bottom, 4)

                if !model.searchResult.facets.isEmpty {
                    Divider()
                    FacetBar(model: model, facets: model.searchResult.facets, query: $query)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                }

                if filtersOpen {
                    Divider()
                    SearchFiltersPanel(
                        includeArchived: includeArchived, setArchived: setArchived)
                }

                // The results toolbar: the true (never-capped) count line +
                // the Compact/Context/Metadata display switch (bp3 a12/a21).
                HStack(spacing: 10) {
                    Text(countLine)
                        .font(.system(size: 11.5)).foregroundColor(.secondary)
                    Button {
                        filtersOpen.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 10))
                            Text("Filters").font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(filtersOpen || includeArchived ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    // Save view (P18d, feature-map #21/#28): bookmark the
                    // QUERY on screen as a named view entity — the widget
                    // board and the Library's Views group read the same list.
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Save view…") {
                            let saved = query
                            Dialogs.shared.prompt(
                                "Save view", placeholder: "Name", confirmLabel: "Save"
                            ) { name in
                                guard let name = name?.trimmingCharacters(in: .whitespaces),
                                    !name.isEmpty
                                else { return }
                                model.saveView(name: name, query: saved)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .padding(.leading, 10)
                    }
                    Spacer()
                    Picker("", selection: $displayModeRaw) {
                        ForEach(SearchDisplayMode.allCases, id: \.rawValue) { m in
                            Text(m.label).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented).fixedSize().controlSize(.small)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)

                Divider()

                if rows.isEmpty {
                    searchEmptyState(fresh: fresh)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(grouped, id: \.name) { group in
                                ResultGroupHeader(
                                    name: group.name, count: group.rows.count,
                                    collapsed: collapsed.contains(group.name),
                                    grouping: !isEmptyQuery,
                                    toggle: {
                                        if collapsed.contains(group.name) { collapsed.remove(group.name) }
                                        else { collapsed.insert(group.name) }
                                        highlighted = 0  // re-anchor: displayRows just shifted
                                    })
                                if !collapsed.contains(group.name) {
                                    ForEach(group.rows, id: \.id) { row in
                                        let index = displayRows.firstIndex { $0.id == row.id } ?? 0
                                        resultRow(row, mode: displayMode, field: fieldFor[row.id])
                                            .contentShape(Rectangle())
                                            .onTapGesture { open(row.id); dismiss() }
                                            .background(
                                                RoundedRectangle(cornerRadius: Theme.radiusMd)
                                                    .fill(index == highlighted
                                                        ? Theme.primary.opacity(0.12) : .clear))
                                            .onHover { if $0 { highlighted = index } }
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 380)
                }

                PaletteFootbar()

                // The footer actions (bp3 a13/a14/a15) — reserved disabled
                // frames: Save-as-view / Export / Open-in-view need the views
                // substrate lotus lacks; the raw query stays re-runnable.
                Divider()
                HStack(spacing: 8) {
                    Spacer()
                    reservedFooterButton("square.and.arrow.up", "Export")
                    reservedFooterButton("bookmark", "Save")
                    reservedFooterButton("arrow.up.forward.square", "Open in view", primary: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .frame(maxWidth: 620)
            .background(RoundedRectangle(cornerRadius: Theme.radiusXl).fill(Theme.popover))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusXl).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            // CENTERED on the window (the owner's call — it hung 96pt off the
            // top before). The fixed-height anchor keeps the box's TOP pinned
            // while results grow downward, so the palette doesn't bounce as
            // the hit list changes height.
            .frame(height: 520, alignment: .top)
        }
        // Debounce keystrokes before hitting the box lock.
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            model.search(query)
        }
        .onAppear {
            if let initialQuery { query = initialQuery }
            fieldFocused = true
            model.search(query) // seed recent immediately, don't wait 150ms
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let count = self.displayRows.count
                // Alt+1/2/3 switches display mode (bp3 a21).
                if event.modifierFlags.contains(.option),
                    let idx = [18: 0, 19: 1, 20: 2][Int(event.keyCode)] {
                    displayModeRaw = SearchDisplayMode.allCases[idx].rawValue
                    return nil
                }
                switch event.keyCode {
                case 125:
                    highlighted = min(max(count - 1, 0), highlighted + 1)
                    return nil
                case 126:
                    highlighted = max(0, highlighted - 1)
                    return nil
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        .onChange(of: query) { highlighted = 0 }
    }

    /// The V2 compact grammar (P11.5d): icon · title · one anchor chip · the
    /// labeled status chip. Three display modes (bp3 a21): Compact is the row;
    /// Context adds a matched-FIELD label (the highlighted-body snippet is
    /// deferred — the seam returns no offsets); Metadata adds up to two more
    /// VALUE_HEX chips + "+N" (NOT ObjectCard — the palette stays scannable
    /// rows; recorded delta). Chips filter IN the palette, additively.
    @ViewBuilder
    private func resultRow(_ row: EntityRow, mode: SearchDisplayMode, field: String?) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: rowKindIcon(row))
                .font(.system(size: 13))
                .foregroundColor(Theme.accent)
                .frame(width: 18)
                .padding(.top, mode == .context ? 1 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title.isEmpty ? "Untitled" : row.title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if mode == .context, let field, field != "structured", field != "name" {
                    Text("matched in \(field)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let anchor = anchorChip(for: row) {
                ValueChip(
                    text: anchor.text, hue: anchor.hue,
                    tap: anchor.filter.map { f in { addQualifier(f) } },
                    help: anchor.filter.map { "add filter: \($0)" })
            }
            if mode == .metadata { metadataChips(row) }
            if let status = row.status {
                StatusChip(
                    option: statusVocabulary(model, kind: row.kinds.first ?? "")
                        .first { $0.name == status },
                    statusName: status,
                    tap: { addQualifier(searchQualifier("status", status)) })
            }
        }
        .padding(.vertical, mode == .compact ? 6 : 8)
        .padding(.horizontal, 10)
    }

    /// Metadata mode's extra chips (bp3 a21): up to two more VALUE_HEX
    /// values beyond the anchor + a "+N" — the BP-7 chip budget, as rows.
    @ViewBuilder
    private func metadataChips(_ row: EntityRow) -> some View {
        // The frozen never-hue budget: tier (with status/priority/type) renders
        // neutral, never VALUE_HEX (the review's finding).
        let neverHue: Set<String> = ["status", "priority", "tier", "type"]
        let anchorText = anchorChip(for: row)?.text
        let extras = row.cells
            .filter { ["subjects", "people", "project", "area", "tier"].contains($0.property) }
            .map { (property: $0.property, value: $0.value) }
            .filter { !$0.value.isEmpty && $0.value != anchorText }
        return HStack(spacing: 4) {
            ForEach(Array(extras.prefix(2).enumerated()), id: \.offset) { _, cell in
                ValueChip(
                    text: cell.value,
                    hue: neverHue.contains(cell.property) ? nil : Hues.valueHex(cell.value))
            }
            if extras.count > 2 {
                Text("+\(extras.count - 2)")
                    .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
            }
        }
    }

    /// The empty results state (bp3 a26 reconciled): not a bare "Nothing
    /// matches" but the next moves — pop the last qualifier, open Filters,
    /// include archived. A blank query just prompts to type.
    @ViewBuilder
    private func searchEmptyState(fresh: Bool) -> some View {
        if !fresh || query.isEmpty {
            Text("Type to search, or jump to a recent object.")
                .font(.system(size: 12.5)).foregroundColor(Theme.mutedFg)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing matches.").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 8) {
                    if let last = pills.last {
                        emptyMove("Remove “\(QueryPillDisplay(last))”") { removePill(last) }
                    }
                    emptyMove(filtersOpen ? "Close Filters" : "Open Filters") { filtersOpen.toggle() }
                    if !includeArchived {
                        emptyMove("Include archived") { setArchived(true) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }

    private func emptyMove(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain).foregroundColor(Theme.accent)
    }

    private func reservedFooterButton(_ symbol: String, _ label: String, primary: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(label).font(.system(size: 11.5, weight: .medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 11).frame(height: 28)
        .overlay(Capsule().strokeBorder(
            Color(nsColor: .separatorColor),
            style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])))
        .opacity(0.5)
        .help("\(label) needs the views/export substrate — arrives with the files/views pass")
    }
}

/// Human-readable pill text ("object: not contact") for the empty-state hint.
func QueryPillDisplay(_ token: String) -> String {
    let excluded = token.hasPrefix("-")
    let body = excluded ? String(token.dropFirst()) : token
    for sep in [":", "<"] as [Character] {
        if let at = body.firstIndex(of: sep) {
            let key = body[..<at]
            let val = body[body.index(after: at)...].replacingOccurrences(of: "\"", with: "")
            return excluded ? "\(key): not \(val)" : "\(key): \(val)"
        }
    }
    return body
}

/// The Filters panel (bp3 a20): the working Archived toggle over the DSL's
/// existing is:archived gate, plus the deferred rows (date ranges need a new
/// AtLeast op; created-in-workspace, subnotes, match-scope) rendered static
/// so the layout diffs clean when they land.
struct SearchFiltersPanel: View {
    let includeArchived: Bool
    var setArchived: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filters").font(.system(size: 10.5, weight: .bold)).kerning(0.5)
                .foregroundColor(Theme.mutedFg)
            HStack(spacing: 24) {
                Toggle(isOn: Binding(get: { includeArchived }, set: { setArchived($0) })) {
                    Text("Include archived").font(.system(size: 12))
                }
                .toggleStyle(.switch).controlSize(.mini)
                deferredFilter("Edited", "Any time", "needs ranges")
            }
            HStack(spacing: 24) {
                deferredFilter("Match", "Name + content", "name-only soon")
                deferredFilter("Subnotes", "Included", "gate deferred")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deferredFilter(_ key: String, _ value: String, _ note: String) -> some View {
        HStack(spacing: 7) {
            Text(key).font(.system(size: 11)).foregroundColor(Theme.mutedFg)
            Text(value).font(.system(size: 12)).foregroundColor(.secondary)
            Text(note)
                .font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.mutedFg)
                .padding(.horizontal, 5)
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
        }
        .opacity(0.6)
    }
}

/// The palette's always-visible shortcut contract (bp3 a16) — same footbar
/// grammar as the inspector (P11.5 InspectorFootbar).
/// A reusable shortcut footbar (P14e): the same KeyCap-pair grammar the
/// inspector and search palette teach (bp6 a27), driven by a pair list.
struct ShortcutBar: View {
    let pairs: [(String, String)]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, p in
                HStack(spacing: 4) {
                    Text(p.0).font(.system(size: 10.5, design: .monospaced))
                        .padding(.horizontal, 3).frame(minHeight: 16)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                    Text(p.1).font(.system(size: 11))
                }
                .foregroundColor(Theme.mutedFg)
            }
            Spacer()
        }
        .padding(.horizontal, 32).padding(.vertical, 8)
        .overlay(Divider(), alignment: .top)
    }
}

struct PaletteFootbar: View {
    var body: some View {
        HStack(spacing: 10) {
            pair("↑↓", "move")
            pair("⏎", "open")
            pair("⌥1/2/3", "mode")
            pair("⎋", "close")
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .overlay(Divider(), alignment: .top)
    }

    private func pair(_ cap: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(cap).font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 3).frame(minHeight: 16)
                .background(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            Text(label).font(.system(size: 10.5))
        }
        .foregroundColor(Theme.mutedFg)
    }
}

/// The result display modes (bp3 a21) — Compact rows, Context adds a match
/// field, Metadata adds chips. Alt+1/2/3 and remembered per session.
enum SearchDisplayMode: String, CaseIterable {
    case compact, context, metadata
    var label: String { rawValue.capitalized }
}

/// A kind-group header in the results (bp3 a22): the group name + count,
/// tappable to collapse. The empty-query "Recent" header names the intent.
struct ResultGroupHeader: View {
    let name: String
    let count: Int
    let collapsed: Bool
    /// True when this is a kind group (collapsible); the recents header is not.
    let grouping: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: { if grouping { toggle() } }) {
            HStack(spacing: 6) {
                if grouping {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                Text(name.uppercased())
                    .font(.system(size: 10.5, weight: .bold)).kerning(0.6)
                Text("· \(count)").font(.system(size: 10.5, weight: .semibold))
                Spacer()
            }
            .foregroundColor(Theme.mutedFg)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!grouping)
    }
}

// MARK: - Inspector

// MARK: - the file ladder (P7)

/// A file entity's read-only ladder: the Finder icon, the filename and
/// format, the path (struck-through if it no longer resolves), and Open
/// externally. A file NEVER opens the editor — read-only-by-decision is
/// law. Its editable properties live in the right-rail inspector; the
/// extracted-text preview (rung 2) and thumbnail (rung 3) arrive in 7b/7d.
struct BaseFileView: View {
    @ObservedObject var model: BoxModel
    let id: UInt64

    @State private var preview: String = ""
    @State private var previewLoaded = false

    private var entity: EntityRow? { model.entity(id) }
    private var filePath: String? {
        entity?.cells.first(where: { $0.kind == "file" })?.value
    }
    private var format: String? {
        entity?.cells.first(where: { $0.property == "format" })?.value
    }

    var body: some View {
        ScrollView {
            if let entity, let path = filePath {
                let exists = FileManager.default.fileExists(atPath: path)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entity.title.isEmpty ? "Untitled file" : entity.title)
                                .font(.system(size: 18, weight: .semibold))
                                .lineLimit(2)
                            if let format, !format.isEmpty {
                                Text(format.uppercased())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    Text(path)
                        .font(.system(size: 12))
                        .foregroundColor(exists ? .secondary : Color.red.opacity(0.85))
                        .strikethrough(!exists)
                        .textSelection(.enabled)
                    if !exists {
                        Text("This file has moved or been deleted — the reference is broken.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.app")
                        }
                        .disabled(!exists)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .disabled(!exists)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    // Rung 2 — the extracted-text preview (from the cache).
                    Divider().padding(.top, 4)
                    if !previewLoaded {
                        Text("Reading…")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else if preview.isEmpty {
                        Text("No text preview available.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        Text(preview)
                            .font(.system(size: 12.5))
                            .foregroundColor(.primary.opacity(0.9))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(28)
                .padding(.top, 8)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                Text("This file is no longer available.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The middle is the bare face: the window material shows through, so the
        // side panels are the only cards floating on it (owner's model). The
        // content (rows, cards, the editor page) carries its own surface.
        // On open: re-hash (a changed file re-extracts), then load the
        // preview. No timer — freshness is per-open.
        .onAppear {
            model.resyncFile(id) { _ in
                model.extractedText(id) { text in
                    preview = text
                    previewLoaded = true
                }
            }
        }
    }
}

/// The Library surface (P7/7c): a saved view of file entities — every
/// entity carrying a `file` cell. A list lens, not Liv's multi-mode file
/// shell; format facets / an image grid are follow-ups. Clicking a file
/// opens it read-only in a file tab; "+ Add file" is the NSOpenPanel flow.
struct LibraryView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    let addFile: () -> Void
    let open: (UInt64) -> Void

    /// The lens over the file pool (bp7 a15, P15d): Table ships; Gallery is a
    /// deferred candidate — 2-slot-ready in the switcher, disabled until image
    /// volume justifies the renderer (#35). Folder + Kanban are refused (no
    /// folders; files carry no status).
    enum LibraryLens: String, CaseIterable {
        case table = "Table", gallery = "Gallery"
        var symbol: String { self == .table ? "list.bullet" : "square.grid.2x2" }
    }
    @State private var lens: LibraryLens = .table
    /// The reconciled "Folder" control (bp7 a23): group the collection by a
    /// property value, one level. nil = flat.
    @State private var groupBy: String? = nil

    private var files: [EntityRow] {
        model.rows(model.snap?.everything ?? []).filter {
            $0.cells.contains { $0.kind == "file" }
        }
    }

    var body: some View {
        let files = self.files
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(files.count)
                    viewsGroup
                    if files.isEmpty {
                        emptyState
                    } else {
                        tableLens(files)
                    }
                }
            }
            ShortcutBar(pairs: [("⌃1", "table"), ("↵", "open"), ("⌘⇧I", "import")])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The middle is the bare face: the window material shows through, so the
        // side panels are the only cards floating on it (owner's model). The
        // content (rows, cards, the editor page) carries its own surface.
    }

    /// Saved views (P18d, the proving surface): the filter engine's bookmarks,
    /// listed where files live — click re-runs the query in the one palette;
    /// delete rides the ordinary trash door.
    @ViewBuilder
    private var viewsGroup: some View {
        let views = model.snap?.views ?? []
        if !views.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text("VIEWS · \(views.count)")
                    .font(.system(size: 11, weight: .bold)).kerning(0.6)
                    .foregroundColor(Theme.mutedFg)
                    .padding(.bottom, 2)
                ForEach(views) { view in
                    Button {
                        NotificationCenter.default.post(name: .lotusSearchFor, object: view.query)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.mutedFg)
                            Text(view.name).font(.system(size: 12.5))
                            Text(view.query)
                                .font(.system(size: 10.5).monospaced())
                                .foregroundColor(Theme.mutedFg)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete view") { model.trash(view.id) }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)
        }
    }

    private func header(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            LensHeader(title: "Library", subtitle: subtitle(count))
            Spacer()
            libraryLensSwitcher
            groupByMenu
            Button {
                NotificationCenter.default.post(name: .lotusOpenImport, object: nil)
            } label: {
                Image(systemName: "square.and.arrow.down").font(.system(size: 12.5))
            }
            .buttonStyle(.borderless)
            .help("Import…  ⌘⇧I")
            Button {
                NotificationCenter.default.post(name: .lotusOpenExport, object: nil)
            } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 12.5))
            }
            .buttonStyle(.borderless)
            .help("Export…  ⌘⇧E")
            Button(action: addFile) {
                Label("Add file", systemImage: "plus").font(.system(size: 12))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
    }

    private func subtitle(_ count: Int) -> String {
        let base = count == 1 ? "1 file" : "\(count) files"
        return groupBy.map { "\(base) · by \($0)" } ?? base
    }

    private var libraryLensSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(Array(LibraryLens.allCases.enumerated()), id: \.element) { index, option in
                Button { if option == .table { lens = option } } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(lens == option ? Theme.accent : .secondary)
                        .frame(width: 27, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(lens == option ? Theme.accentTint : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(option == .gallery)
                .help(
                    option == .gallery
                        ? "Gallery — arrives when image volume justifies it"
                        : "\(option.rawValue)  ⌃\(index + 1)"
                )
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .fixedSize()
    }

    private var groupByMenu: some View {
        Menu {
            Button("None") { groupBy = nil }
            Button("Format") { groupBy = "format" }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 11))
                Text(groupBy.map { "Group: \($0)" } ?? "Group").font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(groupBy == nil ? .secondary : Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func tableLens(_ files: [EntityRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let key = groupBy {
                let groups = Dictionary(grouping: files) { row in
                    row.cells.first(where: { $0.property == key })?.value ?? "—"
                }
                ForEach(groups.keys.sorted(), id: \.self) { value in
                    SectionLabel(text: "\(value) · \(groups[value]?.count ?? 0)")
                        .padding(.top, 14)
                    rows(groups[value] ?? [])
                }
            } else {
                rows(files)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func rows(_ files: [EntityRow]) -> some View {
        ForEach(files) { row in
            ObjectRow(
                row: row,
                selected: selection == row.id,
                chipTap: { filter in
                    NotificationCenter.default.post(name: .lotusSearchFor, object: filter)
                },
                select: { selection = row.id },
                openRow: { open(row.id) })
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 34))
                .foregroundColor(Theme.foreground.opacity(0.12))
            Text("No files yet.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("Add a file by reference — lotus links it, never copies it.")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.mutedFg)
            Button("Add file…", action: addFile).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// The Tasks surface (P8): a cross-workspace list of every task (type=task),
/// grouped by status (todo / doing / done) in seeded order, due-ascending
/// within a group. Quick-add creates a task (typed, born todo). The working
/// checkbox and filters arrive in 8b; the board is a deferred candidate.
struct TasksView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    let open: (UInt64) -> Void

    @State private var draft = ""
    @State private var filter: TaskFilter = .open
    /// The lens over the ONE task pool (bp6 a6, P14a): List | Board |
    /// Schedule | Cards — ephemeral shell state, NOT a persisted view-object
    /// (D3). Only the grouping key + layout change; the pool is shared.
    @State private var lens: TaskLens = .list
    /// Done (completes) columns fold by default (bp6 a11); the header
    /// chevron adds a column name here to expand it. Session state.
    @State private var expandedDone: Set<String> = []
    /// The column currently under a drag (accent-tinted while hovered).
    @State private var dropTarget: String? = nil
    @FocusState private var addFocused: Bool

    enum TaskFilter: String, CaseIterable { case all = "All", open = "Open", done = "Done" }
    enum TaskLens: String, CaseIterable {
        case list = "List", board = "Board", schedule = "Schedule", cards = "Cards"
        var symbol: String {
            switch self {
            case .list: return "list.bullet"
            case .board: return "rectangle.split.3x1"
            case .schedule: return "calendar.day.timeline.left"
            case .cards: return "square.grid.2x2"
            }
        }
    }

    /// The ungated task pool — everything → tasks. The BOARD renders THIS
    /// (its columns carry status, so the Open/Done gate would empty the Done
    /// columns and vanish a card dragged to Done — the review's high).
    private var allTasks: [EntityRow] {
        model.rows(model.snap?.everything ?? []).filter { $0.kinds.contains("task") }
    }

    /// The list/schedule/cards pool: allTasks → the All/Open/Done gate.
    /// Done-ness follows the option's `completes` (the vocabulary-aware law).
    private var tasks: [EntityRow] {
        let terminal = Set(
            statusVocabulary(model, kind: "task").filter(\.isTerminal).map(\.name)
        ).union(["done"])
        switch filter {
        case .all: return allTasks
        case .open: return allTasks.filter { !terminal.contains($0.status ?? "") }
        case .done: return allTasks.filter { terminal.contains($0.status ?? "") }
        }
    }

    var body: some View {
        let tasks = self.tasks
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                LensHeader(
                    title: "Tasks",
                    subtitle: lens == .board
                        ? (allTasks.count == 1 ? "1 task" : "\(allTasks.count) tasks")
                        : (tasks.count == 1 ? "1 task" : "\(tasks.count) tasks"))
                Spacer()
                agentsButton
                lensSwitcher
                // The Board's columns carry status, so the Open/Done gate is
                // a list-lens concern; it stays hidden on (and unused by) the
                // board — which renders the ungated pool.
                if lens != .board { filterSegments }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 8)

            switch lens {
            case .list: listLens(tasks)
            case .board: boardLens(allTasks)
            case .schedule: scheduleLens(tasks)
            case .cards: cardsLens(tasks)
            }

            // The shortcut contract (bp6 a27 — "the two surfaces teach each
            // other"; same footbar grammar as the P13 palette). [Selection |
            // View]: Selection is the shared right inspector (already shown
            // on this surface via body3Pane); the View config frame is
            // reserved (needs the views substrate, D3).
            ShortcutBar(pairs: lens == .board
                ? [("⌃1–4", "lens"), ("drag", "set status"), ("N", "new"), ("⏎", "open")]
                : [("⌃1–4", "lens"), ("↑↓", "move"), ("⏎", "open"), ("N", "new")])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The middle is the bare face: the window material shows through, so the
        // side panels are the only cards floating on it (owner's model). The
        // content (rows, cards, the editor page) carries its own surface.
    }

    /// The List lens (bp6 a14): the status-grouped list — rows are ObjectRow
    /// at the 34px budget with the StatusDot (the one lens that shows the
    /// status dot; the board tile drops even that). Sections ARE the user's
    /// vocabulary in board order (P11.5c).
    @ViewBuilder
    private func listLens(_ tasks: [EntityRow]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                quickAdd
                if tasks.isEmpty {
                    emptyState
                } else {
                    let vocabulary = statusVocabulary(model, kind: "task")
                    let unstatused = tasks.filter { $0.status == nil }
                        .sorted { dueKey($0) < dueKey($1) }
                    if !unstatused.isEmpty {
                        SectionLabel(text: "no status").padding(.top, 14)
                        ForEach(unstatused) { taskRow($0, option: nil) }
                    }
                    ForEach(vocabulary) { option in
                        let group = tasks
                            .filter { $0.status == option.name }
                            .sorted { dueKey($0) < dueKey($1) }
                        if !group.isEmpty {
                            SectionLabel(text: option.name).padding(.top, 14)
                            ForEach(group) { taskRow($0, option: option) }
                        }
                    }
                    // A status whose option left the vocabulary still shows —
                    // labeled like every other section (the P11.5 review).
                    let known = Set(vocabulary.map(\.name))
                    let orphanNames = Set(
                        tasks.compactMap(\.status).filter { !known.contains($0) }
                    ).sorted()
                    ForEach(orphanNames, id: \.self) { name in
                        let group = tasks
                            .filter { $0.status == name }
                            .sorted { dueKey($0) < dueKey($1) }
                        SectionLabel(text: name).padding(.top, 14)
                        ForEach(group) { taskRow($0, option: nil) }
                    }
                }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The Board lens (bp6 a8–a13): horizontal columns = the status
    /// vocabulary in board order; tiles carry NO status (the column does);
    /// cross-column DRAG writes status (the existing set-status seam);
    /// completes columns fold; manual within-column ordering is DEFERRED
    /// (D1 — cards sort by due). No board replaces the list — it is one lens.
    private func boardLens(_ tasks: [EntityRow]) -> some View {
        let vocabulary = statusVocabulary(model, kind: "task")
        let known = Set(vocabulary.map(\.name))
        let orphanNames = Set(tasks.compactMap(\.status).filter { !known.contains($0) }).sorted()
        let unstatused = tasks.filter { $0.status == nil }.sorted { dueKey($0) < dueKey($1) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                if !unstatused.isEmpty {
                    boardColumn(title: "no status", statusName: nil, option: nil, cards: unstatused)
                }
                ForEach(vocabulary) { option in
                    boardColumn(
                        title: option.name, statusName: option.name, option: option,
                        cards: tasks.filter { $0.status == option.name }.sorted { dueKey($0) < dueKey($1) })
                }
                ForEach(orphanNames, id: \.self) { name in
                    boardColumn(
                        title: name, statusName: name, option: nil,
                        cards: tasks.filter { $0.status == name }.sorted { dueKey($0) < dueKey($1) })
                }
                addColumn
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 20)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// The trailing "+ New status" column (bp6 a8) — adds a status OPTION
    /// entity to the task vocabulary via the landed lotus_add_status_option
    /// seam (hue −1: the vocabulary editor assigns hues, P19). Rename /
    /// reorder / retire the option happen on its entity in the inspector.
    private var addColumn: some View {
        Button {
            Dialogs.shared.prompt(
                "New status", message: "Adds a column to the task board.",
                placeholder: "e.g. blocked", confirmLabel: "Add"
            ) { name in
                let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                model.addStatusOption(kind: "task", name: trimmed)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11))
                Text("New status").font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.secondary)
            .frame(width: 150, alignment: .leading)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func boardColumn(
        title: String, statusName: String?, option: OptionRow?, cards: [EntityRow]
    ) -> some View {
        let terminal = option?.isTerminal ?? false
        let folded = terminal && !expandedDone.contains(title)
        let dot = option?.hue.map { Hues.degrees($0) } ?? Color(nsColor: .tertiaryLabelColor)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(cards.count)").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer(minLength: 4)
                if terminal {
                    Button {
                        if folded { expandedDone.insert(title) } else { expandedDone.remove(title) }
                    } label: {
                        Image(systemName: folded ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                } else if statusName != nil {
                    Button { addToColumn(statusName) } label: {
                        Image(systemName: "plus").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundColor(.secondary).help("New task here")
                }
            }
            .padding(.horizontal, 4)
            if !folded {
                LazyVStack(spacing: 7) {
                    ForEach(cards) { card in boardTile(card) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(width: 252, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10).fill(
            dropTarget == title ? Theme.accentTint : Color.secondary.opacity(0.05)))
        .onDrop(
            of: [.plainText],
            isTargeted: Binding(get: { dropTarget == title }, set: { dropTarget = $0 ? title : nil })
        ) { providers in
            providers.first?.loadObject(ofClass: NSString.self) { obj, _ in
                guard let s = obj as? String, s.hasPrefix("task:"),
                    let id = UInt64(s.dropFirst(5)) else { return }
                DispatchQueue.main.async {
                    // Drag = the existing set-status command; the no-status
                    // column unsets (moving a task back out of the vocabulary).
                    if let statusName { model.set(id, property: "status", value: statusName) }
                    else { model.unset(id, property: "status") }
                }
            }
            return true
        }
    }

    /// A board card — ObjectTile carries NO status by construction (the
    /// column is the status). The date leg never hues (never-hue law), so it
    /// rides the neutral dateText slot, not the VALUE_HEX person slot.
    private func boardTile(_ row: EntityRow) -> some View {
        let anchor = anchorChip(for: row)
        return ObjectTile(
            title: row.title,
            person: anchor?.isDate == false ? anchor?.text : nil,
            dateText: row.due.map { Civil.text($0, dateOnly: row.dueDateOnly) },
            tier: row.cells.first { $0.property == "priority" }?.value)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.background))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(selection == row.id ? Theme.accent : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { selection = row.id }
        .onDrag { NSItemProvider(object: "task:\(row.id)" as NSString) }
    }

    private func addToColumn(_ statusName: String?) {
        model.createTask { id in
            guard let id else { return }
            if let statusName { model.set(id, property: "status", value: statusName) }
            selection = id
        }
    }

    /// The Schedule lens (bp6 a16): the same task rows re-bucketed by `due`
    /// into Overdue / Today / This week / Later (client-side). Rows are
    /// ObjectRow; drag-to-set-due is deferred (the calendar owns the drag).
    private func scheduleLens(_ tasks: [EntityRow]) -> some View {
        let buckets = ["Overdue", "Today", "This week", "Later", "No date"]
        let grouped = Dictionary(grouping: tasks) { scheduleBucket($0).name }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                quickAdd
                ForEach(buckets, id: \.self) { name in
                    if let group = grouped[name], !group.isEmpty {
                        SectionLabel(text: name).padding(.top, 14)
                        ForEach(group.sorted { dueKey($0) < dueKey($1) }) { row in
                            taskRow(row, option: statusOptionFor(row))
                        }
                    }
                }
                if tasks.isEmpty { emptyState }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The Cards lens (bp6 a15): an ObjectCard gallery — description clamp,
    /// ≤3 chips + "+N", no status dot (the grouping carries state).
    private func cardsLens(_ tasks: [EntityRow]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 210), spacing: 11)]
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                quickAdd
                LazyVGrid(columns: columns, alignment: .leading, spacing: 11) {
                    ForEach(tasks.sorted { dueKey($0) < dueKey($1) }) { row in
                        ObjectCard(
                            row: row,
                            descriptionText: row.cells.first { $0.property == "description" }?.value ?? "",
                            chips: [anchorChip(for: row)].compactMap { $0 })
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(selection == row.id ? Theme.accentTint : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture { selection = row.id }
                    }
                }
                if tasks.isEmpty { emptyState }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The status option for a row (so the schedule/list rows show the right
    /// dot hue) — nil when the status left the vocabulary.
    private func statusOptionFor(_ row: EntityRow) -> OptionRow? {
        statusVocabulary(model, kind: "task").first { $0.name == row.status }
    }

    /// The Schedule bucket for a task, by calendar-day distance from today.
    private func scheduleBucket(_ row: EntityRow) -> (order: Int, name: String) {
        guard let due = row.due else { return (4, "No date") }
        func date(_ ymd: Int64) -> Date? {
            var c = DateComponents()
            c.year = Int(ymd / 10_000); c.month = Int((ymd / 100) % 100); c.day = Int(ymd % 100)
            return Civil.gregorian.date(from: c)
        }
        guard let d = date(due / 10_000), let t = date(Civil.todayYMD),
            let days = Civil.gregorian.dateComponents([.day], from: t, to: d).day
        else { return (4, "No date") }
        if days < 0 { return (0, "Overdue") }
        if days == 0 { return (1, "Today") }
        if days <= 7 { return (2, "This week") }
        return (3, "Later")
    }

    /// The lens switcher tabs (bp6 a6) — List | Board | Schedule | Cards.
    /// The AI Agents frame (bp6) — inert; the task copilot's proposals enter
    /// the ONE inbox in the P16 pass, never a second mutation door here.
    private var agentsButton: some View {
        let count = model.snap?.inbox.count ?? 0
        return Button {
            NotificationCenter.default.post(name: .lotusGoTidy, object: nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars").font(.system(size: 10.5))
                Text(count > 0 ? "Agents · \(count)" : "Agents").font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Theme.warning)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(Theme.warning.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("The clerk’s suggestions — review in the one inbox (Inbox › Tidy)")
    }

    // Icon-only so four lenses fit beside the header controls even with the
    // inspector open — a labelled switcher overflowed and wrapped its text
    // vertically. The active lens is named in the ⌃1–4 footbar + each tooltip.
    private var lensSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(Array(TaskLens.allCases.enumerated()), id: \.element) { index, option in
                Button { lens = option } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(lens == option ? Theme.accent : .secondary)
                        .frame(width: 27, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(lens == option ? Theme.accentTint : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(option.rawValue)  ⌃\(index + 1)")
                // Ctrl+1..4 switches the lens (bp6 a6, the review's finding).
                .keyboardShortcut(
                    KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .fixedSize()
    }

    /// A task row in the V2 chip-forward grammar (P11.5c): checkbox (the
    /// same status toggle), title, priority as a neutral chip menu, ONE
    /// anchor chip (chip-click filters), status dot, modified. Single-click
    /// selects into the inspector; double-click opens — same data, same
    /// gestures, new skin.
    private func taskRow(_ row: EntityRow, option: OptionRow?) -> some View {
        ObjectRow(
            row: row,
            statusOption: option,
            selected: selection == row.id,
            toggle: taskStatusToggle(model, row),
            trailing: AnyView(priorityFlag(row)),
            chipTap: { filter in
                NotificationCenter.default.post(name: .lotusSearchFor, object: filter)
            },
            select: { selection = row.id },
            openRow: { open(row.id) },
            haloCount: model.proposalCount(row.id),
            onHalo: { NotificationCenter.default.post(name: .lotusGoTidy, object: nil) })
    }

    /// The priority flag — a menu over the seeded `priority` options (never
    /// hardcoded), faint when unset. Only shown if the property exists.
    @ViewBuilder
    private func priorityFlag(_ row: EntityRow) -> some View {
        if let prop = model.property(named: "priority") {
            let current = row.cells.first { $0.property == "priority" }?.value ?? ""
            Menu {
                ForEach(prop.options) { option in
                    Button(option.name.capitalized) {
                        model.set(row.id, property: "priority", value: option.name)
                    }
                }
                if !current.isEmpty {
                    Divider()
                    Button("None") { model.unset(row.id, property: "priority") }
                }
            } label: {
                // The tier/priority slot: a NEUTRAL chip by the color budget
                // (tier is never VALUE_HEX); empty renders the faint flag only.
                if current.isEmpty {
                    Image(systemName: "flag")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary.opacity(0.5))
                } else {
                    ValueChip(text: current, hue: nil, icon: "flag")
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(current.isEmpty ? "Set priority" : "Priority: \(current)")
        }
    }

    private var filterSegments: some View {
        HStack(spacing: 0) {
            ForEach(TaskFilter.allCases, id: \.self) { option in
                Button { filter = option } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .foregroundColor(filter == option ? Theme.accent : .secondary)
                        .background(filter == option ? Theme.accent.opacity(0.12) : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var quickAdd: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.mutedFg)
            TextField("Add a task…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($addFocused)
                .onSubmit { addTask() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.square")
                .font(.system(size: 30))
                .foregroundColor(Theme.foreground.opacity(0.12))
            Text("No tasks yet.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("Add one above — it lands in Todo.")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.mutedFg)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// Create the task (born nameless + todo), then set its title — two
    /// transactions for one quick-add, matching create_note's nameless birth.
    /// The draft is cleared only once the box confirms, so a busy box beeps
    /// and keeps the typed title for a retry — never lose a task.
    private func addTask() {
        let title = draft.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        model.createTask { id in
            guard let id else { return }
            model.set(id, property: "name", value: title)
            draft = ""
        }
    }

    /// Due ascending, nil-due last.
    private func dueKey(_ row: EntityRow) -> Int64 {
        row.due ?? Int64.max
    }
}

/// The Lists surface (P9): a manual list is an entity of type=list whose
/// ordered `related` members are shown here. An index of lists (+ New list);
/// clicking one opens its ordered members (read-only rows, hover-× to remove
/// — removing un-tags, never deletes). The "Add to list…" gesture is 9b.
struct ListsSurface: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    let open: (UInt64) -> Void

    @State private var openList: UInt64?
    @State private var newName = ""

    private var lists: [EntityRow] {
        model.rows(model.snap?.everything ?? []).filter { $0.kinds.contains("list") }
    }

    private func memberIds(_ list: EntityRow) -> [UInt64] {
        list.cells
            .filter { $0.property == "related" && $0.refTarget != list.id }
            .compactMap { $0.refTarget }
    }

    // The resolvable (live, non-trashed) members — model.rows drops any id the
    // snapshot can't resolve. Both the index badge and the detail count off
    // THIS, so they never disagree; a trashed member is hidden from both and
    // returns to both when it's restored (its `related` tag is kept, as trash
    // is reversible).
    private func liveMembers(_ list: EntityRow) -> [EntityRow] {
        model.rows(memberIds(list))
    }

    var body: some View {
        if let openList, let list = model.entity(openList) {
            detail(list)
        } else {
            index
        }
    }

    private var index: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LensHeader(
                    title: "Lists",
                    subtitle: lists.count == 1 ? "1 list" : "\(lists.count) lists")
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.mutedFg)
                    TextField("New list…", text: $newName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onSubmit { addList() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .padding(.top, 8)

                if lists.isEmpty {
                    Text("No lists yet. Name one above.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.mutedFg)
                        .padding(.top, 16)
                } else {
                    ForEach(lists) { row in
                        indexRow(row)
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The middle is the bare face: the window material shows through, so the
        // side panels are the only cards floating on it (owner's model). The
        // content (rows, cards, the editor page) carries its own surface.
    }

    private func indexRow(_ row: EntityRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 13))
                .foregroundColor(Theme.accent)
            Text(row.title.isEmpty ? "Untitled list" : row.title)
                .font(.system(size: 14))
                .lineLimit(1)
            Spacer()
            Text("\(liveMembers(row).count)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(Color.secondary.opacity(0.6))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = row.id
            openList = row.id
        }
        .overlay(Divider(), alignment: .bottom)
    }

    private func detail(_ list: EntityRow) -> some View {
        let members = liveMembers(list)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { openList = nil } label: {
                    Label("Lists", systemImage: "chevron.left").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.accent)
                .padding(.bottom, 10)

                LensHeader(
                    title: list.title.isEmpty ? "Untitled list" : list.title,
                    subtitle: members.count == 1 ? "1 item" : "\(members.count) items")

                if members.isEmpty {
                    Text("No items yet. Select anything and use \u{201C}Add to list\u{2026}\u{201D} in its inspector.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.mutedFg)
                        .padding(.top, 20)
                } else {
                    ForEach(members) { row in
                        EntityLine(
                            row: row, selected: selection == row.id,
                            toggle: taskStatusToggle(model, row),
                            accessory: AnyView(removeButton(list: list.id, member: row.id))
                        ) {
                            open(row.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The middle is the bare face: the window material shows through, so the
        // side panels are the only cards floating on it (owner's model). The
        // content (rows, cards, the editor page) carries its own surface.
    }

    private func removeButton(list: UInt64, member: UInt64) -> some View {
        Button { model.removeMember(list, member) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9))
                .foregroundColor(Theme.mutedFg)
        }
        .buttonStyle(.plain)
        .help("Remove from list")
    }

    private func addList() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.createList(name) { id in
            if id != nil { newName = "" }
        }
    }
}

// The V3 inspector (P11.5f) lives in Inspector.swift.

/// The note's content history (P4/4d): every past version from the log,
/// newest first, each restorable. Restore appends a new version — the
/// log is never rewritten.
struct HistorySection: View {
    @ObservedObject var model: BoxModel
    let id: UInt64
    /// The History LENS mounts this expanded; the inspector-era default was
    /// a collapsed disclosure.
    var startOpen = false

    @State private var open = false
    @State private var versions: [HistoryVersion] = []
    /// The live content spans, so "current" is the version that matches
    /// the actual value — not merely the newest logged edit (a cleared
    /// note has an empty current that no logged version equals).
    @State private var currentSpans: [SpanJSON] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                open.toggle()
                if open { load() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("HISTORY")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.5)
                    if !versions.isEmpty {
                        Text("\(versions.count)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .foregroundColor(Color.secondary.opacity(0.85))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                if versions.isEmpty {
                    Text("No history yet.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(versions) { version in
                        HistoryRow(
                            version: version, isCurrent: version.spans == currentSpans,
                            restore: {
                                model.restoreContent(id, spans: version.spans) { _ in load() }
                            })
                    }
                }
            }
        }
        .onAppear {
            if startOpen && !open {
                open = true
                load()
            }
        }
        .onChange(of: id) {
            open = false
            versions = []
            currentSpans = []
            if startOpen {
                open = true
                load()
            }
        }
    }

    private func load() {
        model.contentHistory(id) { fetched in versions = fetched }
        model.content(id) { read in
            if case .doc(let doc) = read { currentSpans = doc.spans } else { currentSpans = [] }
        }
    }
}

struct HistoryRow: View {
    let version: HistoryVersion
    let isCurrent: Bool
    let restore: () -> Void

    @State private var hovering = false

    /// The transaction time is a Unix timestamp (store.rs `now()`), not a
    /// civil value — format the wall clock in the system calendar.
    static func when(_ epoch: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isCurrent ? "circle.fill" : "circle")
                .font(.system(size: 6))
                .foregroundColor(isCurrent ? Theme.accent : .secondary)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(version.preview)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(Self.when(version.time))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.secondary)
                    if version.author != "user" {
                        Text(version.author)
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.accent)
                    }
                }
            }
            Spacer(minLength: 4)
            if hovering && !isCurrent {
                Button("Restore", action: restore)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(.vertical, 7)
        .overlay(Divider(), alignment: .bottom)
        .onHover { hovering = $0 }
    }
}

// MARK: - the right-panel lenses (bp4 five-lens bar · P17)

/// A quiet lens empty state — text on the panel face, never a slab.
private struct LensEmpty: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundColor(Theme.foreground.opacity(0.12))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundColor(Theme.mutedFg)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Outline — a live shell parse of the open note's headings; click jumps.
struct OutlineLensPane: View {
    let editor: EditorModel?
    @State private var entries: [OutlineEntry] = []

    var body: some View {
        Group {
            if editor == nil {
                LensEmpty(symbol: "list.bullet.indent", message: "Open a note to see its outline.")
            } else if entries.isEmpty {
                LensEmpty(symbol: "list.bullet.indent", message: "No headings yet — start a line with #.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(entries) { entry in
                            Button { editor?.reveal(entry.id) } label: {
                                Text(entry.text)
                                    .font(.system(
                                        size: entry.level == 1 ? 12.5 : 12,
                                        weight: entry.level == 1 ? .semibold : .regular))
                                    .foregroundColor(Theme.foreground.opacity(0.85))
                                    .lineLimit(1)
                                    .padding(.leading, CGFloat(max(0, entry.level - 1)) * 13)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
            }
        }
        .onAppear { entries = editor?.outline() ?? [] }
        .onReceive(
            editor?.objectWillChange.eraseToAnyPublisher()
                ?? Empty<Void, Never>().eraseToAnyPublisher()
        ) { _ in
            // willChange — read after the update lands.
            DispatchQueue.main.async { entries = editor?.outline() ?? [] }
        }
    }
}

/// History — the content-version projection, expanded (Snapshots renamed,
/// IA-5). Restore is an append, never a rewrite.
struct HistoryLensPane: View {
    @ObservedObject var model: BoxModel
    let focus: UInt64?

    var body: some View {
        if let id = focus {
            ScrollView {
                HistorySection(model: model, id: id, startOpen: true)
                    .padding(.horizontal, 13)
                    .padding(.top, 12)
            }
        } else {
            LensEmpty(symbol: "clock", message: "Select an object to see its history.")
        }
    }
}

/// ✦ Assist — the P16 amber cards for THIS object; the AI's only panel home.
/// Same fingerprints as Inbox › Tidy, accept/dismiss run the same seams.
struct AssistLensPane: View {
    @ObservedObject var model: BoxModel
    let focus: UInt64?

    var body: some View {
        let proposals = (model.snap?.inbox ?? []).filter { $0.entity == focus }
        Group {
            if focus == nil {
                LensEmpty(symbol: "sparkle", message: "Select an object to see its suggestions.")
            } else if proposals.isEmpty {
                LensEmpty(
                    symbol: "sparkle",
                    message: "Nothing suggested for this object.\nThe full queue lives in Inbox › Tidy.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(proposals) { proposal in
                            SuggestionCard(model: model, proposal: proposal)
                        }
                        Button("All suggestions — Inbox › Tidy") {
                            NotificationCenter.default.post(name: .lotusGoTidy, object: nil)
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11.5))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
