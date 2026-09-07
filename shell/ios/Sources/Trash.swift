import SwiftUI

// MARK: - The trash (2026-08-20)

/// Everything you have thrown away, and the way back.
///
/// This surface exists because trash was **one-way**. `liv_trash_at` is
/// soft and the log never forgets, but the C ABI exported no restore verb
/// and the snapshot filtered trashed rows out entirely — so the only
/// recovery was the Undo chip, and only while the trash was still the very
/// last transaction. One more write and the thing was unreachable from the
/// phone forever.
///
/// Nothing here deletes. There is no "empty the trash" and no permanent
/// erase, because the core has no Delete command — `Create`'s inverse is
/// `Trash`, and the log only grows. That is a real limitation, written
/// down rather than papered over: this screen restores, and that is all it
/// can honestly offer.
struct TrashView: View {
    @EnvironmentObject var box: BoxModel

    private var rows: [EntityRow] {
        (box.snap?.trashed ?? []).compactMap { box.entity($0) }
    }

    var body: some View {
        // NO NavigationStack, and no `Done` in a toolbar. This was the
        // one screen in the app still wearing system navigation
        // furniture: a nav bar with the platform's own chrome material,
        // title font and hairline, and a confirmation-action button
        // that — with no tint anywhere in the subtree — came out in iOS
        // system blue. Every other sheet in the app draws its own header
        // and is dismissed by its grabber; this one now does the same
        // (2026-09-07).
        VStack(alignment: .leading, spacing: 4) {
            // ABOVE the Group, not inside the ScrollView: the empty
            // branch is not in a ScrollView, so a header placed there
            // would leave an empty trash with no name on it.
            Text("Trash")
                .font(.system(size: LivType.title, weight: .bold))
                .foregroundStyle(LivTheme.text)
                .padding(.horizontal, LivRow.cardInset + 4)
                .padding(.top, 16)
            Group {
                if rows.isEmpty {
                    EmptyHint(
                        "Nothing in the trash",
                        detail: "Deleted things wait here until you put them back.",
                        glyph: .trash
                    )
                    .padding(.top, 40)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                HStack(spacing: 0) {
                                    LivListRow(
                                        glyph: LivKind.glyph(of: row),
                                        title: livRowTitle(row),
                                        untitled: livRowIsUntitled(row),
                                        divided: i < rows.count - 1)
                                    Button {
                                        box.restore(row.id)
                                    } label: {
                                        Text("Put back")
                                            .font(.system(size: LivType.body, weight: .medium))
                                            .foregroundStyle(LivTheme.accent)
                                            .padding(.horizontal, 12)
                                            .frame(height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, LivRow.margin)
                    }
                }
            }
        }
        // FILL BOTH WAYS, so `canvas` paints the whole sheet. The empty
        // branch is a hint that hugs its own text — without this the
        // ground would stop under it and the sheet's default grey would
        // show below.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
    }
}
