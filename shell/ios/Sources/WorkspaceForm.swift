// liv iOS — the WORKSPACE FORM (the switcher's list moved into the
// library panel on 2026-09-29).
//
// Lifted out of Chrome.swift on 2026-08-23, which was 1,870 lines:
// standing rule 9 calls ~600 the signal to look for the seam, and this
// sheet was a self-contained 340 of them. It is a workspace surface, not
// chrome: it hangs from the workspace button, it reads WorkspaceModel,
// and it writes the `query` cell that IS a workspace. `Workspace.swift`
// holds the model and the grammar; this holds the door.

import SwiftUI

/// Which lens row is being picked, and which draft it writes back to.
struct WorkspacePick: Identifiable {
    let property: String
    var id: String { property }
}

// MARK: - the workspace form (M4)

/// NAME A WORKSPACE, AND SAY WHAT IT HOLDS — new, or an edit of one.
///
/// THE FORM IS ALL THAT IS LEFT (clearer spec, 2026-09-29, "option A").
/// This was the Workspaces card: All, a row per workspace, and a "New
/// workspace…" row, rising from a button at the panel's foot. The panel
/// lists the workspaces itself now — so switching is a row there, and New
/// workspace and Edit workspace open this, and nothing else.
struct WorkspaceForm: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    /// nil makes a new workspace; an id edits that one. Editing exists
    /// because a box can arrive with a workspace in it: with a create-only
    /// form it could never be changed.
    let editing: LivEntityID?
    /// How this closes: it hangs from the panel, so there is no sheet
    /// environment to dismiss — the presenter hands it the way out.
    var onClose: () -> Void

    @State private var draftName = ""
    @State private var draftQuery = ""
    /// Which picker row is open, and whose draft it edits.
    @State private var picking: WorkspacePick?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The title says which form it is, so the card is never
            // unlabelled.
            LivCardTitle(text: editing == nil ? "New workspace" : "Edit workspace")
            form
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard let id = editing, let ws = workspaces.workspaces.first(where: { $0.id == id })
            else { return }
            draftName = ws.display
            draftQuery = workspaces.query(of: id) ?? ""
        }
        // No .presentationDetents: it is not a sheet. It hangs from the
        // panel (LivTopSheetHost), which sizes itself to this content.
        // The SAME picker the properties panel uses, told to report the
        // choice instead of writing a cell.
        .sheet(item: $picking) { pick in
            InspectorValueSheet(
                field: InspectorField.describe(pick.property, in: box.snap),
                // NO ENTITY: this sheet is picking a value to put in a
                // QUERY, not a cell on a thing. `.absent` is what "no
                // thing" is called now that `0` cannot say it.
                id: .absent,
                current: [],
                onPick: { (value: String?) in put(value, for: pick) }
            )
            .environmentObject(box)
        }
    }

    /// One picked value, written into whichever draft is open.
    ///
    /// Kept OUT of the `.sheet` closure with every type spelled out.
    private func put(_ value: String?, for pick: WorkspacePick) {
        let terms: [BoxModel.LivQueryTerm] = box.lex(draftQuery)
        draftQuery = LivTerms.setting(pick.property, to: value, in: terms)
    }

    // MARK: the form — name + query

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Name", text: $draftName)
            lensRows($draftQuery)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onClose)
                // text2, not text3. A control is not a placeholder, and
                // text3 is the tier the palette check exempts from the
                // read floor on the grounds that it holds placeholders
                // and timestamps (rev 79). It stays QUIETER than the
                // filled pill beside it, which is the pair a form wants:
                // one primary, one way out.
                .font(.system(size: LivType.body, weight: .medium))
                .foregroundStyle(LivTheme.text2)
                .buttonStyle(.plain)
                ConfirmPill(editing == nil ? "Create" : "Save", action: saveWorkspace)
                .disabled(trimmed(draftName).isEmpty)
                .opacity(trimmed(draftName).isEmpty ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// What the picker row shows for one property in this draft query.
    ///
    /// Hoisted out of the ViewBuilder with the type spelled: a call this
    /// shape, nested inline, is where Swift 6.3.3 stops reporting errors
    /// and starts crashing (recordResolvedOverload), blaming `body`.
    private func pickedValue(_ property: String, in raw: String) -> String? {
        let terms: [BoxModel.LivQueryTerm] = box.lex(raw)
        return LivTerms.value(of: property, in: terms)
    }

    /// What the lens is made of: pick an area, pick tags. The two the
    /// owner named (2026-08-11) — project and people are reachable
    /// through Advanced and were noise here.
    ///
    /// No sentence explains any of this. A grey line under a control is
    /// a design failure (owner, 2026-08-06), so the row shows the value
    /// itself and nothing else; the old "stamps area:Work" hint is gone
    /// with it.
    @ViewBuilder private func lensRows(
        _ query: Binding<String>
    ) -> some View {
        ForEach(["area", "tags"], id: \.self) { property in
            let value: String? = pickedValue(property, in: query.wrappedValue)
            Button {
                picking = WorkspacePick(property: property)
            } label: {
                HStack(spacing: 8) {
                    // THE BOX'S WORD FOR IT, not a pair spelled here.
                    //
                    // This was `property == "area" ? "Area" : "Tags"` —
                    // a two-entry word table in a view file, which is
                    // the shell-side furnishing `one-core.md` §4 records
                    // as a mistake. It is also how the owner ended up
                    // asking what "Tags" was (2026-09-16): a tag in this
                    // app is what a thing is ABOUT, the box says
                    // "Subject", and this file said otherwise.
                    Text(InspectorField.describe(property, in: box.snap).shown.capitalized)
                        .font(.system(size: LivType.body))
                        .foregroundStyle(LivTheme.text)
                    Spacer(minLength: 8)
                    if let value {
                        ValueChip(value)
                    } else {
                        Text("Any")
                            .font(.system(size: LivType.body))
                            .foregroundStyle(LivTheme.text3)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: LivType.caption, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                .frame(height: LivRow.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                if property != "area" {
                    LivHairline()
                }
            }
        }
    }

    /// One dress, one font. The mono variant existed for the raw query
    /// field, which is gone (owner, 2026-08-14).
    ///
    /// IT FILLED WITH THE COLOUR BEHIND IT (fixed 2026-09-13, owner:
    /// *"These spaces need visual polish"*). The card is
    /// `LivTheme.surface` and this field was `LivTheme.surface`, so the
    /// only thing separating them was a 0.5pt hairline — which is why
    /// "Name" read as a placeholder floating loose in the card rather
    /// than as a field waiting for a word. `panel2` is the app's own
    /// answer for a well: "a quiet fill for a lit row, a chip, a well".
    ///
    /// The border goes with the same argument rev 83 used on the filter
    /// chips: a fill either reads as a well or it does not, and a
    /// hairline propping up a fill that does not is two devices for one
    /// job. The capsule matches the search field, which is the app's
    /// other place you type a word into a shape.
    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(.system(size: LivType.body))
            .foregroundStyle(LivTheme.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .frame(height: LivRow.touch)
            .background(Capsule().fill(LivTheme.panel2))
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Birth (or re-aim) the workspace: write its `query` cell, and mint any
    /// property the stamp names but the box has never seen — `set` REFUSES
    /// an unknown property name, so without this the stamp would silently do
    /// nothing. One serial lane, so these land in order.
    private func saveWorkspace() {
        let name = trimmed(draftName)
        let query = trimmed(draftQuery)
        guard !name.isEmpty else { return }
        if let id = editing {
            box.set(id, "name", name)
            workspaces.remember(id, name: name, query: query)
            write(query, to: id)
            finish(id)
        } else {
            box.createWorkspace(name: name) { id in
                guard !id.isAbsent else { return }
                // THE MODEL LEARNS IT BEFORE THE SNAPSHOT DOES. `finish`
                // makes this workspace active, and a snapshot taken
                // before the create lands a beat later carrying no such
                // id — which `apply` reads as "it left the box" and
                // answers by falling back to All. Handing the row over
                // here is what stops the new workspace throwing you off
                // itself (owner, 2026-09-22).
                workspaces.remember(id, name: name, query: query)
                write(query, to: id)
                finish(id)
            }
        }
    }

    /// The `query` cell IS the workspace. An emptied query clears the cell
    /// rather than leaving a stale lens behind.
    ///
    /// **AND THE WORDS IT NAMES HAVE TO EXIST** — both of them, which is
    /// the half this got wrong (owner, 2026-09-22).
    ///
    /// It already minted a missing PROPERTY, because `set` refuses a
    /// property name the box has never seen and the stamp would then do
    /// nothing. The same is true one level down and was not handled: a
    /// select's VALUE is matched by name and never minted — a typo must
    /// not create an area — so a workspace whose query says
    /// `area:test1`, written by typing a new name into the form's Area
    /// row, stamps nothing at all. Every note made in it came out
    /// unfiled, in silence, while the form showed the area as set.
    ///
    /// Picking an area that already existed worked, which is what made
    /// it look like the stamp was broken rather than the vocabulary.
    ///
    /// Typing a name into that row IS how an area is born now that none
    /// ships (2026-09-21), so minting here is not a convenience — it is
    /// the only door that form has.
    ///
    /// Both verbs are idempotent by name, so a workspace saved twice
    /// mints nothing the second time. `addProperty` was not, until the
    /// same day — it left a duplicate field behind on every save.
    private func write(_ query: String, to id: LivEntityID) {
        if query.isEmpty {
            box.unset(id, "query")
        } else {
            box.set(id, "query", query)
            for cell in LivTerms.stamps(box.lex(query)) where cell.property != "type" {
                box.addProperty(cell.property) { pid in
                    guard !pid.isAbsent else { return }
                    // ONLY A FIELD THAT KEEPS A VOCABULARY. `tags` is
                    // text and holds no options, and asking it to mint
                    // one is refused — which would raise a fault chip
                    // about a workspace that saved perfectly well.
                    // `mintsValues` is the box's own answer to that
                    // question and the one the value picker already uses.
                    guard InspectorField.describe(cell.property, in: box.snap).mintsValues
                    else { return }
                    box.addOption(pid, cell.value)
                }
            }
        }
        workspaces.rememberQuery(id, query)
    }

    /// Saved: the workspace it made or changed is the one you are in.
    private func finish(_ id: LivEntityID) {
        workspaces.setActive(id)
        onClose()
    }
}

/// A WORKSPACE'S MARK, for the panel's rows (the clearer board: no box,
/// no colour). "All" is four dots; a workspace is its first letter, or its
/// first character when its name has no letter (`LivGlyph.initial`).
/// Hidden from VoiceOver: the name beside it says the same thing.
struct LivWorkspaceMark: View {
    let workspace: WorkspaceRow?
    let size: CGFloat

    var body: some View {
        Group {
            if let ws = workspace {
                LivIcon(glyph: .letter(ws.display), color: LivTheme.text, size: size)
            } else {
                LivIcon(glyph: .workspaces, color: LivTheme.text, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
