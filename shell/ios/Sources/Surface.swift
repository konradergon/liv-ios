// liv iOS — WHICH SURFACE IS ACTUALLY ON SCREEN.
//
// This exists because of a day lost on 2026-08-23. A rework left the app
// changing `desk.state` correctly while the screen never repainted: the
// bar's own label read "Tabs. 0 open in Calendar" over a body still
// drawing Today. Every probe that asked the MODEL said the navigation
// had worked. It had not.
//
// So each surface now says what it is, in the accessibility tree, where
// a test can read it. The rule this enforces is the one that was
// missing: **a test must assert what is RENDERED, not what the model
// believes**. `drive.sh` is the reader.
//
// It is an identifier, never a label: identifiers are for machines and
// are not spoken, so VoiceOver hears nothing new.

import SwiftUI

/// The name a surface answers to. Frozen — `drive.sh` matches on these
/// strings, and a renamed surface is a silently skipped check.
enum LivSurface {
    static let prefix = "liv.surface."

    /// The desk's three bodies. The five feature views use their
    /// `Feature.rawValue`, so there is one vocabulary, not two.
    ///
    /// `tabs` is Notes' root: the grid, drawn as the surface rather than
    /// over it (owner, 2026-08-24).
    static let tabs = "tabs"
    static let document = "document"
}

extension View {
    /// Mark this as the surface `name`. One invisible element carrying an
    /// identifier — it adds nothing a person can hear or touch, and it
    /// cannot be confused with content, which is the whole point: the
    /// marker is there whether the box is full or empty.
    ///
    /// An empty box is exactly what made the old coordinate-and-content
    /// checks lie. "No LATE pile" meant both "you left Today" and "Today
    /// has nothing today", and the harness could not tell them apart.
    func livSurface(_ name: String) -> some View {
        overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                // The identifier is what `drive.sh` reads. A LABEL was
                // tried first and works too — and is wrong, because
                // VoiceOver would read "liv dot surface dot today" aloud
                // to a person. Identifiers are for machines only.
                //
                // `accessibilityHidden(false)` is load-bearing: a
                // `Color.clear` with no label is not an accessibility
                // element on its own, so without this the marker is not
                // in the tree at all and every check would pass by
                // finding nothing.
                .accessibilityIdentifier(LivSurface.prefix + name)
                .accessibilityHidden(false)
                .allowsHitTesting(false)
        }
    }
}

/// The name an OVERLAY answers to — the things that sit over a surface
/// rather than being one.
///
/// Separate prefix, on purpose: `drive.sh check` asserts that exactly ONE
/// surface is on screen, and a panel is not a second surface.
///
/// These exist because the harness used to detect the library panel by
/// looking for the word "Trash" on screen. The settings sheet contains
/// that word too, so a check that left settings open made every later
/// check believe the library panel was up (2026-08-27). Reading content
/// to answer a structural question is the same mistake `livSurface` was
/// built to end.
enum LivOverlay {
    static let prefix = "liv.overlay."

    static let library = "library"
    static let settings = "settings"
}

extension View {
    /// Mark this as the overlay `name`. Same invisible, unspoken element
    /// as `livSurface`, and for the same reason.
    func livOverlay(_ name: String) -> some View {
        overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier(LivOverlay.prefix + name)
                .accessibilityHidden(false)
                .allowsHitTesting(false)
        }
    }
}
