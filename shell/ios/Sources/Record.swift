// liv iOS — the RECORD CARD. A task and an event are not documents, and
// until 2026-08-06 the desk edited them as if they were: every tab, of
// every kind, rendered NoteEditor, so a task's name was line 1 of a
// markdown buffer and its properties hid behind a swipe. The owner
// named it — "things that aren't documents should not be edited like a
// document" — and this is the answer.
//
// A record is a NAME, its FACTS, and (optionally) some notes. The name
// is one line and commits on return. The facts are the inspector's own
// rows, embedded as the body rather than hidden behind the (i) door —
// on a task, the due date IS the content.
//
// The NOTES used to be a plain TextEditor, on the reasoning that "the
// markdown apparatus belongs to notes, which is what notes are for".
// That is reversed as of 2026-08-10, on the owner's question: "there is
// already a note editor — can this and other app mechanisms be reused?"
// It can, and the reasoning was wrong twice over. A record's notes are
// content spans on the record entity — the SAME data a note's body is,
// so the plain field was not a different kind of thing, only a worse
// way of editing the same thing. And what it withheld is what a task
// most wants: a CHECKLIST, and a [[link]] to the note or project the
// task belongs to. The editor is now embedded here without its title
// line, which the card supplies.

import SwiftUI

/// What a thing IS, which decides where it opens: a document lands as a
/// tab, a record rises as a card over wherever you stand. Derived from
/// the entity's kinds, never from where it was tapped — the same task
/// behaves the same from the calendar, from Tasks, and from search.
enum TabShape {
    case document
    case record
    case file

    /// A FILE is checked first, because having a file crosscuts the six
    /// kinds — a scanned contract is a file and can also be a task, and
    /// what you want to see is the contract. Before this it fell through
    /// to `.document` and opened as an empty markdown editor over a real
    /// file (shipped bug, found 2026-08-08).
    ///
    /// Then: a note, a template, and an untyped CAPTURE (no kinds at
    /// all, its title derived from its own first line) are documents.
    /// Everything with a declared type that isn't a note is a record.
    static func of(_ row: EntityRow?) -> TabShape {
        if FileFacts.of(row) != nil { return .file }
        let kinds = row?.kinds ?? []
        if kinds.isEmpty { return .document }
        if kinds.contains("note") { return .document }
        return .record
    }
}

// MARK: - the card

/// A record, edited over whatever you were looking at. Half height at
/// first — a task's facts fill a card, not a screen (owner, 2026-08-07:
/// "a tab that just contains the properties view feels broken") — and
/// draggable taller when its notes want the room.
///
/// Swiping it down MINIMISES rather than closes: the pill above the
/// bottom bar brings it back, so you can go read something and return
/// (owner, 2026-08-08). Every edit inside saves as you make it, so the
/// card holds nothing that could be lost.
struct RecordCard: View {
    let id: UInt64
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel
    /// The embedded editor's [[ picker offers a Create row, which stamps
    /// the active workspace. Without this the card would trap the first
    /// time anyone created an entity from a link.
    @EnvironmentObject var workspaces: WorkspaceModel

    var body: some View {
        // The same focus request a new note claims: "New task" must land
        // you typing the name, not looking at an empty field.
        RecordBody(id: id, autoFocus: desk.consumeFocus(id) != nil, inCard: true)
            // A card is a NEW view per record. Following a [[link]] from
            // one record to another only reassigns desk.recordCard, so
            // without this SwiftUI reuses the view and the embedded
            // editor's model stays attached to the record you LEFT —
            // showing B's name and facts while writing into A.
            .id(id)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(LivTheme.surface)
            .environmentObject(box)
            .environmentObject(desk)
            .environmentObject(workspaces)
    }
}

/// The pill a minimised card leaves behind. One at a time.
struct MinimisedRecordPill: View {
    let id: UInt64
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                desk.restoreRecord()
            } label: {
                HStack(spacing: 8) {
                    IconChip(
                        glyph: LivKind.glyph(of: box.entity(id)),
                        color: LivKind.color(of: box.entity(id)), size: 22,
                        on: LivTheme.panel2)
                    Text(box.entity(id).map(livRowTitle) ?? "Untitled")
                        .font(.system(size: LivType.body, weight: .medium))
                        .foregroundStyle(LivTheme.text)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                desk.dropMinimised()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: LivType.caption, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(height: 38)
        .background(Capsule().fill(LivTheme.panel2))
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

}

/// Attach to every surface that can be standing when a record opens.
///
/// Exactly ONE of them may be active at a time. UIKit gives a presenter
/// one presentation, so if the desk tried to raise the card while a
/// full-screen feature window was up, the window was torn down first —
/// which is the very context exit Option C exists to stop (found live,
/// 2026-08-08). Each cover presents its own; the desk presents only
/// when nothing covers it.
struct RecordCardHost: ViewModifier {
    let active: Bool
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { active && desk.recordCard != nil },
                set: { if !$0 { desk.minimiseRecord() } })
        ) {
            if let id = desk.recordCard {
                RecordCard(id: id)
            }
        }
    }
}

extension View {
    func recordCardHost(active: Bool) -> some View {
        modifier(RecordCardHost(active: active))
    }
}

struct RecordBody: View {
    let id: UInt64
    /// A record created a moment ago: open with the caret in the name.
    var autoFocus: Bool = false
    /// Inside a card there are no floating doors overhead, so the name
    /// does not need to duck under them.
    var inCard: Bool = false

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel

    @State private var name = ""
    @State private var seeded = false
    @State private var notesShown = false
    @State private var claimed = false
    /// The name already handed to the box and not yet visible in the
    /// snapshot. Return commits, then the blur commits again a beat
    /// later — without this the box logged the same rename twice
    /// (found live, 2026-08-06).
    @State private var pendingName: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if let row = box.entity(id) {
                body(row)
            } else {
                EmptyHint("This entity is not in the box anymore.")
                    .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            seed()
            claimFocus()
        }
        // The parent sets autoFocus in ITS onAppear, which runs AFTER
        // this one — the same ordering the note editor works around.
        .onChange(of: autoFocus) { _, now in
            if now { claimFocus() }
        }
        .onChange(of: storedName) { old, fresh in
            if pendingName == fresh { pendingName = nil }
            // The same reseed guard the note title uses: an external
            // rename must land, a live edit must not be stomped.
            if name != fresh, name == "" || name == old { name = fresh }
        }
    }

    private func body(_ row: EntityRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                nameField(row)
                // The facts, as the body. Same rows as the (i) panel —
                // one implementation, so a due date edited here and a due
                // date edited there are the same code.
                EntityInspector(id: id, scrolls: false)
                notesSection
            }
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: the name — one line, because a name is one line

    private func nameField(_ row: EntityRow) -> some View {
        TextField(placeholder(row), text: $name, axis: .vertical)
            .font(.system(size: LivType.hero, weight: .semibold))
            .foregroundStyle(LivTheme.text)
            .lineLimit(1...3)
            .focused($nameFocused)
            .submitLabel(.done)
            .onSubmit(commitName)
            .onChange(of: nameFocused) { _, now in
                if !now { commitName() }
            }
            .padding(.horizontal, 16)
            .padding(.top, inCard ? 18 : 56)
            .padding(.bottom, 14)
    }

    /// A record with no name cell still has a title everywhere else in
    /// the app — the core derives one from its first line. Showing
    /// "Untitled" here would contradict the list you just tapped, so the
    /// derived name is the PROMPT: it reads right, and typing over it is
    /// what writes the name. Nothing is written by merely opening it.
    private func placeholder(_ row: EntityRow) -> String {
        let derived = livRowTitle(row)
        if derived != "Untitled" { return derived }
        return (row.kinds ?? []).contains("event") ? "New event" : "Untitled"
    }

    private var storedName: String {
        (box.entity(id)?.cells ?? []).first { $0.property == "name" }?.value ?? ""
    }

    /// @FocusState set during a view update is dropped; one runloop hop
    /// later it takes.
    private func claimFocus() {
        guard autoFocus, !claimed else { return }
        claimed = true
        DispatchQueue.main.async { nameFocused = true }
    }

    private func seed() {
        guard !seeded else { return }
        name = storedName
        seeded = true
        // A record that already carries notes opens with them showing;
        // an empty one does not offer a text box nobody asked for.
        notesShown = (box.entity(id)?.contentPrint ?? 0) != 0
    }

    private func commitName() {
        guard let row = box.entity(id), row.trashed != true else { return }
        let stored = storedName
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            name = stored  // an emptied field reverts, never erases the name
            return
        }
        guard typed != stored, typed != pendingName else { return }
        pendingName = typed
        box.set(id, "name", typed)
    }

    // MARK: notes — the note editor, embedded

    @ViewBuilder private var notesSection: some View {
        if notesShown {
            SectionLabel("Notes")
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 2)
            // The REAL editor, minus its title line — the card names the
            // record above it. Checkboxes, [[links]], markdown styling
            // and the keyboard toolbar all come with it, and the second,
            // worse text editor this used to be is gone (owner,
            // 2026-08-10). A tapped link opens as a tab, which closes
            // this card on its way out (openDocument clears it).
            NoteEditor(
                id: id,
                title: .constant(""),
                onTitleCommit: {},
                // A token whose target is not in this box LOOKS like a
                // link but saves as text (ruling 5) — tapping it must
                // not open a dead tab. The desk's own call site obeys
                // this (Desk.swift); the card must too.
                onOpenRef: { target in
                    if box.entity(target) != nil { desk.open(target) }
                },
                showsTitle: false,
                embedded: true
            )

        } else {
            Button {
                withAnimation(LivMotion.nav) { notesShown = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: LivType.caption, weight: .semibold))
                    Text("Add notes")
                        .font(.system(size: LivType.body, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(LivTheme.accent)
                .frame(height: 44)
                .contentShape(Rectangle())
            }            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}
