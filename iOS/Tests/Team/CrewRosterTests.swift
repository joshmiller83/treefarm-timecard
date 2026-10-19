import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Team: crew roster")
struct CrewRosterTests {
    @Test func countsOnlyThisWeeksShiftsPerPerson() {
        var f = TeamFixture()
        // Last week (Sunday) doesn't count; Monday and today do.
        f.addShift(f.sam, from: f.at(18, 7), to: f.at(18, 15))
        f.addShift(f.sam, from: f.at(19, 7), to: f.at(19, 15), breaks: [Break(kind: .lunch, start: f.at(19, 11), end: f.at(19, 11, 30))])
        f.addShift(f.alex, from: f.at(21, 8), to: f.at(21, 10))

        let roster = CrewRoster.build(snapshot: f.snapshot, me: f.alex.userId, now: f.now, calendar: f.calendar)
        let sam = roster.current.first { $0.member.userId == f.sam.userId }
        let alex = roster.current.first { $0.member.userId == f.alex.userId }
        #expect(nearly(sam?.week, 7.5 * 3600))
        #expect(sam?.today == 0)
        #expect(nearly(alex?.week, 2 * 3600))
        #expect(nearly(alex?.today, 2 * 3600))
        #expect(nearly(roster.weekTotal, 9.5 * 3600))
        #expect(roster.weekStart == f.at(19, 0))
        #expect(roster.weekLabel == "Oct 19 – Oct 25, 2026")
    }

    @Test func anOpenShiftCountsUpToNowAndShowsWhoIsWorking() {
        var f = TeamFixture()
        f.addShift(f.sam, from: f.at(21, 9), to: nil)
        f.addShift(f.alex, from: f.at(21, 7), to: nil, breaks: [Break(kind: .lunch, start: f.at(21, 11, 45))])

        let roster = CrewRoster.build(snapshot: f.snapshot, me: f.alex.userId, now: f.now, calendar: f.calendar)
        let sam = roster.current.first { $0.member.userId == f.sam.userId }
        let alex = roster.current.first { $0.member.userId == f.alex.userId }
        #expect(nearly(sam?.week, 3 * 3600))
        #expect(sam?.status == .working(since: f.at(21, 9)))
        #expect(alex?.status == .onBreak(.lunch, since: f.at(21, 11, 45)))
        #expect(roster.onTheClock == 2)
    }

    @Test func listsCurrentCrewByNameAndKeepsFormerCrewApart() {
        var f = TeamFixture()
        f.addShift(f.jo, from: f.at(19, 7), to: f.at(19, 9))
        let roster = CrewRoster.build(snapshot: f.snapshot, me: f.alex.userId, now: f.now, calendar: f.calendar)
        #expect(roster.current.map(\.member.displayName) == ["Alex Rivera", "Sam Ortiz"])
        #expect(roster.former.map(\.member.displayName) == ["Jo Banks"])
        #expect(nearly(roster.former.first?.week, 2 * 3600))
        // Former crew's hours still count toward the farm's week.
        #expect(nearly(roster.weekTotal, 2 * 3600))
        #expect(roster.current.first?.isYou == true)
        #expect(roster.current.last?.isYou == false)
    }

    @Test func countsTreesShapedOnThisWeeksShifts() {
        var f = TeamFixture()
        let block = f.addBlock("1", row: 0, column: 0)
        let old = f.addShift(f.sam, from: f.at(16, 7), to: f.at(16, 15))
        let now = f.addShift(f.sam, from: f.at(20, 7), to: f.at(20, 15))
        f.mark(block, row: 0, position: 0, shift: old)
        f.mark(block, row: 0, position: 1, shift: now)
        f.mark(block, row: 0, position: 2, shift: now)
        let roster = CrewRoster.build(snapshot: f.snapshot, me: nil, now: f.now, calendar: f.calendar)
        #expect(roster.current.first { $0.member.userId == f.sam.userId }?.weekTrees == 2)
    }

    @Test func statusLinesSayTheDayWhenItIsNotToday() {
        let f = TeamFixture()
        #expect(CrewStatusText.line(.working(since: f.at(21, 7, 2)), calendar: f.calendar, now: f.now) == "Working since 7:02 AM")
        #expect(CrewStatusText.line(.onBreak(.lunch, since: f.at(21, 11, 45)), calendar: f.calendar, now: f.now) == "On lunch since 11:45 AM")
        #expect(CrewStatusText.line(.onBreak(.break, since: f.at(21, 10)), calendar: f.calendar, now: f.now) == "On a break since 10:00 AM")
        #expect(CrewStatusText.line(.working(since: f.at(20, 23, 52)), calendar: f.calendar, now: f.now) == "Working since Tue, Oct 20 at 11:52 PM")
        #expect(CrewStatusText.line(.off, calendar: f.calendar, now: f.now) == nil)
    }

    @Test func aShiftOpenMoreThanSixteenHoursLooksForgotten() {
        var f = TeamFixture()
        // It's Wednesday at noon. Sam clocked in Tuesday at 10 and never clocked out: 26 hours.
        let sams = f.addShift(f.sam, from: f.at(20, 10), to: nil)
        // Alex has been on since 7 this morning: 5 hours, nothing wrong.
        f.addShift(f.alex, from: f.at(21, 7), to: nil)
        // Jo was removed; an old open shift of theirs isn't the crew's problem to catch.
        f.addShift(f.jo, from: f.at(19, 7), to: nil)

        let roster = CrewRoster.build(snapshot: f.snapshot, me: f.alex.userId, now: f.now, calendar: f.calendar)
        let sam = roster.current.first { $0.member.userId == f.sam.userId }
        let alex = roster.current.first { $0.member.userId == f.alex.userId }
        #expect(sam?.forgotSince == f.at(20, 10))
        #expect(sam?.forgotClockOut == true)
        #expect(sam?.isOnTheClock == true)
        #expect(alex?.forgotSince == nil)
        #expect(roster.forgotClockOut.map(\.member.displayName) == ["Sam Ortiz"])
        #expect(roster.forgotSummary == "Sam Ortiz may have forgotten to clock out.")

        #expect(CrewStatusText.forgotLine(since: f.at(20, 10), calendar: f.calendar, now: f.now)
            == "Still clocked in since Tue, Oct 20 at 10:00 AM (26 h)")
        #expect(CrewStatusText.forgotQuestion(f.sam) == "Did Sam forget to clock out?")
        #expect(CrewStatusText.tone(sam!) == .alert)
        #expect(CrewStatusText.tone(alex!) == .working)

        let recent = CrewRoster.recentShifts(of: f.sam.userId, snapshot: f.snapshot, now: f.now, limit: 3)
        #expect(recent.first?.shift.id == sams.id)
        #expect(recent.first?.forgotClockOut == true)
    }

    @Test func sixteenHoursOnTheDotIsStillAShift() {
        var f = TeamFixture()
        f.addShift(f.sam, from: f.now.addingTimeInterval(-16 * 3600), to: nil)
        f.addShift(f.alex, from: f.now.addingTimeInterval(-16 * 3600 - 60), to: nil)
        let roster = CrewRoster.build(snapshot: f.snapshot, me: nil, now: f.now, calendar: f.calendar)
        #expect(roster.forgotClockOut.map(\.member.displayName) == ["Alex Rivera"])
        #expect(roster.forgotSummary == "Alex Rivera may have forgotten to clock out.")
        // An older shift left open behind the newer one is caught too.
        f.addShift(f.sam, from: f.at(19, 7), to: nil)
        let two = CrewRoster.build(snapshot: f.snapshot, me: nil, now: f.now, calendar: f.calendar)
        #expect(two.forgotSummary == "2 people may have forgotten to clock out.")
        #expect(CrewRoster.build(snapshot: TeamFixture().snapshot, me: nil, now: f.now, calendar: f.calendar).forgotSummary == nil)
    }

    @Test func zeroHoursAreSpokenAsNoHours() {
        #expect(CrewStatusText.spokenWeek(0) == "no hours this week")
        #expect(CrewStatusText.spokenWeek(7.5 * 3600) == "7 hours 30 minutes this week")
        #expect(CrewStatusText.spokenHours(0) == "No hours")
        #expect(CrewStatusText.spokenHours(2 * 3600) == "2 hours")
    }

    @Test func recentShiftsComeNewestFirstWithTreeCounts() {
        var f = TeamFixture()
        let block = f.addBlock("1", row: 0, column: 0)
        let monday = f.addShift(f.sam, from: f.at(19, 7), to: f.at(19, 15))
        let tuesday = f.addShift(f.sam, from: f.at(20, 7), to: f.at(20, 12))
        f.addShift(f.alex, from: f.at(20, 7), to: f.at(20, 12))
        f.mark(block, row: 1, position: 0, shift: monday)
        let recent = CrewRoster.recentShifts(of: f.sam.userId, snapshot: f.snapshot, now: f.now, limit: 5)
        #expect(recent.map(\.shift.id) == [tuesday.id, monday.id])
        #expect(recent.map(\.trees) == [0, 1])
        #expect(nearly(recent.first?.worked, 5 * 3600))
    }
}

/// Times built from calendar dates can be a hair off in the last bits.
func nearly(_ a: TimeInterval?, _ b: TimeInterval) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 0.001
}
