// lotus — the Import funnel (P15e). A transient tool you run: drop tabs / files /
// a bookmarks.html / pasted text into the pool, glance-review, then "Import N →"
// commits the whole batch in ONE transaction (the shipped `commit_batch`).
//
// DELTA (recorded): bp14/LB6 wanted the funnel as a content TAB. lotus's tab
// system is Notes-scoped, so forcing an import tool into the Notes tab strip is
// awkward; it opens as a transient SHEET instead — the same "run it, close it,
// it's gone" contract. The pool is pure shell scratch (D1): nothing touches the
// log until the one Import commit.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - the wire item (matches the Rust ImportItem tagged enum)

private struct WireItem: Encodable {
    let kind: String
    var url: String?
    var title: String?
    var path: String?
    var text: String?
}

// MARK: - a candidate — pure shell scratch until the one Import transaction

struct ImportCandidate: Identifiable, Equatable {
    let id = UUID()
    enum Kind { case link, file, scrap }
    enum State { case collected, deferred, discarded }
    let kind: Kind
    var title: String
    var detail: String  // domain · captured / the file's folder / "pasted text"
    let source: String  // the url / path / raw text
    var state: State = .collected

    var glyph: String {
        switch kind {
        case .link: return "link"
        case .file: return "doc"
        case .scrap: return "text.quote"
        }
    }
    fileprivate var wire: WireItem {
        switch kind {
        case .link: return WireItem(kind: "link", url: source, title: title.isEmpty ? nil : title)
        case .file: return WireItem(kind: "file", path: source)
        case .scrap: return WireItem(kind: "scrap", text: source)
        }
    }
}

final class ImportFunnelModel: ObservableObject {
    @Published var candidates: [ImportCandidate] = []
    @Published var selected: UUID?

    var staged: [ImportCandidate] { candidates.filter { $0.state == .collected } }
    var deferred: [ImportCandidate] { candidates.filter { $0.state == .deferred } }
    var discarded: [ImportCandidate] { candidates.filter { $0.state == .discarded } }

    func add(_ items: [ImportCandidate]) {
        guard !items.isEmpty else { return }
        candidates.append(contentsOf: items)
        if selected == nil { selected = staged.first?.id }
    }

    func setState(_ id: UUID, _ s: ImportCandidate.State) {
        guard let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[i].state = s
        if selected == id { selected = staged.first?.id }
    }

    func rename(_ id: UUID, _ title: String) {
        guard let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[i].title = title
    }

    /// The staged items as the tagged JSON `commit_batch` reads.
    func itemsJSON() -> String {
        let wire = staged.map { $0.wire }
        guard let data = try? JSONEncoder().encode(wire),
            let s = String(data: data, encoding: .utf8)
        else { return "[]" }
        return s
    }

    /// The always-visible destination line — what will be CREATED, never a path
    /// (LB1: no bytes copied inward).
    var destinationLine: String {
        let links = staged.filter { $0.kind == .link }.count
        let files = staged.filter { $0.kind == .file }.count
        let scraps = staged.filter { $0.kind == .scrap }.count
        var parts: [String] = []
        if links > 0 { parts.append("\(links) link\(links == 1 ? "" : "s")") }
        if files > 0 { parts.append("\(files) file\(files == 1 ? "" : "s") referenced") }
        if scraps > 0 { parts.append("\(scraps) capture\(scraps == 1 ? "" : "s")") }
        return parts.isEmpty ? "nothing staged yet" : "will create " + parts.joined(separator: " · ")
    }
}

// MARK: - drop parsing

enum ImportDrop {
    /// Build candidates from dropped providers (files / urls / text / a
    /// bookmarks.html). Returns via the callback on the main thread.
    static func parse(_ providers: [NSItemProvider], into add: @escaping ([ImportCandidate]) -> Void) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let items = fromURL(url)
                    DispatchQueue.main.async { add(items) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { str, _ in
                    guard let s = str as? String else { return }
                    DispatchQueue.main.async { add(fromText(s)) }
                }
            }
        }
    }

    static func fromURL(_ url: URL) -> [ImportCandidate] {
        if url.isFileURL {
            if url.pathExtension.lowercased() == "html", let html = try? String(contentsOf: url) {
                let links = bookmarks(from: html)
                if !links.isEmpty { return links }
            }
            let folder = url.deletingLastPathComponent().lastPathComponent
            return [ImportCandidate(kind: .file, title: url.lastPathComponent, detail: folder, source: url.path)]
        }
        return [link(url.absoluteString)]
    }

    static func fromText(_ text: String) -> [ImportCandidate] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let urls = lines.filter { $0.contains("://") }
        if !urls.isEmpty { return urls.map { link($0) } }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [ImportCandidate(kind: .scrap, title: String(trimmed.prefix(60)), detail: "pasted text", source: trimmed)]
    }

    private static func link(_ url: String) -> ImportCandidate {
        let host = URL(string: url)?.host ?? url
        return ImportCandidate(kind: .link, title: "", detail: host, source: url)
    }

    /// A Netscape bookmarks.html: pull every `<A HREF="…">title</A>` (title
    /// survives — LB8; it never gets clobbered by a later scrape).
    static func bookmarks(from html: String) -> [ImportCandidate] {
        var out: [ImportCandidate] = []
        let pattern = "<A[^>]*HREF=\"([^\"]+)\"[^>]*>([^<]*)</A>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return out
        }
        let ns = html as NSString
        re.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 3 else { return }
            let href = ns.substring(with: m.range(at: 1))
            let title = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard href.hasPrefix("http") else { return }
            out.append(
                ImportCandidate(
                    kind: .link, title: title, detail: URL(string: href)?.host ?? href, source: href))
        }
        return out
    }
}

// MARK: - the sheet

struct ImportFunnelView: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var funnel: ImportFunnelModel
    var dismiss: () -> Void = {}
    var onImported: () -> Void = {}

    @State private var targeted = false
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            progressMeter
            Divider()
            HStack(spacing: 0) {
                pool
                Divider()
                review
            }
            Divider()
            destinationBar
        }
        .frame(width: 780, height: 540)
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.and.arrow.down").foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Import").font(.system(size: 14.5, weight: .semibold))
                Text("a tool you run — close it and it's gone")
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

    private var progressMeter: some View {
        HStack(spacing: 14) {
            meterChip(count: funnel.staged.count, label: "staged", color: Theme.accent)
            meterChip(count: funnel.deferred.count, label: "deferred", color: Theme.warning)
            meterChip(count: funnel.discarded.count, label: "discarded", color: Theme.mutedFg)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func meterChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count)").font(.system(size: 12, weight: .semibold).monospacedDigit())
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    // The pool: drop zone + staged cards.
    private var pool: some View {
        VStack(spacing: 0) {
            dropZone
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(funnel.staged) { c in poolCard(c) }
                }
            }
        }
        .frame(width: 300)
    }

    private var dropZone: some View {
        VStack(spacing: 3) {
            Text("Drop tabs, files, or a bookmarks.html")
                .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.accentDeep)
            Text("or paste URLs · nothing is written yet")
                .font(.system(size: 11)).foregroundColor(.secondary)
            Button("Pick files…") { pickFiles() }
                .font(.system(size: 11)).buttonStyle(.link).padding(.top, 2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.accentTint)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            Theme.accent.opacity(targeted ? 0.9 : 0.4),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5])))
        )
        .padding(12)
        .onDrop(of: [.fileURL, .url, .plainText, .text], isTargeted: $targeted) { providers in
            ImportDrop.parse(providers) { funnel.add($0) }
            return true
        }
    }

    private func poolCard(_ c: ImportCandidate) -> some View {
        HStack(spacing: 9) {
            Image(systemName: c.glyph).font(.system(size: 11)).foregroundColor(Theme.mutedFg).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title.isEmpty ? c.source : c.title).font(.system(size: 12)).lineLimit(1)
                Text(c.detail).font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 42)
        .background(funnel.selected == c.id ? Theme.accentTint : Color.clear)
        .overlay(
            Rectangle().fill(Theme.accent).frame(width: 2)
                .opacity(funnel.selected == c.id ? 1 : 0), alignment: .leading
        )
        .contentShape(Rectangle())
        .onTapGesture { funnel.selected = c.id }
    }

    // The review pane: the selected candidate.
    private var review: some View {
        Group {
            if let id = funnel.selected, let c = funnel.staged.first(where: { $0.id == id }) {
                reviewBody(c)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 30)).foregroundColor(Color.secondary.opacity(0.35))
                    Text("Drop something to begin").font(.system(size: 12)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func reviewBody(_ c: ImportCandidate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: c.glyph).foregroundColor(Theme.accent)
                TextField(
                    "Title",
                    text: Binding(
                        get: { c.title },
                        set: { funnel.rename(c.id, $0) })
                )
                .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
            }
            Text(c.source).font(.system(size: 11.5).monospaced()).foregroundColor(.secondary).lineLimit(2)
            Divider()
            Text("INHERITED")
                .font(.system(size: 10.5, weight: .semibold)).kerning(0.5).foregroundColor(.secondary)
            Text("project / area stamping arrives with the workspace picker")
                .font(.system(size: 11.5)).foregroundColor(Theme.mutedFg)
            Spacer()
            HStack(spacing: 8) {
                Button("Defer") { funnel.setState(c.id, .deferred) }.buttonStyle(.bordered)
                Button("Discard", role: .destructive) { funnel.setState(c.id, .discarded) }.buttonStyle(.bordered)
            }
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var destinationBar: some View {
        HStack(spacing: 12) {
            Text(funnel.destinationLine).font(.system(size: 11.5)).foregroundColor(.secondary)
            Spacer()
            Button {
                runImport()
            } label: {
                Text("Import \(funnel.staged.count) →")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
            }
            .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            .disabled(funnel.staged.isEmpty || importing)
        }
        .padding(.horizontal, 16).padding(.vertical, 11).background(Theme.surface2)
    }

    private func runImport() {
        importing = true
        model.importBatch(funnel.itemsJSON()) { n in
            importing = false
            if n >= 0 {
                dismiss()
                onImported()
            }
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            funnel.add(panel.urls.flatMap { ImportDrop.fromURL($0) })
        }
    }
}
