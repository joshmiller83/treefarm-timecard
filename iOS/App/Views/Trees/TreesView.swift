import SwiftUI
import TimeCardCore

/// The Trees tab. (Stand-in until the map slice lands: the farm's fields as synced.)
struct TreesView: View {
    @Environment(TimeCardSession.self) private var session

    private struct FieldSummary: Identifiable {
        var id: UUID
        var name: String
        var blocks: Int
        var trees: Int
        var shaped: Int
    }

    private var summaries: [FieldSummary] {
        let snapshot = session.snapshot
        let season = snapshot.farm?.activeSeasonId
        let fields = snapshot.fields.values.filter { $0.archivedAt == nil }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        return fields.map { field in
            let blocks = snapshot.blocks.values.filter { $0.fieldId == field.id }
            let ids = Set(blocks.map(\.id))
            let shaped = snapshot.marks.values.filter { ids.contains($0.blockId) && $0.seasonId == season }.count
            return FieldSummary(id: field.id, name: field.name, blocks: blocks.count, trees: blocks.reduce(0) { $0 + $1.treeCount }, shaped: shaped)
        }
    }

    var body: some View {
        PlaceholderScreen(title: "Trees", systemImage: "tree",
                          headline: "The field map",
                          detail: "Blocks laid out as they stand in the field. Tap a row to mark it shaped, long-press a tree for its notes.") {
            if !summaries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Fields")
                    ForEach(summaries) { field in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.name).font(.tcHeadline).foregroundStyle(Palette.ink)
                                Text(field.blocks == 1 ? "1 block" : "\(field.blocks) blocks")
                                    .font(.subheadline).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Text("\(field.shaped) / \(field.trees)")
                                .numberStyle(.body)
                                .foregroundStyle(Palette.firText)
                                .accessibilityLabel("\(field.shaped) of \(field.trees) trees shaped")
                        }
                        .accessibilityElement(children: .combine)
                        if field.id != summaries.last?.id { Divider().overlay(Palette.line) }
                    }
                }
                .card()
            }
        }
    }
}
