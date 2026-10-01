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
    let id: LivEntityID

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
        let outRows = visible(links.outRows, all: showAllOut)
        let inRows = visible(links.inRows, all: showAllIn)
        VStack(alignment: .leading, spacing: 0) {
            // A GROUP OF ITS OWN (the clearer board): a small sheet label
            // and a card — the links are content of a different shape
            // from the property rows above, so they get a word. The label
            // is the CARD's, so it takes the card's inset (36).
            LivCard(label: "Links", labelStyle: .sheet, fill: LivTheme.panel2) {
                ForEach(outRows) { link in
                    LinkRowView(
                        link: link, row: box.entity(link.id ?? .absent),
                        onOpen: { open(link) }, onRemove: removal(for: link))
                }
                moreRow(links.outRows, expanded: $showAllOut)
                addRow
            }
            if !links.inRows.isEmpty {
                LivCard(label: "Linked from", labelStyle: .sheet, fill: LivTheme.panel2) {
                    ForEach(Array(inRows.enumerated()), id: \.element.id) { i, link in
                        LinkRowView(
                            link: link, row: box.entity(link.id ?? .absent),
                            onOpen: { open(link) }, onRemove: nil, backlink: true,
                            divided: i < inRows.count - 1 || moreShows(links.inRows, showAllIn))
                    }
                    moreRow(links.inRows, expanded: $showAllIn, last: true)
                }
            }
        }
        .onAppear(perform: load)
        // One user action gets one snapshot (standing rule 8); a link
        // written here rides that same refresh back into this list.
        .onChange(of: box.snap?.entities?.count ?? 0) { _, _ in load() }
        .onChange(of: box.entity(id)?.recency ?? 0) { _, _ in load() }
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

    /// THE DOOR THAT MAKES ONE — always the card's last row, always there:
    /// a create key that comes and goes is a key you cannot learn (owner,
    /// 2026-08-17). A full-width row whose words are the accent — a door,
    /// which is one of the three shapes a tappable thing may wear.
    private var addRow: some View {
        Button {
            picking = true
        } label: {
            // The accent is set ON the words: the row paints its own title
            // ink, and an outer style never reaches past it.
            LivCardRow(
                divided: false,
                lead: { LivCardMark(glyph: .plus) },
                title: { Text("Add link").foregroundStyle(LivTheme.accent) },
                trailing: { EmptyView() }
            )
        }
        .buttonStyle(.plain)
    }

    private func visible(_ rows: [LinkRow], all: Bool) -> [LinkRow] {
        all ? rows : Array(rows.prefix(Self.shown))
    }

    private func moreShows(_ rows: [LinkRow], _ expanded: Bool) -> Bool {
        rows.count > Self.shown && !expanded
    }

    /// "Show all 12" — a row of the card, words in the accent, no chevron.
    @ViewBuilder private func moreRow(
        _ rows: [LinkRow], expanded: Binding<Bool>, last: Bool = false
    ) -> some View {
        if moreShows(rows, expanded.wrappedValue) {
            Button {
                expanded.wrappedValue = true
            } label: {
                LivCardRow(
                    divided: !last, rule: LivCards.ruleBare,
                    lead: { EmptyView() },
                    title: { Text("Show all \(rows.count)").foregroundStyle(LivTheme.accent) },
                    trailing: { EmptyView() }
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// A body link has no remove button here — the brackets are the link.
    private func removal(for link: LinkRow) -> (() -> Void)? {
        guard link.fromBody != true, let target = link.id else { return nil }
        return {
            // `#<id>` is the ABI's own grammar for "a reference to this"
            // (services parses it with `trim_start_matches('#')`), not a
            // string anyone reads. It is a write, not a label.
            // `engineId`, not `written`: this value crosses to C and the
        // engine reads it with `thing_named`, which is `from_hex` past
        // the `#`. The shell's storage form was decimal, so both ends of
        // a link in the properties card were refused (slice 5b).
        box.removeCell(id, "related", "#\(engineId(target))") { _ in load() }
        }
    }

    private func link(to target: LivEntityID) {
        guard !target.isAbsent, target != id else { return }
        box.addCell(id, "related", "#\(engineId(target))") { _ in load() }
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

/// A link row is the thing it points at: its glyph, its name, where the
/// link lives ("Linked here" — a link made in this card — or "In the
/// text"), and a chevron: it opens.
///
/// UNLINKING MOVED OFF THE ROW. The board's row ends in a chevron, so the
/// ✕ that stood there is now the row's context menu and an accessibility
/// action, "Unlink <name>" — the same verb, a press-and-hold away. A body
/// link has neither: the brackets ARE the link, so the words are where it
/// is removed.
private struct LinkRowView: View {
    let link: LinkRow
    /// The snapshot's own row for the target, when the shell holds it —
    /// so a link row is a row like any other (standing rule 4).
    let row: EntityRow?
    let onOpen: () -> Void
    let onRemove: (() -> Void)?
    var backlink = false
    var divided = true

    var body: some View {
        Button(action: onOpen) {
            LivCardRow(
                glyph: glyph, title: name,
                detail: backlink ? nil : (link.fromBody == true ? "In the text" : "Linked here"),
                muted: untitled, divided: divided
            ) {
                LivChevron()
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onRemove {
                Button("Unlink \(name)", role: .destructive, action: onRemove)
            }
        }
        .accessibilityActions {
            if let onRemove {
                Button("Unlink \(name)", action: onRemove)
            }
        }
    }

    private var untitled: Bool {
        if let row { return livRowIsUntitled(row) }
        // The `"#<id>"` comparison that used to live here is gone with the
        // placeholder it looked for: the core sends a made name now, never
        // an id (2026-09-13). A wire link the snapshot has no row for is
        // one we cannot ask about, so an empty name is all there is to go
        // on.
        return wireName.isEmpty
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
}

