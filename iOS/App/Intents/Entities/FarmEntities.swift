import AppIntents
import Foundation
import TimeCardCore

// The farm's places as Siri and Shortcuts see them. Each query reads the farm through
// `IntentRunner.fieldState()`, the same view the field actions use, and leaves the naming
// and matching to `VoiceCatalog`.

/// One row of a block. Siri learns the next ten open rows by name (`suggestedEntities`), so
/// "Mark row 14 in Time Card" is a single phrase; after each change the app tells Siri the
/// new ones (`updateAppShortcutParameters`).
struct RowEntity: AppEntity, Equatable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Row" }
    static var defaultQuery: RowQuery { RowQuery() }

    var id: String
    var blockId: UUID
    /// Counts from 0.
    var row: Int
    /// "Row 14", or "Row 1 in block 2" outside the block you're in.
    var title: String
    var blockName: String
    var fieldName: String
    var synonyms: [String]

    init(blockId: UUID, row: Int, title: String, blockName: String, fieldName: String, synonyms: [String] = []) {
        self.id = Self.id(blockId: blockId, row: row)
        self.blockId = blockId
        self.row = row
        self.title = title
        self.blockName = blockName
        self.fieldName = fieldName
        self.synonyms = synonyms
    }

    var rowRef: RowRef { RowRef(blockId: blockId, row: row) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(blockName) · \(fieldName)", synonyms: synonyms.map { "\($0)" })
    }

    static func id(blockId: UUID, row: Int) -> String {
        "\(blockId.uuidString)#\(row)"
    }

    static func parse(id: String) -> RowRef? {
        let parts = id.split(separator: "#")
        guard parts.count == 2, let block = UUID(uuidString: String(parts[0])), let row = Int(parts[1]), row >= 0 else { return nil }
        return RowRef(blockId: block, row: row)
    }
}

struct RowQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RowEntity] {
        guard let state = await IntentRunner.fieldState() else { return [] }
        return VoiceCatalog.rows(ids: identifiers, state: state)
    }

    func suggestedEntities() async throws -> [RowEntity] {
        guard let state = await IntentRunner.fieldState() else { return [] }
        return VoiceCatalog.suggestedRows(state)
    }

    func entities(matching string: String) async throws -> [RowEntity] {
        guard let state = await IntentRunner.fieldState() else { return [] }
        return VoiceCatalog.rows(matching: string, state: state)
    }
}

/// A block, said by its name: "block 3", "North 3".
struct BlockEntity: AppEntity, Equatable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Block" }
    static var defaultQuery: BlockQuery { BlockQuery() }

    var id: String
    var blockId: UUID
    /// "Block 3", or a longer name as typed.
    var title: String
    var fieldName: String
    var synonyms: [String]

    init(blockId: UUID, title: String, fieldName: String, synonyms: [String] = []) {
        self.id = blockId.uuidString
        self.blockId = blockId
        self.title = title
        self.fieldName = fieldName
        self.synonyms = synonyms
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(fieldName)", synonyms: synonyms.map { "\($0)" })
    }
}

struct BlockQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [BlockEntity] {
        guard let state = await IntentRunner.fieldState() else { return [] }
        return VoiceCatalog.blocks(ids: identifiers, state: state)
    }

    func suggestedEntities() async throws -> [BlockEntity] {
        guard let state = await IntentRunner.fieldState() else { return [] }
        return VoiceCatalog.blocks(state)
    }

    func entities(matching string: String) async throws -> [BlockEntity] {
        guard let state = await IntentRunner.fieldState() else { return [] }
        return VoiceCatalog.blocks(matching: string, state: state)
    }
}

/// A field: "North Field", or just "North".
struct FieldEntity: AppEntity, Equatable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Field" }
    static var defaultQuery: FieldQuery { FieldQuery() }

    var id: String
    var fieldId: UUID
    var title: String
    var synonyms: [String]

    init(fieldId: UUID, title: String, synonyms: [String] = []) {
        self.id = fieldId.uuidString
        self.fieldId = fieldId
        self.title = title
        self.synonyms = synonyms
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", synonyms: synonyms.map { "\($0)" })
    }
}

struct FieldQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [FieldEntity] {
        guard let state = await IntentRunner.fieldState() else { return [] }
        return VoiceCatalog.fields(ids: identifiers, state: state)
    }

    func suggestedEntities() async throws -> [FieldEntity] {
        guard let state = await IntentRunner.fieldState() else { return [] }
        return VoiceCatalog.fields(state)
    }

    func entities(matching string: String) async throws -> [FieldEntity] {
        guard let state = await IntentRunner.fieldState() else { return [] }
        return VoiceCatalog.fields(matching: string, state: state)
    }
}
