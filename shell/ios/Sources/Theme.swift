// liv iOS — tokens (design/ios.md §7). Dark is the house look; a LIGHT
// twin arrived 2026-08-07 (owner: "add light mode") — every token is a
// dark/light pair resolved by the system's appearance machinery, and a
// Settings row picks Dark, Light, or System.
//
// THE PALETTE COMES FROM THE APP ICON (owner, 2026-08-15). The icon is
// three arms of dots, each one hue running light to dark: VIOLET, PINK,
// AMBER. The app uses them the same way — violet for chrome and notes,
// pink for tasks and people, amber for events, files and captures. There
// is no blue and no cyan anywhere, because there is none in the mark.
//
// And it is built to a CONTRAST FLOOR, the one thing worth taking from
// the Modus themes (owner brought them for exactly this): every colour
// here clears 7:1 against the ground it sits on, in BOTH schemes. The
// old set was Apple's system colours, where six of thirteen sat under
// that and the accent — every link and every button label — was the
// worst thing on screen at 4.95:1. `livPaletteSelfCheck` measures it now
// rather than trusting anyone's eye.

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
    /// was 7.5–9.5 · glyph badges, a card's kind footer, the ✕ on a chip
    static let micro: CGFloat = 10.5
    /// was 10–10.5 · chips, stamps, counts
    static let caption: CGFloat = 12
    /// was 11–11.5 · uppercase field labels, secondary detail
    static let label: CGFloat = 13
    /// was 12–13.5 · the app's ORDINARY text: list rows, values, buttons
    static let body: CGFloat = 15
    /// was 14–15 · emphasised rows, the create-menu verbs
    static let strong: CGFloat = 16
    /// was 16–17 · screen and sheet titles
    static let title: CGFloat = 18
    /// was 19–20 · an entity's name in the properties panel
    static let display: CGFloat = 22
    /// was 24 · a record's name field
    static let hero: CGFloat = 26
}

/// Row metrics. A list row was 46pt when its text was 11–13; the type
/// scale went up on 2026-08-10 and the rows had to go with it, or the
/// bigger text would simply be more cramped in the same box (owner:
/// "UI in the property panel is cramped towards the top when almost half
/// of the panel is empty").
enum LivRow {
    /// An ordinary list row: a label, a value, a chevron.
    static let height: CGFloat = 54
    /// A row carrying a title and a second line under it.
    static let tall: CGFloat = 58
    /// The band the top chrome owns: the two door circles and the
    /// workspace button centred between them. ANYTHING that speaks at
    /// the top of the screen — a banner, a notice, an acknowledgment —
    /// starts below this, or it lands on the workspace's own name
    /// (owner, 2026-08-15: "the message is on top of each other").
    static let topChrome: CGFloat = 56
}

enum LivMotion {
    static let nav = Animation.easeInOut(duration: navSeconds)
    /// The same duration as a NUMBER, for the one case that must wait
    /// for the motion to land before swapping what is underneath (the
    /// calendar's month pager). Two literals would drift.
    static let navSeconds: Double = 0.22
}

/// The same tokens at the UIColor level, for the UIKit text stack (the
/// markdown editor draws with TextKit, which never sees SwiftUI Color).
enum LivInk {
    static let accent = hex(0xB9ADFF, light: 0x4B3BC4)
    static let onAccent = hex(0x08070A, light: 0xFFFFFF)
    static let surface = hex(0x141118, light: 0xFFFFFF)
    static let panel2 = hex(0x262130, light: 0xE9E5F0)
    static let text = hex(0xFFFFFF, light: 0x14121A)
    static let text2 = hex(0xDCD6E8, light: 0x3C3648)
    static let text3 = hex(0xB4ACC4, light: 0x5C5570)
    static let muted = hex(0xB4ACC4, light: 0x5C5570)
    static let border = hex(0xFFFFFF, 0.10, light: 0x000000, lightAlpha: 0.12)
    /// Style-panel key fill — kept for any full-size key surface.
    static let keyFill = hex(0x262130, light: 0xE9E5F0)
}

enum LivTheme {
    // The one accent: the system blue, in each scheme's own shade.
    static let accent = solid(0xB9ADFF, light: 0x4B3BC4)
    static let accentSoft = tint(accent)
    /// The violet arm ONE STEP DOWN from the accent. A note is the app's
    /// default thing, so it wears the accent's family — but chrome and
    /// content saying the same word was the old palette's flaw, and the
    /// icon's own arms are exactly this: one hue, light to dark.
    static let noteViolet = solid(0xA796FF, light: 0x352A93)
    static let onAccent = solid(0x08070A, light: 0xFFFFFF)

    // Elevation is tonal — canvas behind everything, surface for cards,
    // panel for wells, panel2 for chips/small fills. Light inverts the
    // ramp: white canvas, grouped greys for wells.
    static let canvas = solid(0x08070A, light: 0xFFFFFF)
    static let surface = solid(0x141118, light: 0xFFFFFF)
    static let panel = solid(0x1C1822, light: 0xF4F2F8)
    static let panel2 = solid(0x262130, light: 0xE9E5F0)

    // The four text tiers + hairlines.
    static let text = solid(0xFFFFFF, light: 0x14121A)
    static let text2 = solid(0xDCD6E8, light: 0x3C3648)
    static let text3 = solid(0xB4ACC4, light: 0x5C5570)
    // #707078 read at 3.7:1 against the canvas — under the 4.5:1
    // readability minimum. #8E8E93 clears it on both canvases.
    static let muted = solid(0xB4ACC4, light: 0x5C5570)
    static let border = solid(0xFFFFFF, 0.10, light: 0x000000, lightAlpha: 0.12)
    static let border2 = solid(0xFFFFFF, 0.16, light: 0x000000, lightAlpha: 0.18)

    // The semantic set — the ONLY value colors (O2: VALUE_HEX retired),
    // each in its scheme's own shade.
    static let green = solid(0x57E39A, light: 0x0B5C36)
    static let red = solid(0xFF7A8A, light: 0x9E1F30)
    static let amber = solid(0xFFB020, light: 0x6B4900)
    static let purple = solid(0xFF6FA8, light: 0xA32450)
    // The rest of the KIND language (blueprints, 2026-08-12).
    static let teal = solid(0xFFB020, light: 0x6B4900)
    static let orange = solid(0xFFD27A, light: 0x5F4A0E)
    static let pink = solid(0xFF9EC4, light: 0x8E3059)
    static let yellow = solid(0xFFE08A, light: 0x5C4E12)

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
