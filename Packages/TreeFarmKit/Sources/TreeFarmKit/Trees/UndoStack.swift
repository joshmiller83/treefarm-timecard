import Foundation

/// Fixed-depth undo: past `depth` entries the oldest falls off. Generic so the
/// app can keep richer entries (a mark change plus what to say, say).
public struct UndoStack<Entry: Sendable>: Sendable {
    public let depth: Int
    /// Oldest first.
    public private(set) var entries: [Entry] = []

    public init(depth: Int = Limits.undoDepth) {
        self.depth = max(1, depth)
    }

    /// A stack restored from saved entries (oldest first); extras past `depth` fall off the old end.
    public init(depth: Int = Limits.undoDepth, entries: [Entry]) {
        self.depth = max(1, depth)
        self.entries = Array(entries.suffix(self.depth))
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    public mutating func push(_ e: Entry) {
        entries.append(e)
        if entries.count > depth { entries.removeFirst(entries.count - depth) }
    }

    public mutating func pop() -> Entry? {
        entries.popLast()
    }

    /// Drops entries that can no longer be undone, such as ones for a deleted shift.
    public mutating func removeAll(where shouldRemove: (Entry) -> Bool) {
        entries.removeAll(where: shouldRemove)
    }
}

extension UndoStack: Codable where Entry: Codable {
    private enum CodingKeys: String, CodingKey { case depth, entries }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(depth: try c.decode(Int.self, forKey: .depth), entries: try c.decode([Entry].self, forKey: .entries))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(depth, forKey: .depth)
        try c.encode(entries, forKey: .entries)
    }
}
