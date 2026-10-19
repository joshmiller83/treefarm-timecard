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
