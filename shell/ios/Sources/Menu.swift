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
        .padding(up ? .bottom : .top, safeInset(up))
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: up ? 22 : 0, bottomLeadingRadius: up ? 0 : 22,
                bottomTrailingRadius: up ? 0 : 22, topTrailingRadius: up ? 22 : 0,
                style: .continuous
            )
            .fill(LivTheme.surface)
        )
    }

    /// The window's own inset on that edge — the home indicator below,
    /// the clock and notch above.
    private func safeInset(_ up: Bool) -> CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let insets = scene?.keyWindow?.safeAreaInsets
        return up ? (insets?.bottom ?? 0) : (insets?.top ?? 0)
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
