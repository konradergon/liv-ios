// liv iOS — THE BOTTOM BAR.
//
// Lifted out of Chrome.swift on 2026-08-23 (standing rule 9). It is the
// one row of furniture that is always on screen, and it reads exactly
// two things off the desk: which view you are in, and how many live tabs
// it holds. Everything else it does is open something.

import SwiftUI

/// SIX KEYS, IN ONE CAPSULE — a browser's, literally (owner,
/// 2026-08-23: "the bottom bar having the same button set you'd expect
/// in a browser or Obsidian—literally"). Measured off the owner's own
/// clip of Obsidian for iOS; every number lives in `LivBar`.
///
///     ‹   ›   🔍   +   [3]
///
/// What this reverses, deliberately:
///
/// - "THREE KEYS: where you are, search, create" (owner, 2026-08-18).
/// - "TWO PIECES, not one" — navigation in a capsule and create as its
///   own circle beside it (owner, 2026-08-18, pointing at ClickUp).
///   Every reference measures ONE capsule.
/// - "The history keys ‹ › are gone with the tabs they stepped through"
///   (team, 2026-08-22). They come back, but not as they were: the old
///   pair stepped through per-launch tab UUIDs and greyed out as tabs
///   closed. These drive `LivReturns`, the durable way-back stack that
///   the labelled back at the top of a document already drives.
/// - The TAB KEY (glyph + count + chevron) is deleted. The strip above
///   answers "where am I" now, and a key that also answered it would be
///   the duplication the owner objected to.
///
/// It stays Liquid Glass. The reference's own material is "fill exactly
/// equal to the page, separated by a shadow alone", which does not
/// survive translation into a dark theme — and the owner asked for
/// Liquid Glass by name.
struct BottomBar: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        HStack(spacing: 0) {
            key("chevron.left", "Back", on: desk.back != nil) { desk.goBack() }
            key("chevron.right", "Forward", on: desk.forward != nil) { desk.goForward() }
            key("magnifyingglass", "Search") { desk.searchShown = true }
            key("plus", "New") { desk.createSomething() }
            tabKey
        }
        // The first and last glyph centres stand `endInset` from the
        // capsule's ends; `endInset - slot/2` of padding puts them there
        // while the six slots share the rest evenly.
        .padding(.horizontal, LivBar.endInset - LivBar.height / 2)
        .frame(height: LivBar.height)
        .livGlass(in: Capsule())
        .padding(.horizontal, LivBar.sideInset)
    }

    /// THE NUMBERED BOX — the tab key, and the only door to the tabs.
    ///
    /// Owner, 2026-08-23: *"Not a tab 'bar', remove it. We're on the
    /// phone, not desktop. Just have tabs as they appeared before when
    /// you clicked the numbered box."* So there is no strip along the
    /// top; tapping this opens the GRID of cards, which is what a phone
    /// browser does and what this app already had.
    ///
    /// It borrows the reference's fifth-key SHAPE — a rounded outline
    /// with a number inside — and puts the count in it instead of the
    /// date. Obsidian's own fifth key opens today's daily note, which
    /// Liv has no concept of; the count is what the box means in every
    /// browser on this phone.
    ///
    /// The count is of LIVE tabs, not all of them: a tab on the Inactive
    /// shelf is open but out of the way, and a key that counted them
    /// would disagree with the grid it opens.
    private var tabKey: some View {
        let n = desk.liveTabs.count
        // YOU CANNOT OPEN THE GRID ON TOP OF THE GRID. Notes' root IS
        // the grid now, so from there this key leads nowhere and is
        // drawn the way every dead key in this bar is drawn: same glyph,
        // same place, dimmer ink (owner, 2026-08-24, having got a card
        // of the grid over the grid).
        let onIt = desk.state == .notes && desk.openDoc == nil
        return Button {
            desk.switcherShown = true
        } label: {
            LivIcon(
                glyph: .day(n),
                color: LivTheme.text.opacity(onIt ? LivBar.disabledInk : 1),
                size: LivBar.glyph + 2
            )
            .frame(maxWidth: .infinity)
            .frame(height: LivBar.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onIt)
        .accessibilityLabel("Tabs. \(n) open in \(desk.state.title)")
    }

    /// One key. Six of these share the capsule evenly, and each one's
    /// TAP TARGET is its whole slot even though the glyph is ~22pt.
    private func key(
        _ icon: String, _ label: String, on: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: LivBar.glyph, weight: .medium))
                .foregroundStyle(LivTheme.text.opacity(on ? 1 : LivBar.disabledInk))
                .frame(maxWidth: .infinity)
                .frame(height: LivBar.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityLabel(label)
    }
}
