import Foundation
import TreeFarmKit

/// The watch app's own scripted WatchConnectivity for `-watchDemo` (docs/watch.md 7.3). The app
/// can't link `TreeFarmKitTestSupport`, so this plays the iPhone in-process with `DemoPhone`.
///
/// Launch arguments:
/// - `-watchDemo`: signed in, off the clock, next row 14 in block 2.
/// - `-watchDemoWorking`: on the clock since 7:02 instead; `-watchDemoLunch`: on lunch too.
/// - `-watchDemoPage controls|now|today`: the page to open on.
/// - `-watchDemoNoWorkouts`: "Record shifts as workouts" is off on the phone.
/// - `-watchDemoSignedOut`: nobody is signed in on the phone.
/// - `-watchDemoNeverConnected` (with `-watchPhoneAway`): the watch has never heard from it.
/// - `-watchPhoneAway`: the phone starts out of reach.
/// - `-watchPhoneBackAfter <seconds>`: an away phone comes back by itself after that long.
/// - `-watchPhonePushEvery <seconds>`: the phone pushes its state on its own (a context
///   without the watch's waiting taps, as when Siri on the phone changes something).
///
/// The Today page also shows its controls (phone away or back, push the state) in demo mode.
final class DemoWatchTransport: WatchTransport, @unchecked Sendable {
    static let argument = "-watchDemo"

    /// The page `-watchDemoPage` asks for.
    static func page(_ arguments: [String]) -> ShiftPage? {
        guard let i = arguments.firstIndex(of: "-watchDemoPage"), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "controls": return .controls
        case "today": return .today
        case "now": return .now
        default: return nil
        }
    }

    let events: AsyncStream<WatchTransportEvent>
    let phone: DemoPhone
    private let continuation: AsyncStream<WatchTransportEvent>.Continuation
    private let ledger = WatchEventLedger()
    private let lock = NSLock()
    private var reachable: Bool
    private let backAfter: Duration?
    private let pushEvery: Duration?
    /// How long the phone takes to answer, for a realistic "sending" dot.
    private let latency: Duration
    /// `-watchDemoNeverConnected`: no state yet, until the phone is asked.
    private let neverConnected: Bool

    @MainActor
    init(phone: DemoPhone, reachable: Bool = true, backAfter: Duration? = nil, pushEvery: Duration? = nil,
         latency: Duration = .milliseconds(250), neverConnected: Bool = false) {
        self.phone = phone
        self.neverConnected = neverConnected
        self.reachable = reachable
        self.backAfter = backAfter
        self.pushEvery = pushEvery
        self.latency = latency
        (events, continuation) = AsyncStream.makeStream()
    }

    @MainActor
    static func fromLaunchArguments(_ arguments: [String]) -> DemoWatchTransport {
        func seconds(after flag: String) -> Duration? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count, let value = Double(arguments[i + 1]) else { return nil }
            return .milliseconds(Int(value * 1000))
        }
        let phone = DemoPhone(working: arguments.contains("-watchDemoWorking"), lunch: arguments.contains("-watchDemoLunch"))
        phone.recordWorkouts = !arguments.contains("-watchDemoNoWorkouts")
        phone.signedIn = !arguments.contains("-watchDemoSignedOut")
        return DemoWatchTransport(phone: phone,
                                  reachable: !arguments.contains("-watchPhoneAway"),
                                  backAfter: seconds(after: "-watchPhoneBackAfter"),
                                  pushEvery: seconds(after: "-watchPhonePushEvery"),
                                  neverConnected: arguments.contains("-watchDemoNeverConnected"))
    }

    // MARK: WatchTransport

    var isReachable: Bool { lock.withLock { reachable } }
    var hasContentPending: Bool { false }

    func activate() {
        continuation.yield(.activated(paired: true, installed: true, complicationEnabled: false))
        continuation.yield(.reachabilityChanged(isReachable))
        Task { @MainActor in
            // What WatchConnectivity replays after activation: the last application context.
            if !self.neverConnected { self.pushState() }
            if let backAfter = self.backAfter {
                try? await Task.sleep(for: backAfter)
                self.setReachable(true)
            }
        }
        if let pushEvery {
            Task { @MainActor in
                while true {
                    try? await Task.sleep(for: pushEvery)
                    self.pushState()
                }
            }
        }
    }

    func send(_ message: Data, timeout: Duration) async throws -> Data {
        guard isReachable else { throw WatchTransportError.notReachable }
        try? await Task.sleep(for: latency)
        guard isReachable else { throw WatchTransportError.notReachable }
        return await MainActor.run { phone.handle(message) }
    }

    func post(_ message: Data) async throws {
        guard isReachable else { throw WatchTransportError.notReachable }
    }

    func publishContext(_ state: Data) throws {}

    func transferComplicationState(_ state: Data) -> Bool { false }

    func drained() async {
        await ledger.drained()
    }

    // MARK: The script

    @MainActor
    func setReachable(_ value: Bool) {
        lock.withLock { reachable = value }
        continuation.yield(.reachabilityChanged(value))
    }

    /// The phone publishes its state, as an application context.
    @MainActor
    func pushState() {
        guard let data = try? WatchEnvelope(.state(phone.makeState())).data() else { return }
        continuation.yield(.contextReceived(data, done: ledger.begin()))
    }
}
