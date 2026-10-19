import AppIntents
import Foundation
import TreeFarmKit

/// A row Siri on the watch can mark: "Mark row 14 in Time Card". It's said as "row 14", and
/// its id is "<blockId>-<row>" (the row counts from 0).
struct WatchRowEntity: AppEntity, Equatable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Row" }
    static var defaultQuery: WatchRowQuery { WatchRowQuery() }

    var id: String
    var blockId: UUID
    /// Counts from 0.
    var row: Int
    /// "Block 2", or "" when the watch doesn't know the block's name.
    var blockName: String

    init(blockId: UUID, row: Int, blockName: String) {
        self.id = Self.id(blockId: blockId, row: row)
        self.blockId = blockId
        self.row = row
        self.blockName = blockName
    }

    init(chip: RowChip) {
        self.init(blockId: chip.blockId, row: chip.row, blockName: chip.blockName)
    }

    var rowRef: RowRef { RowRef(blockId: blockId, row: row) }

    /// "row 14"
    var displayTitle: String { "row \(row + 1)" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayTitle)",
                              subtitle: blockName.isEmpty ? nil : "\(blockName)",
                              synonyms: ["\(WatchSpokenNumber.words(row + 1))", "row \(WatchSpokenNumber.words(row + 1))"])
    }

    static func id(blockId: UUID, row: Int) -> String {
        "\(blockId.uuidString)-\(row)"
    }

    /// The row an id names. The block id has dashes of its own, so the row is after the last.
    static func parse(id: String) -> RowRef? {
        guard let dash = id.lastIndex(of: "-"), let block = UUID(uuidString: String(id[..<dash])),
              let row = Int(id[id.index(after: dash)...]), row >= 0 else { return nil }
        return RowRef(blockId: block, row: row)
    }
}

/// Siri's rows, from the watch's displayed state.
struct WatchRowQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WatchRowEntity] {
        let state = await MainActor.run { WatchIntentRunner.model.displayed }
        return WatchRowCatalog.rows(ids: identifiers, state: state)
    }

    func suggestedEntities() async throws -> [WatchRowEntity] {
        let state = await MainActor.run { WatchIntentRunner.model.displayed }
        return WatchRowCatalog.suggested(state)
    }

    func entities(matching string: String) async throws -> [WatchRowEntity] {
        let state = await MainActor.run { WatchIntentRunner.model.displayed }
        return WatchRowCatalog.rows(matching: string, state: state)
    }
}

/// The rows behind `WatchRowQuery`, from a state (pure, so it's tested without Siri).
enum WatchRowCatalog {
    /// How many rows Siri suggests (and fills "Mark row 14" phrases with).
    static let suggestedCount = 10

    /// The first ten chips the watch shows.
    static func suggested(_ state: WatchState?) -> [WatchRowEntity] {
        (state?.nextRows ?? []).prefix(suggestedCount).map(WatchRowEntity.init(chip:))
    }

    static func rows(ids: [String], state: WatchState?) -> [WatchRowEntity] {
        ids.compactMap { id in
            guard let row = WatchRowEntity.parse(id: id) else { return nil }
            let name = state?.nextRows.first { $0.blockId == row.blockId }?.blockName ?? ""
            return WatchRowEntity(blockId: row.blockId, row: row.row, blockName: name)
        }
    }

    /// A spoken number is a row in the block you're in, even one that isn't a chip ("Mark row
    /// 40"); `WatchConfirm` asks before marking one that far. With no chips, nothing: Siri then
    /// says the no-chip line.
    static func rows(matching text: String, state: WatchState?) -> [WatchRowEntity] {
        guard let here = state?.nextRows.first, let number = WatchSpokenNumber.parse(text), number >= 1 else { return [] }
        return [WatchRowEntity(blockId: here.blockId, row: number - 1, blockName: here.blockName)]
    }
}

/// Numbers as Siri writes down what someone said: "14", "fourteen", "row twenty-two",
/// "one hundred and five".
enum WatchSpokenNumber {
    private static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    /// The first number in the text, or nil.
    static func parse(_ text: String) -> Int? {
        let tokens = text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if let digits = tokens.first(where: { $0.allSatisfy(\.isNumber) }) { return Int(digits) }
        var value: Int?
        for token in tokens {
            if let n = units.firstIndex(of: token) {
                value = (value ?? 0) + n
            } else if let n = tens.firstIndex(of: token), n >= 2 {
                value = (value ?? 0) + n * 10
            } else if token == "hundred" {
                value = max(1, value ?? 1) * 100
            } else if token == "and", value != nil {
                continue
            } else if value != nil {
                break
            }
        }
        return value
    }

    /// "fourteen", "forty-two", "one hundred five" (1 through 999).
    static func words(_ n: Int) -> String {
        guard (0..<1000).contains(n) else { return String(n) }
        if n < 20 { return units[n] }
        if n < 100 { return tens[n / 10] + (n % 10 == 0 ? "" : "-" + units[n % 10]) }
        let rest = n % 100
        return units[n / 100] + " hundred" + (rest == 0 ? "" : " " + words(rest))
    }
}
