import Foundation
import TimeCardCore

/// Launch arguments for UI-test runs of the Team tab (only read when `-UITestInMemory` is on):
///
/// - `-UITestTeamSection crew|fields|season` opens the tab on that section.
/// - `-UITestTeamWeek` fills the last two weeks with shifts for the demo crew, puts the
///   worker on the clock, and adds a former crew member, so there are hours to show.
/// - `-UITestTeamForgot` (with `-UITestTeamWeek`) starts the worker's open shift 26 hours
///   ago instead of 3, so the crew list shows a forgotten clock-out.
/// - `-UITestTeamWaiting` holds the Fields and Season sections on "Getting the farm from
///   the server…", the way they look before the first pull lands.
@MainActor
enum TeamScenario {
    static let sectionArgument = "-UITestTeamSection"
    static let weekArgument = "-UITestTeamWeek"
    static let forgotArgument = "-UITestTeamForgot"
    static let waitingArgument = "-UITestTeamWaiting"

    /// Pretend the first pull hasn't landed (UI tests only).
    static var forceWaiting: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains(LaunchMode.inMemoryArgument) && args.contains(waitingArgument)
    }

    static var section: TeamView.Section? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains(LaunchMode.inMemoryArgument), let i = args.firstIndex(of: sectionArgument), i + 1 < args.count else { return nil }
        return TeamView.Section(rawValue: args[i + 1])
    }

    private static var applied = false

    static func applyIfRequested(_ session: TimeCardSession, arguments: [String] = ProcessInfo.processInfo.arguments, now: Date = Date()) async {
        guard !applied, arguments.contains(LaunchMode.inMemoryArgument), arguments.contains(weekArgument) else { return }
        applied = true
        // Wait for the first pull so the crew's records are here.
        for _ in 0..<40 where session.snapshot.members.count < 2 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let farm = session.farm else { return }
        try? session.save(weekRecords(snapshot: session.snapshot, farm: farm, now: now, forgot: arguments.contains(forgotArgument)))
    }

    /// Closed shifts 7:00–3:30 with a half-hour lunch on each weekday of the last two weeks
    /// before today, an open one for the worker that began three hours ago (26 when `forgot`),
    /// and a former trimmer with one shift.
    static func weekRecords(snapshot: FarmSnapshot, farm: Farm, now: Date, forgot: Bool = false) -> [SyncRecord] {
        let calendar = FarmCalendar(farm: farm)
        let members = snapshot.members.values.sorted { $0.displayName < $1.displayName }
        let today = calendar.startOfDay(now)
        let weekStart = calendar.startOfWeek(containing: now)
        let worker = members.first(where: { $0.role == .worker })
        let openStart = now.addingTimeInterval(-((forgot ? 26 : 3) * 3600 + 12 * 60)).roundedToMillisecond
        var records: [SyncRecord] = []
        for back in stride(from: 13, through: 1, by: -1) {
            let day = calendar.addDays(today, -back)
            let weekday = calendar.calendar.component(.weekday, from: day)
            guard weekday != 1 && weekday != 7 else { continue }
            let key = calendar.dayKey(day)
            for (index, member) in members.enumerated() {
                let start = calendar.date(on: key, hour: 7, minute: index * 10)
                let lunch = Break(kind: .lunch, start: calendar.date(on: key, hour: 11, minute: 30 + index * 5),
                                  end: calendar.date(on: key, hour: 12, minute: index * 5))
                let end = calendar.date(on: key, hour: 15, minute: 30 + index * 10)
                // The worker's open shift can't overlap a closed one.
                if member.userId == worker?.userId, end > openStart { continue }
                records.append(.shift(Shift(userId: member.userId, farmId: farm.id, start: start, end: end,
                                            breaks: [lunch], rateCents: member.rateCents, updatedAt: start)))
            }
        }
        if let worker {
            let start = openStart
            let open = Shift(userId: worker.userId, farmId: farm.id, start: start, rateCents: worker.rateCents, updatedAt: start)
            records.append(.shift(open))
            // Two rows shaped so far, in the first block of the first field.
            let field = FieldPlans.sorted(Array(snapshot.fields.values)).active.first
            if let season = snapshot.activeSeason, let field,
               let block = FieldWalker(blocks: snapshot.blocks.values.filter { $0.fieldId == field.id }).blocks.first {
                let taken = Set(snapshot.marks.values.filter { $0.seasonId == season.id }.map(\.tree))
                let free = (0..<block.rowCount).lazy.filter { row in !taken.contains(TreeRef(blockId: block.id, row: row, position: 0)) }
                for (n, row) in free.prefix(2).enumerated() {
                    for position in 0..<block.treesPerRow {
                        let at = start.addingTimeInterval(Double(n * block.treesPerRow + position + 1) * 300)
                        records.append(.treeMark(TreeMark(seasonId: season.id, tree: TreeRef(blockId: block.id, row: row, position: position),
                                                          shiftId: open.id, userId: worker.userId, markedAt: at.roundedToMillisecond)))
                    }
                }
            }
        }
        let formerId = UUID(uuidString: "00000000-0000-0000-0000-0000000F0123")!
        let removed = calendar.addDays(weekStart, -3)
        let former = Member(userId: formerId, farmId: farm.id, displayName: "Jo Banks", email: "", role: .worker,
                            jobTitle: "Trimmer", updatedAt: removed, removedAt: removed)
        let earlier = calendar.addDays(weekStart, -5)
        let key = calendar.dayKey(earlier)
        records.append(.member(former))
        records.append(.shift(Shift(userId: formerId, farmId: farm.id, start: calendar.date(on: key, hour: 7, minute: 0),
                                    end: calendar.date(on: key, hour: 13, minute: 0), rateCents: 0, updatedAt: removed)))
        return records
    }
}
