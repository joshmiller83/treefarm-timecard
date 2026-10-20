import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Watch link")
struct WatchLinkTests {
    let block = UUID(uuidString: "6F36AC4A-2482-43AB-93EB-D015C1503B1B")!
    let t0 = Date(timeIntervalSince1970: 1_792_400_000)

    static let commands: [FieldCommand] = {
        let b = UUID(uuidString: "6F36AC4A-2482-43AB-93EB-D015C1503B1B")!
        return [
            .clockIn(fieldId: nil), .clockIn(fieldId: UUID()), .clockOut,
            .startBreak(.lunch, reason: ""), .startBreak(.break, reason: "Sharpening shears"), .endBreak,
            .markNextRow, .markRow(RowRef(blockId: b, row: 13)), .markTrees(RowRef(blockId: b, row: 2), positions: 0...4),
            .moveTo(blockId: b, row: nil), .moveTo(blockId: b, row: 7),
            .addShiftNote("Fuel low"), .addTreeNote(TreeRef(blockId: b, row: 3, position: 6), body: "Leader broken", flag: .attention),
            .changeStart(Date(timeIntervalSince1970: 1_792_399_000)), .undo, .cancelShift(UUID()),
        ]
    }()

    func state(epoch: UUID = WatchState.noEpoch, revision: Int = 1) -> WatchState {
        let snapshot = LiveSnapshot(phase: .working, timerStart: t0.addingTimeInterval(-3600), workedSoFar: 3600, workedLabel: "worked today",
                                    breakStart: nil, breakReason: "", fieldName: "North",
                                    nextRows: [RowChip(blockId: block, row: 13, title: "Row 14", blockName: "Block 2")],
                                    shiftTrees: 38, fieldShaped: 120, fieldTotal: 400, lastAction: "Row 13 marked", canUndo: true)
        return WatchState(signedIn: true, farmName: "Dull’s Tree Farm", fieldName: "North", snapshot: snapshot,
                          nextRows: [RowChip(blockId: block, row: 13, title: "Row 14", blockName: "Block 2")],
                          todayWorked: 3600, todayTrees: 40, canUndo: true, recordWorkouts: true, updatedAt: t0,
                          epoch: epoch, revision: revision, userId: UUID(), shiftId: UUID(), shiftStart: t0.addingTimeInterval(-3600),
                          lastClosedShift: ClosedShift(shiftId: UUID(), start: t0.addingTimeInterval(-90_000), end: t0.addingTimeInterval(-60_000),
                                                       worked: 28_000, trees: 412),
                          appliedRequestIds: [UUID(), UUID()], hadLunchToday: true, pacePerHour: 34.5,
                          farmTimeZone: "America/Indiana/Indianapolis", usualStart: DateComponents(hour: 7, minute: 5))
    }

    func roundTrip(_ message: WatchMessage) throws -> WatchMessage {
        try WatchEnvelope.decode(WatchEnvelope(message).data()).message
    }

    // MARK: Commands and questions

    @Test(arguments: commands)
    func everyCommandTravels(command: FieldCommand) throws {
        let back = try JSONCoding.decoder().decode(FieldCommand.self, from: JSONCoding.encoder().encode(command))
        #expect(back == command)
    }

    @Test func questionsTravel() throws {
        for q in [FieldQuestion.hours, .trees, .whereAmI, .pace, .pay(locked: true, sayWhenLocked: false)] {
            #expect(try JSONCoding.decoder().decode(FieldQuestion.self, from: JSONCoding.encoder().encode(q)) == q)
        }
    }

    // MARK: Envelopes

    @Test func requestsKeepWhenTheyWereMadeWhoMadeThemAndTheirShift() throws {
        let request = WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: 13))), issuedAt: t0, userId: UUID(), shiftId: UUID())
        #expect(try roundTrip(.request(request)) == .request(request))
    }

    @Test func repliesTravelWithTheirState() throws {
        let reply = WatchReply(requestId: UUID(), speech: "Row 14 marked, 10 trees. Next is row 15.", succeeded: true,
                               lastAction: "Row 14 marked", state: state(), appliedAt: t0, keepQueued: false)
        #expect(try roundTrip(.reply(reply)) == .reply(reply))
    }

    @Test func stateTravelsWithEveryField() throws {
        let s = state()
        guard case .state(let back) = try roundTrip(.state(s)) else { Issue.record("not a state"); return }
        #expect(back == s)
        #expect(back.usualStart?.hour == 7 && back.usualStart?.minute == 5)
        #expect(back.lastClosedShift?.trees == 412)
    }

    @Test func aWorkoutSummaryTravels() throws {
        let summary = WorkoutSummary(shiftId: UUID(), start: t0, end: t0.addingTimeInterval(29_520), activeDuration: 27_660,
                                     activeKcal: 1120.5, avgHeartRate: 104, maxHeartRate: 151)
        #expect(try roundTrip(.workoutSummary(summary)) == .workoutSummary(summary))
        let bare = WorkoutSummary(shiftId: nil, start: t0, end: t0.addingTimeInterval(600), activeDuration: 600)
        #expect(try roundTrip(.workoutSummary(bare)) == .workoutSummary(bare))
    }

    @Test func envelopesCarryTheVersion() throws {
        let data = try WatchEnvelope(.request(WatchRequest(body: .refresh, issuedAt: t0))).data()
        struct VersionOnly: Decodable { var v: Int }
        #expect(try JSONDecoder().decode(VersionOnly.self, from: data).v == WatchWire.version)
        #expect(WatchWire.version == 1)
    }

    @Test func aNewerVersionIsRefusedBeforeItsMessageIsRead() throws {
        let newer = Data(#"{"v":2,"message":{"somethingNew":{}}}"#.utf8)
        #expect(throws: WatchWireError.unsupportedVersion(2)) { try WatchEnvelope.decode(newer) }
        let zero = Data(#"{"v":0,"message":{}}"#.utf8)
        #expect(throws: WatchWireError.unsupportedVersion(0)) { try WatchEnvelope.decode(zero) }
    }

    @Test func dataThatIsntAnEnvelopeIsRefused() {
        #expect(throws: (any Error).self) { try WatchEnvelope.decode(Data("hello".utf8)) }
        #expect(throws: (any Error).self) { try WatchEnvelope.decode(Data(#"{"hello":"world"}"#.utf8)) }
        #expect(throws: (any Error).self) { try WatchEnvelope.decode(Data(#"{"v":1,"message":{"nope":{}}}"#.utf8)) }
    }

    // MARK: Requests and replies

    @Test func requestsSayWhichCommandsBelongToAShift() {
        let scoped = ["clockOut", "startBreak", "endBreak", "markRow", "markTrees", "addShiftNote", "cancelShift"]
        for command in Self.commands {
            let request = WatchRequest(body: .command(command), issuedAt: t0)
            #expect(request.command == command)
            #expect(request.isCommand)
            #expect(request.isShiftScoped == scoped.contains(Self.name(command)), "\(command)")
        }
        #expect(!WatchRequest(body: .refresh, issuedAt: t0).isShiftScoped)
        #expect(WatchRequest(body: .question(.hours), issuedAt: t0).command == nil)
        #expect(!WatchRequest(body: .question(.hours), issuedAt: t0).isCommand)
    }

    static func name(_ command: FieldCommand) -> String {
        Mirror(reflecting: command).children.first?.label ?? "\(command)"
    }

    @Test func requestsFromBeforeTheWatchKnewThePersonStillRead() throws {
        let old = Data(#"{"id":"6F36AC4A-2482-43AB-93EB-D015C1503B1B","body":{"refresh":{}},"issuedAt":1792400000000}"#.utf8)
        let request = try JSONCoding.decoder().decode(WatchRequest.self, from: old)
        #expect(request.userId == nil && request.shiftId == nil)
        #expect(request.issuedAt == t0)
    }

    @Test func anUnreadableEnvelopeGetsAReplyThatKeepsTheTapQueued() {
        let reply = WatchReply.unreadable("Update Time Card on your iPhone.")
        #expect(reply.requestId == UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(reply.keepQueued)
        #expect(!reply.succeeded)
        #expect(reply.speech == "Update Time Card on your iPhone.")
        #expect(reply.state == nil)
    }

    @Test func aReplyWithoutKeepQueuedLeavesTheOutbox() throws {
        let json = Data(#"{"requestId":"6F36AC4A-2482-43AB-93EB-D015C1503B1B","speech":"Done.","succeeded":true}"#.utf8)
        let reply = try JSONCoding.decoder().decode(WatchReply.self, from: json)
        #expect(!reply.keepQueued)
        #expect(reply.state == nil && reply.appliedAt == nil)
    }

    // MARK: State ordering

    @Test func aHigherRevisionSupersedes() {
        let epoch = UUID()
        #expect(state(epoch: epoch, revision: 5).supersedes(nil))
        #expect(state(epoch: epoch, revision: 6).supersedes(state(epoch: epoch, revision: 5)))
        #expect(!state(epoch: epoch, revision: 5).supersedes(state(epoch: epoch, revision: 5)))
        #expect(!state(epoch: epoch, revision: 4).supersedes(state(epoch: epoch, revision: 5)))
    }

    @Test func aNewEpochWithALowerRevisionIsAccepted() {
        // A reinstalled phone starts counting again.
        #expect(state(epoch: UUID(), revision: 1).supersedes(state(epoch: UUID(), revision: 900)))
    }

    @Test func theSignedOutStateCarriesNothing() {
        let epoch = UUID()
        let s = WatchState.signedOut(epoch: epoch, revision: 7, now: t0)
        #expect(!s.signedIn)
        #expect(s.epoch == epoch && s.revision == 7 && s.updatedAt == t0)
        #expect(s.snapshot == nil && s.nextRows.isEmpty && s.userId == nil && s.shiftId == nil)
        #expect(s.lastClosedShift == nil && s.appliedRequestIds.isEmpty)
        #expect(!s.isClockedIn)
    }

    // MARK: Outbox

    @Test func aPhoneOutOfReachLeavesTapsWaitingInOrder() {
        var outbox = WatchOutbox()
        let a = WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: 13))), issuedAt: t0)
        let b = WatchRequest(body: .command(.startBreak(.lunch, reason: "")), issuedAt: t0.addingTimeInterval(60))
        do { let added = outbox.add(a); #expect(added) }
        do { let added = outbox.add(b); #expect(added) }
        do { let added = outbox.add(a); #expect(!added) }
        #expect(outbox.pending.map(\.id) == [a.id, b.id])
        #expect(outbox.next == a)
        outbox.delivered(a.id)
        #expect(outbox.pending.map(\.id) == [b.id])
        outbox.delivered(UUID())
        #expect(outbox.count == 1)
    }

    @Test func undoNextRowQuestionsAndRefreshesAreNeverQueued() {
        var outbox = WatchOutbox()
        do { let added = outbox.add(WatchRequest(body: .command(.undo), issuedAt: t0)); #expect(!added) }
        do { let added = outbox.add(WatchRequest(body: .command(.markNextRow), issuedAt: t0)); #expect(!added) }
        do { let added = outbox.add(WatchRequest(body: .question(.hours), issuedAt: t0)); #expect(!added) }
        do { let added = outbox.add(WatchRequest(body: .refresh, issuedAt: t0)); #expect(!added) }
        #expect(outbox.isEmpty)
    }

    @Test func pastTheLimitTheOldestRowMarksGoFirst() {
        var outbox = WatchOutbox(limit: 4)
        let clockIn = WatchRequest(body: .command(.clockIn(fieldId: nil)), issuedAt: t0)
        let marks = (0..<4).map { WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: $0))), issuedAt: t0.addingTimeInterval(Double($0 + 1))) }
        let note = WatchRequest(body: .command(.addShiftNote("Fuel")), issuedAt: t0.addingTimeInterval(10))
        outbox.add(clockIn)
        marks.forEach { outbox.add($0) }
        outbox.add(note)
        #expect(outbox.pending.map(\.id) == [clockIn.id, marks[2].id, marks[3].id, note.id])
        #expect(outbox.dropped == 2)
    }

    @Test func clockAndBreakChangesAndCancelsAreNeverDropped() {
        var outbox = WatchOutbox(limit: 3)
        let kept: [FieldCommand] = [.clockIn(fieldId: nil), .startBreak(.lunch, reason: ""), .endBreak, .cancelShift(UUID()), .clockOut]
        let requests = kept.enumerated().map { WatchRequest(body: .command($1), issuedAt: t0.addingTimeInterval(Double($0))) }
        for request in requests { let added = outbox.add(request); #expect(added) }
        #expect(outbox.pending.map(\.id) == requests.map(\.id))
        #expect(outbox.dropped == 0)
        // A row mark arriving now is the one that goes.
        let mark = WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: 1))), issuedAt: t0.addingTimeInterval(9))
        do { let added = outbox.add(mark); #expect(!added) }
        #expect(outbox.dropped == 1)
        // With nothing else to drop, notes go before anything that is kept.
        let note = WatchRequest(body: .command(.addShiftNote("x")), issuedAt: t0.addingTimeInterval(10))
        do { let added = outbox.add(note); #expect(!added) }
        #expect(outbox.dropped == 2)
    }

    @Test func aStateCanAcknowledgeTapsWhoseRepliesWereLost() {
        var outbox = WatchOutbox()
        let requests = (0..<3).map { WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: $0))), issuedAt: t0.addingTimeInterval(Double($0))) }
        requests.forEach { outbox.add($0) }
        outbox.acknowledge([requests[0].id, requests[2].id, UUID()])
        #expect(outbox.pending.map(\.id) == [requests[1].id])
        outbox.acknowledge([])
        #expect(outbox.count == 1)
    }

    @Test func theLastWaitingTapCanBeTakenBack() {
        var outbox = WatchOutbox()
        do { let last = outbox.removeLast(); #expect(last == nil) }
        let a = WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: 13))), issuedAt: t0)
        let b = WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: 14))), issuedAt: t0.addingTimeInterval(5))
        outbox.add(a)
        outbox.add(b)
        do { let last = outbox.removeLast(); #expect(last == b) }
        #expect(outbox.pending == [a])
    }

    @Test func theOutboxSurvivesARestartOfTheWatchApp() throws {
        var outbox = WatchOutbox(limit: 50)
        outbox.add(WatchRequest(body: .command(.endBreak), issuedAt: t0, userId: UUID(), shiftId: UUID()))
        let back = try JSONCoding.decoder().decode(WatchOutbox.self, from: JSONCoding.encoder().encode(outbox))
        #expect(back == outbox)
        #expect(back.limit == 50)
    }

    // MARK: Timing

    @Test func aTapIsAppliedAtTheTimeItWasMade() {
        let received = t0.addingTimeInterval(300)
        #expect(WatchTiming.effectiveTime(issuedAt: t0, receivedAt: received) == t0)
        // A watch clock that runs ahead can't put a tap in the future.
        #expect(WatchTiming.effectiveTime(issuedAt: received.addingTimeInterval(90), receivedAt: received) == received)
    }

    @Test func aLateTapNeverLandsBeforeWhatIsAlreadyRecorded() {
        let received = t0.addingTimeInterval(600)
        let notBefore = t0.addingTimeInterval(120)
        #expect(WatchTiming.effectiveTime(issuedAt: t0, receivedAt: received, notBefore: notBefore) == notBefore)
        #expect(WatchTiming.effectiveTime(issuedAt: t0.addingTimeInterval(300), receivedAt: received, notBefore: notBefore) == t0.addingTimeInterval(300))
        #expect(WatchTiming.effectiveTime(issuedAt: t0, receivedAt: received, notBefore: nil) == t0)
        #expect(WatchTiming.effectiveTime(issuedAt: received.addingTimeInterval(60), receivedAt: received, notBefore: notBefore) == received)
    }

    @Test func notBeforeIsTheStartOfAnOpenBreak() {
        // Break started on the phone at 10:40; the watch's "back to work" was tapped at 10:38.
        var f = FieldFixture()
        let start = f.at(0)
        let breakStart = f.at(100)
        let shift = Shift(userId: f.josh.userId, farmId: f.farm.id, start: start,
                          breaks: [Break(kind: .lunch, start: f.at(30), end: f.at(60)), Break(kind: .break, start: breakStart)],
                          rateCents: 1500, updatedAt: breakStart)
        f.state.myShifts = [shift]
        for command: FieldCommand in [.endBreak, .clockOut, .startBreak(.lunch, reason: ""), .markRow(f.row(f.block1, 1)),
                                      .markTrees(f.row(f.block1, 1), positions: 0...1), .addShiftNote("x"), .cancelShift(shift.id)] {
            #expect(WatchTiming.notBefore(for: command, state: f.state) == breakStart)
        }
        let tapped = f.at(98)
        #expect(WatchTiming.effectiveTime(issuedAt: tapped, receivedAt: f.at(120), notBefore: WatchTiming.notBefore(for: .endBreak, state: f.state)) == breakStart)
    }

    @Test func notBeforeCountsAClosedBreaksEnd() {
        var f = FieldFixture()
        let shift = Shift(userId: f.josh.userId, farmId: f.farm.id, start: f.at(0),
                          breaks: [Break(kind: .lunch, start: f.at(30), end: f.at(60))], rateCents: 1500, updatedAt: f.at(60))
        f.state.myShifts = [shift]
        #expect(WatchTiming.notBefore(for: .startBreak(.break, reason: ""), state: f.state) == f.at(60))
    }

    @Test func notBeforeForAClockInIsTheEndOfTheLastShift() {
        var f = FieldFixture()
        let earlier = Shift(userId: f.josh.userId, farmId: f.farm.id, start: f.at(-600), end: f.at(-300), rateCents: 1500)
        let latest = Shift(userId: f.josh.userId, farmId: f.farm.id, start: f.at(-200), end: f.at(-60), rateCents: 1500)
        var deleted = Shift(userId: f.josh.userId, farmId: f.farm.id, start: f.at(-50), end: f.at(-10), rateCents: 1500)
        deleted.deletedAt = f.at(-5)
        f.state.myShifts = [latest, earlier, deleted]
        #expect(WatchTiming.notBefore(for: .clockIn(fieldId: nil), state: f.state) == f.at(-60))
    }

    @Test func notBeforeWithNoShiftAtAll() {
        let f = FieldFixture()
        #expect(WatchTiming.notBefore(for: .clockIn(fieldId: nil), state: f.state) == nil)
        #expect(WatchTiming.notBefore(for: .endBreak, state: f.state) == nil)
        #expect(WatchTiming.notBefore(for: .clockOut, state: f.state) == nil)
    }

    @Test func notBeforeIsNilForCommandsThatDontBelongToAShift() {
        var f = FieldFixture()
        f.state.myShifts = [Shift(userId: f.josh.userId, farmId: f.farm.id, start: f.at(0), rateCents: 1500)]
        for command: FieldCommand in [.markNextRow, .undo, .moveTo(blockId: f.block1.id, row: nil), .changeStart(f.at(1))] {
            #expect(WatchTiming.notBefore(for: command, state: f.state) == nil)
        }
    }

    // MARK: Stamping

    @Test func recordsAreStampedWithTheTimeThePhoneGotThem() {
        let f = FieldFixture()
        let received = Date(timeIntervalSince1970: 1_792_400_123.4567)
        let mark = TreeMark(seasonId: f.season.id, tree: TreeRef(blockId: f.block1.id, row: 0, position: 0),
                            shiftId: UUID(), userId: f.josh.userId, markedAt: f.at(0))
        guard case .treeMark(let stamped) = SyncRecord.treeMark(mark).stamped(updatedAt: received) else { Issue.record("kind"); return }
        #expect(stamped.markedAt == f.at(0))
        #expect(stamped.updatedAt == received.roundedToMillisecond)

        var gone = Shift(userId: f.josh.userId, farmId: f.farm.id, start: f.at(0), rateCents: 1500, updatedAt: f.at(1))
        gone.deletedAt = f.at(1)
        guard case .shift(let shift) = SyncRecord.shift(gone).stamped(updatedAt: received) else { Issue.record("kind"); return }
        #expect(shift.start == f.at(0))
        #expect(shift.deletedAt == f.at(1))
        #expect(shift.updatedAt == received.roundedToMillisecond)

        for record: SyncRecord in [.farm(f.farm), .member(f.josh), .season(f.season), .field(f.field), .block(f.block1),
                                   .treeNote(TreeNote(farmId: f.farm.id, tree: TreeRef(blockId: f.block1.id, row: 0, position: 0),
                                                      authorId: f.josh.userId, authorName: "Josh", body: "x", createdAt: f.at(0)))] {
            let s = record.stamped(updatedAt: received)
            #expect(s.updatedAt == received.roundedToMillisecond)
            #expect(s.key == record.key)
        }
    }

    // MARK: Workout inputs

    @Test func pendingIsTheOutboxAndInFlightOnceEachOldestFirst() {
        let a = WatchRequest(body: .command(.clockIn(fieldId: nil)), issuedAt: t0)
        let b = WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: 1))), issuedAt: t0.addingTimeInterval(1))
        let c = WatchRequest(body: .command(.clockOut), issuedAt: t0.addingTimeInterval(2))
        let inputs = WorkoutInputs(confirmed: nil, outbox: [b, c], inFlight: [a, b])
        #expect(inputs.pending == [a, b, c])
    }

    @Test func aFreshWorkoutLocalHasNoSession() throws {
        let local = WorkoutLocal()
        #expect(local.phase == .none && !local.hasSession)
        #expect(WorkoutLocal(phase: .stopped).hasSession)
        let saved = WorkoutLocal(phase: .paused, shiftId: UUID(), origin: .actionButton, startedAt: t0, stoppedAt: nil,
                                 syncIdentifier: UUID(), stoppedUnexpectedly: false, lastFinishedShiftId: UUID())
        #expect(try JSONCoding.decoder().decode(WorkoutLocal.self, from: JSONCoding.encoder().encode(saved)) == saved)
    }
}
