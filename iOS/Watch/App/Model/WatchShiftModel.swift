import AppIntents
import Foundation
import Observation
import TreeFarmKit
import WidgetKit

// The only thing the views, intents and workout code talk to (docs/watch.md 1.4).
//
// It holds the **confirmed** state (the newest `WatchState` from the phone, taken only when it
// `supersedes` the one held), the courier's outbox and in-flight requests, and from them the
// **displayed** state: the confirmed state with every waiting tap applied, oldest first. Every
// view, the complications and `WatchConfirm` read `displayed`, so a tap shows at once and stays
// shown while it waits for the phone.
//
// Two loops on the main actor read what arrives: the transport's events (states, reachability)
// and the courier's (answers to queued taps). Each change is handed to the observers registered
// at launch (the workout, the Action button donor, the App Shortcut parameters) and written to
// `WatchStateFile` for the complications.

/// How the phone can be reached: `.reachable`, `.outOfReach`, `.needsUnlock`, `.neverConnected`.
typealias PhoneReach = WatchDisplay.Reach

/// Where a command came from.
enum WatchSource: Sendable {
    case button, doubleTap, crown, siri, actionButton
}

/// What became of a command.
enum WatchOutcome: Equatable, Sendable {
    /// The phone did it.
    case done(WatchReply)
    /// The phone refused it; `reply.speech` says why.
    case refused(WatchReply)
    /// Saved on the watch for later; the string is what to show or say.
    case queued(String)
    /// Not sent and not saved (live-only with the phone away, or refused by `WatchPrecheck`).
    case notSent(String)
}

/// The short message over the bottom of the timer (docs/watch.md 3.10).
struct WatchToast: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case success, refusal, saved, info }

    var text: String
    var kind: Kind

    /// 2.5 s for success and "Saved on watch"; 4 s for a refusal or a sentence to read.
    var duration: TimeInterval {
        switch kind {
        case .success, .saved: 2.5
        case .refusal, .info: 4
        }
    }
}

/// What the model's observers hear after every state, outbox or in-flight change.
struct WatchModelChange {
    let displayed: WatchState?
    let waitingCount: Int
    let workout: WorkoutInputs
}

@MainActor
@Observable
final class WatchShiftModel {
    static let shared = WatchShiftModel.makeShared()

    /// The complications' widget kind.
    static let complicationKind = "timecard.watch.shift"
    /// How long Undo clock-in shows after a watch clock-in.
    static let undoClockInWindow: TimeInterval = 120
    /// The shift summary shows after a clock-out for this long.
    static let summaryWindow: TimeInterval = 3600

    // MARK: What the views read

    private(set) var confirmed: WatchState?
    private(set) var displayed: WatchState?
    private(set) var reach: PhoneReach = .neverConnected
    /// Outbox items not in flight.
    private(set) var waitingCount = 0
    /// Goes away by itself after its `duration`, however it was set (the workout sets it too).
    var toast: WatchToast? {
        didSet {
            guard let toast else { return }
            toastGeneration += 1
            let generation = toastGeneration
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(toast.duration))
                guard let self, self.toastGeneration == generation else { return }
                self.toast = nil
            }
        }
    }
    /// The taps waiting for the phone, oldest first (the Queue sheet).
    private(set) var queue: [WatchRequest] = []
    /// Older row taps dropped past the outbox limit.
    private(set) var dropped = 0
    /// A tap is on its way: the "sending" dot.
    private(set) var isSending = false
    /// No answer for 3 s: "Waiting for phone…".
    private(set) var isSlow = false
    /// A watch clock-out waits for the phone ("Clock-out waiting for iPhone").
    private(set) var clockOutWaiting = false
    /// Minted ids of watch clock-ins the phone refused, the last 10 (for the workout).
    private(set) var refusedClockIns: [UUID] = []
    /// The on-the-clock page, and the wrist-raise rule.
    var pages = PageMemory()

    private var memory: WatchModelMemory

    // MARK: Dependencies

    @ObservationIgnored let transport: any WatchTransport
    @ObservationIgnored private let courier: WatchCourier
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let haptics: @MainActor (WatchHapticEvent) -> Void
    @ObservationIgnored private let reloadComplications: @MainActor () -> Void
    @ObservationIgnored private let sessionActive: @MainActor () -> Bool
    /// The scripted phone in `-watchDemo` mode (its controls show on the Today page).
    @ObservationIgnored let demo: DemoWatchTransport?
    /// How long a tap waits before the button says "Waiting for phone…".
    @ObservationIgnored var slowAfter: Duration = .seconds(3)

    // MARK: Bookkeeping

    @ObservationIgnored private var snapshot: CourierSnapshot
    /// Taps sent from here whose `submit` hasn't returned yet.
    @ObservationIgnored private var submitting: [WatchRequest] = []
    /// Requests whose answer is handled where they were sent (not as a background flush).
    @ObservationIgnored private var directIds: Set<UUID> = []
    @ObservationIgnored private var reachable = false
    @ObservationIgnored private var needsUnlock = false
    @ObservationIgnored private var activated = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [@MainActor (WatchModelChange) -> Void] = []
    @ObservationIgnored private var lastChange: (displayed: WatchState?, waiting: Int, workout: WorkoutInputs)?
    @ObservationIgnored private var lastFile: WatchStateFile.Contents?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var toastGeneration = 0
    @ObservationIgnored private var lastFirstChip: RowChip?
    @ObservationIgnored private var refreshing = false

    init(transport: any WatchTransport, store: any WatchOutboxStore, directory: URL?,
         replyTimeout: Duration = .seconds(4),
         now: @escaping @Sendable () -> Date = { Date() },
         haptics: @escaping @MainActor (WatchHapticEvent) -> Void = { WatchHaptics.play($0) },
         reloadComplications: @escaping @MainActor () -> Void = {
             WidgetCenter.shared.reloadTimelines(ofKind: WatchShiftModel.complicationKind)
         },
         sessionActive: @escaping @MainActor () -> Bool = { WatchShiftModel.sessionExists(ShiftWorkout.shared.live) },
         demo: DemoWatchTransport? = nil) {
        self.transport = transport
        self.courier = WatchCourier(transport: transport, store: store, replyTimeout: replyTimeout, now: now)
        self.directory = directory
        self.now = now
        self.haptics = haptics
        self.reloadComplications = reloadComplications
        self.sessionActive = sessionActive
        self.demo = demo
        self.snapshot = CourierSnapshot(outbox: store.load() ?? WatchOutbox())
        self.memory = WatchModelMemory.read(from: directory)
        self.confirmed = memory.confirmed
        self.refusedClockIns = memory.refusedClockIns
        recompute()
    }

    // MARK: Starting

    /// Starts reading the transport and the courier, then activates the transport. The app
    /// delegate calls it first thing at launch; calling it again does nothing.
    func activate() {
        guard !started else { return }
        started = true
        // The observers were registered after `init` read the state and outbox from disk, and
        // WatchConnectivity replays a context that doesn't supersede it: tell them now, so a
        // workout recovered after a crash is reconciled (docs/watch.md 2.5).
        lastChange = nil
        notifyObservers()
        let events = transport.events
        tasks.append(Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        })
        let updates = courier.updates
        tasks.append(Task { [weak self] in
            for await update in updates {
                guard let self else { return }
                await self.handle(update)
            }
        })
        // Once a minute while a workout session exists (even a stopped one), try the outbox:
        // the session keeps the app running and reachable with the wrist down.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                self.pruneRefused()
                if self.sessionActive() { await self.flush() }
            }
        })
        transport.activate()
        publishComplications()
    }

    /// The observers the app needs at launch (docs/watch.md 8.3).
    func registerAppObservers() {
        addObserver { change in ShiftWorkout.shared.reconcile(change.workout) }
        addObserver { change in ActionButtonDonor.shared.update(change.displayed) }
        addObserver { [weak self] change in
            guard let self else { return }
            let chip = change.displayed?.nextRows.first
            guard chip != self.lastFirstChip else { return }
            self.lastFirstChip = chip
            WatchShortcuts.updateAppShortcutParameters()
        }
    }

    func addObserver(_ observer: @escaping @MainActor (WatchModelChange) -> Void) {
        observers.append(observer)
    }

    // MARK: Commands

    func perform(_ command: FieldCommand, source: WatchSource) async -> WatchOutcome {
        var command = command
        if case .undo = command { return await undo() }
        guard let state = displayed else {
            Task { await refresh() }
            return fail(WatchDisplay.neverConnected)
        }
        guard state.signedIn else { return fail(WatchDisplay.signedOut) }
        // What you see is what gets marked: the chip shown, never "the next row" on the phone.
        if case .markNextRow = command {
            guard let chip = WatchDisplay.chips(state).first else { return fail(WatchDisplay.noChipLine(state)) }
            command = .markRow(chip.rowRef)
        }
        // With the phone in reach the phone decides; out of reach, don't queue a sure failure.
        if !transport.isReachable, let refusal = WatchPrecheck.refusal(for: command, state: state) {
            return fail(refusal)
        }

        let request = makeRequest(command, state: state)
        if case .clockIn = command {
            memory.watchClockIn = request.shiftId
            memory.undoClockInUntil = request.issuedAt.addingTimeInterval(Self.undoClockInWindow)
            saveMemory()
        } else if Self.isWork(command), request.shiftId != nil, request.shiftId == memory.watchClockIn,
                  memory.undoClockInUntil != nil {
            // The phone won't cancel a shift with a mark or a break on it.
            memory.undoClockInUntil = nil
            saveMemory()
        }
        submitting.append(request)
        directIds.insert(request.id)
        recompute()
        let slow = watchForSlowReply(request.id)

        let result = await courier.submit(request, durable: true)

        slow.cancel()
        let outcome = await settle(request, result, source: source)
        await syncCourier()
        submitting.removeAll { $0.id == request.id }
        isSlow = false
        recompute()
        publishComplications()
        return outcome
    }

    /// Undo: takes back the newest waiting tap on the watch first ("Took back row 15. It wasn't
    /// sent yet."); with nothing waiting it asks the phone, which must be in reach.
    func undo() async -> WatchOutcome {
        if !snapshot.waiting.isEmpty, let taken = await courier.takeBackLastQueued() {
            await syncCourier()
            publishComplications()
            let text = WatchDisplay.tookBack(taken)
            show(WatchToast(text: text, kind: .success))
            haptics(.confirmed)
            return .done(WatchReply(requestId: taken.id, speech: text, succeeded: true, lastAction: text))
        }
        guard transport.isReachable else { return fail(WatchDisplay.undoNeedsPhone) }
        let request = WatchRequest(body: .command(.undo), issuedAt: now(), userId: displayed?.userId)
        directIds.insert(request.id)
        let result = await courier.submit(request, durable: false)
        let outcome = await settle(request, result, source: .button)
        await syncCourier()
        publishComplications()
        return outcome
    }

    /// Takes back a watch clock-in (`.cancelShift`), offered for 2 minutes after it. It is
    /// durable, so it works while the clock-in still waits for the phone.
    func undoClockIn() async -> WatchOutcome {
        guard let shiftId = displayed?.shiftId else { return fail(Speech.notClockedIn) }
        let outcome = await perform(.cancelShift(shiftId), source: .button)
        if case .refused = outcome {} else {
            memory.undoClockInUntil = nil
            saveMemory()
        }
        return outcome
    }

    /// Undo clock-in shows: the shift on screen is the one this watch just clocked in, less
    /// than 2 minutes ago, with no work on it yet (`FieldEngine.cancelShift` refuses a shift
    /// with marks or breaks, and a mark or break from the watch ends the window).
    var canUndoClockIn: Bool {
        guard let until = memory.undoClockInUntil, let minted = memory.watchClockIn, now() < until,
              let shown = displayed, shown.shiftId == minted, let snapshot = shown.snapshot else { return false }
        return snapshot.phase == .working && snapshot.shiftTrees == 0
    }

    /// Commands that put work on a shift, so it can no longer be cancelled.
    private static func isWork(_ command: FieldCommand) -> Bool {
        switch command {
        case .markRow, .markNextRow, .markTrees, .startBreak, .endBreak: true
        default: false
        }
    }

    /// When Undo clock-in stops showing.
    var undoClockInUntil: Date? { canUndoClockIn ? memory.undoClockInUntil : nil }

    /// A question for the phone (live only).
    func ask(_ question: FieldQuestion) async -> String {
        let request = WatchRequest(body: .question(question), issuedAt: now(), userId: displayed?.userId)
        directIds.insert(request.id)
        switch await courier.submit(request, durable: false) {
        case .replied(let reply):
            if let state = reply.state { await accept(state) }
            return reply.speech
        case .queued:
            directIds.remove(request.id)
            return WatchDisplay.askNeedsPhone
        case .notSent(let text):
            directIds.remove(request.id)
            return text
        }
    }

    /// The watch's own copy of the engine's question, asked before clock-out and before a row
    /// far from the next one. No round trip, so it works out of reach.
    func confirmation(for command: FieldCommand) -> String? {
        displayed.flatMap { WatchConfirm.question(for: command, state: $0, now: now()) }
    }

    /// Asks the phone for its state, then sends anything waiting.
    func refresh() async {
        if transport.isReachable, !refreshing {
            refreshing = true
            defer { refreshing = false }
            let request = WatchRequest(body: .refresh, issuedAt: now(), userId: displayed?.userId)
            directIds.insert(request.id)
            if case .replied(let reply) = await courier.submit(request, durable: false), let state = reply.state {
                await accept(state)
            } else {
                directIds.remove(request.id)
            }
        }
        await flush()
    }

    /// Shows a sentence the watch says on its own (the battery at clock-in).
    func say(_ text: String) {
        show(WatchToast(text: text, kind: .info))
    }

    /// Sends what waits, oldest first.
    func flush() async {
        await courier.flush()
        await syncCourier()
        publishComplications()
    }

    // MARK: Scenes and background wakes

    /// The app came forward: back to Now after 30 s away, and try the outbox. No round trip
    /// otherwise: the phone pushes its state when something changes (docs/watch.md 2.8).
    func sceneBecameActive() {
        pages.cameBack(at: now())
        pruneRefused()
        Task { await refreshOrFlush() }
    }

    func sceneWentAway() {
        pages.wentAway(at: now())
    }

    /// `.backgroundTask(.watchConnectivity)`: done once activation finished, nothing is pending
    /// and every delivered context and user-info event was handled.
    func handleBackgroundWake() async {
        activate()
        for _ in 0..<50 where !activated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        for _ in 0..<100 where transport.hasContentPending {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await transport.drained()
    }

    // MARK: The shift summary

    /// The shift just closed, shown once after a clock-out (the watch's, or the phone's within
    /// the hour). Never pay.
    var summary: ClosedShift? {
        guard WatchDisplay.phase(displayed) == .offClock, let closed = displayed?.lastClosedShift,
              closed.shiftId != memory.dismissedSummaryId,
              now().timeIntervalSince(closed.end) < Self.summaryWindow else { return nil }
        return closed
    }

    func dismissSummary() {
        memory.dismissedSummaryId = displayed?.lastClosedShift?.shiftId
        saveMemory()
    }

    /// Refused taps from the last hour, newest first.
    var refused: [RefusedTap] {
        let cutoff = now().addingTimeInterval(-RefusedTap.keptFor)
        return memory.refused.filter { $0.at > cutoff }.reversed()
    }

    /// What the workout decides from (docs/watch.md 2.2): taps still being handed to the
    /// courier count as waiting, so a clock-in starts the workout before any reply.
    var workoutInputs: WorkoutInputs {
        let known = Set(snapshot.outbox.pending.map(\.id)).union(snapshot.inFlight.map(\.id))
        let outbox = snapshot.waiting + submitting.filter { !known.contains($0.id) }
        return WorkoutInputs(confirmed: confirmed, outbox: outbox, inFlight: snapshot.inFlight, refusedClockIns: refusedClockIns)
    }

    // MARK: Events

    private func handle(_ event: WatchTransportEvent) async {
        switch event {
        case .activated:
            activated = true
            reachable = transport.isReachable
            recompute()
            if reachable { Task { await refreshOrFlush() } }
        case .reachabilityChanged(let value):
            reachable = value
            recompute()
            if value { Task { await refreshOrFlush() } }
        case .needsUnlock(let value):
            needsUnlock = value
            recompute()
        case .received(let data, _):
            if let state = Self.state(in: data) { await accept(state) }
            publishComplications()
        case .contextReceived(let data, let done), .userInfoReceived(let data, let done):
            if let state = Self.state(in: data) { await accept(state) }
            publishComplications()
            done()
        }
    }

    private func refreshOrFlush() async {
        if confirmed == nil { await refresh() } else { await flush() }
    }

    private func handle(_ event: CourierEvent) async {
        if case .replied(let request, let reply) = event {
            let direct = directIds.remove(request.id) != nil
            if let state = reply.state { await accept(state) }
            noteRefusedClockIn(request, reply)
            if !direct, request.isCommand, !reply.succeeded, !reply.keepQueued {
                // A tap that waited, refused now: listed for an hour, said once.
                memory.refused.append(RefusedTap(request: request, speech: reply.speech, at: now()))
                pruneRefused()
                saveMemory()
                show(WatchToast(text: reply.speech, kind: .refusal))
                haptics(.refused)
            }
        }
        await syncCourier()
        publishComplications()
    }

    /// Takes a state from the phone when it supersedes the one held.
    private func accept(_ state: WatchState) async {
        guard state.supersedes(confirmed) else { return }
        confirmed = state
        memory.confirmed = state
        saveMemory()
        recompute()
        await courier.acknowledge(state)
        await syncCourier()
    }

    private func syncCourier() async {
        snapshot = await courier.snapshot
        recompute()
    }

    // MARK: Answers

    /// Turns the courier's answer into the outcome, the toast and the one haptic.
    private func settle(_ request: WatchRequest, _ result: CourierResult, source: WatchSource) async -> WatchOutcome {
        switch result {
        case .replied(let reply):
            if let state = reply.state { await accept(state) }
            noteRefusedClockIn(request, reply)
            if reply.keepQueued {
                show(WatchToast(text: reply.speech, kind: .info))
                haptics(.queued)
                return .queued(reply.speech)
            }
            if reply.succeeded {
                show(WatchToast(text: reply.lastAction ?? reply.speech, kind: .success))
                haptics(Self.successHaptic(request.command))
                return .done(reply)
            }
            show(WatchToast(text: reply.speech, kind: .refusal))
            haptics(.refused)
            return .refused(reply)
        case .queued(let count):
            directIds.remove(request.id)
            // A phone restarted and not yet unlocked can't be reached until it is: say so.
            let text = reach == .needsUnlock ? WatchDisplay.unlockPhone : WatchDisplay.savedOnWatch(waiting: count)
            show(WatchToast(text: text, kind: .saved))
            haptics(.queued)
            return .queued(source == .siri ? WatchDisplay.savedForSiri : text)
        case .notSent(let text):
            directIds.remove(request.id)
            return fail(text)
        }
    }

    private static func successHaptic(_ command: FieldCommand?) -> WatchHapticEvent {
        switch command {
        case .clockIn?: .started
        case .clockOut?: .stopped
        case .startBreak?: .breakStarted
        case .endBreak?: .backToWork
        default: .confirmed
        }
    }

    private func fail(_ text: String) -> WatchOutcome {
        show(WatchToast(text: text, kind: .refusal))
        haptics(.refused)
        return .notSent(text)
    }

    private func noteRefusedClockIn(_ request: WatchRequest, _ reply: WatchReply) {
        guard case .clockIn? = request.command, !reply.succeeded, !reply.keepQueued, let minted = request.shiftId,
              !refusedClockIns.contains(minted) else { return }
        refusedClockIns = Array((refusedClockIns + [minted]).suffix(10))
        memory.refusedClockIns = refusedClockIns
        saveMemory()
        recompute()
    }

    private func show(_ toast: WatchToast) {
        self.toast = toast
    }

    private func watchForSlowReply(_ id: UUID) -> Task<Void, Never> {
        let wait = slowAfter
        return Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, self.submitting.contains(where: { $0.id == id }) else { return }
            self.isSlow = true
        }
    }

    // MARK: Requests

    /// Who and which shift a tap is for: a clock-in mints the new shift's id; a shift-scoped
    /// command carries the shift on screen when it was tapped.
    private func makeRequest(_ command: FieldCommand, state: WatchState) -> WatchRequest {
        let shiftId: UUID? = switch command {
        case .clockIn: UUID()
        default: WatchRequest.isShiftScoped(command) ? state.shiftId : nil
        }
        return WatchRequest(body: .command(command), issuedAt: now(), userId: state.userId, shiftId: shiftId)
    }

    private static func state(in data: Data) -> WatchState? {
        guard case .state(let state)? = try? WatchEnvelope.decode(data).message else { return nil }
        return state
    }

    // MARK: Derived state

    private func recompute() {
        let pending = snapshot.outbox.pending + snapshot.inFlight + submitting
        let shown = WatchOptimism.displayed(confirmed: confirmed, pending: pending)
        if shown != displayed { displayed = shown }
        let waiting = snapshot.waiting
        if waiting != queue { queue = waiting }
        if waiting.count != waitingCount { waitingCount = waiting.count }
        if snapshot.outbox.dropped != dropped { dropped = snapshot.outbox.dropped }
        let sending = !submitting.isEmpty || !snapshot.inFlight.isEmpty
        if sending != isSending { isSending = sending }
        let clockOut = waiting.contains { if case .clockOut? = $0.command { true } else { false } }
        if clockOut != clockOutWaiting { clockOutWaiting = clockOut }
        let newReach: PhoneReach = needsUnlock ? .needsUnlock : reachable ? .reachable : confirmed == nil ? .neverConnected : .outOfReach
        if newReach != reach { reach = newReach }
        notifyObservers()
    }

    private func notifyObservers() {
        let workout = workoutInputs
        if let last = lastChange, last.displayed == displayed, last.waiting == waitingCount, last.workout == workout { return }
        lastChange = (displayed, waitingCount, workout)
        let change = WatchModelChange(displayed: displayed, waitingCount: waitingCount, workout: workout)
        for observer in observers { observer(change) }
    }

    /// Writes the displayed state for the complications, and reloads them only when
    /// something they show changed.
    private func publishComplications() {
        guard let directory else { return }
        let contents = WatchStateFile.Contents(displayed: displayed, waitingCount: waitingCount, clockOutWaiting: clockOutWaiting)
        let old = lastFile ?? {
            let read = WatchStateFile.read(from: directory)
            return read == .empty ? nil : read
        }()
        lastFile = contents
        guard contents != old else { return }
        WatchStateFile.write(contents, to: directory)
        if ComplicationReload.needsReload(old: old, new: contents) { reloadComplications() }
    }

    private func pruneRefused() {
        let cutoff = now().addingTimeInterval(-RefusedTap.keptFor)
        let kept = memory.refused.filter { $0.at > cutoff }
        guard kept.count != memory.refused.count else { return }
        memory.refused = kept
        saveMemory()
    }

    private func saveMemory() {
        memory.write(to: directory)
    }
}

extension WatchShiftModel {
    /// A workout session exists (it may be stopped, waiting for a clock-out): it keeps the app
    /// running and reachable, so the outbox is tried once a minute and the rain lock shows.
    static func sessionExists(_ live: WorkoutLive) -> Bool {
        switch live.recording {
        case .recording, .paused, .waitingForClockOut: true
        case .off, .notAuthorized, .idle, .stoppedUnexpectedly: false
        }
    }
}

// MARK: - The shared model

extension WatchShiftModel {
    /// The app's model: WatchConnectivity normally, the scripted phone with `-watchDemo`, and
    /// a disconnected transport while hosting unit tests (no test touches the real WCSession).
    fileprivate static func makeShared() -> WatchShiftModel {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(DemoWatchTransport.argument) {
            let directory = URL.temporaryDirectory.appending(path: "watch-demo-\(UUID().uuidString)")
            let demo = DemoWatchTransport.fromLaunchArguments(arguments)
            let model = WatchShiftModel(transport: demo, store: FileOutboxStore(directory: directory), directory: directory, demo: demo)
            model.registerAppObservers()
            if let page = DemoWatchTransport.page(arguments) { model.pages.selection = page }
            return model
        }
        if isHostingTests {
            let directory = URL.temporaryDirectory.appending(path: "watch-test-host-\(UUID().uuidString)")
            return WatchShiftModel(transport: DisconnectedWatchTransport(), store: FileOutboxStore(directory: directory),
                                   directory: nil, reloadComplications: {}, sessionActive: { false })
        }
        let model = WatchShiftModel(transport: WCSessionTransport(), store: FileOutboxStore(), directory: WatchStateFile.directory)
        model.registerAppObservers()
        return model
    }

    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }
}
