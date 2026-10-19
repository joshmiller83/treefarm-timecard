import Foundation
import TimeCardCore
@testable import TimeCard

/// A small farm in Indiana time with a Monday week, for the Log and Report tests.
/// October 2026: Mon 12 … Sun 18, Mon 19 … Sun 25. DST ends Sun Nov 1.
enum LogReportFixture {
    static let farmId = UUID(uuidString: "00000000-0000-0000-0000-00000000F000")!
    static let me = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let sam = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    static let seasonId = UUID(uuidString: "00000000-0000-0000-0000-0000000005E1")!
    static let oldSeasonId = UUID(uuidString: "00000000-0000-0000-0000-0000000005E0")!
    static let fieldId = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!

    static let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!
    static let farm = Farm(id: farmId, name: "Pine Hollow Tree Farm", timeZoneId: zone.identifier, weekStart: .monday, activeSeasonId: seasonId)
    static var calendar: FarmCalendar { FarmCalendar(farm: farm) }

    static let block1 = Block(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!, fieldId: fieldId, name: "1",
                              gridRow: 0, gridColumn: 0, rowCount: 20, treesPerRow: 10)
    static let block2 = Block(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!, fieldId: fieldId, name: "2",
                              gridRow: 0, gridColumn: 1, rowCount: 20, treesPerRow: 10)

    static let meMember = Member(userId: me, farmId: farmId, displayName: "Alex Rivera", email: "alex@example.com", role: .admin,
                                 jobTitle: "Crew lead", rateCents: 2000)
    static let samMember = Member(userId: sam, farmId: farmId, displayName: "Sam Ortiz", email: "sam@example.com", role: .worker,
                                  jobTitle: "Trimmer", rateCents: 1800)

    static func day(_ y: Int, _ m: Int, _ d: Int) -> DayKey { DayKey(year: y, month: m, day: d) }

    /// That wall-clock time on the farm.
    static func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int, year: Int = 2026) -> Date {
        calendar.date(on: day(year, m, d), hour: h, minute: min)
    }

    /// One of Alex's shifts.
    static func shift(_ month: Int, _ d: Int, from: (Int, Int), to: (Int, Int)?, nextDay: Bool = false,
                      breaks: [Break] = [], notes: String = "", rate: Int = 2000) -> Shift {
        shift(me, month, d, from: from, to: to, nextDay: nextDay, breaks: breaks, notes: notes, rate: rate)
    }

    static func shift(_ user: UUID, _ month: Int, _ d: Int, from: (Int, Int), to: (Int, Int)?, nextDay: Bool = false,
                      breaks: [Break] = [], notes: String = "", rate: Int = 2000, id: UUID = UUID()) -> Shift {
        let start = at(month, d, from.0, from.1)
        let end = to.map { at(month, d + (nextDay ? 1 : 0), $0.0, $0.1) }
        return Shift(id: id, userId: user, farmId: farmId, start: start, end: end, breaks: breaks, notes: notes, rateCents: rate, updatedAt: start)
    }

    static func lunch(_ month: Int, _ d: Int, _ h: Int = 12, _ m: Int = 0, minutes: Int = 30) -> Break {
        Break(kind: .lunch, start: at(month, d, h, m), end: at(month, d, h, m).addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// Whole rows of a block, marked on a shift.
    static func marks(rows: ClosedRange<Int>, in block: Block = block1, on shift: Shift, season: UUID = seasonId, positions: Range<Int>? = nil) -> [TreeMark] {
        rows.flatMap { row in
            (positions ?? 0..<block.treesPerRow).map { p in
                TreeMark(seasonId: season, tree: TreeRef(blockId: block.id, row: row, position: p), shiftId: shift.id, userId: shift.userId,
                         markedAt: shift.start.addingTimeInterval(TimeInterval(row * 100 + p)))
            }
        }
    }

    /// A snapshot holding the farm, both people, the blocks, and the given shifts and marks.
    static func snapshot(shifts: [Shift], marks: [TreeMark] = []) -> FarmSnapshot {
        var s = FarmSnapshot(farmId: farmId)
        s.apply(.farm(farm))
        s.members = [me: meMember, sam: samMember]
        s.blocks = [block1.id: block1, block2.id: block2]
        s.fields = [fieldId: Field(id: fieldId, farmId: farmId, name: "North Field")]
        s.seasons = [seasonId: Season(id: seasonId, farmId: farmId, name: "2026", startedAt: at(1, 1, 0, 0))]
        for shift in shifts { s.shifts[shift.id] = shift }
        for mark in marks { s.apply(.treeMark(mark)) }
        return s
    }

    /// A signed-in session on the fixture farm (the stub server holds the records, and a
    /// first sync brings them down). Stop it when done.
    @MainActor
    static func session(shifts: [Shift] = [], marks: [TreeMark] = []) async throws -> TimeCardSession {
        let user = UserProfile(id: me, email: meMember.email, displayName: meMember.displayName)
        let response = MeResponse(user: user, farms: [farm], memberships: [meMember])
        var records: [SyncRecord] = [.farm(farm), .member(meMember), .member(samMember)]
        let snap = snapshot(shifts: [])
        records += snap.seasons.values.map(SyncRecord.season) + snap.fields.values.map(SyncRecord.field) + [.block(block1), .block(block2)]
        records += shifts.map(SyncRecord.shift) + marks.map(SyncRecord.treeMark)
        let server = StubAPIClient(seed: .init(farmId: farmId, records: records,
                                               accounts: [.init(email: meMember.email, password: "fixture-password", me: response)],
                                               signedIn: response))
        let store = try LocalStore.inMemory()
        try store.setValue(try JSONCoding.encoder().encode(response), forKey: AuthService.meKey)
        // Writes wait in the outbox during a test instead of racing a push.
        var engine = SyncEngine.Configuration()
        engine.debounce = .seconds(3600)
        let session = TimeCardSession(store: store, api: server, tokens: InMemoryTokenStore(token: "fixture-token"), deviceName: "Test",
                                      engineConfiguration: engine)
        await session.start()
        _ = await session.syncNow()
        return session
    }
}
