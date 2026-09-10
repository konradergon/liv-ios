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
        // WHAT A KEYSTROKE COSTS, and whether it grows with the note
        // (EditorCost.swift), same door: `-editor-cost.selfcheck 1`. The
        // only cost test in the shell; the Rust ones all scale the
        // NUMBER of notes, never the LENGTH of one.
        if UserDefaults.standard.bool(forKey: "editor-cost.selfcheck") {
            let failures = livEditorCostSelfCheck()
            print("EDITCOST-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("EDITCOST-SELFCHECK \($0)") }
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
        // The inactive-tab rule (Tabs.swift), same door:
        // `-tabs.selfcheck 1`. Restored with the tabs on 2026-08-22.
        if UserDefaults.standard.bool(forKey: "tabs.selfcheck") {
            let failures = livTabsSelfCheck()
            print("TABS-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("TABS-SELFCHECK \($0)") }
        }
        // One plane per view (Positions.swift), same door:
        // `-planes.selfcheck 1`. Added with phase 4 of design/tabs.md.
        if UserDefaults.standard.bool(forKey: "planes.selfcheck") {
            let failures = livPlanesSelfCheck()
            print("PLANES-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("PLANES-SELFCHECK \($0)") }
        }
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
        // The `liv://` parser, every shape, no desk: `-routes.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "routes.selfcheck") {
            let failures = livRoutesSelfCheck()
            print("ROUTES-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("ROUTES-SELFCHECK \($0)") }
        }
        // door: `simctl launch … -editor.selfcheck 1`.
        if UserDefaults.standard.bool(forKey: "editor.selfcheck") {
            let failures = livEditorSelfCheck()
            print("ED-SELFCHECK \(failures.isEmpty ? "PASS" : "FAIL \(failures.count)")")
            failures.forEach { print("ED-SELFCHECK \($0)") }
        }
    }

    var body: some Scene {
        WindowGroup {
            // THE GLYPH SHEET, before the app. Mockup-first is the
            // house rule for visible UI and a drawing cannot be reviewed
            // in prose: `-glyph.sheet 1` shows the set and nothing else.
            if UserDefaults.standard.bool(forKey: "glyph.sheet") {
                GlyphSheet()
            } else {
                RootView()
                    .environmentObject(box)
                    .environmentObject(desk)
                    .environmentObject(outbox)
                    .environmentObject(workspaces)
                    // THE CARET IS OURS TOO. There was no tint on the
                    // root until 2026-09-07, so every text caret,
                    // selection highlight and drag handle in the app
                    // came out the device's blue — the most-touched
                    // pixel in a writing app, in the one colour that
                    // changes underneath us when the phone's owner picks
                    // a different system tint. That is the whole reason
                    // `Theme.swift` gives for having an accent at all.
                    //
                    // OUTERMOST, so it also wraps the presentations
                    // RootView itself puts up.
                    .tint(LivTheme.accent)
            }
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
    @State private var bootApplied = false
    /// One spool drain at a time: `.onAppear` and the first `.active`
    /// can both fire at launch, and two drains over one folder would
    /// catch every file twice.
    @State private var draining = false
    /// The furnishing pass runs once per launch, on the FIRST decoded
    /// snapshot. Cross-launch idempotence is Furnish's presence guards,
    /// never this flag (it only stops re-entry from the refreshes the
    /// pass itself triggers).
    @State private var furnished = false

    var body: some View {
        // ONE CHILD, and that is the point of it (2026-09-08).
        //
        // This ZStack also held the bottom bar and the minimised-record
        // pill, painted after the body — so the bar floated over the
        // whole app rather than belonging to the view under it, and
        // every cover that had to appear above the bar had to be lifted
        // out of its own surface and re-hosted up here beside it. The
        // menu was, the record card was, the properties sheet is a
        // system sheet and got it free; the workspace card was not, and
        // came up underneath the bar (owner: "when opening workspaces
        // from the panel, the bar is above that card").
        //
        // The bar is the surface's own foot now — see `surfaceFoot` in
        // DeskHost — so a cover drawn over the surface is over its bar
        // without anybody arranging it.
        //
        // No persistent top bar (owner, 2026-07-31): the note takes the
        // screen; Workspace and Settings live behind the desk's floating
        // ••• (DeskHost). The body is the desk, edge to edge.
        bodyView
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LivTheme.canvas.ignoresSafeArea())
        // The one menu is hosted HERE rather than in DeskHost so it
        // covers the desk whole — its bar included, now that the bar is
        // part of the desk. The card hosts its own when a card is the
        // surface in front.
        .livMenu($desk.menu, active: desk.recordCard == nil)
        // Only when nothing covers the desk — see RecordCardHost. The
        // same question the window's panel drag asks, so it is asked in
        // one place (standing rule 4).
        .recordCardHost(active: desk.deskInFront)
        // PROPERTIES ARE A CARD (owner, 2026-08-29: "maybe card
        // everywhere. start with one").
        //
        // They were a panel on the trailing edge, mirrored off the
        // library's — which was right while the desktop's own metadata
        // lived in a right rail. That reference is dropped: it is very
        // early, and the end goal is one mobile and one desktop app
        // mirroring each other rather than this one chasing that one.
        //
        // Anytype for iOS, doing the same job at the same size, opens
        // properties as a sheet from the bottom with a grabber, reached
        // from the object's ••• menu. So does a record's card here
        // already, which is the second half of the point: the app had
        // two containers for one idea.
        .sheet(
            isPresented: Binding(
                get: { desk.inspectorShown && desk.openDoc != nil },
                set: { if !$0 { desk.inspectorShown = false } })
        ) {
            if let id = desk.openDoc {
                EntityInspector(id: id)
                    .livOverlay(LivOverlay.properties)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(LivTheme.surface)
                    .environmentObject(box)
                    .environmentObject(desk)
                    .environmentObject(workspaces)
            }
        }
        // HISTORY IS A CARD, hosted exactly as the properties card is:
        // the same detents, the same grabber, the same ground, gated on
        // the same open document. One container for one idea.
        .sheet(
            isPresented: Binding(
                get: { desk.historyShown && desk.openDoc != nil },
                set: { if !$0 { desk.historyShown = false } })
        ) {
            if let id = desk.openDoc {
                HistoryCard(id: id)
                    .livOverlay(LivOverlay.history)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(LivTheme.surface)
                    .environmentObject(box)
                    .environmentObject(desk)
            }
        }
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
            desk.knows = { [weak box] id in box?.entity(id) != nil }
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
        // The switcher takes the whole screen (owner, 2026-07-29) — top
        // bar and bottom bar both covered. Its own footer carries Done.
        .fullScreenCover(isPresented: $desk.switcherShown) {
            TabSwitcher()
                .environmentObject(box)
                .environmentObject(desk)
                .livOverlay(LivOverlay.tabs)
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
        .sheet(isPresented: $desk.trashShown) {
            TrashView()
                .environmentObject(box)
                .livOverlay(LivOverlay.trash)
                // THE WAY OUT. The trash lost its `Done` button with its
                // nav bar on 2026-09-07, and a sheet's grabber is NOT
                // visible by default — without this the screen has no
                // dismissal affordance at all. Every other themed sheet
                // in the app already asks for it.
                .presentationDragIndicator(.visible)
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
                drainSpool()
            } else if phase == .background {
                Outbox.shared.closeBatch(snapshot: box.snap)
            }
        }
        // THE `liv://` DOOR. Warm and cold launch both, for a
        // single-scene app; no UIApplicationDelegate needed.
        .onOpenURL { Routes.shared.handle($0) }
        .onAppear {
            bindOutboxTitles()
            // A cold launch may never report a phase CHANGE to .active,
            // so the spool is read here as well; `draining` keeps the
            // two from overlapping.
            drainSpool()
            // A tapped notification lands as a desk tab (design/ios.md §3);
            // Notify parks a cold-launch tap until this wiring exists.
            Notify.shared.onOpen = { [weak desk] id in
                desk?.open(id)
            }
            // A link from another app lands wherever it names. Assigning
            // this flushes anything that arrived during the launch —
            // `desk.newNote` is nil until DeskHost appears, so a cold
            // `liv://capture` would otherwise be swallowed.
            Routes.shared.apply = { [weak desk, weak box] route in
                guard let desk else { return }
                switch route {
                case .capture(let payload):
                    if let payload {
                        desk.catchText?(payload)
                    } else {
                        desk.newNote?()
                    }
                case .capturePhoto: desk.cameraShown = true
                // A link that NAMES a view lands on that view, by the
                // same rule the panel's rows follow (2026-09-09):
                // `liv://notes` means the list, not whatever note the
                // desk happens to hold.
                case .view(let feature, let at): desk.go(feature, at: at)
                case .entity(let id):
                    // ASK THE BOX BEFORE SAYING IT IS GONE. A link can
                    // name something written since the last snapshot —
                    // by the CLI, by an import, by anything that is not
                    // this app — and the document body draws "This was
                    // deleted." for an id the snapshot has not caught up
                    // with yet. Seen twice on 2026-09-06 while measuring
                    // with CLI-written notes. The body re-renders when
                    // the snapshot lands, so one refresh is the whole
                    // fix.
                    if box?.live(id) == nil { box?.refresh() }
                    desk.open(id)
                }
            }
        }
        .onReceive(box.$snap) { snap in
            // Rebind on every snapshot: assigning the resolver republishes the
            // ledger, and at .onAppear there is no snapshot to resolve against
            // yet (titles would freeze as "#id"). Rebinding also keeps entry
            // titles current when an entity is renamed after capture.
            bindOutboxTitles()
            workspaces.apply(snap)
            // The lens is answered by the core, so it has to be re-asked
            // whenever the box moves — a note created a moment ago must
            // enter a filtered view, and only the box knows if it belongs.
            workspaces.refreshLens(box)
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
            workspaces.refreshLens(box)
        }
        // A saved filter is the other half of the lens, and it changes
        // without the workspace changing.
        .onChange(of: workspaces.activeFilterId) { _, _ in
            workspaces.refreshLens(box)
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

    /// A CATCH THE SHARE SHEET LEFT (2026-09-09). The extension writes
    /// a file into the App Group spool and goes (Catch.swift says why it
    /// does not write the box itself); this turns each file into a
    /// capture, oldest first, through the same `liv_capture_at` the
    /// `liv://` door uses, and stamps it into the workspace the way that
    /// door does. NOT focused or opened: a share is fire-and-forget, and
    /// landing in a note you shared an hour ago when the app comes to the
    /// front would be the wrong surprise. It is in the Inbox, where an
    /// unrouted capture waits.
    ///
    /// The file is removed only once the box answered with an id, so a
    /// refused catch (a busy box) waits for the next foreground rather
    /// than being lost. The other way round — the app dying between the
    /// write and the removal — catches it twice, which is the better of
    /// the two mistakes.
    private func drainSpool() {
        guard !draining else { return }
        let waiting = Spool.pending()
        guard !waiting.isEmpty else { return }
        draining = true
        func next(_ i: Int) {
            guard i < waiting.count else {
                draining = false
                return
            }
            let item = waiting[i]
            box.capture(item.text) { id in
                if id != 0 {
                    item.done()
                    workspaces.stamp(id, in: box)
                }
                next(i + 1)
            }
        }
        next(0)
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
        case "switcher": desk.switcherShown = true
        case "inactive":
            desk.backdateTabsForRehearsal(days: LivTabs.defaultDays + 1)
            desk.switcherShown = true
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
        // THE LIST OF NOTES. It was a view of its own until 2026-09-10;
        // it is a lens in Everything now, and the flag keeps its name
        // because a rehearsal flag is a name for a SCREEN, and this is
        // still that screen.
        case "notes", "docs": desk.go(.everything, at: EverythingLens.notes.rawValue)
        default: break
        }
    }

    /// The body IS the desk — features and the tab view are windows over
    /// it, never a mode.
    private var bodyView: some View {
        DeskHost()
    }
}


