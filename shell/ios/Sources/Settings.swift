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
/// growth is possible, not daily use. The Handoff section
/// (design/ios.md §2.2) is the funnel's honesty surface: the status card,
/// the per-item Pending/Shipped/Delivered ledger, "Ship now", and the
/// satellite-path row (dev-grade paste field — file pickers arrive with
/// the real Xcode project). Setting the path is device config, not a cell.
struct SettingsSheet: View {
    @EnvironmentObject var box: BoxModel
    @ObservedObject private var notify = Notify.shared
    @State private var addingField = false
    @State private var fieldDraft = ""
    /// Dark, light, or follow the system — device state, never a cell.
    @AppStorage(LivAppearance.key) private var appearance = LivAppearance.dark.rawValue

    /// The vault card's state. Read on appear, refreshed after a sync or a
    /// rebuild — never polled: a projection that is quiet has nothing to say.
    @State private var vault: BoxModel.LivVaultStatus?
    @State private var findings: [BoxModel.LivVaultFinding] = []
    /// READ AND CLEAR on the Rust side, so these are held here once drained
    /// and shown until the sheet closes. Dropping them would be losing the
    /// only notice a length regression ever gets.
    @State private var alerts: [String] = []
    @State private var vaultBusy = false
    @State private var vaultSaid: String?

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
                LivCard(label: "Vault") { vaultRows.padding(12) }
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
            loadVault()
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
        Picker(
            "Appearance",
            selection: Binding(
                get: { LivAppearance(rawValue: appearance) ?? .dark },
                set: { appearance = $0.rawValue })
        ) {
            ForEach(LivAppearance.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 30)
    }

    @ViewBuilder private var fieldsRow: some View {
        if !fieldNames.isEmpty {
            // Chips, not a run-on line of names separated by dots. The
            // vocabulary is data; the app already has a way to show data.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(fieldNames, id: \.self) { ValueChip($0) }
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
            .tint(LivTheme.accent)
            .frame(minHeight: 30)
        }
    }

    // The Notifications section (M5, Notify.swift): master toggle, the two
    // per-kind lead pickers, and the 64-cap honesty line. All DEVICE state
    // (UserDefaults) — Settings never writes cells. Every change rebuilds
    // the pending queue from the snapshot in hand. Quiet hours: DEFERRED —
    // reminders currently ring at any hour.

    @ViewBuilder private var notifyRows: some View {
        Toggle(isOn: notifyEnabled) {
            Text("Due reminders")
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
        }
        .tint(LivTheme.accent)
        .frame(minHeight: 30)
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


    // MARK: the vault

    /// THE FOLDER IS A PROJECTION, NOT A SECOND TRUTH (O14,
    /// `design/p20j-files-projection.md` §1). The box is the one truth and
    /// lives inside the folder; `library/` is written FROM the log and can
    /// be deleted and rebuilt byte-identical. An edit made in another app
    /// is not truth until it is ingested, which is what Sync does.
    ///
    /// Five verbs backed all of this in Rust and no client called any of
    /// them, so the promise that your work sits in an ordinary folder had
    /// nothing behind it on the phone.
    @ViewBuilder private var vaultRows: some View {
        if let vault, vault.isVault {
            vaultLine("Folder", vault.root.isEmpty ? "—" : shortRoot(vault.root))
            vaultLine("Files", "\(vault.files)")
            HStack(spacing: 8) {
                vaultButton("Sync now", busy: vaultBusy) { syncVault() }
                vaultButton("Rebuild", busy: vaultBusy) { rebuildVault() }
            }
            .padding(.top, 10)
            if let vaultSaid {
                Text(vaultSaid)
                    .font(.system(size: LivType.label).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
                    .padding(.top, 8)
            }
            // Only speak when something is WRONG. A quiet vault says nothing.
            if !alerts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(alerts, id: \.self) { line in
                        Text(line)
                            .font(.system(size: LivType.label))
                            .foregroundStyle(LivTheme.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 10)
            }
            if !findings.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(findings) { f in
                        Text(finding(f))
                            .font(.system(size: LivType.label))
                            .foregroundStyle(LivTheme.text2)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 10)
            }
        } else {
            Text("This box is not inside a vault folder, so there is nothing to project.")
                .font(.system(size: LivType.label))
                .foregroundStyle(LivTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func vaultLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: LivType.label).monospacedDigit())
                .foregroundStyle(LivTheme.text3)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(minHeight: 30)
    }

    /// The tail of the path. The whole thing is a sandbox URL a person
    /// cannot act on, and it would wrap three lines to say so.
    private func shortRoot(_ p: String) -> String {
        let parts = p.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }

    private func finding(_ f: BoxModel.LivVaultFinding) -> String {
        let what = f.path.isEmpty ? "\(f.count) files" : shortRoot(f.path)
        return "\(f.kind) · \(what)"
    }

    private func vaultButton(
        _ title: String, busy: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: LivType.label, weight: .medium))
                .foregroundStyle(busy ? LivTheme.text3 : LivTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(LivTheme.panel2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func loadVault() {
        box.vaultStatus { st in
            vault = st
            guard st?.isVault == true else { return }
            box.vaultAlerts { alerts = $0 }
            box.vaultFindings { findings = $0 }
        }
    }

    private func syncVault() {
        vaultBusy = true
        vaultSaid = nil
        box.vaultSync { result in
            vaultBusy = false
            guard let r = result else {
                vaultSaid = "Busy — try again in a moment."
                return
            }
            // One transaction, so one sentence.
            vaultSaid = "Ingested \(r.edited) edited, \(r.created) new"
                + (r.surfaced > 0 ? ", \(r.surfaced) surfaced" : "") + "."
            loadVault()
        }
    }

    private func rebuildVault() {
        vaultBusy = true
        vaultSaid = nil
        box.vaultRebuild { n in
            vaultBusy = false
            vaultSaid = n.map { "Rewrote \($0) files from the log." }
                ?? "Busy — try again in a moment."
            loadVault()
        }
    }

}

