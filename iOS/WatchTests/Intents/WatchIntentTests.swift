import AppIntents
import Foundation
import Testing
import TreeFarmKit
@testable import TimeCardWatch

/// The watch's ten Siri commands (docs/watch.md 4.1) against a scripted model: in reach they
/// say the phone's sentence; with the phone away they queue and say so; with nothing to go on
/// (no state, or a command the cached state shows is bound to fail) they say why and queue
/// nothing. Clock-out and far rows ask first, the same question Siri asks on the phone.
@MainActor
@Suite("Watch Siri")
struct WatchIntentTests {
    typealias F = IntentFixtures

    // MARK: 1 · Clock in

    @Test func clockInInReachSaysThePhonesSentence() async {
        let model = FakeIntentModel(F.offClock())
        let said = await ClockInIntent().speak(model: model)
        #expect(model.performed == [.clockIn(fieldId: nil)])
        #expect(model.sources == [.siri])
        #expect(said == F.phoneSays(.clockIn(fieldId: nil)))
    }

    @Test func clockInWithThePhoneAwayIsSavedOnTheWatch() async {
        let model = FakeIntentModel(F.offClock(), reach: .outOfReach)
        let said = await ClockInIntent().speak(model: model)
        #expect(model.performed == [.clockIn(fieldId: nil)])
        #expect(said == WatchDisplay.savedForSiri)
        #expect(said == "Saved on your watch. It’ll reach your phone when it’s back in range.")
    }

    @Test func clockInWithNoStateQueuesNothing() async {
        let model = FakeIntentModel(nil, reach: .outOfReach)
        let said = await ClockInIntent().speak(model: model)
        #expect(model.performed.isEmpty)
        #expect(said == "Open Time Card on your iPhone once.")
    }

    @Test func clockInWhenTheCacheShowsAShiftIsRefusedAway() async {
        let state = F.working()
        let model = FakeIntentModel(state, reach: .outOfReach)
        let said = await ClockInIntent().speak(model: model)
        #expect(model.performed.isEmpty)
        #expect(said == "You’re already clocked in since \(Fmt.spokenTime(state.shiftStart!, state.calendar)).")
    }

    @Test func clockInOpensTheAppSoTheWorkoutStartsInTheForeground() {
        #expect(ClockInIntent.openAppWhenRun)
    }

    // MARK: 2 · Clock out

    @Test func clockOutAsksTheWatchConfirmQuestionFirst() async {
        let model = FakeIntentModel(F.working())
        var asked: [String] = []
        let said = await ClockOutIntent().speak(model: model) { question in
            asked.append(question)
            return true
        }
        #expect(asked == [WatchConfirm.question(for: .clockOut, state: F.working(), now: model.now)!])
        #expect(asked.first?.hasSuffix("Clock out?") == true)
        #expect(model.performed == [.clockOut])
        #expect(said == F.phoneSays(.clockOut))
    }

    @Test func clockOutAnsweredNoChangesNothing() async {
        let model = FakeIntentModel(F.working())
        let said = await ClockOutIntent().speak(model: model) { _ in false }
        #expect(model.performed.isEmpty)
        #expect(said == Speech.stillClockedIn)
    }

    @Test func clockOutAwayAsksThenSaves() async {
        let model = FakeIntentModel(F.working(), reach: .outOfReach)
        var asks = 0
        let said = await ClockOutIntent().speak(model: model) { _ in asks += 1; return true }
        #expect(asks == 1)
        #expect(model.performed == [.clockOut])
        #expect(said == WatchDisplay.savedForSiri)
    }

    @Test func clockOutOffTheClockAwayIsRefusedWithoutAsking() async {
        let model = FakeIntentModel(F.offClock(), reach: .outOfReach)
        var asks = 0
        let said = await ClockOutIntent().speak(model: model) { _ in asks += 1; return true }
        #expect(asks == 0)
        #expect(model.performed.isEmpty)
        #expect(said == Speech.notClockedIn)
    }

    // MARK: 3, 4, 5 · Breaks

    @Test func lunchAndABreakAndBackToWork() async {
        let model = FakeIntentModel(F.working())
        _ = await TakeLunchIntent().speak(model: model)
        _ = await TakeBreakIntent().speak(model: model)
        _ = await BackToWorkIntent().speak(model: model)
        #expect(model.performed == [.startBreak(.lunch, reason: ""), .startBreak(.break, reason: ""), .endBreak])
    }

    @Test func lunchAwayWhileOnLunchIsRefused() async {
        let state = F.onLunch()
        let model = FakeIntentModel(state, reach: .outOfReach)
        let said = await TakeLunchIntent().speak(model: model)
        #expect(model.performed.isEmpty)
        #expect(said.hasPrefix("You’re already on lunch since"))
    }

    @Test func backToWorkAwayWhileWorkingIsRefused() async {
        let model = FakeIntentModel(F.working(), reach: .outOfReach)
        #expect(await BackToWorkIntent().speak(model: model) == "You’re not on a break.")
        #expect(model.performed.isEmpty)
    }

    @Test func aBreakAwayIsSaved() async {
        let model = FakeIntentModel(F.working(), reach: .outOfReach)
        #expect(await TakeBreakIntent().speak(model: model) == WatchDisplay.savedForSiri)
        #expect(model.performed == [.startBreak(.break, reason: "")])
    }

    // MARK: 6 · Next row

    @Test func nextRowMarksTheChipTheWatchShows() async {
        let model = FakeIntentModel(F.working())
        _ = await NextRowIntent().speak(model: model)
        #expect(model.performed == [.markRow(RowRef(blockId: F.blockId, row: 13))])
    }

    @Test func nextRowAwayIsSaved() async {
        let model = FakeIntentModel(F.working(), reach: .outOfReach)
        #expect(await NextRowIntent().speak(model: model) == WatchDisplay.savedForSiri)
        #expect(model.performed == [.markRow(RowRef(blockId: F.blockId, row: 13))])
    }

    @Test func nextRowWithTheFieldDoneQueuesNothing() async {
        let model = FakeIntentModel(F.fieldDone(), reach: .outOfReach)
        #expect(await NextRowIntent().speak(model: model) == "Every row in North is shaped.")
        #expect(model.performed.isEmpty)
    }

    @Test func nextRowOutOfKnownRowsQueuesNothing() async {
        let model = FakeIntentModel(F.outOfKnownRows(), reach: .outOfReach)
        #expect(await NextRowIntent().speak(model: model) == "Out of rows the watch knows. Bring your phone closer.")
        #expect(model.performed.isEmpty)
    }

    @Test func nextRowWithNoStateOrSignedOut() async {
        #expect(await NextRowIntent().speak(model: FakeIntentModel(nil)) == WatchDisplay.neverConnected)
        #expect(await NextRowIntent().speak(model: FakeIntentModel(F.signedOut)) == WatchDisplay.signedOut)
    }

    @Test func nextRowOffTheClockAwayIsRefused() async {
        let model = FakeIntentModel(F.offClock(), reach: .outOfReach)
        #expect(await NextRowIntent().speak(model: model) == Speech.notClockedIn)
        #expect(model.performed.isEmpty)
    }

    // MARK: 7 · Mark a row

    @Test func aCloseRowIsMarkedWithoutAsking() async throws {
        let model = FakeIntentModel(F.working())
        let row = WatchRowEntity(blockId: F.blockId, row: 15, blockName: "Block 2")
        var asks = 0
        _ = await MarkRowIntent(row: row).speak(model: model, askRow: { throw CancellationError() }) { _ in asks += 1; return true }
        #expect(asks == 0)
        #expect(model.performed == [.markRow(RowRef(blockId: F.blockId, row: 15))])
    }

    @Test func aFarRowAsksFirst() async {
        let model = FakeIntentModel(F.working())
        let row = WatchRowEntity(blockId: F.blockId, row: 39, blockName: "Block 2")
        var asked: [String] = []
        let said = await MarkRowIntent(row: row).speak(model: model, askRow: { throw CancellationError() }) { q in
            asked.append(q)
            return false
        }
        #expect(asked == ["Row 40 in block 2? That’s 26 rows ahead."])
        #expect(model.performed.isEmpty)
        #expect(said == Speech.nothingMarked)
    }

    @Test func noRowAsksWhichRow() async {
        let model = FakeIntentModel(F.working())
        var askedForRow = 0
        _ = await MarkRowIntent().speak(model: model, askRow: {
            askedForRow += 1
            return WatchRowEntity(blockId: F.blockId, row: 14, blockName: "Block 2")
        }) { _ in true }
        #expect(askedForRow == 1)
        #expect(model.performed == [.markRow(RowRef(blockId: F.blockId, row: 14))])
    }

    @Test func markARowAwayOffTheClockIsRefusedBeforeAsking() async {
        let model = FakeIntentModel(F.offClock(), reach: .outOfReach)
        var askedForRow = 0
        let said = await MarkRowIntent().speak(model: model, askRow: {
            askedForRow += 1
            return WatchRowEntity(blockId: F.blockId, row: 14, blockName: "Block 2")
        }) { _ in true }
        #expect(askedForRow == 0)
        #expect(said == Speech.notClockedIn)
    }

    @Test func mappingRow40ResolvesThroughTheSpokenNumber() throws {
        let state = F.working()
        let rows = WatchRowCatalog.rows(matching: "40", state: state)
        #expect(rows.map(\.rowRef) == [RowRef(blockId: F.blockId, row: 39)])
        #expect(WatchRowCatalog.rows(matching: "row forty", state: state).map(\.row) == [39])
        #expect(WatchRowCatalog.rows(matching: "forty-two", state: state).map(\.row) == [41])
        #expect(WatchRowCatalog.rows(matching: "Row 140", state: state).map(\.row) == [139])
        #expect(WatchRowCatalog.rows(matching: "the last row", state: state).isEmpty)
        #expect(WatchRowCatalog.rows(matching: "40", state: F.fieldDone()).isEmpty)
        #expect(WatchRowCatalog.rows(matching: "40", state: nil).isEmpty)
    }

    @Test func suggestedRowsAreTheFirstTenChips() {
        let rows = WatchRowCatalog.suggested(F.working())
        #expect(rows.count == 10)
        #expect(rows.first?.row == 13)
        #expect(rows.last?.row == 22)
        #expect(rows.first?.displayTitle == "row 14")
    }

    @Test func rowIdsRoundTrip() {
        let row = WatchRowEntity(blockId: F.blockId, row: 13, blockName: "Block 2")
        #expect(row.id == "\(F.blockId.uuidString)-13")
        #expect(WatchRowEntity.parse(id: row.id) == RowRef(blockId: F.blockId, row: 13))
        #expect(WatchRowEntity.parse(id: "nonsense") == nil)
        #expect(WatchRowEntity.parse(id: "\(F.blockId.uuidString)--1") == nil)
        let found = WatchRowCatalog.rows(ids: [row.id, "nonsense"], state: F.working())
        #expect(found.map(\.rowRef) == [row.rowRef])
        #expect(found.first?.blockName == "Block 2")
    }

    @Test func spokenNumbers() {
        #expect(WatchSpokenNumber.parse("14") == 14)
        #expect(WatchSpokenNumber.parse("row fourteen") == 14)
        #expect(WatchSpokenNumber.parse("twenty two") == 22)
        #expect(WatchSpokenNumber.parse("one hundred and five") == 105)
        #expect(WatchSpokenNumber.parse("two hundred") == 200)
        #expect(WatchSpokenNumber.parse("row") == nil)
    }

    // MARK: 8 · Undo

    @Test func undoSaysWhatTheModelDid() async {
        let model = FakeIntentModel(F.working(), reach: .outOfReach)
        model.undoOutcome = .notSent("Took back row 15. It wasn’t sent yet.")
        #expect(await UndoIntent().speak(model: model) == "Took back row 15. It wasn’t sent yet.")
        #expect(model.undos == 1)
        model.undoOutcome = .done(WatchReply(requestId: UUID(), speech: "Undid row 14.", succeeded: true))
        #expect(await UndoIntent().speak(model: model) == "Undid row 14.")
    }

    // MARK: 9 · Status

    @Test func statusInReachIsThePhonesAnswer() async {
        let model = FakeIntentModel(F.working())
        model.answers[.hours] = "3 hours 41 minutes today, 18 hours this week."
        model.answers[.trees] = "38 trees today, 34 an hour. You’re on block 2, row 14."
        let said = await StatusIntent().speak(model: model, now: F.now)
        #expect(model.asked == [.hours, .trees])
        #expect(said == "3 hours 41 minutes today, 18 hours this week. 38 trees today, 34 an hour. You’re on block 2, row 14.")
    }

    @Test func statusAwayIsTheCachedAnswerAsOfItsTime() async {
        let state = F.working()
        let model = FakeIntentModel(state, reach: .outOfReach)
        let said = await StatusIntent().speak(model: model, now: F.now)
        let worked = state.todayWorked + 60
        #expect(said == "\(Fmt.spokenDuration(worked)) today, 38 trees, 34 an hour. Next is row 14 in block 2. That’s as of \(F.time(state.updatedAt)).")
    }

    @Test func statusWhenThePhoneDoesntAnswerFallsBackToTheCache() async {
        let model = FakeIntentModel(F.working())
        let said = await StatusIntent().speak(model: model, now: F.now)
        #expect(said.hasSuffix("That’s as of \(F.time(F.working().updatedAt))."))
    }

    @Test func cachedStatusWordings() {
        #expect(WatchVoiceText.cachedStatus(nil, now: F.now) == WatchDisplay.neverConnected)
        #expect(WatchVoiceText.cachedStatus(F.signedOut, now: F.now) == WatchDisplay.signedOut)
        let off = F.offClock()
        #expect(WatchVoiceText.cachedStatus(off, now: F.now) == "You haven’t worked yet today. Next is row 14 in block 2. That’s as of \(F.time(off.updatedAt)).")
        let done = F.fieldDone()
        #expect(WatchVoiceText.cachedStatus(done, now: F.now).contains("Every row in North is shaped."))
        let lunch = F.onLunch()
        // On lunch the worked time is frozen.
        #expect(WatchVoiceText.cachedStatus(lunch, now: F.now).hasPrefix("\(Fmt.spokenDuration(lunch.todayWorked)) today"))
    }

    // MARK: 10 · A note

    @Test func aNoteIsAskedForAndAdded() async {
        let model = FakeIntentModel(F.working())
        let said = await AddNoteIntent().speak(model: model) { "Gate by block 3 is open" }
        #expect(model.performed == [.addShiftNote("Gate by block 3 is open")])
        #expect(said == F.phoneSays(.addShiftNote("")))
    }

    @Test func anEmptyNoteSavesNothing() async {
        let model = FakeIntentModel(F.working())
        let said = await AddNoteIntent().speak(model: model) { "   " }
        #expect(model.performed.isEmpty)
        #expect(said == Speech.emptyNote)
    }

    @Test func aNoteAwayIsSaved() async {
        let model = FakeIntentModel(F.working(), reach: .outOfReach)
        #expect(await AddNoteIntent().speak(model: model) { "Fuel low" } == WatchDisplay.savedForSiri)
    }

    // MARK: Shortcut phrases

    @Test func theShortcutParametersRefreshWhenTheFirstChipChanges() {
        var refreshes = 0
        let refresher = ShortcutParameterRefresher { refreshes += 1 }
        refresher.update(F.working())
        #expect(refreshes == 1)
        // Same first chip, a later chip changed: nothing to refresh.
        var later = F.working()
        later.nextRows[5] = RowChip(blockId: F.blockId, row: 99, title: "Row 100", blockName: "Block 2")
        refresher.update(later)
        #expect(refreshes == 1)
        refresher.update(F.working(chips: F.chips(from: 14, count: 39)))
        #expect(refreshes == 2)
        refresher.update(nil)
        #expect(refreshes == 3)
        refresher.update(nil)
        #expect(refreshes == 3)
    }
}

/// The phrases Xcode compiled into the watch app (Metadata.appintents), which is what Siri on
/// the watch learns: exactly the ten in docs/watch.md 4.1 and docs/voice-test.md, each phrase
/// ending "in Time Card" and also said "with Time Card" (flexible matching is off on the watch).
@Suite("Watch Siri phrases")
struct WatchShortcutPhraseTests {
    let metadata: [String: Any]

    init() throws {
        let url = try #require(Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents"),
                               "the watch app has no App Intents metadata")
        metadata = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    var shortcuts: [[String: Any]] { metadata["autoShortcuts"] as? [[String: Any]] ?? [] }

    var phrases: [(intent: String, phrase: String)] {
        shortcuts.flatMap { shortcut -> [(String, String)] in
            let intent = shortcut["actionIdentifier"] as? String ?? "?"
            let templates = shortcut["phraseTemplates"] as? [[String: Any]] ?? []
            return templates.compactMap { $0["key"] as? String }.map { (intent, $0) }
        }
    }

    @Test func exactlyTenShortcuts() {
        #expect(shortcuts.count == 10)
    }

    @Test func everyPhraseEndsInOrWithTheAppAndComesInBothForms() {
        for (intent, phrase) in phrases {
            let inForm = phrase.hasSuffix(" in ${applicationName}")
            let withForm = phrase.hasSuffix(" with ${applicationName}")
            #expect(inForm || withForm, "\(intent): “\(phrase)”")
            let twin = inForm ? String(phrase.dropLast(" in ${applicationName}".count)) + " with ${applicationName}"
                              : String(phrase.dropLast(" with ${applicationName}".count)) + " in ${applicationName}"
            #expect(phrases.contains { $0.intent == intent && $0.phrase == twin }, "\(intent): “\(phrase)” has no twin")
        }
        let all = phrases.map { $0.phrase.lowercased() }
        #expect(Set(all).count == all.count, "a phrase is used twice")
    }

    @Test func everyCommandFromTheVoiceScript() {
        let expected: [(String, [String])] = [
            ("ClockInIntent", ["Clock in", "Punch in", "Start work", "Start my shift"]),
            ("ClockOutIntent", ["Clock out", "Punch out", "End my shift", "Stop work"]),
            ("TakeLunchIntent", ["Take lunch", "Start lunch"]),
            ("TakeBreakIntent", ["Take a break", "Start a break"]),
            ("BackToWorkIntent", ["Back to work", "End my break"]),
            ("NextRowIntent", ["Next row", "Row done", "Mark the next row"]),
            ("MarkRowIntent", ["Mark ${row}", "${row} done", "Mark a row"]),
            ("UndoIntent", ["Undo", "Undo that"]),
            ("StatusIntent", ["How long have I worked", "How many trees", "What row am I on", "What's my pace"]),
            ("AddNoteIntent", ["Add a note"]),
        ]
        for (intent, starts) in expected {
            for start in starts {
                #expect(phrases.contains { $0.intent == intent && $0.phrase == "\(start) in ${applicationName}" }, "missing “\(start) in Time Card”")
            }
        }
    }
}
