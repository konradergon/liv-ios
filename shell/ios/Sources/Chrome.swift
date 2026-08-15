// liv iOS — the desk-first chrome (design/ios.md §6, revision 2): the body
// IS the desk (content tabs, the Obsidian idioms); features are transient
// windows summoned from the always-present menu button and presented OVER
// the whole chrome, bar included. The bar copies Obsidian's nav row:
// [features ^] ‹ › search + [tab count]. DeskModel is transient shell
// state — tabs persist per device in UserDefaults, never as cells.

import SwiftUI
import UIKit

// MARK: - features

/// The lens roster. Calendar is a v1 placeholder — its body renders
/// EmptyHint("Calendar arrives with M3.") until M3.
enum Feature: String, CaseIterable, Identifiable {
    case today, everything, inbox, tasks, calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .everything: return "Everything"
        case .inbox: return "Inbox"
        case .tasks: return "Tasks"
        case .calendar: return "Calendar"
        }
    }

    /// The blueprints' own drawing for each place (Glyph.swift).
    var glyph: LivGlyph {
        switch self {
        case .today: return .today
        case .everything: return .everything
        case .inbox: return .inbox
        case .tasks: return .tasks
        case .calendar: return .calendar
        }
    }

    // No per-view hue. The library's rows are bare and colourless
    // (owner, 2026-08-13); a view is a place, and kind colour is for
    // things. The drawing alone tells them apart.
}

// MARK: - desk tabs

struct DeskTab: Identifiable {
    let id: UUID
    var content: DeskTabContent
    /// When this tab was last USED — opened, focused, or stepped back
    /// to. A packed civil stamp, the app's one time vocabulary. Tabs
    /// that go untouched long enough fall out of the grid and into the
    /// Inactive list; nothing about them is lost, they are just not in
    /// the way. No default on purpose: every place that mints a tab has
    /// to say when.
    var lastUsed: Int64
}

/// Tabs hold EDITABLE content and nothing else (rev 6): the one case
/// left after `.new` died — the New Tab screen is an overlay now, never
/// a tab.
enum DeskTabContent: Equatable {
    case entity(UInt64)
}

/// The chrome's one state object. Entity-tab ids + the active index ride
/// UserDefaults ("desk.tabs.v1.<workspace>"); ids missing from the box
/// are dropped LAZILY — the dead tab renders an EmptyHint, never a crash
/// and never an eager sweep against a box that may still be opening.
///
/// M4: ONE tab plane whose open SET is remembered per workspace — never a
/// second tab bar (that was the old app's three-tab-system debt).
/// Switching workspace saves the current set and restores that
/// workspace's. The desk MAY be empty: an empty desk shows a hint
/// pointing at the bar's `+`, which is the only way back to a tab.
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
    /// The library panel (left) is up.
    @Published var libraryShown = false
    @Published var cameraShown = false
    /// The Settings sheet and the WORKSPACE switcher sheet (distinct from
    /// `switcherShown`, the tab view). Model state so open() can dismiss
    /// them — as DeskHost-local @State they outlived a notification tap
    /// and the landing tab hid behind them (audit, 2026-08-04).
    @Published var settingsShown = false
    @Published var workspaceShown = false
    /// The workspace sheet should open with the NEW FILTER form already
    /// composing. Filters are reached from the library panel now; the
    /// form still lives in the sheet, so this is how the panel asks for
    /// it without a second copy of the form (standing rule 4).
    @Published var composeFilter = false
    /// The one menu on screen, or nil (Menu.swift). Every menu in the
    /// app rides this: the `+` that makes things, the note's •••, and
    /// the editor's insert menu.
    @Published var menu: LivMenu?

    /// How to build the create menu. Set by DeskHost, which owns the
    /// verbs — the same shape as `shapeOf` above, and the reason the
    /// model can offer a menu it has no way to build itself.
    var newTabMenu: (() -> LivMenu)?
    /// One panel being dragged: which one, whether the drag OPENS or
    /// CLOSES it, and the finger's travel so far. It lives on the MODEL
    /// rather than in DeskHost because the bottom bar — which belongs to
    /// the desk and travels with it — is drawn by RootView, one level up.
    struct PanelDrag: Equatable {
        enum Which { case library, inspector }
        let which: Which
        let opening: Bool
        var amount: CGFloat = 0

        /// Where the drag started from: 0 for an opening drag, 1 for a
        /// closing one.
        var base: CGFloat { opening ? 0 : 1 }

        /// Finger travel that makes this panel MORE visible. The library
        /// comes from the left, so rightward is toward; the properties
        /// come from the right, so leftward is.
        var toward: CGFloat { which == .library ? amount : -amount }

        /// 0 = fully off screen, 1 = fully in. `width` is the screen.
        func progress(_ width: CGFloat) -> CGFloat {
            guard width > 0 else { return base }
            return min(1, max(0, base + toward / width))
        }

        /// The travel that would land the panel exactly at `target`.
        func amount(for target: CGFloat, width: CGFloat) -> CGFloat {
            let toward = (target - base) * width
            return which == .library ? toward : -toward
        }
    }

    /// Which panel the finger is currently dragging. nil = none.
    @Published var panelDrag: PanelDrag?

    /// How far IN a panel is: 0 fully off screen, 1 fully home. ONE
    /// answer, because three things read it — the panel's own offset,
    /// the desk's travel, and the doors' fade — and a pixel of
    /// disagreement between them is visible.
    func panelProgress(_ which: PanelDrag.Which) -> CGFloat {
        let shown = which == .library ? libraryShown : inspectorShown
        guard panelDrag?.which == which else { return shown ? 1 : 0 }
        return panelDrag!.progress(UIScreen.main.bounds.width)
    }

    /// The desk's own travel, and the reason the two panels do not move
    /// alike (owner, 2026-08-15).
    ///
    /// The LIBRARY is a different PLACE, so it and the desk are one
    /// strip: opening it pushes the desk a whole screen right, and the
    /// desk sits off screen to the right the whole time it is open —
    /// "swipe away from the previous view, as if it sits on the left /
    /// right off screen".
    ///
    /// The PROPERTIES panel is about the note you are already looking
    /// at, so it stays a CURTAIN: it slides over a desk that does not
    /// move ("maybe having properties panel behave like a curtain
    /// though"). Hence one term here, not two.
    var deskShift: CGFloat {
        panelProgress(.library) * UIScreen.main.bounds.width
    }

    /// How far the properties CURTAIN has come down, 0…1. Whatever is
    /// drawn above the panels — the workspace button, the bottom bar,
    /// the minimised pill — fades by exactly this, because the curtain
    /// cannot cover what is painted on top of it.
    var curtain: CGFloat { panelProgress(.inspector) }

    /// How far the desk has travelled, as a fraction of the screen.
    /// The doors ride the desk, so they would slide THROUGH the pinned
    /// workspace button on the way out; they fade over the first third
    /// of the journey instead, and are gone before they reach it.
    var deskTravel: CGFloat {
        min(1, abs(deskShift) / max(1, UIScreen.main.bounds.width) * 3)
    }

    /// The metadata inspector covers the active entity tab's body.
    /// Lifted to the model so DeskHost's floating chevron can drive it;
    /// reset on every tab move — metadata is a visit, not a mode.
    @Published var inspectorShown = UserDefaults.standard.bool(forKey: "desk.boot.inspector")

    // MARK: records — a card over where you stand, never a tab (Option C)

    /// The task or event being edited in a card. Presented by whatever
    /// surface is frontmost, so tapping a task inside Tasks edits it
    /// WITHOUT leaving Tasks (owner, 2026-08-08).
    @Published var recordCard: UInt64?
    /// A card swiped away lives on as a pill above the bottom bar. One
    /// at a time, like a mail draft: go read a note, tap the pill, and
    /// you are back where you were. Every record edit saves as you make
    /// it, so the pill is pure navigation — nothing rides in it.
    @Published var minimisedRecord: UInt64?

    /// What kind of thing an id points at. Wired at launch from the box;
    /// nil before the first snapshot, which reads as "document" and is
    /// the safe answer (a document tab renders a record's name fine, a
    /// record card cannot render a note).
    var shapeOf: (UInt64) -> TabShape = { _ in .document }

    /// Put the card away, remembering it.
    func minimiseRecord() {
        guard let id = recordCard else { return }
        recordCard = nil
        withAnimation(LivMotion.nav) { minimisedRecord = id }
    }

    /// Bring the pill back to a card.
    func restoreRecord() {
        guard let id = minimisedRecord else { return }
        withAnimation(LivMotion.nav) { minimisedRecord = nil }
        recordCard = id
    }

    func dropMinimised() {
        withAnimation(LivMotion.nav) { minimisedRecord = nil }
    }

    /// A creation door committed an entity: close the menu and land it.
    /// Each door gets its own tab.
    ///
    /// This used to carry a LATCH — one tab per capture-sheet session,
    /// rewritten by each serial commit (§6 tab hygiene). The capture
    /// sheet is gone (2026-08-12), and with one entity per door there is
    /// nothing left to reuse a tab for, so the latch went with it.
    func adoptCapture(_ id: UInt64, as shape: TabShape? = nil) {
        menu = nil
        open(id, as: shape)
    }

    /// A just-born note whose editor should open with the caret already in
    /// it. Deliberately NOT @Published — it is consumed once by the editor
    /// that claims it, and a republish here would re-focus on every later
    /// visit to that tab.
    private var pendingFocus: UInt64?

    func requestFocus(_ id: UInt64) {
        pendingFocus = id
    }

    /// Whether THIS entity is the one just created — true once, then
    /// never again for that request.
    func consumeFocus(_ id: UInt64) -> Bool {
        guard pendingFocus == id else { return false }
        pendingFocus = nil
        return true
    }

    /// Tab-activation history for the bar's ‹ › — device state, not cells.
    private var backIds: [UUID] = []
    private var forwardIds: [UUID] = []

    /// The workspace whose tab set is currently on the plane. 0 = "All".
    private(set) var workspaceId: UInt64 = 0

    /// The pre-M4 single-plane key. Migrated once into the All plane so no
    /// one loses their open tabs to this change.
    private static let legacyKey = "desk.tabs.v1"

    private var persistKey: String { WorkspaceModel.tabsKey(workspaceId) }

    var activeTab: DeskTab? {
        tabs.first { $0.id == activeTabId }
    }

    var canGoBack: Bool { backIds.contains { alive($0) } }
    var canGoForward: Bool { forwardIds.contains { alive($0) } }

    private func alive(_ id: UUID) -> Bool {
        tabs.contains { $0.id == id }
    }

    /// This tab is being used, now. The ONE place a tab's clock is set.
    func touch(_ tabId: UUID) {
        guard let i = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[i].lastUsed = Civil.nowStamp()
        persist()
    }

    /// The tabs the grid shows. Inactive tabs are NOT removed from
    /// `tabs` — they stay in the one array, so closing, de-duplicating,
    /// pruning, ‹ › and the saved plane all keep working on the whole
    /// set, and only what is DISPLAYED narrows.
    ///
    /// The active tab is never inactive, which is what guarantees this
    /// is non-empty whenever `tabs` is — and therefore that the empty
    /// desk still means "no tabs at all", not "none you looked at
    /// lately".
    var liveTabs: [DeskTab] {
        let now = Civil.nowStamp()
        return tabs.filter {
            $0.id == activeTabId || !LivTabs.isInactive($0.lastUsed, now: now)
        }
    }

    /// Untouched long enough to be out of the way. Most recently used
    /// first, so the list reads newest-stale to oldest.
    var inactiveTabs: [DeskTab] {
        let now = Civil.nowStamp()
        return tabs
            .filter {
                $0.id != activeTabId && LivTabs.isInactive($0.lastUsed, now: now)
            }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    /// Close every inactive tab at once. Safe without a confirmation and
    /// without an undo: a tab is device state, so this writes nothing to
    /// the box — every note, file and capture is still there, in search,
    /// in Everything, in its workspace. The same reasoning the owner
    /// already accepted for the silent record-tab prune (2026-08-08).
    func closeInactive() {
        for tab in inactiveTabs { close(tab.id) }
    }

    /// Activate a tab, recording history. Every activation path funnels
    /// here so ‹ › always tell the truth.
    func focus(_ tabId: UUID) {
        // Stamp FIRST and unconditionally: re-opening the tab you are
        // already on is still using it, and the early return below would
        // otherwise let the active tab age out from under you.
        touch(tabId)
        guard tabId != activeTabId else { return }
        if let current = activeTabId { backIds.append(current) }
        forwardIds.removeAll()
        activeTabId = tabId
        if inspectorShown {
            // In the panel's own motion — a full-screen surface must
            // never vanish in one frame (audit, 2026-08-04).
            withAnimation(LivMotion.nav) { inspectorShown = false }
        }
        objectWillChange.send()
    }

    func goBack() {
        while let id = backIds.popLast() {
            guard alive(id) else { continue }
            if let current = activeTabId { forwardIds.append(current) }
            // ‹ › assign activeTabId directly rather than calling
            // focus(), so they must stamp for themselves — otherwise
            // stepping back to a tab and reading it left it ageing.
            touch(id)
            activeTabId = id
            leaveChooser()
            objectWillChange.send()
            return
        }
    }

    func goForward() {
        while let id = forwardIds.popLast() {
            guard alive(id) else { continue }
            if let current = activeTabId { backIds.append(current) }
            touch(id)
            activeTabId = id
            leaveChooser()
            objectWillChange.send()
            return
        }
    }

    /// ‹ › move the desk UNDERNEATH whatever menu is up. Asking for a
    /// tab means you want to see it.
    private func leaveChooser() {
        guard menu != nil else { return }
        menu = nil
    }

    init() {
        // One-time migration: the old single plane becomes the All plane.
        let defaults = UserDefaults.standard
        if defaults.dictionary(forKey: WorkspaceModel.tabsKey(0)) == nil,
            let legacy = defaults.dictionary(forKey: Self.legacyKey)
        {
            defaults.set(legacy, forKey: WorkspaceModel.tabsKey(0))
        }
        workspaceId = UInt64(defaults.integer(forKey: WorkspaceModel.activeKey))
        let (restored, active) = Self.load(WorkspaceModel.tabsKey(workspaceId))
        tabs = restored
        activeTabId =
            restored.indices.contains(active) ? restored[active].id : restored.first?.id
    }

    /// One plane's saved set. Entity ids only. An empty plane restores as
    /// genuinely empty — the empty desk shows its hint, and the `+`.
    private static func load(_ key: String) -> ([DeskTab], Int) {
        var restored: [DeskTab] = []
        var active = -1
        if let stored = UserDefaults.standard.dictionary(forKey: key) {
            let ids = (stored["ids"] as? [String] ?? []).compactMap { UInt64($0) }
            // The clocks, keyed by ENTITY id — a tab's UUID is minted
            // fresh every launch, so the entity is the only identity a
            // saved plane actually has.
            let used = stored["used"] as? [String: Int] ?? [:]
            // A plane saved before tabs had clocks counts as used NOW.
            // Reading a missing stamp as "never used" would sweep every
            // tab you own on the first launch after the upgrade.
            let now = Civil.nowStamp()
            restored = ids.map {
                DeskTab(
                    id: UUID(), content: .entity($0),
                    lastUsed: used[String($0)].map(Int64.init) ?? now)
            }
            active = stored["active"] as? Int ?? -1
        }
        return (restored, active)
    }

    /// Swap the plane. The outgoing set is saved under ITS key first, so a
    /// switch is never a loss; the incoming set replaces the tabs whole and
    /// the ‹ › history resets — it belonged to the other workspace.
    func adopt(workspace id: UInt64) {
        guard id != workspaceId else { return }
        persist()  // the OUTGOING key — persistKey still points at it
        workspaceId = id
        let (restored, active) = Self.load(persistKey)
        backIds = []
        forwardIds = []
        tabs = restored
        activeTabId =
            restored.indices.contains(active) ? restored[active].id : restored.first?.id
        featureShown = nil
        switcherShown = false
        libraryShown = false
        menu = nil
        inspectorShown = false
        settingsShown = false
        objectWillChange.send()
    }

    /// The one door for opening anything, anywhere.
    ///
    /// A DOCUMENT lands as a tab at the desk, exactly as before. A
    /// RECORD (task, event) opens as a card over whatever you are
    /// looking at and closes nothing — the old behaviour threw you out
    /// of Tasks on every tap and left an orphan tab behind (owner,
    /// 2026-08-08, Option C).
    /// `as` is for a caller that JUST created the entity: the box
    /// answers before the snapshot lands, so `shapeOf` on a brand-new id
    /// reads nil and guesses "document" — which is why "New task" used
    /// to open a markdown editor instead of the task's own card
    /// (traced 2026-08-11). A creator knows what it made; it says so.
    func open(_ entityId: UInt64, as shape: TabShape? = nil) {
        guard (shape ?? shapeOf(entityId)) == .record else {
            openDocument(entityId)
            return
        }
        openAsCard(entityId)
    }

    /// A record rises as a card over wherever you stand, and closes
    /// nothing (Option C).
    private func openAsCard(_ entityId: UInt64) {
        minimisedRecord = nil
        recordCard = entityId
        menu = nil
    }

    /// Land a document as a tab. Everything that used to be `open`.
    private func openDocument(_ entityId: UInt64) {
        recordCard = nil
        if let existing = tabs.first(where: { $0.content == .entity(entityId) }) {
            focus(existing.id)
        } else {
            let tab = DeskTab(
                id: UUID(), content: .entity(entityId),
                lastUsed: Civil.nowStamp())
            tabs.append(tab)
            focus(tab.id)
        }
        featureShown = nil
        switcherShown = false
        // The in-hierarchy overlays animate out in the house motion — a
        // full-screen surface must never vanish in one frame (audit,
        // 2026-08-04). The properties panel is here too: focus() skips
        // its reset when the tab is ALREADY active, so a reminder tap
        // for the open note would land behind it.
        withAnimation(LivMotion.nav) {
            libraryShown = false
            menu = nil
            inspectorShown = false
        }
        // Search, camera, Settings and the workspace switcher are covers
        // and sheets — UIKit animates their dismissal itself. A tapped
        // reminder routes here from anywhere, so leaving any of them up
        // made the notification look ignored: the tab was created and
        // focused behind a surface the user was still looking at.
        searchShown = false
        cameraShown = false
        settingsShown = false
        workspaceShown = false
        persist()
    }

    /// `+`: the create MENU, sliding up over whatever you are looking at
    /// (owner, 2026-08-13). It never appends a tab — choosing something
    /// does. The full-screen page this used to summon is deleted.
    func newTab() {
        featureShown = nil
        menu = newTabMenu?()
    }

    /// Closing the last tab leaves the desk empty — and an empty desk is
    /// empty: a hint, and the `+` that ends it.
    func close(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            activeTabId = nil
        } else if activeTabId == tabId {
            // The nearest tab you have actually been using. Stepping to
            // the plain index neighbour could land the desk on a
            // three-week-old note you never asked for.
            let now = Civil.nowStamp()
            let fresh = tabs.filter { !LivTabs.isInactive($0.lastUsed, now: now) }
            let nextDoor = tabs[min(index, tabs.count - 1)]
            let landing =
                LivTabs.isInactive(nextDoor.lastUsed, now: now)
                ? (fresh.max { $0.lastUsed < $1.lastUsed } ?? nextDoor)
                : nextDoor
            activeTabId = landing.id
            touch(landing.id)
        }
        persist()
    }

    /// Entity ids only — .new tabs are moments, not state worth restoring.
    /// Always to the CURRENT workspace's key: opening something from search
    /// or the inbox joins the current workspace's set, by construction.
    /// Old saved tab sets may hold task or event ids from before Option
    /// C. A record cannot be a tab, so those close quietly the first
    /// time the box says what they are (owner, 2026-08-08: the app is in
    /// alpha, delete freely).
    func pruneRecordTabs() {
        let doomed = tabs.filter {
            // ONLY records. A file is a document you work on and keeps
            // its tab (files, 2026-08-09).
            if case .entity(let id) = $0.content { return shapeOf(id) == .record }
            return false
        }
        guard !doomed.isEmpty else { return }
        for tab in doomed { close(tab.id) }
    }

    /// Rehearsal only (`-desk.boot inactive`): age every tab except the
    /// active one, so the Inactive list can be seen and photographed
    /// today. Writes nothing but the same per-device clocks a real week
    /// of use would.
    func backdateTabsForRehearsal(days: Int) {
        let old = Civil.stamp(
            day: Civil.addDays(Civil.todayDay(), -days), hhmm: 900)
        for i in tabs.indices where tabs[i].id != activeTabId {
            tabs[i].lastUsed = old - Int64(i)
        }
        persist()
        objectWillChange.send()
    }

    /// Self-check only: install a known set of tabs. `tabs` is
    /// private(set) so the suite cannot reach it, and the alternative —
    /// opening the setter to everyone — is how a second file starts
    /// mutating the tab plane.
    func replaceTabsForSelfCheck(_ fresh: [DeskTab]) {
        tabs = fresh
        activeTabId = fresh.last?.id
    }

    private func persist() {
        var ids: [String] = []
        var used: [String: Int] = [:]
        var active = -1
        // EVERY tab, inactive ones included. `active` is an index into
        // the ids array being built here, so filtering any tab out would
        // both point it at the wrong tab and lose the inactive ones for
        // good.
        for tab in tabs {
            guard case .entity(let entity) = tab.content else { continue }
            if tab.id == activeTabId { active = ids.count }
            ids.append(String(entity))
            used[String(entity)] = Int(tab.lastUsed)
        }
        UserDefaults.standard.set(
            ["ids": ids, "active": active, "used": used], forKey: persistKey)
    }
}

/// Which lens row is being picked, and which draft it writes back to.
struct WorkspacePick: Identifiable {
    let property: String
    let forFilter: Bool
    var id: String { "\(property)-\(forFilter)" }
}

// MARK: - the workspace switcher (M4)

/// The hub's sheet: All (no lens), every workspace, and
/// the new-workspace form. Switching swaps the desk's open tabs — one tab
/// plane, remembered per workspace.
struct WorkspaceSwitcher: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @EnvironmentObject var desk: DeskModel
    @Environment(\.dismiss) private var dismiss

    @State private var composing = false
    /// nil while composing a NEW workspace; the id being edited otherwise.
    /// Editing exists because the box ships a seeded "Home" workspace: with
    /// a create-only form it could never become a workspace at all.
    @State private var editing: UInt64?
    @State private var draftName = ""
    @State private var draftQuery = ""
    @State private var composingFilter = false
    @State private var filterName = ""
    @State private var filterQuery = ""
    /// The raw query, folded away. A workspace IS its query — that is how
    /// it is stored — but nobody should have to type one to make one
    /// (standing rule 5), so the text is the escape hatch, not the door.
    /// Which picker row is open, and whose draft it edits.
    @State private var picking: WorkspacePick?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Making a FILTER shows the filter form and nothing else.
                // This sheet is the workspace switcher, and the form only
                // borrows it (standing rule 4: one form, one place) — but
                // a list of workspaces above a filter you are naming is
                // the wrong screen (owner, 2026-08-13).
                if !composingFilter {
                    SectionLabel("Workspace")
                        .padding(.bottom, 4)
                    choice(
                        name: "All", lens: LivQuery.empty,
                        active: workspaces.activeId == 0, glyph: .workspaces
                    ) {
                        choose(0)
                    }
                    ForEach(workspaces.workspaces) { ws in
                        choice(
                            name: ws.display, lens: queryLens(ws),
                            active: workspaces.activeId == ws.id, glyph: .workspace,
                            emoji: ws.emoji
                        ) {
                            choose(ws.id)
                        }
                        .contextMenu {
                            Button {
                                editing = ws.id
                                draftName = ws.display
                                draftQuery = workspaces.query(of: ws.id) ?? ""
                                composing = true
                            } label: {
                                Label("Edit workspace", systemImage: "slider.horizontal.3")
                            }
                            Button(role: .destructive) {
                                workspaces.forgetQuery(ws.id)
                                if workspaces.activeId == ws.id { choose(0, close: false) }
                                box.trashWorkspace(ws.id)
                            } label: {
                                Label("Trash workspace", systemImage: "trash")
                            }
                        }
                    }
                    if composing {
                        newWorkspaceForm
                    } else {
                        addRow("New workspace…") {
                            editing = nil
                            draftName = ""
                            draftQuery = ""
                            composing = true
                        }
                    }
                }
                // Filters LIVE in the library panel now; only their form
                // is still here, opened by the panel's "New filter…".
                if composingFilter {
                    SectionLabel("New filter")
                        .padding(.bottom, 4)
                    newFilterForm
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(LivTheme.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // The SAME picker the properties panel uses, told to report the
        // choice instead of writing a cell.
        .onAppear {
            if desk.composeFilter {
                composingFilter = true
                desk.composeFilter = false
            }
        }
        .sheet(item: $picking) { pick in
            InspectorValueSheet(
                field: InspectorField.describe(pick.property, in: box.snap),
                id: 0,
                current: [],
                onPick: { value in
                    let binding = pick.forFilter ? $filterQuery : $draftQuery
                    binding.wrappedValue = LivQuery.parse(binding.wrappedValue)
                        .setting(pick.property, to: value)
                }
            )
            .environmentObject(box)
        }
    }

    /// The lens, read straight off the wire. A workspace with no query
    /// shows NOTHING — "no query" was a placeholder standing in for an
    /// absence the empty line already states (owner, 2026-08-06).
    private func queryLens(_ ws: WorkspaceRow) -> LivQuery {
        LivQuery.parse(workspaces.query(of: ws.id) ?? "")
    }

    /// The VALUES a lens keeps to — the same words the pickers offered.
    /// Everything else a hand-made query can say (exclusions, presence
    /// tests, free text) has no chip: a chip is a value, and inventing a
    /// shorthand for the rest would be the query language again, spelled
    /// differently. A lens made of those alone shows nothing.
    private func lensChips(_ lens: LivQuery) -> [String] {
        lens.terms.compactMap { term in
            if case .equals(_, let value) = term { return value }
            return nil
        }
    }

    private func choose(_ id: UInt64, close: Bool = true) {
        workspaces.setActive(id)
        if close { dismiss() }
    }

    /// A workspace's own emoji leads its row (the furnished areas each
    /// carry one); the drawn ring is the emoji-less fallback.
    ///
    /// The lens shows as VALUE CHIPS, never as its text. A row used to
    /// read `area:Work project:Viggo` in mono under the name — the query
    /// language showing through, which no user ever types (owner,
    /// 2026-08-11). The raw text is still there, in the folded Advanced
    /// field where it belongs.
    private func choice(
        name: String, lens: LivQuery, active: Bool, glyph: LivGlyph,
        emoji: String? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: LivType.body))
                        .frame(width: 18)
                } else {
                    LivIcon(
                        glyph: glyph,
                        color: active ? LivTheme.accent : LivTheme.text3, size: 18
                    )
                    .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: LivType.body, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? LivTheme.accent : LivTheme.text)
                        .lineLimit(1)
                    if !lensChips(lens).isEmpty {
                        HStack(spacing: 5) {
                            ForEach(lensChips(lens), id: \.self) { ValueChip($0) }
                        }
                    }
                }
                Spacer(minLength: 6)
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: LivType.label, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                }
            }
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }

    private func addRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: LivType.label, weight: .semibold))
                    .frame(width: 18)
                Text(label).font(.system(size: LivType.body))
                Spacer()
            }
            .foregroundStyle(LivTheme.accent)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: the new-workspace form — name + query + the stamp hint

    private var newWorkspaceForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Name", text: $draftName)
            lensRows($draftQuery, forFilter: false)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") {
                    composing = false
                    editing = nil
                }
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text3)
                .buttonStyle(.plain)
                Button(action: saveWorkspace) {
                    Text(editing == nil ? "Create" : "Save")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(LivTheme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmed(draftName).isEmpty)
                .opacity(trimmed(draftName).isEmpty ? 0.45 : 1)
            }
        }
        .padding(.vertical, 10)
    }

    /// What the lens is made of: pick an area, pick a subject. The two
    /// the owner named (2026-08-11) — project and people are reachable
    /// through Advanced and were noise here.
    ///
    /// No sentence explains any of this. A grey line under a control is
    /// a design failure (owner, 2026-08-06), so the row shows the value
    /// itself and nothing else; the old "stamps area:Work" hint is gone
    /// with it.
    @ViewBuilder private func lensRows(
        _ query: Binding<String>, forFilter: Bool
    ) -> some View {
        ForEach(["area", "subjects"], id: \.self) { property in
            let parsed = LivQuery.parse(query.wrappedValue)
            let value = parsed.value(of: property)
            Button {
                picking = WorkspacePick(property: property, forFilter: forFilter)
            } label: {
                HStack(spacing: 8) {
                    Text(property == "area" ? "Area" : "Subject")
                        .font(.system(size: LivType.body))
                        .foregroundStyle(LivTheme.text)
                    Spacer(minLength: 8)
                    if let value {
                        ValueChip(value)
                    } else {
                        Text("Any")
                            .font(.system(size: LivType.body))
                            .foregroundStyle(LivTheme.text3)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: LivType.caption, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                .frame(height: LivRow.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                if property != "area" {
                    Rectangle().fill(LivTheme.border).frame(height: 0.5)
                }
            }
        }
    }

    private var newFilterForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Name", text: $filterName)
            lensRows($filterQuery, forFilter: true)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") {
                    composingFilter = false
                }
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text3)
                .buttonStyle(.plain)
                Button(action: createFilter) {
                    Text("Save")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(LivTheme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmed(filterName).isEmpty || trimmed(filterQuery).isEmpty)
                .opacity(
                    trimmed(filterName).isEmpty || trimmed(filterQuery).isEmpty ? 0.45 : 1)
            }
        }
        .padding(.vertical, 10)
    }

    /// One dress, one font. The mono variant existed for the raw query
    /// field, which is gone (owner, 2026-08-14).
    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(.system(size: LivType.body))
            .foregroundStyle(LivTheme.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel))
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                    .strokeBorder(LivTheme.border, lineWidth: 0.5)
            )
    }

    /// The honesty line: exactly what a capture in this workspace inherits.

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Birth (or re-aim) the workspace: write its `query` cell, and mint any
    /// property the stamp names but the box has never seen — `set` REFUSES
    /// an unknown property name, so without this the stamp would silently do
    /// nothing. One serial lane, so these land in order.
    private func saveWorkspace() {
        let name = trimmed(draftName)
        let query = trimmed(draftQuery)
        guard !name.isEmpty else { return }
        if let id = editing {
            box.set(id, "name", name)
            write(query, to: id)
            finish(id)
        } else {
            box.createWorkspace(name: name) { id in
                guard id != 0 else { return }
                write(query, to: id)
                finish(id)
            }
        }
    }

    /// The `query` cell IS the workspace. An emptied query clears the cell
    /// rather than leaving a stale lens behind.
    private func write(_ query: String, to id: UInt64) {
        if query.isEmpty {
            box.unset(id, "query")
        } else {
            box.set(id, "query", query)
            for cell in LivQuery.parse(query).stampCells where cell.property != "type" {
                box.addProperty(cell.property)
            }
        }
        workspaces.rememberQuery(id, query)
    }

    private func finish(_ id: UInt64) {
        draftName = ""
        draftQuery = ""
        composing = false
        editing = nil
        choose(id)
    }

    private func createFilter() {
        let name = trimmed(filterName)
        let query = trimmed(filterQuery)
        guard !name.isEmpty, !query.isEmpty else { return }
        box.createView(name: name, query: query) { id in
            guard id != 0 else { return }
            filterName = ""
            filterQuery = ""
            composingFilter = false
            workspaces.activeFilterId = id
        }
    }
}

// MARK: - settings (relocated from Today's header; the chrome owns the gear)

/// Facts and notes — plus the ONE schema door (§10): Fields, where a new
/// property definition is minted. Settings still never writes cells on
/// entities; the inspector's old "+ property" moved here because schema
/// growth is possible, not daily use. The Handoff section
/// (design/ios.md §2.2) is the funnel's honesty surface: the status card,
/// the per-item Pending/Shipped/Delivered ledger, "Ship now", and the
/// satellite-path row (dev-grade paste field — file pickers arrive with
/// the real Xcode project). Setting the path is device config, not a cell.
struct SettingsSheet: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var outbox: Outbox
    @ObservedObject private var notify = Notify.shared
    @State private var addingField = false
    @State private var fieldDraft = ""
    /// Dark, light, or follow the system — device state, never a cell.
    @AppStorage(LivAppearance.key) private var appearance = LivAppearance.dark.rawValue
    /// How long a desk tab may sit untouched before it steps out of the
    /// grid. Device state too — Settings never writes cells.
    @AppStorage(LivTabs.key) private var inactiveDays = LivTabs.defaultDays

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.system(size: LivType.title, weight: .bold))
                    .foregroundStyle(LivTheme.text)
                    .padding(.bottom, 4)
                // What a person actually came here to change, first.
                SectionLabel("Appearance")
                appearanceRow
                if box.snap?.assist != nil {
                    SectionLabel("Suggestions")
                        .padding(.top, 10)
                    assistRow
                }
                SectionLabel("Reminders")
                    .padding(.top, 10)
                notifyRows
                SectionLabel("Tabs")
                    .padding(.top, 10)
                inactiveTabsRow
                SectionLabel("Fields")
                    .padding(.top, 10)
                fieldsRow
                // No Advanced drawer. It held the phone→desk handoff
                // (status, ledger, Ship now, the satellite path) and the
                // store's own facts, and it went with every other
                // advanced feature (owner, 2026-08-14): the friendly
                // ones come first. Nothing in the app can set a
                // satellite path now, so the handoff is off until it
                // gets a door someone would want to open.
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(LivTheme.surface)
        // Read-only refresh: acks on disk become Delivered chips.
        .onAppear { outbox.scanAcks() }
    }

    // The Fields door (§10): the schema the box holds, and the ONE place a
    // new field is born. Relocated from the inspector's "+ property" row —
    // adding a kind of field is possible, never in the flow of daily use.

    /// The box's field vocabulary, usage-desc, off the live snapshot.
    private var fieldNames: [String] {
        (box.snap?.properties ?? [])
            .sorted { ($0.usage ?? 0) > ($1.usage ?? 0) }
            .compactMap { $0.name }
            .filter { !$0.isEmpty }
    }

    /// When a tab goes Inactive. A picker over fixed periods, because a
    /// user never types a rule (standing rule 5). "Never" turns the
    /// whole thing off and every tab comes straight back to the grid —
    /// nothing was ever closed, so it is lossless both ways.
    private var inactiveTabsRow: some View {
        Picker("Inactive after", selection: $inactiveDays) {
            ForEach(LivTabs.choices, id: \.self) { days in
                Text(LivTabs.label(days)).tag(days)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 30)
    }

    private var appearanceRow: some View {
        Picker(
            "Appearance",
            selection: Binding(
                get: { LivAppearance(rawValue: appearance) ?? .dark },
                set: { appearance = $0.rawValue })
        ) {
            ForEach(LivAppearance.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 30)
    }

    @ViewBuilder private var fieldsRow: some View {
        if !fieldNames.isEmpty {
            // Chips, not a run-on line of names separated by dots. The
            // vocabulary is data; the app already has a way to show data.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(fieldNames, id: \.self) { ValueChip($0) }
                }
                .padding(.vertical, 1)
            }
        }
        if addingField {
            HStack(spacing: 8) {
                TextField("Name the new field", text: $fieldDraft)
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(createField)
                Button("Create", action: createField)
                    .font(.system(size: LivType.label, weight: .medium))
                    .foregroundStyle(fieldDraftReady ? LivTheme.accent : LivTheme.muted)
                    .buttonStyle(.plain)
                    .disabled(!fieldDraftReady)
                Button {
                    addingField = false
                    fieldDraft = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: LivType.caption, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                    .strokeBorder(LivTheme.border, lineWidth: 0.5)
            )
        } else {
            Button {
                addingField = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: LivType.caption, weight: .semibold))
                    Text("Add field")
                        .font(.system(size: LivType.body, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(LivTheme.accent)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add field")
        }
    }

    private var fieldDraftReady: Bool {
        let name = fieldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        // Minting a duplicate is refused by the core anyway; disable the
        // button rather than offer a refusal.
        return !fieldNames.contains {
            $0.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    /// Births a TEXT property — the same implicit kind the inspector's old
    /// flow assumed. Other kinds stay a desktop/CLI affair for now.
    private func createField() {
        let name = fieldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fieldDraftReady else { return }
        box.addProperty(name) { id in
            guard id != 0 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            fieldDraft = ""
            addingField = false
        }
    }

    // The assist switch (rev 6): the consent that gates every clerk
    // proposal. With it off the sweep is silent and the wire's inbox is
    // force-empty; with it on, the clerk SUGGESTS (Properties panel's
    // Suggested section) and only an explicit Accept ever writes. This is
    // the one Settings row that writes a cell — the switch LIVES in the
    // box, so the desktop and the phone agree about consent.

    @ViewBuilder private var assistRow: some View {
        if let assist = box.snap?.assist, let entity = assist.id {
            Toggle(
                isOn: Binding(
                    get: { assist.on ?? false },
                    set: { on in
                        box.set(entity, assist.prop ?? "automation", on ? "true" : "false")
                    })
            ) {
                Text("Suggest properties")
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text)
            }
            .tint(LivTheme.accent)
            .frame(minHeight: 30)
        }
    }

    // The Notifications section (M5, Notify.swift): master toggle, the two
    // per-kind lead pickers, and the 64-cap honesty line. All DEVICE state
    // (UserDefaults) — Settings never writes cells. Every change rebuilds
    // the pending queue from the snapshot in hand. Quiet hours: DEFERRED —
    // reminders currently ring at any hour.

    @ViewBuilder private var notifyRows: some View {
        Toggle(isOn: notifyEnabled) {
            Text("Due reminders")
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
        }
        .tint(LivTheme.accent)
        .frame(minHeight: 30)
        if notify.enabled {
            // One switch, no lead times. A reminder rings when the thing
            // is due; the two pickers that used to sit here were invented
            // and governed only the rare timed case (owner, 2026-08-06).
            // Only speak when something is WRONG.
            if let line = notifyProblem {
                Text(line)
                    .font(.system(size: LivType.label).monospacedDigit())
                    .foregroundStyle(notify.denied ? LivTheme.red : LivTheme.text3)
            }
        }
    }

    private var notifyEnabled: Binding<Bool> {
        Binding(
            get: { notify.enabled },
            set: {
                notify.enabled = $0
                notify.rebuild(snapshot: box.snap, box: box)
            })
    }

    /// Says something only when a reminder will NOT arrive: iOS refused
    /// permission, or the 64-notification cap dropped the far ones.
    private var notifyProblem: String? {
        if notify.denied { return "Turned off for Liv in iOS Settings." }
        if notify.droppedCount > 0 {
            return "\(notify.droppedCount) beyond iOS's 64-reminder limit won't ring."
        }
        return nil
    }

}


// MARK: - keyboard watch

/// Is a keyboard on screen? While one is, the bottom bar retires — left
/// standing, SwiftUI's keyboard avoidance lifts it ABOVE the editor's
/// formatting row, stacking two bars over the keys (owner, 2026-08-02).
/// One app-wide watcher, because the answer is a property of the screen,
/// not of any one text view.
final class KeyboardWatch: ObservableObject {
    @Published var up = false
    private var tokens: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        tokens.append(
            nc.addObserver(
                forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
            ) { [weak self] _ in
                withAnimation(LivMotion.nav) { self?.up = true }
            })
        tokens.append(
            nc.addObserver(
                forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
            ) { [weak self] _ in
                withAnimation(LivMotion.nav) { self?.up = false }
            })
    }

    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}

// MARK: - bottom bar

/// ONE horizontal row (owner, 2026-08-01 — the floating pill plus a
/// separate circle read as fragments). Navigation over the open notes and
/// the doors that make more of them: ‹ › history, search, new tab, the
/// tab count. Global features left this bar entirely — they live in the
/// library panel, behind the top-left door.
struct BottomBar: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
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
            // ALWAYS live. It was disabled on an empty desk, back when
            // the empty desk's body WAS the New Tab chooser and a second
            // door to it would have been a lie (audit, 2026-08-04). That
            // page is gone (2026-08-13) and the empty desk now points at
            // this button — "No tabs. The + below makes one." — so the
            // guard became the lie it was written to prevent: a
            // workspace with no tabs could not be given one at all
            // (owner, 2026-08-15, from the phone).
            navButton("plus", enabled: true, label: "New tab") {
                desk.newTab()
            }
            tabCountButton
        }
        .padding(.horizontal, 4)
        .frame(height: LivRow.height)
        .frame(maxWidth: .infinity)
        // Solid, never a blur: the body must not read through the bar.
        .background(LivTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }

    private func navButton(
        _ icon: String, enabled: Bool, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: LivType.title, weight: .medium))
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
                    Text(
                        desk.liveTabs.count > 99
                            ? "99" : "\(desk.liveTabs.count)")
                        .font(.system(size: LivType.micro, weight: .bold).monospacedDigit())
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
