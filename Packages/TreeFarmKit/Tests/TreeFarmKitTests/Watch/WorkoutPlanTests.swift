import Foundation
import Testing
@testable import TreeFarmKit

/// What the watch's workout session does, decided only from the phone's confirmed state, the
/// waiting and in-flight taps and the session's own record (docs/watch.md 2.2). Each test is one
/// row of that table or one reconcile rule.
@Suite("Workout plan")
struct WorkoutPlanTests {
    static let zone = "America/Indiana/Indianapolis"
    let cal = FarmCalendar(timeZone: TimeZone(identifier: WorkoutPlanTests.zone)!, weekStart: .monday)
    let block = UUID()
    let user = UUID()
    let epoch = UUID()
    /// The phone's shift.
    let shift = UUID()
    /// The id a watch clock-in minted.
    let minted = UUID()

    func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        cal.date(on: DayKey(year: 2026, month: 10, day: 19), hour: h, minute: m).addingTimeInterval(TimeInterval(s))
    }

    // MARK: States

    func working(_ id: UUID? = nil, start: Date? = nil, phase: LiveSnapshot.Phase = .working, updatedAt: Date? = nil,
                 recordWorkouts: Bool = true, lastClosed: ClosedShift? = nil, applied: [UUID] = []) -> WatchState {
        let start = start ?? at(7, 0)
        let chips = (14...20).map { RowChip(blockId: block, row: $0 - 1, title: "Row \($0)", blockName: "Block 2") }
        let snapshot = LiveSnapshot(phase: phase, timerStart: start, workedSoFar: 0, workedLabel: "worked today",
                                    breakStart: phase == .working ? nil : at(12, 1), breakReason: "", fieldName: "North",
                                    nextRows: Array(chips.prefix(3)), shiftTrees: 38, fieldShaped: 120, fieldTotal: 400,
                                    lastAction: nil, canUndo: false)
        return WatchState(signedIn: true, farmName: "Farm", fieldName: "North", snapshot: snapshot, nextRows: chips,
                          todayWorked: 0, todayTrees: 38, canUndo: false, recordWorkouts: recordWorkouts,
                          updatedAt: updatedAt ?? at(10, 0), epoch: epoch, revision: 9, userId: user, shiftId: id ?? shift,
                          shiftStart: start, lastClosedShift: lastClosed, appliedRequestIds: applied, farmTimeZone: Self.zone)
    }

    func offClock(updatedAt: Date? = nil, lastClosed: ClosedShift? = nil, recordWorkouts: Bool = true,
                  applied: [UUID] = []) -> WatchState {
        WatchState(signedIn: true, farmName: "Farm", fieldName: "North", snapshot: nil, nextRows: [], todayWorked: 0,
                   todayTrees: 0, canUndo: false, recordWorkouts: recordWorkouts, updatedAt: updatedAt ?? at(10, 0),
                   epoch: epoch, revision: 9, userId: user, lastClosedShift: lastClosed, appliedRequestIds: applied,
                   farmTimeZone: Self.zone)
    }

    func closed(_ id: UUID? = nil, start: Date? = nil, end: Date) -> ClosedShift {
        ClosedShift(shiftId: id ?? shift, start: start ?? at(7, 0), end: end, worked: 8 * 3600, trees: 412)
    }

    // MARK: Requests

    func request(_ command: FieldCommand, shift: UUID?, at time: Date) -> WatchRequest {
        WatchRequest(body: .command(command), issuedAt: time, userId: user, shiftId: shift)
    }

    func clockIn(_ id: UUID? = nil, at time: Date) -> WatchRequest {
        request(.clockIn(fieldId: nil), shift: id ?? minted, at: time)
    }

    func clockOut(_ id: UUID? = nil, at time: Date) -> WatchRequest { request(.clockOut, shift: id ?? shift, at: time) }
    func lunch(_ id: UUID? = nil, at time: Date) -> WatchRequest { request(.startBreak(.lunch, reason: ""), shift: id ?? shift, at: time) }
    func backToWork(_ id: UUID? = nil, at time: Date) -> WatchRequest { request(.endBreak, shift: id ?? shift, at: time) }
    func cancel(_ id: UUID, at time: Date) -> WatchRequest { request(.cancelShift(id), shift: id, at: time) }

    func mark(_ row: Int, _ id: UUID? = nil, at time: Date) -> WatchRequest {
        request(.markRow(RowRef(blockId: block, row: row - 1)), shift: id ?? shift, at: time)
    }

    // MARK: Sessions

    func running(_ id: UUID?, since start: Date? = nil, origin: WorkoutLocal.Origin = .phoneLaunch) -> WorkoutLocal {
        WorkoutLocal(phase: .running, shiftId: id, origin: origin, startedAt: start ?? at(7, 0), syncIdentifier: UUID())
    }

    func paused(_ id: UUID?, since start: Date? = nil) -> WorkoutLocal {
        var local = running(id, since: start)
        local.phase = .paused
        return local
    }

    func stopped(_ id: UUID?, at stop: Date, since start: Date? = nil) -> WorkoutLocal {
        var local = running(id, since: start)
        local.phase = .stopped
        local.stoppedAt = stop
        return local
    }

    func plan(_ inputs: WorkoutInputs, _ local: WorkoutLocal = WorkoutLocal(), now: Date) -> [WorkoutStep] {
        WorkoutPlan.reconcile(inputs: inputs, local: local, now: now)
    }

    // MARK: - Rule 1: recording off

    @Test func recordingTurnedOffMidShiftFinishesTheRunningWorkoutNow() {
        let inputs = WorkoutInputs(confirmed: working(recordWorkouts: false))
        #expect(plan(inputs, running(shift), now: at(10, 5)) == [.finish(at: at(10, 5))])
        #expect(plan(inputs, paused(shift), now: at(10, 5)) == [.finish(at: at(10, 5))])
    }

    @Test func recordingTurnedOffFinishesAStoppedWorkoutAtItsStop() {
        let inputs = WorkoutInputs(confirmed: working(recordWorkouts: false), outbox: [clockOut(at: at(16, 30))])
        #expect(plan(inputs, stopped(shift, at: at(16, 30)), now: at(16, 40)) == [.finish(at: at(16, 30))])
    }

    @Test func recordingOffStartsNothing() {
        #expect(plan(WorkoutInputs(confirmed: working(recordWorkouts: false)), now: at(7, 1)) == [])
        let tap = WorkoutInputs(confirmed: offClock(recordWorkouts: false), outbox: [clockIn(at: at(7, 0))])
        #expect(plan(tap, now: at(7, 0)) == [])
    }

    @Test func aStaleRecordingOffStateDoesntEndAPhoneLaunchedWorkout() {
        // The toggle went on and the phone clocked in at once: the watch launched before the context.
        let inputs = WorkoutInputs(confirmed: offClock(updatedAt: at(6, 50), recordWorkouts: false))
        #expect(plan(inputs, running(nil, since: at(7, 0)), now: at(7, 0, 20)) == [])
    }

    // MARK: - Rule 2: stopped, waiting for the clock-out

    @Test func queuedClockOutStopsNowFinishesOnAcknowledgementOrAfter60Minutes() {
        let tap = clockOut(at: at(16, 30))
        let local = stopped(shift, at: at(16, 30))
        let waiting = WorkoutInputs(confirmed: working(), outbox: [tap])
        #expect(plan(waiting, local, now: at(16, 31)) == [])
        #expect(plan(waiting, local, now: at(17, 29, 59)) == [])
        #expect(plan(waiting, local, now: at(17, 30)) == [.finish(at: at(16, 30)), .notifyStuckClockOut])

        let answered = WorkoutInputs(confirmed: offClock(lastClosed: closed(end: at(16, 30))))
        #expect(plan(answered, local, now: at(16, 45)) == [.finish(at: at(16, 30))])
    }

    @Test func aClockOutInFlightStillWaits() {
        let inputs = WorkoutInputs(confirmed: working(), inFlight: [clockOut(at: at(16, 30))])
        #expect(plan(inputs, stopped(shift, at: at(16, 30)), now: at(16, 31)) == [])
    }

    @Test func aClockOutTheStateListsAsAppliedIsAnswered() {
        // The reply was lost, but the phone's next state names the request.
        let tap = clockOut(at: at(16, 30))
        let inputs = WorkoutInputs(confirmed: offClock(applied: [tap.id]), outbox: [tap])
        #expect(plan(inputs, stopped(shift, at: at(16, 30)), now: at(16, 40)) == [.finish(at: at(16, 30))])
    }

    @Test func aRefusedSecondClockOutStillFinishes() {
        // Both devices clocked out: the watch's was refused ("You're not clocked in."), but answered.
        let inputs = WorkoutInputs(confirmed: offClock(lastClosed: closed(end: at(16, 29))))
        #expect(plan(inputs, stopped(shift, at: at(16, 30)), now: at(16, 31)) == [.finish(at: at(16, 30))])
    }

    @Test func aNewClockInFinishesTheStoppedWorkoutFirstThenStartsTheNewOne() {
        let next = UUID()
        let inputs = WorkoutInputs(confirmed: working(), outbox: [clockOut(at: at(11, 0)), clockIn(next, at: at(12, 0))])
        #expect(plan(inputs, stopped(shift, at: at(11, 0)), now: at(12, 0)) ==
                [.finish(at: at(11, 0)), .start(at: at(12, 0), shiftId: next, origin: .watchTap)])
    }

    // MARK: - Rule 3: a pending clock-out stops the session

    @Test func aWatchClockOutStopsAtTheTapTimeBeforeAnyReply() {
        let inputs = WorkoutInputs(confirmed: working(), inFlight: [clockOut(at: at(16, 30))])
        #expect(plan(inputs, running(shift), now: at(16, 30, 1)) == [.stop(at: at(16, 30))])
        #expect(plan(inputs, paused(shift), now: at(16, 30, 1)) == [.stop(at: at(16, 30))])
    }

    @Test func aClockOutForAnotherShiftDoesntStopThisOne() {
        // A clock-out queued yesterday reaches the phone after today's phone clock-in.
        let yesterday = UUID()
        let inputs = WorkoutInputs(confirmed: working(), outbox: [clockOut(yesterday, at: at(7, 0))])
        #expect(plan(inputs, running(shift), now: at(7, 5)) == [])
    }

    @Test func anUntaggedWorkoutStopsForAClockOutOfThePhonesOpenShift() {
        let inputs = WorkoutInputs(confirmed: working(updatedAt: at(6, 59)), outbox: [clockOut(at: at(16, 30))])
        #expect(plan(inputs, running(nil), now: at(16, 30, 1)) == [.stop(at: at(16, 30))])
    }

    @Test func aStopIsNeverBeforeTheWorkoutStarted() {
        let inputs = WorkoutInputs(confirmed: working(), outbox: [clockOut(at: at(7, 0))])
        #expect(plan(inputs, running(shift, since: at(7, 2)), now: at(7, 3)) == [.stop(at: at(7, 2))])
    }

    // MARK: - Rule 4: a pending clock-in

    @Test func aWatchClockInStartsAtOnceTaggedWithTheMintedId() {
        let tap = clockIn(at: at(7, 0))
        #expect(plan(WorkoutInputs(confirmed: offClock(), outbox: [tap]), now: at(7, 0)) ==
                [.start(at: at(7, 0), shiftId: minted, origin: .watchTap)])
        #expect(plan(WorkoutInputs(confirmed: offClock(), inFlight: [tap]), now: at(7, 0, 1)) ==
                [.start(at: at(7, 0), shiftId: minted, origin: .watchTap)])
    }

    @Test func aWatchClockInNeverBackdatesMoreThanFiveMinutes() {
        // The start failed the first time and is tried again much later.
        let inputs = WorkoutInputs(confirmed: offClock(), outbox: [clockIn(at: at(7, 0))])
        #expect(plan(inputs, now: at(7, 30)) == [.start(at: at(7, 25), shiftId: minted, origin: .watchTap)])
    }

    @Test func inFlightClockInPlusStaleStateNoDiscard() {
        // The phone published "off the clock" after the session started, before it got the tap.
        let inputs = WorkoutInputs(confirmed: offClock(updatedAt: at(7, 0, 2)), inFlight: [clockIn(at: at(7, 0))])
        #expect(plan(inputs, running(minted, since: at(7, 0), origin: .watchTap), now: at(7, 0, 3)) == [])
    }

    @Test func aWatchClockInTagsAnUntaggedWorkout() {
        let inputs = WorkoutInputs(confirmed: offClock(updatedAt: at(6, 0)), outbox: [clockIn(at: at(7, 0))])
        #expect(plan(inputs, running(nil, since: at(6, 59)), now: at(7, 0)) == [.tag(shiftId: minted)])
    }

    @Test func aClockInAndALunchBothQueuedStartThenPause() {
        let inputs = WorkoutInputs(confirmed: offClock(), outbox: [clockIn(at: at(7, 0)), lunch(minted, at: at(7, 1))])
        #expect(plan(inputs, now: at(7, 1)) == [.start(at: at(7, 0), shiftId: minted, origin: .watchTap), .pause])
    }

    @Test func aWatchLunchTapPausesAtOnceWhileTheClockInStillWaits() {
        let inputs = WorkoutInputs(confirmed: offClock(), outbox: [clockIn(at: at(7, 0)), lunch(minted, at: at(12, 0))])
        #expect(plan(inputs, running(minted, since: at(7, 0), origin: .watchTap), now: at(12, 0)) == [.pause])
    }

    @Test func undoClockInWhileTheClockInStillWaitsDiscards() {
        let inputs = WorkoutInputs(confirmed: offClock(), outbox: [clockIn(at: at(7, 0)), cancel(minted, at: at(7, 1))])
        #expect(plan(inputs, running(minted, since: at(7, 0), origin: .watchTap), now: at(7, 1)) == [.discard])
    }

    @Test func aCancelledClockInNeverStarts() {
        let inputs = WorkoutInputs(confirmed: offClock(), outbox: [clockIn(at: at(7, 0)), cancel(minted, at: at(7, 1))])
        #expect(plan(inputs, now: at(7, 1)) == [])
    }

    @Test func aClockInWhoseWorkoutAlreadyFinishedDoesntStartAgain() {
        // The clock-out waited 60 minutes and finished; both taps still wait for the phone.
        var local = WorkoutLocal(phase: .ended, shiftId: minted, lastFinishedShiftId: minted)
        local.origin = .watchTap
        let inputs = WorkoutInputs(confirmed: offClock(), outbox: [clockIn(at: at(7, 0)), clockOut(minted, at: at(9, 0))])
        #expect(plan(inputs, local, now: at(10, 1)) == [])
    }

    @Test func aPendingClockInAfterUndoClockInReplacesTheCancelledWorkout() {
        let second = UUID()
        let inputs = WorkoutInputs(confirmed: offClock(), outbox: [cancel(minted, at: at(7, 1)), clockIn(second, at: at(7, 2))])
        #expect(plan(inputs, running(minted, since: at(7, 0), origin: .watchTap), now: at(7, 2)) ==
                [.discard, .start(at: at(7, 2), shiftId: second, origin: .watchTap)])
    }

    @Test func aWatchClockInAfterAPhoneClockOutFinishesTheOldWorkoutFirst() {
        let inputs = WorkoutInputs(confirmed: offClock(lastClosed: closed(end: at(11, 0))), outbox: [clockIn(at: at(12, 0))])
        #expect(plan(inputs, running(shift), now: at(12, 0)) ==
                [.finish(at: at(11, 0)), .start(at: at(12, 0), shiftId: minted, origin: .watchTap)])
    }

    @Test func aWatchClockInTheOpenShiftWillRefuseLeavesTheWorkoutAlone() {
        // The phone already has a shift open; the workout keeps recording it.
        let inputs = WorkoutInputs(confirmed: working(), outbox: [clockIn(at: at(7, 5))])
        #expect(plan(inputs, running(shift), now: at(7, 5)) == [])
    }

    // MARK: - Rule 5: Undo clock-in

    @Test func undoClockInDiscardsAtOnce() {
        let inputs = WorkoutInputs(confirmed: working(minted, start: at(7, 0)), inFlight: [cancel(minted, at: at(7, 1))])
        #expect(plan(inputs, running(minted, since: at(7, 0), origin: .watchTap), now: at(7, 1)) == [.discard])
    }

    // MARK: - Rule 6: the phone says off the clock

    @Test func aPhoneClockOutFinishesAtTheShiftsEnd() {
        let inputs = WorkoutInputs(confirmed: offClock(updatedAt: at(16, 31), lastClosed: closed(end: at(16, 30))))
        #expect(plan(inputs, running(shift), now: at(16, 31)) == [.finish(at: at(16, 30))])
        #expect(plan(inputs, paused(shift), now: at(16, 31)) == [.finish(at: at(16, 30))])
    }

    @Test func theFinishStaysInsideTheWorkout() {
        // The shift's start was edited earlier on the phone; the workout isn't stretched.
        let early = WorkoutInputs(confirmed: offClock(lastClosed: closed(end: at(6, 0))))
        #expect(plan(early, running(shift, since: at(7, 0)), now: at(10, 0)) == [.finish(at: at(7, 0))])
        let late = WorkoutInputs(confirmed: offClock(lastClosed: closed(end: at(11, 0))))
        #expect(plan(late, running(shift, since: at(7, 0)), now: at(10, 0)) == [.finish(at: at(10, 0))])
    }

    @Test func untaggedSessionPlusPhoneClockOutFinishes() {
        let inputs = WorkoutInputs(confirmed: offClock(updatedAt: at(16, 31), lastClosed: closed(end: at(16, 30))))
        #expect(plan(inputs, running(nil, since: at(7, 1)), now: at(16, 32)) == [.finish(at: at(16, 30))])
    }

    @Test func aRefusedClockInDiscards() {
        let inputs = WorkoutInputs(confirmed: offClock(updatedAt: at(6, 0)), refusedClockIns: [minted])
        #expect(plan(inputs, running(minted, since: at(7, 0), origin: .watchTap), now: at(7, 0, 5)) == [.discard])
    }

    @Test func aNewerOffClockStateFinishesNow() {
        // The phone knew about this session and still says off the clock (a cancelled shift
        // whose cancel came from elsewhere): finish now, which discards on its own under 2 minutes.
        let inputs = WorkoutInputs(confirmed: offClock(updatedAt: at(9, 0)))
        #expect(plan(inputs, running(shift, since: at(7, 0)), now: at(9, 1)) == [.finish(at: at(9, 1))])
    }

    @Test func staleOffClockContextRightAfterAPhoneLaunchNoDiscard() {
        let inputs = WorkoutInputs(confirmed: offClock(updatedAt: at(6, 50)))
        #expect(plan(inputs, running(nil, since: at(7, 0)), now: at(7, 0, 10)) == [])
    }

    @Test func signingOutOnThePhoneLeavesTheWorkoutAlone() {
        let inputs = WorkoutInputs(confirmed: .signedOut(epoch: epoch, revision: 10, now: at(9, 0)))
        #expect(plan(inputs, running(shift), now: at(9, 1)) == [])
    }

    // MARK: - Rule 7: the phone says on the clock

    @Test func aPhoneClockInSeenWithinFiveMinutesStartsAtTheShiftStart() {
        let inputs = WorkoutInputs(confirmed: working(start: at(7, 0)))
        #expect(plan(inputs, now: at(7, 4)) == [.start(at: at(7, 0), shiftId: shift, origin: .phoneLaunch)])
        #expect(plan(inputs, now: at(7, 5)) == [.start(at: at(7, 0), shiftId: shift, origin: .phoneLaunch)])
    }

    @Test func aPhoneClockInSeenLateStartsNow() {
        let inputs = WorkoutInputs(confirmed: working(start: at(7, 0)))
        #expect(plan(inputs, now: at(7, 14)) == [.start(at: at(7, 14), shiftId: shift, origin: .phoneLaunch)])
    }

    @Test func aShiftWhoseWorkoutFinishedIsntStartedAgain() {
        let local = WorkoutLocal(phase: .ended, shiftId: shift, lastFinishedShiftId: shift)
        #expect(plan(WorkoutInputs(confirmed: working()), local, now: at(10, 0)) == [])
    }

    @Test func noAutomaticRestartAfterAnotherWorkoutEndedTheSession() {
        let local = WorkoutLocal(phase: .ended, shiftId: shift, stoppedUnexpectedly: true, lastFinishedShiftId: shift)
        #expect(plan(WorkoutInputs(confirmed: working()), local, now: at(10, 0)) == [])
        let neverSaved = WorkoutLocal(phase: .none, shiftId: shift, stoppedUnexpectedly: true)
        #expect(plan(WorkoutInputs(confirmed: working()), neverSaved, now: at(10, 0)) == [])
    }

    @Test func aLaterShiftStartsAfterAnUnexpectedEnd() {
        let earlier = UUID()
        let local = WorkoutLocal(phase: .ended, shiftId: earlier, stoppedUnexpectedly: true, lastFinishedShiftId: earlier)
        #expect(plan(WorkoutInputs(confirmed: working(start: at(13, 0))), local, now: at(13, 1)) ==
                [.start(at: at(13, 0), shiftId: shift, origin: .phoneLaunch)])
    }

    @Test func aWorkoutLostWithTheBatteryRestartsNowAsRecovered() {
        // Recovery found no session; the shift is still on the clock.
        let local = WorkoutLocal(phase: .none, shiftId: shift, origin: .phoneLaunch, startedAt: at(7, 0))
        #expect(plan(WorkoutInputs(confirmed: working()), local, now: at(14, 14)) ==
                [.start(at: at(14, 14), shiftId: shift, origin: .recovered)])
    }

    @Test func alreadyOpenRetagsTheRefusedClockIn() {
        let inputs = WorkoutInputs(confirmed: working(), refusedClockIns: [minted])
        #expect(plan(inputs, running(minted, since: at(7, 5), origin: .watchTap), now: at(7, 6)) == [.tag(shiftId: shift)])
    }

    @Test func anUntaggedWorkoutIsTaggedWhenTheStateArrives() {
        #expect(plan(WorkoutInputs(confirmed: working()), running(nil, since: at(7, 0)), now: at(7, 1)) == [.tag(shiftId: shift)])
    }

    @Test func aPhoneClockOutAndInAgainFinishesThenStarts() {
        let next = UUID()
        let inputs = WorkoutInputs(confirmed: working(next, start: at(12, 30), lastClosed: closed(end: at(11, 0))))
        #expect(plan(inputs, running(shift), now: at(12, 31)) ==
                [.finish(at: at(11, 0)), .start(at: at(12, 30), shiftId: next, origin: .phoneLaunch)])
    }

    @Test func lunchOnThePhonePausesAndBackToWorkResumes() {
        #expect(plan(WorkoutInputs(confirmed: working(phase: .lunch)), running(shift), now: at(12, 2)) == [.pause])
        #expect(plan(WorkoutInputs(confirmed: working(phase: .onBreak)), running(shift), now: at(12, 2)) == [.pause])
        #expect(plan(WorkoutInputs(confirmed: working()), paused(shift), now: at(12, 30)) == [.resume])
        #expect(plan(WorkoutInputs(confirmed: working()), running(shift), now: at(12, 30)) == [])
        #expect(plan(WorkoutInputs(confirmed: working(phase: .lunch)), paused(shift), now: at(12, 30)) == [])
    }

    @Test func watchBreakTapsPauseAndResumeBeforeThePhoneAnswers() {
        let away = WorkoutInputs(confirmed: working(), outbox: [lunch(at: at(12, 0))])
        #expect(plan(away, running(shift), now: at(12, 0)) == [.pause])
        let back = WorkoutInputs(confirmed: working(phase: .lunch), inFlight: [backToWork(at: at(12, 30))])
        #expect(plan(back, paused(shift), now: at(12, 30)) == [.resume])
    }

    @Test func aPhoneClockInStartedOnLunchStartsThenPauses() {
        #expect(plan(WorkoutInputs(confirmed: working(start: at(7, 0), phase: .lunch)), now: at(7, 2)) ==
                [.start(at: at(7, 0), shiftId: shift, origin: .phoneLaunch), .pause])
    }

    @Test func rowMarksChangeNothing() {
        let inputs = WorkoutInputs(confirmed: working(), outbox: [mark(14, at: at(10, 0)), mark(15, at: at(10, 1))])
        #expect(plan(inputs, running(shift), now: at(10, 2)) == [])
    }

    @Test func nothingHappensWithoutAStateOrATap() {
        #expect(plan(WorkoutInputs(), now: at(7, 0)) == [])
        #expect(plan(WorkoutInputs(confirmed: offClock()), now: at(7, 0)) == [])
    }

    @Test func aMistakenClockInThenClockOutWithinTwoMinutesStopsForTheDriverToDiscard() {
        // The driver discards a finished workout shorter than `minimumDuration`; the plan just stops it.
        let inputs = WorkoutInputs(confirmed: working(minted, start: at(7, 0)), outbox: [clockOut(minted, at: at(7, 1))])
        #expect(plan(inputs, running(minted, since: at(7, 0), origin: .watchTap), now: at(7, 1)) == [.stop(at: at(7, 1))])
        #expect(WorkoutPlan.minimumDuration == 120)
    }

    // MARK: - The phone launched the watch app (`handle(_ workoutConfiguration:)`)

    @Test func aPhoneLaunchWithTheShiftInTheStateStartsTagged() {
        let inputs = WorkoutInputs(confirmed: working(start: at(7, 0)))
        #expect(WorkoutPlan.phoneLaunch(inputs: inputs, local: WorkoutLocal(), now: at(7, 0, 8)) ==
                [.start(at: at(7, 0), shiftId: shift, origin: .phoneLaunch)])
        #expect(WorkoutPlan.phoneLaunch(inputs: inputs, local: WorkoutLocal(), now: at(7, 20)) ==
                [.start(at: at(7, 20), shiftId: shift, origin: .phoneLaunch)])
    }

    @Test func aPhoneLaunchBeforeTheStateArrivesStartsUntaggedNow() {
        let stale = WorkoutInputs(confirmed: offClock(updatedAt: at(6, 50)))
        #expect(WorkoutPlan.phoneLaunch(inputs: stale, local: WorkoutLocal(), now: at(7, 0)) ==
                [.start(at: at(7, 0), shiftId: nil, origin: .phoneLaunch)])
        #expect(WorkoutPlan.phoneLaunch(inputs: WorkoutInputs(), local: WorkoutLocal(), now: at(7, 0)) ==
                [.start(at: at(7, 0), shiftId: nil, origin: .phoneLaunch)])
    }

    @Test func aPhoneLaunchWithASessionDoesNothing() {
        let inputs = WorkoutInputs(confirmed: working())
        #expect(WorkoutPlan.phoneLaunch(inputs: inputs, local: running(shift), now: at(7, 1)) == [])
        #expect(WorkoutPlan.phoneLaunch(inputs: inputs, local: stopped(shift, at: at(7, 0)), now: at(7, 1)) == [])
    }

    @Test func aPhoneLaunchForAShiftAlreadyFinishedStartsUntagged() {
        // The state still shows the old shift; the launch is for a new one.
        let local = WorkoutLocal(phase: .ended, shiftId: shift, lastFinishedShiftId: shift)
        #expect(WorkoutPlan.phoneLaunch(inputs: WorkoutInputs(confirmed: working()), local: local, now: at(13, 0)) ==
                [.start(at: at(13, 0), shiftId: nil, origin: .phoneLaunch)])
    }

    // MARK: - Record again

    @Test func recordAgainStartsANewWorkoutForTheSameShiftNow() {
        let local = WorkoutLocal(phase: .ended, shiftId: shift, stoppedUnexpectedly: true, lastFinishedShiftId: shift)
        #expect(WorkoutPlan.recordAgain(inputs: WorkoutInputs(confirmed: working()), local: local, now: at(10, 0)) ==
                [.start(at: at(10, 0), shiftId: shift, origin: .recovered)])
        #expect(WorkoutPlan.recordAgain(inputs: WorkoutInputs(confirmed: working(phase: .lunch)), local: local, now: at(12, 5)) ==
                [.start(at: at(12, 5), shiftId: shift, origin: .recovered), .pause])
    }

    @Test func recordAgainDoesNothingOffTheClockOrWithASession() {
        let local = WorkoutLocal(phase: .ended, shiftId: shift, stoppedUnexpectedly: true)
        #expect(WorkoutPlan.recordAgain(inputs: WorkoutInputs(confirmed: offClock()), local: local, now: at(10, 0)) == [])
        #expect(WorkoutPlan.recordAgain(inputs: WorkoutInputs(confirmed: working()), local: running(shift), now: at(10, 0)) == [])
        #expect(WorkoutPlan.recordAgain(inputs: WorkoutInputs(confirmed: working(recordWorkouts: false)), local: local,
                                        now: at(10, 0)) == [])
    }

    @Test func recordAgainOffersNothingWhileTheShiftsClockOutWaits() {
        // A stopped workout ended from outside, or a watch clock-out after "Recording stopped":
        // the person is clocking out, so there's nothing to record again.
        let local = WorkoutLocal(phase: .ended, shiftId: shift, stoppedUnexpectedly: true, lastFinishedShiftId: shift)
        let queued = WorkoutInputs(confirmed: working(), outbox: [clockOut(at: at(16, 30))])
        #expect(WorkoutPlan.recordAgain(inputs: queued, local: local, now: at(16, 40)) == [])
        let sending = WorkoutInputs(confirmed: working(), inFlight: [clockOut(at: at(16, 30))])
        #expect(WorkoutPlan.recordAgain(inputs: sending, local: local, now: at(16, 40)) == [])
        // A clock-out for another shift doesn't stand in the way.
        let other = WorkoutInputs(confirmed: working(), outbox: [clockOut(UUID(), at: at(9, 0))])
        #expect(WorkoutPlan.recordAgain(inputs: other, local: local, now: at(10, 0)) ==
                [.start(at: at(10, 0), shiftId: shift, origin: .recovered)])
    }

    // MARK: - A watch clock-out still waiting

    @Test func aClockOutWaitsWhileQueuedOrInFlightAndNotListedAsApplied() {
        let queued = clockOut(at: at(16, 30))
        let other = clockOut(UUID(), at: at(9, 0))
        #expect(WorkoutPlan.waitingClockOuts(WorkoutInputs(confirmed: working(), outbox: [queued])) == [queued])
        #expect(WorkoutPlan.waitingClockOuts(WorkoutInputs(confirmed: working(), inFlight: [queued])) == [queued])
        #expect(WorkoutPlan.waitingClockOuts(WorkoutInputs(confirmed: offClock(applied: [queued.id]), outbox: [queued])).isEmpty)
        #expect(WorkoutPlan.waitingClockOuts(WorkoutInputs(confirmed: working(), outbox: [lunch(at: at(12, 0))])).isEmpty)
        #expect(WorkoutPlan.waitingClockOuts(WorkoutInputs(confirmed: working(), outbox: [queued, other])) == [other, queued])
        #expect(WorkoutPlan.waitingClockOut(for: shift, WorkoutInputs(confirmed: working(), outbox: [queued, other])) == queued)
        #expect(WorkoutPlan.waitingClockOut(for: nil, WorkoutInputs(confirmed: working(), outbox: [queued])) == nil)
    }

    // MARK: - The five-minute rule

    @Test func startTimeBackdatesAtMostFiveMinutesAndNeverIntoTheFuture() {
        #expect(WorkoutPlan.startTime(shiftStart: at(7, 0), now: at(7, 5)) == at(7, 0))
        #expect(WorkoutPlan.startTime(shiftStart: at(7, 0), now: at(7, 5, 1)) == at(7, 5, 1))
        #expect(WorkoutPlan.startTime(shiftStart: at(7, 10), now: at(7, 5)) == at(7, 5))
        #expect(WorkoutPlan.startTime(shiftStart: nil, now: at(7, 5)) == at(7, 5))
        #expect(WorkoutPlan.backdateLimit == 300 && WorkoutPlan.stoppedLimit == 3600)
    }

    // MARK: - The session's record

    @Test func aStartResetsTheRecord() {
        let sync = UUID()
        let before = WorkoutLocal(phase: .ended, shiftId: shift, stoppedAt: at(9, 0), stoppedUnexpectedly: true, lastFinishedShiftId: shift)
        let local = before.started(at: at(10, 0), shiftId: minted, origin: .watchTap, syncIdentifier: sync)
        #expect(local == WorkoutLocal(phase: .running, shiftId: minted, origin: .watchTap, startedAt: at(10, 0),
                                      syncIdentifier: sync, lastFinishedShiftId: shift))
    }

    @Test func stoppingAndEndingKeepWhatRecoveryNeeds() {
        let started = WorkoutLocal().started(at: at(7, 0), shiftId: shift, origin: .phoneLaunch, syncIdentifier: UUID())
        let stopped = started.stopped(at: at(16, 30))
        #expect(stopped.phase == .stopped && stopped.stoppedAt == at(16, 30) && stopped.hasSession)
        let ended = stopped.ended()
        #expect(ended.phase == .ended && ended.lastFinishedShiftId == shift && !ended.hasSession)
        #expect(ended.shiftId == shift && ended.syncIdentifier == started.syncIdentifier)
        #expect(started.tagged(minted).shiftId == minted)
        #expect(started.with(phase: .paused).phase == .paused)
    }

    @Test func anUnexpectedEndIsRemembered() {
        let started = WorkoutLocal().started(at: at(7, 0), shiftId: shift, origin: .phoneLaunch, syncIdentifier: UUID())
        let ended = started.endedUnexpectedly()
        #expect(ended.stoppedUnexpectedly && ended.phase == .ended && ended.shiftId == shift)
        #expect(ended.lastFinishedShiftId == shift)
    }

    @Test func aSessionRecoveryCouldntFindIsForgottenButItsShiftKept() {
        let sync = UUID()
        let started = WorkoutLocal().started(at: at(7, 0), shiftId: shift, origin: .phoneLaunch, syncIdentifier: sync)
        let lost = started.lost()
        #expect(lost.phase == .none && lost.shiftId == shift && !lost.stoppedUnexpectedly && lost.lastFinishedShiftId == nil)
        // Recovery runs twice at a crash relaunch: the second call may still find the session.
        #expect(lost.startedAt == at(7, 0) && lost.syncIdentifier == sync && lost.origin == .phoneLaunch)
        // A session that had already ended stays ended.
        #expect(started.ended().lost() == started.ended())
    }

    @Test func aLostStoppedRecordThatIsLaterRecoveredStillFinishesAtItsStoppedAt() {
        // applicationDidFinishLaunching's recovery found nothing; handleActiveWorkoutRecovery's did.
        let lost = stopped(shift, at: at(16, 30)).lost()
        #expect(lost.phase == .none && lost.stoppedAt == at(16, 30))
        let waiting = WorkoutInputs(confirmed: working(), outbox: [clockOut(at: at(16, 30))])
        // Between the two calls, nothing starts over the orphaned session while its clock-out waits.
        #expect(plan(waiting, lost, now: at(16, 41)) == [])

        let recovered = lost.with(phase: .stopped)
        #expect(plan(waiting, recovered, now: at(17, 29)) == [])
        #expect(plan(waiting, recovered, now: at(17, 30)) == [.finish(at: at(16, 30)), .notifyStuckClockOut])
        let answered = WorkoutInputs(confirmed: offClock(lastClosed: closed(end: at(16, 30))))
        #expect(plan(answered, recovered, now: at(16, 50)) == [.finish(at: at(16, 30))])
    }

    @Test func theRecordSurvivesARoundTrip() throws {
        let local = WorkoutLocal().started(at: at(7, 0), shiftId: shift, origin: .actionButton, syncIdentifier: UUID()).stopped(at: at(9, 0))
        let data = try JSONCoding.encoder().encode(local)
        #expect(try JSONCoding.decoder().decode(WorkoutLocal.self, from: data) == local)
    }
}
