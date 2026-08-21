import SwiftUI

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

// MARK: - the way out of a document (owner, 2026-08-18)

/// The top-left control INSIDE a document: an ordinary list→detail back,
/// labelled with where it goes.
///
/// Why labelled and not a bare chevron: the destination is not always the
/// list. Follow a `[[link]]` and it is the note you came from; open a
/// note out of Today and it is Today. A bare arrow would be a guess; the
/// word is the promise.
///
/// With nothing beneath it the destination is the list — a document is a
/// level inside Docs, so up always exists.
struct DocumentBack: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        Button(action: act) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: LivType.body, weight: .semibold))
                Text(label)
                    .font(.system(size: LivType.body))
                    .lineLimit(1)
            }
            .foregroundStyle(LivTheme.text)
            .frame(height: 44)
            .frame(maxWidth: 170, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(label)")
    }

    private var label: String {
        switch desk.back {
        case .state(let feature): return feature.title
        case .document(let id):
            return box.entity(id).map(livRowTitle) ?? "Notes"
        case nil: return Feature.notes.title
        }
    }

    private func act() {
        if desk.back == nil {
            desk.showList()
        } else {
            desk.goBack()
        }
    }
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
            case .notes: EmptyView()  // Docs draws itself (NotesList / the editor)
            case .today: TodayView()
            case .everything: EverythingView()
            case .inbox: InboxView()
            case .tasks: TasksView()
            case .calendar: CalendarView()
            }
        }
        .transition(LivMotion.surface)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The bar floats over this, and the glass controls over that: a
        // state keeps room for both, and its own content scrolls under
        // them (owner, 2026-08-17).
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 58) }
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

    let desk = DeskModel()
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

    // A record never becomes the document surface — it rises as a card.
    desk.shapeOf = { _ in .record }
    let openBefore = desk.openDoc
    desk.open(5)
    check("a record opens as a card", desk.recordCard == 5 && desk.openDoc == openBefore)

    return failures
}
