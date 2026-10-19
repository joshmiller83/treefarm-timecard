import Foundation
import Testing
import TreeFarmKit
@testable import TimeCardWatch

/// The complications reload only when something they show changed (docs/watch.md 4.3): a
/// reload in the background counts against a small daily budget, so a timer tick, a new
/// revision or a chip past the first never spends one.
@Suite("Complication reload")
struct ComplicationReloadTests {
    typealias F = ComplicationFixtures
    typealias Contents = WatchStateFile.Contents

    func reloads(_ old: WatchState?, _ new: WatchState?, waiting: (Int, Int) = (0, 0)) -> Bool {
        ComplicationReload.needsReload(old: Contents(displayed: old, waitingCount: waiting.0),
                                       new: Contents(displayed: new, waitingCount: waiting.1))
    }

    // MARK: Always

    @Test func theKindIsTheOneTheWidgetExtensionRegisters() {
        // docs/watch.md 4.3: one StaticConfiguration of this kind, reloaded by the app.
        #expect(ComplicationReload.kind == "timecard.watch.shift")
    }

    @Test func theFirstWriteReloads() {
        #expect(ComplicationReload.needsReload(old: nil, new: Contents(displayed: F.working())))
        #expect(ComplicationReload.needsReload(old: nil, new: .empty))
    }

    @Test func nothingChangedNeverReloads() {
        for state in [F.working(), F.onBreak(.lunch), F.onBreak(.onBreak), F.offClock(todayWorked: 6.5 * 3600), nil] {
            #expect(!reloads(state, state))
        }
        #expect(!ComplicationReload.needsReload(old: .empty, new: .empty))
    }

    // MARK: What doesn't show

    @Test func aTimerTickDoesNotReload() {
        // The phone's next state: a minute later, a new revision, a minute more worked, the
        // timer counting from the same moment.
        let old = F.working()
        var new = old
        new.updatedAt = old.updatedAt.addingTimeInterval(60)
        new.revision += 1
        new.snapshot!.workedSoFar += 60
        #expect(!reloads(old, new))
        // A rebuilt snapshot can land a fraction of a second away.
        new.snapshot!.timerStart = old.snapshot!.timerStart.addingTimeInterval(0.6)
        #expect(!reloads(old, new))
        // The same on a break and off the clock.
        var lunch = F.onBreak(.lunch)
        let lunchBefore = lunch
        lunch.updatedAt = lunch.updatedAt.addingTimeInterval(300)
        lunch.revision += 3
        #expect(!reloads(lunchBefore, lunch))
        var off = F.offClock(todayWorked: 6.5 * 3600)
        let offBefore = off
        off.updatedAt = off.updatedAt.addingTimeInterval(3600)
        #expect(!reloads(offBefore, off))
    }

    @Test func aLaterChipDoesNotReload() {
        let old = F.working(rows: Array(14...30))
        // Row 20 was marked from the lock screen; 14 is still next.
        let new = F.working(rows: [14, 15, 16, 17, 18, 19] + Array(21...31))
        #expect(!reloads(old, new))
        // Fewer chips known, the first the same.
        #expect(!reloads(old, F.working(rows: [14])))
        // Off the clock too.
        var off = F.offClock()
        let offBefore = off
        off.nextRows.removeLast(5)
        #expect(!reloads(offBefore, off))
    }

    @Test func bookkeepingTheComplicationsDontShowDoesNotReload() {
        let old = F.working()
        var new = old
        new.epoch = UUID()
        new.appliedRequestIds = [UUID(), UUID()]
        new.canUndo = true
        new.snapshot!.canUndo = true
        new.snapshot!.lastAction = "Row 13 marked"
        new.todayTrees += 40
        new.pacePerHour = 34
        new.hadLunchToday = true
        new.recordWorkouts = false
        new.farmName = "Pine Hollow"
        new.snapshot!.fieldShaped += 12
        #expect(!reloads(old, new))
    }

    @Test func moreTapsWaitingDoesNotReloadUntilTheCountReachesZero() {
        let state = F.working()
        #expect(!reloads(state, state, waiting: (1, 3)))
        #expect(!reloads(state, state, waiting: (3, 2)))
    }

    // MARK: What shows

    @Test func signingInOrOutReloads() {
        let signedOut = WatchState.signedOut(epoch: F.epoch, revision: 9, now: F.at(10, 43))
        #expect(reloads(F.working(), signedOut))
        #expect(reloads(signedOut, F.offClock()))
        #expect(reloads(nil, signedOut))
    }

    @Test func everyPhaseChangeReloads() {
        let phases = [F.offClock(), F.working(), F.onBreak(.lunch), F.onBreak(.onBreak)]
        for old in phases {
            for new in phases where WatchDisplay.phase(old) != WatchDisplay.phase(new) {
                #expect(reloads(old, new), "\(WatchDisplay.phase(old)) → \(WatchDisplay.phase(new))")
            }
        }
    }

    @Test func aNewFirstChipReloads() {
        // Row 14 marked: 15 is next.
        #expect(reloads(F.working(rows: Array(14...30)), F.working(rows: Array(15...30))))
        // The same row number in another block.
        var other = F.working()
        other.nextRows[0] = F.chips([14], block: F.block3, name: "Block 3")[0]
        #expect(reloads(F.working(), other))
        // The last known chip used up.
        #expect(reloads(F.working(rows: [14]), F.working(rows: [])))
        // Off the clock: "Row 14 next".
        var off = F.offClock()
        let offBefore = off
        off.nextRows.removeFirst()
        #expect(reloads(offBefore, off))
    }

    @Test func theFieldReloads() {
        let old = F.working()
        var new = old
        new.fieldName = "South"
        new.snapshot!.fieldName = "South"
        #expect(reloads(old, new))
        // Every row shaped: the ring's row number turns into a check.
        let lastRow = F.state(F.snapshot(.working, rows: [], shaped: 399, total: 400), rows: [])
        let done = F.state(F.snapshot(.working, rows: [], shaped: 400, total: 400), rows: [])
        #expect(reloads(lastRow, done))
    }

    @Test func waitingTapsReloadWhenTheyStartAndWhenTheyClear() {
        let state = F.working()
        #expect(reloads(state, state, waiting: (0, 1)))
        #expect(reloads(state, state, waiting: (2, 0)))
    }

    @Test func aClockOutWaitingForThePhoneReloads() {
        let off = F.offClock(todayWorked: 3.7 * 3600)
        #expect(ComplicationReload.needsReload(old: Contents(displayed: off, waitingCount: 1),
                                               new: Contents(displayed: off, waitingCount: 1, clockOutWaiting: true)))
        #expect(ComplicationReload.needsReload(old: Contents(displayed: off, waitingCount: 1, clockOutWaiting: true),
                                               new: Contents(displayed: off, waitingCount: 0)))
    }

    @Test func theLastClosedShiftReloads() {
        let old = F.offClock(todayWorked: 3.7 * 3600)
        var new = old
        new.lastClosedShift = ClosedShift(shiftId: F.shift, start: F.at(7, 1), end: F.at(10, 43), worked: 3.7 * 3600, trees: 38)
        #expect(reloads(old, new))
    }

    @Test func theUsualStartReloads() {
        // It moves "Clock in" up the Smart Stack at another time.
        #expect(reloads(F.offClock(usualStart: DateComponents(hour: 7, minute: 0)), F.offClock(usualStart: DateComponents(hour: 6, minute: 30))))
        #expect(reloads(F.offClock(usualStart: nil), F.offClock(usualStart: DateComponents(hour: 7, minute: 0))))
    }

    @Test func aStartTimeChangedOnThePhoneReloads() {
        // The timers would count from the wrong moment.
        let old = F.working()
        var new = old
        new.snapshot!.timerStart = old.snapshot!.timerStart.addingTimeInterval(-15 * 60)
        new.snapshot!.workedSoFar += 15 * 60
        new.shiftStart = old.shiftStart!.addingTimeInterval(-15 * 60)
        #expect(reloads(old, new))
        // The shift's start alone moves the Smart Stack window.
        var moved = old
        moved.shiftStart = old.shiftStart!.addingTimeInterval(-15 * 60)
        #expect(reloads(old, moved))
        // On a break: when it started, and the worked time frozen beside it.
        let lunch = F.onBreak(.lunch)
        var earlier = lunch
        earlier.snapshot!.breakStart = lunch.snapshot!.breakStart!.addingTimeInterval(-10 * 60)
        #expect(reloads(lunch, earlier))
        var moreWorked = lunch
        moreWorked.snapshot!.workedSoFar += 15 * 60
        #expect(reloads(lunch, moreWorked))
    }

    @Test func treesThisShiftReload() {
        // "Row 14 next · 38 trees": a few trees marked in a row that isn't done yet.
        #expect(reloads(F.working(trees: 38), F.working(trees: 44)))
    }

    @Test func hoursTodayReloadOnlyWhenTheShownTenthChanges() {
        // "6.5 h today" off the clock.
        #expect(reloads(F.offClock(todayWorked: 6.5 * 3600), F.offClock(todayWorked: 7 * 3600)))
        #expect(!reloads(F.offClock(todayWorked: 6.5 * 3600), F.offClock(todayWorked: 6.5 * 3600 + 30)))
        #expect(reloads(F.offClock(todayWorked: 0), F.offClock(todayWorked: 2 * 3600)))
    }

    @Test func theSameHoursOnALaterDayReload() {
        // Monday's timeline turned back to "IN" at midnight; Tuesday's own 6.5 h must show.
        let monday = F.offClock(todayWorked: 6.5 * 3600)
        var tuesday = monday
        tuesday.updatedAt = F.at(18, 0, day: 20)
        #expect(reloads(monday, tuesday))
        // With nothing worked, the day doesn't show.
        let mondayIdle = F.offClock(todayWorked: 0)
        var tuesdayIdle = mondayIdle
        tuesdayIdle.updatedAt = F.at(6, 50, day: 20)
        #expect(!reloads(mondayIdle, tuesdayIdle))
    }

    @Test func theFarmsTimeZoneReloads() {
        // "Lunch since 12:01" and the morning window read in it.
        let old = F.onBreak(.lunch)
        var new = old
        new.farmTimeZone = "America/Los_Angeles"
        #expect(reloads(old, new))
    }
}
