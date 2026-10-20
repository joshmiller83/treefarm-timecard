import Foundation
import TreeFarmKit

/// The scripted iPhone behind `-watchDemo` (docs/watch.md 7.3): a small farm in memory, run
/// through the real `FieldEngine` and `WatchStateBuilder`, so every sentence the watch shows in
/// UI tests and screenshots is the phone's own. It answers the way `WatchDesk` does in outline:
/// a retried request gets its saved reply, a tap for a closed shift is refused, a watch clock-in
/// creates the shift under the minted id, and taps count at their tap time.
@MainActor
final class DemoPhone {
    private(set) var state: FieldState
    private var undo = UndoStack<UndoEntry>()
    private var inbox = WatchInbox()
    private let epoch = UUID()
    private var revision = 0
    private var lastAction: String?
    private let now: () -> Date
    var recordWorkouts = true
    var signedIn = true

    init(working: Bool = false, lunch: Bool = false, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.state = DemoFarm.state(now: now(), working: working || lunch, lunchSince: lunch ? now().addingTimeInterval(-12 * 60 - 40) : nil)
    }

    /// One watch request, envelope in and `.reply` envelope out (always).
    func handle(_ data: Data) -> Data {
        let received = now()
        guard case .request(let request)? = try? WatchEnvelope.decode(data).message else {
            var reply = WatchReply.unreadable(WatchDisplay.updatePhone)
            reply.state = makeState()
            return Self.envelope(reply)
        }
        guard signedIn else {
            var reply = WatchReply(requestId: request.id, speech: Speech.signedOut, succeeded: false, keepQueued: true)
            reply.state = makeState()
            return Self.envelope(reply)
        }
        if var saved = inbox.reply(for: request.id) {
            saved.state = makeState()
            return Self.envelope(saved)
        }
        var reply: WatchReply
        switch request.body {
        case .refresh:
            reply = WatchReply(requestId: request.id, speech: "", succeeded: true)
        case .question(let question):
            reply = WatchReply(requestId: request.id, speech: FieldAnswers.answer(question, state: state, now: received), succeeded: true)
        case .command(let command):
            reply = run(command, request, received: received)
        }
        inbox.record(reply, at: received)
        reply.state = makeState()
        return Self.envelope(reply)
    }

    /// The next state, from one revision counter.
    func makeState() -> WatchState {
        revision += 1
        guard signedIn else { return .signedOut(epoch: epoch, revision: revision, now: now()) }
        return WatchStateBuilder.build(state: state, now: now(), epoch: epoch, revision: revision, recordWorkouts: recordWorkouts,
                                       appliedRequestIds: inbox.recentIds(WatchState.maxAppliedIds), lastAction: lastAction,
                                       canUndo: !undo.isEmpty)
    }

    private func run(_ command: FieldCommand, _ request: WatchRequest, received: Date) -> WatchReply {
        let open = state.openShift
        if case .clockIn = command, let open, let minted = request.shiftId {
            inbox.alias(minted, to: open.id, at: received)
        }
        if request.isShiftScoped, let open, inbox.resolve(shiftId: request.shiftId) != open.id {
            return WatchReply(requestId: request.id, speech: "That shift isn’t the one on the clock, so it wasn’t applied.", succeeded: false)
        }
        let at = WatchTiming.effectiveTime(issuedAt: request.issuedAt, receivedAt: received,
                                           notBefore: WatchTiming.notBefore(for: command, state: state))
        let newShiftId: UUID? = if case .clockIn = command { request.shiftId } else { nil }
        switch FieldEngine.perform(command, state: state, undo: &undo, now: at, newShiftId: newShiftId) {
        case .success(let outcome):
            state = state.applying(outcome)
            lastAction = outcome.lastAction
            return WatchReply(requestId: request.id, speech: outcome.speech, succeeded: true, lastAction: outcome.lastAction, appliedAt: at)
        case .failure(let failure):
            return WatchReply(requestId: request.id, speech: failure.speech, succeeded: false)
        }
    }

    private static func envelope(_ reply: WatchReply) -> Data {
        (try? WatchEnvelope(.reply(reply)).data()) ?? Data()
    }
}

/// The demo farm: Dull’s Tree Farm, field North, two blocks of 61 rows × 10 trees. Block 1 is
/// shaped (most of it on yesterday's shift), and block 2 up to row 13, so the next row is 14.
enum DemoFarm {
    static let timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!

    static func state(now: Date, working: Bool, lunchSince: Date? = nil) -> FieldState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        let farmId = UUID()
        let season = Season(farmId: farmId, name: "2026", startedAt: calendar.date(byAdding: .day, value: -40, to: today)!, updatedAt: yesterday)
        let farm = Farm(id: farmId, name: "Dull’s Tree Farm", timeZoneId: timeZone.identifier, weekStart: .monday,
                        activeSeasonId: season.id, updatedAt: yesterday)
        let field = Field(farmId: farmId, name: "North", sortOrder: 0, updatedAt: yesterday)
        let block1 = Block(fieldId: field.id, name: "1", gridRow: 0, gridColumn: 0, rowCount: 61, treesPerRow: 10, updatedAt: yesterday)
        let block2 = Block(fieldId: field.id, name: "2", gridRow: 0, gridColumn: 1, rowCount: 61, treesPerRow: 10, updatedAt: yesterday)
        let josh = Member(userId: UUID(), farmId: farmId, displayName: "Josh", email: "josh@example.com", role: .worker,
                          jobTitle: "Tree trimming", rateCents: 1500, updatedAt: yesterday)
        let sam = Member(userId: UUID(), farmId: farmId, displayName: "Sam", email: "", role: .worker, updatedAt: yesterday)

        // Earlier shifts at about 7:00, so the Smart Stack knows the usual start.
        var shifts: [Shift] = (2...4).map { daysAgo in
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            return Shift(userId: josh.userId, farmId: farmId, start: at(day, 7, 0), end: at(day, 15, 0),
                         breaks: [Break(kind: .lunch, start: at(day, 12, 0), end: at(day, 12, 30))], rateCents: 1500, updatedAt: at(day, 15, 0))
        }
        let last = Shift(userId: josh.userId, farmId: farmId, start: at(yesterday, 7, 2), end: at(yesterday, 15, 44),
                         breaks: [Break(kind: .lunch, start: at(yesterday, 12, 1), end: at(yesterday, 12, 31))],
                         rateCents: 1500, updatedAt: at(yesterday, 15, 44))
        shifts.append(last)

        var marks: [TreeMark] = []
        func shape(_ block: Block, rows: ClosedRange<Int>, trees: Range<Int> = 0..<10, shift: UUID, user: UUID, on day: Date) {
            for row in rows {
                for position in trees {
                    marks.append(TreeMark(seasonId: season.id, tree: TreeRef(blockId: block.id, row: row - 1, position: position),
                                          shiftId: shift, userId: user, markedAt: at(day, 9, 0)))
                }
            }
        }
        // Yesterday: 412 trees for Josh.
        shape(block1, rows: 1...41, shift: last.id, user: josh.userId, on: yesterday)
        shape(block1, rows: 42...42, trees: 0..<2, shift: last.id, user: josh.userId, on: yesterday)
        // The rest of block 1, and block 2 to row 13, by Sam.
        let samShift = UUID()
        shape(block1, rows: 42...42, trees: 2..<10, shift: samShift, user: sam.userId, on: yesterday)
        shape(block1, rows: 43...61, shift: samShift, user: sam.userId, on: yesterday)
        shape(block2, rows: 1...13, shift: samShift, user: sam.userId, on: yesterday)

        if working {
            // On the clock since 7:02, with 38 trees marked this morning.
            let lunch = lunchSince.map { [Break(kind: .lunch, start: $0)] } ?? []
            let open = Shift(userId: josh.userId, farmId: farmId, start: at(today, 7, 2), breaks: lunch, rateCents: 1500,
                             updatedAt: at(today, 7, 2))
            shifts.append(open)
            shape(block2, rows: 14...16, shift: open.id, user: josh.userId, on: today)
            shape(block2, rows: 17...17, trees: 0..<8, shift: open.id, user: josh.userId, on: today)
        }

        let next = RowRef(blockId: block2.id, row: working ? 16 : 13)
        return FieldState(farm: farm, me: josh, season: season, fields: [field], blocks: [block1, block2], myShifts: shifts,
                          marks: marks, members: [josh, sam], position: WorkPosition(fieldId: field.id, next: next))
    }
}
