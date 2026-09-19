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
        VStack(alignment: .leading, spacing: 0) {
            // A PROPERTY, LIKE EVERY OTHER ROW ON THIS CARD (owner,
            // 2026-09-15: "should we make the link appear like any
            // property? the '+ Link…' clickable text looks bad").
            //
            // It was a `SectionLabel` over a run of blue words. The card
            // no longer carries headings over its properties at all
            // (Detail.swift), and this is a property: `links` on the
            // left in the same face every field name wears, the door on
            // the VALUE side as the app's own hollow add chip — the one
            // the capture sheet's +Tag row already uses.
            SectionGap()
            linkRow
            ForEach(Array(visible(links.outRows, all: showAllOut).enumerated()), id: \.element.id) {
                i, link in
                DetailHairline()
                LinkRowView(
                    link: link, row: box.entity(link.id ?? .absent),
                    onOpen: { open(link) }, onRemove: removal(for: link))
            }
            moreButton(links.outRows, expanded: $showAllOut)
            if !links.inRows.isEmpty {
                SectionGap()
                DetailRowLabel("linked from")
                    .frame(height: LivRow.height, alignment: .leading)
                ForEach(Array(visible(links.inRows, all: showAllIn).enumerated()), id: \.element.id) {
                    i, link in
                    DetailHairline()
                    LinkRowView(
                        link: link, row: box.entity(link.id ?? .absent),
                        onOpen: { open(link) }, onRemove: nil)
                }
                moreButton(links.inRows, expanded: $showAllIn)
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

    /// THE `links` PROPERTY ROW — a name on the left, the door on the
    /// right, the geometry every other field on this card has.
    ///
    /// The door is always present: a create key that comes and goes is a
    /// key you cannot learn (owner, 2026-08-17). What changed twice is
    /// its dress.
    ///
    /// It was `+ Link…` in accent ink with no shape around it, which
    /// reads as a hyperlink, and the rule is that the only clickable
    /// TEXT in this app is a link inside a note (owner, 2026-09-15). It
    /// became an `AddChip` — right about the shape, wrong about the
    /// grammar: it left a small hollow pill sitting where every other
    /// row on this card has its VALUE (owner, 2026-09-18: "links
    /// metadata has a strange '(+link)' blip. make it same as other
    /// metadata").
    ///
    /// SO IT IS A PROPERTY ROW, EXACTLY (Detail.swift, `row`): the whole
    /// row is the button, the name is on the left, and the right-hand
    /// column holds the value — a dash when there is none, the count
    /// when there is. The door did not go away; the row IS the door,
    /// which is how every other field on this card opens its own editor.
    private var linkRow: some View {
        Button {
            picking = true
        } label: {
            HStack {
                DetailRowLabel("links")
                Spacer(minLength: 12)
                if links.outRows.isEmpty {
                    DetailEmptyValue()
                } else {
                    // The face the standard row's overflow count wears,
                    // and it counts what the list below holds — including
                    // the ones folded behind "Show all".
                    Text("\(links.outRows.count)")
                        .font(.system(size: LivType.body).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                }
            }
            .frame(minHeight: LivRow.height)
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
            // A CHIP, not a blue word — the same rule as the add door
            // above it, and the same recipe with a different mark.
            HStack {
                AddChip("Show all \(rows.count)", symbol: "chevron.down") {
                    expanded.wrappedValue = true
                }
                Spacer(minLength: 0)
            }
            .frame(height: LivRow.height)
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
            }
            // A LINK TYPED IN THE BODY USED TO GET A GLYPH HERE — a
            // 40x44 `text.quote` you could not press, standing in the
            // column where every other row has its ✕. It said "this one
            // is different" by occupying the space of a control and
            // doing nothing, which is the worst of both: it read as a
            // broken button and it explained nothing. The row already
            // reads differently — it has no ✕ — and that IS the
            // statement (the link lives in the words, so the words are
            // where it is removed). Its meaning moves to the row's
            // accessibility hint, where it can be a sentence.
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

    private var color: Color {
        row.map { LivKind.color(of: $0) } ?? LivKind.named(link.kinds?.first ?? "").color
    }
}

