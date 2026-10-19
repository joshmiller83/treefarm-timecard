import Fluent
import Foundation

// This file doesn't import TreeFarmKit: its `Field` type would hide Fluent's
// `@Field` wrapper. Conversions to Kit types live in Models+Kit.swift.

// Server-only tables. Synced data (farms, members, shifts, marks, ...) lives in
// `records` as JSON; see RecordModel.

final class UserModel: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    /// Always stored lower-cased, so the unique index is case-insensitive in effect.
    @Field(key: "email") var email: String
    @Field(key: "display_name") var displayName: String
    @Field(key: "password_hash") var passwordHash: String
    @Field(key: "created_at") var createdAt: Date

    init() {}

    init(id: UUID? = nil, email: String, displayName: String, passwordHash: String, createdAt: Date) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.passwordHash = passwordHash
        self.createdAt = createdAt
    }
}

final class SessionModel: Model, @unchecked Sendable {
    static let schema = "sessions"

    @ID(key: .id) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "token_hash") var tokenHash: String
    @Field(key: "device_name") var deviceName: String
    @Field(key: "created_at") var createdAt: Date
    @Field(key: "last_used_at") var lastUsedAt: Date
    @Field(key: "expires_at") var expiresAt: Date
    @OptionalField(key: "revoked_at") var revokedAt: Date?

    init() {}

    init(userId: UUID, tokenHash: String, deviceName: String, now: Date, lifetime: TimeInterval) {
        self.userId = userId
        self.tokenHash = tokenHash
        self.deviceName = deviceName
        self.createdAt = now
        self.lastUsedAt = now
        self.expiresAt = now.addingTimeInterval(lifetime)
    }
}

final class InviteModel: Model, @unchecked Sendable {
    static let schema = "invites"

    @ID(key: .id) var id: UUID?
    @Field(key: "farm_id") var farmId: UUID
    @Field(key: "role") var role: String
    @Field(key: "note") var note: String
    @Field(key: "code_hash") var codeHash: String
    @Field(key: "created_at") var createdAt: Date
    @Field(key: "expires_at") var expiresAt: Date
    @OptionalField(key: "created_by") var createdBy: UUID?
    @OptionalField(key: "used_by") var usedBy: UUID?
    @OptionalField(key: "used_at") var usedAt: Date?

    init() {}

    init(farmId: UUID, role: String, note: String, codeHash: String, createdAt: Date, expiresAt: Date, createdBy: UUID?) {
        self.farmId = farmId
        self.role = role
        self.note = note
        self.codeHash = codeHash
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.createdBy = createdBy
    }
}

final class ResetCodeModel: Model, @unchecked Sendable {
    static let schema = "reset_codes"

    @ID(key: .id) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "code_hash") var codeHash: String
    @Field(key: "created_at") var createdAt: Date
    @Field(key: "expires_at") var expiresAt: Date
    @OptionalField(key: "used_at") var usedAt: Date?

    init() {}

    init(userId: UUID, codeHash: String, createdAt: Date, expiresAt: Date) {
        self.userId = userId
        self.codeHash = codeHash
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

/// Every synced record, stored whole as JSON. The other columns are copies of a
/// few fields so the server can find and filter records without decoding them.
final class RecordModel: Model, @unchecked Sendable {
    static let schema = "records"

    @ID(key: .id) var id: UUID?
    @Field(key: "kind") var kind: String
    @Field(key: "entity_id") var entityId: UUID
    @Field(key: "farm_id") var farmId: UUID
    /// Shift and mark: the worker. Note: the author. Member: the user.
    @OptionalField(key: "owner_user_id") var ownerUserId: UUID?
    /// Mark and note: the block the tree is in.
    @OptionalField(key: "block_id") var blockId: UUID?
    /// Shift only.
    @OptionalField(key: "starts_at") var startsAt: Date?
    /// Shift only; empty while the shift is open.
    @OptionalField(key: "ends_at") var endsAt: Date?
    /// Monotonic across the whole server; a pull asks for everything after a seq.
    @Field(key: "seq") var seq: Int64
    /// The seq the record was first stored at; equal to `seq` until it's changed.
    @Field(key: "created_seq") var createdSeq: Int64
    @Field(key: "updated_at") var updatedAt: Date
    @OptionalField(key: "deleted_at") var deletedAt: Date?
    @Field(key: "json") var json: String

    init() {}
}

/// One row per live tree mark. The unique index on the tree is what makes
/// "first commit wins" hold even if two pushes race.
final class TreeClaimModel: Model, @unchecked Sendable {
    static let schema = "tree_claims"

    @ID(key: .id) var id: UUID?
    @Field(key: "farm_id") var farmId: UUID
    @Field(key: "season_id") var seasonId: UUID
    @Field(key: "block_id") var blockId: UUID
    @Field(key: "row") var row: Int
    @Field(key: "position") var position: Int
    @Field(key: "mark_id") var markId: UUID
    @Field(key: "shift_id") var shiftId: UUID

    init() {}
}

/// The first answer to each mutation id, so a retried push gets the same answer.
final class AppliedMutationModel: Model, @unchecked Sendable {
    static let schema = "applied_mutations"

    @ID(custom: .id, generatedBy: .user) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "farm_id") var farmId: UUID
    @Field(key: "result_json") var resultJSON: String
    @Field(key: "created_at") var createdAt: Date

    init() {}

    init(id: UUID, userId: UUID, farmId: UUID, resultJSON: String, createdAt: Date) {
        self.id = id
        self.userId = userId
        self.farmId = farmId
        self.resultJSON = resultJSON
        self.createdAt = createdAt
    }
}
