// lotus — the visual system of the Liv port (liv-ui-map.md §3).
// One intended divergence from Liv: every accent is lake green.
// Semantic tokens only; no per-component palettes. Elevation is tonal —
// chrome darkest, page lighter, cards lightest; shadows only for floaters.

import AppKit
import SwiftUI

extension Theme {
    // MARK: §3.1 token vocabulary (Google-skin reference values, re-hued)

    /// One dynamic color, light/dark, from the reference table.
    private static func dyn(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(hex: hex)
        })
    }

    /// The accent: lake green, both modes (Liv's --primary slot).
    static let primary = accent
    static let background = dyn("#ffffff", "#1f1f1f")
    static let foreground = dyn("#202124", "#e8eaed")
    static let surface1 = dyn("#ffffff", "#2d2e30")
    static let surface2 = dyn("#f1f3f4", "#1b1b1b")
    static let popover = dyn("#ffffff", "#292a2d")
    /// Sidebar / activity bar / title bar chrome.
    static let panel = dyn("#f1f3f4", "#1b1b1b")
    static let secondary = dyn("#e8eaed", "#3c4043")
    static let mutedFg = dyn("#5f6368", "#9aa0a6")
    static let border = dyn("#dadce0", "#3c4043")
    static let destructive = dyn("#d93025", "#f28b82")
    /// Amber: reserved app-wide for AI presence (badges, rings, cards).
    static let warning = dyn("#e37400", "#fdd663")

    // MARK: §3.3 radii ("google" shape: --radius 8, controls pill)

    static let radiusSm: CGFloat = 4
    static let radiusMd: CGFloat = 6
    static let radius: CGFloat = 8
    static let radiusXl: CGFloat = 12

    // MARK: §3.4 motion

    /// The signature spring — settles, never overshoots.
    static let spring = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.2)
    static let springFast = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.14)
    /// Gliding indicators.
    static let glide = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.32)

    // MARK: §1.2 chrome geometry

    static let railWidth: CGFloat = 44  // w-11
    static let trafficLightSpacer: CGFloat = 72
    /// The sidebar header band; buttons top-align in it so their centres
    /// (~14pt) line up with the macOS traffic lights.
    static let headerBandHeight: CGFloat = 40
}

extension NSColor {
    /// "#rrggbb" → NSColor; the reference table is authored in hex.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }
}

// MARK: §3.4 states — the shared row/badge idioms

/// `.badge-soft`: pill, min-w 20, 10.4px/600, primary-14% bg + primary text.
struct SoftBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10.4, weight: .semibold).monospacedDigit())
            .foregroundColor(Theme.primary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 16.8)
            .background(Capsule().fill(Theme.primary.opacity(0.14)))
    }
}

/// Warning-tinted variant: the amber AI-presence badge.
struct WarningBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10.4, weight: .semibold).monospacedDigit())
            .foregroundColor(Theme.warning)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 16.8)
            .background(Capsule().fill(Theme.warning.opacity(0.14)))
    }
}

/// `.kbd`: mono 11.5px keycap chip (1px border, 2px bottom edge).
struct KbdChip: View {
    let label: String
    var size: CGFloat = 10.5

    var body: some View {
        Text(label)
            .font(.system(size: size, design: .monospaced))
            .foregroundColor(Theme.mutedFg)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5.6)
                    .fill(Theme.secondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5.6)
                    .strokeBorder(Theme.border, lineWidth: 1)
                    .padding(.bottom, -1)
            )
    }
}
