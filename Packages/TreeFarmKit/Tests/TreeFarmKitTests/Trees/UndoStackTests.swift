import Foundation
import Testing
@testable import TreeFarmKit

@Suite("UndoStack")
struct UndoStackTests {
    @Test func popsTheLatestFirst() {
        var stack = UndoStack<Int>()
        #expect(stack.isEmpty)
        #expect(stack.pop() == nil)
        stack.push(1)
        stack.push(2)
        #expect(stack.count == 2)
        #expect(!stack.isEmpty)
        #expect(stack.pop() == 2)
        #expect(stack.pop() == 1)
        #expect(stack.pop() == nil)
    }

    @Test func dropsTheOldestPastItsDepth() {
        var stack = UndoStack<Int>(depth: 3)
        for n in 1...5 { stack.push(n) }
        #expect(stack.count == 3)
        #expect(stack.pop() == 5)
        #expect(stack.pop() == 4)
        #expect(stack.pop() == 3)
        #expect(stack.pop() == nil)
    }

    @Test func defaultDepthIsTheSharedLimit() {
        var stack = UndoStack<Int>()
        for n in 0..<100 { stack.push(n) }
        #expect(stack.count == Limits.undoDepth)
        #expect(stack.pop() == 99)
    }

    @Test func removesEntriesThatNoLongerApply() {
        // The artifact skips undo entries whose shift was deleted.
        var stack = UndoStack<(shift: String, n: Int)>()
        stack.push(("a", 1))
        stack.push(("b", 2))
        stack.push(("a", 3))
        stack.removeAll { $0.shift == "a" }
        #expect(stack.count == 1)
        #expect(stack.pop()?.n == 2)
    }

    @Test func holdsMarkChanges() {
        var stack = UndoStack<MarkChange>(depth: 2)
        stack.push(MarkChange())
        #expect(stack.pop() == MarkChange())
    }

    @Test func aDepthBelowOneStillKeepsOne() {
        var stack = UndoStack<Int>(depth: 0)
        stack.push(1)
        stack.push(2)
        #expect(stack.count == 1)
        #expect(stack.pop() == 2)
    }
}
