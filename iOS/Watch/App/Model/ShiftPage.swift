import Foundation

/// The on-the-clock pages, horizontal as in Apple's Workout app (docs/watch.md 3.1):
/// Controls ← Now → Today. Every wrist raise lands on Now.
enum ShiftPage: Hashable, Sendable, CaseIterable {
    case controls, now, today
}

/// Which page shows, and the rule that brings it back to Now.
struct PageMemory: Equatable, Sendable {
    /// Away this long, the next wrist raise lands on Now.
    static let resetAfter: TimeInterval = 30

    var selection: ShiftPage = .now
    private var awaySince: Date?

    init(selection: ShiftPage = .now) {
        self.selection = selection
    }

    /// The app left the screen (wrist down, Always On, background). The first time counts.
    mutating func wentAway(at time: Date) {
        if awaySince == nil { awaySince = time }
    }

    mutating func cameBack(at time: Date) {
        defer { awaySince = nil }
        guard let awaySince, time.timeIntervalSince(awaySince) >= Self.resetAfter else { return }
        selection = .now
    }

    /// Only Now (and the off-clock screen) takes Double Tap, and never while a dialog shows.
    func primaryActionEnabled(dialogShown: Bool) -> Bool {
        selection == .now && !dialogShown
    }
}
