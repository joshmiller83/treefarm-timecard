import Foundation
import Network

/// Reports whether the phone has a usable network, using `NWPathMonitor`.
/// Feed the readings to `ReachabilityTracker` to spot the moment it comes back.
public enum NetworkMonitor {
    /// The current reachability right away, then every change, until the caller stops iterating.
    public static func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = MonitorBox()
            monitor.monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.monitor.cancel() }
            monitor.monitor.start(queue: DispatchQueue(label: "TimeCard.NetworkMonitor"))
        }
    }

    private final class MonitorBox: @unchecked Sendable {
        let monitor = NWPathMonitor()
    }
}
