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

/// The properties panel: the desk's OWN layer, and it looks like one
/// (owner, 2026-08-15: "the property panel … really is a panel belonging
/// to desk").
///
/// A CARD over the note, not a screen of its own: it starts below the
/// desk's top band, so the doors and the workspace name stay lit above
/// it and you can see the thing it describes is still there; it carries
/// the `surface` fill, a rounded leading corner and a shadow, so it
/// reads as laid ON the desk rather than as a place you went to. The
/// library takes the opposite treatment — see LibraryPlace below.
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
            .padding(.top, 10)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: LivTheme.radiusLg,
                    bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(LivTheme.surface)
                .ignoresSafeArea(edges: .bottom)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: -6, y: 0)
            .padding(.top, LivRow.topChrome)
        // VoiceOver's two-finger scrub, Voice Control's escape.
        .accessibilityAction(.escape, onDismiss)
        // No .transition: DeskHost positions these with an offset that
        // follows the finger, and a transition on top of it would move
        // the panel twice (owner, 2026-08-08).
    }
}

/// The library: a PLACE, the desk's peer — not a panel of it (owner,
/// 2026-08-15: "the left 'panel' is really a separate main place of the
/// app, the other being desk").
///
/// So it wears the app's own GROUND, the same `canvas` the desk stands
/// on, edge to edge and corner to corner: two rooms on one floor. No
/// card fill, no rounded corner, no shadow — nothing that would say
/// "something laid over something else". It arrives by pushing the desk
/// out of the way (rev 23), which is the motion half of the same idea.
struct LibraryPlace<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LivTheme.canvas.ignoresSafeArea())
            .accessibilityAction(.escape, onDismiss)
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

    /// The two bands (rev 6): global views see the whole box; workspace
    /// views wear the active workspace's lens.
    private let globalViews: [Feature] = [.today, .inbox]
    private let workspaceViews: [Feature] = [.calendar, .tasks, .everything]

    var body: some View {
        LibraryPlace(onDismiss: onDismiss) {
            VStack(spacing: 0) {
                topBand
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
                        SectionLabel("All workspaces")
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        ForEach(globalViews) { feature in
                            row(feature.title, glyph: feature.glyph) {
                                open(feature)
                            }
                        }

                        // Not the workspace's NAME any more — the button
                        // floating above this panel says that, and saying
                        // it twice on one screen is what the calendar's
                        // date row was doing. These two labels say the
                        // thing the name never did: which lists ignore the
                        // workspace and which wear it.
                        SectionLabel("This workspace")
                            .padding(.top, 22)
                            .padding(.bottom, 2)
                        ForEach(workspaceViews) { feature in
                            row(feature.title, glyph: feature.glyph) {
                                open(feature)
                            }
                        }
                        // Saved filters live HERE, not inside the workspace
                        // sheet — a filter is not a workspace, and this is
                        // where you already come to change what you are
                        // looking at (owner, 2026-08-11). The band is
                        // absent until there is one to show.
                        SectionLabel("Filters")
                            .padding(.top, 18)
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

    /// The library's OWN top band — the same 56pt the desk's chrome
    /// owns, so the two rooms' tops line up, and the pinned workspace
    /// button lands inside a band this place paints rather than over a
    /// hole cut in its list. Empty on purpose: the button is the only
    /// thing that belongs here.
    private var topBand: some View {
        HStack(spacing: 0) {
            // Back to the library's own list. Only there is anything to
            // go back FROM — on the list itself the band is empty, and
            // the workspace button floats in the middle of it.
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: LivRow.topChrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }

    private func open(_ feature: Feature) {
        desk.featureShown = feature
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
