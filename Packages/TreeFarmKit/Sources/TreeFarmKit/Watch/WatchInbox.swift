import Foundation

/// The phone's ledger of watch requests it has answered, so a retried request (its reply
/// was lost, or arrived after the watch gave up waiting) gets the same answer again and
/// **does not run again**. The phone attaches a fresh state to the saved reply.
///
/// Replies are kept without their state, so 500 of them stay small. Entries older than
/// `maxAge` (7 days) or past `limit` (500) are forgotten.
///
/// It also keeps shift aliases: when a watch clock-in with minted id M is refused because
/// shift S is already open, the phone records M → S, and later requests tagged M act on S.
public struct WatchInbox: Codable, Hashable, Sendable {
    struct Entry: Codable, Hashable, Sendable {
        var reply: WatchReply
        var at: Date
    }

    struct Alias: Codable, Hashable, Sendable {
        var minted: UUID
        var shiftId: UUID
        var at: Date
    }

    public let limit: Int
    public let maxAge: TimeInterval
    /// Oldest first.
    private var entries: [Entry] = []
    private var aliases: [Alias] = []

    public init(limit: Int = 500, maxAge: TimeInterval = 7 * 86_400) {
        self.limit = max(1, limit)
        self.maxAge = maxAge
    }

    public var count: Int { entries.count }

    /// The saved reply to a request, without state.
    public func reply(for id: UUID) -> WatchReply? {
        entries.last { $0.reply.requestId == id }?.reply
    }

    /// Saves a reply (its state is dropped) and forgets what is too old or too many.
    /// An `unreadable` reply answers no request in particular and isn't kept.
    public mutating func record(_ reply: WatchReply, at now: Date) {
        guard reply.requestId != WatchReply.unreadableId else { return }
        var kept = reply
        kept.state = nil
        entries.removeAll { $0.reply.requestId == reply.requestId }
        entries.append(Entry(reply: kept, at: now))
        prune(now: now)
    }

    /// The ids of the last `count` requests answered, newest last (`WatchState.appliedRequestIds`).
    public func recentIds(_ count: Int) -> [UUID] {
        guard count > 0 else { return [] }
        return entries.suffix(count).map(\.reply.requestId)
    }

    /// The shift a request's `shiftId` means on the phone: itself, or the shift its minted
    /// id was aliased to.
    public func resolve(shiftId: UUID?) -> UUID? {
        guard var id = shiftId else { return nil }
        var seen: Set<UUID> = [id]
        while let next = aliases.last(where: { $0.minted == id })?.shiftId, seen.insert(next).inserted {
            id = next
        }
        return id
    }

    /// Records that requests tagged `minted` act on `shiftId`.
    public mutating func alias(_ minted: UUID, to shiftId: UUID, at now: Date) {
        aliases.removeAll { $0.minted == minted }
        aliases.append(Alias(minted: minted, shiftId: shiftId, at: now))
        prune(now: now)
    }

    /// Minted id → shift id.
    public var shiftAliases: [UUID: UUID] {
        Dictionary(aliases.map { ($0.minted, $0.shiftId) }) { _, last in last }
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-maxAge)
        entries.removeAll { $0.at < cutoff }
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        aliases.removeAll { $0.at < cutoff }
        if aliases.count > limit { aliases.removeFirst(aliases.count - limit) }
    }
}
