// liv — the local graph (P18a, bp12 Scene B): the right panel's fifth lens.
// Hub = the focused object, radial rings = hop depth; values are squares in
// their frozen VALUE_HEX hue (byte-identical to their chips), objects are
// neutral circles, the hub is the ONE lake-green. A navigator only: click an
// object → it becomes the focus; click a value → the one filter engine.
// Deterministic and static — one Canvas draw, no physics, no timers.

import AppKit
import SwiftUI

// MARK: - the model

struct GraphNode: Identifiable {
    enum Kind {
        case object(UInt64)
        /// property display + value display — the search qualifier's parts.
        case value(property: String, value: String)
    }
    let id: String
    let kind: Kind
    let label: String
    /// 1-based hop ring.
    let ring: Int
    /// Unit angle around the ring (radians).
    let angle: Double
    /// The node this one was reached FROM — the edge's other end ("" = hub).
    let parent: String
}

struct LocalGraph {
    var nodes: [GraphNode] = []
    var objectCount = 0
    var valueCount = 0
    /// Dropped beyond the per-ring budget — the honest "+N more".
    var hidden = 0
}

/// Build the focused object's neighborhood, breadth-first, deterministic.
/// Ring budget ~12 by recency (id desc — owner call #6); values hop exactly
/// one step when enabled. Derived per (focus · depth · toggle · snapshot);
/// never touches the box.
func buildLocalGraph(
    model: BoxModel, focus: UInt64, depth: Int, valueHops: Bool, perRing: Int = 12
) -> LocalGraph {
    var graph = LocalGraph()
    guard let hub = model.entity(focus) else { return graph }

    var placedObjects: Set<UInt64> = [focus]
    var placedValues: Set<String> = []

    /// One entity's outgoing reference targets + select values.
    func neighbors(of row: EntityRow) -> (objects: [UInt64], values: [(String, String)]) {
        var objects: [UInt64] = []
        var values: [(String, String)] = []
        for cell in row.cells {
            guard let target = cell.refTarget, !cell.value.isEmpty else { continue }
            if cell.kind == "select" {
                values.append((cell.property, cell.value))
            } else if cell.kind == "reference", model.entity(target) != nil {
                objects.append(target)
            }
        }
        return (objects, values)
    }

    // Objects per select value — ONE snapshot pass builds every bucket
    // (the per-value scan cost 12 full sweeps per render; the review's
    // finding). Lazily built only when the value-hop expansion runs.
    var valueBuckets: [String: [UInt64]]? = nil
    func sharers(property: String, value: String) -> [UInt64] {
        if valueBuckets == nil {
            var buckets: [String: [UInt64]] = [:]
            for row in (model.snap?.entities ?? []) where !row.kinds.contains("widget") {
                for cell in row.cells where cell.kind == "select" && !cell.value.isEmpty {
                    buckets["\(cell.property)=\(cell.value)", default: []].append(row.id)
                }
            }
            valueBuckets = buckets
        }
        return valueBuckets?["\(property)=\(value)"] ?? []
    }

    var frontier: [(row: EntityRow, nodeId: String)] = [(hub, "")]
    for ring in 1...max(1, depth) {
        var candidates: [(node: GraphNode, row: EntityRow?)] = []
        var seenValues: Set<String> = []

        for (row, parentId) in frontier {
            let (objects, values) = neighbors(of: row)
            // Value nodes mount on ring 1 only (the hub's own metadata);
            // deeper rings connect through objects.
            if ring == 1 {
                for (property, value) in values {
                    let key = "v:\(property)=\(value)"
                    guard !placedValues.contains(key), seenValues.insert(key).inserted else {
                        continue
                    }
                    candidates.append((
                        GraphNode(
                            id: key, kind: .value(property: property, value: value),
                            label: value, ring: ring, angle: 0, parent: parentId),
                        nil
                    ))
                }
            }
            let connected = objects + model.backlinks(of: row.id).map(\.id)
            for target in connected.uniqued() where !placedObjects.contains(target) {
                guard let targetRow = model.entity(target) else { continue }
                candidates.append((
                    GraphNode(
                        id: "o:\(target)", kind: .object(target),
                        label: targetRow.title, ring: ring, angle: 0, parent: parentId),
                    targetRow
                ))
            }
        }

        // Value-hop expansion: objects sharing a ring-1 value join ring 2,
        // attached to the value node.
        if valueHops, ring == 2 {
            for node in graph.nodes where node.ring == 1 {
                guard case .value(let property, let value) = node.kind else { continue }
                for sharer in sharers(property: property, value: value)
                where !placedObjects.contains(sharer) {
                    guard let row = model.entity(sharer) else { continue }
                    candidates.append((
                        GraphNode(
                            id: "o:\(sharer)", kind: .object(sharer),
                            label: row.title, ring: ring, angle: 0, parent: node.id),
                        row
                    ))
                }
            }
        }

        // Dedup (a node can be reached twice within a ring), budget by
        // recency (higher id = newer), count the honest remainder.
        var unique: [(node: GraphNode, row: EntityRow?)] = []
        var seen: Set<String> = []
        for candidate in candidates where seen.insert(candidate.node.id).inserted {
            unique.append(candidate)
        }
        // Recency is NUMERIC (a string sort ranked "o:99" over "o:100" —
        // the review's finding): values first (stable by label), then
        // objects newest-first by their real id.
        func rank(_ node: GraphNode) -> (Int, UInt64, String) {
            switch node.kind {
            case .value: return (0, 0, node.label)
            case .object(let id): return (1, UInt64.max - id, "")
            }
        }
        unique.sort { a, b in
            let (ra, rb) = (rank(a.node), rank(b.node))
            return ra.0 != rb.0 ? ra.0 < rb.0 : (ra.1 != rb.1 ? ra.1 < rb.1 : ra.2 < rb.2)
        }
        let kept = Array(unique.prefix(perRing))
        graph.hidden += unique.count - kept.count

        // Deterministic angles: even spread, ring-index offset so rings
        // don't stack labels.
        let count = kept.count
        var next: [(row: EntityRow, nodeId: String)] = []
        for (index, candidate) in kept.enumerated() {
            var node = candidate.node
            let angle = (Double(index) / Double(max(1, count))) * 2 * .pi
                - .pi / 2 + Double(ring) * 0.35
            node = GraphNode(
                id: node.id, kind: node.kind, label: node.label,
                ring: ring, angle: angle, parent: node.parent)
            graph.nodes.append(node)
            switch node.kind {
            case .object(let id):
                placedObjects.insert(id)
                graph.objectCount += 1
                if let row = candidate.row { next.append((row, node.id)) }
            case .value:
                placedValues.insert(node.id)
                graph.valueCount += 1
            }
        }
        frontier = next
        if frontier.isEmpty && ring >= 1 && !valueHops { break }
    }
    return graph
}

extension Array where Element: Hashable {
    fileprivate func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - the lens pane

struct GraphLensPane: View {
    @ObservedObject var model: BoxModel
    let focus: UInt64?
    var select: (UInt64) -> Void = { _ in }
    var searchFor: (String) -> Void = { _ in }

    /// Shell prefs — never the box (acceptance).
    @AppStorage("app.graph.depth.v1") private var depth = 2
    @AppStorage("app.graph.valueHops.v1") private var valueHops = true

    var body: some View {
        if let focus, let hub = model.entity(focus) {
            let graph = buildLocalGraph(
                model: model, focus: focus, depth: depth, valueHops: valueHops)
            VStack(spacing: 0) {
                if graph.nodes.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 24))
                            .foregroundColor(Theme.foreground.opacity(0.12))
                        Text("Nothing connects here yet. Add a value or a [[link]] and the map draws itself.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.mutedFg)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geo in
                        canvas(graph, hub: hub, size: geo.size)
                    }
                }
                footer(graph)
            }
        } else {
            VStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.foreground.opacity(0.12))
                Text("Select an object to map its neighborhood.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.mutedFg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func position(_ node: GraphNode, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = ringRadius(node.ring, in: size)
        return CGPoint(
            x: center.x + Foundation.cos(node.angle) * radius,
            y: center.y + Foundation.sin(node.angle) * radius)
    }

    private func ringRadius(_ ring: Int, in size: CGSize) -> CGFloat {
        let max = min(size.width, size.height) / 2 - 26
        return max * [0.38, 0.68, 0.97][min(ring, 3) - 1]
    }

    private func canvas(_ graph: LocalGraph, hub: EntityRow, size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var positions: [String: CGPoint] = ["": center]
        for node in graph.nodes { positions[node.id] = position(node, in: size) }

        return Canvas { ctx, _ in
            // Rings, dashed, with depth numerals.
            for ring in 1...max(1, depth) {
                let radius = ringRadius(ring, in: size)
                let rect = CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2)
                ctx.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Theme.foreground.opacity(0.10)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                ctx.draw(
                    Text("\(ring)").font(.system(size: 8)).foregroundColor(Theme.mutedFg.opacity(0.6)),
                    at: CGPoint(x: center.x + radius - 7, y: center.y - radius + 9))
            }
            // Edges: each node to its parent.
            for node in graph.nodes {
                guard let from = positions[node.parent], let to = positions[node.id] else {
                    continue
                }
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                ctx.stroke(
                    path,
                    with: .color(Theme.foreground.opacity(node.ring == 1 ? 0.22 : 0.12)),
                    lineWidth: 1)
            }
            // Nodes + labels.
            for node in graph.nodes {
                guard let at = positions[node.id] else { continue }
                switch node.kind {
                case .value(_, let value):
                    let hue = Color(nsColor: Hues.valueHex(value))
                    let rect = CGRect(x: at.x - 6.5, y: at.y - 6.5, width: 13, height: 13)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3.5), with: .color(hue))
                case .object:
                    let radius: CGFloat = node.ring == 1 ? 6 : 5
                    let rect = CGRect(
                        x: at.x - radius, y: at.y - radius,
                        width: radius * 2, height: radius * 2)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .color(Theme.foreground.opacity(node.ring == 1 ? 0.28 : 0.16)))
                    ctx.stroke(
                        Path(ellipseIn: rect),
                        with: .color(Theme.foreground.opacity(node.ring == 1 ? 0.5 : 0.3)),
                        lineWidth: 1)
                }
                if node.ring <= 2 {
                    let label = node.label.count > 22
                        ? String(node.label.prefix(21)) + "…" : node.label
                    ctx.draw(
                        Text(label)
                            .font(.system(size: node.ring == 1 ? 9 : 8.5))
                            .foregroundColor(
                                node.ring == 1
                                    ? Theme.mutedFg : Theme.mutedFg.opacity(0.65)),
                        at: CGPoint(x: at.x, y: at.y - 13))
                }
            }
            // The hub — the ONE lake-green — plus its halo and label.
            let hubRect = CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)
            ctx.fill(Path(ellipseIn: hubRect), with: .color(Theme.accent))
            ctx.stroke(
                Path(ellipseIn: hubRect.insetBy(dx: -5, dy: -5)),
                with: .color(Theme.accent.opacity(0.35)), lineWidth: 3)
            let hubLabel = hub.title.count > 26 ? String(hub.title.prefix(25)) + "…" : hub.title
            ctx.draw(
                Text(hubLabel).font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.foreground),
                at: CGPoint(x: center.x, y: center.y + 23))
            // The honest remainder.
            if graph.hidden > 0 {
                ctx.draw(
                    Text("+\(graph.hidden) more beyond the budget")
                        .font(.system(size: 9)).foregroundColor(Theme.mutedFg),
                    at: CGPoint(x: center.x, y: size.height - 10))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { tap in
                // Nearest node within 14pt: object → refocus; value → filter.
                var best: (node: GraphNode, distance: CGFloat)?
                for node in graph.nodes {
                    guard let at = positions[node.id] else { continue }
                    let distance = hypot(at.x - tap.location.x, at.y - tap.location.y)
                    if distance < 14, distance < (best?.distance ?? .infinity) {
                        best = (node, distance)
                    }
                }
                guard let hit = best?.node else { return }
                switch hit.kind {
                case .object(let id): select(id)
                case .value(let property, let value):
                    searchFor(searchQualifier(property, value))
                }
            })
    }

    private func footer(_ graph: LocalGraph) -> some View {
        HStack(spacing: 8) {
            Text("\(graph.objectCount) objects · \(graph.valueCount) values")
                .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                ForEach([1, 2, 3], id: \.self) { level in
                    Button {
                        depth = level
                    } label: {
                        Text("\(level)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(depth == level ? Theme.accent : Theme.mutedFg)
                            .padding(.horizontal, 7).padding(.vertical, 1)
                            .background(
                                depth == level
                                    ? Theme.accent.opacity(0.16) : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Button {
                valueHops.toggle()
            } label: {
                Text("values")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(valueHops ? Theme.accent : Theme.mutedFg)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(valueHops ? Theme.accent.opacity(0.16) : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hop through shared values")
            Button("Vault graph") {
                NotificationCenter.default.post(name: .livVaultGraph, object: focus)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.accent)
            .help("The whole vault as a map (⌃⇧G)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(Divider(), alignment: .top)
    }
}
