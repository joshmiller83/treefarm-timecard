import Foundation

/// Why a clock action can't happen. `message` is the plain sentence; the app adds voice hints itself.
public enum ClockError: Error, Equatable, Sendable {
    case notClockedIn
    /// The person's shift that's already open.
    case alreadyClockedIn(Shift)
    /// The break that's already running.
    case alreadyOnBreak(Break)
    case notOnBreak

    public var message: String {
        switch self {
        case .notClockedIn: "You’re not clocked in."
        case .alreadyClockedIn: "You’re already clocked in."
        case .alreadyOnBreak(let b): b.kind == .lunch ? "You’re already on lunch." : "You’re already on a break."
        case .notOnBreak: "You’re not on a break."
        }
    }
}

/// Clock in, breaks and clock out (ports of the artifact's clockIn, startBreak, endBreak and clockOut).
/// Each one returns the changed shift with `updatedAt = now`; saving and syncing it is the caller's job.
/// Note: inside code that also imports Swift's `Clock` protocol, write `TreeFarmKit.Clock` if the name is ambiguous.
public enum Clock {
    /// The live shift still on the clock (the latest one, should there ever be two).
    public static func openShift(in shifts: [Shift]) -> Shift? {
        Hours.latestOpen(shifts)
    }

    /// The person's open shift, when `shifts` holds other people's too (an admin's device does).
    public static func openShift(in shifts: [Shift], userId: UUID) -> Shift? {
        Hours.latestOpen(shifts.filter { $0.userId == userId })
    }

    /// A new open shift starting now. Refused when the person already has one open.
    public static func clockIn(userId: UUID, farmId: UUID, rateCents: Int, at now: Date, shifts: [Shift]) throws(ClockError) -> Shift {
        if let open = openShift(in: shifts, userId: userId) { throw .alreadyClockedIn(open) }
        return Shift(userId: userId, farmId: farmId, start: now, rateCents: rateCents, updatedAt: now)
    }

    /// Starts lunch or another break now. The reason is trimmed and clamped to `Limits.reason`.
    public static func startBreak(_ kind: BreakKind, reason: String, at now: Date, in shift: Shift) throws(ClockError) -> Shift {
        guard shift.isLive && shift.isOpen else { throw .notClockedIn }
        if let b = shift.openBreak { throw .alreadyOnBreak(b) }
        var s = shift
        s.breaks.append(Break(kind: kind, start: now, reason: Limits.clampReason(reason)))
        s.updatedAt = RecordMetadata.stamp(now, after: shift.updatedAt)
        return s
    }

    /// Ends the running break now ("Back to work").
    public static func endBreak(at now: Date, in shift: Shift) throws(ClockError) -> Shift {
        guard shift.isLive && shift.isOpen else { throw .notClockedIn }
        guard shift.openBreak != nil else { throw .notOnBreak }
        var s = shift
        // A break ended the moment it began leaves nothing behind (ShiftRules refuses zero-length breaks).
        if s.breaks[s.breaks.count - 1].start >= now {
            s.breaks.removeLast()
        } else {
            s.breaks[s.breaks.count - 1].end = now
        }
        s.updatedAt = RecordMetadata.stamp(now, after: shift.updatedAt)
        return s
    }

    /// Ends the shift now, closing a running break at the same instant.
    public static func clockOut(at now: Date, shift: Shift) throws(ClockError) -> Shift {
        guard shift.isLive && shift.isOpen else { throw .notClockedIn }
        var s = shift
        if s.openBreak != nil {
            if s.breaks[s.breaks.count - 1].start >= now { s.breaks.removeLast() } else { s.breaks[s.breaks.count - 1].end = now }
        }
        s.end = now
        s.updatedAt = RecordMetadata.stamp(now, after: shift.updatedAt)
        return s
    }

    /// One line per break, as on the log and the report: "Lunch 30 min", "Break 12 min (Fuel run)",
    /// and "… so far" for a break still running on an open shift.
    public static func breakLines(_ shift: Shift, now: Date) -> [String] {
        shift.breaks.map { b in
            b.kind.label + " " + Fmt.minutesText(b.duration(shiftEnd: shift.end, now: now))
                + (b.reason.isEmpty ? "" : " (\(b.reason))")
                + (b.isOpen && shift.isOpen ? " so far" : "")
        }
    }
}
