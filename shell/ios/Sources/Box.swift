// liv iOS — the box seam. One serial lane to the core, one JSON snapshot,
// act-then-refresh. The shell never holds the box; every FFI call opens it
// and closes it. Mirrors the macOS BoxModel (Window.swift) idioms.

import Combine
import Foundation
import os

// MARK: - snapshot rows (mirror ffi/src/lib.rs, decoded from snake_case)

/// EVERY field Optional — one missing key must never drop the snapshot
/// (a real, recurring bug; Optionality is resilience, not politeness).
struct Snapshot: Decodable {
    var today, unstructured, everything, dated: [UInt64]?
    var occurrences: [Occurrence]?
    var entities: [EntityRow]?
    var properties: [PropertyRow]?
    var kinds: [KindRow]?
    /// The workspace tree (M4). Shapes live in Workspace.swift.
    var workspaces: [WorkspaceRow]?
    /// Saved filters — view entities with a `query` cell (M4).
    var views: [SavedViewRow]?
}

/// Optionals carry `= nil` so the memberwise initializer has defaults —
/// the workspace self-check builds rows by hand, and a 15-argument call
/// would be a test that lies about what it is testing.
struct EntityRow: Decodable, Identifiable {
    var id: UInt64
    var title: String? = nil
    var kinds: [String]? = nil
    var due: Int64? = nil
    var dueEnd: Int64? = nil
    var dueDateOnly: Bool? = nil
    var positionedBy: String? = nil
    var status: String? = nil
    var created: Int64? = nil
    var trashed: Bool? = nil
    var bookmarked: Bool? = nil
    var archived: Bool? = nil
    var contentPrint: UInt64? = nil
    var vaultPath: String? = nil
    var cells: [CellRow]? = nil
}

struct CellRow: Decodable {
    var propertyId: UInt64? = nil
    var property: String? = nil
    var kind: String? = nil
    var value: String? = nil
    var refTarget: UInt64? = nil
}

struct Occurrence: Decodable {
    var series: UInt64?
    var civil: Int64?
}

struct PropertyRow: Decodable {
    var id: UInt64?
    var name: String?
    var kind: String?
    var usage: Int?
    var icon: String?
    var hideWhenEmpty: Bool?
    /// A select property's vocabulary (the wire's OptionRow list; empty for
    /// other kinds). The area picker reads it live off the snapshot.
    var options: [PropertyOptionRow]?
}

/// One option of a select property. Every field Optional — the standing law.
struct PropertyOptionRow: Decodable {
    var id: UInt64?
    var name: String?
    var hidden: Bool?
}

struct KindRow: Decodable {
    var id: UInt64?
    var name: String?
}

/// One liv_status_options_at row. The wire's hue is a float degree;
/// the shell keeps a rounded Int. The wire's numeric `id` is ignored —
/// options identify by name here.
struct StatusOption: Decodable, Identifiable {
    var id: String { name ?? "" }
    var name: String?
    var hue: Int?
    var completes: Bool?
    var order: Double?

    init(name: String?, hue: Int? = nil, completes: Bool? = nil, order: Double? = nil) {
        self.name = name
        self.hue = hue
        self.completes = completes
        self.order = order
    }

    private enum CodingKeys: String, CodingKey { case name, hue, completes, order }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        completes = try? c.decodeIfPresent(Bool.self, forKey: .completes)
        order = try? c.decodeIfPresent(Double.self, forKey: .order)
        if let d = try? c.decodeIfPresent(Double.self, forKey: .hue) {
            hue = Int(d.rounded())
        } else {
            hue = try? c.decodeIfPresent(Int.self, forKey: .hue)
        }
    }
}

/// One entity's content, fresh from the box (liv_content_at). EVERY field
/// Optional — the standing law; a missing key must never drop the doc.
/// `spans` are the log's own serde encoding of Span, verbatim (Editor.swift
/// holds the total decoder).
struct ContentDoc: Decodable {
    var id: UInt64?
    var name: String?
    var trashed: Bool?
    /// True when the box opened fine but no such entity exists. A nil
    /// ContentDoc means something else entirely: the box would not open.
    var missing: Bool?
    /// Identity of the stored content value; a save must present it back.
    /// 0 when the entity carries no content cell.
    var fingerprint: UInt64?
    var spans: [SpanJSON]?
}

// MARK: - private wires (payloads the model flattens before publishing)

private struct DistinctWire: Decodable {
    var value: String?
    var count: Int?
}

private struct SearchWire: Decodable {
    struct Hit: Decodable { var id: UInt64? }
    var hits: [Hit]?
}

private struct ProbeWire: Decodable {
    var code: String?
    var message: String?
}

// MARK: - the model: refresh-after-every-act, never hold the box

final class BoxModel: ObservableObject {
    let path: String

    @Published private(set) var snap: Snapshot?
    /// Human message for a box that will not open for a reason retrying
    /// cannot fix — corrupt / version / io. nil = healthy.
    @Published private(set) var boxFault: String?
    /// The box is merely locked (the CLI, an extension); a backoff retry
    /// is scheduled. Render as quiet busyness, never a fault.
    @Published private(set) var busyRetrying: Bool = false
    /// id -> row, rebuilt on each snapshot apply. Per-row lookups on every
    /// render; a linear scan would be O(n²).
    private(set) var entities: [UInt64: EntityRow] = [:]

    /// One serial lane to the box: the app must never race its own lock.
    private let boxQueue = DispatchQueue(label: "liv.box", qos: .userInitiated)
    private var retryScheduled = false
    private var retryDelay = 0.2
    /// The last-used occurrence window. Held here so act-then-refresh
    /// reloads the window the calendar is showing instead of snapping its
    /// occurrences back to the current month. Main-thread only.
    private var window: (from: Int64, to: Int64)?

    private static let log = Logger(subsystem: "app.liv.ios", category: "box")

    init(path: String) {
        self.path = path
    }

    func entity(_ id: UInt64) -> EntityRow? {
        entities[id]
    }

    // MARK: reads

    /// Re-snapshot, keeping the last-used occurrence window (default:
    /// liv_snapshot's current month).
    func refresh() {
        let path = self.path
        let window = self.window
        boxQueue.async {
            let raw: UnsafeMutablePointer<CChar>?
            if let window {
                raw = liv_snapshot_window_at(path, window.from, window.to)
            } else {
                raw = liv_snapshot(path)
            }
            guard let raw else {
                self.snapshotFailed()
                return
            }
            self.applySnapshot(raw)
        }
    }

    /// Point the snapshot at a caller-chosen occurrence window (civil
    /// YYYYMMDDHHMM bounds) and reload. Sticks across later refreshes.
    func refreshWindow(from: Int64, to: Int64) {
        window = (from, to)
        refresh()
    }

    /// Back to the default current-month window.
    func resetWindow() {
        window = nil
        refresh()
    }

    /// Decode on the box queue, publish on main. A decode failure logs and
    /// keeps the previous snap — never crash, never silently drop.
    private func applySnapshot(_ raw: UnsafeMutablePointer<CChar>) {
        let json = String(cString: raw)
        liv_string_free(raw)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let fresh: Snapshot
        do {
            fresh = try decoder.decode(Snapshot.self, from: Data(json.utf8))
        } catch {
            Self.log.error("snapshot decode failed, keeping previous snap: \(String(describing: error), privacy: .public)")
            DispatchQueue.main.async { self.busyRetrying = false }
            return
        }
        var index = [UInt64: EntityRow](minimumCapacity: fresh.entities?.count ?? 0)
        for e in fresh.entities ?? [] { index[e.id] = e }
        DispatchQueue.main.async {
            self.entities = index  // before snap: observers read a fresh index
            self.snap = fresh
            self.boxFault = nil
            self.busyRetrying = false
            self.retryDelay = 0.2
        }
    }

    /// The snapshot said no. Locked (or probe silent) means retry — and
    /// mean it; anything else is a fault the user must see, not a spinner.
    private func snapshotFailed() {
        var code = "locked"
        var message = "The box did not open."
        if let (c, m) = probe() {
            code = c
            message = m
        }
        DispatchQueue.main.async {
            if code == "locked" {
                self.beginRetry()
            } else {
                self.boxFault = message
                self.busyRetrying = false
            }
        }
    }

    /// Why the box would not open. nil = it opens fine. Box-queue only.
    private func probe() -> (code: String, message: String)? {
        guard let raw = liv_probe(path) else { return nil }
        let json = String(cString: raw)
        liv_string_free(raw)
        let p = try? JSONDecoder().decode(ProbeWire.self, from: Data(json.utf8))
        return (p?.code ?? "io", p?.message ?? "The box did not open.")
    }

    /// Main-thread only: mark busy and schedule one refresh, 0.2s doubling
    /// to a 2.0s ceiling.
    private func beginRetry() {
        busyRetrying = true
        guard !retryScheduled else { return }
        retryScheduled = true
        let delay = retryDelay
        retryDelay = min(delay * 2, 2.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.retryScheduled = false
            self.refresh()
        }
    }

    // MARK: acts (verb -> on success refresh)

    /// A verb said no: probe. Locked = busy + retry; a real fault = the
    /// blocking notice; a healthy box = the verb was refused on its merits
    /// (log only — mutations must never replay themselves). Box-queue only.
    private func verbFailed(_ verb: String) {
        guard let (code, message) = probe() else {
            Self.log.notice("\(verb, privacy: .public) refused; box healthy")
            return
        }
        DispatchQueue.main.async {
            if code == "locked" {
                self.beginRetry()
            } else {
                self.boxFault = message
                self.busyRetrying = false
            }
        }
    }

    /// `done` (optional) always receives the verdict — the chip-honesty
    /// seam: a caller may show an applied chip ONLY inside `done(true)`.
    private func act(
        _ verb: String, _ done: ((Bool) -> Void)? = nil, _ work: @escaping () -> Bool
    ) {
        boxQueue.async {
            let ok = work()
            if !ok { self.verbFailed(verb) }
            DispatchQueue.main.async {
                done?(ok)
                if ok { self.refresh() }
            }
        }
    }

    /// An id-returning verb; 0 = failure. `done` always receives the id.
    private func actId(_ verb: String, _ done: ((UInt64) -> Void)?, _ work: @escaping () -> UInt64) {
        boxQueue.async {
            let id = work()
            if id == 0 { self.verbFailed(verb) }
            DispatchQueue.main.async {
                done?(id)
                if id != 0 { self.refresh() }
            }
        }
    }

    func capture(_ text: String, done: ((UInt64) -> Void)? = nil) {
        actId("capture", Outbox.tracking(.idea, done)) { liv_capture_at(self.path, text) }
    }

    func createTask(done: ((UInt64) -> Void)? = nil) {
        actId("createTask", Outbox.tracking(.task, done)) { liv_create_task_at(self.path) }
    }

    func createEvent(dueCivil: Int64, dateOnly: Bool, done: ((UInt64) -> Void)? = nil) {
        actId("createEvent", Outbox.tracking(.event, done)) { liv_create_event_at(self.path, dueCivil, dateOnly ? 1 : 0) }
    }

    func set(_ id: UInt64, _ property: String, _ value: String, done: ((Bool) -> Void)? = nil) {
        act("set", done) { liv_set_at(self.path, id, property, value) == 1 }
    }

    /// One span write (the mirror contract). end <= 0 = no end (plain date);
    /// dateOnly applies to both ends.
    func setSpan(
        _ id: UInt64, _ property: String, start: Int64, end: Int64, dateOnly: Bool,
        done: ((Bool) -> Void)? = nil
    ) {
        act("setSpan", done) {
            liv_set_span_at(self.path, id, property, start, end <= 0 ? 0 : end, dateOnly ? 1 : 0) == 1
        }
    }

    func setType(_ id: UInt64, _ type: String, done: ((Bool) -> Void)? = nil) {
        act("setType", done) { liv_set_type_at(self.path, id, type) == 1 }
    }

    /// One cell of a multi-valued property — membership, never replace-all.
    func addCell(_ id: UInt64, _ property: String, _ value: String, done: ((Bool) -> Void)? = nil) {
        act("addCell", done) { liv_add_cell_at(self.path, id, property, value) == 1 }
    }

    /// The librarian: by reference, never moves the file.
    func addFile(_ path: String, done: ((UInt64) -> Void)? = nil) {
        actId("addFile", Outbox.tracking(.photo, done)) { liv_add_file_at(self.path, path) }
    }

    /// Remove EVERY cell of one property — the inverse of `set`. This is
    /// how a capture-time stamp chip is taken back off.
    func unset(_ id: UInt64, _ property: String) {
        act("unset") { liv_unset_at(self.path, id, property) == 1 }
    }

    /// Soft, reversible, never cascades.
    func trash(_ id: UInt64) {
        act("trash") { liv_trash_at(self.path, id) == 1 }
    }

    // MARK: workspaces + saved filters (M4)

    /// Birth a workspace: Create + type + name (+ parent), one transaction.
    /// parent 0 = top level. The `query` cell is a SEPARATE `set` — the
    /// caller writes it, so one refused write never half-builds a workspace.
    func createWorkspace(
        name: String, parent: UInt64 = 0, done: ((UInt64) -> Void)? = nil
    ) {
        actId("createWorkspace", done) {
            liv_create_workspace_at(self.path, name, parent)
        }
    }

    /// Trash ONE workspace. Deletion never cascades: children keep their
    /// dangling `parent` and the shell re-roots them.
    func trashWorkspace(_ id: UInt64) {
        act("trashWorkspace") { liv_trash_workspace_at(self.path, id) == 1 }
    }

    /// Save a filter: a view entity carrying the query string. Same
    /// grammar as a workspace's, minus the stamp.
    func createView(name: String, query: String, done: ((UInt64) -> Void)? = nil) {
        actId("createView", done) {
            liv_create_view_at(self.path, name, query)
        }
    }

    /// Birth a property definition by name + value kind. `set` REFUSES an
    /// unknown property name, so a workspace whose query names a property
    /// the box has never seen must mint it before it can stamp. Minting an
    /// existing name is refused harmlessly (id 0) — never a duplicate.
    func addProperty(_ name: String, kind: String = "text", done: ((UInt64) -> Void)? = nil) {
        actId("addProperty", done) {
            liv_add_property_at(self.path, name, kind)
        }
    }

    /// Mint an option for a select/status property, BY PROPERTY ID (the
    /// snapshot's properties[] carries it). Idempotent in the core: an
    /// existing name returns the existing option's id — never a duplicate.
    /// 0 = refusal (unknown/trashed property, wrong kind, empty name).
    func addOption(_ property: UInt64, _ name: String, done: ((UInt64) -> Void)? = nil) {
        actId("addOption", done) {
            liv_add_option_at(self.path, property, name)
        }
    }

    func undo() {
        act("undo") { liv_undo_at(self.path) == 1 }
    }

    // MARK: seam reads (their own payloads, off the snapshot)

    /// The status vocabulary offered to a kind, in board order.
    func statusOptions(kind: String, done: @escaping ([StatusOption]) -> Void) {
        let path = self.path
        boxQueue.async {
            var options: [StatusOption] = []
            if let raw = liv_status_options_at(path, kind) {
                let json = String(cString: raw)
                liv_string_free(raw)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                options = (try? decoder.decode([StatusOption].self, from: Data(json.utf8))) ?? []
            }
            DispatchQueue.main.async { done(options) }
        }
    }

    /// A property's distinct live values, count-desc order preserved.
    /// Fetched once per editor open, never per keystroke.
    func distinctValues(property: String, done: @escaping ([String]) -> Void) {
        let path = self.path
        boxQueue.async {
            var values: [String] = []
            if let raw = liv_distinct_values_at(path, property) {
                let json = String(cString: raw)
                liv_string_free(raw)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let wire = (try? decoder.decode([DistinctWire].self, from: Data(json.utf8))) ?? []
                values = wire.compactMap { $0.value }
            }
            DispatchQueue.main.async { done(values) }
        }
    }

    /// One entity's content, fresh from the box — the editor's read.
    /// nil = the box itself was unavailable (probe to learn why); a doc with
    /// `missing == true` means the box opened and holds no such entity.
    /// The span encoding is capitalized ("Text"/"Break"/"Ref"), so this
    /// decoder must NOT wear the snapshot's snake_case strategy.
    func content(_ id: UInt64, done: @escaping (ContentDoc?) -> Void) {
        let path = self.path
        boxQueue.async {
            guard let raw = liv_content_at(path, id) else {
                self.verbFailed("content")
                DispatchQueue.main.async { done(nil) }
                return
            }
            let json = String(cString: raw)
            liv_string_free(raw)
            var doc: ContentDoc?
            do {
                doc = try JSONDecoder().decode(ContentDoc.self, from: Data(json.utf8))
            } catch {
                Self.log.error(
                    "content decode failed: \(String(describing: error), privacy: .public)")
            }
            DispatchQueue.main.async { done(doc) }
        }
    }

    /// Replace one entity's whole content in one transaction — the editor's
    /// save, compare-and-swap on `base`. There is no force flag by design.
    /// `done` receives (status, freshFingerprint): 1 saved (fresh valid),
    /// -1 STALE (the base moved — re-read, never overwrite), 0 busy/invalid.
    func setContent(
        _ id: UInt64, spansJson: String, base: UInt64,
        done: @escaping (Int32, UInt64) -> Void
    ) {
        let path = self.path
        boxQueue.async {
            var fresh: UInt64 = 0
            let status = liv_set_content_at(path, id, spansJson, base, &fresh)
            if status == 0 { self.verbFailed("setContent") }
            DispatchQueue.main.async {
                done(status, fresh)
                if status == 1 { self.refresh() }
            }
        }
    }

    /// Ranked hit ids for one raw DSL query — the shell already holds each
    /// row; search carries only rank. Parsed in Rust, never re-parsed here.
    func search(_ query: String, done: @escaping ([UInt64]) -> Void) {
        let path = self.path
        boxQueue.async {
            var ids: [UInt64] = []
            if let raw = liv_search_at(path, query) {
                let json = String(cString: raw)
                liv_string_free(raw)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let wire = try? decoder.decode(SearchWire.self, from: Data(json.utf8))
                ids = (wire?.hits ?? []).compactMap { $0.id }
            }
            DispatchQueue.main.async { done(ids) }
        }
    }
}

// MARK: - civil stamps (packed local-civil i64: YYYYMMDDHHMM; day = x / 10_000)

/// Calendar math on packed components only — a stamp never round-trips
/// through a timezone for storage. The core's civil dates are Gregorian by
/// construction; the user's display calendar (Buddhist, Hebrew…) never
/// leaks in.
enum Civil {
    private static let gregorian = Calendar(identifier: .gregorian)

    /// Thread-safe since iOS 7; display format, current locale.
    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = gregorian
        f.dateFormat = "EEE d MMM"
        return f
    }()

    static func todayDay() -> Int64 {
        let c = gregorian.dateComponents([.year, .month, .day], from: Date())
        return pack(c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func nowStamp() -> Int64 {
        let c = gregorian.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        return pack(c.year ?? 0, c.month ?? 0, c.day ?? 0) * 10_000
            + Int64((c.hour ?? 0) * 100 + (c.minute ?? 0))
    }

    static func stamp(day: Int64, hhmm: Int64) -> Int64 {
        day * 10_000 + hhmm
    }

    static func addDays(_ day: Int64, _ n: Int) -> Int64 {
        guard let date = date(ofDay: day),
            let moved = gregorian.date(byAdding: .day, value: n, to: date)
        else { return day }
        let c = gregorian.dateComponents([.year, .month, .day], from: moved)
        return pack(c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func day(of stamp: Int64) -> Int64 {
        stamp / 10_000
    }

    /// "14:00"; "" for 0000 (a date-only stamp carries no time).
    static func timeString(_ stamp: Int64) -> String {
        let hm = stamp % 10_000
        guard hm != 0 else { return "" }
        return String(format: "%02d:%02d", hm / 100, hm % 100)
    }

    /// "Tue 21 Jul"
    static func dayLabel(_ day: Int64) -> String {
        guard let date = date(ofDay: day) else { return "\(day)" }
        return labelFormatter.string(from: date)
    }

    static func weekdayLetter(_ day: Int64) -> String {
        guard let date = date(ofDay: day) else { return "" }
        let i = gregorian.component(.weekday, from: date) - 1
        let symbols = gregorian.veryShortWeekdaySymbols
        return symbols.indices.contains(i) ? symbols[i] : ""
    }

    static func dayNumber(_ day: Int64) -> Int {
        Int(day % 100)
    }

    private static func pack(_ y: Int, _ m: Int, _ d: Int) -> Int64 {
        Int64(y) * 10_000 + Int64(m) * 100 + Int64(d)
    }

    /// Noon anchor: components-in, components-out within one calendar; noon
    /// dodges the DST-skipped-midnight edge.
    private static func date(ofDay day: Int64) -> Date? {
        var parts = DateComponents()
        parts.year = Int(day / 10_000)
        parts.month = Int((day / 100) % 100)
        parts.day = Int(day % 100)
        parts.hour = 12
        return gregorian.date(from: parts)
    }
}
