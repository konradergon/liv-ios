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
    /// The ids of everything in the trash, newest first (2026-08-20). An id
    /// list like `everything`; the rows are in `entities` carrying
    /// `trashed: true`. Optional, like every wire addition — one missing
    /// key must never drop the whole snapshot.
    var trashed: [UInt64]?
    var properties: [PropertyRow]?
    var kinds: [KindRow]?
    /// The workspace tree (M4). Shapes live in Workspace.swift.
    var workspaces: [WorkspaceRow]?
    /// Saved filters — view entities with a `query` cell (M4).
    var views: [SavedViewRow]?
    /// The clerk's pending proposals (rev 6: the Properties panel's
    /// Suggestions). Force-empty on the wire while assist is off.
    var inbox: [ProposalRow]?
    /// The assist switch — the consent that gates every clerk proposal.
    var assist: AssistRow?
    /// Open checkbox lines inside notes (phase 3) — the Tasks view's
    /// "In notes" section. A projection: nothing here is stored.
    var noteTasks: [NoteTaskRow]?
}

/// One open `- [ ]` line inside a note (phase 3, services/src/tasks.rs).
/// Every field Optional — the standing law.
struct NoteTaskRow: Decodable, Identifiable {
    /// Stable per line, so SwiftUI keeps rows in place across refreshes.
    var id: String { "\(entity ?? 0).\(line ?? 0)" }
    /// The note that holds the line.
    var entity: UInt64? = nil
    /// What to call that note — computed in Rust, where the content is
    /// (never EntityRow.title, which flattens the whole body).
    var source: String? = nil
    /// Line index in the buffer — the toggle's address.
    var line: Int? = nil
    var text: String? = nil
    var indent: Int? = nil
}

/// One clerk proposal (mirrors the archived macOS shell's shape). The
/// fingerprint rides back on accept/reject — a consent is to a PROPOSAL,
/// never a position, so a stale click is refused, not misapplied.
struct ProposalRow: Decodable, Identifiable {
    var id: String { "\(entity ?? 0).\(fingerprint ?? 0)" }
    var entity: UInt64? = nil
    var ordinal: UInt32? = nil
    var fingerprint: UInt64? = nil
    var reason: String? = nil
    var author: String? = nil
    /// The structured writes this proposal makes — the diff's source.
    var commands: [ProposalCommandRow]? = nil
}

/// One command of a proposal, for the +/− diff.
struct ProposalCommandRow: Decodable {
    var kind: String? = nil  // add | remove | trash | redirect | create | restore
    var property: String? = nil
    var value: String? = nil
    var valueKind: String? = nil
    var refTarget: UInt64? = nil
}

/// The assist switch: the entity the toggle writes to, and the switch
/// property's CURRENT name (survives a definition rename).
struct AssistRow: Decodable {
    var id: UInt64? = nil
    var on: Bool? = nil
    var prop: String? = nil
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
    /// The seq of the newest transaction that touched this — a
    /// MONOTONIC recency key, not a date (2026-08-18). Docs sorts on it;
    /// it must never be printed as a time.
    var recency: UInt64? = nil

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

/// One end of a link, as the box reports it (liv_links_at). EVERY field
/// Optional — the standing law.
struct LinkRow: Decodable, Identifiable, Equatable {
    var id: UInt64?
    var name: String?
    var kinds: [String]?
    /// "related" for a link picked in properties, "content" for one typed
    /// in a body.
    var property: String?
    /// Typed in a body: the brackets ARE the link, so it is removed by
    /// editing the words, never from a list.
    var fromBody: Bool?
}

/// Both directions at once — what this thing points at, and what points
/// at it. `inbound` is the wire's `in` (a Swift keyword).
struct LinkSet: Decodable, Equatable {
    var out: [LinkRow]?
    var inbound: [LinkRow]?

    enum CodingKeys: String, CodingKey {
        case out
        case inbound = "in"
    }

    static let empty = LinkSet(out: [], inbound: [])
    var outRows: [LinkRow] { out ?? [] }
    var inRows: [LinkRow] { inbound ?? [] }
    var isEmpty: Bool { outRows.isEmpty && inRows.isEmpty }
}

// MARK: - private wires (payloads the model flattens before publishing)

private struct DistinctWire: Decodable {
    var value: String?
    var count: Int?
}

private struct SearchWire: Decodable {
    struct Hit: Decodable { var id: UInt64? }
    var hits: [Hit]?
    /// The counts the core already computed and the shell was throwing
    /// away. `services::search::facet` runs one probe query per candidate
    /// value on every search and sends back, per property, how many
    /// results each value WOULD leave — plus whether the current query
    /// already includes or excludes it. None of it reached a screen.
    var facets: [FacetWire]?
    /// How many matched IN TOTAL. The core ranks everything and sends
    /// the first 200; the shell was throwing this away, so a query
    /// matching 1,800 things showed 200 and said nothing about the
    /// other 1,600 (found 2026-08-08).
    var total: Int?
}

private struct FacetWire: Decodable {
    /// The property's name, which is also its spelling in the query DSL —
    /// `type:task` resolves by name (services/src/search.rs).
    var label: String?
    var values: [ValueWire]?

    struct ValueWire: Decodable {
        var label: String?
        var count: Int?
        var active: Bool?
        var excluded: Bool?
    }
}

/// One property's facet: its name, and every value worth offering.
///
/// The `value` field on the wire is deliberately NOT decoded. A chip needs
/// the label (which is the query spelling), the count, and the two state
/// flags; decoding the core's `Value` enum would couple the shell to that
/// enum's JSON shape for nothing.
struct LivFacet: Identifiable {
    let label: String
    let values: [LivFacetValue]
    var id: String { label }
}

struct LivFacetValue: Identifiable {
    let label: String
    let count: Int
    /// The query INCLUDES this value. The core decides this, not the shell —
    /// so a chip drawn from a hand-typed query is still right.
    let active: Bool
    /// The query EXCLUDES it. include -> exclude -> off is the cycle
    /// (bp3 a19, services/src/search.rs).
    let excluded: Bool
    var id: String { label }
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

    /// The row for an id, whether or not it is in the trash. Use this for
    /// EXISTENCE — "has this box ever heard of it?" — which is what the
    /// editor's link oracle asks.
    func entity(_ id: UInt64) -> EntityRow? {
        entities[id]
    }

    /// The row for an id, but only if it is LIVE. Use this for anything
    /// that opens, renders or navigates.
    ///
    /// The two used to be the same call, because the snapshot filtered
    /// trashed rows out entirely and `entity(_:)` could only ever return a
    /// live one. Since 2026-08-20 the trash rides the wire — which is what
    /// stops the editor demoting a link to a trashed note — so every site
    /// that meant "alive" and wrote "exists" would silently start opening
    /// deleted things. A rule that matters lives in a type, not a comment.
    func live(_ id: UInt64) -> EntityRow? {
        guard let row = entities[id], row.trashed != true else { return nil }
        return row
    }

    // MARK: reads

    /// Re-snapshot, keeping the last-used occurrence window (default:
    /// liv_snapshot's current month).
    /// A read is in the air; and one more was asked for while it was.
    ///
    /// One typed task fires createTask, set(name), setSpan(due) and
    /// stamp — four writes, each scheduling its own full re-read of the
    /// whole box. Only the last answer is ever seen, so three were
    /// waste (measured 2026-08-08).
    ///
    /// Collapsing them must never lose the LAST one: a read that is
    /// already in the air may have been taken before the write that
    /// asked for this one. So a request during a read is remembered and
    /// re-run when it lands, rather than dropped.
    private var refreshInFlight = false
    private var refreshAgain = false

    func refresh() {
        if refreshInFlight {
            refreshAgain = true
            return
        }
        refreshInFlight = true
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
                self.refreshLanded()
                return
            }
            self.applySnapshot(raw)
            self.refreshLanded()
        }
    }

    /// One read finished. If anything asked for another while it was in
    /// the air, run exactly one more.
    private func refreshLanded() {
        DispatchQueue.main.async {
            self.refreshInFlight = false
            if self.refreshAgain {
                self.refreshAgain = false
                self.refresh()
            }
        }
    }

    /// Point the snapshot at a caller-chosen occurrence window (civil
    /// YYYYMMDDHHMM bounds) and reload. Sticks across later refreshes.
    func refreshWindow(from: Int64, to: Int64) {
        window = (from, to)
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

    /// An empty, typed note — the editor's own creation door. Unlike
    /// `capture`, which refuses empty text (a blank thought is not a
    /// capture), this births the entity so the caret has somewhere to land.
    func createNote(done: ((UInt64) -> Void)? = nil) {
        actId("createNote", Outbox.tracking(.idea, done)) { liv_create_note_at(self.path) }
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
    /// One value of a multi-valued property, removed by value — the
    /// mirror of addCell. `unset` clears the whole property instead.
    func removeCell(_ id: UInt64, _ property: String, _ value: String, done: ((Bool) -> Void)? = nil) {
        act("removeCell", done) {
            liv_remove_cell_at(self.path, id, property, value) == 1
        }
    }

    func unset(_ id: UInt64, _ property: String) {
        act("unset") { liv_unset_at(self.path, id, property) == 1 }
    }

    /// Put a trashed thing back — the inverse of `trash`, and the door
    /// that did not exist until 2026-08-20. Before it, undo-right-after was
    /// the only recovery, and only while the trash was still the last
    /// transaction; after any other write the thing was unreachable.
    func restore(_ id: UInt64, done: ((Bool) -> Void)? = nil) {
        act("restore", done) { liv_restore_at(self.path, id) == 1 }
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

    /// Rename ONE VALUE everywhere it is carried — one grouped
    /// transaction, one undo step (P19b).
    ///
    /// Text cells rewrite; a select or status renames the option, or
    /// MERGES into an existing one when the new name is already taken.
    /// That merge is the reason this cannot be N per-entity writes from
    /// the shell: only the core can see every carrier at once.
    ///
    /// `done` receives the number of carriers changed, or nil on refusal
    /// (unknown property, wrong kind, empty or unchanged name).
    func renameValue(
        property: String, from old: String, to new: String,
        done: @escaping (Int?) -> Void
    ) {
        let path = self.path
        boxQueue.async {
            let n = liv_rename_value_at(path, property, old, new)
            DispatchQueue.main.async {
                done(n < 0 ? nil : Int(n))
                if n > 0 { self.refresh() }
            }
        }
    }

    func undo() {
        act("undo") { liv_undo_at(self.path) == 1 }
    }

    // MARK: the clerk's proposals (rev 6 — suggest, never act)

    /// The pending proposals aimed at one entity, off the live snapshot.
    func proposals(for entity: UInt64) -> [ProposalRow] {
        (snap?.inbox ?? []).filter { $0.entity == entity }
    }

    /// Consent to ONE proposal. The fingerprint makes a stale consent a
    /// refusal (returns 0), never a misapplied write.
    func accept(_ p: ProposalRow) {
        act("accept") {
            liv_accept_at(self.path, p.entity ?? 0, p.ordinal ?? 0, p.fingerprint ?? 0) == 1
        }
    }

    /// Decline ONE proposal — persisted; the clerk never re-asks.
    func reject(_ p: ProposalRow) {
        act("reject") {
            liv_reject_at(self.path, p.entity ?? 0, p.ordinal ?? 0, p.fingerprint ?? 0) == 1
        }
    }

    /// Consent to a whole group as ONE transaction, one undo — the
    /// members' fingerprints through liv_accept_group_at (all-or-nothing;
    /// a stale member refuses the lot).
    func acceptGroup(_ fingerprints: [UInt64], done: ((Bool) -> Void)? = nil) {
        let json =
            (try? String(data: JSONEncoder().encode(fingerprints), encoding: .utf8)) ?? "[]"
        act("acceptGroup", done) { liv_accept_group_at(self.path, json) == 1 }
    }

    /// A fresh entity wearing another's property cells — the filing
    /// context without the body (rev 6, "Duplicate note"). Identity and
    /// content stay behind, and so does a `template` cell: the feature
    /// is gone (2026-08-15) but boxes written before it went carry the
    /// marker, and a copy must not spread it. Owner rulings
    /// (2026-08-04): the TYPE copies too (a duplicated task is a task),
    /// and reference/file cells are SKIPPED — the wire carries their
    /// display value, and re-adding by display string can silently link
    /// the wrong entity, which is worse than no link.
    func duplicateProperties(of source: UInt64, done: ((UInt64) -> Void)? = nil) {
        guard let row = entity(source) else {
            done?(0)
            return
        }
        let skip: Set<String> = ["name", "content", "created", "type", "template"]
        let skipKinds: Set<String> = ["datetime", "reference", "file"]
        createNote { copy in
            guard copy != 0 else {
                done?(0)
                return
            }
            if let kind = row.kinds?.first, !kind.isEmpty, kind != "note" {
                self.setType(copy, kind)
            }
            for cell in row.cells ?? [] {
                guard let property = cell.property, let value = cell.value,
                    !value.isEmpty, !skip.contains(property),
                    // Datetime copies structurally below; reference/file
                    // never copy (see above).
                    !skipKinds.contains(cell.kind ?? "")
                else { continue }
                self.addCell(copy, property, value)
            }
            if let due = row.due {
                let property = (row.positionedBy?.isEmpty == false ? row.positionedBy! : "due")
                self.setSpan(
                    copy, property, start: due, end: row.dueEnd ?? 0,
                    dateOnly: row.dueDateOnly ?? false)
            }
            done?(copy)
        }
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

    /// Both directions of one entity's links (liv_links_at): what it
    /// points at, and what points at it. A `[[ ]]` typed in a body and a
    /// link picked in properties are the same edge — the core indexes
    /// both — so this is the only reader either list needs.
    func links(_ id: UInt64, done: @escaping (LinkSet) -> Void) {
        let path = self.path
        boxQueue.async {
            guard let raw = liv_links_at(path, id) else {
                self.verbFailed("links")
                DispatchQueue.main.async { done(.empty) }
                return
            }
            let json = String(cString: raw)
            liv_string_free(raw)
            var set = LinkSet.empty
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                set = try decoder.decode(LinkSet.self, from: Data(json.utf8))
            } catch {
                Self.log.error(
                    "links decode failed: \(String(describing: error), privacy: .public)")
            }
            DispatchQueue.main.async { done(set) }
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
    // MARK: files — the bytes stay on disk; the box holds a reference

    /// Re-hash the referenced path. The core rewrites the file cell when
    /// the bytes changed — a changed hash IS the integration, so opening
    /// a file is how Liv learns Word saved it. Never on a timer.
    /// `done` gets true when something changed, so the caller can
    /// refresh rather than guess.
    func resyncFile(_ id: UInt64, done: ((Bool) -> Void)? = nil) {
        boxQueue.async {
            let status = liv_resync_file_at(self.path, id)
            DispatchQueue.main.async {
                done?(status == 1)
                if status == 1 { self.refresh() }
            }
        }
    }

    /// One term of a query, as the CORE lexed it.
    ///
    /// The shell used to lex this itself and the two disagreed sixteen
    /// ways — `Area:Work` found nothing, a typo filtered nothing,
    /// `is:archived` meant the opposite thing. There is one lexer now and
    /// it is in Rust (`services::search::lex`).
    struct LivQueryTerm: Decodable, Equatable {
        /// equals | notequals | atmost | has | no | is | text
        let op: String
        let key: String
        let value: String
        /// The token respelled canonically, so joining a term list
        /// reproduces a query the core reads back the same way.
        let raw: String
    }

    /// Lex a query into terms. Synchronous, because it opens nothing: the
    /// core's `lex` consults no store, so a picker editing a DRAFT query
    /// can call it per keystroke without touching the box lock.
    func lex(_ raw: String) -> [LivQueryTerm] {
        guard let out = liv_lex(raw) else { return [] }
        let json = String(cString: out)
        liv_string_free(out)
        return (try? JSONDecoder().decode([LivQueryTerm].self, from: Data(json.utf8))) ?? []
    }

    /// Which entities a LENS admits, and the terms it is made of.
    ///
    /// `is:archived` RESTRICTS here — a workspace called Archive shows the
    /// archive — where the same token WIDENS in `search` (owner,
    /// 2026-08-27). Uncapped: search sends a 200-row page, which is a page
    /// and not a membership set.
    func query(
        _ raw: String,
        done: @escaping (Set<UInt64>, [LivQueryTerm]) -> Void
    ) {
        let path = self.path
        boxQueue.async {
            var ids: Set<UInt64> = []
            var terms: [LivQueryTerm] = []
            if let out = liv_query_ids_at(path, raw) {
                let json = String(cString: out)
                liv_string_free(out)
                struct Wire: Decodable {
                    var ids: [UInt64]?
                    var terms: [LivQueryTerm]?
                }
                if let w = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) {
                    ids = Set(w.ids ?? [])
                    terms = w.terms ?? []
                }
            }
            DispatchQueue.main.async { done(ids, terms) }
        }
    }

    // MARK: the vault — a projection, never a second truth

    /// What the folder around the box is, if anything.
    ///
    /// The ruling is O14 (`design/p20j-files-projection.md` §1): the box
    /// stays the ONE truth and the vault folder is a total, continuously
    /// reconciled, rebuildable PROJECTION with an inbound ingest channel.
    /// An external edit is not truth until ingested — a window of
    /// scan-at-open plus a debounce, which the design flags as its one
    /// honest cost (F1).
    ///
    /// `legacy` means the box is not inside a vault folder, so there is no
    /// projection to speak of. Cheap: no scan.
    struct LivVaultStatus {
        let mode: String
        let root: String
        let files: Int
        var isVault: Bool { mode == "vault" }
    }

    /// One divergence the last scan found. `kind` is
    /// conflict | missing | newfile | masschange | orphan | edited.
    struct LivVaultFinding: Identifiable {
        let kind: String
        let path: String
        let count: Int
        var id: String { kind + ":" + path }
    }

    func vaultStatus(done: @escaping (LivVaultStatus?) -> Void) {
        let path = self.path
        boxQueue.async {
            var out: LivVaultStatus?
            if let raw = liv_vault_status_at(path) {
                let json = String(cString: raw)
                liv_string_free(raw)
                struct Wire: Decodable { var mode: String?; var root: String?; var files: Int? }
                if let w = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) {
                    out = LivVaultStatus(
                        mode: w.mode ?? "legacy", root: w.root ?? "", files: w.files ?? 0)
                }
            }
            DispatchQueue.main.async { done(out) }
        }
    }

    /// Scan, ingest every tier-A finding as ONE "vault-edit" transaction,
    /// adopt, re-project. One user action, one transaction, one undo step.
    /// `nil` means busy or legacy — never a silent no-op.
    func vaultSync(done: @escaping ((edited: Int, created: Int, surfaced: Int)?) -> Void) {
        let path = self.path
        boxQueue.async {
            var out: (edited: Int, created: Int, surfaced: Int)?
            if let raw = liv_vault_sync_at(path) {
                let json = String(cString: raw)
                liv_string_free(raw)
                struct Wire: Decodable { var edited: Int?; var created: Int?; var surfaced: Int? }
                if let w = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) {
                    out = (w.edited ?? 0, w.created ?? 0, w.surfaced ?? 0)
                }
            }
            DispatchQueue.main.async {
                done(out)
                if let out, out.edited + out.created > 0 { self.refresh() }
            }
        }
    }

    /// Re-materialize every file from an empty manifest, so the folder
    /// returns byte-identical even when the manifest lies. This is the
    /// half of "rebuildable" the constitution permits: the projection
    /// rebuilds from the log, never the log from the files.
    /// Returns the file count, or nil on busy/legacy/failure.
    func vaultRebuild(done: @escaping (Int?) -> Void) {
        let path = self.path
        boxQueue.async {
            let n = liv_vault_rebuild_at(path)
            DispatchQueue.main.async { done(n < 0 ? nil : Int(n)) }
        }
    }

    /// A read-only scan: what has diverged, without ingesting any of it.
    func vaultFindings(all: Bool = false, done: @escaping ([LivVaultFinding]) -> Void) {
        let path = self.path
        boxQueue.async {
            var out: [LivVaultFinding] = []
            if let raw = liv_vault_findings_at(path, all ? 1 : 0) {
                let json = String(cString: raw)
                liv_string_free(raw)
                struct Wire: Decodable { var kind: String?; var path: String?; var count: Int? }
                let wire = (try? JSONDecoder().decode([Wire].self, from: Data(json.utf8))) ?? []
                out = wire.compactMap { w in
                    guard let k = w.kind else { return nil }
                    return LivVaultFinding(kind: k, path: w.path ?? "", count: w.count ?? 0)
                }
            }
            DispatchQueue.main.async { done(out) }
        }
    }

    /// The vault's self-defense notices — a length regression, an in-place
    /// replacement, a conflicted-copy sibling. READ AND CLEAR: whoever
    /// asks gets them once, so they must be shown, not counted.
    func vaultAlerts(done: @escaping ([String]) -> Void) {
        let path = self.path
        boxQueue.async {
            var out: [String] = []
            if let raw = liv_vault_alerts_at(path) {
                let json = String(cString: raw)
                liv_string_free(raw)
                out = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
            }
            DispatchQueue.main.async { done(out) }
        }
    }

    /// `done` receives the page of ids AND the true total, so a capped
    /// result can say so instead of quietly looking complete.
    func search(
        _ query: String,
        done: @escaping ([UInt64], Int, [LivFacet]) -> Void
    ) {
        let path = self.path
        boxQueue.async {
            var ids: [UInt64] = []
            var total = 0
            var facets: [LivFacet] = []
            if let raw = liv_search_at(path, query) {
                let json = String(cString: raw)
                liv_string_free(raw)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let wire = try? decoder.decode(SearchWire.self, from: Data(json.utf8))
                ids = (wire?.hits ?? []).compactMap { $0.id }
                total = wire?.total ?? ids.count
                facets = (wire?.facets ?? []).compactMap { f in
                    guard let label = f.label, !label.isEmpty else { return nil }
                    let values: [LivFacetValue] = (f.values ?? []).compactMap { v in
                        guard let vl = v.label, !vl.isEmpty else { return nil }
                        return LivFacetValue(
                            label: vl, count: v.count ?? 0,
                            active: v.active ?? false, excluded: v.excluded ?? false)
                    }
                    return values.isEmpty ? nil : LivFacet(label: label, values: values)
                }
            }
            DispatchQueue.main.async { done(ids, total, facets) }
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
    ///
    /// This was `private`, so five other files wrote it out again — each
    /// with its own copy of the noon trick, which is how a real
    /// daylight-saving bug eventually arrives (owner, 2026-08-07). It is
    /// the one gregorian calendar in the shell now.
    static func date(ofDay day: Int64) -> Date? {
        var parts = DateComponents()
        parts.year = Int(day / 10_000)
        parts.month = Int((day / 100) % 100)
        parts.day = Int(day % 100)
        parts.hour = 12
        return gregorian.date(from: parts)
    }

    /// A packed civil day (+ HHMM) as a real moment, for seeding pickers.
    static func date(day: Int64, hhmm: Int64) -> Date? {
        var parts = DateComponents()
        parts.year = Int(day / 10_000)
        parts.month = Int((day / 100) % 100)
        parts.day = Int(day % 100)
        parts.hour = Int(hhmm / 100)
        parts.minute = Int(hhmm % 100)
        return gregorian.date(from: parts)
    }

    /// The civil day a picker is sitting on.
    static func day(of date: Date) -> Int64 {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return pack(c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The clock time a picker is sitting on, packed HHMM.
    static func hhmm(of date: Date) -> Int64 {
        let c = gregorian.dateComponents([.hour, .minute], from: date)
        return Int64((c.hour ?? 0) * 100 + (c.minute ?? 0))
    }

    /// 1 = Sunday … 7 = Saturday, the Gregorian numbering.
    static func weekday(_ day: Int64) -> Int {
        guard let date = date(ofDay: day) else { return 0 }
        return gregorian.component(.weekday, from: date)
    }

    /// Whole days from `a` to `b`, signed.
    static func daysBetween(_ a: Int64, _ b: Int64) -> Int {
        guard let da = date(ofDay: a), let db = date(ofDay: b) else { return 0 }
        return gregorian.dateComponents([.day], from: da, to: db).day ?? 0
    }
}
