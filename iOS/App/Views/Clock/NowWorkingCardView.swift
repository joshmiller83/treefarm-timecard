import SwiftUI
import TimeCardCore

/// "Now working": where you are, and the lock screen's three next-row buttons and Break,
/// so the app and the lock screen work the same way.
struct NowWorkingCardView: View {
    var card: NowWorking
    var onMarkRow: (RowChip) -> Void
    var onBreak: () -> Void
    var onUndo: () -> Void
    var onMove: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Now working")
                    fieldLabel
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel("Now working")
                    Spacer(minLength: 8)
                    fieldLabel
                }
            }
            Text(card.place ?? card.done ?? "")
                .headingStyle(card.place == nil ? .tcHeadline : .tcTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("now-place")

            if card.onBreak {
                if let waiting = card.waiting {
                    Label(waiting, systemImage: "pause.circle")
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                }
            } else if !card.rows.isEmpty {
                buttons
            }

            if card.canUndo, let last = card.lastAction {
                undoLine(last)
            }

            if card.blocks.count > 1 {
                moveMenu
            }
        }
        .card()
    }

    @ViewBuilder
    private var fieldLabel: some View {
        if !card.fieldName.isEmpty {
            Label(card.fieldName, systemImage: "tree")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
        }
    }

    private var buttons: some View {
        let columns = typeSize.isAccessibilitySize ? 2 : 4
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(Array(card.rows.enumerated()), id: \.element.id) { index, chip in
                Button { onMarkRow(chip) } label: {
                    RowButtonLabel(chip: chip, showsBlock: card.showsBlock(chip))
                }
                .buttonStyle(TileButtonStyle(tone: .fir))
                .accessibilityLabel(card.showsBlock(chip) ? "Mark \(chip.blockName), \(chip.title.lowercased())" : "Mark \(chip.title.lowercased())")
                .accessibilityHint("Marks every open tree in the row shaped.")
                // Voice Control: "Tap Row 14" (the tile's words) or "Tap Mark row 14".
                .accessibilityInputLabels(["Row \(chip.row + 1)", "Mark row \(chip.row + 1)"])
                .accessibilityIdentifier("next-row-\(index)")
            }
            Button(action: onBreak) {
                VStack(spacing: 4) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title3)
                    Text("Break")
                        .font(.subheadline.weight(.bold))
                }
            }
            .buttonStyle(TileButtonStyle(tone: .sap))
            .accessibilityLabel("Take a break")
            .accessibilityInputLabels(["Break", "Take a break", "Start a break"])
            .accessibilityIdentifier("now-break")
        }
    }

    @ViewBuilder
    private func undoLine(_ last: String) -> some View {
        let label = Label(last, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(Palette.firText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("last-action")
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                label
                undoButton.frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
        } else {
            HStack(spacing: 12) {
                label
                undoButton
            }
            .padding(.top, 2)
        }
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Label("Undo", systemImage: "arrow.uturn.backward")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: GloveButtonStyle.minHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
        .accessibilityIdentifier("undo")
    }

    private var moveMenu: some View {
        let fields = Dictionary(grouping: card.blocks, by: \.fieldName)
        let order = card.blocks.map(\.fieldName).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return Menu {
            ForEach(order, id: \.self) { field in
                Section(field) {
                    ForEach(fields[field] ?? []) { block in
                        Button(block.title) { onMove(block.id) }
                    }
                }
            }
        } label: {
            Label("Move to another block", systemImage: "arrow.triangle.swap")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.gloveSecondary)
        .accessibilityIdentifier("move-block")
    }
}

/// "ROW / 14", with the block underneath when the row is in the next block.
private struct RowButtonLabel: View {
    var chip: RowChip
    var showsBlock: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("ROW")
                .font(.caption2.weight(.bold))
                .tracking(1)
            Text("\(chip.row + 1)")
                .numberStyle(.stat)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if showsBlock {
                Text(chip.blockName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// A square-ish tile for the row buttons: big, soft, and at least 72 pt tall.
struct TileButtonStyle: ButtonStyle {
    enum Tone { case fir, sap }
    var tone: Tone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tone == .fir ? Palette.firText : Palette.sapInk)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 6)
            .background(tone == .fir ? Palette.firSoft : Palette.sapSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder((tone == .fir ? Palette.fir : Palette.sap).opacity(0.35), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .pressScale(configuration.isPressed, 0.96)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
