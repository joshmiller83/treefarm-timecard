import Foundation
import TimeCardCore

/// A launch argument that puts a UI-test run on the clock, so the real Live Activity can be
/// seen on the simulator's lock screen without tapping through the app:
///
///     -UITestInMemory -LiveActivityDemo working   clocked in 6 h 42 min ago on the demo farm
///     -UITestInMemory -LiveActivityDemo rows      the same, then two rows marked ("Row 6 marked · Undo")
///     -UITestInMemory -LiveActivityDemo lunch     two rows marked, then lunch
///     -UITestInMemory -LiveActivityDemo break     a break for "Parts run"
///
/// It only runs with the in-memory demo farm (`-UITestInMemory`), and goes through
/// `FieldActions` like Siri and the lock screen do.
@MainActor
enum LiveActivityLaunchScript {
    static let argument = "-LiveActivityDemo"

    static var isRequested: Bool { phase != nil }

    static var phase: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains(LaunchMode.inMemoryArgument), let i = args.firstIndex(of: argument) else { return nil }
        return i + 1 < args.count ? args[i + 1] : "working"
    }

    /// Called while AppModel is being made, so the work waits for the next turn of the main actor.
    static func runIfRequested() {
        guard let phase else { return }
        Task { @MainActor in
            let model = AppModel.shared
            await model.start()
            // The demo farm comes from the stub server's first sync.
            for _ in 0..<100 where model.session.snapshot.blocks.isEmpty {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard model.actions.state()?.openShift == nil else { return }
            let actions = model.actions
            actions.perform(.clockIn(fieldId: nil))
            actions.perform(.changeStart(Date().addingTimeInterval(-(6 * 3600 + 42 * 60)).roundedToMillisecond))
            switch phase {
            case "rows":
                actions.perform(.markNextRow)
                actions.perform(.markNextRow)
            case "lunch":
                actions.perform(.markNextRow)
                actions.perform(.markNextRow)
                actions.perform(.startBreak(.lunch, reason: ""))
            case "break":
                actions.perform(.startBreak(.break, reason: "Parts run"))
            default:
                break
            }
        }
    }
}
