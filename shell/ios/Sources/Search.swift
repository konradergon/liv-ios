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
    /// ONE CONSTRAINT A PICKER MADE. Never derived from the text — the
    /// core is the only parser (standing rule 4), and this is only ever
    /// SPELLED, by `LivTerms.term`, at the instant it crosses the seam.
    struct SearchTerm: Equatable, Identifiable {
        /// The facet label the core sent: "type", "area".
        let property: String
        /// The value label: "note".
        let value: String
        var exclude: Bool
        var id: String { "\(property)=\(value)" }
    }

    /// WHAT THE PERSON TYPED, and nothing else. Until 2026-09-07 this was
    /// one `query` that the facet chips wrote INTO, so tapping "note" put
    /// `type:note` in the search field and tapping it again put
    /// `-type:note` — the storage format on screen, which is exactly what
    /// standing rule 5 forbids (owner: "clunky things like 'type:foo'
    /// appearing in search bar").
    @State private var words = ""
    /// WHAT THE PICKERS CHOSE, in tap order. Drawn as chips under the
    /// field, where you can see and undo them.
    @State private var terms: [SearchTerm] = []
    /// The facet menu. Search is a `fullScreenCover`, and the desk's menu
    /// host lives under it at the root — so this surface hosts its own.
    @State private var menu: LivMenu?
    /// Raw ranked ids from the core, before the workspace lens.
    @State private var rawHits: [UInt64] = []
    /// How many matched in total. The core sends the first 200; without
    /// this a query matching 1,800 things looked like it matched 200.
    @State private var totalHits = 0
    @State private var facets: [LivFacet] = []
    /// Monotonic ticket: a stale debounce or a stale result must drop.
    @State private var seq = 0
    @FocusState private var focused: Bool

    /// THE QUERY THE CORE GETS — words plus the constraints, spelled by
    /// the one speller. This string is composed at the seam and nowhere
    /// else; it is never shown, and never written back into the field.
    private var raw: String {
        ([words.trimmingCharacters(in: .whitespacesAndNewlines)]
            + terms.map { LivTerms.term($0.property, $0.value, exclude: $0.exclude) })
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// THE WORDS, trimmed. `create()` and the find-or-create offer use
    /// this, and until the split they used the whole query — so with a
    /// chip lit, "Create" made a scrap whose content was `a type:note`.
    /// Splitting the state fixed that on the way past.
    private var trimmed: String {
        words.trimmingCharacters(in: .whitespaces)
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
            // WHAT YOU CHOSE, always on screen — the way back when a
            // constraint has narrowed the list to nothing and the core
            // sends no facets to un-tap.
            constraintLine
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
                            // NO KIND DOT. The heading names the kind
                            // in words and every row under it already
                            // carries that kind's glyph, so the circle
                            // was the third telling (polish pass,
                            // 2026-08-30).
                            SectionLabel(
                                group.kind == .capture ? "captures" : group.kind.wire,
                                trailing: "\(group.ids.count)"
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
            if words.isEmpty, !seed.isEmpty {
                words = seed
                kick(debounce: false)
            }
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: words) { _, _ in kick(debounce: true) }
        .livMenu($menu)
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
            TextField("Search", text: $words)
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { kick(debounce: false) }
            if !words.isEmpty {
                Button {
                    words = ""
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
        VStack(alignment: .leading, spacing: 2) {
            ForEach(facets) { facet in
                HStack(alignment: .center, spacing: 10) {
                    // THE PROPERTY'S NAME, ON SCREEN. It was 12pt
                    // uppercase kerned `text3` — the label style the
                    // polish pass removed everywhere else, under the 14
                    // floor — and every property but the first sat off
                    // the right edge of one long scroller. So the screen
                    // never said what you could narrow by (owner,
                    // 2026-09-06: "it isn't obvious how").
                    //
                    // One row per property, the name first at the margin
                    // in the app's own heading recipe, values scrolling
                    // sideways within their row.
                    Text(facet.label.capitalized)
                        .font(.system(size: LivType.label, weight: .medium))
                        .foregroundStyle(LivTheme.text2)
                        .frame(width: 74, alignment: .leading)
                        .lineLimit(1)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(facet.values) { value in
                                chip(facet.label, value)
                            }
                        }
                        .padding(.trailing, 16)
                    }
                }
                .frame(height: 38)
            }
        }
        .padding(.leading, 16)
        .padding(.bottom, 4)
    }

    /// WHAT YOU CHOSE, under the field, where you can see it and undo it.
    ///
    /// This is the line the old design had nowhere to put, so it put it
    /// in the search field as grammar. A constraint is a chip: tap it for
    /// the verbs, tap its ✕ to drop it.
    @ViewBuilder private var constraintLine: some View {
        if !terms.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(terms) { term in
                        Button {
                            menu = termMenu(term)
                        } label: {
                            HStack(spacing: 5) {
                                if term.exclude {
                                    Text("not")
                                        .foregroundStyle(LivTheme.text3)
                                }
                                Text(term.value)
                                    .foregroundStyle(LivTheme.text)
                                Button {
                                    drop(term)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: LivChip.glyph, weight: .semibold))
                                        .foregroundStyle(LivTheme.text3)
                                        .frame(width: 22, height: LivChip.tall)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(term.value)")
                            }
                            .font(.system(size: LivType.label, weight: .medium))
                            .padding(.leading, 11)
                            .padding(.trailing, 2)
                            .frame(height: LivChip.tall)
                            .livGlass(in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(term.property) \(term.value), "
                                + (term.exclude ? "hidden" : "only") + ". Change")
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: LivChip.tall + 8)
            .animation(LivMotion.pick, value: terms)
        }
    }

    private func chip(_ key: String, _ v: LivFacetValue) -> some View {
        Button {
            cycle(key, v)
        } label: {
            HStack(spacing: 5) {
                // "not note", not a red strikethrough. Red is the
                // palette's one warning word and hiding notes from a
                // search is not a warning; a struck word reads as DONE
                // in a list app besides. The word says which state it is
                // in, and both chosen states share ink and weight.
                if v.excluded {
                    Text("not").foregroundStyle(LivTheme.text3)
                }
                Text(v.label)
                Text("\(v.count)")
                    .font(.system(size: LivType.caption).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
            }
            // CHOSEN IS INK AND WEIGHT, not a saturated capsule. The
            // same mark the Tasks filter row, the Inbox lens and the day
            // strip use — this was the last chip in the app still
            // filling itself with the accent and inverting its text
            // (polish pass, 2026-08-31).
            .font(
                .system(
                    size: LivType.label,
                    weight: (v.active || v.excluded) ? .medium : .regular))
            .foregroundStyle((v.active || v.excluded) ? LivTheme.text : LivTheme.text2)
            .padding(.horizontal, 11)
            .frame(height: LivChip.tall)
            .background(
                Capsule().fill((v.active || v.excluded) ? LivTheme.panel2 : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // THE SECOND DOOR to the verbs, for someone who already knows:
        // hold a chip to hide its value without including it first. The
        // same simultaneous gesture the bar's `+` uses, so the tap still
        // fires (Bar.swift).
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                menu = termMenu(
                    SearchTerm(property: key, value: v.label, exclude: v.excluded))
            })
        .accessibilityAction(named: "More") {
            menu = termMenu(
                SearchTerm(property: key, value: v.label, exclude: v.excluded))
        }
        .accessibilityLabel(
            "\(key) \(v.label), \(v.count)"
                + (v.active ? ", included" : v.excluded ? ", excluded" : ""))
    }

    /// ONE TAP INCLUDES, and tapping the same chip again drops it.
    ///
    /// The old gesture was a CYCLE — include, then exclude, then off —
    /// which cannot be labelled before you tap it, and whose second tap
    /// flipped the results to the opposite of the first (owner,
    /// 2026-09-06: "'-type:foo' to exclude is not good on a phone and
    /// isn't obvious"). Excluding is a named verb in a menu now, so a
    /// tap only ever means one thing.
    private func cycle(_ key: String, _ v: LivFacetValue) {
        if v.active {
            drop(SearchTerm(property: key, value: v.label, exclude: false))
        } else {
            set(SearchTerm(property: key, value: v.label, exclude: false))
        }
    }

    /// THE THREE VERBS, in words, on a chip you can see. Reached by
    /// tapping the constraint chip under the field, or by holding a chip
    /// in the band.
    private func termMenu(_ term: SearchTerm) -> LivMenu {
        let live = terms.first { $0.id == term.id }
        return LivMenu(
            id: "facet-\(term.id)",
            from: .bottom,
            subject: term.value,
            subjectDetail: term.property.capitalized,
            items: [
                LivMenuItem(
                    label: "Only \(term.value)",
                    selected: live?.exclude == false
                ) { set(SearchTerm(property: term.property, value: term.value, exclude: false)) },
                LivMenuItem(
                    label: "Hide \(term.value)",
                    selected: live?.exclude == true
                ) { set(SearchTerm(property: term.property, value: term.value, exclude: true)) },
                LivMenuItem(label: "Any \(term.property)") {
                    clear(property: term.property)
                },
            ])
    }

    /// Put a constraint in, replacing whatever that PROPERTY said — one
    /// value per property is what a picker means, and it makes tapping a
    /// sibling a pivot rather than an accumulation.
    private func set(_ term: SearchTerm) {
        terms.removeAll { $0.property == term.property }
        terms.append(term)
        kick(debounce: false)
    }

    private func drop(_ term: SearchTerm) {
        terms.removeAll { $0.id == term.id }
        kick(debounce: false)
    }

    /// "Any type" — the constraint goes, and so does a hand-typed term
    /// for the same property, in the two canonical spellings this file
    /// produces. Anything spelled otherwise is the person's own text and
    /// is left exactly as they wrote it.
    private func clear(property: String) {
        terms.removeAll { $0.property == property }
        for value in facets.first(where: { $0.label == property })?.values ?? [] {
            for spelling in [
                LivTerms.term(property, value.label, exclude: true),
                LivTerms.term(property, value.label),
            ] {
                words = words.replacingOccurrences(of: spelling, with: " ")
            }
        }
        words = words.split(separator: " ").joined(separator: " ")
        kick(debounce: false)
    }

    private func kick(debounce: Bool) {
        seq += 1
        let ticket = seq
        let q = raw
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
            // NO PLATE. A tinted tile behind a `+` that sits directly
            // beside the word "Create" is a box drawn for its own sake:
            // the row is already a row, and the words already say what
            // the button does.
            Image(systemName: "plus")
                .font(.system(size: LivType.body, weight: .medium))
                .foregroundStyle(LivTheme.accent)
                .frame(width: 24, height: 24)
            (Text("Create \"") + Text(query).fontWeight(.semibold)
                + Text("\""))
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.accent)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: LivRow.height)
        .accessibilityLabel("Create \(query)")
    }
}

// MARK: - one hit row: title + the positioning date, nothing louder

private struct SearchHitRow: View {
    let row: EntityRow

    var body: some View {
        HStack(spacing: 9) {
            // What the hit IS, before what it says.
            LivIcon(glyph: LivKind.glyph(of: row), color: LivKind.color(of: row), size: 22)
            Text(livRowTitle(row))
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let due = row.due {
                // The app's one second-voice recipe. This was a fifth
                // hand-rolled copy of it, and it stayed at caption when
                // the other four moved (2026-09-05).
                LivRowFact(text: dueLabel(due))
            }
        }
        .frame(minHeight: LivRow.height)
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
