import Foundation

/// The original web artifact's database: settings, the field's blocks ("batches")
/// and shifts. Times are milliseconds since 1970 (JavaScript `Date.now()`), and a
/// shift's trees are `row * 1000 + tree` per block id, both counted from 0.
public struct ArtifactExport: Codable, Sendable {
    public struct Settings: Codable, Sendable {
        public var name: String?
        public var job: String?
        public var farm: String?
        /// Dollars an hour.
        public var rate: Double?
        /// 0 is Sunday, anything else Monday.
        public var weekStart: Int?

        public init(name: String? = nil, job: String? = nil, farm: String? = nil, rate: Double? = nil, weekStart: Int? = nil) {
            self.name = name
            self.job = job
            self.farm = farm
            self.rate = rate
            self.weekStart = weekStart
        }
    }

    public struct Batch: Codable, Sendable {
        public var id: String
        public var name: String?
        public var rows: Int
        public var trees: Int
        /// "down" or "across".
        public var dir: String?

        public init(id: String, name: String? = nil, rows: Int, trees: Int, dir: String? = nil) {
            self.id = id
            self.name = name
            self.rows = rows
            self.trees = trees
            self.dir = dir
        }
    }

    public struct FieldConfig: Codable, Sendable {
        public var batches: [Batch]

        public init(batches: [Batch]) {
            self.batches = batches
        }
    }

    public struct ABreak: Codable, Sendable {
        /// "lunch" or "break".
        public var type: String?
        public var start: Double
        public var end: Double?
        public var reason: String?

        public init(type: String? = nil, start: Double, end: Double? = nil, reason: String? = nil) {
            self.type = type
            self.start = start
            self.end = end
            self.reason = reason
        }
    }

    public struct AShift: Codable, Sendable {
        public var id: String
        public var start: Double
        public var end: Double?
        public var breaks: [ABreak]?
        public var notes: String?
        public var trees: [String: [Int]]?
        public var updatedAt: Double?

        public init(id: String, start: Double, end: Double? = nil, breaks: [ABreak]? = nil, notes: String? = nil, trees: [String: [Int]]? = nil, updatedAt: Double? = nil) {
            self.id = id
            self.start = start
            self.end = end
            self.breaks = breaks
            self.notes = notes
            self.trees = trees
            self.updatedAt = updatedAt
        }
    }

    public var settings: Settings?
    public var field: FieldConfig?
    public var shifts: [AShift]

    public init(settings: Settings? = nil, field: FieldConfig? = nil, shifts: [AShift] = []) {
        self.settings = settings
        self.field = field
        self.shifts = shifts
    }
}

/// Records ready to store, plus the person's settings and anything worth telling them.
public struct ArtifactImportResult: Sendable {
    public var blocks: [Block]
    public var shifts: [Shift]
    public var marks: [TreeMark]
    public var displayName: String?
    public var jobTitle: String?
    public var farmName: String?
    public var rateCents: Int?
    public var weekStart: Weekday?
    /// Plain sentences about what was skipped or changed.
    public var warnings: [String]

    public init(blocks: [Block] = [], shifts: [Shift] = [], marks: [TreeMark] = [], displayName: String? = nil, jobTitle: String? = nil,
                farmName: String? = nil, rateCents: Int? = nil, weekStart: Weekday? = nil, warnings: [String] = []) {
        self.blocks = blocks
        self.shifts = shifts
        self.marks = marks
        self.displayName = displayName
        self.jobTitle = jobTitle
        self.farmName = farmName
        self.rateCents = rateCents
        self.weekStart = weekStart
        self.warnings = warnings
    }
}

/// Turns an artifact export into records. Ids come from `StableID` keyed by the
/// farm and the artifact's own ids, so running it again updates instead of duplicating.
public enum ArtifactImport {
    public static func run(_ export: ArtifactExport, farmId: UUID, fieldId: UUID, userId: UUID, seasonId: UUID, now: Date) -> ArtifactImportResult {
        var result = ArtifactImportResult()
        if let s = export.settings {
            result.displayName = s.name
            result.jobTitle = s.job
            result.farmName = s.farm
            result.rateCents = s.rate.map { max(0, Int(($0 * 100).rounded())) }
            result.weekStart = s.weekStart.map { $0 == 0 ? .sunday : .monday }
        }

        // Blocks: one strip, in the artifact's order.
        var blocks: [String: Block] = [:]
        for batch in export.field?.batches ?? [] {
            guard blocks[batch.id] == nil else {
                result.warnings.append("Skipped a second block with the id \(batch.id).")
                continue
            }
            let column = result.blocks.count
            let name = Limits.clampBlockName(batch.name ?? "")
            let rows = clamp(batch.rows, Limits.blockRows), trees = clamp(batch.trees, Limits.treesPerRow)
            let block = Block(id: StableID.uuid(farmId, "block:\(batch.id)"), fieldId: fieldId, name: name.isEmpty ? "Block \(column + 1)" : name,
                              gridRow: 0, gridColumn: column, rowCount: rows, treesPerRow: trees,
                              direction: batch.dir == "down" ? .down : .across, updatedAt: now)
            if rows != batch.rows || trees != batch.trees {
                result.warnings.append("\(block.name) was \(batch.rows) rows × \(batch.trees) trees, so it is now \(rows) × \(trees).")
            }
            blocks[batch.id] = block
            result.blocks.append(block)
        }
        /// Known blocks in artifact order, then unknown keys by name.
        func rank(_ key: String) -> (Int, String) { (blocks[key]?.gridColumn ?? .max, key) }

        // Shifts, earliest first, so the earliest shift keeps a tree two shifts claim.
        let rate = result.rateCents ?? 0
        var taken = Set<TreeRef>()
        var unknown: [String: Int] = [:]
        var outside: [UUID: Int] = [:]
        var claimedTwice = 0
        for a in export.shifts.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
            let shift = Shift(
                id: StableID.uuid(farmId, "shift:\(a.id)"), userId: userId, farmId: farmId,
                start: date(a.start), end: a.end.map(date),
                breaks: (a.breaks ?? []).enumerated().map { i, b in
                    Break(id: StableID.uuid(farmId, "break:\(a.id):\(i)"), kind: b.type == "lunch" ? .lunch : .break,
                          start: date(b.start), end: b.end.map(date), reason: Limits.clampReason(b.reason ?? ""))
                },
                notes: Limits.clampNotes(a.notes ?? ""), rateCents: rate,
                updatedAt: a.updatedAt.flatMap { $0 > 0 ? date($0) : nil } ?? now)
            result.shifts.append(shift)

            let markedAt = shift.end ?? shift.start
            for key in (a.trees ?? [:]).keys.sorted(by: { rank($0) < rank($1) }) {
                let indexes = Set(a.trees?[key] ?? []).sorted()
                guard let block = blocks[key] else {
                    unknown[key, default: 0] += indexes.count
                    continue
                }
                for idx in indexes {
                    let tree = TreeRef(blockId: block.id, row: idx / 1000, position: idx % 1000)
                    guard idx >= 0, block.contains(tree) else {
                        outside[block.id, default: 0] += 1
                        continue
                    }
                    guard taken.insert(tree).inserted else {
                        claimedTwice += 1
                        continue
                    }
                    result.marks.append(TreeMark(id: StableID.uuid(farmId, "mark:\(seasonId.uuidString):\(key):\(idx)"), seasonId: seasonId,
                                                 tree: tree, shiftId: shift.id, userId: userId, markedAt: markedAt))
                }
            }
        }

        for (key, n) in unknown.sorted(by: { $0.key < $1.key }) {
            result.warnings.append("Skipped \(trees(n)) in a block that isn’t in the field (\(key)).")
        }
        for block in result.blocks {
            if let n = outside[block.id] { result.warnings.append("Skipped \(trees(n)) outside \(block.displayName).") }
        }
        if claimedTwice > 0 {
            result.warnings.append("\(trees(claimedTwice)) \(claimedTwice == 1 ? "was" : "were") marked on more than one shift. The earliest shift keeps each one.")
        }
        return result
    }

    private static func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    private static func clamp(_ n: Int, _ range: ClosedRange<Int>) -> Int { min(max(n, range.lowerBound), range.upperBound) }

    private static func trees(_ n: Int) -> String { "\(n) tree\(n == 1 ? "" : "s")" }
}
