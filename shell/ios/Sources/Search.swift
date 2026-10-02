// liv iOS — Search (design/ios.md §6): the global full-screen overlay the
// chrome presents while desk.searchShown. A pill bar over
// liv_view_search — the DSL parses in Rust, never here; the shell sends the
// raw query and the workspace lens (150ms debounce) and gets back the hit
// rows in rank order, already inside the lens, with whether one is named
// exactly like the words. It draws them grouped by the kind each row's
// glyph shows — task → event → note → file, then the rest, untyped scraps
// last — keeping rank order inside each group. A result
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
    var onPick: ((LivEntityID, String) -> Void)? = nil
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
    /// WHAT THE PICKERS CHOSE, in tap order. Lit in their facet rows.
    @State private var terms: [SearchTerm] = []
    /// The facet menu. Search is a `fullScreenCover`, and the desk's menu
    /// host lives under it at the root — so this surface hosts its own.
    @State private var menu: LivMenu?
    /// The chip a hold just opened the menu for. The hold is simultaneous,
    /// so the tap still fires when the finger lifts — and on a picked chip
    /// that tap undid the pick the menu was opened about (2026-10-01).
    @State private var held: String?
    /// The hits Rust ranked, inside the workspace lens, first 200.
    @State private var hits: [EntityRow] = []
    /// How many the lens admits in all. Rust sends the first 200; without
    /// this a query matching 1,800 things looked like it matched 200.
    @State private var totalHits = 0
    /// A hit is named exactly like the typed words, so there is nothing
    /// to offer to create.
    @State private var exact = false
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

    /// Find-or-create offers only when no hit is titled exactly like the
    /// words (Rust's `exact`, any case).
    private var offersCreate: Bool {
        !trimmed.isEmpty && !exact
    }

    /// Grouped by the kind each row's GLYPH shows — `LivKind`, the app's
    /// one classifier for how a thing looks — so a row's group, its colour
    /// and its glyph can never disagree. Rank order survives inside each
    /// group.
    private var groups: [(kind: LivKind, rows: [EntityRow])] {
        var order: [LivKind] = []
        var byKind: [LivKind: [EntityRow]] = [:]
        for row in hits {
            let kind = LivKind.of(row)
            if byKind[kind] == nil { order.append(kind) }
            byKind[kind, default: []].append(row)
        }
        return order
            .sorted { SearchView.rank($0) < SearchView.rank($1) }
            .map { (kind: $0, rows: byKind[$0] ?? []) }
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

    /// THE FIELD IS AT THE THUMB (owner, 2026-09-13, with a screen
    /// recording: *"Search should be more similar to the video"*).
    ///
    /// It was at the top with the word "Cancel" beside it — the shape
    /// every search screen had in 2010, and a reach on a 2,532px phone.
    /// The reference puts the field at the BOTTOM, directly above the
    /// keyboard, as a plain pill with a round ✕ beside it, and lets the
    /// results fill everything above.
    ///
    /// That is also this app's own argument, made twice already: the tab
    /// switcher was moved because it "used to start 700pt away at the top
    /// of the screen", and the bar has always been at the foot. Search
    /// was the last surface reaching upward.
    ///
    /// WHAT MOVES WITH IT. The lens chip, the constraint line and the
    /// facet row sit with the field now rather than under the old header.
    /// They are what you TAP to narrow, so they belong in the same reach
    /// as the field — and a facet row halfway up the screen while your
    /// thumb is on the keyboard was the same reach problem one layer
    /// down.
    var body: some View {
        VStack(spacing: 0) {
            // NOTHING TYPED AND NOTHING PICKED. A chip on its own is a
            // question too — "everything in Work", left when the words
            // that found it are cleared — and until 2026-09-29 it answered
            // with a blank page, because this asked only about words.
            if trimmed.isEmpty && terms.isEmpty {
                // CENTRED, the way the reference centres its own — not
                // pinned 40pt under a header that is no longer there.
                //
                // NO GLYPH, deliberately, though the reference draws one.
                // `EmptyHint` lost its glyph and its sentence in rev 66 on
                // the owner's word about verbose empty states, and the
                // TYPE lost them so they could not come back one surface
                // at a time (standing rule 3). Adding one here would
                // reverse that on a screenshot rather than on his word.
                // AND NO SENTENCE (owner, 2026-09-29: "the interface should
                // explain itself") — a focused field over nothing is the
                // whole invitation.
                Spacer(minLength: 0)
            } else if hits.isEmpty {
                // Zero results: the Create row IS the empty state, at the
                // head of the results area — which is now the TOP of the
                // screen rather than just under a header, since the field
                // moved to the foot.
                // A chip alone has no words to make a thing from.
                ScrollView {
                    if !trimmed.isEmpty {
                        createButton
                            .padding(.horizontal, 16)
                    }
                }
            } else {
                if totalHits > hits.count {
                    Text("Showing \(hits.count) of \(totalHits)")
                        .font(.system(size: LivType.body).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
                List {
                    ForEach(groups, id: \.kind) { group in
                        Section {
                            ForEach(group.rows) { row in
                                Button {
                                    open(row)
                                } label: {
                                    SearchHitRow(row: row)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(LivTheme.rule)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0, leading: 16, bottom: 0,
                                        trailing: 16
                                    )
                                )
                            }
                        } header: {
                            // NO KIND DOT. The heading names the kind
                            // in words and every row under it already
                            // carries that kind's glyph, so the circle
                            // was the third telling (polish pass,
                            // 2026-08-30).
                            SectionLabel(
                                group.kind == .capture ? "captures" : group.kind.wire,
                                count: group.rows.count
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
                                .listRowSeparatorTint(LivTheme.rule)
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
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LivTheme.canvas.ignoresSafeArea())
        .onAppear {
            if words.isEmpty, !seed.isEmpty {
                words = seed
                kick(debounce: false)
            }
            // AFTER THE SLIDE, as the properties card does: asked for
            // mid-slide, the keyboard could come up over the field. The
            // `[[` link sheet is the exception — the keyboard is already up
            // and the letters after `[[` are on their way; for half a
            // second they had nowhere to go (review, 2026-10-02).
            if onPick != nil {
                focused = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.coverSeconds) {
                    focused = true
                }
            }
        }
        .onChange(of: words) { _, _ in kick(debounce: true) }
        .onChange(of: workspaces.lensIds) { _, _ in kick(debounce: false) }
        // Where the lift fired no tap, the hold is forgotten with its menu.
        .onChange(of: menu == nil) { _, closed in
            if closed { held = nil }
        }
        .livMenu($menu)
    }

    /// The one exit that carries a result. Picking REPORTS it; searching
    /// lands at the desk. Both then drop the veil.
    private func open(_ row: EntityRow) {
        if let onPick {
            onPick(row.id, livRowTitle(row))
            close()
            return
        }
        desk.open(row.id)
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
            guard !id.isAbsent else { return }
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

    /// THE FOOT: what narrows the search, and the field itself, in the
    /// order you reach them. The chips sit ABOVE the field so the field
    /// stays welded to the top of the keyboard and nothing moves under
    /// your thumb as facets arrive and leave.
    @ViewBuilder private var footer: some View {
        VStack(spacing: 0) {
            if workspaces.lensOn {
                HStack {
                    LensChip(label: workspaces.lensLabel)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            // WHAT YOU CHOSE is lit in its own row, and Rust keeps a
            // picked chip even when nothing is left to count — so the row
            // is also the way back (2026-10-01; a second line repeating
            // every pick above the rows went).
            if !facets.isEmpty {
                facetRow
            }
            HStack(spacing: 10) {
                pill
                // A ROUND ✕, not the word "Cancel" (the reference's, and
                // the reason is the same one that took the words off the
                // bar in rev 68): a glyph everyone already reads, at a
                // size a thumb can hit, instead of a word spelling out
                // what the shape already says.
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.text)
                        .frame(width: LivRow.touch, height: LivRow.touch)
                        .background(Circle().fill(LivTheme.panel2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    private var pill: some View {
        LivSearchField(text: $words, focused: $focused) { kick(debounce: false) }
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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(facets) { facet in
                HStack(alignment: .center, spacing: LivFacets.gap) {
                    // THE PROPERTY'S NAME, ON SCREEN, at the margin — so
                    // the screen says what you can narrow by (owner,
                    // 2026-09-06: "it isn't obvious how").
                    Text(facet.label.capitalized)
                        .font(.system(size: LivType.body, weight: .medium))
                        .foregroundStyle(LivTheme.text2)
                        .frame(width: LivFacets.name, alignment: .leading)
                        .lineLimit(1)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: LivFacets.gap) {
                                ForEach(facet.values) { value in
                                    chip(facet.label, value)
                                }
                            }
                            .padding(.trailing, 16)
                        }
                        // A PICK STAYS IN SIGHT. Picking in another row
                        // re-counts this one, and a lit chip can be
                        // re-ordered off the edge; with no second line
                        // repeating the picks, the row brings it back —
                        // by the least it can, so a chip already in view
                        // never moves.
                        .onAppear { reveal(facet, proxy) }
                        .onChange(of: facet.values.map { "\($0.id)\($0.active)\($0.excluded)" }) {
                            _, _ in reveal(facet, proxy)
                        }
                    }
                }
                .frame(height: LivFacets.row)
            }
        }
        .padding(.leading, 16)
        .padding(.bottom, 2)
    }

    private func reveal(_ facet: LivFacet, _ proxy: ScrollViewProxy) {
        if let lit = facet.values.first(where: { $0.active || $0.excluded }) {
            proxy.scrollTo(lit.id)
        }
    }

    private func chip(_ key: String, _ v: LivFacetValue) -> some View {
        let lit = v.active || v.excluded
        let id = SearchTerm(property: key, value: v.label, exclude: v.excluded).id
        return Button {
            if held == id {
                held = nil
            } else {
                toggle(key, v)
            }
        } label: {
            HStack(spacing: 6) {
                // "not note", not a red strikethrough: hiding notes from a
                // search is not a warning, and a struck word reads as DONE.
                if v.excluded {
                    Text("not").foregroundStyle(LivTheme.text3)
                }
                Text(v.label)
                Text("\(v.count)")
                    .font(.system(size: LivType.label).monospacedDigit())
                    .foregroundStyle(lit ? LivTheme.text2 : LivTheme.text3)
            }
            .font(.system(size: LivType.body, weight: lit ? .semibold : .regular))
            .foregroundStyle(LivTheme.text)
            .lineLimit(1)
            .padding(.horizontal, LivFacets.pad)
            .frame(height: LivFacets.chip)
            // HOLLOW UNTIL PICKED, then the plate a chosen segment wears
            // (`LivSegment`) — one mark for "chosen" across the app.
            .background(Capsule().fill(lit ? LivTheme.thumb : .clear))
            .overlay(
                Capsule().strokeBorder(
                    lit ? .clear : LivTheme.border2, lineWidth: LivChip.addOutline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .livDoor()
        // HOLD A CHIP for the verbs — Only, Hide, Any. The same
        // simultaneous gesture the bar's `+` uses (Bar.swift).
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                held = id
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

    /// ONE TAP PICKS, and tapping a lit chip — picked or hidden — puts it
    /// back. Hiding is a named verb in the menu a held chip opens (owner,
    /// 2026-09-06: "'-type:foo' to exclude is not good on a phone"), so a
    /// tap only ever means one thing.
    private func toggle(_ key: String, _ v: LivFacetValue) {
        if v.active || v.excluded {
            drop(SearchTerm(property: key, value: v.label, exclude: v.excluded))
        } else {
            set(SearchTerm(property: key, value: v.label, exclude: false))
        }
    }

    /// THE THREE VERBS, in words. Reached by holding a chip.
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
            hits = []
            facets = []
            exact = false
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
        box.search(q, lens: workspaces.lensIds) { found, total, facets, exact in
            guard ticket == seq else { return }
            hits = found
            totalHits = total
            self.facets = facets
            self.exact = exact
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
            // PLAIN INK, NOT ACCENT. The row shape is the button — a
            // full-width 52pt row with a `+` in front of it, which is
            // exactly the library panel's "New filter" door. The accent
            // was the only thing making it read as a hyperlink instead
            // (owner, 2026-09-15), and it was the last of the nine.
            Image(systemName: "plus")
                .font(.system(size: LivType.body, weight: .medium))
                .foregroundStyle(LivTheme.text2)
                .frame(width: 24, height: 24)
            (Text("Create \"") + Text(query).fontWeight(.semibold)
                + Text("\""))
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
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
            // What the hit IS, before what it says — in ink (the clearer
            // boards: kind colour lives only on Today's bars and the
            // calendar's blocks).
            LivIcon(glyph: LivKind.glyph(of: row), color: LivTheme.text2, size: 22)
            Text(livRowTitle(row))
                .font(.system(size: LivType.strong))
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
