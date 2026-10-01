import SwiftUI

// MARK: - The trash (2026-08-20; rebuilt 2026-09-29)

/// Everything you have thrown away, and the way back.
///
/// This surface exists because trash was **one-way**. `liv_trash_at` is
/// soft and the log never forgets, but the C ABI exported no restore verb
/// and the snapshot filtered trashed rows out entirely — so the only
/// recovery was the Undo chip, and only while the trash was still the very
/// last transaction. One more write and the thing was unreachable from the
/// phone forever.
///
/// REBUILT ON 2026-09-29 (owner: "who scrolls through a huge list and adds
/// back one item at a time?"). It was one card of everything, in the order
/// each thing was MADE, with a Put back pill on every row — so undoing a
/// morning's clear-out was one pill per thing, hunted for in a list sorted
/// by the wrong clock. Now it is newest THROWN AWAY first, in Today,
/// Yesterday and Earlier; a search; "Put back all" on each of those; and
/// Select for any several. Several come back as ONE write
/// (`liv_restore_many`), so one undo throws them all out again.
///
/// Nothing here deletes. There is no "empty the trash" and no permanent
/// erase, because the engine has no Delete — `Create`'s inverse is
/// `Trash`, and the log only grows. This screen restores, and that is all
/// it can honestly offer.
struct TrashView: View {
    @EnvironmentObject var box: BoxModel
    @State private var words = ""
    @FocusState private var searching: Bool
    @State private var selecting = false
    @State private var picked: Set<LivEntityID> = []
    /// Earlier is folded while there is anything newer to look at. A
    /// search looks through everything regardless.
    @State private var earlierOpen = false

    /// The core's order: the most recently thrown away first.
    private var rows: [EntityRow] {
        (box.snap?.trashed ?? []).compactMap { box.entity($0) }
    }

    private var matching: [EntityRow] {
        let q = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return rows }
        return rows.filter { livRowTitle($0).localizedCaseInsensitiveContains(q) }
    }

    /// When it went. A trashed thing's last write IS its trashing, so its
    /// `touchedMs` is the moment — as a local civil stamp.
    private static func went(_ row: EntityRow) -> Int64 {
        Civil.civil(ofInstantMs: row.touchedMs ?? 0)
    }

    private enum Bucket: CaseIterable { case today, yesterday, earlier }

    private static func bucket(_ row: EntityRow, today: Int64) -> Bucket {
        let day = Civil.day(of: went(row))
        if day >= today { return .today }
        return day == Civil.addDays(today, -1) ? .yesterday : .earlier
    }

    var body: some View {
        let today = Civil.todayDay()
        let groups = Dictionary(grouping: matching) { Self.bucket($0, today: today) }
        let folded = hasFold && !earlierOpen
        VStack(alignment: .leading, spacing: 0) {
            header
            if rows.isEmpty {
                EmptyHint("Empty")
                    .padding(.top, 40)
            } else {
                LivSearchField(text: $words, focused: $searching)
                    .padding(.horizontal, LivRow.cardInset)
                    .padding(.top, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if matching.isEmpty {
                            EmptyHint("Nothing found")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                        ForEach(Bucket.allCases, id: \.self) { b in
                            if let rows = groups[b] {
                                section(b, rows, folded: b == .earlier && folded)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        // FILL BOTH WAYS, so `canvas` paints the whole sheet. The empty
        // branch is a hint that hugs its own text — without this the
        // ground would stop under it and the sheet's default grey would
        // show below.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            if selecting && !picked.isEmpty {
                ConfirmPill("Put back \(picked.count)") { putBack(Array(picked)) }
                    .padding(.bottom, 8)
            }
        }
    }

    // NO NavigationStack, and no `Done` in a toolbar: every sheet in the
    // app draws its own header and is dismissed by its grabber (2026-09-07).
    private var header: some View {
        HStack(alignment: .center) {
            LivSheetTitle("Trash")
            Spacer(minLength: 0)
            if !rows.isEmpty {
                AddChip(
                    selecting ? "Cancel" : "Select",
                    symbol: selecting ? "xmark" : "checkmark.circle"
                ) {
                    selecting.toggle()
                    picked = []
                }
                .padding(.top, 16)
                .padding(.trailing, LivRow.cardInset + 4)
            }
        }
    }

    /// One day's worth — or Earlier's — under its name and count. "Put
    /// back all" wherever there is more than one thing to put back and it
    /// is on screen; a folded Earlier is a header that opens.
    private func section(_ b: Bucket, _ rows: [EntityRow], folded: Bool) -> some View {
        let name: String
        switch b {
        case .today: name = "Today"
        case .yesterday: name = "Yesterday"
        case .earlier: name = "Earlier"
        }
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(
                name, count: rows.count,
                fold: b == .earlier && hasFold ? !folded : nil, style: .sheet
            ) {
                if !selecting && !folded && rows.count > 1 {
                    AddChip("Put back all", symbol: "arrow.uturn.backward") {
                        putBack(rows.map(\.id))
                    }
                }
            }
            .padding(.horizontal, LivRow.cardInset)
            .contentShape(Rectangle())
            .onTapGesture {
                if b == .earlier && hasFold { earlierOpen.toggle() }
            }
            if !folded {
                LivCard {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        line(row, earlier: b == .earlier, divided: i < rows.count - 1)
                    }
                }
            }
        }
    }

    /// Earlier folds only when something newer is above it; with nothing
    /// newer it is the whole list, and a fold would hide all of it.
    private var hasFold: Bool {
        let today = Civil.todayDay()
        return words.isEmpty && matching.contains { Self.bucket($0, today: today) != .earlier }
    }

    /// The thing's mark, name, and "Note · Home · 14:02" — what it is,
    /// where it was filed, and when it went (a day, under Earlier). While
    /// selecting, the mark is the selection and the row is the button.
    private func line(_ row: EntityRow, earlier: Bool, divided: Bool) -> some View {
        let on = picked.contains(row.id)
        let at = Self.went(row)
        let when = earlier ? Civil.dayWord(Civil.day(of: at)) : Civil.timeString(at)
        let detail = [LivKind.of(row).word, livPlace(of: row) ?? "", when]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return LivCardRow(
            detail: detail, muted: livRowIsUntitled(row), divided: divided,
            lead: {
                if selecting {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: LivType.title))
                        .foregroundStyle(on ? LivTheme.accent : LivTheme.text3)
                        .frame(width: LivCards.mark)
                } else {
                    LivCardMark(glyph: LivKind.glyph(of: row))
                }
            },
            title: { Text(livRowTitle(row)) }
        ) {
            if !selecting {
                Button { putBack([row.id]) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: LivType.body, weight: .medium))
                        .foregroundStyle(LivTheme.text2)
                        .frame(width: LivRow.touch, height: LivRow.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Put back")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard selecting else { return }
            if on { picked.remove(row.id) } else { picked.insert(row.id) }
        }
    }

    /// Every way back is this one write, one thing or forty.
    private func putBack(_ ids: [LivEntityID]) {
        box.restore(ids)
        picked.subtract(ids)
        if selecting && picked.isEmpty { selecting = false }
    }
}
