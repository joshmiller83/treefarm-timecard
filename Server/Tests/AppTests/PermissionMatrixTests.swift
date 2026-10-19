import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

/// Every route against every kind of caller: nobody, a worker, an admin, an
/// admin of another farm, and someone removed from this farm (but still on another).
@Suite("Permissions matrix")
struct PermissionMatrixTests {
    enum Persona: String, CaseIterable {
        case anonymous, worker, admin, otherFarm, removed
    }

    struct Check {
        let method: HTTPMethod
        let path: String
        let body: (any Encodable)?
        let expect: [Persona: HTTPStatus]

        init(_ method: HTTPMethod, _ path: String, body: (any Encodable)? = nil, _ expect: [Persona: HTTPStatus]) {
            self.method = method
            self.path = path
            self.body = body
            self.expect = expect
        }
    }

    /// Answers for a farm route: members in, everyone else out.
    static func farm(_ ok: HTTPStatus, worker: HTTPStatus? = nil) -> [Persona: HTTPStatus] {
        [.anonymous: .unauthorized, .worker: worker ?? ok, .admin: ok, .otherFarm: .forbidden, .removed: .forbidden]
    }

    /// Answers for an account route: any signed-in person.
    static func account(_ ok: HTTPStatus) -> [Persona: HTTPStatus] {
        [.anonymous: .unauthorized, .worker: ok, .admin: ok, .otherFarm: ok, .removed: ok]
    }

    static func everyone(_ status: HTTPStatus) -> [Persona: HTTPStatus] {
        Dictionary(uniqueKeysWithValues: Persona.allCases.map { ($0, status) })
    }

    @Test func everyRouteAnswersEachCallerAsDocumented() async throws {
        // All in-memory requests share one client address; this test makes many sign-in calls.
        try await withTestApp(adjust: { $0.ipAttempts = 1000 }) { app, _ in
            let farm = try await FarmFixture.make(app)
            let other = try await FarmFixture.make(app, farmName: "Other", adminEmail: "other@example.com")
            let worker = try await farm.join("Sam")
            let target = try await farm.join("Alex")
            // Riley is on both farms, then removed from this one.
            let riley = try await other.join("Riley")
            let rejoin = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: try await farm.inviteCode(), email: riley.email, password: riley.password, displayName: "Riley", deviceName: "p"))
            #expect(rejoin.status == .ok)
            #expect(try await app.client2.send(.DELETE, APIPath.member(farm: farm.farmId, user: riley.userId), token: farm.admin.token).status == .noContent)

            let tokens: [Persona: String?] = [.anonymous: nil, .worker: worker.token, .admin: farm.admin.token, .otherFarm: other.admin.token, .removed: riley.token]
            let f = farm.farmId
            let missing = UUID()
            let checks: [Check] = [
                Check(.GET, APIPath.health, Self.everyone(.ok)),
                Check(.GET, "/", Self.everyone(.found)),
                Check(.POST, APIPath.login, body: LoginRequest(email: "ghost@example.com", password: "wrong wrong", deviceName: "x"), Self.everyone(.unauthorized)),
                Check(.POST, APIPath.register, body: RegisterRequest(inviteCode: "NOPE-NOPE-NO", email: "n@example.com", password: "long enough", displayName: "N", deviceName: "x"), Self.everyone(.badRequest)),
                Check(.POST, APIPath.resetPassword, body: ResetPasswordRequest(email: "phantom@example.com", resetCode: "NOPE-NOPE-NO", newPassword: "long enough", deviceName: "x"), Self.everyone(.badRequest)),
                Check(.GET, APIPath.me, Self.account(.ok)),
                Check(.PATCH, APIPath.me, body: UpdateMeRequest(), Self.account(.ok)),
                Check(.GET, APIPath.sessions, Self.account(.ok)),
                Check(.DELETE, APIPath.session(missing), Self.account(.notFound)),
                Check(.DELETE, APIPath.me, body: DeleteAccountRequest(password: "wrong wrong"), Self.account(.forbidden)),
                Check(.POST, APIPath.push(farm: f), body: PushRequest(mutations: []), Self.farm(.ok)),
                Check(.GET, APIPath.pull(farm: f), Self.farm(.ok)),
                Check(.GET, APIPath.exportCSV(farm: f), Self.farm(.ok)),
                Check(.GET, APIPath.invites(farm: f), Self.farm(.ok, worker: .forbidden)),
                Check(.POST, APIPath.invites(farm: f), body: CreateInviteRequest(role: .worker), Self.farm(.ok, worker: .forbidden)),
                Check(.DELETE, APIPath.invite(farm: f, id: missing), Self.farm(.notFound, worker: .forbidden)),
                Check(.POST, APIPath.memberReset(farm: f, user: target.userId), Self.farm(.ok, worker: .forbidden)),
                Check(.DELETE, APIPath.member(farm: f, user: missing), Self.farm(.notFound, worker: .forbidden)),
                // Last, since it ends the session.
                Check(.POST, APIPath.logout, Self.account(.noContent)),
            ]

            for check in checks {
                for persona in Persona.allCases {
                    let expected = try #require(check.expect[persona])
                    let token = tokens[persona] ?? nil
                    let res: TestResponse
                    if let body = check.body {
                        res = try await app.client2.send(check.method, check.path, token: token, json: AnyEncodable(body))
                    } else {
                        res = try await app.client2.send(check.method, check.path, token: token)
                    }
                    #expect(res.status == expected, "\(check.method) \(check.path) as \(persona.rawValue): \(res.text)")
                }
            }
        }
    }

    @Test func whoMayPushWhat() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let alex = try await farm.join("Alex")
            let block = try await farm.seedBlock()
            let alexShift = try await farm.clockIn(alex)
            let alexMark = farm.mark(block, row: 0, tree: 0, on: alexShift)
            try await farm.push(.treeMark(alexMark), as: alex)
            let alexNote = try await farm.seedNote(block, row: 1, tree: 1, by: alex)
            let store = RecordStore(db: app.db)
            let alexMember = try #require(try await store.member(alex.userId, farm: farm.farmId))
            let farmRecord = try await farm.farmRecord()
            let field = try #require(try await store.field(farm.fieldId, farm: farm.farmId))
            let season = try #require(try await store.season(farm.seasonId, farm: farm.farmId))

            // Changes to other people's things or to the farm's layout: workers no, admins yes.
            let records: [(String, SyncRecord)] = [
                ("farm", .farm(edited(farmRecord) { $0.name = "Renamed" })),
                ("season", .season(edited(season) { $0.name = "This year" })),
                ("field", .field(edited(field) { $0.name = "Home field" })),
                ("block", .block(edited(block) { $0.name = "One" })),
                ("member", .member(edited(alexMember) { $0.rateCents = 2500 })),
                ("shift", .shift(edited(alexShift) { $0.notes = "Edited" })),
                ("treeMark", .treeMark(edited(alexMark) { $0.deletedAt = clock.now })),
                ("treeNote", .treeNote(edited(alexNote) { $0.body = "Edited" })),
            ]
            for (name, record) in records {
                let asWorker = try await farm.push(record, as: sam)
                #expect(asWorker.reason == .forbidden, "worker pushing \(name)")
                let asAdmin = try await farm.push(record, as: farm.admin)
                #expect(asAdmin.isApplied, "admin pushing \(name): \(asAdmin.message ?? "")")
            }
        }
    }
}

/// Lets the matrix hold bodies of different types.
struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}
