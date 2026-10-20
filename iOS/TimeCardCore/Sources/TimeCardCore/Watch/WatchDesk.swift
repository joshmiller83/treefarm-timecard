import Foundation

/// The phone's side of the watch link (docs/watch.md 1.3). The watch sends requests and shows
/// state; every rule, sentence and record still comes from `FieldEngine` through
/// `FieldActions`, so the watch can't drift from Siri or the lock screen.
///
/// - `handle(_:receivedAt:)` answers one request: envelope in, `.reply` envelope out, always,
///   so the bridge calls WatchConnectivity's reply handler exactly once.
/// - A retried request (its reply was lost) gets its saved answer from `WatchInbox` with a
///   fresh state, and **doesn't run again**.
/// - Taps made for someone else, or during a shift that has closed since, are refused with a
///   sentence that names them. A clock-in the phone refuses because a shift is already open
///   aliases the watch's minted id to that shift, so the marks tapped after it still count.
/// - The rest run at their tap time (`WatchTiming.effectiveTime`, clamped by `notBefore`), and
///   `FieldActions` stamps what they write with the time the phone got them.
/// - `makeState()` builds every `WatchState` the phone sends, published or replied, from one
///   revision counter kept in the store (`watch.revision`, beside `watch.epoch`), so the watch
///   never sees two states tie or go backwards, and a new phone or store starts a new epoch.
///
/// Settings are read on every call, so turning "Record shifts as workouts" off shows up in the
/// very next state.
@MainActor
public final class WatchDesk {
    public static let revisionKey = "watch.revision"
    public static let epochKey = "watch.epoch"
    public static let inboxKey = "watch.inbox"
    /// The phase of the last state made: what the watch last heard, across launches.
    public static let phaseKey = "watch.phase"

    /// Where a workout summary from the watch is kept: on this phone, for the worker only.
    public static func summaryKey(shiftId: UUID?, start: Date) -> String {
        "watch.workout.\(shiftId?.uuidString ?? "none-\(Int(start.timeIntervalSince1970))")"
    }

    private let actions: FieldActions
    private let store: any KeyValueStore
    private let settings: @MainActor () -> WatchSettings
    private let now: () -> Date
    private var inbox: WatchInbox
    /// Shifts opened by a watch clock-in this launch, newest last.
    private var watchOpened: [UUID] = []
    /// The counter's epoch, once this desk has made a state.
    private var epoch: UUID?
    /// The last revision this desk handed out, in `epoch`.
    private var issued = 0

    /// The phase of the last state this desk (or an earlier one on the same store) made. Every
    /// state made is sent, so this is what the watch last heard about.
    public private(set) var lastPhase: WatchPhase?

    public init(actions: FieldActions, store: any KeyValueStore,
                settings: @escaping @MainActor () -> WatchSettings, now: @escaping () -> Date = Date.init) {
        self.actions = actions
        self.store = store
        self.settings = settings
        self.now = now
        inbox = Self.load(WatchInbox.self, Self.inboxKey, from: store) ?? WatchInbox()
        lastPhase = Self.load(WatchPhase.self, Self.phaseKey, from: store)
    }

    // MARK: Requests

    /// Envelope in, `.reply` envelope out, always. The reply carries a fresh state.
    public func handle(_ data: Data, receivedAt: Date) -> Data {
        var reply = answer(data, receivedAt: receivedAt)
        reply.state = makeState()
        // Encoding our own value types can't fail; an empty reply is still exactly one reply.
        return (try? WatchEnvelope(.reply(reply)).data()) ?? Data()
    }

    /// The reply when the phone can't read its own data (locked since a restart): "try later",
    /// and **no state**, because a made-up signed-out state would stop the watch's workout.
    public static func unavailable(_ data: Data, speech: String) -> Data {
        var id = WatchReply.unreadableId
        if case .request(let request)? = try? WatchEnvelope.decode(data).message { id = request.id }
        let reply = WatchReply(requestId: id, speech: speech, succeeded: false, keepQueued: true)
        return (try? WatchEnvelope(.reply(reply)).data()) ?? Data()
    }

    /// A message that waits for no reply: a workout summary from the watch.
    public func receive(_ data: Data) {
        guard let envelope = try? WatchEnvelope.decode(data) else { return }
        if case .workoutSummary(let summary) = envelope.message { save(summary) }
    }

    private func answer(_ data: Data, receivedAt: Date) -> WatchReply {
        guard let envelope = try? WatchEnvelope.decode(data) else { return .unreadable(WatchDisplay.updatePhone) }
        switch envelope.message {
        case .request(let request):
            return answer(request, receivedAt: receivedAt)
        case .workoutSummary(let summary):
            save(summary)
            return WatchReply(requestId: WatchReply.unreadableId, speech: "", succeeded: true)
        case .reply, .state:
            return .unreadable(WatchDisplay.updatePhone)
        }
    }

    private func answer(_ request: WatchRequest, receivedAt: Date) -> WatchReply {
        if let saved = inbox.reply(for: request.id) { return saved }
        switch request.body {
        case .refresh:
            return WatchReply(requestId: request.id, speech: "", succeeded: true)
        case .question(let question):
            guard actions.state() != nil else {
                return WatchReply(requestId: request.id, speech: FieldActions.signedOut, succeeded: false, keepQueued: true)
            }
            return WatchReply(requestId: request.id, speech: actions.answer(Self.watchSafe(question)), succeeded: true)
        case .command(let command):
            let reply = run(command, request: request, receivedAt: receivedAt)
            // "Try later" answers aren't kept: the retry has to run once it can.
            if !reply.keepQueued {
                inbox.record(reply, at: receivedAt)
                saveInbox()
            }
            return reply
        }
    }

    /// Pay is never said on a wrist that bystanders can see (the watch never asks).
    private static func watchSafe(_ question: FieldQuestion) -> FieldQuestion {
        if case .pay = question { return .pay(locked: true, sayWhenLocked: false) }
        return question
    }

    private func run(_ original: FieldCommand, request: WatchRequest, receivedAt: Date) -> WatchReply {
        func refuse(_ speech: String) -> WatchReply {
            WatchReply(requestId: request.id, speech: speech, succeeded: false)
        }
        guard let state = actions.state() else {
            return WatchReply(requestId: request.id, speech: FieldActions.signedOut, succeeded: false, keepQueued: true)
        }
        // The right person: a tap never applies to anyone but the one the watch showed.
        guard let person = request.userId else { return refuse(WatchDeskSpeech.beforeSignIn) }
        guard person == state.me.userId else { return refuse(WatchDeskSpeech.forSomeoneElse(state.member(person)?.displayName)) }

        // The right shift.
        var command = original
        let cal = state.calendar
        if case .clockIn = command {
            if let open = state.openShift, let minted = request.shiftId, minted != open.id {
                inbox.alias(minted, to: open.id, at: receivedAt)
                saveInbox()
            }
            if state.openShift == nil, let lastEnd = WatchTiming.notBefore(for: command, state: state), request.issuedAt < lastEnd {
                return refuse(WatchDeskSpeech.clockInBeforeLastShift(tapped: request.issuedAt, lastEnd: lastEnd, calendar: cal))
            }
        }
        if WatchRequest.isShiftScoped(command) {
            let tagged = inbox.resolve(shiftId: request.shiftId)
            guard let open = state.openShift else {
                // Name the shift it was made in when the phone knows it.
                guard let made = state.myShifts.first(where: { $0.id == tagged }) else { return refuse(WatchDeskSpeech.notClockedIn(command)) }
                return refuse(WatchDeskSpeech.closedShift(command, start: made.start, calendar: cal))
            }
            if let tagged {
                guard tagged == open.id else {
                    let start = state.myShifts.first { $0.id == tagged }?.start
                    return refuse(WatchDeskSpeech.closedShift(command, start: start, calendar: cal))
                }
            } else if request.issuedAt < open.start {
                // No shift on the watch when it was tapped, and made before this one began.
                return refuse(WatchDeskSpeech.closedShift(command, start: nil, calendar: cal))
            }
            if case .cancelShift(let id) = command, inbox.resolve(shiftId: id) == open.id {
                command = .cancelShift(open.id)
            }
        }

        // Run it at the tap time, never before what's already recorded, never after now.
        let at = WatchTiming.effectiveTime(issuedAt: request.issuedAt, receivedAt: receivedAt,
                                           notBefore: WatchTiming.notBefore(for: command, state: state))
        var newShiftId: UUID?
        if case .clockIn = command { newShiftId = request.shiftId }
        let result = actions.perform(command, at: at, newShiftId: newShiftId)
        if result.succeeded, let newShiftId { noteOpenedByWatch(newShiftId) }
        return WatchReply(requestId: request.id, speech: result.speech, succeeded: result.succeeded,
                          lastAction: result.lastAction, appliedAt: result.succeeded ? at : nil,
                          // The store failed: nothing changed, so it can run later.
                          keepQueued: !result.succeeded && result.speech == Speech.saveFailed)
    }

    // MARK: State

    /// The next state, from the one counter every published or replied state takes.
    public func makeState() -> WatchState {
        let (epoch, revision) = nextRevision()
        let at = now()
        let state: WatchState
        if let field = actions.state() {
            state = WatchStateBuilder.build(state: field, now: at, epoch: epoch, revision: revision,
                                            recordWorkouts: settings().recordWorkouts,
                                            appliedRequestIds: inbox.recentIds(WatchState.maxAppliedIds),
                                            lastAction: actions.liveSnapshot()?.lastAction, canUndo: actions.canUndo)
        } else {
            state = WatchState.signedOut(epoch: epoch, revision: revision, now: at)
        }
        remember(WatchDisplay.phase(state))
        return state
    }

    /// True when a watch clock-in opened this shift (so the phone doesn't start the watch's
    /// workout for it: the watch already did).
    public func openedByWatch(_ shiftId: UUID) -> Bool {
        watchOpened.contains(shiftId)
    }

    private func noteOpenedByWatch(_ shiftId: UUID) {
        watchOpened.append(shiftId)
        if watchOpened.count > 20 { watchOpened.removeFirst(watchOpened.count - 20) }
    }

    /// The epoch is made with the counter, so a lost store (or a new phone) starts a new one,
    /// and the watch accepts its states even though their revisions start again.
    ///
    /// The epoch and the last revision handed out are kept here too, because a write can fail
    /// (a database suspended in the background, a full disk) and the watch has already seen
    /// what was handed out: the next state is always past both the store and this desk, so two
    /// states never tie, and a failed write never starts a new epoch per state.
    private func nextRevision() -> (UUID, Int) {
        let storedEpoch = Self.load(UUID.self, Self.epochKey, from: store)
        let storedRevision = Self.load(Int.self, Self.revisionKey, from: store)
        if let storedEpoch, let storedRevision, storedEpoch != epoch {
            // The first state this launch, or another desk's counter on the same store.
            epoch = storedEpoch
            issued = storedRevision
        }
        let current = epoch ?? UUID()
        if epoch == nil {
            epoch = current
            issued = 0
        }
        if storedEpoch != current { Self.save(current, Self.epochKey, to: store) }
        let next = max(storedEpoch == current ? storedRevision ?? 0 : 0, issued) + 1
        issued = next
        Self.save(next, Self.revisionKey, to: store)
        return (current, next)
    }

    private func remember(_ phase: WatchPhase) {
        guard phase != lastPhase else { return }
        lastPhase = phase
        Self.save(phase, Self.phaseKey, to: store)
    }

    // MARK: Workout summaries

    /// Keeps a workout summary from the watch, for the worker only: it never syncs, so no
    /// heart rate or calories ever reach the farm.
    public func save(_ summary: WorkoutSummary) {
        Self.save(summary, Self.summaryKey(shiftId: summary.shiftId, start: summary.start), to: store)
    }

    /// The summary the watch sent for a shift.
    public func summary(for shiftId: UUID) -> WorkoutSummary? {
        Self.load(WorkoutSummary.self, Self.summaryKey(shiftId: shiftId, start: .distantPast), from: store)
    }

    // MARK: Storage

    private func saveInbox() {
        Self.save(inbox, Self.inboxKey, to: store)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, from store: any KeyValueStore) -> T? {
        guard let data = try? store.value(forKey: key) else { return nil }
        return try? JSONCoding.decoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T?, _ key: String, to store: any KeyValueStore) {
        let data = value.flatMap { try? JSONCoding.encoder().encode($0) }
        try? store.setValue(data, forKey: key)
    }
}
