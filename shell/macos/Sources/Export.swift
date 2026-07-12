// lotus — the Export composer (P15f). A transient sheet: select by filter
// (uncheck to exclude), compose a ≤2-level folder structure, preview the tree,
// then Export → COPY. The honest way out — the box keeps everything; the folder
// is an independent projection, never a mirror (LB5; move-out refused).

import AppKit
import SwiftUI

final class ExportComposerModel: ObservableObject {
    @Published var filterText = ""
    @Published var excluded: Set<UInt64> = []
    @Published var group1: PropertyRow?
    @Published var group2: PropertyRow?
    @Published var dest: URL?
}

struct ExportComposerView: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var composer: ExportComposerModel
    var dismiss: () -> Void = {}

    @State private var exporting = false

    // The exportable pool: user entities, narrowed by the free-text filter.
    private var pool: [EntityRow] {
        let q = composer.filterText.trimmingCharacters(in: .whitespaces).lowercased()
        return model.rows(model.snap?.everything ?? []).filter {
            q.isEmpty || $0.title.lowercased().contains(q)
        }
    }
    private var matched: [EntityRow] { pool.filter { !composer.excluded.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                selector
                Divider()
                composerPane
            }
        }
        .frame(width: 820, height: 560)
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.and.arrow.up").foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Export").font(.system(size: 14.5, weight: .semibold))
                Text("the honest way out — copy everything, whenever")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.mutedFg).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // Left: the filter + the matched checklist.
    private var selector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundColor(Theme.mutedFg)
                TextField("Filter by name…", text: $composer.filterText)
                    .textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            Divider()
            HStack {
                Text("\(matched.count) match")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.accentDeep)
                if !composer.excluded.isEmpty {
                    Text("· \(composer.excluded.count) excluded").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(pool) { row in exportRow(row) }
                }
            }
        }
        .frame(width: 380)
    }

    private func exportRow(_ row: EntityRow) -> some View {
        let checked = !composer.excluded.contains(row.id)
        return HStack(spacing: 9) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 13)).foregroundColor(checked ? Theme.accent : Theme.mutedFg)
            Image(systemName: isFile(row) ? "doc" : "text.alignleft")
                .font(.system(size: 11)).foregroundColor(Theme.mutedFg).frame(width: 14)
            Text(row.title.isEmpty ? "Untitled" : row.title)
                .font(.system(size: 12)).lineLimit(1)
                .foregroundColor(checked ? .primary : .secondary)
                .strikethrough(!checked, color: .secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 32)
        .contentShape(Rectangle())
        .onTapGesture {
            if checked { composer.excluded.insert(row.id) } else { composer.excluded.remove(row.id) }
        }
    }

    // Right: structure composer + tree preview + destination + Export.
    private var composerPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("STRUCTURE").font(.system(size: 10.5, weight: .semibold)).kerning(0.5).foregroundColor(.secondary)
            HStack(spacing: 8) {
                Text("Group by").font(.system(size: 12)).foregroundColor(.secondary)
                groupMenu($composer.group1)
                Text("then").font(.system(size: 12)).foregroundColor(.secondary)
                groupMenu($composer.group2)
            }
            Text("PREVIEW").font(.system(size: 10.5, weight: .semibold)).kerning(0.5).foregroundColor(.secondary)
            treePreview
            Spacer()
            destinationLine
            Button { runExport() } label: {
                Text("Export \(matched.count) → Copy")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
            }
            .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            .disabled(matched.isEmpty || composer.dest == nil || exporting)
            Text("Copy only — the box keeps everything. A projection, never a mirror.")
                .font(.system(size: 10.5)).foregroundColor(.secondary).frame(maxWidth: .infinity)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func groupMenu(_ binding: Binding<PropertyRow?>) -> some View {
        Menu {
            Button("None") { binding.wrappedValue = nil }
            ForEach(model.properties()) { prop in
                Button(prop.name) { binding.wrappedValue = prop }
            }
        } label: {
            Text(binding.wrappedValue?.name ?? "—")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(binding.wrappedValue == nil ? .secondary : Theme.accent)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var treePreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                let paths = matched.map { relPath($0) }.sorted()
                if paths.isEmpty {
                    Text("Nothing matches — loosen the filter.")
                        .font(.system(size: 11.5)).foregroundColor(.secondary)
                } else {
                    ForEach(Array(paths.prefix(200).enumerated()), id: \.offset) { _, p in
                        Text(p).font(.system(size: 11).monospaced()).foregroundColor(.primary)
                    }
                    if paths.count > 200 {
                        Text("… \(paths.count - 200) more").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface2))
    }

    private var destinationLine: some View {
        HStack(spacing: 8) {
            Text("→").foregroundColor(.secondary)
            Text(composer.dest?.path ?? "choose a folder…")
                .font(.system(size: 11.5).monospaced())
                .foregroundColor(composer.dest == nil ? .secondary : .primary).lineLimit(1)
            Spacer()
            Button("Browse…") { pickDest() }.font(.system(size: 11)).buttonStyle(.bordered)
        }
    }

    // MARK: helpers

    private func isFile(_ row: EntityRow) -> Bool { row.cells.contains { $0.kind == "file" } }

    private func relPath(_ row: EntityRow) -> String {
        var parts: [String] = []
        for group in [composer.group1, composer.group2] {
            guard let group else { continue }
            let value = row.cells.first { $0.property == group.name }?.value ?? "ungrouped"
            parts.append(sanitize(value))
        }
        let name = row.title.isEmpty ? "untitled-\(row.id)" : row.title
        parts.append(isFile(row) ? sanitize(name) : sanitize(name) + ".md")
        return parts.joined(separator: "/")
    }

    private func sanitize(_ s: String) -> String {
        let cleaned = s.map { "/\\:".contains($0) ? "-" : $0 }
        let trimmed = String(cleaned).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "untitled" : trimmed
    }

    private func runExport() {
        guard let dest = composer.dest else { return }
        exporting = true
        let ids = matched.map { $0.id }
        let groups = [composer.group1?.id, composer.group2?.id].compactMap { $0 }
        model.exportBatch(ids: ids, groupProps: groups, dest: dest.path) { n in
            exporting = false
            if n >= 0 { dismiss() }
        }
    }

    private func pickDest() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { composer.dest = panel.url }
    }
}
