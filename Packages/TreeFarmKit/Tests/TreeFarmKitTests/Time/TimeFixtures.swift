import Foundation
@testable import TreeFarmKit

/// Fixed zones, ids and dates for the time tests. Nothing here reads the machine's clock or zone.
enum TimeFixture {
    static let indyZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
    static let newYorkZone = TimeZone(identifier: "America/New_York")!
    static let utcZone = TimeZone(identifier: "UTC")!

    /// Dull's Tree Farm: Indianapolis, weeks start Monday.
    static let indy = FarmCalendar(timeZone: indyZone, weekStart: .monday)
    static let indySunday = FarmCalendar(timeZone: indyZone, weekStart: .sunday)
    static let newYork = FarmCalendar(timeZone: newYorkZone, weekStart: .monday)
    static let utc = FarmCalendar(timeZone: utcZone, weekStart: .monday)

    static let userId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let otherUserId = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    static let farmId = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!

    /// A moment written with its UTC offset, e.g. "2026-03-08T00:00:00-05:00".
    static func at(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: iso) else { fatalError("Bad ISO date \(iso)") }
        return d
    }

    /// Wall-clock time in a zone, "2026-10-18 07:02" (seconds optional: "2026-10-18 07:02:09").
    /// Built with a plain Calendar so it doesn't lean on the code under test.
    static func wall(_ s: String, _ zone: TimeZone = indyZone) -> Date {
        let parts = s.split(separator: " ")
        let d = parts[0].split(separator: "-").map { Int($0)! }
        let t = parts[1].split(separator: ":").map { Int($0)! }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let comps = DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1], second: t.count > 2 ? t[2] : 0)
        guard let date = cal.date(from: comps) else { fatalError("Bad wall time \(s)") }
        return date
    }

    static func hours(_ h: Double) -> TimeInterval { h * 3600 }
    static func minutes(_ m: Double) -> TimeInterval { m * 60 }

    static func shift(_ start: String, _ end: String?, breaks: [Break] = [], user: UUID = userId, notes: String = "", rateCents: Int = 1500, deleted: Bool = false, id: UUID = UUID()) -> Shift {
        Shift(id: id, userId: user, farmId: farmId, start: wall(start), end: end.map { wall($0) }, breaks: breaks, notes: notes,
              rateCents: rateCents, updatedAt: wall(start), deletedAt: deleted ? wall(start) : nil)
    }

    static func lunch(_ start: String, _ end: String?, reason: String = "") -> Break {
        Break(kind: .lunch, start: wall(start), end: end.map { wall($0) }, reason: reason)
    }

    static func rest(_ start: String, _ end: String?, reason: String = "") -> Break {
        Break(kind: .break, start: wall(start), end: end.map { wall($0) }, reason: reason)
    }
}
