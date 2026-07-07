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
}

/// A property definition — the inspector's catalog entry.
struct PropertyRow: Codable, Identifiable, Hashable {
    let id: UInt64
    let name: String
    let kind: String
    let options: [OptionRow]
}

struct EntityRow: Codable, Identifiable, Hashable {
    let id: UInt64
    let title: String
    let kinds: [String]
    let due: Int64?
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
    var id: String { label }
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

    static let empty = SearchResult()
}

// MARK: - the model: refresh-after-every-act, never hold the box

struct BoxFault: Codable {
    let code: String
    let message: String
}

final class BoxModel: ObservableObject {
    let path: String
    @Published var snap: Snapshot?
    @Published var boxBusy = false
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
        return snap?.entities.first { $0.id == id }
    }

    func rows(_ ids: [UInt64]) -> [EntityRow] {
        ids.compactMap { entity($0) }
    }

    func refresh() {
        let path = self.path
        boxQueue.async {
            guard let raw = lotus_snapshot(path) else {
                self.probeAndRetry()
                return
            }
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
                self.refresh()
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
    static let lotusFocusCapture = Notification.Name("lotus.focusCapture")
    static let lotusNewNote = Notification.Name("lotus.newNote")
    static let lotusOpenStaleDraft = Notification.Name("lotus.openStaleDraft")
}

// MARK: - lenses

enum Lens: String, CaseIterable, Identifiable {
    case today = "Today"
    case calendar = "Calendar"
    case everything = "Everything"
    case inbox = "Inbox"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: return "sparkles"
        case .calendar: return "calendar"
        case .everything: return "line.3.horizontal"
        case .inbox: return "tray"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .today: return "1"
        case .calendar: return "2"
        case .everything: return "3"
        case .inbox: return "4"
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
    @State private var selection: UInt64?
    /// The editor of the active note tab, when one is active.
    @State private var editor: EditorModel?
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
            if chrome.surface == .notes {
                Divider().padding(.top, 6)
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
                    showDesk: { lensValue in showDesk(lensValue) }
                )
            } else {
                Spacer(minLength: 0)
            }
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
                dismiss: { chrome.searchOpen = false }
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
                chrome.searchOpen = true
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
                // inspector must stay reopenable by mouse (§1.5).
                if !chrome.focusMode {
                    PaneDivider(
                        pct: $chrome.rightPct, open: $chrome.rightOpen, total: total,
                        minPct: 10, maxPct: chrome.rightLiveMax, leadingEdge: false
                    ) { chrome.persistPanes() }
                }
                if chrome.rightOpen && !chrome.focusMode {
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
            case .inbox:
                InboxView(model: model)
            case .calendar:
                CalendarView(model: model)
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
        // Search is a centered palette now, not the desk lens — the desk
        // shows Today / Everything.
        switch lens {
        case .everything:
            EverythingView(model: model, selection: $selection)
        default:
            TodayView(model: model, selection: $selection) {
                navigate(to: .inbox)
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
                id: "nav:back", label: "Back", scope: .global, category: "Navigate",
                binding: Hotkey(modifiers: [.alt], key: "ArrowLeft")
            ) {
                chrome.goBack()
            })
        registry.register(
            CommandDef(
                id: "nav:forward", label: "Forward", scope: .global, category: "Navigate",
                binding: Hotkey(modifiers: [.alt], key: "ArrowRight")
            ) {
                chrome.goForward()
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
    var select: () -> Void = {}

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                if row.kinds.contains("task") || row.status != nil {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                }
                Text(row.title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer()
                if showWhen, let due = row.due {
                    Text(Civil.text(due, dateOnly: row.dueDateOnly))
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accentTint : .clear))
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Today

struct TodayView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    /// The inbox is a rail surface now; Today only points at it.
    var openInbox: () -> Void = {}
    @State private var draft = ""
    @FocusState private var captureFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LensHeader(title: "Today", subtitle: todayLine)

                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("Capture a thought…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($captureFocused)
                        .onSubmit {
                            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            // The draft clears only when the log said yes:
                            // never lose a thought. A beep means retry.
                            model.capture(text) { ok in
                                if ok { draft = "" }
                            }
                        }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
                .onReceive(
                    NotificationCenter.default.publisher(for: .lotusFocusCapture)
                ) { _ in
                    captureFocused = true
                }

                if let snap = model.snap {
                    if !snap.today.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(text: "Due")
                            ForEach(model.rows(snap.today)) { row in
                                EntityLine(
                                    row: row,
                                    selected: selection == row.id
                                ) { selection = row.id }
                            }
                        }
                    }
                    if !snap.unstructured.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(text: "Captured · unstructured")
                            ForEach(model.rows(snap.unstructured)) { row in
                                EntityLine(
                                    row: row,
                                    showWhen: false,
                                    selected: selection == row.id
                                ) { selection = row.id }
                            }
                        }
                    }
                    if snap.today.isEmpty && snap.unstructured.isEmpty {
                        Text("Nothing waiting. Absence creates no debt.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    if !snap.inbox.isEmpty {
                        HStack(spacing: 4) {
                            Text(snap.inbox.count == 1
                                 ? "1 proposal waiting —"
                                 : "\(snap.inbox.count) proposals waiting —")
                                .foregroundColor(.secondary)
                            Button("open the inbox") { openInbox() }
                                .buttonStyle(.plain)
                                .foregroundColor(Theme.accent)
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var todayLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
}

// MARK: - Inbox

struct InboxView: View {
    @ObservedObject var model: BoxModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LensHeader(
                    title: "Inbox",
                    subtitle: model.snap.map { "\($0.inbox.count) waiting" } ?? "…"
                )
                if let inbox = model.snap?.inbox, !inbox.isEmpty {
                    ForEach(inbox) { proposal in
                        ProposalLine(model: model, proposal: proposal)
                    }
                    Text("Decline once and the clerk never asks again.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.secondary.opacity(0.8))
                        .padding(.top, 20)
                } else {
                    Text("Nothing waiting.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProposalLine: View {
    @ObservedObject var model: BoxModel
    let proposal: ProposalRow

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                subjectAndReason
                Text("#\(String(proposal.entity)) · \(Text("clerk · \(proposal.author)").foregroundColor(Theme.accent))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Accept") { model.accept(proposal) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            Button("Decline") { model.reject(proposal) }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 14)
        .overlay(Divider(), alignment: .bottom)
    }

    private var subjectAndReason: some View {
        let subject = model.entity(proposal.entity)?.title ?? "#\(proposal.entity)"
        return Text(
            "\(subject) — \(Text(proposal.reason).fontWeight(.semibold).foregroundColor(Theme.accentDeep))"
        )
        .font(.system(size: 14))
        .lineLimit(2)
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

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "done": return Color(red: 74 / 255, green: 158 / 255, blue: 134 / 255)
        case "doing": return Color(red: 207 / 255, green: 154 / 255, blue: 63 / 255)
        default: return Color.secondary.opacity(0.6)
        }
    }
}

// MARK: - Results (search is navigation)

/// The facet chips above the results: each value shows its hypothetical
/// count under the current filter, and clicking it pivots the search by
/// splicing its `key:value` token into the query string — the field and the
/// chips are one source of truth (parse-first, ported from Liv). Native
/// pills, lake-green when active — not Liv's rainbow chrome.
struct FacetBar: View {
    let facets: [SearchFacet]
    @Binding var query: String

    var body: some View {
        if !facets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(facets) { facet in
                        HStack(spacing: 5) {
                            Text(facet.label.capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            ForEach(facet.values) { value in
                                FacetChip(value: value) { toggle(facet.label, value) }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.bottom, 8)
        }
    }

    /// Single-select pivot: drop any existing qualifier for this facet, then
    /// add the clicked value unless it was already the active one (toggle
    /// off). Re-running the same string the field shows keeps them in sync.
    private func toggle(_ key: String, _ value: SearchFacetValue) {
        let key = key.lowercased()
        var tokens = query.split(separator: " ").map(String.init)
        tokens.removeAll { $0.lowercased().hasPrefix("\(key):") }
        if !value.active {
            tokens.append("\(key):\(value.label.lowercased())")
        }
        query = tokens.joined(separator: " ")
    }
}

/// One facet value pill: label + hypothetical count, lake-green when active.
struct FacetChip: View {
    let value: SearchFacetValue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(value.label)
                    .font(.system(size: 11.5))
                Text("\(value.count)")
                    .font(.system(size: 10))
                    .foregroundColor(value.active ? Theme.accent : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(value.active ? Theme.accent : .primary)
            .background(
                Capsule().fill(value.active ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(
                    value.active ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(value.active ? "Remove filter" : "Filter to \(value.label)")
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

    @State private var query = ""
    @State private var highlighted = 0
    @State private var keyMonitor: Any?
    @FocusState private var fieldFocused: Bool

    /// The hits resolved against the snapshot, always fresh (computed) so
    /// keyboard nav and Enter never read a stale count.
    private var rows: [EntityRow] {
        model.rows(model.searchResult.hits.map(\.id))
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
                    TextField("Search…  try type:task  status:done  #idea", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($fieldFocused)
                        .onSubmit {
                            if rows.indices.contains(highlighted) {
                                open(rows[highlighted].id)
                                dismiss()
                            }
                        }
                        .onExitCommand { dismiss() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if !model.searchResult.facets.isEmpty {
                    Divider()
                    FacetBar(facets: model.searchResult.facets, query: $query)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                }

                Divider()

                if rows.isEmpty {
                    Text(fresh && !query.isEmpty ? "Nothing matches." : "Type to search.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.mutedFg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                Button {
                                    open(row.id)
                                    dismiss()
                                } label: {
                                    resultRow(row)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.radiusMd)
                                        .fill(index == highlighted ? Theme.primary.opacity(0.12) : .clear)
                                )
                                .onHover { if $0 { highlighted = index } }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 380)
                }
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
            fieldFocused = true
            model.search(query) // seed recent immediately, don't wait 150ms
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let count = self.rows.count
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

    @ViewBuilder
    private func resultRow(_ row: EntityRow) -> some View {
        HStack(spacing: 9) {
            Image(systemName: kindIcon(row))
                .font(.system(size: 13))
                .foregroundColor(Theme.accent)
                .frame(width: 18)
            Text(row.title.isEmpty ? "Untitled" : row.title)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !row.kinds.isEmpty {
                Text(row.kinds.joined(separator: " · "))
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.mutedFg)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }

    private func kindIcon(_ row: EntityRow) -> String {
        if row.kinds.contains("task") || row.status != nil { return "checkmark.square" }
        if row.kinds.contains("event") { return "calendar" }
        if row.kinds.contains("person") { return "person" }
        if row.kinds.contains("project") { return "folder" }
        return "doc.text"
    }
}

// MARK: - Calendar

struct CalendarView: View {
    @ObservedObject var model: BoxModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let dows = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        let now = Date()
        let cal = Civil.gregorian
        let parts = cal.dateComponents([.year, .month], from: now)
        let first = cal.date(from: parts) ?? now
        let range = cal.range(of: .day, in: .month, for: first) ?? 1..<29
        let lead = cal.component(.weekday, from: first) - 1
        let monthKey = Int64(parts.year! * 100 + parts.month!)
        var byDay = Dictionary(grouping: model.rows(model.snap?.dated ?? [])) {
            row -> Int64 in (row.due ?? 0) / 10_000
        }
        // Virtual occurrences land beside the plain dates: the series
        // entity is drawn on every day its rule names, computed by the
        // engine so every view agrees.
        for occurrence in model.snap?.occurrences ?? [] {
            if let series = model.entity(occurrence.series) {
                byDay[occurrence.civil / 10_000, default: []].append(series)
            }
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LensHeader(title: monthTitle(first), subtitle: "month")
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(dows, id: \.self) { dow in
                        Text(dow.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(0.4)
                            .foregroundColor(Color.secondary.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)
                    }
                    ForEach(0..<lead, id: \.self) { _ in
                        Color.clear.frame(height: 92)
                    }
                    ForEach(range, id: \.self) { day in
                        let key = monthKey * 100 + Int64(day)
                        DayCell(
                            day: day,
                            isToday: key == Civil.todayYMD,
                            events: byDay[key] ?? []
                        )
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Civil.gregorian
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

struct DayCell: View {
    let day: Int
    let isToday: Bool
    let events: [EntityRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isToday {
                Text("\(day)")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.accent))
            } else {
                Text("\(day)")
                    .font(.system(size: 12.5).monospacedDigit())
            }
            // Plain text, primary color: hierarchy from typography, never
            // from boxes — and the accent keeps its three jobs (the today
            // circle is the calendar's only green).
            ForEach(events.prefix(3)) { row in
                Text(row.title)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
            if events.count > 3 {
                Text("+\(events.count - 3) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(minHeight: 92, alignment: .topLeading)
        .overlay(Divider(), alignment: .bottom)
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
                            EntityLine(row: row, selected: selection == row.id) {
                                open(row.id)
                            }
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

struct InspectorPane: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?

    /// Cells the header or the editor owns — not editable rows here.
    /// bookmarked/archived are the header's own actions, so they are not
    /// repeated as toggle rows. order/builtin are structural plumbing a
    /// user never hand-edits, so they stay out of the property sheet.
    static let reserved: Set<String> = [
        "name", "content", "created", "type", "bookmarked", "archived",
        "order", "builtin",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let entity = model.entity(selection) {
                    InspectorHeader(model: model, entity: entity, selection: $selection)
                    ForEach(rows(for: entity), id: \.propertyId) { cell in
                        FieldRow(model: model, entity: entity.id, cell: cell)
                    }
                    if let created = entity.created {
                        Text("Created \(Civil.text(created, dateOnly: false))")
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondary.opacity(0.7))
                            .padding(.top, 16)
                    }
                    if entity.cells.contains(where: { $0.property == "content" }) {
                        HistorySection(model: model, id: entity.id)
                            .padding(.top, 16)
                    }
                } else {
                    Text("Select a row to see its cells.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// A row for every user-facing property, present or not — so all of
    /// them are visible and editable in place, no Add-property menu. An
    /// absent property renders an empty control that writes a cell on
    /// first edit. Reference/file kinds still need the entity picker (a
    /// follow-up), so they show only when already set (read-only).
    private func rows(for entity: EntityRow) -> [CellRow] {
        let present = Dictionary(
            entity.cells.map { ($0.propertyId, $0) }, uniquingKeysWith: { first, _ in first })
        return model.properties()
            .filter { !Self.reserved.contains($0.name) }
            .compactMap { prop -> CellRow? in
                if let cell = present[prop.id] { return cell }
                if prop.kind == "reference" || prop.kind == "file" { return nil }
                return CellRow(
                    propertyId: prop.id, property: prop.name, kind: prop.kind,
                    value: "", refTarget: nil)
            }
            .sorted { $0.property < $1.property }
    }
}

// MARK: - inspector header (title, kind, actions)

struct InspectorHeader: View {
    @ObservedObject var model: BoxModel
    let entity: EntityRow
    @Binding var selection: UInt64?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: kindSymbol)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.accent)
                Text(entity.title.isEmpty ? "Untitled" : entity.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(entity.title.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                // The bookmark / archive / trash actions sit at the far
                // right of the header, on the title's line.
                actionButton(
                    entity.bookmarked ? "bookmark.fill" : "bookmark",
                    entity.bookmarked ? "Remove bookmark" : "Bookmark",
                    active: entity.bookmarked
                ) {
                    model.set(entity.id, property: "bookmarked", value: entity.bookmarked ? "false" : "true")
                }
                actionButton(
                    entity.archived ? "archivebox.fill" : "archivebox",
                    entity.archived ? "Unarchive" : "Archive",
                    active: entity.archived
                ) {
                    model.set(entity.id, property: "archived", value: entity.archived ? "false" : "true")
                }
                actionButton("trash", "Move to Trash", active: false) {
                    Dialogs.shared.confirm(
                        "Move to Trash?", message: "Reversible with ⌘⌥Z.",
                        danger: true, confirmLabel: "Trash"
                    ) { yes in
                        guard yes else { return }
                        model.trash(entity.id) { ok in if ok { selection = nil } }
                    }
                }
            }
            if !entity.kinds.isEmpty {
                Text(entity.kinds.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 16)
        .overlay(Divider(), alignment: .bottom)
        .padding(.bottom, 12)
    }

    private var kindSymbol: String {
        if entity.kinds.contains("task") || entity.status != nil { return "checkmark.square" }
        if entity.kinds.contains("event") { return "calendar" }
        if entity.kinds.contains("person") { return "person" }
        if entity.kinds.contains("project") { return "folder" }
        return "doc.text"
    }

    private func actionButton(
        _ symbol: String, _ help: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(active ? Theme.accent : Theme.mutedFg)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - one editable field, dispatched by value-kind

struct FieldRow: View {
    @ObservedObject var model: BoxModel
    let entity: UInt64
    let cell: CellRow
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(cell.property)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 76, alignment: .leading)
            control
            // Only a set property can be cleared; an empty one has no cell.
            if hovering && !cell.value.isEmpty {
                Button {
                    model.unset(entity, property: cell.property)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.mutedFg)
                }
                .buttonStyle(.plain)
                .help("Remove this property")
            }
        }
        .padding(.vertical, 6)
        .overlay(Divider(), alignment: .bottom)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var control: some View {
        switch cell.kind {
        case "bool":
            Toggle("", isOn: Binding(
                get: { cell.value == "yes" || cell.value == "true" },
                set: { model.set(entity, property: cell.property, value: $0 ? "true" : "false") }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            Spacer(minLength: 0)
        case "select":
            SelectField(model: model, entity: entity, cell: cell)
        case "reference":
            Text(cell.value)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.accent)
            Spacer(minLength: 0)
        default:
            EditableText(model: model, entity: entity, cell: cell)
        }
    }
}

/// A commit-on-blur/Enter text field over a cell — text, number, and
/// datetime all edit as their string form (parsed by the seam's kind).
struct EditableText: View {
    @ObservedObject var model: BoxModel
    let entity: UInt64
    let cell: CellRow
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .focused($focused)
            .onAppear { draft = cell.value }
            // An external refresh must not clobber a value being typed.
            .onChange(of: cell.value) { if !focused { draft = cell.value } }
            // Return blurs; the single commit rides the focus change, so
            // Enter and click-away never both fire a set for one edit.
            .onSubmit { focused = false }
            .onChange(of: focused) { if !focused { commit() } }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed != cell.value else { return }
        if trimmed.isEmpty {
            model.unset(entity, property: cell.property)
        } else {
            // A value the seam can't parse (a bad date, a non-number)
            // beeps and changes nothing — revert the draft to what is
            // stored so the field never lingers showing an uncommitted,
            // invalid string.
            model.set(entity, property: cell.property, value: trimmed) { ok in
                if !ok { draft = cell.value }
            }
        }
    }
}

/// A select cell edited via a menu of the property's options.
struct SelectField: View {
    @ObservedObject var model: BoxModel
    let entity: UInt64
    let cell: CellRow

    var body: some View {
        let options = model.property(named: cell.property)?.options ?? []
        Menu {
            ForEach(options) { option in
                Button(option.name) {
                    model.set(entity, property: cell.property, value: option.name)
                }
            }
        } label: {
            Text(cell.value.isEmpty ? "—" : cell.value)
                .font(.system(size: 12.5))
                .foregroundColor(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        Spacer(minLength: 0)
    }
}

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
