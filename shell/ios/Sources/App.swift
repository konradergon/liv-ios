// Liv iOS — the capture satellite (design/ios.md, M1).
// Two-mode chrome (owner sketch 2026-07-22): Feature view = the rail,
// Desk view = the center pane with content tabs. One consistent bottom
// bar: mode toggle far left, global search far right.

import SwiftUI

@main
struct LivApp: App {
    @StateObject private var box = BoxModel(path: BoxPath.resolve())
    @StateObject private var desk = DeskModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(box)
                .environmentObject(desk)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var bootApplied = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TopBar()
                bodyView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Room for the floating bar; the body scrolls under it.
            .padding(.bottom, 0)

            if desk.gridShown {
                // Tap-away scrim under the feature grid.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { desk.gridShown = false }
                FeatureGrid()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 76)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            BottomBar()
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
        .background(LivTheme.canvas.ignoresSafeArea())
        .sheet(item: $desk.featureShown) { feature in
            FeatureWindow(feature: feature)
                .environmentObject(box)
                .environmentObject(desk)
        }
        .fullScreenCover(isPresented: $desk.searchShown) {
            SearchView()
                .environmentObject(box)
                .environmentObject(desk)
        }
        .fullScreenCover(isPresented: $desk.cameraShown) {
            CameraFlow(onDone: { ids in
                if let last = ids.last { desk.open(last) }
            })
            .environmentObject(box)
            .environmentObject(desk)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { box.refresh() }
        }
        .onReceive(box.$snap) { snap in
            guard !bootApplied, let snap else { return }
            bootApplied = true
            applyBootState(snap)
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

    /// The body IS the desk — features are windows over it, never a mode.
    @ViewBuilder private var bodyView: some View {
        if desk.switcherShown {
            TabSwitcher()
        } else {
            DeskHost()
        }
    }
}

/// A feature summoned from the menu: a window over the whole chrome
/// (bar included), dismissed by swipe or by opening a row as a desk tab.
struct FeatureWindow: View {
    @EnvironmentObject var box: BoxModel
    let feature: Feature

    var body: some View {
        // Feature bodies carry their own headers — the window adds only
        // the sheet chrome (grabber, canvas, large detent).
        Group {
            switch feature {
            case .today: TodayView()
            case .inbox: InboxView()
            case .tasks: TasksView()
            case .calendar: EmptyHint("Calendar arrives with M3.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 10)
        .background(LivTheme.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
