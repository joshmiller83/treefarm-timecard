import Fluent
import Foundation
import TreeFarmKit
import Vapor

enum Invites {
    static let lifetime: TimeInterval = 7 * 24 * 3600

    struct Created {
        let model: InviteModel
        let code: String
    }

    static func create(on db: any Database, farmId: UUID, role: Role, note: String, createdBy: UUID?, now: Date) async throws -> Created {
        let code = Codes.humanCode()
        let model = InviteModel(farmId: farmId, role: role, note: Limits.clampName(note), codeHash: Codes.codeHash(code),
                                createdAt: now, expiresAt: now.addingTimeInterval(lifetime), createdBy: createdBy)
        try await model.create(on: db)
        return Created(model: model, code: code)
    }

    /// The invite a code names, if it can still be used; otherwise a 400 saying why.
    static func usable(_ code: String, on db: any Database, now: Date) async throws -> InviteModel {
        guard let invite = try await InviteModel.query(on: db).filter(\.$codeHash == Codes.codeHash(code)).first() else {
            throw Abort(.badRequest, reason: "That invite code isn’t valid. Ask your admin for a new one.")
        }
        if invite.usedAt != nil {
            throw Abort(.badRequest, reason: "That invite code was already used. Ask your admin for a new one.")
        }
        if invite.expiresAt <= now {
            throw Abort(.badRequest, reason: "That invite code has expired. Ask your admin for a new one.")
        }
        return invite
    }
}

enum ResetCodes {
    static let lifetime: TimeInterval = 24 * 3600

    /// Issues a single-use code for the user, replacing any earlier unused one.
    static func issue(for userId: UUID, on db: any Database, now: Date) async throws -> ResetCodeResponse {
        try await ResetCodeModel.query(on: db)
            .filter(\.$userId == userId)
            .filter(\.$usedAt == nil)
            .delete()
        let code = Codes.humanCode()
        let expires = now.addingTimeInterval(lifetime)
        try await ResetCodeModel(userId: userId, codeHash: Codes.codeHash(code), createdAt: now, expiresAt: expires).create(on: db)
        return ResetCodeResponse(code: code, expiresAt: expires)
    }

    static func usable(_ code: String, for userId: UUID, on db: any Database, now: Date) async throws -> ResetCodeModel? {
        try await ResetCodeModel.query(on: db)
            .filter(\.$userId == userId)
            .filter(\.$codeHash == Codes.codeHash(code))
            .filter(\.$usedAt == nil)
            .filter(\.$expiresAt > now)
            .first()
    }
}
