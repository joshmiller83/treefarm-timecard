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
            return "You're offline. Changes are saved on this phone and sync when you're back online."
        case .unauthorized(let reason):
            return reason.isEmpty ? "Your sign-in has ended. Sign in again." : reason
        case .rateLimited(let reason, let retryAfter):
            if !reason.isEmpty { return reason }
            guard let retryAfter, retryAfter > 60 else { return "Too many tries. Try again in a minute." }
            return "Too many tries. Try again in \(Int((retryAfter / 60).rounded(.up))) minutes."
        case .client(_, let reason), .server(_, let reason):
            return reason.isEmpty ? Self.serverTrouble : reason
        case .badResponse:
            return "The server sent an answer this app doesn't understand. Check for an app update."
        case .transport(let detail):
            return "Couldn't reach the server (\(detail))."
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

    // MARK: Plumbing

    private struct Empty: Encodable {}

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

    private func data(_ method: String, _ path: String, query: [URLQueryItem], body: Data?, authenticated: Bool) async throws -> Data {
        let relative = String(path.drop(while: { $0 == "/" }))
        var components = URLComponents(url: baseURL.appendingPathComponent(relative), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
