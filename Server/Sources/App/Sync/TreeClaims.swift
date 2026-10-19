import Fluent
import Foundation
import TreeFarmKit

/// Live tree marks hold a claim on their tree for the season. The unique index on
/// (farm, season, block, row, position) is what makes "first commit wins" hold.
enum TreeClaims {
    /// Claims the mark's tree. Returns the other mark's claim when someone already holds it.
    static func claim(_ mark: TreeMark, farm: UUID, on db: any Database) async throws -> TreeClaimModel? {
        if let holder = try await holder(season: mark.seasonId, tree: mark.tree, farm: farm, on: db) {
            return holder.markId == mark.id ? nil : holder
        }
        try await release(markId: mark.id, on: db)
        try await TreeClaimModel(farmId: farm, mark: mark).create(on: db)
        return nil
    }

    static func release(markId: UUID, on db: any Database) async throws {
        try await TreeClaimModel.query(on: db).filter(\.$markId == markId).delete()
    }

    static func holder(season: UUID, tree: TreeRef, farm: UUID, on db: any Database) async throws -> TreeClaimModel? {
        try await TreeClaimModel.query(on: db)
            .filter(\.$farmId == farm)
            .filter(\.$seasonId == season)
            .filter(\.$blockId == tree.blockId)
            .filter(\.$row == tree.row)
            .filter(\.$position == tree.position)
            .first()
    }
}
