import Foundation
import Testing
import TreeFarmKit
@testable import TimeCardWatch

/// What the four complication families show (docs/watch.md 4.3), worked out once from what
/// the watch app wrote and the entry's moment. The views only lay these out.
@Suite("Complication face")
struct ComplicationFaceTests {
    typealias F = ComplicationFixtures
    typealias Contents = WatchStateFile.Contents

    func face(_ state: WatchState?, waiting: Int = 0, clockOutWaiting: Bool = false, at date: Date = F.at(10, 42)) -> ComplicationFace {
        ComplicationFace(Contents(displayed: state, waitingCount: waiting, clockOutWaiting: clockOutWaiting), at: date)
    }

    // MARK: Working

    @Test func working() {
        let state = F.working()
        let f = face(state)
        #expect(f.phase == .working)
        #expect(f.tone == .working)
        #expect(f.glyph == "leaf.fill")
        #expect(f.word == "Working")
        #expect(f.timerStart == state.snapshot!.timerStart)
        #expect(f.breakStart == nil)
        // Circular "14", corner "R14", read as "next row 14".
        #expect(f.rowNumber == "14")
        #expect(f.cornerRow == "R14")
        #expect(f.noRowGlyph == nil)
        #expect(f.rowAccessibility == "next row 14")
        // Rectangular.
        #expect(f.title == "Working · Block 2")
        #expect(f.shortTitle == "Block 2")
        #expect(f.detail == "Row 14 next · 38 trees")
        #expect(!f.detailIsWaiting)
        #expect(f.detailAccessibility == nil)
        // Inline, after the timer.
        #expect(f.inlineDetail == "Row 14")
    }

    @Test func aShapedFieldShowsACheck() {
        let done = F.state(F.snapshot(.working, rows: [], shaped: 400, total: 400), rows: [])
        let f = face(done)
        #expect(f.rowNumber == nil)
        #expect(f.cornerRow == nil)
        #expect(f.noRowGlyph == "checkmark")
        #expect(f.rowAccessibility == "Field done")
        #expect(f.title == "Working")
        #expect(f.detail == "38 trees")
    }

    @Test func outOfKnownRowsShowsThePhoneAway() {
        // Rows are left, but the watch marked every one it knew while the phone was away.
        let away = F.state(F.snapshot(.working, rows: [], shaped: 160, total: 400), rows: [])
        let f = face(away)
        #expect(f.rowNumber == nil)
        #expect(f.noRowGlyph == "iphone.slash")
        #expect(f.rowAccessibility == "Out of rows the watch knows")
    }

    // MARK: Lunch and breaks

    @Test func lunch() {
        let state = F.onBreak(.lunch)
        let f = face(state)
        #expect(f.phase == .lunch)
        #expect(f.tone == .onBreak)
        #expect(f.glyph == "cup.and.saucer.fill")
        #expect(f.word == "Lunch")
        #expect(f.breakWord == "Lunch")
        // The break's own timer; the worked time frozen in the ring.
        #expect(f.timerStart == nil)
        #expect(f.breakStart == F.at(10, 30))
        let worked: TimeInterval = 3 * 3600 + 41 * 60
        #expect(f.frozenRing == worked / ComplicationFace.ringDay)
        #expect(f.rowNumber == nil)
        #expect(f.rowAccessibility == nil)
        #expect(f.title == "Lunch since 10:30")
        #expect(f.detail == "3:41 worked today")
        // One element per timer: the frozen one is read whole.
        #expect(f.detailAccessibility == "Worked 3 hours 41 minutes")
        #expect(f.inlineDetail == "3:41 worked")
    }

    @Test func aBreak() {
        let f = face(F.onBreak(.onBreak))
        #expect(f.phase == .onBreak)
        #expect(f.tone == .onBreak)
        #expect(f.glyph == "pause.fill")
        #expect(f.word == "Break")
        #expect(f.breakWord == "Break")
        #expect(f.title == "Break since 10:30")
    }

    @Test func aBreakWithoutAStartCountsFromTheTimer() {
        var state = F.onBreak(.lunch)
        state.snapshot!.breakStart = nil
        #expect(face(state).breakStart == state.snapshot!.timerStart)
    }

    // MARK: Off the clock

    @Test func offTheClockBeforeAnyWork() {
        let f = face(F.offClock(todayWorked: 0))
        #expect(f.phase == .offClock)
        #expect(f.tone == .offClock)
        #expect(f.glyph == "leaf")
        #expect(f.word == "Off the clock")
        #expect(f.hoursMark == "IN")
        #expect(f.hoursLine == "Clock in")
        #expect(f.title == "Time Card")
        #expect(f.detail == "Row 14 next")
        #expect(f.inlineDetail == "Clock in")
        #expect(f.timerStart == nil)
        #expect(f.breakStart == nil)
    }

    @Test func offTheClockAfterAShift() {
        let f = face(F.offClock(todayWorked: 6.5 * 3600))
        #expect(f.hoursMark == "6.5h")
        #expect(f.hoursLine == "6.5 h today")
        #expect(f.detail == "6.5 h today · Row 14 next")
        #expect(f.inlineDetail == "6.5 h today")
    }

    @Test func yesterdaysHoursAreGoneTheNextMorning() {
        // Clocked out Monday with 6.5 h; Tuesday at 7:00 the phone hasn't said anything new.
        let f = face(F.offClock(todayWorked: 6.5 * 3600), at: F.at(7, 0, day: 20))
        #expect(f.hoursMark == "IN")
        #expect(f.hoursLine == "Clock in")
        #expect(f.detail == "Row 14 next")
        #expect(f.inlineDetail == "Clock in")
        // Later the same Monday they still show.
        #expect(face(F.offClock(todayWorked: 6.5 * 3600), at: F.at(23, 30)).hoursMark == "6.5h")
    }

    // MARK: Waiting for the phone

    @Test func tapsWaitingTakeLineThree() {
        let f = face(F.working(), waiting: 2)
        #expect(f.detail == "2 taps waiting for iPhone")
        #expect(f.detailIsWaiting)
        #expect(f.detailAccessibility == nil)
        // On a break too: the frozen total gives way.
        #expect(face(F.onBreak(.lunch), waiting: 1).detail == "1 tap waiting for iPhone")
        #expect(face(F.onBreak(.lunch), waiting: 1).detailAccessibility == nil)
    }

    @Test func aClockOutWaitingSaysSo() {
        let f = face(F.offClock(todayWorked: 3.7 * 3600), waiting: 1, clockOutWaiting: true)
        #expect(f.detail == "Clock-out waiting for iPhone")
        #expect(f.detailIsWaiting)
    }

    // MARK: Signed out and no data

    @Test func signedOut() {
        let f = face(WatchState.signedOut(epoch: F.epoch, revision: 1, now: F.at(10, 42)))
        #expect(f.phase == .signedOut)
        #expect(f.tone == .none)
        #expect(f.glyph == "iphone")
        #expect(f.word == "Signed out")
        #expect(f.title == "Time Card")
        #expect(f.detail == nil)
        #expect(f.inlineDetail == "Time Card")
    }

    @Test func neverHeardFromThePhone() {
        let f = ComplicationFace(.empty, at: F.at(10, 42))
        #expect(f.phase == .noData)
        #expect(f.tone == .none)
        #expect(f.glyph == "iphone")
        #expect(f.word == "Time Card")
        #expect(f.title == "Time Card")
        #expect(f.detail == nil)
        #expect(f.inlineDetail == "Time Card")
    }
}
