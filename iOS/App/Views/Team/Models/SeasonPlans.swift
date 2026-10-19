import Foundation
import TimeCardCore

/// Seasons: tree marks belong to one, so starting a new season gives a clean map while
/// last season's marks stay in reports. Notes aren't seasonal; they follow the tree.
enum SeasonPlans {
    struct Row: Identifiable, Equatable {
        var season: Season
        var shaped: Int
        var isActive: Bool
        var id: UUID { season.id }
    }

    struct FieldProgress: Identifiable, Equatable {
        var field: Field
        var shaped: Int
        var total: Int
        var id: UUID { field.id }
        var fraction: Double { total == 0 ? 0 : Double(shaped) / Double(total) }
    }

    /// The next season's name: the year after the active one when it's named for a year,
    /// else this year on the farm, moving on a year while the name is taken.
    static func suggestedName(seasons: [Season], active: Season?, now: Date, calendar: FarmCalendar) -> String {
        let taken = Set(seasons.map { $0.name.trimmingCharacters(in: .whitespaces) })
        var year = calendar.dayKey(now).year
        if let name = active?.name.trimmingCharacters(in: .whitespaces), name.count == 4, let activeYear = Int(name) {
            year = max(year, activeYear + 1)
        }
        while taken.contains(String(year)) { year += 1 }
        return String(year)
    }

    /// The new season, and the farm pointing at it.
    static func start(name: String, farm: Farm, now: Date) -> TeamEdit {
        if let problem = TeamErrors.nameProblem(name, thing: "season") { return .problem(problem) }
        let stamp = now.roundedToMillisecond
        let season = Season(farmId: farm.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), startedAt: stamp, updatedAt: stamp)
        var updated = farm
        updated.activeSeasonId = season.id
        updated.updatedAt = max(stamp, farm.updatedAt.addingTimeInterval(0.001))
        return .save([.season(season), .farm(updated)])
    }

    /// Every season, newest first, with the trees shaped in it.
    static func rows(_ snapshot: FarmSnapshot) -> [Row] {
        var shaped: [UUID: Int] = [:]
        for mark in snapshot.marks.values where mark.isLive { shaped[mark.seasonId, default: 0] += 1 }
        let active = snapshot.farm?.activeSeasonId
        return snapshot.seasons.values
            .sorted { ($0.startedAt, $0.id.uuidString) > ($1.startedAt, $1.id.uuidString) }
            .map { Row(season: $0, shaped: shaped[$0.id] ?? 0, isActive: $0.id == active) }
    }

    /// This season's shaped trees in each field that's in use.
    static func progress(_ snapshot: FarmSnapshot) -> [FieldProgress] {
        let season = snapshot.farm?.activeSeasonId
        let index = MarkIndex(marks: snapshot.marks.values.filter { $0.seasonId == season })
        let blocks = Dictionary(grouping: snapshot.blocks.values.filter { $0.deletedAt == nil }, by: \.fieldId)
        return FieldPlans.sorted(Array(snapshot.fields.values)).active.map { field in
            let inField = blocks[field.id] ?? []
            return FieldProgress(field: field, shaped: inField.reduce(0) { $0 + index.shapedCount(in: $1) },
                                 total: inField.reduce(0) { $0 + $1.treeCount })
        }
    }
}
