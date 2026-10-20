import Foundation
import TreeFarmKit
import TreeFarmKitTestSupport
@testable import TimeCardWatch

/// States and a scripted phone for the watch model's tests. The phone answers each request
/// the way the real one does in shape: the command applied (by `WatchOptimism`, close enough
/// for a test), the next revision, the request listed as applied, and a sentence.
enum WatchFixture {
    static let zone = "America/Indiana/Indianapolis"
    static let calendar = FarmCalendar(timeZone: TimeZone(identifier: zone)!, weekStart: .monday)
    static let block = UUID(uuidString: "B10C0000-0000-0000-0000-000000000002")!
    static let user = UUID(uuidString: "05E40000-0000-0000-0000-00000000005A")!
    static let shift = UUID(uuidString: "5A1F0000-0000-0000-0000-000000000001")!
    static let epoch = UUID(uuidString: "E90C0000-0000-0000-0000-000000000001")!

    static func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        calendar.date(on: DayKey(year: 2026, month: 10, day: 19), hour: h, minute: m).addingTimeInterval(TimeInterval(s))
    }

    static func chips(_ rows: ClosedRange<Int>) -> [RowChip] {
        rows.map { RowChip(blockId: block, row: $0 - 1, title: "Row \($0)", blockName: "Block 2") }
    }

    static func row(_ n: Int) -> RowRef { RowRef(blockId: block, row: n - 1) }

    static func working(rows: ClosedRange<Int>? = 14...53, revision: Int = 5, epoch: UUID = epoch,
                        shaped: Int = 120, total: Int = 400, at now: Date = at(10, 0)) -> WatchState {
        let next = rows.map(chips) ?? []
        let worked: TimeInterval = 3 * 3600
        let snapshot = LiveSnapshot(phase: .working, timerStart: now.addingTimeInterval(-worked), workedSoFar: worked, workedLabel: "worked today",
                                    breakStart: nil, breakReason: "", fieldName: "North", nextRows: Array(next.prefix(3)),
                                    shiftTrees: 38, fieldShaped: shaped, fieldTotal: total, lastAction: nil, canUndo: false)
        return WatchState(signedIn: true, farmName: "Dull’s Tree Farm", fieldName: "North", snapshot: snapshot, nextRows: next,
                          todayWorked: worked, todayTrees: 38, canUndo: false, recordWorkouts: true, updatedAt: now,
                          epoch: epoch, revision: revision, userId: user, shiftId: shift, shiftStart: at(7, 0), farmTimeZone: zone)
    }

    static func offClock(revision: Int = 5, epoch: UUID = epoch, at now: Date = at(6, 50)) -> WatchState {
        WatchState(signedIn: true, farmName: "Dull’s Tree Farm", fieldName: "North", snapshot: nil, nextRows: chips(14...53),
                   todayWorked: 0, todayTrees: 0, canUndo: false, recordWorkouts: true, updatedAt: now,
                   epoch: epoch, revision: revision, userId: user, farmTimeZone: zone)
    }

    static func onLunch(revision: Int = 5) -> WatchState {
        var s = working(revision: revision)
        s.snapshot?.phase = .lunch
        s.snapshot?.breakStart = at(9, 55)
        return s
    }

    static func envelope(_ state: WatchState) -> Data {
        FakeWatchTransport.envelope(.state(state))
    }
}

/// A phone for the model's tests, behind a `FakeWatchTransport`.
final class WatchTestPhone: @unchecked Sendable {
    private let lock = NSLock()
    private var state: WatchState
    private var _requests: [WatchRequest] = []
    private var refusals: [String] = []
    private var applied: [UUID] = []

    init(_ state: WatchState) {
        self.state = state
    }

    var requests: [WatchRequest] { lock.withLock { _requests } }
    /// The commands among them (not refreshes or questions).
    var commands: [WatchRequest] { requests.filter(\.isCommand) }
    var current: WatchState { lock.withLock { state } }

    /// The next command is refused with this sentence.
    func refuseNext(_ speech: String) {
        lock.withLock { refusals.append(speech) }
    }

    /// The phone's state moves on by itself (Siri, the lock screen): the next revision.
    func change(_ body: (inout WatchState) -> Void) -> WatchState {
        lock.withLock {
            body(&state)
            state.revision += 1
            state.appliedRequestIds = applied
            return state
        }
    }

    func answer(_ data: Data) -> Data {
        guard case .request(let r)? = try? WatchEnvelope.decode(data).message else {
            return FakeWatchTransport.envelope(.reply(.unreadable(WatchDisplay.updatePhone)))
        }
        let reply: WatchReply = lock.withLock {
            _requests.append(r)
            applied.append(r.id)
            if r.isCommand, !refusals.isEmpty {
                let speech = refusals.removeFirst()
                state.revision += 1
                state.appliedRequestIds = applied
                return WatchReply(requestId: r.id, speech: speech, succeeded: false, state: state)
            }
            var lastAction: String?
            if let command = r.command {
                state = WatchOptimism.apply(command, shiftId: r.shiftId, to: state, at: r.issuedAt)
                lastAction = state.snapshot?.lastAction ?? WatchDisplay.label(for: command)
                if case .undo = command { lastAction = "Undid row 14" }
            }
            state.revision += 1
            state.appliedRequestIds = applied
            let speech = r.command == nil ? "You’ve shaped 38 trees today." : "\(lastAction ?? "Done")."
            return WatchReply(requestId: r.id, speech: speech, succeeded: true, lastAction: lastAction, state: state,
                              appliedAt: r.issuedAt)
        }
        return FakeWatchTransport.envelope(.reply(reply))
    }
}

/// Records what the model plays and reloads.
@MainActor
final class WatchModelRecorder {
    var haptics: [WatchHapticEvent] = []
    var reloads = 0
    var changes: [WatchModelChange] = []
    /// Minted shift ids the model named as Action button clock-ins.
    var actionButtonShifts: [UUID] = []
    /// Outbox flushes the model finished.
    var flushes = 0
}

extension WatchFixture {
    /// Polls `condition` on the main actor until it holds or `timeout` passes.
    @MainActor
    static func eventually(_ timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: timeout)
        while clock.now < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

/// A clock a test can move.
final class WatchTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Set once something finished.
@MainActor
final class WatchTestFlag {
    var isSet = false
}
