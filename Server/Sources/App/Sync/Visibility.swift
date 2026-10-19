import Foundation
import TreeFarmKit

/// What each person may see. Everyone on a farm sees the farm, seasons, fields,
/// blocks, every tree mark and every tree note (the map is shared). Workers see
/// their own shifts only, and other people's email and rate come back blank.
enum Visibility {
    static func canSee(_ record: SyncRecord, caller: Member) -> Bool {
        if caller.role == .admin { return true }
        if case .shift(let s) = record { return s.userId == caller.userId }
        return true
    }

    static func redact(_ record: SyncRecord, for caller: Member) -> SyncRecord {
        guard caller.role != .admin, case .member(var m) = record, m.userId != caller.userId else { return record }
        m.email = ""
        m.rateCents = 0
        return .member(m)
    }
}
