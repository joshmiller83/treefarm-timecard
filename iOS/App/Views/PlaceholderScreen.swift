import SwiftUI
import TimeCardCore

/// A quiet stand-in for a tab that's still being built.
struct PlaceholderScreen<Extra: View>: View {
    var title: String
    var systemImage: String
    var headline: String
    var detail: String
    @ViewBuilder var extra: Extra

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    extra
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: systemImage)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Palette.firText)
                            .frame(width: 56, height: 56)
                            .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                        Text(headline).headingStyle(.tcTitle2)
                        Text(detail)
                            .font(.body)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Coming soon")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.sapInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Palette.sapSoft, in: Capsule())
                    }
                    .card(padding: 20)
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationTitle(title)
        }
    }
}

extension PlaceholderScreen where Extra == EmptyView {
    init(title: String, systemImage: String, headline: String, detail: String) {
        self.init(title: title, systemImage: systemImage, headline: headline, detail: detail) { EmptyView() }
    }
}

/// Clock tab stand-in: who and where, and what's coming.
struct ClockPlaceholder: View {
    @Environment(TimeCardSession.self) private var session

    var body: some View {
        PlaceholderScreen(title: "Clock", systemImage: "clock",
                          headline: "Clock in, breaks and your next rows",
                          detail: "The big status card with a running timer, lunch and breaks, and the next three rows to shape will live here.") {
            VStack(alignment: .leading, spacing: 10) {
                StatusPill(text: "Off the clock", tone: .off)
                Text(session.farm?.name ?? "")
                    .headingStyle(.tcTitle)
                    .accessibilityIdentifier("clock-farm-name")
                if let name = session.me?.user.displayName {
                    Text("Signed in as \(name)").font(.subheadline).foregroundStyle(Palette.muted)
                }
            }
            .card(padding: 20)
        }
    }
}

/// Trees tab stand-in: the farm's fields as synced, so you can see the data arrive.
struct TreesPlaceholder: View {
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
