import SwiftUI
import TimeCardCore

/// One tree: who shaped it and when, its notes, and a way to add one.
struct TreeCardView: View {
    @Bindable var model: TreeMapModel
    var tree: TreeRef
    @Environment(\.dismiss) private var dismiss
    @State private var editing: NoteDraft?
    @State private var deleting: TreeCardInfo.Note?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Group {
                if let info = model.treeInfo(tree) {
                    content(info)
                } else {
                    ContentUnavailableView("This tree isn’t on the map anymore", systemImage: "tree")
                }
            }
            .screenBackground()
            .navigationTitle(model.treeInfo(tree)?.title ?? "Tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("tree-card-done")
                }
            }
        }
        .sheet(item: $editing) { draft in
            NoteEditorView(model: model, draft: draft, onGone: { problem = $0 })
                .presentationDetents([.large])
        }
        .confirmationDialog("Delete this note?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { note in
            Button("Delete note", role: .destructive) {
                problem = model.deleteNote(note.id)
            }
        } message: { note in
            Text("“\(note.body.prefix(80))” goes away for everyone on the farm.")
        }
    }

    private func content(_ info: TreeCardInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                status(info)
                if info.canToggle {
                    Button {
                        model.toggle(info.tree)
                    } label: {
                        Label(info.state == .thisShift ? "Unmark this tree" : "Mark this tree shaped",
                              systemImage: info.state == .thisShift ? "circle" : "checkmark.circle.fill")
                    }
                    .buttonStyle(GloveButtonStyle(kind: info.state == .thisShift ? .secondary : .primary))
                    .accessibilityIdentifier("tree-card-toggle")
                }
                // Above the notes, so it's in reach at the half-height card however many there are.
                Button {
                    editing = NoteDraft(tree: info.tree)
                } label: {
                    Label("Add a note", systemImage: "square.and.pencil")
                }
                .buttonStyle(info.canToggle ? .gloveSecondary : .glovePrimary)
                .accessibilityIdentifier("tree-card-add-note")
                if let problem { ErrorMessage(text: problem) }
                notes(info)
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    private func status(_ info: TreeCardInfo) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                switch info.state {
                case .notShaped: Circle().strokeBorder(Color.mapTreeEmpty, lineWidth: 3)
                case .thisShift: Circle().fill(Palette.sap)
                case .earlier: Circle().fill(Palette.fir)
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            Text(info.status)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tree-card-status")
        }
        .card()
    }

    @ViewBuilder private func notes(_ info: TreeCardInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(info.notes.isEmpty ? "Notes" : "Notes (\(info.notes.count))")
            if info.notes.isEmpty {
                Text("No notes on this tree yet. Add one for a broken leader, a dead tree or one to replant.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(info.notes) { note in
                NoteRow(note: note,
                        edit: { editing = NoteDraft(tree: info.tree, noteId: note.id, body: note.body, flag: note.flag) },
                        delete: { deleting = note })
            }
        }
    }
}

/// One note in the tree card.
private struct NoteRow: View {
    var note: TreeCardInfo.Note
    var edit: () -> Void
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.author).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(note.when).font(.footnote).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
            }
            if note.flag != .none {
                FlagPill(flag: note.flag)
            }
            Text(note.body)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if note.canEdit {
                HStack(spacing: 10) {
                    Button("Edit", action: edit)
                        .buttonStyle(.gloveSecondary)
                        .accessibilityLabel("Edit note")
                    Button(role: .destructive, action: delete) {
                        Text("Delete")
                            .font(.headline)
                            .foregroundStyle(Palette.rust)
                            .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rust.opacity(0.45), lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete note")
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tree-note")
    }
}

/// "Needs attention", "Dead", "Replant".
struct FlagPill: View {
    var flag: NoteFlag

    var body: some View {
        let look = FlagLook(flag)
        Label(flag.label, systemImage: look.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(look.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(look.fill, in: Capsule())
    }
}

/// How a note flag looks: its icon and colors.
struct FlagLook {
    var icon: String
    var ink: Color
    var fill: Color

    init(_ flag: NoteFlag) {
        switch flag {
        case .none: (icon, ink, fill) = ("note.text", Palette.muted, Palette.stripe)
        case .attention: (icon, ink, fill) = ("exclamationmark.triangle.fill", Palette.sapInk, Palette.sapSoft)
        case .dead: (icon, ink, fill) = ("xmark.octagon.fill", Palette.rust, Palette.rust.opacity(0.14))
        case .replant: (icon, ink, fill) = ("leaf.arrow.triangle.circlepath", Palette.firText, Palette.firSoft)
        }
    }
}

/// A note being written or changed.
struct NoteDraft: Identifiable, Equatable {
    var tree: TreeRef
    var noteId: UUID?
    var body = ""
    var flag: NoteFlag = .none

    var id: String { noteId?.uuidString ?? "new-\(tree.blockId.uuidString)-\(tree.row)-\(tree.position)" }
}

/// Writes or edits a tree note: the text (dictation works from the keyboard's mic) and a flag.
struct NoteEditorView: View {
    @Bindable var model: TreeMapModel
    @State var draft: NoteDraft
    /// The note was deleted on another phone while this was open: the editor closes and says so.
    var onGone: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("What’s going on with this tree?", text: $draft.body, axis: .vertical)
                        .lineLimit(4...10)
                        .font(.body)
                        .padding(14)
                        .frame(minHeight: 120, alignment: .topLeading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        .focused($focused)
                        .accessibilityLabel("Note")
                        .accessibilityIdentifier("note-body")
                        .onChange(of: draft.body) { _, text in
                            if text.count > Limits.notes { draft.body = String(text.prefix(Limits.notes)) }
                        }
                    if draft.body.count > Limits.notes - 200 {
                        Text("\(Limits.notes - draft.body.count) characters left")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                    SectionLabel("Flag")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(NoteFlag.allCases, id: \.self) { flag in
                            flagButton(flag)
                        }
                    }
                    if let problem { ErrorMessage(text: problem) }
                    Button(draft.noteId == nil ? "Save note" : "Save changes") { save() }
                        .buttonStyle(.glovePrimary)
                        .disabled(draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("note-save")
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(draft.noteId == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = draft.noteId == nil }
        }
    }

    private func flagButton(_ flag: NoteFlag) -> some View {
        let selected = draft.flag == flag
        let look = FlagLook(flag)
        return Button {
            draft.flag = flag
        } label: {
            Label(flag.label, systemImage: selected ? "checkmark.circle.fill" : look.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? look.ink : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
                .background(selected ? look.fill : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? look.ink.opacity(0.5) : Palette.line, lineWidth: selected ? 1.5 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("note-flag-\(flag.rawValue)")
    }

    private func save() {
        if let id = draft.noteId {
            if let problem = model.editNote(id, body: draft.body, flag: draft.flag) {
                if problem == MarkMessages.noteGone {
                    onGone(problem)
                    dismiss()
                } else {
                    self.problem = problem
                }
                return
            }
        } else {
            let reply = model.addNote(draft.tree, body: draft.body, flag: draft.flag)
            guard reply.succeeded else {
                problem = reply.speech
                return
            }
        }
        dismiss()
    }
}
