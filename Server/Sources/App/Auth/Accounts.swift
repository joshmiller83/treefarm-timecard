import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// Input rules and shared steps for the account routes.
enum Accounts {
    static let sessionLifetime: TimeInterval = 90 * 24 * 3600
    static let passwordLength = 8...200

    static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func validEmail(_ raw: String) throws -> String {
        let email = normalizeEmail(raw)
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard email.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !email.contains(where: \.isWhitespace)
        else { throw Abort(.badRequest, reason: "That doesn't look like an email address.") }
        return email
    }

    static func validPassword(_ password: String) throws -> String {
        guard password.count >= passwordLength.lowerBound else {
            throw Abort(.badRequest, reason: "Use at least 8 characters for your password.")
        }
        guard password.count <= passwordLength.upperBound else {
            throw Abort(.badRequest, reason: "That password is too long.")
        }
        return password
    }

    static func validName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Abort(.badRequest, reason: "Please enter your name.") }
        guard name.count <= Limits.name else { throw Abort(.badRequest, reason: "Names can be up to \(Limits.name) characters.") }
        return name
    }

    static func deviceName(_ raw: String) -> String {
        let name = Limits.clampName(raw)
        return name.isEmpty ? "Unknown device" : name
    }

    /// Starts a session and returns its token. Only the token's hash is kept.
    static func startSession(userId: UUID, deviceName: String, on db: any Database, now: Date) async throws -> String {
        let token = Codes.token()
        let session = SessionModel(userId: userId, tokenHash: Codes.sha256Hex(token), deviceName: Self.deviceName(deviceName), now: now, lifetime: sessionLifetime)
        try await session.create(on: db)
        return token
    }

    static func revokeSessions(of userId: UUID, except keep: UUID? = nil, on db: any Database, now: Date) async throws {
        let query = SessionModel.query(on: db)
            .filter(\.$userId == userId)
            .filter(\.$revokedAt == nil)
        if let keep { query.filter(\.$id != keep) }
        try await query.set(\.$revokedAt, to: now).update()
    }

    /// The user, their current farms and their own (unredacted) memberships.
    static func me(_ user: UserModel, on db: any Database) async throws -> MeResponse {
        let store = RecordStore(db: db)
        let memberships = try await store.activeMemberships(of: user.id!)
        var farms: [Farm] = []
        for m in memberships {
            if let farm = try await store.farm(m.farmId) { farms.append(farm) }
        }
        return MeResponse(user: user.profile, farms: farms, memberships: memberships)
    }

    static func authResponse(_ user: UserModel, token: String, on db: any Database) async throws -> AuthResponse {
        AuthResponse(token: token, me: try await me(user, on: db))
    }
}

/// Who is calling, set by `BearerAuth`.
struct AuthContext: Sendable {
    let user: UserModel
    let session: SessionModel

    var userId: UUID { user.id! }
}

extension Request {
    private struct AuthKey: StorageKey { typealias Value = AuthContext }

    var authContext: AuthContext? {
        get { storage[AuthKey.self] }
        set { storage[AuthKey.self] = newValue }
    }

    func requireAuth() throws -> AuthContext {
        guard let ctx = authContext else { throw Abort(.unauthorized, reason: "Please sign in again.") }
        return ctx
    }
}

/// Checks `Authorization: Bearer <token>` against live sessions and slides the
/// 90-day expiry forward on use (at most once a minute, to spare writes).
struct BearerAuth: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let token = req.headers.bearerAuthorization?.token, !token.isEmpty else {
            throw Abort(.unauthorized, reason: "Please sign in again.")
        }
        let now = req.now
        guard let session = try await SessionModel.query(on: req.db)
            .filter(\.$tokenHash == Codes.sha256Hex(token))
            .filter(\.$revokedAt == nil)
            .first(),
            session.expiresAt > now,
            let user = try await UserModel.find(session.userId, on: req.db)
        else {
            throw Abort(.unauthorized, reason: "Please sign in again.")
        }
        if now.timeIntervalSince(session.lastUsedAt) > 60 {
            session.lastUsedAt = now
            session.expiresAt = now.addingTimeInterval(Accounts.sessionLifetime)
            try await session.save(on: req.db)
        }
        req.authContext = AuthContext(user: user, session: session)
        return try await next.respond(to: req)
    }
}
