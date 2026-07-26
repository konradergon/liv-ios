// liv iOS — Search (design/ios.md §6): the global full-screen overlay the
// chrome presents while desk.searchShown. A pill bar over liv_search_at —
// the DSL parses in Rust, never here; the shell sends the raw query (150ms
// debounce) and renders the ranked ids from the snapshot index, grouped by
// first kind — task → event → note → file, then the rest alphabetical,
// untyped scraps last. Rank order survives inside each group. A result
// opens as a Desk tab and the overlay closes itself; Cancel is the
// overlay's own close affordance (self-contained — the chrome only flips
// the flag). Find-or-create (eval §4.3, Obsidian's quick switcher): a
// query no rendered title matches exactly ends in a Create row — capture
// as a scrap, open the tab, drop the veil.

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @State private var query = ""
    /// Raw ranked ids from the core, before the workspace lens.
    @State private var rawHits: [UInt64] = []
    /// Monotonic ticket: a stale debounce or a stale result must drop.
    @State private var seq = 0
    @FocusState private var focused: Bool

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// The lens (M4), applied to the CORE's ranked ids — rank order is
    /// preserved, the workspace only removes. Search is filtered; the
    /// Inbox never is.
    private var hits: [UInt64] {
        let lens = workspaces.activeQuery
        guard workspaces.lensOn, !lens.isInert else { return rawHits }
        return rawHits.filter { id in
            guard let row = box.entity(id) else { return true }
            return lens.matches(row)
        }
    }

    /// Find-or-create offers only when no row we actually render is
    /// titled exactly like the query (case-insensitive).
    private var offersCreate: Bool {
        guard !trimmed.isEmpty else { return false }
        return !hits.contains { id in
            guard let title = box.entity(id)?.title else { return false }
            return title.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private var groups: [(kind: String, ids: [UInt64])] {
        var order: [String] = []
        var byKind: [String: [UInt64]] = [:]
        for id in hits {
            guard let row = box.entity(id) else { continue }
            let kind = row.kinds?.first ?? ""
            if byKind[kind] == nil { order.append(kind) }
            byKind[kind, default: []].append(id)
        }
        return order
            .sorted { SearchView.rank($0) < SearchView.rank($1) }
            .map { (kind: $0, ids: byKind[$0] ?? []) }
    }

    private static func rank(_ kind: String) -> (Int, String) {
        switch kind {
        case "task": return (0, "")
        case "event": return (1, "")
        case "note": return (2, "")
        case "file": return (3, "")
        case "": return (5, "")
        default: return (4, kind)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                pill
                Button {
                    desk.searchShown = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LivTheme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            if workspaces.lensOn {
                HStack {
                    LensChip(label: workspaces.lensLabel)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            if trimmed.isEmpty {
                ScrollView {
                    EmptyHint("Search the box.").padding(.top, 40)
                }
            } else if hits.isEmpty {
                // Zero results: the Create row IS the empty state, at the
                // top of the scroll area so the keyboard never hides it.
                ScrollView {
                    createButton
                        .padding(.horizontal, 16)
                }
            } else {
                List {
                    ForEach(groups, id: \.kind) { group in
                        Section {
                            ForEach(group.ids, id: \.self) { id in
                                if let row = box.entity(id) {
                                    Button {
                                        open(id)
                                    } label: {
                                        SearchHitRow(row: row)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparatorTint(LivTheme.border)
                                    .listRowInsets(
                                        EdgeInsets(
                                            top: 0, leading: 16, bottom: 0,
                                            trailing: 16
                                        )
                                    )
                                }
                            }
                        } header: {
                            SectionLabel(
                                group.kind.isEmpty ? "scraps" : group.kind,
                                trailing: "\(group.ids.count)"
                            )
                            .textCase(nil)
                            .padding(.horizontal, 16)
                        }
                        .listSectionSeparator(.hidden, edges: .top)
                    }
                    if offersCreate {
                        Section {
                            createButton
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(LivTheme.border)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0, leading: 16, bottom: 0,
                                        trailing: 16
                                    )
                                )
                        }
                        .listSectionSeparator(.hidden, edges: .top)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LivTheme.canvas.ignoresSafeArea())
        .onAppear {
            box.refresh()  // hits render off the entity index
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: query) { _, _ in kick(debounce: true) }
    }

    /// The one exit that carries a result: land at the desk, drop the veil.
    private func open(_ id: UInt64) {
        desk.open(id)
        desk.searchShown = false
    }

    private var createButton: some View {
        Button {
            create()
        } label: {
            SearchCreateRow(query: trimmed, stampHint: workspaces.stampHint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Find-or-create commits capture-asks-nothing: the query is the
    /// scrap's content verbatim — no type, no title.
    private func create() {
        box.capture(trimmed) { id in
            if id != 0 {
                // Search is lensed, so its create door stamps too (M4).
                workspaces.stamp(id, in: box)
                desk.open(id)
                desk.searchShown = false
            }
        }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(LivTheme.text3)
            TextField("Search the box", text: $query)
                .font(.system(size: 13))
                .foregroundStyle(LivTheme.text)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { kick(debounce: false) }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(LivTheme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Capsule().fill(LivTheme.panel2))
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
    }

    private func kick(debounce: Bool) {
        seq += 1
        let ticket = seq
        let q = trimmed
        guard !q.isEmpty else {
            rawHits = []
            return
        }
        if debounce {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                fire(ticket, q)
            }
        } else {
            fire(ticket, q)
        }
    }

    /// @State reads pierce the struct copy, so the ticket checks see the
    /// CURRENT seq, not the captured one — stale debounces and stale
    /// results both drop.
    private func fire(_ ticket: Int, _ q: String) {
        guard ticket == seq else { return }
        box.search(q) { ids in
            guard ticket == seq else { return }
            rawHits = ids
        }
    }
}

// MARK: - the find-or-create row (eval §4.3)

private struct SearchCreateRow: View {
    let query: String
    /// The active workspace's stamp, promised before the write.
    let stampHint: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                .fill(LivTheme.accentSoft)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                )
            (Text("Create \"") + Text(query).fontWeight(.semibold)
                + Text("\""))
                .font(.system(size: 13))
                .foregroundStyle(LivTheme.accent)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !stampHint.isEmpty {
                Text(stampHint)
                    .font(.system(size: 10))
                    .foregroundStyle(LivTheme.muted)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 42)
        .accessibilityLabel("Create \(query)")
    }
}

// MARK: - one hit row: title + the positioning date, nothing louder

private struct SearchHitRow: View {
    let row: EntityRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.title ?? "#\(row.id)")
                .font(.system(size: 13))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let due = row.due {
                Text(dueLabel(due))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
            }
        }
        .frame(minHeight: 42)
    }

    private func dueLabel(_ due: Int64) -> String {
        let day = Civil.day(of: due)
        if day == Civil.todayDay() {
            let t = Civil.timeString(due)
            return t.isEmpty ? "today" : t
        }
        return Civil.dayLabel(day)
    }
}
