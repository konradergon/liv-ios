// lotus — the visual system of the Liv port (liv-ui-map.md §3).
// One intended divergence from Liv: every accent is lake green.
// Semantic tokens only; no per-component palettes. Elevation is tonal —
// chrome darkest, page lighter, cards lightest; shadows only for floaters.

import AppKit
import SwiftUI

extension Theme {
    // MARK: the token vocabulary (P20a — app-mockup.tokens.css, four themes)
    //
    // Every color routes through themeToken (Themes.swift): resolved
    // against the CURRENT ThemeSpec at draw time. The legacy names below
    // keep every P1–P19 call site compiling — mapped onto the new
    // vocabulary; new work should prefer the new names.

    // The new vocabulary.
    static var chrome: Color { themeToken { $0.chrome } }
    static var canvas: Color { themeToken { $0.canvas } }
    static var surface: Color { themeToken { $0.surface } }
    static var panel2: Color { themeToken { $0.panel2 } }
    static var text2: Color { themeToken { $0.text2 } }
    static var muted: Color { themeToken { $0.muted } }
    static var border2: Color { themeToken { $0.border2 } }
    static var hover: Color { themeToken { $0.hover } }
    static var accentSoft: Color { themeToken { $0.accentSoft } }
    static var onAccent: Color { themeToken { $0.onAccent } }
    static var green: Color { themeToken { $0.green } }
    static var red: Color { themeToken { $0.red } }
    static var yellow: Color { themeToken { $0.yellow } }
    static var purple: Color { themeToken { $0.purple } }
    static var onYellow: Color { Color(nsColor: onYellowInk) }

    // The legacy names (P1–P19 call sites), mapped.
    static var primary: Color { accent }
    static var background: Color { canvas }
    static var foreground: Color { themeToken { $0.text } }
    static var surface1: Color { surface }
    static var surface2: Color { panel2 }
    static var popover: Color { surface }
    /// Sidebar / activity bar / title bar chrome.
    static var panel: Color { themeToken { $0.panel } }
    static var secondary: Color { panel2 }
    static var mutedFg: Color { themeToken { $0.text3 } }
    static var border: Color { themeToken { $0.border } }
    static var destructive: Color { red }
    /// Amber: reserved app-wide for AI presence (badges, rings, cards).
    static var warning: Color { yellow }

    // MARK: radii — the theme's token, shifted by the Shape flavor pref

    /// Standard = the theme's own radius · Soft = 12 · Sharp = 4.
    static var radius: CGFloat {
        switch UserDefaults.standard.string(forKey: "app.shape.v1") {
        case "soft": return 12
        case "sharp": return 4
        default: return ThemeCore.shared.spec.radius
        }
    }
    static var radiusSm: CGFloat { max(3, radius - 4) }
    static var radiusMd: CGFloat { max(4, radius - 2) }
    static var radiusXl: CGFloat { radius + 4 }

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
