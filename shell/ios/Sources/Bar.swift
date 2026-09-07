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
///
/// EVERY KEY HAS A WORD UNDER IT (owner, 2026-09-05). Two of the five
/// were riddles: `+` made a different thing in every view and said
/// nothing, and a box with a number in it is a browser's tab count only
/// if you already know browsers. The owner asked for the bar to "hint
/// user about what '+' creates and that '[n]' is for open notes", in
/// the style of the Throwaway recordings — and of those, Todoist's bar
/// is the one that puts a word under each glyph. So the `+` prints the
/// kind it will make here (`Feature.makes`: Note, Task or Event — the
/// same rule that makes it), the box prints "Open", and the other three
/// print their names, because three bare keys beside two labelled ones
/// would read as two bars.
struct BottomBar: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        HStack(spacing: 0) {
            key("chevron.left", "Back", on: desk.back != nil) { desk.goBack() }
            key("chevron.right", "Forward", on: desk.forward != nil) { desk.goForward() }
            key("magnifyingglass", "Search") { desk.searchShown = true }
            // TAP MAKES, HOLD ASKS. The menu is still one gesture away
            // and it is the same menu; what changed is which of the two
            // costs more. The word is what a tap makes HERE; spoken, it
            // stays "New", which is also what the harness taps.
            key("plus", desk.state.makes.word, spoken: "New", hold: { desk.createSomething() }) {
                desk.createHere?()
            }
            tabKey
        }
        .padding(.horizontal, LivBar.endPad)
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
        // ALIVE EVERYWHERE AGAIN (2026-08-28). This key was dead on
        // Notes' root for as long as that root WAS the grid — you cannot
        // open the grid on top of itself. The root is the list again, so
        // the switcher is always a different surface from the one you
        // are standing on, and the special case goes rather than being
        // handled.
        return Button {
            desk.switcherShown = true
        } label: {
            // "OPEN", not "Desk": the word the owner used for what the
            // box counts (2026-09-05), and the word the grid it opens
            // now uses too. "Desk" was the dropped desktop's word.
            slot("Open") {
                LivIcon(glyph: .day(n), color: LivTheme.text, size: LivBar.glyphSlot)
            }
            .foregroundStyle(LivTheme.text)
        }
        .buttonStyle(.plain)
        // IT STOPPED BEING TRUE. "3 open in Calendar" named a plane per
        // view, and there is one desk now — the count is the same in
        // every view, which is the whole point of it.
        .accessibilityLabel(n == 1 ? "1 document open" : "\(n) documents open")
    }

    /// One key. Five of these share the capsule evenly, and each one's
    /// TAP TARGET is its whole slot even though the glyph is ~22pt.
    /// `word` is printed under the glyph; `spoken` is what VoiceOver
    /// says when the two should differ (the `+` prints the kind it makes
    /// and is spoken as "New").
    private func key(
        _ icon: String, _ word: String, spoken: String? = nil, on: Bool = true,
        hold: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            slot(word) {
                Image(systemName: icon)
                    .font(.system(size: LivBar.glyph, weight: .medium))
            }
            .foregroundStyle(LivTheme.text.opacity(on ? 1 : LivBar.disabledInk))
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityLabel(spoken ?? word)
        // The hold is a SIMULTANEOUS gesture so it cannot eat the tap:
        // attached with `.onLongPressGesture`, the button stops firing
        // on a quick press and every key would have to be held.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in hold?() },
            including: hold == nil ? .subviews : .all
        )
        // VoiceOver and Voice Control cannot press-and-hold, so the
        // menu has to be reachable as a named action too.
        .accessibilityAction(named: "More") { hold?() }
    }

    /// A glyph over its word, filling one slot. The glyph gets a fixed
    /// box whatever its own height — a chevron is shorter than the
    /// numbered box — so the five words share one baseline.
    private func slot<Glyph: View>(_ word: String, @ViewBuilder glyph: () -> Glyph) -> some View {
        VStack(spacing: LivBar.wordGap) {
            glyph().frame(height: LivBar.glyphSlot)
            Text(word)
                .font(.system(size: LivType.caption, weight: .medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: LivBar.height)
        .contentShape(Rectangle())
    }
}
