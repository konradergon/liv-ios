// liv iOS — tokens (design/ios.md §7). Dark is the house look; a LIGHT
// twin arrived 2026-08-07 (owner: "add light mode") — every token is a
// dark/light pair resolved by the system's appearance machinery, and a
// Settings row picks Dark, Light, or System.
//
// THE COLOURS ARE THE SYSTEM'S (owner, 2026-08-15: "revert colors and
// faces to as system like as possible… we should do the surface
// appearance last and thoroughly"). An icon-derived palette — violet,
// pink, amber, measured to a 7:1 floor — came first and was reverted;
// the paragraph describing it lived on at the top of this file for five
// days after the code below stopped doing it, which is what a comment
// that outlives its code looks like.
//
// THE SURFACE PASS ARRIVED 2026-08-20, and it is the one this file
// predicted: "when the surface pass comes, it changes the right-hand
// side of these lines and nothing else". It did not repaint anything.
// It gave the app the shapes its reference set shares — a card, one
// row, one hairline inset, a press state — because measuring showed
// the app's roughness was never the colours; it was thirteen row
// recipes with five heights and five separator insets.
//
// `livPaletteSelfCheck` still measures contrast rather than trusting
// anyone's eye.

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

/// One consistent motion for the whole app (owner, 2026-07-31): navigation
/// areas move from and into view — nothing rotates, nothing fades in
/// combination, nothing springs. One curve, one duration, everywhere.
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
    // THE PLATFORM'S SCALE (owner, 2026-08-18: "ui text is just too
    // small throughout, and dimmed"). The app was reading a full step
    // under iOS: our `body` was 15, which is the system's *subheadline*,
    // and every list row, button and value sat on it. These are Apple's
    // own sizes now — body 17, subheadline 15, footnote 13 — so the app
    // reads like the rest of the phone instead of like a dense
    // desktop tool shrunk onto it.
    //
    /// A badge, the ✕ on a chip — never a word you have to read.
    static let micro: CGFloat = 11
    /// Chips, stamps, counts.
    static let caption: CGFloat = 13
    /// Uppercase section labels, secondary detail.
    static let label: CGFloat = 15
    /// The app's ORDINARY text: list rows, values, buttons. iOS body.
    static let body: CGFloat = 17
    /// Emphasised rows, the create-menu verbs.
    static let strong: CGFloat = 18
    /// Screen and sheet titles.
    static let title: CGFloat = 20
    /// An entity's name in the properties panel.
    static let display: CGFloat = 24
    /// A record's name field.
    static let hero: CGFloat = 28
}

/// Row metrics. A list row was 46pt when its text was 11–13; the type
/// scale went up on 2026-08-10 and the rows had to go with it, or the
/// bigger text would simply be more cramped in the same box (owner:
/// "UI in the property panel is cramped towards the top when almost half
/// of the panel is empty").
enum LivRow {
    /// An ordinary list row: a label, a value, a chevron. 54 was the
    /// number when a row's text was 16–18 and every row had a hairline
    /// under it; the surface pass took the hairlines out of content
    /// lists and the rows came down with them (owner, 2026-08-18:
    /// "maximize simplicity… quiet, effortless").
    static let height: CGFloat = 52
    /// A row carrying a title and a second line under it.
    static let tall: CGFloat = 62
    /// The band the top chrome owns: the two door circles and the
    /// workspace button centred between them. ANYTHING that speaks at
    /// the top of the screen — a banner, a notice, an acknowledgment —
    /// starts below this, or it lands on the workspace's own name
    /// (owner, 2026-08-15: "the message is on top of each other").
    static let topChrome: CGFloat = 52

    /// WHERE A HAIRLINE STARTS — at the text, past the glyph column.
    /// Measured 2026-08-20: the app drew its row separators at five
    /// different insets (36, 32, 31, full width, none) across thirteen
    /// hand-rolled row recipes, which is why a list and a menu never
    /// looked like the same app. One number now.
    static let hairline: CGFloat = 36

    /// The gap a CARD leaves at the screen's edges. A card is how the
    /// reference apps group rows — Apple Notes, Obsidian's overflow
    /// sheet and ChatGPT's settings all put related rows on a raised
    /// panel with a quiet label above it, rather than running hairlines
    /// edge to edge (owner's clips, 2026-08-20).
    static let cardInset: CGFloat = 16

    /// The room a section heading owns. It used to own none, so all
    /// twenty-eight call sites supplied their own and disagreed ten
    /// ways (10/14/16/18/22 above, 0/2/4/6 below).
    static let sectionTop: CGFloat = 18
    static let sectionBottom: CGFloat = 6

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
enum LivBar {
    static let height: CGFloat = 50
    /// The breath between the bar and the screen's bottom edge.
    static let gap: CGFloat = 4
    /// From the bottom of the SCREEN to the top of the bar.
    static var clearance: CGFloat { height + gap + LivSafeArea.bottom }
}

enum LivMotion {
    static let nav = Animation.easeInOut(duration: navSeconds)

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
    /// The same duration as a NUMBER, for the one case that must wait
    /// for the motion to land before swapping what is underneath (the
    /// calendar's month pager). Two literals would drift.
    static let navSeconds: Double = 0.22
}

/// The same tokens at the UIColor level, for the UIKit text stack (the
/// markdown editor draws with TextKit, which never sees SwiftUI Color).
///
/// These MIRROR LivTheme's values exactly; when one moves, the other
/// moves in the same change.
enum LivInk {
    static let accent = UIColor.tintColor
    static let onAccent = UIColor.white
    static let surface = UIColor.secondarySystemBackground
    static let panel2 = UIColor.tertiarySystemFill
    static let text = UIColor.label
    static let text2 = UIColor.secondaryLabel
    static let text3 = UIColor.tertiaryLabel
    static let muted = UIColor.secondaryLabel
    static let border = UIColor.separator
    /// Style-panel key fill — kept for any full-size key surface.
    static let keyFill = UIColor.tertiarySystemFill
}

enum LivTheme {
    // SYSTEM COLOURS, on purpose (owner, 2026-08-15: "revert colors and
    // faces to as system like as possible… we should do the surface
    // appearance last and thoroughly").
    //
    // What this replaces: a palette derived from the app icon — a violet
    // accent, a near-black ground, a hand-mixed kind set, all measured to
    // a 7:1 floor. It was not wrong, it was EARLY: a bespoke surface
    // pays off once the app's shapes have settled, and until then it is
    // a second thing to keep true on every screen. The system's own
    // semantic colours cost nothing to keep true, adapt to light, dark,
    // increased contrast and accessibility tints for free, and read as
    // "an iOS app" rather than as a look someone chose in a hurry.
    //
    // The names below stay. When the surface pass comes, it changes the
    // right-hand side of these lines and nothing else — which is the
    // whole reason colour lives in a type here (standing rule 3).

    /// The app's tint: the system's, which follows the device.
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.15)
    /// A note's own colour. PURPLE, not the tint's own blue family: a
    /// thing and the chrome that acts on it must never say the same
    /// word, and the palette self-check holds us to it.
    static let noteViolet = Color(.systemPurple)
    /// Ink ON the tint — a filled button, a lit toggle. White on the
    /// light-blue dark-mode tint reads at 3.2:1, so the dark scheme puts
    /// black there instead and both clear the floor.
    static let onAccent = Color(
        UIColor { $0.userInterfaceStyle == .light ? .white : .black })

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
    static let canvas = Color(.systemBackground)
    static let surface = Color(.secondarySystemBackground)
    static let panel = Color(.secondarySystemBackground)
    /// A quiet fill for a lit row, a chip, a well — never a border.
    static let panel2 = Color(.tertiarySystemFill)
    /// The lightest possible mark of "this row is the one you are on".
    static let selection = Color(.quaternarySystemFill)
    /// A row UNDER THE FINGER. Measured 2026-08-20: the app had no
    /// custom button style anywhere, and eight row sites used
    /// `.onTapGesture`, which gives no feedback at all — a tap either
    /// worked or seemed not to. Every app in the owner's reference set
    /// answers a touch before it acts.
    static let pressed = Color(.quaternarySystemFill)

    // The four text tiers + hairlines, the system's own.
    static let text = Color(.label)
    static let text2 = Color(.secondaryLabel)
    static let text3 = Color(.tertiaryLabel)
    static let muted = Color(.secondaryLabel)
    static let border = Color(.separator)
    static let border2 = Color(.opaqueSeparator)

    // The semantic set — the ONLY value colors (O2: VALUE_HEX retired),
    // each the system's shade of that word.
    static let green = Color(.systemGreen)
    static let red = Color(.systemRed)
    static let amber = Color(.systemOrange)
    /// Indigo, kept under the old name's slot: a TASK's colour, one
    /// step from a note's purple.
    static let purple = Color(.systemIndigo)
    // The rest of the KIND language (blueprints, 2026-08-12).
    static let teal = Color(.systemTeal)
    static let orange = Color(.systemOrange)
    static let pink = Color(.systemPink)
    static let yellow = Color(.systemYellow)

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

    static let radius: CGFloat = 10
    static let radiusSm: CGFloat = 6
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

enum Hue {
    static func hash(_ display: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in display.precomposedStringWithCanonicalMapping.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }

    /// Five steps around the icon's three arms — violet, pink, amber and
    /// the light ends of two of them. It used to be Apple's semantic five
    /// (purple, green, amber, red, blue), which put a green and a system
    /// blue on screen that exist nowhere in the mark.
    private static let set: [Color] = [
        LivTheme.noteViolet, LivTheme.purple, LivTheme.amber, LivTheme.pink,
        LivTheme.orange,
    ]

    /// A display string's dot color — stable per string, semantic set only.
    static func dot(_ display: String) -> Color {
        set[Int(hash(display) % UInt64(set.count))]
    }
}
