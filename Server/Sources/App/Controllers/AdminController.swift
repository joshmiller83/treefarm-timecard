import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// Invites and password-reset codes. Admins only.
struct AdminController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let admin = routes.farmRoutes().grouped(AdminOnly())
        admin.get("invites", use: listInvites)
        admin.post("invites", use: createInvite)
        admin.delete("invites", ":inviteId", use: deleteInvite)
        admin.post("members", ":userId", "reset", use: resetCode)
        admin.delete("members", ":userId", use: removeMember)
    }

    /// Sets `removedAt` through the same path a pushed member change takes, so it
    /// syncs to every device and the last-admin rule applies.
    func removeMember(req: Request) async throws -> HTTPStatus {
        let ctx = try req.requireAdmin()
        let now = req.now
        guard let userId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.notFound, reason: "That person isn’t on this farm.")
        }
        let outcome = try await req.db.transaction { db -> Outcome in
            let store = RecordStore(db: db)
            guard let caller = try await store.member(ctx.member.userId, farm: ctx.farmId), caller.removedAt == nil, caller.role == .admin else {
                return .rejected(.forbidden, "Only an admin can do that.")
            }
            guard var member = try await store.member(userId, farm: ctx.farmId) else {
                return .rejected(.notFound, "That person isn’t on this farm.")
            }
            guard member.removedAt == nil else { return .applied(0) }
            member.removedAt = now
            member.updatedAt = max(now, member.updatedAt.addingTimeInterval(0.001))
            return try await PushApplier(db: db, farmId: ctx.farmId, caller: caller, now: now).apply(.member(member))
        }
        switch outcome {
        case .applied: return .noContent
        case .rejected(.notFound, let message, _): throw Abort(.notFound, reason: message)
        case .rejected(.forbidden, let message, _): throw Abort(.forbidden, reason: message)
        case .rejected(_, let message, _): throw Abort(.conflict, reason: message)
        }
    }

    func listInvites(req: Request) async throws -> Response {
        let ctx = try req.requireAdmin()
        let invites = try await InviteModel.query(on: req.db)
            .filter(\.$farmId == ctx.farmId)
            .sort(\.$createdAt, .descending)
            .all()
        return try .json(invites.map(\.info))
    }

    func createInvite(req: Request) async throws -> Response {
        let ctx = try req.requireAdmin()
        let body = try req.decodeJSON(CreateInviteRequest.self)
        let created = try await Invites.create(on: req.db, farmId: ctx.farmId, role: body.role, note: body.note, createdBy: ctx.member.userId, now: req.now)
        var info = created.model.info
        info.code = created.code
        return try .json(info)
    }

    func deleteInvite(req: Request) async throws -> HTTPStatus {
        let ctx = try req.requireAdmin()
        guard let id = req.parameters.get("inviteId", as: UUID.self),
              let invite = try await InviteModel.query(on: req.db).filter(\.$id == id).filter(\.$farmId == ctx.farmId).first()
        else { throw Abort(.notFound, reason: "That invite is already gone.") }
        try await invite.delete(on: req.db)
        return .noContent
    }

    func resetCode(req: Request) async throws -> Response {
        let ctx = try req.requireAdmin()
        guard let userId = req.parameters.get("userId", as: UUID.self),
              let member = try await RecordStore(db: req.db).member(userId, farm: ctx.farmId), member.removedAt == nil,
              try await UserModel.find(userId, on: req.db) != nil
        else { throw Abort(.notFound, reason: "That person isn’t on this farm.") }
        let reset = try await req.db.transaction { db in
            try await ResetCodes.issue(for: userId, on: db, now: req.now)
        }
        return try .json(reset)
    }
}
