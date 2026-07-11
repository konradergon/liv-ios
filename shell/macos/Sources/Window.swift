// lotus — the main window. One window, three regions: sidebar, one lens,
// inspector. Every lens swaps in place; nothing floats free. The window
// renders one JSON snapshot from the seam and never holds the box.
//
// interface.md is the law here: system materials, Apple text styles,
// lake green in exactly three jobs, the inbox count as the only badge.

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
    let properties: [PropertyRow]
    let entities: [EntityRow]
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

    func undo() {
        act { lotus_undo_at(self.path) == 1 }
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
    /// The top-right Spaces popover (the workspace tree, out of the panel).
    @State private var spacesOpen = false
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
            .overlay(alignment: .topTrailing) {
                // The Spaces / files picker at the window's far top-right,
                // over the inspector's titlebar band — its views open as a
                // popover, never in the panel.
                if chrome.surface == .notes && !chrome.focusMode {
                    spacesPicker
                }
            }
            .overlay(switcherOverlay)
            .overlay(searchOverlay)
            .overlay(faultNotice)
            .overlay(DialogHost())
            .background(eventHandlers)
            .onAppear {
                model.refresh()
                installReturnMonitor()
                registerCommands()
                // Seed the history with the launch location, or the
                // first Back has nothing to return to.
                chrome.recordNav(.init(surface: chrome.surface, selection: nil))
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
        body3Pane
            .overlay(alignment: .topLeading) {
                // Collapsed or focused: the only way back to the sidebar
                // floats top-left over the content, beside the lights.
                if (!chrome.leftOpen || chrome.focusMode) {
                    CollapsedControls(
                        chrome: chrome,
                        expand: {
                            if chrome.focusMode { chrome.toggleFocus() }
                            if !chrome.leftOpen {
                                chrome.leftOpen = true
                                chrome.persistPanes()
                            }
                        },
                        search: { chrome.searchOpen = true })
                }
            }
    }

    /// The persistent left panel: header controls, the labeled surface
    /// nav, the notes desk (Spaces tree etc.) when Notes is active, and
    /// the workspace switcher pinned at the bottom.
    private var leftPanel: some View {
        VStack(spacing: 0) {
            SidebarHeader(
                chrome: chrome,
                collapse: {
                    chrome.leftOpen = false
                    chrome.persistPanes()
                },
                search: { chrome.searchOpen = true })
            SurfaceNav(chrome: chrome, model: model) { target in
                navigate(to: target)
            }
            .padding(.top, 2)
            // The workspace tree lives in the top-right Spaces popover now,
            // not the panel — the panel stays nav + footer.
            Spacer(minLength: 0)
            WorkspaceFooter(model: model, chrome: chrome, actions: workspaceActions)
        }
        .background(SidebarMaterial().ignoresSafeArea())
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

    /// The Spaces / files picker, pinned to the window's far top-right. ⊞
    /// drops the workspace tree as a popover (out of the panel); the folder
    /// jumps to the Library surface (the real files browser).
    private var spacesPicker: some View {
        HStack(spacing: 2) {
            Button { spacesOpen.toggle() } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .foregroundColor(spacesOpen ? Theme.accent : Theme.mutedFg)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Spaces")
            .popover(isPresented: $spacesOpen, arrowEdge: .top) {
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
                    openEntity: { id in
                        spacesOpen = false
                        openEntityTab(id)
                    },
                    showDesk: { lensValue in
                        spacesOpen = false
                        showDesk(lensValue)
                    }
                )
                .frame(width: 280, height: 440)
            }
            Button {
                spacesOpen = false
                navigate(to: .library)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .foregroundColor(Theme.mutedFg)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Files (Library)")
        }
        .frame(height: Theme.headerBandHeight, alignment: .top)
        .padding(.trailing, 12)
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
            chrome.recordNav(.init(surface: target, selection: nil))
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
            .onReceive(NotificationCenter.default.publisher(for: .lotusNavFocus)) { note in
                selection = note.object as? UInt64
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusGoHome)) { _ in
                navigate(to: .notes)
                query = ""
                lens = .today
            }
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
                    chrome.recordNav(.init(surface: chrome.surface, selection: id))
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
                if chrome.leftOpen && !chrome.focusMode {
                    leftPanel
                        .frame(width: max(total * chrome.leftPct / 100, 0))
                    PaneDivider(
                        pct: $chrome.leftPct, total: total,
                        minPct: 12, maxPct: chrome.leftLiveMax, leadingEdge: true,
                        collapsible: false
                    ) { chrome.persistPanes() }
                }
                center
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // The right divider outlives its panel: a drag-collapsed
                // inspector must stay reopenable by mouse (§1.5). The Calendar
                // never shows the GLOBAL inspector: it embeds one inside its
                // own fixed-width right column, so selecting an item never
                // reflows the grid — a reflow between the two clicks of a
                // double-tap made the second click miss (the review's high).
                if !chrome.focusMode && chrome.surface != .calendar {
                    PaneDivider(
                        pct: $chrome.rightPct, open: $chrome.rightOpen, total: total,
                        minPct: 10, maxPct: chrome.rightLiveMax, leadingEdge: false
                    ) { chrome.persistPanes() }
                }
                if chrome.rightOpen && !chrome.focusMode && chrome.surface != .calendar {
                    InspectorPane(model: model, selection: $selection)
                        .frame(width: max(total * chrome.rightPct / 100, 0))
                }
            }
            .coordinateSpace(name: "chrome.body")
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
                    open: { id in openEntityTab(id) })
            case .calendar:
                CalendarView(
                    model: model, selection: $selection,
                    open: { id in openEntityTab(id) },
                    openDaily: { day in openDailyNote(forDay: day) })
            case .library:
                LibraryView(
                    model: model, selection: $selection,
                    addFile: { addFileFlow() },
                    open: { id in openEntityTab(id) })
            default:
                ExtensionStub(surface: chrome.surface)
            }
        }
        .id(chrome.surface)
    }

    /// The Notes surface: the tab strip over the active tab's content.
    private var notesBody: some View {
        VStack(spacing: 0) {
            TabStrip(
                tabs: tabs, model: model, chrome: chrome,
                activate: { tab in activateTab(tab) },
                close: { tab in closeTab(tab) },
                openNew: { openBlankTab() },
                rename: { id in renameEntity(id) }
            )
            activeTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
                category: "File", binding: Hotkey(modifiers: [.mod, .shift], key: "i")
            ) {
                addFileFlow()
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
                id: "object:toggle-bookmark", label: "Bookmark", scope: .global,
                category: "Object", binding: Hotkey(modifiers: [.mod, .shift], key: "b"),
                enabled: { selection != nil }
            ) {
                guard let id = selection, let row = model.entity(id) else { return }
                let starred = row.cells.contains {
                    $0.property == "bookmarked" && $0.value == "yes"
                }
                model.set(id, property: "bookmarked", value: starred ? "false" : "true")
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
            .padding(.top, 40)
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
    var open: (UInt64) -> Void = { _ in }
    @State private var lens: InboxLens = .route
    @FocusState private var surfaceFocused: Bool

    private var orphans: [EntityRow] { model.orphans() }
    private var proposals: [ProposalRow] { model.snap?.inbox ?? [] }

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
        .onKeyPress(.init("[")) { cycleLens(-1); return .handled }
        .onKeyPress(.init("]")) { cycleLens(1); return .handled }
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
        .padding(.horizontal, 32).padding(.top, 34).padding(.bottom, 14)
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
    private var routeBar: some View {
        let target = selection.flatMap { id in orphans.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 8) {
            if let target {
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
            } else {
                Text("Select a capture to route it.")
                    .font(.system(size: 12.5)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .underPageBackgroundColor))
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
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("Assist queue — the clerk’s live proposals; nothing here was applied")
                        .font(.system(size: 11.5)).foregroundColor(.secondary)
                    Spacer()
                    Button { NSSound.beep() } label: {
                        Label("Suggest for all", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("The batch metadata suggester arrives with the AI pass (P16)")
                }
                if proposals.isEmpty {
                    Text("Nothing to tidy. Assist re-scans in the background; the amber badge only counts what is actionable.")
                        .font(.system(size: 12.5)).foregroundColor(.secondary)
                        .padding(.top, 4)
                } else {
                    ForEach(proposals) { proposal in
                        AssistCard(model: model, proposal: proposal)
                    }
                }
                // A static heuristic card — the proposer defers to P16, but
                // the card + accept path are the frame it will ride (§1.3).
                StaticAssistCard()
                Text("Dismissals are remembered — suggestions carry deterministic ids and are never re-asked.")
                    .font(.system(size: 11)).foregroundColor(Color.secondary.opacity(0.8))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 32).padding(.top, 14).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The marigold-halo assist card (bp5 a23): one live clerk proposal —
/// "date mentioned", "person mentioned" — with the accept/reject that
/// ships. AI presence is the amber halo (Theme.warning), never a silent edit.
struct AssistCard: View {
    @ObservedObject var model: BoxModel
    let proposal: ProposalRow

    private var subject: String {
        model.entity(proposal.entity)?.title ?? "#\(proposal.entity)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text("✦ Clerk")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.warning)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.warning.opacity(0.14)))
                Text(proposal.reason)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            Text(subject)
                .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(2)
            HStack(spacing: 7) {
                Button("Accept · ⏎") { model.accept(proposal) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                Button("Dismiss · Esc") { model.reject(proposal) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.warning, lineWidth: 1))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Theme.warning.opacity(0.14), lineWidth: 3))
        .frame(maxWidth: 520, alignment: .leading)
    }
}

/// A static heuristic card (bp5 a23: "3 notes missing type") — the proposer
/// is P16; this shows the card grammar and marks itself STATIC so nothing
/// reads as applied.
struct StaticAssistCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text("✦ Assist")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.warning)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.warning.opacity(0.14)))
                Text("Notes missing a type")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("STATIC · P16")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
            }
            Text("Suggested from your own vocabulary + the seed, never invented. The heuristic proposer arrives with the AI pass; the card and accept path are the frame it will ride.")
                .font(.system(size: 11.5)).foregroundColor(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.warning.opacity(0.5), lineWidth: 1))
        .frame(maxWidth: 520, alignment: .leading)
        .opacity(0.9)
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
            .padding(.top, 40)

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
        return ZStack(alignment: .top) {
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
            .padding(.top, 96)
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
        .background(Theme.background)
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

    var body: some View {
        let files = model.rows(model.snap?.everything ?? []).filter {
            $0.cells.contains { $0.kind == "file" }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    LensHeader(
                        title: "Library",
                        subtitle: files.count == 1 ? "1 file" : "\(files.count) files")
                    Spacer()
                    Button(action: addFile) {
                        Label("Add file", systemImage: "plus").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)

                if files.isEmpty {
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
                } else {
                    VStack(spacing: 0) {
                        ForEach(files) { row in
                            ObjectRow(
                                row: row,
                                selected: selection == row.id,
                                chipTap: { filter in
                                    NotificationCenter.default.post(
                                        name: .lotusSearchFor, object: filter)
                                },
                                select: { selection = row.id },
                                openRow: { open(row.id) })
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
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

    /// The shared pipeline: everything → tasks → the All/Open/Done gate.
    /// Done-ness follows the option's `completes` (the vocabulary-aware law).
    private var tasks: [EntityRow] {
        let all = model.rows(model.snap?.everything ?? []).filter { $0.kinds.contains("task") }
        let terminal = Set(
            statusVocabulary(model, kind: "task").filter(\.isTerminal).map(\.name)
        ).union(["done"])
        switch filter {
        case .all: return all
        case .open: return all.filter { !terminal.contains($0.status ?? "") }
        case .done: return all.filter { terminal.contains($0.status ?? "") }
        }
    }

    var body: some View {
        let tasks = self.tasks
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                LensHeader(
                    title: "Tasks",
                    subtitle: tasks.count == 1 ? "1 task" : "\(tasks.count) tasks")
                Spacer()
                lensSwitcher
                // The Board's columns carry status, so the Open/Done gate is
                // a list-lens concern; it stays hidden on the board.
                if lens != .board { filterSegments }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 8)

            switch lens {
            case .list: listLens(tasks)
            case .board: boardLens(tasks)
            case .schedule: scheduleLens(tasks)
            case .cards: cardsLens(tasks)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
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
    private var lensSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(TaskLens.allCases, id: \.self) { option in
                Button { lens = option } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.symbol).font(.system(size: 11))
                        Text(option.rawValue).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(lens == option ? Theme.accent : .secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(lens == option ? Theme.accentTint : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.08)))
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
            openRow: { open(row.id) })
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
                        .padding(.top, 40)
                } else {
                    ForEach(lists) { row in
                        indexRow(row)
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
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
            .padding(.top, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
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
        .onChange(of: id) {
            open = false
            versions = []
            currentSpans = []
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
