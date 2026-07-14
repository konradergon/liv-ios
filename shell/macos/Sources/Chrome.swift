// lotus — the window chrome of the Liv port (liv-ui-map.md §1, P1).
// Three chrome rows over an activity rail and a three-pane body. The
// active extension is app-global; vault-wide tools go full-bleed and
// hide the note chrome; the right inspector stays. Focus mode hides
// everything and restores it exactly.

import AppKit
import SwiftUI

// MARK: - extensions (§1.4)

enum Surface: String, CaseIterable {
    case notes
    case aiChat = "ai-chat"
    case tasks
    case lists
    case library
    case inbox
    case contacts
    case calendar
    case dashboard

    /// Vault-wide tools: full-bleed, no note chrome, no left sidebar.
    var isGlobalTool: Bool { self != .notes }

    var label: String {
        switch self {
        case .notes: return "Notes"
        case .aiChat: return "Chats"
        case .tasks: return "Tasks"
        case .lists: return "Lists"
        case .library: return "Library"
        case .inbox: return "Inbox"
        case .contacts: return "Contacts"
        case .calendar: return "Calendar"
        case .dashboard: return "Dashboard"
        }
    }

    /// SF Symbols at Liv's optical roles (§3.5 ACTIVITY_ICONS).
    var symbol: String {
        switch self {
        case .notes: return "doc.text"
        case .aiChat: return "bubble.left.and.text.bubble.right"
        case .tasks: return "checkmark.square"
        case .lists: return "list.bullet.rectangle"
        case .library: return "books.vertical"
        case .inbox: return "tray"
        case .contacts: return "person.2"
        case .calendar: return "calendar"
        case .dashboard: return "square.grid.2x2"
        }
    }
}

/// The right panel's lenses (bp4 five-lens bar, P17): each is already-owned
/// machinery re-homed — Metadata = the BP-1 inspector; ✦ Assist = the P16
/// amber cards (the AI's only panel home); Outline = a shell parse of the open
/// note; History = the content-version projection. The local Graph lens waits
/// for P18 (no dead buttons).
enum RightLens: String, CaseIterable {
    case metadata, assist, outline, history, graph

    var symbol: String {
        switch self {
        case .metadata: return "slider.horizontal.3"
        case .assist: return "sparkle"
        case .outline: return "list.bullet.indent"
        case .history: return "clock"
        case .graph: return "point.3.connected.trianglepath.dotted"
        }
    }

    var label: String {
        switch self {
        case .metadata: return "Metadata"
        case .assist: return "Assist"
        case .outline: return "Outline"
        case .history: return "History"
        case .graph: return "Graph"
        }
    }
}

// MARK: - navigation history (§2.6, the P1 slice)

/// The PLACES history (bp4 ⟨1⟩, P17f) — one merged ring for the rail
/// chevrons and ⌥←/⌥→: where the user was looking, as (workspace ·
/// surface · object). Records places, never text edits. Consecutive
/// dedup, forward truncation, bounded, replays don't re-record, and a
/// dangling target is pruned on replay (never crashes).
///
/// bp4's SECOND history (the per-content-tab back-stack) collapses to
/// nothing here by design: a lotus tab holds exactly one entity for its
/// whole life (dedup on open, blank converts once at birth), so there is
/// no within-tab navigation to stack — the places history subsumes it,
/// and reopen-with-content rides the ⌘⇧T tombstone ring.
final class NavHistory {
    struct Entry: Equatable {
        let workspace: UInt64?
        let surface: Surface
        let selection: UInt64?
    }

    private var entries: [Entry] = []
    private var index = -1
    private var replaying = false

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index < entries.count - 1 }

    func record(_ entry: Entry) {
        guard !replaying else { return }
        if index >= 0 && index < entries.count && entries[index] == entry { return }
        entries.removeSubrange((index + 1)...)
        entries.append(entry)
        if entries.count > 200 { entries.removeFirst() }
        index = entries.count - 1
    }

    func back() -> Entry? {
        guard canGoBack else { return nil }
        index -= 1
        return entries[index]
    }

    func forward() -> Entry? {
        guard canGoForward else { return nil }
        index += 1
        return entries[index]
    }

    /// Drop the entry the cursor sits on — a replay found its target gone
    /// (trashed under us). `forward` re-aims the cursor so the NEXT step in
    /// that direction lands on the entry that shifted into the hole.
    func pruneCurrent(forward: Bool) {
        guard index >= 0 && index < entries.count else { return }
        entries.remove(at: index)
        if forward { index -= 1 }
        index = min(index, entries.count - 1)
    }

    func replay(_ apply: () -> Void) {
        replaying = true
        apply()
        replaying = false
    }
}

/// The payload a chevron posts: the window completes the restore
/// (workspace → surface → tab → selection) and prunes dangling targets.
struct NavReplay {
    let entry: NavHistory.Entry
    let forward: Bool
}

// MARK: - the chrome model

final class ChromeModel: ObservableObject {
    @Published var surface: Surface {
        didSet {
            UserDefaults.standard.set(surface.rawValue, forKey: "app.activeExtension.v1")
            // Per-extension last-lens memory (bp4): each surface remembers
            // which right-panel lens it was on.
            rightLens =
                RightLens(
                    rawValue: UserDefaults.standard.string(forKey: "app.rightLens.v1.\(surface.rawValue)")
                        ?? "") ?? .metadata
        }
    }
    /// The right panel's active lens for the CURRENT surface — persisted
    /// per surface (shell state).
    @Published var rightLens: RightLens = .metadata {
        didSet {
            UserDefaults.standard.set(
                rightLens.rawValue, forKey: "app.rightLens.v1.\(surface.rawValue)")
        }
    }
    /// Panel widths, percentages of the body (§1.5).
    @Published var leftPct: Double
    @Published var rightPct: Double
    @Published var leftOpen: Bool
    @Published var rightOpen: Bool
    @Published var focusMode = false
    @Published var isFullscreen = false
    @Published var pinnedProject: UInt64?
    /// The calendar's selected day (civil YMD) — on the chrome, not inside
    /// CalendarView, because the GLOBAL right card renders the day panel for
    /// it (one right-panel code path; the calendar owns no private column).
    /// Transient view state, never a cell (interface.md 0.5).
    @Published var calendarDay: Int64 = Civil.todayYMD
    /// The active workspace — nil means the built-in Home (§2.7.1).
    /// A shell preference: losing it loses no data.
    @Published var activeWorkspace: UInt64? {
        didSet {
            UserDefaults.standard.set(activeWorkspace ?? 0, forKey: "app.activeWorkspace.v1")
        }
    }
    @Published var switcherOpen = false
    /// The vault graph overlay (P18c) — on the chrome so the command-map
    /// gate can see it (an @State copy in a stored closure goes stale).
    @Published var vaultGraphOpen = false
    /// Settings (P19a) — the fourth overlay carve-out; same gate rule.
    @Published var settingsOpen = false
    /// The centered search palette (⌘F / the magnifier). Search is a popup,
    /// not the list lens in place — the owner's call after seeing it live.
    @Published var searchOpen = false

    let nav = NavHistory()
    /// Focus mode stashes the panel states and restores them exactly.
    private var stashed: (left: Bool, right: Bool)?

    init() {
        let defaults = UserDefaults.standard
        surface = Surface(rawValue: defaults.string(forKey: "app.activeExtension.v1") ?? "")
            ?? .notes
        let panes = defaults.dictionary(forKey: "app.layout.panes.v4")
        // Persisted clamps: left ∈ [8,55], right ∈ [8,48] (§1.5).
        leftPct = min(max(panes?["left"] as? Double ?? 18, 8), 55)
        rightPct = min(max(panes?["right"] as? Double ?? 30, 8), 48)
        leftOpen = defaults.object(forKey: "app.leftPanel.open.v1") as? Bool ?? true
        rightOpen = defaults.object(forKey: "app.rightPanel.open.v1") as? Bool ?? true
        let workspace = UInt64(defaults.integer(forKey: "app.activeWorkspace.v1"))
        activeWorkspace = workspace == 0 ? nil : workspace
        // Observers don't fire in init — load the surface's last lens by hand.
        rightLens =
            RightLens(
                rawValue: defaults.string(forKey: "app.rightLens.v1.\(surface.rawValue)") ?? "")
            ?? .metadata
    }

    func persistPanes() {
        UserDefaults.standard.set(
            ["left": min(max(leftPct, 8), 55), "right": min(max(rightPct, 8), 48)],
            forKey: "app.layout.panes.v4")
        UserDefaults.standard.set(leftOpen, forKey: "app.leftPanel.open.v1")
        UserDefaults.standard.set(rightOpen, forKey: "app.rightPanel.open.v1")
    }

    /// True when the left panel is actually on screen. The sidebar is
    /// persistent across every surface now (Claude-style chrome), so
    /// this no longer keys on the surface — only on collapse / focus.
    var leftShown: Bool { leftOpen && !focusMode }

    /// The right panel's live max is capped so a right-handle drag can
    /// never cascade into and shrink the left sidebar — against the
    /// LIVE left width, whatever surface is showing.
    var rightLiveMax: Double {
        min(50, 100 - 30 - (leftShown ? leftPct : 0))
    }

    /// The mirror clamp for the left handle: center ≥ 30 holds from
    /// both sides.
    var leftLiveMax: Double {
        min(60, 100 - 30 - (rightOpen && !focusMode ? rightPct : 0))
    }

    /// Re-clamp persisted widths against the live maxima at launch: a
    /// stored left+right that once fit a Notes layout (where the left
    /// panel was hidden on tools) must not launch a tool surface into a
    /// negative center.
    func reconcilePanes() {
        leftPct = min(max(leftPct, 12), leftLiveMax)
        rightPct = min(max(rightPct, 10), rightLiveMax)
    }

    /// Nav mutations repaint the chevrons: the history itself is not
    /// observable, so the model announces on its behalf.
    /// Replays land asynchronously (selection onChange, workspace reload) —
    /// a short grace keeps those echoes out of the ring.
    private var recordGraceUntil = Date.distantPast

    func beginReplayGrace() {
        recordGraceUntil = Date().addingTimeInterval(0.4)
    }

    func recordNav(_ entry: NavHistory.Entry) {
        guard Date() >= recordGraceUntil else { return }
        objectWillChange.send()
        nav.record(entry)
    }

    /// The active scope must always resolve to a live workspace. If it
    /// no longer does — trashed here, or by the CLI, or archived — fall
    /// back to Home. Runs on every snapshot, so no path can strand it.
    func reconcileActive(_ workspaces: [WorkspaceRow]) {
        guard let active = activeWorkspace else { return }
        if !workspaces.contains(where: { $0.id == active && !$0.archived }) {
            activeWorkspace = nil
        }
    }

    func toggleFocus() {
        if focusMode {
            focusMode = false
            if let stash = stashed {
                leftOpen = stash.left
                rightOpen = stash.right
            }
            stashed = nil
        } else {
            stashed = (leftOpen, rightOpen)
            focusMode = true
        }
    }

    func goBack() {
        objectWillChange.send()
        guard let entry = nav.back() else {
            NSSound.beep()
            return
        }
        beginReplayGrace()
        NotificationCenter.default.post(
            name: .lotusNavReplay, object: NavReplay(entry: entry, forward: false))
    }

    func goForward() {
        objectWillChange.send()
        guard let entry = nav.forward() else {
            NSSound.beep()
            return
        }
        beginReplayGrace()
        NotificationCenter.default.post(
            name: .lotusNavReplay, object: NavReplay(entry: entry, forward: true))
    }

    /// The rail chevrons' dim state (repainted on the objectWillChange the nav
    /// mutations already send).
    var canNavBack: Bool { nav.canGoBack }
    var canNavForward: Bool { nav.canGoForward }
}

extension Notification.Name {
    static let lotusNavReplay = Notification.Name("lotus.navReplay")
    static let lotusNavFocus = Notification.Name("lotus.navFocus")
    static let lotusOpenSettings = Notification.Name("lotus.openSettings")
    static let lotusGoHome = Notification.Name("lotus.goHome")
    static let lotusGoInbox = Notification.Name("lotus.goInbox")
}

// MARK: - the activity rail (BP-4 · P17a)

/// A tight 44px icon strip — the global nav, pulled OUT of the panel so the
/// panel is pure Spaces/Vault. Feature-complete-but-tighter (owner ruling): the
/// 7 items that WORK ship now; the utility trio (Pin-project / Extensions /
/// Settings) mounts when its features land (17g / P19), never as dead buttons.
/// Notes sits alone at primary altitude above the seam; the 6 ambient surfaces
/// (Lists folds into Library, IA) sit below it.
struct LeftRail: View {
    @ObservedObject var chrome: ChromeModel
    @ObservedObject var model: BoxModel
    let select: (Surface) -> Void

    private let ambient: [Surface] = [.aiChat, .tasks, .library, .inbox, .contacts, .calendar, .dashboard]

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 0) {
                chevron("chevron.left", enabled: chrome.canNavBack) { chrome.goBack() }
                chevron("chevron.right", enabled: chrome.canNavForward) { chrome.goForward() }
            }
            .padding(.top, 2)
            hair()
            icon(.notes)          // Notes — alone, primary altitude
            hair()                // the altitude seam
            ForEach(ambient, id: \.rawValue) { icon($0) }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .frame(width: 44)
    }

    private func icon(_ surface: Surface) -> some View {
        let active = chrome.surface == surface
        return Button { select(surface) } label: {
            ZStack {
                Image(systemName: surface.symbol)
                    .font(.system(size: 15))
                    .foregroundColor(active ? Theme.accent : Theme.mutedFg)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(active ? Theme.accent.opacity(0.12) : .clear))
                if surface == .inbox { inboxCounts }
            }
            .frame(width: 34, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            if active {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent)
                    .frame(width: 3, height: 18).offset(x: -6)
            }
        }
        .help(surface.label)
    }

    /// Dual count on the ONE Inbox icon (space-conservative — no extra row):
    /// a neutral Route pip (top-right, never blue/lake-green) + an amber Tidy
    /// pip (bottom-right; amber = the AI hue).
    private var inboxCounts: some View {
        let route = model.orphans().count
        let tidy = model.snap?.inbox.count ?? 0
        return ZStack {
            if route > 0 {
                pip("\(route)", bg: Theme.mutedFg, fg: Color(nsColor: .windowBackgroundColor))
                    .offset(x: 12, y: -9)
            }
            if tidy > 0 {
                pip("\(tidy)", bg: Theme.warning, fg: Color(red: 0.22, green: 0.14, blue: 0))
                    .offset(x: 12, y: 9)
            }
        }
    }

    private func pip(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold)).foregroundColor(fg)
            .padding(.horizontal, 3).frame(minWidth: 12, minHeight: 12)
            .background(Capsule().fill(bg))
    }

    private func chevron(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(enabled ? Theme.mutedFg : Theme.mutedFg.opacity(0.3))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func hair() -> some View {
        Rectangle().fill(Theme.border).frame(width: 20, height: 1).padding(.vertical, 1)
    }
}

/// A quiet 28pt chrome icon-button — shared by the workspace footer's
/// appearance/settings controls.
private func headerButton(
    _ symbol: String, _ help: String, _ action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 28)
            .foregroundColor(Theme.mutedFg)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
}

// MARK: - workspace footer (the bottom switcher, popup opens upward)

/// Where "Konrad" sits in Claude: the active workspace, its popover
/// rising above, plus the appearance and settings controls. Replaces
/// Liv's HomeHub tab row — one fewer chrome row.
struct WorkspaceFooter: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var chrome: ChromeModel
    let actions: WorkspaceActions
    @State private var hubOpen = false
    // Manual double-click detection (the tab-strip idiom — a count:2 gesture
    // would stall the single click by the double-click interval).
    @State private var lastHubTap = Date.distantPast

    private var label: String {
        guard let id = chrome.activeWorkspace,
            let row = (model.snap?.workspaces ?? []).first(where: { $0.id == id })
        else { return "Home" }
        return row.name
    }

    /// bp4 ⑥: single click toggles the switcher popover; a second click
    /// inside the interval opens the Home hub surface itself.
    private func hubTapped() {
        let now = Date()
        if now.timeIntervalSince(lastHubTap) < NSEvent.doubleClickInterval {
            lastHubTap = .distantPast
            hubOpen = false
            NotificationCenter.default.post(name: .lotusGoHome, object: nil)
        } else {
            lastHubTap = now
            hubOpen.toggle()
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { hubTapped() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.primary)
                    Text(label)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.mutedFg)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .fill(hubOpen ? Theme.secondary.opacity(0.5) : .clear)
            )
            .popover(isPresented: $hubOpen, arrowEdge: .top) {
                HomeHubPopover(model: model, chrome: chrome, actions: actions) {
                    hubOpen = false
                }
            }
            appearanceButton
            headerButton("gearshape", "Settings (⌘,)") {
                NotificationCenter.default.post(name: .lotusOpenSettings, object: nil)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var appearanceButton: some View {
        headerButton(darkMode ? "sun.max" : "moon", "Toggle appearance") {
            let next = darkMode ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua)
            NSApp.appearance = next
            UserDefaults.standard.set(darkMode ? "dark" : "light", forKey: "app.appearance")
        }
    }

    private var darkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - pane divider (§1.5)

struct PaneDivider: View {
    let pct: Binding<Double>
    /// Absent for the left panel: it collapses by the header button now,
    /// not by drag — the handle only resizes.
    var open: Binding<Bool> = .constant(true)
    let total: CGFloat
    let minPct: Double
    let maxPct: Double
    /// Left panel grows rightward; the right panel grows leftward.
    let leadingEdge: Bool
    /// Drag-to-collapse (right inspector); false = resize only (left).
    var collapsible: Bool = true
    let persist: () -> Void

    @State private var startPct: Double?
    @State private var cursorPushed = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 7)
            .contentShape(Rectangle())
            .overlay(Divider().opacity(open.wrappedValue ? 0 : 1), alignment: .center)
            .onHover { inside in
                // Balanced by hand: a divider can vanish mid-hover (its
                // panel collapsing) and must not strand a resize cursor.
                if inside && !cursorPushed {
                    NSCursor.resizeLeftRight.push()
                    cursorPushed = true
                } else if !inside && cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("chrome.body"))
                    .onChanged { drag in
                        let base = startPct ?? (open.wrappedValue ? pct.wrappedValue : 0)
                        startPct = base
                        let delta = Double(drag.translation.width / total) * 100
                        let raw = base + (leadingEdge ? delta : -delta)
                        if collapsible && raw < minPct / 2 {
                            // Collapsible to 0 — persisted immediately:
                            // the collapse may unmount this very divider
                            // and cancel the gesture before onEnded.
                            if open.wrappedValue {
                                open.wrappedValue = false
                                persist()
                            }
                        } else {
                            open.wrappedValue = true
                            pct.wrappedValue = min(max(raw, minPct), maxPct)
                        }
                    }
                    .onEnded { _ in
                        startPct = nil
                        persist()
                    }
            )
    }
}

// MARK: - window drag regions (§1.2)

/// Liv's rows are OS drag regions; the content is not. Empty pixels in
/// the chrome start a window drag — interactive views above still win.
struct WindowDragRegion: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

// MARK: - focus chip (§1.6)

struct FocusChip: View {
    @ObservedObject var chrome: ChromeModel

    var body: some View {
        Button { chrome.toggleFocus() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11))
                Text("Exit focus").font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.panel.opacity(0.9)))
            .overlay(Capsule().strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .help("Exit focus mode (⌘.)")
        .padding(12)
    }
}

// MARK: - extension stub (§2.29)

struct ExtensionStub: View {
    let surface: Surface

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: surface.symbol)
                .font(.system(size: 56))
                .foregroundColor(Theme.foreground.opacity(0.1))
            Text(surface.label).font(.system(size: 15, weight: .semibold))
            Text("Coming soon.")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.mutedFg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
