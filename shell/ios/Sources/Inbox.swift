// liv iOS — Inbox (design/ios.md §6). ONE inbox, two lenses, never two
// cleanup surfaces. M1 ships the ROUTE lens only: untyped orphan scraps
// (content ∧ ¬type — the macOS orphans() set), newest first. A type verb
// converts in place; the routed row leaves the list on the act's refresh.
// Tapping a row opens it as a Desk tab — the one gesture grammar. Tidy
// (clerk proposals, amber) arrives with assist — the control shows it
// disabled, never hidden. No screen title: the lens bar IS the header
// (SectionLabel scale; the bottom bar already names the feature).

import SwiftUI

struct InboxView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel

    /// (kinds empty) ∧ (contentPrint set) ∧ ¬trashed over the `everything`
    /// projection — the id lists exclude backstage plumbing; entities[] alone
    /// does not.
    ///
    /// THE WORKSPACE LENS IS NOT APPLIED HERE, EVER (design/ios.md M4). An
    /// unfiled thing must be reachable from every workspace, or a capture
    /// made under the wrong lens appears to vanish — the classic bug that
    /// hits every workspace system. This is a stated safety rule, not an
    /// oversight; do not "fix" it.
    private var scraps: [EntityRow] {
        (box.snap?.everything ?? [])
            .compactMap { box.entity($0) }
            .filter {
                ($0.kinds ?? []).isEmpty && ($0.contentPrint ?? 0) != 0
                    && !($0.trashed ?? false)
            }
            .sorted {
                let a = $0.created ?? 0
                let b = $1.created ?? 0
                return a == b ? $0.id > $1.id : a > b
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            lensBar
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
            if scraps.isEmpty {
                ScrollView {
                    EmptyHint("Inbox zero — captures wait here until routed.")
                        .padding(.top, 32)
                    tidyFootnote
                }
            } else {
                HStack {
                    Text("\(scraps.count) unrouted — newest first")
                        .font(.system(size: 11))
                        .foregroundStyle(LivTheme.text3)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                List {
                    ForEach(scraps) { row in
                        InboxScrapRow(row: row)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(LivTheme.border)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0, leading: 16, bottom: 0, trailing: 16
                                )
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    box.trash(row.id)  // soft, undoable
                                } label: {
                                    Label("Trash", systemImage: "trash")
                                }
                                .tint(LivTheme.red)
                            }
                    }
                    tidyFootnote
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 16, for: .scrollContent)  // full screen: no bar under it
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LivTheme.canvas)
        .onAppear { box.refresh() }
    }

    /// Route active; Tidy visibly present but inert until assist lands.
    /// While a workspace lens is on elsewhere, say plainly that it is NOT
    /// on here — the user should never wonder where a capture went.
    private var lensBar: some View {
        HStack(spacing: 4) {
            lensSegment("Route", active: true)
            lensSegment("Tidy", active: false)
                .opacity(0.45)
                .accessibilityLabel("Tidy — arrives with assist")
            Spacer()
            if workspaces.lensOn {
                Text("shows every workspace")
                    .font(.system(size: 10))
                    .foregroundStyle(LivTheme.muted)
            }
        }
    }

    private func lensSegment(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(active ? LivTheme.accent : LivTheme.text3)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(Capsule().fill(active ? LivTheme.accentSoft : Color.clear))
    }

    private var tidyFootnote: some View {
        EmptyHint("Proposals arrive with assist — later.")
    }
}

// MARK: - one scrap row: derived title + stamp over the four type verbs

private struct InboxScrapRow: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    let row: EntityRow

    /// A real name cell means the title is the user's; absent, the wire's
    /// title is the derived summary — mark it ✦ (shown, never written).
    private var named: Bool {
        (row.cells ?? []).contains {
            $0.property == "name" && !($0.value ?? "").isEmpty
        }
    }

    private var stamp: String {
        guard let created = row.created, created > 0 else { return "" }
        let day = Civil.day(of: created)
        if day == Civil.todayDay() {
            let t = Civil.timeString(created)
            return t.isEmpty ? "today" : t
        }
        return Civil.dayLabel(day)
    }

    private var titleText: Text {
        let t = row.title ?? "#\(row.id)"
        guard !named else { return Text(t).foregroundStyle(LivTheme.text) }
        return Text("✦ ").foregroundStyle(LivTheme.text3)
            + Text(t).foregroundStyle(LivTheme.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(stamp)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
            }
            HStack(spacing: 6) {
                verb("Task", "checkmark.circle", "task")
                verb("Note", "doc.text", "note")
                verb("Event", "calendar", "event")
                verb("Link", "link", "link")
                Spacer()
            }
        }
        .padding(.vertical, 8)
        // Row tap = open as a Desk tab; the verb buttons hit-test apart
        // (.borderless children win over the container gesture).
        .contentShape(Rectangle())
        .onTapGesture { desk.open(row.id) }
    }

    /// Neutral capsule verbs — the act refreshes, the routed row departs.
    /// .borderless: multiple buttons in one List row must hit-test apart.
    private func verb(_ label: String, _ icon: String, _ type: String)
        -> some View
    {
        Button {
            box.setType(row.id, type)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9.5))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(LivTheme.text2)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .overlay(Capsule().strokeBorder(LivTheme.border2, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
    }
}
