// liv — Comms (P20g, BP-15 · override O6): read-only messages, resolved
// to people. Message lists ARE saved views (no folders, no second inbox);
// fetch runs at open and on the button only — nothing runs on a timer;
// every message carries an external-id, so re-import is a no-op. v0
// ingestion is import-shaped: drop a JSON feed file on the surface
// ([{external_id, from, source, sent?, body}]) — honestly labeled; live
// connectors are a later fence-opening. "Liv reads your messages; it
// never sends them. there is no compose box."

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MessageRowData: Identifiable {
    let id: UInt64
    let row: EntityRow
    let fromPerson: UInt64?
    let fromLabel: String
    let source: String
    let sent: String
    let body: String
    let unread: Bool
}

func commsMessages(_ model: BoxModel) -> [MessageRowData] {
    model.rows(model.snap?.everything ?? [])
        .filter { $0.kinds.contains("message") }
        .map { row in
            let cell = { (name: String) -> CellRow? in
                row.cells.first { $0.property == name && !$0.value.isEmpty }
            }
            let fromCell = cell("from")
            let person = fromCell?.refTarget
            let label = person.flatMap { model.entity($0)?.title }
                ?? cell("from-label")?.value ?? "unknown"
            return MessageRowData(
                id: row.id, row: row,
                fromPerson: person,
                fromLabel: label,
                source: cell("source")?.value ?? "",
                sent: cell("sent")?.value ?? "",
                body: cell("content")?.value ?? "",
                unread: cell("unread")?.value == "true")
        }
        .sorted { ($0.sent, $0.row.created ?? 0) > ($1.sent, $1.row.created ?? 0) }
}

/// The left panel: message lists (saved views) + the filter chips.
struct CommsNav: View {
    @ObservedObject var model: BoxModel
    @Binding var list: String
    @Binding var fromFilter: String?
    @Binding var sourceFilter: String?

    private var messages: [MessageRowData] { commsMessages(model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MESSAGE LISTS — SAVED VIEWS")
                .font(.system(size: 9.5, weight: .bold)).kerning(0.5)
                .foregroundColor(Theme.mutedFg)
                .padding(.horizontal, 8).padding(.top, 8)
            let unreadKnown = messages.filter { $0.unread && $0.fromPerson != nil }.count
            listRow("unread", label: "Unread from people I know", count: unreadKnown)
            ForEach(sources, id: \.self) { source in
                listRow(
                    "source:\(source)", label: source,
                    count: messages.filter { $0.source == source }.count)
            }
            listRow("all", label: "All messages", count: messages.count)
            Text("a list here is an ordinary saved view — filter, group and pin it like anything else. no folders, no second inbox.")
                .font(.system(size: 9)).foregroundColor(Theme.mutedFg.opacity(0.8))
                .padding(.horizontal, 8)
            Text("FILTER").font(.system(size: 9.5, weight: .bold)).kerning(0.5)
                .foregroundColor(Theme.mutedFg)
                .padding(.horizontal, 8).padding(.top, 10)
            HStack(spacing: 5) {
                filterMenu(
                    "person", label: fromFilter ?? "from",
                    values: Array(Set(messages.map(\.fromLabel))).sorted(),
                    binding: $fromFilter)
                filterMenu(
                    "bubble.left", label: sourceFilter ?? "source",
                    values: sources, binding: $sourceFilter)
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
    }

    private var sources: [String] {
        var seen: [String] = []
        for m in messages where !m.source.isEmpty {
            if !seen.contains(m.source) { seen.append(m.source) }
        }
        return seen
    }

    private func listRow(_ id: String, label: String, count: Int) -> some View {
        let on = list == id
        return Button { list = id } label: {
            HStack(spacing: 7) {
                Image(systemName: id == "unread" ? "envelope.badge" : id == "all" ? "tray.full" : "bubble.left")
                    .font(.system(size: 10)).foregroundColor(on ? Theme.accent : Theme.mutedFg)
                    .frame(width: 14)
                Text(label).font(.system(size: 11.5, weight: on ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 10).monospacedDigit())
                    .foregroundColor(Theme.mutedFg)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.accentTint : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filterMenu(
        _ icon: String, label: String, values: [String], binding: Binding<String?>
    ) -> some View {
        Menu {
            Button("any") { binding.wrappedValue = nil }
            ForEach(values, id: \.self) { value in
                Button(value) { binding.wrappedValue = value }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8.5))
                Text(label).font(.system(size: 10)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7))
            }
            .foregroundColor(binding.wrappedValue == nil ? Theme.mutedFg : Theme.accent)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Theme.border))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

struct CommsView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    @Binding var list: String
    @Binding var fromFilter: String?
    @Binding var sourceFilter: String?
    var openPerson: (UInt64) -> Void = { _ in }

    @State private var lastFetch = "at open"
    @State private var dropActive = false

    private var filtered: [MessageRowData] {
        commsMessages(model).filter { m in
            let inList: Bool
            switch list {
            case "unread": inList = m.unread && m.fromPerson != nil
            case let l where l.hasPrefix("source:"): inList = m.source == String(l.dropFirst(7))
            default: inList = true
            }
            return inList
                && (fromFilter == nil || m.fromLabel == fromFilter)
                && (sourceFilter == nil || m.source == sourceFilter)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 26)).foregroundColor(Theme.foreground.opacity(0.12))
                    Text("No messages here.")
                        .font(.system(size: 12.5)).foregroundColor(.secondary)
                    Text("Drop a feed file (JSON: external_id · from · source · sent · body) — live connectors are a later fence-opening.")
                        .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(filtered) { m in
                            if selection == m.id {
                                expandedCard(m)
                            } else {
                                messageRow(m)
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 8)
                }
            }
            HStack {
                Image(systemName: "lock").font(.system(size: 8.5))
                Text("Liv reads your messages; it never sends them. there is no compose box.")
                    .font(.system(size: 10))
                Spacer()
            }
            .foregroundColor(Theme.mutedFg)
            .padding(.horizontal, 24).padding(.vertical, 5)
            .overlay(Divider(), alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .json], isTargeted: $dropActive) { providers in
            handleDrop(providers)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    dropActive ? Theme.accent.opacity(0.6) : .clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .padding(6))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                // v0 (recorded): fetch-at-open with file-drop ingestion —
                // the button is the honest no-op the sim itself performs.
                lastFetch = "just now"
                Toast.show("fetched — 0 new · external-id makes re-import a no-op")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9.5))
                    Text("Fetch now").font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Theme.text2)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(Theme.border))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Text("fetched at open — nothing runs on a timer · last fetch \(lastFetch)")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            Spacer()
            Text("re-import is a no-op — every message carries an external-id")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg.opacity(0.8))
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .overlay(Divider(), alignment: .bottom)
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }

    private func sourceShort(_ source: String) -> String {
        source.components(separatedBy: " · ").first ?? source
    }

    private func sentDisplay(_ m: MessageRowData) -> String {
        // Relative rendering: time today · weekday this week · the date.
        let stamp = m.sent
        guard stamp.count >= 10 else { return stamp }
        let dateISO = String(stamp.prefix(10))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dateISO) else { return stamp }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return stamp.count > 11 ? String(stamp.suffix(5)) : "today"
        }
        if cal.isDateInYesterday(date) { return "yesterday" }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            let g = DateFormatter()
            g.setLocalizedDateFormatFromTemplate("EEE")
            return g.string(from: date)
        }
        let g = DateFormatter()
        g.setLocalizedDateFormatFromTemplate("dMMM")
        return g.string(from: date)
    }

    private func messageRow(_ m: MessageRowData) -> some View {
        Button {
            selection = m.id
            if m.unread {
                // One undoable write — reading clears the dot; a refresh
                // never re-sets it (unread is written at first ingest only).
                model.set(m.id, property: "unread", value: "false")
            }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent)
                    .frame(width: 7, height: 7)
                    .opacity(m.unread ? 1 : 0)
                senderChip(m)
                Text(m.body).font(.system(size: 11.5))
                    .foregroundColor(Theme.text2).lineLimit(1)
                Spacer(minLength: 6)
                if !m.source.isEmpty {
                    Text(sourceShort(m.source)).font(.system(size: 9.5))
                        .foregroundColor(Theme.mutedFg)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.panel2))
                }
                Text(sentDisplay(m)).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.mutedFg)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func senderChip(_ m: MessageRowData) -> some View {
        Group {
            if let person = m.fromPerson {
                Button { openPerson(person) } label: {
                    chipBody(m)
                }
                .buttonStyle(.plain)
                .help("opens \(m.fromLabel) — messages resolve to the person entity")
            } else {
                chipBody(m)
                    .help("no person entity yet — the sender is feed-owned text")
            }
        }
    }

    private func chipBody(_ m: MessageRowData) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.panel2)
                .frame(width: 15, height: 15)
                .overlay(
                    Text(initials(m.fromLabel)).font(.system(size: 6.5, weight: .semibold))
                        .foregroundColor(Theme.text2))
            Text(m.fromLabel)
                .font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private func expandedCard(_ m: MessageRowData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                senderChip(m)
                Text("via \(m.source) · sent \(m.sent)")
                    .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                Spacer()
                if let ext = m.row.cells.first(where: { $0.property == "external-id" })?.value {
                    Text("external-id: \(ext)")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(Theme.mutedFg.opacity(0.8))
                        .lineLimit(1)
                        .help("the dedupe key — refresh updates feed-owned cells, never yours")
                }
                Button {
                    selection = nil
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8))
                        .foregroundColor(Theme.mutedFg).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text(m.body).font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                cellBox(
                    "FEED-OWNED — UPDATES ON REFRESH",
                    rows: [("from", m.fromLabel), ("sent", m.sent), ("body", "as received")])
                cellBox(
                    "YOURS — NEVER TOUCHED BY REFRESH",
                    rows: m.row.cells
                        .filter { ["subjects", "status", "related"].contains($0.property) }
                        .map { ($0.property, $0.value) })
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border2))
    }

    private func cellBox(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8.5, weight: .bold)).kerning(0.4)
                .foregroundColor(Theme.mutedFg)
            if rows.isEmpty {
                Text("—").font(.system(size: 10.5)).foregroundColor(Theme.mutedFg.opacity(0.6))
            }
            ForEach(rows, id: \.0) { name, value in
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 9.5)).foregroundColor(Theme.mutedFg)
                        .frame(width: 50, alignment: .leading)
                    Text(value).font(.system(size: 10.5)).lineLimit(1)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, let data = try? Data(contentsOf: url),
                let json = String(data: data, encoding: .utf8)
            else {
                DispatchQueue.main.async { Toast.show("That file didn't read as a feed.") }
                return
            }
            DispatchQueue.main.async {
                model.importMessages(json) { changed in
                    Toast.show(
                        changed > 0
                            ? "fetched — \(changed) new or refreshed · one batch, one undo (⌘⌥Z)"
                            : changed == 0
                                ? "fetched — 0 new · external-id makes re-import a no-op"
                                : "The feed was refused — [{external_id, from, source, sent, body}]")
                }
            }
        }
        return true
    }
}
