import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// The rows, blocks and fields Siri knows by name follow the farm, whatever changed it: the
/// app opening, the app's own buttons (which call FieldActions directly), a sync, signing out.
@MainActor
@Suite("Siri's suggestions follow the farm")
struct SiriSuggestionsTests {
    let model: AppModel
    let sent = Tally()
    let suggestions: SiriSuggestions

    init() async {
        model = await Demo.model()
        let sent = sent
        suggestions = SiriSuggestions(settle: .milliseconds(20)) { sent.count += 1 }
    }

    /// Lets observation hand over the change, then waits out the settle time.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(80))
        await suggestions.settled()
    }

    @Test func itTellsSiriWhenWhatItCanNameChanges() async throws {
        suggestions.follow(model)
        await settle()
        #expect(sent.count == 1, "when the app opens")

        // Clocking in names the same rows: nothing to tell.
        model.actions.perform(.clockIn(fieldId: nil))
        await settle()
        #expect(sent.count == 1)

        // Three rows in a quick run make one update.
        model.actions.perform(.markNextRow)
        model.actions.perform(.markNextRow)
        model.actions.perform(.markNextRow)
        await settle()
        #expect(sent.count == 2)

        model.actions.perform(.addShiftNote("Fuel low"))
        await settle()
        #expect(sent.count == 2, "a note changes nothing Siri names")

        // A move changes only where you are (kept outside the records), heard through FieldActions.
        model.actions.perform(.moveTo(blockId: try Demo.block(model, "3").id, row: nil))
        await settle()
        #expect(sent.count == 3)
        #expect(VoiceCatalog.suggestedRows(try Demo.state(model)).first?.blockName == "Block 3")
    }

    @Test func rowsSomeoneElseMarkedArriveInASync() async throws {
        suggestions.follow(model)
        await settle()
        let sam = try #require(model.snapshot.marks.values.first)
        let row5 = try Demo.row(model, 5)
        let marks = (0..<12).map { position in
            SyncRecord.treeMark(TreeMark(seasonId: sam.seasonId, tree: TreeRef(blockId: row5.blockId, row: row5.row, position: position),
                                         shiftId: sam.shiftId, userId: sam.userId, markedAt: Date().roundedToMillisecond))
        }
        try model.save(marks)
        await settle()
        #expect(sent.count == 2)
        #expect(VoiceCatalog.suggestedRows(try Demo.state(model)).first?.title == "Row 6")
    }

    @Test func signingOutLeavesNothingToName() async throws {
        suggestions.follow(model)
        await settle()
        await model.session.signOut()
        await settle()
        #expect(sent.count == 2)
        #expect(SiriSuggestions.Names(model.actions.state()) == SiriSuggestions.Names(nil))
    }

    @Test func anIntentTellsSiriBeforeItReturns() async throws {
        suggestions.follow(model)
        suggestions.refreshNow()
        #expect(sent.count == 1, "at once, not after the settle time")
        await settle()
        #expect(sent.count == 1, "and the pending update was folded in")
    }

    @Test func theLockScreenStillHearsEveryChange() async throws {
        var heard = 0
        model.actions.onLiveSnapshot = { _ in heard += 1 }
        suggestions.follow(model)
        model.actions.perform(.clockIn(fieldId: nil))
        #expect(heard == 1)
    }
}
