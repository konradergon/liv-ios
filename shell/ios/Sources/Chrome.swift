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
/// NOTES IS ONE OF THEM (owner, 2026-08-18: "Each state should be treated
/// equally… and the notes should remain separate"). It leads because it
/// is where the words are, and its ROOT is the list of them; a note open
/// on the desk is one level inside it.
enum Feature: String, CaseIterable, Identifiable {
    case notes, today, everything, inbox, tasks, calendar

    var id: String { rawValue }

    /// THE ORDER, declared once. `allCases` follows the declaration and
    /// the Go-to menu hard-coded a different one; only the menu's was
    /// ever visible, so they were free to disagree. Putting the views in
    /// the side panel makes a second one visible, which is exactly when
    /// two orderings become a bug (standing rule 4).
    static let inOrder: [Feature] = [.today, .notes, .inbox, .calendar, .tasks, .everything]

    var title: String {
        switch self {
        case .notes: return "Notes"
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
        case .notes: return .note
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

/// One tab. Restored 2026-08-22 with the model it had before
/// `0aa2af3` deleted it (design/tabs.md).
struct DeskTab: Identifiable {
    /// Minted fresh every launch. A tab's durable identity is the entity
    /// it holds, which is what the saved plane stores.
    let id: UUID
    var content: DeskTabContent
    /// When this tab was last USED — opened or focused. A packed civil
    /// stamp, the app's one time vocabulary. Tabs that go untouched long
    /// enough fall out of the grid onto the Inactive shelf; nothing about
    /// them is lost, they are just not in the way. No default on purpose:
    /// every place that mints a tab has to say when.
    var lastUsed: Int64
}

/// **Notes only, for now.** The team's ruling of 2026-08-22 is Reading B:
/// each view owns a tab strip, and a tab is a saved POSITION inside that
/// view. In Notes that position is a document, which is exactly what this
/// case was before. The other views' cases arrive with their planes; in
/// Tasks a tab will be a list, and tapping a task still raises a card —
/// so neither of the owner's 2026-08-07 and 2026-08-08 rulings is
/// reversed.
enum DeskTabContent: Equatable {
    case entity(UInt64)
}

// MARK: - where you are

/// One place you have been: a state, or a document inside Docs. The
/// stack exists for ONE control — the labelled back at the top of a
/// document, which says where it will take you ("‹ Docs", "‹ Today",
/// "‹ Kitchen rebuild"). Device state, never a cell.
enum LivPlace: Equatable {
    case state(Feature)
    case document(UInt64)
}

/// The chrome's one state object.
///
/// **One open document** (owner, 2026-08-18). Tabs are gone: Docs is a
/// list of your notes ordered by what you touched last, opening one
/// replaces what was open, and the id rides UserDefaults per workspace
/// ("desk.doc.v1.<workspace>") so a relaunch resumes where you were. The
/// plane of tabs, its grid, its inactive shelf and its saved layouts are
/// all deleted; what they were for — "hold two notes at once" — is the
/// list's top rows and the labelled back.
final class DeskModel: ObservableObject {
    // MARK: the chrome gets out of the way while you read

    /// THE BAR AND THE DOORS ARE OFF SCREEN because you are reading
    /// (owner's clips, 2026-08-20 — Obsidian). Scrolling INTO a list
    /// sends them away; scrolling back up, or reaching the top, brings
    /// them home. A long note or a long list is the whole screen, and
    /// the furniture is one small scroll away.
    ///
    /// One flag on this model, because both halves of the chrome are
    /// mounted in different files and both already observe it: the bar
    /// in `RootView` (App.swift) and the doors in `DeskHost`
    /// (Desk.swift).
    @Published private(set) var chromeAway = false

    /// The offset the last decision was made at. Kept within
    /// `chromeThreshold` of the live offset, so a direction change
    /// answers on the next few points rather than having to undo the
    /// whole scroll first.
    private var chromeAnchor: CGFloat = 0

    /// How far you must scroll before the chrome agrees you meant it.
    /// Small enough to feel immediate, large enough that the rubber-band
    /// at the end of a list does not flap it.
    private let chromeThreshold: CGFloat = 44

    /// The band at the top of a list where the chrome is ALWAYS there.
    /// Arriving at a surface must never be the state where its
    /// furniture is missing.
    private let chromeHome: CGFloat = 40

    /// One scroll offset, in points from the content's top.
    func scrolled(to y: CGFloat) {
        if y <= chromeHome {
            chromeAnchor = y
            setChrome(away: false)
            return
        }
        if y > chromeAnchor + chromeThreshold { setChrome(away: true) }
        if y < chromeAnchor - chromeThreshold { setChrome(away: false) }
        chromeAnchor = min(max(chromeAnchor, y - chromeThreshold), y + chromeThreshold)
    }

    /// Back on screen, unconditionally — leaving a surface, opening a
    /// menu, anything that is not reading.
    func chromeHomeAgain() {
        chromeAnchor = 0
        setChrome(away: false)
    }

    private func setChrome(away: Bool) {
        guard away != chromeAway else { return }
        withAnimation(LivMotion.nav) { chromeAway = away }
    }

    /// WHICH STATE YOU ARE IN. The bar's key names it and the Go-to menu
    /// changes it; there is no "no state" — Docs is one of them.
    @Published var state: Feature = .notes
    /// The Notes plane: the open tabs and which one is active.
    @Published private(set) var tabs: [DeskTab] = []
    @Published var activeTabId: UUID? {
        didSet { persist() }
    }
    @Published var switcherShown = false

    /// The document on the desk — now DERIVED from the active tab rather
    /// than stored beside it.
    ///
    /// This one line is why `Desk.swift` needed no changes at all: every
    /// existing caller of `openDoc` keeps working, and the tab plane
    /// became the single place the answer lives. Two slots holding the
    /// same fact is how they start to disagree.
    var openDoc: UInt64? {
        guard case .entity(let id)? = activeTab?.content else { return nil }
        return id
    }

    var activeTab: DeskTab? { tabs.first { $0.id == activeTabId } }
    /// Where the labelled back at the top of a document goes. Capped:
    /// a chain of link jumps is a stack, not a diary.
    @Published private(set) var returns: [LivPlace] = []
    @Published var searchShown = false
    /// The library place (left) is up.
    @Published private(set) var libraryShown = false
    /// The library is MOUNTED. It goes up before `libraryShown` and comes
    /// down after it, so the slide has a frame to start from: a view
    /// inserted and offset in the same frame has nowhere to travel from,
    /// and SwiftUI falls back to a fade (owner, 2026-08-15: "clicking on
    /// the library button doesn't literally move in quickly like it
    /// should but rather fades in"). The one menu learned this first
    /// (Menu.swift's `sync`).
    @Published private(set) var libraryDrawn = false

    /// Go to the library, or come back to the desk. THE door — the
    /// button, a settled drag and every internal jump all land here, so
    /// the mount and the motion can never disagree.
    func setLibrary(_ open: Bool, animated: Bool = true) {
        guard open != libraryShown else { return }
        if open {
            libraryDrawn = true
            guard animated else {
                libraryShown = true
                return
            }
            // Mount first, THEN slide.
            DispatchQueue.main.async { [self] in
                withAnimation(LivMotion.nav) { libraryShown = true }
            }
        } else {
            if animated {
                withAnimation(LivMotion.nav) { libraryShown = false }
            } else {
                libraryShown = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.navSeconds) {
                [self] in
                if !libraryShown { libraryDrawn = false }
            }
        }
    }

    @Published var cameraShown = false
    /// The Settings sheet and the WORKSPACE switcher sheet (distinct from
    /// the tab view). Model state so open() can dismiss
    /// them — as DeskHost-local @State they outlived a notification tap
    /// and the landing tab hid behind them (audit, 2026-08-04).
    @Published var settingsShown = false
    /// The trash list — the only door to `liv_restore_at`.
    @Published var trashShown = false
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

    /// The day the surface in front is looking at, or nil when the
    /// surface has no day of its own. The bar's create key reads it, so
    /// a task made while looking at Thursday is due Thursday — the one
    /// thing the views' own floating keys knew that the bar's did not
    /// (owner, 2026-08-17). Set by Today and the calendar as their
    /// selection moves; cleared when they leave.
    var contextDay: Int64?

    /// How to build the create menu. Set by DeskHost, which owns the
    /// verbs — the same shape as `shapeOf` above, and the reason the
    /// model can offer a menu it has no way to build itself.
    var createMenu: (() -> LivMenu)?
    /// One panel being dragged: which one, whether the drag OPENS or
    /// CLOSES it, and the finger's travel so far. It lives on the MODEL
    /// because the bottom bar and the pill, which fade under a curtain,
    /// are drawn by RootView, one level up.
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

    /// The desk is the surface in FRONT — nothing full-screen covers it.
    ///
    /// The panel drag is a recognizer on the WINDOW, so it sees touches
    /// inside a feature window, search, the tab switcher, the camera and
    /// every sheet as well. Its own installer says so ("the window
    /// recognizer would otherwise drag panels invisibly behind a
    /// full-screen view") but it was only ever told about the menu.
    /// Measured 2026-08-15: one sideways drag of the mini calendar
    /// latched a panel behind the calendar window and published 58
    /// times, and the calendar re-rendered on every one of them — the
    /// owner's "minicalendar lags when dragged".
    /// A view is no longer one of these: it opens INSIDE the library
    /// (2026-08-15), which is a place on the strip, not a cover — the
    /// swipe back to the desk has to keep working while you are in one.
    var deskInFront: Bool {
        !searchShown && !cameraShown && !settingsShown
            && !workspaceShown
    }

    /// How far IN a panel is: 0 fully off screen, 1 fully home. ONE
    /// answer, because three things read it — the panel's own offset,
    /// the desk's travel, and the doors' fade — and a pixel of
    /// disagreement between them is visible.
    func panelProgress(_ which: PanelDrag.Which) -> CGFloat {
        let shown = which == .library ? libraryShown : inspectorShown
        guard panelDrag?.which == which else { return shown ? 1 : 0 }
        return panelDrag!.progress(UIScreen.main.bounds.width)
    }

    /// The two panels do NOT move alike, and the reason is what each
    /// one is (owner, 2026-08-17: "make the left panel parked on the
    /// right and have you move to / from it").
    ///
    /// The LIBRARY is a PLACE — the app's primary menu — so it and the
    /// surface in front are one horizontal strip: the menu is parked off
    /// the left edge, everything else is parked to its right, and going
    /// between them is travel. Opening the menu pushes the surface a
    /// whole screen right; it waits there while you choose.
    ///
    /// The PROPERTIES panel is about the note you are already looking
    /// at, so it stays a CURTAIN over a surface that does not move
    /// (owner, 2026-08-15: "maybe having properties panel behave like a
    /// curtain though").
    ///
    /// This is the strip of 2026-08-15 restored, deliberately: it was
    /// withdrawn the next day with the surface work it arrived in, and
    /// it is right again now that the left panel is where the app's
    /// views live.
    var deskShift: CGFloat {
        panelProgress(.library) * UIScreen.main.bounds.width
    }

    /// How far the surface has travelled, 0…1. The doors ride it, so
    /// they would slide THROUGH the pinned workspace button on the way
    /// out; they fade over the first third of the journey instead, and
    /// are gone before they reach it.
    var deskTravel: CGFloat {
        min(1, abs(deskShift) / max(1, UIScreen.main.bounds.width) * 3)
    }

    var curtain: CGFloat { panelProgress(.inspector) }

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
    /// Does the box hold this at all? Defaults to yes, so nothing is
    /// pruned before a box has answered.
    var knows: (UInt64) -> Bool = { _ in true }

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

    /// The pre-M4 single plane, and the per-workspace tab sets that
    /// followed it. READ-ONLY now: the first launch after tabs die takes
    /// the workspace's active tab out of the old dictionary and makes it
    /// the open document, so nobody boots to an empty desk.
    private static let legacyKey = "desk.tabs.v1"

    /// The workspace whose document is on the desk. 0 = "All".
    private(set) var workspaceId: UInt64 = 0

    private var persistKey: String { WorkspaceModel.tabsKey(workspaceId) }

    // ---- the plane -------------------------------------------------

    /// This tab is being used, now. The ONE place a tab's clock is set.
    func touch(_ tabId: UUID) {
        guard let i = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[i].lastUsed = Civil.nowStamp()
        persist()
    }

    /// The tabs the grid shows. Inactive tabs are NOT removed from
    /// `tabs` — they stay in the one array, so closing, de-duplicating,
    /// pruning and the saved plane all keep working on the whole set, and
    /// only what is DISPLAYED narrows.
    ///
    /// The active tab is never inactive, which guarantees this is
    /// non-empty whenever `tabs` is — and therefore that an empty desk
    /// means "no tabs at all", not "none you looked at lately".
    var liveTabs: [DeskTab] {
        let now = Civil.nowStamp()
        return tabs.filter {
            $0.id == activeTabId || !LivTabs.isInactive($0.lastUsed, now: now)
        }
    }

    /// Untouched long enough to be out of the way. Most recently used
    /// first, so the shelf reads newest-stale to oldest.
    var inactiveTabs: [DeskTab] {
        let now = Civil.nowStamp()
        return tabs
            .filter { $0.id != activeTabId && LivTabs.isInactive($0.lastUsed, now: now) }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    /// Close every inactive tab at once. Safe without a confirmation and
    /// without an undo: a tab is device state, so this writes nothing to
    /// the box — every note is still there, in search, in Everything, in
    /// its workspace.
    func closeInactive() {
        for tab in inactiveTabs { close(tab.id) }
    }

    /// Activate a tab. Every activation path funnels here.
    ///
    /// The `‹ ›` history keys did NOT come back with the rest: they
    /// stepped through per-launch tab UUIDs, greyed out as tabs closed,
    /// and were never persisted. The labelled back at the top of a
    /// document, over the durable `returns` stack, replaced them and is
    /// better (design/tabs.md).
    func focus(_ tabId: UUID) {
        // Stamp FIRST and unconditionally: re-opening the tab you are
        // already on is still using it, and the early return below would
        // otherwise let the active tab age out from under you.
        touch(tabId)
        guard tabId != activeTabId else { return }
        endEditing()
        activeTabId = tabId
        if inspectorShown {
            withAnimation(LivMotion.nav) { inspectorShown = false }
        }
    }

    /// Closing the last tab leaves the desk empty — and an empty desk is
    /// empty: a hint, and the `+` that ends it.
    func close(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        endEditing()
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

    /// Old saved planes may hold task or event ids from before records
    /// became cards. A record cannot be a tab, so those close quietly the
    /// first time the box says what they are (owner, 2026-08-08).
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
    /// active one, so the shelf can be seen and photographed today.
    func backdateTabsForRehearsal(days: Int) {
        let old = Civil.stamp(day: Civil.addDays(Civil.todayDay(), -days), hhmm: 900)
        for i in tabs.indices where tabs[i].id != activeTabId {
            tabs[i].lastUsed = old - Int64(i)
        }
        persist()
        objectWillChange.send()
    }

    /// Self-check only: install a known set. `tabs` is private(set) so the
    /// suite cannot reach it, and opening the setter to everyone is how a
    /// second file starts mutating the plane.
    func replaceTabsForSelfCheck(_ fresh: [DeskTab]) {
        tabs = fresh
        activeTabId = fresh.last?.id
    }

    /// LAUNCH ON TODAY (owner, 2026-08-18). Resuming the last document
    /// is what a notes app does; planning is what this one is for, so
    /// the day is where it opens. Nothing is lost — the document you
    /// were in is still loaded, one tap away as the first row of Docs.
    init() {
        let defaults = UserDefaults.standard
        workspaceId = UInt64(defaults.integer(forKey: WorkspaceModel.activeKey))
        let (restored, active) = Self.loadPlane(workspaceId)
        tabs = restored
        activeTabId = active ?? restored.last?.id
        state = .today
    }

    /// The workspace's document: the new key, else one taken out of the
    /// old tab plane (its active tab, or the last one saved).
    /// One plane's saved set. Entity ids only — a tab's UUID is minted
    /// fresh every launch, so the entity is the only identity a saved
    /// plane actually has.
    ///
    /// **And the four days without tabs are folded in here.** Between
    /// 2026-08-18 and 2026-08-22 the desk held one document under its own
    /// key, while the old plane sat beside it untouched. Restoring the
    /// plane alone would bring back a four-day-old tab set and silently
    /// drop the note actually in use, so the live document is added and
    /// focused, and its key is then removed — one truth, once.
    private static func loadPlane(_ workspace: UInt64) -> ([DeskTab], UUID?) {
        let defaults = UserDefaults.standard
        let now = Civil.nowStamp()
        var restored: [DeskTab] = []
        var active = -1

        let stored =
            defaults.dictionary(forKey: WorkspaceModel.tabsKey(workspace))
            ?? (workspace == 0 ? defaults.dictionary(forKey: legacyKey) : nil)
        if let stored {
            let ids = (stored["ids"] as? [String] ?? []).compactMap { UInt64($0) }
            // A plane saved before tabs had clocks counts as used NOW.
            // Reading a missing stamp as "never used" would sweep every
            // tab you own on the first launch after the upgrade.
            let used = stored["used"] as? [String: Int] ?? [:]
            restored = ids.map {
                DeskTab(
                    id: UUID(), content: .entity($0),
                    lastUsed: used[String($0)].map(Int64.init) ?? now)
            }
            active = stored["active"] as? Int ?? -1
        }

        var activeId = restored.indices.contains(active) ? restored[active].id : nil
        let docKey = WorkspaceModel.docKey(workspace)
        if let saved = defaults.object(forKey: docKey) as? NSNumber, saved.uint64Value != 0 {
            let live = saved.uint64Value
            if let already = restored.first(where: { $0.content == .entity(live) }) {
                activeId = already.id
            } else {
                let tab = DeskTab(id: UUID(), content: .entity(live), lastUsed: now)
                restored.append(tab)
                activeId = tab.id
            }
            defaults.removeObject(forKey: docKey)
        }
        return (restored, activeId)
    }

    private func persist() {
        var ids: [String] = []
        var used: [String: Int] = [:]
        var active = -1
        // EVERY tab, inactive ones included. `active` indexes the array
        // being built here, so filtering any tab out would both point it
        // at the wrong tab and lose the inactive ones for good.
        for tab in tabs {
            guard case .entity(let entity) = tab.content else { continue }
            if tab.id == activeTabId { active = ids.count }
            ids.append(String(entity))
            used[String(entity)] = Int(tab.lastUsed)
        }
        UserDefaults.standard.set(
            ["ids": ids, "active": active, "used": used], forKey: persistKey)
    }

    /// Swap the workspace. The outgoing document is saved under ITS key
    /// first, so a switch is never a loss; the incoming one replaces it,
    /// and the way-back stack resets — it belonged to the other place.
    func adopt(workspace id: UInt64) {
        guard id != workspaceId else { return }
        persist()  // the OUTGOING key — persistKey still points at it
        workspaceId = id
        returns = []
        let (restored, active) = Self.loadPlane(id)
        tabs = restored
        activeTabId = active ?? restored.last?.id
        switcherShown = false
        state = .notes
        setLibrary(false, animated: false)
        menu = nil
        inspectorShown = false
        settingsShown = false
        objectWillChange.send()
    }

    // MARK: going places

    /// The Go-to menu's one door. A state REPLACES the state you were in
    /// — states are roots, never children of each other — and Docs keeps
    /// whatever document was open, so "Notes" from the calendar puts you
    /// back in the note you were writing.
    func go(_ feature: Feature) {
        guard feature != state else { return }
        endEditing()
        returns = []
        withAnimation(LivMotion.nav) { state = feature }
        setLibrary(false)
        menu = nil
        chromeHomeAgain()
    }

    /// Up, out of a document, to the list of them. The state does not
    /// change: you were in Docs the whole time.
    /// **The tabs stay open.** Before the plane came back this cleared
    /// the one document slot; now it deselects, which is the same thing
    /// on screen and a different thing underneath — your tabs are where
    /// you left them.
    func showList() {
        endEditing()
        returns = []
        withAnimation(LivMotion.nav) { activeTabId = nil }
    }

    /// The labelled back at the top of a document: where it goes, or nil
    /// when there is nothing beneath (then the document's own way up is
    /// the list — see `DocumentBack`).
    var back: LivPlace? { returns.last }

    /// Take it. Pops one place; a document below is re-opened without
    /// pushing itself back on.
    func goBack() {
        guard let place = returns.popLast() else { return }
        endEditing()
        withAnimation(LivMotion.nav) {
            switch place {
            case .state(let feature):
                state = feature
                // No longer clears the document: leaving Notes for Today
                // does not close what you had open, because the plane is
                // Notes' own and Desk draws a feature body regardless.
            case .document(let id):
                state = .notes
                if let tab = tabs.first(where: { $0.content == .entity(id) }) {
                    focus(tab.id)
                } else {
                    let tab = DeskTab(
                        id: UUID(), content: .entity(id), lastUsed: Civil.nowStamp())
                    tabs.append(tab)
                    focus(tab.id)
                }
            }
        }
        menu = nil
    }

    /// Put the keyboard away and COMMIT what is in it. The title line
    /// commits on resign (EditorText's TitleDelegate) and the body's
    /// flush rides teardown, so a surface swap that skips this loses a
    /// rename typed a second earlier — a real hazard now that leaving a
    /// document happens on every state change (2026-08-18).
    private func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// A document that turns out to be a RECORD is not a document: it
    /// belongs in a card. Called once, on the first snapshot, because
    /// that is the first moment the shape of a saved id can be known.
    /// Called once, on the first snapshot — the first moment the box can
    /// say what a saved id IS.
    ///
    /// Two sweeps, and both wait for this moment on purpose. A record
    /// cannot be a tab, so tabs holding one close (owner, 2026-08-08).
    /// And a tab whose entity is not in the box at all is a card that can
    /// only ever say "this was deleted" — the plane restored on
    /// 2026-08-22 had 65 of them on a test device whose box had been
    /// rebuilt underneath it.
    ///
    /// The original rule was that missing ids drop LAZILY, "never an
    /// eager sweep against a box that may still be opening". This is not
    /// that sweep: the box has opened, which is the whole reason this
    /// function is called here and not in `init`.
    func dropRecordDocument() {
        pruneRecordTabs()
        let gone = tabs.filter {
            if case .entity(let id) = $0.content { return !knows(id) }
            return false
        }
        for tab in gone { close(tab.id) }
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

    /// Land a document on the desk. It REPLACES what was open (owner,
    /// 2026-08-18): there is one document surface, and the note you were
    /// in is one row down the list you came from.
    private func openDocument(_ entityId: UInt64) {
        endEditing()
        recordCard = nil
        guard entityId != openDoc else {
            // Already here — a reminder tap for the open note, say. Land
            // on it rather than pushing it onto its own way-back stack.
            surfaceCleanup()
            return
        }
        // Where the labelled back will go: the state you were in, or the
        // document you were reading before this one.
        let from: LivPlace = state == .notes && openDoc != nil
            ? .document(openDoc!) : .state(state)
        returns.append(from)
        if returns.count > 20 { returns.removeFirst(returns.count - 20) }
        state = .notes
        // Append or focus — the whole difference tabs make. Opening a
        // second note no longer replaces the first.
        if let existing = tabs.first(where: { $0.content == .entity(entityId) }) {
            focus(existing.id)
        } else {
            let tab = DeskTab(
                id: UUID(), content: .entity(entityId), lastUsed: Civil.nowStamp())
            tabs.append(tab)
            focus(tab.id)
        }
        switcherShown = false
        surfaceCleanup()
    }

    /// Everything an arrival closes. A tapped reminder routes here from
    /// anywhere, so leaving a cover up made the notification look ignored
    /// (audit, 2026-08-04).
    private func surfaceCleanup() {
        setLibrary(false)
        withAnimation(LivMotion.nav) {
            menu = nil
            inspectorShown = false
        }
        searchShown = false
        cameraShown = false
        settingsShown = false
        trashShown = false
        workspaceShown = false
    }

    /// `+`: the create MENU, sliding up over whatever you are looking at
    /// (owner, 2026-08-13). It never opens anything by itself — choosing
    /// something does — and it leaves the surface in front alone.
    func createSomething() {
        menu = createMenu?()
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
    /// How this closes. It hangs from the workspace button now (a top
    /// sheet in the hierarchy), so there is no sheet environment to
    /// dismiss — the presenter hands it the way out.
    var onClose: () -> Void

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
        VStack(alignment: .leading, spacing: 0) {
                // Making a FILTER shows the filter form and nothing else.
                // This sheet is the workspace switcher, and the form only
                // borrows it (standing rule 4: one form, one place) — but
                // a list of workspaces above a filter you are naming is
                // the wrong screen (owner, 2026-08-13).
                if !composingFilter {
                    // The SAME title and rows the `+` menu wears (owner,
                    // 2026-08-17: bigger text, simpler). This card used
                    // to draw its own smaller, denser list.
                    LivMenuTitle(text: "Workspace")
                    choice(
                        name: "All", active: workspaces.activeId == 0,
                        glyph: .workspaces, divided: false
                    ) {
                        choose(0)
                    }
                    ForEach(Array(workspaces.workspaces.enumerated()), id: \.element.id) { _, ws in
                        choice(
                            name: ws.display, active: workspaces.activeId == ws.id,
                            glyph: .workspace, emoji: ws.emoji, divided: true
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
                    LivMenuTitle(text: "New filter")
                    newFilterForm
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The ROWS carry their own 16pt inset, like the menu's; only the
        // forms below need the card's.
        .padding(.vertical, 4)
        // No .presentationDetents: it is not a sheet any more. It hangs
        // from the workspace button at the top (LivTopSheetHost), which
        // sizes itself to this content and scrolls only when it must.
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

    private func choose(_ id: UInt64, close: Bool = true) {
        workspaces.setActive(id)
        if close { onClose() }
    }

    /// One workspace to switch to. The row is the app's ONE row — the
    /// same one the `+` menu draws (LivMenuRow) — because a list of
    /// things to choose from should not look different depending on
    /// which card it is in (owner, 2026-08-17).
    ///
    /// The lens chips that used to sit under each name are gone with the
    /// smaller type they belonged to. A workspace's lens is still on
    /// screen where it acts: the filter chip in every view's header, and
    /// the filters in the menu.
    private func choice(
        name: String, active: Bool, glyph: LivGlyph,
        emoji: String? = nil, divided: Bool, action: @escaping () -> Void
    ) -> some View {
        LivMenuRow(
            label: name, glyph: glyph, emoji: emoji, selected: active, divided: divided,
            action: action)
    }

    private func addRow(_ label: String, action: @escaping () -> Void) -> some View {
        LivMenuRow(label: label, symbol: "plus", accent: true, divided: true, action: action)
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
        .padding(.horizontal, 16)
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
        .padding(.horizontal, 16)
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

    var body: some View {
        // GROUPS AS CARDS (owner's clips, 2026-08-20). ChatGPT's
        // settings, Obsidian's overflow sheet and Apple Notes' list all
        // group with a raised card and a quiet label ABOVE it, never
        // with a heading over a flat run of controls. The gap between
        // two cards says "different things" without a word.
        //
        // The sheet drops to `canvas` so the cards have a ground to
        // stand on — the elevation ramp already says this is what the
        // two steps are for; nothing here used them.
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: LivType.title, weight: .bold))
                    .foregroundStyle(LivTheme.text)
                    .padding(.horizontal, LivRow.cardInset + 4)
                    .padding(.top, 16)
                // What a person actually came here to change, first.
                LivCard(label: "Appearance") { appearanceRow.padding(12) }
                if box.snap?.assist != nil {
                    LivCard(label: "Suggestions") { assistRow.padding(12) }
                }
                LivCard(label: "Reminders") { notifyRows.padding(12) }
                LivCard(label: "Fields") { fieldsRow.padding(12) }
                // No Advanced drawer. It held the phone→desk handoff
                // (status, ledger, Ship now, the satellite path) and the
                // store's own facts, and it went with every other
                // advanced feature (owner, 2026-08-14): the friendly
                // ones come first. Nothing in the app can set a
                // satellite path now, so the handoff is off until it
                // gets a door someone would want to open.
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(LivTheme.canvas)
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

/// The app's ONE floating surface: Liquid Glass where the phone has it
/// (iOS 26), a material where it does not. The bar wears it, and so does
/// every button at the top of the screen (owner, 2026-08-17: "make all
/// top buttons have a liquid glass style like the bar").
///
/// Glass brings its own edge and shading, so nothing is stacked on top
/// of it — the border and drop shadow a solid capsule needed would read
/// as a second, duller rim. Below iOS 26 they come back, because a flat
/// material with no rim has no edge at all.
///
/// `tinted` is the ON state — the library door while the menu is open.
struct LivGlass<S: Shape>: ViewModifier {
    let shape: S
    var tinted = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // NOT `.interactive()`: that variant takes the touch for its
            // own press effect, and a button wearing it stops firing
            // (the library door, found live 2026-08-17).
            content.glassEffect(
                tinted ? .regular.tint(LivTheme.accent) : .regular, in: shape)
        } else {
            content
                .background(
                    tinted ? AnyShapeStyle(LivTheme.accent) : AnyShapeStyle(.ultraThinMaterial),
                    in: shape
                )
                .overlay(shape.stroke(LivTheme.border, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        }
    }
}

extension View {
    func livGlass<S: Shape>(in shape: S, tinted: Bool = false) -> some View {
        modifier(LivGlass(shape: shape, tinted: tinted))
    }

}

/// THE SOFT EDGE. Every surface runs under the clock now (owner,
/// 2026-08-17), so the top band fades from the ground colour to nothing:
/// without it a list scrolled to the top puts its words through the
/// time, and the glass controls lose their contrast.
///
/// It belongs to the SURFACE, not to the chrome — as its own layer in
/// the desk's stack it swallowed the library door's taps, whatever
/// `allowsHitTesting` said (found live). A view hands it to
/// `safeAreaInset`, which is also what reserves the room; the desk
/// overlays it on the words.
struct LivTopScrim: View {
    var body: some View {
        // Solid where the clock is, then a fade under the controls: a
        // plain two-stop gradient left words legible behind the time.
        LinearGradient(
            stops: [
                .init(color: LivTheme.canvas, location: 0),
                .init(color: LivTheme.canvas, location: 0.45),
                .init(color: LivTheme.canvas.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: LivRow.topInset)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - bottom bar

/// THREE KEYS: where you are, search, create (owner, 2026-08-18).
///
/// The state key NAMES the state you are in and opens the Go-to menu.
/// It sat in the left sidebar for two days (2026-08-17) and came back
/// here for a reason worth keeping: a drawer is the right home for what
/// you touch rarely — the workspace, filters, Settings — and the wrong
/// home for the thing you touch on every navigation, which also has to
/// be reachable from inside a document.
///
/// The history keys ‹ › are gone with the tabs they stepped through.
/// Going back is the labelled control at the top of a document, which
/// says where it will take you.
///
/// It is Safari's bar, deliberately: a floating capsule of glass that
/// the page passes under. That reverses "solid, never a blur" from
/// 2026-08-01 — the reason then was that a body reading through the bar
/// looked like a bug; Liquid Glass is the platform's own answer to
/// exactly that, and the owner asked for it by name.
///
/// It also gets out of the way: while the keyboard is up the bar is not
/// drawn at all (App.swift), because a row of navigation over a
/// half-typed sentence is noise.
struct BottomBar: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        // TWO PIECES, not one (owner, 2026-08-18, pointing at ClickUp):
        // navigation in a bar, and CREATE as its own object beside it.
        // Create is the only key here that is not navigation, and a
        // container it does not belong in is exactly the kind of quiet
        // wrongness the surface pass is for.
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                tabKey
                navButton("magnifyingglass", label: "Search") {
                    desk.searchShown = true
                }
                .frame(width: 52)
            }
            .padding(.leading, 6)
            .padding(.trailing, 2)
            .frame(height: 50)
            .livGlass(in: Capsule())

            Button {
                desk.createSomething()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(LivTheme.text)
                    .frame(width: 50, height: 50)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .livGlass(in: Circle())
            .accessibilityLabel("New")
        }
        .padding(.horizontal, 16)
    }

    /// WHERE YOU ARE, and the way anywhere else (owner, 2026-08-18: the
    /// ClickUp arrangement, after the sidebar proved to be the wrong
    /// home for something you touch on every navigation). It NAMES the
    /// state, so the bar answers "where am I" as well as "where to".
    ///
    /// Six states will not fit as six keys; one labelled key that opens
    /// the menu is two taps to anywhere — the same two the sidebar cost,
    /// with the difference that this one is on screen inside a document.
    /// THE TAB KEY, in the slot the state key used to hold.
    ///
    /// The views moved to the side panel on 2026-08-22, which freed this
    /// place — and freeing it is what let the bar gain a tab door without
    /// a fifth key or a second row. It still answers "where am I" with the
    /// view's own glyph; the panel now answers it in words.
    ///
    /// The count is of LIVE tabs, not all of them: a tab on the Inactive
    /// shelf is open but out of the way, and a key that counted them would
    /// disagree with the grid it opens.
    private var tabKey: some View {
        Button {
            desk.switcherShown = true
        } label: {
            HStack(spacing: 7) {
                LivIcon(glyph: desk.state.glyph, color: LivTheme.text, size: 19)
                Text("\(desk.liveTabs.count)")
                    .font(.system(size: LivType.body, weight: .medium).monospacedDigit())
                    .foregroundStyle(LivTheme.text)
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Tabs. \(desk.liveTabs.count) open in \(desk.state.title)")
    }

    private func navButton(
        _ icon: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: LivType.title, weight: .medium))
                .foregroundStyle(LivTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

}
