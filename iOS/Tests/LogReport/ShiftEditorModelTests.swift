import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@MainActor
@Suite("Shift editor")
struct ShiftEditorModelTests {
    typealias F = LogReportFixture
    let now = LogReportFixture.at(10, 19, 16, 0)

    @Test func addsANewShift() async throws {
        let session = try await F.session()
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: nil, now: { now }))
        #expect(model.isNew)
        #expect(model.visibleProblem == nil)
        #expect(model.save() == "Shift added.")
        let saved = try #require(session.snapshot.shifts.values.first)
        #expect(saved.userId == F.me)
        #expect(saved.rateCents == 2000)
        #expect(saved.start == F.at(10, 19, 7, 0))
        #expect(saved.end == F.at(10, 19, 15, 30))
        #expect(saved.updatedAt == now.roundedToMillisecond)
        #expect(try session.store.pendingCount() >= 1)
    }

    @Test func anOverlapIsRefusedWithTheRulesMessage() async throws {
        let existing = F.shift(10, 19, from: (7, 0), to: (15, 30))
        let session = try await F.session(shifts: [existing])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: nil, now: { now }))
        // Problems wait until a save is tried, so a fresh form isn't red.
        #expect(model.visibleProblem == nil)
        #expect(model.save() == nil)
        #expect(model.visibleProblem == "This overlaps your shift on Mon, Oct 19 from 7:00 AM to 3:30 PM. Change the times or edit that shift.")
        #expect(session.snapshot.shifts.count == 1)

        // Fixing it clears the message as they edit, then it saves.
        model.draft.day = F.day(2026, 10, 16)
        #expect(model.visibleProblem == nil)
        #expect(model.save() == "Shift added.")
        #expect(session.snapshot.shifts.count == 2)
    }

    @Test func otherPeoplesShiftsDontClash() async throws {
        let sams = F.shift(F.sam, 10, 19, from: (7, 0), to: (15, 30))
        let session = try await F.session(shifts: [sams])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: nil, now: { now }))
        model.draft.start = WallClock(hour: 8, minute: 0)
        #expect(model.save() == "Shift added.")
    }

    @Test func breakProblemsUseTheRulesWords() async throws {
        let existing = F.shift(10, 16, from: (7, 0), to: (15, 0))
        let session = try await F.session(shifts: [existing])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: existing.id, now: { now }))
        model.addBreak()
        model.draft.breaks[0].start = WallClock(hour: 16, minute: 0)
        model.draft.breaks[0].end = WallClock(hour: 16, minute: 30)
        #expect(model.save() == nil)
        #expect(model.visibleProblem == "Break 1 has to fall inside the shift.")
        model.removeBreak(model.draft.breaks[0].id)
        #expect(model.visibleProblem == nil)
    }

    @Test func savingNotesLeavesTheTimesAlone() async throws {
        var existing = F.shift(10, 16, from: (7, 2), to: (15, 31), breaks: [F.lunch(10, 16)])
        existing.start = existing.start.addingTimeInterval(17.25).roundedToMillisecond
        let session = try await F.session(shifts: [existing])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: existing.id, now: { now }))
        #expect(!model.isNew)
        model.draft.notes = "  Fixed the gate.  "
        #expect(model.save() == "Shift saved.")
        let saved = try #require(session.snapshot.shifts[existing.id])
        #expect(saved.start == existing.start)
        #expect(saved.end == existing.end)
        #expect(saved.breaks == existing.breaks)
        // Notes are trimmed on the way in, like everywhere else.
        #expect(saved.notes == "Fixed the gate.")
    }

    @Test func deletingTakesTheShiftsTreesAndSaysHowMany() async throws {
        let mine = F.shift(10, 16, from: (7, 0), to: (15, 0))
        let sams = F.shift(F.sam, 10, 15, from: (7, 0), to: (15, 0))
        let myMarks = F.marks(rows: 0...1, on: mine)
        let samMarks = F.marks(rows: 2...2, on: sams)
        let session = try await F.session(shifts: [mine, sams], marks: myMarks + samMarks)
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: mine.id, now: { now }))
        #expect(model.trees == 20)
        #expect(model.treeSummary == "Block 1: rows 1–2")
        #expect(model.stage == .editing)
        model.askToDelete()
        #expect(model.stage == .confirmingDelete)
        #expect(model.deleteQuestion == "Delete this shift? Its 20 trees will be unmarked on the map too. This can’t be undone.")
        #expect(model.deleteButton == "Delete shift and 20 trees")
        let before = try session.store.pendingCount()
        #expect(model.delete() == "Shift deleted. 20 trees unmarked.")
        #expect(session.snapshot.shifts[mine.id] == nil)
        #expect(session.snapshot.shifts[sams.id] != nil)
        #expect(Set(session.snapshot.marks.values.map(\.shiftId)) == [sams.id])
        #expect(try session.store.pendingCount() == before + 21)
    }

    @Test func keepingTheShiftChangesNothing() async throws {
        let mine = F.shift(10, 16, from: (7, 0), to: (15, 0))
        let session = try await F.session(shifts: [mine])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: mine.id, now: { now }))
        model.askToDelete()
        #expect(model.deleteQuestion == "Delete this shift? Its hours come off your time card. This can’t be undone.")
        #expect(model.deleteButton == "Delete shift")
        model.cancelDelete()
        #expect(model.stage == .editing)
        #expect(session.snapshot.shifts[mine.id] != nil)
    }

    @Test func deletingAnOpenShiftSaysYoureClockedIn() async throws {
        let open = Shift(userId: F.me, farmId: F.farmId, start: F.at(10, 19, 7, 0), rateCents: 2000)
        let session = try await F.session(shifts: [open])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: open.id, now: { now }))
        #expect(model.deleteQuestion.contains("You’re still clocked in on it."))
    }

    @Test func clockingOutAnOpenShiftEndsItsBreakToo() async throws {
        let start = F.at(10, 19, 7, 0)
        let open = Shift(userId: F.me, farmId: F.farmId, start: start,
                         breaks: [Break(kind: .break, start: F.at(10, 19, 15, 40), reason: "Fuel run")], rateCents: 2000)
        let session = try await F.session(shifts: [open])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: open.id, now: { now }))
        #expect(model.canStayOpen)
        #expect(model.draft.end == nil)
        model.setStillOnTheClock(false)
        #expect(model.draft.end == WallClock(hour: 16, minute: 0))
        #expect(model.draft.breaks[0].end == WallClock(hour: 16, minute: 0))
        #expect(model.save() == "Shift saved.")
        let saved = try #require(session.snapshot.shifts[open.id])
        #expect(saved.end == F.at(10, 19, 16, 0))
        #expect(saved.breaks[0].end == F.at(10, 19, 16, 0))
    }

    @Test func aClosedShiftCantBeLeftOpenAgain() async throws {
        let closed = F.shift(10, 16, from: (7, 0), to: (15, 0))
        let session = try await F.session(shifts: [closed])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: closed.id, now: { now }))
        #expect(!model.canStayOpen)
    }

    @Test func aShiftThatIsGoneHasNoEditor() async throws {
        let session = try await F.session()
        defer { Task { await session.stop() } }
        #expect(ShiftEditorModel(session: session, shiftId: UUID(), now: { now }) == nil)
    }

    @Test func adminsCanFixSomeoneElsesShift() async throws {
        let sams = F.shift(F.sam, 10, 15, from: (7, 0), to: (15, 0), rate: 1800)
        let samsOther = F.shift(F.sam, 10, 16, from: (7, 0), to: (15, 0), rate: 1800)
        let session = try await F.session(shifts: [sams, samsOther])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: sams.id, now: { now }))
        // Moving it onto Sam's other day clashes with Sam's shift, not the admin's.
        model.draft.day = F.day(2026, 10, 16)
        #expect(model.save() == nil)
        #expect(model.visibleProblem?.hasPrefix("This overlaps your shift on Fri, Oct 16") == true)
        model.draft.day = F.day(2026, 10, 14)
        #expect(model.save() == "Shift saved.")
        let saved = try #require(session.snapshot.shifts[sams.id])
        #expect(saved.userId == F.sam)
        #expect(saved.rateCents == 1800)
    }

    @Test func totalsLineReadsWorkedAndBreaks() async throws {
        let existing = F.shift(10, 16, from: (7, 0), to: (15, 30), breaks: [F.lunch(10, 16)])
        let session = try await F.session(shifts: [existing])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: existing.id, now: { now }))
        #expect(model.totalsLine == "8.00 hrs worked · 30 min of breaks")
        model.removeBreak(model.draft.breaks[0].id)
        #expect(model.totalsLine == "8.50 hrs worked")
    }
}
