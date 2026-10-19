import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// The signed-in person's own account.
struct MeController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let me = routes.grouped("v1", "me").grouped(BearerAuth())
        me.get(use: show)
    }

    func show(req: Request) async throws -> Response {
        let ctx = try req.requireAuth()
        return try .json(try await Accounts.me(ctx.user, on: req.db))
    }
}
