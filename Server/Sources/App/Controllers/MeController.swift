import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// The signed-in person's own account and sessions.
struct MeController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let me = routes.grouped("v1", "me").grouped(BearerAuth())
        me.get(use: show)
        me.patch(use: update)
        me.delete(use: delete)
        me.get("sessions", use: sessions)
        me.delete("sessions", ":sessionId", use: revokeSession)
    }

    func show(req: Request) async throws -> Response {
        let ctx = try req.requireAuth()
        return try .json(try await Accounts.me(ctx.user, on: req.db))
    }

    /// Name changes reach every farm the person is on; a password change needs the
    /// current password and signs out every other device.
    func update(req: Request) async throws -> Response {
        let ctx = try req.requireAuth()
        let body = try req.decodeJSON(UpdateMeRequest.self)
        let now = req.now
        let user = ctx.user

        let name = try body.displayName.map(Accounts.validName)
        var newHash: String?
        if let newPassword = body.newPassword {
            guard let current = body.currentPassword, !current.isEmpty else {
                throw Abort(.badRequest, reason: "Enter your current password to change it.")
            }
            guard try await req.hasher.verify(current, hash: user.passwordHash) else {
                throw Abort(.forbidden, reason: "Your current password isn’t right.")
            }
            newHash = try await req.hasher.hash(try Accounts.validPassword(newPassword))
        }

        let finalHash = newHash
        try await req.db.transaction { db in
            if let name, name != user.displayName {
                user.displayName = name
                let store = RecordStore(db: db)
                for var member in try await store.activeMemberships(of: user.id!) where member.displayName != name {
                    member.displayName = name
                    member.updatedAt = now
                    try await store.save(.member(member), farm: member.farmId)
                }
            }
            if let finalHash {
                user.passwordHash = finalHash
                try await Accounts.revokeSessions(of: user.id!, except: ctx.session.id, on: db, now: now)
            }
            try await user.save(on: db)
        }
        return try .json(try await Accounts.me(user, on: req.db))
    }

    /// Deletes the login. Shifts stay with the farm: the person's membership is
    /// marked removed and keeps their name, but not their email.
    func delete(req: Request) async throws -> HTTPStatus {
        let ctx = try req.requireAuth()
        let body = try req.decodeJSON(DeleteAccountRequest.self)
        let now = req.now
        guard try await req.hasher.verify(body.password, hash: ctx.user.passwordHash) else {
            throw Abort(.forbidden, reason: "That password isn’t right.")
        }
        let userId = ctx.userId

        try await req.db.transaction { db in
            let store = RecordStore(db: db)
            let memberships = try await store.activeMemberships(of: userId)
            for membership in memberships where membership.role == .admin {
                let others = try await store.members(farm: membership.farmId).filter { $0.userId != userId && $0.removedAt == nil }
                if !others.isEmpty && !others.contains(where: { $0.role == .admin }) {
                    let farmName = try await store.farm(membership.farmId)?.name ?? "your farm"
                    throw Abort(.conflict, reason: "You’re the only admin of \(farmName). Make someone else an admin first.")
                }
            }
            for var member in memberships {
                member.removedAt = now
                member.email = ""
                member.updatedAt = now
                try await store.save(.member(member), farm: member.farmId)
            }
            try await SessionModel.query(on: db).filter(\.$userId == userId).delete()
            try await ResetCodeModel.query(on: db).filter(\.$userId == userId).delete()
            try await ctx.user.delete(on: db)
        }
        return .noContent
    }

    func sessions(req: Request) async throws -> Response {
        let ctx = try req.requireAuth()
        let now = req.now
        let list = try await SessionModel.query(on: req.db)
            .filter(\.$userId == ctx.userId)
            .filter(\.$revokedAt == nil)
            .filter(\.$expiresAt > now)
            .sort(\.$lastUsedAt, .descending)
            .all()
            .map { SessionInfo(id: $0.id!, deviceName: $0.deviceName, createdAt: $0.createdAt, lastUsedAt: $0.lastUsedAt, isCurrent: $0.id == ctx.session.id) }
        return try .json(list)
    }

    func revokeSession(req: Request) async throws -> HTTPStatus {
        let ctx = try req.requireAuth()
        guard let id = req.parameters.get("sessionId", as: UUID.self),
              let session = try await SessionModel.query(on: req.db)
                .filter(\.$id == id)
                .filter(\.$userId == ctx.userId)
                .filter(\.$revokedAt == nil)
                .first()
        else { throw Abort(.notFound, reason: "That session isn’t signed in anymore.") }
        session.revokedAt = req.now
        try await session.save(on: req.db)
        return .noContent
    }
}
