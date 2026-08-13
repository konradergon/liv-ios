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
    /// Which panel the finger is currently dragging, and how far it has
    /// moved. nil = no drag in flight.
    @State private var dragging: PanelDrag?

    /// One panel being dragged: which one, whether the drag OPENS or
    /// CLOSES it, and the finger's travel so far.
    struct PanelDrag: Equatable {
        enum Which { case library, inspector }
        let which: Which
        let opening: Bool
        var amount: CGFloat = 0

        /// Where the drag started from: 0 for an opening drag, 1 for a
        /// closing one.
        var base: CGFloat { opening ? 0 : 1 }

        /// Finger travel that makes this panel MORE visible. The library
        /// comes from the left, so rightward is toward; the properties
        /// come from the right, so leftward is.
        var toward: CGFloat { which == .library ? amount : -amount }

        /// 0 = fully off screen, 1 = fully in. `width` is the screen.
        func progress(_ width: CGFloat) -> CGFloat {
            guard width > 0 else { return base }
            return min(1, max(0, base + toward / width))
        }

        /// The travel that would land the panel exactly at `target`.
        func amount(for target: CGFloat, width: CGFloat) -> CGFloat {
            let toward = (target - base) * width
            return which == .library ? toward : -toward
        }
    }
    /// One transient acknowledgment chip: text, and an optional Undo verb
    /// (the trash chip carries one; the template chip does not).
    @State private var chipText: String?
    @State private var chipUndo: (() -> Void)?
    /// Closes the double-tap window while a template copy is in flight.
    @State private var templateBusy = false
    /// What the ••• is handing to the rest of the phone (phase 7).
    @State private var share: SharePayload?

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let tab = desk.activeTab, case .entity(let id) = tab.content {
                    // Keyed by ENTITY: serial captures rewrite this same
                    // tab with a new entity, and per-entity @State (the
                    // seeded title) must reseed on that flip.
                    EntityTabBody(id: id).id(id)
                } else {
                    // An empty desk IS the chooser (rev 6) — no tab holds it.
                    NewTabChooser(overlay: false, onWorkspace: { desk.workspaceShown = true })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(anyPanel)

            // The doors (design/ios.md §6 rev 6): top-left opens the
            // LIBRARY; top-right, Properties is a FREQUENT action so it
            // gets its own door, and the ••• holds only the secondary
            // verbs (duplicate, template, trash). Visible in every state,
            // writing included.
            HStack(spacing: 8) {
                FloatCircle(
                    symbol: "line.3.horizontal", on: desk.libraryShown, label: "Library"
                ) {
                    endEditing()
                    withAnimation(LivMotion.nav) { desk.libraryShown.toggle() }
                }
                Spacer()
                if case .entity(let id) = desk.activeTab?.content {
                    FloatCircle(
                        symbol: "info.circle", on: desk.inspectorShown,
                        label: "Properties"
                    ) {
                        endEditing()
                        withAnimation(LivMotion.nav) { desk.inspectorShown.toggle() }
                    }
                    noteMenu(id)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            // Full-screen panels cover the doors; fade them in the same
            // motion so the exit slide never shows dead controls.
            .opacity(anyPanel ? 0 : 1)
            .accessibilityHidden(anyPanel)

            // The panels, drawn last so they cover doors and body alike.
            // Mounted while shown OR while a finger is dragging one, and
            // positioned by that drag — they follow the hand rather than
            // waiting for it to let go (owner, 2026-08-08).
            if desk.libraryShown || dragging?.which == .library {
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
                desk.inspectorShown || dragging?.which == .inspector
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

            // The New Tab chooser: a full-screen overlay summoned by `+`,
            // never a tab (rev 6). Drawn over the panels — it is the most
            // recent ask.
            if desk.newTabShown {
                NewTabChooser(
                    overlay: true, onWorkspace: { desk.workspaceShown = true }
                )
                .background(LivTheme.canvas.ignoresSafeArea())
                // The panels' escape gesture, here too — a full-screen
                // surface without it is a VoiceOver trap (audit,
                // 2026-08-04). At the presentation site, so the
                // empty-desk body (nothing to close into) has no stray
                // escape.
                .accessibilityAction(.escape) {
                    withAnimation(LivMotion.nav) { desk.newTabShown = false }
                }
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .background(LivTheme.canvas)
        // The whole desk goes INERT while a drag is latched. This — not
        // anything at the UIKit layer — is what stops a drag from
        // pressing the button it started on: disabling a SwiftUI
        // control mid-press cancels the press, where touch
        // cancellation, recognizer exclusion and delayed delivery all
        // failed to reach SwiftUI's forwarding (each tried, each
        // beaten, 2026-08-09). A tap never latches, so taps are never
        // disabled.
        .disabled(dragging != nil)
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
                active: { !desk.newTabShown },
                mayClaim: { dx in claimPanel(dx) != nil },
                onLatch: { dx in
                    if let claim = claimPanel(dx) {
                        endEditing()
                        dragging = PanelDrag(
                            which: claim.which, opening: claim.opening, amount: dx)
                    }
                },
                onMove: { dx in dragging?.amount = dx },
                onEnd: { dx, velocity in settleDrag(dx, velocity) }
            )
            .frame(width: 0, height: 0)
        )
        // The acknowledgment chip: a verb that changes something you can
        // no longer see (the copy, the trashed note) says so, briefly.
        .overlay(alignment: .top) {
            if let text = chipText {
                chip(text)
                    .padding(.top, 56)
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
        desk.libraryShown || desk.inspectorShown || desk.newTabShown
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
    /// document, rarely: duplicate, template, trash.
    /// The secondary verbs. Every tab is a document now (Option C), so
    /// the kind branch that used to hide template/share/export is gone.
    /// How far off its own edge a panel currently sits. A panel with no
    /// drag in flight is simply open (0) — the transition handles its
    /// arrival and departure as before.
    private func panelOffset(_ which: PanelDrag.Which) -> CGFloat {
        let width = UIScreen.main.bounds.width
        let shown = which == .library ? desk.libraryShown : desk.inspectorShown
        let progress = dragging?.which == which
            ? dragging!.progress(width) : (shown ? 1 : 0)
        let hidden = (1 - progress) * width
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
        guard let live = dragging else { return }
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
            dragging?.amount = live.amount(for: shown ? 1 : 0, width: width)
        } completion: {
            dragging = nil
        }
    }

    private func noteMenu(_ id: UInt64) -> some View {
        let isFile = TabShape.of(box.entity(id)) == .file
        return Menu {
            Button {
                duplicate(id)
            } label: {
                // The owner's own name for it — the copy carries the
                // PROPERTIES, deliberately not the body.
                Label("Duplicate note", systemImage: "plus.square.on.square")
            }
            // A file hands its BYTES to whatever owns the format —
            // this is the file integration, and it moved here from a
            // button on the file screen (owner, 2026-08-13). Secondary
            // verbs live in this menu; the file screen shows the file.
            if isFile, let facts = FileFacts.of(box.entity(id)), facts.exists {
                Button {
                    share = SharePayload(items: [facts.url])
                } label: {
                    Label("Open in…", systemImage: "square.and.arrow.up")
                }
            }
            // Template, Share and Export are about MARKDOWN.
            if !isFile {
                if LivKind.of(box.entity(id)) != .template {
                    Button {
                        saveTemplate(id)
                    } label: {
                        Label("Save as template", systemImage: "doc.on.doc")
                    }
                }
                Button {
                    shareNote(id, asFile: false)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button {
                    shareNote(id, asFile: true)
                } label: {
                    Label("Export as Markdown", systemImage: "arrow.down.doc")
                }
            }
            Button(role: .destructive) {
                confirmTrash = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        } label: {
            FloatCircleLabel(symbol: "ellipsis")
        }
        .accessibilityLabel("Note actions")
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
        guard !templateBusy else { return }
        templateBusy = true
        box.duplicateProperties(of: id) { copy in
            templateBusy = false
            guard copy != 0 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            desk.requestFocus(copy)
            desk.open(copy)
        }
    }

    /// Copies (never moves — ruling 6); the chip is the only trace, since
    /// the copy itself appears nowhere on screen.
    private func saveTemplate(_ id: UInt64) {
        guard !templateBusy else { return }
        templateBusy = true
        box.saveAsTemplate(id) { copy in
            templateBusy = false
            if copy == 0 {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                flash("Saved as template")
            }
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
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct FloatCircleLabel: View {
    let symbol: String
    var on: Bool = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: LivType.strong, weight: .medium))
            .foregroundStyle(on ? LivTheme.onAccent : LivTheme.text2)
            .frame(width: 36, height: 36)
            .background(Circle().fill(on ? LivTheme.accent : LivTheme.panel2))
            .overlay(
                Circle().strokeBorder(on ? Color.clear : LivTheme.border, lineWidth: 0.5)
            )
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

// MARK: - the create chooser (rev 6: a door, never a tab)

/// Verbs, no questions. Two of them make a DOCUMENT, which lands as a
/// tab: "Create a note" opens the editor with the caret in it, and
/// "From template…" copies one first. The rest make a RECORD or open a
/// door — a task or event rises as a card over wherever you are, and
/// never takes a tab (Option C, owner 2026-08-08). So this is a create
/// menu, not a "new tab" screen; it is the `+` overlay and the empty
/// desk's own body.
struct NewTabChooser: View {
    /// Overlay mode (summoned by `+` over a live desk) carries a close
    /// band; the empty-desk body has nothing to close into.
    let overlay: Bool
    /// Presented by DESKHOST — switching workspace tears this view down.
    let onWorkspace: () -> Void

    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @State private var creating = false
    @State private var templatesShown = false

    var body: some View {
        VStack(spacing: 0) {
            if overlay {
                closeBand
            }
            VStack(spacing: 8) {
                Spacer()
                // Documents first — they are what a tab holds.
                verb("Create a note", .note, primary: true) { createNote() }
                verb("From template…", .template) { templatesShown = true }
                fileDoor
                // No "Open…" here: the bar below carries search, and the
                // bar is now always up on this screen. Two doors to one
                // room is a defect (standing rule 4), and the one that
                // went is the one that was only reachable from here.
                Spacer()
                // The workspace this creation lands in — switchable right
                // here (owner, 2026-08-03), because the stamp depends on it.
                workspaceRow
                Spacer()
            }
            .padding(.horizontal, 48)
        }
        .disabled(creating)
        .sheet(isPresented: $templatesShown) {
            TemplateSheet(verb: .create) { template in
                fromTemplate(template.id)
            }
            .environmentObject(box)
        }
    }

    /// The file door. It carries its own picker, so it is a view rather
    /// than a `verb(…)` call; FileImportButton wears the verb dress
    /// itself.
    private var fileDoor: some View {
        FileImportButton()
    }

    /// The house close band (App.swift's FeatureWindow recipe): the WHOLE
    /// band closes, not just the glyph, and a downward drag does too.
    private var closeBand: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(LivMotion.nav) { desk.newTabShown = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: LivType.strong, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(LivMotion.nav) { desk.newTabShown = false }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { g in
                    if g.translation.height > 40 {
                        withAnimation(LivMotion.nav) { desk.newTabShown = false }
                    }
                }
        )
    }

    private var workspaceRow: some View {
        Button(action: onWorkspace) {
            HStack(spacing: 8) {
                LivIcon(
                    glyph: workspaces.activeId == 0 ? .workspaces : .workspace,
                    color: LivTheme.text3, size: 17)
                Text(workspaces.activeName)
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text2)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: LivType.caption, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workspace: \(workspaces.activeName). Switch")
    }

    /// A new note from a template: the same landing as "Create a note" —
    /// the note becomes a tab with the caret already in it, at the
    /// template's {{cursor}} if it named one.
    private func fromTemplate(_ template: UInt64) {
        guard !creating else { return }
        creating = true
        box.newFromTemplate(template, now: Civil.nowStamp()) { id, caret in
            guard id != 0 else {
                creating = false
                return
            }
            workspaces.stamp(id, in: box)
            desk.requestFocus(id, caret: caret)
            desk.adoptCapture(id)
        }
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
            workspaces.stamp(id, in: box)
            desk.requestFocus(id)
            desk.adoptCapture(id)
        }
    }

    /// A plain glyph, no chip. Carved kind chips were tried here on
    /// 2026-08-12 and rejected (owner: "color / boxed icons in new tab
    /// looks bad"). This is a column of five verbs a person reads by
    /// their words; five colored boxes made it a toy shelf. Kind color
    /// still marks what a THING is, in the lists — not what a button
    /// would make.
    ///
    /// The GLYPH is still the shared drawing — one table, so the door
    /// that makes a note shows the same mark the note wears afterwards.
    /// Only the colour is withheld.
    private func verb(
        _ label: String, _ glyph: LivGlyph, primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LivIcon(
                    glyph: glyph,
                    color: primary ? LivTheme.onAccent : LivTheme.text, size: 18)
                Text(label)
            }
            .livVerbFace(primary: primary)
        }
        .buttonStyle(.plain)
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
    @State private var autoCaret: Int?
    /// Set once, in onAppear, for a note born a moment ago.
    @State private var autoFocus = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        if box.entity(id) != nil {
            content
        } else {
            // A persisted tab whose entity left the box — dropped lazily.
            EmptyHint("This entity is not in the box anymore.")
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

    /// The template safeguard (rev 6): a template on the desk SAYS so,
    /// and offers the thing you probably meant — a new note from it.
    /// Editing stays allowed (a template is a note), but editing-when-
    /// you-meant-a-copy stops being the silent default.
    private var isTemplate: Bool {
        LivKind.of(box.entity(id)) == .template
    }

    /// A floating pill BETWEEN the doors, in the clearance the editor
    /// already reserves for them — it pushes nothing (the old banner
    /// stacked its own band on the editor's door clearance: ~90pt of
    /// dead space; audit 2026-08-04).
    private var templatePill: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: LivType.label))
                .foregroundStyle(LivTheme.text3)
            Text("Template")
                .font(.system(size: LivType.body, weight: .medium))
                .foregroundStyle(LivTheme.text2)
            Button {
                box.newFromTemplate(id, now: Civil.nowStamp()) { fresh, caret in
                    guard fresh != 0 else { return }
                    desk.requestFocus(fresh, caret: caret)
                    desk.open(fresh)
                }
            } label: {
                Text("New note")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .frame(height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New note from this template")
            .accessibilityHint("Edits to this note change every future copy")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(LivTheme.panel2, in: Capsule())
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
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
                    autoFocus: autoFocus, autoCaret: autoCaret
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // In the doors' own band, anchored after the LEFT door — centered
        // it would graze the right-side pair on narrow screens. No layout
        // push either way.
        .overlay(alignment: .topLeading) {
            if isTemplate {
                templatePill
                    .padding(.leading, 64)
                    .padding(.top, 10)
            }
        }
        .onAppear {
            seedTitle()
            // Child onAppear fires before the parent's, so the editor reads
            // this through onChange, not its own onAppear.
            if let request = desk.consumeFocus(id) {
                autoFocus = true
                autoCaret = request.caret
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
