import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Push: tree marks")
struct MarkPushTests {
    @Test func workersMarkTreesOnTheirShifts() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let block = try await farm.seedBlock()
            let shift = try await farm.clockIn(sam)
            let mark = farm.mark(block, row: 0, tree: 0, on: shift)
            #expect(try await farm.push(.treeMark(mark), as: sam).isApplied)
            #expect(try await TreeClaimModel.query(on: app.db).count() == 1)
        }
    }

    @Test func theFirstMarkOnATreeWins() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let alex = try await farm.join("Alex")
            let block = try await farm.seedBlock(name: "2")
            let samShift = try await farm.clockIn(sam)
            let alexShift = try await farm.clockIn(alex)
            let winner = farm.mark(block, row: 11, tree: 3, on: samShift)
            #expect(try await farm.push(.treeMark(winner), as: sam).isApplied)

            let loser = try await farm.push(.treeMark(farm.mark(block, row: 11, tree: 3, on: alexShift)), as: alex)
            #expect(loser.status == .rejected)
            #expect(loser.reason == .treeTaken)
            #expect(loser.message == "Row 12, tree 4 in Block 2 was shaped by Sam on Oct 16.")
            #expect(loser.current == .treeMark(winner))

            // Told about their own mark from another shift, people hear "you".
            let again = try await farm.push(.treeMark(farm.mark(block, row: 11, tree: 3, on: samShift)), as: sam)
            #expect(again.message == "Row 12, tree 4 in Block 2 was shaped by you on Oct 16.")
        }
    }

    @Test func twoWorkersRacingForATreeGetOneWinner() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let alex = try await farm.join("Alex")
            let block = try await farm.seedBlock()
            let samShift = try await farm.clockIn(sam)
            let alexShift = try await farm.clockIn(alex)
            for row in 0..<10 {
                async let a = farm.push(.treeMark(farm.mark(block, row: row, tree: 5, on: samShift)), as: sam)
                async let b = farm.push(.treeMark(farm.mark(block, row: row, tree: 5, on: alexShift)), as: alex)
                let results = try await [a, b]
                #expect(results.filter(\.isApplied).count == 1)
                #expect(results.filter { $0.reason == .treeTaken }.count == 1)
            }
            #expect(try await TreeClaimModel.query(on: app.db).count() == 10)
        }
    }

    @Test func pushingYourOwnMarkAgainIsHarmless() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let block = try await farm.seedBlock()
            let shift = try await farm.clockIn(farm.admin)
            let mark = farm.mark(block, row: 3, tree: 3, on: shift)
            let first = try await farm.push(.treeMark(mark), as: farm.admin)
            let second = try await farm.push(.treeMark(mark), as: farm.admin)
            #expect(second.isApplied)
            #expect(second.seq == first.seq)
        }
    }

    @Test func unmarkingFreesTheTree() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let alex = try await farm.join("Alex")
            let block = try await farm.seedBlock()
            let samShift = try await farm.clockIn(sam)
            let alexShift = try await farm.clockIn(alex)
            var mark = farm.mark(block, row: 0, tree: 0, on: samShift)
            try await farm.push(.treeMark(mark), as: sam)
            mark.deletedAt = clock.now
            mark.updatedAt = clock.now.addingTimeInterval(1)
            #expect(try await farm.push(.treeMark(mark), as: sam).isApplied)
            #expect(try await farm.push(.treeMark(farm.mark(block, row: 0, tree: 0, on: alexShift)), as: alex).isApplied)

            // Sam's phone, offline, still has the old live copy: it doesn't come back.
            var stale = mark
            stale.deletedAt = nil
            stale.updatedAt = clock.now
            let res = try await farm.push(.treeMark(stale), as: sam)
            #expect(res.status == .rejected)
            #expect(res.reason == .invalid)
        }
    }

    @Test func workersOnlyTouchMarksOnTheirOwnShifts() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let block = try await farm.seedBlock()
            let joshShift = try await farm.clockIn(farm.admin)
            let samShift = try await farm.clockIn(sam)

            var onJosh = farm.mark(block, row: 0, tree: 0, on: joshShift)
            onJosh.userId = sam.userId
            #expect(try await farm.push(.treeMark(onJosh), as: sam).reason == .forbidden)

            var joshMark = farm.mark(block, row: 1, tree: 1, on: joshShift)
            try await farm.push(.treeMark(joshMark), as: farm.admin)
            joshMark.deletedAt = clock.now
            joshMark.updatedAt = clock.now.addingTimeInterval(1)
            #expect(try await farm.push(.treeMark(joshMark), as: sam).reason == .forbidden)

            // Admins may mark on anyone's shift and erase anyone's mark.
            var samMark = farm.mark(block, row: 2, tree: 2, on: samShift)
            #expect(try await farm.push(.treeMark(samMark), as: farm.admin).isApplied)
            samMark.deletedAt = clock.now
            samMark.updatedAt = clock.now.addingTimeInterval(1)
            #expect(try await farm.push(.treeMark(samMark), as: farm.admin).isApplied)
        }
    }

    @Test func marksAreChecked() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let block = try await farm.seedBlock(rows: 5, trees: 5)
            let shift = try await farm.clockIn(farm.admin)

            var wrongPerson = farm.mark(block, row: 0, tree: 0, on: shift)
            wrongPerson.userId = sam.userId
            #expect(try await farm.push(.treeMark(wrongPerson), as: farm.admin).reason == .invalid)

            let outside = try await farm.push(.treeMark(farm.mark(block, row: 5, tree: 0, on: shift)), as: farm.admin)
            #expect(outside.reason == .invalid)
            #expect(outside.message?.contains("Block 1") == true)

            #expect(try await farm.push(.treeMark(farm.mark(block, row: 0, tree: 0, on: shift, season: UUID())), as: farm.admin).reason == .notFound)

            let otherBlock = Block(fieldId: UUID(), name: "x", gridRow: 0, gridColumn: 0, rowCount: 5, treesPerRow: 5)
            #expect(try await farm.push(.treeMark(farm.mark(otherBlock, row: 0, tree: 0, on: shift)), as: farm.admin).reason == .notFound)

            let ghostShift = farm.shift(for: farm.admin, start: clock.now)
            #expect(try await farm.push(.treeMark(farm.mark(block, row: 0, tree: 0, on: ghostShift)), as: farm.admin).reason == .notFound)

            // Last season's marks stay put; new ones go on the active season.
            let old = Season(farmId: farm.farmId, name: "2024", startedAt: clock.now.addingTimeInterval(-400 * 86400), updatedAt: clock.now)
            try await RecordStore(db: app.db).save(.season(old), farm: farm.farmId)
            #expect(try await farm.push(.treeMark(farm.mark(block, row: 0, tree: 0, on: shift, season: old.id)), as: farm.admin).reason == .invalid)

            var mark = farm.mark(block, row: 0, tree: 0, on: shift)
            #expect(try await farm.push(.treeMark(mark), as: farm.admin).isApplied)
            mark.position = 1
            mark.updatedAt = clock.now.addingTimeInterval(1)
            #expect(try await farm.push(.treeMark(mark), as: farm.admin).reason == .invalid)
        }
    }

    @Test func deletingAShiftErasesItsMarks() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let alex = try await farm.join("Alex")
            let block = try await farm.seedBlock()
            var shift = try await farm.clockIn(sam)
            let marks = (0..<3).map { farm.mark(block, row: 0, tree: $0, on: shift) }
            try await farm.push(marks.map { .treeMark($0) }, as: sam)
            let before = try await farm.pull(as: sam).cursor

            shift.deletedAt = clock.now
            shift.updatedAt = clock.now.addingTimeInterval(1)
            #expect(try await farm.push(.shift(shift), as: sam).isApplied)
            #expect(try await TreeClaimModel.query(on: app.db).count() == 0)

            let erased = try await farm.pull(as: sam, since: before).changes.compactMap { c -> TreeMark? in
                if case .treeMark(let m) = c.record { return m }; return nil
            }
            #expect(erased.count == 3)
            #expect(erased.allSatisfy { !$0.isLive })

            // The device's own copy of the delete arrives later and is fine.
            var gone = marks[0]
            gone.deletedAt = clock.now
            gone.updatedAt = clock.now
            #expect(try await farm.push(.treeMark(gone), as: sam).isApplied)

            let alexShift = try await farm.clockIn(alex)
            #expect(try await farm.push(.treeMark(farm.mark(block, row: 0, tree: 0, on: alexShift)), as: alex).isApplied)
        }
    }
}
