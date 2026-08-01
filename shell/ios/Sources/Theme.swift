// liv iOS — tokens (design/ios.md §7, owner delta 2026-07-31): a generic
// dark theme. The lake-green identity is retired by the owner's word —
// neutral dark greys, the system blue as the one accent, and the app
// renders dark regardless of the system setting (RootView forces the
// scheme). Amber stays reserved app-wide for AI presence.

import SwiftUI
import UIKit

private func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha)
}

private func solid(_ value: UInt32, _ alpha: CGFloat = 1) -> Color {
    Color(hex(value, alpha))
}

/// One consistent motion for the whole app (owner, 2026-07-31): navigation
/// areas move from and into view — nothing rotates, nothing fades in
/// combination, nothing springs. One curve, one duration, everywhere.
enum LivMotion {
    static let nav = Animation.easeInOut(duration: 0.22)
}

/// The same tokens at the UIColor level, for the UIKit text stack (the
/// markdown editor draws with TextKit, which never sees SwiftUI Color).
enum LivInk {
    static let accent = hex(0x0A84FF)
    static let onAccent = hex(0xFFFFFF)
    static let surface = hex(0x1E1E20)
    static let panel2 = hex(0x2C2C2E)
    static let text = hex(0xF5F5F7)
    static let text2 = hex(0xC9C9CE)
    static let text3 = hex(0x9A9AA2)
    static let muted = hex(0x707078)
    static let border = hex(0xFFFFFF, 0.10)
    /// Style-panel key fill — kept for any full-size key surface.
    static let keyFill = hex(0x2C2C2E)
}

enum LivTheme {
    // The one accent: the system blue. Generic on purpose.
    static let accent = solid(0x0A84FF)
    static let accentSoft = solid(0x0A84FF, 0.18)
    static let onAccent = solid(0xFFFFFF)

    // Elevation is tonal — canvas behind everything, surface for cards,
    // panel for wells, panel2 for chips/small fills.
    static let canvas = solid(0x161618)
    static let surface = solid(0x1E1E20)
    static let panel = solid(0x242426)
    static let panel2 = solid(0x2C2C2E)

    // The four text tiers + hairlines.
    static let text = solid(0xF5F5F7)
    static let text2 = solid(0xC9C9CE)
    static let text3 = solid(0x9A9AA2)
    static let muted = solid(0x707078)
    static let border = solid(0xFFFFFF, 0.10)
    static let border2 = solid(0xFFFFFF, 0.16)

    // The semantic set — the ONLY value colors (O2: VALUE_HEX retired).
    static let green = solid(0x30D158)
    static let red = solid(0xFF453A)
    static let amber = solid(0xFFB340)
    static let purple = solid(0xBF5AF2)

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
