// Liv iOS (design/ios.md, M1).
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
        // Template resolution, same door: `-template.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "template.selfcheck") {
            let failures = livTemplateSelfCheck()
            print("TPL-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("TPL-SELFCHECK \($0)") }
        }
        // The day grid's clock arithmetic (Calendar.swift), same door:
        // `-calendar.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "calendar.selfcheck") {
            let failures = livCalendarSelfCheck()
            print("CAL-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("CAL-SELFCHECK \($0)") }
        }
        // Share/Export's markdown + filename shaping, same door:
        // `-share.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "share.selfcheck") {
            let failures = livShareSelfCheck()
            print("SHARE-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("SHARE-SELFCHECK \($0)") }
        }
        // The inactive-tab rule (Tabs.swift), same door:
        // `-tabs.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "tabs.selfcheck") {
            let failures = livTabsSelfCheck()
            print("TABS-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("TABS-SELFCHECK \($0)") }
        }
        // The icon language (Glyph.swift) — one kind per row, one colour
        // per kind, every drawing inside its box: `-glyph.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "glyph.selfcheck") {
            let failures = livGlyphSelfCheck()
            print("GLYPH-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("GLYPH-SELFCHECK \($0)") }
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
    /// Dark, light, or follow the system (Settings → Appearance).
    @AppStorage(LivAppearance.key) private var appearance = LivAppearance.dark.rawValue

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var keyboard = KeyboardWatch()
    @State private var bootApplied = false
    /// The furnishing pass runs once per launch, on the FIRST decoded
    /// snapshot. Cross-launch idempotence is Furnish's presence guards,
    /// never this flag (it only stops re-entry from the refreshes the
    /// pass itself triggers).
    @State private var furnished = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // No persistent top bar (owner, 2026-07-31): the note takes the
            // screen; Workspace and Settings live behind the desk's floating
            // ••• (DeskHost). The body is the desk, edge to edge.
            bodyView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The bar retires while a PANEL is up — RootView draws it
            // after the desk, so left alone it would float over the
            // panel it should be behind. It also retires while a
            // keyboard is up: keyboard avoidance would park it above the
            // editor's formatting row, two bars deep (owner,
            // 2026-08-02).
            //
            // It does NOT retire for the New Tab chooser any more
            // (owner, 2026-08-10). The chooser had a bar when it was the
            // empty desk's body and none when summoned by `+` — the same
            // screen, furnished two ways depending on how you got there.
            // Drawing over the chooser is what we want: the bar is the
            // way back to your tabs. The pill follows the bar, since it
            // is positioned against it.
            if let id = desk.minimisedRecord, !desk.libraryShown, !keyboard.up {
                MinimisedRecordPill(id: id)
                    .padding(.bottom, 62)
                    .zIndex(2)
            }
            if !desk.libraryShown && !desk.inspectorShown && !keyboard.up
                && desk.menu == nil
            {
                BottomBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    // The extra offset carries it past the bottom safe
                    // area; the z keeps the exit above the opaque desk
                    // (audit, 2026-08-01). Both are pure translations.
                    .transition(.move(edge: .bottom).combined(with: .offset(y: 40)))
                    .zIndex(1)
            }
        }
        .background(LivTheme.canvas.ignoresSafeArea())
        // The one menu is hosted HERE, above the bottom bar — the bar is
        // drawn after the desk, so a menu hosted inside DeskHost came up
        // underneath it and lost its last row. The card hosts its own
        // when a card is the surface in front.
        .livMenu($desk.menu, active: desk.recordCard == nil)
        // Only when nothing covers the desk — see RecordCardHost.
        .recordCardHost(
            active: desk.featureShown == nil && !desk.searchShown
                && !desk.switcherShown && !desk.cameraShown)
        // Set on the WINDOW, not with preferredColorScheme. A sheet is a
        // separate presentation with its own root, so it never inherited
        // the scheme: flipping the appearance FROM Settings changed the
        // whole app except the Settings sheet you were standing in, until
        // you closed it (owner, 2026-08-08). The window override reaches
        // every presentation there is.
        .onAppear {
            (LivAppearance(rawValue: appearance) ?? .dark).applyToWindows()
            // The tab plane learns what an id IS (Option C). Reading the
            // live snapshot each time means the answer is never stale —
            // deciding once at open() would race the refresh that follows
            // a creation (Box.actId calls back before the snapshot moves).
            desk.shapeOf = { [weak box] id in TabShape.of(box?.entity(id)) }
        }
        // Saved tab sets from before Option C may hold tasks. The first
        // snapshot is the first moment we can tell; after that they are
        // closed quietly (owner, 2026-08-08).
        .onReceive(box.$snap.compactMap { $0 }.prefix(1)) { _ in
            desk.pruneRecordTabs()
        }
        .onChange(of: appearance) { _, fresh in
            (LivAppearance(rawValue: fresh) ?? .dark).applyToWindows()
        }
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
                // Search can open a task too, and it is a cover.
                .recordCardHost(active: true)
                .overlay(alignment: .bottom) {
                    if let id = desk.minimisedRecord {
                        MinimisedRecordPill(id: id).padding(.bottom, 10)
                    }
                }
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
            Notify.shared.onOpen = { [weak desk] id in
                desk?.open(id)
            }
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
            // One hop later: `workspaces.apply` above can change activeId,
            // whose onChange runs desk.adopt() — which clears featureShown
            // and every overlay. Applied inline, a boot state was wiped a
            // frame after it was set (found live, 2026-08-05; it silently
            // broke -desk.boot for every feature view).
            DispatchQueue.main.async { applyBootState(snap) }
        }
        // One tab plane, swapped per workspace — the desk saves the set it
        // is leaving and restores the one it is joining.
        .onChange(of: workspaces.activeId) { _, id in
            desk.adopt(workspace: id)
        }
        .overlay(alignment: .top) {
            if let fault = box.boxFault {
                Text(fault)
                    .font(.system(size: LivType.body, weight: .semibold))
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
            return livRowTitle(row)
        }
    }

    /// Rehearsal hook (headless screenshots, the LIV_BOX_PATH spirit):
    /// `simctl launch … app.liv.ios -desk.boot <state>` where state is one of
    /// library | search | today | tasks | inbox | calendar | everything |
    /// desk | newtab | switcher. Launch args of the
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
        case "grid", "library": desk.libraryShown = true
        case "search": desk.searchShown = true
        case "today": desk.featureShown = .today
        case "tasks": desk.featureShown = .tasks
        case "inbox": desk.featureShown = .inbox
        case "calendar": desk.featureShown = .calendar
        case "everything": desk.featureShown = .everything
        case "desk": if let id = newest.first { desk.open(id) }
        // Open one NAMED entity, for looking at a specific note without
        // driving the whole UI to reach it: `-desk.boot open -desk.open
        // <substring of its title>`.
        case "open":
            let needle = (UserDefaults.standard.string(forKey: "desk.open") ?? "").lowercased()
            if !needle.isEmpty,
                let hit = newest.first(where: {
                    (box.entity($0)?.title ?? "").lowercased().contains(needle)
                })
            {
                desk.open(hit)
            }
        // rev 6: the chooser overlay (or the empty desk's own body).
        case "newtab": desk.newTab()
        case "switcher":
            for id in newest.prefix(3).reversed() { desk.open(id) }
            desk.switcherShown = true
        // Rehearsal for the Inactive list: open a handful of tabs and
        // BACKDATE all but the active one, because nobody can wait three
        // weeks to look at a screen (2026-08-10).
        case "inactive":
            for id in newest.prefix(7).reversed() { desk.open(id) }
            desk.backdateTabsForRehearsal(days: 30)
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
        // A feature window is a full-screen cover, and UIKit allows one
        // presentation per presenter — so the desk behind cannot show
        // the card while this is up. Tapping a task inside Tasks must
        // edit it HERE (owner, 2026-08-08).
        .recordCardHost(active: true)
        .overlay(alignment: .bottom) {
            if let id = desk.minimisedRecord {
                MinimisedRecordPill(id: id).padding(.bottom, 10)
            }
        }
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
                    .font(.system(size: LivType.strong, weight: .semibold))
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
