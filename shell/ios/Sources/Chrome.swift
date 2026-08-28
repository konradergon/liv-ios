// liv iOS — THE CHROME: `DeskModel`, the one state object every surface
// observes, and the furniture it wears.
//
// The body IS the desk (design/ios.md §6, revision 2); features are
// transient windows summoned over the whole chrome, bar included. This
// model is transient shell state — panels, covers, the record card, the
// menu, where you are — and it holds the tab planes without being them.
//
// WHAT IS NO LONGER HERE. On 2026-08-23 this file was 1,870 lines and
// standing rule 9 said to look for the seam. Five of them were found:
//   Plane.swift            the tab planes and their UserDefaults
//   Navigate.swift         the roster of places, and the way back
//   WorkspaceSwitch.swift  the workspace sheet and its form
//   Settings.swift         the gear's sheet
//   Bar.swift              the bottom bar
// The chrome kept the state object and the surfaces it owns; each of
// those kept a subject of its own. No behaviour moved with them.

import SwiftUI
import UIKit

/// The chrome's one state object: where you are, what is covering it,
/// and the one door for opening anything.
///
/// It OWNS the tab planes (`DeskPlanes`, Plane.swift) rather than being
/// them. Everything a surface asks the desk about a tab — `tabs`,
/// `activeTabId`, `openDoc`, `focus`, `close` — still answers here and
/// still means the CURRENT view's strip, so no caller learned what a
/// plane is; the storage and the tab arithmetic live in the type.
///
/// The doc comment this replaces described 2026-08-18, when tabs were
/// deleted and the desk held one document under its own key. The plane
/// came back on 2026-08-22 (design/tabs.md) and the comment did not.
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
    /// One plane per view (`DeskPlanes`, Plane.swift). The strip you see
    /// is the current view's, so every caller of `tabs` and `activeTabId`
    /// below keeps working and none of them had to learn what a plane is
    /// — the same trick that kept `Desk.swift` at zero changes when
    /// `openDoc` became derived.
    ///
    /// `private(set)` is the whole point of the value type: the planes
    /// are readable everywhere and movable only from this class.
    @Published private(set) var planes: DeskPlanes

    /// THE STRIP YOU SEE — the plane of the view you are standing in.
    var tabs: [DeskTab] { planes.tabs(in: state) }

    var activeTabId: UUID? { planes.activeTabId(in: state) }

    @Published var switcherShown = false

    /// The document on the desk — DERIVED from the active tab rather
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

    var activeTab: DeskTab? { planes.activeTab(in: state) }

    // MARK: positions — a tab in a view that is not Notes

    /// Where the active tab of `feature` is parked, in that view's own
    /// vocabulary (`Positions.swift`). `nil` means the plane has no tab
    /// yet and the view shows its root — which is what no tabs has always
    /// meant in Notes.
    func position(_ feature: Feature) -> String? { planes.position(feature) }

    /// Park the active tab at `token`. **Moving is what mints the tab**:
    /// a view whose plane is empty gets one here, so a user who never
    /// leaves a view's root never accumulates a tab they did not ask for.
    func park(_ feature: Feature, at token: String) { planes.park(feature, at: token) }

    /// Where the labelled back at the top of a document goes. The cap is
    /// on the type (`LivReturns`, Navigate.swift): a chain of link jumps
    /// is a stack, not a diary.
    @Published private(set) var returns = LivReturns()
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
        return panelDrag!.progress(Self.travel(which))
    }

    /// HOW FAR A PANEL TRAVELS. The library stops short of the right edge
    /// now (owner, 2026-08-23: "Panel should not be full screen!"), so its
    /// travel is its own width and no longer the screen's. The properties
    /// panel is unchanged — it is about the note in front of it and still
    /// stands edge to edge (owner, 2026-08-15).
    ///
    /// ONE function, because the panel's offset, the desk's shift and the
    /// drag's settle all have to agree to the pixel. They read
    /// `UIScreen.main.bounds.width` from four places before this, which is
    /// four chances to disagree (standing rule 4).
    static func travel(_ which: PanelDrag.Which) -> CGFloat {
        which == .library ? LivPanel.width : LivScreen.width
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
        panelProgress(.library) * Self.travel(.library)
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

    /// The workspace whose planes are on the desk. 0 = "All". The planes
    /// own it — every key they write is scoped by it.
    var workspaceId: UInt64 { planes.workspaceId }

    // ---- the plane (Plane.swift holds the arithmetic) ----------------

    /// This tab is being used, now.
    func touch(_ tabId: UUID) { planes.touch(tabId, in: state) }

    /// The tabs the grid shows — the current view's, inactive ones left
    /// out. Never empty while the plane has tabs: the active tab is never
    /// inactive, so an empty grid means "no tabs at all", not "none you
    /// looked at lately".
    var liveTabs: [DeskTab] { planes.live(in: state) }

    /// Untouched long enough to be out of the way, newest-stale first.
    func inactive(in feature: Feature) -> [DeskTab] { planes.inactive(in: feature) }

    var inactiveTabs: [DeskTab] { planes.inactive(in: state) }

    /// EVERY plane's shelf, in the declared view order, empty ones left
    /// out.
    ///
    /// **One attic, not six.** With a plane per view, a shelf that showed
    /// only the view you were standing in would hide five of them — a
    /// Calendar tab you stopped using in July would be invisible until
    /// you happened to open the Calendar. The grid above is the view you
    /// are in; the shelf is everything you have parked.
    var inactiveEverywhere: [(feature: Feature, tabs: [DeskTab])] {
        planes.inactiveEverywhere
    }

    var inactiveCount: Int { planes.inactiveCount }

    /// Close every inactive tab at once, in every view. Safe without a
    /// confirmation and without an undo: a tab is device state, so this
    /// writes nothing to the box — every note is still there, in search,
    /// in Everything, in its workspace.
    func closeInactive() {
        for (feature, parked) in planes.inactiveEverywhere {
            for tab in parked { close(tab.id, in: feature) }
        }
    }

    /// Activate a tab. Every activation path funnels here.
    func focus(_ tabId: UUID) {
        // Stamp FIRST and unconditionally: re-opening the tab you are
        // already on is still using it, and the early return below would
        // otherwise let the active tab age out from under you.
        planes.touch(tabId, in: state)
        guard tabId != activeTabId else { return }
        endEditing()
        planes.setActive(tabId, in: state)
        if inspectorShown {
            withAnimation(LivMotion.nav) { inspectorShown = false }
        }
    }

    /// Open a tab that lives in ANOTHER view. The shelf spans every
    /// plane, so tapping a card there has to take you to the view that
    /// card belongs to first — otherwise the tab would be focused
    /// somewhere you cannot see it.
    func focus(_ tabId: UUID, in feature: Feature) {
        if feature != state {
            endEditing()
            state = feature
        }
        focus(tabId)
    }

    func close(_ tabId: UUID) { close(tabId, in: state) }

    /// Closing the last tab leaves the desk empty — and an empty desk is
    /// empty: a hint, and the `+` that ends it.
    ///
    /// The keyboard is committed only when there is something to close,
    /// as it always was: a close that does nothing must not resign a
    /// field someone is typing in.
    func close(_ tabId: UUID, in feature: Feature) {
        guard planes.holds(tabId, in: feature) else { return }
        endEditing()
        planes.close(tabId, in: feature)
    }

    /// Called once, on the first snapshot — the first moment the box can
    /// say what a saved id IS. A record cannot be a tab (owner,
    /// 2026-08-08), and a tab whose entity the box has never heard of is
    /// a card that can only ever say "this was deleted". The sweep itself
    /// is the plane's (Plane.swift); the shapes are the desk's.
    /// **TWO guards, and the app spins at 100% CPU without either.**
    /// Found live on 2026-08-23 with a stack sample: the caller is
    /// `.onReceive(box.$snap…prefix(1))` written inline in `RootView`'s
    /// body, and an inline publisher is REBUILT every time that body
    /// runs — so `prefix(1)` means "the first value of this render's
    /// publisher", not "the first snapshot ever". It re-delivers on
    /// every render.
    ///
    /// That was survivable while the sweep only published when it
    /// actually removed something. It stopped being survivable when the
    /// plane moved into a `@Published` STRUCT: calling any `mutating`
    /// method on one publishes whether or not the method changed a
    /// single byte, so a no-op sweep still invalidated the view, which
    /// re-ran the body, which rebuilt the publisher, which swept again.
    ///
    /// So: `swept` makes "once" true, and the `hasStrangers` test keeps
    /// the mutating call — and its unconditional publish — off the path
    /// when there is nothing to do.
    func dropRecordDocument() {
        guard !swept else { return }
        swept = true
        guard planes.hasStrangers(shapeOf: shapeOf, knows: knows) else { return }
        planes.dropRecordsAndStrangers(shapeOf: shapeOf, knows: knows)
    }

    /// Not `@Published`: nothing draws it, and publishing it would be
    /// the very loop it exists to stop.
    private var swept = false

    /// Rehearsal only (`-desk.boot inactive`): age every tab except each
    /// plane's active one, so the shelf can be seen and photographed
    /// today.
    func backdateTabsForRehearsal(days: Int) {
        planes.backdate(days: days)
        objectWillChange.send()
    }

    /// Self-check only: a desk whose planes are nobody's.
    ///
    /// **Every verb on a plane writes through to UserDefaults**, so a
    /// suite built on a plain `DeskModel()` quietly rearranges the tabs of
    /// whoever ran it. The tabs suite did exactly that from the day it was
    /// written; it was invisible while there was one plane, and it
    /// surfaced the moment each view got its own — three fake tabs on
    /// Today, on a real device, after a run of the suites.
    static func scratchForSelfCheck() -> DeskModel {
        let desk = DeskModel()
        desk.adopt(workspace: DeskPlanes.scratchWorkspace)
        return desk
    }

    /// Self-check only: leave nothing behind.
    static func forgetScratchForSelfCheck() { DeskPlanes.forgetScratch() }

    /// Self-check only: install a known set. The planes are `private(set)`
    /// so the suite cannot reach them, and opening them to everyone is how
    /// a second file starts mutating the plane.
    func replaceTabsForSelfCheck(_ fresh: [DeskTab]) {
        planes.replaceForSelfCheck(fresh, in: state)
    }

    /// Self-check only: make a tab active WITHOUT stamping its clock.
    /// `focus` cannot serve here — it touches the tab, and the invariant
    /// under test is that a tab whose own clock is ancient still counts
    /// as live while it is the active one.
    func activateForSelfCheck(_ tabId: UUID?) {
        planes.setActive(tabId, in: state)
    }

    /// LAUNCH ON TODAY (owner, 2026-08-18). Resuming the last document
    /// is what a notes app does; planning is what this one is for, so
    /// the day is where it opens. Nothing is lost — the document you
    /// were in is still loaded, one tap away as the first row of Docs.
    init() {
        planes = DeskPlanes(
            workspace: UInt64(UserDefaults.standard.integer(forKey: WorkspaceModel.activeKey)))
        state = .today
    }

    /// Save every plane. Reachable from outside because the planes suite
    /// reopens the desk to prove that what is on screen and what is on
    /// disk agree.
    func persist() { planes.persist() }

    /// Swap the workspace. The outgoing planes are saved under THEIR keys
    /// first, so a switch is never a loss; the incoming ones replace them,
    /// and the way-back stack resets — it belonged to the other place.
    func adopt(workspace id: UInt64) {
        guard id != workspaceId else { return }
        planes.adopt(workspace: id)
        returns.clear()
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
        returns.clear()
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
        returns.clear()
        withAnimation(LivMotion.nav) { planes.setActive(nil, in: state) }
    }

    /// Where `‹` on the bar would take you, or nil when there is nothing
    /// beneath. The labelled version that sat at the top of a document is
    /// gone (owner, 2026-08-24); the bar is the one door.
    var back: LivPlace? { returns.last }

    /// WHERE YOU ARE STANDING, as one value. Both legs of the history
    /// need it and `openDocument` computed it inline; three copies of
    /// one answer is how they start to disagree (standing rule 4).
    var here: LivPlace {
        state == .notes && openDoc != nil ? .document(openDoc!) : .state(state)
    }

    /// The next place `›` would take you, or nil — which is most of the
    /// time, and is why the key spends most of its life dimmed.
    var forward: LivPlace? { returns.next }

    /// Take it. Pops one place; a document below is re-opened without
    /// pushing itself back on, and where you LEFT becomes the forward step.
    func goBack() {
        guard let place = returns.stepBack(from: here) else { return }
        land(place)
    }

    func goForward() {
        guard let place = returns.stepForward(from: here) else { return }
        land(place)
    }

    /// The one arrival. Back and forward differ only in which stack they
    /// take from — where they put you is the same code.
    private func land(_ place: LivPlace) {
        endEditing()
        withAnimation(LivMotion.nav) {
            switch place {
            case .state(let feature):
                state = feature
                // Leaving Notes for Today does not close what you had
                // open: the plane is Notes' own and Desk draws a feature
                // body regardless.
            case .document(let id):
                state = .notes
                focus(planes.open(entity: id, in: .notes))
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
        returns.push(here)
        state = .notes
        // Append or focus — the whole difference tabs make. Opening a
        // second note no longer replaces the first.
        focus(planes.open(entity: entityId, in: .notes))
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

    /// The switcher's new-tab door.
    ///
    /// **In Notes it is the create menu**, because a tab there holds a
    /// document and a new tab needs a document to hold. In every other
    /// view a tab is a position, so a new one simply opens at the view's
    /// root and the user moves it where they want.
    func newTab() {
        guard state != .notes else {
            createSomething()
            return
        }
        planes.openRoot(in: state)
    }

    /// `+`: the create MENU, sliding up over whatever you are looking at
    /// (owner, 2026-08-13). It never opens anything by itself — choosing
    /// something does — and it leaves the surface in front alone.
    func createSomething() {
        menu = createMenu?()
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
