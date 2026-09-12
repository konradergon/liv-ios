// liv iOS — tokens (design/ios.md §7). Dark is the house look; a LIGHT
// twin arrived 2026-08-07 (owner: "add light mode") — every token is a
// dark/light pair resolved by the system's appearance machinery, and a
// Settings row picks Dark, Light, or System.
//
// THE COLOURS ARE OURS, as of 2026-08-30 — see `Palette` below for the
// measurements they came from. They were the system's semantic set from
// 2026-08-15 ("revert colors and faces to as system like as possible…
// we should do the surface appearance last and thoroughly"), which was
// the right call at the time and is now spent: the owner has asked for
// exactly the surface appearance that sentence deferred, and named the
// system look as the thing to get away from.
//
// This is the SECOND surface pass. The first, on 2026-08-20, repainted
// nothing on purpose — it gave the app the shapes its reference set
// shares (a card, one row, one hairline inset, a press state), because
// measuring showed the roughness then was never the colours; it was
// thirteen row recipes with five heights and five separator insets.
// That groundwork is why this pass could be mostly one file.
//
// An icon-derived palette was tried before either of them and reverted,
// and the paragraph describing it lived on at the top of this file for
// five days after the code stopped doing it — which is what a comment
// that outlives its code looks like, and why this one was rewritten in
// the same change as the values.
//
// `livPaletteSelfCheck` still measures contrast rather than trusting
// anyone's eye, and its floors went up with this pass.

import SwiftUI
import UIKit

private func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha)
}

/// A dark/light pair as one UIColor — resolved per view by the trait
/// system, so a sheet or panel re-renders itself when the scheme flips.
private func hex(
    _ dark: UInt32, _ alpha: CGFloat = 1, light: UInt32, lightAlpha: CGFloat? = nil
) -> UIColor {
    UIColor { traits in
        traits.userInterfaceStyle == .light
            ? hex(light, lightAlpha ?? alpha) : hex(dark, alpha)
    }
}

private func solid(_ value: UInt32, _ alpha: CGFloat = 1) -> Color {
    Color(hex(value, alpha))
}

private func solid(
    _ dark: UInt32, _ alpha: CGFloat = 1, light: UInt32, lightAlpha: CGFloat? = nil
) -> Color {
    Color(hex(dark, alpha, light: light, lightAlpha: lightAlpha))
}

// MARK: - appearance (device setting, never a cell)


/// Dark / Light / follow the system. Stored raw in UserDefaults;
/// consumed by RootView's preferredColorScheme.
enum LivAppearance: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    static let key = "appearance"

    static var current: LivAppearance {
        UserDefaults.standard.string(forKey: key).flatMap(LivAppearance.init)
            ?? .dark
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return .unspecified
        }
    }

    /// Apply to every WINDOW, not with `preferredColorScheme`.
    ///
    /// `preferredColorScheme` only reaches the view tree it is attached
    /// to. A sheet is a separate presentation with its own root, so a
    /// scheme flip made from inside Settings changed the whole app
    /// except the Settings sheet you were standing in, until you closed
    /// it (owner, 2026-08-08). The window override reaches every
    /// presentation there is, UIKit views included.
    func applyToWindows() {
        let style = self.style
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

/// The TYPE SCALE. Until 2026-08-10 sizes were prose: 19 distinct values
/// across 253 call sites, 86 of them under 12pt — against the owner's own
/// "no micro-text" rule, and the exact drift CLAUDE.md's rule 3 predicts
/// ("colours are tokenised and have never drifted; type sizes are prose
/// and have drifted 38 times"). Type now works the way colour does.
///
/// Every step went up on the owner's word (2026-08-10: "text is too
/// small… and text could in places be a notch bigger throughout the app
/// for readability"). The old band each step replaces is named so the
/// next person can see what was merged into what.
enum LivType {
    // ONE STEP ABOVE THE PLATFORM (owner, 2026-08-31: "things are too
    // small in general" — the THIRD time, after 2026-08-10 "text is too
    // small… could in places be a notch bigger" and 2026-08-18 "ui text
    // is just too small throughout").
    //
    // Twice the answer was to move UP to Apple's own scale: body 15 →
    // 17, which is the system's body. That is where it sat, and the app
    // still read small — so the answer is not "match the platform"
    // any more. Liv is a reading-and-deciding app, not a dense
    // inspector, and its owner wants it comfortable at arm's length.
    // Every step goes up one notch past iOS.
    //
    // Measured against the references first, so this is not just
    // bigger-because-asked: Todoist's row title is 17–18 and its screen
    // title is 34. `body` at 18 and `hero` at 32 sit right beside them —
    // this is the reference set's size, arrived at from underneath.
    //
    /// A badge — never a word you have to read.
    static let micro: CGFloat = 12
    /// Chips, stamps, counts, a row's second line.
    static let caption: CGFloat = 14
    /// Section labels, secondary detail.
    static let label: CGFloat = 16
    /// The app's ORDINARY text: list rows, values, buttons.
    static let body: CGFloat = 18
    /// Emphasised rows, the create-menu verbs.
    static let strong: CGFloat = 20
    /// Sheet titles.
    static let title: CGFloat = 22
    /// An entity's name in the properties panel.
    static let display: CGFloat = 26
    /// A SCREEN's name, and a record's name field.
    static let hero: CGFloat = 32

    /// THE EDITOR'S OWN SCALE, and the fact that it is a second one.
    ///
    /// The markdown editor draws with TextKit, so it needs `UIFont`
    /// sizes rather than the steps above — but that is a reason for
    /// different UNITS, not for different NUMBERS, and until 2026-09-07
    /// these lived as literals inside `EditorText.swift`, dated
    /// 2026-07-31: they predate `LivType` entirely.
    ///
    /// They were moved here UNCHANGED, on purpose (design/editor-study.md:
    /// "move the numbers to Theme.swift without changing them, so the
    /// drift is visible"). And it is visible: `body` is 16 while every
    /// list row that opens a note is `LivType.body` at 18.
    ///
    /// THE SECOND EXAMPLE THIS COMMENT USED TO GIVE WAS WRONG, and it
    /// is worth recording why, because it is the reason to measure a
    /// drift rather than read one off a list of numbers. It said `mono`
    /// was 12 "for a code block that is nothing but words" — but the
    /// font that size fed was never applied to anything. Its only call
    /// site was `dim()`'s font override, and that went on the owner's
    /// word on 2026-08-11 ("a marker is greyed, NEVER resized"); the
    /// styler has no fenced-block branch to put it back. So a size with
    /// no readers was being cited as visible drift. The size went on
    /// 2026-09-12 under standing rule 6, and the rev that teaches the
    /// styler the fence picks its own monospace size rather than
    /// inheriting one nobody chose.
    ///
    /// Closing the `body` gap is NOT a token swap. `EditorFont.listGutter`
    /// is calibrated against the widest marker at the CURRENT body size,
    /// and the drawn checkbox and bullet are centred on `body.lineHeight`
    /// — so a resize has to re-derive all three and be seen on a
    /// simulator. It is its own rev, on the owner's word.
    enum Editor {
        static let body: CGFloat = 16
        static let codeInline: CGFloat = 14.5
        static let h1: CGFloat = 25
        static let h2: CGFloat = 21
        static let h3: CGFloat = 18
    }
}

/// A DAY'S MARK — the disc behind the number that says "this is the day
/// you are on".
///
/// Rev 47 made the correction standing (owner: *"today's date is marked
/// by a tiny dot that is completely hidden by a horizontal bar when
/// selected. You have a tendency to make UI elements tiny and subtle.
/// Try to go for the opposite."*). It landed on Today's week strip and
/// nowhere else; the calendar's month grid kept the 2pt rule and the 4pt
/// dot the owner had just named, until 2026-09-07.
///
/// TWO DIAMETERS, because the two grids carry different loads. The strip
/// shows seven days in a full-width row and can afford 36. A month cell
/// is one of seven columns and also stacks three busy dots under the
/// number, so its disc is 28 in a cell grown from 40 to 46 — sized to
/// what forty-two cells can carry, not copied from the strip.
///
/// The grid cannot simply take the strip's numbers: `CalGrid.gridHeight`
/// is `cellHeight * 6 + rowGap * 5`, and it is also the picker sheet's
/// detent. At the strip's 62 the card would stand 382pt tall, which is
/// the jump card becoming the screen — the thing design/ios.md §37 says
/// it deliberately is not.
enum LivDay {
    /// The week strip's disc, and the row it sits in.
    static let disc: CGFloat = 36
    static let strip: CGFloat = 62
    /// The month grid's disc — smaller, because the cell also carries
    /// the busy dots.
    static let gridDisc: CGFloat = 28
}

/// Row metrics. A list row was 46pt when its text was 11–13; the type
/// scale went up on 2026-08-10 and the rows had to go with it, or the
/// bigger text would simply be more cramped in the same box (owner:
/// "UI in the property panel is cramped towards the top when almost half
/// of the panel is empty").
/// THE LEFT PANEL, measured off the owner's own reference.
///
/// Every number here was read out of `~/Desktop/Throwaway/ui-inspo/left-panel.MOV`
/// frame by frame (2026-08-23) rather than invented, because the owner
/// asked for the aesthetic to be COPIED, not approximated. The clip is
/// the ChatGPT iOS app; the two attached screenshots (Notesnook,
/// Obsidian) agree with it on everything they both show.
///
/// **The panel is not full screen.** That reverses rev 6's "both panels
/// are FULL-SCREEN (Notesnook's layout is the model)" of 2026-08-03 —
/// the owner looked at it on a phone and said no.
enum LivPanel {
    /// How much of the desk stays on screen beside the panel. The
    /// reference leaves 99pt of a 430pt screen; a fixed peek rather than
    /// a percentage, so a small phone keeps a real, tappable sliver
    /// instead of a stripe.
    static let peek: CGFloat = 100

    /// The panel's width: everything except the peek. 330 of 430 = 77%,
    /// which is what the reference measures.
    static let width: CGFloat = max(240, LivScreen.width - peek)

    /// One inset for EVERYTHING in the panel — the title, every glyph
    /// column, every section heading, every row's text, and the trailing
    /// edge of the header button. The reference uses 28 for all of them,
    /// and that single column is what makes two different lists read as
    /// one.
    static let inset: CGFloat = 28

    /// One rhythm for the whole panel: nav rows and list rows alike.
    /// Grew with the type scale on 2026-08-31, like `LivRow.height`.
    static let row: CGFloat = 57

    /// The lit row's fill sits 12pt from each panel edge — 16pt OUTSIDE
    /// the text inset, so the fill is the row plus its padding rather
    /// than a box drawn around the words.
    static let litInset: CGFloat = 12
    static let litRadius: CGFloat = 12
    static let litHeight: CGFloat = 49

    /// The desk's corner radius while it is pushed aside. This is the
    /// DEVICE's own display radius, which is the whole trick: the desk
    /// reads as the same screen moved sideways, not as a card.
    static let deskRadius: CGFloat = 55

    /// How far the desk's own content fades while the panel is open.
    /// The reference measures 0.50 on three separate elements. It is a
    /// wash toward the background, never a black scrim — so in a dark
    /// theme it is the canvas laid over the content, not shade.
    static let wash: CGFloat = 0.5

    // The desk's shadow onto the panel lived here and is gone
    // (2026-08-31): it never drew, because the panel sits above the desk
    // in z and the shadow painted underneath it. Deleted with its one
    // call site rather than left as two numbers nothing reads.
}

/// The screen, asked once. `UIScreen.main.bounds` is deprecated and was
/// being read from five places that all had to agree about how far a
/// panel travels; they now agree by construction (standing rule 4).
enum LivScreen {
    /// READ ONCE, not per render.
    ///
    /// It was a computed property, and `deskShift` reads it on every
    /// evaluation of the desk's body — so every render pulled UIKit
    /// scene state into the SwiftUI graph. The result was not a crash
    /// but something worse to find: bodies kept evaluating with the
    /// right values while the screen stopped updating at all. Switching
    /// view left the old surface on screen with the new chrome over it,
    /// and a stack sample showed the layout attributes cycling (found
    /// live, 2026-08-23, after bisecting eight innocent modifiers).
    ///
    /// A phone does not change its screen width. One read at launch.
    static let width: CGFloat = {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.width ?? 430
    }()
}

/// A CHIP, in one place. Three capsule recipes were hand-copied across
/// Today, Tasks and Search with different heights and paddings, and the
/// two in `Kit` disagreed with all of them. A chip is a shape this app
/// draws forty times; it gets a token like everything else that matters
/// (standing rule 3).
enum LivChip {
    /// The ordinary chip: a SECOND VOICE in a row, `caption` (14). 17
    /// was the old height, sized around 11pt text, and the capsule grew
    /// with the text. Never `micro`, which is a badge size.
    static let height: CGFloat = 24
    /// The roomier variant, for a chip that stands alone in a row rather
    /// than in a run of them. Same text as `height`; padding is the
    /// whole difference.
    static let tall: CGFloat = 30
    /// A CHIP THAT IS A VALUE, not a second voice: the properties card,
    /// where the chip is the whole answer to "what is this field?" and
    /// every other value in that column is `strong` (20). A 20pt line
    /// box is ~24, so 34 leaves 5 either side — `tall` (30) would sit a
    /// descender on the capsule's edge, and `tall` is shared with the
    /// filter chips besides.
    static let value: CGFloat = 34
    /// A glyph inside a chip, and the only size one may be.
    static let glyph: CGFloat = 14
    /// A glyph inside a `value` chip, scaled to its text the way `glyph`
    /// is scaled to `caption`.
    static let valueGlyph: CGFloat = 20
}

enum LivRow {
    /// THE ROW HEIGHT — every row that names a thing and opens it, and
    /// a good deal more besides: the properties card's field rows, the
    /// create menu's items, the workspace picker, the tab-switcher row.
    /// 25 call sites. Move this number and all of them move.
    ///
    /// Until 2026-09-05 it was one list's number pretending to be a
    /// token (owner: *"tasks rows still to low. make row height more
    /// consistent"*). The six content views ran 42 / 44 / 48 / 56:
    /// Notes, Everything and Inbox called this, and Tasks, Today and
    /// Search each carried a raw literal instead — three different
    /// ones, and Today alone used two. Scrolling from one view to the
    /// next changed the beat of the list for no reason a reader could
    /// name. A number with three callers and four values is not a rule;
    /// it is a habit (standing rule 3). Those six are on it now.
    ///
    /// `drive.sh rows` asserts it from the screen.
    ///
    /// 54 was the number when a row's text was 16–18 and every row had
    /// a hairline under it; the surface pass took the hairlines out of
    /// content lists and the rows came down with them (owner,
    /// 2026-08-18: "maximize simplicity… quiet, effortless").
    // THE ROWS GO UP WITH THE TEXT. This file's own lesson from
    // 2026-08-10: when the scale grew and the rows did not, the bigger
    // text was simply more cramped in the same box. 56 also clears
    // Apple's 44pt touch minimum with room to spare — the Inbox's Route
    // rows were measured at 40 on 2026-08-31, under the minimum, which
    // is part of why they read as small.
    static let height: CGFloat = 56
    /// A TALLER row, for one that carries its own controls under the
    /// words rather than beside them — the clerk's proposal row is the
    /// only caller.
    static let tall: CGFloat = 70
    /// A CHROME row inside a content list — a collapse heading, a
    /// notice, a "N captured today" banner. It does not name a thing you
    /// open, so it does not take `height` and stays visibly shorter than
    /// the rows above it. Four raw literals were doing this job, two at
    /// 38 and two at 40 (2026-09-05).
    ///
    /// 44, not 40: three of the four are the whole hit area of a Button,
    /// and this file argues the 44pt touch minimum twice. Still 12 short
    /// of a content row, which is the distinction it exists to draw.
    static let band: CGFloat = 44
    /// THE TOUCH MINIMUM, Apple's. Not a row height — the hit area of a
    /// control that lives inside one, where the ink is smaller than the
    /// finger: a status ring, a checkbox, a reject cross. It was a raw
    /// 44 in five places across two files.
    static let touch: CGFloat = 44
    /// The band the top chrome owns: the two door circles and the
    /// workspace button centred between them. ANYTHING that speaks at
    /// the top of the screen — a banner, a notice, an acknowledgment —
    /// starts below this, or it lands on the workspace's own name
    /// (owner, 2026-08-15: "the message is on top of each other").
    static let topChrome: CGFloat = 52

    // THE ROW GRID, measured off `~/Desktop/Throwaway/new/todoist-inbox.mov`
    // frame by frame (2026-08-30), the way the panel's numbers were read
    // off its own reference. Todoist's inbox row is: an 18pt screen
    // margin, a 24pt circle, 15pt of air, then the words at 57. Ours is
    // the same shape at this app's own 16pt margin.
    //
    /// The screen's own margin. Every surface starts here.
    static let margin: CGFloat = 16
    /// The leading MARK column: a checkbox, a kind glyph, a status ring.
    /// One width, so a list of tasks and a list of notes share a spine.
    static let mark: CGFloat = 24
    /// Mark to words.
    static let markGap: CGFloat = 14

    /// THE KIND MARK at the head of a LIST row — the leaf, the tray,
    /// the ring. It was a raw `19` in `LivListRow` and a second raw `19`
    /// in the Inbox's own row: one number, two copies, neither in a type
    /// (standing rule 3).
    ///
    /// It does NOT claim every mark in the app. Search draws its hit
    /// mark at 22 and Today's agenda at 17, both deliberately, because
    /// those rows lead with something other than a 24pt mark column.
    static let glyph: CGFloat = 19

    /// WHERE A ROW'S WORDS START — past the mark column.
    static let text: CGFloat = margin + mark + markGap

    /// WHERE A HAIRLINE STARTS, and it is the same place as the words.
    ///
    /// Measured 2026-08-20 the app drew separators at five different
    /// insets across thirteen hand-rolled recipes; one number fixed that,
    /// but the number was 36 and no row's text began at 36 — so every
    /// hairline started 18pt to the left of the words it divided.
    /// Todoist's begins exactly at its text column, which is what makes
    /// the mark column read as a clear spine down the list rather than
    /// as an indent. Derived now, so the two cannot drift apart.
    static let hairline: CGFloat = text

    /// The gap a CARD leaves at the screen's edges. A card is how the
    /// reference apps group rows — Apple Notes, Obsidian's overflow
    /// sheet and ChatGPT's settings all put related rows on a raised
    /// panel with a quiet label above it, rather than running hairlines
    /// edge to edge (owner's clips, 2026-08-20).
    static let cardInset: CGFloat = 16

    /// THE ROOM A SECTION HEADING OWNS.
    ///
    /// It used to own none. `SectionLabel` drew the words and left the
    /// space to whoever placed it, so all sixteen call sites supplied
    /// their own and disagreed five ways: 14, 16, 18 or 22 above and 2,
    /// 4 or 6 below, with two sites giving none at all. The same
    /// heading sat closer to its rows on Today than in the properties
    /// panel, which is the kind of unevenness you feel without being
    /// able to point at it.
    ///
    /// 18 and 4 are chosen to MOVE THE LEAST: no heading in the app
    /// shifts more than 4pt above or 2pt below from where it sat. Every
    /// other candidate moved something twice as far.
    ///
    /// The ratio is the part that matters and every reference app
    /// agrees on it — a big gap above, a small one below, so a heading
    /// binds downward to the rows it names and separates upward from
    /// the group before it.
    static let sectionTop: CGFloat = 18
    static let sectionBottom: CGFloat = 4

    /// The same band measured from the very top of the SCREEN. Surfaces
    /// run under the status bar now (owner, 2026-08-17: "the screen
    /// should also extend to the very top where time and battery
    /// indicators are and all the top buttons should float above"), so
    /// anything that must clear the floating buttons has to clear the
    /// clock as well.
    static var topInset: CGFloat { LivSafeArea.top + topChrome }
}

/// The floating bottom bar's own size, so anything that must clear it —
/// or send it off screen — asks rather than guesses. Measured
/// 2026-08-20: four unrelated literals were doing this job (58 in the
/// panel and the feature bodies, 62 in App, 88 in Notes, 110 inside the
/// editor), none of them the bar's actual height. Those four are still
/// there; only the scroll-away chrome asks.
/// THE BOTTOM BAR, measured off `bar-and-buttons-dynamic-hiding.MOV`
/// (Obsidian for iOS) on 2026-08-23. The owner asked for "the same
/// button set you'd expect in a browser or Obsidian — literally", so
/// the capsule's proportions are the reference's own rather than ours.
///
/// THE LABELS ARE TODOIST'S (owner, 2026-09-05: the bar "should hint
/// user about what '+' creates and that '[n]' is for open notes", in
/// the style of the Throwaway recordings). Obsidian's bar is five bare
/// glyphs; Todoist's is a glyph over a word, and that is the one form
/// in the owner's references that SAYS what a key does. Measured off
/// `todoist-inbox.mov`: glyph ~20, word ~11, ~6 between — a 24pt slot
/// for our 22pt glyph and a word under it.
///
/// THE WORD IS `caption`, NOT `micro` (owner, 2026-09-05: "bump to 14").
/// Todoist's own is ~11 and this app has been called too small four
/// times; the reference is a floor to clear, not a ceiling.
enum LivBar {
    /// 52, which is a 44pt touch target in 4pt of padding. It was 66 to
    /// hold a 14pt word under each glyph; the words are gone (2026-09-11)
    /// and so is the row they needed. Even, so the radius stays whole.
    static let height: CGFloat = 52
    /// The breath between the bar and the screen's bottom edge.
    static let gap: CGFloat = 4
    /// How far the OUTER pieces stand in from each screen edge. It was
    /// 42 for one capsule, measured off Obsidian at 43 of 430. Three
    /// pieces want the edges: at 42 they huddle in the middle and the
    /// gaps between them stop reading as deliberate.
    static let sideInset: CGFloat = 24
    /// A piece's own horizontal padding, inside the glass.
    static let piecePad: CGFloat = 4
    /// The least air between two pieces. In practice they are pushed
    /// apart by Spacers and stand much further; this is the floor that
    /// keeps them three shapes rather than one broken one.
    static let pieceGap: CGFloat = 12
    /// One key's width inside a piece. Its HEIGHT is `LivRow.touch` —
    /// the app's one touch floor, not a second copy of 44.
    static let slot: CGFloat = 46
    static let glyph: CGFloat = 22
    /// The box the numbered glyph draws in. It was sized so the words
    /// under the five keys shared a baseline; it stays because the box
    /// is a drawing with a digit in it and wants a fixed frame.
    static let glyphSlot: CGFloat = glyph + 2
    /// DISABLED IS INK, and nothing else: same glyph, same size, same
    /// place. The reference's disabled grey is 31% of its enabled ink,
    /// with no plate, no border and no removal from the row.
    static let disabledInk: CGFloat = 0.3
    /// From the bottom of the SCREEN to the top of the bar. Includes the
    /// live safe area, so it is for offsets and paddings only.
    static var clearance: CGFloat { height + gap + LivSafeArea.bottom }

    /// THE ROOM A SURFACE LEAVES FOR THE BAR — and the one to use inside
    /// `.safeAreaInset`.
    ///
    /// It must NOT read the live safe area. A safe-area inset whose own
    /// height is derived from the safe area feeds itself: AttributeGraph
    /// reports a cycle, and the surface then STOPS UPDATING while its
    /// body keeps evaluating perfectly — switching view leaves the old
    /// screen up under the new chrome. That cost half a day and eight
    /// innocent suspects on 2026-08-23; the giveaway was `desk.state`
    /// logging the right value while the pixels never changed.
    ///
    /// A surface inside a safe-area inset is already above the home
    /// indicator, so the bar's own height plus its gap is the whole
    /// requirement.
    static let room: CGFloat = height + gap + 8

    /// THE ROOM A SCROLLING LIST LEAVES, which is `room` plus a hand's
    /// width of air so the last row is not pinned under the glass.
    ///
    /// Written out as `LivBar.room + 24` at five call sites — Everything,
    /// Inbox, Notes, Tasks and Today — three of which also carried a
    /// prose copy of this same reason. One number, one place (standing
    /// rules 3 and 4).
    ///
    /// Not to be confused with `room + gap` (App.swift), which is a
    /// different number for a different job: the bar's own floor, not a
    /// list's tail.
    static let listRoom: CGFloat = room + 24
}

/// One consistent motion for the whole app (owner, 2026-07-31): navigation
/// areas move from and into view — nothing rotates, nothing fades in
/// combination. One curve, one duration for NAVIGATION.
///
/// "NOTHING SPRINGS" WAS LIFTED on 2026-08-31 (owner: "i said somewhere
/// that animations should be used little. ignore that now. modern apps
/// have animations"). The navigation rule above stands — a surface
/// replacing a surface is still one easing, because a spring on a
/// full-screen move reads as wobble. What the lift buys is `list`
/// below: things that arrive and leave INSIDE a surface, which the app
/// used to snap in and out with no motion at all.
enum LivMotion {
    /// THE ONE CURVE MOST OF THE APP MOVES ON — 35 of the 45
    /// `withAnimation` calls in the shell, plus two `.animation(value:)`
    /// modifiers: every sheet, card, menu and panel, the surface swap,
    /// and the chrome retiring under a scroll.
    ///
    /// IT WAS `easeInOut`, and that is most of why the app read amateur
    /// (owner, 2026-09-11: *"mainly motion but also type and spacing…
    /// currently it wouldn't appeal to users"*). A symmetric ease is the
    /// curve every prototype uses and nothing on the platform does: it
    /// starts and stops at the same rate, so a card arrives with no
    /// weight and a panel stops dead. The app already owned two springs
    /// and they covered twelve call sites out of forty-seven.
    ///
    /// `snappy` is the SYSTEM's spring, not a hand-rolled one, which is
    /// the point — the thing that reads expensive here is matching the
    /// platform rather than inventing a feel. `extraBounce: 0` keeps it
    /// sober: the owner asked for better, not fancier, and a bar that
    /// wobbles is worse than one that eases.
    ///
    /// One token still, deliberately. Splitting a sheet's rise from a
    /// surface's swap is a real distinction and a later pass; doing it
    /// here would also fork `navSeconds`, which seven teardown timers
    /// read to know when the motion has landed.
    static let nav = Animation.snappy(duration: navSeconds, extraBounce: 0)

    /// HOW A SURFACE REPLACES A SURFACE. Measured 2026-08-20: there was
    /// no transition declared on either branch point, so SwiftUI used
    /// its default — `.opacity`. The app's primary navigation, the one
    /// the Go-to menu drives, CROSS-FADED, which is the one thing the
    /// rule above forbids ("nothing fades in combination"). It had been
    /// that way since the states were built.
    ///
    /// A state replaces a state — they are roots, never children — so
    /// there is no forward and no back to encode. One direction for
    /// all of them: the next thing arrives from the right, the last
    /// thing leaves to the left. Pure movement, no fade mixed in.
    static let surface = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing),
        removal: .move(edge: .leading))
    /// The same duration as a NUMBER, for the seven places that must
    /// wait for the motion to land before swapping or unmounting what is
    /// underneath — the calendar's month pager, the chrome's settle
    /// window, and every sheet's teardown. Two literals would drift.
    ///
    /// 0.30 since the curve became a spring. At 0.22 an ease and a
    /// spring read about the same, which is to say too fast to have any
    /// weight; a spring wants a little longer to show its shape.
    static let navSeconds: Double = 0.30

    /// A ROW ARRIVING OR LEAVING A LIST.
    ///
    /// Ticking a suggestion in the Inbox used to make it vanish and the
    /// rows below it jump up a notch — the list simply redrew. Every
    /// reference animates that: Todoist slides the row out and closes
    /// the gap behind it, and the motion is what tells you the tick
    /// landed on the row you aimed at.
    ///
    /// A spring, not an easing, and a gentle one: `response` is the time
    /// it takes to cover the distance, `damping` at 0.86 settles without
    /// visible bounce. Slower than `nav` on purpose — a list closing a
    /// gap is a small event that should read as physical, where
    /// navigation should get out of the way.
    static let list = Animation.spring(response: 0.34, dampingFraction: 0.86)

    /// A SELECTION MARK MOVING between the things it can mark — the
    /// lens underline, the day strip's rule, a filter chip's fill. Quick
    /// and tight: the mark should arrive about when your finger lifts.
    static let pick = Animation.spring(response: 0.28, dampingFraction: 0.9)
}

/// THE PALETTE, ONCE — every colour the app has, as a dark/light pair.
///
/// THE SURFACE PASS OF 2026-08-30. The file above has predicted this
/// twice: "when the surface pass comes, it changes the right-hand side
/// of these lines and nothing else", and the self-check's own promise
/// that "when the surface pass makes the palette ours again, the ink
/// floor goes back to 7:1 and marks get a 3:1 floor". Both are kept
/// below. What changed is that the colours are now CHOSEN.
///
/// They were the system's semantic set, and the owner has rejected that
/// (2026-08-30: "avoid gradients, default/system-looking colors,
/// arbitrary colors"). Nothing here is arbitrary either — every number
/// was measured off the three reference recordings in
/// `~/Desktop/Throwaway/new` (Todoist, Notion Calendar, Anytype), by
/// counting pixels rather than by eye:
///
///   GROUND. Todoist #1D1D1D, Anytype #1A1A1C, Notion #222222 — all
///   neutral, all lifted off black. Ours is #1A1A1A, and it is NEUTRAL:
///   the system's dark ground is #1C1C1E, which carries a blue cast
///   (blue two points over red) that tints every grey in the app.
///
///   ELEVATION. Each reference steps about +9 per channel to raise a
///   sheet. #1A1A1A → #232323 → #2C2C2E. Three steps, no shadow, no
///   gradient — a step of tone does it, flat.
///
///   INK. Todoist's secondary text is #9D9D9D, Anytype's #8D8D8F. Ours
///   is #A5A5A5, one notch up, which is what 7:1 on this ground costs.
///
///   COLOUR IS ALMOST ABSENT. Measured across the frames: saturated
///   pixels are 0.58% of a Todoist screen, 0.31% of Notion Calendar's,
///   0.01% of Anytype's. Liv's Today was 1.05% and Tasks 1.85% — two to
///   six times as loud — and every one of Liv's colours was at 100%
///   saturation, where the loudest routine colour in any reference is
///   Todoist's red at 57%. So no colour here exceeds 62%, and the marks
///   are drawn small.
///
/// Both schemes are checked by `livPaletteSelfCheck`: every ink clears
/// 4.5:1 on its ground (the two read tiers clear 7:1), every mark clears
/// 3:1, and no two marks sit within 0.12 of each other in RGB.
private enum Palette {
    // Ground and elevation.
    static let canvas = hex(0x1A1A1A, light: 0xFFFFFF)
    static let surface = hex(0x232323, light: 0xF6F6F6)
    static let fill = hex(0x2C2C2C, light: 0xEDEDED)
    static let selection = hex(0x242424, light: 0xF1F1F1)
    static let hairline = hex(0x2E2E2E, light: 0xE4E4E4)
    static let hairline2 = hex(0x3A3A3A, light: 0xD3D3D3)

    // Ink. Three tiers and no more.
    static let text = hex(0xF5F5F5, light: 0x161616)   // 15.96:1 / 18.10:1
    static let text2 = hex(0xA5A5A5, light: 0x575757)  //  7.07:1 /  7.23:1
    static let text3 = hex(0x828282, light: 0x757575)  //  4.53:1 /  4.61:1

    // The one live colour, and the kind marks. Hue/saturation/lightness
    // are spread so that no two read alike in either scheme — the search
    // that placed them is the reason `task` is violet-blue rather than
    // sitting on top of the accent.
    static let accent = hex(0x5B8BC2, light: 0x3167A5)
    static let onAccent = UIColor.white
    static let violet = hex(0xC698D7, light: 0xA63DAE)  // a note
    static let indigo = hex(0x9277CF, light: 0x644AC9)  // a task
    static let teal = hex(0x47B8A9, light: 0x1F7A6E)    // an event
    static let orange = hex(0xCF6A30, light: 0xB64D20)  // a file, a link
    static let pink = hex(0xD27FA3, light: 0xAD3468)    // a person
    static let yellow = hex(0xE4DA95, light: 0x81710E)  // a capture
    static let red = hex(0xD1575B, light: 0xB42D31)
    static let green = hex(0x51B87E, light: 0x257447)
    static let amber = hex(0xD29C56, light: 0x9F6923)

    // THE CAMERA'S CHROME, and the reason it does not flip.
    //
    // A live viewfinder is whatever the lens is pointing at, so a
    // control over it cannot take its ground from the app's scheme —
    // there is no scheme out there. These two are scheme-INVARIANT for
    // the same reason `onAccent` is: what they sit on is fixed.
    //
    // The dark was `cameraChromeFill` in Camera.swift until 2026-09-07,
    // a hand-mixed green-cast near-black defined in a feature file. Its
    // argument was sound and its home was not (standing rule 3).
    static let cameraChrome = hex(0x1B2220)
    /// Ink on the viewfinder. Deliberately the SAME white as `onAccent`
    /// rather than a second one — two whites is the two-lists-held-true-
    /// by-a-comment shape `LivInk` exists to have removed.
    static let cameraInk = onAccent
}

/// The same tokens at the UIColor level, for the UIKit text stack (the
/// markdown editor draws with TextKit, which never sees SwiftUI Color).
///
/// They no longer MIRROR LivTheme — they read the same `Palette`, so the
/// two cannot drift. The old pair was two lists of system colours held
/// in agreement by a comment asking the next person to remember
/// (standing rule 4: one grammar, one parser).
enum LivInk {
    static let accent = Palette.accent
    static let onAccent = Palette.onAccent
    static let surface = Palette.surface
    static let panel2 = Palette.fill
    static let text = Palette.text
    static let text2 = Palette.text2
    static let text3 = Palette.text3
    static let muted = Palette.text2
    static let border = Palette.hairline
    /// Style-panel key fill — kept for any full-size key surface.
    static let keyFill = Palette.fill
}

enum LivTheme {
    // EVERY COLOUR IN THE APP, AND EVERY ONE OF THEM CHOSEN. The values
    // are in `Palette` above, with the measurements they came from.
    //
    // This block said "SYSTEM COLOURS, on purpose" until 2026-09-05,
    // quoting the owner's 2026-08-15 "revert colors and faces to as
    // system like as possible" — three lines above `accent`, which has
    // read "ONE live colour, and it is ours" since the surface pass of
    // 2026-08-30. A comment that contradicts the line under it is worse
    // than no comment: it is the file telling you the opposite of what
    // the code does.
    //
    // The history it recorded is worth keeping, because it is the reason
    // the pass waited. An icon-derived palette was tried FIRST and
    // reverted — not wrong, early: a bespoke surface pays off once the
    // app's shapes have settled, and until then it is a second thing to
    // keep true on every screen. The system's set held the place while
    // the shapes moved. When they stopped, the owner asked for the
    // surface that sentence had deferred.
    //
    // The names below never changed through any of it, which is the
    // whole reason colour lives in a type here (standing rule 3).

    /// The app's tint — ONE live colour, and it is ours. A muted denim
    /// (H212 S46 L56 in dark), not the device's blue: the system tint is
    /// what "default-looking" means, and it also changes underneath the
    /// app when the owner of the phone picks a different one.
    static let accent = Color(Palette.accent)
    /// A wash of the tint, mixed INTO the ground rather than laid over
    /// it at an opacity — see `tint(_:_:)` below for why.
    static let accentSoft = tint(Color(Palette.accent), 0.18)
    /// A note's own colour. VIOLET, well away from the tint's blue: a
    /// thing and the chrome that acts on it must never say the same
    /// word, and the palette self-check holds us to it.
    static let noteViolet = Color(Palette.violet)
    /// Ink ON the tint — a filled button, a lit toggle. White clears 3:1
    /// on both schemes' accent now (3.51:1 dark, 5.81:1 light), so this
    /// is one colour instead of the scheme-flipping pair it needed while
    /// the tint was the system's pale blue.
    static let onAccent = Color(Palette.onAccent)

    /// The camera's two, which do not flip with the scheme — see
    /// `Palette.cameraChrome` for why a viewfinder has no scheme.
    static let cameraChrome = Color(Palette.cameraChrome)
    static let cameraInk = Color(Palette.cameraInk)

    // ELEVATION, the system's ramp (surface pass, owner 2026-08-18: the
    // left panel "should feel like a panel, not a view or a curtain…
    // distinct from the main canvas, but not pitch black"). Three steps
    // and no more: the ground, the raised surface a panel or a card
    // stands on, and a fill for the small stuff. Nothing in this app
    // uses a shadow or a gradient to say "raised" — a step of tone does
    // it, flat.
    //
    // The panel read as a curtain because it was painted in `canvas`:
    // the same black as the thing it covered, so only motion told them
    // apart.
    /// THE RAMP IS SHIFTED ONE STEP UP IN DARK, and only in dark.
    ///
    /// The system's `.systemBackground` is #000000 in dark — night
    /// black. The owner rejected it (2026-08-28: "Screw the night black
    /// in desk. Dark mode is too dark."), and it was always the odd one
    /// out: every surface above it is a lifted grey, so the ground being
    /// absolute black made the app look like two different materials.
    ///
    /// Rather than mix a value, each token takes the NEXT rung of the
    /// system's own dark ramp (#000 → #1C1C1E → #2C2C2E). The steps
    /// between them are unchanged, so nothing that depended on one
    /// surface reading as raised above another has moved; light is
    /// untouched, where white is already the right ground.
    static let canvas = Color(Palette.canvas)
    static let surface = Color(Palette.surface)
    static let panel = Color(Palette.surface)
    /// A quiet fill for a lit row, a chip, a well — never a border.
    static let panel2 = Color(Palette.fill)
    /// The lightest possible mark of "this row is the one you are on".
    /// One step off the ground, and nothing else: the references mark a
    /// selected row with weight or a tick, never with a coloured band.
    static let selection = Color(Palette.selection)
    /// A row UNDER THE FINGER. Measured 2026-08-20: the app had no
    /// custom button style anywhere, and eight row sites used
    /// `.onTapGesture`, which gives no feedback at all — a tap either
    /// worked or seemed not to. Every app in the owner's reference set
    /// answers a touch before it acts.
    static let pressed = Color(Palette.fill)

    // THREE ink tiers, not four. `muted` was a second name for `text2`
    // and both were `.secondaryLabel`; it stays as an alias so the call
    // sites need not all move at once, but there is one value.
    static let text = Color(Palette.text)
    static let text2 = Color(Palette.text2)
    static let text3 = Color(Palette.text3)
    static let muted = Color(Palette.text2)
    /// A hairline, and it is meant to be nearly invisible: #2E2E2E on
    /// #1A1A1A is the same whisper the references draw. A separator you
    /// can see across the room is a border, and this app does not draw
    /// borders.
    static let border = Color(Palette.hairline)
    static let border2 = Color(Palette.hairline2)

    // The semantic set — the ONLY value colours (O2: VALUE_HEX retired).
    // Each is the muted shade of that word: none exceeds 62% saturation,
    // against the system set's 85–100%.
    static let green = Color(Palette.green)
    static let red = Color(Palette.red)
    static let amber = Color(Palette.amber)
    /// A TASK's colour, kept under the old name's slot: violet-blue, and
    /// deliberately far from both the accent and a note's violet — the
    /// three were within a hair of each other when they were the
    /// system's blue, indigo and purple.
    static let purple = Color(Palette.indigo)
    // The rest of the KIND language (blueprints, 2026-08-12).
    static let teal = Color(Palette.teal)
    static let orange = Color(Palette.orange)
    static let pink = Color(Palette.pink)
    static let yellow = Color(Palette.yellow)

    /// A tint that is a COLOUR, not a translucency.
    ///
    /// Soft fills used to be `accent.opacity(0.16)` and friends, which is
    /// the machine-made look in one line: the hue drifts with whatever is
    /// behind it, and nothing was ever chosen. This mixes the hue INTO
    /// the ground once and hands back an opaque colour, per scheme.
    static func tint(_ color: Color, _ amount: CGFloat = 0.22) -> Color {
        Color(
            UIColor { traits in
                let ink = UIColor(color).resolvedColor(with: traits)
                let ground = UIColor(canvas).resolvedColor(with: traits)
                var ir: CGFloat = 0, ig: CGFloat = 0, ib: CGFloat = 0, ia: CGFloat = 0
                var gr: CGFloat = 0, gg: CGFloat = 0, gb: CGFloat = 0, ga: CGFloat = 0
                ink.getRed(&ir, green: &ig, blue: &ib, alpha: &ia)
                ground.getRed(&gr, green: &gg, blue: &gb, alpha: &ga)
                return UIColor(
                    red: gr + (ir - gr) * amount,
                    green: gg + (ig - gg) * amount,
                    blue: gb + (ib - gb) * amount,
                    alpha: 1)
            })
    }

    /// THE ONE SHADOW, and it is only for something a finger has picked
    /// up and is moving.
    ///
    /// This file says two hundred lines above that "nothing in this app
    /// uses a shadow or a gradient to say raised — a step of tone does
    /// it, flat", and on 2026-08-30 there were six shadows in five
    /// different recipes, two of them byte-identical copies in different
    /// files. Three were deleted (a chip, its duplicate, a pill: each
    /// already had a fill and a hairline, which is enough separation on
    /// this ground). The desk keeps its own, measured off the panel
    /// reference and living in `LivPanel`. What is left is this: a block
    /// being DRAGGED, where the shadow is not decoration but the whole
    /// point — it is what says the thing has left the surface.
    static let lift = (color: Color.black.opacity(0.45), radius: 10.0, y: 4.0)

    static let radius: CGFloat = 10
    static let radiusSm: CGFloat = 6
    /// A SMALL CARD — a count tile, a tab on the desk. Between `radius`
    /// and `radiusLg` because it is neither a control nor a sheet: it is
    /// a card you can pick up.
    ///
    /// It was a hand-typed 12 in nine places (three in `Kit`, six in
    /// `Tabs`) sitting beside the three named radii, which is how a
    /// fourth radius starts.
    static let radiusCard: CGFloat = 12
    /// A surface laid OVER another one — the slide-up menus, the
    /// properties card. Big enough to read as a separate sheet at a
    /// glance, which is the whole job of it.
    static let radiusLg: CGFloat = 22
}

// MARK: - Hue — the stable value→dot assignment

// FNV-1a 64 over NFC-normalized UTF-8 (ported VERBATIM from the desktop's
// Hues.swift — offset 0xcbf29ce484222325, prime 0x100000001b3; no case
// folding, no trimming: the input IS the display string). Chips render
// NEUTRAL; the value's color is ONLY the small leading dot, drawn from the
// closed semantic set mod 5 (O2).
//
// FROZEN VECTORS (R3 hash identity, mod 9 — bit-identical to the desktop):
//   "SSK" → 5 · "thesis" → 7 · "climbing" → 0 · "invoices" → 2
//   "Steven" → 5 · "warranty" → 1 · "tournament" → 6 · "Anna" → 0
//   "physics" → 3 · "" → 5
// Same hashes mod 5 into [purple, green, amber, red, accent] (this set):
//   "SSK" → 0 purple · "thesis" → 4 accent · "climbing" → 2 amber
//   "invoices" → 0 purple · "Steven" → 2 amber · "warranty" → 4 accent
//   "tournament" → 3 red · "Anna" → 0 purple · "physics" → 0 purple
//   "" → 2 amber
// The KIND colors live with the kind itself, in `LivKind`
// (Glyph.swift): a kind's color and its drawing are one decision, and
// splitting them is what let a task draw a blue chip with a tick in it.

// `Hue` IS GONE (2026-08-29). It hashed a display string to one of five
// colours, stable per word — and its own doc admitted that meant
// "nothing beyond 'these two say the same thing'".
//
// A coloured dot is read as a signal. Five hues down a list of property
// names is a code with nothing to decode, and at 6pt in an otherwise
// grey app it was the loudest thing on the screen. Colour now appears
// only where it carries something: a KIND (a note is violet, a task
// indigo) and a status option's own hue, which a person chose.
