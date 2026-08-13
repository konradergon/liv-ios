// liv iOS — tokens (design/ios.md §7). Dark is the house look; a LIGHT
// twin arrived 2026-08-07 (owner: "add light mode") — every token is a
// dark/light pair resolved by the system's appearance machinery, and a
// Settings row picks Dark, Light, or System. The lake-green identity
// stays retired; the system blue is the one accent; amber stays
// reserved app-wide for AI presence.

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
    static let accent = hex(0x0A84FF, light: 0x007AFF)
    static let onAccent = hex(0xFFFFFF)
    static let surface = hex(0x1E1E20, light: 0xFFFFFF)
    static let panel2 = hex(0x2C2C2E, light: 0xE5E5EA)
    static let text = hex(0xF5F5F7, light: 0x1C1C1E)
    static let text2 = hex(0xC9C9CE, light: 0x3A3A3C)
    static let text3 = hex(0x9A9AA2, light: 0x6E6E73)
    static let muted = hex(0x8E8E93)
    static let border = hex(0xFFFFFF, 0.10, light: 0x000000, lightAlpha: 0.12)
    /// Style-panel key fill — kept for any full-size key surface.
    static let keyFill = hex(0x2C2C2E, light: 0xE5E5EA)
}

enum LivTheme {
    // The one accent: the system blue, in each scheme's own shade.
    static let accent = solid(0x0A84FF, light: 0x007AFF)
    static let accentSoft = solid(0x0A84FF, 0.18, light: 0x007AFF)
    static let onAccent = solid(0xFFFFFF)

    // Elevation is tonal — canvas behind everything, surface for cards,
    // panel for wells, panel2 for chips/small fills. Light inverts the
    // ramp: white canvas, grouped greys for wells.
    static let canvas = solid(0x161618, light: 0xFFFFFF)
    static let surface = solid(0x1E1E20, light: 0xFFFFFF)
    static let panel = solid(0x242426, light: 0xF2F2F7)
    static let panel2 = solid(0x2C2C2E, light: 0xE5E5EA)

    // The four text tiers + hairlines.
    static let text = solid(0xF5F5F7, light: 0x1C1C1E)
    static let text2 = solid(0xC9C9CE, light: 0x3A3A3C)
    static let text3 = solid(0x9A9AA2, light: 0x6E6E73)
    // #707078 read at 3.7:1 against the canvas — under the 4.5:1
    // readability minimum. #8E8E93 clears it on both canvases.
    static let muted = solid(0x8E8E93)
    static let border = solid(0xFFFFFF, 0.10, light: 0x000000, lightAlpha: 0.12)
    static let border2 = solid(0xFFFFFF, 0.16, light: 0x000000, lightAlpha: 0.18)

    // The semantic set — the ONLY value colors (O2: VALUE_HEX retired),
    // each in its scheme's own shade.
    static let green = solid(0x30D158, light: 0x34C759)
    static let red = solid(0xFF453A, light: 0xFF3B30)
    static let amber = solid(0xFFB340, light: 0xF5A623)
    static let purple = solid(0xBF5AF2, light: 0xAF52DE)
    // The rest of the KIND language (blueprints, 2026-08-12).
    static let teal = solid(0x64D2FF, light: 0x32ADE6)
    static let orange = solid(0xFF9F0A, light: 0xFF9500)
    static let pink = solid(0xFF375F, light: 0xFF2D55)
    static let yellow = solid(0xFFD60A, light: 0xFFCC00)
    static let gray = solid(0x98989D, light: 0x8E8E93)

    static let radius: CGFloat = 10
    static let radiusSm: CGFloat = 6
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

    private static let set: [Color] = [
        LivTheme.purple, LivTheme.green, LivTheme.amber, LivTheme.red,
        LivTheme.accent,
    ]

    /// A display string's dot color — stable per string, semantic set only.
    static func dot(_ display: String) -> Color {
        set[Int(hash(display) % UInt64(set.count))]
    }
}
