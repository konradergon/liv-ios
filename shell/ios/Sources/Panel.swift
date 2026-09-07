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
            // THE SAME TOP A VIEW HAS (owner, 2026-08-17: "in the left
            // sidebar it is opaque at the top — do the same as you did
            // for views here"): the list runs under the clock and fades
            // out behind it. What was here instead: 56pt of empty band
            // with a hairline under it, which read as a bar that was not
            // one.
            // ONLY THE STATUS BAR. `LivTopScrim()`'s default also
            // reserves the 52pt chrome row, which is right on the desk —
            // the library door floats there — and wrong here, where
            // nothing floats over the panel at all. It pushed the first
            // row a sixth of the way down a panel the owner had already
            // called too empty at the top (2026-08-28: "In the panel,
            // there is a huge cut-off that needs to go").
            //
            // NEVER DERIVE AN INSET'S HEIGHT FROM THE SAFE AREA. A
            // `.safeAreaInset` that does feeds itself: AttributeGraph
            // reports a cycle and the surface stops repainting while its
            // body keeps evaluating perfectly (2026-08-23, half a day
            // and eight innocent suspects). `LivTopScrim` reads a
            // literal, and so must anything added beside it.
            .safeAreaInset(edge: .top) { LivTopScrim(underChrome: false) }
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
            .background(LivTheme.panel)
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
        SidePanel(onDismiss: onDismiss, width: LivPanel.width) {
            list
        }
    }

    private var list: some View {
        // ONE walk of the box per render. `counts` used to be a computed
        // property, so every row that read it built a fresh ViewCounts —
        // seven walks per render, which is the exact thing its own doc
        // says it avoids (found 2026-08-27).
        let counts = ViewCounts(box: box, lens: workspaces)
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
                        // TAPPING THE VIEW YOU ARE IN GOES TO ITS ROOT.
                        //
                        // Notes' root is the LIST of notes; a document is
                        // a tab on the desk, and the desk is app-wide, so
                        // once any note was open Notes always drew the
                        // document and the list could not be reached at
                        // all without closing every tab (owner,
                        // 2026-08-31: "you can't access note list without
                        // closing all note tabs"). There was no door.
                        //
                        // This is the phone's own idiom — tap the tab you
                        // are already on to go to its root — and it keeps
                        // the other half working: arriving at Notes from
                        // ANOTHER view still restores the document you
                        // left, and the bar's numbered box is still how
                        // you get back to it from the list.
                        if desk.state == feature {
                            desk.showList()
                        } else {
                            desk.go(feature)
                        }
                        onDismiss()
                    }
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
                        workspaces.activeFilterId =
                            workspaces.activeFilterId == view.id ? nil : view.id
                        onDismiss()
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
                // The last rows must be able to clear the foot, or a
                // long filter list ends underneath it with no way to
                // scroll further.
                Color.clear.frame(height: LivPanel.row)
            }
        }
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
        .overlay(alignment: .bottom) { foot(counts) }
        .livOverlay(LivOverlay.library)
    }

    /// THE FOOT: the workspace, what it holds, and the way to settings.
    ///
    /// Obsidian's shape, which the owner pointed at: the name, a quiet
    /// line under it saying what is inside, and a gear beside it. It is
    /// pinned rather than scrolling with the list, because it is not a
    /// place in the list — it says which box you are in.
    ///
    /// This reverses 2026-08-17's "Settings is the last row, not a
    /// pinned foot", whose argument was that a pinned row plus the
    /// global bar was one fixed layer too many. The bar now slides away
    /// on scroll, so the objection is gone.
    private func foot(_ counts: ViewCounts) -> some View {
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
                    Text(counts.foot)
                        .font(.system(size: LivType.label))
                        .foregroundStyle(LivTheme.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // A CIRCLE, one step of tone off the panel it sits on — the
            // shape both references use for the settings key, and the
            // reason a same-coloured control still reads as a control.
            Button(action: onSettings) {
                LivIcon(glyph: .settings, color: LivTheme.text2, size: 22)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(LivTheme.panel2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.leading, LivPanel.inset)
        .padding(.trailing, LivPanel.litInset)
        .padding(.bottom, 4)
        // NO HAIRLINE. The reference panel has no divider anywhere in it
        // — a full-width scan of every row found none — and the fade
        // above already says the list continues underneath.
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
    private var notes = 0
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
            case .note: notes += 1
            case .task: tasks += 1
            case .event: events += 1
            case .capture: inbox += 1
            default: break
            }
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
        case .notes: return shown(notes)
        case .tasks: return shown(tasks)
        case .inbox: return shown(inbox)
        case .calendar: return shown(events)
        case .everything: return shown(everything)
        case .today: return shown(today)
        }
    }

    /// What the workspace holds, and HOW MUCH OF IT IS SORTED. Obsidian's
    /// foot says how big the vault is; Liv's says how much is unfiled,
    /// which is the product page's second success test (2026-09-06).
    var foot: String {
        let items = "\(everything) item\(everything == 1 ? "" : "s")"
        return unfiled > 0 ? items + " · \(unfiled) unfiled" : items
    }
}
