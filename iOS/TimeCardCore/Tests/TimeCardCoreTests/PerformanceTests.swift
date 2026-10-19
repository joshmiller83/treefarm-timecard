import Foundation
import XCTest
@testable import TimeCardCore

/// A late-season farm: 8,540 marks. Reading the field actions' state and the lock-screen
/// snapshot happens many times per redraw and on every lock-screen press, so it has to come
/// from what the store keeps up to date, not be rebuilt from every mark each time.
@MainActor
final class PerformanceTests: XCTestCase {
    static let rows = 854

    private func lateSeason() async throws -> (TimeCardSession, FieldActions) {
        let f = Fixtures()
        var block = f.block
        block.rowCount = Self.rows
        let shift = Shift(userId: f.userId, farmId: f.farmId, start: Fixtures.t0 - 86400, end: Fixtures.t0 - 86400 + 8 * 3600, rateCents: 1800,
                          updatedAt: Fixtures.t0)
        let marks = (0..<Self.rows).flatMap { row in (0..<10).map { f.mark(row: row, position: $0, shiftId: shift.id, at: Fixtures.t0 - 86400) } }
        XCTAssertEqual(marks.count, 8_540)
        let me = MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [f.member])
        let stub = StubAPIClient()
        await stub.seed(farmId: f.farmId, [.farm(f.farm), .member(f.member), .season(f.season), .field(f.field), .block(block), .shift(shift)]
                        + marks.map(SyncRecord.treeMark))
        await stub.addAccount(email: "josh@example.com", password: "pw", me: me)
        let session = TimeCardSession(store: try LocalStore.inMemory(), api: stub, tokens: InMemoryTokenStore(), deviceName: "Test")
        try await session.signIn(email: "josh@example.com", password: "pw")
        _ = await session.syncNow()
        XCTAssertEqual(session.snapshot.marks.count, 8_540)
        let actions = FieldActions(session: session, now: { Fixtures.t0 })
        XCTAssertTrue(actions.perform(.clockIn(fieldId: nil)).succeeded)
        return (session, actions)
    }

    func testReadingTheStateIsCheapOnALateSeasonFarm() async throws {
        let (session, actions) = try await lateSeason()
        defer { Task { await session.stop() } }
        let clock = ContinuousClock()
        let took = clock.measure {
            for _ in 0..<200 {
                _ = actions.state()
                _ = actions.liveSnapshot()
            }
        }
        XCTAssertLessThan(took, .milliseconds(250), "200 reads took \(took)")
        measure {
            for _ in 0..<50 {
                _ = actions.state()?.index.mark(at: TreeRef(blockId: Fixtures().blockId, row: 3, position: 3))
                _ = actions.liveSnapshot()
            }
        }
    }

    func testAPressOnALateSeasonFarmStaysQuick() async throws {
        let (session, actions) = try await lateSeason()
        defer { Task { await session.stop() } }
        // Every row is shaped, so a press walks to the end and says so; then the next state.
        measure {
            _ = actions.perform(.markNextRow)
            _ = actions.liveSnapshot()
        }
    }

    /// Other copies of the snapshot are always held (the session, the field actions, the map),
    /// so a write used to copy every mark under the store's lock. Now it copies a bucket.
    func testAWriteOnALateSeasonFarmCopiesLittle() throws {
        let f = Fixtures()
        let store = try LocalStore.inMemory()
        try store.activate(farmId: f.farmId)
        var block = f.block
        block.rowCount = Self.rows
        let marks = (0..<Self.rows).flatMap { row in (0..<10).map { f.mark(row: row, position: $0) } }
        try store.applyRemote(f.changes([.farm(f.farm), .season(f.season), .block(block)] + marks.map(SyncRecord.treeMark)), farmId: f.farmId, cursor: 1)
        let held = store.snapshot
        XCTAssertEqual(held.marks.count, 8_540)
        let clock = ContinuousClock()
        let took = clock.measure {
            for i in 0..<50 {
                var mark = marks[i]
                mark.updatedAt = Fixtures.t0 + Double(i + 1)
                try? store.save([.treeMark(mark)])
                _ = store.snapshot.seasonIndex.mark(at: mark.tree)
            }
        }
        XCTAssertLessThan(took, .milliseconds(250), "50 writes took \(took)")
        XCTAssertEqual(held.marks.count, 8_540)
        measure {
            var mark = marks[60]
            mark.updatedAt = Date()
            try? store.save([.treeMark(mark)])
        }
    }
}
