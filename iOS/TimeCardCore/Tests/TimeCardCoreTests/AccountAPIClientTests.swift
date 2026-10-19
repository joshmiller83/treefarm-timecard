import Foundation
import Testing
@testable import TimeCardCore

/// The account and admin routes in docs/api.md, as `URLSessionAPIClient` sends them.
@Suite("API client: account and admin")
struct AccountAPIClientTests {
    let host = "server-\(UUID().uuidString.lowercased()).test"
    let tokens = InMemoryTokenStore(token: "abc")
    let f = Fixtures()

    var client: URLSessionAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSessionAPIClient(baseURL: URL(string: "https://\(host)")!, tokens: tokens, session: URLSession(configuration: config))
    }

    func json<T: Encodable>(_ value: T) -> Data { try! JSONCoding.encoder().encode(value) }

    var me: MeResponse {
        MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [f.member])
    }

    /// Answers every request with `answer` and keeps what was sent.
    func capture(status: Int = 200, headers: [String: String] = [:], _ answer: Data = Data()) -> Locked<[(URLRequest, Data?)]> {
        let seen = Locked<[(URLRequest, Data?)]>([])
        MockURLProtocol.register(host: host) { request, body in
            seen.withLock { $0.append((request, body)) }
            return (status, headers, answer)
        }
        return seen
    }

    func only(_ seen: Locked<[(URLRequest, Data?)]>) throws -> (request: URLRequest, body: Data?) {
        let all = seen.withLock { $0 }
        try #require(all.count == 1)
        return all[0]
    }

    // MARK: Account

    @Test func updateMeSendsAPatchAndReturnsTheNewMe() async throws {
        var renamed = me
        renamed.user.displayName = "Joshua"
        let seen = capture(json(renamed))
        let answer = try await client.updateMe(UpdateMeRequest(displayName: "Joshua"))
        #expect(answer == renamed)

        let (request, body) = try only(seen)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        let sent = try JSONCoding.decoder().decode(UpdateMeRequest.self, from: try #require(body))
        #expect(sent == UpdateMeRequest(displayName: "Joshua"))
    }

    @Test func deleteAccountSendsThePassword() async throws {
        let seen = capture(status: 204)
        try await client.deleteAccount(DeleteAccountRequest(password: "right horse"))

        let (request, body) = try only(seen)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(try JSONCoding.decoder().decode(DeleteAccountRequest.self, from: try #require(body)).password == "right horse")
    }

    @Test func deleteAccountWithTheWrongPasswordCarriesTheReason() async throws {
        _ = capture(status: 403, json(APIErrorBody(reason: "That password isn’t right.")))
        await #expect(throws: APIError.client(status: 403, reason: "That password isn’t right.")) {
            try await client.deleteAccount(DeleteAccountRequest(password: "wrong"))
        }
    }

    @Test func listsSessions() async throws {
        let sessions = [
            SessionInfo(id: UUID(), deviceName: "Josh’s iPhone", createdAt: Fixtures.t0, lastUsedAt: Fixtures.t0.addingTimeInterval(60), isCurrent: true),
            SessionInfo(id: UUID(), deviceName: "Office Mac", createdAt: Fixtures.t0, lastUsedAt: Fixtures.t0, isCurrent: false),
        ]
        let seen = capture(json(sessions))
        #expect(try await client.sessions() == sessions)

        let (request, _) = try only(seen)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/me/sessions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func revokesASession() async throws {
        let id = UUID()
        let seen = capture(status: 204)
        try await client.revokeSession(id: id)

        let (request, _) = try only(seen)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/me/sessions/\(id.uuidString)")
    }

    // MARK: Admin

    @Test func listsInvites() async throws {
        let invites = [InviteInfo(id: UUID(), role: .worker, note: "New trimmer", createdAt: Fixtures.t0, expiresAt: Fixtures.t0.addingTimeInterval(7 * 86400))]
        let seen = capture(json(invites))
        #expect(try await client.invites(farmId: f.farmId) == invites)

        let (request, _) = try only(seen)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/farms/\(f.farmId.uuidString)/invites")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func createsAnInvite() async throws {
        let made = InviteInfo(id: UUID(), role: .admin, note: "Liz", createdAt: Fixtures.t0, expiresAt: Fixtures.t0.addingTimeInterval(7 * 86400),
                              code: "K7Q4-M2XP-9R")
        let seen = capture(json(made))
        let answer = try await client.createInvite(farmId: f.farmId, CreateInviteRequest(role: .admin, note: "Liz"))
        #expect(answer == made)
        #expect(answer.code == "K7Q4-M2XP-9R")

        let (request, body) = try only(seen)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/farms/\(f.farmId.uuidString)/invites")
        #expect(try JSONCoding.decoder().decode(CreateInviteRequest.self, from: try #require(body)) == CreateInviteRequest(role: .admin, note: "Liz"))
    }

    @Test func revokesAnInvite() async throws {
        let id = UUID()
        let seen = capture(status: 204)
        try await client.revokeInvite(farmId: f.farmId, id: id)

        let (request, _) = try only(seen)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/farms/\(f.farmId.uuidString)/invites/\(id.uuidString)")
    }

    @Test func asksForAResetCode() async throws {
        let reset = ResetCodeResponse(code: "ABCD-EFGH-JK", expiresAt: Fixtures.t0.addingTimeInterval(86400))
        let seen = capture(json(reset))
        #expect(try await client.resetCode(farmId: f.farmId, userId: f.otherUserId) == reset)

        let (request, _) = try only(seen)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/farms/\(f.farmId.uuidString)/members/\(f.otherUserId.uuidString)/reset")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func removesAMember() async throws {
        let seen = capture(status: 204)
        try await client.removeMember(farmId: f.farmId, userId: f.otherUserId)

        let (request, _) = try only(seen)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/farms/\(f.farmId.uuidString)/members/\(f.otherUserId.uuidString)")
    }

    @Test func workersAreToldOnlyAnAdminCan() async throws {
        _ = capture(status: 403, json(APIErrorBody(reason: "Only an admin can do that.")))
        await #expect(throws: APIError.client(status: 403, reason: "Only an admin can do that.")) {
            _ = try await client.invites(farmId: f.farmId)
        }
    }

    // MARK: Export

    @Test func exportsCSVAsRawBytes() async throws {
        let csv = Data("Name,Date,In,Out,Breaks,Hours,Notes\r\nJosh,2025-10-09,9:46 AM,,0,1.00,\r\n".utf8)
        let seen = capture(headers: ["Content-Type": "text/csv; charset=utf-8"], csv)
        let from = Date(timeIntervalSince1970: 1_760_000_000.123)
        let to = Date(timeIntervalSince1970: 1_760_604_800)
        let answer = try await client.exportCSV(farmId: f.farmId, from: from, to: to, userId: f.userId)
        #expect(answer == csv)

        let (request, _) = try only(seen)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/farms/\(f.farmId.uuidString)/export.csv")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/csv")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(Set(query) == [
            URLQueryItem(name: "from", value: "1760000000123"),
            URLQueryItem(name: "to", value: "1760604800000"),
            URLQueryItem(name: "userId", value: f.userId.uuidString),
        ])
    }

    @Test func exportLeavesOutWhatIsntAsked() async throws {
        let seen = capture(Data("Name,Date,In,Out,Breaks,Hours,Notes\r\n".utf8))
        _ = try await client.exportCSV(farmId: f.farmId)

        let (request, _) = try only(seen)
        #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == nil)
    }

    @Test func exportErrorsStillReadTheJSONReason() async throws {
        _ = capture(status: 403, json(APIErrorBody(reason: "You can only export your own hours.")))
        await #expect(throws: APIError.client(status: 403, reason: "You can only export your own hours.")) {
            _ = try await client.exportCSV(farmId: f.farmId, userId: f.otherUserId)
        }
    }
}
