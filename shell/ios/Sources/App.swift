// Liv iOS — the capture satellite (design/ios.md, M1).
// Two-mode chrome (owner sketch 2026-07-22): Feature view = the rail,
// Desk view = the center pane with content tabs. One consistent bottom
// bar: mode toggle far left, global search far right.

import SwiftUI
import UserNotifications

@main
struct LivApp: App {
    @StateObject private var box = BoxModel(path: BoxPath.resolve())
    @StateObject private var desk = DeskModel()
    @StateObject private var outbox = Outbox.shared
    @StateObject private var workspaces = WorkspaceModel()

    init() {
        // The delegate must exist before launch finishes, or a cold-start
        // notification tap is dropped by the system (M5, Notify.swift).
        UNUserNotificationCenter.current().delegate = Notify.shared
        // The span codec has no test target to live in (no Xcode project);
        // `simctl launch … -spans.selfcheck 1` runs its round-trips and
        // prints the failures. Silent = pass.
        if UserDefaults.standard.bool(forKey: "spans.selfcheck") {
            let failures = livSpanCodecSelfCheck()
            print("SPAN-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("SPAN-SELFCHECK \($0)") }
        }
        // The workspace query grammar, same door:
        // `simctl launch … -workspace.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "workspace.selfcheck") {
            let failures = livWorkspaceSelfCheck()
            print("WS-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("WS-SELFCHECK \($0)") }
        }
        // The markdown scan + edit operations (EditorStyle.swift), same
        // door: `simctl launch … -editor.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "editor.selfcheck") {
            let failures = livEditorSelfCheck()
            print("ED-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("ED-SELFCHECK \($0)") }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(box)
                .environmentObject(desk)
                .environmentObject(outbox)
                .environmentObject(workspaces)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var bootApplied = false
    /// The furnishing pass runs once per launch, on the FIRST decoded
    /// snapshot. Cross-launch idempotence is Furnish's presence guards,
    /// never this flag (it only stops re-entry from the refreshes the
    /// pass itself triggers).
    @State private var furnished = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TopBar()
                bodyView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // While the menu is up, a tap anywhere here only dismisses it
            // (the catcher below). Assistive tech has to be told separately:
            // occlusion hides a view from eyes and from touch, never from
            // VoiceOver, so without this a swipe walks onto controls the
            // panel covers and activating them really fires.
            .accessibilityHidden(desk.gridShown)

            BottomBar()
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .accessibilityHidden(desk.gridShown)

            // The features menu is drawn AFTER the bar, so it covers the
            // bar it was summoned from (owner, 2026-07-29). Its own `v`
            // button lands where the `^` was.
            if desk.gridShown {
                // An invisible tap-away catcher, not a dimming scrim.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) {
                            desk.gridShown = false
                        }
                    }
                FeatureGrid()
                    .transition(.move(edge: .bottom))
            }
        }
        .background(LivTheme.canvas.ignoresSafeArea())
        .fullScreenCover(item: $desk.featureShown) { feature in
            FeatureWindow(feature: feature)
                .environmentObject(box)
                .environmentObject(desk)
                .environmentObject(workspaces)
        }
        // The tab view takes the whole screen too (owner, 2026-07-29) — top
        // bar and bottom bar both covered. Its own footer carries Done.
        .fullScreenCover(isPresented: $desk.switcherShown) {
            TabSwitcher()
                .environmentObject(box)
                .environmentObject(desk)
        }
        .fullScreenCover(isPresented: $desk.searchShown) {
            SearchView()
                .environmentObject(box)
                .environmentObject(desk)
                .environmentObject(workspaces)
        }
        .fullScreenCover(isPresented: $desk.cameraShown) {
            CameraFlow(onDone: { ids in
                if let last = ids.last { desk.open(last) }
            })
            .environmentObject(box)
            .environmentObject(desk)
            .environmentObject(workspaces)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                box.refresh()
                Outbox.shared.scanAcks()
            } else if phase == .background {
                Outbox.shared.closeBatch(snapshot: box.snap)
            }
        }
        .onAppear {
            bindOutboxTitles()
            // A tapped notification lands as a desk tab (design/ios.md §3);
            // Notify parks a cold-launch tap until this wiring exists.
            Notify.shared.onOpen = { [weak desk] id in desk?.open(id) }
        }
        .onReceive(box.$snap) { snap in
            // Rebind on every snapshot: assigning the resolver republishes the
            // ledger, and at .onAppear there is no snapshot to resolve against
            // yet (titles would freeze as "#id"). Rebinding also keeps entry
            // titles current when an entity is renamed after capture.
            bindOutboxTitles()
            workspaces.apply(snap)
            // Every decoded snapshot rebuilds the notification schedule —
            // the queue is a projection of the box, never patched (M5).
            Notify.shared.rebuild(snapshot: snap, box: box)
            guard let snap else { return }
            if !furnished {
                furnished = true
                Furnish.run(snap, box: box)
            }
            guard !bootApplied else { return }
            bootApplied = true
            applyBootState(snap)
        }
        // One tab plane, swapped per workspace — the desk saves the set it
        // is leaving and restores the one it is joining.
        .onChange(of: workspaces.activeId) { _, id in
            desk.adopt(workspace: id)
        }
        .overlay(alignment: .top) {
            if let fault = box.boxFault {
                Text(fault)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LivTheme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(LivTheme.red, in: Capsule())
                    .padding(.top, 4)
            }
        }
    }

    /// The outbox resolves ledger titles through the live box. A scrap
    /// carries no name cell (capture writes content only), so fall back to
    /// its first content line — the display name the rest of the shell shows.
    private func bindOutboxTitles() {
        Outbox.shared.titleResolver = { [weak box] id in
            guard let row = box?.entity(id) else { return nil }
            // Markers off for display (livDisplayTitle) — ledger rows and
            // scrap titles must not read "# Trip planning".
            if let name = row.title, !name.isEmpty {
                let clean = livDisplayTitle(name)
                return clean.isEmpty ? name : clean
            }
            let first = row.cells?.first { $0.property == "content" }?.value?
                .split(separator: "\n").first.map(String.init)
            guard let first else { return nil }
            let clean = livDisplayTitle(first)
            return clean.isEmpty ? first : clean
        }
    }

    /// Rehearsal hook (headless screenshots, the LIV_BOX_PATH spirit):
    /// `simctl launch … app.liv.ios -desk.boot <state>` where state is one of
    /// grid | tasks | inbox | desk | newtab | switcher. Launch args of the
    /// form `-key value` land in UserDefaults automatically.
    private func applyBootState(_ snap: Snapshot) {
        guard let state = UserDefaults.standard.string(forKey: "desk.boot") else { return }
        // Front-of-house entities only — `everything` is the curated list.
        let newest = (snap.everything ?? [])
            .compactMap { box.entity($0) }
            .filter { !($0.trashed ?? false) && !($0.title ?? "").isEmpty }
            .sorted { $0.id > $1.id }
            .map(\.id)
        switch state {
        case "grid": desk.gridShown = true
        case "search": desk.searchShown = true
        case "today": desk.featureShown = .today
        case "tasks": desk.featureShown = .tasks
        case "inbox": desk.featureShown = .inbox
        case "desk": if let id = newest.first { desk.open(id) }
        case "newtab": desk.newTab()
        case "switcher":
            for id in newest.prefix(3).reversed() { desk.open(id) }
            desk.switcherShown = true
        default: break
        }
    }

    /// The body IS the desk — features and the tab view are windows over
    /// it, never a mode.
    private var bodyView: some View {
        DeskHost()
    }
}

/// A feature summoned from the menu: it takes the ENTIRE screen (owner,
/// 2026-07-29) — no sheet inset, no strip of desk showing above it, nothing
/// reading through. Dismissed by the `v` in its header, by dragging that
/// header down, or by opening a row as a desk tab.
struct FeatureWindow: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    let feature: Feature

    var body: some View {
        VStack(spacing: 0) {
            header
            // Feature bodies carry their own headers — the window adds
            // only the one control that puts it away.
            Group {
                switch feature {
                case .today: TodayView()
                case .everything: EverythingView()
                case .inbox: InboxView()
                case .tasks: TasksView()
                case .calendar: CalendarView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LivTheme.canvas.ignoresSafeArea())
    }

    /// Same 40pt band as TopBar, in the same place, so the screen swaps
    /// under a header that does not move. The drag keeps the swipe-down
    /// muscle memory a sheet used to give for free.
    ///
    /// The WHOLE band closes the window, not just the 32pt glyph. SwiftUI
    /// merges this HStack into one accessibility element spanning the full
    /// width and labelled "Close <feature>", and its activation point is
    /// the band's centre — so with only the glyph wired up, Voice Control,
    /// Switch Control and UI tests aimed at the middle of the band and
    /// nothing happened. A full-screen window with no bar and no grabber
    /// has no other way out, so the band must mean what it advertises.
    private var header: some View {
        HStack(spacing: 0) {
            Button { desk.featureShown = nil } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(feature.title)")
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { desk.featureShown = nil }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { g in
                    if g.translation.height > 40 { desk.featureShown = nil }
                }
        )
    }
}
