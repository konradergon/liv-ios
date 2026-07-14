// lotus — the vault graph overlay (P18c, bp12 Scene A). The second
// interface-0.5 carve-out (owner call #4): summon (⌃⇧G) / glance / jump /
// Esc — it consumes no tab and the shell behind is untouched. A navigator
// only: click a value → the one filter engine; click an object → open it.
//
// Canvas-rendered, hand-rolled springs, no d3 (BRIEF §8). DETERMINISTIC:
// positions seed from the frozen FNV hash, the timestep is fixed, and the
// springs settle & freeze (≤ ~4s) — one draw at rest, zero CPU. Reheat
// restarts the sim. Values are squares in their VALUE_HEX hue; objects are
// neutral circles sized by link count; an explicit reference edge is
// HEAVIER NEUTRAL than a via-value edge (weight, not hue — recorded delta).

import AppKit
import SwiftUI

// MARK: - the simulation

final class VaultGraphModel: ObservableObject {
    struct Node: Identifiable {
        enum Kind {
            case object(UInt64)
            case value(property: String, value: String)
        }
        let id: String
        let kind: Kind
        let label: String
        var links = 0
        var position: CGPoint = .zero
        var velocity: CGVector = .zero
        var pinned = false
    }
    struct Edge {
        let a: Int
        let b: Int
        /// An explicit reference (heavier neutral) vs via-value (thin).
        let heavy: Bool
    }

    @Published private(set) var frozen = false
    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    private(set) var unlinkedHidden = 0
    private var ticks = 0

    // Forces (shell prefs, applied live).
    var repulsion: Double = 1.0
    var linkDistance: Double = 1.0

    /// Rebuild from the snapshot under the current filters, reseed, reheat.
    func build(
        model: BoxModel,
        hiddenKinds: Set<String>,
        hiddenValueProps: Set<String>,
        showUnlinked: Bool,
        focus: UInt64?
    ) {
        let rows = model.snap?.entities ?? []
        var nodeIndex: [String: Int] = [:]
        var built: [Node] = []
        var builtEdges: [Edge] = []

        func objectKey(_ id: UInt64) -> String { "o:\(id)" }
        func addObject(_ row: EntityRow) -> Int {
            let key = objectKey(row.id)
            if let at = nodeIndex[key] { return at }
            built.append(
                Node(id: key, kind: .object(row.id), label: row.title))
            nodeIndex[key] = built.count - 1
            return built.count - 1
        }

        let shown = rows.filter { !hiddenKinds.contains(graphKind($0)) }
        let shownIds = Set(shown.map(\.id))
        for row in shown { _ = addObject(row) }

        for row in shown {
            let from = nodeIndex[objectKey(row.id)]!
            for cell in row.cells {
                guard let target = cell.refTarget, !cell.value.isEmpty else { continue }
                if cell.kind == "select", !hiddenValueProps.contains(cell.property) {
                    let key = "v:\(cell.property)=\(cell.value)"
                    let at: Int
                    if let existing = nodeIndex[key] {
                        at = existing
                    } else {
                        built.append(
                            Node(
                                id: key,
                                kind: .value(property: cell.property, value: cell.value),
                                label: cell.value))
                        nodeIndex[key] = built.count - 1
                        at = built.count - 1
                    }
                    builtEdges.append(Edge(a: from, b: at, heavy: false))
                } else if cell.kind == "reference", shownIds.contains(target), target != row.id {
                    let to = nodeIndex[objectKey(target)]!
                    builtEdges.append(Edge(a: from, b: to, heavy: true))
                }
            }
        }

        for edge in builtEdges {
            built[edge.a].links += 1
            built[edge.b].links += 1
        }
        // Unlinked objects hide by default — counted honestly, dashed at the
        // rim when shown.
        if !showUnlinked {
            let keep = built.enumerated().filter { $0.element.links > 0 }.map(\.offset)
            let remap = Dictionary(uniqueKeysWithValues: keep.enumerated().map { ($1, $0) })
            unlinkedHidden = built.count - keep.count
            builtEdges = builtEdges.compactMap { edge in
                guard let a = remap[edge.a], let b = remap[edge.b] else { return nil }
                return Edge(a: a, b: b, heavy: edge.heavy)
            }
            built = keep.map { built[$0] }
        } else {
            unlinkedHidden = 0
        }

        // Seeded, deterministic starting positions (FNV over the node key);
        // the focused object starts at the center — the camera's anchor.
        for index in built.indices {
            let hash = Hues.hash(built[index].id)
            let angle = Double(hash % 3600) / 3600.0 * 2 * .pi
            let radius = 90 + Double((hash >> 16) % 220)
            built[index].position = CGPoint(
                x: Foundation.cos(angle) * radius, y: Foundation.sin(angle) * radius)
            built[index].velocity = .zero
            built[index].pinned = false
            if case .object(let id) = built[index].kind, id == focus {
                built[index].position = .zero
                built[index].pinned = true
            }
        }
        nodes = built
        edges = builtEdges
        reheat()
        // The degrade threshold (owner call #6): a huge box settles
        // synchronously once and freezes — never an animation loop.
        if nodes.count > 2000 {
            for _ in 0..<90 { step() }
            ticks = 10_000
            frozen = true
        }
    }

    func reheat() {
        ticks = 0
        frozen = false
    }

    /// One fixed-timestep tick — springs + repulsion + center pull. Freezes
    /// on rest or after ~4s (240 ticks at 60fps).
    func step() {
        guard !frozen, !nodes.isEmpty else { return }
        ticks += 1
        let rest = 70.0 * linkDistance
        let repulse = 2600.0 * repulsion
        var forces = [CGVector](repeating: .zero, count: nodes.count)

        // Repulsion, O(n²) with a cutoff — fine at lens scale, degraded above.
        for i in nodes.indices {
            for j in (i + 1)..<nodes.count {
                let dx = nodes[j].position.x - nodes[i].position.x
                let dy = nodes[j].position.y - nodes[i].position.y
                let d2 = max(120, dx * dx + dy * dy)
                guard d2 < 260_000 else { continue }
                let f = repulse / d2
                let d = sqrt(d2)
                let fx = f * dx / d
                let fy = f * dy / d
                forces[i].dx -= fx
                forces[i].dy -= fy
                forces[j].dx += fx
                forces[j].dy += fy
            }
        }
        // Springs.
        for edge in edges {
            let dx = nodes[edge.b].position.x - nodes[edge.a].position.x
            let dy = nodes[edge.b].position.y - nodes[edge.a].position.y
            let d = max(1, sqrt(dx * dx + dy * dy))
            let stretch = (d - rest) * 0.02
            let fx = stretch * dx / d
            let fy = stretch * dy / d
            forces[edge.a].dx += fx
            forces[edge.a].dy += fy
            forces[edge.b].dx -= fx
            forces[edge.b].dy -= fy
        }
        // Center pull + integrate (fixed dt), damped.
        var maxSpeed = 0.0
        for i in nodes.indices {
            guard !nodes[i].pinned else { continue }
            forces[i].dx -= nodes[i].position.x * 0.004
            forces[i].dy -= nodes[i].position.y * 0.004
            nodes[i].velocity.dx = (nodes[i].velocity.dx + forces[i].dx) * 0.86
            nodes[i].velocity.dy = (nodes[i].velocity.dy + forces[i].dy) * 0.86
            nodes[i].position.x += nodes[i].velocity.dx
            nodes[i].position.y += nodes[i].velocity.dy
            maxSpeed = max(
                maxSpeed, abs(nodes[i].velocity.dx) + abs(nodes[i].velocity.dy))
        }
        if ticks > 240 || (ticks > 30 && maxSpeed < 0.05) {
            frozen = true
        }
        objectWillChange.send()
    }

    func drag(_ index: Int, to point: CGPoint) {
        guard nodes.indices.contains(index) else { return }
        nodes[index].position = point
        nodes[index].pinned = true
        reheat()
    }

    var objectCount: Int {
        nodes.filter { if case .object = $0.kind { return true }; return false }.count
    }
    var valueCount: Int { nodes.count - objectCount }
}

/// The graph's kind bucket for the filter rail — mirrors rowKindIcon.
func graphKind(_ row: EntityRow) -> String {
    if row.kinds.contains("task") || row.status != nil { return "tasks" }
    if row.kinds.contains("event") { return "events" }
    if row.kinds.contains("person") || row.kinds.contains("contact") { return "contacts" }
    if row.cells.contains(where: { $0.kind == "file" }) { return "files" }
    return "notes"
}

// MARK: - the overlay

struct VaultGraphOverlay: View {
    @ObservedObject var model: BoxModel
    /// Entered from the lens: the camera anchors on this object.
    let focus: UInt64?
    let dismiss: () -> Void
    let open: (UInt64) -> Void
    let searchFor: (String) -> Void

    @StateObject private var sim = VaultGraphModel()
    @State private var find = ""
    @State private var hover: String?
    @State private var camera: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var draggedNode: Int?
    @State private var filtersOpen = true
    @State private var hiddenKinds: Set<String> = []
    @State private var hiddenValueProps: Set<String> = []
    @State private var showUnlinked = false
    @FocusState private var findFocused: Bool
    @AppStorage("app.vaultgraph.repulsion.v1") private var repulsion = 1.0
    @AppStorage("app.vaultgraph.linkdist.v1") private var linkDistance = 1.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(spacing: 0) {
                topBar
                Divider()
                HStack(spacing: 0) {
                    if filtersOpen { filterRail }
                    canvasBody
                }
            }
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            .padding(16)
        }
        .onAppear { rebuild() }
        .onChange(of: hiddenKinds) { rebuild() }
        .onChange(of: hiddenValueProps) { rebuild() }
        .onChange(of: showUnlinked) { rebuild() }
    }

    private func rebuild() {
        sim.repulsion = repulsion
        sim.linkDistance = linkDistance
        sim.build(
            model: model, hiddenKinds: hiddenKinds, hiddenValueProps: hiddenValueProps,
            showUnlinked: showUnlinked, focus: focus)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Vault graph").font(.system(size: 13, weight: .bold))
            Text("\(sim.objectCount) objects · \(sim.valueCount) values · \(sim.edges.count) edges"
                + (sim.unlinkedHidden > 0 ? " · \(sim.unlinkedHidden) unlinked hidden" : ""))
                .font(.system(size: 11)).foregroundColor(Theme.mutedFg)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
                TextField("Find a node…", text: $find)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($findFocused)
                    .onExitCommand {
                        // First Esc clears the query; a second closes.
                        if find.isEmpty { dismiss() } else { find = "" }
                    }
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
            .frame(maxWidth: 240)
            Button {
                filtersOpen.toggle()
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                    .foregroundColor(filtersOpen ? Theme.accent : Theme.mutedFg)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Filters")
            Spacer()
            if !sim.frozen {
                Text("settling…").font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            } else {
                Button("Reheat") { sim.reheat() }
                    .buttonStyle(.plain).font(.system(size: 10.5))
                    .foregroundColor(Theme.accent)
            }
            HStack(spacing: 2) {
                zoomButton("minus") { zoom = max(0.25, zoom / 1.3) }
                Text("\(Int(zoom * 100))%")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(Theme.mutedFg).frame(width: 38)
                zoomButton("plus") { zoom = min(4, zoom * 1.3) }
            }
            Text("Esc").font(.system(size: 9.5, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                .foregroundColor(Theme.mutedFg)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11))
                    .foregroundColor(Theme.mutedFg).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func zoomButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.mutedFg)
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filterRail: some View {
        let rows = model.snap?.entities ?? []
        var kindCounts: [String: Int] = [:]
        for row in rows { kindCounts[graphKind(row), default: 0] += 1 }
        var valueProps: [String: Int] = [:]
        for row in rows {
            for cell in row.cells where cell.kind == "select" && !cell.value.isEmpty {
                valueProps[cell.property, default: 0] += 1
            }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                railHeader("OBJECT KINDS")
                ForEach(kindCounts.keys.sorted(), id: \.self) { kind in
                    filterRow(
                        kind, count: kindCounts[kind] ?? 0,
                        on: !hiddenKinds.contains(kind)
                    ) {
                        if hiddenKinds.contains(kind) {
                            hiddenKinds.remove(kind)
                        } else {
                            hiddenKinds.insert(kind)
                        }
                    }
                }
                railHeader("VALUE KINDS")
                ForEach(valueProps.keys.sorted(), id: \.self) { property in
                    filterRow(
                        property, count: valueProps[property] ?? 0,
                        on: !hiddenValueProps.contains(property)
                    ) {
                        if hiddenValueProps.contains(property) {
                            hiddenValueProps.remove(property)
                        } else {
                            hiddenValueProps.insert(property)
                        }
                    }
                }
                railHeader("DISPLAY")
                filterRow("unlinked at the rim", count: sim.unlinkedHidden, on: showUnlinked) {
                    showUnlinked.toggle()
                }
                railHeader("FORCES")
                forceSlider("Repulsion", value: $repulsion, range: 0.3...2.5)
                forceSlider("Link distance", value: $linkDistance, range: 0.4...2.2)
                Text("settles & freezes ~4 s")
                    .font(.system(size: 9)).foregroundColor(Theme.mutedFg)
                    .padding(.horizontal, 10).padding(.top, 4)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 190)
        .overlay(Divider(), alignment: .trailing)
    }

    private func railHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold)).kerning(0.5)
            .foregroundColor(Theme.mutedFg)
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
    }

    private func filterRow(
        _ label: String, count: Int, on: Bool, toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundColor(on ? Theme.accent : Theme.mutedFg)
                Text(label).font(.system(size: 11))
                Spacer()
                Text("\(count)").font(.system(size: 10).monospacedDigit())
                    .foregroundColor(Theme.mutedFg)
            }
            .padding(.horizontal, 10).padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func forceSlider(
        _ label: String, value: Binding<Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            Slider(value: value, in: range) { editing in
                if !editing {
                    sim.repulsion = repulsion
                    sim.linkDistance = linkDistance
                    sim.reheat()
                }
            }
            .controlSize(.mini)
        }
        .padding(.horizontal, 10).padding(.top, 3)
    }

    // MARK: canvas

    @ViewBuilder
    private var canvasBody: some View {
        if sim.nodes.isEmpty {
            // A16: the thin-vault state — honest, with the route pointer.
            VStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.foreground.opacity(0.12))
                Text("Nothing to map yet")
                    .font(.system(size: 13, weight: .semibold))
                Text("Edges appear when notes share a value (area, project, subject) or reference each other. Route your inbox and the map draws itself.")
                    .font(.system(size: 11.5)).foregroundColor(Theme.mutedFg)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            canvasLive
        }
    }

    private var canvasLive: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: sim.frozen)) { _ in
                let _ = sim.step()
                canvasContent(size: geo.size)
            }
        }
        .background(
            // The dot grid.
            Canvas { ctx, size in
                let step: CGFloat = 22
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                            with: .color(Theme.foreground.opacity(0.05)))
                        x += step
                    }
                    y += step
                }
            })
        .clipped()
    }

    private func transform(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + (point.x * zoom) + camera.width,
            y: size.height / 2 + (point.y * zoom) + camera.height)
    }

    private func inverse(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - size.width / 2 - camera.width) / zoom,
            y: (point.y - size.height / 2 - camera.height) / zoom)
    }

    private func canvasContent(size: CGSize) -> some View {
        let matching = find.trimmingCharacters(in: .whitespaces).lowercased()
        return Canvas { ctx, _ in
            // Edges first: heavy neutral for explicit references, thin for
            // via-value (weight, not hue).
            for edge in sim.edges {
                let a = transform(sim.nodes[edge.a].position, in: size)
                let b = transform(sim.nodes[edge.b].position, in: size)
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                ctx.stroke(
                    path,
                    with: .color(Theme.foreground.opacity(edge.heavy ? 0.4 : 0.14)),
                    lineWidth: edge.heavy ? 2 : 1)
            }
            for node in sim.nodes {
                let at = transform(node.position, in: size)
                guard at.x > -30, at.x < size.width + 30, at.y > -30, at.y < size.height + 30
                else { continue }
                let dimmed = !matching.isEmpty && !node.label.lowercased().contains(matching)
                switch node.kind {
                case .value(_, let value):
                    let side = 12 * zoom.squareRoot()
                    let rect = CGRect(
                        x: at.x - side / 2, y: at.y - side / 2, width: side, height: side)
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: side * 0.28),
                        with: .color(
                            Color(nsColor: Hues.valueHex(value)).opacity(dimmed ? 0.2 : 1)))
                    ctx.draw(
                        Text(node.label).font(.system(size: 9.5))
                            .foregroundColor(Theme.mutedFg.opacity(dimmed ? 0.3 : 1)),
                        at: CGPoint(x: at.x, y: at.y - side / 2 - 8))
                case .object(let id):
                    let radius = (4 + min(5, CGFloat(node.links) * 0.7)) * zoom.squareRoot()
                    let rect = CGRect(
                        x: at.x - radius, y: at.y - radius,
                        width: radius * 2, height: radius * 2)
                    if node.links == 0 {
                        ctx.stroke(
                            Path(ellipseIn: rect),
                            with: .color(Theme.foreground.opacity(dimmed ? 0.12 : 0.35)),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    } else {
                        ctx.fill(
                            Path(ellipseIn: rect),
                            with: .color(Theme.foreground.opacity(dimmed ? 0.06 : 0.2)))
                        ctx.stroke(
                            Path(ellipseIn: rect),
                            with: .color(Theme.foreground.opacity(dimmed ? 0.12 : 0.5)),
                            lineWidth: 1)
                    }
                    if id == focus {
                        ctx.stroke(
                            Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                            with: .color(Theme.accent), lineWidth: 1.5)
                    }
                    if hover == node.id || (!matching.isEmpty && !dimmed) {
                        ctx.draw(
                            Text(node.label.count > 24
                                ? String(node.label.prefix(23)) + "…" : node.label)
                                .font(.system(size: 9.5))
                                .foregroundColor(Theme.foreground.opacity(0.85)),
                            at: CGPoint(x: at.x, y: at.y - radius - 9))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hover = nearestNode(to: location, in: size)?.id
            case .ended:
                hover = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { drag in
                    if draggedNode == nil {
                        if let hit = nearestNode(to: drag.startLocation, in: size),
                            let index = sim.nodes.firstIndex(where: { $0.id == hit.id })
                        {
                            draggedNode = index
                        } else {
                            draggedNode = -1  // background pan
                        }
                    }
                    if let index = draggedNode, index >= 0 {
                        sim.drag(index, to: inverse(drag.location, in: size))
                    } else {
                        camera = CGSize(
                            width: camera.width + drag.translation.width * 0.15,
                            height: camera.height + drag.translation.height * 0.15)
                    }
                }
                .onEnded { _ in draggedNode = nil })
        .simultaneousGesture(
            SpatialTapGesture().onEnded { tap in
                guard let hit = nearestNode(to: tap.location, in: size) else { return }
                switch hit.kind {
                case .object(let id):
                    dismiss()
                    open(id)
                case .value(let property, let value):
                    dismiss()
                    searchFor(searchQualifier(property, value))
                }
            })
    }

    private func nearestNode(to point: CGPoint, in size: CGSize) -> VaultGraphModel.Node? {
        var best: (node: VaultGraphModel.Node, distance: CGFloat)?
        for node in sim.nodes {
            let at = transform(node.position, in: size)
            let distance = hypot(at.x - point.x, at.y - point.y)
            if distance < 16, distance < (best?.distance ?? .infinity) {
                best = (node, distance)
            }
        }
        return best?.node
    }
}
