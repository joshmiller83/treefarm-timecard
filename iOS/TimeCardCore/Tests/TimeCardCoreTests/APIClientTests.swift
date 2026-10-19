import Foundation
import Testing
@testable import TimeCardCore

/// Answers URLSession requests from a handler registered for the request's host, so
/// tests running in parallel each get their own fake server.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Data?) throws -> (Int, [String: String], Data)
    private static let handlers = Locked<[String: Handler]>([:])

    static func register(host: String, _ handler: @escaping Handler) {
        handlers.withLock { $0[host] = handler }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host, let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, headers, data) = try handler(request, Self.body(of: request))
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

@Suite("API client")
struct APIClientTests {
    let host = "server-\(UUID().uuidString.lowercased()).test"
    let tokens = InMemoryTokenStore()
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

    @Test func logsInWithJSONAndNoToken() async throws {
        let auth = AuthResponse(token: "t-123", me: me)
        let seen = Locked<URLRequest?>(nil)
        let sent = Locked<Data?>(nil)
        MockURLProtocol.register(host: host) { request, body in
            seen.withLock { $0 = request }
            sent.withLock { $0 = body }
            return (200, ["Content-Type": "application/json"], json(auth))
        }
        try tokens.save("stale")
        let answer = try await client.login(LoginRequest(email: "josh@example.com", password: "pw", deviceName: "iPhone"))
        #expect(answer == auth)

        let request = try #require(seen.withLock { $0 })
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/auth/login")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONCoding.decoder().decode(LoginRequest.self, from: try #require(sent.withLock { $0 }))
        #expect(body.email == "josh@example.com")
    }

    @Test func sendsTheBearerTokenOnFarmRoutes() async throws {
        let seen = Locked<URLRequest?>(nil)
        MockURLProtocol.register(host: host) { request, _ in
            seen.withLock { $0 = request }
            return (200, [:], json(PullResponse(changes: [Change(seq: 7, record: .farm(f.farm))], cursor: 7, hasMore: false)))
        }
        try tokens.save("abc")
        let answer = try await client.pull(farmId: f.farmId, since: 5, limit: 500)
        #expect(answer.cursor == 7)
        #expect(answer.changes.first?.record == .farm(f.farm))

        let request = try #require(seen.withLock { $0 })
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/farms/\(f.farmId.uuidString)/sync/pull")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "since", value: "5")))
        #expect(query.contains(URLQueryItem(name: "limit", value: "500")))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func pushesMutations() async throws {
        let mutation = Mutation(record: .shift(f.shift()))
        let path = Locked<String?>(nil)
        MockURLProtocol.register(host: host) { request, body in
            path.withLock { $0 = request.url?.path }
            let pushed = try JSONCoding.decoder().decode(PushRequest.self, from: body ?? Data())
            return (200, [:], json(PushResponse(results: pushed.mutations.map { .applied($0.id, seq: 1) })))
        }
        let answer = try await client.push(farmId: f.farmId, PushRequest(mutations: [mutation]))
        #expect(answer.results == [.applied(mutation.id, seq: 1)])
        #expect(path.withLock { $0 } == "/v1/farms/\(f.farmId.uuidString)/sync/push")
    }

    @Test func logoutAcceptsAnEmptyAnswer() async throws {
        let seen = Locked<URLRequest?>(nil)
        MockURLProtocol.register(host: host) { request, _ in
            seen.withLock { $0 = request }
            return (204, [:], Data())
        }
        try tokens.save("abc")
        try await client.logout()
        #expect(seen.withLock { $0?.url?.path } == "/v1/auth/logout")
        #expect(seen.withLock { $0?.value(forHTTPHeaderField: "Authorization") } == "Bearer abc")
    }

    @Test func a401MeansSignedOut() async throws {
        MockURLProtocol.register(host: host) { _, _ in (401, [:], json(APIErrorBody(reason: "Your session ended. Sign in again."))) }
        await #expect(throws: APIError.unauthorized(reason: "Your session ended. Sign in again.")) {
            _ = try await client.me()
        }
    }

    @Test func a429CarriesTheWait() async throws {
        MockURLProtocol.register(host: host) { _, _ in
            (429, ["Retry-After": "900"], json(APIErrorBody(reason: "Too many tries. Try again in 15 minutes.")))
        }
        await #expect(throws: APIError.rateLimited(reason: "Too many tries. Try again in 15 minutes.", retryAfter: 900)) {
            _ = try await client.login(LoginRequest(email: "a@b.c", password: "x", deviceName: "d"))
        }
    }

    @Test func otherClientErrorsCarryTheServersReason() async throws {
        MockURLProtocol.register(host: host) { _, _ in (410, [:], json(APIErrorBody(reason: "That invite code has expired."))) }
        await #expect(throws: APIError.client(status: 410, reason: "That invite code has expired.")) {
            _ = try await client.register(RegisterRequest(inviteCode: "X", email: "a@b.c", password: "pw", displayName: "A", deviceName: "d"))
        }
    }

    @Test func serverErrorsWithoutJSONStillMap() async throws {
        MockURLProtocol.register(host: host) { _, _ in (502, ["Content-Type": "text/html"], Data("<html>Bad gateway</html>".utf8)) }
        await #expect(throws: APIError.server(status: 502, reason: APIError.serverTrouble)) {
            _ = try await client.me()
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost])
    func networkFailuresMeanOffline(code: URLError.Code) async throws {
        MockURLProtocol.register(host: host) { _, _ in throw URLError(code) }
        await #expect(throws: APIError.offline) {
            _ = try await client.me()
        }
    }

    @Test func undecodableAnswersAreReported() async throws {
        MockURLProtocol.register(host: host) { _, _ in (200, [:], Data("{}".utf8)) }
        do {
            _ = try await client.me()
            Issue.record("expected a decoding error")
        } catch let error as APIError {
            guard case .badResponse = error else { Issue.record("got \(error)"); return }
        }
    }

    @Test func messagesForPeople() {
        #expect(APIError.offline.userMessage == "You’re offline. Changes are saved on this phone and sync when you’re back online.")
        #expect(APIError.unauthorized(reason: "That email and password don’t match.").userMessage == "That email and password don’t match.")
        #expect(APIError.rateLimited(reason: "", retryAfter: 900).userMessage == "Too many tries. Try again in 15 minutes.")
        #expect(APIError.rateLimited(reason: "Locked for a bit.", retryAfter: 60).userMessage == "Locked for a bit.")
        #expect(APIError.client(status: 410, reason: "That invite code has expired.").userMessage == "That invite code has expired.")
        #expect(APIError.server(status: 500, reason: APIError.serverTrouble).userMessage == APIError.serverTrouble)
    }

    @Test func retryableErrors() {
        #expect(APIError.offline.isRetryable)
        #expect(APIError.server(status: 503, reason: "").isRetryable)
        #expect(APIError.rateLimited(reason: "", retryAfter: 5).isRetryable)
        #expect(!APIError.unauthorized(reason: "").isRetryable)
        #expect(!APIError.client(status: 400, reason: "").isRetryable)
    }
}
