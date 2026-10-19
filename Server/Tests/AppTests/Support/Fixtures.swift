import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

/// A signed-in person in a test.
struct Person {
    let userId: UUID
    let email: String
    let password: String
    let name: String
    let token: String
}

/// A farm made the way production makes one: `bootstrap`, then the admin signs
/// in with the printed reset code, then people join with invite codes.
struct FarmFixture {
    let app: Application
    let farmId: UUID
    let seasonId: UUID
    let fieldId: UUID
    let admin: Person

    var client: TestClient { app.client2 }

    static func make(_ app: Application, farmName: String = "Dull's Tree Farm", adminEmail: String = "josh@example.com", tz: String = "America/Indiana/Indianapolis") async throws -> FarmFixture {
        let result = try await Bootstrap.run(app: app, email: adminEmail, name: "Josh", farmName: farmName, timeZoneId: tz)
        let password = "correct horse battery"
        let res = try await app.client2.send(.POST, APIPath.resetPassword, json: ResetPasswordRequest(email: adminEmail, resetCode: result.resetCode, newPassword: password, deviceName: "Josh's iPhone"))
        #expect(res.status == .ok, "reset: \(res.text)")
        let auth = try res.decode(AuthResponse.self)
        let admin = Person(userId: result.userId, email: adminEmail, password: password, name: "Josh", token: auth.token)
        return FarmFixture(app: app, farmId: result.farmId, seasonId: result.seasonId, fieldId: result.fieldId, admin: admin)
    }

    func inviteCode(role: Role = .worker) async throws -> String {
        try await Invites.create(on: app.db, farmId: farmId, role: role, note: "", createdBy: admin.userId, now: app.now).code
    }

    /// Invites and registers someone new.
    func join(_ name: String, role: Role = .worker, email: String? = nil, password: String = "pine needles 42") async throws -> Person {
        let email = email ?? "\(name.lowercased())@example.com"
        let code = try await inviteCode(role: role)
        let res = try await client.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: code, email: email, password: password, displayName: name, deviceName: "\(name)'s phone"))
        #expect(res.status == .ok, "register: \(res.text)")
        let auth = try res.decode(AuthResponse.self)
        return Person(userId: auth.me.user.id, email: email, password: password, name: name, token: auth.token)
    }

    func login(_ person: Person, device: String = "Another phone") async throws -> String {
        let res = try await client.send(.POST, APIPath.login, json: LoginRequest(email: person.email, password: person.password, deviceName: device))
        #expect(res.status == .ok, "login: \(res.text)")
        return try res.decode(AuthResponse.self).token
    }
}

extension FarmFixture {
    /// Pushes records as `person` and returns the results, one per record.
    @discardableResult
    func push(_ records: [SyncRecord], as person: Person, ids: [UUID]? = nil) async throws -> [MutationResult] {
        let mutations = records.enumerated().map { i, r in Mutation(id: ids?[i] ?? UUID(), record: r) }
        let res = try await client.send(.POST, APIPath.push(farm: farmId), token: person.token, json: PushRequest(mutations: mutations))
        #expect(res.status == .ok, "push: \(res.text)")
        return try res.decode(PushResponse.self).results
    }

    func push(_ record: SyncRecord, as person: Person) async throws -> MutationResult {
        try await push([record], as: person)[0]
    }

    func shift(for person: Person, start: Date, end: Date? = nil, notes: String = "", updatedAt: Date? = nil) -> Shift {
        Shift(userId: person.userId, farmId: farmId, start: start, end: end, notes: notes, rateCents: 1500, updatedAt: updatedAt ?? app.now)
    }
}

extension MutationResult {
    var isApplied: Bool { status == .applied }
}

extension FarmFixture {
    func pull(as person: Person, since: Int64 = 0, limit: Int? = nil) async throws -> PullResponse {
        var path = APIPath.pull(farm: farmId) + "?since=\(since)"
        if let limit { path += "&limit=\(limit)" }
        let res = try await client.send(.GET, path, token: person.token)
        #expect(res.status == .ok, "pull: \(res.text)")
        return try res.decode(PullResponse.self)
    }

    /// Pulls until `hasMore` is false.
    func pullAll(as person: Person, since: Int64 = 0) async throws -> [Change] {
        var changes: [Change] = []
        var cursor = since
        while true {
            let page = try await pull(as: person, since: cursor)
            changes += page.changes
            cursor = page.cursor
            if !page.hasMore { return changes }
        }
    }
}

extension FarmFixture {
    /// Stores a block straight into the farm's first field.
    func seedBlock(name: String = "1", rows: Int = 61, trees: Int = 10, column: Int = 0) async throws -> Block {
        let block = Block(fieldId: fieldId, name: name, gridRow: 0, gridColumn: column, rowCount: rows, treesPerRow: trees, updatedAt: app.now)
        try await RecordStore(db: app.db).save(.block(block), farm: farmId)
        return block
    }

    /// Clocks `person` in an hour ago and returns the open shift.
    func clockIn(_ person: Person, hoursAgo: Double = 1) async throws -> Shift {
        let shift = shift(for: person, start: app.now.addingTimeInterval(-hoursAgo * 3600))
        let result = try await push(.shift(shift), as: person)
        #expect(result.isApplied, "clock in: \(result.message ?? "")")
        return shift
    }

    func mark(_ block: Block, row: Int, tree: Int, on shift: Shift, season: UUID? = nil) -> TreeMark {
        TreeMark(seasonId: season ?? seasonId, tree: TreeRef(blockId: block.id, row: row, position: tree), shiftId: shift.id, userId: shift.userId, markedAt: app.now)
    }
}

extension FarmFixture {
    func seedNote(_ block: Block, row: Int, tree: Int, by person: Person, body: String = "Leaning") async throws -> TreeNote {
        let note = TreeNote(farmId: farmId, tree: TreeRef(blockId: block.id, row: row, position: tree), authorId: person.userId, authorName: person.name, body: body, createdAt: app.now)
        try await RecordStore(db: app.db).save(.treeNote(note), farm: farmId)
        return note
    }

    func farmRecord() async throws -> Farm {
        try #require(try await RecordStore(db: app.db).farm(farmId))
    }
}

/// A copy with `updatedAt` moved forward, as an edit on a device would have.
func edited<T>(_ value: T, by seconds: TimeInterval = 1, _ change: (inout T) -> Void) -> T where T: Any {
    var copy = value
    change(&copy)
    switch copy {
    case var b as Block: b.updatedAt = b.updatedAt.addingTimeInterval(seconds); return b as! T
    case var f as Field: f.updatedAt = f.updatedAt.addingTimeInterval(seconds); return f as! T
    case var f as Farm: f.updatedAt = f.updatedAt.addingTimeInterval(seconds); return f as! T
    case var s as Season: s.updatedAt = s.updatedAt.addingTimeInterval(seconds); return s as! T
    case var m as Member: m.updatedAt = m.updatedAt.addingTimeInterval(seconds); return m as! T
    case var n as TreeNote: n.updatedAt = n.updatedAt.addingTimeInterval(seconds); return n as! T
    case var m as TreeMark: m.updatedAt = m.updatedAt.addingTimeInterval(seconds); return m as! T
    case var s as Shift: s.updatedAt = s.updatedAt.addingTimeInterval(seconds); return s as! T
    default: return copy
    }
}
