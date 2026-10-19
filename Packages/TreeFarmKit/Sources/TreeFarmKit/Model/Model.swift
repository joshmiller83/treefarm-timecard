import Foundation

// The shared data model. Every record the server stores and the app syncs is
// declared here. Ids are client-made UUIDs so records can be created offline,
// and nothing is ever hard-deleted: a record is removed by setting `deletedAt`.

public enum Role: String, Codable, Sendable, CaseIterable {
    case admin
    case worker
}

public enum BreakKind: String, Codable, Sendable, CaseIterable {
    case lunch
    case `break`

    public var label: String { self == .lunch ? "Lunch" : "Break" }
}

/// How a block's rows run on the map. `across`: each row is a line, row numbers
/// down the left. `down`: each row is a column, row numbers across the top.
public enum RowDirection: String, Codable, Sendable, CaseIterable {
    case across
    case down
}

public enum NoteFlag: String, Codable, Sendable, CaseIterable {
    case none
    case attention
    case dead
    case replant

    public var label: String {
        switch self {
        case .none: "No flag"
        case .attention: "Needs attention"
        case .dead: "Dead"
        case .replant: "Replant"
        }
    }
}

/// Uses `Calendar` numbering, so `rawValue` can be assigned to `Calendar.firstWeekday`.
public enum Weekday: Int, Codable, Sendable, CaseIterable {
    case sunday = 1, monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6, saturday = 7
}

public struct Farm: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var timeZoneId: String
    public var weekStart: Weekday
    public var activeSeasonId: UUID?
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, timeZoneId: String, weekStart: Weekday = .monday, activeSeasonId: UUID? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.timeZoneId = timeZoneId
        self.weekStart = weekStart
        self.activeSeasonId = activeSeasonId
        self.updatedAt = updatedAt
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneId) ?? .current }
}

/// A person's place on a farm. Rates are per farm because pay is.
public struct Member: Codable, Hashable, Sendable, Identifiable {
    public var userId: UUID
    public var farmId: UUID
    public var displayName: String
    public var email: String
    public var role: Role
    public var jobTitle: String
    public var rateCents: Int
    public var updatedAt: Date
    /// Set when an admin removes someone. Their hours stay; they can no longer sign in to this farm.
    public var removedAt: Date?

    public var id: UUID { userId }

    public init(userId: UUID, farmId: UUID, displayName: String, email: String, role: Role, jobTitle: String = "", rateCents: Int = 0, updatedAt: Date = Date(), removedAt: Date? = nil) {
        self.userId = userId
        self.farmId = farmId
        self.displayName = displayName
        self.email = email
        self.role = role
        self.jobTitle = jobTitle
        self.rateCents = rateCents
        self.updatedAt = updatedAt
        self.removedAt = removedAt
    }
}

/// Tree marks belong to a season so each year starts with a clean map.
public struct Season: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var farmId: UUID
    public var name: String
    public var startedAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), farmId: UUID, name: String, startedAt: Date, updatedAt: Date = Date()) {
        self.id = id
        self.farmId = farmId
        self.name = name
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

public struct Field: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var farmId: UUID
    public var name: String
    public var sortOrder: Int
    public var archivedAt: Date?
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), farmId: UUID, name: String, sortOrder: Int = 0, archivedAt: Date? = nil, updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id
        self.farmId = farmId
        self.name = name
        self.sortOrder = sortOrder
        self.archivedAt = archivedAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// A rectangle of rows × trees. Blocks sit on a grid inside their field:
/// `gridRow` stacks strips of blocks top to bottom, `gridColumn` orders blocks left to right in a strip.
public struct Block: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var fieldId: UUID
    public var name: String
    public var gridRow: Int
    public var gridColumn: Int
    public var rowCount: Int
    public var treesPerRow: Int
    public var direction: RowDirection
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), fieldId: UUID, name: String, gridRow: Int, gridColumn: Int, rowCount: Int, treesPerRow: Int, direction: RowDirection = .across, updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id
        self.fieldId = fieldId
        self.name = name
        self.gridRow = gridRow
        self.gridColumn = gridColumn
        self.rowCount = rowCount
        self.treesPerRow = treesPerRow
        self.direction = direction
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var treeCount: Int { rowCount * treesPerRow }

    public func contains(_ tree: TreeRef) -> Bool {
        tree.blockId == id && (0..<rowCount).contains(tree.row) && (0..<treesPerRow).contains(tree.position)
    }

    public func contains(_ row: RowRef) -> Bool {
        row.blockId == id && (0..<rowCount).contains(row.row)
    }
}

/// A row in a block. `row` counts from 0; people see `row + 1`.
public struct RowRef: Codable, Hashable, Sendable {
    public var blockId: UUID
    public var row: Int

    public init(blockId: UUID, row: Int) {
        self.blockId = blockId
        self.row = row
    }
}

/// One tree, by position. Trees aren't stored on their own; marks and notes point at them.
/// `row` and `position` count from 0; people see them plus one.
public struct TreeRef: Codable, Hashable, Sendable {
    public var blockId: UUID
    public var row: Int
    public var position: Int

    public init(blockId: UUID, row: Int, position: Int) {
        self.blockId = blockId
        self.row = row
        self.position = position
    }

    public var rowRef: RowRef { RowRef(blockId: blockId, row: row) }
}

/// "This tree was shaped on this shift." At most one live mark per tree per season.
public struct TreeMark: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var seasonId: UUID
    public var blockId: UUID
    public var row: Int
    public var position: Int
    public var shiftId: UUID
    public var userId: UUID
    public var markedAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), seasonId: UUID, tree: TreeRef, shiftId: UUID, userId: UUID, markedAt: Date, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.seasonId = seasonId
        self.blockId = tree.blockId
        self.row = tree.row
        self.position = tree.position
        self.shiftId = shiftId
        self.userId = userId
        self.markedAt = markedAt
        self.updatedAt = updatedAt ?? markedAt
        self.deletedAt = deletedAt
    }

    public var tree: TreeRef { TreeRef(blockId: blockId, row: row, position: position) }
    public var isLive: Bool { deletedAt == nil }
}

/// A note on one tree. Notes outlive seasons: they follow the tree, not the year.
public struct TreeNote: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var farmId: UUID
    public var blockId: UUID
    public var row: Int
    public var position: Int
    public var authorId: UUID
    public var authorName: String
    public var body: String
    public var flag: NoteFlag
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), farmId: UUID, tree: TreeRef, authorId: UUID, authorName: String, body: String, flag: NoteFlag = .none, createdAt: Date, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.farmId = farmId
        self.blockId = tree.blockId
        self.row = tree.row
        self.position = tree.position
        self.authorId = authorId
        self.authorName = authorName
        self.body = body
        self.flag = flag
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    public var tree: TreeRef { TreeRef(blockId: blockId, row: row, position: position) }
    public var isLive: Bool { deletedAt == nil }
}

public struct Break: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: BreakKind
    public var start: Date
    public var end: Date?
    public var reason: String

    public init(id: UUID = UUID(), kind: BreakKind, start: Date, end: Date? = nil, reason: String = "") {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.reason = reason
    }

    public var isOpen: Bool { end == nil }
}

/// One stretch on the clock. Breaks live inside the shift, so a shift syncs as one record.
public struct Shift: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var farmId: UUID
    public var start: Date
    public var end: Date?
    public var breaks: [Break]
    public var notes: String
    /// The hourly rate when the shift was made, so a later raise doesn't rewrite past pay.
    public var rateCents: Int
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), userId: UUID, farmId: UUID, start: Date, end: Date? = nil, breaks: [Break] = [], notes: String = "", rateCents: Int, updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.farmId = farmId
        self.start = start
        self.end = end
        self.breaks = breaks
        self.notes = notes
        self.rateCents = rateCents
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isOpen: Bool { end == nil }
    public var isLive: Bool { deletedAt == nil }

    /// The break still running, if any. Only the latest break can be open.
    public var openBreak: Break? {
        guard let last = breaks.last, last.isOpen else { return nil }
        return last
    }
}

public struct UserProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var email: String
    public var displayName: String

    public init(id: UUID, email: String, displayName: String) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}

/// Sizes and lengths shared by the app's forms and the server's validation.
public enum Limits {
    public static let notes = 2000
    public static let reason = 80
    public static let name = 80
    public static let blockName = 40
    public static let blockRows: ClosedRange<Int> = 1...300
    public static let treesPerRow: ClosedRange<Int> = 1...300
    /// A closed shift can't run longer than this.
    public static let maxShift: TimeInterval = 24 * 3600
    /// An open shift past this probably means someone forgot to clock out.
    public static let forgotToClockOut: TimeInterval = 16 * 3600
    public static let undoDepth = 40
    /// How far ahead of the server clock a device's times may be.
    public static let clockSkew: TimeInterval = 5 * 60
    /// Mutations per sync push.
    public static let pushBatch = 200
    /// The highest hourly rate, in cents ($10,000), for Settings, the Team tab and the server.
    public static let maxRateCents = 1_000_000

    public static func clampNotes(_ s: String) -> String { clamp(s, notes) }
    public static func clampReason(_ s: String) -> String { clamp(s, reason) }
    public static func clampName(_ s: String) -> String { clamp(s, name) }
    public static func clampBlockName(_ s: String) -> String { clamp(s, blockName) }

    static func clamp(_ s: String, _ n: Int) -> String {
        String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(n))
    }
}
