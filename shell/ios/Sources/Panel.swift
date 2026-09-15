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
struct SidePanel<Content: View, Head: View>: View {
    let onDismiss: () -> Void
    /// How wide the panel stands, leaving the rest of the desk showing.
    let width: CGFloat
    /// What stands at the top, pinned, on the opaque part of the fade —
    /// the library's workspace head. Drawn by the caller because it is
    /// the caller's business; placed here because where it goes is the
    /// panel's.
    let head: Head
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
            // THE HEAD AND THE FADE, on the panel's real top edge.
            //
            // The workspace stands at the head (owner, 2026-09-16: the
            // panel that mirrors the model — "a workspace is a filter
            // plus a desk", so the thing that scopes everything is drawn
            // ABOVE everything it scopes, not in a foot). It sits at the
            // same height as the library door on the desk: the same
            // 44pt row with the same 6pt above it, so the two line up
            // across the seam.
            //
            // Under it, the fade — and the fade is opaque through the
            // whole chrome row rather than the status bar alone, because
            // the head is words and rows scroll up under it. `LivTopScrim`
            // ignores the safe area itself, so it begins at the very
            // top (owner, 2026-09-16); the head is placed by the same
            // number, once.
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    LivTopScrim(ground: LivTheme.surface, solid: LivRow.topInset)
                    head
                        .padding(.top, LivSafeArea.top + 6)
                }
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
        let counts = ViewCounts(box: box, lens: workspaces)
        return SidePanel(onDismiss: onDismiss, width: LivPanel.width, head: head(counts)) {
            list(counts)
        }
    }

    /// ONE walk of the box per render, passed in from `body` so the head
    /// and the rows read the same numbers. `counts` used to be a computed
    /// property, so every row that read it built a fresh ViewCounts —
    /// seven walks per render (found 2026-08-27).
    private func list(_ counts: ViewCounts) -> some View {
        ScrollView {
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
                    // the same separator the saved filters and Trash use
                    // below, and no label — a heading over two rows
                    // costs more than the rows do.
                    .padding(.top, Feature.startsGroup(feature) ? LivPanel.row / 2 : 0)
                }

                // NO SECTION LABELS (owner, 2026-08-18: "eliminate
                // unnecessary small text and labels"). One empty row-slot
                // does the separating — which is also exactly how the
                // reference spaces its one section heading.
                ForEach(Array(workspaces.filters.enumerated()), id: \.element.id) { i, view in
                    row(
                        view.display,
                        glyph: .filter,
                        on: workspaces.activeFilterId == view.id
                    ) {
                        // **A FILTER IS NOT A PLACE, so the panel stays.**
                        //
                        // Every row above this one is somewhere you GO,
                        // and going somewhere closes the drawer you went
                        // from. A filter is a lens over the view you are
                        // already standing in — it narrows what you were
                        // looking at rather than taking you anywhere, and
                        // it is a TOGGLE: tapping it again turns it off.
                        // Closing on it said "you have arrived" about a
                        // move that never happened (owner, 2026-09-15:
                        // "it kind of gives that incorrect feeling, even
                        // though it opens the place you were in").
                        //
                        // Staying open is also what makes the toggle
                        // usable: the row's own mark is the confirmation,
                        // and the counts beside every row above are
                        // already counted THROUGH the lens, so the whole
                        // list answers as you press it.
                        workspaces.activeFilterId =
                            workspaces.activeFilterId == view.id ? nil : view.id
                    }
                    .padding(.top, i == 0 ? LivPanel.row / 2 : 0)
                }
                row("New filter", glyph: .plus) {
                    desk.composeFilter = true
                    onWorkspace()
                }
                // Trash stays in the list — it is house-keeping, not a
                // place you work. Settings moved to the foot with the
                // workspace (team, 2026-08-22).
                row("Trash", glyph: .trash) { onTrash() }
                    .padding(.top, LivPanel.row / 2)
            }
        }
        // THE ROOM THE HEAD AND THE FADE TAKE, so the first row is clear
        // ink at rest and only dims on its way up. Asked of the scrim
        // with the same `solid` the overlay paints, so the two cannot
        // drift.
        //
        // A content margin, because room that is CONTENT scrolls away
        // and room that is a `.safeAreaInset` is discarded by the
        // `.ignoresSafeArea()` in `SidePanel`. Both were tried. This is
        // what `CalendarView` reserves its hour label with.
        .contentMargins(.top, LivTopScrim.height(solid: LivRow.topInset), for: .scrollContent)
        // NO FOOT, NO BOTTOM FADE (2026-09-16). The workspace moved to
        // the head, the gear went with it, and nothing floats over the
        // bottom of this panel any more — so the mask that dissolved the
        // rows into a foot, and the empty row that let the last one
        // clear it, both went (standing rule 6).
        .livOverlay(LivOverlay.library)
    }

    /// THE HEAD: which workspace, what it holds, and the way to settings.
    ///
    /// It was the foot, and Obsidian's shape — the name, a quiet line
    /// under it saying what is inside, and a gear beside it — is
    /// unchanged. What changed is WHERE (owner, 2026-09-16). A workspace
    /// is a filter plus a desk: it scopes every row in this panel, and a
    /// scope drawn at the bottom of the thing it scopes reads as an
    /// afterthought. At the head it reads as what it is — "you are in
    /// Work; everything below is Work's."
    ///
    /// The line under the name says three things. How many notes, which
    /// is the workspace's substance. How many are unfiled, which is the
    /// product page's second success test (2026-09-06). And how many
    /// are OPEN — the desk, which is the half of "filter plus desk" that
    /// had no affordance anywhere. A saved filter has no desk, so it
    /// never says "open", and that word is now the visible difference
    /// between the two.
    private func head(_ counts: ViewCounts) -> some View {
        HStack(spacing: 8) {
            Button {
                onWorkspace()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(workspaces.activeName)
                            .font(.system(size: LivType.body, weight: .semibold))
                            .foregroundStyle(LivTheme.text)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: LivType.caption, weight: .semibold))
                            .foregroundStyle(LivTheme.text2)
                    }
                    Text(counts.held + " · \(desk.liveTabs.count) open")
                        .font(.system(size: LivType.label))
                        .foregroundStyle(LivTheme.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .livDoor()
            // NAMED, because its label was DERIVED — the workspace's own
            // name plus the line under it, so it changed with the box and
            // could not be tapped by a driver. "Switch workspace" and not
            // "Workspace": the card this opens draws that word as its
            // title, and a label matching two elements is refused by
            // `axe tap` (the third such collision in two days,
            // 2026-09-05).
            .accessibilityLabel("Switch workspace")

            // A CIRCLE, one step of tone off the panel it sits on — the
            // shape both references use for the settings key, and the
            // reason a same-coloured control still reads as a control.
            // 44, the library door's own size, so the two stand level.
            Button(action: onSettings) {
                LivIcon(glyph: .settings, color: LivTheme.text2, size: 22)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LivTheme.panel2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(height: 44)
        .padding(.leading, LivPanel.inset)
        .padding(.trailing, LivPanel.litInset)
        // NO HAIRLINE. The reference panel has no divider anywhere in it
        // — a full-width scan of every row found none — and the fade
        // under this already says the list continues beneath.
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
        /// The row you are in. The reference marks it with a FILL and
        /// nothing else — same ink, same weight, no accent, no dot, no
        /// border — and the fill is the row plus its padding rather than
        /// a box drawn around the words.
        on: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            // ONE COLUMN AT 28pt for the whole panel: the glyph box
            // starts there, and a 24pt box plus a 16pt gap puts every
            // label at 68. Section text, when there is any, aligns to
            // the GLYPH and not to the label — that is what makes two
            // different lists read as one column.
            HStack(spacing: 16) {
                LivIcon(glyph: glyph, color: LivTheme.text, size: 21)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: LivType.body, weight: .medium))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail {
                    // The count rides INSIDE the grid rather than
                    // growing the row — the reference's own note about
                    // trailing elements.
                    Text(detail)
                        .font(.system(size: LivType.body))
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

/// The counts beside the view rows, and the line under the workspace.
///
/// Counted THROUGH THE LENS. With a filter on, the panel used to say
/// "Everything 246" over a screen showing nothing (found 2026-08-27 by
/// `drive.sh lens`) — the count answered a question nobody had asked.
///
/// **One pass over the box, not one per row.** Six rows each asking the
/// box a question would be the same shape as the four defects
/// `design/core.md` §10 records — rebuild on read, once per render. This
/// walks the entities once and answers from what it found.
struct ViewCounts {
    private var tasks = 0
    private var inbox = 0
    private var events = 0
    private var everything = 0
    private var today = 0
    /// Rows with no area cell — the pile that is not yet sorted.
    private var unfiled = 0

    init(box: BoxModel, lens: WorkspaceModel) {
        let now = Civil.todayDay()
        for row in box.entities.values where row.trashed != true {
            // The same gate every surface uses, so the number beside a
            // view is the number of rows that view will show.
            guard lens.admits(row) else { continue }
            everything += 1
            if !(row.cells ?? []).contains(where: { $0.property == "area" && !($0.value ?? "").isEmpty }) {
                unfiled += 1
            }
            switch LivKind.of(row) {
            case .task: tasks += 1
            case .event: events += 1
            default: break
            }
            // THE SAME PREDICATE THE INBOX LISTS BY, not a second
            // reading of the same pile — see `livIsScrap`. This counted
            // every `.capture` including the empty ones, while the
            // screen asked for words in it as well.
            if livIsScrap(row) { inbox += 1 }
            // Today counts what is DUE today or earlier and still open —
            // the same question the Today surface asks.
            if livCanTick(row), let due = row.due, due > 0, Civil.day(of: due) <= now {
                today += 1
            }
        }
    }

    /// A zero is not worth drawing. Notesnook shows one; this app's own
    /// rule is that a count which is always there stops being read
    /// (owner, 2026-08-18: "eliminate unnecessary small text").
    private func shown(_ n: Int) -> String? {
        n > 0 ? "\(n)" : nil
    }

    func of(_ feature: Feature) -> String? {
        switch feature {
        case .tasks: return shown(tasks)
        case .inbox: return shown(inbox)
        case .calendar: return shown(events)
        case .everything: return shown(everything)
        case .today: return shown(today)
        }
    }

    /// What the workspace holds, and HOW MUCH OF IT IS SORTED. Obsidian's
    /// head says how big the vault is; Liv's says how much is unfiled,
    /// which is the product page's second success test (2026-09-06).
    /// "Notes", not "items": a workspace is made of notes, and a task or
    /// an event is a note with a status or a date (Navigate.swift).
    var held: String {
        let notes = "\(everything) note\(everything == 1 ? "" : "s")"
        return unfiled > 0 ? notes + " · \(unfiled) unfiled" : notes
    }
}
