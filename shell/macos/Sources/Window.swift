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
    let property: String
    let value: String
}

struct EntityRow: Codable, Identifiable, Hashable {
    let id: UInt64
    let title: String
    let kinds: [String]
    let due: Int64?
    let dueDateOnly: Bool
    let status: String?
    let created: Int64?
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
    let entities: [EntityRow]
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
    /// Editing is orthogonal state, like search: non-nil overrides the
    /// desk in the notes surface.
    @State private var editor: EditorModel?
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
                // The switcher owns the keyboard while open.
                CommandRegistry.shared.overlayActive = { chrome.switcherOpen }
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
                        search: { chrome.switcherOpen = true })
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
                search: { chrome.switcherOpen = true })
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
                    openEntity: { id in
                        closeEditor { ok in
                            guard ok else { return }
                            openEditor(id: id)
                        }
                    }
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
                // Search is the switcher now (the fake bar is gone); the
                // real omnibox lands in P6.
                if chrome.focusMode { chrome.toggleFocus() }
                chrome.switcherOpen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusFocusCapture)) { _ in
                closeEditor()
                chrome.surface = .notes
                query = ""
                lens = .today
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusNewNote)) { _ in
                // The newborn opens only once the old draft is safe: a
                // refused flush cancels the birth exactly as it cancels
                // a lens switch.
                chrome.surface = .notes
                closeEditor { ok in
                    guard ok else { return }
                    model.createNote { id in
                        if let id = id {
                            openEditor(id: id, bornBlank: true)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .lotusOpenStaleDraft)) { note in
                guard let draft = note.object as? DraftFile else { return }
                chrome.surface = .notes
                closeEditor { ok in
                    guard ok else { return }  // the journal file survives
                    openEditor(id: draft.entity, adopt: draft)
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
            default:
                ExtensionStub(surface: chrome.surface)
            }
        }
        .id(chrome.surface)
    }

    @ViewBuilder
    private var notesBody: some View {
        if let editing = editor {
            EditorView(model: editing).id(editing.id)
        } else if !query.isEmpty {
            ResultsView(model: model, query: query, selection: $selection)
        } else {
            switch lens {
            case .today:
                TodayView(model: model, selection: $selection) {
                    chrome.surface = .inbox
                }
            case .everything:
                EverythingView(model: model, selection: $selection)
            default:
                TodayView(model: model, selection: $selection) {
                    chrome.surface = .inbox
                }
            }
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
            openEditor(id: id)
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

struct ResultsView: View {
    @ObservedObject var model: BoxModel
    let query: String
    @Binding var selection: UInt64?

    var body: some View {
        let hits = (model.snap?.entities ?? []).filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.cells.contains { c in c.value.localizedCaseInsensitiveContains(query) }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LensHeader(
                    title: "Results",
                    subtitle: hits.count == 1 ? "1 match" : "\(hits.count) matches"
                )
                ForEach(hits) { row in
                    EntityLine(row: row, selected: selection == row.id) {
                        selection = row.id
                    }
                }
                if hits.isEmpty {
                    Text("Nothing matches.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

struct InspectorPane: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entity = model.entity(selection) {
                Text("SELECTED")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.5)
                    .foregroundColor(Color.secondary.opacity(0.7))
                    .padding(.bottom, 8)
                Text(entity.title)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.bottom, 20)
                ForEach(entity.cells, id: \.self) { cell in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(cell.property)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 72, alignment: .leading)
                        Text(cell.value)
                            .font(.system(size: 13))
                            .lineLimit(3)
                    }
                    .padding(.vertical, 7)
                    .overlay(Divider(), alignment: .bottom)
                }
            } else {
                Text("Select a row to see its cells.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
