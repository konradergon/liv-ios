// liv iOS — WHERE YOU ARE, and how you got there.
//
// The roster of places, one place you have been, the capped way back,
// the control that takes it, and the body each place draws. The first
// three moved here from Chrome.swift on 2026-08-23 (standing rule 9):
// they were the chrome's neighbours by accident, and they are this
// file's subject — the view that reads `desk.back` and the suite that
// pins it were already here.

import SwiftUI

// MARK: - the places

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

// MARK: - where you are

/// One place you have been: a state, or a document inside Docs. The
/// stack exists for ONE control — the labelled back at the top of a
/// document, which says where it will take you ("‹ Docs", "‹ Today",
/// "‹ Kitchen rebuild"). Device state, never a cell.
enum LivPlace: Equatable {
    case state(Feature)
    case document(UInt64)
}

/// The way back: a stack of places, with the cap ON THE TYPE.
///
/// A chain of link jumps is a stack, not a diary, so it forgets its
/// oldest step rather than growing without bound. The rule lived as two
/// lines inside `openDocument` before 2026-08-23; standing rule 3 says a
/// rule that matters lives in a type.
struct LivReturns: Equatable {
    /// The deepest chain anyone keeps. Twenty jumps is already further
    /// back than a person can name.
    static let cap = 20

    private var places: [LivPlace] = []
    /// WHERE BACK CAME FROM. The forward leg, added 2026-08-23 with the
    /// bar's `›` key. Obsidian draws that key permanently dead — that is
    /// literally what the reference measures — and shipping a control
    /// that can never work seemed worse than giving it the job every
    /// browser gives it.
    private var forwards: [LivPlace] = []

    var last: LivPlace? { places.last }
    var next: LivPlace? { forwards.last }
    var count: Int { places.count }
    var forwardCount: Int { forwards.count }

    /// A FRESH navigation, which ends any forward journey: you cannot go
    /// forward into a future you have just replaced. Every browser does
    /// this and a user would notice immediately if it did not.
    mutating func push(_ place: LivPlace) {
        cap(&places, adding: place)
        forwards = []
    }

    /// Back one step. `here` is where you are standing as you leave, and
    /// it becomes the place `›` returns to.
    mutating func stepBack(from here: LivPlace) -> LivPlace? {
        guard let place = places.popLast() else { return nil }
        cap(&forwards, adding: here)
        return place
    }

    mutating func stepForward(from here: LivPlace) -> LivPlace? {
        guard let place = forwards.popLast() else { return nil }
        cap(&places, adding: here)
        return place
    }

    mutating func clear() {
        places = []
        forwards = []
    }

    private func cap(_ stack: inout [LivPlace], adding place: LivPlace) {
        stack.append(place)
        if stack.count > Self.cap { stack.removeFirst(stack.count - Self.cap) }
    }
}

// MARK: - where you were in a note (owner, 2026-08-18)

/// The caret per note, for the session.
///
/// With one open document the editor is torn down every time you go to
/// another state and rebuilt when you come back; a tab used to stay
/// mounted and keep its place for free. This is that place, made
/// explicit — and it is the CARET only, not a scroll offset in points:
/// the text arrives asynchronously and the title's inset is written a
/// frame later, so a remembered offset lands somewhere else. Scrolling
/// the caret into view puts the same words on screen, whatever the
/// layout has decided by then.
///
/// Device state, and deliberately not persisted: the caret's meaning
/// dies with the session, and a stale one after an edit on another
/// device would be a lie about where you were.
enum LivCaret {
    private static var byNote: [UInt64: Int] = [:]

    static func remember(_ note: UInt64, at offset: Int) {
        guard note != 0 else { return }
        byNote[note] = max(0, offset)
    }

    static func recall(_ note: UInt64) -> Int? { byNote[note] }
}


// MARK: - a state's body

/// The five states that are not Docs. They used to be a LAYER over the
/// desk; they are the surface itself now (owner, 2026-08-18), which is
/// what "each state treated equally" means once Docs is a state too.
struct FeatureBody: View {
    let feature: Feature

    var body: some View {
        Group {
            switch feature {
            case .notes: EmptyView()  // Notes draws itself (the tab grid / the editor)
            case .today: TodayView().livSurface(feature.rawValue)
            case .everything: EverythingView().livSurface(feature.rawValue)
            case .inbox: InboxView().livSurface(feature.rawValue)
            case .tasks: TasksView().livSurface(feature.rawValue)
            case .calendar: CalendarView().livSurface(feature.rawValue)
            }
        }
        .transition(LivMotion.surface)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The bar floats over this, and the glass controls over that: a
        // state keeps room for both, and its own content scrolls under
        // them (owner, 2026-08-17).
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: LivBar.room) }
        .safeAreaInset(edge: .top) { LivTopScrim() }
    }
}

// MARK: - the chrome gets out of the way while you read

extension View {
    /// Put this on a top-level surface's OWN scroll view — never on a
    /// parent, and never on a sheet or a panel. Scrolling down sends the
    /// bar and the doors off screen; scrolling up brings them back.
    ///
    /// iOS 18 and later. `onScrollGeometryChange` is the only way to
    /// read a SwiftUI `List`'s offset without reaching into UIKit, and
    /// the build targets 17.0 (`build.sh`). Below 18 the chrome simply
    /// stays where it is, which is the behaviour this app had until
    /// today — a missing nicety, never a broken screen. Raising the
    /// floor is the owner's call, not this change's.
    func livHidesChrome() -> some View {
        modifier(LivChromeScroll())
    }
}

private struct LivChromeScroll: ViewModifier {
    @EnvironmentObject var desk: DeskModel

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    // From the CONTENT's top, not the container's: the
                    // lists carry different top insets, and a raw
                    // contentOffset would put "the top" in a different
                    // place on each one.
                    geo.contentOffset.y + geo.contentInsets.top
                } action: { _, y in
                    desk.scrolled(to: y)
                }
                // Leaving the surface must not leave the chrome hidden.
                .onDisappear { desk.chromeHomeAgain() }
        } else {
            content
        }
    }
}

// MARK: - the self-check: where you are, and how you got there

/// `-places.selfcheck 1`. It replaces the tab plane's suite, which went
/// with the tabs (2026-08-18). The rules it pins are the ones a person
/// would notice breaking: a state replaces a state, a document is inside
/// Docs, the way back says where it goes, and the stack cannot grow
/// without a bound.
func livPlacesSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }

    // A SCRATCH desk, on a workspace nobody has. This suite opens sixty
    // documents to prove the way-back stack is capped, and every one of
    // them is a real tab write — on a plain `DeskModel()` that lands in
    // the Notes plane of whatever workspace you are actually using. It
    // survived only because the first snapshot sweeps ids the box does
    // not know (2026-08-23; the tabs and planes suites were fixed the
    // same way the day before).
    let desk = DeskModel.scratchForSelfCheck()
    desk.shapeOf = { _ in .document }

    // A state replaces a state — states are roots, never children.
    desk.go(.today)
    check("go sets the state", desk.state == .today)
    check("a state has nothing beneath it", desk.back == nil)
    desk.go(.calendar)
    check("state replaces state", desk.state == .calendar && desk.back == nil)

    // A document is INSIDE Docs, and it remembers where you came from.
    desk.open(7)
    check("opening a document lands in Docs", desk.state == .notes, "\(desk.state)")
    check("the open document is the one asked for", desk.openDoc == 7)
    check("back goes where you came from", desk.back == .state(.calendar), "\(String(describing: desk.back))")

    // A link jump: document to document, and back to the first.
    desk.open(9)
    check("the second document replaces the first", desk.openDoc == 9)
    check("back is the note you were reading", desk.back == .document(7))
    desk.goBack()
    check("stepping back re-opens it", desk.openDoc == 7 && desk.state == .notes)
    check("and it does not push itself back on", desk.back == .state(.calendar))

    // Up, out of the document, to the list — the state does not change.
    desk.showList()
    check("the list is Docs with no document", desk.state == .notes && desk.openDoc == nil)
    check("and nothing is beneath it", desk.back == nil)

    // Opening the SAME document again is not a step.
    desk.open(11)
    let before = desk.returns.count
    desk.open(11)
    check("re-opening the open document adds no step", desk.returns.count == before)

    // The stack is a stack, not a diary.
    for id in 100..<160 { desk.open(UInt64(id)) }
    check("the way back is capped", desk.returns.count <= 20, "\(desk.returns.count)")

    // THE FORWARD LEG (2026-08-23, with the bar's `›` key).
    let fresh = DeskModel.scratchForSelfCheck()
    fresh.shapeOf = { _ in .document }
    check("nothing to go forward to at rest", fresh.forward == nil)
    fresh.go(.today)
    fresh.open(3)
    check("still nothing forward after a normal journey", fresh.forward == nil)
    fresh.goBack()
    check("back leaves a forward step", fresh.forward == .document(3), "\(String(describing: fresh.forward))")
    check("and back went where it said", fresh.state == .today && fresh.openDoc == nil)
    fresh.goForward()
    check("forward returns you", fresh.openDoc == 3 && fresh.state == .notes)
    check("and nothing is left ahead", fresh.forward == nil)
    check("while back is where you came from", fresh.back == .state(.today))
    // A FRESH navigation ends the forward journey — you cannot go
    // forward into a future you have just replaced.
    fresh.goBack()
    check("back again leaves a forward step", fresh.forward != nil)
    fresh.go(.calendar)
    check("a new move clears the way forward", fresh.forward == nil, "\(String(describing: fresh.forward))")
    // The forward stack is capped like the back one.
    for id in 200..<260 { fresh.open(UInt64(id)) }
    for _ in 0..<60 { fresh.goBack() }
    check("the way forward is capped", fresh.returns.forwardCount <= 20, "\(fresh.returns.forwardCount)")
    DeskModel.forgetScratchForSelfCheck()

    // A record never becomes the document surface — it rises as a card.
    desk.shapeOf = { _ in .record }
    let openBefore = desk.openDoc
    desk.open(5)
    check("a record opens as a card", desk.recordCard == 5 && desk.openDoc == openBefore)

    DeskModel.forgetScratchForSelfCheck()
    return failures
}
