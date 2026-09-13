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
    var today, unstructured, everything, dated: [LivEntityID]?
    var occurrences: [Occurrence]?
    var entities: [EntityRow]?
    /// The ids of everything in the trash, newest first (2026-08-20). An id
    /// list like `everything`; the rows are in `entities` carrying
    /// `trashed: true`. Optional, like every wire addition — one missing
    /// key must never drop the whole snapshot.
    var trashed: [LivEntityID]?
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
    var id: String { "\(LivIDText.written(entity ?? .absent)).\(line ?? 0)" }
    /// The note that holds the line.
    var entity: LivEntityID? = nil
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
    var id: String { "\(LivIDText.written(entity ?? .absent)).\(fingerprint ?? 0)" }
    var entity: LivEntityID? = nil
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
    var refTarget: LivEntityID? = nil
}

/// The assist switch: the entity the toggle writes to, and the switch
/// property's CURRENT name (survives a definition rename).
struct AssistRow: Decodable {
    var id: LivEntityID? = nil
    var on: Bool? = nil
    var prop: String? = nil
}

/// Optionals carry `= nil` so the memberwise initializer has defaults —
/// the workspace self-check builds rows by hand, and a 15-argument call
/// would be a test that lies about what it is testing.
struct EntityRow: Decodable, Identifiable {
    var id: LivEntityID
    var title: String? = nil
    /// The title was MADE, not given — see `livRowIsUntitled`.
    var untitled: Bool? = nil
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
    var propertyId: LivEntityID? = nil
    var property: String? = nil
    var kind: String? = nil
    var value: String? = nil
    var refTarget: LivEntityID? = nil
}

struct Occurrence: Decodable {
    var series: LivEntityID?
    var civil: Int64?
}

struct PropertyRow: Decodable {
    var id: LivEntityID?
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
    var id: LivEntityID?
    var name: String?
    var hidden: Bool?
}

struct KindRow: Decodable {
    var id: LivEntityID?
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
    var id: LivEntityID?
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

/// One past version of an entity's content (liv_content_history_at).
/// EVERY field Optional — the standing law. `spans` is the same shape
/// `ContentDoc.spans` carries, so a restore is `SpanText.json` of it
/// handed back to `setContent`.
struct ContentVersion: Decodable {
    var seq: UInt64?
    /// Unix seconds — the core's `now()`.
    var time: Int64?
    var author: String?
    var label: String?
    var spans: [SpanJSON]?
}

/// One end of a link, as the box reports it (liv_links_at). EVERY field
/// Optional — the standing law.
struct LinkRow: Decodable, Identifiable, Equatable {
    var id: LivEntityID?
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
    struct Hit: Decodable { var id: LivEntityID? }
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
    private(set) var entities: [LivEntityID: EntityRow] = [:]

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
    func entity(_ id: LivEntityID) -> EntityRow? {
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
    func live(_ id: LivEntityID) -> EntityRow? {
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
        var index = [LivEntityID: EntityRow](minimumCapacity: fresh.entities?.count ?? 0)
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
    ///
    /// **The ONE place a `core/` id becomes a `LivID`.** Every creating
    /// verb in the old ABI returns a raw `UInt64`, so the conversion
    /// belongs here rather than at nine call sites — and when slice 5
    /// swaps the source, this is the one line that changes.
    private func actId(
        _ verb: String, _ done: ((LivEntityID) -> Void)?, _ work: @escaping () -> UInt64
    ) {
        boxQueue.async {
            let id = LivEntityID(core: work())
            if id.isAbsent { self.verbFailed(verb) }
            DispatchQueue.main.async {
                done?(id)
                if !id.isAbsent { self.refresh() }
            }
        }
    }

    func capture(_ text: String, done: ((LivEntityID) -> Void)? = nil) {
        actId("capture", Outbox.tracking(.idea, done)) { liv_capture_at(self.path, text) }
    }

    /// An empty, typed note — the editor's own creation door. Unlike
    /// `capture`, which refuses empty text (a blank thought is not a
    /// capture), this births the entity so the caret has somewhere to land.
    func createNote(done: ((LivEntityID) -> Void)? = nil) {
        actId("createNote", Outbox.tracking(.idea, done)) { liv_create_note_at(self.path) }
    }

    func createTask(done: ((LivEntityID) -> Void)? = nil) {
        actId("createTask", Outbox.tracking(.task, done)) { liv_create_task_at(self.path) }
    }

    func createEvent(dueCivil: Int64, dateOnly: Bool, done: ((LivEntityID) -> Void)? = nil) {
        actId("createEvent", Outbox.tracking(.event, done)) { liv_create_event_at(self.path, dueCivil, dateOnly ? 1 : 0) }
    }

    func set(_ id: LivEntityID, _ property: String, _ value: String, done: ((Bool) -> Void)? = nil) {
        act("set", done) { liv_set_at(self.path, id.core, property, value) == 1 }
    }

    /// One span write (the mirror contract). end <= 0 = no end (plain date);
    /// dateOnly applies to both ends.
    func setSpan(
        _ id: LivEntityID, _ property: String, start: Int64, end: Int64, dateOnly: Bool,
        done: ((Bool) -> Void)? = nil
    ) {
        act("setSpan", done) {
            liv_set_span_at(self.path, id.core, property, start, end <= 0 ? 0 : end, dateOnly ? 1 : 0) == 1
        }
    }

    func setType(_ id: LivEntityID, _ type: String, done: ((Bool) -> Void)? = nil) {
        act("setType", done) { liv_set_type_at(self.path, id.core, type) == 1 }
    }

    /// One cell of a multi-valued property — membership, never replace-all.
    func addCell(_ id: LivEntityID, _ property: String, _ value: String, done: ((Bool) -> Void)? = nil) {
        act("addCell", done) { liv_add_cell_at(self.path, id.core, property, value) == 1 }
    }

    /// The librarian: by reference, never moves the file.
    func addFile(_ path: String, done: ((LivEntityID) -> Void)? = nil) {
        actId("addFile", Outbox.tracking(.photo, done)) { liv_add_file_at(self.path, path) }
    }

    /// Remove EVERY cell of one property — the inverse of `set`. This is
    /// how a capture-time stamp chip is taken back off.
    /// One value of a multi-valued property, removed by value — the
    /// mirror of addCell. `unset` clears the whole property instead.
    func removeCell(_ id: LivEntityID, _ property: String, _ value: String, done: ((Bool) -> Void)? = nil) {
        act("removeCell", done) {
            liv_remove_cell_at(self.path, id.core, property, value) == 1
        }
    }

    func unset(_ id: LivEntityID, _ property: String) {
        act("unset") { liv_unset_at(self.path, id.core, property) == 1 }
    }

    /// Put a trashed thing back — the inverse of `trash`, and the door
    /// that did not exist until 2026-08-20. Before it, undo-right-after was
    /// the only recovery, and only while the trash was still the last
    /// transaction; after any other write the thing was unreachable.
    func restore(_ id: LivEntityID, done: ((Bool) -> Void)? = nil) {
        act("restore", done) { liv_restore_at(self.path, id.core) == 1 }
    }

    /// Soft, reversible, never cascades.
    func trash(_ id: LivEntityID) {
        act("trash") { liv_trash_at(self.path, id.core) == 1 }
    }

    // MARK: workspaces + saved filters (M4)

    /// Birth a workspace: Create + type + name (+ parent), one transaction.
    /// parent 0 = top level. The `query` cell is a SEPARATE `set` — the
    /// caller writes it, so one refused write never half-builds a workspace.
    func createWorkspace(
        name: String, parent: LivEntityID = 0, done: ((LivEntityID) -> Void)? = nil
    ) {
        actId("createWorkspace", done) {
            liv_create_workspace_at(self.path, name, parent.core)
        }
    }

    /// Trash ONE workspace. Deletion never cascades: children keep their
    /// dangling `parent` and the shell re-roots them.
    func trashWorkspace(_ id: LivEntityID) {
        act("trashWorkspace") { liv_trash_workspace_at(self.path, id.core) == 1 }
    }

    /// Save a filter: a view entity carrying the query string. Same
    /// grammar as a workspace's, minus the stamp.
    func createView(name: String, query: String, done: ((LivEntityID) -> Void)? = nil) {
        actId("createView", done) {
            liv_create_view_at(self.path, name, query)
        }
    }

    /// Birth a property definition by name + value kind. `set` REFUSES an
    /// unknown property name, so a workspace whose query names a property
    /// the box has never seen must mint it before it can stamp. Minting an
    /// existing name is refused harmlessly (id 0) — never a duplicate.
    func addProperty(_ name: String, kind: String = "text", done: ((LivEntityID) -> Void)? = nil) {
        actId("addProperty", done) {
            liv_add_property_at(self.path, name, kind)
        }
    }

    /// Mint an option for a select/status property, BY PROPERTY ID (the
    /// snapshot's properties[] carries it). Idempotent in the core: an
    /// existing name returns the existing option's id — never a duplicate.
    /// 0 = refusal (unknown/trashed property, wrong kind, empty name).
    func addOption(_ property: LivEntityID, _ name: String, done: ((LivEntityID) -> Void)? = nil) {
        actId("addOption", done) {
            liv_add_option_at(self.path, property.core, name)
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
    func proposals(for entity: LivEntityID) -> [ProposalRow] {
        (snap?.inbox ?? []).filter { $0.entity == entity }
    }

    /// Consent to ONE proposal. The fingerprint makes a stale consent a
    /// refusal (returns 0), never a misapplied write. `done` is for a
    /// caller that files on top of the consent (the Inbox's suggested
    /// area, 2026-09-09) and must not write into a refusal.
    func accept(_ p: ProposalRow, done: ((Bool) -> Void)? = nil) {
        act("accept", done) {
            liv_accept_at(self.path, (p.entity ?? .absent).core, p.ordinal ?? 0, p.fingerprint ?? 0) == 1
        }
    }

    /// Decline ONE proposal — persisted; the clerk never re-asks.
    func reject(_ p: ProposalRow) {
        act("reject") {
            liv_reject_at(self.path, (p.entity ?? .absent).core, p.ordinal ?? 0, p.fingerprint ?? 0) == 1
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
    func duplicateProperties(of source: LivEntityID, done: ((LivEntityID) -> Void)? = nil) {
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
    func content(_ id: LivEntityID, done: @escaping (ContentDoc?) -> Void) {
        let path = self.path
        boxQueue.async {
            guard let raw = liv_content_at(path, id.core) else {
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

    /// EVERY PAST VERSION of one entity's content, NEWEST first
    /// (liv_content_history_at). The log is the history: each entry is a
    /// whole content value, and restoring one is an ordinary `setContent`
    /// of its spans over a freshly read base — the restore is appended as
    /// a new version, and the log is never rewritten.
    ///
    /// The verb has been in the ABI and tested three times since the
    /// history was built; until 2026-09-09 nothing in the shell called
    /// it, so the thesis's "read what you wrote three weeks ago, put it
    /// back" was core-only.
    func history(_ id: LivEntityID, done: @escaping ([ContentVersion]) -> Void) {
        let path = self.path
        boxQueue.async {
            guard let raw = liv_content_history_at(path, id.core) else {
                self.verbFailed("history")
                DispatchQueue.main.async { done([]) }
                return
            }
            let json = String(cString: raw)
            liv_string_free(raw)
            var versions: [ContentVersion] = []
            do {
                versions = try JSONDecoder().decode([ContentVersion].self, from: Data(json.utf8))
            } catch {
                Self.log.error(
                    "history decode failed: \(String(describing: error), privacy: .public)")
            }
            DispatchQueue.main.async { done(versions) }
        }
    }

    /// Both directions of one entity's links (liv_links_at): what it
    /// points at, and what points at it. A `[[ ]]` typed in a body and a
    /// link picked in properties are the same edge — the core indexes
    /// both — so this is the only reader either list needs.
    func links(_ id: LivEntityID, done: @escaping (LinkSet) -> Void) {
        let path = self.path
        boxQueue.async {
            guard let raw = liv_links_at(path, id.core) else {
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
        _ id: LivEntityID, spansJson: String, base: UInt64,
        done: @escaping (Int32, UInt64) -> Void
    ) {
        let path = self.path
        boxQueue.async {
            var fresh: UInt64 = 0
            let status = liv_set_content_at(path, id.core, spansJson, base, &fresh)
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
    func resyncFile(_ id: LivEntityID, done: ((Bool) -> Void)? = nil) {
        boxQueue.async {
            let status = liv_resync_file_at(self.path, id.core)
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
        done: @escaping (Set<LivEntityID>, [LivQueryTerm]) -> Void
    ) {
        let path = self.path
        boxQueue.async {
            var ids: Set<LivEntityID> = []
            var terms: [LivQueryTerm] = []
            if let out = liv_query_ids_at(path, raw) {
                let json = String(cString: out)
                liv_string_free(out)
                struct Wire: Decodable {
                    var ids: [LivEntityID]?
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

    // THE VAULT'S FOUR OTHER DOORS ARE GONE (2026-09-12), with the card
    // that was their only caller: `LivVaultStatus`, `LivVaultFinding`,
    // `vaultStatus`, `vaultSync`, `vaultRebuild`, `vaultFindings`.
    //
    // Not because the projection is a bad idea — because on a phone none
    // of them could ever do anything. `vault_root_of` wants the log at
    // `<root>/.liv/box/<log>`; `BoxPath.resolve` puts it under an App
    // Group container at `<container>/liv/liv.log`. Every one of those
    // verbs opens with its own `vault_root_of` guard and returns early,
    // so the wrappers marshalled a refusal. Standing rule 6, and the
    // owner's word on the card they fed.
    //
    // The five FFI verbs and the CLI's `liv vault` keep them: a vault is
    // a folder on a computer, and that is where a shell over this core
    // has a reachable surface for them. Restoring the phone's reach is
    // this comment plus a caller.

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
        done: @escaping ([LivEntityID], Int, [LivFacet]) -> Void
    ) {
        let path = self.path
        boxQueue.async {
            var ids: [LivEntityID] = []
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

    /// A packed civil day as DAYS SINCE THE EPOCH, which is what the
    /// engine counts in.
    ///
    /// **Two different numbers that both look like a date.** `Civil` packs
    /// `YYYYMMDD`; the engine counts days from 1970-01-01. Handing one
    /// where the other is expected is not a rounding error, it is a date
    /// four hundred thousand years out — so the conversion is named and
    /// lives here, next to the packing it undoes.
    ///
    /// Both ends are anchored at noon, the same trick `date(ofDay:)` uses,
    /// so a daylight-saving boundary between them cannot lose a day.
    static func epochDay(_ day: Int64) -> Int32 {
        var epoch = DateComponents()
        epoch.year = 1970
        epoch.month = 1
        epoch.day = 1
        epoch.hour = 12
        guard let from = gregorian.date(from: epoch), let to = date(ofDay: day) else {
            return 0
        }
        return Int32(gregorian.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// Milliseconds since the epoch for right now — the engine's clock
    /// reading, where `nowStamp()` is the packed civil one.
    static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - the new seam (design/rust-owns-the-mechanisms.md §3)
//
// One verb per screen, over the engine, beside the snapshot rather than
// through it. **Nothing here is on a live screen yet**, and the reason is
// worth stating plainly: an engine id is 16 bytes and the shell's is a
// number, in 225 places. Moving a surface means moving that type, and
// that is a refactor to do with a compiler rather than by hand — so it is
// being done in slices, and `LivID.swift` says where they are up to.
//
// So this is the plumbing plus one place to LOOK at it — `EngineCheck`
// in Settings — which answers the one question no test here can: does the
// whole chain work on a device? Rust, SQLite linked into the staticlib,
// the new ABI, a Swift decode, pixels. If it does, the id refactor is
// mechanical. If SQLite does not link, we find out for the price of one
// build instead of after twenty-two files have moved.
//
// Standing rule 1 holds: every `liv_*` call is still in this file.

/// One row as the new seam sends it. **Ids are hex**, 32 characters, and
/// they stay `String` here on purpose — turning them into a native type is
/// the refactor above, and doing half of it would be worse than none.
/// **EVERY FIELD IS OPTIONAL** — the H1 rule, which exists because a
/// synthesized `Decodable` uses `decode` (not `decodeIfPresent`) for a
/// non-optional property, so a default value does NOT save it: one
/// missing key throws and the whole answer is dropped. That has been a
/// real, recurring bug on the snapshot path, and a new seam is not a
/// reason to learn it again.
///
/// `id` is the one exception, because `Identifiable` requires it and a
/// row without one is not a row.
struct LivViewRow: Decodable, Identifiable {
    var id: LivID
    var title: String?
    var untitled: Bool?
    var kind: LivID?
    var dueMs: Int64?
    var allDay: Bool?
    var status: LivID?
    var done: Bool?
    var area: LivID?
    var createdMs: Int64?
    var touchedMs: Int64?
    var hasFile: Bool?

    /// What to draw.
    ///
    /// **The title is never empty and never an id** (owner, 2026-09-13):
    /// a thing nobody has named arrives already called something sensible
    /// — its kind's word and when, made in `liv-surface`. So the shell
    /// has nothing to invent, which is the point; it had four words for
    /// nothing before this ("Untitled", "untitled", the kind's word, and
    /// a hash-number) precisely because each surface invented its own.
    ///
    /// `untitled` survives as a STYLING flag, not a text one: a made name
    /// is still not a given one, and a list draws it more quietly.
    var display: String {
        title ?? ""
    }
}

/// Today, already split. The shell does not decide which pile a row is in.
struct LivTodayView: Decodable {
    var late: [LivViewRow]?
    var passed: [LivViewRow]?
    var ahead: [LivViewRow]?
    var allDay: [LivViewRow]?
    var done: [LivViewRow]?
    var next: LivID?
    var captured: Int?

    /// Everything the day itself holds, in the order the screen draws it.
    var onTheDay: [LivViewRow] {
        (passed ?? []) + (ahead ?? []) + (allDay ?? [])
    }
}

/// What a conversion carried, and what it could not.
struct LivConvertReport: Decodable {
    var entities: Int?
    var cells: Int?
    var resolved: Int?
    var mintedVocabulary: Int?
    var filesDropped: Int?
    var undeclared: Int?
    var clean: Bool?
    var unknownKinds: [String]?
}

extension BoxModel {
    /// Where the engine's box sits: beside the log, same directory.
    ///
    /// A separate FILE, not a separate place. The core box stays exactly
    /// where it is and stays the truth until stage 5; this one is built
    /// from it and can be deleted at any time without losing anything.
    var enginePath: String {
        (path as NSString).deletingLastPathComponent + "/liv.db"
    }

    var engineBoxExists: Bool {
        FileManager.default.fileExists(atPath: enginePath)
    }

    /// Build the engine box from the core box. Refuses if it is already
    /// there — `rebuildEngineBox` is the way to start over.
    ///
    /// **The value, then the fault**, which is how `query` and `search`
    /// already answer. `Result` was the first shape here and it does not
    /// compile: `Result` requires `Failure: Error` and `String` is not
    /// one. Rather than mint an error type the shell has never needed —
    /// there is no `: Error` conformance anywhere in it — this matches
    /// the house style. Exactly one of the two is non-nil.
    func convertToEngine(_ done: @escaping (LivConvertReport?, String?) -> Void) {
        let from = path
        let to = enginePath
        boxQueue.async {
            var out: UnsafeMutablePointer<CChar>?
            let code = liv_view_convert(from, to, &out)
            let (value, fault) = Self.decodeView(LivConvertReport.self, code: code, out: out)
            DispatchQueue.main.async { done(value, fault) }
        }
    }

    /// Throw the conversion away and build it again. The core box is
    /// never touched, so this is always safe.
    func rebuildEngineBox(_ done: @escaping (LivConvertReport?, String?) -> Void) {
        let to = enginePath
        boxQueue.async {
            liv_view_close_all()
            // -wal and -shm are SQLite's, and a stale one beside a deleted
            // database is how a "fresh" box comes back with old rows in it.
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: to + suffix)
            }
            DispatchQueue.main.async { self.convertToEngine(done) }
        }
    }

    /// Today, from the engine.
    ///
    /// `day` and `today` are DAYS SINCE THE EPOCH, not the packed civil
    /// the old ABI uses — the engine counts days and `Civil` packs
    /// YYYYMMDD, and pretending they are the same number is the kind of
    /// thing that puts a task on the wrong side of midnight.
    func engineToday(
        day: Int32, today: Int32, nowMs: Int64,
        _ done: @escaping (LivTodayView?, String?) -> Void
    ) {
        let to = enginePath
        boxQueue.async {
            var out: UnsafeMutablePointer<CChar>?
            let code = liv_view_today(to, day, today, nowMs, nil, &out)
            let (value, fault) = Self.decodeView(LivTodayView.self, code: code, out: out)
            DispatchQueue.main.async { done(value, fault) }
        }
    }

    /// Everything, from the engine. `slice` is 0 all, 1 notes, 2 upcoming,
    /// 3 unfiled.
    func engineEverything(
        slice: Int32, today: Int32,
        _ done: @escaping ([LivViewRow]?, String?) -> Void
    ) {
        let to = enginePath
        boxQueue.async {
            var out: UnsafeMutablePointer<CChar>?
            let code = liv_view_everything(to, slice, today, nil, &out)
            let (value, fault) = Self.decodeView([LivViewRow].self, code: code, out: out)
            DispatchQueue.main.async { done(value, fault) }
        }
    }

    /// The error channel, in words.
    ///
    /// **This is the whole reason for the new codes.** The old ABI returns
    /// `0` for both "no id" and "it broke", so a shell cannot tell an
    /// empty box from an unreadable one and every failure reads the same.
    /// Here each one says what it is.
    static func viewFault(_ code: Int32) -> String {
        switch code {
        case 0: return ""
        case -1: return "bad path"
        case -2: return "no engine box yet — convert first"
        case -3: return "bad argument"
        case -4: return "the box refused the read"
        case -5: return "the answer would not encode"
        default: return "unknown error \(code)"
        }
    }

    /// Decode one answer from the new seam, freeing the string either way.
    /// Exactly one of the two is non-nil.
    private static func decodeView<T: Decodable>(
        _ type: T.Type, code: Int32, out: UnsafeMutablePointer<CChar>?
    ) -> (T?, String?) {
        guard code == 0 else {
            // A failing call writes nothing through `out` — the Rust side
            // asserts it on every failure path — so there is nothing to
            // free here.
            return (nil, viewFault(code))
        }
        guard let out else { return (nil, "no answer") }
        let json = String(cString: out)
        liv_string_free(out)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return (try decoder.decode(type, from: Data(json.utf8)), nil)
        } catch {
            return (nil, "decode: \(error)")
        }
    }
}

// MARK: - the engine lane, complete
//
// **This is 5b's Swift half.** Everything above the `enginePath` extension
// is the core lane: one `liv_snapshot` holding the whole box, decoded into
// `Snapshot`, which every screen reads. The engine answers questions
// instead — one verb per surface, already filtered, already sorted — and
// the ABI for all of it landed in 5a (`design/rust-owns-the-mechanisms.md`
// §5). These are the Swift doors to it.
//
// Three rules hold across every one of them, and they are not style:
//
//  1. **Every wire field is Optional.** One missing key must never drop
//     the whole answer. It is a real, recurring bug, not politeness — see
//     the note on `Snapshot`.
//  2. **The value, then the fault**, exactly one non-nil. `Result` needs
//     `Failure: Error` and this shell has no error type; minting one for
//     this would be a type nothing else in the app uses.
//  3. **Ids are 32 hex characters and are never shown to anyone**
//     (owner, 2026-09-13). `LivID` decodes them; `LivIDText.written` is
//     the only way to write one down.

/// One band of the Tasks view: a status, and the rows under it.
///
/// **`late` is the GROUP's count, not a flag per row.** On a real box
/// every task is overdue, and a colour on every row distinguishes
/// nothing. An empty group is not returned at all.
struct LivTaskGroup: Decodable, Identifiable {
    var status: LivID?
    var name: String?
    var completes: Bool?
    var late: Int?
    var rows: [LivViewRow]?
    var id: String { LivIDText.written(status ?? .absent) + (name ?? "") }
}

/// One block on the day's timeline, with its overlap already resolved.
///
/// **`column`/`columns` are a CLUSTER's, not a pair's**: two blocks that
/// miss each other can both hit a third, and all three share the width.
/// The engine works that out, because getting it wrong is a layout bug
/// that only shows up on a busy day.
struct LivBlock: Decodable, Identifiable {
    var row: LivViewRow?
    var startMin: Int?
    /// Never zero, so a thing with no duration stays tappable.
    var minutes: Int?
    var column: Int?
    var columns: Int?
    var id: String { LivIDText.written(row?.id ?? .absent) }
}

/// One day: the all-day band, and the timeline under it.
struct LivDayView: Decodable {
    var allDay: [LivViewRow]?
    var blocks: [LivBlock]?
}

/// One row of the inspector, as `liv_cells` reports it.
struct LivCell: Decodable, Identifiable {
    var property: LivID?
    var name: String?
    /// text | number | bool | datetime | reference | richtext | file —
    /// so a row picks its editor without knowing the property.
    var holds: String?
    var many: Bool?
    /// Always a display string, so a row draws without knowing the kind.
    var value: String?
    /// Where to go when the row is tapped, when there is anywhere.
    var ref: LivID?
    /// **Two devices left this register holding two values.** Nothing
    /// silently wins, so the row has to be able to show the choice.
    var contended: Bool?

    var id: String { LivIDText.written(property ?? .absent) }
}

/// One thing a picker may offer: compiled-in furniture and the user's own
/// in one list, because that is what the cell accepts.
struct LivNamed: Decodable, Identifiable {
    var id: LivID
    var name: String?
    var display: String { (name ?? "").isEmpty ? "Untitled" : (name ?? "") }
}

/// One value a property is actually carrying, with how many carry it.
struct LivInUse: Decodable, Identifiable {
    var label: String?
    var ref: LivID?
    var count: Int?
    var id: String { label ?? "" }
}

/// One suggestion the clerk would make.
///
/// **Named by the thing it is about AND its fingerprint**, never its
/// position: the sweep is recomputed in every process, so an index would
/// mean something different by the time the user tapped it.
struct LivSuggestion: Decodable, Identifiable {
    var entity: LivID?
    var print: UInt64?
    var proposer: String?
    var reason: String?
    var id: String { "\(LivIDText.written(entity ?? .absent)).\(print ?? 0)" }
}

/// One workspace, or one saved filter.
struct LivSpace: Decodable, Identifiable {
    var id: LivID
    var name: String?
    var query: String?
    var emoji: String?
    var favorite: Bool?
    var archived: Bool?
    var builtin: String?
    var parent: LivID?
    var order: Double?
    /// Never an id (owner, 2026-09-13). A nameless workspace is for the
    /// shell to title.
    var display: String { (name ?? "").isEmpty ? "Workspace" : (name ?? "") }
}

/// A body and the fingerprint to save it against.
struct LivBody: Decodable {
    var spans: [SpanJSON]?
    /// **Zero is never a real fingerprint** — it is what "no body yet"
    /// reads as, so a first save needs no special case.
    var print: UInt64?
}

/// One past version of a body, from `liv_body_history`.
struct LivBodyVersion: Decodable, Identifiable {
    var device: String?
    var seq: UInt64?
    var atMs: Int64?
    /// "user", or the proposer's name.
    var author: String?
    var spans: [SpanJSON]?
    var id: String { "\(device ?? "")\(seq ?? 0)" }
}

/// Both directions of one thing's links, as bare ids. A `[[ ]]` typed in
/// a body is the same edge as a link picked in properties.
struct LivLinks: Decodable {
    var out: [LivID]?
    var inbound: [LivID]?
    enum CodingKeys: String, CodingKey {
        case out
        case inbound = "in"
    }
    static let empty = LivLinks(out: [], inbound: [])
}

/// What undo and redo would take, without taking it.
struct LivUndoState: Decodable {
    var undo: Bool?
    var redo: Bool?
}

/// A search: ranked hits, and the facet rows beside them.
struct LivFound: Decodable {
    var hits: [LivHit]?
    var facets: [LivEngineFacet]?
}

struct LivHit: Decodable, Identifiable {
    var id: LivID
    var score: Double?
    /// name | cell | filed | content | structured — where the best match
    /// was, so a row can hint why it is here.
    var field: String?
}

struct LivEngineFacet: Decodable, Identifiable {
    var property: LivID?
    var label: String?
    var values: [LivEngineFacetValue]?
    var id: String { label ?? LivIDText.written(property ?? .absent) }
}

struct LivEngineFacetValue: Decodable, Identifiable {
    var label: String?
    var count: Int?
    /// include → exclude → off is a three-state cycle, so a chip needs
    /// both flags rather than one.
    var active: Bool?
    var excluded: Bool?
    var id: String { label ?? "" }
}

/// The ids a lens admits, and the terms it is made of.
struct LivLens: Decodable {
    var ids: [LivID]?
    var terms: [LivTerm]?
}

/// One token of the filter grammar — what a chip is drawn from.
///
/// **Standing rule 5: a user never types a query language.** The text is
/// the storage format; this is how it becomes something to tap.
struct LivTerm: Decodable, Identifiable {
    /// equals | not-equals | at-most | has | no | is | text
    var op: String?
    var key: String?
    var value: String?
    /// The term respelled canonically, so joining a list back together
    /// reproduces a query that reads the same way.
    var raw: String?
    var id: String { raw ?? "" }
}

/// One file this device cannot open.
struct LivFileAlert: Decodable, Identifiable {
    var id: LivID
    var name: String?
    /// Where this device last looked — null for a file that arrived by
    /// sync and has no copy here.
    var path: String?
    /// **`absent` is not `gone`.** A hash travels and a path does not, so
    /// a file added on the laptop reaches the phone as a valid reference
    /// with no local copy: that is "find it for me", not "this is broken".
    var why: String?
}

/// Why the box will not open. `code` is ok | version | corrupt | io.
struct LivBoxHealth: Decodable {
    var code: String?
    var message: String?
}

/// What `liv_resync_file` found.
struct LivResync: Decodable {
    /// unchanged | changed | broken
    var state: String?
    var path: String?
}

// MARK: - the engine lane: verbs

/// The out-pointer every engine verb delivers its answer through: a
/// `char **`, exactly as C sees it.
///
/// Named so the helpers below can take it as an ordinary parameter. The
/// first shape here was `inout UnsafeMutablePointer<CChar>?`, which reads
/// better at a call site and is a closure type this container cannot
/// compile to check — and an escaping closure over an `inout` is the sort
/// of thing that is either fine or a hard error with nothing in between.
/// This one maps to the C signature with no translation at all.
typealias LivOut = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>


extension BoxModel {
    /// A write, and the refresh that follows it.
    ///
    /// **One user action gets one snapshot** (standing rule 8): every
    /// write lands, then asks for exactly one re-read, and `refresh`
    /// coalesces the rest. `LIV_OK` is 0; anything negative is a fault
    /// with its own meaning, which is the whole reason the new codes
    /// exist.
    private func engineWrite(
        _ work: @escaping (String) -> Int32,
        _ done: ((String?) -> Void)? = nil
    ) {
        let to = enginePath
        boxQueue.async {
            let code = work(to)
            DispatchQueue.main.async {
                done?(code == 0 ? nil : Self.writeFault(code))
                self.refresh()
            }
        }
    }

    /// A write that hands back a JSON answer — a new thing's id, a fresh
    /// fingerprint, how many carriers a rename touched.
    private func engineWriteValue<T: Decodable>(
        _ type: T.Type,
        _ work: @escaping (String, LivOut) -> Int32,
        _ done: @escaping (T?, String?) -> Void
    ) {
        let to = enginePath
        boxQueue.async {
            var out: UnsafeMutablePointer<CChar>?
            let code = withUnsafeMutablePointer(to: &out) { work(to, $0) }
            let (value, fault) = Self.decodeView(type, code: code, out: out)
            DispatchQueue.main.async {
                done(value, fault)
                self.refresh()
            }
        }
    }

    /// A read: no refresh, because nothing changed.
    private func engineRead<T: Decodable>(
        _ type: T.Type,
        _ work: @escaping (String, LivOut) -> Int32,
        _ done: @escaping (T?, String?) -> Void
    ) {
        let to = enginePath
        boxQueue.async {
            var out: UnsafeMutablePointer<CChar>?
            let code = withUnsafeMutablePointer(to: &out) { work(to, $0) }
            let (value, fault) = Self.decodeView(type, code: code, out: out)
            DispatchQueue.main.async { done(value, fault) }
        }
    }

    /// The three codes a WRITE can return that a read cannot, in words.
    ///
    /// Each one is a different thing for the shell to do, which is why
    /// they are separate codes and not one failure: re-read and decide;
    /// tell the user the box said no; say nothing, because nothing was
    /// wrong.
    static func writeFault(_ code: Int32) -> String {
        switch code {
        case -6: return "someone else changed this — reopen it"
        case -7: return "the box would not take that"
        case -8: return "there was nothing to do"
        default: return viewFault(code)
        }
    }

    /// Milliseconds, which is what every engine verb takes.
    static var nowMs: UInt64 { UInt64(Date().timeIntervalSince1970 * 1000) }

    // MARK: making things

    /// Capture a scrap. **Untyped on purpose** — a capture is a thought,
    /// not a decision about what kind of thing it is, and the clerk's
    /// promotion proposer can only offer to make it a task because
    /// nothing here decided first.
    func engineCapture(_ text: String, _ done: ((LivID?, String?) -> Void)? = nil) {
        engineWriteValue(LivMade.self, { to, out in
            liv_capture(to, text, Self.nowMs, out)
        }) { made, fault in done?(made?.id, fault) }
    }

    /// Make one thing of a kind. `name` nil is something born untitled,
    /// which is the common case and not an error.
    func engineMake(
        kind: LivID, name: String? = nil,
        _ done: ((LivID?, String?) -> Void)? = nil
    ) {
        let k = LivIDText.written(kind)
        engineWriteValue(LivMade.self, { to, out in
            if let name {
                return liv_make(to, k, name, Self.nowMs, out)
            }
            return liv_make(to, k, nil, Self.nowMs, out)
        }) { made, fault in done?(made?.id, fault) }
    }

    /// Declare a field the app did not ship with. `holds` is text |
    /// number | bool | datetime | reference | richtext | file.
    func engineDeclareField(
        _ name: String, holds: String = "text", many: Bool = false,
        _ done: ((LivID?, String?) -> Void)? = nil
    ) {
        engineWriteValue(LivMade.self, { to, out in
            liv_declare_field(to, name, holds, many, Self.nowMs, out)
        }) { made, fault in done?(made?.id, fault) }
    }

    // MARK: changing cells

    /// **A value crosses as TEXT and the property says what it means.**
    /// The shell sends "yes", "3", "2026-09-13", "Work"; which of those
    /// is a bool, a number, a date or an option is the box's business,
    /// not the shell's. A value that does not read is refused with
    /// nothing written.
    func engineSet(
        _ id: LivID, _ property: LivID, _ value: String,
        _ done: ((String?) -> Void)? = nil
    ) {
        let (i, p) = (LivIDText.written(id), LivIDText.written(property))
        engineWrite({ to in liv_set(to, i, p, value, Self.nowMs) }, done)
    }

    func engineAdd(
        _ id: LivID, _ property: LivID, _ value: String,
        _ done: ((String?) -> Void)? = nil
    ) {
        let (i, p) = (LivIDText.written(id), LivIDText.written(property))
        engineWrite({ to in liv_add(to, i, p, value, Self.nowMs) }, done)
    }

    /// **Add-wins**: a member added on another device survives this.
    func engineRemove(
        _ id: LivID, _ property: LivID, _ value: String,
        _ done: ((String?) -> Void)? = nil
    ) {
        let (i, p) = (LivIDText.written(id), LivIDText.written(property))
        engineWrite({ to in liv_remove(to, i, p, value, Self.nowMs) }, done)
    }

    /// Empty a cell. **Not the same as setting it to nothing** — an unset
    /// cell has no value, which is what a picker's "None" means.
    func engineUnset(_ id: LivID, _ property: LivID, _ done: ((String?) -> Void)? = nil) {
        let (i, p) = (LivIDText.written(id), LivIDText.written(property))
        engineWrite({ to in liv_unset(to, i, p, Self.nowMs) }, done)
    }

    /// **Trashing is a cell, not a deletion**, which is what makes
    /// restore a write rather than a resurrection.
    func engineTrash(_ id: LivID, _ done: ((String?) -> Void)? = nil) {
        let i = LivIDText.written(id)
        engineWrite({ to in liv_trash(to, i, Self.nowMs) }, done)
    }

    func engineRestore(_ id: LivID, _ done: ((String?) -> Void)? = nil) {
        let i = LivIDText.written(id)
        engineWrite({ to in liv_restore(to, i, Self.nowMs) }, done)
    }

    // MARK: the editor

    func engineBody(_ id: LivID, _ done: @escaping (LivBody?, String?) -> Void) {
        let i = LivIDText.written(id)
        engineRead(LivBody.self, { to, out in liv_read_body(to, i, out) }, done)
    }

    /// Save a body against the fingerprint it was read at.
    ///
    /// **Re-read, never overwrite.** There is no force flag by design: a
    /// stale save comes back as its own fault so the caller re-reads and
    /// decides. Empty spans clear the body.
    func engineSaveBody(
        _ id: LivID, spansJson: String, base: UInt64,
        _ done: @escaping (UInt64?, String?) -> Void
    ) {
        let i = LivIDText.written(id)
        engineWriteValue(LivBody.self, { to, out in
            liv_write_body(to, i, spansJson, base, Self.nowMs, out)
        }) { body, fault in done(body?.print, fault) }
    }

    func engineBodyHistory(_ id: LivID, _ done: @escaping ([LivBodyVersion], String?) -> Void) {
        let i = LivIDText.written(id)
        engineRead([LivBodyVersion].self, { to, out in liv_body_history(to, i, out) }) {
            done($0 ?? [], $1)
        }
    }

    func engineLinks(_ id: LivID, _ done: @escaping (LivLinks) -> Void) {
        let i = LivIDText.written(id)
        engineRead(LivLinks.self, { to, out in liv_links(to, i, out) }) { v, _ in
            done(v ?? .empty)
        }
    }

    // MARK: undo

    func engineUndoState(_ done: @escaping (LivUndoState) -> Void) {
        engineRead(LivUndoState.self, { to, out in liv_undo_state(to, out) }) { v, _ in
            done(v ?? LivUndoState(undo: false, redo: false))
        }
    }

    /// Take back this device's last action. **Undo is what YOU did here**
    /// — a box holding both ends of a sync must not let either end take
    /// back the other's last write.
    func engineUndo(_ done: ((String?) -> Void)? = nil) {
        engineWrite({ to in liv_undo(to, Self.nowMs) }, done)
    }

    func engineRedo(_ done: ((String?) -> Void)? = nil) {
        engineWrite({ to in liv_redo(to, Self.nowMs) }, done)
    }

    // MARK: vocabulary

    /// **The words come from the box, never from the shell.** A shell
    /// carrying its own copy of the furniture drifts from the box that
    /// stores it, and the drift is invisible until someone renames
    /// something (`one-core.md` §4).
    func engineOptions(_ property: LivID, _ done: @escaping ([LivNamed]) -> Void) {
        let p = LivIDText.written(property)
        engineRead([LivNamed].self, { to, out in liv_options(to, p, out) }) { v, _ in
            done(v ?? [])
        }
    }

    /// What a create menu offers: the six the product names, plus
    /// anything the user declared. Not every kind that exists.
    func engineKinds(_ done: @escaping ([LivNamed]) -> Void) {
        engineRead([LivNamed].self, { to, out in liv_kinds(to, out) }) { v, _ in done(v ?? []) }
    }

    /// A compiled-in property's id by its frozen name — "due", "status",
    /// "area". A shell needs some way in, and hard-coding 32 hex
    /// characters in Swift is worse than asking.
    func engineProperty(_ name: String, _ done: @escaping (LivID?) -> Void) {
        engineRead(LivMade.self, { to, out in liv_property_named(to, name, out) }) { v, _ in
            done(v?.id)
        }
    }

    /// What this property is actually CARRYING — a different question
    /// from `engineOptions`, which asks what it may hold.
    func engineValuesInUse(_ property: LivID, _ done: @escaping ([LivInUse]) -> Void) {
        let p = LivIDText.written(property)
        engineRead([LivInUse].self, { to, out in liv_values_in_use(to, p, out) }) { v, _ in
            done(v ?? [])
        }
    }

    func engineCells(_ id: LivID, _ done: @escaping ([LivCell]) -> Void) {
        let i = LivIDText.written(id)
        engineRead([LivCell].self, { to, out in liv_cells(to, i, out) }) { v, _ in done(v ?? []) }
    }

    /// Rename one value of a property, everywhere it is carried.
    /// `carriers` is how many things change ON SCREEN, which for a select
    /// is not the number of writes: one write re-renders every carrier.
    func engineRenameValue(
        _ property: LivID, from old: String, to new: String,
        _ done: @escaping (Int?, String?) -> Void
    ) {
        let p = LivIDText.written(property)
        engineWriteValue(LivCarriers.self, { box, out in
            liv_rename_value(box, p, old, new, Self.nowMs, out)
        }) { v, fault in done(v?.carriers, fault) }
    }

    // MARK: files

    /// Take a file into the box BY REFERENCE. Never copies or moves it.
    func engineAddFile(_ file: String, _ done: @escaping (LivID?, String?) -> Void) {
        engineWriteValue(LivMade.self, { to, out in
            liv_add_file(to, file, Self.nowMs, out)
        }) { v, fault in done(v?.id, fault) }
    }

    /// Re-hash what a file points at here. A changed hash IS the
    /// integration — it is how Liv learns Word saved the file.
    func engineResync(_ id: LivID, _ done: @escaping (LivResync?, String?) -> Void) {
        let i = LivIDText.written(id)
        engineWriteValue(LivResync.self, { to, out in
            liv_resync_file(to, i, Self.nowMs, out)
        }, done)
    }

    /// Every file reference this device cannot open.
    func engineFileAlerts(_ done: @escaping ([LivFileAlert]) -> Void) {
        engineRead([LivFileAlert].self, { to, out in liv_file_alerts(to, out) }) { v, _ in
            done(v ?? [])
        }
    }

    // MARK: the clerk

    func engineSuggestions(_ done: @escaping ([LivSuggestion]) -> Void) {
        engineRead([LivSuggestion].self, { to, out in liv_sweep(to, out) }) { v, _ in
            done(v ?? [])
        }
    }

    /// Say yes to one. Passing the entity back is what makes the check
    /// cost one thing rather than the whole box.
    func engineAccept(_ s: LivSuggestion, _ done: ((String?) -> Void)? = nil) {
        guard let entity = s.entity, let print = s.print else {
            done?("that suggestion is gone")
            return
        }
        let e = LivIDText.written(entity)
        engineWrite({ to in liv_accept(to, e, print, Self.nowMs) }, done)
    }

    /// **Declining is not forgetting** — the refusal persists, and since
    /// 2026-09-13 it TRAVELS: saying no on the phone says no on the
    /// laptop too.
    func engineDecline(_ s: LivSuggestion, _ done: ((String?) -> Void)? = nil) {
        guard let entity = s.entity, let print = s.print else {
            done?("that suggestion is gone")
            return
        }
        let e = LivIDText.written(entity)
        engineWrite({ to in liv_decline(to, e, print, Self.nowMs) }, done)
    }

    /// Accept several as ONE action. **All or nothing, and one undo**:
    /// half a consent is worse than none. A suggestion the box no longer
    /// makes is skipped rather than failing the batch.
    func engineAcceptAll(_ many: [LivSuggestion], _ done: @escaping (Int?, String?) -> Void) {
        let pairs = many.compactMap { s -> (String, UInt64)? in
            guard let e = s.entity, let p = s.print else { return nil }
            return (LivIDText.written(e), p)
        }
        guard !pairs.isEmpty else {
            done(nil, "there was nothing to do")
            return
        }
        let prints = pairs.map { $0.1 }
        engineWriteValue(LivTaken.self, { to, out in
            // **The C strings must outlive the call.** Bridging a Swift
            // String to a `const char *` gives a pointer valid only for
            // the one call it is an argument to, so an array of them
            // built the easy way is an array of dangling pointers by the
            // time the callee reads the second one. These are copied,
            // held for the whole call, and freed after.
            let held: [UnsafeMutablePointer<CChar>?] = pairs.map { strdup($0.0) }
            defer { held.forEach { free($0) } }
            let ptrs: [UnsafePointer<CChar>?] = held.map { $0.map(UnsafePointer.init) }
            return ptrs.withUnsafeBufferPointer { p in
                prints.withUnsafeBufferPointer { f in
                    liv_accept_all(to, p.baseAddress, f.baseAddress, UInt32(pairs.count),
                                   Self.nowMs, out)
                }
            }
        }) { v, fault in done(v?.taken, fault) }
    }

    /// The clerk's consent switch. **Absent or true is ON**; only an
    /// explicit no silences it, so an older box that never set it is not
    /// a box that said no.
    func engineAssist(_ done: @escaping (Bool, LivID?) -> Void) {
        engineRead(LivAssist.self, { to, out in liv_assist(to, out) }) { v, _ in
            done(v?.on ?? true, v?.property)
        }
    }

    // MARK: finding

    /// Ranked hits and the facets beside them. `limit` 0 is no ceiling.
    ///
    /// **A search box WIDENS**: `is:archived` here means "look in the
    /// archive too", because someone hunting for a thing wants it found.
    func engineSearch(_ query: String, limit: UInt32 = 200,
                      _ done: @escaping (LivFound?, String?) -> Void) {
        engineRead(LivFound.self, { to, out in liv_search(to, query, limit, out) }, done)
    }

    /// **A lens RESTRICTS**: the same `is:archived` means "only archived
    /// things", because a filter is a boundary and a search is a hunt.
    func engineLens(_ query: String, _ done: @escaping (LivLens?, String?) -> Void) {
        engineRead(LivLens.self, { to, out in liv_lens(to, query, out) }, done)
    }

    /// Split a filter into the chips a person taps. No box, no lock — so
    /// it is safe on every keystroke.
    func engineTerms(_ query: String) -> [LivTerm] {
        var out: UnsafeMutablePointer<CChar>?
        let code = liv_terms(query, &out)
        let (value, _) = Self.decodeView([LivTerm].self, code: code, out: out)
        return value ?? []
    }

    // MARK: the box itself

    /// The day view, from the engine. `day` is DAYS SINCE THE EPOCH, not
    /// a packed civil.
    func engineDay(day: Int32, _ done: @escaping (LivDayView?, String?) -> Void) {
        engineRead(LivDayView.self, { to, out in liv_view_day(to, day, nil, out) }, done)
    }

    /// Tasks by band. `filter` is 0 all, 1 status, 2 project.
    func engineTasks(filter: Int32 = 0, filterId: LivID? = nil, today: Int32,
                     _ done: @escaping ([LivTaskGroup]?, String?) -> Void) {
        let f = filterId.map(LivIDText.written)
        engineRead([LivTaskGroup].self, { to, out in
            liv_view_tasks(to, filter, f, today, nil, out)
        }, done)
    }

    func engineWorkspaces(_ done: @escaping ([LivSpace]) -> Void) {
        engineRead([LivSpace].self, { to, out in liv_workspaces(to, out) }) { v, _ in
            done(v ?? [])
        }
    }

    func engineViews(_ done: @escaping ([LivSpace]) -> Void) {
        engineRead([LivSpace].self, { to, out in liv_views(to, out) }) { v, _ in done(v ?? []) }
    }

    /// Why the box will not open. **A shell that cannot open the box has
    /// nothing else to ask**, and the four answers need different
    /// screens: `version` means update, and a wrong answer strands
    /// someone on it.
    func engineHealth(_ done: @escaping (LivBoxHealth?) -> Void) {
        engineRead(LivBoxHealth.self, { to, out in liv_probe_box(to, out) }) { v, _ in done(v) }
    }
}

/// `{"id":hex}` — what every making verb answers.
struct LivMade: Decodable {
    var id: LivID?
}

/// `{"carriers":N}` — how many things a rename changed on screen.
struct LivCarriers: Decodable {
    var carriers: Int?
}

/// `{"taken":N}` — how many of a batch actually landed.
struct LivTaken: Decodable {
    var taken: Int?
}

/// `{"on":bool,"property":hex}` — the clerk's consent switch and the cell
/// that holds it.
struct LivAssist: Decodable {
    var on: Bool?
    var property: LivID?
}

// MARK: - the engine lane: the two the swap would otherwise take away

/// One open `- [ ]` line inside a note. A projection: nothing behind it
/// is stored, and ticking it is an edit to the note's body.
struct LivNoteTask: Decodable, Identifiable {
    var note: LivID?
    /// What that note is called — computed in Rust, where the body is.
    var source: String?
    /// The block's index from the top of the body: the toggle's address.
    var line: Int?
    var text: String?
    var depth: Int?
    var id: String { "\(LivIDText.written(note ?? .absent)).\(line ?? 0)" }
}

extension BoxModel {
    /// What is in the trash, newest first.
    func engineTrash(_ done: @escaping ([LivViewRow]) -> Void) {
        engineRead([LivViewRow].self, { to, out in liv_view_trash(to, out) }) { v, _ in
            done(v ?? [])
        }
    }

    /// Open checkbox lines inside notes — the Tasks view's "In notes".
    func engineNoteTasks(_ done: @escaping ([LivNoteTask]) -> Void) {
        engineRead([LivNoteTask].self, { to, out in liv_note_tasks(to, out) }) { v, _ in
            done(v ?? [])
        }
    }
}
