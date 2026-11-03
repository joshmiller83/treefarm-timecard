import Foundation

// What the person says they're doing while on the clock, tapped on the watch for the phase 0
// field log (docs/gis.md 10): the labels the matching engine learns from. They go into the log
// only, so like the rest of it they stay on the person's own devices and never reach the farm.

/// One of three, always: shaping a row, prep (tools, the truck, driving, helping, walking to
/// the next row), or rest on the clock. Lunch and breaks stay what they were: they pause the
/// workout, and the log's phase says so.
public enum FieldActivity: String, Codable, Hashable, Sendable, CaseIterable {
    case shaping, prep, rest
}

/// A change of activity, as the log records it.
public struct FieldActivityEvent: Codable, Hashable, Sendable {
    public enum Cause: String, Codable, Hashable, Sendable {
        /// The log opened (clock-in): prep until the first row starts.
        case start
        /// A tap on Start row, Stop row, Prep or Rest.
        case button
        /// The row was marked (here, by Siri or on the phone), which ends it.
        case mark
    }

    public var t: Date
    public var activity: FieldActivity
    public var by: Cause
    /// The row started, for shaping. Counts from 0, like `RowChip`.
    public var blockId: UUID?
    public var blockName: String?
    public var row: Int?

    public init(t: Date, activity: FieldActivity, by: Cause, blockId: UUID? = nil, blockName: String? = nil, row: Int? = nil) {
        self.t = t
        self.activity = activity
        self.by = by
        self.blockId = blockId
        self.blockName = blockName
        self.row = row
    }
}

/// The current activity and the rules between them. Each change returns its event for the log;
/// a tap that changes nothing returns nil.
public struct FieldActivityTracker: Equatable, Sendable {
    public private(set) var activity: FieldActivity
    public private(set) var since: Date
    /// The row being shaped.
    public private(set) var row: RowChip?
    /// The shift's tree count when last seen: when it goes up, a row was marked.
    private var trees: Int?

    public init(at date: Date) {
        activity = .prep
        since = date
    }

    /// A new log: prep, until the first row starts.
    public mutating func begin(at date: Date) -> FieldActivityEvent {
        self = FieldActivityTracker(at: date)
        return FieldActivityEvent(t: date, activity: .prep, by: .start)
    }

    /// Start row: shaping that row. Starting another row while shaping moves to it.
    public mutating func startRow(_ chip: RowChip, at date: Date) -> FieldActivityEvent? {
        guard activity != .shaping || row?.rowRef != chip.rowRef else { return nil }
        activity = .shaping
        since = date
        row = chip
        return FieldActivityEvent(t: date, activity: .shaping, by: .button, blockId: chip.blockId, blockName: chip.blockName,
                                  row: chip.row)
    }

    /// Prep or Rest (Stop row is Prep). Shaping only ever starts on a row (`startRow`).
    public mutating func choose(_ next: FieldActivity, at date: Date) -> FieldActivityEvent? {
        guard next != .shaping, next != activity else { return nil }
        return change(to: next, at: date, by: .button)
    }

    /// The shift's trees as the watch now shows them. A mark while shaping ends the row: prep.
    public mutating func observe(shiftTrees: Int?, at date: Date) -> FieldActivityEvent? {
        defer { trees = shiftTrees }
        guard let before = trees, let now = shiftTrees, now > before, activity == .shaping else { return nil }
        return change(to: .prep, at: date, by: .mark)
    }

    private mutating func change(to next: FieldActivity, at date: Date, by cause: FieldActivityEvent.Cause) -> FieldActivityEvent {
        activity = next
        since = date
        row = nil
        return FieldActivityEvent(t: date, activity: next, by: cause)
    }
}
