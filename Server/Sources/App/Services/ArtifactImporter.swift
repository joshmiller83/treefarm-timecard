import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// Brings a time card exported from the original web artifact into a farm, for one
/// person. Records go through the same store as pushes, so they get seqs and every
/// device pulls them. Ids come from `StableID`, so running it again only adds what's
/// new: records already on the server are left as they are unless the export's copy
/// of a shift is newer, and nothing removed in the app comes back.
enum ArtifactImporter {
    struct Tally: Sendable {
        var added = 0
        var updated = 0
        var unchanged = 0
        var skipped = 0

        var text: String { "\(added) added, \(updated) updated, \(unchanged) unchanged, \(skipped) skipped" }
    }

    struct Summary: Sendable {
        var farmName = ""
        var email = ""
        var blocks = Tally()
        var shifts = Tally()
        var marks = Tally()
        var warnings: [String] = []

        var lines: [String] {
            ["Imported into \(farmName) for \(email):",
             "  Blocks: \(blocks.text)",
             "  Shifts: \(shifts.text)",
             "  Tree marks: \(marks.text) (\(marks.added + marks.updated) marks written)"]
                + warnings.map { "  Note: \($0)" }
        }
    }

    enum Failure: Error, CustomStringConvertible {
        case badFile(String)
        case noFarm
        case notOnFarm(String)
        case noSeason

        var description: String {
            switch self {
            case .badFile(let why): "That file isn’t an artifact export (\(why))."
            case .noFarm: "There’s no farm with that id."
            case .notOnFarm(let email): "\(email) isn’t a current member of that farm. Invite them first."
            case .noSeason: "The farm has no active season."
            }
        }
    }

    static func run(app: Application, farmId: UUID, email rawEmail: String, data: Data) async throws -> Summary {
        let export: ArtifactExport
        do {
            export = try JSONDecoder().decode(ArtifactExport.self, from: data)
        } catch let error as DecodingError {
            throw Failure.badFile(error.shortDescription)
        } catch {
            throw Failure.badFile("unreadable")
        }
        let email = Accounts.normalizeEmail(rawEmail)
        let now = app.now

        return try await app.db.transaction { db in
            let store = RecordStore(db: db)
            guard let farmRow = try await store.find(.farm, farmId, farm: farmId), case .farm(var farm) = farmRow.record else {
                throw Failure.noFarm
            }
            guard let user = try await UserModel.query(on: db).filter(\.$email == email).first(),
                  var member = try await store.member(user.id!, farm: farmId), member.removedAt == nil
            else { throw Failure.notOnFarm(email) }
            guard let seasonId = farm.activeSeasonId, try await store.season(seasonId, farm: farmId) != nil else {
                throw Failure.noSeason
            }
            let userId = user.id!
            let calendar = FarmCalendar(farm: farm)
            var summary = Summary(farmName: farm.name, email: email)

            let fieldId = try await firstLiveField(store, farmId: farmId, now: now)
            let result = ArtifactImport.run(export, farmId: farmId, fieldId: fieldId, userId: userId, seasonId: seasonId, now: now)
            summary.warnings += result.warnings

            // Blocks: new ones are added; the app's copy of an existing block wins.
            for block in result.blocks {
                guard let stored = try await store.block(block.id, farm: farmId) else {
                    try await store.save(.block(block), farm: farmId)
                    summary.blocks.added += 1
                    continue
                }
                summary.blocks.unchanged += 1
                if stored.rowCount != block.rowCount || stored.treesPerRow != block.treesPerRow {
                    summary.warnings.append("\(stored.displayName) is \(stored.rowCount) × \(stored.treesPerRow) here and \(block.rowCount) × \(block.treesPerRow) in the export. Kept the size here.")
                }
            }

            // Shifts: add new ones, update ones the export changed more recently, and check each with ShiftRules.
            var liveShiftIds = Set<UUID>()
            for incoming in result.shifts.map(ShiftRules.normalized) {
                let stored = try await store.shift(incoming.id, farm: farmId)
                if let stored, stored.userId != userId {
                    summary.shifts.skipped += 1
                    summary.warnings.append("Skipped the shift on \(Fmt.day(incoming.start, calendar)): it was imported for someone else.")
                    continue
                }
                if let stored, try ServerJSON.string(stored) == ServerJSON.string(incoming) || stored.updatedAt.millis >= incoming.updatedAt.millis {
                    summary.shifts.unchanged += 1
                    if stored.isLive { liveShiftIds.insert(stored.id) }
                    continue
                }
                let others = try await userShifts(store, userId: userId, farmId: farmId)
                if let problem = ShiftRules.validate(incoming, others: others, now: now, calendar: calendar, skew: Limits.clockSkew) {
                    summary.shifts.skipped += 1
                    summary.warnings.append("Skipped the shift on \(Fmt.day(incoming.start, calendar)): \(problem.message)")
                    continue
                }
                try await store.save(.shift(incoming), farm: farmId)
                if stored == nil { summary.shifts.added += 1 } else { summary.shifts.updated += 1 }
                liveShiftIds.insert(incoming.id)
            }

            // Marks: first commit wins, and a mark erased in the app stays erased.
            for mark in result.marks {
                guard liveShiftIds.contains(mark.shiftId) else {
                    summary.marks.skipped += 1
                    continue
                }
                if try await store.mark(mark.id, farm: farmId) != nil {
                    summary.marks.unchanged += 1
                    continue
                }
                if try await TreeClaims.claim(mark, farm: farmId, on: db) != nil {
                    summary.marks.skipped += 1
                    continue
                }
                try await store.save(.treeMark(mark), farm: farmId)
                summary.marks.added += 1
            }
            if summary.marks.skipped > 0 {
                summary.warnings.append("\(summary.marks.skipped) tree mark\(summary.marks.skipped == 1 ? " was" : "s were") skipped: the tree was already shaped on the server or its shift was skipped.")
            }

            // The person's name, job and rate on this farm.
            var changed = member
            if let name = result.displayName.map(Limits.clampName), !name.isEmpty { changed.displayName = name }
            if let job = result.jobTitle { changed.jobTitle = Limits.clampName(job) }
            if let rate = result.rateCents { changed.rateCents = rate }
            if changed != member {
                changed.updatedAt = now
                member = changed
                try await store.save(.member(member), farm: farmId)
            }

            // The farm's name and week start, only while the farm is as bootstrap left it.
            var newFarm = farm
            if let name = result.farmName.map(Limits.clampName), !name.isEmpty { newFarm.name = name }
            if let week = result.weekStart { newFarm.weekStart = week }
            if newFarm != farm {
                if farmRow.model.createdSeq == farmRow.model.seq {
                    newFarm.updatedAt = now
                    farm = newFarm
                    try await store.save(.farm(farm), farm: farmId)
                    summary.farmName = farm.name
                } else {
                    summary.warnings.append("Kept the farm’s name and week start: they were already changed in the app.")
                }
            }
            return summary
        }
    }

    /// The farm's first live field, or a new "Field 1".
    private static func firstLiveField(_ store: RecordStore, farmId: UUID, now: Date) async throws -> UUID {
        let fields = try await store.all(.field, farm: farmId).compactMap { row -> Field? in
            if case .field(let f) = row.record, f.deletedAt == nil, f.archivedAt == nil { return f }
            return nil
        }
        if let first = fields.min(by: { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }) { return first.id }
        let field = Field(farmId: farmId, name: "Field 1", sortOrder: 0, updatedAt: now)
        try await store.save(.field(field), farm: farmId)
        return field.id
    }

    private static func userShifts(_ store: RecordStore, userId: UUID, farmId: UUID) async throws -> [Shift] {
        try await store.all(.shift, farm: farmId) { $0.filter(\.$ownerUserId == userId).filter(\.$deletedAt == nil) }
            .compactMap { if case .shift(let s) = $0.record { return s }; return nil }
    }
}
