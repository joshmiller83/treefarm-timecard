import SwiftUI
import TimeCardCore

/// Every field with a small map of its blocks. A field opens its editor; archived fields
/// sit at the bottom and can be put back.
struct FieldsSection: View {
    /// Opens a field's editor (a new field opens right away, so its blocks come next).
    var open: (UUID) -> Void
    @Environment(TimeCardSession.self) private var session
    @State private var adding = false
    @State private var added: UUID?

    var body: some View {
        let snapshot = session.snapshot
        let fields = FieldPlans.sorted(Array(snapshot.fields.values))
        let blocks = Dictionary(grouping: snapshot.blocks.values, by: \.fieldId)
        let season = snapshot.farm?.activeSeasonId
        let shaped = Dictionary(grouping: snapshot.marks.values.filter { $0.seasonId == season }.map(\.tree), by: \.blockId)

        VStack(alignment: .leading, spacing: 16) {
            if fields.active.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No fields yet").headingStyle(.tcTitle2)
                    Text("Add a field, then lay out its blocks of rows and trees. The crew’s map follows what you set up here.")
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
            ForEach(fields.active) { field in
                let inField = blocks[field.id] ?? []
                FieldCard(field: field, blocks: inField, shaped: inField.flatMap { shaped[$0.id] ?? [] })
            }
            Button { adding = true } label: {
                Label("Add a field", systemImage: "plus")
            }
            .buttonStyle(.gloveSecondary)
            .accessibilityIdentifier("field-add")
            if !fields.archived.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Archived")
                    VStack(spacing: 0) {
                        ForEach(Array(fields.archived.enumerated()), id: \.element.id) { index, field in
                            if index > 0 { RowDivider().padding(.leading, 16) }
                            NavigationLink(value: TeamView.Route.field(field.id)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(field.name).font(.headline).foregroundStyle(Palette.muted)
                                        Text(Fmt.plural((blocks[field.id] ?? []).count, "block")).font(.subheadline).foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 64)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                    Text("Archived fields are off the crew’s map. Their blocks, shaped trees and notes are kept.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .sheet(isPresented: $adding, onDismiss: {
            if let added { open(added) }
            added = nil
        }) {
            FieldNameSheet(field: nil) { added = $0 }
        }
    }
}

/// A field: its name, a map of its strips of blocks, and its size.
private struct FieldCard: View {
    var field: Field
    var blocks: [Block]
    var shaped: [TreeRef]

    var body: some View {
        let live = blocks.filter { $0.deletedAt == nil }
        let total = live.reduce(0) { $0 + $1.treeCount }
        NavigationLink(value: TeamView.Route.field(field.id)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(field.name).font(.tcHeadline).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                }
                MiniMapView(blocks: live, shaped: shaped, maxHeight: 130,
                            accessibilityText: MiniMapView.describe(fieldName: field.name, blocks: live))
                Text("\(Fmt.plural(live.count, "block")) · \(Fmt.plural(total, "tree")) · \(Fmt.count(shaped.count)) shaped this season")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("field-\(field.name)")
    }
}

/// Names a new field, or renames one.
struct FieldNameSheet: View {
    var field: Field?
    /// Called with a new field's id after it's saved.
    var onAdded: (UUID) -> Void = { _ in }
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                LabeledGloveField(title: "Field name", prompt: "North Field", text: $name, identifier: "field-name",
                                  footnote: field == nil ? "You’ll add its blocks next." : nil)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                if let problem { ErrorMessage(text: problem) }
                Button(field == nil ? "Add field" : "Save name", action: save)
                    .buttonStyle(.glovePrimary)
                    .accessibilityIdentifier("field-name-save")
                Spacer()
            }
            .teamPage()
            .screenBackground()
            .navigationTitle(field == nil ? "New Field" : "Rename Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                name = field?.name ?? ""
                focused = true
            }
            .onChange(of: name) { problem = nil }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let farm = session.farm else { return }
        let edit = field.map { FieldPlans.rename($0, to: name, now: Date()) }
            ?? FieldPlans.add(name: name, farmId: farm.id, fields: Array(session.snapshot.fields.values), now: Date())
        do {
            if let text = try TeamSave.apply(edit, in: session) {
                problem = text
                return
            }
            if field == nil, case .save(let records) = edit, case .field(let new)? = records.first { onAdded(new.id) }
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
