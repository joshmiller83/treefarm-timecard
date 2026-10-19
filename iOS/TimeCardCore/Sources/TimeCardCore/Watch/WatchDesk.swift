import Foundation

// STUB: slice d replaces
//
// The phone's side of the watch link: answers each watch request (envelope in, envelope out,
// always exactly one reply), dedupes retries through `WatchInbox`, resolves shift aliases,
// refuses taps for someone else or for a closed shift, runs the rest through
// `FieldActions.perform(_:at:newShiftId:)` at `WatchTiming.effectiveTime`, and builds every
// `WatchState` the phone sends from one revision counter (`watch.revision`, `watch.epoch` in
// the store). See docs/watch.md 1.3. Slice 0 fixed these signatures; slice d writes the real
// thing, test-first (WatchDeskTests).
@MainActor
public final class WatchDesk {
    public static let revisionKey = "watch.revision"
    public static let epochKey = "watch.epoch"

    private let actions: FieldActions
    private let store: any KeyValueStore
    private let settings: @MainActor () -> WatchSettings
    private let now: () -> Date
    private var revision = 0
    private let epoch = UUID()

    public init(actions: FieldActions, store: any KeyValueStore,
                settings: @escaping @MainActor () -> WatchSettings, now: @escaping () -> Date = Date.init) {
        self.actions = actions
        self.store = store
        self.settings = settings
        self.now = now
    }

    /// Envelope in, `.reply` envelope out, always.
    public func handle(_ data: Data, receivedAt: Date) -> Data {
        var reply = WatchReply.unreadable("Update Time Card on your iPhone.")
        reply.state = makeState()
        return (try? WatchEnvelope(.reply(reply)).data()) ?? Data()
    }

    /// The next state, from the one counter every published or replied state takes.
    public func makeState() -> WatchState {
        revision += 1
        return WatchState.signedOut(epoch: epoch, revision: revision, now: now())
    }

    /// Keeps a workout summary from the watch, for the worker only (never synced).
    public func save(_ summary: WorkoutSummary) {}
}
