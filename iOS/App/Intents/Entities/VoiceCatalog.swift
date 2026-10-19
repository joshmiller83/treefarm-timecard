import Foundation
import TimeCardCore

/// The rows, blocks and fields Siri can name, built from the farm as the field actions see
/// it, and the matching of what someone said ("row fourteen", "block three", "the creek
/// field") to them. Pure functions of a `FieldState`, so they're tested without Siri.
enum VoiceCatalog {
    /// How many upcoming rows Siri learns by name, so "Mark row 14 in Time Card" works as
    /// one phrase.
    static let suggestedRowCount = 10

    // MARK: Rows

    /// The next open rows from where you are: what you're most likely to say next.
    static func suggestedRows(_ state: FieldState, count: Int = suggestedRowCount) -> [RowEntity] {
        let here = state.nextRows(1).first?.blockId
        return state.nextRows(count).compactMap { row(for: $0, state: state, here: here) }
    }

    /// One row as Siri names it. Rows in the block you're in are "Row 14"; others say their
    /// block: "Row 1 in block 2".
    static func row(for ref: RowRef, state: FieldState, here: UUID?? = nil) -> RowEntity? {
        guard let block = state.block(ref.blockId), let field = state.field(block.fieldId), ref.row >= 0 else { return nil }
        let current = here ?? state.nextRows(1).first?.blockId
        let number = ref.row + 1
        let title = current == block.id ? "Row \(number)" : "Row \(number) in \(Speech.blockPhrase(block))"
        return RowEntity(blockId: block.id, row: ref.row, title: title, blockName: Speech.blockTitle(block), fieldName: field.name,
                         synonyms: ["row \(SpokenNumber.words(number))", "row \(number) in \(Speech.blockPhrase(block))"])
    }

    /// What someone said when asked "Which row?": "14", "fourteen", "row 3 in block 2",
    /// "block three row two". Without a block it's the block you're in. Rows past the end
    /// of the block still come back, so the answer can say what the block's rows are.
    static func rows(matching text: String, state: FieldState) -> [RowEntity] {
        var words = " " + SpokenNumber.digitized(text) + " "
        var blockId = state.nextRows(1).first?.blockId ?? state.currentField.flatMap { state.walker(for: $0).blocks.first?.id }
        if let named = namedBlock(in: words, state: state) {
            blockId = named.block.id
            words = words.replacingOccurrences(of: " \(named.key) ", with: " ")
        } else if words.contains(" block ") {
            return []
        }
        guard let blockId, let number = SpokenNumber.parse(words), number >= 1 else { return [] }
        return row(for: RowRef(blockId: blockId, row: number - 1), state: state).map { [$0] } ?? []
    }

    static func rows(ids: [String], state: FieldState) -> [RowEntity] {
        let here = state.nextRows(1).first?.blockId
        return ids.compactMap { RowEntity.parse(id: $0) }.compactMap { row(for: $0, state: state, here: here) }
    }

    // MARK: Blocks

    /// The field you're in first, in walk order, then the other fields' blocks.
    static func blocks(_ state: FieldState) -> [BlockEntity] {
        orderedFields(state).flatMap { field in
            state.walker(for: field).blocks.map { block(for: $0, field: field) }
        }
    }

    static func block(for block: Block, field: Field) -> BlockEntity {
        var synonyms: [String] = []
        let name = block.name.trimmingCharacters(in: .whitespaces)
        if let n = Int(name) { synonyms.append("block \(SpokenNumber.words(n))") }
        return BlockEntity(blockId: block.id, title: Speech.blockTitle(block), fieldName: field.name, synonyms: synonyms)
    }

    /// "block three", "3", "North 3", "I'm in block 3".
    static func blocks(matching text: String, state: FieldState) -> [BlockEntity] {
        let said = normalized(text)
        let all = orderedFields(state).flatMap { field in state.walker(for: field).blocks.map { ($0, field) } }
        let exact = all.filter { keys(for: $0.0).contains(said) || keys(for: $0.0).contains(strip(said, ["the"])) }
        let found = exact.isEmpty ? all.filter { pair in keys(for: pair.0).contains { $0.contains(" ") && " \(said) ".contains(" \($0) ") } } : exact
        guard let firstField = found.first?.1.id else { return [] }
        // A block in the field you're in wins over one with the same name elsewhere.
        return found.filter { $0.1.id == firstField }.map { block(for: $0.0, field: $0.1) }
    }

    static func blocks(ids: [String], state: FieldState) -> [BlockEntity] {
        ids.compactMap(UUID.init(uuidString:)).compactMap { id in
            guard let b = state.block(id), let f = state.field(b.fieldId) else { return nil }
            return block(for: b, field: f)
        }
    }

    // MARK: Fields

    static func fields(_ state: FieldState) -> [FieldEntity] {
        state.liveFields.map(field(for:))
    }

    static func field(for field: Field) -> FieldEntity {
        let short = shortName(field.name)
        return FieldEntity(fieldId: field.id, title: field.name,
                           synonyms: short == field.name ? ["the \(field.name)"] : [short, "the \(field.name)"])
    }

    /// "creek", "the Creek field", "Creek Field".
    static func fields(matching text: String, state: FieldState) -> [FieldEntity] {
        let said = strip(normalized(text), ["the"])
        let saidShort = normalized(shortName(said))
        let live = state.liveFields
        let exact = live.filter { [normalized($0.name), normalized(shortName($0.name))].contains(where: { $0 == said || $0 == saidShort }) }
        let found = exact.isEmpty ? live.filter { " \(said) ".contains(" \(normalized(shortName($0.name))) ") } : exact
        return found.map(field(for:))
    }

    static func fields(ids: [String], state: FieldState) -> [FieldEntity] {
        ids.compactMap(UUID.init(uuidString:)).compactMap { id in state.liveFields.first { $0.id == id } }.map(field(for:))
    }

    // MARK: Matching

    private static func orderedFields(_ state: FieldState) -> [Field] {
        let current = state.currentField
        return (current.map { [$0] } ?? []) + state.liveFields.filter { $0.id != current?.id }
    }

    /// The ways a block can be said: its name and its title ("3" and "block 3").
    private static func keys(for block: Block) -> Set<String> {
        [normalized(block.name), normalized(Speech.blockTitle(block))]
    }

    /// A block named in the words ("in block 2", "north 3"), the field you're in first.
    private static func namedBlock(in words: String, state: FieldState) -> (block: Block, key: String)? {
        for field in orderedFields(state) {
            for block in state.walker(for: field).blocks {
                // Only keys with a space ("block 3", "north 3"), so a bare row number isn't taken for a block.
                for key in keys(for: block) where key.contains(" ") && words.contains(" \(key) ") {
                    return (block, key)
                }
            }
        }
        return nil
    }

    /// Lowercase words, numbers as digits, single spaces.
    static func normalized(_ text: String) -> String {
        SpokenNumber.digitized(text)
    }

    private static func strip(_ text: String, _ leading: [String]) -> String {
        var words = text.split(separator: " ").map(String.init)
        while let first = words.first, leading.contains(first) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// "North Field" → "North".
    private static func shortName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        for suffix in [" field", " Field", " FIELD"] where trimmed.hasSuffix(suffix) && trimmed.count > suffix.count {
            return String(trimmed.dropLast(suffix.count))
        }
        return trimmed
    }
}
