import Foundation

// Request and response bodies for the HTTP API. docs/api.md lists the routes.
// Everything is JSON made with `JSONCoding`, so dates are milliseconds since 1970.

public enum APIPath {
    public static let version = "v1"

    public static let health = "/health"
    public static let login = "/v1/auth/login"
    public static let register = "/v1/auth/register"
    public static let logout = "/v1/auth/logout"
    public static let resetPassword = "/v1/auth/reset"
    public static let me = "/v1/me"
    public static let sessions = "/v1/me/sessions"

    public static func session(_ id: UUID) -> String { "/v1/me/sessions/\(id.uuidString)" }
    public static func push(farm: UUID) -> String { "/v1/farms/\(farm.uuidString)/sync/push" }
    public static func pull(farm: UUID) -> String { "/v1/farms/\(farm.uuidString)/sync/pull" }
    public static func invites(farm: UUID) -> String { "/v1/farms/\(farm.uuidString)/invites" }
    public static func invite(farm: UUID, id: UUID) -> String { "/v1/farms/\(farm.uuidString)/invites/\(id.uuidString)" }
    public static func memberReset(farm: UUID, user: UUID) -> String { "/v1/farms/\(farm.uuidString)/members/\(user.uuidString)/reset" }
    public static func member(farm: UUID, user: UUID) -> String { "/v1/farms/\(farm.uuidString)/members/\(user.uuidString)" }
    public static func exportCSV(farm: UUID) -> String { "/v1/farms/\(farm.uuidString)/export.csv" }
}

public struct LoginRequest: Codable, Hashable, Sendable {
    public var email: String
    public var password: String
    /// Shown in the session list, e.g. "Josh's iPhone".
    public var deviceName: String

    public init(email: String, password: String, deviceName: String) {
        self.email = email
        self.password = password
        self.deviceName = deviceName
    }
}

public struct RegisterRequest: Codable, Hashable, Sendable {
    public var inviteCode: String
    public var email: String
    public var password: String
    public var displayName: String
    public var deviceName: String

    public init(inviteCode: String, email: String, password: String, displayName: String, deviceName: String) {
        self.inviteCode = inviteCode
        self.email = email
        self.password = password
        self.displayName = displayName
        self.deviceName = deviceName
    }
}

/// An admin gives a reset code to someone who forgot their password (there's no email service).
public struct ResetPasswordRequest: Codable, Hashable, Sendable {
    public var email: String
    public var resetCode: String
    public var newPassword: String
    public var deviceName: String

    public init(email: String, resetCode: String, newPassword: String, deviceName: String) {
        self.email = email
        self.resetCode = resetCode
        self.newPassword = newPassword
        self.deviceName = deviceName
    }
}

/// Answer to login, register and reset. The token goes in `Authorization: Bearer <token>`.
public struct AuthResponse: Codable, Hashable, Sendable {
    public var token: String
    public var me: MeResponse

    public init(token: String, me: MeResponse) {
        self.token = token
        self.me = me
    }
}

public struct MeResponse: Codable, Hashable, Sendable {
    public var user: UserProfile
    public var farms: [Farm]
    public var memberships: [Member]

    public init(user: UserProfile, farms: [Farm], memberships: [Member]) {
        self.user = user
        self.farms = farms
        self.memberships = memberships
    }
}

public struct UpdateMeRequest: Codable, Hashable, Sendable {
    public var displayName: String?
    /// Needed only to change the password.
    public var currentPassword: String?
    public var newPassword: String?

    public init(displayName: String? = nil, currentPassword: String? = nil, newPassword: String? = nil) {
        self.displayName = displayName
        self.currentPassword = currentPassword
        self.newPassword = newPassword
    }
}

public struct DeleteAccountRequest: Codable, Hashable, Sendable {
    public var password: String

    public init(password: String) {
        self.password = password
    }
}

public struct SessionInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var deviceName: String
    public var createdAt: Date
    public var lastUsedAt: Date
    public var isCurrent: Bool

    public init(id: UUID, deviceName: String, createdAt: Date, lastUsedAt: Date, isCurrent: Bool) {
        self.id = id
        self.deviceName = deviceName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isCurrent = isCurrent
    }
}

public struct CreateInviteRequest: Codable, Hashable, Sendable {
    public var role: Role
    /// Optional: who it's for, so the admin remembers.
    public var note: String

    public init(role: Role, note: String = "") {
        self.role = role
        self.note = note
    }
}

public struct InviteInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var role: Role
    public var note: String
    public var createdAt: Date
    public var expiresAt: Date
    public var usedAt: Date?
    /// Present only in the answer to the request that made it; the server keeps a hash.
    public var code: String?

    public init(id: UUID, role: Role, note: String, createdAt: Date, expiresAt: Date, usedAt: Date? = nil, code: String? = nil) {
        self.id = id
        self.role = role
        self.note = note
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.usedAt = usedAt
        self.code = code
    }
}

public struct ResetCodeResponse: Codable, Hashable, Sendable {
    public var code: String
    public var expiresAt: Date

    public init(code: String, expiresAt: Date) {
        self.code = code
        self.expiresAt = expiresAt
    }
}

public struct HealthResponse: Codable, Hashable, Sendable {
    public var status: String
    public var version: String

    public init(status: String, version: String) {
        self.status = status
        self.version = version
    }
}

/// The body of every error answer. `reason` is a sentence the app can show as-is.
public struct APIErrorBody: Codable, Hashable, Sendable {
    public var error: Bool
    public var reason: String

    public init(reason: String) {
        self.error = true
        self.reason = reason
    }
}
