import SwiftUI
import TimeCardCore

/// "Type row and tree numbers": for when tapping tiny dots with gloves on is no fun.
struct TypeNumbersSheet: View {
    @Bindable var model: TreeMapModel
    @Environment(\.dismiss) private var dismiss
    @State private var blockId: UUID?
    @State private var fromRow = ""
    @State private var toRow = ""
    @State private var fromTree = ""
    @State private var toTree = ""
    @FocusState private var focus: Box?

    private enum Box: Hashable { case fromRow, toRow, fromTree, toTree }

    private var block: Block? {
        model.blocks.first { $0.id == blockId } ?? model.blocks.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.blocks.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Block")
                            Menu {
                                Picker("Block", selection: Binding(get: { block?.id }, set: { blockId = $0 })) {
                                    ForEach(model.blocks) { b in
                                        Text(b.displayName).tag(Optional(b.id))
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(block?.displayName ?? "")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down").foregroundStyle(Palette.firText)
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: GloveButtonStyle.minHeight)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                            }
                            .accessibilityLabel("Block")
                            .accessibilityValue(block?.displayName ?? "")
                            .accessibilityIdentifier("type-block")
                        }
                    }
                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            number("From row", text: $fromRow, prompt: block.map { "1–\($0.rowCount)" } ?? "", box: .fromRow)
                            number("To row", text: $toRow, prompt: "same row", box: .toRow)
                        }
                        GridRow {
                            number("From tree", text: $fromTree, prompt: "1", box: .fromTree)
                            number("To tree", text: $toTree, prompt: block.map { "\($0.treesPerRow)" } ?? "", box: .toTree)
                        }
                    }
                    if let message = model.message, message.tone != .hint {
                        Label(message.text, systemImage: message.tone == .done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(message.tone == .done ? Palette.firText : Palette.sapInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("type-message")
                    }
                    HStack(spacing: 10) {
                        Button("Mark") { apply(add: true) }
                            .buttonStyle(.glovePrimary)
                            .accessibilityIdentifier("type-mark")
                        Button("Unmark") { apply(add: false) }
                            .buttonStyle(.gloveSecondary)
                            .accessibilityIdentifier("type-unmark")
                    }
                    .disabled(Int(fromRow) == nil)
                    Text("Leave “To row” empty for one row. Leave the tree numbers empty for the whole row.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationTitle("Type Numbers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if model.message?.tone != .hint { model.show(nil) }
                focus = .fromRow
            }
        }
    }

    private func number(_ title: String, text: Binding<String>, prompt: String, box: Box) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            TextField(prompt, text: text)
                .keyboardType(.numberPad)
                .font(.tcNumber)
                .textFieldStyle(.glove)
                .focused($focus, equals: box)
                .accessibilityLabel(title)
                .accessibilityIdentifier("type-\(box)")
        }
    }

    private func apply(add: Bool) {
        guard let block, let first = Int(fromRow) else { return }
        let changed = model.typeRange(blockId: block.id, fromRow: first, toRow: Int(toRow), fromTree: Int(fromTree), toTree: Int(toTree), add: add)
        if changed {
            focus = nil
        }
    }
}
