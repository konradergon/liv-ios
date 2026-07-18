// lotus — the theme engine (P20a, the Viggo pack's token system).
// Four named themes as TOKEN SWAPS — never layout, never behavior
// (app-mockup.tokens.css is the authority; the values below are its bytes).
// Every Theme.* color resolves through a dynamic provider that reads the
// CURRENT spec at draw time, so a switch repaints without rebuilding view
// state; ThemeCore also mirrors the theme's lightness into NSAppearance so
// system controls match, and nudges a re-resolve when two themes share one
// appearance (brand-dark → night).

import AppKit
import SwiftUI

/// One theme — concrete resolved colors (the CSS custom-property block).
struct ThemeSpec {
    let id: String
    let label: String
    let dark: Bool
    /// Window frame / titlebar / rail.
    let chrome: NSColor
    /// The content background behind cards (also the active-tab fill).
    let canvas: NSColor
    /// Cards, popovers, toasts, tiles, key fields.
    let surface: NSColor
    /// Panels, footbars, dropdown lists, log wells.
    let panel: NSColor
    /// Chips, toggle tracks, meta tags, small fills.
    let panel2: NSColor
    // The four text tiers.
    let text: NSColor
    let text2: NSColor
    let text3: NSColor
    let muted: NSColor
    let border: NSColor
    let border2: NSColor
    /// Accent-tinted in the brand themes — hover is a statement here.
    let hover: NSColor
    let accent: NSColor
    /// The selection fill (.on rows, active rail buttons, selected cards).
    let accentSoft: NSColor
    let onAccent: NSColor
    // The semantic set — the ONLY value colors (O2: VALUE_HEX retired).
    let green: NSColor
    let red: NSColor
    let yellow: NSColor
    let purple: NSColor
    let radius: CGFloat
    /// The UI face the theme asks for; nil = the system face. Faces that
    /// are not installed fall through to system at resolve time.
    let fontName: String?
}

private func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha)
}

/// The four themes, byte-faithful to app-mockup.tokens.css.
let themeSpecs: [ThemeSpec] = [
    ThemeSpec(
        id: "brand-light", label: "Liv · Light", dark: false,
        chrome: hex(0xE7E4EF), canvas: hex(0xF0EEF6), surface: hex(0xFFFFFF),
        panel: hex(0xF3F1F8), panel2: hex(0xEEEBF5),
        text: hex(0x1B1623), text2: hex(0x4A4553), text3: hex(0x6B6675), muted: hex(0x9A93A6),
        border: hex(0x1B1623, 0.10), border2: hex(0x1B1623, 0.16),
        hover: hex(0x6F5BE6, 0.06),
        accent: hex(0x6F5BE6), accentSoft: hex(0xEDEBFB), onAccent: hex(0xFFFFFF),
        green: hex(0x2F7A63), red: hex(0xC0392B), yellow: hex(0xF6A823), purple: hex(0x9334E6),
        radius: 10, fontName: "Hanken Grotesk"),
    ThemeSpec(
        id: "brand-dark", label: "Liv · Dark", dark: true,
        chrome: hex(0x0E0A14), canvas: hex(0x17121F), surface: hex(0x201A2B),
        panel: hex(0x171220), panel2: hex(0x1C1628),
        text: hex(0xECEAF2), text2: hex(0xC3BDD0), text3: hex(0xA79FB5), muted: hex(0x6E6780),
        border: hex(0xFFFFFF, 0.09), border2: hex(0xFFFFFF, 0.15),
        hover: hex(0x8B7BF0, 0.10),
        accent: hex(0x8B7BF0), accentSoft: hex(0x8B7BF0, 0.16), onAccent: hex(0xFFFFFF),
        green: hex(0x97C459), red: hex(0xF09595), yellow: hex(0xF6A823), purple: hex(0xC99BF5),
        radius: 10, fontName: "Hanken Grotesk"),
    ThemeSpec(
        id: "night", label: "Night", dark: true,
        chrome: hex(0x0A0B16), canvas: hex(0x0F1122), surface: hex(0x171A2E),
        panel: hex(0x12142A), panel2: hex(0x171A30),
        text: hex(0xC9CCE0), text2: hex(0xA9AEC8), text3: hex(0x8B8FA8), muted: hex(0x5F6488),
        border: hex(0xFFFFFF, 0.08), border2: hex(0xFFFFFF, 0.14),
        hover: hex(0x6F5BE6, 0.10),
        accent: hex(0x6F5BE6), accentSoft: hex(0x6F5BE6, 0.16), onAccent: hex(0xFFFFFF),
        green: hex(0x5E86B0), red: hex(0xCC7D7D), yellow: hex(0xBDA15F), purple: hex(0x9287BF),
        radius: 8, fontName: nil),  // Segoe UI Variable does not exist on macOS
    ThemeSpec(
        id: "google", label: "Google Workspace", dark: false,
        chrome: hex(0xE9EBEF), canvas: hex(0xF1F3F4), surface: hex(0xFFFFFF),
        panel: hex(0xF6F8FA), panel2: hex(0xF1F3F4),
        text: hex(0x202124), text2: hex(0x444746), text3: hex(0x5F6368), muted: hex(0x80868B),
        border: hex(0xDADCE0), border2: hex(0xC9CDD2),
        hover: hex(0xF1F3F4),
        accent: hex(0x1A73E8), accentSoft: hex(0xE8F0FE), onAccent: hex(0xFFFFFF),
        green: hex(0x188038), red: hex(0xD93025), yellow: hex(0xF9AB00), purple: hex(0x9334E6),
        radius: 8, fontName: nil),  // Google Sans is not redistributable
]

/// Amber ink for solid amber fills — one value across every theme.
let onYellowInk = hex(0x3A2A00)

// MARK: - the engine

final class ThemeCore: ObservableObject {
    static let shared = ThemeCore()
    private static let key = "app.theme.v1"

    /// The current spec — @Published so the root re-evaluates (radius,
    /// fonts); COLORS re-resolve on their own via the dynamic providers.
    @Published private(set) var spec: ThemeSpec = themeSpecs[0]

    /// Launch: migrate the P19 light/dark pref once, then apply.
    func boot() {
        var id = UserDefaults.standard.string(forKey: Self.key)
        if id == nil {
            // The old rail toggle's pref — dark stays dark.
            id = UserDefaults.standard.string(forKey: "app.appearance") == "dark"
                ? "brand-dark" : "brand-light"
        }
        apply(id ?? "brand-light", persist: false)
    }

    func apply(_ id: String, persist: Bool = true) {
        let next = themeSpecs.first { $0.id == id } ?? themeSpecs[0]
        spec = next
        if persist {
            UserDefaults.standard.set(next.id, forKey: Self.key)
        }
        // System controls follow the theme's lightness. Two themes can
        // share one appearance (brand-dark → night): flip-and-restore so
        // every dynamic provider re-resolves.
        let target: NSAppearance.Name = next.dark ? .darkAqua : .aqua
        NSApp.appearance = NSAppearance(named: next.dark ? .aqua : .darkAqua)
        DispatchQueue.main.async {
            NSApp.appearance = NSAppearance(named: target)
        }
    }

    /// The rail button's gesture (sim: theme.cycle) — brand pair first.
    func cycle() {
        let ids = themeSpecs.map(\.id)
        let at = ids.firstIndex(of: spec.id) ?? 0
        apply(ids[(at + 1) % ids.count])
        Toast.show("Theme: \(spec.label)")
    }
}

/// A draw-time token: resolves against the CURRENT spec on every paint, so
/// a theme switch repaints without any view-state rebuild.
func themeToken(_ read: @escaping (ThemeSpec) -> NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { _ in read(ThemeCore.shared.spec) })
}
