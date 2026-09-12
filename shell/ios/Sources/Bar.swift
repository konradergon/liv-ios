// liv iOS — THE BOTTOM BAR.
//
// Lifted out of Chrome.swift on 2026-08-23 (standing rule 9). It is the
// one row of furniture that is always on screen, and it reads exactly
// two things off the desk: whether there is a way back, and how many
// live tabs it holds. Everything else it does is open something.

import SwiftUI

/// THREE PIECES, GROUPED BY WHAT THEY DO (owner, 2026-09-11).
///
///     ‹ ›            🔍            +  [3]
///     move          find         make · reach
///
/// The owner's complaint was two things at once: *"it shows how it works
/// more by inline text instead of icons"*, and *"it looks too similar to
/// obsidian's bar"*. One capsule of five evenly spaced keys IS Obsidian's
/// bar — it was measured off his own clip of it — so the words and the
/// shape are one problem, not two.
///
/// THE WORDS ARE GONE, and this reverses the owner's own ruling of
/// 2026-09-05 on the owner's own word. That ruling was right when it was
/// made: *"the bottom bar should hint user about what '+' creates and
/// that '[n]' is for open notes"*, and at the time `+` printed
/// `Feature.makes` — Note here, Task there, Event on the Calendar. A key
/// whose meaning changed under a glyph that did not is exactly a riddle,
/// and a word was the cheapest answer.
///
/// That condition expired on 2026-09-10, when `+` became a note
/// everywhere. Its word now repeats its glyph, and five captions across
/// 294pt were carrying one key's worth of doubt.
///
/// THE ONE WORD THAT WAS STILL WORKING is the numbered box's. A box with
/// a digit in it is a browser idiom and "Open" was the owner's word for
/// it. It is dropped here as a BET that the digit reads alone; if it does
/// not, that one key gets its caption back and the other four stay bare.
/// The accessibility label is unchanged either way — nothing about this
/// is a change for VoiceOver, which never read the captions.
///
/// WHY THREE AND NOT FIVE-IN-A-ROW. The grouping is the only thing on
/// this bar that says anything now the captions are gone: where you have
/// been, finding, and the pair that makes a note and reaches the open
/// ones. Search stands alone in the middle because it is the one key
/// that is about everything in the box rather than about notes (owner:
/// *"do c, but flip search and create"* — in the drawing the `+` had the
/// middle and search sat with the box).
///
/// BOTH OUTER PIECES ARE TWO KEYS WIDE, which is what lets the middle one
/// be centred by a plain pair of Spacers. If a key is ever added to one
/// side, the middle stops being centred and starts being wherever it
/// lands — so keep them even, or centre it deliberately.
///
/// What this bar has already reversed, and still does:
///
/// - "THREE KEYS: where you are, search, create" (owner, 2026-08-18).
/// - "The history keys ‹ › are gone with the tabs they stepped through"
///   (team, 2026-08-22). They drive `LivReturns`, the durable way-back
///   stack, not the per-launch tab UUIDs the old pair stepped through.
///
/// It stays Liquid Glass, which the owner asked for by name — now on
/// three shapes instead of one.
struct BottomBar: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        HStack(spacing: 0) {
            // MOVE.
            piece {
                key("chevron.left", "Back", on: desk.back != nil) { desk.goBack() }
                key("chevron.right", "Forward", on: desk.forward != nil) { desk.goForward() }
            }
            Spacer(minLength: LivBar.pieceGap)
            // FIND. Alone, and in the middle, because it is the only key
            // here that is not about notes.
            piece {
                key("magnifyingglass", "Search") { desk.searchShown = true }
            }
            Spacer(minLength: LivBar.pieceGap)
            // MAKE, AND REACH. TAP MAKES, HOLD ASKS — the 2026-08-28
            // ruling, untouched: the common thing is one tap and every
            // exception is a tap and a hold. Spoken it is still "New",
            // which is also what the harness taps.
            piece {
                key("plus", "New", hold: { desk.createSomething() }) { desk.newNote?() }
                tabKey
            }
        }
        .padding(.horizontal, LivBar.sideInset)
    }

    /// One glass shape holding one or two keys. The glass is per PIECE,
    /// which is the whole visual change: three shapes with air between
    /// them read as a grouping, where one long capsule reads as a
    /// toolbar.
    private func piece<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, LivBar.piecePad)
            .frame(height: LivBar.height)
            .livGlass(in: Capsule())
    }

    /// THE NUMBERED BOX — the tab key, and the only door to the tabs.
    ///
    /// Owner, 2026-08-23: *"Not a tab 'bar', remove it. We're on the
    /// phone, not desktop. Just have tabs as they appeared before when
    /// you clicked the numbered box."* So there is no strip along the
    /// top; tapping this opens the GRID of cards, which is what a phone
    /// browser does and what this app already had.
    ///
    /// The count is of LIVE tabs, not all of them: a tab on the Inactive
    /// shelf is open but out of the way, and a key that counted them
    /// would disagree with the grid it opens.
    private var tabKey: some View {
        let n = desk.liveTabs.count
        return Button {
            desk.switcherShown = true
        } label: {
            LivIcon(glyph: .day(n), color: LivTheme.text, size: LivBar.glyphSlot)
                .frame(width: LivBar.slot, height: LivRow.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // IT STOPPED BEING TRUE. "3 open in Calendar" named a plane per
        // view, and there is one desk now — the count is the same in
        // every view, which is the whole point of it.
        .accessibilityLabel(n == 1 ? "1 document open" : "\(n) documents open")
    }

    /// One key: a glyph in a `slot` × `LivRow.touch` target, and nothing
    /// else. `spoken` is the accessibility label and, since the captions
    /// went, the only place the key's name survives — which is why it is
    /// no longer optional.
    private func key(
        _ icon: String, _ spoken: String, on: Bool = true,
        hold: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: LivBar.glyph, weight: .medium))
                // DISABLED IS INK, and nothing else: same glyph, same
                // size, same place. A key that vanished when it could
                // not fire would move every key beside it.
                .foregroundStyle(LivTheme.text.opacity(on ? 1 : LivBar.disabledInk))
                .frame(width: LivBar.slot, height: LivRow.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityLabel(spoken)
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
}
