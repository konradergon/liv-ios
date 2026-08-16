// liv iOS — the properties panel (design/ios.md §6 rev 6, owner
// 2026-08-03; the floor, 2026-08-16).
//
// The app's model is now: a FLOOR under everything (Today, Calendar,
// Tasks, Find), things you OPEN lying over it as tabs, and this — the
// panel that describes the thing you have open. It DESCRIBES; the verbs
// live in the ••• menu.
//
// Full-screen, swiped in from the right edge from anywhere, one gesture
// for open and close. Full screen means there is no exposed sliver to
// tap, so the escape action below is what a finger-less user gets.

import SwiftUI

// MARK: - the slide-over container

/// The properties panel: full screen, the app's own ground, no radius,
/// no shadow, no inset — it stands on the right and slides over a desk
/// that stays put (owner, 2026-08-15). It is the only panel left; the
/// library was demolished on 2026-08-16, when the views it held became
/// the floor under everything.
///
/// NO close button. It had a 40pt band of its own holding one chevron,
/// then rode the first row, where it landed almost inside the title
/// (owner, 2026-08-10: "you probably should get rid of the collapse
/// buttons"). A panel is DRAGGED back — the gesture the owner asked for
/// on 2026-08-08, and the same one that opens it. The escape action
/// below is what remains for anyone not using a finger.
struct SidePanel<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // The band the panel owns: the same 56pt the chrome above
            // it owns, so the tops line up and nothing the panel draws
            // lands under the workspace name floating over it.
            Color.clear
            .frame(height: LivRow.topChrome)
            .overlay(alignment: .bottom) {
                Rectangle().fill(LivTheme.border).frame(height: 0.5)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LivTheme.canvas.ignoresSafeArea())
        // VoiceOver's two-finger scrub, Voice Control's escape.
        .accessibilityAction(.escape, onDismiss)
        // No .transition: DeskHost positions these with an offset that
        // follows the finger, and a transition on top of it would move
        // the panel twice (owner, 2026-08-08).
    }
}
