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
        // The palette's contrast floor (Glyph.swift), same door:
        // `-palette.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "palette.selfcheck") {
            let failures = livPaletteSelfCheck()
            print("PALETTE-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("PALETTE-SELFCHECK \($0)") }
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

/// THE FLOOR: one of the four, always under you (2026-08-16).
private struct FloorLayer: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        Group {
            switch desk.floor {
            case .today: TodayView()
            case .calendar: CalendarView()
            case .tasks: TasksView()
            case .find: SearchView(isFloor: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Below the band the workspace name owns, above the bar it
        // stands on: the floor is the ground BETWEEN the two pieces of
        // chrome, never under them.
        .padding(.top, LivRow.topChrome)
        .accessibilityHidden(desk.standingOnOpen)
    }
}

/// What you have OPEN, lying over the floor. Only ever drawn with
/// something to draw — closing the last thing puts you back on the
/// floor rather than on an empty desk.
private struct OpenLayer: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        if desk.standingOnOpen, desk.activeTab != nil {
            DeskHost()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
    }
}

/// The workspace, top CENTRE, over floor and desk alike: the one thing
/// on screen that says what you are looking at, and every floor wears
/// it.
private struct WorkspaceLayer: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceButton { desk.workspaceShown = true }
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .opacity(1 - desk.curtain)
    }
}

/// The ONE create key, on every surface (owner, 2026-08-16). What it
/// makes and what it inherits is RootView's `createMenu`.
private struct CreateKeyLayer: View {
    @EnvironmentObject var desk: DeskModel
    @ObservedObject var keyboard = KeyboardWatch.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                LivAddButton(label: "New") { desk.createHere() }
            }
        }
        .padding(.bottom, LivRow.barHeight + LivSafeArea.bottom)
        .opacity(hidden ? 0 : 1 - desk.curtain)
        .allowsHitTesting(!hidden)
    }

    private var hidden: Bool {
        keyboard.up || desk.recordCard != nil || desk.menu != nil
    }
}

/// The floor bar, retiring under a keyboard and under a menu.
private struct BarLayer: View {
    @EnvironmentObject var desk: DeskModel
    @ObservedObject var keyboard = KeyboardWatch.shared

    var body: some View {
        if !keyboard.up && desk.menu == nil {
            FloorBar()
                .opacity(1 - desk.curtain)
                .accessibilityHidden(desk.curtain > 0)
                .transition(.move(edge: .bottom))
        }
    }
}

/// The one menu's host, as a VIEW. It observes the model itself, so a
/// menu raised from anywhere is drawn even when the root around it does
/// not rebuild.
private struct MenuLayer: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        Color.clear
            .allowsHitTesting(desk.menu != nil)
            .livMenu($desk.menu, active: desk.recordCard == nil)
    }
}

struct RootView: View {
    /// Dark, light, or follow the system (Settings → Appearance).
    @AppStorage(LivAppearance.key) private var appearance = LivAppearance.dark.rawValue

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
    /// The file picker, opened by the create key's File row.
    @State private var picking = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Each layer is its OWN view, observing the model itself.
            // As modifiers and branches on the root they missed the
            // changes that raise a menu or stand you on a note — the
            // root is rebuilt rarely, and a layer that only the root
            // reads is a layer that does not move (found on the
            // simulator, 2026-08-16).
            FloorLayer()
            OpenLayer()
                .zIndex(1)
            WorkspaceLayer()
                .zIndex(3)
            CreateKeyLayer()
                .zIndex(2)
            MenuLayer()
                .zIndex(4)
            BarLayer()
                .zIndex(2)
        }
        .background(LivTheme.canvas.ignoresSafeArea())
        // The one menu is hosted HERE, above the bottom bar — the bar is
        // drawn after the desk, so a menu hosted inside DeskHost came up
        // underneath it and lost its last row. The card hosts its own
        // when a card is the surface in front.
        // Only when nothing covers the desk — see RecordCardHost. The
        // same question the window's panel drag asks, so it is asked in
        // one place (standing rule 4).
        .recordCardHost(active: desk.deskInFront)
        // Set on the WINDOW, not with preferredColorScheme. A sheet is a
        // separate presentation with its own root, so it never inherited
        // the scheme: flipping the appearance FROM Settings changed the
        // whole app except the Settings sheet you were standing in, until
        // you closed it (owner, 2026-08-08). The window override reaches
        // every presentation there is.
        .fileImporter(
            isPresented: $picking, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            FileImport.adopt(urls, box: box, workspaces: workspaces, desk: desk)
        }
        .onAppear {
            desk.newTabMenu = createMenu
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
        // The tab view takes the whole screen too (owner, 2026-07-29) — top
        // bar and bottom bar both covered. Its own footer carries Done.
        .fullScreenCover(isPresented: $desk.switcherShown) {
            TabSwitcher()
                .environmentObject(box)
                .environmentObject(desk)
        }
        // The inbox is not a floor — it is where the day's catches wait,
        // reached from Today's own line about them.
        .fullScreenCover(isPresented: $desk.inboxShown) {
            InboxView()
                .environmentObject(box)
                .environmentObject(desk)
                .environmentObject(workspaces)
                .recordCardHost(active: true)
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
        // Below the doors' band, like every other thing that speaks:
        // centred at the very top it printed itself over the workspace
        // name (owner, 2026-08-15).
        .overlay(alignment: .top) {
            if let fault = box.boxFault {
                Text(fault)
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(LivTheme.red, in: Capsule())
                    .padding(.top, LivRow.topChrome)
            }
        }
    }

    /// The four floors. Each is built fresh when you stand on it and
    /// remembers where it was through FloorMemory — publishing that
    /// state on the model would re-render the world on every drag, which
    /// is the bug the calendar already paid for (design/ios.md rev 24).
    @ViewBuilder private var floorBody: some View {
        switch desk.floor {
        case .today: TodayView()
        case .calendar: CalendarView()
        case .tasks: TasksView()
        case .find: SearchView(isFloor: true)
        }
    }

    /// What the create key makes, and what it inherits from where you
    /// are standing: on Today or the calendar, the day you are looking
    /// at; anywhere else, just the workspace.
    private func createMenu() -> LivMenu {
        LivMenu(
            id: "create",
            from: .bottom,
            title: "New",
            items: [
                LivMenuItem(label: "Note", glyph: .note) { newNote() },
                LivMenuItem(label: "Task", glyph: .task) { newRecord(event: false) },
                LivMenuItem(label: "Event", glyph: .event) { newRecord(event: true) },
                LivMenuItem(label: "File", glyph: .file(.other)) { picking = true },
            ])
    }

    /// A note lands as a TAB, with the caret in it.
    private func newNote() {
        box.createNote { id in
            guard id != 0 else { return }
            workspaces.stamp(id, in: box)
            desk.requestFocus(id)
            desk.open(id)
        }
    }

    /// A task or an event lands as a CARD, with the caret in its name —
    /// the app's one create rule (owner, 2026-08-13). Both inherit the
    /// day you are standing on.
    private func newRecord(event: Bool) {
        let day = FloorMemory.shared.day
        let stamp = Civil.stamp(day: day, hhmm: Int64(LivDue.defaultHHMM))
        let landed: (UInt64) -> Void = { id in
            guard id != 0 else { return }
            workspaces.stamp(id, in: box)
            desk.requestFocus(id)
            desk.open(id, as: .record)
        }
        if event {
            box.createEvent(dueCivil: stamp, dateOnly: false, done: landed)
        } else {
            box.createTask { id in
                guard id != 0 else { return }
                box.setSpan(id, "due", start: stamp, end: 0, dateOnly: false)
                landed(id)
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
        case "search", "find", "everything": desk.stand(on: .find)
        case "today": desk.stand(on: .today)
        case "tasks": desk.stand(on: .tasks)
        case "calendar": desk.stand(on: .calendar)
        case "inbox": desk.inboxShown = true
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
        // The create menu, from the key at the bottom right.
        case "newtab": desk.createHere()
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
}

