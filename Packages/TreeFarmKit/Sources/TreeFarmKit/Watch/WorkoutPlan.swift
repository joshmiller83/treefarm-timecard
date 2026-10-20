import Foundation

/// What the watch's workout session should do, decided purely from the phone's confirmed state,
/// the waiting and in-flight taps and the session's own record (docs/watch.md 2.2). `ShiftWorkout`
/// never decides on its own: it does exactly the steps returned here, in order.
///
/// The rules are checked in order and the first that matches decides:
///
/// 1. Recording off: finish any session; start none.
/// 2. Stopped at a watch clock-out: finish once the clock-out is answered, or after an hour.
/// 3. A pending clock-out for this session: stop now, at the tap time.
/// 4. A pending watch clock-in: start at once under the minted id (or tag an untagged session).
/// 5. A pending Undo clock-in for this session: discard.
/// 6. The phone says off the clock: finish at the shift's end, discard a refused clock-in.
/// 7. The phone says on the clock: start (at most 5 minutes back), tag, retag, or swap.
///
/// After the session is settled, its pause matches the shift: lunch and breaks pause it, back to
/// work resumes it. That reads the waiting taps too, so a watch tap pauses at once.
///
/// "Pending" means waiting in the outbox or in flight, and not yet listed as applied by the phone.
public enum WorkoutPlan {
    /// A workout never starts more than this before now (a phone clock-in seen late starts now):
    /// an Other workout would invent brisk-walk calories for time the watch never measured.
    public static let backdateLimit: TimeInterval = 5 * 60
    /// A finished workout shorter than this is discarded, not saved.
    public static let minimumDuration: TimeInterval = 2 * 60
    /// How long a stopped session waits for its clock-out to be answered.
    public static let stoppedLimit: TimeInterval = 60 * 60

    public static func reconcile(inputs: WorkoutInputs, local: WorkoutLocal, now: Date) -> [WorkoutStep] {
        let plan = Reconciler(inputs: inputs, local: local, now: now)
        return plan.steps()
    }

    /// `handle(_ workoutConfiguration:)`: the phone clocked in and launched the watch app. With the
    /// shift already in the state, start tagged with it (at most 5 minutes back); before the state
    /// arrives, start untagged at now and let reconcile tag it. Never over an existing session.
    public static func phoneLaunch(inputs: WorkoutInputs, local: WorkoutLocal, now: Date) -> [WorkoutStep] {
        guard !local.hasSession else { return [] }
        let plan = Reconciler(inputs: inputs, local: local, now: now)
        if let state = inputs.confirmed, state.signedIn, state.isClockedIn, let shift = state.shiftId,
           shift != local.lastFinishedShiftId {
            let start = startTime(shiftStart: state.shiftStart, now: now)
            return [.start(at: start, shiftId: shift, origin: .phoneLaunch)] + plan.matchPhase(running: true, shift: shift)
        }
        return [.start(at: now, shiftId: nil, origin: .phoneLaunch)]
    }

    /// The "Record again" button after a session ended from outside the app: a new session for
    /// the shift still on the clock, from now. Nothing while that shift's watch clock-out waits:
    /// the person already clocked out, the phone just hasn't heard yet.
    public static func recordAgain(inputs: WorkoutInputs, local: WorkoutLocal, now: Date) -> [WorkoutStep] {
        guard !local.hasSession, let state = inputs.confirmed, state.signedIn, state.recordWorkouts,
              state.isClockedIn, let shift = state.shiftId ?? local.shiftId,
              waitingClockOut(for: shift, inputs) == nil, waitingClockOut(for: local.shiftId, inputs) == nil else { return [] }
        let plan = Reconciler(inputs: inputs, local: local, now: now)
        return [.start(at: now, shiftId: shift, origin: .recovered)] + plan.matchPhase(running: true, shift: shift)
    }

    /// The watch clock-outs still waiting for the phone: in the outbox or in flight and not yet
    /// listed as applied, oldest first. The stuck clock-out reminder stands while any waits.
    public static func waitingClockOuts(_ inputs: WorkoutInputs) -> [WatchRequest] {
        let applied = Set(inputs.confirmed?.appliedRequestIds ?? [])
        return inputs.pending.filter { $0.command == .clockOut && !applied.contains($0.id) }
    }

    /// The watch clock-out still waiting for this shift, if any.
    public static func waitingClockOut(for shiftId: UUID?, _ inputs: WorkoutInputs) -> WatchRequest? {
        guard let shiftId else { return nil }
        return waitingClockOuts(inputs).first { $0.shiftId == shiftId }
    }

    /// The five-minute rule: a shift that started at most `backdateLimit` ago is recorded from its
    /// start, a later one from now. Never in the future.
    public static func startTime(shiftStart: Date?, now: Date) -> Date {
        guard let shiftStart, shiftStart <= now, now.timeIntervalSince(shiftStart) <= backdateLimit else { return now }
        return shiftStart
    }
}

// MARK: - The rules

private struct Reconciler {
    let inputs: WorkoutInputs
    let local: WorkoutLocal
    let now: Date
    let state: WatchState?
    /// Waiting or in flight, oldest first, without the ones the phone lists as applied.
    let pending: [WatchRequest]

    init(inputs: WorkoutInputs, local: WorkoutLocal, now: Date) {
        self.inputs = inputs
        self.local = local
        self.now = now
        self.state = inputs.confirmed
        let applied = Set(inputs.confirmed?.appliedRequestIds ?? [])
        self.pending = inputs.pending.filter { !applied.contains($0.id) }
    }

    func steps() -> [WorkoutStep] {
        // 1. Recording off: finish whatever runs, start nothing. A phone-launched session newer
        //    than the state was started by a phone that had recording on; the state is stale.
        if let state, !state.recordWorkouts, !isNewerThan(state) {
            return local.hasSession ? [.finish(at: clamped(local.stoppedAt ?? now))] : []
        }

        // 2. Stopped at a watch clock-out, waiting for the phone to answer it.
        if local.phase == .stopped {
            let stoppedAt = local.stoppedAt ?? now
            if let next = liveClockIn(), next.shiftId != local.shiftId {
                return [.finish(at: stoppedAt)] + start(for: next)
            }
            guard clockOut() != nil else { return [.finish(at: stoppedAt)] }
            if now.timeIntervalSince(stoppedAt) >= WorkoutPlan.stoppedLimit {
                return [.finish(at: stoppedAt), .notifyStuckClockOut]
            }
            return []
        }

        // 3. A pending clock-out for this session: stop now, at the tap time, before any reply.
        if local.hasSession, let tap = clockOut() {
            return [.stop(at: clamped(tap.issuedAt))]
        }

        // 4. A pending watch clock-in. It always prevents a discard.
        if let tap = liveClockIn() {
            guard local.hasSession else { return start(for: tap) }
            guard let tag = local.shiftId else {
                return (tap.shiftId.map { [.tag(shiftId: $0)] } ?? []) + matchPhase(running: isRunning, shift: tap.shiftId)
            }
            if tag != tap.shiftId {
                if isCancelled(tag) { return [.discard] + start(for: tap) }
                if let closed = closedShift(tag) { return [.finish(at: clamped(closed.end))] + start(for: tap) }
            }
            return matchPhase(running: isRunning, shift: tag)
        }

        // 5. Undo clock-in for this session.
        if local.hasSession, let tag = local.shiftId, isCancelled(tag) {
            return [.discard]
        }

        guard let state, state.signedIn else { return [] }
        return state.isClockedIn ? onTheClock(state) : offTheClock(state)
    }

    /// 6. The phone says off the clock.
    private func offTheClock(_ state: WatchState) -> [WorkoutStep] {
        guard local.hasSession else { return [] }
        if let closed = state.lastClosedShift {
            if closed.shiftId == local.shiftId { return [.finish(at: clamped(closed.end))] }
            if local.shiftId == nil, let started = local.startedAt, closed.end >= started, closed.end <= now {
                return [.finish(at: closed.end)]
            }
        }
        if let tag = local.shiftId, inputs.refusedClockIns.contains(tag) { return [.discard] }
        // The phone knew about this session and still says off the clock. Under two minutes the
        // finish discards on its own. An older state (a context right after a phone launch) waits.
        if isOlderThanTheSession(state) { return [] }
        return [.finish(at: now)]
    }

    /// 7. The phone says on the clock with shift S.
    private func onTheClock(_ state: WatchState) -> [WorkoutStep] {
        guard let shift = state.shiftId else { return [] }
        let begin = WorkoutPlan.startTime(shiftStart: state.shiftStart, now: now)

        guard local.hasSession else {
            let blocked = shift == local.lastFinishedShiftId
                || (local.stoppedUnexpectedly && (local.shiftId == nil || local.shiftId == shift))
                || isCancelled(shift) || pending.contains { $0.command == .clockOut && $0.shiftId == shift }
            guard !blocked else { return [] }
            let origin: WorkoutLocal.Origin = local.shiftId == shift ? .recovered : .phoneLaunch
            return [.start(at: begin, shiftId: shift, origin: origin)] + matchPhase(running: true, shift: shift)
        }

        guard let tag = local.shiftId, tag != shift else {
            // Untagged (a phone launch before the state): this is its shift.
            let retag: [WorkoutStep] = local.shiftId == nil ? [.tag(shiftId: shift)] : []
            return retag + matchPhase(running: isRunning, shift: shift)
        }
        // The phone clocked out and in again: finish the old one at its end, start the new one.
        if let closed = state.lastClosedShift, closed.shiftId == tag {
            return [.finish(at: clamped(closed.end)), .start(at: begin, shiftId: shift, origin: .phoneLaunch)]
                + matchPhase(running: true, shift: shift)
        }
        // A watch clock-in the phone refused because this shift was already open (or one whose
        // refusal never reached the watch): the session records the open shift.
        return [.tag(shiftId: shift)] + matchPhase(running: isRunning, shift: shift)
    }

    // MARK: Steps

    /// A watch clock-in starts at its tap time (at most 5 minutes back), tagged with the minted id.
    private func start(for tap: WatchRequest) -> [WorkoutStep] {
        let begin = min(max(tap.issuedAt, now.addingTimeInterval(-WorkoutPlan.backdateLimit)), now)
        return [.start(at: begin, shiftId: tap.shiftId, origin: .watchTap)] + matchPhase(running: true, shift: tap.shiftId)
    }

    /// Lunch and breaks pause the workout; back to work resumes it. Reads the state the watch
    /// shows (with its waiting taps), so a watch tap pauses at once and a phone change when it arrives.
    func matchPhase(running: Bool, shift: UUID?) -> [WorkoutStep] {
        guard let predicted = WatchOptimism.displayed(confirmed: state, pending: pending),
              let snapshot = predicted.snapshot, shift == nil || predicted.shiftId == shift else { return [] }
        let onBreak = snapshot.phase != .working
        if running && onBreak { return [.pause] }
        if !running && !onBreak { return [.resume] }
        return []
    }

    // MARK: Reading the inputs

    private var isRunning: Bool { local.phase == .running }

    /// The newest waiting clock-in that still stands: not taken back, not already clocked out or
    /// finished, not refused.
    private func liveClockIn() -> WatchRequest? {
        pending.last { tap in
            guard case .clockIn? = tap.command else { return false }
            guard let minted = tap.shiftId else { return true }
            return minted != local.lastFinishedShiftId && !inputs.refusedClockIns.contains(minted) && !isCancelled(minted)
                && !pending.contains { $0.command == .clockOut && $0.shiftId == minted }
        }
    }

    /// A waiting clock-out for the shift this session records.
    private func clockOut() -> WatchRequest? {
        let shifts = sessionShifts
        return pending.first { $0.command == .clockOut && $0.shiftId.map(shifts.contains) == true }
    }

    /// The shifts this session stands for: its tag, and the phone's open shift when the session is
    /// untagged or its tag is a watch clock-in the phone refused (or will refuse, a shift being open).
    private var sessionShifts: Set<UUID> {
        var shifts = Set([local.shiftId].compactMap { $0 })
        guard let state, state.isClockedIn, let open = state.shiftId else { return shifts }
        let waiting = Set(pending.filter { if case .clockIn? = $0.command { true } else { false } }.compactMap(\.shiftId))
        if let tag = local.shiftId {
            if inputs.refusedClockIns.contains(tag) || waiting.contains(tag) { shifts.insert(open) }
        } else {
            shifts.insert(open)
        }
        return shifts
    }

    private func isCancelled(_ shift: UUID) -> Bool {
        pending.contains { $0.command == .cancelShift(shift) }
    }

    /// The phone's state shows this shift closed.
    private func closedShift(_ shift: UUID) -> ClosedShift? {
        guard let closed = state?.lastClosedShift, closed.shiftId == shift, state?.shiftId != shift else { return nil }
        return closed
    }

    /// A phone-launched session started after this state was made: the state can't know about it.
    private func isNewerThan(_ state: WatchState) -> Bool {
        guard local.hasSession, local.origin == .phoneLaunch else { return false }
        return isOlderThanTheSession(state)
    }

    private func isOlderThanTheSession(_ state: WatchState) -> Bool {
        guard let started = local.startedAt else { return false }
        return state.updatedAt <= started
    }

    /// A finish or stop stays inside the session: no earlier than its start, no later than now.
    private func clamped(_ date: Date) -> Date {
        min(max(date, local.startedAt ?? date), now)
    }
}

// MARK: - The session's record

extension WorkoutLocal {
    /// A new session: running from `date`, with a new sync identifier. An unexpected end is cleared.
    public func started(at date: Date, shiftId: UUID?, origin: Origin, syncIdentifier: UUID) -> WorkoutLocal {
        WorkoutLocal(phase: .running, shiftId: shiftId, origin: origin, startedAt: date, stoppedAt: nil,
                     syncIdentifier: syncIdentifier, stoppedUnexpectedly: false, lastFinishedShiftId: lastFinishedShiftId)
    }

    public func tagged(_ shiftId: UUID) -> WorkoutLocal {
        var local = self
        local.shiftId = shiftId
        return local
    }

    public func with(phase: Phase) -> WorkoutLocal {
        var local = self
        local.phase = phase
        return local
    }

    /// Stopped at a watch clock-out; still a session until it finishes.
    public func stopped(at date: Date) -> WorkoutLocal {
        var local = self
        local.phase = .stopped
        local.stoppedAt = date
        return local
    }

    /// Finished or discarded: its shift never starts again by itself.
    public func ended() -> WorkoutLocal {
        var local = self
        local.phase = .ended
        local.lastFinishedShiftId = shiftId ?? lastFinishedShiftId
        return local
    }

    /// Ended from outside the app (another workout, an error): the shift stays on the clock and
    /// nothing restarts until "Record again".
    public func endedUnexpectedly() -> WorkoutLocal {
        var local = ended()
        local.stoppedUnexpectedly = true
        return local
    }

    /// Recovery found no session to reattach (a crash or a dead battery): forget it but keep its
    /// shift, so the next start for that shift counts as recovered. Everything else stays: at a
    /// crash relaunch recovery runs twice (at launch and from `handleActiveWorkoutRecovery()`),
    /// and when the second call finds the session, a stopped one still needs its `stoppedAt`.
    /// A new start resets the record anyway.
    public func lost() -> WorkoutLocal {
        guard hasSession else { return self }
        return with(phase: .none)
    }
}
