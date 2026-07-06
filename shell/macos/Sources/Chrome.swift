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
    case library
    case inbox
    case contacts
    case calendar

    /// Vault-wide tools: full-bleed, no note chrome, no left sidebar.
    var isGlobalTool: Bool { self != .notes }

    var label: String {
        switch self {
        case .notes: return "Notes"
        case .aiChat: return "Chats"
        case .tasks: return "Tasks"
        case .library: return "Library"
        case .inbox: return "Inbox"
        case .contacts: return "Contacts"
        case .calendar: return "Calendar"
        }
    }

    /// SF Symbols at Liv's optical roles (§3.5 ACTIVITY_ICONS).
    var symbol: String {
        switch self {
        case .notes: return "doc.text"
        case .aiChat: return "bubble.left.and.text.bubble.right"
        case .tasks: return "checkmark.square"
        case .library: return "books.vertical"
        case .inbox: return "tray"
        case .contacts: return "person.2"
        case .calendar: return "calendar"
        }
    }
}

// MARK: - navigation history (§2.6, the P1 slice)

/// One merged stack for the rail chevrons and ⌥←/⌥→: where the user
/// was looking — surface + selected object. Consecutive dedup, forward
/// truncation, replays don't re-record.
final class NavHistory {
    struct Entry: Equatable {
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

    func replay(_ apply: () -> Void) {
        replaying = true
        apply()
        replaying = false
    }
}

// MARK: - the chrome model

final class ChromeModel: ObservableObject {
    @Published var surface: Surface {
        didSet { UserDefaults.standard.set(surface.rawValue, forKey: "app.activeExtension.v1") }
    }
    /// Panel widths, percentages of the body (§1.5).
    @Published var leftPct: Double
    @Published var rightPct: Double
    @Published var leftOpen: Bool
    @Published var rightOpen: Bool
    @Published var focusMode = false
    @Published var isFullscreen = false
    @Published var pinnedProject: UInt64?

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
    }

    func persistPanes() {
        UserDefaults.standard.set(
            ["left": min(max(leftPct, 8), 55), "right": min(max(rightPct, 8), 48)],
            forKey: "app.layout.panes.v4")
        UserDefaults.standard.set(leftOpen, forKey: "app.leftPanel.open.v1")
        UserDefaults.standard.set(rightOpen, forKey: "app.rightPanel.open.v1")
    }

    /// The right panel's live max is capped so a right-handle drag can
    /// never cascade into and shrink the left sidebar (§1.5).
    var rightLiveMax: Double {
        min(50, 100 - 30 - (leftOpen ? leftPct : 0))
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
        guard let entry = nav.back() else {
            NSSound.beep()
            return
        }
        nav.replay { surface = entry.surface }
        NotificationCenter.default.post(
            name: .lotusNavFocus, object: entry.selection)
    }

    func goForward() {
        guard let entry = nav.forward() else {
            NSSound.beep()
            return
        }
        nav.replay { surface = entry.surface }
        NotificationCenter.default.post(
            name: .lotusNavFocus, object: entry.selection)
    }
}

extension Notification.Name {
    static let lotusNavFocus = Notification.Name("lotus.navFocus")
    static let lotusOpenSettings = Notification.Name("lotus.openSettings")
    static let lotusGoHome = Notification.Name("lotus.goHome")
    static let lotusGoInbox = Notification.Name("lotus.goInbox")
}

// MARK: - title row (§1.2, §2.1)

struct TitleRow: View {
    @ObservedObject var chrome: ChromeModel

    var body: some View {
        ZStack {
            // The whole row is a drag region; the search sits absolutely
            // centered on the window, not in flex leftover space.
            HStack {
                if !chrome.isFullscreen {
                    Color.clear.frame(width: Theme.trafficLightSpacer)
                }
                Spacer()
            }
            HeaderSearch()
        }
        .frame(height: Theme.titleRowHeight)
        .background(Theme.background)
        .overlay(Divider(), alignment: .bottom)
    }
}

/// A button styled as a field (§2.1 HeaderSearch).
struct HeaderSearch: View {
    var body: some View {
        Button {
            CommandRegistry.shared.run("switcher:open")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.mutedFg)
                Text("Search")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.mutedFg)
                Spacer(minLength: 24)
                KbdChip(label: "⌘O")
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .fill(Theme.secondary.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(Theme.border.opacity(0.7))
            )
        }
        .buttonStyle(.plain)
        .help("Search (⌘O) — type > for commands")
        .padding(.horizontal, 120)
    }
}

// MARK: - tabs row (§1.2; the strip itself is P3)

struct TabsRow: View {
    @ObservedObject var chrome: ChromeModel

    var body: some View {
        HStack(spacing: 8) {
            // HomeHub (§2.7.2) — the workspace control; the popover
            // arrives with workspaces (P2). Reads the app name on a
            // vault-wide tool.
            Button {} label: {
                HStack(spacing: 4) {
                    Text(chrome.surface.isGlobalTool ? "lotus" : "Home")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Theme.mutedFg)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusMd)
                        .fill(Theme.secondary.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            Spacer()  // the tab strip lands here in P3
        }
        .frame(height: Theme.tabsRowHeight)
        .background(Theme.panel)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - bookmarks row (§1.2; SlotsBar chips are P2)

struct BookmarksRow: View {
    var body: some View {
        HStack {
            Spacer()
        }
        .frame(height: Theme.bookmarksRowHeight)
        .background(Theme.background)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - activity bar (§1.3)

struct ActivityBar: View {
    @ObservedObject var chrome: ChromeModel
    @ObservedObject var model: BoxModel
    @Namespace private var indicator
    @State private var pinMenuOpen = false

    var body: some View {
        VStack(spacing: 6) {
            navChevrons
            Divider().padding(.horizontal, 8)
            railButton(.notes)
            Divider().padding(.horizontal, 8)  // the altitude seam
            railButton(.aiChat, warningBadge: 0)
            railButton(.tasks)
            railButton(.library)
            railButton(
                .inbox,
                badge: model.snap?.unstructured.count ?? 0,
                badgeHelp: "unsorted objects in the inbox")
            railButton(.contacts)
            railButton(.calendar)
            Spacer()
            projectPin
            utilityButton("puzzlepiece") {}  // Browse extensions — as shipped, inert
            utilityButton(darkMode ? "sun.max" : "moon") { toggleAppearance() }
            utilityButton("gearshape") {
                NotificationCenter.default.post(name: .lotusOpenSettings, object: nil)
            }
        }
        .padding(.vertical, 10)
        .frame(width: Theme.railWidth)
        .background(Theme.panel.opacity(0.9))
        .overlay(Divider(), alignment: .trailing)
    }

    private var navChevrons: some View {
        HStack(spacing: 2) {
            Button { chrome.goBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 18, height: 24)
            .foregroundColor(
                chrome.nav.canGoBack ? Theme.mutedFg : Theme.mutedFg.opacity(0.2))
            .help("Back (⌥←)")
            Button { chrome.goForward() } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 18, height: 24)
            .foregroundColor(
                chrome.nav.canGoForward ? Theme.mutedFg : Theme.mutedFg.opacity(0.2))
            .help("Forward (⌥→)")
        }
    }

    private func railButton(
        _ surface: Surface, badge: Int = 0, badgeHelp: String = "", warningBadge: Int = -1
    ) -> some View {
        Button {
            chrome.surface = surface
            chrome.nav.record(.init(surface: surface, selection: nil))
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: surface.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundColor(
                        chrome.surface == surface ? Theme.primary : Theme.mutedFg.opacity(0.7)
                    )
                    .scaleEffect(chrome.surface == surface ? 1.05 : 1)
                if badge > 0 {
                    SoftBadge(count: badge).offset(x: 4, y: -2).help("\(badge) \(badgeHelp)")
                }
                if warningBadge > 0 {
                    WarningBadge(count: warningBadge).offset(x: 4, y: -2)
                }
            }
            .background {
                if chrome.surface == surface {
                    // The one gliding indicator: a pill that slides
                    // between icons instead of teleporting.
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .fill(Theme.primary.opacity(0.1))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Theme.primary)
                                .frame(width: 2, height: 16)
                        }
                        .matchedGeometryEffect(id: "rail", in: indicator)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(Theme.glide, value: chrome.surface)
        .help(surface.label)
    }

    private var projectPin: some View {
        Button { pinMenuOpen.toggle() } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "folder")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundColor(
                        chrome.pinnedProject != nil ? Theme.primary : Theme.mutedFg.opacity(0.7))
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .fill(
                                chrome.pinnedProject != nil
                                    ? Theme.primary.opacity(0.15) : .clear)
                    )
                if chrome.pinnedProject != nil {
                    Circle().fill(Theme.primary).frame(width: 8, height: 8)
                        .offset(x: -2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Pin project")
        .popover(isPresented: $pinMenuOpen, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PIN PROJECT")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.7)
                    .foregroundColor(Theme.mutedFg)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                Button {
                    chrome.pinnedProject = nil
                    pinMenuOpen = false
                } label: {
                    Label("Show all", systemImage: "xmark")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                ForEach(projects) { row in
                    Button {
                        chrome.pinnedProject = row.id
                        pinMenuOpen = false
                    } label: {
                        HStack {
                            Text(row.title).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            if chrome.pinnedProject == row.id {
                                Image(systemName: "checkmark").font(.system(size: 10))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                if projects.isEmpty {
                    Text("No projects yet.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.mutedFg)
                        .padding(10)
                }
            }
            .padding(.bottom, 8)
            .frame(width: 200, alignment: .leading)
        }
    }

    private var projects: [EntityRow] {
        (model.snap?.entities ?? []).filter { $0.kinds.contains("project") }
    }

    private func utilityButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundColor(Theme.mutedFg.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private var darkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func toggleAppearance() {
        let next = darkMode ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua)
        NSApp.appearance = next
        UserDefaults.standard.set(darkMode ? "dark" : "light", forKey: "app.appearance")
    }
}

// MARK: - pane divider (§1.5)

struct PaneDivider: View {
    let pct: Binding<Double>
    let open: Binding<Bool>
    let total: CGFloat
    let minPct: Double
    let maxPct: Double
    /// Left panel grows rightward; the right panel grows leftward.
    let leadingEdge: Bool
    let persist: () -> Void

    @State private var startPct: Double?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 7)
            .contentShape(Rectangle())
            .overlay(Divider().opacity(open.wrappedValue ? 0 : 1), alignment: .center)
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("chrome.body"))
                    .onChanged { drag in
                        let base = startPct ?? (open.wrappedValue ? pct.wrappedValue : 0)
                        startPct = base
                        let delta = Double(drag.translation.width / total) * 100
                        let raw = base + (leadingEdge ? delta : -delta)
                        if raw < minPct / 2 {
                            open.wrappedValue = false  // collapsible to 0
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
