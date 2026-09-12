// liv iOS — the one menu (owner, 2026-08-13, pointing at Notesnook):
// "implement one reusable slide-up menu component and reuse it for all
// three, with variations for placement and slide direction".
//
// It replaces three different mechanisms that all looked different: a
// UIKit UIMenu hanging off the toolbar's `+`, a SwiftUI Menu hanging off
// the note's •••, and a whole full-screen PAGE for New Tab. One recipe,
// one row height, one motion; only the edge it comes from changes.
//
// Why an overlay and not a `.sheet`: a sheet can only come from the
// bottom, and the ••• menu comes DOWN from the top, where its own button
// is. The scrim and the panel are drawn by whoever hosts the menu, which
// is also what lets the desk hand the job to a record card when the card
// is the surface in front.

import SwiftUI

// MARK: - what a menu is

/// One row. The glyph is the app's own drawing where the language has
/// one, and an Apple symbol where the verb is chrome (share, trash) —
/// the same split the toolbar makes.
struct LivMenuItem: Identifiable {
    let label: String
    var glyph: LivGlyph?
    var symbol: String?
    /// THE ONE YOU ARE ON. `LivMenuRow` has drawn a checkmark for this
    /// since it was written; no menu had a state to mark until the
    /// search facet menu (2026-09-07), which is three verbs of which
    /// exactly one is true.
    var selected = false
    /// A row that opens something further, marked the way a list marks it.
    var chevron = false
    var destructive = false
    let action: () -> Void

    var id: String { label }
}

/// A menu, ready to show. `id` is what the animation watches, so two
/// different menus never cross-fade into each other.
struct LivMenu: Identifiable {
    let id: String
    /// The edge it comes from: `.bottom` slides up, `.top` slides down.
    let from: VerticalEdge
    var title: String?
    /// WHAT THE MENU IS ACTING ON, when that is a specific thing rather
    /// than the app in general (owner's clips, 2026-08-20). The
    /// reference menu opens under the document's own title and repeats
    /// it in a header — name on one line, what it is on a second — so
    /// "Rename…", "Move to…" and "Delete" have a visible subject.
    /// Liv's note ••• menu had no title at all: five verbs and no sign
    /// of which note they were about.
    var subject: String?
    var subjectDetail: String?
    let items: [LivMenuItem]
}

// MARK: - one row, for every card

/// The row BOTH cards are made of (owner, 2026-08-17: the workspace card
/// "has a different style from the 'New' card… like the latter more
/// since it has bigger text and looks simpler").
///
/// It was two: the menu's row at title size with a 26pt icon slot, and
/// the workspace switcher's own at body size with an 18pt one, plus
/// chips under the label and a hairline under every line. One list of
/// things to choose from, drawn two ways, is exactly what standing rule
/// 4 is about — so there is one row now, and the plainer, larger one
/// won.
struct LivMenuRow: View {
    let label: String
    var glyph: LivGlyph?
    var symbol: String?
    /// A workspace may wear an emoji instead of a glyph.
    var emoji: String?
    /// The one you are on: a checkmark, the way a list marks a choice.
    var selected = false
    var chevron = false
    var destructive = false
    /// A door rather than a choice — "New workspace…" — in the accent.
    var accent = false
    /// A hairline above, inset past the icon: rows after the first.
    var divided = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if let emoji, !emoji.isEmpty {
                        Text(emoji).font(.system(size: LivType.title))
                    } else if let glyph {
                        LivIcon(glyph: glyph, color: tint(icon: true), size: 24)
                    } else if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: LivType.title))
                            .foregroundStyle(tint(icon: true))
                    }
                }
                .frame(width: 26)
                Text(label)
                    .font(.system(size: LivType.title, weight: selected ? .semibold : .regular))
                    .foregroundStyle(tint(icon: false))
                    .lineLimit(1)
                Spacer(minLength: 8)
                // NO TICK. The comment below already argued that a fill
                // is found without reading and a tick is not — and then
                // kept the tick anyway, so a chosen row carried three
                // marks for one fact: a fill, a semibold word, and an
                // accent checkmark. The fill is the one that works.
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: LivType.caption, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: LivRow.height)
            // THE ONE YOU ARE ON, as a fill and nothing else (owner's
            // clips, 2026-08-20). ChatGPT's drawer marks the current
            // destination with a soft rounded fill and no tick at all.
            // The weight stays — it costs no ink — and the tick is gone.
            .background(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm, style: .continuous)
                    .fill(selected ? LivTheme.panel2 : .clear)
                    .padding(.horizontal, 8))
            .contentShape(Rectangle())
        }
        .livRowPress()
        // A ROW IS A DOOR TOO. A menu raised from a menu row — the trash
        // confirm, "Not a note…" — grows out of the row you touched
        // rather than sliding up from an edge 400pt away, which is the
        // case the owner's diagnosis explains best.
        .livDoor()
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(LivTheme.border).frame(height: 0.5)
                    .padding(.leading, LivRow.hairline + 18)
            }
        }
    }

    private func tint(icon: Bool) -> Color {
        if destructive { return LivTheme.red }
        if accent { return LivTheme.accent }
        return icon ? LivTheme.text2 : LivTheme.text
    }
}

/// The title both cards wear: the one word for what the card is.
struct LivMenuTitle: View {
    let text: String

    var body: some View {
        Text(text)
            // BOLD, matching `LivSheetTitle` (owner, 2026-09-12). A title
            // on a card was two weights depending on which kind of card
            // it was: bold in Settings, Trash and History, semibold here.
            // The argument against bold is that it is also the SCREEN
            // title's weight, so reusing it blurs the rank between the
            // screen and the sheet over it — but the rank is already
            // carried by ten points of size (32 against 22), and the
            // owner has called this app's text too small three times.
            .font(.system(size: LivType.title, weight: .bold))
            .foregroundStyle(LivTheme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }
}

/// The menu's subject: the thing every verb below it will act on.
/// THE GRABBER, ONCE. `LivMenuHost` and `LivTopSheetHost` each carried
/// their own copy of the same capsule — two types, one shape, and the
/// kind of duplication that drifts (standing rule 4). It is drawn on
/// every card in the app, and since 2026-08-31 it means what it looks
/// like: the card follows the finger and a pull toward its own edge
/// dismisses it.
struct LivGrabber: View {
    var body: some View {
        Capsule()
            .fill(LivTheme.panel2)
            .frame(width: 36, height: 5)
            .padding(.vertical, 8)
    }
}

struct LivMenuSubject: View {
    let name: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: LivType.title, weight: .semibold))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: LivType.label))
                    .foregroundStyle(LivTheme.text2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}

// MARK: - where the card came from

/// THE LAST DOOR PRESSED, in screen coordinates.
///
/// Owner, 2026-09-12: *"the chrome looks independent from the buttons
/// that invoke them … some animations make it visually look like
/// something 'comes out' or 'expands' from the buttons, which is what
/// should happen instead of a card sliding on top."*
///
/// That is a better diagnosis than the one it replaces. The app already
/// had a rule — a card comes from the edge its button is on — and the
/// rule was right but approximate: it picks one of two edges for a
/// button that is at a POINT. Grow the card from the point and the edge
/// stops being a setting anyone can get wrong. The two violations the
/// audit found on 2026-09-12, the trash confirm raised from inside a
/// top-hanging card and Search's facet menu raised from chips near the
/// top, both simply cease to exist.
///
/// How a door marks itself is `livDoor()`, below.
enum LivDoors {
    /// Written by `livDoor()` when a door is tapped, read once when the
    /// card it raises is built. Not published: nothing re-renders on a
    /// tap, and a card reads it exactly once.
    static var lastPressed: CGRect?

    /// Where a door sits INSIDE a card that is about to appear, as a
    /// `UnitPoint` for `scaleEffect(_:anchor:)`. Values outside 0...1 are
    /// legal and are the normal case: a card at the bottom of the screen
    /// grows from a button above its own top edge.
    static func anchor(in card: CGRect) -> UnitPoint? {
        guard let door = lastPressed, card.width > 0, card.height > 0 else {
            return nil
        }
        return UnitPoint(
            x: (door.midX - card.minX) / card.width,
            y: (door.midY - card.minY) / card.height)
    }
}

/// A DOOR: a control that raises a card, marking where it is so the card
/// can grow out of it.
///
/// WHY A MODIFIER AND NOT A `ButtonStyle`. A style was the first shape of
/// this: it reads `configuration.isPressed`, SwiftUI's own press
/// tracking, and adds no recogniser at all. But a button has ONE style,
/// and this app's doors already spend theirs — `LivMenuRow` wears
/// `livRowPress`, which is where a menu row's touch feedback comes from,
/// and `LivTheme.pressed` exists because eight row sites once had none
/// and the owner noticed. A door would have had to choose between its
/// press feedback and its origin. One modifier that composes with
/// whatever style a button already wears beats two mechanisms.
///
/// WHY A TAP AND NOT A DRAG. The other tempting one-liner records every
/// touch from a zero-distance `DragGesture` on the root: no per-door
/// change at all, and automatically right for a menu raised from another
/// menu. A zero-distance drag recogniser above a scroll view is also the
/// version that can quietly break scrolling, and there is no simulator
/// here to find out. A `TapGesture` cannot: a scroll is a pan, and a
/// simultaneous tap does not claim it.
///
/// A door that forgets to wear this is not a defect, only a card that
/// still slides — `LivMenuHost` falls back to the offset it always used
/// when no origin is known.
extension View {
    func livDoor() -> some View { modifier(LivDoor()) }
}

struct LivDoor: ViewModifier {
    @State private var box: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { box = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, f in box = f }
                }
            )
            // BOTH WAYS A DOOR OPENS. Several menus in this app are
            // raised by a HOLD rather than a tap — the bar's `+`, a
            // Search chip — so a tap-only recorder would leave exactly
            // those cards sliding. 0.3 is under the 0.45 those holds
            // use, so the origin is recorded before the menu is asked
            // for. Neither gesture claims a scroll: a scroll is a pan,
            // which is not a tap and which cancels a long press.
            .simultaneousGesture(TapGesture().onEnded { LivDoors.lastPressed = box })
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in LivDoors.lastPressed = box })
    }
}

// MARK: - a sheet from the TOP

/// A whole SCREEN of content, arriving from the top edge — the same
/// motion, scrim and card the one menu wears, for the one surface that
/// is too big to be a list of rows: the workspace switcher.
///
/// IT COMES FROM THE EDGE ITS BUTTON IS ON, and that is the whole rule
/// (owner, 2026-08-15: "clicking on workspace has a card come in at the
/// bottom, but since the button is on top it would be more convenient
/// have it appearing at top also"). A `.sheet` cannot do the top half —
/// on iPhone a sheet only ever comes up from the bottom — so this is
/// drawn in the hierarchy, exactly as the menu is.
///
/// THE EDGE IS A PARAMETER SINCE 2026-08-31, because the rule outlived
/// the arrangement it was written for. The workspace button WAS at the
/// top when the owner asked for this; it moved to the foot of the
/// library panel a week later (team, 2026-08-22) and the direction
/// stayed behind, so the workspace and filter cards fell from the top of
/// the screen while the buttons that opened them sat at the bottom — the
/// workspace button drawing a `chevron.down` the whole time (owner,
/// 2026-08-31: "some menus are popping up top down when the button is
/// not at the top"). Hard-coding a direction records an answer; taking
/// it as a parameter records the rule, and the rule survives the
/// furniture moving again.
extension View {
    func livSheet<Sheet: View>(
        from edge: VerticalEdge = .bottom, isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        modifier(LivEdgeSheetHost(from: edge, isPresented: isPresented, sheet: content))
    }
}

struct LivEdgeSheetHost<Sheet: View>: ViewModifier {
    let from: VerticalEdge
    @Binding var isPresented: Bool
    @ViewBuilder let sheet: () -> Sheet

    /// Measured, so the closed position is exactly one card off screen —
    /// a guessed offset slides the wrong distance and reads as a jump.
    @State private var height: CGFloat = 520
    /// The content's own height, so the card is as tall as what is in it.
    @State private var content: CGFloat = 200
    @State private var shown = false
    @State private var drawn = false
    /// The door this card is growing out of — see `LivDoors`. Named
    /// `origin` and not `from` because this host already has a `from`,
    /// which is the EDGE. Two different questions: which edge the card
    /// hangs off, and which point it grew from.
    @State private var origin: UnitPoint?

    func body(content: Content) -> some View {
        content.overlay {
            if drawn {
                ZStack(alignment: from == .top ? .top : .bottom) {
                    Rectangle()
                        .fill(Color.black.opacity(shown ? 0.4 : 0))
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isPresented = false }
                    card
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { height = geo.size.height }
                                    .onChange(of: geo.size.height) { _, h in height = h }
                            }
                        )
                        // OUT OF ITS DOOR, or off its edge — the same
                        // rule as the menu host, applied to the app's only
                        // other cover it owns.
                        .scaleEffect(
                            shown || origin == nil ? 1 : 0.86,
                            anchor: origin ?? .center)
                        .opacity(origin == nil || shown ? 1 : 0)
                        .offset(
                            y: origin != nil || shown
                                ? 0 : (from == .top ? -height : height))
                }
                .ignoresSafeArea()
                .accessibilityAction(.escape) { isPresented = false }
            }
        }
        .onChange(of: isPresented) { _, _ in sync() }
        .onAppear(perform: sync)
    }

    /// Where the card will be, in screen coordinates. Same reasoning as
    /// the menu host's: resolved BEFORE the card is told to appear, not
    /// inside its own `GeometryReader`, whose `onAppear` and the async
    /// below run in an order SwiftUI does not promise.
    private func cardBox() -> CGRect {
        CGRect(
            x: 0, y: from == .top ? 0 : LivScreen.height - height,
            width: LivScreen.width, height: height)
    }

    /// Mount first, THEN slide — the menu's own rule.
    private func sync() {
        if isPresented {
            drawn = true
            origin = LivDoors.anchor(in: cardBox())
            shown = false
            DispatchQueue.main.async {
                withAnimation(LivMotion.nav) { shown = true }
            }
        } else if drawn {
            withAnimation(LivMotion.nav) { shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.navSeconds) {
                if !isPresented { drawn = false }
            }
        }
    }

    /// The same card the menu wears, hanging from the top: square against
    /// the edge it is attached to, rounded on the side facing the content,
    /// the grabber on the bottom, and the safe area kept as space inside.
    private var card: some View {
        let up = from == .bottom
        return VStack(spacing: 0) {
            if up { LivGrabber() } else { Spacer(minLength: 0).frame(height: 4) }
            // Hugs its content, and scrolls only once the content is
            // taller than the cap — a four-row switcher hanging down 86%
            // of the screen is a wall, not a card.
            ScrollView {
                sheet()
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: LivSheetHeight.self, value: geo.size.height)
                        }
                    )
            }
            .frame(height: min(content, LivScreen.height * 0.72))
            .onPreferenceChange(LivSheetHeight.self) { content = $0 }
            if !up { LivGrabber() }
        }
        // The safe area is SPACE INSIDE the card, on whichever edge it is
        // attached to — a top card whose first row sits under the clock
        // reads as broken, and so does a bottom one running into the home
        // indicator.
        .padding(.top, up ? 0 : LivSafeArea.top)
        .padding(.bottom, up ? LivSafeArea.bottom : 0)
        .background(
            // Square against the edge it hangs from, rounded on the side
            // facing the content.
            UnevenRoundedRectangle(
                topLeadingRadius: up ? LivTheme.radiusLg : 0,
                bottomLeadingRadius: up ? 0 : LivTheme.radiusLg,
                bottomTrailingRadius: up ? 0 : LivTheme.radiusLg,
                topTrailingRadius: up ? LivTheme.radiusLg : 0,
                style: .continuous
            )
            .fill(LivTheme.surface)
        )
    }
}

/// The measured height of a top sheet's content.
private struct LivSheetHeight: PreferenceKey {
    static let defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The window's own insets, in one place — the menu and the top sheet
/// both keep the safe area as SPACE inside the card rather than bleeding
/// past it (a top sheet whose first row sits under the clock is broken).
enum LivSafeArea {
    static var top: CGFloat { insets?.top ?? 0 }
    static var bottom: CGFloat { insets?.bottom ?? 0 }
    private static var insets: UIEdgeInsets? {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.keyWindow?.safeAreaInsets
    }
}

// MARK: - the host

extension View {
    /// Draw `menu` over this surface. `active` is the same rule the
    /// record card uses: only the surface in FRONT draws it, so a menu
    /// asked for from inside a card does not appear behind the card.
    func livMenu(_ menu: Binding<LivMenu?>, active: Bool = true) -> some View {
        modifier(LivMenuHost(menu: menu, active: active))
    }
}

struct LivMenuHost: ViewModifier {
    @Binding var menu: LivMenu?
    var active: Bool = true

    /// The panel's own height, measured, so the closed position is
    /// exactly one panel off screen. A guessed offset slides the wrong
    /// distance and reads as a jump.
    @State private var height: CGFloat = 320
    /// What is on screen right now. Separate from `menu` on purpose: the
    /// panel must still EXIST while it slides out, so the binding clears
    /// only after the motion (`shown` drives the offset, `menu` drives
    /// what is drawn).
    @State private var shown = false
    @State private var drawn: LivMenu?
    /// How far the finger has pulled the card toward its own edge.
    @State private var drag: CGFloat = 0
    /// WHERE THIS CARD IS GROWING FROM — the door's centre, expressed
    /// inside the card's own box. Nil means no door was recorded, and the
    /// card slides from its edge the way it always did. Named `origin`
    /// rather than `from`, which on a `LivMenu` means the EDGE.
    @State private var origin: UnitPoint?

    func body(content: Content) -> some View {
        content.overlay {
            if active, let drawn {
                let up = drawn.from == .bottom
                ZStack(alignment: drawn.from == .top ? .top : .bottom) {
                    // The scrim: everything behind it is out of reach
                    // until this closes, and tapping it closes.
                    Rectangle()
                        .fill(Color.black.opacity(shown ? 0.4 : 0))
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                    panel(drawn)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { height = geo.size.height }
                                    .onChange(of: geo.size.height) { _, h in height = h }
                            }
                        )
                        // THE GRABBER NOW TELLS THE TRUTH.
                        //
                        // Every card in this app draws the little
                        // capsule that means "drag me away", and none of
                        // them could be dragged — they closed by tapping
                        // the scrim, and the grabber was decoration
                        // promising an affordance that did not exist
                        // (polish audit, 2026-08-30). A card is easier
                        // to dismiss this way than by reaching for the
                        // scrim, and it is what the phone has taught
                        // everyone to try first.
                        //
                        // The threshold is distance OR speed: a short
                        // flick closes, a long slow drag closes, and a
                        // small accidental movement puts it back.
                        .offset(y: drag)
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { g in
                                    let d = up ? g.translation.height
                                        : -g.translation.height
                                    drag = up ? max(0, d) : -max(0, d)
                                }
                                .onEnded { g in
                                    let d = up ? g.translation.height
                                        : -g.translation.height
                                    let v = up ? g.predictedEndTranslation.height
                                        : -g.predictedEndTranslation.height
                                    if d > 90 || v > 220 {
                                        withAnimation(LivMotion.nav) { drag = 0 }
                                        close()
                                    } else {
                                        withAnimation(LivMotion.pick) { drag = 0 }
                                    }
                                }
                        )
                        // OUT OF THE DOOR, or off the edge (owner,
                        // 2026-09-12). With a door recorded the card
                        // grows from it and fades in; with none it slides
                        // off screen by exactly its own height, which is
                        // what every card did before.
                        //
                        // 0.86 rather than 0: a card that starts at
                        // nothing reads as a pop, and the ask was better
                        // rather than fancier. It is small enough to be a
                        // growth and large enough that the words inside
                        // never scale through illegibility.
                        //
                        // The panel is always mounted while `drawn` is
                        // set, so this is real motion in BOTH directions
                        // — a `.transition` on an `if` gave neither.
                        .scaleEffect(
                            shown || origin == nil ? 1 : 0.86,
                            anchor: origin ?? .center)
                        .opacity(origin == nil || shown ? 1 : 0)
                        .offset(
                            y: origin != nil || shown
                                ? 0 : (drawn.from == .top ? -height : height))
                }
                .ignoresSafeArea()
                .accessibilityAction(.escape) { close() }
            }
        }
        .onChange(of: menu?.id) { _, _ in sync() }
        .onAppear(perform: sync)
    }

    /// Where the card will be, in screen coordinates: full width, hung
    /// from whichever edge it comes from, as tall as the last one was.
    private func cardBox(_ edge: VerticalEdge) -> CGRect {
        CGRect(
            x: 0, y: edge == .top ? 0 : LivScreen.height - height,
            width: LivScreen.width, height: height)
    }

    /// Mount first, THEN slide: a view inserted and offset in the same
    /// frame has nowhere to travel from.
    private func sync() {
        if let menu {
            // THE ANCHOR IS RESOLVED BEFORE THE CARD IS TOLD TO APPEAR,
            // and deliberately not inside the card's own `GeometryReader`.
            // That reader's `onAppear` and the async below both run after
            // this, in an order SwiftUI does not promise — and if the
            // anchor lands second the card is already at scale 1 and the
            // growth never happens. So it is computed here from the
            // screen and the last measured height, which is exact for
            // every card after the first and close for the first.
            drawn = menu
            origin = LivDoors.anchor(in: cardBox(menu.from))
            shown = false
            // The motion is asked for EXPLICITLY, here, rather than left
            // to an `.animation(value:)` on the modified content — that
            // one watched the right value and animated nothing, because
            // the view it was attached to is not the one that moves.
            DispatchQueue.main.async {
                withAnimation(LivMotion.nav) { shown = true }
            }
        } else if drawn != nil {
            withAnimation(LivMotion.nav) { shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.navSeconds) {
                if menu == nil { drawn = nil }
            }
        }
    }

    private func close() {
        menu = nil
    }

    /// The sheet itself: a native-feeling card — rounded on the side
    /// facing the content, square against the edge it is attached to, the
    /// grabber on that same edge, and the SAME paddings whichever way it
    /// comes from. The safe area is padding, not something to bleed past:
    /// a top sheet whose first row sits under the clock reads as broken.
    private func panel(_ menu: LivMenu) -> some View {
        let up = menu.from == .bottom
        return VStack(spacing: 0) {
            if !up { Spacer(minLength: 0).frame(height: 4) }
            if up { LivGrabber() }
            if let title = menu.title {
                LivMenuTitle(text: title)
            }
            if let subject = menu.subject {
                LivMenuSubject(name: subject, detail: menu.subjectDetail)
            }
            ForEach(Array(menu.items.enumerated()), id: \.element.id) { i, item in
                row(item, divided: i > 0)
            }
            if up { Spacer(minLength: 0).frame(height: 4) }
            if !up { LivGrabber() }
        }
        .frame(maxWidth: .infinity)
        // The safe area on the attached edge, kept as SPACE inside the
        // card rather than ignored.
        .padding(up ? .bottom : .top, up ? LivSafeArea.bottom : LivSafeArea.top)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: up ? LivTheme.radiusLg : 0,
                bottomLeadingRadius: up ? 0 : LivTheme.radiusLg,
                bottomTrailingRadius: up ? 0 : LivTheme.radiusLg,
                topTrailingRadius: up ? LivTheme.radiusLg : 0,
                style: .continuous
            )
            .fill(LivTheme.surface)
        )
    }



    private func row(_ item: LivMenuItem, divided: Bool) -> some View {
        LivMenuRow(
            label: item.label, glyph: item.glyph, symbol: item.symbol,
            selected: item.selected,
            chevron: item.chevron, destructive: item.destructive, divided: divided
        ) {
            close()
            // After the motion, not during it: a sheet that acts while
            // it is still moving takes the new screen's first frame with
            // it (the panels' own rule).
            DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.navSeconds) {
                item.action()
            }
        }
    }
}
