// lotus — the Capture surface (P20d, mockup s-capture): the doorway that
// asks nothing, now a first-class rail surface. Keep = the take card over a
// masonry wall of scraps; Composer = the same door, full width, where a
// leading "# " line becomes the name. The pool is vault-wide by design —
// the workspace lens does not apply here. Scrap titles DISPLAY-derive from
// the first line (✦ = derived, zero writes — a real name is one edit away
// in the inspector; the in-transaction namer verb is recorded for later).

import AppKit
import SwiftUI

struct CaptureSurface: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    var openInbox: () -> Void = {}

    @AppStorage("app.capture.mode.v1") private var mode = "keep"
    @State private var draft = ""
    @State private var chip = "all"
    @FocusState private var draftFocused: Bool

    private var orphans: [EntityRow] { model.orphans() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                takeCard
                underRow
                chipRow
                wall
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lotusFocusCapture)) { _ in
            draftFocused = true
        }
    }

    // MARK: the doorway header + the Keep|Composer toggle

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.warning.opacity(0.15))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "bolt.fill").font(.system(size: 13))
                        .foregroundColor(Theme.warning))
            VStack(alignment: .leading, spacing: 0) {
                Text("Capture").font(.system(size: 15, weight: .bold))
                Text("the doorway that asks nothing")
                    .font(.system(size: 11)).foregroundColor(Theme.mutedFg)
            }
            KbdChip(label: "⌃⌥Space", size: 9.5)
            Text("from anywhere").font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            Spacer()
            HStack(spacing: 2) {
                segButton("Keep", on: mode == "keep") { mode = "keep" }
                segButton("Composer", on: mode == "composer") { mode = "composer" }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel2))
        }
    }

    private func segButton(_ label: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label).font(.system(size: 11.5, weight: on ? .semibold : .regular))
                .foregroundColor(on ? Theme.foreground : Theme.mutedFg)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.surface : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: the take card

    private var takeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                mode == "composer"
                    ? "Compose — a leading # line becomes the name…"
                    : "Capture a thought…",
                text: $draft, axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .lineLimit(mode == "composer" ? 10...30 : 1...8)
            .focused($draftFocused)
            .onSubmit { commit() }
            HStack {
                Spacer()
                Button(action: commit) {
                    HStack(spacing: 5) {
                        Text("Save").font(.system(size: 11.5, weight: .semibold))
                        KbdChip(label: "⌘⏎", size: 9)
                    }
                    .foregroundColor(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accent))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(maxWidth: 640, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(draftFocused ? Theme.accent.opacity(0.5) : Theme.border))
    }

    /// The honesty line + the saves-to readout (presentational until 20j
    /// materializes real files — recorded).
    private var underRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("✦").font(.system(size: 9)).foregroundColor(Theme.warning)
                Text("name it later").font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.warning)
            }
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Theme.warning.opacity(0.12)))
            Text("names derive on save — always visible, always editable")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            Spacer()
            Text("saves to →").font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            HStack(spacing: 4) {
                Image(systemName: "folder").font(.system(size: 9))
                Text("library/inbox/").font(.system(size: 10, design: .monospaced))
            }
            .foregroundColor(Theme.text2)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Theme.panel2))
            .help(model.inVault
                ? "a scrap waits in the box; routing it writes the real file into library/notes/"
                : "the vault path — real files arrive in vault mode")
        }
        .frame(maxWidth: 640)
    }

    // MARK: the quick chips (every chip leads with a monochrome glyph)

    private var chipRow: some View {
        HStack(spacing: 6) {
            filterChip("all", icon: "square.grid.2x2", label: "All")
            filterChip("today", icon: "calendar", label: "Today")
            filterChip("idea", icon: "sparkles", label: "idea")
            filterChip("link", icon: "link", label: "link")
            let unrouted = orphans.count
            Button(action: openInbox) {
                HStack(spacing: 4) {
                    Image(systemName: "tray").font(.system(size: 9.5))
                    Text("unrouted · \(unrouted)").font(.system(size: 10.5))
                }
                .foregroundColor(Theme.mutedFg)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(Theme.border))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("\(unrouted) scrap\(unrouted == 1 ? "" : "s") wait in Inbox › Route")
            Spacer()
        }
    }

    private func filterChip(_ id: String, icon: String, label: String) -> some View {
        let on = chip == id
        return Button { chip = id } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9.5))
                Text(label).font(.system(size: 10.5, weight: on ? .semibold : .regular))
            }
            .foregroundColor(on ? Theme.accent : Theme.mutedFg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(on ? Theme.accentTint : .clear))
            .overlay(Capsule().strokeBorder(on ? Theme.accent.opacity(0.4) : Theme.border))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: the masonry wall

    private var filtered: [EntityRow] {
        orphans.filter { row in
            switch chip {
            case "today":
                guard let created = row.created else { return false }
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f.string(from: Date(timeIntervalSince1970: Double(created)))
                    == f.string(from: Date())
            case "link":
                return scrapBody(row).contains("http")
            case "idea":
                return !scrapBody(row).contains("http")
            default:
                return true
            }
        }
    }

    private var wall: some View {
        // Keep-style masonry: round-robin by estimated height — deterministic,
        // no measurement loop.
        let items = filtered
        let columnCount = 4
        var columns: [[EntityRow]] = Array(repeating: [], count: columnCount)
        var heights = Array(repeating: 0, count: columnCount)
        for row in items {
            let shortest = heights.firstIndex(of: heights.min() ?? 0) ?? 0
            columns[shortest].append(row)
            heights[shortest] += 60 + min(scrapBody(row).count, 160) / 3
        }
        return HStack(alignment: .top, spacing: 12) {
            ForEach(0..<columnCount, id: \.self) { at in
                VStack(spacing: 12) {
                    ForEach(columns[at]) { row in
                        wallCard(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func wallCard(_ row: EntityRow) -> some View {
        let haloed = (model.snap?.inbox ?? []).contains { $0.entity == row.id }
        let title = scrapTitle(row)
        let body = scrapBody(row)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill").font(.system(size: 9))
                    .foregroundColor(Theme.warning)
                Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                if row.title.isEmpty && !title.isEmpty {
                    Text("✦").font(.system(size: 8)).foregroundColor(Theme.warning)
                        .help("name derived from the first line — editable, never silently written")
                }
                Spacer(minLength: 0)
            }
            if !body.isEmpty && body != title {
                Text(body).font(.system(size: 11.5)).foregroundColor(Theme.mutedFg)
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                ForEach(row.cells.filter { $0.kind == "select" }.prefix(2), id: \.property) { cell in
                    ValueChip(text: cell.value, hue: Hues.valueHex(cell.value))
                }
                Spacer(minLength: 0)
                if let created = row.created {
                    Text(age(created)).font(.system(size: 9.5))
                        .foregroundColor(Theme.mutedFg.opacity(0.8))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    haloed
                        ? Theme.warning.opacity(0.8)
                        : selection == row.id ? Theme.accent.opacity(0.6) : Theme.border,
                    lineWidth: haloed ? 1.5 : 1))
        .background(
            // The one soft pulse lives in the halo's shadow, never animated
            // continuously (the in-fiction ruling).
            RoundedRectangle(cornerRadius: 9)
                .fill(haloed ? Theme.warning.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { selection = row.id }
        .help(haloed ? "✦ suggestion waiting — review in Inbox › Tidy" : "")
    }

    // MARK: derived naming (✦ = shown, never written)

    private func scrapContent(_ row: EntityRow) -> String {
        row.cells.first { $0.property == "content" }?.value ?? ""
    }

    private func scrapTitle(_ row: EntityRow) -> String {
        if !row.title.isEmpty { return row.title }
        let line = scrapContent(row)
            .split(separator: "\n").map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return String(line.prefix(52))
    }

    private func scrapBody(_ row: EntityRow) -> String {
        scrapContent(row)
    }

    private func age(_ created: Int64) -> String {
        let seconds = Int(Date().timeIntervalSince1970) - Int(created)
        if seconds < 3600 { return "\(max(1, seconds / 60))m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        if seconds < 604_800 { return "\(seconds / 86400)d" }
        return "\(seconds / 604_800)w"
    }

    // MARK: the commit

    private func commit() {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var name: String?
        if mode == "composer", text.hasPrefix("# ") {
            // Composer: the H1 line becomes the name; the rest the body.
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            name = String(lines[0].dropFirst(2)).trimmingCharacters(in: .whitespaces)
            text = lines.dropFirst().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { text = name ?? "" }
        }
        draft = ""
        model.captureId(text) { id in
            if let id, let name, !name.isEmpty {
                model.set(id, property: "name", value: name)
            }
            Toast.show("Captured — no questions asked. It waits in Inbox › Route.")
        }
        draftFocused = true
    }
}
