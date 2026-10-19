import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// `sync/push` and `sync/pull`.
struct SyncController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let farm = routes.farmRoutes()
        farm.post("sync", "push", use: push)
        farm.get("sync", "pull", use: pull)
    }

    static let defaultPullLimit = 500
    static let maxPullLimit = 1000

    /// Changes after `since` the caller may see, oldest first. `cursor` is the last
    /// seq returned (or `since` when nothing is), to pass back as the next `since`.
    func pull(req: Request) async throws -> Response {
        let ctx = try req.requireFarm()
        let since = try req.queryInt64("since") ?? 0
        guard since >= 0 else { throw Abort(.badRequest, reason: "since can’t be negative.") }
        let limit = min(max(Int(try req.queryInt64("limit") ?? Int64(Self.defaultPullLimit)), 1), Self.maxPullLimit)

        let query = RecordModel.query(on: req.db)
            .filter(\.$farmId == ctx.farmId)
            .filter(\.$seq > since)
        if !ctx.isAdmin {
            let me = ctx.member.userId
            query.group(.or) { or in
                or.filter(\.$kind != RecordKind.shift.rawValue)
                or.filter(\.$ownerUserId == me)
            }
        }
        let rows = try await query.sort(\.$seq).limit(limit + 1).all()
        let page = rows.prefix(limit)
        let changes = try page.map { Change(seq: $0.seq, record: Visibility.redact(try $0.decoded(), for: ctx.member)) }
        return try .json(PullResponse(changes: changes, cursor: changes.last?.seq ?? since, hasMore: rows.count > limit))
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
                if let prior = try await AppliedMutationModel.find(mutation.id, on: db) {
                    guard prior.userId == userId, prior.farmId == farmId else {
                        return .rejected(mutation.id, .forbidden, "That change id was already used.")
                    }
                    return try ServerJSON.decode(MutationResult.self, from: prior.resultJSON)
                }
                // The caller's role can change partway through a batch, so it's read each time.
                guard let caller = try await RecordStore(db: db).member(userId, farm: farmId), caller.removedAt == nil else {
                    return .rejected(mutation.id, .forbidden, "You’re no longer on this farm.")
                }
                let outcome = try await PushApplier(db: db, farmId: farmId, caller: caller, now: now).apply(mutation.record)
                let result = outcome.result(mutation.id)
                try await AppliedMutationModel(id: mutation.id, userId: userId, farmId: farmId,
                                               resultJSON: try ServerJSON.string(result), createdAt: now).create(on: db)
                return result
            }
            results.append(result)
        }
        return try .json(PushResponse(results: results))
    }
}
