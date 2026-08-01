// liv iOS — the template picker (design/editor-study.md §7, phase 4).
// One sheet, two verbs: start a new note from a template, or drop one in
// at the caret. Which verb it performs is the caller's business; the list
// is identical, because a template is a template.

import SwiftUI

// MARK: - the model: templates are a projection, never a registry

extension BoxModel {
    /// Every note wearing the marker cell, newest first. A query, not a
    /// list the app maintains — nothing to keep in sync, nothing to
    /// corrupt, and a template the user trashes simply stops matching.
    var templates: [EntityRow] {
        (snap?.everything ?? [])
            .compactMap { entity($0) }
            .filter { row in
                row.trashed != true && row.archived != true
                    && (row.cells ?? []).contains {
                        $0.property == Template.property && !($0.value ?? "").isEmpty
                    }
            }
            .sorted { ($0.created ?? 0, $0.id) > ($1.created ?? 0, $1.id) }
    }

    /// Mark a note as a template. Ruling 6: this COPIES — the note you
    /// were writing stays exactly where it is, and the copy becomes the
    /// template, so "save as template" never moves your work.
    func saveAsTemplate(_ source: UInt64, done: ((UInt64) -> Void)? = nil) {
        guard let row = entity(source) else {
            done?(0)
            return
        }
        content(source) { [weak self] doc in
            guard let self else {
                done?(0)
                return
            }
            let body = SpanText.spansToText(doc?.spans ?? [])
            // The template's name: the note's own name cell if a human set
            // one, else its FIRST LINE with markers off. Never row.title —
            // the wire's summary flattens the whole body, so a structured
            // note would be named "Sat 1 Aug ## Today - [ ] ## Notes".
            let named = (row.cells ?? [])
                .first { $0.property == "name" }?.value ?? ""
            let derived = livDisplayTitle(body)
            let name = named.isEmpty ? derived : named
            self.createNote { copy in
                guard copy != 0 else {
                    done?(0)
                    return
                }
                self.set(copy, "name", name.isEmpty ? "Template" : name)
                self.set(copy, Template.property, Template.marker)
                // Every cell the source carries, minus identity and the
                // marker itself — a template inherits filing, not history.
                for cell in row.cells ?? [] {
                    guard let property = cell.property, let value = cell.value,
                        !value.isEmpty, !Template.notInherited.contains(property)
                    else { continue }
                    self.addCell(copy, property, value)
                }
                if body.isEmpty {
                    done?(copy)
                } else {
                    self.setContent(
                        copy, spansJson: SpanText.json(SpanText.textToSpans(body)), base: 0
                    ) { _, _ in done?(copy) }
                }
            }
        }
    }

    /// A new note from a template: the resolved body, plus the template's
    /// property cells copied onto it as real, visible, removable values.
    /// `caret` is where the editor should put the cursor.
    func newFromTemplate(
        _ template: UInt64, now: Int64, done: @escaping (UInt64, Int?) -> Void
    ) {
        guard let row = entity(template) else {
            done(0, nil)
            return
        }
        content(template) { [weak self] doc in
            guard let self else {
                done(0, nil)
                return
            }
            let resolved = Template.resolve(
                SpanText.spansToText(doc?.spans ?? []), now: now)
            self.createNote { fresh in
                guard fresh != 0 else {
                    done(0, nil)
                    return
                }
                for cell in row.cells ?? [] {
                    guard let property = cell.property, let value = cell.value,
                        !value.isEmpty, !Template.notInherited.contains(property)
                    else { continue }
                    self.addCell(fresh, property, value)
                }
                guard !resolved.text.isEmpty else {
                    done(fresh, resolved.caret)
                    return
                }
                self.setContent(
                    fresh,
                    spansJson: SpanText.json(SpanText.textToSpans(resolved.text)), base: 0
                ) { _, _ in done(fresh, resolved.caret) }
            }
        }
    }

    /// The resolved body of a template, for inserting at the caret.
    func templateBody(_ template: UInt64, now: Int64, done: @escaping (String) -> Void) {
        content(template) { doc in
            done(Template.resolve(SpanText.spansToText(doc?.spans ?? []), now: now).text)
        }
    }
}

// MARK: - the sheet

struct TemplateSheet: View {
    enum Verb {
        case create
        case insert

        var title: String {
            switch self {
            case .create: return "New from template"
            case .insert: return "Insert template"
            }
        }
    }

    let verb: Verb
    let onPick: (EntityRow) -> Void

    @EnvironmentObject var box: BoxModel
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var trimmed: String { typed.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var rows: [EntityRow] {
        let all = box.templates
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            name($0).localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verb.title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            if box.templates.count > 5 {
                TextField("Search templates…", text: $typed)
                    .font(.system(size: 16))
                    .foregroundStyle(LivTheme.text)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel))
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            onPick(row)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 13))
                                    .foregroundStyle(LivTheme.text3)
                                    .frame(width: 18)
                                Text(name(row))
                                    .font(.system(size: 16))
                                    .foregroundStyle(LivTheme.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(LivTheme.border).frame(height: 0.5)
                        }
                    }
                    if rows.isEmpty {
                        EmptyHint(
                            "No templates yet. Any note can become one — open it and choose Save as template."
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func name(_ row: EntityRow) -> String {
        let clean = livDisplayTitle(row.title ?? "")
        return clean.isEmpty ? "Untitled" : clean
    }
}
