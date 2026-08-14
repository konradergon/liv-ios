// liv iOS — the TAB VIEW and the INACTIVE list.
//
// Lifted out of Desk.swift on 2026-08-10, which was 1,159 lines: house
// rule 9 calls ~600 the signal to look for the seam, and the switcher
// was a self-contained 230 of them.
//
// INACTIVE TABS (owner, 2026-08-10, pointing at Chrome for iOS). A tab
// you have not touched in three weeks is not work in progress, it is
// clutter — so it steps out of the grid onto a list of its own, still
// open, still one tap away. Chrome's shape, minus the two things this
// app refuses: the grey subtitle under the row and the explanatory
// paragraph with an inline link (owner, 2026-08-06 — "a grey sentence
// explaining a control is a design failure; say it with the app\'s own
// chips, or don\'t say it"). The threshold rides as a chip instead, and
// each card carries its own age, so "why is this here" is answered
// without prose.
//
// The rule itself lives in LivTabs (Chrome.swift); this file only draws.

import SwiftUI

/// When a desk tab counts as INACTIVE, and the ONE place that decides.
/// The number, the copy and the sweep all read from here, so the row can
/// never claim "21 days" while the rule uses another figure.
///
/// Modelled on Chrome for iOS at the owner's direction (2026-08-10),
/// with its two grey explanatory sentences left out: a sentence
/// explaining a control is a design failure here (owner, 2026-08-06), so
/// the threshold rides as a chip on the row instead.
enum LivTabs {
    /// Device state, like every other tab fact — never a cell.
    static let key = "tabs.inactive.days"
    /// Chrome's own default, and the reference the owner pointed at.
    static let defaultDays = 21
    /// The offered periods; 0 is off. A picker, never a typed number
    /// (standing rule 5).
    static let choices = [7, 14, 21, 0]

    static func label(_ days: Int) -> String {
        days == 0 ? "Never" : "\(days) days"
    }

    static var days: Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? defaultDays
    }

    /// Whole days since a tab was last used. A stamp in the FUTURE — a
    /// clock that moved backwards, a flight west — reads as 0, which is
    /// the safe direction: it sweeps nothing.
    static func age(_ lastUsed: Int64, now: Int64) -> Int {
        max(0, Civil.daysBetween(Civil.day(of: lastUsed), Civil.day(of: now)))
    }

    static func isInactive(_ lastUsed: Int64, now: Int64) -> Bool {
        days > 0 && age(lastUsed, now: now) >= days
    }
}


/// The tab view: it takes the WHOLE screen (owner, 2026-07-29) — top bar
/// and bottom bar both covered, nothing showing through. Card grid with
/// previews, ✕ per card, the dashed new-tab card, and the
/// + | "N tabs" | Done footer, which is the way out.
struct TabSwitcher: View {
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel

    /// The inactive list, over the grid. An overlay in this view's own
    /// hierarchy, not another cover: the switcher is already a
    /// fullScreenCover, and stacking a second one on top of it is how
    /// surfaces started tearing each other down (audit, 2026-08-04).
    @State private var inactiveShown = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ZStack {
            grid
            if inactiveShown {
                InactiveTabs(shown: $inactiveShown)
                    .environmentObject(desk)
                    .environmentObject(box)
                    .background(LivTheme.canvas.ignoresSafeArea())
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }
        }
        .background(LivTheme.canvas.ignoresSafeArea())
    }

    private var grid: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                inactiveRow
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(desk.liveTabs) { tab in card(tab) }
                    newTabCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            footer
        }
    }

    /// FeatureWindow's header, same 40pt band, same `v`. It is not
    /// decoration: a ScrollView that touches the top safe area takes it over
    /// and draws its content THROUGH it, so without a band ahead of it a
    /// scrolled card row slides under the clock and the Dynamic Island —
    /// and a ✕ resting behind the Island cannot be tapped, because that
    /// region belongs to the system. Rule 2 bans the blur that would
    /// normally sit there. This band absorbs the inset and gives the tab
    /// view the same way out the feature windows have.
    private var header: some View {
        HStack(spacing: 0) {
            Button { desk.switcherShown = false } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: LivType.strong, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tabs")
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { desk.switcherShown = false }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { g in
                    if g.translation.height > 40 { desk.switcherShown = false }
                }
        )
    }

    // MARK: cards

    private func card(_ tab: DeskTab) -> some View {
        TabCard(
            tab: tab,
            active: tab.id == desk.activeTabId,
            onOpen: {
                desk.focus(tab.id)
                desk.switcherShown = false
            },
            onClose: { desk.close(tab.id) })
    }

    private var newTabCard: some View {
        Button {
            desk.newTab()
            desk.switcherShown = false
        } label: {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LivTheme.border2,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
                .frame(height: 150)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: LivType.title, weight: .medium))
                        Text("New tab").font(.system(size: LivType.caption, weight: .medium))
                    }
                    .foregroundStyle(LivTheme.text3)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: footer — + | N tabs | Done

    private var footer: some View {
        HStack {
            Button {
                desk.newTab()
                desk.switcherShown = false
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: LivType.strong, weight: .medium))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New tab")
            Spacer()
            // The count agrees with what the grid SHOWS. Inactive tabs
            // are counted on their own row, the only place claiming them.
            Text(
                "\(desk.liveTabs.count) "
                    + (desk.liveTabs.count == 1 ? "tab" : "tabs")
            )
                .font(.system(size: LivType.body).monospacedDigit())
                .foregroundStyle(LivTheme.text3)
            Spacer()
            Button {
                desk.switcherShown = false
            } label: {
                Text("Done")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        // Full screen: no floating bar to clear, just the home indicator
        // (the safe area already handles that).
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }

    // MARK: the door to the inactive list

    /// One row, above the grid. Hidden entirely at zero — an empty
    /// "Inactive 0" row is furniture explaining itself.
    @ViewBuilder private var inactiveRow: some View {
        let parked = desk.inactiveTabs
        if !parked.isEmpty {
            Button {
                withAnimation(LivMotion.nav) { inactiveShown = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: LivType.body))
                        .foregroundStyle(LivTheme.text3)
                        .frame(width: 16)
                    Text("Inactive")
                        .font(.system(size: LivType.body, weight: .medium))
                        .foregroundStyle(LivTheme.text)
                    ValueChip(LivTabs.label(LivTabs.days), dotted: false)
                    Spacer(minLength: 0)
                    Text("\(parked.count)")
                        .font(.system(size: LivType.body).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: LivType.label, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                .padding(.horizontal, 12)
                .frame(height: LivRow.height)
                .background(
                    RoundedRectangle(cornerRadius: LivTheme.radius)
                        .fill(LivTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LivTheme.radius)
                        .strokeBorder(LivTheme.border, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }

}

// MARK: - the inactive list

/// Every tab that has aged out of the grid. Reached from the row above
/// the grid; leaves by the back chevron, which is where this app puts
/// the way out of every full-screen surface (§6: a 40pt band, no
/// navigation bar — this shell has no navigation stack at all).
///
/// Tapping a card revives it: the tab becomes the one you are on, its
/// clock restarts, and it is back in the grid. Nothing here is a
/// second copy of anything — these are the same tabs, in the same one
/// array, just filtered out of the way.
struct InactiveTabs: View {
    @Binding var shown: Bool
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(spacing: 0) {
            band
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(desk.inactiveTabs) { tab in card(tab) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .accessibilityAction(.escape) { close() }
    }

    /// Back, the title, and the bulk verb. "Close all" is a real
    /// control in the band rather than Chrome's floating capsule, and it
    /// asks nothing first: a tab is device state, so closing one writes
    /// NOTHING to the box. Every note and file is still in search, in
    /// Everything, in its workspace. There is no undo chip for the same
    /// reason — the chip means "a transaction was written", and none was.
    private var band: some View {
        HStack(spacing: 0) {
            Button(action: close) {
                Image(systemName: "chevron.left")
                    .font(.system(size: LivType.strong, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to tabs")
            Text("Inactive")
                .font(.system(size: LivType.body, weight: .semibold))
                .foregroundStyle(LivTheme.text)
                .padding(.leading, 4)
            Spacer(minLength: 0)
            Button {
                desk.closeInactive()
                close()
            } label: {
                Text("Close all")
                    .font(.system(size: LivType.body, weight: .medium))
                    .foregroundStyle(LivTheme.accent)
                    .frame(height: 32)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private func close() {
        withAnimation(LivMotion.nav) { shown = false }
    }

    /// The SAME card the grid draws, with the age added to the kind
    /// footer — the one slot that already existed and had room. That is
    /// what earns this screen its explanation without a sentence.
    private func card(_ tab: DeskTab) -> some View {
        TabCard(
            tab: tab,
            age: LivTabs.age(tab.lastUsed, now: Civil.nowStamp()),
            onOpen: { revive(tab) },
            onClose: { desk.close(tab.id) })
    }

    /// Back into the grid, and onto the screen: this is the only way a
    /// tab leaves the inactive list, exactly as Chrome does it.
    private func revive(_ tab: DeskTab) {
        desk.focus(tab.id)
        close()
        desk.switcherShown = false
    }

}

// MARK: - self-check (-tabs.selfcheck 1)

/// The inactive rule, checked against its own edges. Everything here is
/// arithmetic over LivTabs plus the two invariants the grid depends on,
/// so it runs without a box and without a screen.
func livTabsSelfCheck() -> [String] {
    var failures: [String] = []
    func check(
        _ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = ""
    ) {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }

    // Anchored on today rather than a frozen date: the packing is
    // Civil's own business, and running against real dates means the
    // month- and year-boundary cases are exercised for free as the
    // calendar moves.
    let anchor = Civil.todayDay()
    let now = Civil.stamp(day: anchor, hhmm: 1200)
    func daysAgo(_ n: Int) -> Int64 {
        Civil.stamp(day: Civil.addDays(anchor, -n), hhmm: 900)
    }

    // Ages, including the ones that bite.
    check("age today", LivTabs.age(now, now: now) == 0)
    check("age 1d", LivTabs.age(daysAgo(1), now: now) == 1)
    check("age 21d", LivTabs.age(daysAgo(21), now: now) == 21)
    // A month boundary is where hand-rolled day maths goes wrong.
    check("age across months", LivTabs.age(daysAgo(40), now: now) == 40)
    // A clock that moved backwards must never sweep anything.
    let future = Civil.stamp(day: Civil.addDays(anchor, 5), hhmm: 900)
    check("future stamp reads 0", LivTabs.age(future, now: now) == 0)

    // The threshold is a boundary, and >= is the side it falls on.
    let saved = UserDefaults.standard.object(forKey: LivTabs.key)
    UserDefaults.standard.set(21, forKey: LivTabs.key)
    check("20d is live", !LivTabs.isInactive(daysAgo(20), now: now))
    check("21d is inactive", LivTabs.isInactive(daysAgo(21), now: now))
    check("22d is inactive", LivTabs.isInactive(daysAgo(22), now: now))
    check("today is live", !LivTabs.isInactive(now, now: now))
    // Off means off, for any age.
    UserDefaults.standard.set(0, forKey: LivTabs.key)
    check("never: 400d is live", !LivTabs.isInactive(daysAgo(400), now: now))
    UserDefaults.standard.set(7, forKey: LivTabs.key)
    check("7d threshold bites at 7", LivTabs.isInactive(daysAgo(7), now: now))
    check("7d threshold spares 6", !LivTabs.isInactive(daysAgo(6), now: now))

    // The two invariants the grid leans on. Built against a real model
    // so the filters are the ones that actually ship.
    UserDefaults.standard.set(21, forKey: LivTabs.key)
    let model = DeskModel()
    model.replaceTabsForSelfCheck([
        DeskTab(id: UUID(), content: .entity(1), lastUsed: daysAgo(90)),
        DeskTab(id: UUID(), content: .entity(2), lastUsed: daysAgo(40)),
        DeskTab(id: UUID(), content: .entity(3), lastUsed: daysAgo(0)),
    ])
    check("three tabs held", model.tabs.count == 3, "\(model.tabs.count)")
    check("two are inactive", model.inactiveTabs.count == 2, "\(model.inactiveTabs.count)")
    check("one is live", model.liveTabs.count == 1, "\(model.liveTabs.count)")
    check(
        "inactive sorted newest first",
        model.inactiveTabs.first?.lastUsed ?? 0 > model.inactiveTabs.last?.lastUsed ?? 0)

    // Closing every inactive tab leaves exactly the live ones, and the
    // one you are looking at is among them.
    let survivor = model.activeTabId
    model.closeInactive()
    check("close all inactive leaves the live one", model.tabs.count == 1, "\(model.tabs.count)")
    check("the active tab survived", model.activeTabId == survivor)
    check("nothing inactive remains", model.inactiveTabs.isEmpty)

    // INVARIANT 1: the active tab is never inactive, even when its own
    // clock is ancient — otherwise the desk would render a body for a
    // tab the grid refuses to show, and "Close all" would shut the
    // screen out from under you.
    let aged = DeskModel()
    aged.replaceTabsForSelfCheck([
        DeskTab(id: UUID(), content: .entity(1), lastUsed: daysAgo(90)),
        DeskTab(id: UUID(), content: .entity(2), lastUsed: daysAgo(40)),
        DeskTab(id: UUID(), content: .entity(3), lastUsed: daysAgo(0)),
    ])
    aged.activeTabId = aged.tabs.first?.id  // the 90-day-old one
    check("ancient active tab is not inactive", !aged.inactiveTabs.contains { $0.id == aged.activeTabId })
    check("ancient active tab is live", aged.liveTabs.contains { $0.id == aged.activeTabId })
    check("only the untouched middle tab is inactive", aged.inactiveTabs.count == 1, "\(aged.inactiveTabs.count)")

    // INVARIANT 2: live is never empty while tabs is not. This is what
    // keeps "the empty desk IS the chooser" meaning "no tabs at all",
    // rather than "none you opened lately".
    check("live non-empty while tabs non-empty", !aged.liveTabs.isEmpty)

    // And the tab you are on survives the bulk close even at 90 days.
    let ancient = aged.activeTabId
    aged.closeInactive()
    check("ancient active tab survives Close all", aged.tabs.contains { $0.id == ancient })
    check("bulk close took only the inactive one", aged.tabs.count == 2, "\(aged.tabs.count)")

    if let saved { UserDefaults.standard.set(saved, forKey: LivTabs.key) } else {
        UserDefaults.standard.removeObject(forKey: LivTabs.key)
    }
    return failures
}

// MARK: - the card, drawn once

/// ONE tab card, used by the grid and by the Inactive list. Two copies
/// of this existed for about an hour on 2026-08-10 and immediately
/// disagreed about their own height; standing rule 4 says a display
/// helper gets one implementation, same as a parser does.
///
/// `age` is the only difference between the two uses: given, it rides
/// the kind footer as "NOTE · 24D", which is how the Inactive screen
/// explains itself without a sentence.
struct TabCard: View {
    let tab: DeskTab
    var age: Int? = nil
    var active: Bool = false
    let onOpen: () -> Void
    let onClose: () -> Void

    @EnvironmentObject var box: BoxModel

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    Text(title)
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: LivType.micro, weight: .semibold))
                            .foregroundStyle(LivTheme.text3)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close tab")
                }
                .padding(.horizontal, 10)
                Text(excerpt)
                    .font(.system(size: LivType.micro))
                    .foregroundStyle(LivTheme.muted)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Circle().fill(kindColor).frame(width: 5, height: 5)
                    Text(footer)
                        .font(.system(size: LivType.micro, weight: .semibold).monospacedDigit())
                        .kerning(0.5)
                        .foregroundStyle(LivTheme.text3)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(LivTheme.panel)
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(LivTheme.surface))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        active ? LivTheme.accent : LivTheme.border,
                        lineWidth: active ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            age.map { "\(title), inactive \($0) days" } ?? title)
    }

    private var row: EntityRow? {
        guard case .entity(let id) = tab.content else { return nil }
        return box.entity(id)
    }

    private var title: String { row.map(livRowTitle) ?? "Untitled" }

    /// A tab whose entity is gone says so. The dead-tab case is
    /// exactly what collects in the Inactive list, and calling it a
    /// capture would hide the one fact worth knowing about it.
    private var kind: String {
        guard let row else { return "missing" }
        return LivKind.of(row).wire
    }

    /// The kind's own colour, not a hash of the word: this dot used to
    /// come out of `Hue.dot`, which spreads any string over five colours
    /// — so a tab's dot said nothing about what the tab held.
    private var kindColor: Color {
        row == nil ? LivTheme.muted : LivKind.color(of: row)
    }

    private var footer: String {
        age.map { "\(kind.uppercased()) · \($0)D" } ?? kind.uppercased()
    }

    /// 3–4 preview lines. Content bodies are not on the wire yet, so the
    /// honest preview is the property cells.
    private var excerpt: String {
        guard let row else { return "Deleted" }
        var lines: [String] = []
        for cell in row.cells ?? [] {
            guard let p = cell.property, !p.isEmpty, p != "name",
                let v = cell.value, !v.isEmpty
            else { continue }
            lines.append("\(p) · \(v)")
            if lines.count == 4 { break }
        }
        if lines.isEmpty {
            return (row.contentPrint ?? 0) != 0
                ? "Content lives on this entity." : "No details yet."
        }
        return lines.joined(separator: "\n")
    }
}
