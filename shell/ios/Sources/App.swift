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
        // Where you are and how you got there (Navigate.swift), same
        // door: `-places.selfcheck 1`. It replaces the tab plane's
        // suite, which went with the tabs (2026-08-18).
        if UserDefaults.standard.bool(forKey: "places.selfcheck") {
            let failures = livPlacesSelfCheck()
            print("PLACES-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("PLACES-SELFCHECK \($0)") }
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
            // It does NOT retire for an EMPTY desk: the bar is the only
            // way out of one, and its `+` is what the empty desk's hint
            // points at. The pill follows the bar, since it is
            // positioned against it.
            if let id = desk.minimisedRecord, !keyboard.up {
                MinimisedRecordPill(id: id)
                    .padding(.bottom, 62)
                    // The pill belongs to the desk, so it travels with
                    // it into the wings; under the properties curtain,
                    // which it is painted above, it fades instead.
                    .offset(x: desk.deskShift)
                    .opacity(1 - desk.curtain)
                    .accessibilityHidden(desk.deskShift != 0 || desk.curtain > 0)
                    .zIndex(2)
            }
            if !keyboard.up && desk.menu == nil {
                BottomBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    // The bar does NOT travel with the surface: it is
                    // four GLOBAL actions (owner, 2026-08-17), so it
                    // stays exactly where it is while the world moves
                    // under it — Safari's bar over a page that scrolls
                    // away. Under the properties curtain, which it is
                    // painted above, it fades.
                    .opacity(1 - desk.curtain)
                    .accessibilityHidden(desk.curtain > 0)
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
        .onAppear {
            (LivAppearance(rawValue: appearance) ?? .dark).applyToWindows()
            // The tab plane learns what an id IS (Option C). Reading the
            // live snapshot each time means the answer is never stale —
            // deciding once at open() would race the refresh that follows
            // a creation (Box.actId calls back before the snapshot moves).
            desk.shapeOf = { [weak box] id in TabShape.of(box?.entity(id)) }
        }
        // A saved document from before Option C may BE a task. The first
        // snapshot is the first moment we can tell; a record belongs in a
        // card, so the desk falls back to the list (owner, 2026-08-08,
        // carried over to one open document).
        .onReceive(box.$snap.compactMap { $0 }.prefix(1)) { _ in
            desk.dropRecordDocument()
        }
        .onChange(of: appearance) { _, fresh in
            (LivAppearance(rawValue: fresh) ?? .dark).applyToWindows()
        }
        // The tab view takes the whole screen too (owner, 2026-07-29) — top
        // bar and bottom bar both covered. Its own footer carries Done.
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
                    .padding(.top, LivRow.topInset)
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
        case "grid", "library": desk.setLibrary(true)
        case "search": desk.searchShown = true
        case "today": desk.go(.today)
        case "tasks": desk.go(.tasks)
        case "inbox": desk.go(.inbox)
        case "calendar": desk.go(.calendar)
        case "everything": desk.go(.everything)
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
        // The create menu, from the bar's `+`.
        case "newtab", "create": desk.createSomething()
        // The Docs LIST, which is the state's root.
        case "docs": desk.showList()
        default: break
        }
    }

    /// The body IS the desk — features and the tab view are windows over
    /// it, never a mode.
    private var bodyView: some View {
        DeskHost()
    }
}


