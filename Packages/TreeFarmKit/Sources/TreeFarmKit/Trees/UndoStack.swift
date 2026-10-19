import Foundation

/// Fixed-depth undo: past `depth` entries the oldest falls off. Generic so the
/// app can keep richer entries (a mark change plus what to say, say).
public struct UndoStack<Entry: Sendable>: Sendable {
    public let depth: Int
    private var entries: [Entry] = []

    public init(depth: Int = Limits.undoDepth) {
        self.depth = max(1, depth)
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
