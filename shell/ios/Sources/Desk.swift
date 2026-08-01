// liv iOS — Desk view (design/ios.md §6): the active tab's body, the
// new-tab capture door, and the tab switcher (Obsidian's, verbatim in
// structure; Liv's soul). Tabs are shell state — every mutation still
// rides the one BoxModel, act-then-refresh.

import SwiftUI

// MARK: - DeskHost

/// The desk body: the switcher while it is up, else the active tab.
/// `.id(tab.id)` resets per-tab @State when focus moves between tabs.
struct DeskHost: View {
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel

    @State private var settingsShown = false
    @State private var switcherShown = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let tab = desk.activeTab {
                    switch tab.content {
                    case .new:
                        NewTabBody(tabId: tab.id).id(tab.id)
                    case .entity(let id):
                        // Keyed by ENTITY: serial captures rewrite this same
                        // tab with a new entity, and per-entity @State (the
                        // seeded title) must reseed on that flip.
                        EntityTabBody(id: id).id(id)
                    }
                } else {
                    // DeskModel keeps a tab alive by invariant; belt anyway.
                    EmptyHint("No tab open — tap + for one.")
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The only standing chrome over the note: two quiet circles,
            // top-right, hovering over the full-bleed text — visible in
            // every state, editing included (owner, 2026-08-01: the top
            // actions stay put). Workspace and Settings moved here from
            // the old persistent top bar, one level back from daily use.
            HStack(spacing: 8) {
                if case .entity = desk.activeTab?.content {
                    FloatCircle(
                        symbol: desk.inspectorShown ? "chevron.up" : "chevron.down",
                        on: desk.inspectorShown, label: "Metadata"
                    ) {
                        withAnimation(LivMotion.nav) { desk.inspectorShown.toggle() }
                    }
                }
                Menu {
                    // Ruling 6: this COPIES. The note you are writing
                    // stays exactly where it is; the copy becomes the
                    // template, so nothing you wrote ever moves.
                    if case .entity(let entity) = desk.activeTab?.content {
                        Button {
                            box.saveAsTemplate(entity)
                        } label: {
                            Label("Save as template", systemImage: "doc.on.doc")
                        }
                    }
                    Button {
                        switcherShown = true
                    } label: {
                        Label(workspaces.activeName, systemImage: "square.grid.2x2")
                    }
                    Button {
                        settingsShown = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    FloatCircleLabel(symbol: "ellipsis", on: false)
                }
                .accessibilityLabel("More")
            }
            .padding(.trailing, 12)
            .padding(.top, 6)
        }
        .background(LivTheme.canvas)
        .sheet(isPresented: $settingsShown) { SettingsSheet() }
        .sheet(isPresented: $switcherShown) {
            WorkspaceSwitcher()
                .environmentObject(box)
                .environmentObject(workspaces)
        }
        // The capture sheet hangs off the HOST, not the .new tab body: the
        // commit flips that tab to .entity, and a sheet presented from the
        // replaced body is torn down mid-flow — the eval §5.2/§5.3
        // vanishing confirmation and dead-ended "Another". The host
        // outlives the flip, so the sheet shows its saved stage after
        // EVERY commit and "Another" keeps the sheet alive.
        .sheet(item: $desk.captureRequest) { req in
            CaptureSheet(
                initialVerb: req.verb,
                openCamera: {
                    desk.captureRequest = nil
                    desk.cameraShown = true
                },
                onCreated: { id in desk.setContent(req.tabId, entity: id) }
            )
            .environmentObject(box)
            .environmentObject(workspaces)
        }
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
            .font(.system(size: 14, weight: .medium))
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

// MARK: - the new-tab body (the capture door)

/// Verbs, no questions. "Create a note" opens the editor DIRECTLY — no
/// sheet, no intermediate question (owner, 2026-07-31: the desktop has no
/// "capture an idea" concept, and a note starts by writing). Task and
/// event still run through the CaptureSheet, which is where their date and
/// status live. Photo and Open… hand off to the chrome's flags.
struct NewTabBody: View {
    let tabId: UUID

    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @State private var creating = false
    @State private var templatesShown = false

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            verb("Create a note", "square.and.pencil", primary: true) { createNote() }
            verb("From template…", "doc.on.doc") { templatesShown = true }
            verb("New task", "checkmark.circle") { present(.task) }
            verb("New event", "calendar") { present(.event) }
            verb("Photo", "camera") { desk.cameraShown = true }
            verb("Open…", "magnifyingglass") { desk.searchShown = true }
            Spacer()
            Spacer()  // sit the stack a touch above center
        }
        .padding(.horizontal, 48)
        .disabled(creating)
        .sheet(isPresented: $templatesShown) {
            TemplateSheet(verb: .create) { template in
                fromTemplate(template.id)
            }
            .environmentObject(box)
        }
    }

    /// A new note from a template: the same landing as "Create a note" —
    /// this tab becomes the note and the caret is already in it, at the
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
            desk.setContent(tabId, entity: id)
        }
    }

    /// Birth an empty note and become it: this tab flips to the entity and
    /// the editor takes the screen with the caret already in it. The
    /// workspace stamps it exactly as any other creation door does.
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
            desk.setContent(tabId, entity: id)
        }
    }

    /// The verb rides the request so the sheet opens in ITS mode (§5.5);
    /// DeskHost presents — this body will not survive the first commit.
    private func present(_ v: CaptureVerb) {
        desk.captureRequest = CaptureRequest(verb: v, tabId: tabId)
    }

    private func verb(
        _ label: String, _ icon: String, primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: primary ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 15, weight: primary ? .semibold : .regular))
            }
            .foregroundStyle(primary ? LivTheme.onAccent : LivTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: LivTheme.radius)
                    .fill(primary ? LivTheme.accent : LivTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radius)
                    .strokeBorder(
                        primary ? Color.clear : LivTheme.border, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: LivTheme.radius))
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if desk.inspectorShown {
                EntityInspector(id: id)
                    // Clear the floating bottom bar — the inspector's
                    // Undo / Move to Trash row must never rest under it.
                    .padding(.top, 52)
                    .padding(.bottom, 76)
                    .transition(.move(edge: .trailing))
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
        .onAppear {
            seedTitle()
            // Child onAppear fires before the parent's, so the editor reads
            // this through onChange, not its own onAppear.
            if let request = desk.consumeFocus(id) {
                autoFocus = true
                autoCaret = request.caret
            }
        }
        .onChange(of: storedName) { _, fresh in
            // The snapshot moved under us (undo, another surface). Reseed
            // only when the field is not mid-edit, which the comparison
            // against the live draft already tells us.
            if title != fresh, title == "" || title == storedName { title = fresh }
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
        let stored = storedName
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != stored, !typed.isEmpty else {
            title = stored  // an emptied field reverts, never erases the name
            return
        }
        box.set(id, "name", typed)
    }
}

// MARK: - the tab switcher

/// The tab view: it takes the WHOLE screen (owner, 2026-07-29) — top bar
/// and bottom bar both covered, nothing showing through. Card grid with
/// previews, ✕ per card, the dashed new-tab card, and the
/// + | "N tabs" | Done footer, which is the way out.
struct TabSwitcher: View {
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(desk.tabs) { tab in card(tab) }
                    newTabCard
                }
                .padding(16)
            }
            footer
        }
        .background(LivTheme.canvas.ignoresSafeArea())
    }

    /// FeatureWindow's header, same 40pt band, same `v`. It is not
    /// decoration: a ScrollView that touches the top safe area takes it over
    /// and draws its content THROUGH it, so without a band ahead of it a
    /// scrolled card row slides under the clock and the Dynamic Island —
    /// and a ✕ resting behind the Island cannot be tapped, because that
    /// region belongs to the system. Rule 2 bans the blur that would
    /// normally sit there. This band absorbs the inset and gives the tab
    /// view the same way out the feature windows have.
    private var header: some View {
        HStack(spacing: 0) {
            Button { desk.switcherShown = false } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tabs")
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { desk.switcherShown = false }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { g in
                    if g.translation.height > 40 { desk.switcherShown = false }
                }
        )
    }

    // MARK: cards

    private func card(_ tab: DeskTab) -> some View {
        let active = tab.id == desk.activeTabId
        return Button {
            desk.focus(tab.id)
            desk.switcherShown = false
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    Text(cardTitle(tab))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LivTheme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                    Button {
                        desk.close(tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(LivTheme.text3)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close tab")
                }
                .padding(.horizontal, 10)
                Text(cardExcerpt(tab))
                    .font(.system(size: 9.5))
                    .foregroundStyle(LivTheme.muted)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Circle().fill(Hue.dot(cardKind(tab))).frame(width: 5, height: 5)
                    Text(cardKind(tab).uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(LivTheme.text3)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(LivTheme.panel)
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(LivTheme.surface))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        active ? LivTheme.accent : LivTheme.border,
                        lineWidth: active ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var newTabCard: some View {
        Button {
            desk.newTab()
            desk.switcherShown = false
        } label: {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LivTheme.border2,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
                .frame(height: 150)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                        Text("New tab").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(LivTheme.text3)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: footer — + | N tabs | Done

    private var footer: some View {
        HStack {
            Button {
                desk.newTab()
                desk.switcherShown = false
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New tab")
            Spacer()
            Text("\(desk.tabs.count) \(desk.tabs.count == 1 ? "tab" : "tabs")")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(LivTheme.text3)
            Spacer()
            Button {
                desk.switcherShown = false
            } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        // Full screen: no floating bar to clear, just the home indicator
        // (the safe area already handles that).
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }

    // MARK: card copy

    private func cardTitle(_ tab: DeskTab) -> String {
        switch tab.content {
        case .new:
            return "New tab"
        case .entity(let id):
            let t = box.entity(id)?.title ?? ""
            guard !t.isEmpty else { return "Untitled" }
            let clean = livDisplayTitle(t)
            return clean.isEmpty ? t : clean
        }
    }

    /// 3–4 preview lines. Content bodies are not on the wire yet, so the
    /// honest preview is the property cells.
    private func cardExcerpt(_ tab: DeskTab) -> String {
        switch tab.content {
        case .new:
            return "Capture an idea, create a task or event, or open something."
        case .entity(let id):
            guard let row = box.entity(id) else {
                return "Not in this box anymore."
            }
            var lines: [String] = []
            for cell in row.cells ?? [] {
                guard let p = cell.property, !p.isEmpty, p != "name",
                    let v = cell.value, !v.isEmpty
                else { continue }
                lines.append("\(p) · \(v)")
                if lines.count == 4 { break }
            }
            if lines.isEmpty {
                return (row.contentPrint ?? 0) != 0
                    ? "Content lives on this entity." : "No details yet."
            }
            return lines.joined(separator: "\n")
        }
    }

    private func cardKind(_ tab: DeskTab) -> String {
        switch tab.content {
        case .new:
            return "new"
        case .entity(let id):
            guard let row = box.entity(id) else { return "missing" }
            return row.kinds?.first ?? "scrap"
        }
    }
}
