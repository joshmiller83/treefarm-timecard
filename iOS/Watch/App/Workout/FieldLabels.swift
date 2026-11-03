import Foundation
import Observation
import TreeFarmKit
import WatchKit

/// What the person says they're doing, for the field log (docs/gis.md 10): Start row, Stop row,
/// Prep and Rest on the watch. The screens read it; `FieldLogger` writes it into every second
/// and takes the changes as they happen. Nothing here leaves the watch except in the log.
@MainActor
@Observable
final class FieldLabels {
    static let shared = FieldLabels()

    /// A field log is being written: only then do the screens offer the buttons.
    private(set) var logging = false
    private(set) var tracker = FieldActivityTracker(at: Date())
    @ObservationIgnored private var pending: [FieldActivityEvent] = []

    var activity: FieldActivity { tracker.activity }
    var since: Date { tracker.since }
    var row: RowChip? { tracker.row }

    /// A log opened: prep until the first row starts.
    func begin(at date: Date) {
        logging = true
        pending = [tracker.begin(at: date)]
    }

    func end() {
        logging = false
        pending = []
    }

    func startRow(_ chip: RowChip) {
        record(tracker.startRow(chip, at: Date()))
    }

    /// Prep or Rest. Stop row is Prep.
    func choose(_ activity: FieldActivity) {
        record(tracker.choose(activity, at: Date()))
    }

    /// Every state the watch shows: a mark (here, by Siri or on the phone) ends the row.
    func observe(_ state: WatchState?) {
        guard let event = tracker.observe(shiftTrees: state?.snapshot?.shiftTrees, at: Date()), logging else { return }
        pending.append(event)
    }

    /// The activity now and the changes since the last call, for the log's next second.
    func drain() -> (activity: FieldActivity, events: [FieldActivityEvent]) {
        defer { pending = [] }
        return (tracker.activity, pending)
    }

    private func record(_ event: FieldActivityEvent?) {
        guard let event else { return }
        pending.append(event)
        WKInterfaceDevice.current().play(event.activity == .shaping ? .start : .click)
    }
}
