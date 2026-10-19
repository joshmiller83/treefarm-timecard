import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Shift draft")
struct ShiftDraftTests {
    typealias F = LogReportFixture
    let cal = LogReportFixture.calendar
    let now = LogReportFixture.at(10, 19, 16, 0)

    @Test func anUntouchedShiftComesBackExactly() {
        // Odd seconds and milliseconds, which the pickers can't show, must survive a save.
        var shift = F.shift(10, 13, from: (7, 2), to: (15, 31), breaks: [F.lunch(10, 13)], notes: "Rain")
        // Saved times carry milliseconds, as everything stamped with `roundedToMillisecond` does.
        shift.start = shift.start.addingTimeInterval(13.456).roundedToMillisecond
        shift.end = shift.end!.addingTimeInterval(41.5).roundedToMillisecond
        shift.breaks[0].start = shift.breaks[0].start.addingTimeInterval(7)
        let draft = ShiftDraft(shift: shift, calendar: cal)
        let back = draft.shift(calendar: cal, now: now)
        #expect(back.start == shift.start)
        #expect(back.end == shift.end)
        #expect(back.breaks == shift.breaks)
        #expect(back.notes == "Rain")
        #expect(back.id == shift.id)
        #expect(back.rateCents == shift.rateCents)
        #expect(back.updatedAt == now.roundedToMillisecond)
    }

    @Test func aClockOutEarlierThanClockInIsTheNextDay() {
        var draft = ShiftDraft(shift: F.shift(10, 16, from: (18, 0), to: (23, 0)), calendar: cal)
        draft.end = WallClock(hour: 1, minute: 30)
        #expect(draft.endsNextDay)
        let s = draft.shift(calendar: cal, now: now)
        #expect(s.end == F.at(10, 17, 1, 30))
        #expect(s.workedTime(at: now) == 7.5 * 3600)
        #expect(ShiftRules.validate(s, others: [], now: now, calendar: cal) == nil)
    }

    @Test func breaksAfterMidnightLandOnTheNextDay() {
        var draft = ShiftDraft(shift: F.shift(10, 16, from: (20, 0), to: (4, 0), nextDay: true), calendar: cal)
        draft.breaks = [BreakDraft(kind: .break, start: WallClock(hour: 23, minute: 50), end: WallClock(hour: 0, minute: 20), reason: "Coffee")]
        let s = draft.shift(calendar: cal, now: now)
        #expect(s.breaks[0].start == F.at(10, 16, 23, 50))
        #expect(s.breaks[0].end == F.at(10, 17, 0, 20))
        #expect(draft.isNextDay(WallClock(hour: 0, minute: 20)))
        #expect(!draft.isNextDay(WallClock(hour: 23, minute: 50)))
        #expect(ShiftRules.validate(s, others: [], now: now, calendar: cal) == nil)
    }

    @Test func theSameTimeInAndOutIsAnErrorNotADayLongShift() {
        var draft = ShiftDraft(shift: F.shift(10, 16, from: (7, 0), to: (15, 0)), calendar: cal)
        draft.end = WallClock(hour: 7, minute: 0)
        #expect(!draft.endsNextDay)
        let s = draft.shift(calendar: cal, now: now)
        #expect(ShiftRules.validate(s, others: [], now: now, calendar: cal)?.message == "Clock out has to be after clock in.")
    }

    @Test func aBreakThatEndsBeforeItStartsSaysSo() {
        var draft = ShiftDraft(shift: F.shift(10, 16, from: (7, 0), to: (15, 0)), calendar: cal)
        draft.breaks = [BreakDraft(kind: .lunch, start: WallClock(hour: 12, minute: 30), end: WallClock(hour: 12, minute: 0))]
        let s = draft.shift(calendar: cal, now: now)
        #expect(ShiftRules.validate(s, others: [], now: now, calendar: cal)?.message == "Break 1 has to end after it starts.")
    }

    @Test func changingTheDayMovesEveryTime() {
        var draft = ShiftDraft(shift: F.shift(10, 16, from: (7, 0), to: (15, 0), breaks: [F.lunch(10, 16)]), calendar: cal)
        draft.day = F.day(2026, 10, 14)
        let s = draft.shift(calendar: cal, now: now)
        #expect(s.start == F.at(10, 14, 7, 0))
        #expect(s.end == F.at(10, 14, 15, 0))
        #expect(s.breaks[0].start == F.at(10, 14, 12, 0))
    }

    @Test func theRepeatedHourOnAFallBackNightKeepsItsInstant() {
        // Nov 1, 2026: 1:00–2:00 AM happens twice in Indiana. Start in the second one.
        let firstOneThirty = F.at(11, 1, 1, 30)
        let second = firstOneThirty.addingTimeInterval(3600)
        let shift = Shift(userId: F.me, farmId: F.farmId, start: second, end: second.addingTimeInterval(4 * 3600), rateCents: 0)
        let back = ShiftDraft(shift: shift, calendar: cal).shift(calendar: cal, now: second.addingTimeInterval(86400))
        #expect(back.start == second)
        #expect(back.end == shift.end)
    }

    @Test func aNewShiftCopiesTheLatestHoursOnADayTheyAreOver() {
        let mine = [F.shift(10, 12, from: (6, 45), to: (15, 15)), F.shift(10, 14, from: (7, 5), to: (16, 20)),
                    F.shift(F.sam, 10, 15, from: (5, 0), to: (9, 0))]
        // At 4 PM, 7:05–4:20 hasn't finished today, so it goes on yesterday.
        let early = ShiftDraft.newShift(userId: F.me, farmId: F.farmId, rateCents: 2100, mine: mine, now: now, calendar: cal)
        #expect(early.start == WallClock(hour: 7, minute: 5))
        #expect(early.end == WallClock(hour: 16, minute: 20))
        #expect(early.day == F.day(2026, 10, 18))
        #expect(early.rateCents == 2100)
        #expect(early.isNew)
        #expect(early.breaks.isEmpty)
        // At 5 PM it's over, so today.
        let late = ShiftDraft.newShift(userId: F.me, farmId: F.farmId, rateCents: 2100, mine: mine, now: F.at(10, 19, 17, 0), calendar: cal)
        #expect(late.day == F.day(2026, 10, 19))
    }

    @Test func aFirstShiftStartsAtSevenToHalfPastThree() {
        let d = ShiftDraft.newShift(userId: F.me, farmId: F.farmId, rateCents: 0, mine: [], now: F.at(10, 19, 9, 0), calendar: cal)
        #expect(d.start == WallClock(hour: 7, minute: 0))
        #expect(d.end == WallClock(hour: 15, minute: 30))
        #expect(d.day == F.day(2026, 10, 18))
        let s = d.shift(calendar: cal, now: F.at(10, 19, 9, 0))
        #expect(ShiftRules.validate(s, others: [], now: F.at(10, 19, 9, 0), calendar: cal) == nil)
    }

    @Test func theFirstSuggestedBreakIsLunchAtNoon() {
        var draft = ShiftDraft(shift: F.shift(10, 16, from: (7, 0), to: (15, 30)), calendar: cal)
        let lunch = draft.suggestedBreak(calendar: cal, now: now)
        #expect(lunch.kind == .lunch)
        #expect(lunch.start == WallClock(hour: 12, minute: 0))
        #expect(lunch.end == WallClock(hour: 12, minute: 30))
        draft.breaks.append(lunch)
        // Then a 15-minute break in the middle of the longest free stretch (7:00–12:00).
        let next = draft.suggestedBreak(calendar: cal, now: now)
        #expect(next.kind == .break)
        #expect(next.start == WallClock(hour: 9, minute: 20))
        #expect(next.end == WallClock(hour: 9, minute: 35))
        draft.breaks.append(next)
        #expect(ShiftRules.validate(draft.shift(calendar: cal, now: now), others: [], now: now, calendar: cal) == nil)
    }

    @Test func suggestedBreaksFitNightShifts() {
        let draft = ShiftDraft(shift: F.shift(10, 16, from: (18, 0), to: (2, 0), nextDay: true), calendar: cal)
        let b = draft.suggestedBreak(calendar: cal, now: now)
        #expect(b.kind == .lunch)
        #expect(b.start == WallClock(hour: 21, minute: 45))
        #expect(b.end == WallClock(hour: 22, minute: 15))
        var withBreak = draft
        withBreak.breaks = [b]
        #expect(ShiftRules.validate(withBreak.shift(calendar: cal, now: now), others: [], now: now, calendar: cal) == nil)
    }

    @Test func suggestedBreaksStayInsideAnOpenShift() {
        let start = F.at(10, 19, 7, 0)
        let open = Shift(userId: F.me, farmId: F.farmId, start: start, rateCents: 2000)
        let at = F.at(10, 19, 10, 0)
        let b = ShiftDraft(shift: open, calendar: cal).suggestedBreak(calendar: cal, now: at)
        // Noon hasn't come yet, so a lunch in the middle of the three hours so far.
        #expect(b.kind == .lunch)
        #expect(b.start == WallClock(hour: 8, minute: 15))
        #expect(b.end == WallClock(hour: 8, minute: 45))
    }

    @Test func totalsCountWorkedTimeAndBreaks() {
        let draft = ShiftDraft(shift: F.shift(10, 16, from: (7, 0), to: (15, 30), breaks: [F.lunch(10, 16)]), calendar: cal)
        let t = draft.totals(calendar: cal, now: now)
        #expect(t.worked == 8 * 3600)
        #expect(t.breaks == 30 * 60)
    }
}
