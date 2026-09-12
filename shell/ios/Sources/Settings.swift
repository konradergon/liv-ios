// liv iOS — SETTINGS.
//
// Lifted out of Chrome.swift on 2026-08-23 (standing rule 9). The gear
// is chrome; what it opens is not — this sheet reads the box's own
// vocabulary, the assist consent cell and the device's notification
// state, and shares nothing with the desk but the theme.

import SwiftUI

/// Facts and notes. Settings never writes cells on entities, with one
/// deliberate exception: the assist consent switch, which lives in the
/// box so the phone and a desktop agree about consent.
///
/// It held §10's ONE schema door — Fields, where a property definition
/// was minted — until 2026-09-12. See the note above `appearanceRow` for
/// why it went and what replaced nothing.
///
/// The Handoff section this comment used to describe — the status card,
/// the Pending/Shipped/Delivered ledger, "Ship now", the satellite-path
/// row — went with the Advanced drawer on 2026-08-14 and is recorded at
/// the foot of `body`. The paragraph describing it outlived it by four
/// weeks.
struct SettingsSheet: View {
    @EnvironmentObject var box: BoxModel
    @ObservedObject private var notify = Notify.shared
    /// Dark, light, or follow the system — device state, never a cell.
    @AppStorage(LivAppearance.key) private var appearance = LivAppearance.dark.rawValue

    /// THE LOG'S OWN NOTICES, and NOT the vault's — see `logRows`.
    ///
    /// READ AND CLEAR on the Rust side, so these are held here once drained
    /// and shown until the sheet closes. Dropping them would be losing the
    /// only notice a length regression ever gets.
    @State private var alerts: [String] = []

    var body: some View {
        // GROUPS AS CARDS (owner's clips, 2026-08-20). ChatGPT's
        // settings, Obsidian's overflow sheet and Apple Notes' list all
        // group with a raised card and a quiet label ABOVE it, never
        // with a heading over a flat run of controls. The gap between
        // two cards says "different things" without a word.
        //
        // The sheet drops to `canvas` so the cards have a ground to
        // stand on — the elevation ramp already says this is what the
        // two steps are for; nothing here used them.
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                LivSheetTitle("Settings")
                // What a person actually came here to change, first.
                LivCard(label: "Appearance") { appearanceRow.padding(12) }
                if box.snap?.assist != nil {
                    LivCard(label: "Suggestions") { assistRow.padding(12) }
                }
                LivCard(label: "Reminders") { notifyRows.padding(12) }
                // ONLY WHEN SOMETHING IS WRONG WITH THE LOG.
                if !alerts.isEmpty {
                    LivCard(label: "The log") { logRows.padding(12) }
                }
                // No Advanced drawer. It held the phone→desk handoff
                // (status, ledger, Ship now, the satellite path) and the
                // store's own facts, and it went with every other
                // advanced feature (owner, 2026-08-14): the friendly
                // ones come first. Nothing in the app can set a
                // satellite path now, so the handoff is off until it
                // gets a door someone would want to open.
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 20)
        }
        .livOverlay(LivOverlay.settings)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(LivTheme.canvas)
        .onAppear {
            loadLogNotices()
        }
    }

    // FIELDS IS GONE (owner, 2026-09-12: "delete fields too"), and with
    // it §10's claim that this sheet holds the app's ONE schema door.
    //
    // The question he asked first was "what is the point of Fields?" and
    // the measured answer was: on a phone, none. A field minted here
    // could never receive a value. `fieldRow` is the only editable row in
    // the inspector, it has exactly one call site, and that site iterates
    // `InspectorField.core` — the four hardcoded names area, project,
    // tags, people. The "Other" section renders cells that ALREADY hold
    // values and is a plain `HStack` with no gesture on it. So minting
    // was reachable, and filling was not.
    //
    // §10 IS THEREFORE REVERSED, on his word. Schema growth is a CLI and
    // desktop affair now: `liv_add_property_at` is untouched in the ABI,
    // and `Box.addProperty` stays because the workspace switcher and
    // `Furnish` both still call it to mint the furniture a new box needs.
    // What went is the door a person could open, the chip row that showed
    // the vocabulary, and `LivGlyph.field` — the name-to-mark lookup this
    // card was the last caller of.

    private var appearanceRow: some View {
        // OURS, NOT THE SYSTEM'S — see `LivSegment`. The stock control's
        // thumb was #6D6D72, a grey with a blue cast that appears nowhere
        // in `Palette`, and it was the ugliest object in the app.
        LivSegment(
            options: LivAppearance.allCases.map { ($0, $0.label) },
            selection: Binding(
                get: { LivAppearance(rawValue: appearance) ?? .dark },
                set: { appearance = $0.rawValue })
        )
    }

    // The assist switch (rev 6): the consent that gates every clerk
    // proposal. With it off the sweep is silent and the wire's inbox is
    // force-empty; with it on, the clerk SUGGESTS (Properties panel's
    // Suggested section) and only an explicit Accept ever writes. This is
    // the one Settings row that writes a cell — the switch LIVES in the
    // box, so the desktop and the phone agree about consent.

    @ViewBuilder private var assistRow: some View {
        if let assist = box.snap?.assist, let entity = assist.id {
            Toggle(
                isOn: Binding(
                    get: { assist.on ?? false },
                    set: { on in
                        box.set(entity, assist.prop ?? "automation", on ? "true" : "false")
                    })
            ) {
                Text("Suggest properties")
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text)
            }
            .toggleStyle(LivSwitchStyle())
            .frame(minHeight: 44)
        }
    }

    // The Notifications section (M5, Notify.swift): master toggle, the two
    // per-kind lead pickers, and the 64-cap honesty line. All DEVICE state
    // (UserDefaults) — Settings never writes cells. Every change rebuilds
    // the pending queue from the snapshot in hand. Quiet hours: DEFERRED —
    // reminders currently ring at any hour.

    @ViewBuilder private var notifyRows: some View {
        // A SWITCH THAT CANNOT RING IS DRAWN OFF.
        //
        // This card contradicted itself: the switch sat ON, in the
        // accent, directly above the line "Turned off for Liv in iOS
        // Settings." Both were true of different things — the app's
        // preference was on, the permission was refused — and a person
        // reading the card sees one control and one sentence disagreeing.
        // The permission is the one that decides whether anything
        // happens, so it is the one the switch shows.
        Toggle(isOn: notify.denied ? .constant(false) : notifyEnabled) {
            Text("Due reminders")
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
        }
        .toggleStyle(LivSwitchStyle())
        .disabled(notify.denied)
        .frame(minHeight: 44)
        if notify.enabled {
            // One switch, no lead times. A reminder rings when the thing
            // is due; the two pickers that used to sit here were invented
            // and governed only the rare timed case (owner, 2026-08-06).
            // Only speak when something is WRONG.
            if let line = notifyProblem {
                Text(line)
                    .font(.system(size: LivType.label).monospacedDigit())
                    .foregroundStyle(notify.denied ? LivTheme.red : LivTheme.text3)
            }
        }
    }

    private var notifyEnabled: Binding<Bool> {
        Binding(
            get: { notify.enabled },
            set: {
                notify.enabled = $0
                notify.rebuild(snapshot: box.snap, box: box)
            })
    }

    /// Says something only when a reminder will NOT arrive: iOS refused
    /// permission, or the 64-notification cap dropped the far ones.
    private var notifyProblem: String? {
        if notify.denied { return "Turned off for Liv in iOS Settings." }
        if notify.droppedCount > 0 {
            return "\(notify.droppedCount) beyond iOS's 64-reminder limit won't ring."
        }
        return nil
    }


    // MARK: the log's own notices

    /// WHAT THE LOG SAYS ABOUT ITSELF, and it had no way to say it.
    ///
    /// `liv_vault_alerts_at` drains three notices the FFI raises on EVERY
    /// box open, in `hit()`, before any projection is considered: the log
    /// SHRANK against what the cache last proved, the log was REPLACED in
    /// place (same length, new inode), or a conflicted copy of it exists
    /// beside it. Each one means something outside this app wrote over the
    /// append-only source, and each one is the only notice that ever
    /// arrives — the open refuses the fast path and replays honestly, so
    /// nothing is adopted silently, but a person is told nothing.
    ///
    /// They were drained inside `guard st?.isVault == true`, and on a
    /// phone that guard is ALWAYS FALSE: `vault_root_of` wants the log at
    /// `<root>/.liv/box/<log>` and `BoxPath.resolve` puts it at
    /// `<container>/liv/liv.log`, whose parent is named `liv` and not
    /// `box`. So the app has never been able to show one of these, and the
    /// static they queue in was never drained either. That is the bug this
    /// card fixes, and it is a bug about the log rather than about the
    /// folder projection — which is why the two are separate now, and why
    /// this one survives the vault card being questioned.
    @ViewBuilder private var logRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(alerts, id: \.self) { line in
                Text(line)
                    .font(.system(size: LivType.label))
                    .foregroundStyle(LivTheme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // THE VAULT CARD IS GONE (owner, 2026-09-11: "Vault section is just
    // noice that nobody needs to see"), and the measurement agrees with
    // him more strongly than he knew: it could never show anything else.
    //
    // `vault_root_of` wants the log at `<root>/.liv/box/<log>` and checks
    // both directory names; `BoxPath.resolve` puts it at
    // `<container>/liv/liv.log`, whose parent is named `liv`. So
    // `isVault` is false on every iOS install, every vault verb bails on
    // its own `vault_root_of` guard before doing anything, and the card
    // had exactly one reachable state: a sentence apologising that there
    // was nothing to project. `drive.sh vault` only ever passed through
    // that branch, and went with it.
    //
    // What went, under standing rule 6: `vaultRows`, `vaultLine`,
    // `shortRoot`, `finding`, `vaultButton`, `syncVault`, `rebuildVault`,
    // the four `@State` vars they read, and in `Box.swift` the four
    // wrappers and two types nothing else called. `vaultAlerts` STAYS —
    // it is about the log, not the folder, and the commit before this one
    // is why.
    //
    // This is not a claim that the projection was a bad idea. It is a
    // claim about the phone: the box lives in an App Group container, and
    // a vault is a folder you keep your own way. A desktop shell over the
    // same core is where these verbs have a reachable surface, and the
    // FFI and the CLI keep all five for it.

    /// Drain the log's notices, once, on appear. Never polled: a log that
    /// has not been tampered with has nothing to say, and the verb is
    /// read-and-clear, so asking twice would lose them.
    private func loadLogNotices() {
        box.vaultAlerts { alerts = $0 }
    }

}

