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
    @Environment(\.dismiss) private var dismiss

    private var rows: [EntityRow] {
        (box.snap?.trashed ?? []).compactMap { box.entity($0) }
    }

    var body: some View {
        NavigationStack {
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
                        .padding(.horizontal, 18)
                    }
                }
            }
            .background(LivTheme.canvas)
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
