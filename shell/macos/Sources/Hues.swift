// lotus — VALUE_HEX (P11.5b, ruling R3): one hash, one table, FROZEN.
//
// Every metadata VALUE everywhere — chips, facets, graph nodes, tree dots —
// derives its hue from the same function, so "SSK is sky-blue" holds across
// every surface by construction. The nine seed colors are byte-identical
// across all blueprint pages; the hash is FNV-1a 64 (trivially portable: if
// a Rust helper ever needs the same hue, the constants copy in one line and
// stay bit-identical). Collisions are allowed by law ("9–12 hues").
//
// FROZEN VECTORS (R3 — changing any of these after this pass is a spec
// break, not a tweak; verified at freeze time by executing this exact
// function against an independent Python FNV-1a — bit-identical):
//   "SSK" → 5 · "thesis" → 7 · "climbing" → 0 · "invoices" → 2
//   "Steven" → 5 · "warranty" → 1 · "tournament" → 6 · "Anna" → 0
//   "physics" → 3 · "" → 5
//
// The color budget (design §5.3): hue always means METADATA VALUE. Dates,
// recurrence, and tier render neutral; status dots use the option's own
// `hue` cell (degrees), never VALUE_HEX; objects render neutral and type is
// an icon. Chips are colorful always-on — there is no toggle.

import AppKit
import SwiftUI

enum Hues {
    /// The nine seeds — theme-independent raw hues (only the chip MIXES
    /// below are scheme-aware). FROZEN (R3).
    static let seed: [NSColor] = [
        NSColor(red: 0xF4 / 255, green: 0x3F / 255, blue: 0x5E / 255, alpha: 1),  // 0 #f43f5e rose
        NSColor(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255, alpha: 1),  // 1 #f59e0b amber
        NSColor(red: 0x0E / 255, green: 0xA5 / 255, blue: 0xE9 / 255, alpha: 1),  // 2 #0ea5e9 sky
        NSColor(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255, alpha: 1),  // 3 #8b5cf6 violet
        NSColor(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255, alpha: 1),  // 4 #f97316 orange
        NSColor(red: 0x06 / 255, green: 0xB6 / 255, blue: 0xD4 / 255, alpha: 1),  // 5 #06b6d4 cyan
        NSColor(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255, alpha: 1),  // 6 #3b82f6 blue
        NSColor(red: 0x84 / 255, green: 0xCC / 255, blue: 0x16 / 255, alpha: 1),  // 7 #84cc16 lime
        NSColor(red: 0xEC / 255, green: 0x48 / 255, blue: 0x99 / 255, alpha: 1),  // 8 #ec4899 pink
    ]

    /// FNV-1a 64 over the NFC-normalized UTF-8 bytes. No case folding, no
    /// trimming — the input IS the display string (lotus_views::display)
    /// exactly as it appears in CellRow.value / distinct values / option
    /// names, so every surface agrees by construction.
    static func hash(_ display: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in display.precomposedStringWithCanonicalMapping.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }

    static func index(_ display: String) -> Int {
        Int(hash(display) % 9)
    }

    /// THE function: a display string's hue.
    static func valueHex(_ display: String) -> NSColor {
        seed[index(display)]
    }

    // ---- the chip mixes (frozen constants beside the hues, design §4.1) ----
    // bg = hue @ 12% (light) / 16% (dark) · border = hue @ 32% ·
    // ink = hue blended 62% (light) / 55% (dark) into the theme ink.

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func chipBackground(_ hue: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            hue.withAlphaComponent(isDark(appearance) ? 0.16 : 0.12)
        })
    }

    static func chipBorder(_ hue: NSColor) -> Color {
        Color(nsColor: hue.withAlphaComponent(0.32))
    }

    static func chipInk(_ hue: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let fraction = isDark(appearance) ? 0.55 : 0.62
            let ink = NSColor.labelColor.resolved(for: appearance)
            return hue.usingColorSpace(.sRGB)?
                .blended(withFraction: 1 - fraction, of: ink) ?? hue
        })
    }

    /// A status option's dot color: the option's `hue` cell in DEGREES,
    /// rendered at a fixed saturation/brightness pair per scheme — NEVER
    /// VALUE_HEX (design §5.3). nil = the neutral dot.
    static func degrees(_ deg: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = isDark(appearance)
            return NSColor(
                hue: CGFloat((deg.truncatingRemainder(dividingBy: 360)) / 360),
                saturation: dark ? 0.45 : 0.55,
                brightness: dark ? 0.75 : 0.62,
                alpha: 1)
        })
    }

    /// The override ladder for any chip/dot (design §5.3): a per-option
    /// `hue` cell wins → else VALUE_HEX of the display → the caller renders
    /// neutral for the never-VALUE_HEX classes itself (dates, recurrence,
    /// tier — neutrality is the call site's law, not a fallback here).
    static func optionColor(hueOverride: Double?, display: String) -> Color {
        if let deg = hueOverride {
            return degrees(deg)
        }
        return Color(nsColor: valueHex(display))
    }
}

private extension NSColor {
    func resolved(for appearance: NSAppearance) -> NSColor {
        var out = self
        appearance.performAsCurrentDrawingAppearance {
            out = self.usingColorSpace(.sRGB) ?? self
        }
        return out
    }
}
