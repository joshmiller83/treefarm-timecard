import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// `sync/push` and `sync/pull`.
struct SyncController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let farm = routes.farmRoutes()
        farm.post("sync", "push", use: push)
    }

    /// One result per mutation, in order. Each mutation runs in its own transaction
    /// and its result is kept, so a retried mutation id gets the same answer.
    func push(req: Request) async throws -> Response {
        let ctx = try req.requireFarm()
        let body = try req.decodeJSON(PushRequest.self)
        guard body.mutations.count <= Limits.pushBatch else {
            throw Abort(.payloadTooLarge, reason: "Send at most \(Limits.pushBatch) changes at a time.")
        }
        let userId = ctx.member.userId
        let farmId = ctx.farmId
        let now = req.now

        var results: [MutationResult] = []
        for mutation in body.mutations {
            let result = try await req.db.transaction { db -> MutationResult in
                // The caller's role can change partway through a batch, so it's read each time.
                guard let caller = try await RecordStore(db: db).member(userId, farm: farmId), caller.removedAt == nil else {
                    return .rejected(mutation.id, .forbidden, "You’re no longer on this farm.")
                }
                let outcome = try await PushApplier(db: db, farmId: farmId, caller: caller, now: now).apply(mutation.record)
                return outcome.result(mutation.id)
            }
            results.append(result)
        }
        return try .json(PushResponse(results: results))
    }
}
