import Foundation
import TimeCardCore
@testable import TimeCard

/// Lock-screen snapshots for each phase, as `LiveSnapshot.build` would make them.
enum LiveFixtures {
    static let block2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    static let block3 = UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static let attributes = TimeCardActivityAttributes(farmName: "Pine Hollow Tree Farm", userName: "Alex Rivera")

    static func chip(_ row: Int, block: UUID = block2, name: String = "Block 2") -> RowChip {
        RowChip(blockId: block, row: row - 1, title: "Row \(row)", blockName: name)
    }

    static func working(rows: [RowChip] = [chip(13), chip(14), chip(15)], trees: Int = 212, shaped: Int = 3_240, total: Int = 8_540,
                        lastAction: String? = nil, canUndo: Bool = false, worked: TimeInterval = 6 * 3600 + 42 * 60 + 10,
                        field: String = "North Field", label: String = "worked today", now: Date = LiveFixtures.now) -> LiveSnapshot {
        LiveSnapshot(phase: .working, timerStart: now.addingTimeInterval(-worked), workedSoFar: worked, workedLabel: label,
                     breakStart: nil, breakReason: "", fieldName: field, nextRows: rows, shiftTrees: trees,
                     fieldShaped: shaped, fieldTotal: total, lastAction: lastAction, canUndo: canUndo)
    }

    static func onBreak(_ phase: LiveSnapshot.Phase = .lunch, reason: String = "", minutes: Double = 12.5,
                        lastAction: String? = "Lunch started", canUndo: Bool = true, now: Date = LiveFixtures.now) -> LiveSnapshot {
        let worked: TimeInterval = 4 * 3600 + 12 * 60 + 8
        return LiveSnapshot(phase: phase, timerStart: now.addingTimeInterval(-worked), workedSoFar: worked, workedLabel: "worked today",
                            breakStart: now.addingTimeInterval(-minutes * 60), breakReason: reason, fieldName: "North Field",
                            nextRows: [chip(13), chip(14), chip(15)], shiftTrees: 148, fieldShaped: 3_176, fieldTotal: 8_540,
                            lastAction: lastAction, canUndo: canUndo)
    }
}
