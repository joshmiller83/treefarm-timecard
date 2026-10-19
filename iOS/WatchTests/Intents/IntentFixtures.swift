import Foundation
import TreeFarmKit
@testable import TimeCardWatch

/// A scripted `WatchShiftModel` for the intents: what it displays, whether the phone is in
/// reach, what each command and question comes back with, and everything it was asked to do.
@MainActor
final class FakeIntentModel: WatchIntentModel {
    var displayed: WatchState?
    var reach: PhoneReach = .reachable
    var now = IntentFixtures.now

    private(set) var performed: [FieldCommand] = []
    private(set) var sources: [WatchSource] = []
    private(set) var asked: [FieldQuestion] = []
    private(set) var undos = 0

    /// What a command comes back with. By default: done while in reach, saved while away.
    var outcome: ((FieldCommand) -> WatchOutcome)?
    var answers: [FieldQuestion: String] = [:]
    var undoOutcome = WatchOutcome.notSent(WatchDisplay.undoNeedsPhone)

    init(_ displayed: WatchState? = IntentFixtures.working(), reach: PhoneReach = .reachable) {
        self.displayed = displayed
        self.reach = reach
    }

    func perform(_ command: FieldCommand, source: WatchSource) async -> WatchOutcome {
        performed.append(command)
        sources.append(source)
        if let outcome { return outcome(command) }
        guard reach == .reachable else { return .queued(WatchDisplay.savedOnWatch(waiting: performed.count)) }
        return .done(WatchReply(requestId: UUID(), speech: IntentFixtures.phoneSays(command), succeeded: true))
    }

    func ask(_ question: FieldQuestion) async -> String {
        asked.append(question)
        guard reach == .reachable else { return WatchDisplay.askNeedsPhone }
        return answers[question] ?? WatchDisplay.askNeedsPhone
    }

    func confirmation(for command: FieldCommand) -> String? {
        displayed.flatMap { WatchConfirm.question(for: command, state: $0, now: now) }
    }

    func undo() async -> WatchOutcome {
        undos += 1
        return undoOutcome
    }
}

enum IntentFixtures {
    static let now = Date(timeIntervalSince1970: 1_792_400_000)
    static let blockId = UUID(uuidString: "6F9A3C1E-2B4D-4E5F-8A7B-9C0D1E2F3A4B")!
    static let otherBlockId = UUID(uuidString: "0A1B2C3D-4E5F-4061-8273-94A5B6C7D8E9")!
    static let shiftId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let userId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    /// What the scripted phone says for a command.
    static func phoneSays(_ command: FieldCommand) -> String {
        "Phone: \(WatchDisplay.label(for: command))."
    }

    static func chips(from row: Int, count: Int, block: UUID = blockId, name: String = "Block 2") -> [RowChip] {
        (row..<(row + count)).map { RowChip(blockId: block, row: $0, title: "Row \($0 + 1)", blockName: name) }
    }

    static func snapshot(_ phase: LiveSnapshot.Phase = .working, chips: [RowChip], shaped: Int = 120, total: Int = 610,
                         breakStart: Date? = nil) -> LiveSnapshot {
        LiveSnapshot(phase: phase, timerStart: now.addingTimeInterval(-(3 * 3600 + 41 * 60)), workedSoFar: 3 * 3600 + 41 * 60,
                     workedLabel: "worked today", breakStart: breakStart, breakReason: "", fieldName: "North",
                     nextRows: Array(chips.prefix(3)), shiftTrees: 38, fieldShaped: shaped, fieldTotal: total,
                     lastAction: nil, canUndo: true)
    }

    static func state(snapshot: LiveSnapshot?, chips: [RowChip], hadLunch: Bool = false, pace: Double? = 34,
                      todayWorked: TimeInterval = 3 * 3600 + 41 * 60, todayTrees: Int = 38) -> WatchState {
        WatchState(signedIn: true, farmName: "Dull’s Tree Farm", fieldName: "North", snapshot: snapshot, nextRows: chips,
                   todayWorked: todayWorked, todayTrees: todayTrees, canUndo: snapshot != nil, recordWorkouts: true,
                   updatedAt: now.addingTimeInterval(-60), epoch: UUID(), revision: 7, userId: userId,
                   shiftId: snapshot == nil ? nil : shiftId, shiftStart: snapshot == nil ? nil : now.addingTimeInterval(-4 * 3600),
                   hadLunchToday: hadLunch, pacePerHour: pace, farmTimeZone: "America/Indiana/Indianapolis")
    }

    /// Working in block 2, rows 14 to 53 next.
    static func working(chips: [RowChip] = chips(from: 13, count: 40)) -> WatchState {
        state(snapshot: snapshot(chips: chips), chips: chips)
    }

    static func onLunch(hadLunch: Bool = true) -> WatchState {
        let chips = chips(from: 13, count: 40)
        return state(snapshot: snapshot(.lunch, chips: chips, breakStart: now.addingTimeInterval(-12 * 60)), chips: chips, hadLunch: hadLunch)
    }

    static func onBreak() -> WatchState {
        let chips = chips(from: 13, count: 40)
        return state(snapshot: snapshot(.onBreak, chips: chips, breakStart: now.addingTimeInterval(-5 * 60)), chips: chips)
    }

    static func offClock(todayWorked: TimeInterval = 0, todayTrees: Int = 0) -> WatchState {
        state(snapshot: nil, chips: chips(from: 13, count: 40), pace: nil, todayWorked: todayWorked, todayTrees: todayTrees)
    }

    /// Every row of North shaped.
    static func fieldDone() -> WatchState {
        state(snapshot: snapshot(chips: [], shaped: 610, total: 610), chips: [])
    }

    /// Rows remain, but the watch knows none of them (marked offline past its 40 chips).
    static func outOfKnownRows() -> WatchState {
        state(snapshot: snapshot(chips: [], shaped: 400, total: 610), chips: [])
    }

    static var signedOut: WatchState {
        WatchState.signedOut(epoch: UUID(), revision: 3, now: now)
    }

    static func time(_ date: Date) -> String {
        WatchDisplay.time(date, working())
    }
}
