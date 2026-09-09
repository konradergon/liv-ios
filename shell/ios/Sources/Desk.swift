// liv iOS — Desk view (design/ios.md §6): the active tab's body, the
// new-tab capture door, and the tab switcher (Obsidian's, verbatim in
// structure; Liv's soul). Tabs are shell state — every mutation still
// rides the one BoxModel, act-then-refresh.

import SwiftUI
import UIKit

// MARK: - DeskHost

/// The desk body: the switcher while it is up, else the active tab.
/// `.id(tab.id)` resets per-tab @State when focus moves between tabs.
struct DeskHost: View {
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel

    /// The bar and the pill retire under a keyboard, and they live here
    /// now (2026-09-08), so the watch does too — it was `RootView`'s
    /// while they were, and nothing else there read it.
    @StateObject private var keyboard = KeyboardWatch()

    /// The drag lives on the model now (the bar reads it too); this is
    /// the short name for it in here.
    private typealias PanelDrag = DeskModel.PanelDrag

    /// One transient acknowledgment chip: text, and an optional Undo verb
    /// (the trash chip carries one; a plain acknowledgment does not).
    @State private var chipText: String?
    @State private var chipUndo: (() -> Void)?
    /// Closes the double-tap window while a copy is in flight.
    @State private var copying = false
    /// What the ••• is handing to the rest of the phone (phase 7).
    @State private var share: SharePayload?
    /// The file picker, opened by the `+` menu's file row.
    @State private var picking = false
    /// Guards the create doors against a double tap while a write is in
    /// flight.
    @State private var creating = false

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let id = desk.openDoc, desk.state == .notes {
                    // Keyed by ENTITY: a serial capture rewrites the
                    // surface with a new entity, and per-entity @State
                    // (the seeded title) must reseed on that flip.
                    EntityTabBody(id: id).id(id).livSurface(LivSurface.document)
                } else if desk.state == .notes {
                    // NOTES' ROOT IS THE LIST AGAIN (2026-08-28).
                    //
                    // From 2026-08-24 it was the tab grid, on the
                    // owner's "make sure it replaces notes list". The
                    // argument against `NotesList` then was that search
                    // reaches what the grid cannot. Measured on the
                    // simulator four days later, that is not what
                    // happened: the grid draws `desk.liveTabs`, so Notes
                    // showed EIGHT of the box's hundred and thirty-four
                    // notes and offered no route at all to the other
                    // hundred and twenty-six. A surface named after a
                    // thing has to contain it.
                    //
                    // The grid keeps its real job — it is the tab
                    // switcher, opened by the numbered box on the bar.
                    // One is the shelf, the other is what is on the desk.
                    NotesList().livSurface(LivSurface.notes)
                } else {
                    // Another state entirely — Today, the calendar. The
                    // views draw themselves (FeatureLayer is gone with
                    // the layer it was).
                    FeatureBody(feature: desk.state)
                        .transition(LivMotion.surface)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // TO THE VERY TOP: the words run under the clock and the
            // battery, with the three glass controls floating over them
            // (owner, 2026-08-17). What must not land under the buttons
            // keeps `LivRow.topInset` for itself.
            .overlay(alignment: .top) { LivTopScrim() }
            // THE BAR IS PART OF THE SURFACE (owner, 2026-09-08: "the
            // bar should be 'part of' the right view").
            //
            // It was a sibling of the whole app body in `RootView`'s
            // ZStack, painted after it — so it floated over everything
            // there is, and every cover that had to appear ABOVE it had
            // to be hoisted out of the surface and re-hosted up there
            // beside it. Three were: the one menu, the record card, the
            // properties sheet. The workspace card was not, so it came
            // up UNDERNEATH the bar, scrim and all — the same bug the
            // menu had before it moved, with the reason still written
            // above `livMenu` in App.swift.
            //
            // Inside the card, that whole class of bug is gone rather
            // than fixed case by case: anything a surface puts over
            // itself is over its bar, because its bar is part of it.
            // Three special cases go with it — the bar no longer needs
            // its own `deskShift` (the card travels and it travels
            // with it), the library panel covers it by being a later
            // sibling instead of by the bar retiring, and the wash that
            // takes the desk's touches takes the bar's too, so a bar in
            // the sliver is no longer live under a panel that says it
            // has your attention.
            .overlay(alignment: .bottom) { surfaceFoot }
            .ignoresSafeArea(edges: .top)
            // THE DESK AS A CARD. The panel stops 100pt short of the
            // right edge (owner, 2026-08-23: "Panel should not be full
            // screen!"), so the desk stays on screen beside it — pushed,
            // rounded off and washed back. Every number was measured
            // frame by frame off the owner's own reference clip; they
            // live in `LivPanel` with their source.
            //
            // The corner is a MASK, not a `clipShape`. The body
            // deliberately runs out of its own bounds at the top so the
            // words pass under the clock, and a clip is computed on those
            // bounds and cuts them off at the status bar.
            // ROUNDED ON THREE SIDES. The leading corners are SQUARE
            // while the panel is out, because they are the ones that
            // meet it: a curve there pulls away from the seam and leaves
            // a wedge of panel showing at the top and the bottom — the
            // "ugly gaps" the owner reported (2026-08-28). Butted flush,
            // there is nothing to see. The trailing corners keep the
            // device's radius, which is where the screen's own edge is.
            .mask {
                let meetsLeading = desk.panelOut > 0
                UnevenRoundedRectangle(
                    topLeadingRadius: meetsLeading ? 0 : LivPanel.deskRadius,
                    bottomLeadingRadius: meetsLeading ? 0 : LivPanel.deskRadius,
                    bottomTrailingRadius: LivPanel.deskRadius,
                    topTrailingRadius: LivPanel.deskRadius,
                    style: .continuous
                )
                .ignoresSafeArea()
            }
            // NO SHADOW. It was cast back onto the panel and never
            // arrived: the panel is `.zIndex(1)` and this Group has none
            // (0), so the shadow painted under an opaque surface. Two
            // days of the app's largest depth event being a hard
            // one-pixel step. The panel draws its own edge now
            // (Panel.swift), which is a line you can actually see.
            // A WASH, not a scrim: the reference fades the content to
            // ~50% and leaves the background alone, so this is the app's
            // own ground laid over the top. A black scrim in a dark theme
            // would just look like the screen switching off.
            //
            // IT ALSO TAKES THE TOUCHES. With the panel open you could
            // still reach the desk through the sliver and work it —
            // scroll a list, tick a task — behind a panel that says it
            // has your attention (owner, 2026-08-24). The reference does
            // not: tapping the pushed-aside content brings it back.
            //
            // So while the panel is showing, this layer is what your
            // finger meets, and its one job is to put the panel away.
            // That also gives the sliver the purpose it is drawn for —
            // it is the way back, and now it behaves like one.
            .overlay {
                let showing = desk.panelOut
                LivTheme.canvas
                    .opacity(LivPanel.wash * showing)
                    .contentShape(Rectangle())
                    // At rest this must be completely absent, or every
                    // tap on the desk would land here instead.
                    .allowsHitTesting(showing > 0)
                    .onTapGesture { closePanel() }
                    // AND THE DRAG, because this layer swallows it.
                    //
                    // The panel is dragged open and shut from anywhere
                    // (owner, 2026-08-08) by a recognizer on the window.
                    // Measured with a probe: a touch that starts in the
                    // sliver never reaches that recognizer once this
                    // overlay is live — SwiftUI claims it first — while
                    // one starting inside the panel still does. So the
                    // gesture is put back exactly where it was lost,
                    // rather than left quietly narrower than the rule
                    // says it is.
                    .gesture(
                        DragGesture(minimumDistance: 18)
                            .onEnded { g in
                                // Toward the panel's own edge closes it,
                                // and its edge is the leading one.
                                if g.translation.width < -40 { closePanel() }
                            }
                    )
                    // The desk is already hidden from VoiceOver behind a
                    // panel; this must not become the one thing it finds.
                    .accessibilityHidden(true)
            }
            .offset(x: desk.deskShift)
            .accessibilityHidden(anyPanel)

            // The doors (design/ios.md §6 rev 6): top-left opens the
            // LIBRARY, top-right the ••• holds the secondary verbs.
            //
            // The (i) PROPERTIES door is gone (owner, 2026-08-14). The
            // properties panel is dragged in from the right edge, from
            // anywhere, which is the gesture that opens it today and the
            // one that closes it — a button beside it was a second door
            // to one room (standing rule 4).
            HStack(spacing: 8) {
                // THE TOP-LEFT IS THE LIBRARY DOOR, always.
                //
                // It used to become a labelled "‹ Notes" inside a
                // document (owner, 2026-08-18). That is gone (owner,
                // 2026-08-24: "the old '< Notes' should be gone"), and
                // it should be: the bar below now carries a real `‹`
                // over the same way-back stack, and the numbered box
                // goes up to the grid. A labelled back beside them was a
                // second door to one room — the reason the (i)
                // properties door was deleted on 2026-08-14, and the
                // same standing rule 4.
                Button {
                    endEditing()
                    goToLibrary()
                } label: {
                    // THE SIZE GOES INSIDE THE LABEL. Applied outside, as
                    // `livTopButton` does, the accessibility element came
                    // out 396pt wide — the button plus the Spacer beside
                    // it — so its activation point sat in the middle of
                    // the screen and VoiceOver's "Library" overlapped the
                    // ••• at the far end of the row. Found by `drive.sh
                    // tour`, which could not open the panel from inside a
                    // note because the tap landed on the text.
                    PanelMark(color: LivTheme.text, open: desk.libraryShown, size: 24)
                        .livTopKeyShape()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Library")
                Spacer()
                // The ••• is the open DOCUMENT's menu — share, export,
                // trash — so it belongs to Docs and to nothing else.
                if desk.state == .notes, let id = desk.openDoc {
                    propertiesKey()
                    noteMenu(id)
                }
            }
            // EACH DOOR IS ITS OWN ELEMENT. Left alone, SwiftUI merged
            // the leading button with the `Spacer` next to it into one
            // 396pt-wide accessibility element whose activation point sat
            // in the middle of the note — so VoiceOver's "Library"
            // covered the ••• as well, and a tap by label landed on the
            // text. `.contain` says these are separate things in a row
            // (found by `drive.sh tour`, 2026-08-24).
            .accessibilityElement(children: .contain)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            // THEY TRAVEL WITH THE DESK. They used to fade out as the
            // panel arrived, which was invisible while the panel covered
            // the screen. Now that it stops 100pt short, the toggle rides
            // along in the sliver — and tapping it there is how the panel
            // closes, which is what the reference does.
            .offset(x: desk.deskShift)
            // …and they leave upward while you read, with the bar
            // (owner's clips, 2026-08-20). `topInset` is exactly the
            // band they own, clock included.
            .offset(y: desk.chromeAway ? -LivRow.topInset : 0)
            .accessibilityHidden(desk.libraryShown || desk.chromeAway)
            .zIndex(3)

            // The panels, drawn last so they cover doors and body alike.
            // Mounted while shown OR while a finger is dragging one, and
            // positioned by that drag — they follow the hand rather than
            // waiting for it to let go (owner, 2026-08-08).
            if desk.libraryDrawn || desk.panelDrag != nil {
                LibraryPanel(
                    onDismiss: { desk.setLibrary(false) },
                    onWorkspace: { desk.workspaceShown = true },
                    onSettings: { desk.settingsShown = true },
                    onTrash: { desk.trashShown = true }
                )
                .offset(x: panelOffset())
                // Exit transitions render BELOW later siblings without an
                // explicit z — the panel would vanish behind the desk
                // instead of sliding out (audit, 2026-08-01).
                .zIndex(1)
            }

        }
        .background(LivTheme.canvas)
        .onAppear {
            desk.createMenu = createMenu
            desk.createHere = createHere
            desk.newNote = createNote
            desk.catchText = catchText
        }
        .fileImporter(
            isPresented: $picking, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            FileImport.adopt(urls, box: box, workspaces: workspaces, desk: desk)
        }
        // The whole desk goes INERT while a drag is latched. This — not
        // anything at the UIKit layer — is what stops a drag from
        // pressing the button it started on: disabling a SwiftUI
        // control mid-press cancels the press, where touch
        // cancellation, recognizer exclusion and delayed delivery all
        // failed to reach SwiftUI's forwarding (each tried, each
        // beaten, 2026-08-09). A tap never latches, so taps are never
        // disabled.
        .disabled(desk.panelDrag != nil)
        // Both side panels are dragged in from ANYWHERE and back out the
        // same way, and they FOLLOW the finger (owner, 2026-08-08). The
        // drag is a real UIKit recognizer (PanelDrag.swift) because of a
        // flaw the owner caught in the SwiftUI version (2026-08-09):
        // "dragging over interactive elements should not trigger them."
        // A simultaneous SwiftUI drag runs alongside every button under
        // the finger — a drag that started on a library row both moved
        // the panel and opened Tasks. The recognizer cancels those
        // touches the instant the drag latches; a plain tap never
        // latches, so taps still press.
        .background(
            PanelDragInstaller(
                active: { desk.deskInFront && desk.menu == nil },
                mayClaim: { dx in claimPanel(dx) != nil },
                pagerZone: { desk.pagerZone },
                onLatch: { dx in
                    if let opening = claimPanel(dx) {
                        endEditing()
                        desk.panelDrag = PanelDrag(opening: opening, amount: dx)
                    }
                },
                onMove: { dx in desk.panelDrag?.amount = dx },
                onEnd: { dx, velocity in settleDrag(dx, velocity) }
            )
            .frame(width: 0, height: 0)
        )
        // The acknowledgment chip: a verb that changes something you can
        // no longer see (the copy, the trashed note) says so, briefly.
        .overlay(alignment: .top) {
            if let text = chipText {
                chip(text)
                    .padding(.top, LivRow.topInset)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        // FROM THE BOTTOM: the workspace button and "New filter" both
        // live at the FOOT of the library panel (team, 2026-08-22), and
        // this card was still falling from the top of the screen because
        // that is where the button used to be.
        .livSheet(from: .bottom, isPresented: $desk.workspaceShown) {
            WorkspaceSwitcher(onClose: { desk.workspaceShown = false })
                .livOverlay(LivOverlay.workspace)
                .environmentObject(box)
                .environmentObject(workspaces)
                .environmentObject(desk)
        }
        // Hung HERE so they survive whatever closes the library panel
        // mid-use; MODEL state so a notification tap can dismiss them
        // (audits 2026-08-04).
        .sheet(isPresented: $desk.settingsShown) { SettingsSheet() }
        .sheet(item: $share) { payload in
            ShareSheet(items: payload.items)
        }
    }

    /// THE SURFACE'S OWN FOOT: the bar, and the pill that stands on it.
    ///
    /// Both were mounted in `RootView` until 2026-09-08 and both carried
    /// `.offset(x: desk.deskShift)` by hand to fake travelling with a
    /// desk they were not part of. They are part of it now, so the
    /// offset is the card's and they inherit it.
    @ViewBuilder private var surfaceFoot: some View {
        ZStack(alignment: .bottom) {
            // IT DOES NOT RETIRE FOR AN EMPTY DESK: the bar is the only
            // way out of one, and its `+` is what the empty desk's hint
            // points at. The pill follows the bar, since it is
            // positioned against it.
            //
            // Both retire under a KEYBOARD: keyboard avoidance would
            // park the bar above the editor's formatting row, two bars
            // deep (owner, 2026-08-02).
            // The bar FIRST, so the pill declared after it keeps the
            // z order the two had as `zIndex(1)` and `zIndex(2)` in
            // RootView. They do not overlap — the pill is padded up by
            // the bar's whole room — but the order is the record of
            // which stands on which.
            if !keyboard.up && desk.menu == nil {
                BottomBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .accessibilityHidden(desk.chromeAway)
                    // OUT OF THE WAY WHILE YOU READ (owner's clips,
                    // 2026-08-20). Its own height plus the safe area it
                    // sits in, so it leaves the screen rather than
                    // peeking over the edge. The extra 12 carries it
                    // past the bottom safe area; both are pure
                    // translations.
                    .offset(y: desk.chromeAway ? LivBar.clearance + 12 : 0)
                    .transition(.move(edge: .bottom).combined(with: .offset(y: 40)))
            }
            if let id = desk.minimisedRecord, !keyboard.up {
                MinimisedRecordPill(id: id)
                    .padding(.bottom, LivBar.room + LivBar.gap)
                    .accessibilityHidden(desk.chromeAway)
            }
        }
    }

    /// Any full-screen surface covering the desk body. One panel left —
    /// the properties are a card, and a card is a sheet the system
    /// hosts, not a layer of the desk.
    private var anyPanel: Bool { desk.libraryShown }

    /// The library door. It stays LIT with the properties card up
    /// (owner, 2026-08-15: "that button should be visible with the
    /// property card open") and it means one thing wherever you press
    /// it: GO TO THE LIBRARY. With the card up that means putting the
    /// card away first — it is a layer of the desk, and the desk is
    /// about to leave — and then sliding. Tapping it used to park the
    /// library invisibly behind the card.
    private func goToLibrary() {
        endEditing()
        guard !desk.libraryShown else {
            desk.setLibrary(false)
            return
        }
        guard desk.inspectorShown else {
            desk.setLibrary(true)
            return
        }
        withAnimation(LivMotion.nav) { desk.inspectorShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.navSeconds) {
            desk.setLibrary(true)
        }
    }

    /// A panel over a live keyboard would sit UNDER it — the keyboard is a
    /// system window. End editing first; the note's autosave flushes on
    /// focus loss anyway.
    private func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: the note's ••• menu (rev 6: SECONDARY verbs only)

    // Four doc comments had stacked up here over one function, none of
    // them about it — the residue of three deletions that each left
    // their prose behind. The two that are still true have gone back to
    // what they describe: the ••• menu's own doc is on `noteVerbs`, and
    // the properties door's is on `propertiesKey`. Untangled 2026-09-07.

    /// Shut the panel. The wash and its drag both need this, and they
    /// must not each decide it for themselves.
    private func closePanel() { desk.setLibrary(false) }

    private func panelOffset() -> CGFloat {
        -(1 - desk.panelProgress) * DeskModel.travel
    }

    /// Would a drag moving `dx` do anything? nil = nothing to claim in
    /// that direction, so the recognizer must not latch (and must not
    /// cancel any touches). The Bool is whether it OPENS.
    ///
    /// ONE PANEL LEFT, so one claim each way. The properties used to be
    /// summoned by a leftward drag and put away by a rightward one; they
    /// open as a CARD now (2026-08-29), from the note's ••• menu, which
    /// is where Anytype puts them and where this app's other card verbs
    /// already live.
    private func claimPanel(_ dx: CGFloat) -> Bool? {
        if dx > 0 { return desk.libraryShown ? nil : true }
        return desk.libraryShown ? false : nil
    }

    /// Let go: finish the journey the finger started, or put it back.
    /// A flick commits from anywhere; a slow drag commits past halfway.
    private func settleDrag(_ dx: CGFloat, _ velocity: CGFloat) {
        guard let live = desk.panelDrag else { return }
        let width = DeskModel.travel
        // A real flick is fast: 700pt/s is a sharp throw, well above
        // the drift a finger has at the end of a deliberate drag. At
        // 250 a moderate release read as a flick and a 30%% drag flew
        // open instead of snapping back (found live, 2026-08-09).
        let flicked = abs(velocity) > 700
        // Toward-visible is a direction, not a verb: the same rightward
        // flick that opens the library would re-open a half-closed one.
        // So the answer is simply "does the panel end up visible" — a
        // flick answers with its direction, a slow drag with where it
        // stopped. The first version asked "did the drag commit" and
        // inverted the slow-close case: a 57% pull away snapped back
        // open (found live, 2026-08-09).
        let towardVisible = velocity > 0
        let shown = flicked ? towardVisible : live.progress(width) > 0.5
        withAnimation(LivMotion.nav) {
            desk.setLibrary(shown, animated: false)
            desk.panelDrag?.amount = live.amount(for: shown ? 1 : 0, width: width)
        } completion: {
            desk.panelDrag = nil
        }
    }

     /// The note's secondary verbs, sliding DOWN from the top — from
    /// under the button that opened them (owner, 2026-08-13). It was a
    /// SwiftUI `Menu`, which is a fourth look for the same idea; now it
    /// is the one menu, pointed the other way.
    /// PROPERTIES, ONE TAP.
    ///
    /// It was an item inside the ••• menu, which is two taps and a read
    /// for the thing the owner calls central to the app (todo.org:
    /// *"selecting properties from a menu is too slow and/or
    /// inconvenient since it's central in the app"*).
    ///
    /// MOVED, NOT ADDED. Leaving the menu item in place would have made
    /// two doors to one room — which is precisely why the old (i) door
    /// was deleted on 2026-08-14 (standing rule 4), so the item goes in
    /// the same change.
    ///
    /// Not the edge drag it used to be, either: `PanelDrag.Which`, the
    /// two-way claim and the two-panel desk push were all deleted when
    /// the properties became a card, and the card is a system `.sheet`
    /// with detents that `settleDrag` has no way to drive. Bringing the
    /// gesture back means rebuilding that machinery.
    private func propertiesKey() -> some View {
        Button {
            endEditing()
            withAnimation(LivMotion.nav) { desk.inspectorShown = true }
        } label: {
            FloatCircleLabel(symbol: "slider.horizontal.3")
        }
        .livTopButton()
        .accessibilityLabel("Properties")
    }

    private func noteMenu(_ id: UInt64) -> some View {
        Button {
            endEditing()
            desk.menu = noteVerbs(id)
        } label: {
            FloatCircleLabel(symbol: "ellipsis")
        }
        .livTopButton()
        .accessibilityLabel("Note actions")
    }

    /// The SECONDARY verbs — what remains once Properties took its own
    /// key: things that ACT on the document, rarely. Every tab is a
    /// document now (Option C), so the kind branch that used to hide
    /// share/export is gone.
    private func noteVerbs(_ id: UInt64) -> LivMenu {
        let row = box.entity(id)
        let isFile = TabShape.of(row) == .file
        var items: [LivMenuItem] = [
            // NO PROPERTIES ITEM. It was first in this list and was the
            // stated reason the ••• existed on a note at all; it became
            // its own key on the top row on 2026-09-07, because two taps
            // is too many for the app's most central card and a menu you
            // have to read is not a door (owner, todo.org). It is not
            // ALSO here — one door to one room.
            //
            // The owner's own name for it — the copy carries the
            // PROPERTIES, deliberately not the body.
            LivMenuItem(label: "Duplicate note", symbol: "plus.square.on.square") {
                duplicate(id)
            },
        ]
        // A file hands its BYTES to whatever owns the format. Share and
        // Export are about MARKDOWN, so a file has none.
        if isFile, let facts = FileFacts.of(row), facts.exists {
            items.append(
                LivMenuItem(label: "Open in…", symbol: "square.and.arrow.up") {
                    share = SharePayload(items: [facts.url])
                })
        }
        if !isFile {
            items.append(
                LivMenuItem(label: "Share", symbol: "square.and.arrow.up") {
                    shareNote(id, asFile: false)
                })
            items.append(
                LivMenuItem(label: "Export as Markdown", symbol: "arrow.down.doc") {
                    shareNote(id, asFile: true)
                })
        }
        items.append(
            // ASKS IN THE SAME CARD IT WAS ASKED FROM.
            //
            // This raised a `.confirmationDialog`, which SwiftUI drew as
            // an anchored popover with an arrow tail, landing part-way
            // down the screen and across the bottom bar — the defect the
            // owner caught in the Inbox on 2026-08-31 ("a message
            // popping up at a random place at the bottom"). Both are the
            // app's own menu now, which comes from the bottom edge every
            // time and names what it is about (standing rule 4).
            LivMenuItem(label: "Move to Trash", symbol: "trash", destructive: true) {
                let name = row.map(livRowTitle) ?? "This note"
                desk.menu = LivMenu(
                    id: "trash-\(id)",
                    from: .bottom,
                    subject: name,
                    subjectDetail: "Moved to Trash, and undoable",
                    items: [
                        LivMenuItem(
                            label: "Move to Trash", symbol: "trash",
                            destructive: true
                        ) { trashNote(id) }
                    ])
            })
        // THE MENU SAYS WHAT IT IS ABOUT (owner's clips, 2026-08-20).
        // Five verbs with no subject is the same defect the owner named
        // in the Inbox — "nobody knows what #xxxxx means" — in a
        // different place: a control that acts on something it will not
        // name.
        return LivMenu(
            id: "note-verbs", from: .top,
            subject: row.map(livRowTitle) ?? "This note",
            subjectDetail: row.map { LivKind.of($0).word },
            items: items)
    }

    /// Birth an empty note and land in it: the editor takes the screen
    /// with the caret already in it. The workspace stamps it exactly as
    /// any other creation door does.
    private func createNote() {
        guard !creating else { return }
        creating = true
        box.createNote { id in
            guard id != 0 else {
                creating = false
                return
            }
            creating = false
            workspaces.stamp(id, in: box)
            desk.requestFocus(id)
            desk.adoptCapture(id)
        }
    }

    /// A CATCH FROM OUTSIDE — `liv://capture?text=…` (2026-09-09). The
    /// text is saved FIRST, through the same `liv_capture_at` the search
    /// field's find-or-create uses; a catch is not a draft, and if you
    /// can start it, it is saved. Then it is treated exactly as the note
    /// `+` makes: stamped into the workspace, focused, adopted as an
    /// Inbox capture — the same three lines as `createNote`, so there is
    /// one rule for what a new thing is and not one per door.
    private func catchText(_ text: String) {
        guard !creating else { return }
        creating = true
        box.capture(text) { id in
            creating = false
            guard id != 0 else { return }
            workspaces.stamp(id, in: box)
            desk.requestFocus(id)
            desk.adoptCapture(id)
        }
    }

    /// The create menu, sliding up from the bar that summoned it. These
    /// three verbs were a whole full-screen PAGE until 2026-08-13.
    ///
    /// PLAIN glyphs, no colour: carved kind chips were tried here on
    /// 2026-08-12 and rejected (owner: "color / boxed icons in new tab
    /// looks bad"). Kind colour marks what a THING is, in the lists —
    /// never what a button would make.
    /// The `+` makes ANY object, not only the two that can hold a tab
    /// (owner, 2026-08-16: "make it support adding any object with
    /// properties. tabs still hold documents though").
    ///
    /// That last clause is the whole shape of this: a note and a file
    /// LAND as tabs, because a tab holds a document; a task and an event
    /// land as CARDS with the caret in the name, because a record's
    /// facts fill a card and not a screen (the 2026-08-07 ruling, still
    /// standing). One door, two landings, decided by what the thing IS.
    ///
    /// It supersedes 2026-08-12's "task and event don't belong in new
    /// tab" — that was aimed at the full-screen New Tab page and its
    /// four-way chooser, both long deleted, and neither is what this is.
    /// What `+` makes is `Feature.makes`' to say, since 2026-09-05 —
    /// the bar prints the same answer under the key.
    ///
    /// Tasks and Today both go through `createRecord`, which already
    /// dates the task from `desk.contextDay` — so a task made in Today
    /// is due today and one made on a Calendar day is due that day,
    /// without this function knowing anything about dates.
    ///
    /// `createNote` calls `adoptCapture`, so a note made from the bar IS
    /// the capture the Inbox is a list of.
    private func createHere() {
        switch desk.state.makes {
        case .task: createRecord(event: false)
        case .event: createRecord(event: true)
        // The rule only ever answers note, task or event; the rest of
        // the kinds are what the long-press menu is for.
        default: createNote()
        }
    }

    private func createMenu() -> LivMenu {
        LivMenu(
            id: "create",
            from: .bottom,
            title: "New",
            items: [
                LivMenuItem(label: "Note", glyph: .note) { createNote() },
                LivMenuItem(label: "Task", glyph: .task) { createRecord(event: false) },
                LivMenuItem(label: "Event", glyph: .event) { createRecord(event: true) },
                LivMenuItem(label: "File", glyph: .file(.other)) { picking = true },
                // The camera's way in. It had none: nothing has set
                // `cameraShown` since the tab plane that used to hold the
                // button was deleted, so the whole flow was unreachable
                // (found 2026-08-19). Named for what the owner uses it
                // for — "i don't see usage for camera except ocr
                // scanning" — and the shutter still takes plain photos
                // once you are in there.
                LivMenuItem(label: "Scan text", symbol: "text.viewfinder") {
                    desk.cameraShown = true
                },
            ])
    }

    /// A task or an event: made at once, landing in its properties with
    /// the caret in the name — the app's one create rule (owner,
    /// 2026-08-13: "naming of items should be done in properties").
    ///
    /// Dated TODAY at 09:00. The bar has no day of its own to inherit,
    /// and a task with no clock time has no moment to ring at
    /// (2026-08-07); the card's own due row is one tap away for anything
    /// else.
    private func createRecord(event: Bool) {
        guard !creating else { return }
        creating = true
        // The day the surface in front is looking at, or today's.
        let stamp = Civil.stamp(
            day: desk.contextDay ?? Civil.todayDay(),
            hhmm: Int64(LivDue.defaultHHMM))
        let landed: (UInt64) -> Void = { id in
            creating = false
            guard id != 0 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            workspaces.stamp(id, in: box)
            desk.requestFocus(id)
            // `as: .record` — the snapshot has not caught up yet.
            desk.open(id, as: .record)
        }
        if event {
            box.createEvent(dueCivil: stamp, dateOnly: false, done: landed)
        } else {
            box.createTask { id in
                guard id != 0 else {
                    landed(0)
                    return
                }
                box.setSpan(id, "due", start: stamp, end: 0, dateOnly: false)
                landed(id)
            }
        }
    }


    /// Hand this note to the phone as markdown. The content arrives on
    /// the box's serial queue, so the payload is built FIRST and the
    /// sheet is presented with it finished — a share sheet that opens
    /// before it knows what it is sharing has nothing to offer.
    ///
    /// `asFile` is the difference between Share and Export: the same
    /// markdown, handed over as text or as a real .md file so "Save to
    /// Files" produces markdown rather than a .txt of the same words.
    /// Neither writes to the box — sharing a note is a READ.
    private func shareNote(_ id: UInt64, asFile: Bool) {
        let name = LivName.stored(box.entity(id))
        box.content(id) { doc in
            guard let doc, doc.missing != true else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            // WITH the display names: an export that renders "[[4155]]"
            // names nothing an outside reader can resolve, and the
            // editor's own buffer has always shown the name.
            let body = SpanText.spansToText(doc.spans ?? []) { [weak box] id in
                (box?.entity(id)?.cells ?? [])
                    .first { $0.property == "name" }?.value
            }
            // An unnamed note still deserves a title: its own first line,
            // markers off — the same name it wears everywhere else.
            let title = name.isEmpty ? livDisplayTitle(body) : name
            let markdown = NoteExport.markdown(name: title, body: body)
            guard !markdown.isEmpty else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            if asFile {
                guard
                    let payload = SharePayload.file(
                        markdown, named: NoteExport.filename(title, id: id))
                else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }
                share = payload
            } else {
                share = SharePayload.text(markdown)
            }
        }
    }

    /// A fresh note wearing THIS note's property cells — the filing
    /// context without the body (owner, 2026-08-03). The source is never
    /// touched; the copy opens as a tab with the caret in it.
    private func duplicate(_ id: UInt64) {
        guard !copying else { return }
        copying = true
        box.duplicateProperties(of: id) { copy in
            copying = false
            guard copy != 0 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            desk.requestFocus(copy)
            desk.open(copy)
        }
    }

    /// Trash leaves the desk showing the LIST (a trashed note has no
    /// business on it) and offers Undo on the chip — the box has no restore verb yet, and
    /// undo-right-after IS restore ONLY while the trash is the last
    /// transaction. So the order matters: end editing FIRST, which
    /// flushes any dirty title/body onto the serial lane ahead of the
    /// trash; a teardown flush after the trash would slip between it and
    /// the Undo, and the chip would undo the wrong thing (found live,
    /// 2026-08-02).
    private func trashNote(_ id: UInt64) {
        endEditing()
        box.trash(id)
        desk.showList()
        flash("Moved to Trash", undo: {
            box.undo()
            desk.open(id)
        })
    }

    private func flash(_ text: String, undo: (() -> Void)? = nil) {
        withAnimation(LivMotion.nav) {
            chipText = text
            chipUndo = undo
        }
        let shown = text
        DispatchQueue.main.asyncAfter(deadline: .now() + (undo == nil ? 2.0 : 5.0)) {
            guard chipText == shown else { return }
            withAnimation(LivMotion.nav) {
                chipText = nil
                chipUndo = nil
            }
        }
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.system(size: LivType.body, weight: .medium))
                .foregroundStyle(LivTheme.text)
            if let undo = chipUndo {
                Button("Undo") {
                    undo()
                    withAnimation(LivMotion.nav) {
                        chipText = nil
                        chipUndo = nil
                    }
                }
                .font(.system(size: LivType.body, weight: .semibold))
                .foregroundStyle(LivTheme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(LivTheme.panel2, in: Capsule())
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
    }
}

extension View {
    /// The top row's button dress: the SAME surface as the bottom bar
    /// (owner, 2026-08-15: "should be made of the same thing"; 2026-08-17:
    /// "make all top buttons have a liquid glass style like the bar"), on
    /// a circle of one FIXED size.
    ///
    /// It wore the system's `.bordered` circle for a day. Two faults,
    /// both visible in a screenshot: that style sizes itself to its
    /// LABEL, so the wide hamburger came out a bigger circle than the
    /// narrow •••; and its fill is derived from the tint, so the two
    /// buttons floated in a lighter grey than the bar they belong with.
    /// One surface, one size — the bar's own recipe, which is now glass.
    /// GLASS AGAIN, in a circle (owner, 2026-08-28: "the icons at the
    /// top… have no button shape unlike everything below and icons give
    /// off an outdated iOS UI look").
    ///
    /// This reverses the bare treatment of 2026-08-18 ("fewer giant
    /// rounded buttons… compact, unobtrusive controls"), and the reason
    /// it reverses is worth keeping: bare was argued from Safari, whose
    /// toolbar glyphs sit in a bar that is itself a surface. These do
    /// not — they float on the words, with nothing under them but a
    /// fading scrim, so they read as loose icons rather than controls.
    /// The bar below wears glass and the panel's settings key wears a
    /// circle; these now wear both, which makes the app's three rows of
    /// chrome one language (standing rule 4).
    ///
    /// **Do not use this on a button that is followed by a `Spacer`.**
    /// The frame lands OUTSIDE the button, and SwiftUI then reports an
    /// accessibility element covering the button and the spacer both —
    /// 396pt wide in the row that found this, with its activation point
    /// in the middle of the screen and its bounds overlapping the ••• at
    /// the far end. A person tapping the glyph is fine; VoiceOver and any
    /// test driving by label are not. In that position, put
    /// `.frame(width: 40, height: 40).contentShape(Rectangle())` inside
    /// the label instead — see the library door above (2026-08-24).
    ///
    /// It took an `on:` flag until 2026-09-07 and never read it — the
    /// only caller passing one was `FloatCircle`, which had no callers
    /// of its own and went in the same change.
    func livTopButton() -> some View {
        buttonStyle(.plain)
            .livTopKeyShape()
    }

    /// The SHAPE a top door wears, on its own so the library button can
    /// apply it inside its label — see the warning above about the
    /// 396pt-wide accessibility element.
    func livTopKeyShape() -> some View {
        // 44, not 40 (owner, 2026-08-28: "a notch larger"). It is also
        // the platform's minimum target, which the 40 never was.
        frame(width: 44, height: 44)
            .livGlass(in: Circle())
            .contentShape(Circle())
    }
}

/// The glyph inside a top-row button. The SHAPE is the system's
/// (`livTopButton`); this is only what goes in it.
struct FloatCircleLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            // LIGHT, not regular (owner, 2026-08-18: "even more plain
            // looking… i like a minimalist look"). A thinner stroke is
            // the whole difference between an icon that announces
            // itself and one that is just there.
            .font(.system(size: LivType.title, weight: .light))
            // FULL INK, always. There was an `on` state here that
            // turned the glyph accent, reachable only through
            // `FloatCircle` — which nothing called. A top door says it
            // is open by its mark's geometry, never by going blue
            // (see `LivGlass` in Chrome.swift for the same removal).
            .foregroundStyle(LivTheme.text)
            // A FIXED square, so a wide glyph and a narrow one come out
            // the same button.
            .frame(width: 24, height: 24)
    }
}

// MARK: - the entity tab body

/// One entity, full-bleed: the text IS the screen (owner, 2026-07-31).
/// No DETAILS row, no meta line, no card — properties live behind the
/// floating metadata chevron (DeskHost), and the title, when the entity
/// has one, is the only thing above the text.
struct EntityTabBody: View {
    let id: UInt64

    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel
    @State private var title = ""
    @State private var titleSeeded = false
    /// Set once, in onAppear, for a note born a moment ago.
    @State private var autoFocus = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        if box.live(id) != nil {
            content
        } else {
            // A persisted tab whose entity left the box — dropped lazily.
            EmptyHint("This was deleted.")
                .frame(maxHeight: .infinity)
        }
    }

    /// A name CELL, not the displayed title: a scrap has none, and its
    /// title is derived from its content's first line — the editor is its
    /// only surface.
    private var named: Bool {
        (box.entity(id)?.cells ?? []).contains {
            $0.property == "name" && !($0.value ?? "").isEmpty
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if TabShape.of(box.entity(id)) == .file {
                // A file IS a document you work on — it belongs in a
                // tab. Liv shows the bytes and never writes them.
                FileBody(id: id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if box.live(id) != nil {
                NoteEditor(
                    id: id,
                    title: $title, onTitleCommit: commitTitle,
                    // A token whose target is not in this box LOOKS like a
                    // link but saves as text (ruling 5) — tapping it must
                    // not open a dead tab.
                    onOpenRef: { target in
                        if box.live(target) != nil { desk.open(target) }
                    },
                    autoFocus: autoFocus
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            seedTitle()
            // Child onAppear fires before the parent's, so the editor reads
            // this through onChange, not its own onAppear.
            //
            // OPENING A NOTE PUTS THE CARET IN IT (owner, 2026-08-20:
            // "Opening a note doesn't put cursor in note automatically").
            // It used to focus only what was just CREATED — `consumeFocus`
            // is one-shot by design — so opening something you wrote
            // yesterday left you looking at your words with no way to add
            // to them but a tap. The caret lands where you left it
            // (`LivCaret`) or, for a note this launch has not seen yet,
            // at the END — never at the top (owner, 2026-08-20: "The
            // caret is always put at the beginning of the document, not
            // where you left or at the end").
            //
            // `consumeFocus` still runs, and must: it is what puts the
            // caret at the START of a brand-new note rather than at a
            // remembered position, and leaving it unconsumed would strand
            // the request for the next thing opened.
            _ = desk.consumeFocus(id)
            autoFocus = true
        }
        .onChange(of: storedName) { old, fresh in
            // The snapshot moved under us (undo, another surface). Reseed
            // unless the user actually edited the draft — compared against
            // the OLD stored name: `storedName` inside this closure already
            // reads the new value, so the old guard could only ever fire on
            // an empty field and an external rename froze the title, which
            // a later commit then silently reverted (audit, 2026-08-04).
            if let seed = LivName.reseed(draft: title, was: old, now: fresh) {
                title = seed
            }
        }
    }

    // MARK: title — lives in the editor's scroll view now

    /// The name cell — `LivName.stored` since 2026-09-07, so the desk,
    /// the record card and the properties card all read it one way.
    private var storedName: String { LivName.stored(box.entity(id)) }

    private func seedTitle() {
        guard !titleSeeded else { return }
        title = storedName
        titleSeeded = true
    }

    /// The rules live in `LivName.commit` (Kit.swift) — including the
    /// trashed-entity guard this function used to carry alone, and which
    /// the record card's own copy never had.
    private func commitTitle() {
        switch LivName.commit(typed: title, row: box.entity(id)) {
        case .write(let typed): box.set(id, "name", typed)
        case .revert(let stored): title = stored
        case .ignore: break
        }
    }
}
