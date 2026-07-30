// liv iOS — tokens (design/ios.md §7). The desktop ThemeSpec ported 1:1 to
// UIColor(dynamicProvider:); brand-light/brand-dark ride the SYSTEM scheme —
// no theme engine on the phone. Neutrals re-derived toward neutral-green
// (the phone wears lake green, not the desktop's violet-leaning greys).
// Amber is reserved app-wide for AI presence. Never violet/blue accents.

import SwiftUI
import UIKit

private func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha)
}

/// One token = a light/dark pair resolved at draw time.
private func dyn(_ light: UIColor, _ dark: UIColor) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}

/// The same tokens at the UIColor level, for the UIKit text stack (the
/// markdown editor draws with TextKit, which never sees SwiftUI Color).
/// Same hex pairs as LivTheme — add here only what the editor needs.
enum LivInk {
    static func pair(_ light: UIColor, _ dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    static let accent = pair(hex(0x2F7D6B), hex(0x5CB596))
    static let onAccent = pair(hex(0xFFFFFF), hex(0x0B1310))
    static let surface = pair(hex(0xFFFFFF), hex(0x1A2220))
    static let panel2 = pair(hex(0xEAEEEA), hex(0x1D2622))
    static let text = pair(hex(0x17201B), hex(0xEAF0EC))
    static let text2 = pair(hex(0x45514A), hex(0xBFCCC4))
    static let text3 = pair(hex(0x67736C), hex(0x9FADA4))
    static let muted = pair(hex(0x96A09A), hex(0x66746C))
    static let border = pair(hex(0x000000, 0.10), hex(0xFFFFFF, 0.09))
}

enum LivTheme {
    // Accent: lake green — #2F7D6B light / #5CB596 dark (owner-decided).
    static let accent = dyn(hex(0x2F7D6B), hex(0x5CB596))
    static let accentSoft = dyn(hex(0xE2EFEA), hex(0x5CB596, 0.16))
    static let onAccent = dyn(hex(0xFFFFFF), hex(0x0B1310))

    // Elevation is tonal — canvas behind cards, surface for cards/tiles,
    // panel for wells, panel2 for chips/small fills.
    static let canvas = dyn(hex(0xF1F3F1), hex(0x12171A))
    static let surface = dyn(hex(0xFFFFFF), hex(0x1A2220))
    static let panel = dyn(hex(0xF2F4F2), hex(0x151C19))
    static let panel2 = dyn(hex(0xEAEEEA), hex(0x1D2622))

    // The four text tiers + hairlines.
    static let text = dyn(hex(0x17201B), hex(0xEAF0EC))
    static let text2 = dyn(hex(0x45514A), hex(0xBFCCC4))
    static let text3 = dyn(hex(0x67736C), hex(0x9FADA4))
    static let muted = dyn(hex(0x96A09A), hex(0x66746C))
    static let border = dyn(hex(0x000000, 0.10), hex(0xFFFFFF, 0.09))
    static let border2 = dyn(hex(0x000000, 0.16), hex(0xFFFFFF, 0.15))

    // The semantic set — the ONLY value colors (O2: VALUE_HEX retired).
    static let green = dyn(hex(0x2F7A63), hex(0x97C459))
    static let red = dyn(hex(0xC0392B), hex(0xF09595))
    static let amber = dyn(hex(0xF6A823), hex(0xF6A823))
    static let purple = dyn(hex(0x9334E6), hex(0xC99BF5))

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
