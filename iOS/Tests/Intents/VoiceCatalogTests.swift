import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// The rows, blocks and fields Siri can name, and how what someone said is matched to them.
@MainActor
@Suite("Siri's rows, blocks and fields")
struct VoiceCatalogTests {
    @Test func rowSuggestionsAreTheNextTenOpenRows() async throws {
        let model = await Demo.model()
        let rows = VoiceCatalog.suggestedRows(try Demo.state(model))
        #expect(rows.map(\.title) == (5...14).map { "Row \($0)" })
        let block1 = try Demo.block(model, "1")
        #expect(rows.allSatisfy { $0.blockId == block1.id && $0.blockName == "Block 1" && $0.fieldName == "North Field" })
        #expect(rows.first?.rowRef == RowRef(blockId: block1.id, row: 4))
    }

    @Test func rowsInTheNextBlockSayWhichBlock() async throws {
        let model = await Demo.model()
        _ = await Demo.voice(model).moveTo(block: try Demo.block(model, "1").id, row: 15)
        let rows = VoiceCatalog.suggestedRows(try Demo.state(model))
        #expect(rows.map(\.title) == ["Row 15", "Row 16", "Row 17", "Row 18", "Row 19", "Row 20",
                                      "Row 1 in block 2", "Row 2 in block 2", "Row 3 in block 2", "Row 4 in block 2"])
    }

    @Test func aSpokenRowIsInTheCurrentBlockUnlessOneIsNamed() async throws {
        let model = await Demo.model()
        let state = try Demo.state(model)
        let block1 = try Demo.block(model, "1"), block2 = try Demo.block(model, "2"), block3 = try Demo.block(model, "3")
        #expect(VoiceCatalog.rows(matching: "14", state: state).map(\.rowRef) == [RowRef(blockId: block1.id, row: 13)])
        #expect(VoiceCatalog.rows(matching: "fourteen", state: state).map(\.rowRef) == [RowRef(blockId: block1.id, row: 13)])
        #expect(VoiceCatalog.rows(matching: "Row 14", state: state).map(\.rowRef) == [RowRef(blockId: block1.id, row: 13)])
        #expect(VoiceCatalog.rows(matching: "row 3 in block 2", state: state).map(\.rowRef) == [RowRef(blockId: block2.id, row: 2)])
        #expect(VoiceCatalog.rows(matching: "block three row two", state: state).map(\.rowRef) == [RowRef(blockId: block3.id, row: 1)])
        // A number past the block's end still comes back, so the answer can say the range.
        #expect(VoiceCatalog.rows(matching: "40", state: state).map(\.rowRef) == [RowRef(blockId: block1.id, row: 39)])
        #expect(VoiceCatalog.rows(matching: "row 2 in block 9", state: state).isEmpty)
        #expect(VoiceCatalog.rows(matching: "hello", state: state).isEmpty)
        #expect(VoiceCatalog.rows(matching: "0", state: state).isEmpty)
    }

    @Test func rowIdsComeBack() async throws {
        let model = await Demo.model()
        let state = try Demo.state(model)
        let rows = VoiceCatalog.suggestedRows(state)
        #expect(VoiceCatalog.rows(ids: rows.map(\.id), state: state) == rows)
        #expect(VoiceCatalog.rows(ids: ["nonsense", "\(UUID().uuidString)#3"], state: state).isEmpty)
    }

    @Test func blocksByNameOrNumber() async throws {
        let model = await Demo.model()
        let state = try Demo.state(model)
        let blocks = VoiceCatalog.blocks(state)
        #expect(blocks.prefix(4).map(\.title) == ["Block 1", "Block 2", "Block 3", "Block 4"])
        #expect(blocks.prefix(4).allSatisfy { $0.fieldName == "North Field" })
        #expect(blocks.count == 5, "the other field's blocks come after")
        let block3 = try Demo.block(model, "3")
        for said in ["block three", "Block 3", "3", "three", "I’m in block 3"] {
            #expect(VoiceCatalog.blocks(matching: said, state: state).map(\.id) == [block3.id.uuidString], "\(said)")
        }
        // Both fields have a block 1; the field you're in comes first.
        let north1 = try Demo.block(model, "1")
        #expect(VoiceCatalog.blocks(matching: "block 1", state: state).first?.id == north1.id.uuidString)
        #expect(VoiceCatalog.blocks(matching: "block 9", state: state).isEmpty)
        #expect(VoiceCatalog.blocks(ids: [block3.id.uuidString], state: state).map(\.title) == ["Block 3"])
    }

    @Test func fieldsByName() async throws {
        let model = await Demo.model()
        let state = try Demo.state(model)
        #expect(VoiceCatalog.fields(state).map(\.title) == ["North Field", "Creek Field"])
        let creek = try Demo.field(model, "Creek Field")
        for said in ["creek", "the Creek field", "Creek Field"] {
            #expect(VoiceCatalog.fields(matching: said, state: state).map(\.id) == [creek.id.uuidString], "\(said)")
        }
        #expect(VoiceCatalog.fields(matching: "south", state: state).isEmpty)
    }

    @Test func spokenWordsAreSynonyms() async throws {
        let model = await Demo.model()
        let state = try Demo.state(model)
        let row = try #require(VoiceCatalog.suggestedRows(state).first)
        #expect(row.synonyms.contains("row five"))
        let block = try #require(VoiceCatalog.blocks(state).dropFirst(2).first)
        #expect(block.synonyms.contains("block three"))
        let field = try #require(VoiceCatalog.fields(state).first)
        #expect(field.synonyms.contains("North"))
    }
}
