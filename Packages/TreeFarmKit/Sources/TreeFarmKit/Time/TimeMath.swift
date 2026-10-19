import Foundation

// Worked time is the shift's length minus its breaks. An open shift runs to `now`;
// an open break runs to the shift's end, or to `now` while the shift is still open.
// Times are real elapsed seconds, so a shift across a DST change counts what was worked.

extension Break {
    /// How long this break ran, clamped to the shift's end (or `now` while the shift is open).
    public func duration(shiftEnd: Date?, now: Date) -> TimeInterval {
        let limit = shiftEnd ?? now
        return max(0, min(end ?? limit, limit).timeIntervalSince(start))
    }
}

extension Shift {
    /// All break time inside this shift.
    public func breakTime(at now: Date) -> TimeInterval {
        breaks.reduce(0) { total, b in
            var inside = b
            inside.start = max(b.start, start)
            return total + inside.duration(shiftEnd: end, now: now)
        }
    }

    /// Time on the clock minus breaks. Never negative.
    public func workedTime(at now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start) - breakTime(at: now))
    }
}
