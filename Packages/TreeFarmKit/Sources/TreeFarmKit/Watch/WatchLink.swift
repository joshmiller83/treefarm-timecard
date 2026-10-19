import Foundation

// What the Apple Watch and the iPhone say to each other over WatchConnectivity.
//
// The phone is the hub: it holds the farm, runs every command through FieldEngine and
// syncs. The watch sends requests (a tap, a question) and keeps the latest WatchState the
// phone sent. When the phone is out of reach, taps wait in the watch's WatchOutbox and are
// applied later at the time they were made, to the shift they were made in.
//
// Every message is one `WatchEnvelope`, encoded with `JSONCoding` into `Data`. Data is
// Sendable, so nothing untyped crosses an isolation boundary: live traffic goes by
// `sendMessageData`, and the state by the application context (and, for phase changes, a
// complication user-info transfer), each carrying a `.state` envelope.

// MARK: - Envelope

public enum WatchWire {
    /// Bumped when the two apps can no longer read each other's messages. TestFlight updates
    /// the iPhone and watch apps separately, so for a while one side may be newer.
    public static let version = 1
}

public enum WatchWireError: Error, Equatable, Sendable {
    /// The envelope came from a newer (or unknown) version of the other app.
    case unsupportedVersion(Int)
}

public enum WatchMessage: Codable, Hashable, Sendable {
    case request(WatchRequest)
    case reply(WatchReply)
    case state(WatchState)
    case workoutSummary(WorkoutSummary)
}

public struct WatchEnvelope: Codable, Hashable, Sendable {
    public var v: Int
    public var message: WatchMessage

    public init(_ message: WatchMessage) {
        self.v = WatchWire.version
        self.message = message
    }

    public func data() throws -> Data {
        try JSONCoding.encoder().encode(self)
    }

    /// Reads an envelope. Throws `WatchWireError.unsupportedVersion` for one this app can't
    /// read (checked before the message itself, which a newer app may have changed).
    public static func decode(_ data: Data) throws -> WatchEnvelope {
        let version = try JSONCoding.decoder().decode(VersionOnly.self, from: data).v
        guard (1...WatchWire.version).contains(version) else { throw WatchWireError.unsupportedVersion(version) }
        return try JSONCoding.decoder().decode(WatchEnvelope.self, from: data)
    }

    private struct VersionOnly: Decodable { var v: Int }
}

// MARK: - Requests and replies

/// A request from the watch. `issuedAt` is when the person tapped, so a queued tap is
/// applied at that time rather than when it finally reaches the phone.
public struct WatchRequest: Codable, Hashable, Sendable, Identifiable {
    public enum Body: Codable, Hashable, Sendable {
        case command(FieldCommand)
        case question(FieldQuestion)
        /// "Send me the current state" (the watch app opened, or the phone came back in reach).
        case refresh
    }

    public var id: UUID
    public var body: Body
    public var issuedAt: Date
    /// The person the watch believed was signed in. A tap never applies to anyone else.
    public var userId: UUID?
    /// For `.clockIn`: the id the watch minted for the shift it is about to show (the phone
    /// creates the shift with it). For the shift-scoped commands (`isShiftScoped`): the open
    /// shift in the watch's displayed state when the tap was made. Nil for everything else.
    public var shiftId: UUID?

    public init(id: UUID = UUID(), body: Body, issuedAt: Date, userId: UUID? = nil, shiftId: UUID? = nil) {
        self.id = id
        self.body = body
        self.issuedAt = issuedAt
        self.userId = userId
        self.shiftId = shiftId
    }

    public var isCommand: Bool { command != nil }

    public var command: FieldCommand? {
        if case .command(let command) = body { return command }
        return nil
    }

    /// Commands that belong to one shift: they never apply to a later shift than the one
    /// they were made in.
    public var isShiftScoped: Bool {
        guard let command else { return false }
        return Self.isShiftScoped(command)
    }

    public static func isShiftScoped(_ command: FieldCommand) -> Bool {
        switch command {
        case .clockOut, .startBreak, .endBreak, .markRow, .markTrees, .addShiftNote, .cancelShift: true
        case .clockIn, .markNextRow, .moveTo, .addTreeNote, .changeStart, .undo: false
        }
    }
}

/// The phone's answer to one request: the same sentence Siri would say, and the state after it.
public struct WatchReply: Codable, Hashable, Sendable {
    /// The id of an `unreadable` reply, which answers an envelope the phone couldn't read.
    public static let unreadableId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    public var requestId: UUID
    public var speech: String
    public var succeeded: Bool
    public var lastAction: String?
    /// The phone's state after answering. Always set on the wire; never kept in `WatchInbox`.
    public var state: WatchState?
    /// The time the command counted at (`WatchTiming.effectiveTime`), when it ran.
    public var appliedAt: Date?
    /// "Couldn't run this now, try later": the phone wasn't unlocked since a reboot, its store
    /// failed, it was signed out, or the protocol was too new. Otherwise the request leaves the
    /// watch's outbox whatever the answer.
    public var keepQueued: Bool

    public init(requestId: UUID, speech: String, succeeded: Bool, lastAction: String? = nil,
                state: WatchState? = nil, appliedAt: Date? = nil, keepQueued: Bool = false) {
        self.requestId = requestId
        self.speech = speech
        self.succeeded = succeeded
        self.lastAction = lastAction
        self.state = state
        self.appliedAt = appliedAt
        self.keepQueued = keepQueued
    }

    /// The answer to an envelope the phone couldn't read (undecodable, or from a newer app).
    /// The courier matches it to its request by the send it answered, not by `requestId`.
    public static func unreadable(_ speech: String) -> WatchReply {
        WatchReply(requestId: unreadableId, speech: speech, succeeded: false, keepQueued: true)
    }

    private enum CodingKeys: String, CodingKey { case requestId, speech, succeeded, lastAction, state, appliedAt, keepQueued }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decode(UUID.self, forKey: .requestId)
        speech = try c.decode(String.self, forKey: .speech)
        succeeded = try c.decode(Bool.self, forKey: .succeeded)
        lastAction = try c.decodeIfPresent(String.self, forKey: .lastAction)
        state = try c.decodeIfPresent(WatchState.self, forKey: .state)
        appliedAt = try c.decodeIfPresent(Date.self, forKey: .appliedAt)
        keepQueued = try c.decodeIfPresent(Bool.self, forKey: .keepQueued) ?? false
    }
}

// MARK: - State

/// A shift that ended: the watch's "Last shift" line, and how a watch workout matches the
/// phone's clock-out.
public struct ClosedShift: Codable, Hashable, Sendable {
    public var shiftId: UUID
    public var start: Date
    public var end: Date
    public var worked: TimeInterval
    public var trees: Int

    public init(shiftId: UUID, start: Date, end: Date, worked: TimeInterval, trees: Int) {
        self.shiftId = shiftId
        self.start = start
        self.end = end
        self.worked = worked
        self.trees = trees
    }
}

/// Everything the watch shows, sent by the phone after every change (as the
/// WatchConnectivity application context, so the watch always has the latest). It never
/// carries pay: bystanders can see a wrist.
public struct WatchState: Codable, Hashable, Sendable {
    /// The most row chips a state carries: the screen shows 3 and Siri suggests 10; the rest
    /// let the watch keep marking while the phone is away (about 4 hours of rows).
    public static let maxRows = 40
    /// How many applied request ids a state carries, to clear the outbox after a lost reply.
    public static let maxAppliedIds = 50

    public var signedIn: Bool
    public var farmName: String
    public var fieldName: String
    /// The shift on the clock; nil when off the clock.
    public var snapshot: LiveSnapshot?
    /// Where you'd start: the next open rows (up to `maxRows`), also when off the clock.
    public var nextRows: [RowChip]
    public var todayWorked: TimeInterval
    public var todayTrees: Int
    public var canUndo: Bool
    /// Whether clocking in also starts a workout on the watch.
    public var recordWorkouts: Bool
    /// When the phone built this state.
    public var updatedAt: Date

    /// Made once per phone store (`watch.epoch`): a reinstall, a new phone or a lost store
    /// starts a new one, so the watch accepts its states even with a lower revision.
    public var epoch: UUID
    /// One counter for every state the phone sends (`watch.revision`): published or replied.
    public var revision: Int
    /// The signed-in person, nil when signed out.
    public var userId: UUID?
    /// The open shift, nil off the clock.
    public var shiftId: UUID?
    public var shiftStart: Date?
    public var lastClosedShift: ClosedShift?
    /// The last `maxAppliedIds` requests the phone answered, newest last.
    public var appliedRequestIds: [UUID]
    /// Lunch was already taken today (the Action button's pause picks a break then).
    public var hadLunchToday: Bool
    /// Trees an hour today, once there's enough to say.
    public var pacePerHour: Double?
    /// The farm's time zone identifier: times on the watch read in it.
    public var farmTimeZone: String
    /// The usual clock-in time (hour and minute, farm time): the median start of the last 10
    /// shifts, nil with fewer than 3. The Smart Stack raises "Clock in" around it.
    public var usualStart: DateComponents?

    public init(signedIn: Bool, farmName: String, fieldName: String, snapshot: LiveSnapshot?, nextRows: [RowChip],
                todayWorked: TimeInterval, todayTrees: Int, canUndo: Bool, recordWorkouts: Bool, updatedAt: Date,
                epoch: UUID = WatchState.noEpoch, revision: Int = 0, userId: UUID? = nil, shiftId: UUID? = nil,
                shiftStart: Date? = nil, lastClosedShift: ClosedShift? = nil, appliedRequestIds: [UUID] = [],
                hadLunchToday: Bool = false, pacePerHour: Double? = nil,
                farmTimeZone: String = TimeZone.current.identifier, usualStart: DateComponents? = nil) {
        self.signedIn = signedIn
        self.farmName = farmName
        self.fieldName = fieldName
        self.snapshot = snapshot
        self.nextRows = nextRows
        self.todayWorked = todayWorked
        self.todayTrees = todayTrees
        self.canUndo = canUndo
        self.recordWorkouts = recordWorkouts
        self.updatedAt = updatedAt
        self.epoch = epoch
        self.revision = revision
        self.userId = userId
        self.shiftId = shiftId
        self.shiftStart = shiftStart
        self.lastClosedShift = lastClosedShift
        self.appliedRequestIds = appliedRequestIds
        self.hadLunchToday = hadLunchToday
        self.pacePerHour = pacePerHour
        self.farmTimeZone = farmTimeZone
        self.usualStart = usualStart
    }

    /// The epoch of a state made by hand (tests, previews). The phone always sets a real one.
    public static let noEpoch = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// What the phone sends while nobody is signed in.
    public static func signedOut(epoch: UUID, revision: Int, now: Date) -> WatchState {
        WatchState(signedIn: false, farmName: "", fieldName: "", snapshot: nil, nextRows: [], todayWorked: 0, todayTrees: 0,
                   canUndo: false, recordWorkouts: true, updatedAt: now, epoch: epoch, revision: revision)
    }

    public var isClockedIn: Bool { snapshot != nil }

    /// Times and days as the farm reads them.
    public var calendar: FarmCalendar {
        FarmCalendar(timeZone: TimeZone(identifier: farmTimeZone) ?? .current, weekStart: .monday)
    }

    /// True when this state should replace `old`: there was none, it comes from a new epoch
    /// (a reinstalled or new phone, whose revisions start again), or it is newer.
    public func supersedes(_ old: WatchState?) -> Bool {
        guard let old else { return true }
        return epoch != old.epoch || revision > old.revision
    }
}

// MARK: - The watch's outbox

/// Taps made while the phone is out of reach (or waiting for its answer), oldest first.
///
/// Only commands wait: questions, refreshes and `undo` only make sense right away, and
/// `markNextRow` is never sent (the watch sends `markRow` for the chip it showed). Past `limit`
/// the oldest row marks are dropped first and counted; clock-ins, clock-outs, break changes and
/// cancels are never dropped.
public struct WatchOutbox: Codable, Hashable, Sendable {
    public private(set) var pending: [WatchRequest] = []
    public private(set) var dropped = 0
    public let limit: Int

    public init(limit: Int = 200) {
        self.limit = max(1, limit)
    }

    public var next: WatchRequest? { pending.first }
    public var count: Int { pending.count }
    public var isEmpty: Bool { pending.isEmpty }

    /// Whether a request may wait in the outbox at all.
    public static func canQueue(_ request: WatchRequest) -> Bool {
        switch request.command {
        case nil, .undo?, .markNextRow?: false
        default: true
        }
    }

    /// Never dropped past the limit: losing one would leave a shift or a break wrong.
    public static func isKept(_ command: FieldCommand) -> Bool {
        switch command {
        case .clockIn, .clockOut, .startBreak, .endBreak, .cancelShift: true
        default: false
        }
    }

    /// Adds a request. Returns false when it isn't queued: it can't wait (`canQueue`), it is
    /// already there, or it was the one dropped to make room.
    @discardableResult
    public mutating func add(_ request: WatchRequest) -> Bool {
        guard Self.canQueue(request), !pending.contains(where: { $0.id == request.id }) else { return false }
        pending.append(request)
        trim()
        return pending.contains { $0.id == request.id }
    }

    /// The phone has the request (whatever it answered), so it never goes again.
    public mutating func delivered(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    /// The phone's state lists these as applied (a reply may have been lost on the way back).
    public mutating func acknowledge(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let done = Set(ids)
        pending.removeAll { done.contains($0.id) }
    }

    /// Takes back the newest waiting tap (the watch's Undo while taps wait).
    @discardableResult
    public mutating func removeLast() -> WatchRequest? {
        pending.popLast()
    }

    private mutating func trim() {
        var extra = pending.count - limit
        guard extra > 0 else { return }
        // Row marks first, then anything else that may go; the clock and break changes stay.
        for isRowMark in [true, false] where extra > 0 {
            var kept: [WatchRequest] = []
            for request in pending {
                if extra > 0, let command = request.command, !Self.isKept(command), Self.isRowMark(command) == isRowMark {
                    extra -= 1
                    dropped += 1
                } else {
                    kept.append(request)
                }
            }
            pending = kept
        }
    }

    private static func isRowMark(_ command: FieldCommand) -> Bool {
        switch command {
        case .markRow, .markTrees, .markNextRow: true
        default: false
        }
    }
}

// MARK: - Timing

public enum WatchTiming {
    /// The time a watch tap counts at: when it was made, but never later than when the phone got it
    /// (a watch clock running ahead can't put a tap in the future).
    public static func effectiveTime(issuedAt: Date, receivedAt: Date) -> Date {
        effectiveTime(issuedAt: issuedAt, receivedAt: receivedAt, notBefore: nil)
    }

    /// The same, and never before `notBefore` (`notBefore(for:state:)`): a late tap can't land
    /// before something already recorded, so breaks can't overlap and a break can't end
    /// before it started.
    public static func effectiveTime(issuedAt: Date, receivedAt: Date, notBefore: Date?) -> Date {
        min(max(issuedAt, notBefore ?? .distantPast), receivedAt)
    }

    /// The earliest a command may count at, by what the phone already recorded. `Clock` checks
    /// only open or closed, so this clamp is what keeps a queued tap from saving an invalid shift.
    ///
    /// - Shift-scoped commands: the latest of the open shift's start and every break's start
    ///   and end in it (an open break's start counts).
    /// - `clockIn`: the end of the person's latest closed shift.
    /// - Anything else: nil.
    public static func notBefore(for command: FieldCommand, state: FieldState) -> Date? {
        switch command {
        case .clockIn:
            return state.liveShifts.compactMap(\.end).max()
        case _ where WatchRequest.isShiftScoped(command):
            guard let open = state.openShift else { return nil }
            let times = [open.start] + open.breaks.flatMap { [$0.start, $0.end].compactMap { $0 } }
            return times.max()
        default:
            return nil
        }
    }
}

// MARK: - Workouts

/// What the watch's workout measured for one shift. It goes to the phone (`.workoutSummary`),
/// which keeps it for the worker only: health data never syncs and never reaches the farm.
public struct WorkoutSummary: Codable, Hashable, Sendable {
    public var shiftId: UUID?
    public var start: Date
    public var end: Date
    public var activeDuration: TimeInterval
    public var activeKcal: Double?
    public var avgHeartRate: Double?
    public var maxHeartRate: Double?

    public init(shiftId: UUID?, start: Date, end: Date, activeDuration: TimeInterval,
                activeKcal: Double? = nil, avgHeartRate: Double? = nil, maxHeartRate: Double? = nil) {
        self.shiftId = shiftId
        self.start = start
        self.end = end
        self.activeDuration = activeDuration
        self.activeKcal = activeKcal
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
    }
}

/// The watch's own record of its workout session, saved on every change so a recovered
/// session picks up where it was.
public struct WorkoutLocal: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Sendable { case none, running, paused, stopped, ended }
    public enum Origin: String, Codable, Sendable { case watchTap, phoneLaunch, actionButton, recovered }

    public var phase: Phase
    /// The shift the session records; nil while untagged.
    public var shiftId: UUID?
    public var origin: Origin?
    public var startedAt: Date?
    /// When the activity was stopped (a watch clock-out waiting for the phone).
    public var stoppedAt: Date?
    /// `HKMetadataKeySyncIdentifier`, made when the session starts.
    public var syncIdentifier: UUID?
    /// The session ended from outside the app (another workout, a crash, the battery).
    public var stoppedUnexpectedly: Bool
    /// The last shift a workout was finished for, so it isn't started again.
    public var lastFinishedShiftId: UUID?

    public init(phase: Phase = .none, shiftId: UUID? = nil, origin: Origin? = nil, startedAt: Date? = nil,
                stoppedAt: Date? = nil, syncIdentifier: UUID? = nil, stoppedUnexpectedly: Bool = false,
                lastFinishedShiftId: UUID? = nil) {
        self.phase = phase
        self.shiftId = shiftId
        self.origin = origin
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.syncIdentifier = syncIdentifier
        self.stoppedUnexpectedly = stoppedUnexpectedly
        self.lastFinishedShiftId = lastFinishedShiftId
    }

    /// A session exists (it may be stopped and waiting for a clock-out to be answered).
    public var hasSession: Bool { phase == .running || phase == .paused || phase == .stopped }
}

/// What `WorkoutPlan.reconcile` decides from.
public struct WorkoutInputs: Equatable, Sendable {
    /// The phone's newest state, with no optimism.
    public var confirmed: WatchState?
    /// Taps waiting in the outbox (not in flight), oldest first.
    public var outbox: [WatchRequest]
    /// Taps sent and not yet answered.
    public var inFlight: [WatchRequest]
    /// Minted shift ids of watch clock-ins the phone refused (the last 10).
    public var refusedClockIns: [UUID]

    public init(confirmed: WatchState? = nil, outbox: [WatchRequest] = [], inFlight: [WatchRequest] = [], refusedClockIns: [UUID] = []) {
        self.confirmed = confirmed
        self.outbox = outbox
        self.inFlight = inFlight
        self.refusedClockIns = refusedClockIns
    }

    /// "Pending": waiting in the outbox or in flight, oldest first, each once.
    public var pending: [WatchRequest] {
        var seen = Set<UUID>()
        return (outbox + inFlight).sorted { $0.issuedAt < $1.issuedAt }.filter { seen.insert($0.id).inserted }
    }
}

/// One thing `ShiftWorkout` does to its session. An empty list means do nothing.
public enum WorkoutStep: Equatable, Sendable {
    case start(at: Date, shiftId: UUID?, origin: WorkoutLocal.Origin)
    case tag(shiftId: UUID)
    case pause
    case resume
    case stop(at: Date)
    case finish(at: Date)
    case discard
    case notifyStuckClockOut
}
