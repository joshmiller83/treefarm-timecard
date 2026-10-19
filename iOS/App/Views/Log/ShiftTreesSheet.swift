import SwiftUI
import TimeCardCore

/// The trees one shift shaped, block by block, in the map's words.
struct ShiftTreesSheet: View {
    var shiftId: UUID
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let shift = session.snapshot.shifts[shiftId], let farm = session.farm {
                        content(shift: shift, calendar: FarmCalendar(farm: farm))
                    } else {
                        Text(LogWording.missing)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .card()
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationTitle("Trees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("trees-done")
                }
            }
        }
        .accessibilityIdentifier("shift-trees-sheet")
    }

    @ViewBuilder
    private func content(shift: Shift, calendar: FarmCalendar) -> some View {
        let trees = ShiftTrees(snapshot: session.snapshot)
        let blocks = trees.byBlock(shift.id, fields: Array(session.snapshot.fields.values))
        let total = trees.count(shift.id)
        let fields = session.snapshot.fields

        VStack(alignment: .leading, spacing: 6) {
            Text("\(Fmt.dayLong(shift.start, calendar)) · \(Fmt.time(shift.start, calendar)) – \(shift.end.map { Fmt.time($0, calendar) } ?? "now")")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.count(total)).numberStyle(.timer).foregroundStyle(Palette.firText)
                Text(total == 1 ? "tree shaped" : "trees shaped").font(.tcHeadline).foregroundStyle(Palette.ink)
            }
        }
        .accessibilityElement(children: .combine)

        if blocks.isEmpty {
            Text("No trees are marked on this shift.")
                .font(.body)
                .foregroundStyle(Palette.muted)
                .card()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.element.block.id) { index, item in
                    if index > 0 { Divider().overlay(Palette.line) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.block.displayName).font(.tcHeadline).foregroundStyle(Palette.ink)
                            if let field = fields[item.block.fieldId], fields.count > 1 {
                                Text(field.name).font(.subheadline).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Text(Fmt.plural(item.count, "tree")).numberStyle(.body).foregroundStyle(Palette.firText)
                        }
                        Text(rowsPart(item.text, block: item.block))
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
            }
            .card(padding: 16)
        }

        Text("To change these, open the Trees tab and pick this shift under “Marking trees for”.")
            .font(.footnote)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Block 1: rows 1–12, row 13 (trees 1–4)" → "Rows 1–12, row 13 (trees 1–4)".
    private func rowsPart(_ text: String, block: Block) -> String {
        let prefix = block.displayName + ": "
        guard text.hasPrefix(prefix) else { return text }
        let rest = text.dropFirst(prefix.count)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }
}
