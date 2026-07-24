// liv iOS — the desk-first chrome (design/ios.md §6, revision 2): the body
// IS the desk (content tabs, the Obsidian idioms); features are transient
// windows summoned from the always-present menu button and presented OVER
// the whole chrome, bar included. The bar copies Obsidian's nav row:
// [features ^] ‹ › search + [tab count]. DeskModel is transient shell
// state — tabs persist per device in UserDefaults, never as cells.

import SwiftUI

/// Ink for solid amber fills (the desktop's onYellowInk; Kit's copy is
/// file-private).
private let chromeAmberInk = Color(red: 0x3A / 255, green: 0x2A / 255, blue: 0)

// MARK: - features

/// The lens roster. Calendar is a v1 placeholder — its body renders
/// EmptyHint("Calendar arrives with M3.") until M3.
enum Feature: String, CaseIterable, Identifiable {
    case today, inbox, tasks, calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .tasks: return "Tasks"
        case .calendar: return "Calendar"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .inbox: return "tray"
        case .tasks: return "checkmark.circle"
        case .calendar: return "calendar"
        }
    }

    var filledIcon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .inbox: return "tray.fill"
        case .tasks: return "checkmark.circle.fill"
        case .calendar: return "calendar"  // no .fill variant exists
        }
    }
}

// MARK: - desk tabs

struct DeskTab: Identifiable {
    let id: UUID
    var content: DeskTabContent
}

enum DeskTabContent: Equatable {
    case new
    case entity(UInt64)
}

/// The chrome's one state object. Boots in Feature view on Today; the
/// desk keeps at least one tab alive at all times. Entity-tab ids + the
/// active index ride UserDefaults ("desk.tabs.v1"); ids missing from the
/// box are dropped LAZILY — the dead tab renders an EmptyHint, never a
/// crash and never an eager sweep against a box that may still be opening.
final class DeskModel: ObservableObject {
    /// The feature window currently covering the chrome (sheet item);
    /// nil = the desk.
    @Published var featureShown: Feature?
    @Published private(set) var tabs: [DeskTab]
    @Published var activeTabId: UUID? {
        didSet { persist() }
    }
    @Published var switcherShown = false
    @Published var searchShown = false
    @Published var gridShown = false
    @Published var cameraShown = false

    /// Tab-activation history for the bar's ‹ › — device state, not cells.
    private var backIds: [UUID] = []
    private var forwardIds: [UUID] = []

    private static let persistKey = "desk.tabs.v1"

    var activeTab: DeskTab? {
        tabs.first { $0.id == activeTabId }
    }

    var canGoBack: Bool { backIds.contains { alive($0) } }
    var canGoForward: Bool { forwardIds.contains { alive($0) } }

    private func alive(_ id: UUID) -> Bool {
        tabs.contains { $0.id == id }
    }

    /// Activate a tab, recording history. Every activation path funnels
    /// here so ‹ › always tell the truth.
    func focus(_ tabId: UUID) {
        guard tabId != activeTabId else { return }
        if let current = activeTabId { backIds.append(current) }
        forwardIds.removeAll()
        activeTabId = tabId
        objectWillChange.send()
    }

    func goBack() {
        while let id = backIds.popLast() {
            guard alive(id) else { continue }
            if let current = activeTabId { forwardIds.append(current) }
            activeTabId = id
            objectWillChange.send()
            return
        }
    }

    func goForward() {
        while let id = forwardIds.popLast() {
            guard alive(id) else { continue }
            if let current = activeTabId { backIds.append(current) }
            activeTabId = id
            objectWillChange.send()
            return
        }
    }

    init() {
        var restored: [DeskTab] = []
        var active = -1
        if let stored = UserDefaults.standard.dictionary(forKey: Self.persistKey) {
            let ids = (stored["ids"] as? [String] ?? []).compactMap { UInt64($0) }
            restored = ids.map { DeskTab(id: UUID(), content: .entity($0)) }
            active = stored["active"] as? Int ?? -1
        }
        if restored.isEmpty { restored = [DeskTab(id: UUID(), content: .new)] }
        tabs = restored
        activeTabId =
            restored.indices.contains(active) ? restored[active].id : restored.first?.id
    }

    /// Focus the tab already holding this entity, or append one. Opening a
    /// row anywhere lands you at the desk — the desktop's rail→center
    /// gesture grammar.
    func open(_ entityId: UInt64) {
        if let existing = tabs.first(where: { $0.content == .entity(entityId) }) {
            focus(existing.id)
        } else {
            let tab = DeskTab(id: UUID(), content: .entity(entityId))
            tabs.append(tab)
            focus(tab.id)
        }
        featureShown = nil
        switcherShown = false
        gridShown = false
        persist()
    }

    func newTab() {
        let tab = DeskTab(id: UUID(), content: .new)
        tabs.append(tab)
        focus(tab.id)
        featureShown = nil
        persist()
    }

    /// Closing the last tab leaves one fresh .new tab — the desk is never
    /// empty.
    func close(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            let fresh = DeskTab(id: UUID(), content: .new)
            tabs = [fresh]
            activeTabId = fresh.id
        } else if activeTabId == tabId {
            activeTabId = tabs[min(index, tabs.count - 1)].id
        }
        persist()
    }

    /// A .new tab became an entity tab (the capture door committed).
    func setContent(_ tabId: UUID, entity: UInt64) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].content = .entity(entity)
        persist()
    }

    /// Entity ids only — .new tabs are moments, not state worth restoring.
    private func persist() {
        var ids: [String] = []
        var active = -1
        for tab in tabs {
            guard case .entity(let entity) = tab.content else { continue }
            if tab.id == activeTabId { active = ids.count }
            ids.append(String(entity))
        }
        UserDefaults.standard.set(
            ["ids": ids, "active": active], forKey: Self.persistKey)
    }
}

// MARK: - top bar

/// Both modes: the workspace hub left (the desktop HomeHub — one
/// workspace in v1, so the menu is a placeholder), the gear right.
struct TopBar: View {
    @State private var settingsShown = false

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Text("Home is the only workspace yet.")
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "house")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LivTheme.text2)
                    Text("Home")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LivTheme.text)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                .contentShape(Rectangle())
            }
            Spacer()
            Button {
                settingsShown = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .sheet(isPresented: $settingsShown) {
            SettingsSheet()
        }
    }
}

// MARK: - settings (relocated from Today's header; the chrome owns the gear)

/// Facts and notes only — Settings never writes cells.
struct SettingsSheet: View {
    @EnvironmentObject var box: BoxModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(LivTheme.text)
                .padding(.bottom, 4)
            SectionLabel("Box")
            Text(box.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(LivTheme.text2)
                .textSelection(.enabled)
            Text("\(box.snap?.entities?.count ?? 0) entities")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(LivTheme.text3)
            SectionLabel("Assist")
                .padding(.top, 10)
            Text(
                "Assist is proposals-only and lands with the Inbox Tidy lens (M2). Amber marks its presence; nothing writes without an accept."
            )
            .font(.system(size: 12))
            .foregroundStyle(LivTheme.text2)
            SectionLabel("Handoff")
                .padding(.top, 10)
            Text(
                "Captures stay in this phone's own box for now. The desk funnel — write-once batches the Mac drains at open — arrives with M2."
            )
            .font(.system(size: 12))
            .foregroundStyle(LivTheme.text2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(LivTheme.surface)
    }
}

// MARK: - bottom bar

/// The Obsidian nav row under Liv law: the features menu button far left
/// (always present — it summons the grid; a chosen feature covers the
/// whole chrome), then ‹ › search + [tab count], always there. One 46pt
/// hairline pill on ultra-thin material + the features circle beside it.
struct BottomBar: View {
    @EnvironmentObject var desk: DeskModel
    /// The proposal count — the app's one in-app badge (amber). 0 until
    /// assist lands (M2).
    var inboxBadge: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            featuresButton
            HStack(spacing: 0) {
                navButton("chevron.left", enabled: desk.canGoBack, label: "Back") {
                    desk.goBack()
                }
                navButton("chevron.right", enabled: desk.canGoForward, label: "Forward") {
                    desk.goForward()
                }
                navButton("magnifyingglass", enabled: true, label: "Search") {
                    desk.searchShown = true
                }
                navButton("plus", enabled: true, label: "New tab") {
                    desk.newTab()
                }
                tabCountButton
            }
            .padding(.horizontal, 4)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        }
        .padding(.horizontal, 16)
    }

    /// The `^` of the sketch: always far left, badge-carrying (the inbox
    /// proposal count surfaces here since Inbox lives behind this menu).
    private var featuresButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { desk.gridShown.toggle() }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .rotationEffect(.degrees(desk.gridShown ? 180 : 0))
                .foregroundStyle(desk.gridShown ? LivTheme.accent : LivTheme.text2)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(
                    desk.gridShown ? LivTheme.accent : LivTheme.border,
                    lineWidth: desk.gridShown ? 1 : 0.5))
                .overlay(alignment: .topTrailing) {
                    if inboxBadge > 0 { badge }
                }
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Features")
    }

    private var badge: some View {
        Text(inboxBadge > 99 ? "99+" : "\(inboxBadge)")
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .foregroundStyle(chromeAmberInk)
            .padding(.horizontal, 3.5)
            .frame(minWidth: 13, minHeight: 13)
            .background(Capsule().fill(LivTheme.amber))
            .offset(x: 2, y: -2)
    }

    private func navButton(
        _ icon: String, enabled: Bool, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(enabled ? LivTheme.text2 : LivTheme.muted.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// The Obsidian tab square: the open-tab count inside its own outline.
    private var tabCountButton: some View {
        Button {
            desk.switcherShown = true
        } label: {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(LivTheme.text2, lineWidth: 1.5)
                .frame(width: 20, height: 20)
                .overlay(
                    Text(desk.tabs.count > 99 ? "99" : "\(desk.tabs.count)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(LivTheme.text2)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tabs")
    }
}

// MARK: - feature grid

/// The `^` overflow card (ClickUp's "More") — the consumer floats it just
/// above the bar while gridShown. Tap swaps the body or fires the verb,
/// then closes. A later pass lets this grid re-pin the two bar features.
struct FeatureGrid: View {
    @EnvironmentObject var desk: DeskModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Feature.allCases) { f in
                cell(f.title, f.icon, on: desk.featureShown == f) {
                    desk.featureShown = f
                }
            }
            cell("Capture", "square.and.pencil", on: false) {
                desk.newTab()
            }
            cell("Camera", "camera", on: false) {
                desk.cameraShown = true
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(LivTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LivTheme.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, 16)
    }

    private func cell(
        _ label: String, _ icon: String, on: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { desk.gridShown = false }
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(on ? LivTheme.accent : LivTheme.text2)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(on ? LivTheme.accentSoft : LivTheme.panel)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
