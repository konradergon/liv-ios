import SwiftUI

// MARK: - links, both directions, in properties (owner, 2026-08-17)

/// The links section of the properties surface.
///
/// **One mechanism, two doors** (feature-map §6). Typing `[[` in a body
/// and picking a link here write the same edge — a `Ref` span in the
/// words, or a `related` cell — and the core indexes both, so this list
/// shows them together and the other end sees them come back. The only
/// difference the reader may see is WHERE a link lives, because that is
/// what decides whether it can be removed from a list: the brackets ARE
/// the body link, so a body link is unlinked by editing the words.
///
/// Filing is not a link. `area`, `project` and `people` are references
/// too, and they have their own rows above; a "linked from" list that
/// swallowed every filed note would say nothing (services/src/links.rs).
///
/// The picker is SEARCH — the same screen the `[[` door opens, with the
/// same create row, because a second picker is a second thing to keep
/// true (standing rule 4).
struct LinksSection: View {
    let id: UInt64

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @State private var links: LinkSet = .empty
    @State private var picking = false
    /// A hub can be linked from hundreds of things. The list shows the
    /// first few and says honestly how many it is holding back, rather
    /// than turning a properties panel into a scroll of one thing.
    @State private var showAllOut = false
    @State private var showAllIn = false

    private static let shown = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Links")
            ForEach(Array(visible(links.outRows, all: showAllOut).enumerated()), id: \.element.id) {
                i, link in
                LinkRowView(
                    link: link, row: box.entity(link.id ?? 0),
                    onOpen: { open(link) }, onRemove: removal(for: link))
            }
            moreButton(links.outRows, expanded: $showAllOut)
            linkButton
            if !links.inRows.isEmpty {
                SectionLabel("Linked from")
                ForEach(Array(visible(links.inRows, all: showAllIn).enumerated()), id: \.element.id) {
                    i, link in
                        LinkRowView(
                        link: link, row: box.entity(link.id ?? 0),
                        onOpen: { open(link) }, onRemove: nil)
                }
                moreButton(links.inRows, expanded: $showAllIn)
            }
        }
        .onAppear(perform: load)
        // One user action gets one snapshot (standing rule 8); a link
        // written here rides that same refresh back into this list.
        .onChange(of: box.snap?.entities?.count ?? 0) { _, _ in load() }
        .onChange(of: box.entity(id)?.contentPrint ?? 0) { _, _ in load() }
        // A link written from anywhere else — another tab's body, the
        // clerk, an import — moves one of these two numbers.
        .onChange(of: box.entity(id)?.cells?.count ?? 0) { _, _ in load() }
        .onChange(of: id) { _, _ in load() }
        .sheet(isPresented: $picking) {
            SearchView(onPick: { target, _ in link(to: target) })
                .environmentObject(box)
                .environmentObject(desk)
                .environmentObject(workspaces)
        }
    }

    @EnvironmentObject private var workspaces: WorkspaceModel

    /// The one door that makes a link here. Always present: a create key
    /// that comes and goes is a key you cannot learn (owner, 2026-08-17).
    private var linkButton: some View {
        Button { picking = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: LivType.caption, weight: .semibold))
                Text("Link…")
                    .font(.system(size: LivType.body, weight: .medium))
                Spacer()
            }
            .foregroundStyle(LivTheme.accent)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func visible(_ rows: [LinkRow], all: Bool) -> [LinkRow] {
        all ? rows : Array(rows.prefix(Self.shown))
    }

    @ViewBuilder private func moreButton(
        _ rows: [LinkRow], expanded: Binding<Bool>
    ) -> some View {
        if rows.count > Self.shown && !expanded.wrappedValue {
            Button { expanded.wrappedValue = true } label: {
                Text("Show all \(rows.count)")
                    .font(.system(size: LivType.body, weight: .medium))
                    .foregroundStyle(LivTheme.accent)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// A body link has no remove button here — the brackets are the link.
    private func removal(for link: LinkRow) -> (() -> Void)? {
        guard link.fromBody != true, let target = link.id else { return nil }
        return {
            box.removeCell(id, "related", "#\(target)") { _ in load() }
        }
    }

    private func link(to target: UInt64) {
        guard target != 0, target != id else { return }
        box.addCell(id, "related", "#\(target)") { _ in load() }
    }

    private func open(_ link: LinkRow) {
        guard let target = link.id, box.live(target) != nil else { return }
        desk.open(target)
    }

    private func load() {
        box.links(id) { links = $0 }
    }
}

// MARK: - one row

/// A link row is the thing it points at: its kind chip, its name, and —
/// only when this list is where the link lives — the way to remove it.
private struct LinkRowView: View {
    let link: LinkRow
    /// The snapshot's own row for the target, when the shell holds it —
    /// so a link row is a row like any other (standing rule 4).
    let row: EntityRow?
    let onOpen: () -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                LivListRow(
                    glyph: glyph, tint: color, title: name, untitled: untitled,
                    divided: false)
            }
            .buttonStyle(.plain)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: LivType.caption, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unlink \(name)")
            } else if link.fromBody == true {
                // The whole reason this row has no ✕: the link lives in
                // the words, so the words are where it is removed.
                Image(systemName: "text.quote")
                    .font(.system(size: LivType.caption))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 40, height: 44)
                    .accessibilityLabel("Typed in the note")
            }
        }
    }

    private var untitled: Bool {
        if let row { return livRowIsUntitled(row) }
        let n = wireName
        return n.isEmpty || n == "#\(link.id ?? 0)"
    }

    private var wireName: String {
        (link.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var name: String {
        if let row { return livRowTitle(row) }
        return untitled ? "Untitled" : wireName
    }

    private var glyph: LivGlyph {
        row.map { LivKind.glyph(of: $0) } ?? LivKind.named(link.kinds?.first ?? "").glyph()
    }

    private var color: Color {
        row.map { LivKind.color(of: $0) } ?? LivKind.named(link.kinds?.first ?? "").color
    }
}

