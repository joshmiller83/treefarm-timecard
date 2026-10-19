import AppIntents
import SwiftUI
import WidgetKit

// Control Center and lock-screen controls (iOS 18): Clock in, Next row and Break.
// Each runs the same intent as the Live Activity's buttons, which runs in the app's
// process through FieldActions, so a control says and does what Siri does.
// There's no clock-out control on purpose: a stray tap shouldn't end a shift.

@available(iOS 18.0, *)
struct ClockInControl: ControlWidget {
    static let kind = "com.timecard.control.clock-in"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ClockInButtonIntent()) {
                Label("Clock In", systemImage: "clock.badge.checkmark")
            }
        }
        .displayName("Clock In")
        .description("Start your shift and the lock-screen timer.")
    }
}

@available(iOS 18.0, *)
struct NextRowControl: ControlWidget {
    static let kind = "com.timecard.control.next-row"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: NextRowButtonIntent()) {
                Label("Next Row", systemImage: "scissors")
            }
        }
        .displayName("Next Row")
        .description("Mark the next open row shaped.")
    }
}

@available(iOS 18.0, *)
struct BreakControl: ControlWidget {
    static let kind = "com.timecard.control.break"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartBreakButtonIntent()) {
                Label("Break", systemImage: "cup.and.saucer.fill")
            }
        }
        .displayName("Take a Break")
        .description("Start a break. Back to work from the lock screen.")
    }
}
