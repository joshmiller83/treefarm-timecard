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
        // The running break ends at the same moment, on the shift's end day.
        #expect(model.draft.breaks[0].end == WallClock(hour: 16, minute: 0, dayOffset: 0))
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
        // ShiftRules' words (it may name Sam once the Kit says whose shift it is).
        #expect(model.visibleProblem?.hasPrefix("This overlaps") == true)
        #expect(model.visibleProblem?.contains("shift on Fri, Oct 16") == true)
        model.draft.day = F.day(2026, 10, 14)
        #expect(model.save() == "Shift saved.")
        let saved = try #require(session.snapshot.shifts[sams.id])
        #expect(saved.userId == F.sam)
        #expect(saved.rateCents == 1800)
        #expect(model.ownerLine == "Editing Sam Ortiz’s shift.")
    }

    @Test func yourOwnShiftNeedsNoOwnerLine() async throws {
        let mine = F.shift(10, 16, from: (7, 0), to: (15, 0))
        let session = try await F.session(shifts: [mine])
        defer { Task { await session.stop() } }
        #expect(try #require(ShiftEditorModel(session: session, shiftId: mine.id, now: { now })).ownerLine == nil)
    }

    @Test func aShiftDeletedElsewhereIsntBroughtBack() async throws {
        let mine = F.shift(10, 16, from: (7, 0), to: (15, 0))
        let session = try await F.session(shifts: [mine])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: mine.id, now: { now }))
        var gone = mine
        gone.deletedAt = now
        gone.updatedAt = now
        try session.save([.shift(gone)])
        model.draft.notes = "Late edit"
        #expect(model.save() == nil)
        #expect(model.visibleProblem == ShiftMessages.missing)
        #expect(session.snapshot.shifts[mine.id] == nil)
    }

    // MARK: Changes made elsewhere while the editor is open

    @Test func aBreakStartedElsewhereSurvivesAnEditorSave() async throws {
        let open = Shift(userId: F.me, farmId: F.farmId, start: F.at(10, 19, 7, 0), rateCents: 2000)
        let session = try await F.session(shifts: [open])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: open.id, now: { now }))
        // Lunch from the lock screen, saved the way FieldActions saves it.
        var withLunch = try #require(session.snapshot.shifts[open.id])
        withLunch.breaks = [Break(kind: .lunch, start: F.at(10, 19, 12, 0), end: F.at(10, 19, 12, 30))]
        withLunch.updatedAt = F.at(10, 19, 12, 30)
        try session.save([.shift(withLunch)])

        model.draft.notes = "Gate fixed."
        #expect(model.save() == "Shift saved.")
        let saved = try #require(session.snapshot.shifts[open.id])
        #expect(saved.breaks == withLunch.breaks)
        #expect(saved.notes == "Gate fixed.")
        #expect(saved.isOpen)
    }

    @Test func aClockOutElsewhereWhileTheEditorIsOpenStaysClosed() async throws {
        let open = Shift(userId: F.me, farmId: F.farmId, start: F.at(10, 19, 7, 0),
                         breaks: [Break(kind: .break, start: F.at(10, 19, 14, 40))], rateCents: 2000)
        let session = try await F.session(shifts: [open])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: open.id, now: { now }))
        #expect(model.canStayOpen)
        // "Clock out" to Siri: the running break ends too.
        var out = try #require(session.snapshot.shifts[open.id])
        out.end = F.at(10, 19, 15, 0)
        out.breaks[0].end = F.at(10, 19, 15, 0)
        out.updatedAt = F.at(10, 19, 15, 0)
        try session.save([.shift(out)])

        model.draft.notes = "Long day."
        #expect(model.save() == "Shift saved.")
        let saved = try #require(session.snapshot.shifts[open.id])
        #expect(saved.end == F.at(10, 19, 15, 0))
        #expect(saved.breaks[0].end == F.at(10, 19, 15, 0))
        #expect(saved.notes == "Long day.")
        #expect(!model.canStayOpen)
    }

    @Test func aPartChangedOnBothSidesAsksToLookAgain() async throws {
        let mine = F.shift(10, 16, from: (7, 0), to: (15, 0))
        let session = try await F.session(shifts: [mine])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: mine.id, now: { now }))
        var noted = mine
        noted.notes = "Said to Siri."
        noted.updatedAt = F.at(10, 19, 15, 0)
        try session.save([.shift(noted)])

        model.draft.notes = "Typed here."
        model.draft.start = WallClock(hour: 7, minute: 30)
        #expect(model.save() == nil)
        #expect(model.visibleProblem == ShiftMessages.changedElsewhere)
        // Nothing was written; the editor now shows the stored notes and keeps the other edit.
        #expect(session.snapshot.shifts[mine.id]?.notes == "Said to Siri.")
        #expect(session.snapshot.shifts[mine.id]?.start == mine.start)
        #expect(model.draft.notes == "Said to Siri.")
        #expect(model.draft.start == WallClock(hour: 7, minute: 30))

        // Saving again writes it.
        #expect(model.save() == "Shift saved.")
        #expect(model.visibleProblem == nil)
        let saved = try #require(session.snapshot.shifts[mine.id])
        #expect(saved.notes == "Said to Siri.")
        #expect(saved.start == F.at(10, 16, 7, 30))
    }

    @Test func savingWithoutChangesWritesNothing() async throws {
        let mine = F.shift(10, 16, from: (7, 0), to: (15, 0))
        let session = try await F.session(shifts: [mine])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: mine.id, now: { now }))
        let before = try session.store.pendingCount()
        #expect(model.save() == ShiftMessages.unchanged)
        #expect(try session.store.pendingCount() == before)
        #expect(session.snapshot.shifts[mine.id]?.updatedAt == mine.updatedAt)
    }

    @Test func aStaleOpenShiftKeepsTodaysBreakOnSave() async throws {
        // Left open since Sunday 7:00; a break this morning at 9:00, later in the day than 7:00.
        let open = Shift(userId: F.me, farmId: F.farmId, start: F.at(10, 18, 7, 0),
                         breaks: [Break(kind: .break, start: F.at(10, 19, 9, 0), end: F.at(10, 19, 9, 15))], rateCents: 2000)
        let session = try await F.session(shifts: [open])
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: open.id, now: { now }))
        model.draft.notes = "Forgot to clock out."
        #expect(model.save() == "Shift saved.")
        let saved = try #require(session.snapshot.shifts[open.id])
        #expect(saved.breaks == open.breaks)
        #expect(saved.start == open.start)
        #expect(saved.isOpen)
    }

    @Test func theDeleteCountIncludesRowsMarkedWhileOpen() async throws {
        let open = Shift(userId: F.me, farmId: F.farmId, start: F.at(10, 19, 7, 0), rateCents: 2000)
        let session = try await F.session(shifts: [open], marks: F.marks(rows: 0...1, on: open))
        defer { Task { await session.stop() } }
        let model = try #require(ShiftEditorModel(session: session, shiftId: open.id, now: { now }))
        #expect(model.trees == 20)
        // A row marked from the lock screen while the editor is open.
        try session.save(F.marks(rows: 2...2, on: open).map(SyncRecord.treeMark))
        model.askToDelete()
        #expect(model.deleteButton == "Delete shift and 30 trees")
        #expect(model.delete() == "Shift deleted. 30 trees unmarked.")
        #expect(session.snapshot.marks.isEmpty)
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
