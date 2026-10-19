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
    public static let signedOut = "Open Time Card to sign in."

    public let session: TimeCardSession
    private let now: () -> Date
    /// Called with the new lock-screen snapshot after every change (nil when off the clock).
    public var onLiveSnapshot: (@MainActor (LiveSnapshot?) -> Void)?

    public init(session: TimeCardSession, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    /// The engine's view of the open farm for the signed-in person, or nil when signed out.
    public func state() -> FieldState? {
        guard let farm = session.farm, let me = session.membership else { return nil }
        let snap = session.snapshot
        return FieldState(
            farm: farm,
            me: me,
            season: snap.activeSeason,
            fields: Array(snap.fields.values),
            blocks: Array(snap.blocks.values),
            myShifts: snap.shifts.values.filter { $0.userId == me.userId },
            marks: Array(snap.marks.values),
            members: Array(snap.members.values),
            position: load(WorkPosition.self, "position", farm: farm.id, user: me.userId),
            notes: Array(snap.notes.values))
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
            return FieldReply(speech: failure.speech, succeeded: false)
        case .success(let outcome):
            do {
                if !outcome.records.isEmpty { try session.save(outcome.records) }
            } catch {
                return FieldReply(speech: "Couldn’t save that on this phone. Try again.", succeeded: false)
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
        guard let state = state() else { return nil }
        let last = load(String.self, "lastAction", farm: state.farm.id, user: state.me.userId)
        return LiveSnapshot.build(state: state, now: now(), lastAction: last, canUndo: canUndo)
    }

    public func publishLiveSnapshot() {
        onLiveSnapshot?(liveSnapshot())
    }

    // MARK: Saved per farm and person

    public static func key(_ name: String, farm: UUID, user: UUID) -> String {
        "field.\(name).\(farm.uuidString).\(user.uuidString)"
    }

    private func undoStack(farm: UUID, user: UUID) -> UndoStack<UndoEntry> {
        load(UndoStack<UndoEntry>.self, "undo", farm: farm, user: user) ?? UndoStack()
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
