import Foundation
import Testing
import TreeFarmKit
@testable import TimeCardWatch

/// The watch's workout session (docs/watch.md 2): one serial input queue, recovery first, and
/// every decision from `WorkoutPlan`. Run against `FakeWorkoutDriver`.
@MainActor
@Suite("Shift workout")
struct ShiftWorkoutTests {
    static let zone = "America/Indiana/Indianapolis"
    let cal = FarmCalendar(timeZone: TimeZone(identifier: ShiftWorkoutTests.zone)!, weekStart: .monday)
    let block = UUID()
    let user = UUID()
    let shift = UUID()
    let minted = UUID()
    let directory = FileManager.default.temporaryDirectory.appending(path: "ShiftWorkoutTests-\(UUID().uuidString)")

    let driver = FakeWorkoutDriver()
    let notifier = FakeShiftNotifier()
    let clock: TestClock
    let recorder = Recorder()

    @MainActor final class Recorder {
        var notices: [String] = []
        var haptics: [WatchHapticEvent] = []
        var foreground = true
        var battery: Double = 0.9
    }

    init() {
        clock = TestClock(Self.calendar.date(on: DayKey(year: 2026, month: 10, day: 19), hour: 7, minute: 0))
    }

    static var calendar: FarmCalendar { FarmCalendar(timeZone: TimeZone(identifier: zone)!, weekStart: .monday) }

    func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        cal.date(on: DayKey(year: 2026, month: 10, day: 19), hour: h, minute: m).addingTimeInterval(TimeInterval(s))
    }

    func make(driver: FakeWorkoutDriver? = nil, sleeper: ManualSleeper? = nil) -> ShiftWorkout {
        let clock = clock, recorder = recorder
        var hooks = ShiftWorkout.Hooks()
        hooks.now = { clock.now }
        hooks.isForeground = { recorder.foreground }
        hooks.battery = { recorder.battery }
        hooks.notice = { recorder.notices.append($0) }
        hooks.haptic = { recorder.haptics.append($0) }
        if let sleeper { hooks.sleep = sleeper.sleep }
        return ShiftWorkout(driver: driver ?? self.driver, notifier: notifier, store: WorkoutStore(directory: directory), hooks: hooks)
    }

    // MARK: States and taps

    func working(_ id: UUID? = nil, start: Date? = nil, phase: LiveSnapshot.Phase = .working, updatedAt: Date? = nil,
                 recordWorkouts: Bool = true) -> WatchState {
        let start = start ?? at(7, 0)
        let snapshot = LiveSnapshot(phase: phase, timerStart: start, workedSoFar: 0, workedLabel: "worked today",
                                    breakStart: phase == .working ? nil : at(12, 0), breakReason: "", fieldName: "North",
                                    nextRows: [], shiftTrees: 0, fieldShaped: 0, fieldTotal: 400, lastAction: nil, canUndo: false)
        return WatchState(signedIn: true, farmName: "Farm", fieldName: "North", snapshot: snapshot, nextRows: [], todayWorked: 0,
                          todayTrees: 0, canUndo: false, recordWorkouts: recordWorkouts, updatedAt: updatedAt ?? clock.now,
                          userId: user, shiftId: id ?? shift, shiftStart: start, farmTimeZone: Self.zone)
    }

    func offClock(closed: ClosedShift? = nil, recordWorkouts: Bool = true, updatedAt: Date? = nil) -> WatchState {
        WatchState(signedIn: true, farmName: "Farm", fieldName: "North", snapshot: nil, nextRows: [], todayWorked: 0,
                   todayTrees: 0, canUndo: false, recordWorkouts: recordWorkouts, updatedAt: updatedAt ?? clock.now,
                   userId: user, lastClosedShift: closed, farmTimeZone: Self.zone)
    }

    func closed(_ id: UUID, start: Date, end: Date) -> ClosedShift {
        ClosedShift(shiftId: id, start: start, end: end, worked: end.timeIntervalSince(start), trees: 412)
    }

    func tap(_ command: FieldCommand, shift: UUID?, at time: Date) -> WatchRequest {
        WatchRequest(body: .command(command), issuedAt: time, userId: user, shiftId: shift)
    }

    func clockIn(_ id: UUID, at time: Date) -> WatchRequest { tap(.clockIn(fieldId: nil), shift: id, at: time) }

    /// Waits for something that happens on another task (a driver event).
    func until(_ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let end = clock.now + .seconds(3)
        while !condition() && clock.now < end { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: - The shift's life

    @Test func startPauseResumeStopAndFinishFollowTheShiftWithTheirTimes() async {
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: offClock(), outbox: [clockIn(minted, at: at(7, 0))]))
        await workout.settled()
        #expect(driver.calls == [.recover, .start(at(7, 0), minted, .watchTap)])
        #expect(workout.live.recording == .recording)

        clock.now = at(12, 0)
        workout.reconcile(WorkoutInputs(confirmed: working(minted), outbox: [tap(.startBreak(.lunch, reason: ""), shift: minted, at: at(12, 0))]))
        await workout.settled()
        #expect(driver.calls.last == .pause)
        #expect(workout.live.recording == .paused)

        clock.now = at(12, 30)
        workout.reconcile(WorkoutInputs(confirmed: working(minted, phase: .lunch), inFlight: [tap(.endBreak, shift: minted, at: at(12, 30))]))
        await workout.settled()
        #expect(driver.calls.last == .resume)

        clock.now = at(16, 30, 1)
        workout.reconcile(WorkoutInputs(confirmed: working(minted), outbox: [tap(.clockOut, shift: minted, at: at(16, 30))]))
        await workout.settled()
        #expect(driver.calls.last == .stop(at(16, 30)))
        #expect(workout.live.recording == .waitingForClockOut && workout.live.waitingClockOut)

        clock.now = at(16, 32)
        workout.reconcile(WorkoutInputs(confirmed: offClock(closed: closed(minted, start: at(7, 0), end: at(16, 30)))))
        await workout.settled()
        #expect(driver.calls == [.recover, .start(at(7, 0), minted, .watchTap), .pause, .resume, .stop(at(16, 30)),
                                 .finish(at(16, 30), Self.zone)])
        #expect(workout.live.recording == .idle && !workout.live.waitingClockOut)
        #expect(workout.live.lastSummary?.shiftId == minted)
        #expect(workout.live.lastSummary?.avgHeartRate == 104)
    }

    @Test func aPhoneClockOutFinishesAtTheShiftsEnd() async {
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        #expect(driver.calls.last == .start(at(7, 0), shift, .phoneLaunch))

        clock.now = at(15, 1)
        workout.reconcile(WorkoutInputs(confirmed: offClock(closed: closed(shift, start: at(7, 0), end: at(15, 0)))))
        await workout.settled()
        #expect(driver.calls.last == .finish(at(15, 0), Self.zone))
    }

    // MARK: - One serial queue, recovery first

    @Test func recoveryRunsBeforeAnyOtherInput() async {
        let workout = make()
        workout.handleLaunch()
        workout.reconcile(WorkoutInputs(confirmed: offClock()))
        await workout.settled()
        #expect(driver.calls.first == .recover)
        #expect(driver.calls.filter { $0 == .recover }.count == 1)
    }

    @Test func aRecoveredStoppedSessionGoesStraightBackToWaitingForItsClockOut() async {
        driver.recoverable = WorkoutLocal().started(at: at(7, 0), shiftId: shift, origin: .phoneLaunch, syncIdentifier: UUID())
            .stopped(at: at(16, 30))
        let workout = make()
        clock.now = at(16, 40)
        workout.recoverIfNeeded()
        // The phone answered the clock-out while the app was gone.
        workout.reconcile(WorkoutInputs(confirmed: offClock(closed: closed(shift, start: at(7, 0), end: at(16, 30)))))
        await workout.settled()
        #expect(driver.calls == [.recover, .finish(at(16, 30), Self.zone)])
    }

    @Test func aRecoveredSessionStillWaitingStaysStopped() async {
        driver.recoverable = WorkoutLocal().started(at: at(7, 0), shiftId: shift, origin: .phoneLaunch, syncIdentifier: UUID())
            .stopped(at: at(16, 30))
        let workout = make()
        clock.now = at(16, 40)
        workout.recoverIfNeeded()
        await workout.settled()
        // Nothing is decided before the model reports its outbox.
        #expect(driver.calls == [.recover])
        workout.reconcile(WorkoutInputs(confirmed: working(), outbox: [tap(.clockOut, shift: shift, at: at(16, 30))]))
        await workout.settled()
        #expect(driver.calls == [.recover])
        #expect(workout.live.waitingClockOut)
    }

    @Test func twoReconcileInputsDuringASlowStartGiveOneStart() async {
        driver.startDelay = .milliseconds(300)
        let workout = make()
        let tapIn = clockIn(minted, at: at(7, 0))
        workout.reconcile(WorkoutInputs(confirmed: offClock(), outbox: [tapIn]))
        try? await Task.sleep(for: .milliseconds(50))
        workout.reconcile(WorkoutInputs(confirmed: offClock(), inFlight: [tapIn]))
        workout.reconcile(WorkoutInputs(confirmed: working(minted)))
        await workout.settled()
        #expect(driver.starts.count == 1)
    }

    @Test func handleDuringRecoveryStartsNoSecondSession() async {
        driver.recoverDelay = .milliseconds(300)
        driver.recoverable = WorkoutLocal().started(at: at(7, 0), shiftId: shift, origin: .phoneLaunch, syncIdentifier: UUID())
        let workout = make()
        workout.recoverIfNeeded()
        try? await Task.sleep(for: .milliseconds(50))
        workout.handleLaunch()
        workout.reconcile(WorkoutInputs(confirmed: working()))
        await workout.settled()
        #expect(driver.starts.isEmpty)
        #expect(workout.live.recording == .recording)
    }

    // MARK: - Phone launches and the foreground

    @Test func aPhoneLaunchStartsInTheBackgroundThenTagsWhenTheStateArrives() async {
        recorder.foreground = false
        let workout = make()
        workout.handleLaunch()
        await workout.settled()
        #expect(driver.calls == [.recover, .start(at(7, 0), nil, .phoneLaunch)])
        #expect(recorder.haptics == [.started])

        clock.now = at(7, 0, 4)
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(6, 59, 58))))
        await workout.settled()
        #expect(driver.calls.last == .tag(shift))
    }

    @Test func aStateSeenInTheBackgroundStartsTheWorkoutWhenTheAppComesForward() async {
        recorder.foreground = false
        let workout = make()
        clock.now = at(7, 1)
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        #expect(driver.starts.isEmpty)

        recorder.foreground = true
        clock.now = at(7, 14)
        workout.recheck()
        await workout.settled()
        #expect(driver.calls.last == .start(at(7, 14), shift, .phoneLaunch))
        #expect(recorder.notices == ["Recording from 7:14"])
    }

    @Test func aWorkoutStartedAtTheShiftsStartSaysNothing() async {
        let workout = make()
        clock.now = at(7, 2)
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        #expect(driver.calls.last == .start(at(7, 0), shift, .phoneLaunch))
        #expect(recorder.notices.isEmpty)
    }

    @Test func aLowBatteryWarnsAtClockIn() async {
        recorder.battery = 0.42
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: offClock(), outbox: [clockIn(minted, at: at(7, 0))]))
        await workout.settled()
        #expect(recorder.notices == ["Battery 42%. Charge at lunch to last the shift."])
    }

    @Test func anActionButtonClockInRecordsItsOrigin() async {
        let workout = make()
        workout.noteActionButtonClockIn(shiftId: minted)
        workout.reconcile(WorkoutInputs(confirmed: offClock(), outbox: [clockIn(minted, at: at(7, 0))]))
        await workout.settled()
        #expect(driver.calls.last == .start(at(7, 0), minted, .actionButton))
    }

    // MARK: - Ended from outside

    @Test func anUnexpectedEndSavesWhatWasCollectedKeepsTheShiftAndOffersRecordAgain() async {
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()

        clock.now = at(10, 0)
        driver.emit(.endedUnexpectedly("Another workout started."))
        await until { workout.live.recording == .stoppedUnexpectedly }
        #expect(driver.calls.last == .salvage(at(10, 0)))
        #expect(recorder.haptics.last == .stopped)

        // No automatic restart, even with a fresh state.
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        #expect(driver.starts.count == 1)
        #expect(workout.live.recording == .stoppedUnexpectedly)

        clock.now = at(10, 2)
        workout.recordAgain()
        await workout.settled()
        #expect(driver.calls.last == .start(at(10, 2), shift, .recovered))
        #expect(workout.live.recording == .recording)
    }

    @Test func theBannerGoesOnceTheShiftEnds() async {
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        driver.emit(.endedUnexpectedly("Another workout started."))
        await until { workout.live.recording == .stoppedUnexpectedly }
        workout.reconcile(WorkoutInputs(confirmed: offClock(closed: closed(shift, start: at(7, 0), end: at(9, 0)))))
        await workout.settled()
        #expect(workout.live.recording == .idle)
    }

    @Test func aBatteryShutdownWithNoSessionToRecoverRestartsNow() async {
        let saved = WorkoutLocal().started(at: at(7, 0), shiftId: shift, origin: .phoneLaunch, syncIdentifier: UUID())
        let driver = FakeWorkoutDriver(local: saved)
        let workout = make(driver: driver)
        clock.now = at(14, 14)
        workout.recoverIfNeeded()
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        #expect(driver.calls == [.recover, .start(at(14, 14), shift, .recovered)])
        #expect(recorder.notices == ["Recording from 2:14"])
    }

    // MARK: - No workout

    @Test func deniedHealthRecordsNoWorkoutAndTheShiftGoesOn() async {
        driver.access = .denied
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: offClock(), outbox: [clockIn(minted, at: at(7, 0))]))
        await workout.settled()
        #expect(driver.starts.isEmpty)
        #expect(workout.live.recording == .notAuthorized)
    }

    @Test func recordingOffRecordsNoWorkout() async {
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: working(recordWorkouts: false)))
        await workout.settled()
        #expect(driver.starts.isEmpty)
        #expect(workout.live.recording == .off)
    }

    @Test func recordingTurnedOffMidShiftFinishesNow() async {
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        clock.now = at(9, 0)
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0), recordWorkouts: false)))
        await workout.settled()
        #expect(driver.calls.last == .finish(at(9, 0), Self.zone))
        #expect(workout.live.recording == .off)
    }

    // MARK: - The stuck clock-out

    @Test func theStuckClockOutNotifiesAfterSixtyMinutes() async {
        let sleeper = ManualSleeper()
        let workout = make(sleeper: sleeper)
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        let waiting = WorkoutInputs(confirmed: working(start: at(7, 0)), outbox: [tap(.clockOut, shift: shift, at: at(16, 30))])
        clock.now = at(16, 30)
        workout.reconcile(waiting)
        await workout.settled()
        #expect(driver.calls.last == .stop(at(16, 30)))
        #expect(notifier.stuckClockOuts == 0)

        // Let the deadline task reach its sleep.
        let wait = ContinuousClock.now + .seconds(3)
        while await sleeper.waiting == 0, ContinuousClock.now < wait { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(await sleeper.waiting == 1)
        clock.now = at(17, 30, 1)
        await sleeper.wakeAll()
        await until { notifier.stuckClockOuts == 1 }
        await workout.settled()
        #expect(notifier.stuckClockOuts == 1)
        #expect(driver.calls.last == .finish(at(16, 30), Self.zone))
        #expect(!workout.live.waitingClockOut)
    }

    // MARK: - Discards and the summary

    @Test func undoClockInDiscardsAndLeavesNoSummary() async {
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: offClock(), outbox: [clockIn(minted, at: at(7, 0))]))
        await workout.settled()
        clock.now = at(7, 1)
        workout.reconcile(WorkoutInputs(confirmed: working(minted), outbox: [tap(.cancelShift(minted), shift: minted, at: at(7, 1))]))
        await workout.settled()
        #expect(driver.calls.last == .discard)
        #expect(workout.live.lastSummary == nil)
        #expect(workout.summaryToShow(now: clock.now) == nil)
    }

    @Test func aWorkoutUnderTwoMinutesIsDiscardedWithNoSummary() async {
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: offClock(), outbox: [clockIn(minted, at: at(7, 0))]))
        await workout.settled()
        clock.now = at(7, 1, 30)
        workout.reconcile(WorkoutInputs(confirmed: offClock(closed: closed(minted, start: at(7, 0), end: at(7, 1)))))
        await workout.settled()
        #expect(driver.calls.last == .finish(at(7, 1), Self.zone))
        #expect(workout.live.lastSummary == nil)
    }

    @Test func theSummaryShowsForAnHourAndReachesThePhoneOrWaitsForTheNextFlush() async {
        @MainActor final class Phone {
            var sent: [WorkoutSummary] = []
            var inReach = false
        }
        let phone = Phone()
        let workout = make()
        workout.sendSummary = { summary in
            phone.sent.append(summary)
            return phone.inReach
        }
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        clock.now = at(15, 1)
        workout.reconcile(WorkoutInputs(confirmed: offClock(closed: closed(shift, start: at(7, 0), end: at(15, 0)))))
        await workout.settled()
        await until { !phone.sent.isEmpty }

        let summary = workout.live.lastSummary
        #expect(summary?.end == at(15, 0) && summary?.shiftId == shift)
        #expect(workout.summaryToShow(now: at(15, 59)) == summary)
        #expect(workout.summaryToShow(now: at(16, 0, 1)) == nil)
        #expect(phone.sent == [summary].compactMap { $0 })
        #expect(WorkoutStore(directory: directory).summaries().pending == summary)

        // The next flush, with the phone back.
        phone.inReach = true
        await workout.sendPendingSummary()
        #expect(phone.sent.count == 2)
        #expect(WorkoutStore(directory: directory).summaries().pending == nil)

        workout.dismissSummary()
        #expect(workout.summaryToShow(now: at(15, 2)) == nil)
        // A relaunch remembers it was seen.
        let again = make(driver: FakeWorkoutDriver())
        #expect(again.live.lastSummary == summary)
        #expect(again.summaryToShow(now: at(15, 3)) == nil)
    }

    // MARK: - Live numbers

    @Test func heartRateAndCaloriesFlowIntoTheLiveNumbers() async {
        let workout = make()
        workout.reconcile(WorkoutInputs(confirmed: working(start: at(7, 0))))
        await workout.settled()
        driver.emit(.metrics(heartRate: 104, kcal: 612))
        await until { workout.live.heartRate == 104 }
        #expect(workout.live.kcal == 612)
    }

    // MARK: - Onboarding

    @Test func theHealthCardShowsOnceAndAsksForHealthThenNotifications() async {
        driver.access = .notDetermined
        let workout = make()
        #expect(workout.needsHealthOnboarding)
        #expect(workout.onboardingStep == .health)
        workout.reconcile(WorkoutInputs(confirmed: offClock(recordWorkouts: false)))
        #expect(!workout.needsHealthOnboarding)
        workout.reconcile(WorkoutInputs(confirmed: offClock(), outbox: [clockIn(minted, at: at(7, 0))]))
        await workout.settled()
        #expect(workout.needsHealthOnboarding)
        #expect(driver.starts.isEmpty)

        await workout.allowHealth()
        #expect(driver.authorizationRequests == 1 && notifier.authorizationRequests == 1)
        #expect(!workout.needsHealthOnboarding && workout.onboardingStep == nil)
        await workout.settled()
        #expect(driver.calls.last == .start(at(7, 0), minted, .watchTap))
    }

    @Test func noCardWithoutHealthKit() {
        driver.access = .unavailable
        #expect(!make().needsHealthOnboarding)
    }
}

// MARK: - The queue

@Suite("Workout input queue")
struct WorkoutInputQueueTests {
    let a = WorkoutInputs(refusedClockIns: [UUID()])
    let b = WorkoutInputs(refusedClockIns: [UUID()])

    @Test func inputsCoalesceToTheNewest() {
        var queue = WorkoutInputQueue()
        queue.push(.inputs(a))
        queue.push(.phoneLaunch)
        queue.push(.inputs(b))
        #expect(queue.pop() == .phoneLaunch)
        #expect(queue.pop() == .inputs(b))
        #expect(queue.pop() == nil)
    }

    @Test func recoveryGoesFirstAndTheRestKeepTheirOrder() {
        var queue = WorkoutInputQueue()
        queue.push(.recordAgain)
        queue.push(.phoneLaunch)
        queue.push(.recover)
        #expect(queue.pop() == .recover)
        #expect(queue.pop() == .recordAgain)
        #expect(queue.pop() == .phoneLaunch)
        #expect(queue.isEmpty)
    }

    @Test func aSecondRecoveryWaitingIsTheSameOne() {
        var queue = WorkoutInputQueue()
        queue.push(.recover)
        queue.push(.recover)
        #expect(queue.pop() == .recover)
        #expect(queue.pop() == nil)
    }
}
