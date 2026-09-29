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
/// THE ONE WORD THAT WAS STILL WORKING was the tab key's. "Open" was the
/// owner's word for it. It is dropped here as a BET that the drawing
/// reads alone — since the Icons board (2026-09-24) stacked notes with
/// the count on the front one, not a numbered box that "read as a date";
/// if it does not, that one key gets its caption back and the other four
/// stay bare. The accessibility label is unchanged either way — nothing
/// about this is a change for VoiceOver, which never read the captions.
///
/// THE KEYS ARE DRAWN in the icon hand (`LivGlyph`), not SF Symbols: the
/// boards draw the chevrons, the lens and `+` at the family's 1.75pt, and
/// Apple's at `.medium` stood heavier than everything around them.
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
/// WHERE THE BAR IS STANDING, in window coordinates. `.zero` when it is
/// not on screen at all.
///
/// **A recognizer on the WINDOW sees touches through anything that is
/// merely drawn on top** — the note beside `LivOverDesk` says the same
/// thing about the panel's, and four surfaces were fixed one at a time
/// before that was understood. The calendar's grid recognizer has it
/// too: holding `+` opened the create menu AND, 0.28s in, started
/// placing an event on the timeline underneath, so letting go made one
/// (owner, 2026-09-15).
///
/// `LivOverDesk` cannot answer this. It counts what is ALREADY up, and
/// a press that starts on the bar has raised nothing yet. Only the
/// bar's own geometry knows.
///
/// Not `@Published` and not on `DeskModel` on purpose: the bar's frame
/// changes on every frame of its retire animation, and nothing should
/// re-render because of it. The one reader is a gesture delegate asking
/// a yes-or-no question.
enum LivBarFrame {
    static var rect: CGRect = .zero

    /// Did this window-space point land on the bar?
    static func holds(_ point: CGPoint) -> Bool {
        rect != .zero && rect.contains(point)
    }
}

struct BottomBar: View {
    @EnvironmentObject var desk: DeskModel
    /// A finger is down on the key that holds a menu (`+`, the only one),
    /// so it wears the held plate — until the finger lifts, or the hold
    /// fires and the bar steps aside for the menu (`Desk.surfaceFoot`
    /// drops it while any menu is up, so the plate is never seen under
    /// the menu itself).
    @GestureState private var holding = false

    var body: some View {
        HStack(spacing: 0) {
            // MOVE.
            piece {
                key(.back, "Back", on: desk.back != nil) { desk.goBack() }
                key(.forward, "Forward", on: desk.forward != nil) { desk.goForward() }
            }
            Spacer(minLength: LivBar.pieceGap)
            // FIND. Alone, and in the middle, because it is the only key
            // here that is not about notes.
            piece {
                key(.search, "Search") { desk.searchShown = true }
            }
            Spacer(minLength: LivBar.pieceGap)
            // MAKE, AND REACH. TAP MAKES, HOLD ASKS — the 2026-08-28
            // ruling, untouched: the common thing is one tap and every
            // exception is a tap and a hold. The glyph is a page with a
            // plus, and the hold now SHOWS, as the corner tick. Spoken it
            // is still "New", which is also what the harness taps; the
            // hold is its hint.
            piece {
                key(.new, "New", hold: { desk.createSomething() }) { desk.newNote?() }
                tabKey
            }
        }
        .padding(.horizontal, LivBar.sideInset)
        // WHERE IT IS, so a recognizer on the window can refuse it.
        //
        // Measured AFTER every modifier that moves it, so the rect
        // follows the bar off screen when the chrome retires and the
        // band underneath goes live again. Paired with
        // `location(in: nil)`, which is the same window space — the
        // calendar's trash zone already works this way.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { LivBarFrame.rect = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, f in LivBarFrame.rect = f }
                    .onDisappear { LivBarFrame.rect = .zero }
            }
        )
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

    /// THE TAB KEY — notes stacked, the count on the front one — and
    /// the only door to the tabs.
    ///
    /// Owner, 2026-08-23: *"Not a tab 'bar', remove it. We're on the
    /// phone, not desktop. Just have tabs as they appeared before when
    /// you clicked the numbered box."* So there is no strip along the
    /// top; tapping this opens the GRID of cards, which is what a phone
    /// browser does and what this app already had. It was a numbered box
    /// until the Icons board, where it "read as a date".
    ///
    /// The count is of LIVE tabs, not all of them: a tab on the Inactive
    /// shelf is open but out of the way, and a key that counted them
    /// would disagree with the grid it opens.
    private var tabKey: some View {
        let n = desk.liveTabs.count
        return Button {
            desk.switcherShown = true
        } label: {
            LivIcon(glyph: .tabs(n), color: LivTheme.text, size: LivBar.glyphSlot)
                .frame(width: LivBar.slot, height: LivRow.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // IT STOPPED BEING TRUE. "3 open in Calendar" named a plane per
        // view, and there is one desk now — the count is the same in
        // every view, which is the whole point of it.
        .accessibilityLabel(n == 1 ? "1 document open" : "\(n) documents open")
    }

    /// One key: a drawn glyph in a `slot` × `LivRow.touch` target, and
    /// nothing else. `spoken` is the accessibility label and, since the
    /// captions went, the only place the key's name survives — which is
    /// why it is no longer optional. A key with a `hold` wears the corner
    /// tick, and the held plate while a finger is on it.
    private func key(
        _ glyph: LivGlyph, _ spoken: String, on: Bool = true,
        hold: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            LivIcon(glyph: glyph, color: LivTheme.text, size: LivBar.glyph)
                // DISABLED IS INK, and nothing else: same glyph, same
                // size, same place. A key that vanished when it could
                // not fire would move every key beside it. The WHOLE
                // icon dims, so its layers never compound.
                .opacity(on ? 1 : LivBar.disabledInk)
                // HOLD FOR MORE: the tick's corner stands `tickOffset`
                // right of and below the glyph's. An overlay, so the
                // key's frame — which drive.sh measures — does not move.
                .overlay(alignment: .bottomTrailing) {
                    if hold != nil {
                        HoldTick().offset(x: LivPen.tickOffset, y: LivPen.tickOffset)
                    }
                }
                .frame(width: LivBar.slot, height: LivRow.touch)
                // HELD: the full height of the piece, concentric with its
                // capsule. A background, so it changes no frame either.
                .background {
                    if hold != nil && holding {
                        RoundedRectangle(cornerRadius: LivBar.height / 2 - LivBar.piecePad)
                            .fill(LivTheme.text.opacity(LivPen.held))
                            .frame(width: LivBar.slot, height: LivBar.height)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .livDoor()
        .disabled(!on)
        .accessibilityLabel(spoken)
        .accessibilityHint(hold == nil ? "" : "Hold for more")
        // The hold is a SIMULTANEOUS gesture so it cannot eat the tap:
        // attached with `.onLongPressGesture`, the button stops firing
        // on a quick press and every key would have to be held.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .updating($holding) { pressing, held, _ in held = pressing }
                .onEnded { _ in hold?() },
            including: hold == nil ? .subviews : .all
        )
        // VoiceOver and Voice Control cannot press-and-hold, so the
        // menu has to be reachable as a named action too.
        .accessibilityAction(named: "More") { hold?() }
    }
}
