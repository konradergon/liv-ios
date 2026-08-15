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
    let items: [LivMenuItem]
}

// MARK: - a sheet from the TOP

/// A whole SCREEN of content, arriving from the top edge — the same
/// motion, scrim and card the one menu wears, for the one surface that
/// is too big to be a list of rows: the workspace switcher.
///
/// It comes from the top because its BUTTON is at the top (owner,
/// 2026-08-15: "clicking on workspace has a card come in at the bottom,
/// but since the button is on top it would be more convenient have it
/// appearing at top also"). A `.sheet` cannot do that — on iPhone a
/// sheet only ever comes up from the bottom — so it is drawn here, in
/// the hierarchy, exactly as the menu is.
extension View {
    func livTopSheet<Sheet: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        modifier(LivTopSheetHost(isPresented: isPresented, sheet: content))
    }
}

struct LivTopSheetHost<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let sheet: () -> Sheet

    /// Measured, so the closed position is exactly one card off screen —
    /// a guessed offset slides the wrong distance and reads as a jump.
    @State private var height: CGFloat = 520
    /// The content's own height, so the card is as tall as what is in it.
    @State private var content: CGFloat = 200
    @State private var shown = false
    @State private var drawn = false

    func body(content: Content) -> some View {
        content.overlay {
            if drawn {
                ZStack(alignment: .top) {
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
                        .offset(y: shown ? 0 : -height)
                }
                .ignoresSafeArea()
                .accessibilityAction(.escape) { isPresented = false }
            }
        }
        .onChange(of: isPresented) { _, _ in sync() }
        .onAppear(perform: sync)
    }

    /// Mount first, THEN slide — the menu's own rule.
    private func sync() {
        if isPresented {
            drawn = true
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
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: 4)
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
            .frame(height: min(content, UIScreen.main.bounds.height * 0.72))
            .onPreferenceChange(LivSheetHeight.self) { content = $0 }
            Capsule()
                .fill(LivTheme.panel2)
                .frame(width: 36, height: 5)
                .padding(.vertical, 8)
        }
        .padding(.top, LivSafeArea.top)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: LivTheme.radiusLg,
                bottomTrailingRadius: LivTheme.radiusLg, topTrailingRadius: 0,
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

    func body(content: Content) -> some View {
        content.overlay {
            if active, let drawn {
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
                        // OFF SCREEN by exactly its own height, then home.
                        // The panel is always mounted while `drawn` is
                        // set, so this is a real slide in BOTH directions
                        // — a `.transition` on an `if` gave neither.
                        .offset(y: shown ? 0 : (drawn.from == .top ? -height : height))
                }
                .ignoresSafeArea()
                .accessibilityAction(.escape) { close() }
            }
        }
        .onChange(of: menu?.id) { _, _ in sync() }
        .onAppear(perform: sync)
    }

    /// Mount first, THEN slide: a view inserted and offset in the same
    /// frame has nowhere to travel from.
    private func sync() {
        if let menu {
            drawn = menu
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
            if up { grabber }
            if let title = menu.title {
                Text(title)
                    .font(.system(size: LivType.title, weight: .semibold))
                    .foregroundStyle(LivTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
            }
            ForEach(Array(menu.items.enumerated()), id: \.element.id) { i, item in
                row(item, divided: i > 0)
            }
            if up { Spacer(minLength: 0).frame(height: 4) }
            if !up { grabber }
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

    private var grabber: some View {
        Capsule()
            .fill(LivTheme.panel2)
            .frame(width: 36, height: 5)
            .padding(.vertical, 8)
    }

    private func row(_ item: LivMenuItem, divided: Bool) -> some View {
        Button {
            close()
            // After the motion, not during it: a sheet that acts while
            // it is still moving takes the new screen's first frame with
            // it (the panels' own rule).
            DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.navSeconds) {
                item.action()
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let glyph = item.glyph {
                        LivIcon(
                            glyph: glyph,
                            color: item.destructive ? LivTheme.red : LivTheme.text2,
                            size: 24)
                    } else if let symbol = item.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: LivType.title))
                            .foregroundStyle(
                                item.destructive ? LivTheme.red : LivTheme.text2)
                    }
                }
                .frame(width: 26)
                Text(item.label)
                    .font(.system(size: LivType.title))
                    .foregroundStyle(item.destructive ? LivTheme.red : LivTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if item.chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: LivType.caption, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: LivRow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(LivTheme.border).frame(height: 0.5)
                    .padding(.leading, 54)
            }
        }
    }
}
