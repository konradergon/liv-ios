// liv iOS — the side panel (design/ios.md §6 rev 6, owner 2026-08-03).
// The app's mental model is three zones:
//
//   LEFT  — the library: everything about the APP. The global views,
//           the workspace's views, the workspace switcher, Settings.
//   CENTER — the desk: ONE editable thing. Tabs hold notes and nothing
//           else — a view is a visit, a note is a tab.
//   RIGHT — everything about THIS note. It DESCRIBES; the verbs live in
//           the desk's ••• menu.
//
// SINGULAR since 2026-08-29: the right-hand zone became a CARD, not a
// panel (Desk.swift, "One panel left"), so `SidePanel` below has exactly
// one caller — the library. Rev 6 made both full-screen (Notesnook's
// layout was the model); the library was pulled back on 2026-08-23
// (owner: "Panel should not be full screen!") and stops at
// LivPanel.width, leaving a sliver of the desk.
//
// It is swiped into from anywhere — the swipe lives on DeskHost, one
// gesture for open and close, and it is also the way out: it carries no
// close button.
//
// (Header rewritten 2026-09-07. It still described two live panels, a
// properties panel standing "on the right, it does not float over
// anything", and paint that "waits for the surface pass" — the card
// landed on 2026-08-29 and the surface passes shipped.)

import SwiftUI

// MARK: - the slide-over container

/// The app's own ground, no radius, no shadow, no inset: a place you
/// go, not a thing that floats over one. It pushes the desk aside
/// rather than covering it.
///
/// It was written as ONE RECIPE FOR BOTH SURFACES (owner, 2026-08-15:
/// "have the base appearance same as library"), and it carried a
/// `side:` and an optional `width` so the properties panel could stand
/// on the right in the same clothes. That second caller went on
/// 2026-08-29, when properties became a card — so both parameters were
/// carrying a shape nothing asked for, and every reader had to work out
/// which of the two branches ran. They were removed on 2026-09-07
/// (standing rule 6). Bringing a right-hand panel back means mirroring
/// two constants, which the comments below name.
///
/// NO close button. It had a 40pt band of its own holding one chevron,
/// then rode the first row, where it landed almost inside the title
/// (owner, 2026-08-10: "you probably should get rid of the collapse
/// buttons"). A panel is DRAGGED back — the gesture the owner asked for
/// on 2026-08-08, and the same one that opens it. The escape action
/// below is what remains for anyone not using a finger.
struct SidePanel<Content: View>: View {
    let onDismiss: () -> Void
    /// How wide the panel stands, leaving the rest of the desk showing.
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // NOTHING IS RESERVED HERE. The room the rows come to rest
            // in is a content margin on the list itself (`list`), and
            // the fade is the overlay at the foot of this chain. Room
            // and paint are two jobs; one thing doing both is what drew
            // over the first row for four rounds.
            //
            // Two reservations were tried here and both are gone: a
            // `.safeAreaInset`, which the `.ignoresSafeArea()` below
            // discards — that modifier's job IS to throw the safe area
            // away, and an inset is the safe area — and a clear block at
            // the head of the list, which is content and so scrolls
            // away, taking the first row up under the fade with it.
            //
            // NO BOTTOM INSET: the library's own foot floats and its
            // list runs under it. There was one here until 2026-09-07,
            // reserving `LivBar.room` when `width` was nil — the
            // properties panel's branch, and nil since that panel became
            // a card.
            //
            // A PANEL, not a curtain (owner, 2026-08-18): one step of
            // tone above the canvas, flat — no shadow, no gradient, no
            // border.
            .background(LivTheme.surface)
            // WIDTH FIRST, THEN THE LEADING PIN, THEN the safe area.
            // Painting the background with `.ignoresSafeArea()` on the
            // COLOUR spreads it over the whole window whatever frame
            // follows, so the narrow panel comes out full-screen with its
            // rows centred. Order is the whole of it.
            .frame(width: width)
            // AN EDGE, because the shadow never drew one.
            //
            // Sampled across `library.png` at y=500: the panel holds
            // #232323 to x=319.67 and the desk's #1A1A1A starts at
            // x=320.0 — a hard one-pixel step with no intermediate value
            // anywhere in a 40pt band, where a radius-18 shadow would
            // ramp through a dozen. It does not draw because the desk's
            // Group has no zIndex (0) while this panel is zIndex 1, so
            // the shadow paints UNDER an opaque surface. The app's
            // largest depth event — 320pt of panel over the whole screen
            // — was arriving at 1.07:1, less definition than a list
            // separator. A hairline is 1.50:1 and costs no saturation.
            //
            // The panel stands on the LEADING edge, so its hairline is
            // on the TRAILING one — the two constants below are the pair
            // to mirror if a right-hand panel ever wants this recipe.
            .overlay(alignment: .trailing) {
                Rectangle().fill(LivTheme.border2).frame(width: 0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ignoresSafeArea()
            // THE FADE, in the panel's own ground, starting at the
            // VERY TOP — above the clock, which is why `LivTopScrim`
            // ignores the safe area itself (owner, 2026-09-16: "now the
            // fade is starting below the very top and the clock").
            //
            // It draws only. The rows' room is a content margin on the
            // list below; a band that did both is what covered the first
            // row for four rounds.
            .overlay(alignment: .topLeading) {
                LivTopScrim(ground: LivTheme.surface)
                    .frame(width: width)
            }
            // VoiceOver's two-finger scrub, Voice Control's escape.
            .accessibilityAction(.escape, onDismiss)
            // No .transition: DeskHost positions these with an offset
            // that follows the finger, and a transition on top of it
            // would move the panel twice (owner, 2026-08-08).
    }
}

// MARK: - the library (left)

/// The application, in one place (rev 6, Notesnook's sidebar as the
/// model): the views, then the WORKSPACES — every one, the one you are in
/// lit — then, pinned at the bottom, Trash and Settings. Nothing in here is
/// about the currently open note.
///
/// OPTION A (clearer spec, 2026-09-29; the owner: the panel "looks like an
/// incomplete list of items since the bottom half is empty", then "go with
/// A"). The workspaces were a card that rose from a button at the foot;
/// they are rows in the list now, the list fills the panel, and the foot
/// holds the two house-keeping doors.
struct LibraryPanel: View {
    let onDismiss: () -> Void
    /// ALL presented by DESKHOST, not here: anything that closes this
    /// panel mid-use (workspace adopt(), a notification tap routing
    /// desk.open) would tear down a sheet hung on it (audits 2026-08-01,
    /// 2026-08-04). The form is new with nil, an edit with an id.
    let onWorkspaceForm: (LivEntityID?) -> Void
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
        SidePanel(onDismiss: onDismiss, width: LivPanel.width) {
            list
        }
    }

    private var list: some View {
        let counts = ViewCounts(box.lists.counts)
        // NO bottom inset and no divider: the rows run all the way down
        // and are occluded by the floating foot, fading over the last
        // stretch. That is the reference's own arrangement, and it is
        // what stops the foot reading as a second bar.
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // THE VIEWS ARE BACK (team, 2026-08-22 — see
                // design/tabs.md). They left on 2026-08-18 for the bar's
                // own key, on the argument that a drawer is the wrong
                // home for what you touch on every navigation. Under a
                // tab-centric model the argument inverts: a view now
                // decides what the TABS hold, so it is picked once and
                // then lived in.
                //
                // Notesnook's shape, which the owner attached: a
                // monochrome glyph, the name, a count on the right, and
                // the one you are in wearing a soft fill.
                ForEach(Feature.inOrder) { feature in
                    row(
                        feature.title,
                        glyph: feature.glyph,
                        detail: counts.of(feature),
                        on: desk.state == feature
                    ) {
                        // ONE ROW, ONE MEANING: the view you named, with
                        // nothing over it. Tapping the view you are
                        // already in lays the document down, which is the
                        // phone's own idiom for going to a tab's root.
                        //
                        // This used to need its own verb (`goToRoot`)
                        // because a document was drawn by Notes wearing
                        // it, so arriving at a view and getting out of a
                        // document were two different moves. Since the
                        // desk holds its own `shown` (2026-09-10) they
                        // are one, and `go` is the whole rule.
                        //
                        // The note is not closed — the bar's numbered box
                        // is still how you get back to it, from any view.
                        desk.go(feature)
                        onDismiss()
                    }
                    // THE GROUPS ARE THE ORDER (`Feature.groups`, owner
                    // 2026-09-10): Today, Inbox and Everything are
                    // windows onto the box; Calendar and Tasks are the
                    // two you add to. One empty half-row separates them,
                    // the same separator Trash uses
                    // below, and no label — a heading over two rows
                    // costs more than the rows do.
                    // 12 between the two groups (clearer spec): the same
                    // kind of row on both sides, so a small step.
                    .padding(.top, Feature.startsGroup(feature) ? LivPanel.groupGap : 0)
                }

                workspaceList
                // The last row must be able to clear the foot.
                Color.clear.frame(height: LivPanelFoot.circle + LivBar.gap + LivSafeArea.bottom)
            }
        }
        // THE CLOCK'S ROOM, and only the clock's.
        //
        // The rows ran to the panel's real top edge and the first one
        // sat beside the status bar (owner, 2026-09-16: "the panel rows
        // (the buttons) now begin at the very top where the clock is").
        // Nothing floats over this panel, so unlike a view it needs no
        // room for door buttons — the status bar is the whole of it.
        //
        // A content margin, because room that is CONTENT scrolls away
        // and room that is a `.safeAreaInset` is discarded by the
        // `.ignoresSafeArea()` in `SidePanel`. Both were tried. This is
        // what `CalendarView` reserves its hour label with.
        //
        // AS FAR DOWN AS THE FADE REACHES, so the first row is clear ink
        // at rest and only dims on its way up (owner, 2026-09-16: "move
        // down the panel buttons slightly"). It was the status bar
        // alone, which left the top row sitting in the ramp.
        .contentMargins(.top, LivTopScrim.height, for: .scrollContent)
        // The rows dissolve as they reach the foot rather than stopping
        // dead behind it.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.90),
                    .init(color: .black.opacity(0.15), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) { foot }
        .livOverlay(LivOverlay.library)
    }

    /// THE WORKSPACES, as rows (option A): each one its mark and its name,
    /// the one you are in lit — the panel's second lit row, one per list —
    /// then All workspaces and New workspace. Holding a workspace offers
    /// Edit and Trash, as the rows of the old card did.
    ///
    /// NO COUNTS HERE. A count per workspace needs that workspace's lens
    /// read from the core — a query per workspace per render (standing
    /// rule 2). The views keep theirs.
    @ViewBuilder private var workspaceList: some View {
        Text("Workspaces")
            .font(.system(size: LivType.label, weight: .medium))
            .foregroundStyle(LivTheme.text2)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, LivPanel.inset)
            .padding(.top, LivPanel.labelTop)
            .padding(.bottom, LivPanel.labelBottom)
        ForEach(workspaces.workspaces) { ws in
            row(ws.display, on: workspaces.activeId == ws.id) {
                LivWorkspaceMark(workspace: ws, size: LivCards.glyph)
            } action: {
                workspaces.setActive(ws.id)
                onDismiss()
            }
            .contextMenu {
                Button {
                    onWorkspaceForm(ws.id)
                } label: {
                    Label("Edit workspace", systemImage: "slider.horizontal.3")
                }
                Button(role: .destructive) {
                    workspaces.forgetQuery(ws.id)
                    if workspaces.activeId == ws.id { workspaces.setActive(.absent) }
                    box.trashWorkspace(ws.id)
                } label: {
                    Label("Trash workspace", systemImage: "trash")
                }
            }
        }
        row("All workspaces", on: workspaces.activeId.isAbsent) {
            LivWorkspaceMark(workspace: nil, size: LivCards.glyph)
        } action: {
            workspaces.setActive(.absent)
            onDismiss()
        }
        // A PLUS SET LIKE A LETTER, and the words a step quieter: this row
        // makes a workspace rather than going to one.
        row("New workspace", ink: LivTheme.text2) {
            Text("+")
                .font(.system(size: (LivCards.glyph * LivPen.letter).rounded(), weight: .medium))
                .foregroundStyle(LivTheme.text2)
                .frame(width: LivCards.glyph, height: LivCards.glyph)
        } action: {
            onWorkspaceForm(nil)
        }
    }

    /// THE FOOT: two circles, Trash on the left and Settings on the right —
    /// the two doors that are house-keeping rather than places you work.
    /// Pinned rather than scrolling with the list. Trash was its glyph and
    /// its word for an hour (owner, 2026-09-29: "trash should have a button
    /// like settings").
    ///
    /// It held the workspace — its mark, its name and what it held, a
    /// button that raised the Workspaces card — until the panel listed the
    /// workspaces itself (option A, 2026-09-29).
    private var foot: some View {
        HStack(spacing: LivPanelFoot.gap) {
            footKey(.trash, "Trash", onTrash)
            Spacer(minLength: 0)

            footKey(.settings, "Settings", onSettings)
        }
        .padding(.horizontal, LivPanelFoot.inset)
        .padding(.bottom, LivSafeArea.bottom + LivBar.gap)
        // NO HAIRLINE. The reference panel has no divider anywhere in it
        // — a full-width scan of every row found none — and the fade
        // above already says the list continues underneath.
    }

    /// A CIRCLE, one step of tone off the panel it sits on — the shape
    /// both references use for the settings key, and the reason a
    /// same-coloured control still reads as a control.
    private func footKey(
        _ glyph: LivGlyph, _ label: String, _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            LivIcon(glyph: glyph, color: LivTheme.text2, size: LivPanelFoot.glyph)
                .frame(width: LivPanelFoot.circle, height: LivPanelFoot.circle)
                .background(Circle().fill(LivTheme.panel2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// One list row. NO hairline: a line between rows is what a FORM
    /// does — it is what the properties card's rules mean one screen to
    /// the right — and this is a list of places to go, held apart by its section
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
        _ label: String, glyph: LivGlyph, detail: String? = nil, on: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        row(label, detail: detail, on: on) {
            LivIcon(glyph: glyph, color: LivTheme.text, size: LivCards.glyph)
        } action: {
            action()
        }
    }

    private func row(
        _ label: String, detail: String? = nil,
        /// The row you are in. The reference marks it with a FILL and
        /// nothing else — same ink, same weight, no accent, no dot, no
        /// border — and the fill is the row plus its padding rather than
        /// a box drawn around the words.
        on: Bool = false,
        ink: Color = LivTheme.text,
        @ViewBuilder lead: () -> some View,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            // ONE COLUMN AT 28pt for the whole panel: the mark starts
            // there, and a 22pt mark plus a 16pt gap puts every label at
            // 66. Section text aligns to the MARK and not to the label —
            // that is what makes two lists read as one column.
            HStack(spacing: 16) {
                lead()
                Text(label)
                    .font(.system(size: LivType.body, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail {
                    // The count rides INSIDE the grid rather than
                    // growing the row — the reference's own note about
                    // trailing elements.
                    Text(detail)
                        .font(.system(size: LivType.body).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                }
            }
            .padding(.horizontal, LivPanel.inset)
            .frame(height: LivPanel.row)
            .background(alignment: .center) {
                if on {
                    RoundedRectangle(cornerRadius: LivPanel.litRadius, style: .continuous)
                        .fill(LivTheme.selection)
                        .frame(height: LivPanel.litHeight)
                        .padding(.horizontal, LivPanel.litInset)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - what each view holds

/// The counts beside the view rows: Rust's (`liv_view_library`,
/// `surface/src/library.rs`), read in the same pass as the lists they
/// count, so the number beside a view is the number of rows that view
/// shows. Unsorted's ignores the workspace, as its list does; every other
/// count wears it.
///
/// This was a walk of the box in Swift with its own copy of each screen's
/// rule, and the panel said 8 while Unsorted said nothing — twice, in two
/// different shapes (2026-09-15, again 2026-09-18).
struct ViewCounts {
    let counts: LivCounts

    init(_ counts: LivCounts) {
        self.counts = counts
    }

    /// A zero is not worth drawing. Notesnook shows one; this app's own
    /// rule is that a count which is always there stops being read
    /// (owner, 2026-08-18: "eliminate unnecessary small text").
    private func shown(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return "\(n)"
    }

    func of(_ feature: Feature) -> String? {
        switch feature {
        case .tasks: return shown(counts.tasks)
        case .inbox: return shown(counts.unsorted)
        case .calendar: return shown(counts.events)
        case .everything: return shown(counts.notes)
        case .today: return shown(counts.today)
        }
    }

}
