import Foundation

/// What the app asks of the server. `URLSessionAPIClient` talks HTTP;
/// `StubAPIClient` is an in-memory server for tests and UI-test runs.
/// Authenticated calls read the bearer token from the client's `TokenStore`.
public protocol APIClient: Sendable {
    func login(_ request: LoginRequest) async throws -> AuthResponse
    func register(_ request: RegisterRequest) async throws -> AuthResponse
    func resetPassword(_ request: ResetPasswordRequest) async throws -> AuthResponse
    func logout() async throws
    func me() async throws -> MeResponse
    func push(farmId: UUID, _ request: PushRequest) async throws -> PushResponse
    func pull(farmId: UUID, since: Int64, limit: Int) async throws -> PullResponse

    // MARK: Your account

    /// `PATCH /v1/me`: a new name, or a new password (with the current one).
    func updateMe(_ request: UpdateMeRequest) async throws -> MeResponse
    /// `DELETE /v1/me`: deletes the login. Shifts stay with the farm under the person's name.
    func deleteAccount(_ request: DeleteAccountRequest) async throws
    /// The devices signed in to this account, newest use first.
    func sessions() async throws -> [SessionInfo]
    func revokeSession(id: UUID) async throws

    // MARK: Admin (the server refuses workers)

    /// Every invite on the farm, newest first, without codes.
    func invites(farmId: UUID) async throws -> [InviteInfo]
    /// A new single-use invite; the answer is the only time its `code` is shown.
    func createInvite(farmId: UUID, _ request: CreateInviteRequest) async throws -> InviteInfo
    func revokeInvite(farmId: UUID, id: UUID) async throws
    /// A single-use password-reset code for someone on the farm (24 hours).
    func resetCode(farmId: UUID, userId: UUID) async throws -> ResetCodeResponse
    /// Sets the person's `removedAt`; their hours stay. The change comes down with the next pull.
    func removeMember(farmId: UUID, userId: UUID) async throws

    // MARK: Export

    /// Shifts that clock in within `[from, to)` as CSV. Workers get their own only;
    /// admins anyone's (`userId`), or everyone's when it's nil.
    func exportCSV(farmId: UUID, from: Date?, to: Date?, userId: UUID?) async throws -> Data
}

/// Why a call failed, sorted the way the app reacts to it.
public enum APIError: Error, Equatable, Sendable {
    /// No network, or the server couldn't be reached in time. Try again later.
    case offline
    /// 401: the token is missing, expired or revoked. Sign in again; keep local work.
    case unauthorized(reason: String)
    /// 429: too many tries (login lockout). `retryAfter` is in seconds when the server says.
    case rateLimited(reason: String, retryAfter: TimeInterval?)
    /// Any other 4xx, with the server's sentence (an expired invite, a bad reset code, ...).
    case client(status: Int, reason: String)
    /// 5xx, including a Cloudflare error page when the server is down.
    case server(status: Int, reason: String)
    /// The answer wasn't what the API promises.
    case badResponse(String)
    /// A network failure that isn't about being offline (TLS, a bad URL, ...).
    case transport(String)

    public static let serverTrouble = "The server had a problem. Try again in a minute."

    /// Worth retrying on its own after a pause.
    public var isRetryable: Bool {
        switch self {
        case .offline, .server, .rateLimited, .transport: true
        case .unauthorized, .client, .badResponse: false
        }
    }

    /// A sentence to show or speak.
    public var userMessage: String {
        switch self {
        case .offline:
            return "You’re offline. Changes are saved on this phone and sync when you’re back online."
        case .unauthorized(let reason):
            return reason.isEmpty ? "Your sign-in has ended. Sign in again." : reason
        case .rateLimited(let reason, let retryAfter):
            if !reason.isEmpty { return reason }
            guard let retryAfter, retryAfter > 60 else { return "Too many tries. Try again in a minute." }
            return "Too many tries. Try again in \(Int((retryAfter / 60).rounded(.up))) minutes."
        case .client(_, let reason), .server(_, let reason):
            return reason.isEmpty ? Self.serverTrouble : reason
        case .badResponse:
            return "The server sent an answer this app doesn’t understand. Check for an app update."
        case .transport(let detail):
            return "Couldn’t reach the server (\(detail))."
        }
    }

    /// Sorts a `URLSession` failure.
    public static func from(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            return .offline
        default:
            return .transport(error.localizedDescription)
        }
    }
}

/// The HTTP client for the Vapor server. JSON both ways via `JSONCoding`.
public struct URLSessionAPIClient: APIClient {
    public let baseURL: URL
    private let tokens: any TokenStore
    private let session: URLSession

    public init(baseURL: URL = TimeCardCore.defaultServerURL, tokens: any TokenStore, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session ?? URLSession(configuration: Self.defaultConfiguration)
    }

    static var defaultConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }

    public func login(_ request: LoginRequest) async throws -> AuthResponse {
        try await send("POST", APIPath.login, body: request, authenticated: false)
    }

    public func register(_ request: RegisterRequest) async throws -> AuthResponse {
        try await send("POST", APIPath.register, body: request, authenticated: false)
    }

    public func resetPassword(_ request: ResetPasswordRequest) async throws -> AuthResponse {
        try await send("POST", APIPath.resetPassword, body: request, authenticated: false)
    }

    public func logout() async throws {
        _ = try await data("POST", APIPath.logout, query: [], body: nil, authenticated: true)
    }

    public func me() async throws -> MeResponse {
        try await send("GET", APIPath.me, body: Optional<Empty>.none)
    }

    public func push(farmId: UUID, _ request: PushRequest) async throws -> PushResponse {
        try await send("POST", APIPath.push(farm: farmId), body: request)
    }

    public func pull(farmId: UUID, since: Int64, limit: Int) async throws -> PullResponse {
        try await send("GET", APIPath.pull(farm: farmId), query: [
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "limit", value: String(limit)),
        ], body: Optional<Empty>.none)
    }

    // MARK: Your account

    public func updateMe(_ request: UpdateMeRequest) async throws -> MeResponse {
        try await send("PATCH", APIPath.me, body: request)
    }

    public func deleteAccount(_ request: DeleteAccountRequest) async throws {
        try await sendNoAnswer("DELETE", APIPath.me, body: request)
    }

    public func sessions() async throws -> [SessionInfo] {
        try await send("GET", APIPath.sessions, body: Optional<Empty>.none)
    }

    public func revokeSession(id: UUID) async throws {
        try await sendNoAnswer("DELETE", APIPath.session(id), body: Optional<Empty>.none)
    }

    // MARK: Admin

    public func invites(farmId: UUID) async throws -> [InviteInfo] {
        try await send("GET", APIPath.invites(farm: farmId), body: Optional<Empty>.none)
    }

    public func createInvite(farmId: UUID, _ request: CreateInviteRequest) async throws -> InviteInfo {
        try await send("POST", APIPath.invites(farm: farmId), body: request)
    }

    public func revokeInvite(farmId: UUID, id: UUID) async throws {
        try await sendNoAnswer("DELETE", APIPath.invite(farm: farmId, id: id), body: Optional<Empty>.none)
    }

    public func resetCode(farmId: UUID, userId: UUID) async throws -> ResetCodeResponse {
        try await send("POST", APIPath.memberReset(farm: farmId, user: userId), body: Optional<Empty>.none)
    }

    public func removeMember(farmId: UUID, userId: UUID) async throws {
        try await sendNoAnswer("DELETE", APIPath.member(farm: farmId, user: userId), body: Optional<Empty>.none)
    }

    // MARK: Export

    public func exportCSV(farmId: UUID, from: Date? = nil, to: Date? = nil, userId: UUID? = nil) async throws -> Data {
        var query: [URLQueryItem] = []
        if let from { query.append(URLQueryItem(name: "from", value: String(Self.millis(from)))) }
        if let to { query.append(URLQueryItem(name: "to", value: String(Self.millis(to)))) }
        if let userId { query.append(URLQueryItem(name: "userId", value: userId.uuidString)) }
        return try await data("GET", APIPath.exportCSV(farm: farmId), query: query, body: nil, authenticated: true, accept: "text/csv")
    }

    // MARK: Plumbing

    private struct Empty: Encodable {}

    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private func send<Body: Encodable, Answer: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Body?, authenticated: Bool = true
    ) async throws -> Answer {
        let encoded = try body.map { try JSONCoding.encoder().encode($0) }
        let data = try await data(method, path, query: query, body: encoded, authenticated: authenticated)
        do {
            return try JSONCoding.decoder().decode(Answer.self, from: data)
        } catch {
            throw APIError.badResponse("\(Answer.self): \(error)")
        }
    }

    /// For routes that answer 204 No Content.
    private func sendNoAnswer<Body: Encodable>(_ method: String, _ path: String, body: Body?) async throws {
        let encoded = try body.map { try JSONCoding.encoder().encode($0) }
        _ = try await data(method, path, query: [], body: encoded, authenticated: true)
    }

    private func data(_ method: String, _ path: String, query: [URLQueryItem], body: Data?, authenticated: Bool,
                      accept: String = "application/json") async throws -> Data {
        let relative = String(path.drop(while: { $0 == "/" }))
        var components = URLComponents(url: baseURL.appendingPathComponent(relative), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token = try? tokens.read() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.from(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse("Not an HTTP answer") }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data, headers: http) }
        return data
    }

    static func error(status: Int, data: Data, headers: HTTPURLResponse) -> APIError {
        let reason = (try? JSONCoding.decoder().decode(APIErrorBody.self, from: data))?.reason
        switch status {
        case 401:
            return .unauthorized(reason: reason ?? "")
        case 429:
            let retryAfter = headers.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            return .rateLimited(reason: reason ?? "", retryAfter: retryAfter)
        case 400..<500:
            return .client(status: status, reason: reason ?? "")
        default:
            return .server(status: status, reason: reason ?? APIError.serverTrouble)
        }
    }
}
