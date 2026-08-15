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

    /// The ••• menu's trash leg asks once before it acts.
    @State private var confirmTrash = false
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
                if let tab = desk.activeTab, case .entity(let id) = tab.content {
                    // Keyed by ENTITY: serial captures rewrite this same
                    // tab with a new entity, and per-entity @State (the
                    // seeded title) must reseed on that flip.
                    EntityTabBody(id: id).id(id)
                } else {
                    // An empty desk is EMPTY. It used to be the New Tab
                    // page; that page is gone (owner, 2026-08-13) and its
                    // three verbs live in the `+` menu on the bar below.
                    EmptyHint("No tabs. The + below makes one.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                FloatCircle(
                    symbol: "line.3.horizontal", on: desk.libraryShown, label: "Library"
                ) {
                    endEditing()
                    withAnimation(LivMotion.nav) { desk.libraryShown.toggle() }
                }
                Spacer()
                if case .entity(let id) = desk.activeTab?.content {
                    noteMenu(id)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            // The doors belong to the desk and leave with it — fading
            // early, because their path crosses the pinned workspace
            // button and two labels on one line is the defect the owner
            // named the same day.
            .offset(x: desk.deskShift)
            .opacity(1 - desk.deskTravel)
            .accessibilityHidden(anyPanel)

            // The workspace, top CENTRE, between the doors — on the desk,
            // full or empty, and OVER the library panel, which
            // is why it is drawn last with the highest z (owner,
            // 2026-08-13: "it should remain visible as you swipe into the
            // global panel"). It hides only under the PROPERTIES panel,
            // which is about this note and not about the app.
            WorkspaceButton { desk.workspaceShown = true }
                .padding(.top, 6)
                .opacity(inspectorUp ? 0 : 1)
                .accessibilityHidden(inspectorUp)
                .zIndex(3)

            // The panels, drawn last so they cover doors and body alike.
            // Mounted while shown OR while a finger is dragging one, and
            // positioned by that drag — they follow the hand rather than
            // waiting for it to let go (owner, 2026-08-08).
            if desk.libraryShown || desk.panelDrag?.which == .library {
                LibraryPanel(
                    onDismiss: {
                        withAnimation(LivMotion.nav) { desk.libraryShown = false }
                    },
                    onWorkspace: { desk.workspaceShown = true },
                    onSettings: { desk.settingsShown = true }
                )
                .offset(x: panelOffset(.library))
                // Exit transitions render BELOW later siblings without an
                // explicit z — the panel would vanish behind the desk
                // instead of sliding out (audit, 2026-08-01).
                .zIndex(1)
            }
            if case .entity(let id) = desk.activeTab?.content,
                desk.inspectorShown || desk.panelDrag?.which == .inspector
            {
                SidePanel(
                    edge: .trailing,
                    onDismiss: {
                        withAnimation(LivMotion.nav) { desk.inspectorShown = false }
                    }
                ) {
                    EntityInspector(id: id)
                }
                .offset(x: panelOffset(.inspector))
                .zIndex(1)
            }

        }
        .background(LivTheme.canvas)
        .onAppear { desk.newTabMenu = createMenu }
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
                active: { desk.menu == nil },
                mayClaim: { dx in claimPanel(dx) != nil },
                onLatch: { dx in
                    if let claim = claimPanel(dx) {
                        endEditing()
                        desk.panelDrag = PanelDrag(
                            which: claim.which, opening: claim.opening, amount: dx)
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
                    .padding(.top, LivRow.topChrome)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .confirmationDialog(
            "Move to Trash?", isPresented: $confirmTrash, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let tab = desk.activeTab, case .entity(let id) = tab.content {
                    trashNote(id, tab: tab.id)
                }
            }
        }
        .sheet(isPresented: $desk.workspaceShown) {
            WorkspaceSwitcher()
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

    /// Any full-screen surface covering the desk body.
    private var anyPanel: Bool {
        desk.libraryShown || desk.inspectorShown
    }

    /// The PROPERTIES panel is up, or a finger is bringing it in. The one
    /// surface the workspace button steps aside for: it describes this
    /// note, and the workspace is not one of its facts.
    private var inspectorUp: Bool {
        desk.inspectorShown || desk.panelDrag?.which == .inspector
    }

    /// A panel over a live keyboard would sit UNDER it — the keyboard is a
    /// system window. End editing first; the note's autosave flushes on
    /// focus loss anyway.
    private func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: the note's ••• menu (rev 6: SECONDARY verbs only)

    /// Frequent actions get dedicated UI (owner principle) — Properties
    /// left this menu for its own door. What remains ACTS on the
    /// document, rarely: duplicate, share, trash.
    /// The secondary verbs. Every tab is a document now (Option C), so
    /// the kind branch that used to hide share/export is gone.
    /// How far off its own edge a panel currently sits. A panel with no
    /// drag in flight is simply open (0) — the transition handles its
    /// arrival and departure as before.
    private func panelOffset(_ which: PanelDrag.Which) -> CGFloat {
        let hidden = (1 - desk.panelProgress(which)) * UIScreen.main.bounds.width
        return which == .library ? -hidden : hidden
    }

    /// What a drag moving `dx` would do: which panel, opening or
    /// closing. nil = nothing to claim in that direction, so the
    /// recognizer must not latch (and must not cancel any touches).
    private func claimPanel(
        _ dx: CGFloat
    ) -> (which: PanelDrag.Which, opening: Bool)? {
        if dx > 0 {
            // Rightward: put the properties away, else summon the library.
            if desk.inspectorShown { return (.inspector, false) }
            if !desk.libraryShown { return (.library, true) }
        } else {
            // Leftward: put the library away, else summon the properties.
            if desk.libraryShown { return (.library, false) }
            if !desk.inspectorShown, case .entity = desk.activeTab?.content {
                return (.inspector, true)
            }
        }
        return nil
    }

    /// Let go: finish the journey the finger started, or put it back.
    /// A flick commits from anywhere; a slow drag commits past halfway.
    private func settleDrag(_ dx: CGFloat, _ velocity: CGFloat) {
        guard let live = desk.panelDrag else { return }
        let width = UIScreen.main.bounds.width
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
        let towardVisible = live.which == .library ? velocity > 0 : velocity < 0
        let shown = flicked ? towardVisible : live.progress(width) > 0.5
        withAnimation(LivMotion.nav) {
            switch live.which {
            case .library: desk.libraryShown = shown
            case .inspector: desk.inspectorShown = shown
            }
            desk.panelDrag?.amount = live.amount(for: shown ? 1 : 0, width: width)
        } completion: {
            desk.panelDrag = nil
        }
    }

     /// The note's secondary verbs, sliding DOWN from the top — from
    /// under the button that opened them (owner, 2026-08-13). It was a
    /// SwiftUI `Menu`, which is a fourth look for the same idea; now it
    /// is the one menu, pointed the other way.
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

    private func noteVerbs(_ id: UInt64) -> LivMenu {
        let row = box.entity(id)
        let isFile = TabShape.of(row) == .file
        var items: [LivMenuItem] = [
            // The owner's own name for it — the copy carries the
            // PROPERTIES, deliberately not the body.
            LivMenuItem(label: "Duplicate note", symbol: "plus.square.on.square") {
                duplicate(id)
            }
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
            LivMenuItem(label: "Move to Trash", symbol: "trash", destructive: true) {
                confirmTrash = true
            })
        return LivMenu(id: "note-verbs", from: .top, items: items)
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

    /// The create menu, sliding up from the bar that summoned it. These
    /// three verbs were a whole full-screen PAGE until 2026-08-13.
    ///
    /// PLAIN glyphs, no colour: carved kind chips were tried here on
    /// 2026-08-12 and rejected (owner: "color / boxed icons in new tab
    /// looks bad"). Kind colour marks what a THING is, in the lists —
    /// never what a button would make.
    private func createMenu() -> LivMenu {
        LivMenu(
            id: "create",
            from: .bottom,
            title: "New",
            items: [
                LivMenuItem(label: "Create a note", glyph: .note) { createNote() },
                LivMenuItem(label: "Add a file", glyph: .file(.other)) {
                    picking = true
                },
            ])
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
        let name = (box.entity(id)?.cells ?? [])
            .first { $0.property == "name" }?.value ?? ""
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

    /// Trash closes the tab (a trashed note has no business on the desk)
    /// and offers Undo on the chip — the box has no restore verb yet, and
    /// undo-right-after IS restore ONLY while the trash is the last
    /// transaction. So the order matters: end editing FIRST, which
    /// flushes any dirty title/body onto the serial lane ahead of the
    /// trash; a teardown flush after the trash would slip between it and
    /// the Undo, and the chip would undo the wrong thing (found live,
    /// 2026-08-02).
    private func trashNote(_ id: UInt64, tab: UUID) {
        endEditing()
        box.trash(id)
        withAnimation(LivMotion.nav) { desk.close(tab) }
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
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }
}

/// One quiet floating control: 36pt circle, 44pt target.
struct FloatCircle: View {
    let symbol: String
    var on: Bool = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FloatCircleLabel(symbol: symbol, on: on)
        }
        .livTopButton(on: on)
        .accessibilityLabel(label)
    }
}

extension View {
    /// The top row's button dress: the SAME material as the bottom bar
    /// (owner, 2026-08-15: "should be made of the same thing"), on a
    /// circle of one FIXED size.
    ///
    /// It wore the system's `.bordered` circle for a day. Two faults,
    /// both visible in a screenshot: that style sizes itself to its
    /// LABEL, so the wide hamburger came out a bigger circle than the
    /// narrow •••; and its fill is derived from the tint, so the two
    /// buttons floated in a lighter grey than the bar they belong with.
    /// One surface, one hairline, one size — the bar's own recipe.
    func livTopButton(on: Bool = false) -> some View {
        buttonStyle(.plain)
            .frame(width: 40, height: 40)
            .background(on ? LivTheme.accent : LivTheme.surface, in: Circle())
            .overlay(
                Circle().strokeBorder(
                    on ? Color.clear : LivTheme.border, lineWidth: 0.5))
            .contentShape(Circle())
    }
}

/// The glyph inside a top-row button. The SHAPE is the system's
/// (`livTopButton`); this is only what goes in it.
struct FloatCircleLabel: View {
    let symbol: String
    var on: Bool = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: LivType.title, weight: .regular))
            .foregroundStyle(on ? LivTheme.onAccent : LivTheme.text2)
            // A FIXED square, so a wide glyph and a narrow one come out
            // the same button.
            .frame(width: 22, height: 22)
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
        if box.entity(id) != nil {
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
            } else if box.entity(id) != nil {
                NoteEditor(
                    id: id,
                    title: $title, onTitleCommit: commitTitle,
                    // A token whose target is not in this box LOOKS like a
                    // link but saves as text (ruling 5) — tapping it must
                    // not open a dead tab.
                    onOpenRef: { target in
                        if box.entity(target) != nil { desk.open(target) }
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
            if desk.consumeFocus(id) {
                autoFocus = true
            }
        }
        .onChange(of: storedName) { old, fresh in
            // The snapshot moved under us (undo, another surface). Reseed
            // unless the user actually edited the draft — compared against
            // the OLD stored name: `storedName` inside this closure already
            // reads the new value, so the old guard could only ever fire on
            // an empty field and an external rename froze the title, which
            // a later commit then silently reverted (audit, 2026-08-04).
            if title != fresh, title == "" || title == old { title = fresh }
        }
    }

    // MARK: title — lives in the editor's scroll view now

    /// The NAME CELL, never row.title — the wire title is a derived
    /// display string ("#id" for an empty note, the first content line for
    /// a scrap) and belongs in the grey prompt, not in the field.
    private var storedName: String {
        (box.entity(id)?.cells ?? [])
            .first { $0.property == "name" }?.value ?? ""
    }

    private func seedTitle() {
        guard !titleSeeded else { return }
        title = storedName
        titleSeeded = true
    }

    private func commitTitle() {
        // A gone or trashed note takes no name: after a trash, the entity
        // stops resolving, storedName reads empty, and the equality guard
        // below would happily write the old name back onto the trashed
        // note — the stray transaction that broke the chip's Undo
        // (found live, 2026-08-02).
        guard let row = box.entity(id), row.trashed != true else { return }
        let stored = storedName
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != stored, !typed.isEmpty else {
            title = stored  // an emptied field reverts, never erases the name
            return
        }
        box.set(id, "name", typed)
    }
}
