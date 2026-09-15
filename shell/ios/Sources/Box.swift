// liv iOS — the box seam. One serial lane to the core, one JSON snapshot,
// act-then-refresh. The shell never holds the box; every FFI call opens it
// and closes it. Mirrors the macOS BoxModel (Window.swift) idioms.

import Combine
import Foundation
import os

// MARK: - snapshot rows (mirror ffi/src/lib.rs, decoded from snake_case)

/// EVERY field Optional — one missing key must never drop the snapshot
/// (a real, recurring bug; Optionality is resilience, not politeness).
/// One open `- [ ]` line inside a note (phase 3, services/src/tasks.rs).
/// Every field Optional — the standing law.
/// One cell of one thing, in the shape the inspector already reads.
///
/// **Fetched per thing, not shipped for the whole box.** The old snapshot
/// carried every cell of every entity on every refresh, which is most of
/// what made it 3.5 MB; `BoxModel.cells(of:)` asks for one thing's when
/// something opens it.
struct CellRow: Decodable {
    var propertyId: LivEntityID? = nil
    var property: String? = nil
    var kind: String? = nil
    var value: String? = nil
    var refTarget: LivEntityID? = nil
}

struct NoteTaskRow: Decodable, Identifiable {
    /// Stable per line, so SwiftUI keeps rows in place across refreshes.
    var id: String { "\(engineId(entity ?? .absent)).\(line ?? 0)" }
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
    var id: String { "\(engineId(entity ?? .absent)).\(fingerprint ?? 0)" }
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

/// What the screens read, in the shape they already read it.
///
/// **Not a wire type any more.** This used to be one `liv_snapshot`
/// holding the whole box — 3.5 MB at 6,400 notes, rebuilt on every
/// refresh, linear in the box and independent of what was on screen. The
/// engine answers questions instead (§3), and `BoxModel` assembles this
/// from those answers.
///
/// Keeping the shape is deliberate and temporary. Fifteen view files read
/// it; moving each one onto the verb for its own surface is the next
/// step, and doing it here in one go would be fifteen files of risk for
/// no behaviour. What is already true is the part that mattered: the data
/// comes from per-surface verbs, and no screen is handed the box.
struct Snapshot {
    var today: [LivEntityID]?
    var unstructured: [LivEntityID]?
    var everything: [LivEntityID]?
    var dated: [LivEntityID]?
    /// **Always empty.** Nothing expands a recurrence yet: `prop::RECURRENCE`
    /// is declared and unread, so a repeating event has no engine answer
    /// and the calendar shows one-off things only. A real gap, named here
    /// rather than hidden (`design/rust-owns-the-mechanisms.md` §5).
    var occurrences: [Occurrence]?
    var entities: [EntityRow]?
    var trashed: [LivEntityID]?
    var properties: [PropertyRow]?
    var kinds: [KindRow]?
    var workspaces: [WorkspaceRow]?
    var views: [SavedViewRow]?
    var inbox: [ProposalRow]?
    var assist: AssistRow?
    var noteTasks: [NoteTaskRow]?
}

// MARK: - the model: refresh-after-every-act, never hold the box

final class BoxModel: ObservableObject {
    let path: String

    /// **Everything the screens read, one list per surface.**
    ///
    /// This replaces `snap`, which was one `liv_snapshot` holding the
    /// whole box — 3.5 MB at 6,400 notes, rebuilt on every refresh,
    /// linear in the box and independent of what was on screen. The
    /// engine answers questions instead (§3), so each of these is one
    /// verb's answer and costs what it shows.
    /// The screens' view of the box, assembled from the lists below.
    /// Republished whenever any of them lands, so `box.$snap` fires as it
    /// always did.
    @Published private(set) var snap: Snapshot?

    @Published private(set) var rows: [EntityRow] = []
    @Published private(set) var trashRows: [EntityRow] = []
    @Published private(set) var suggestions: [LivSuggestion] = []
    @Published private(set) var spaces: [LivSpace] = []
    @Published private(set) var filters: [LivSpace] = []
    @Published private(set) var noteTasks: [LivNoteTask] = []
    /// **Absent or true is ON.** Only an explicit no silences the clerk,
    /// so a box that never said anything is not a box that said no.
    @Published private(set) var assistOn: Bool = true
    /// The property the switch above writes to, as the box names it.
    @Published private(set) var assistProperty: LivID?
    /// Human message for a box that will not open for a reason retrying
    /// cannot fix — corrupt / version / io. nil = healthy.
    @Published private(set) var boxFault: String?
    /// The box is merely locked (the CLI, an extension); a backoff retry
    /// is scheduled. Render as quiet busyness, never a fault.
    @Published private(set) var busyRetrying: Bool = false
    /// id -> row, rebuilt on each refresh. Per-row lookups happen on
    /// every render; a linear scan would be O(n²).
    ///
    /// **The trash is in here too**, carrying `trashed: true`. `entity`
    /// asks "has this box ever heard of it", which is what the editor's
    /// link oracle needs; `live` is the one that opens things.
    private(set) var entities: [LivEntityID: EntityRow] = [:]

    /// One thing's cells, fetched when something asks and kept.
    ///
    /// **Not on the row, and not fetched for every row.** The old
    /// snapshot shipped every cell of every entity on every refresh,
    /// which is most of what made it 3.5 MB. An inspector needs one
    /// thing's cells when it opens; asking then is the whole difference.
    private var cellCache: [LivEntityID: [LivCell]] = [:]
    private var cellsInFlight: Set<LivEntityID> = []

    /// name -> id for the compiled-in properties the views name.
    ///
    /// **Asked of the box once, then kept.** These names are frozen, so
    /// the lookup is of something stable; the ids are 32 hex characters
    /// and spelling them in Swift would be the shell keeping its own copy
    /// of the furniture (`one-core.md` §4).
    private var propertyIds: [String: LivID] = [:]

    /// The fields and kinds a picker offers, kept for the façade.
    private var propertyRows: [PropertyRow] = []
    private var kindRows: [KindRow] = []

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
        guard let row = entities[id] else { return nil }
        // **Asking for a row is what fetches its cells.** They are not on
        // the wire — the old snapshot shipped every cell of every entity
        // on every refresh, which is most of what made it 3.5 MB — so
        // something has to ask, and the views read `row.cells` rather
        // than calling for them.
        //
        // Nothing did, so `row.cells` was always nil: an area could be
        // written to the box and the inspector would still show no area,
        // because the row it drew had no cells in it.
        //
        // Bounded by what is on screen. A list asks for the rows it is
        // about to draw and no others, which is the same rule as the rest
        // of the engine seam: pay for what you show.
        if row.cells == nil { _ = cells(of: id) }
        return row
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
        loadEverything()
    }

    /// One refresh finished. If anything asked for another while it was
    /// in the air, run exactly one more.
    ///
    /// **A request during a read is remembered, never dropped.** A read
    /// already in the air may have been taken before the write that asked
    /// for this one, so collapsing them must not lose the LAST one. One
    /// typed task fires four writes, each asking for a re-read; only the
    /// last answer is ever seen.
    private func refreshLanded() {
        DispatchQueue.main.async {
            self.refreshInFlight = false
            if self.refreshAgain {
                self.refreshAgain = false
                self.refresh()
            }
        }
    }

    /// Point the calendar at a window and reload.
    ///
    /// **The window no longer changes what comes back**, and saying so
    /// here is better than the call quietly doing nothing. It existed to
    /// re-expand RECURRENCES over a chosen range; nothing expands a
    /// recurrence yet, so every dated thing is a one-off and the whole
    /// set arrives either way. The signature stays because the calendar
    /// calls it and because the window will matter again the day
    /// recurrence lands (`design/rust-owns-the-mechanisms.md` §5).
    func refreshWindow(from: Int64, to: Int64) {
        window = (from, to)
        refresh()
    }

    /// One refresh: the surfaces the screens read, from the engine.
    ///
    /// **Each one is its own verb**, so a screen costs what it shows
    /// rather than what the box holds. They are asked for together
    /// because a refresh follows a write and the whole app has to agree
    /// about what just happened — not because any of them needs another.
    private func loadEverything() {
        let today = Self.todayDay
        // **The rows are the refresh; the rest catch up.**
        //
        // This waited for all nine fetches before calling the refresh
        // finished, which is a fan-in with no timeout: one that never
        // called back left `refreshInFlight` true forever, and every
        // later refresh was swallowed. The app would render once and then
        // silently stop updating — a write would land in the box and
        // never reach the screen, which is exactly the shape of "it says
        // it created the event and nothing renders".
        //
        // Each answer republishes as it arrives (`assemble`), so there is
        // nothing to wait for. The rows decide when the refresh is done
        // because they are what every surface is made of; a slow or
        // broken side fetch now costs its own list and nothing else.

        engineEverything(slice: 0, today: today) { [weak self] rows, fault in
            guard let self else { return }
            if let fault, rows == nil {
                self.readFailed(fault)
            } else {
                self.rows = rows ?? []
                self.reindex()
                self.boxFault = nil
                self.busyRetrying = false
                self.retryDelay = 0.2
            }
            self.refreshLanded()
        }
        engineTrashRows { [weak self] in
            self?.trashRows = $0
            self?.reindex()
        }
        engineSuggestions { [weak self] in
            self?.suggestions = $0
            self?.assemble()
        }
        engineWorkspaces { [weak self] in
            self?.spaces = $0
            self?.assemble()
        }
        engineViews { [weak self] in
            self?.filters = $0
            self?.assemble()
        }
        engineNoteTasks { [weak self] in
            self?.noteTasks = $0
            self?.assemble()
        }
        engineAssist { [weak self] on, property in
            self?.assistOn = on
            self?.assistProperty = property
            self?.assemble()
        }
        // The vocabulary a picker offers. It moves only when someone
        // declares a field or renames one, but it rides the same refresh
        // so the whole app agrees about the box at one moment.
        engineProperties { [weak self] in
            self?.propertyRows = $0.map { p in
                PropertyRow(
                    id: p.id, name: p.name, kind: p.holds, usage: nil,
                    icon: nil, hideWhenEmpty: nil,
                    options: (p.options ?? []).map {
                        PropertyOptionRow(id: $0.id, name: $0.name, hidden: false)
                    })
            }
            self?.assemble()
        }
        engineKinds { [weak self] in
            self?.kindRows = $0.map { KindRow(id: $0.id, name: $0.name) }
            self?.assemble()
        }
    }

    /// Put the screens' view together from the answers that landed.
    ///
    /// One struct rather than fifteen view files each learning a new
    /// shape. The lists it is made of each came from their own verb, so
    /// nothing here re-reads the box.
    private func assemble() {
        let live = rows
        snap = Snapshot(
            // The day's dated things. `liv_view_today` answers this
            // properly, with the piles already sorted; this keeps the old
            // shape until Today.swift moves onto it.
            today: live.filter { $0.dueMs != nil }.map(\.id),
            unstructured: live.filter { $0.kindWord == nil }.map(\.id),
            everything: live.map(\.id),
            dated: live.filter { $0.dueMs != nil }.map(\.id),
            occurrences: [],
            entities: live + trashRows.map { r in
                var row = r
                row.trashed = true
                return row
            },
            trashed: trashRows.map(\.id),
            properties: propertyRows,
            kinds: kindRows,
            workspaces: spaces.map {
                WorkspaceRow(
                    wsId: $0.id, name: $0.name, emoji: $0.emoji,
                    favorite: $0.favorite, archived: $0.archived,
                    builtin: $0.builtin, parent: $0.parent,
                    order: $0.order, query: $0.query)
            },
            views: filters.map { SavedViewRow(viewId: $0.id, name: $0.name, query: $0.query) },
            inbox: suggestions.map {
                ProposalRow(
                    entity: $0.entity,
                    // **The engine names a suggestion by its
                    // fingerprint**, never a position, so there is no
                    // ordinal any more — the sweep is recomputed in every
                    // process and an index would mean something else by
                    // the time the user tapped it.
                    ordinal: 0,
                    fingerprint: $0.print,
                    reason: $0.reason,
                    author: $0.proposer,
                    commands: nil)
            },
            assist: AssistRow(
                id: nil, on: assistOn,
                prop: assistProperty.map(engineId)),
            noteTasks: noteTasks.map {
                NoteTaskRow(entity: $0.note, source: $0.source, line: $0.line,
                            text: $0.text, indent: $0.depth)
            })
    }

    /// Both lists into one index, the trash carrying its flag.
    private func reindex() {
        var index = [LivEntityID: EntityRow](minimumCapacity: rows.count + trashRows.count)
        for r in rows {
            var row = r
            // A refresh replaces every row, and cells a screen already
            // asked for would go with them — so an open inspector would
            // blank every time anything else was written.
            row.cells = cellCache[r.id].map(Self.cellRows)
            index[r.id] = row
        }
        for r in trashRows {
            var row = r
            row.cells = cellCache[r.id].map(Self.cellRows)
            // The trash verb is the only surface that returns these, so
            // the flag is what tells them apart once both are in one
            // index. Every other verb filters them out.
            row.trashed = true
            index[r.id] = row
        }
        entities = index
        assemble()
        // A refresh can retire an id — the box was replaced, or the
        // thing was emptied out of the trash. Cells kept for something
        // that is gone would be answered from memory forever.
        cellCache = cellCache.filter { entities[$0.key] != nil }
    }

    /// A read said no. **Locked means retry and mean it**; anything else
    /// is a fault the user must see, not a spinner.
    private func readFailed(_ fault: String) {
        engineHealth { [weak self] health in
            guard let self else { return }
            switch health?.code {
            case "ok", .none:
                // It opens, so the read failed for a reason a retry can
                // fix — most often the CLI or the share extension
                // holding the file for a moment.
                self.beginRetry()
            case "version":
                self.boxFault = health?.message ?? fault
                self.busyRetrying = false
            default:
                self.boxFault = health?.message ?? fault
                self.busyRetrying = false
            }
        }
    }

    /// One thing's cells, and a fetch if they are not here yet.
    ///
    /// **Returns what it has and asks for the rest.** A view calls this
    /// while rendering, so it cannot wait; the answer publishes and the
    /// view draws again. Empty on the first call for a thing is normal.
    func cells(of id: LivEntityID) -> [LivCell] {
        if let held = cellCache[id] { return held }
        guard !cellsInFlight.contains(id) else { return [] }
        cellsInFlight.insert(id)
        engineCells(id) { [weak self] found in
            guard let self else { return }
            // Still wanted? `forgetCells` takes an id out of the set
            // when a write makes the answer stale, and this is where that
            // decision is honoured.
            guard self.cellsInFlight.remove(id) != nil else { return }
            self.cellCache[id] = found
            // Into the row too, so `box.entity(id)?.cells` reads them —
            // which is how the inspector already asks.
            self.entities[id]?.cells = Self.cellRows(found)
            // Publishing is what makes the view draw again with them.
            self.objectWillChange.send()
        }
        return []
    }

    /// Engine cells in the shape the inspector reads.
    static func cellRows(_ cells: [LivCell]) -> [CellRow] {
        cells.map {
            CellRow(
                propertyId: $0.property, property: $0.name,
                kind: $0.holds, value: $0.value, refTarget: $0.ref)
        }
    }

    /// Forget one thing's cells, so the next ask re-reads them. Called
    /// after a write that changed them.
    func forgetCells(of id: LivEntityID) {
        cellCache.removeValue(forKey: id)
        // **And disown any answer already in the air.** A write clears
        // the cache and then lands; a read that started before it would
        // arrive afterwards carrying the values from before the write,
        // and put them back. Dropping it from the in-flight set is what
        // makes the late answer unwanted rather than authoritative.
        cellsInFlight.remove(id)
    }

    /// Days since the epoch — what every engine verb counts in, and NOT
    /// the packed civil the old ABI used. Pretending they are the same
    /// number is how a task ends up on the wrong side of midnight.
    ///
    /// **THE LOCAL CIVIL DAY, not the UTC one.** This was
    /// `floor(now / 86_400)`, which is the day it is in Greenwich. A due
    /// is a FLOATING civil day — `DateSpec::Day` is a civil day number
    /// with no zone in it — so the day handed to the engine has to be
    /// the day the person is living in, or for the hours either side of
    /// midnight every surface that splits on "today" splits on the
    /// wrong one. The same disagreement about what a number means as
    /// `EntityRow.due`, one layer up.
    ///
    /// `Civil.epochDay` already counted it correctly and `EngineCheck`
    /// already called it — the right answer was in the tree, beside a
    /// second spelling that was not (standing rule 4).
    static var todayDay: Int32 { Civil.epochDay(Civil.todayDay()) }

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
        let (code, message) = Self.health(of: enginePath)
        guard code != "ok" else {
            // The box is fine, so the verb was refused ON ITS MERITS — a
            // value that would not read, a link to nothing. Log it and
            // stop: a mutation must never replay itself.
            Self.log.notice("\(verb, privacy: .public) refused; box healthy")
            return
        }
        DispatchQueue.main.async {
            // **`io` is the retryable one.** The old ABI had a `locked`
            // code because opening a core box took the whole file; the
            // engine holds its connection in WAL mode, so contention is
            // rare — but a moment of it still reads as `io`, and so does
            // a file that has genuinely gone. Retrying is right for the
            // first and harmless for the second, which surfaces as a
            // fault on the next read either way. `version` and `corrupt`
            // are never transient and must be shown.
            if code == "io" {
                self.beginRetry()
            } else {
                self.boxFault = message
                self.busyRetrying = false
            }
        }
    }

    /// Why the box will not open, synchronously. Box-queue only.
    ///
    /// **The one engine verb called without the async wrapper**, because
    /// its callers are already deciding what to do about a failure and
    /// cannot hand the answer back to a closure. `liv_probe_box` opens
    /// the file itself and drops the connection, so it holds nothing a
    /// retry needs.
    static func health(of path: String) -> (code: String, message: String) {
        var out: UnsafeMutablePointer<CChar>?
        let rc = withUnsafeMutablePointer(to: &out) { liv_probe_box(path, $0) }
        let (value, _) = decodeView(LivBoxHealth.self, code: rc, out: out)
        return (value?.code ?? "io", value?.message ?? "The box did not open.")
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

    // MARK: writes — the same doors, the engine behind them
    //
    // **Every signature here is unchanged.** The callers are fifteen view
    // files and renaming them all would be fifteen files of risk for no
    // behaviour; what changed is what each one does. A property still
    // arrives as a NAME because that is what the views hold, and
    // `propertyId` turns it into the id the engine wants — once, cached,
    // from the box rather than from a table in Swift.

    /// One token of the filter grammar — what a chip is drawn from.
    ///
    /// **Standing rule 5: a user never types a query language.** The text
    /// is the storage format; this is how it becomes something to tap.
    /// One lexer, and it is in Rust (`engine::query::lex`).
    struct LivQueryTerm: Decodable, Equatable {
        /// equals | not-equals | at-most | has | no | is | text
        let op: String
        let key: String
        let value: String
        /// The token respelled canonically, so joining a term list
        /// reproduces a query the box reads back the same way.
        let raw: String
    }

    /// A compiled-in property's id, by the frozen name the views use.
    ///
    /// **Asked of the box, not hard-coded.** These names are the ones
    /// `op-format.md` calls ordinals-on-disk-forever, so the lookup is of
    /// something stable — but the ids are 32 hex characters and spelling
    /// them in Swift would be the shell keeping its own copy of the
    /// furniture, which is the mistake `one-core.md` §4 records.
    func propertyId(_ name: String, _ done: @escaping (LivID?) -> Void) {
        if let held = propertyIds[name] {
            done(held)
            return
        }
        engineProperty(name) { [weak self] id in
            if let id { self?.propertyIds[name] = id }
            done(id)
        }
    }

    /// A write that names its property by word. Nothing is written when
    /// the box has never heard of it — which is a refusal, not a crash.
    private func byName(
        _ verb: String, _ id: LivEntityID, _ property: String,
        _ done: ((Bool) -> Void)?,
        _ work: @escaping (LivID, LivID) -> Void
    ) {
        propertyId(property) { [weak self] p in
            guard let p else {
                self?.verbFailed(verb)
                done?(false)
                return
            }
            self?.forgetCells(of: id)
            work(id, p)
        }
    }

    /// Capture a scrap. **Untyped on purpose** — the clerk's promotion
    /// proposer can only offer to make it a task because nothing here
    /// decided first.
    func capture(_ text: String, done: ((LivEntityID) -> Void)? = nil) {
        let tracked = Outbox.tracking(.idea, done)
        engineCapture(text) { [weak self] id, fault in
            if fault != nil { self?.verbFailed("capture") }
            tracked(id ?? .absent)
        }
    }

    /// An empty, typed note — the editor's own creation door. Unlike
    /// `capture`, which refuses empty text, this births the entity so the
    /// caret has somewhere to land.
    func createNote(done: ((LivEntityID) -> Void)? = nil) {
        make(kindWord: "note", .idea, done)
    }

    func createTask(done: ((LivEntityID) -> Void)? = nil) {
        make(kindWord: "task", .task, done)
    }

    /// An event, and its date, as two writes rather than one verb.
    ///
    /// **The date arrives as a packed civil and leaves as a day.** The
    /// engine counts days since the epoch; `Civil` packs YYYYMMDDHHMM,
    /// and treating one as the other is how a thing lands on the wrong
    /// side of midnight.
    func createEvent(dueCivil: Int64, dateOnly: Bool, done: ((LivEntityID) -> Void)? = nil) {
        make(kindWord: "event", .event) { [weak self] id in
            guard let self, !id.isAbsent else {
                done?(id)
                return
            }
            self.set(id, "due", Self.dateText(dueCivil, dateOnly: dateOnly)) { _ in done?(id) }
        }
    }

    /// One of the kinds the box offers, by its word.
    private func make(
        kindWord: String, _ sort: OutboxKind, _ done: ((LivEntityID) -> Void)?
    ) {
        let tracked = Outbox.tracking(sort, done)
        engineKinds { [weak self] kinds in
            guard let self else { return }
            guard let k = kinds.first(where: { ($0.name ?? "").lowercased() == kindWord }) else {
                self.verbFailed("make \(kindWord)")
                tracked(.absent)
                return
            }
            self.engineMake(kind: k.id) { id, fault in
                if fault != nil { self.verbFailed("make \(kindWord)") }
                tracked(id ?? .absent)
            }
        }
    }

    /// A packed civil as the engine reads dates: `yyyy-mm-dd`, with
    /// `hh:mm` only when there is a time.
    static func dateText(_ civil: Int64, dateOnly: Bool) -> String {
        // **Int, not Int64, and padded by hand.**
        //
        // `String(format: "%d", someInt64)` is a varargs size mismatch:
        // `%d` reads an Int32 off the list, so every argument after the
        // first can be read from the wrong bytes. It is the kind of thing
        // that looks right for a year and comes out as zeros for the two
        // values after it — which is what "every event is due 00:00" was.
        //
        // Nothing here needs a format string. The components are small
        // integers and the shape is fixed.
        let day = Int(civil / 10_000)
        let (y, m, d) = (day / 10_000, (day / 100) % 100, day % 100)
        let stamp = "\(Civil.pad(y, 4))-\(Civil.pad(m, 2))-\(Civil.pad(d, 2))"
        if dateOnly { return stamp }
        let (hh, mm) = (Int((civil / 100) % 100), Int(civil % 100))
        return stamp + " \(Civil.pad(hh, 2)):\(Civil.pad(mm, 2))"
    }

    /// **A value crosses as text and the property says what it means.**
    /// A value that does not read is refused with nothing written.
    func set(_ id: LivEntityID, _ property: String, _ value: String, done: ((Bool) -> Void)? = nil) {
        byName("set", id, property, done) { [weak self] i, p in
            self?.engineSet(i, p, value) { fault in
                if fault != nil { self?.verbFailed("set") }
                done?(fault == nil)
            }
        }
    }

    /// One span write. **The engine has no date SPAN**, so the end is
    /// dropped and the start is written: `DateSpec` is a day or an
    /// instant and nothing holds two ends
    /// (`design/rust-owns-the-mechanisms.md` §5). A two-ended event keeps
    /// its start rather than being refused, and the gap is the gap.
    func setSpan(
        _ id: LivEntityID, _ property: String, start: Int64, end: Int64, dateOnly: Bool,
        done: ((Bool) -> Void)? = nil
    ) {
        set(id, property, Self.dateText(start, dateOnly: dateOnly), done: done)
    }

    func setType(_ id: LivEntityID, _ type: String, done: ((Bool) -> Void)? = nil) {
        engineKinds { [weak self] kinds in
            guard let self else { return }
            guard let k = kinds.first(where: { ($0.name ?? "").lowercased() == type.lowercased() })
            else {
                self.verbFailed("setType")
                done?(false)
                return
            }
            self.propertyId("kind") { p in
                guard let p else {
                    done?(false)
                    return
                }
                self.forgetCells(of: id)
                self.engineSet(id, p, engineId(k.id)) { fault in
                    done?(fault == nil)
                }
            }
        }
    }

    /// One cell of a multi-valued property — membership, never
    /// replace-all.
    func addCell(_ id: LivEntityID, _ property: String, _ value: String, done: ((Bool) -> Void)? = nil) {
        byName("addCell", id, property, done) { [weak self] i, p in
            self?.engineAdd(i, p, value) { done?($0 == nil) }
        }
    }

    /// The librarian: by reference, never moves the file.
    func addFile(_ path: String, done: ((LivEntityID) -> Void)? = nil) {
        let tracked = Outbox.tracking(.photo, done)
        engineAddFile(path) { [weak self] id, fault in
            if fault != nil { self?.verbFailed("addFile") }
            tracked(id ?? .absent)
        }
    }

    /// One value of a multi-valued property, removed by value — the
    /// mirror of `addCell`. **Add-wins**: a member added on another
    /// device survives it.
    func removeCell(_ id: LivEntityID, _ property: String, _ value: String, done: ((Bool) -> Void)? = nil) {
        byName("removeCell", id, property, done) { [weak self] i, p in
            self?.engineRemove(i, p, value) { done?($0 == nil) }
        }
    }

    /// Empty a cell. **Not the same as setting it to nothing** — an unset
    /// cell has no value, which is what a picker's "None" means.
    func unset(_ id: LivEntityID, _ property: String) {
        byName("unset", id, property, nil) { [weak self] i, p in
            self?.engineUnset(i, p)
        }
    }

    /// Put a trashed thing back. **Trashing is a cell, not a deletion**,
    /// which is what makes this a write rather than a resurrection.
    func restore(_ id: LivEntityID, done: ((Bool) -> Void)? = nil) {
        engineRestore(id) { done?($0 == nil) }
    }

    /// Soft, reversible, never cascades.
    func trash(_ id: LivEntityID) {
        engineTrash(id)
    }

    // MARK: workspaces + saved filters

    /// Birth a workspace. **An ordinary entity**, so this is `make` plus
    /// its cells — there is no special verb, which is the whole point of
    /// the primitives existing. The `query` cell is a separate `set`, so
    /// one refused write never half-builds a workspace.
    func createWorkspace(
        name: String, parent: LivEntityID = .absent, done: ((LivEntityID) -> Void)? = nil
    ) {
        furnish(kindWord: "workspace", name: name) { [weak self] id in
            guard let self, !id.isAbsent, !parent.isAbsent else {
                done?(id)
                return
            }
            self.set(id, "parent", engineId(parent)) { _ in done?(id) }
        }
    }

    /// Trash ONE workspace. Deletion never cascades: children keep their
    /// dangling `parent` and the shell re-roots them.
    func trashWorkspace(_ id: LivEntityID) {
        engineTrash(id)
    }

    /// Save a filter: a view entity carrying the query string.
    func createView(name: String, query: String, done: ((LivEntityID) -> Void)? = nil) {
        furnish(kindWord: "view", name: name) { [weak self] id in
            guard let self, !id.isAbsent else {
                done?(id)
                return
            }
            self.set(id, "query", query) { _ in done?(id) }
        }
    }

    /// A backstage thing of one kind, by word. Workspaces and saved
    /// filters are both this.
    ///
    /// **NOT through `engineKinds`.** That is the CREATE MENU's list —
    /// the six the product names plus what a user declared — and it
    /// leaves Workspace and View out on purpose: a person never picks
    /// one from a list. So this looked for a kind called "view", never
    /// found it, and gave up: saving a new filter wrote NOTHING, and a
    /// new workspace failed the same way, both without an error anyone
    /// could see (owner, 2026-09-15: "can't save new filters").
    ///
    /// `liv_kind_named` is the door for exactly this — the one
    /// `liv_property_named` already is for properties — and it does not
    /// widen the picker.
    private func furnish(
        kindWord: String, name: String, _ done: @escaping (LivEntityID) -> Void
    ) {
        engineKindNamed(kindWord) { [weak self] k in
            guard let self else { return }
            guard let k else {
                self.verbFailed("furnish \(kindWord)")
                done(.absent)
                return
            }
            self.engineMake(kind: k, name: name) { id, _ in done(id ?? .absent) }
        }
    }

    /// Declare a field the app did not ship with. **Minted once on one
    /// device**, which is what stops it drifting the way a seeded copy
    /// does: there is no second copy to disagree with.
    func addProperty(_ name: String, kind: String = "text", done: ((LivEntityID) -> Void)? = nil) {
        engineDeclareField(name, holds: kind) { [weak self] id, fault in
            if fault != nil { self?.verbFailed("addProperty") }
            done?(id ?? .absent)
        }
    }

    /// Mint a new value for a property that points at things.
    ///
    /// **The kind is whatever the property POINTS AT**, which the box
    /// knows and the shell does not: `area` wants an Area and `status` a
    /// Status. This minted an Option for both, which the cell then
    /// refused — a new area that could not be chosen.
    ///
    /// Asking twice hands back the one that exists.
    func addOption(_ property: LivEntityID, _ name: String, done: ((LivEntityID) -> Void)? = nil) {
        let p = engineId(property)
        engineWriteValue(LivMade.self, { to, out in
            liv_add_option(to, p, name, Self.nowMs, out)
        }) { [weak self] made, fault in
            if fault != nil { self?.verbFailed("addOption") }
            done?(made?.id ?? .absent)
        }
    }

    /// Rename ONE VALUE everywhere it is carried — one action, one undo.
    ///
    /// `done` receives the number of CARRIERS changed, which for a select
    /// is not the number of writes: one write to the option's name
    /// re-renders every carrier. nil on a refusal — an empty or unchanged
    /// name, a value nothing is called, or an ambiguous rename, which
    /// refuses rather than guessing.
    func renameValue(
        property: String, from old: String, to new: String,
        done: @escaping (Int?) -> Void
    ) {
        propertyId(property) { [weak self] p in
            guard let self, let p else {
                done(nil)
                return
            }
            self.engineRenameValue(p, from: old, to: new) { carriers, _ in done(carriers) }
        }
    }

    /// Take back this device's last action. **Undo is what YOU did here.**
    func undo() {
        engineUndo { [weak self] fault in
            if fault != nil { self?.verbFailed("undo") }
        }
    }

    // MARK: the clerk's proposals (rev 6 — suggest, never act)

    /// The suggestions aimed at one thing.
    ///
    /// **Named by the thing AND the fingerprint**, never a position: the
    /// sweep is recomputed in every process, so an index would mean
    /// something else by the time the user tapped it. `ordinal` is gone
    /// for that reason and reads 0.
    func proposals(for entity: LivEntityID) -> [ProposalRow] {
        (snap?.inbox ?? []).filter { $0.entity == entity }
    }

    /// The engine's name for a row the views hold.
    private func suggestion(_ p: ProposalRow) -> LivSuggestion {
        LivSuggestion(
            entity: p.entity, print: p.fingerprint,
            proposer: p.author, reason: p.reason)
    }

    /// Say yes to one. `done` is for a caller that files on top of the
    /// consent and must not write into a refusal.
    func accept(_ p: ProposalRow, done: ((Bool) -> Void)? = nil) {
        engineAccept(suggestion(p)) { [weak self] fault in
            if fault != nil { self?.verbFailed("accept") }
            done?(fault == nil)
        }
    }

    /// Say no. **Declining is not forgetting** — the refusal persists,
    /// and since 2026-09-13 it travels: saying no on the phone says no on
    /// the laptop too.
    func reject(_ p: ProposalRow) {
        engineDecline(suggestion(p)) { [weak self] fault in
            if fault != nil { self?.verbFailed("reject") }
        }
    }

    /// Say yes to a set, as ONE action and one undo. **All or nothing**:
    /// half a consent is worse than none. A suggestion the box no longer
    /// makes is skipped rather than failing the batch.
    func acceptGroup(_ fingerprints: [UInt64], done: ((Bool) -> Void)? = nil) {
        let wanted = Set(fingerprints)
        let many = (snap?.inbox ?? [])
            .filter { wanted.contains($0.fingerprint ?? 0) }
            .map(suggestion)
        engineAcceptAll(many) { [weak self] taken, fault in
            if fault != nil { self?.verbFailed("acceptGroup") }
            done?(taken != nil)
        }
    }

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

    // MARK: reads with their own payloads
    //
    // Each of these asks one question and pays for its answer. They used
    // to go through the core's own verbs; the signatures are unchanged
    // and the engine is behind them now.

    /// The status vocabulary offered to a kind, in the order the box
    /// keeps it. **The words come from the box**, never from a table in
    /// Swift — and so do `completes` and `hue`.
    ///
    /// This dropped both on the floor: it built each option from a name
    /// and a position and left `completes` nil. The ring writes
    /// "whichever option completes", found none, and wrote NOTHING — a
    /// task could not be ticked at all (owner, 2026-09-15). `liv_options`
    /// now carries the answer; this is the half that reads it.
    func statusOptions(kind: String, done: @escaping ([StatusOption]) -> Void) {
        propertyId("status") { [weak self] p in
            guard let self, let p else {
                done([])
                return
            }
            self.engineOptions(p) { named in
                done(named.enumerated().map { n, o in
                    StatusOption(
                        name: o.name, hue: o.hue, completes: o.completes ?? false,
                        order: Double(n))
                })
            }
        }
    }

    /// What this property is actually CARRYING — a different question
    /// from what it MAY hold, and the one a picker over a free-text field
    /// has to ask.
    func distinctValues(property: String, done: @escaping ([String]) -> Void) {
        propertyId(property) { [weak self] p in
            guard let self, let p else {
                done([])
                return
            }
            self.engineValuesInUse(p) { done($0.compactMap(\.label)) }
        }
    }

    /// One thing's body, and the fingerprint a save must present back.
    func content(_ id: LivEntityID, done: @escaping (ContentDoc?) -> Void) {
        engineBody(id) { [weak self] body, _ in
            guard let body else {
                done(nil)
                return
            }
            let row = self?.entities[id]
            done(ContentDoc(
                id: id,
                name: row?.title,
                trashed: row?.trashed ?? false,
                // The box opened and answered, so the thing is there —
                // `liv_read_body` faults rather than inventing a body.
                missing: false,
                fingerprint: body.print ?? 0,
                spans: body.spans))
        }
    }

    /// Every past version of one body, NEWEST first. Restoring one is an
    /// ordinary save of its spans over a freshly read base — the log is
    /// never rewritten, so a restore is itself a version.
    func history(_ id: LivEntityID, done: @escaping ([ContentVersion]) -> Void) {
        engineBodyHistory(id) { versions, _ in
            done(versions.map {
                ContentVersion(
                    seq: $0.seq,
                    // The old wire counted seconds; this one counts
                    // milliseconds, and the views divide.
                    time: $0.atMs.map { $0 / 1000 },
                    author: $0.author,
                    label: nil,
                    spans: $0.spans)
            })
        }
    }

    /// Both directions of one thing's links. A `[[ ]]` typed in a body is
    /// the same edge as a link picked in properties.
    func links(_ id: LivEntityID, done: @escaping (LinkSet) -> Void) {
        engineLinks(id) { [weak self] found in
            let named = { (ids: [LivID]?) -> [LinkRow] in
                (ids ?? []).map { target in
                    let row = self?.entities[target]
                    return LinkRow(
                        id: target,
                        name: row?.title,
                        kinds: row?.kinds,
                        // **The engine indexes both doors the same way**,
                        // so which door an edge came through is no longer
                        // on the wire. A link is a link.
                        property: "related",
                        fromBody: nil)
                }
            }
            done(LinkSet(out: named(found.out), inbound: named(found.inbound)))
        }
    }

    /// Save a body, compare-and-swap on the fingerprint it was read at.
    ///
    /// **Re-read, never overwrite**: there is no force flag by design.
    /// `done` gets 1 saved, -1 stale, 0 refused — the old shape, so the
    /// editor's save path is unchanged.
    func setContent(
        _ id: LivEntityID, spansJson: String, base: UInt64,
        done: @escaping (Int32, UInt64) -> Void
    ) {
        engineSaveBody(id, spansJson: spansJson, base: base) { [weak self] print, fault in
            self?.forgetCells(of: id)
            guard let print else {
                // -6 is the stale code, and it is the one the editor must
                // tell apart: it means someone else moved the body, so
                // re-read and decide rather than insisting.
                done(fault == Self.writeFault(-6) ? -1 : 0, base)
                return
            }
            done(1, print)
        }
    }

    /// Re-hash what a file points at on this device. A changed hash IS
    /// the integration — it is how Liv learns Word saved the file.
    func resyncFile(_ id: LivEntityID, done: ((Bool) -> Void)? = nil) {
        engineResync(id) { result, _ in
            done?(result?.state == "changed")
        }
    }

    /// Split a filter into the chips a person taps. No box, no lock.
    func lex(_ raw: String) -> [LivQueryTerm] {
        engineTerms(raw).map {
            LivQueryTerm(
                op: $0.op ?? "text", key: $0.key ?? "",
                value: $0.value ?? "", raw: $0.raw ?? "")
        }
    }

    /// The ids a LENS admits, plus its terms.
    ///
    /// **A lens RESTRICTS** where a search widens: `is:archived` here
    /// means only archived things, because a filter is a boundary.
    func query(
        _ raw: String,
        done: @escaping (Set<LivEntityID>, [LivQueryTerm]) -> Void
    ) {
        engineLens(raw) { lens, _ in
            done(
                // A SET, because a lens is a membership test: every
                // surface asks it `contains(row.id)` per row.
                Set(lens?.ids ?? []),
                (lens?.terms ?? []).map {
                    LivQueryTerm(
                        op: $0.op ?? "text", key: $0.key ?? "",
                        value: $0.value ?? "", raw: $0.raw ?? "")
                })
        }
    }

    /// Files this device cannot open, as words for a banner.
    ///
    /// **`absent` is not `gone`.** A hash travels and a path does not, so
    /// a file added on the laptop reaches the phone as a valid reference
    /// with no copy here — that is "find it for me", not "this is
    /// broken".
    func vaultAlerts(done: @escaping ([String]) -> Void) {
        engineFileAlerts { alerts in
            done(alerts.map { a in
                let name = a.name ?? "A file"
                return a.why == "absent"
                    ? "\(name) has not reached this device yet"
                    : "\(name) is no longer where Liv last saw it"
            })
        }
    }

    /// Ranked hits, how many matched, and the facets beside them.
    ///
    /// **A search box WIDENS**: `is:archived` means look in the archive
    /// too, because someone hunting for a thing wants it found.
    func search(
        _ query: String,
        done: @escaping ([LivEntityID], Int, [LivFacet]) -> Void
    ) {
        engineSearch(query) { found, _ in
            let hits = found?.hits ?? []
            let facets: [LivFacet] = (found?.facets ?? []).map { f in
                LivFacet(
                    label: f.label ?? "",
                    values: (f.values ?? []).map {
                        LivFacetValue(
                            label: $0.label ?? "",
                            count: $0.count ?? 0,
                            active: $0.active ?? false,
                            excluded: $0.excluded ?? false)
                    })
            }
            // The engine ranks everything the query matches and the limit
            // only cuts the list, so the total is the hit count when the
            // list is short of the ceiling.
            done(hits.map(\.id), hits.count, facets)
        }
    }
}

/// One row of a surface, as the engine reports it.
///
/// **The old snapshot's row by another name.** The engine's wire carries
/// the same facts in the spellings §3 asks for — one kind word rather
/// than a list, milliseconds rather than a packed civil, and the strings
/// the row will draw rather than ids for the shell to resolve.
struct EntityRow: Decodable, Identifiable {
    var id: LivID
    var title: String?
    var untitled: Bool?
    var kind: LivID?
    var dueMs: Int64?
    var allDay: Bool?
    var statusId: LivID?
    var done: Bool?
    var area: LivID?
    var createdMs: Int64?
    var touchedMs: Int64?
    var hasFile: Bool?
    /// **Does it hold any words?** Optional like every wire field (H1),
    /// and read as `false` when absent. This replaces `contentPrint`,
    /// which the engine cannot answer per row — see the note where that
    /// used to be.
    var hasBody: Bool?
    /// Filed away, which is NOT thrown away.
    var archived: Bool?
    /// In the trash. False on every surface but the trash, so a row
    /// carries which it is and nothing has to remember which list it
    /// came from.
    var trashed: Bool?
    /// **The word for the kind, lowercase** — `note`, `task`, `event`.
    /// The same spelling the query grammar uses, so the shell never keeps
    /// its own map from id to word (`one-core.md` §4).
    var kindWord: String?
    /// The status as a person reads it: a display name, because a status
    /// is an option someone can rename and the rename is supposed to show.
    var statusWord: String?
    var areaWord: String?
    /// This thing's cells, once something has asked for them.
    ///
    /// **Never on the wire.** The old snapshot shipped every cell of
    /// every entity on every refresh, which is most of what made it
    /// 3.5 MB. `BoxModel.cells(of:)` fetches one thing's when a screen
    /// opens it; nil means nobody has asked yet.
    var cells: [CellRow]? = nil

    private enum CodingKeys: String, CodingKey {
        case id, title, untitled, kind, dueMs, allDay, done, area
        case createdMs, touchedMs, hasFile, hasBody, archived, trashed
        case kindWord, statusWord, areaWord
        case statusId = "status"
    }

    /// What to draw.
    ///
    /// **The title is never empty and never an id** (owner, 2026-09-13):
    /// a thing nobody has named arrives already called something sensible
    /// — its kind's word and when, made in `liv-surface`. So the shell
    /// has nothing to invent, which is the point; it had four words for
    /// nothing before this precisely because each surface invented its own.
    ///
    /// `untitled` survives as a STYLING flag, not a text one: a made name
    /// is still not a given one, and a list draws it more quietly.
    var display: String { title ?? "" }

    /// Is this one of those? The places that used to ask
    /// `kinds?.contains("task")` ask here, so the spelling lives once.
    func isKind(_ word: String) -> Bool { kindWord == word }
    var isTask: Bool { isKind("task") }
    var isEvent: Bool { isKind("event") }
    var isNote: Bool { kindWord == nil || isKind("note") }

    // MARK: what the views already call these
    //
    // Renaming fifteen view files to the engine's spellings would be
    // fifteen files of risk for no behaviour. These are the old names,
    // computed.

    /// The old row carried a LIST because `core/` let a thing have
    /// several types. The engine's `kind` is one cell, so this is one
    /// word or none — and `isTask` above is what new code should ask.
    var kinds: [String]? { kindWord.map { [$0] } }
    var status: String? { statusWord }
    /// **THE WIRE COUNTS MILLISECONDS; THE SHELL SPEAKS PACKED CIVILS.**
    ///
    /// `Row.due_ms` is epoch ms (`surface/src/lib.rs`), and every reader
    /// on this side does `Civil.day(of:)` and `CalClock.minutes(of:)` —
    /// which divide by 10,000 and take a remainder. Handed a count of
    /// milliseconds those answer a number that is not a time at all: a
    /// block landed at an arbitrary minute of an arbitrary day, a due
    /// sheet opened on it, and tapping a quarter past nine wrote 09:15
    /// and read back something else (owner, 2026-09-15). The write was
    /// never the broken half.
    ///
    /// **UTC, deliberately.** A due crosses as TEXT with no zone, which
    /// `parse_date` takes as tz 0 — so a due is a floating wall-clock
    /// time that happens to be stored as ms. Reading it back in UTC is
    /// what makes 22:15 read as 22:15, on this device and on a device
    /// three zones over. Local would shift every due in the box the
    /// moment a plane landed.
    var due: Int64? { dueMs.map { Civil.civil(ofFloatingMs: $0) } }
    var dueDateOnly: Bool? { allDay }

    /// The same conversion, but this one IS an instant — `now_ms` off
    /// this device's clock — so it reads in the zone the person is
    /// standing in.
    var created: Int64? { createdMs.map { Civil.civil(ofInstantMs: $0) } }
    /// The MONOTONIC recency key — the newest transaction that touched
    /// this. Never printed as a time.
    var recency: UInt64? { touchedMs.map { UInt64(max(0, $0)) } }

    // **Things the engine cannot answer yet**, each returning nothing
    // rather than a wrong answer:
    //
    //  - `dueEnd` and `positionedBy` need a date SPAN and a recurrence.
    //    `DateSpec` has no span variant and nothing expands a recurrence,
    //    so a repeating or two-ended event is a gap, not a bug in these
    //    lines (`design/rust-owns-the-mechanisms.md` §5).
    //  - `vaultPath`: `hasFile` says whether there is one; WHERE it is on
    //    this device is `liv_file_alerts`, because a path does not
    //    survive a device boundary.
    //
    // **`contentPrint` WAS ONE OF THESE AND IS GONE** (2026-09-15). It
    // returned nil forever, and nil is not a harmless "not yet" when
    // four call sites read it as a question: `(contentPrint ?? 0) != 0`
    // is "does this hold words", and it answered no for everything in
    // the box. The Inbox listed nothing to route while the panel counted
    // eight captures; a record card never opened with its notes showing;
    // a tab card never said content lives here. `hasBody` is that
    // question, answered on the wire, and the fifth caller — the
    // editor's "did MY base move" — is a different question and now asks
    // a different thing. A stub that silently answers is worse than one
    // that is missing (standing rule 6).
    var dueEnd: Int64? { nil }
    var positionedBy: String? { nil }
    var vaultPath: String? { nil }
    var bookmarked: Bool? { nil }
}

extension EntityRow {
    /// Build a row by hand, in the words the views use.
    ///
    /// **For fixtures**, which is the only thing that builds one: every
    /// real row is decoded from a surface verb. The self-checks say
    /// `kinds:` and `status:` because that is what a row has always been
    /// called on this side, and the memberwise initialiser would make
    /// them say `kindWord:` and `statusWord:` — renaming a test to suit
    /// the wire, which is the tail wagging the dog.
    ///
    /// `kinds` is a LIST only because the old row carried one: `core/`
    /// let a thing have several types and the engine's `kind` is one
    /// cell, so the first word is the word.
    init(
        id: LivEntityID, title: String? = nil, kinds: [String]? = nil,
        status: String? = nil, cells: [CellRow]? = nil,
        // MILLISECONDS, like the wire — not the packed civil `row.due`
        // answers. The label said `due:` and meant ms, which is the
        // confusion this whole conversion exists to end.
        dueMs: Int64? = nil, allDay: Bool? = nil, archived: Bool? = nil,
        trashed: Bool? = nil, hasFile: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.kindWord = kinds?.first
        self.statusWord = status
        self.cells = cells
        self.dueMs = dueMs
        self.allDay = allDay
        self.archived = archived
        self.trashed = trashed
        self.hasFile = hasFile
    }
}

/// Today, already split. The shell does not decide which pile a row is in.
struct LivTodayView: Decodable {
    var late: [EntityRow]?
    var passed: [EntityRow]?
    var ahead: [EntityRow]?
    var allDay: [EntityRow]?
    var done: [EntityRow]?
    var next: LivID?
    var captured: Int?

    /// Everything the day itself holds, in the order the screen draws it.
    var onTheDay: [EntityRow] {
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
        _ done: @escaping ([EntityRow]?, String?) -> Void
    ) {
        let to = enginePath
        boxQueue.async {
            var out: UnsafeMutablePointer<CChar>?
            let code = liv_view_everything(to, slice, today, nil, &out)
            let (value, fault) = Self.decodeView([EntityRow].self, code: code, out: out)
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

    /// THE WIRE'S MILLISECONDS, PACKED. `yyyymmddHHMM`, the one shape
    /// every reader in the shell divides and remainders.
    ///
    /// **The zone is the argument**, because the two callers genuinely
    /// want different ones and picking either by default is wrong for
    /// the other. Use the two named wrappers below rather than this.
    static func civil(ofMs ms: Int64, in zone: TimeZone) -> Int64 {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let c = gregorian.dateComponents(in: zone, from: date)
        return pack(c.year ?? 0, c.month ?? 0, c.day ?? 0) * 10_000
            + Int64((c.hour ?? 0) * 100 + (c.minute ?? 0))
    }

    /// A DUE. It crossed to the engine as text with no zone, which
    /// `parse_date` reads as UTC, so reading it back in UTC is what
    /// makes the round trip exact: 22:15 in, 22:15 out, wherever the
    /// phone is. An all-day due is midnight UTC for the same reason,
    /// and local would drag it onto the day before west of Greenwich.
    static func civil(ofFloatingMs ms: Int64) -> Int64 {
        civil(ofMs: ms, in: utc)
    }

    /// A REAL INSTANT — when something was made or touched, off this
    /// device's clock — so it reads in the zone the person is in.
    static func civil(ofInstantMs ms: Int64) -> Int64 {
        civil(ofMs: ms, in: gregorian.timeZone)
    }

    private static let utc = TimeZone(secondsFromGMT: 0) ?? .current


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
        return clock(hm)
    }

    /// "14:00", always four digits — the clock face on its own, for the
    /// places that mean midnight when they say 00:00 and so cannot use
    /// `timeString` (a reminder body, a version's stamp). **The one clock
    /// in the shell**: there were four spellings of it, and three printed
    /// the minutes as 00 because they handed an `Int64` to `%02d`.
    static func clock(_ hhmm: Int64) -> String {
        let hm = Int(hhmm)
        return "\(pad(hm / 100, 2)):\(pad(hm % 100, 2))"
    }

    /// Zero-padded, without a format string.
    ///
    /// `String(format: "%02d", someInt64)` is a varargs size mismatch: `%d`
    /// takes four bytes off a list where the Int64 put eight, so every
    /// argument after the first reads the wrong bytes and comes out zero.
    /// That was "every event is due 00:00". Nothing here needs a format
    /// string — the parts are small integers and the shape is fixed.
    static func pad(_ n: Int, _ width: Int) -> String {
        let digits = String(max(0, n))
        return digits.count >= width
            ? digits
            : String(repeating: "0", count: width - digits.count) + digits
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
    var rows: [EntityRow]?
    var id: String { engineId(status ?? .absent) + (name ?? "") }
}

/// One block on the day's timeline, with its overlap already resolved.
///
/// **`column`/`columns` are a CLUSTER's, not a pair's**: two blocks that
/// miss each other can both hit a third, and all three share the width.
/// The engine works that out, because getting it wrong is a layout bug
/// that only shows up on a busy day.
struct LivBlock: Decodable, Identifiable {
    var row: EntityRow?
    var startMin: Int?
    /// Never zero, so a thing with no duration stays tappable.
    var minutes: Int?
    var column: Int?
    var columns: Int?
    var id: String { engineId(row?.id ?? .absent) }
}

/// One day: the all-day band, and the timeline under it.
struct LivDayView: Decodable {
    var allDay: [EntityRow]?
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

    var id: String { engineId(property ?? .absent) }
}

/// One thing a picker may offer: compiled-in furniture and the user's own
/// in one list, because that is what the cell accepts.
struct LivNamed: Decodable, Identifiable {
    var id: LivID
    var name: String?
    /// **Does choosing this CLOSE the thing?** Only a status answers it;
    /// every other vocabulary says false. Optional like every wire field
    /// (H1), and nil is read as "no" at the one place that asks.
    var completes: Bool?
    var hue: Int?
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
    var id: String { "\(engineId(entity ?? .absent)).\(print ?? 0)" }
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
    var id: String { label ?? engineId(property ?? .absent) }
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

/// An id as the ENGINE spells it: 32 hex characters.
///
/// **Not `LivIDText.written`, which is decimal and is for the SHELL's own
/// storage** — notification identifiers, `UserDefaults` keys, the outbox
/// ledger. Those are the shell talking to itself, and changing their
/// format would orphan everything already written.
///
/// Using `written` here was a real bug and a quiet one. It is
/// `String(id.core)` — the low 64 bits, in decimal — and the engine's
/// `parse_id` wants 32 hex characters, so every id the shell handed to C
/// came back LIV_ERR_ARG. Reads that take no id worked, which is exactly
/// why all five screens rendered and nothing could be created or edited.
func engineId(_ id: LivEntityID) -> String { id.hex }


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
            let (value, fault) = Self.decodeView(T.self, code: code, out: out)
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
            let (value, fault) = Self.decodeView(T.self, code: code, out: out)
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
        let k = engineId(kind)
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
        let (i, p) = (engineId(id), engineId(property))
        engineWrite({ to in liv_set(to, i, p, value, Self.nowMs) }, done)
    }

    func engineAdd(
        _ id: LivID, _ property: LivID, _ value: String,
        _ done: ((String?) -> Void)? = nil
    ) {
        let (i, p) = (engineId(id), engineId(property))
        engineWrite({ to in liv_add(to, i, p, value, Self.nowMs) }, done)
    }

    /// **Add-wins**: a member added on another device survives this.
    func engineRemove(
        _ id: LivID, _ property: LivID, _ value: String,
        _ done: ((String?) -> Void)? = nil
    ) {
        let (i, p) = (engineId(id), engineId(property))
        engineWrite({ to in liv_remove(to, i, p, value, Self.nowMs) }, done)
    }

    /// Empty a cell. **Not the same as setting it to nothing** — an unset
    /// cell has no value, which is what a picker's "None" means.
    func engineUnset(_ id: LivID, _ property: LivID, _ done: ((String?) -> Void)? = nil) {
        let (i, p) = (engineId(id), engineId(property))
        engineWrite({ to in liv_unset(to, i, p, Self.nowMs) }, done)
    }

    /// **Trashing is a cell, not a deletion**, which is what makes
    /// restore a write rather than a resurrection.
    func engineTrash(_ id: LivID, _ done: ((String?) -> Void)? = nil) {
        let i = engineId(id)
        engineWrite({ to in liv_trash(to, i, Self.nowMs) }, done)
    }

    func engineRestore(_ id: LivID, _ done: ((String?) -> Void)? = nil) {
        let i = engineId(id)
        engineWrite({ to in liv_restore(to, i, Self.nowMs) }, done)
    }

    // MARK: the editor

    func engineBody(_ id: LivID, _ done: @escaping (LivBody?, String?) -> Void) {
        let i = engineId(id)
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
        let i = engineId(id)
        engineWriteValue(LivBody.self, { to, out in
            liv_write_body(to, i, spansJson, base, Self.nowMs, out)
        }) { body, fault in done(body?.print, fault) }
    }

    func engineBodyHistory(_ id: LivID, _ done: @escaping ([LivBodyVersion], String?) -> Void) {
        let i = engineId(id)
        engineRead([LivBodyVersion].self, { to, out in liv_body_history(to, i, out) }) {
            done($0 ?? [], $1)
        }
    }

    func engineLinks(_ id: LivID, _ done: @escaping (LivLinks) -> Void) {
        let i = engineId(id)
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
        let p = engineId(property)
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

    /// A kind by name, **the backstage ones included** — which is what
    /// `engineKinds` deliberately does not answer. See `furnish`.
    func engineKindNamed(_ name: String, _ done: @escaping (LivID?) -> Void) {
        engineRead(LivMade.self, { to, out in liv_kind_named(to, name, out) }) { v, _ in
            done(v?.id)
        }
    }

    /// What this property is actually CARRYING — a different question
    /// from `engineOptions`, which asks what it may hold.
    func engineValuesInUse(_ property: LivID, _ done: @escaping ([LivInUse]) -> Void) {
        let p = engineId(property)
        engineRead([LivInUse].self, { to, out in liv_values_in_use(to, p, out) }) { v, _ in
            done(v ?? [])
        }
    }

    func engineCells(_ id: LivID, _ done: @escaping ([LivCell]) -> Void) {
        let i = engineId(id)
        engineRead([LivCell].self, { to, out in liv_cells(to, i, out) }) { v, _ in done(v ?? []) }
    }

    /// Rename one value of a property, everywhere it is carried.
    /// `carriers` is how many things change ON SCREEN, which for a select
    /// is not the number of writes: one write re-renders every carrier.
    func engineRenameValue(
        _ property: LivID, from old: String, to new: String,
        _ done: @escaping (Int?, String?) -> Void
    ) {
        let p = engineId(property)
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
        let i = engineId(id)
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
        let e = engineId(entity)
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
        let e = engineId(entity)
        engineWrite({ to in liv_decline(to, e, print, Self.nowMs) }, done)
    }

    /// Accept several as ONE action. **All or nothing, and one undo**:
    /// half a consent is worse than none. A suggestion the box no longer
    /// makes is skipped rather than failing the batch.
    func engineAcceptAll(_ many: [LivSuggestion], _ done: @escaping (Int?, String?) -> Void) {
        let pairs = many.compactMap { s -> (String, UInt64)? in
            guard let e = s.entity, let p = s.print else { return nil }
            return (engineId(e), p)
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
            let ptrs: [UnsafePointer<CChar>?] = held.map { p in p.map { UnsafePointer<CChar>($0) } }
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
    var id: String { "\(engineId(note ?? .absent)).\(line ?? 0)" }
}

extension BoxModel {
    /// What is in the trash, newest first.
    ///
    /// Named apart from `engineTrash(_:)`, which puts something INTO the
    /// trash. Two verbs one letter apart is the kind of pair that reads
    /// fine and calls the wrong one.
    func engineTrashRows(_ done: @escaping ([EntityRow]) -> Void) {
        engineRead([EntityRow].self, { to, out in liv_view_trash(to, out) }) { v, _ in
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

// MARK: - the engine lane: the vocabulary a picker offers

/// One property a person can put on something.
struct LivProperty: Decodable, Identifiable {
    var id: LivID
    var name: String?
    /// text | number | bool | datetime | reference | richtext | file
    var holds: String?
    var many: Bool?
    /// **The vocabulary comes with the field.** A picker handed the field
    /// and not its options has an empty list, and a picker with an empty
    /// list treats everything typed into it as new — so choosing "Work"
    /// from the six that exist tried to mint a seventh called Work.
    var options: [LivNamed]?
    var display: String { (name ?? "").isEmpty ? "Field" : (name ?? "") }
}

extension BoxModel {
    /// The fields a picker offers — not every property that exists.
    func engineProperties(_ done: @escaping ([LivProperty]) -> Void) {
        engineRead([LivProperty].self, { to, out in liv_properties(to, out) }) { v, _ in
            done(v ?? [])
        }
    }

    /// Turn the clerk on or off. **The box owns where the switch lives**,
    /// so this is one call rather than the shell knowing which thing to
    /// write a no onto.
    func setAssist(_ on: Bool, _ done: ((Bool) -> Void)? = nil) {
        engineWrite({ to in liv_set_assist(to, on, Self.nowMs) }) { done?($0 == nil) }
    }
}
