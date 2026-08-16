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
struct SidePanel<Band: View, Content: View>: View {
    let onDismiss: () -> Void
    /// What sits in the panel's own top band, beside the pinned
    /// workspace button that floats over every surface. Usually nothing
    /// — see the EmptyView init below.
    let band: Band
    @ViewBuilder let content: Content

    init(
        onDismiss: @escaping () -> Void,
        @ViewBuilder band: () -> Band,
        @ViewBuilder content: () -> Content
    ) {
        self.onDismiss = onDismiss
        self.band = band()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // The band both panels own: the same 56pt the desk's chrome
            // owns, so the tops line up and nothing a panel draws lands
            // under the workspace name floating above it.
            HStack(spacing: 0) {
                band
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
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

extension SidePanel where Band == EmptyView {
    init(onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.init(onDismiss: onDismiss, band: { EmptyView() }, content: content)
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

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel

    var body: some View {
        SidePanel(onDismiss: onDismiss, band: { backChevron }) {
            VStack(spacing: 0) {
                // A view opens IN here (owner, 2026-08-15: "do the views
                // opening inside the library"). It is not a window over
                // the desk any anymore: you are in the library, looking
                // at Today, and the desk is parked where you left it.
                if let feature = desk.featureShown {
                    Group {
                        switch feature {
                        case .today: TodayView()
                        case .everything: EverythingView()
                        case .inbox: InboxView()
                        case .tasks: TasksView()
                        case .calendar: CalendarView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // THE VIEWS ARE NOT HERE ANY MORE (owner,
                        // 2026-08-16: "library is for filters, workspace
                        // and settings"). They are the bar's own key —
                        // Go to: Today, Inbox, Calendar, Tasks,
                        // Everything, Docs — and two doors to one room is
                        // what standing rule 4 exists to stop.
                        //
                        // Saved filters stay: a filter is not a
                        // workspace, and this is where you come to change
                        // what you are looking at (owner, 2026-08-11).
                        // The WORKSPACE itself has no row here either —
                        // the pinned button at the top centre is its one
                        // door (owner, 2026-08-13), and this panel is
                        // where its filters and the app's settings live.
                        SectionLabel("Filters")
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        Group {
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
                            row("New filter…", glyph: .plus) {
                                desk.composeFilter = true
                                onWorkspace()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                bottomBand
        }
    }

    /// Back to the library's own list. Only there is anything to go
    /// back FROM — on the list itself the band is empty, and the
    /// workspace button floats in the middle of it.
    @ViewBuilder private var backChevron: some View {
        if desk.featureShown != nil {
            Button { desk.featureShown = nil } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: LivType.strong, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to the library")
        }
    }

    /// Pinned below the scroll (rev 6): the app's own door. "Where you
    /// are" left this band on 2026-08-13 — the workspace is named at the
    /// top of the screen now, over this panel, and a second copy at the
    /// foot was the same fact twice.
    private var bottomBand: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Settings", glyph: .settings) {
                onSettings()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // NO fill. It had a grey one for a few hours, on the theory that
        // a place wants its own foot; on screen that is a slab of tone
        // around a single row, saying nothing (owner, 2026-08-15: "what
        // is the grey area towards the bottom in library? looks off").
        // The hairline is the whole job: Settings is pinned, and a line
        // says so.
        .overlay(alignment: .top) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
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
        /// A lens TOGGLE rather than a place to go: the dot says it is on.
        on: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LivIcon(glyph: glyph, color: LivTheme.text2, size: 26)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: LivType.title))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.system(size: LivType.body))
                        .foregroundStyle(LivTheme.muted)
                }
                if on {
                    Circle().fill(LivTheme.accent).frame(width: 8, height: 8)
                }
            }
            .frame(height: LivRow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
