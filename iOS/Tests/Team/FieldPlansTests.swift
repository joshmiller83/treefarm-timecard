import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Team: fields and blocks")
struct FieldPlansTests {
    // MARK: Fields

    @Test func addsAFieldAtTheEndWithATrimmedName() {
        let f = TeamFixture()
        let edit = FieldPlans.add(name: "  Creek Field ", farmId: f.farm.id, fields: Array(f.snapshot.fields.values), now: f.now)
        guard case .field(let field)? = edit.records.first else {
            Issue.record("expected a field, got \(edit)")
            return
        }
        #expect(field.name == "Creek Field")
        #expect(field.sortOrder == 1)
        #expect(field.farmId == f.farm.id)
        #expect(field.updatedAt == f.now.roundedToMillisecond)
    }

    @Test func fieldNamesUseTheServersWords() {
        let f = TeamFixture()
        #expect(FieldPlans.add(name: "  ", farmId: f.farm.id, fields: [], now: f.now).problem == "Give the field a name.")
        #expect(FieldPlans.add(name: String(repeating: "a", count: 81), farmId: f.farm.id, fields: [], now: f.now).problem
            == "Names can be up to 80 characters.")
        #expect(FieldPlans.rename(f.north, to: "North Field", now: f.now) == .unchanged)
        #expect(FieldPlans.rename(f.north, to: "", now: f.now).problem == "Give the field a name.")
    }

    @Test func archivesAndRestoresAField() {
        let f = TeamFixture()
        guard case .field(let archived)? = FieldPlans.archive(f.north, now: f.now).records.first else {
            Issue.record("no record")
            return
        }
        #expect(archived.archivedAt == f.now.roundedToMillisecond)
        #expect(archived.deletedAt == nil)
        guard case .field(let restored)? = FieldPlans.restore(archived, now: f.now.addingTimeInterval(5)).records.first else {
            Issue.record("no record")
            return
        }
        #expect(restored.archivedAt == nil)
        #expect(restored.updatedAt > archived.updatedAt)
    }

    // MARK: New blocks

    @Test func aNewBlockTakesTheNextNumberAndItsNeighborsSize() {
        var f = TeamFixture()
        f.addBlock("1", row: 0, column: 0, rows: 61, trees: 10)
        let two = f.addBlock("2", row: 0, column: 1, rows: 40, trees: 12, direction: .down)
        let blocks = Array(f.snapshot.blocks.values)
        #expect(BlockPlans.nextName(blocks) == "3")
        let draft = BlockPlans.newDraft(blocks: blocks, placement: .rightOf(two.id))
        #expect(draft == BlockDraft(name: "3", rows: 40, treesPerRow: 12, direction: .down))
        #expect(BlockPlans.defaultPlacement(blocks) == .rightOf(two.id))
    }

    @Test func theFirstBlockInAnEmptyField() {
        #expect(BlockPlans.nextName([]) == "1")
        #expect(BlockPlans.defaultPlacement([]) == .first)
        #expect(BlockPlans.choices([]).map(\.label) == ["The first block"])
        #expect(BlockPlans.newDraft(blocks: [], placement: .first) == BlockDraft(name: "1", rows: 20, treesPerRow: 10, direction: .across))
    }

    @Test func offersEveryBlockThenANewRow() {
        var f = TeamFixture()
        f.addBlock("2", row: 0, column: 1)
        f.addBlock("1", row: 0, column: 0)
        f.addBlock("North 3", row: 1, column: 0)
        let labels = BlockPlans.choices(Array(f.snapshot.blocks.values)).map(\.label)
        #expect(labels == ["To the right of Block 1", "To the right of Block 2", "To the right of North 3", "In a new row below"])
    }

    @Test func addingToTheRightShiftsLaterBlocksInTheStrip() {
        var f = TeamFixture()
        let one = f.addBlock("1", row: 0, column: 0)
        let two = f.addBlock("2", row: 0, column: 1)
        f.addBlock("3", row: 1, column: 0)
        let draft = BlockDraft(name: "1A", rows: 10, treesPerRow: 8, direction: .across)
        let edit = BlockPlans.add(draft, placement: .rightOf(one.id), fieldId: f.north.id, blocks: Array(f.snapshot.blocks.values), now: f.now)
        let blocks = edit.records.compactMap { record -> Block? in
            if case .block(let b) = record { return b }
            return nil
        }
        #expect(blocks.count == 2)
        #expect(blocks[0].name == "1A")
        #expect(blocks[0].gridRow == 0 && blocks[0].gridColumn == 1)
        #expect(blocks[0].fieldId == f.north.id)
        #expect(blocks[1].id == two.id && blocks[1].gridColumn == 2)
        #expect(blocks.allSatisfy { $0.updatedAt == f.now.roundedToMillisecond })
    }

    @Test func aNewRowGoesBelowTheLastStrip() {
        var f = TeamFixture()
        f.addBlock("1", row: 0, column: 0)
        f.addBlock("2", row: 3, column: 0)
        let edit = BlockPlans.add(BlockDraft(name: "3", rows: 5, treesPerRow: 5, direction: .across), placement: .newRowBelow,
                                  fieldId: f.north.id, blocks: Array(f.snapshot.blocks.values), now: f.now)
        guard case .block(let block)? = edit.records.first else {
            Issue.record("expected a block, got \(edit)")
            return
        }
        #expect(edit.records.count == 1)
        #expect(block.gridRow == 4 && block.gridColumn == 0)
    }

    @Test func newBlocksAreCheckedWithBlockEdit() {
        let f = TeamFixture()
        let bad = BlockDraft(name: "4", rows: 0, treesPerRow: 10, direction: .across)
        #expect(BlockPlans.add(bad, placement: .first, fieldId: f.north.id, blocks: [], now: f.now).problem
            == BlockEdit.validate(name: "4", rows: 0, treesPerRow: 10))
        let unnamed = BlockDraft(name: " ", rows: 10, treesPerRow: 10, direction: .across)
        #expect(BlockPlans.add(unnamed, placement: .first, fieldId: f.north.id, blocks: [], now: f.now).problem == "Give the block a name.")
    }

    // MARK: Editing blocks

    @Test func resizingKeepsShapedTreesAndNotesInside() {
        var f = TeamFixture()
        let block = f.addBlock("1", row: 0, column: 0, rows: 10, trees: 8)
        let shift = f.addShift(f.sam, from: f.at(20, 7), to: f.at(20, 15))
        f.mark(block, row: 9, position: 0, shift: shift)
        f.note(block, row: 0, position: 7)
        let marks = Array(f.snapshot.marks.values), notes = Array(f.snapshot.notes.values)

        var smaller = BlockDraft(block: block)
        smaller.rows = 8
        smaller.treesPerRow = 6
        #expect(BlockPlans.update(block, with: smaller, marks: marks, notes: notes, now: f.now).problem
            == "1 shaped tree and 1 tree note would fall outside that size. Erase the trees and delete the notes first, or keep the size.")

        var bigger = BlockDraft(block: block)
        bigger.rows = 61
        bigger.direction = .down
        bigger.name = " Block A "
        guard case .block(let saved)? = BlockPlans.update(block, with: bigger, marks: marks, notes: notes, now: f.now).records.first else {
            Issue.record("expected a save")
            return
        }
        #expect(saved.rowCount == 61 && saved.direction == .down && saved.name == "Block A")
        #expect(saved.gridRow == block.gridRow && saved.gridColumn == block.gridColumn)
        #expect(saved.updatedAt == f.now.roundedToMillisecond)
        #expect(BlockPlans.update(block, with: BlockDraft(block: block), marks: marks, notes: notes, now: f.now) == .unchanged)
    }

    @Test func marksFromAnEarlierSeasonStillGuardTheBlock() {
        var f = TeamFixture()
        let block = f.addBlock("1", row: 0, column: 0, rows: 10, trees: 8)
        let shift = f.addShift(f.sam, from: f.at(1, 7), to: f.at(1, 15))
        let last = Season(farmId: f.farm.id, name: "2025", startedAt: f.at(1, 0))
        f.mark(block, row: 5, position: 5, shift: shift, season: last)
        #expect(BlockPlans.remove(block, marks: Array(f.snapshot.marks.values), notes: [], now: f.now).problem
            == "This block has 1 shaped tree, so it can’t be removed. Erase it first.")
    }

    @Test func removesAnEmptyBlockWithASoftDelete() {
        var f = TeamFixture()
        let block = f.addBlock("1", row: 0, column: 0)
        guard case .block(let removed)? = BlockPlans.remove(block, marks: [], notes: [], now: f.now).records.first else {
            Issue.record("expected a save")
            return
        }
        #expect(removed.deletedAt == f.now.roundedToMillisecond)
        #expect(removed.updatedAt == f.now.roundedToMillisecond)
    }

    // MARK: Preview

    @Test func thePreviewShowsTheDraftWhereItWillGo() {
        var f = TeamFixture()
        let one = f.addBlock("1", row: 0, column: 0)
        let two = f.addBlock("2", row: 0, column: 1)
        let blocks = Array(f.snapshot.blocks.values)
        let draft = BlockDraft(name: "New", rows: 400, treesPerRow: 0, direction: .across)
        let preview = BlockPlans.preview(blocks: blocks, draft: draft, editing: nil, placement: .rightOf(one.id))
        let ghost = preview.blocks.first { $0.id == preview.highlight }
        #expect(preview.blocks.count == 3)
        #expect(ghost?.gridColumn == 1)
        // Sizes are clamped so a half-typed number still draws.
        #expect(ghost?.rowCount == 300 && ghost?.treesPerRow == 1)
        #expect(preview.blocks.first { $0.id == two.id }?.gridColumn == 2)

        var edited = BlockDraft(block: two)
        edited.rows = 30
        let editing = BlockPlans.preview(blocks: blocks, draft: edited, editing: two, placement: nil)
        #expect(editing.highlight == two.id)
        #expect(editing.blocks.first { $0.id == two.id }?.rowCount == 30)
    }
}
