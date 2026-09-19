// liv iOS — the WORKSPACE SWITCHER and its form.
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
    let forFilter: Bool
    var id: String { "\(property)-\(forFilter)" }
}

// MARK: - the workspace switcher (M4)

/// The hub's sheet: All (no lens), every workspace, and
/// the new-workspace form. Switching swaps the desk's open tabs — one tab
/// plane, remembered per workspace.
struct WorkspaceSwitcher: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @EnvironmentObject var desk: DeskModel
    /// How this closes. It hangs from the workspace button now (a top
    /// sheet in the hierarchy), so there is no sheet environment to
    /// dismiss — the presenter hands it the way out.
    var onClose: () -> Void

    @State private var composing = false
    /// nil while composing a NEW workspace; the id being edited otherwise.
    /// Editing exists because the box ships a seeded "Home" workspace: with
    /// a create-only form it could never become a workspace at all.
    @State private var editing: LivEntityID?
    @State private var draftName = ""
    @State private var draftQuery = ""
    @State private var composingFilter = false
    @State private var filterName = ""
    @State private var filterQuery = ""
    /// Which picker row is open, and whose draft it edits.
    @State private var picking: WorkspacePick?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                // A FORM SHOWS THE FORM AND NOTHING ELSE.
                //
                // The rule is the owner's, from 2026-08-13: a list of
                // workspaces above a filter you are naming is the wrong
                // screen. It was applied to the FILTER form and not to
                // the workspace one, so naming a workspace left the whole
                // list of workspaces sitting above the field — the same
                // shape of miss as the chip row that kept its border
                // after the rule said otherwise (rev 83).
                //
                // The title says which form it is, so the card is never
                // unlabelled, and editing gets an honest one instead of
                // borrowing the word "Workspace" from the list it
                // replaces.
                if composingFilter {
                    LivMenuTitle(text: "New filter")
                    newFilterForm
                } else if composing {
                    LivMenuTitle(text: editing == nil ? "New workspace" : "Edit workspace")
                    newWorkspaceForm
                } else {
                    // The SAME title and rows the `+` menu wears (owner,
                    // 2026-08-17: bigger text, simpler). This card used
                    // to draw its own smaller, denser list.
                    LivMenuTitle(text: "Workspace")
                    choice(
                        name: "All", active: workspaces.activeId == 0,
                        glyph: .workspaces, divided: false
                    ) {
                        choose(0)
                    }
                    ForEach(Array(workspaces.workspaces.enumerated()), id: \.element.id) { _, ws in
                        choice(
                            name: ws.display, active: workspaces.activeId == ws.id,
                            glyph: .workspace, emoji: ws.emoji, divided: true
                        ) {
                            choose(ws.id)
                        }
                        .contextMenu {
                            Button {
                                editing = ws.id
                                draftName = ws.display
                                draftQuery = workspaces.query(of: ws.id) ?? ""
                                composing = true
                            } label: {
                                Label("Edit workspace", systemImage: "slider.horizontal.3")
                            }
                            Button(role: .destructive) {
                                workspaces.forgetQuery(ws.id)
                                if workspaces.activeId == ws.id { choose(0, close: false) }
                                box.trashWorkspace(ws.id)
                            } label: {
                                Label("Trash workspace", systemImage: "trash")
                            }
                        }
                    }
                    // Filters LIVE in the library panel now; only their
                    // form is still here, opened by the panel's
                    // "New filter…".
                    addRow("New workspace…") {
                        editing = nil
                        draftName = ""
                        draftQuery = ""
                        composing = true
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The ROWS carry their own 16pt inset, like the menu's; only the
        // forms below need the card's.
        .padding(.vertical, 4)
        // No .presentationDetents: it is not a sheet any more. It hangs
        // from the workspace button at the top (LivTopSheetHost), which
        // sizes itself to this content and scrolls only when it must.
        .onAppear {
            if desk.composeFilter {
                composingFilter = true
                desk.composeFilter = false
            }
        }
        // The SAME picker the properties panel uses, told to report the
        // choice instead of writing a cell.
        .sheet(item: $picking) { pick in
            InspectorValueSheet(
                field: InspectorField.describe(pick.property, in: box.snap),
                id: 0,
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
        let raw: String = pick.forFilter ? filterQuery : draftQuery
        let terms: [BoxModel.LivQueryTerm] = box.lex(raw)
        let next: String = LivTerms.setting(pick.property, to: value, in: terms)
        if pick.forFilter { filterQuery = next } else { draftQuery = next }
    }

    private func choose(_ id: LivEntityID, close: Bool = true) {
        workspaces.setActive(id)
        if close { onClose() }
    }

    /// One workspace to switch to. The row is the app's ONE row — the
    /// same one the `+` menu draws (LivMenuRow) — because a list of
    /// things to choose from should not look different depending on
    /// which card it is in (owner, 2026-08-17).
    ///
    /// The lens chips that used to sit under each name are gone with the
    /// smaller type they belonged to. A workspace's lens is still on
    /// screen where it acts: the filter chip in every view's header, and
    /// the filters in the menu.
    private func choice(
        name: String, active: Bool, glyph: LivGlyph,
        emoji: String? = nil, divided: Bool, action: @escaping () -> Void
    ) -> some View {
        LivMenuRow(
            label: name, glyph: glyph, emoji: emoji, selected: active, divided: divided,
            action: action)
    }

    private func addRow(_ label: String, action: @escaping () -> Void) -> some View {
        LivMenuRow(label: label, symbol: "plus", divided: true, action: action)
    }

    // MARK: the new-workspace form — name + query + the stamp hint

    private var newWorkspaceForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Name", text: $draftName)
            lensRows($draftQuery, forFilter: false)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") {
                    composing = false
                    editing = nil
                }
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
        _ query: Binding<String>, forFilter: Bool
    ) -> some View {
        ForEach(["area", "tags"], id: \.self) { property in
            let value: String? = pickedValue(property, in: query.wrappedValue)
            Button {
                picking = WorkspacePick(property: property, forFilter: forFilter)
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
                    Rectangle().fill(LivTheme.border).frame(height: 0.5)
                }
            }
        }
    }

    private var newFilterForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Name", text: $filterName)
            lensRows($filterQuery, forFilter: true)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") {
                    composingFilter = false
                }
                // text2, not text3. A control is not a placeholder, and
                // text3 is the tier the palette check exempts from the
                // read floor on the grounds that it holds placeholders
                // and timestamps (rev 79). It stays QUIETER than the
                // filled pill beside it, which is the pair a form wants:
                // one primary, one way out.
                .font(.system(size: LivType.body, weight: .medium))
                .foregroundStyle(LivTheme.text2)
                .buttonStyle(.plain)
                ConfirmPill("Save", action: createFilter)
                .disabled(trimmed(filterName).isEmpty || trimmed(filterQuery).isEmpty)
                .opacity(
                    trimmed(filterName).isEmpty || trimmed(filterQuery).isEmpty ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
            write(query, to: id)
            finish(id)
        } else {
            box.createWorkspace(name: name) { id in
                guard !id.isAbsent else { return }
                write(query, to: id)
                finish(id)
            }
        }
    }

    /// The `query` cell IS the workspace. An emptied query clears the cell
    /// rather than leaving a stale lens behind.
    private func write(_ query: String, to id: LivEntityID) {
        if query.isEmpty {
            box.unset(id, "query")
        } else {
            box.set(id, "query", query)
            for cell in LivTerms.stamps(box.lex(query)) where cell.property != "type" {
                box.addProperty(cell.property)
            }
        }
        workspaces.rememberQuery(id, query)
    }

    private func finish(_ id: LivEntityID) {
        draftName = ""
        draftQuery = ""
        composing = false
        editing = nil
        choose(id)
    }

    private func createFilter() {
        let name = trimmed(filterName)
        let query = trimmed(filterQuery)
        guard !name.isEmpty, !query.isEmpty else { return }
        box.createView(name: name, query: query) { id in
            guard !id.isAbsent else { return }
            filterName = ""
            filterQuery = ""
            composingFilter = false
            workspaces.activeFilterId = id
        }
    }
}
