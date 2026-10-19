import Foundation
import TreeFarmKit

extension UserModel {
    var profile: UserProfile { UserProfile(id: id!, email: email, displayName: displayName) }
}

extension InviteModel {
    convenience init(farmId: UUID, role: Role, note: String, codeHash: String, createdAt: Date, expiresAt: Date, createdBy: UUID?) {
        self.init(farmId: farmId, role: role.rawValue, note: note, codeHash: codeHash, createdAt: createdAt, expiresAt: expiresAt, createdBy: createdBy)
    }

    var info: InviteInfo {
        InviteInfo(id: id!, role: Role(rawValue: role) ?? .worker, note: note, createdAt: createdAt, expiresAt: expiresAt, usedAt: usedAt)
    }
}

extension TreeClaimModel {
    convenience init(farmId: UUID, mark: TreeMark) {
        self.init()
        self.farmId = farmId
        self.seasonId = mark.seasonId
        self.blockId = mark.blockId
        self.row = mark.row
        self.position = mark.position
        self.markId = mark.id
        self.shiftId = mark.shiftId
    }
}
