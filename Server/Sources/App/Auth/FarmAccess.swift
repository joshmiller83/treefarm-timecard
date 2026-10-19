import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// The farm in the path and the caller's place on it, set by `FarmAccess`.
struct FarmContext: Sendable {
    let farmId: UUID
    let member: Member

    var isAdmin: Bool { member.role == .admin }
}

extension Request {
    private struct FarmKey: StorageKey { typealias Value = FarmContext }

    var farmContext: FarmContext? {
        get { storage[FarmKey.self] }
        set { storage[FarmKey.self] = newValue }
    }

    func requireFarm() throws -> FarmContext {
        guard let ctx = farmContext else { throw Abort(.forbidden, reason: "You’re not on this farm.") }
        return ctx
    }

    /// The farm context, refusing workers.
    func requireAdmin() throws -> FarmContext {
        let ctx = try requireFarm()
        guard ctx.isAdmin else { throw Abort(.forbidden, reason: "Only an admin can do that.") }
        return ctx
    }
}

/// Every `/v1/farms/:farmId` route runs behind this: the caller must be a current
/// member of the farm. Removed members get 403.
struct FarmAccess: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let auth = try req.requireAuth()
        guard let farmId = req.parameters.get("farmId", as: UUID.self) else {
            throw Abort(.notFound, reason: "There’s no farm at that address.")
        }
        guard let member = try await RecordStore(db: req.db).member(auth.userId, farm: farmId), member.removedAt == nil else {
            throw Abort(.forbidden, reason: "You’re not on this farm.")
        }
        req.farmContext = FarmContext(farmId: farmId, member: member)
        return try await next.respond(to: req)
    }
}

/// Refuses workers.
struct AdminOnly: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        _ = try req.requireAdmin()
        return try await next.respond(to: req)
    }
}

extension RoutesBuilder {
    /// `/v1/farms/:farmId`, signed in and on the farm.
    func farmRoutes() -> any RoutesBuilder {
        grouped("v1", "farms", ":farmId").grouped(BearerAuth(), FarmAccess())
    }
}
