import SwiftUI
import TimeCardCore

/// Edits one shift (or adds one when `shiftId` is nil): date, in and out, breaks, notes.
/// Opened from the Log tab and from the Clock tab's "fix the times" warning.
/// (Stand-in until the Log slice lands.)
struct ShiftEditorView: View {
    var shiftId: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlaceholderScreen(title: shiftId == nil ? "Add a Shift" : "Edit Shift", systemImage: "clock.badge",
                              headline: "Shift editor",
                              detail: "Date, clock in and out, breaks and notes.")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
        }
    }
}
