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
    /// When set, search is PICKING a thing rather than going to it: a
    /// result reports itself and the screen closes, instead of landing
    /// as a tab. This is the link door (owner, 2026-08-13) — creating a
    /// link opens search, and the whole `[[id|Name]]` is written for
    /// you. One search screen, two endings; there is no second, smaller
    /// search anywhere in the app.
    var onPick: ((UInt64, String) -> Void)? = nil
    /// What was already typed at the door — the `[[kit` in the note.
    var seed: String = ""

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.dismiss) private var dismissSheet
    @State private var query = ""
    /// Raw ranked ids from the core, before the workspace lens.
    @State private var rawHits: [UInt64] = []
    /// How many matched in total. The core sends the first 200; without
    /// this a query matching 1,800 things looked like it matched 200.
    @State private var totalHits = 0
    @State private var facets: [LivFacet] = []
    /// Monotonic ticket: a stale debounce or a stale result must drop.
    @State private var seq = 0
    @FocusState private var focused: Bool

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// The lens, applied to the CORE's ranked ids — rank order is
    /// preserved, the workspace only removes. Search is filtered; the
    /// Inbox never is.
    ///
    /// TWO SETS MEETING, not a second opinion. Until 2026-08-27 this
    /// re-filtered the core's own ranked answer through a parser written in
    /// Swift, so one list was decided by two grammars that disagreed
    /// sixteen ways. Both sides are the core's now: `rawHits` is what
    /// `liv_search_at` ranked for the typed query, `lensIds` is what
    /// `liv_query_ids_at` admits for the workspace, and this is their
    /// intersection.
    private var hits: [UInt64] {
        guard let lens = workspaces.lensIds else { return rawHits }
        return rawHits.filter { lens.contains($0) }
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

    /// Grouped by KIND — the app's one classifier, so a row's group, its
    /// colour and its glyph can never disagree. This used to read
    /// `kinds.first` on its own, which put a task filed under "note" in
    /// the wrong group.
    private var groups: [(kind: LivKind, ids: [UInt64])] {
        var order: [LivKind] = []
        var byKind: [LivKind: [UInt64]] = [:]
        for id in hits {
            guard let row = box.entity(id) else { continue }
            let kind = LivKind.of(row)
            if byKind[kind] == nil { order.append(kind) }
            byKind[kind, default: []].append(id)
        }
        return order
            .sorted { SearchView.rank($0) < SearchView.rank($1) }
            .map { (kind: $0, ids: byKind[$0] ?? []) }
    }

    private static func rank(_ kind: LivKind) -> Int {
        switch kind {
        case .task: return 0
        case .event: return 1
        case .note: return 2
        case .file: return 3
        case .person: return 4
        case .link: return 5
        case .capture: return 6
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                pill
                Button {
                    close()
                } label: {
                    Text("Cancel")
                        .font(.system(size: LivType.body, weight: .medium))
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
            if !facets.isEmpty {
                facetRow
            }
            if trimmed.isEmpty {
                ScrollView {
                    EmptyHint(
                        "Search everything you have",
                        detail: "Notes, tasks, events, files and people.",
                        glyph: .everything
                    )
                    .padding(.top, 40)
                }
            } else if hits.isEmpty {
                // Zero results: the Create row IS the empty state, at the
                // top of the scroll area so the keyboard never hides it.
                ScrollView {
                    createButton
                        .padding(.horizontal, 16)
                }
            } else {
                if totalHits > rawHits.count {
                    Text("Showing \(rawHits.count) of \(totalHits) — narrow the search")
                        .font(.system(size: LivType.body).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
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
                                group.kind == .capture ? "captures" : group.kind.wire,
                                trailing: "\(group.ids.count)",
                                dot: group.kind.color
                            )
                            .textCase(nil)
                            .padding(.horizontal, 16)
                            // The heading brings its own room now, so
                            // the List must not add a second helping on
                            // top of it — the same zeroing Tasks does
                            // for its group headers.
                            .listRowInsets(
                                EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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
            if query.isEmpty, !seed.isEmpty {
                query = seed
                kick(debounce: false)
            }
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: query) { _, _ in kick(debounce: true) }
    }

    /// The one exit that carries a result. Picking REPORTS it; searching
    /// lands at the desk. Both then drop the veil.
    private func open(_ id: UInt64) {
        if let onPick {
            onPick(id, box.entity(id).map(livRowTitle) ?? "")
            close()
            return
        }
        desk.open(id)
        close()
    }

    private func close() {
        if onPick != nil {
            dismissSheet()
        } else {
            desk.searchShown = false
        }
    }

    private var createButton: some View {
        Button {
            create()
        } label: {
            SearchCreateRow(query: trimmed)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Find-or-create commits capture-asks-nothing: the query is the
    /// scrap's content verbatim — no type, no title.
    ///
    /// Linking to something that does not exist yet is the same verb: the
    /// scrap is born and the link points at it. The NAME comes from what
    /// was typed, not from a lookup — the entity is not in the snapshot
    /// yet at this instant, and the query IS what its title will be.
    private func create() {
        let typed = trimmed
        box.capture(typed) { id in
            guard id != 0 else { return }
            // Search is lensed, so its create door stamps too (M4).
            workspaces.stamp(id, in: box)
            if let onPick {
                onPick(id, typed)
            } else {
                desk.open(id)
            }
            close()
        }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text3)
            TextField("Search", text: $query)
                .font(.system(size: LivType.body))
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
                        .font(.system(size: LivType.body))
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

    /// NARROW BY WHAT IS THERE, not by what you can spell.
    ///
    /// The core counts, for every value of every select property, how many
    /// results picking it would leave — and whether the query already
    /// includes or excludes it. It has sent that on every search since the
    /// facet code was written; nothing drew it. This is that row.
    ///
    /// One line per property, scrolling sideways, count-descending as the
    /// core sorted them. A chip is lit when the query includes its value and
    /// struck through when it excludes it, and the CORE decides which — so a
    /// query typed by hand lights the same chips as one built by tapping.
    private var facetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(facets) { facet in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(facet.label)
                            .font(.system(size: LivType.micro, weight: .medium))
                            .foregroundStyle(LivTheme.text3)
                            .textCase(.uppercase)
                            .kerning(0.6)
                        HStack(spacing: 6) {
                            ForEach(facet.values) { value in
                                chip(facet.label, value)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 52)
        .padding(.bottom, 6)
    }

    private func chip(_ key: String, _ v: LivFacetValue) -> some View {
        Button {
            cycle(key, v)
        } label: {
            HStack(spacing: 5) {
                Text(v.label)
                    .strikethrough(v.excluded, color: LivTheme.red)
                Text("\(v.count)")
                    .font(.system(size: LivType.micro, weight: .medium).monospacedDigit())
                    .foregroundStyle(v.active ? LivTheme.onAccent.opacity(0.7) : LivTheme.text3)
            }
            .font(.system(size: LivType.label, weight: v.active ? .semibold : .regular))
            .foregroundStyle(
                v.excluded ? LivTheme.red : (v.active ? LivTheme.onAccent : LivTheme.text))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                Capsule().fill(v.active ? LivTheme.accent : LivTheme.panel2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(key) \(v.label), \(v.count)"
                + (v.active ? ", included" : v.excluded ? ", excluded" : ""))
    }

    /// include -> exclude -> off, the cycle the core documents (bp3 a19).
    ///
    /// This does NOT parse the query. One grammar, one parser, and the
    /// parser is in Rust (`services::search::parse`); a second one here
    /// would be the defect standing rule 4 names. All this does is remove
    /// the exact spellings THIS function produces and append the next
    /// state's. A term the user typed in some other equivalent spelling is
    /// left alone — and the chip still draws correctly, because `active`
    /// and `excluded` come from the core, not from reading the text back.
    private func cycle(_ key: String, _ v: LivFacetValue) {
        let include = LivTerms.term(key, v.label)
        let exclude = LivTerms.term(key, v.label, exclude: true)
        var q = query
        for spelling in [exclude, include] {
            q = q.replacingOccurrences(of: spelling, with: " ")
        }
        q = q.split(separator: " ").joined(separator: " ")
        let next = v.active ? exclude : (v.excluded ? "" : include)
        query = next.isEmpty ? q : (q.isEmpty ? next : q + " " + next)
        kick(debounce: false)
    }

    private func kick(debounce: Bool) {
        seq += 1
        let ticket = seq
        let q = trimmed
        guard !q.isEmpty else {
            rawHits = []
            facets = []
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
        box.search(q) { ids, total, found in
            guard ticket == seq else { return }
            rawHits = ids
            totalHits = total
            facets = found
        }
    }
}

// MARK: - the find-or-create row (eval §4.3)

private struct SearchCreateRow: View {
    let query: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                .fill(LivTheme.accentSoft)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: LivType.label, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                )
            (Text("Create \"") + Text(query).fontWeight(.semibold)
                + Text("\""))
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.accent)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 42)
        .accessibilityLabel("Create \(query)")
    }
}

// MARK: - one hit row: title + the positioning date, nothing louder

private struct SearchHitRow: View {
    let row: EntityRow

    var body: some View {
        HStack(spacing: 9) {
            // What the hit IS, before what it says.
            IconChip(glyph: LivKind.glyph(of: row), color: LivKind.color(of: row), size: 24)
            Text(livRowTitle(row))
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let due = row.due {
                Text(dueLabel(due))
                    .font(.system(size: LivType.caption).monospacedDigit())
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
