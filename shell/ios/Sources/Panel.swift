// liv iOS — the side panels (design/ios.md §6 rev 6, owner 2026-08-03).
// The app's mental model is three zones:
//
//   LEFT  — the library: everything about the APP. The global views,
//           the workspace's views, the workspace switcher, Settings.
//   CENTER — the desk: ONE editable thing. Tabs hold notes and nothing
//           else — a view is a visit, a note is a tab.
//   RIGHT — the properties panel: everything about THIS note. It
//           DESCRIBES; the verbs live in the desk's ••• menu.
//
// Rev 6: both panels are FULL-SCREEN (Notesnook's layout is the model)
// and are swiped into from anywhere — the swipe lives on DeskHost, one
// gesture for open and close. Full screen means there is no exposed
// sliver to tap, so each panel carries the house close band
// (FeatureWindow's recipe): the whole 40pt band closes, not just the
// glyph, because a full-screen surface with no visible way out is a
// trap — for touch and for Voice Control alike.

import SwiftUI

// MARK: - the slide-over container

/// ONE recipe for both surfaces again (owner, 2026-08-15: "maybe we
/// should keep properties stalled on the right not as a card for
/// simplification's sake, and have the base appearance same as
/// library"). Full screen, the app's own ground, no radius, no shadow,
/// no inset — the properties panel stands on the right, it does not
/// float over anything.
///
/// The two still differ where it costs nothing: the LIBRARY pushes the
/// desk off screen (it is a place) and the PROPERTIES panel slides over
/// a desk that stays put (it is the desk's). That is motion, not paint,
/// and paint waits for the surface pass.
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
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // THE SAME TOP A VIEW HAS (owner, 2026-08-17: "in the left
            // sidebar it is opaque at the top — do the same as you did
            // for views here"): the list runs under the clock and fades
            // out behind it. What was here instead: 56pt of empty band
            // with a hairline under it, which read as a bar that was not
            // one.
            .safeAreaInset(edge: .top) { LivTopScrim() }
            // And the same room at the foot, because the bar floats over
            // a panel too.
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 58) }
            // A PANEL, not a curtain (owner, 2026-08-18): one step of tone
        // above the canvas, flat — no shadow, no gradient, no border.
        .background(LivTheme.panel.ignoresSafeArea())
            .ignoresSafeArea(edges: .top)
            // VoiceOver's two-finger scrub, Voice Control's escape.
            .accessibilityAction(.escape, onDismiss)
            // No .transition: DeskHost positions these with an offset
            // that follows the finger, and a transition on top of it
            // would move the panel twice (owner, 2026-08-08).
    }
}

// MARK: - the library (left)

/// The application, in one place (rev 6, Notesnook's sidebar as the
/// model): the GLOBAL views that ignore the workspace lens, then the
/// active WORKSPACE's own views — the ones its query filters — then,
/// pinned at the bottom, the workspace switcher and Settings. Nothing in
/// here is about the currently open note.
struct LibraryPanel: View {
    let onDismiss: () -> Void
    /// BOTH presented by DESKHOST, not here: anything that closes this
    /// panel mid-use (workspace adopt(), a notification tap routing
    /// desk.open) would tear down a sheet hung on it (audits 2026-08-01,
    /// 2026-08-04).
    let onWorkspace: () -> Void
    let onSettings: () -> Void
    let onTrash: () -> Void

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel

    var body: some View {
        // THE APP'S PRIMARY MENU (owner, 2026-08-17). Which view you are
        // in is global STATE, so it lives here; the bar below holds
        // global ACTIONS and nothing else. The views were briefly a key
        // on that bar (2026-08-16) — this is the deliberate reversal,
        // and the bar is four keys lighter for it.
        //
        // A view still opens WHERE YOU STAND: picking one here closes
        // the panel and the view arrives over what you were looking at,
        // with the bar still under it.
        SidePanel(onDismiss: onDismiss) {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // THE VIEWS ARE NOT HERE (owner, 2026-08-18):
                        // they are the bar's own key, which names where
                        // you are and opens the Go-to menu. A drawer is
                        // the right home for what you touch rarely and
                        // the wrong one for what you touch on every
                        // navigation.
                        //
                        // NO SECTION LABELS either (owner, 2026-08-18:
                        // "eliminate unnecessary small text and
                        // labels"). Two headings over five rows was
                        // furniture explaining furniture; the filters
                        // are obviously filters, and Settings is
                        // obviously Settings.
                        ForEach(workspaces.filters) { view in
                            row(
                                view.display,
                                glyph: .filter,
                                on: workspaces.activeFilterId == view.id
                            ) {
                                workspaces.activeFilterId =
                                    workspaces.activeFilterId == view.id ? nil : view.id
                                onDismiss()
                            }
                        }
                        row("New filter", glyph: .plus) {
                            desk.composeFilter = true
                            onWorkspace()
                        }
                        // Settings is the LAST ROW, not a pinned foot
                        // (owner, 2026-08-17): two fixed layers at the
                        // foot of one list — a pinned row and the global
                        // bar over it — was one too many.
                        // The way back from a delete. It sits with
                        // Settings because it is house-keeping, not a
                        // place you work — and because the alternative was
                        // a fourth pill on Everything, which is already
                        // the screen the owner finds most confusing.
                        row("Trash", glyph: .trash) { onTrash() }
                            .padding(.top, 16)
                        row("Settings", glyph: .settings) { onSettings() }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                }
        }
    }

    /// One list row. NO hairline: a line between rows is what a FORM
    /// does — it is what DetailHairline means one screen to the right —
    /// and this is a list of places to go, held apart by its section
    /// labels. The inset lines it used to draw also broke the
    /// constitution's own rule (interface.md: "Dividers are full-width
    /// or absent").
    /// The library's icons are BARE, colourless and large (owner,
    /// 2026-08-13). They wore carved chips in their own hues for a day;
    /// a column of seven coloured boxes read as a toy shelf next to the
    /// one thing on this screen that matters, which is the words. Kind
    /// colour still marks what a THING is, out in the lists — a view is
    /// a place, not a thing.
    private func row(
        _ label: String, glyph: LivGlyph, detail: String? = nil,
        /// The lens that is ON. The lightest mark that reads as a state:
        /// a quaternary fill and medium ink, no accent, no dot, no
        /// border (surface pass, owner 2026-08-18).
        on: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                LivIcon(glyph: glyph, color: on ? LivTheme.text : LivTheme.text2, size: 21)
                    .frame(width: 22)
                Text(label)
                    .font(.system(size: LivType.body, weight: on ? .semibold : .regular))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.system(size: LivType.label))
                        .foregroundStyle(LivTheme.text3)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm, style: .continuous)
                    .fill(on ? LivTheme.selection : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
