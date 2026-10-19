import Foundation
import TimeCardCore

/// States for UI tests and screenshots of the Trees tab. Only in UI-test runs (`-UITestInMemory`).
///
/// - `-UITestTreesSeed`: the demo admin gets yesterday's shift (block 2, rows 1–10, so there's a
///   pace), clocks in on North Field, marks rows 5 and 6 of block 1 through FieldActions and
///   notes two trees (one by Sam), so the map shows every state.
/// - `-UITestBigField`: adds "Big Field" first in the list: 14 blocks of 61 rows × 10 trees
///   (8,540 trees) side by side, with Sam's 710 marks, the size of the real farm.
/// - `-UITestTreesZoom all|xs|s|m|l`: the map size to open at (UI-test runs always start at M otherwise).
@MainActor
enum TreesDemoSeed {
    static let seedArgument = "-UITestTreesSeed"
    static let bigFieldArgument = "-UITestBigField"
    static let zoomArgument = "-UITestTreesZoom"
    private static var done = false

    static func zoom(arguments: [String] = ProcessInfo.processInfo.arguments) -> MapZoom? {
        guard let i = arguments.firstIndex(of: zoomArgument), i + 1 < arguments.count else { return nil }
        return MapZoom(rawValue: arguments[i + 1])
    }

    static func runIfRequested(model app: AppModel, arguments: [String] = ProcessInfo.processInfo.arguments) async {
        guard app.mode != .live, !done else { return }
        let seed = arguments.contains(seedArgument), big = arguments.contains(bigFieldArgument)
        guard seed || big else { return }
        done = true
        let session = app.session
        // The demo farm arrives with the first sync.
        for _ in 0..<100 where session.snapshot.fields.isEmpty || session.membership == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let farm = session.farm, let me = session.membership else { return }
        let snapshot = session.snapshot
        let sam = snapshot.members.values.first { $0.userId != me.userId }
        let samShift = snapshot.shifts.values.first { $0.userId == sam?.userId }

        if big, let season = snapshot.activeSeason, let sam, let samShift {
            try? session.save(bigField(farm: farm, season: season, sam: sam, shift: samShift))
        }
        if seed, let north = snapshot.fields.values.first(where: { $0.name == "North Field" }),
           let block1 = snapshot.blocks.values.first(where: { $0.fieldId == north.id && $0.name == "1" }) {
            // Yesterday, 8:00 to 3:00: block 2, rows 1–10, so there's a pace and an earlier shift to pick.
            if let season = snapshot.activeSeason,
               let block2 = snapshot.blocks.values.first(where: { $0.fieldId == north.id && $0.name == "2" }),
               !snapshot.shifts.values.contains(where: { $0.userId == me.userId }) {
                let cal = FarmCalendar(farm: farm)
                let start = cal.addDays(cal.startOfDay(Date()), -1).addingTimeInterval(8 * 3600)
                let yesterday = Shift(userId: me.userId, farmId: farm.id, start: start, end: start.addingTimeInterval(7 * 3600),
                                      breaks: [Break(kind: .lunch, start: start.addingTimeInterval(4 * 3600), end: start.addingTimeInterval(4.5 * 3600))],
                                      rateCents: me.rateCents, updatedAt: start)
                var records: [SyncRecord] = [.shift(yesterday)]
                for row in 0..<10 {
                    for position in 0..<block2.treesPerRow {
                        records.append(.treeMark(TreeMark(seasonId: season.id, tree: TreeRef(blockId: block2.id, row: row, position: position),
                                                          shiftId: yesterday.id, userId: me.userId,
                                                          markedAt: start.addingTimeInterval(Double(row * 12 + position) * 150))))
                    }
                }
                try? session.save(records)
            }
            let actions = app.actions
            if snapshot.openShift(for: me.userId) == nil { actions.perform(.clockIn(fieldId: north.id)) }
            actions.perform(.markRow(RowRef(blockId: block1.id, row: 4)))
            actions.perform(.markRow(RowRef(blockId: block1.id, row: 5)))
            actions.perform(.addTreeNote(TreeRef(blockId: block1.id, row: 6, position: 3), body: "Leader snapped in the wind. Pick a new one next pass.", flag: .attention))
            if let sam {
                let note = TreeNote(farmId: farm.id, tree: TreeRef(blockId: block1.id, row: 1, position: 8), authorId: sam.userId,
                                    authorName: sam.displayName, body: "Bagworms on the north side. Sprayed Tuesday.",
                                    flag: .none, createdAt: Date().addingTimeInterval(-2 * 86400).roundedToMillisecond)
                try? session.save([.treeNote(note)])
            }
        }
    }

    private static func bigField(farm: Farm, season: Season, sam: Member, shift: Shift) -> [SyncRecord] {
        let now = Date().roundedToMillisecond
        let field = Field(farmId: farm.id, name: "Big Field", sortOrder: -1, updatedAt: now)
        var records: [SyncRecord] = [.field(field)]
        var blocks: [Block] = []
        for i in 0..<14 {
            let block = Block(fieldId: field.id, name: "\(i + 1)", gridRow: 0, gridColumn: i, rowCount: 61, treesPerRow: 10, updatedAt: now)
            blocks.append(block)
            records.append(.block(block))
        }
        var marked = 0
        outer: for block in blocks {
            for row in 0..<block.rowCount {
                for position in 0..<block.treesPerRow {
                    if marked == 710 { break outer }
                    records.append(.treeMark(TreeMark(seasonId: season.id, tree: TreeRef(blockId: block.id, row: row, position: position),
                                                      shiftId: shift.id, userId: sam.userId, markedAt: shift.start.addingTimeInterval(3600))))
                    marked += 1
                }
            }
        }
        return records
    }
}
