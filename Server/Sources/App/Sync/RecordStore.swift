import Fluent
import Foundation
import TreeFarmKit

/// A stored record with its row.
struct StoredRecord {
    let model: RecordModel
    let record: SyncRecord

    var seq: Int64 { model.seq }
}

/// Reads and writes synced records. Call it with the transaction's database
/// inside a transaction; every save takes the next `seq`.
struct RecordStore {
    let db: any Database

    func maxSeq() async throws -> Int64 {
        try await RecordModel.query(on: db).max(\.$seq) ?? 0
    }

    func find(_ kind: RecordKind, _ id: UUID, farm: UUID) async throws -> StoredRecord? {
        guard let model = try await RecordModel.query(on: db)
            .filter(\.$farmId == farm)
            .filter(\.$kind == kind.rawValue)
            .filter(\.$entityId == id)
            .first()
        else { return nil }
        return StoredRecord(model: model, record: try model.decoded())
    }

    func all(_ kind: RecordKind, farm: UUID, configure: (QueryBuilder<RecordModel>) -> Void = { _ in }) async throws -> [StoredRecord] {
        let query = RecordModel.query(on: db)
            .filter(\.$farmId == farm)
            .filter(\.$kind == kind.rawValue)
        configure(query)
        return try await query.sort(\.$seq).all().map { StoredRecord(model: $0, record: try $0.decoded()) }
    }

    /// Writes the record (new or replacing the stored copy) at the next seq and returns it.
    @discardableResult
    func save(_ record: SyncRecord, farm: UUID) async throws -> Int64 {
        let seq = try await maxSeq() + 1
        let model = try await RecordModel.query(on: db)
            .filter(\.$farmId == farm)
            .filter(\.$kind == record.kind.rawValue)
            .filter(\.$entityId == record.entityId)
            .first() ?? RecordModel()
        model.kind = record.kind.rawValue
        model.entityId = record.entityId
        model.farmId = farm
        model.ownerUserId = record.ownerUserId
        model.blockId = record.blockId
        model.startsAt = record.startsAt
        model.endsAt = record.endsAt
        model.seq = seq
        model.updatedAt = record.updatedAt
        model.deletedAt = record.deletedAt
        model.json = try ServerJSON.string(record)
        try await model.save(on: db)
        return seq
    }

    // MARK: Typed lookups

    func farm(_ id: UUID) async throws -> Farm? {
        if case .farm(let r)? = try await find(.farm, id, farm: id)?.record { return r }
        return nil
    }

    func member(_ userId: UUID, farm: UUID) async throws -> Member? {
        if case .member(let r)? = try await find(.member, userId, farm: farm)?.record { return r }
        return nil
    }

    func season(_ id: UUID, farm: UUID) async throws -> Season? {
        if case .season(let r)? = try await find(.season, id, farm: farm)?.record { return r }
        return nil
    }

    func field(_ id: UUID, farm: UUID) async throws -> Field? {
        if case .field(let r)? = try await find(.field, id, farm: farm)?.record { return r }
        return nil
    }

    func block(_ id: UUID, farm: UUID) async throws -> Block? {
        if case .block(let r)? = try await find(.block, id, farm: farm)?.record { return r }
        return nil
    }

    func shift(_ id: UUID, farm: UUID) async throws -> Shift? {
        if case .shift(let r)? = try await find(.shift, id, farm: farm)?.record { return r }
        return nil
    }

    func mark(_ id: UUID, farm: UUID) async throws -> TreeMark? {
        if case .treeMark(let r)? = try await find(.treeMark, id, farm: farm)?.record { return r }
        return nil
    }

    func members(farm: UUID) async throws -> [Member] {
        try await all(.member, farm: farm).compactMap {
            if case .member(let m) = $0.record { return m }
            return nil
        }
    }

    /// Every farm where the user is a current (not removed) member, with the membership.
    func activeMemberships(of userId: UUID) async throws -> [Member] {
        try await RecordModel.query(on: db)
            .filter(\.$kind == RecordKind.member.rawValue)
            .filter(\.$entityId == userId)
            .sort(\.$seq)
            .all()
            .compactMap { model -> Member? in
                if case .member(let m) = try model.decoded(), m.removedAt == nil { return m }
                return nil
            }
    }
}

extension RecordModel {
    func decoded() throws -> SyncRecord {
        try ServerJSON.decode(SyncRecord.self, from: json)
    }
}

extension SyncRecord {
    var updatedAt: Date {
        switch self {
        case .farm(let r): r.updatedAt
        case .member(let r): r.updatedAt
        case .season(let r): r.updatedAt
        case .field(let r): r.updatedAt
        case .block(let r): r.updatedAt
        case .shift(let r): r.updatedAt
        case .treeMark(let r): r.updatedAt
        case .treeNote(let r): r.updatedAt
        }
    }

    var deletedAt: Date? {
        switch self {
        case .farm, .member, .season: nil
        case .field(let r): r.deletedAt
        case .block(let r): r.deletedAt
        case .shift(let r): r.deletedAt
        case .treeMark(let r): r.deletedAt
        case .treeNote(let r): r.deletedAt
        }
    }

    var ownerUserId: UUID? {
        switch self {
        case .member(let r): r.userId
        case .shift(let r): r.userId
        case .treeMark(let r): r.userId
        case .treeNote(let r): r.authorId
        default: nil
        }
    }

    var blockId: UUID? {
        switch self {
        case .treeMark(let r): r.blockId
        case .treeNote(let r): r.blockId
        default: nil
        }
    }

    var startsAt: Date? {
        if case .shift(let r) = self { return r.start }
        return nil
    }

    var endsAt: Date? {
        if case .shift(let r) = self { return r.end }
        return nil
    }

    /// The farm a record names itself. Blocks and marks don't carry one; the server
    /// works it out from their field or season.
    var declaredFarmId: UUID? {
        switch self {
        case .farm(let r): r.id
        case .member(let r): r.farmId
        case .season(let r): r.farmId
        case .field(let r): r.farmId
        case .shift(let r): r.farmId
        case .treeNote(let r): r.farmId
        case .block, .treeMark: nil
        }
    }
}
