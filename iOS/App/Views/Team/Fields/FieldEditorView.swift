import SwiftUI
import TimeCardCore

/// One field: its map (tap a block to edit it), its blocks, and adding, renaming and
/// archiving.
struct FieldEditorView: View {
    var fieldId: UUID
    @Environment(TimeCardSession.self) private var session
    @State private var editor: BlockEditorTarget?
    @State private var renaming = false
    @State private var confirmingArchive = false
    @State private var problem: String?

    var body: some View {
        ScrollView {
            if let field = session.snapshot.fields[fieldId] {
                content(field).teamPage()
            } else {
                Text("This field is gone.").font(.body).foregroundStyle(Palette.muted).teamPage()
            }
        }
        .screenBackground()
        .navigationTitle(session.snapshot.fields[fieldId]?.name ?? "Field")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { target in
            BlockEditorSheet(fieldId: fieldId, target: target)
        }
        .sheet(isPresented: $renaming) {
            FieldNameSheet(field: session.snapshot.fields[fieldId])
        }
    }

    @ViewBuilder
    private func content(_ field: Field) -> some View {
        let snapshot = session.snapshot
        let blocks = FieldWalker(blocks: snapshot.blocks.values.filter { $0.fieldId == fieldId }).blocks
        let season = snapshot.farm?.activeSeasonId
        let ids = Set(blocks.map(\.id))
        let marks = snapshot.marks.values.filter { $0.seasonId == season && ids.contains($0.blockId) }
        let index = MarkIndex(marks: Array(marks))
        let total = blocks.reduce(0) { $0 + $1.treeCount }
        let shaped = blocks.reduce(0) { $0 + index.shapedCount(in: $1) }

        VStack(alignment: .leading, spacing: 16) {
            if field.archivedAt != nil {
                NoticeBox(systemImage: "archivebox") {
                    Text("Archived. This field is off the crew’s map until you put it back.")
                        .font(.subheadline).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                MiniMapView(blocks: blocks, shaped: marks.map(\.tree), maxHeight: 240,
                            accessibilityText: MiniMapView.describe(fieldName: field.name, blocks: blocks)) { id in
                    if let block = blocks.first(where: { $0.id == id }) { editor = .edit(block) }
                }
                Text("\(Fmt.plural(blocks.count, "block")) · \(Fmt.plural(total, "tree")) · \(Fmt.count(shaped)) shaped this season")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                if !blocks.isEmpty {
                    Text("Tap a block on the map or in the list to change it.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
            }
            .card()

            if !blocks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Blocks")
                    VStack(spacing: 0) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { i, block in
                            if i > 0 { RowDivider().padding(.leading, 16) }
                            BlockRow(block: block, shaped: index.shapedCount(in: block)) { editor = .edit(block) }
                        }
                    }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                }
            }

            Button { editor = .add } label: {
                Label("Add a block", systemImage: "plus.square")
            }
            .buttonStyle(.glovePrimary)
            .accessibilityIdentifier("block-add")

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Field")
                Button { renaming = true } label: {
                    Label("Rename field", systemImage: "character.cursor.ibeam")
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityIdentifier("field-rename")
                if field.archivedAt == nil {
                    Button { confirmingArchive = true } label: {
                        Label("Archive field", systemImage: "archivebox")
                    }
                    .buttonStyle(.gloveSecondary)
                    .accessibilityIdentifier("field-archive")
                } else {
                    Button { apply(FieldPlans.restore(field, now: Date())) } label: {
                        Label("Put back on the map", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.gloveSecondary)
                    .accessibilityIdentifier("field-restore")
                }
                if let problem { ErrorMessage(text: problem) }
            }
        }
        .confirmationDialog("Archive \(field.name)?", isPresented: $confirmingArchive, titleVisibility: .visible) {
            Button("Archive field") { apply(FieldPlans.archive(field, now: Date())) }
            Button("Keep it on the map", role: .cancel) {}
        } message: {
            Text("It leaves the crew’s map. Its blocks, shaped trees and notes stay, and you can put it back any time.")
        }
    }

    private func apply(_ edit: TeamEdit) {
        do {
            problem = try TeamSave.apply(edit, in: session)
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// What the block sheet is for.
enum BlockEditorTarget: Identifiable, Equatable {
    case add
    case edit(Block)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let block): block.id.uuidString
        }
    }
}

/// "Block 2 · 61 rows × 10 trees · rows run across" with what's shaped.
private struct BlockRow: View {
    var block: Block
    var shaped: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .rotationEffect(block.direction == .down ? .degrees(90) : .zero)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.firText)
                    .frame(width: 40, height: 40)
                    .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.displayName).font(.headline).foregroundStyle(Palette.ink)
                    Text("\(Fmt.plural(block.rowCount, "row")) × \(Fmt.plural(block.treesPerRow, "tree")) · rows run \(block.direction.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.count(shaped)).numberStyle(.body).foregroundStyle(shaped > 0 ? Palette.firText : Palette.muted)
                    Text("of \(Fmt.count(block.treeCount))").font(.caption).foregroundStyle(Palette.muted)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.displayName), \(Fmt.plural(block.rowCount, "row")) of \(Fmt.plural(block.treesPerRow, "tree")), rows run \(block.direction.rawValue). \(Fmt.count(shaped)) of \(Fmt.count(block.treeCount)) shaped.")
        .accessibilityIdentifier("block-row-\(block.displayName)")
    }
}
