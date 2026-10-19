import Foundation

/// What a field command did: the sentence for Siri or a toast, and whether anything changed.
public struct FieldReply: Equatable, Sendable {
    public var speech: String
    public var succeeded: Bool
    /// A few words for the lock screen: "Row 14 marked".
    public var lastAction: String?

    public init(speech: String, succeeded: Bool, lastAction: String? = nil) {
        self.speech = speech
        self.succeeded = succeeded
        self.lastAction = lastAction
    }
}

/// Runs field commands from Siri, the Live Activity, controls and the app against the
/// local store, using TreeFarmKit's `FieldEngine`. Everything it changes goes through
/// `TimeCardSession.save`, so it lands in the outbox and syncs.
///
/// The work position, the undo history and the last action are saved per farm and person,
/// because Siri and lock-screen buttons may wake the app in a fresh process each time.
@MainActor
public final class FieldActions {
    public static let signedOut = Speech.signedOut

    public let session: TimeCardSession
    private let now: () -> Date
    /// Called with the new lock-screen snapshot after every change (nil when off the clock).
    public var onLiveSnapshot: (@MainActor (LiveSnapshot?) -> Void)?

    public init(session: TimeCardSession, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    /// What `state()` and `liveSnapshot()` were last built from, and what they gave.
    private struct StateKey: Equatable {
        var generation: UUID
        var revision: Int
        var farm: Farm
        var me: Member
        var position: Data?
    }
    private var cachedState: (key: StateKey, state: FieldState)?
    /// Goes up each time `state()` had to be built again: anything derived from the state can
    /// be kept until it changes.
    public private(set) var stateVersion = 0
    private var cachedLive: (key: StateKey, last: String?, canUndo: Bool, day: DayKey, snapshot: LiveSnapshot?)?
    private var cachedUndo: (data: Data?, stack: UndoStack<UndoEntry>)?

    /// The engine's view of the open farm for the signed-in person, or nil when signed out.
    /// Built once per change to the store (a late-season farm has thousands of marks, and a
    /// screen reads this many times per redraw); the season's index comes from the store.
    public func state() -> FieldState? {
        // Before the farm's records load there's nothing true to say (an empty map, no shift).
        guard session.hasOpened, let farm = session.farm, let me = session.membership else { return nil }
        let snap = session.snapshot
        let key = StateKey(generation: snap.generation, revision: snap.revision, farm: farm, me: me,
                           position: try? session.store.value(forKey: Self.key("position", farm: farm.id, user: me.userId)))
        if let cachedState, cachedState.key == key { return cachedState.state }
        let state = FieldState(
            farm: farm,
            me: me,
            season: snap.activeSeason,
            fields: Array(snap.fields.values),
            blocks: Array(snap.blocks.values),
            myShifts: snap.shifts.values.filter { $0.userId == me.userId },
            marks: Array(snap.marks.values),
            members: Array(snap.members.values),
            position: key.position.flatMap { try? JSONCoding.decoder().decode(WorkPosition.self, from: $0) },
            notes: Array(snap.notes.values),
            seasonIndex: farm.activeSeasonId == snap.farm?.activeSeasonId ? snap.seasonIndex : nil)
        cachedState = (key, state)
        stateVersion += 1
        return state
    }

    public var canUndo: Bool {
        guard let farm = session.farm, let me = session.membership else { return false }
        return !undoStack(farm: farm.id, user: me.userId).isEmpty
    }

    /// Runs one command. Failures change nothing and say why.
    @discardableResult
    public func perform(_ command: FieldCommand) -> FieldReply {
        guard let state = state() else { return FieldReply(speech: Self.signedOut, succeeded: false) }
        let farmId = state.farm.id, userId = state.me.userId
        let at = now().roundedToMillisecond
        var undo = undoStack(farm: farmId, user: userId)
        let before = undo

        switch FieldEngine.perform(command, state: state, undo: &undo, now: at) {
        case .failure(let failure):
            // An undo that couldn't be used is dropped, so the next one isn't stuck on it.
            if undo.entries != before.entries {
                save(undo, "undo", farm: farmId, user: userId)
                publishLiveSnapshot()
            }
            return FieldReply(speech: failure.speech, succeeded: false)
        case .success(let outcome):
            do {
                if !outcome.records.isEmpty { try session.save(outcome.records) }
            } catch {
                return FieldReply(speech: Speech.saveFailed, succeeded: false)
            }
            if outcome.position != state.position {
                save(outcome.position, "position", farm: farmId, user: userId)
            }
            if undo.entries != before.entries {
                save(undo, "undo", farm: farmId, user: userId)
            }
            save(outcome.lastAction, "lastAction", farm: farmId, user: userId)
            publishLiveSnapshot()
            return FieldReply(speech: outcome.speech, succeeded: true, lastAction: outcome.lastAction)
        }
    }

    /// A question to ask out loud before running the command, or nil to just do it.
    public func confirmation(for command: FieldCommand) -> String? {
        guard let state = state() else { return nil }
        return FieldEngine.confirmation(for: command, state: state, now: now())
    }

    public func answer(_ question: FieldQuestion) -> String {
        guard let state = state() else { return Self.signedOut }
        return FieldAnswers.answer(question, state: state, now: now())
    }

    /// What the Live Activity should show right now.
    public func liveSnapshot() -> LiveSnapshot? {
        guard let state = state(), let key = cachedState?.key else { return nil }
        let last = load(String.self, "lastAction", farm: state.farm.id, user: state.me.userId)
        let undo = canUndo
        let at = now()
        let day = state.calendar.dayKey(at)
        // The same while nothing changed: the timer counts from `timerStart` on its own.
        if let cachedLive, cachedLive.key == key, cachedLive.last == last, cachedLive.canUndo == undo, cachedLive.day == day {
            return cachedLive.snapshot
        }
        let snapshot = LiveSnapshot.build(state: state, now: at, lastAction: last, canUndo: undo)
        cachedLive = (key, last, undo, day, snapshot)
        return snapshot
    }

    public func publishLiveSnapshot() {
        onLiveSnapshot?(liveSnapshot())
    }

    /// The server turned down changes this phone made (trees someone else shaped first, a
    /// refused shift): undo entries that wrote them are dropped, and the lock screen shows the
    /// notice in place of the last action, with no Undo beside it.
    public func noteRefusal(_ notice: SyncNotice) {
        guard let farm = session.farm, let me = session.membership else { return }
        let keys = Set(notice.entityIds.map { RecordKey(notice.kind, $0) })
        var undo = undoStack(farm: farm.id, user: me.userId)
        let before = undo.entries
        undo.removeAll { !keys.isDisjoint(with: $0.written.keys) }
        if undo.entries != before { save(undo, "undo", farm: farm.id, user: me.userId) }
        guard notice.kind == .treeMark || notice.kind == .shift else {
            publishLiveSnapshot()
            return
        }
        save(Speech.firstSentence(notice.message), "lastAction", farm: farm.id, user: me.userId)
        publishLiveSnapshot()
    }

    // MARK: Saved per farm and person

    public static func key(_ name: String, farm: UUID, user: UUID) -> String {
        "field.\(name).\(farm.uuidString).\(user.uuidString)"
    }

    private func undoStack(farm: UUID, user: UUID) -> UndoStack<UndoEntry> {
        let data = try? session.store.value(forKey: Self.key("undo", farm: farm, user: user))
        if let cachedUndo, cachedUndo.data == data { return cachedUndo.stack }
        let stack = data.flatMap { try? JSONCoding.decoder().decode(UndoStack<UndoEntry>.self, from: $0) } ?? UndoStack()
        cachedUndo = (data, stack)
        return stack
    }

    private func load<T: Decodable>(_ type: T.Type, _ name: String, farm: UUID, user: UUID) -> T? {
        guard let data = try? session.store.value(forKey: Self.key(name, farm: farm, user: user)) else { return nil }
        return try? JSONCoding.decoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T?, _ name: String, farm: UUID, user: UUID) {
        let data = value.flatMap { try? JSONCoding.encoder().encode($0) }
        try? session.store.setValue(data, forKey: Self.key(name, farm: farm, user: user))
    }
}
