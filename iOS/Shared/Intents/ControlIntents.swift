import AppIntents
import Foundation
import TimeCardCore

// Intents behind the Control Center and lock-screen controls (iOS 18): Clock in, Next row
// and Break. They do what the Live Activity's buttons do, through `IntentRunner`, and also
// hand back what Siri would say as their dialog, so a refused press ("You’re not clocked
// in.") isn't silent. When iOS doesn't show it and no Live Activity is up to carry the
// reason, `IntentRunner.controlPress` posts a quiet notification instead.
//
// Like the buttons they're LiveActivityIntents, so they run in the app's process; in the
// widget extension `perform` is never called and compiles empty.

struct ClockInControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clock In"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
#if !WIDGET_EXTENSION
        let reply = await IntentRunner.controlPress(.clockIn(fieldId: nil))
        return .result(dialog: "\(reply.speech)")
#else
        return .result(dialog: "")
#endif
    }
}

struct NextRowControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark the Next Row"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
#if !WIDGET_EXTENSION
        let reply = await IntentRunner.controlPress(.markNextRow)
        return .result(dialog: "\(reply.speech)")
#else
        return .result(dialog: "")
#endif
    }
}

struct BreakControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start a Break"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
#if !WIDGET_EXTENSION
        let reply = await IntentRunner.controlPress(.startBreak(.break, reason: ""))
        return .result(dialog: "\(reply.speech)")
#else
        return .result(dialog: "")
#endif
    }
}
