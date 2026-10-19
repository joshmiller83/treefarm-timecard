import Foundation
import Testing
@testable import TreeFarmKit

@Suite("ShiftMessages")
struct ShiftMessagesTests {
    @Test func savingAShift() {
        #expect(ShiftMessages.added == "Shift added.")
        #expect(ShiftMessages.saved == "Shift saved.")
        #expect(ShiftMessages.unchanged == "No changes to save.")
        #expect(ShiftMessages.missing == "This shift isn’t on this phone anymore. It may have been deleted on another device.")
        #expect(ShiftMessages.changedElsewhere == "This shift changed while you had it open. Check it and save again.")
        #expect(ShiftMessages.discardQuestion == "Discard your changes to this shift?")
    }

    @Test func deletingAShiftSaysWhatGoesWithIt() {
        #expect(ShiftMessages.deleteQuestion(trees: 0, isOpen: false)
                == "Delete this shift? Its hours come off your time card. This can’t be undone.")
        #expect(ShiftMessages.deleteQuestion(trees: 48, isOpen: true)
                == "Delete this shift? You’re still clocked in on it. Its 48 trees will be unmarked on the map too. This can’t be undone.")
        #expect(ShiftMessages.deleteQuestion(trees: 1, isOpen: false)
                == "Delete this shift? Its 1 tree will be unmarked on the map too. This can’t be undone.")
        #expect(ShiftMessages.deleteButton(trees: 0) == "Delete shift")
        #expect(ShiftMessages.deleteButton(trees: 48) == "Delete shift and 48 trees")
        #expect(ShiftMessages.deleted(trees: 0) == "Shift deleted.")
        #expect(ShiftMessages.deleted(trees: 1) == "Shift deleted. 1 tree unmarked.")
    }
}
