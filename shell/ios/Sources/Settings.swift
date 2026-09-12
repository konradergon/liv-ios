// liv iOS — SETTINGS.
//
// Lifted out of Chrome.swift on 2026-08-23 (standing rule 9). The gear
// is chrome; what it opens is not — this sheet reads the box's own
// vocabulary, the assist consent cell and the device's notification
// state, and shares nothing with the desk but the theme.

import SwiftUI

/// Facts and notes — plus the ONE schema door (§10): Fields, where a new
/// property definition is minted. Settings still never writes cells on
/// entities; the inspector's old "+ property" moved here because schema
/// growth is possible, not daily use.
///
/// The Handoff section this comment used to describe — the status card,
/// the Pending/Shipped/Delivered ledger, "Ship now", the satellite-path
/// row — went with the Advanced drawer on 2026-08-14 and is recorded at
/// the foot of `body`. The paragraph describing it outlived it by four
/// weeks.
struct SettingsSheet: View {
    @EnvironmentObject var box: BoxModel
    @ObservedObject private var notify = Notify.shared
    @State private var addingField = false
    @State private var fieldDraft = ""
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
                Text("Settings")
                    .font(.system(size: LivType.title, weight: .bold))
                    .foregroundStyle(LivTheme.text)
                    .padding(.horizontal, LivRow.cardInset + 4)
                    .padding(.top, 16)
                // What a person actually came here to change, first.
                LivCard(label: "Appearance") { appearanceRow.padding(12) }
                if box.snap?.assist != nil {
                    LivCard(label: "Suggestions") { assistRow.padding(12) }
                }
                LivCard(label: "Reminders") { notifyRows.padding(12) }
                LivCard(label: "Fields") { fieldsRow.padding(12) }
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

    // The Fields door (§10): the schema the box holds, and the ONE place a
    // new field is born. Relocated from the inspector's "+ property" row —
    // adding a kind of field is possible, never in the flow of daily use.

    /// The box's field vocabulary, usage-desc, off the live snapshot.
    private var fieldNames: [String] {
        (box.snap?.properties ?? [])
            .sorted { ($0.usage ?? 0) > ($1.usage ?? 0) }
            .compactMap { $0.name }
            .filter { !$0.isEmpty }
    }

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

    @ViewBuilder private var fieldsRow: some View {
        if !fieldNames.isEmpty {
            // Chips, not a run-on line of names separated by dots. The
            // vocabulary is data; the app already has a way to show data.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    // THE SCHEMA VIEW, so the glyphs live here — this is
                    // a list you scan for a name, not a value you read.
                    ForEach(fieldNames, id: \.self) {
                        ValueChip($0, glyph: LivGlyph.field($0))
                    }
                }
                .padding(.vertical, 1)
            }
        }
        if addingField {
            HStack(spacing: 8) {
                TextField("Name the new field", text: $fieldDraft)
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(createField)
                Button("Create", action: createField)
                    .font(.system(size: LivType.label, weight: .medium))
                    .foregroundStyle(fieldDraftReady ? LivTheme.accent : LivTheme.muted)
                    .buttonStyle(.plain)
                    .disabled(!fieldDraftReady)
                Button {
                    addingField = false
                    fieldDraft = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: LivType.caption, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                    .strokeBorder(LivTheme.border, lineWidth: 0.5)
            )
        } else {
            Button {
                addingField = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: LivType.caption, weight: .semibold))
                    Text("Add field")
                        .font(.system(size: LivType.body, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(LivTheme.accent)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add field")
        }
    }

    private var fieldDraftReady: Bool {
        let name = fieldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        // Minting a duplicate is refused by the core anyway; disable the
        // button rather than offer a refusal.
        return !fieldNames.contains {
            $0.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    /// Births a TEXT property — the same implicit kind the inspector's old
    /// flow assumed. Other kinds stay a desktop/CLI affair for now.
    private func createField() {
        let name = fieldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fieldDraftReady else { return }
        box.addProperty(name) { id in
            guard id != 0 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            fieldDraft = ""
            addingField = false
        }
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

