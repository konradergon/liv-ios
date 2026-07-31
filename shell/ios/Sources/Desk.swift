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

    var body: some View {
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
        .background(LivTheme.canvas)
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

// MARK: - the new-tab body (the capture door)

/// Verbs, no questions. Idea/task/event run in the CaptureSheet; the
/// committed entity becomes THIS tab's content. Photo and Open… hand off
/// to the chrome's camera / search flags.
struct NewTabBody: View {
    let tabId: UUID

    @EnvironmentObject var desk: DeskModel

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            verb("Capture an idea", "lightbulb", primary: true) { present(.idea) }
            verb("New task", "checkmark.circle") { present(.task) }
            verb("New event", "calendar") { present(.event) }
            verb("Photo", "camera") { desk.cameraShown = true }
            verb("Open…", "magnifyingglass") { desk.searchShown = true }
            Text("A new tab holds one thing — capture it, then shape it.")
                .font(.system(size: 11))
                .foregroundStyle(LivTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Spacer()
            Spacer()  // sit the stack a touch above center
        }
        .padding(.horizontal, 48)
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
                    .font(.system(size: 13, weight: primary ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 13, weight: primary ? .semibold : .regular))
            }
            .foregroundStyle(primary ? LivTheme.onAccent : LivTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
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

/// One entity, content-first. The 26pt collapse button top-right swaps
/// the body under the title for the full inspector (Obsidian's properties
/// chevron); the title itself stays put and stays editable.
struct EntityTabBody: View {
    let id: UInt64

    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel
    @State private var title = ""
    @State private var titleSeeded = false
    // Rehearsal hook: `simctl launch … -desk.boot.inspector 1` boots with the
    // metadata editor open (headless screenshots; launch args feed UserDefaults).
    @State private var inspectorShown = UserDefaults.standard.bool(forKey: "desk.boot.inspector")
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
    /// title is derived from its content's first line. Two editors over one
    /// value is the bug this asks about — for a scrap the content editor is
    /// the only surface, so the title row simply is not there.
    private var named: Bool {
        (box.entity(id)?.cells ?? []).contains {
            $0.property == "name" && !($0.value ?? "").isEmpty
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                if named {
                    titleField
                } else if let row = box.entity(id) {
                    // A scrap has no title row; without something in it the
                    // header is a dead band with a lone chevron. Its meta
                    // line moves up here instead of below.
                    metaLine(row)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                }
                collapseButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            if inspectorShown {
                EntityInspector(id: id)
                    // Clear the floating bottom bar, exactly as bodyContent
                    // does below. Without it a long property list ends under
                    // the bar and the bar takes the taps: "Undo" hit the `^`
                    // and opened the features menu, "Move to Trash" hit the
                    // tab square. The clearance belongs here, not inside
                    // EntityInspector — that view also renders on surfaces
                    // where no bar floats.
                    .padding(.bottom, 76)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let row = box.entity(id) {
                bodyContent(row)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { seedTitle() }
        .onChange(of: box.entity(id)?.title) {
            // The snapshot moved under us (undo, another surface): reseed
            // unless the caret is in the field — a draft never loses.
            if !titleFocused {
                titleSeeded = false
                seedTitle()
            }
        }
    }

    // MARK: title — inline-editable, commits through the box

    private var titleField: some View {
        TextField("Untitled", text: $title, axis: .vertical)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(LivTheme.text)
            .lineLimit(1...3)
            .focused($titleFocused)
            .submitLabel(.done)
            .onSubmit(commitTitle)
            .onChange(of: titleFocused) {
                if !titleFocused { commitTitle() }
            }
            .padding(.vertical, 4)
    }

    private func seedTitle() {
        guard !titleSeeded else { return }
        title = box.entity(id)?.title ?? ""
        titleSeeded = true
    }

    private func commitTitle() {
        let stored = box.entity(id)?.title ?? ""
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != stored, !typed.isEmpty else {
            title = stored  // an emptied field reverts, never erases the name
            return
        }
        box.set(id, "name", typed)
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { inspectorShown.toggle() }
        } label: {
            Image(systemName: inspectorShown ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(inspectorShown ? LivTheme.accent : LivTheme.text2)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                        .fill(LivTheme.panel2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                        .strokeBorder(LivTheme.border, lineWidth: 0.5)
                )
                // The visual stays 26pt; the hit target meets the 44pt HIG
                // floor (eval §5.9) — the glyph pinned where it always was.
                .frame(width: 44, height: 44, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Metadata")
    }

    // MARK: the content body

    /// Metadata on top, then the note itself filling everything left — M3.
    /// The editor is not in a ScrollView: it scrolls itself, and a text view
    /// nested in a scroll view has no height to fill.
    private func bodyContent(_ row: EntityRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Named entities keep their meta under the title; a scrap's rides
            // in the header row above (see `content`).
            if named { metaLine(row) }
            // The chip row is PERSISTENT here (eval §5.6) — the sheet's
            // confirmation is transient; the body is where it lives.
            EntityChipRow(id: row.id)
            refSection(row)
            NoteEditor(id: row.id, placeholder: named ? "Write…" : "Write this scrap out…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        // Clear the floating bottom bar — the editor must never hide under it.
        .padding(.bottom, 76)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metaLine(_ row: EntityRow) -> some View {
        HStack(spacing: 6) {
            Text(deskKindLabel(row))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LivTheme.text3)
            if let created = row.created {
                Text("· created \(deskStampLabel(created))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(LivTheme.muted)
            }
        }
    }

    /// Reference cells as chips; a tap opens the target as another tab —
    /// the Ref-span gesture grammar, chip-shaped (a Ref span INSIDE the
    /// content is a token in the editor's buffer, tap-to-open pending).
    @ViewBuilder private func refSection(_ row: EntityRow) -> some View {
        let refs = (row.cells ?? []).filter {
            $0.kind == "reference" && $0.refTarget != nil
        }
        if !refs.isEmpty {
            SectionLabel("Linked").padding(.top, 8)
            DeskChipFlow(spacing: 6) {
                ForEach(Array(refs.enumerated()), id: \.offset) { _, cell in
                    Button {
                        if let target = cell.refTarget { desk.open(target) }
                    } label: {
                        ValueChip(cell.value ?? "#\(cell.refTarget ?? 0)", big: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

// MARK: - helpers (file-private, Desk-prefixed by law)

private func deskKindLabel(_ row: EntityRow) -> String {
    let kinds = row.kinds ?? []
    return kinds.isEmpty ? "scrap" : kinds.joined(separator: " · ")
}

private func deskStampLabel(_ stamp: Int64) -> String {
    var out = Civil.dayLabel(Civil.day(of: stamp))
    let time = Civil.timeString(stamp)
    if !time.isEmpty { out += " " + time }
    return out
}

/// A wrapping chip row (CaptureSheet's Flow is file-private there).
private struct DeskChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(
            width: width.isFinite ? width : max(x - spacing, 0), height: y + rowH)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
