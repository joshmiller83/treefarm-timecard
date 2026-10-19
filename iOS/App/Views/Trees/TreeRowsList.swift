import SwiftUI
import TimeCardCore

/// The map as a list: blocks, then rows. It's what VoiceOver users get, and anyone can switch
/// to it. Each row is one element: double-tap marks or clears it (like tapping its number),
/// swipe up or down marks or unmarks one tree, and "Trees in this row" lists every tree.
struct TreeRowsList: View {
    @Bindable var model: TreeMapModel
    @State private var detail: RowRef?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(model.blocks) { block in
                    Section {
                        ForEach(0..<max(0, block.rowCount), id: \.self) { row in
                            RowCell(model: model, row: RowRef(blockId: block.id, row: row), block: block) {
                                detail = RowRef(blockId: block.id, row: row)
                            }
                            Divider().overlay(Palette.line).padding(.leading, 16)
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(block.displayName).headingStyle(.tcHeadline)
                            Spacer()
                            Text(model.blockSummary(block)).font(.footnote).foregroundStyle(Palette.muted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
        .accessibilityIdentifier("tree-rows-list")
        .sheet(item: Binding(get: { detail.map(RowSheet.init) }, set: { detail = $0?.row })) { sheet in
            RowDetailView(model: model, row: sheet.row)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct RowSheet: Identifiable {
    var row: RowRef
    var id: String { "\(row.blockId.uuidString)-\(row.row)" }
}

private struct RowCell: View {
    @Bindable var model: TreeMapModel
    var row: RowRef
    var block: Block
    var openDetail: () -> Void

    var body: some View {
        let summary = model.rowSummary(row)
        HStack(spacing: 12) {
            Button {
                model.tapRow(row)
            } label: {
                HStack(spacing: 12) {
                    Text("\(row.row + 1)")
                        .font(.tcNumber.weight(.semibold))
                        .foregroundStyle(summary.map { $0.shaped == $0.total } == true ? Palette.firText : Palette.ink)
                        .frame(minWidth: 34, alignment: .trailing)
                    RowBar(shaped: summary?.shaped ?? 0, mine: summary?.mine ?? 0, total: summary?.total ?? 1)
                    if (summary?.notes ?? 0) > 0 {
                        NoteCorner().fill(Palette.rust).frame(width: 10, height: 10)
                    }
                    Text(summary.map { "\($0.shaped)/\($0.total)" } ?? "")
                        .font(.tcNumberSmall)
                        .foregroundStyle(Palette.muted)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: openDetail) {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: GloveButtonStyle.minHeight, height: GloveButtonStyle.minHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trees in this row")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(block.label(row: row.row))
        .accessibilityValue(summary?.value ?? "")
        .accessibilityHint("Double-tap to mark or clear the row. Swipe up or down to mark or unmark one tree.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapRow(row) }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.adjust(row, up: true)
            case .decrement: model.adjust(row, up: false)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Trees in this row", openDetail)
        .accessibilityIdentifier("row-\(block.name)-\(row.row + 1)")
    }
}

/// How much of a row is shaped: green for earlier shifts, gold for this one.
private struct RowBar: View {
    var shaped: Int
    var mine: Int
    var total: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let total = CGFloat(max(1, self.total))
            HStack(spacing: 0) {
                Rectangle().fill(Palette.fir).frame(width: width * CGFloat(shaped - mine) / total)
                Rectangle().fill(Palette.sap).frame(width: width * CGFloat(mine) / total)
                Spacer(minLength: 0)
            }
            .background(Palette.firSoft)
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Every tree in one row: tap to mark or unmark, or open its card for notes.
struct RowDetailView: View {
    @Bindable var model: TreeMapModel
    var row: RowRef
    @Environment(\.dismiss) private var dismiss
    @State private var card: OpenTree?

    var body: some View {
        NavigationStack {
            List {
                if let message = model.message, message.tone != .hint {
                    Text(message.text).font(.callout).foregroundStyle(Palette.muted)
                }
                ForEach(model.trees(in: row), id: \.self) { tree in
                    HStack(spacing: 12) {
                        Button {
                            model.toggle(tree)
                        } label: {
                            Text(model.treeLine(tree))
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Double-tap to mark or unmark this tree.")
                        Button("Notes") { card = OpenTree(tree: tree) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.firText)
                            .frame(minWidth: GloveButtonStyle.minHeight, minHeight: GloveButtonStyle.minHeight)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Notes for tree \(tree.position + 1)")
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(model.data?.block(row.blockId)?.label(row: row.row) ?? "Row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $card) { open in
                TreeCardView(model: model, tree: open.tree)
            }
        }
    }
}
