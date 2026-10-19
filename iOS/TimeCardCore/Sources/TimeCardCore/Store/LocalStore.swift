import Foundation
import GRDB
import os

public enum StoreError: Error, Equatable, Sendable {
    /// `save` was called before `activate(farmId:)`.
    case noActiveFarm
}

/// A change waiting to be pushed.
public struct OutboxEntry: Equatable, Sendable {
    public var seq: Int64
    public var mutationId: UUID
    public var farmId: UUID
    public var kind: RecordKind
    public var entityId: UUID
    public var record: SyncRecord
    public var createdAt: Date
    public var attempts: Int
    public var lastError: String?

    public var mutation: Mutation { Mutation(id: mutationId, record: record) }
}

/// A change the server turned down, after the store has put things right.
public struct Rejection: Equatable, Sendable {
    public var mutationId: UUID
    public var kind: RecordKind
    public var entityId: UUID
    public var reason: RejectReason?
    /// The server's sentence, fit to show or speak.
    public var message: String
    /// True when the server sent its own copy and the store now holds it.
    /// False means the record is refetched on the next pull.
    public var restoredFromServer: Bool
    /// The server's copy (the mark that won the tree, the shift already on the clock).
    public var current: SyncRecord? = nil
}

/// Tells observers the store changed and how many changes wait to sync.
public struct StoreChange: Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        /// Something on this device saved records (sync should push soon).
        case local
        /// Records pulled from the server were applied.
        case remote
        /// The server answered a push.
        case sync
        /// The store switched farms or was wiped.
        case reset
    }

    public var origin: Origin
    public var pendingCount: Int

    public init(origin: Origin, pendingCount: Int) {
        self.origin = origin
        self.pendingCount = pendingCount
    }
}

/// The app's local database plus an in-memory `FarmSnapshot` of the active farm.
///
/// Every write runs in one transaction and then updates the snapshot, serialized
/// on the database's writer so the snapshot always matches the order of commits.
/// Safe to use from any thread: the app, the sync engine and Siri intents share one.
public final class LocalStore: Sendable {
    private let writer: any DatabaseWriter
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State: Sendable {
        var snapshot: FarmSnapshot?
        var observers: [UUID: AsyncStream<StoreChange>.Continuation] = [:]
    }

    /// The farm id an empty snapshot carries before any farm is active.
    public static let noFarm = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public static func inMemory() throws -> LocalStore {
        LocalStore(writer: try AppDatabase.openInMemory())
    }

    public static func onDisk(directory: URL) throws -> LocalStore {
        LocalStore(writer: try AppDatabase.open(directory: directory))
    }

    // MARK: Snapshot

    /// The farm local saves belong to, once `activate(farmId:)` has run.
    public var activeFarmId: UUID? { state.withLock { $0.snapshot?.farmId } }

    /// The active farm's records. Empty before `activate(farmId:)`.
    public var snapshot: FarmSnapshot {
        state.withLock { $0.snapshot } ?? FarmSnapshot(farmId: Self.noFarm)
    }

    /// Loads `farmId`'s records into the snapshot and makes it the farm saves go to.
    public func activate(farmId: UUID) throws {
        let pending = try writer.writeWithoutTransaction { db -> Int in
            var snapshot = FarmSnapshot(farmId: farmId)
            let decoder = JSONCoding.decoder()
            let rows = try Row.fetchCursor(db, sql: "SELECT json FROM records WHERE farmId = ? AND deletedAt IS NULL", arguments: [farmId.uuidString])
            while let row = try rows.next() {
                let data: Data = row[0]
                snapshot.apply(try decoder.decode(SyncRecord.self, from: data))
            }
            let loaded = snapshot
            state.withLock { $0.snapshot = loaded }
            return try Self.count(db)
        }
        notify(.reset, pending)
    }

    // MARK: Local saves

    /// Saves records made on this device and queues them for the server, in one transaction.
    /// A record that already waits in the outbox is replaced there (keeping its place in line)
    /// with a new mutation id, so a late answer about the old version can't clear the new one.
    @discardableResult
    public func save(_ records: [SyncRecord]) throws -> [Mutation] {
        guard let farmId = activeFarmId else { throw StoreError.noActiveFarm }
        let encoder = JSONCoding.encoder()
        let mutations = records.map { Mutation(record: $0) }
        let encoded = try records.map { try encoder.encode($0) }
        let now = Self.ms(Date())
        let farm = farmId.uuidString

        let pending = try writer.writeWithoutTransaction { db -> Int in
            try db.inTransaction {
                for (mutation, json) in zip(mutations, encoded) {
                    let record = mutation.record
                    try Self.upsert(db, farmId: farm, record: record, json: json)
                    let existing = try Int64.fetchOne(db, sql: "SELECT seq FROM outbox WHERE farmId = ? AND kind = ? AND entityId = ?",
                                                      arguments: [farm, record.kind.rawValue, record.entityId.uuidString])
                    if let seq = existing {
                        try db.execute(sql: """
                            UPDATE outbox SET mutationId = ?, json = ?, createdAt = ?, attempts = 0, lastError = NULL WHERE seq = ?
                            """, arguments: [mutation.id.uuidString, json, now, seq])
                    } else {
                        try db.execute(sql: """
                            INSERT INTO outbox (mutationId, farmId, kind, entityId, json, createdAt) VALUES (?, ?, ?, ?, ?, ?)
                            """, arguments: [mutation.id.uuidString, farm, record.kind.rawValue, record.entityId.uuidString, json, now])
                    }
                }
                return .commit
            }
            updateSnapshot(farmId: farmId) { snapshot in records.forEach { snapshot.apply($0) } }
            return try Self.count(db)
        }
        notify(.local, pending)
        return mutations
    }

    // MARK: Pulled records

    /// Merges records pulled from the server and stores the new cursor, in one transaction.
    /// A pulled record replaces the local copy unless a local edit to it still waits to be
    /// pushed; then the local edit wins until the server has answered it.
    public func applyRemote(_ changes: [Change], farmId: UUID, cursor: Int64?) throws {
        let encoder = JSONCoding.encoder()
        let farm = farmId.uuidString
        let pending = try writer.writeWithoutTransaction { db -> Int in
            var applied: [SyncRecord] = []
            try db.inTransaction {
                let waiting = try Self.pendingEntities(db, farmId: farm)
                for change in changes {
                    let record = change.record
                    guard !waiting.contains(EntityKey(record.kind, record.entityId)) else { continue }
                    try Self.upsert(db, farmId: farm, record: record, json: try encoder.encode(record))
                    try db.execute(sql: "DELETE FROM refetch WHERE farmId = ? AND kind = ? AND id = ?",
                                   arguments: [farm, record.kind.rawValue, record.entityId.uuidString])
                    applied.append(record)
                }
                if let cursor { try Self.setCursor(db, farmId: farm, cursor) }
                return .commit
            }
            updateSnapshot(farmId: farmId) { snapshot in applied.forEach { snapshot.apply($0) } }
            return try Self.count(db)
        }
        notify(.remote, pending)
    }

    /// Call when a pull has run to the end. Records the server refused without sending a
    /// copy, and that the pull from 0 didn't bring back, don't exist there: drop them here.
    public func finishPull(farmId: UUID) throws {
        let farm = farmId.uuidString
        let (pending, droppedAny) = try writer.writeWithoutTransaction { db -> (Int, Bool) in
            var dropped: [EntityKey] = []
            try db.inTransaction {
                let waiting = try Self.pendingEntities(db, farmId: farm)
                let rows = try Row.fetchAll(db, sql: "SELECT kind, id FROM refetch WHERE farmId = ?", arguments: [farm])
                for row in rows {
                    guard let key = EntityKey(kind: row["kind"], id: row["id"]), !waiting.contains(key) else { continue }
                    try db.execute(sql: "DELETE FROM records WHERE farmId = ? AND kind = ? AND id = ?",
                                   arguments: [farm, key.kind.rawValue, key.id.uuidString])
                    dropped.append(key)
                }
                try db.execute(sql: "DELETE FROM refetch WHERE farmId = ?", arguments: [farm])
                return .commit
            }
            updateSnapshot(farmId: farmId) { snapshot in dropped.forEach { snapshot.remove(kind: $0.kind, id: $0.id) } }
            return (try Self.count(db), !dropped.isEmpty)
        }
        if droppedAny { notify(.remote, pending) }
    }

    public func refetchCount(farmId: UUID) throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM refetch WHERE farmId = ?", arguments: [farmId.uuidString]) ?? 0
        }
    }

    /// The role the farm's pulls were made under, since the server shows workers less.
    public func pulledAs(farmId: UUID) throws -> Role? {
        try value(forKey: Self.pulledAsKey(farmId)).flatMap { Role(rawValue: String(decoding: $0, as: UTF8.self)) }
    }

    public func setPulledAs(_ role: Role, farmId: UUID) throws {
        try setValue(Data(role.rawValue.utf8), forKey: Self.pulledAsKey(farmId))
    }

    static func pulledAsKey(_ farmId: UUID) -> String { "sync.pulledAs.\(farmId.uuidString)" }

    /// Starts the farm's pulls over from 0, after the person's role changed. With `owner`, other
    /// people's shifts are forgotten too (someone who is no longer an admin doesn't see them).
    public func restartPulls(farmId: UUID, keepingOnlyShiftsOf owner: UUID?) throws {
        let farm = farmId.uuidString
        let decoder = JSONCoding.decoder()
        let pending = try writer.writeWithoutTransaction { db -> Int in
            var dropped: [UUID] = []
            try db.inTransaction {
                try Self.setCursor(db, farmId: farm, 0)
                if let owner {
                    let rows = try Row.fetchAll(db, sql: "SELECT id, json FROM records WHERE farmId = ? AND kind = ?",
                                                arguments: [farm, RecordKind.shift.rawValue])
                    for row in rows {
                        let data: Data = row["json"]
                        guard case .shift(let shift) = try decoder.decode(SyncRecord.self, from: data), shift.userId != owner else { continue }
                        try db.execute(sql: "DELETE FROM records WHERE farmId = ? AND kind = ? AND id = ?",
                                       arguments: [farm, RecordKind.shift.rawValue, shift.id.uuidString])
                        dropped.append(shift.id)
                    }
                }
                return .commit
            }
            updateSnapshot(farmId: farmId) { snapshot in dropped.forEach { snapshot.remove(kind: .shift, id: $0) } }
            return try Self.count(db)
        }
        notify(.remote, pending)
    }

    public func cursor(farmId: UUID) throws -> Int64 {
        try writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT cursor FROM sync_state WHERE farmId = ?", arguments: [farmId.uuidString]) ?? 0
        }
    }

    // MARK: Outbox

    /// Up to `limit` waiting changes for `farmId` after `seq`, oldest first.
    public func outbox(farmId: UUID, after seq: Int64 = 0, limit: Int) throws -> [OutboxEntry] {
        let decoder = JSONCoding.decoder()
        return try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT seq, mutationId, farmId, kind, entityId, json, createdAt, attempts, lastError
                FROM outbox WHERE farmId = ? AND seq > ? ORDER BY seq LIMIT ?
                """, arguments: [farmId.uuidString, seq, limit])
            return try rows.compactMap { row in
                guard let mutationId = UUID(uuidString: row["mutationId"]),
                      let farmId = UUID(uuidString: row["farmId"]),
                      let kind = RecordKind(rawValue: row["kind"]),
                      let entityId = UUID(uuidString: row["entityId"]) else { return nil }
                let json: Data = row["json"]
                return OutboxEntry(seq: row["seq"], mutationId: mutationId, farmId: farmId, kind: kind, entityId: entityId,
                                   record: try decoder.decode(SyncRecord.self, from: json),
                                   createdAt: Date(timeIntervalSince1970: Double(row["createdAt"] as Int64) / 1000),
                                   attempts: row["attempts"], lastError: row["lastError"])
            }
        }
    }

    /// Changes waiting to sync, for one farm or all of them.
    public func pendingCount(farmId: UUID? = nil) throws -> Int {
        try writer.read { db in
            if let farmId {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE farmId = ?", arguments: [farmId.uuidString]) ?? 0
            }
            return try Self.count(db)
        }
    }

    /// Notes a push that didn't get an answer, so the rows stay for the next try.
    public func recordAttempt(mutationIds: [UUID], error: String?) throws {
        guard !mutationIds.isEmpty else { return }
        try writer.write { db in
            for id in mutationIds {
                try db.execute(sql: "UPDATE outbox SET attempts = attempts + 1, lastError = ? WHERE mutationId = ?",
                               arguments: [error, id.uuidString])
            }
        }
    }

    /// Applies the server's answer to a push. Applied changes leave the outbox. A rejected
    /// change leaves it too, and then:
    /// - with the server's copy of the same record (`current`), that copy is stored.
    /// - with a different record: for a tree mark (the mark that won the tree) that record is
    ///   stored and the refused local mark is dropped. For anything else (the shift already on
    ///   the clock) that record is stored, the local one stays, and both are settled by a pull
    ///   from 0, which drops the local one if the server doesn't have it. Trees marked on a
    ///   refused new shift move to the open shift and are queued again, so they aren't lost.
    /// - without a copy, the record is queued for refetch and the next pull starts from 0.
    /// Answers about mutations no longer in the outbox (replaced by a newer edit) are ignored.
    public func applyPushResults(_ results: [MutationResult], farmId: UUID) throws -> [Rejection] {
        let encoder = JSONCoding.encoder()
        let farm = farmId.uuidString
        var rejections: [Rejection] = []
        let now = Date().roundedToMillisecond
        let pending = try writer.writeWithoutTransaction { db -> Int in
            var snapshotChanges: [(SyncRecord?, EntityKey?)] = []
            try db.inTransaction {
                for result in results {
                    let row = try Row.fetchOne(db, sql: "SELECT kind, entityId FROM outbox WHERE mutationId = ? AND farmId = ?",
                                               arguments: [result.mutationId.uuidString, farm])
                    guard let row, let key = EntityKey(kind: row["kind"], id: row["entityId"]) else { continue }
                    try db.execute(sql: "DELETE FROM outbox WHERE mutationId = ?", arguments: [result.mutationId.uuidString])
                    guard result.status == .rejected else { continue }

                    var message = result.message ?? "The server didn’t accept a change."
                    if let current = result.current {
                        try Self.upsert(db, farmId: farm, record: current, json: try encoder.encode(current))
                        var dropped: EntityKey?
                        if EntityKey(current.kind, current.entityId) != key {
                            if key.kind == .treeMark {
                                try db.execute(sql: "DELETE FROM records WHERE farmId = ? AND kind = ? AND id = ?",
                                               arguments: [farm, key.kind.rawValue, key.id.uuidString])
                                dropped = key
                            } else {
                                try Self.refetch(db, farmId: farm, key)
                            }
                            if key.kind == .shift, case .shift(let open) = current, open.isOpen {
                                let moved = try moveMarks(db, farmId: farmId, from: key.id, to: open, now: now, encoder: encoder)
                                snapshotChanges += moved.map { (.treeMark($0), nil) }
                                if !moved.isEmpty { message += " " + Self.movedTrees(moved.count) }
                            }
                        }
                        snapshotChanges.append((current, dropped))
                    } else {
                        try Self.refetch(db, farmId: farm, key)
                    }
                    rejections.append(Rejection(mutationId: result.mutationId, kind: key.kind, entityId: key.id, reason: result.reason,
                                                message: message, restoredFromServer: result.current != nil, current: result.current))
                }
                return .commit
            }
            updateSnapshot(farmId: farmId) { snapshot in
                for (record, dropped) in snapshotChanges {
                    if let dropped { snapshot.remove(kind: dropped.kind, id: dropped.id) }
                    if let record { snapshot.apply(record) }
                }
            }
            return try Self.count(db)
        }
        notify(.sync, pending)
        return rejections
    }

    /// "The 3 trees you marked moved to that shift."
    static func movedTrees(_ n: Int) -> String {
        n == 1 ? "The tree you marked moved to that shift." : "The \(n) trees you marked moved to that shift."
    }

    /// Moves the live marks of a refused shift onto `open` and queues them again at the back
    /// of the outbox (new mutation ids), so this pass pushes them after the answer.
    private func moveMarks(_ db: Database, farmId: UUID, from shiftId: UUID, to open: Shift, now: Date, encoder: JSONEncoder) throws -> [TreeMark] {
        let marks = state.withLock { state -> [TreeMark] in
            guard let snapshot = state.snapshot, snapshot.farmId == farmId else { return [] }
            return snapshot.marks.values.filter { $0.shiftId == shiftId }
        }
        let farm = farmId.uuidString
        let stamp = Self.ms(now)
        return try marks.sorted { ($0.blockId.uuidString, $0.row, $0.position) < ($1.blockId.uuidString, $1.row, $1.position) }.map { mark in
            var moved = mark
            moved.shiftId = open.id
            moved.userId = open.userId
            moved.updatedAt = max(now, mark.updatedAt.addingTimeInterval(0.001)).roundedToMillisecond
            let record = SyncRecord.treeMark(moved)
            let json = try encoder.encode(record)
            try Self.upsert(db, farmId: farm, record: record, json: json)
            try db.execute(sql: "DELETE FROM outbox WHERE farmId = ? AND kind = ? AND entityId = ?",
                           arguments: [farm, RecordKind.treeMark.rawValue, mark.id.uuidString])
            try db.execute(sql: """
                INSERT INTO outbox (mutationId, farmId, kind, entityId, json, createdAt) VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, farm, RecordKind.treeMark.rawValue, mark.id.uuidString, json, stamp])
            return moved
        }
    }

    // MARK: Small values

    /// Small preferences and cached answers (the last `/me`, settings).
    public func value(forKey key: String) throws -> Data? {
        try writer.read { db in try Data.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [key]) }
    }

    public func setValue(_ value: Data?, forKey key: String) throws {
        try writer.write { db in
            if let value {
                try db.execute(sql: "INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)", arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM kv WHERE key = ?", arguments: [key])
            }
        }
    }

    // MARK: Observation and reset

    /// A stream of changes, one per write, for as long as the caller keeps iterating.
    public func events() -> AsyncStream<StoreChange> {
        let (stream, continuation) = AsyncStream<StoreChange>.makeStream(bufferingPolicy: .bufferingNewest(256))
        let id = UUID()
        state.withLock { $0.observers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.observers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Forgets every record, queued change, cursor and stored value except `keeping`
    /// (sign-out, or a different person signing in on this phone). The active farm stays
    /// active, now empty.
    public func wipe(keeping keys: Set<String> = []) throws {
        try writer.writeWithoutTransaction { db in
            try db.inTransaction {
                for table in ["records", "outbox", "sync_state", "refetch"] {
                    try db.execute(sql: "DELETE FROM \(table)")
                }
                let kept = Array(keys)
                if kept.isEmpty {
                    try db.execute(sql: "DELETE FROM kv")
                } else {
                    let marks = Array(repeating: "?", count: kept.count).joined(separator: ", ")
                    try db.execute(sql: "DELETE FROM kv WHERE key NOT IN (\(marks))", arguments: StatementArguments(kept))
                }
                return .commit
            }
            state.withLock { state in
                if let farmId = state.snapshot?.farmId { state.snapshot = FarmSnapshot(farmId: farmId) }
            }
        }
        notify(.reset, 0)
    }

    // MARK: Helpers

    private func updateSnapshot(farmId: UUID, _ body: (inout FarmSnapshot) -> Void) {
        state.withLockUnchecked { state in
            guard var snapshot = state.snapshot, snapshot.farmId == farmId else { return }
            state.snapshot = nil // keep the dictionaries uniquely referenced while mutating
            body(&snapshot)
            state.snapshot = snapshot
        }
    }

    private func notify(_ origin: StoreChange.Origin, _ pending: Int) {
        let change = StoreChange(origin: origin, pendingCount: pending)
        let observers = state.withLock { Array($0.observers.values) }
        for observer in observers { observer.yield(change) }
    }

    private static func upsert(_ db: Database, farmId: String, record: SyncRecord, json: Data) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO records (kind, id, farmId, json, updatedAt, deletedAt) VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [record.kind.rawValue, record.entityId.uuidString, farmId, json, ms(record.updatedAt), record.deletedAt.map(ms)])
    }

    /// Asks the next pull to start from 0 and settle this record.
    private static func refetch(_ db: Database, farmId: String, _ key: EntityKey) throws {
        try db.execute(sql: "INSERT OR IGNORE INTO refetch (farmId, kind, id) VALUES (?, ?, ?)",
                       arguments: [farmId, key.kind.rawValue, key.id.uuidString])
        try setCursor(db, farmId: farmId, 0)
    }

    private static func setCursor(_ db: Database, farmId: String, _ cursor: Int64) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO sync_state (farmId, cursor) VALUES (?, ?)", arguments: [farmId, cursor])
    }

    private static func pendingEntities(_ db: Database, farmId: String) throws -> Set<EntityKey> {
        let rows = try Row.fetchAll(db, sql: "SELECT kind, entityId FROM outbox WHERE farmId = ?", arguments: [farmId])
        return Set(rows.compactMap { EntityKey(kind: $0["kind"], id: $0["entityId"]) })
    }

    private static func count(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox") ?? 0
    }

    static func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
}

/// A record's identity within a farm.
struct EntityKey: Hashable, Sendable {
    var kind: RecordKind
    var id: UUID

    init(_ kind: RecordKind, _ id: UUID) {
        self.kind = kind
        self.id = id
    }

    init?(kind: String, id: String) {
        guard let kind = RecordKind(rawValue: kind), let id = UUID(uuidString: id) else { return nil }
        self.init(kind, id)
    }
}
