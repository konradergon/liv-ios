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

    /// WHERE THE CURRENT TRAVEL BEGAN — the offset the scroll last
    /// turned around at. The distance from here is what the threshold
    /// measures, so it only moves on a REVERSAL.
    ///
    /// It used to be clamped to within `chromeThreshold` of the live
    /// offset on every sample, which meant it could never be more than
    /// the threshold behind — so `y > anchor + threshold` was false by
    /// construction on any smooth scroll, and the chrome only ever
    /// retired when one geometry sample happened to jump the whole 44pt
    /// at once. Measured on the Calendar, 2026-09-07: a swipe produced
    /// 49 callbacks ending at y=795 and the chrome never moved.
    private var chromeAnchor: CGFloat = 0

    /// Which way the last sample was going, so a turn can be spotted.
    private var chromeDescending = true

    /// How far you must scroll before the chrome agrees you meant it.
    /// Small enough to feel immediate, large enough that the rubber-band
    /// at the end of a list does not flap it.
    private let chromeThreshold: CGFloat = 44

    /// The band at the top of a list where the chrome is ALWAYS there.
    /// Arriving at a surface must never be the state where its
    /// furniture is missing.
    private let chromeHome: CGFloat = 40

    /// One scroll offset, in points from the content's top.
    ///
    /// HYSTERESIS FROM THE LAST TURN, not from the last sample. Scroll
    /// down `chromeThreshold` from wherever you last changed direction
    /// and the chrome goes; scroll back up as far and it returns. Near
    /// the top it is always home, whatever the direction.
    func scrolled(to y: CGFloat) {
        guard Date() >= chromeSettled else { return }
        // The band has just finished moving: this sample is the first
        // honest one, so measure from HERE rather than from the number
        // the animation left behind.
        if lastScroll != y, chromeSettled != .distantPast {
            chromeSettled = .distantPast
            chromeAnchor = y
            lastScroll = y
            return
        }
        if y <= chromeHome {
            chromeAnchor = y
            chromeDescending = true
            setChrome(away: false)
            return
        }
        // A turn re-bases the measurement, so coming back costs the same
        // as going did — and so a long smooth scroll in one direction
        // keeps measuring from where it started.
        let descending = y >= lastScroll
        if descending != chromeDescending {
            chromeDescending = descending
            chromeAnchor = lastScroll
        }
        lastScroll = y
        if descending {
            if y > chromeAnchor + chromeThreshold { setChrome(away: true) }
        } else {
            if y < chromeAnchor - chromeThreshold { setChrome(away: false) }
        }
    }

    /// The previous sample, for spotting the turn.
    private var lastScroll: CGFloat = 0

    /// WHILE THE BAND IS MOVING, THE OFFSET IS THE BAND'S, NOT THE
    /// FINGER'S. Retiring the chrome collapses the top inset, and that
    /// collapse ANIMATES — so for the length of the animation every
    /// scroll sample carries a slice of the inset's own travel. The
    /// decision would then be reading its own output: traced on the
    /// Calendar (2026-09-07) as 909 / 932 / 854 / 802 / 879 / 931 with
    /// the doors flickering in and out on every frame.
    ///
    /// A constant correction cannot fix this, because the inset passes
    /// through every value in between. Ignoring the samples until the
    /// motion settles can, and costs nothing: nobody decides to reverse
    /// a scroll within a fifth of a second of starting it.
    private var chromeSettled: Date = .distantPast

    /// Back on screen, unconditionally — leaving a surface, opening a
    /// menu, anything that is not reading.
    func chromeHomeAgain() {
        chromeAnchor = 0
        lastScroll = 0
        chromeDescending = true
        chromeSettled = .distantPast
        setChrome(away: false)
    }

    private func setChrome(away: Bool) {
        guard away != chromeAway else { return }
        chromeSettled = Date().addingTimeInterval(LivMotion.navSeconds + 0.08)
        withAnimation(LivMotion.nav) { chromeAway = away }
    }

    /// WHICH STATE YOU ARE IN. The bar's key names it and the Go-to menu
    /// changes it; there is no "no state". `init` overwrites this with
    /// Today, which is where the app launches; the declaration needs a
    /// value and the first view in the panel's order is the honest one.
    @Published var state: Feature = .today

    /// IS A DOCUMENT LYING ON THE DESK. **The desk's own state**, beside
    /// `state` rather than borrowed from it (2026-09-10,
    /// design/navigation-study.md §4.3).
    ///
    /// Until now a document rendered only while `state == .notes`, so
    /// opening a note from Today MOVED you to Notes. That one borrow is
    /// what made Notes mean three things at once — a peer view, the list
    /// of every note, and the only surface a document could be drawn on —
    /// and it is what the owner kept hitting from the other end: the lit
    /// panel row said Notes when the note came from Today, and `‹` out of
    /// a note opened off the Notes list did nothing at all (it landed on
    /// `.state(.notes)`, which is where you already were, with the
    /// document still on top).
    ///
    /// With the desk holding its own answer, the view underneath a
    /// document is the view you opened it from, and laying the document
    /// down uncovers it. `state` never changes when a document opens.
    @Published private(set) var shown = false

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
    var tabs: [DeskTab] { planes.tabs }

    var activeTabId: UUID? { planes.activeTabId }

    @Published var switcherShown = false

    /// The document on the desk — DERIVED from the active tab rather
    /// than stored beside it.
    ///
    /// This one line is why `Desk.swift` needed no changes at all: every
    /// existing caller of `openDoc` keeps working, and the tab plane
    /// became the single place the answer lives. Two slots holding the
    /// same fact is how they start to disagree.
    /// The document ON SCREEN, not merely the one the desk has active.
    ///
    /// The guard is load-bearing since the desk went app-wide
    /// (2026-08-28): one desk keeps its active tab wherever you go, which
    /// is the point of it, so "there is an active tab" is not "you are
    /// looking at it" — without the guard `goBack()` out of a note
    /// reported the note as still open (caught by `-places.selfcheck`).
    ///
    /// It used to be `state == .notes`, which answered the right question
    /// with the wrong fact and cost a view its own identity. `shown` is
    /// that fact, held where it belongs.
    var openDoc: UInt64? {
        guard shown, case .entity(let id)? = activeTab?.content else { return nil }
        return id
    }

    var activeTab: DeskTab? { planes.activeTab }

    // MARK: positions — where a view was left

    /// Where `feature` is parked, in that view's own vocabulary
    /// (`Positions.swift`). `nil` means it has never been moved and the
    /// view shows its root.
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
    /// ANY OTHER CARD A SURFACE PUTS UP over itself — the calendar's day
    /// picker is the first, and the reason this exists.
    ///
    /// A COUNTER, NOT A FIFTH FLAG. Every name above was added to
    /// `deskInFront` one at a time, each after the same bug reached the
    /// owner: a drag near the bezel latches a panel behind whatever is
    /// covering the desk, and every touch move then republishes
    /// `panelDrag` and re-renders the surface underneath. The list is
    /// the smell — a surface that puts up a card should not have to get
    /// its name added here, so it raises this instead and any number of
    /// them can be up at once.
    @Published var cards = 0
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
    /// Make the thing the surface in front of you HOLDS, with no menu:
    /// a task in Tasks, an event on the day Calendar is showing, a note
    /// everywhere else (owner, 2026-08-28 — note creation was two taps
    /// by every route, including the one you take most).
    ///
    /// The menu is still there, on a long press. This inverts the cost:
    /// the common thing is one tap and the exception is a tap and a
    /// hold, where before everything cost two.
    ///
    /// It is not a new axis. Creating already belongs to where you
    /// stand — a capture in a filtered workspace inherits that
    /// workspace's cells (`WorkspaceModel.stamp`) — so this extends
    /// "where you are decides the cells" to "where you are decides the
    /// kind".
    var createHere: (() -> Void)?

    /// Make one note, no menu. `newTab` in the switcher grid uses this:
    /// every card in that grid is a document, so asking "note, task,
    /// event, file or scan?" is a question with one sensible answer
    /// (owner, 2026-08-28).
    var newNote: (() -> Void)?
    /// A catch from OUTSIDE with the text already in hand —
    /// `liv://capture?text=…`. Wired by DeskHost beside `newNote`, and
    /// parked by `Routes` on a cold launch the same way (2026-09-09).
    var catchText: ((String) -> Void)?
    /// The library being dragged: whether the drag OPENS or CLOSES it,
    /// and the finger's travel so far. It lives on the MODEL because the
    /// bottom bar and the pill, which travel with the desk, are drawn by
    /// RootView, one level up.
    ///
    /// IT USED TO NAME WHICH PANEL. There were two — the library on the
    /// leading edge and the note's properties on the trailing one — and
    /// every member here had a `which == .library ? … : …` in it for the
    /// mirror image. The properties became a card on 2026-08-29 (owner:
    /// "maybe card everywhere. start with one"), so the enum had one
    /// case left and every ternary had one live branch. A one-case enum
    /// is a fork in the road with a wall down one side.
    struct PanelDrag: Equatable {
        let opening: Bool
        var amount: CGFloat = 0

        /// Where the drag started from: 0 for an opening drag, 1 for a
        /// closing one.
        var base: CGFloat { opening ? 0 : 1 }

        /// 0 = fully off screen, 1 = fully in. The library comes from the
        /// left, so rightward travel is toward.
        func progress(_ width: CGFloat) -> CGFloat {
            guard width > 0 else { return base }
            return min(1, max(0, base + amount / width))
        }

        /// The travel that would land the panel exactly at `target`.
        func amount(for target: CGFloat, width: CGFloat) -> CGFloat {
            (target - base) * width
        }
    }

    /// Which panel the finger is currently dragging. nil = none.
    @Published var panelDrag: PanelDrag?

    /// WHERE A SURFACE PAGES SIDEWAYS ON ITS OWN, in window coordinates.
    ///
    /// The panel is dragged in from anywhere (owner, 2026-08-08), which
    /// is right everywhere except on top of something that already means
    /// something by a sideways drag. The calendar's month grid is the
    /// only such place in the app; it publishes its frame here and the
    /// window recognizer refuses to start inside it.
    ///
    /// NOT `@Published`: the recognizer reads it through a closure at
    /// touch time, and publishing it would re-render the desk every time
    /// the grid's frame settled.
    var pagerZone: CGRect = .zero

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
    /// (2026-09-07: `cards` closes the list. The owner reported the same
    /// lag a second time — *"the picker that comes up when you select
    /// date title in calendar. It is low fps and laggy"* — and the cause
    /// was the same mechanism reached through a door this list did not
    /// know about. The `pagerZone` veto added on 2026-08-31 could not
    /// help: `PanelDrag`'s edge escape returns true before the veto is
    /// consulted, and the grid is padded only 16pt, so a sideways drag
    /// on the Monday or Sunday column near the bezel latched anyway.)
    var deskInFront: Bool {
        !searchShown && !cameraShown && !settingsShown
            && !workspaceShown && cards == 0
    }

    /// How far IN the library is: 0 fully off screen, 1 fully home. ONE
    /// answer, because three things read it — the panel's own offset,
    /// the desk's travel, and the doors' fade — and a pixel of
    /// disagreement between them is visible.
    var panelProgress: CGFloat {
        guard let drag = panelDrag else { return libraryShown ? 1 : 0 }
        return drag.progress(Self.travel)
    }

    /// HOW FAR THE PANEL TRAVELS. It stops short of the right edge
    /// (owner, 2026-08-23: "Panel should not be full screen!"), so its
    /// travel is its own width and not the screen's.
    ///
    /// ONE value, because the panel's offset, the desk's shift and the
    /// drag's settle all have to agree to the pixel. They read
    /// `UIScreen.main.bounds.width` from four places before this, which is
    /// four chances to disagree (standing rule 4).
    static var travel: CGFloat { LivPanel.width }

    /// How far the desk stands aside. The LIBRARY is a PLACE — the app's
    /// primary menu — so it and the surface in front are one horizontal
    /// strip: the menu is parked off the left edge, everything else is
    /// parked to its right, and going between them is travel. Opening the
    /// menu pushes the surface right; it waits there while you choose
    /// (owner, 2026-08-17: "make the left panel parked on the right and
    /// have you move to / from it").
    ///
    /// NOTHING ELSE PUSHES IT. The properties used to pull it the other
    /// way, and they are a card now — a card lies OVER the desk, so the
    /// desk does not move at all when it comes up. `drive.sh panel`
    /// measures exactly that, because a sheet that still shoves the desk
    /// is a panel in a sheet's clothes.
    var deskShift: CGFloat { panelProgress * Self.travel }

    /// How far the panel is out, 0…1 — read by the desk's mask, its
    /// shadow, and the wash that takes its touches.
    var panelOut: CGFloat { panelProgress }

    /// Is the note's properties CARD up? It was a panel on the trailing
    /// edge until 2026-08-29 (owner: "maybe card everywhere. start with
    /// one") and it is a sheet now, like the task and event cards beside
    /// it — so this no longer takes part in any panel arithmetic. It is
    /// reset on every tab move: metadata is a visit, not a mode.
    @Published var inspectorShown = UserDefaults.standard.bool(forKey: "desk.boot.inspector")
    /// The open document's version history, as a card (2026-09-09). Same
    /// shape as the properties card: a system sheet hosted by RootView,
    /// gated on `openDoc`, reset wherever the inspector is.
    @Published var historyShown = false

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
    func touch(_ tabId: UUID) { planes.touch(tabId) }

    /// The tabs the grid shows — the current view's, inactive ones left
    /// out. Never empty while the plane has tabs: the active tab is never
    /// inactive, so an empty grid means "no tabs at all", not "none you
    /// looked at lately".
    var liveTabs: [DeskTab] { planes.live }

    /// Untouched long enough to be out of the way, newest-stale first.
    var inactiveTabs: [DeskTab] { planes.inactive }

    var inactiveCount: Int { planes.inactiveCount }

    /// Close every inactive tab at once, in every view. Safe without a
    /// confirmation and without an undo: a tab is device state, so this
    /// writes nothing to the box — every note is still there, in search,
    /// in Everything, in its workspace.
    func closeInactive() {
        for tab in planes.inactive { close(tab.id) }
    }

    /// A tab picked from the switcher: onto the screen, not merely made
    /// active. One desk (2026-08-28) meant the switcher opens from every
    /// view, and its cards called `focus`, which sets the active tab and
    /// nothing else — so from Today the tap closed the grid and Today
    /// kept drawing, because a document then rendered only in Notes and
    /// `openDoc` was nil elsewhere by design. Nothing happened, visibly,
    /// until you walked to Notes (owner, 2026-09-09).
    ///
    /// A document goes through the one door every open goes through, so
    /// it lands on the desk with the way back pushed, exactly as a row in
    /// a list does. A position tab (pre-2026-08-28 planes, folded away on
    /// read) has no document to show, so picking one lays down whatever
    /// is on the desk and leaves you in the view.
    func show(_ tab: DeskTab) {
        switch tab.content {
        case .entity(let id): openDocument(id)
        case .position:
            layDown()
            focus(tab.id)
        }
    }

    /// Activate a tab. Every activation path funnels here.
    ///
    /// Activation is NOT arrival: this leaves `state` and `shown` alone,
    /// so a caller that wants the tab on screen goes through `show` (from
    /// the switcher) or `open` (from anywhere else).
    func focus(_ tabId: UUID) {
        // Stamp FIRST and unconditionally: re-opening the tab you are
        // already on is still using it, and the early return below would
        // otherwise let the active tab age out from under you.
        planes.touch(tabId)
        guard tabId != activeTabId else { return }
        endEditing()
        planes.setActive(tabId)
        if inspectorShown {
            withAnimation(LivMotion.nav) { inspectorShown = false }
        }
    }

    /// Closing the last tab leaves the desk empty — and an empty desk is
    /// empty: a hint, and the `+` that ends it.
    ///
    /// The keyboard is committed only when there is something to close,
    /// as it always was: a close that does nothing must not resign a
    /// field someone is typing in.
    func close(_ tabId: UUID) {
        guard planes.holds(tabId) else { return }
        endEditing()
        planes.close(tabId)
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
        planes.replaceForSelfCheck(fresh)
    }

    /// Self-check only: make a tab active WITHOUT stamping its clock.
    /// `focus` cannot serve here — it touches the tab, and the invariant
    /// under test is that a tab whose own clock is ancient still counts
    /// as live while it is the active one.
    func activateForSelfCheck(_ tabId: UUID?) {
        planes.setActive(tabId)
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
        // The other place's document does not come along. Where you are
        // STANDING does: a workspace is a different set of things, not a
        // different app, and being thrown to Notes on every switch was
        // only ever the old borrow showing through.
        shown = false
        setLibrary(false, animated: false)
        menu = nil
        inspectorShown = false
        historyShown = false
        settingsShown = false
        objectWillChange.send()
    }

    // MARK: going places

    /// THE ONE DOOR TO A VIEW — the panel's rows, the Go-to menu, a
    /// `liv://` link that names a view, the rehearsal flags. A state
    /// REPLACES the state you were in (states are roots, never children
    /// of each other) and it LAYS THE DOCUMENT DOWN, so the view you
    /// named is the view you get.
    ///
    /// This absorbed `goToRoot` on 2026-09-10. That verb existed to
    /// reconcile two answers to "am I in a document" — the panel had one
    /// branch for the view you were already in and another for arriving
    /// from elsewhere, and the same row landed on the list or in a note
    /// depending on state the row does not show (owner, 2026-09-09:
    /// *"sometimes when selecting Notes from the panel it gets you to an
    /// open note instead of showing the list"*). With `shown` there is
    /// only one answer to reconcile, so there is only one door.
    ///
    /// A POSITION SURVIVES, A DOCUMENT DOES NOT. The Calendar's month and
    /// Today's day are where you left a tool — a scroll position, still
    /// that view. A document is a different SURFACE over it.
    ///
    /// The note is not lost or closed: it is still on the desk, and the
    /// bar's numbered key opens the switcher that lands you back on it
    /// from any view (rev 58).
    ///
    /// The guard reads "nothing to do": naming the view you are standing
    /// in with nothing over it. With a document over it there is plenty
    /// to do — that tap is how you get out.
    /// `at` parks the view at a position on the way in (`LivPosition`),
    /// for a caller that means a PLACE INSIDE a view rather than the view
    /// — `liv://notes` and the `-desk.boot notes` flag, which since
    /// 2026-09-10 mean Everything's Notes lens. Parked before the
    /// animation, so the surface draws the right lens on its first frame
    /// instead of showing the old one and swapping.
    func go(_ feature: Feature, at position: String? = nil) {
        if let position { planes.park(feature, at: position) }
        guard feature != state || shown else { return }
        endEditing()
        returns.clear()
        withAnimation(LivMotion.nav) {
            state = feature
            shown = false
        }
        setLibrary(false)
        menu = nil
        chromeHomeAgain()
    }

    /// LAY THE DOCUMENT DOWN — the desk goes back to showing the view you
    /// are standing in, whichever one that is.
    ///
    /// **The tabs stay open**, and so does the ACTIVE one. This is what
    /// is on SCREEN, not what is on the desk: the note you were reading
    /// is one tap away on the bar's numbered key. Was `showList`, which
    /// deselected the tab as well — a second fact to keep in step, for no
    /// visible difference.
    ///
    /// The way back goes with it, as it does on every deliberate move:
    /// you asked for the view, so `‹` is not a way back into the note.
    /// `go` says these same three lines rather than calling this, because
    /// `state` has to change inside the SAME animation as `shown` or the
    /// old surface slides out while the new one is already drawn.
    func layDown() {
        guard shown else { return }
        endEditing()
        returns.clear()
        withAnimation(LivMotion.nav) { shown = false }
    }

    /// Where `‹` on the bar would take you, or nil when there is nothing
    /// beneath. The labelled version that sat at the top of a document is
    /// gone (owner, 2026-08-24); the bar is the one door.
    var back: LivPlace? { returns.last }

    /// WHERE YOU ARE STANDING, as one value. Both legs of the history
    /// need it and `openDocument` computed it inline; three copies of
    /// one answer is how they start to disagree (standing rule 4).
    var here: LivPlace {
        if let id = openDoc { return .document(id) }
        return .state(state)
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
                // Stepping back out of a document does not CLOSE it —
                // the desk keeps it, and stepping forward resumes it. It
                // stops being `openDoc` because it is no longer on
                // screen; the tab is still there.
                //
                // Laying it down is the whole of what changed here: this
                // used to set `state` alone, so `‹` out of a note opened
                // off the Notes list landed on `.state(.notes)` — where
                // you already were, with the note still on top — and did
                // nothing at all.
                shown = false
            case .document(let id):
                // The view underneath is whatever it was. A document is
                // a surface over a view now, not a view of its own.
                shown = true
                focus(planes.open(entity: id))
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
        // Where the labelled back will go: the view you were in, or the
        // document you were reading before this one.
        returns.push(here)
        // ONTO the view you are standing in, which does not change. The
        // panel's lit row keeps saying Today while you read a note you
        // opened from Today, and `‹` puts you back on Today's list of
        // rows rather than on Notes (2026-09-10).
        shown = true
        // Append or focus — the whole difference tabs make. Opening a
        // second note no longer replaces the first.
        focus(planes.open(entity: entityId))
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
            historyShown = false
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
    /// A NEW TAB IS A NEW NOTE, from anywhere.
    ///
    /// It used to branch: a note in Notes, and `openRoot` — a second copy
    /// of the view you were in — everywhere else. That branch is what
    /// put three Todays in the switcher. A tab holds a document; there is
    /// nothing else to open.
    func newTab() { newNote?() }

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
/// NO ON STATE, and that is the decision rather than an omission. This
/// said "`tinted` is the ON state — the library door while the menu is
/// open" until 2026-09-07, and it had not been true since 2026-08-28:
/// the door turning accent was called amateur, and it was also the
/// wrong idea — a tint says "selected", and a door standing open is not
/// a selection. The door says it is open by WIDENING PanelMark's
/// column (`Glyph.swift`). The `tinted` flag itself outlived that by
/// ten days, with both of its arms unreachable and a comment insisting
/// they were live.
struct LivGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // NOT `.interactive()`: that variant takes the touch for its
            // own press effect, and a button wearing it stops firing
            // (the library door, found live 2026-08-17).
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(LivTheme.border, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        }
    }
}

extension View {
    func livGlass<S: Shape>(in shape: S) -> some View {
        modifier(LivGlass(shape: shape))
    }
}

/// "A CARD IS UP OVER THIS SURFACE" — raised for as long as the view is
/// on screen, released when it leaves. (Named `LivOverDesk` because
/// `LivCard` is already the app's raised-panel container in Rows.swift;
/// the modifier that applies it is `livCard(while:)`.)
///
/// It exists so a surface that presents a sheet does not have to get its
/// own name added to `DeskModel.deskInFront`. Four names were added
/// there one at a time, each after the same bug reached the owner: the
/// panel recognizer lives on the WINDOW, so it sees touches through
/// anything that is merely drawn on top, latches a panel behind it, and
/// then republishes on every touch move while the surface underneath
/// re-renders.
///
/// The count is raised and lowered rather than set, so two cards at once
/// cannot have the first one to close hand the desk back early.
/// APPLIED TO THE PRESENTING VIEW, not to the sheet's content, and it
/// takes the flag that presents it. A `.sheet`'s content is a separate
/// presentation with its own environment root — which is why every
/// sheet in this app hands its `environmentObject` in by hand — so a
/// modifier inside one cannot be trusted to find the desk. The
/// presenter always can.
struct LivOverDesk: ViewModifier {
    let up: Bool
    @EnvironmentObject var desk: DeskModel

    func body(content: Content) -> some View {
        content
            .onChange(of: up) { _, now in
                desk.cards = max(0, desk.cards + (now ? 1 : -1))
            }
            // A surface torn down with its card still up must not leave
            // the count raised — the desk would never come back.
            .onDisappear { if up { desk.cards = max(0, desk.cards - 1) } }
    }
}

extension View {
    /// Hold the desk's recognizer off while `up` is true.
    func livCard(while up: Bool) -> some View { modifier(LivOverDesk(up: up)) }
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

// THERE IS NO BOTTOM SCRIM. One lived here for a day: a fade to the
// ground under the floating bar, so a list dissolved into the page
// instead of being read through the capsule. The owner looked at it and
// said no (2026-09-05: "remove the bottom fade. just ugh"), which is the
// end of it — a soft edge at the top is there because words genuinely
// run under the clock, and the bar has no such problem to solve.

struct LivTopScrim: View {
    /// Does chrome float over this surface? The library door does on the
    /// desk, so the fade runs the full chrome row and the words stay
    /// legible under it. Nothing floats over the panel, and covering a
    /// chrome row it has not got pushed its first line a sixth of the
    /// way down (owner, 2026-08-28: "a huge cut-off that needs to go").
    ///
    /// A BOOL, NOT A HEIGHT. The height is read INSIDE this body on
    /// purpose. Passed in from the call site of a `.safeAreaInset`, the
    /// safe area feeds itself: AttributeGraph reports a cycle and the
    /// surface stops repainting while its body keeps evaluating. That is
    /// the 2026-08-23 bug written three lines above the call in
    /// SidePanel, and it cost an hour again on 2026-08-28 — the panel
    /// simply never drew.
    var underChrome: Bool = true
    @EnvironmentObject private var desk: DeskModel

    /// THE BAND SHRINKS WHEN THE BUTTONS LEAVE (owner, 2026-09-07: "the
    /// area is where the panel button is and reserved for that, but is
    /// wasted space and looks odd when the buttons are dynamically
    /// hidden", with a photograph of the Calendar).
    ///
    /// This inset is what RESERVES the doors' band, and until now it
    /// reserved it unconditionally — so `livHidesChrome` slid the buttons
    /// up by `LivRow.topInset` (Desk.swift) and left an empty 52pt strip
    /// between the clock and the day's title. The buttons were gone and
    /// their room was not.
    ///
    /// When they are away only the clock needs covering. `chromeAway` is
    /// ordinary published state, not a safe-area read, so deriving the
    /// height from it cannot feed the cycle `LivBar.room` documents.
    /// Whether the band is the doors' full one, or the clock's alone.
    private var tall: Bool { underChrome && !desk.chromeAway }

    private var height: CGFloat { tall ? LivRow.topInset : LivSafeArea.top }

    var body: some View {
        // Solid where the clock is, then a fade under the controls: a
        // plain two-stop gradient left words legible behind the time.
        // SOLID WHERE THE CLOCK IS, then a fade under the controls. The
        // solid share is a FRACTION of the band, so when the band
        // collapses to the status bar alone the same 0.45 would stop
        // being solid a third of the way up the clock and a row
        // scrolling past showed through beside it (measured 2026-09-07:
        // a checkbox at 48/255 against a ground of 26). With no controls
        // to fade under, almost all of the band is the clock.
        LinearGradient(
            stops: [
                .init(color: LivTheme.canvas, location: 0),
                .init(color: LivTheme.canvas, location: tall ? 0.45 : 0.82),
                .init(color: LivTheme.canvas.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}
