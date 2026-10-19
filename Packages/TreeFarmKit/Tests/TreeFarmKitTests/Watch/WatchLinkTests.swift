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
            .changeStart(Date(timeIntervalSince1970: 1_792_399_000)), .undo,
        ]
    }()

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

    @Test func requestsKeepWhenTheyWereMade() throws {
        let request = WatchRequest(body: .command(.markNextRow), issuedAt: t0)
        let back = try WatchRequest.decode(request.encoded())
        #expect(back == request)
        #expect(back.issuedAt == t0)
    }

    @Test func repliesAndStateTravelAsDictionaries() throws {
        let reply = WatchReply(requestId: UUID(), speech: "Row 14 marked, 10 trees. Next is row 15.", succeeded: true, lastAction: "Row 14 marked")
        #expect(try WatchReply.decode(reply.encoded()) == reply)

        let state = WatchState(signedIn: true, farmName: "Dull’s Tree Farm", fieldName: "Field 1", snapshot: nil,
                               nextRows: [RowChip(blockId: block, row: 13, title: "Row 14", blockName: "Block 2")],
                               todayWorked: 3600, todayTrees: 40, canUndo: false, recordWorkouts: true, updatedAt: t0)
        let dict = try state.encoded()
        #expect(dict.keys.contains(WatchState.payloadKey))
        #expect(try WatchState.decode(dict) == state)
    }

    @Test func plainDictionariesThatArentOursAreRefused() {
        #expect(throws: (any Error).self) { try WatchRequest.decode(["hello": "world"]) }
    }

    @Test func aPhoneOutOfReachLeavesTapsWaitingInOrder() {
        var outbox = WatchOutbox()
        let a = WatchRequest(body: .command(.markNextRow), issuedAt: t0)
        let b = WatchRequest(body: .command(.startBreak(.lunch, reason: "")), issuedAt: t0.addingTimeInterval(60))
        outbox.add(a)
        outbox.add(b)
        outbox.add(a)
        #expect(outbox.pending.map(\.id) == [a.id, b.id])
        #expect(outbox.next == a)
        outbox.delivered(a.id)
        #expect(outbox.pending.map(\.id) == [b.id])
        outbox.delivered(UUID())
        #expect(outbox.count == 1)
    }

    @Test func theOutboxHasALimitAndDropsTheOldestFirst() {
        var outbox = WatchOutbox(limit: 3)
        let requests = (0..<5).map { WatchRequest(body: .command(.markNextRow), issuedAt: t0.addingTimeInterval(Double($0))) }
        requests.forEach { outbox.add($0) }
        #expect(outbox.pending.map(\.id) == requests.suffix(3).map(\.id))
        #expect(outbox.dropped == 2)
    }

    @Test func questionsAreNeverQueued() {
        var outbox = WatchOutbox()
        outbox.add(WatchRequest(body: .question(.hours), issuedAt: t0))
        outbox.add(WatchRequest(body: .refresh, issuedAt: t0))
        #expect(outbox.isEmpty)
    }

    @Test func theOutboxSurvivesARestartOfTheWatchApp() throws {
        var outbox = WatchOutbox()
        outbox.add(WatchRequest(body: .command(.endBreak), issuedAt: t0))
        let back = try JSONDecoder().decode(WatchOutbox.self, from: JSONEncoder().encode(outbox))
        #expect(back == outbox)
    }

    @Test func aTapIsAppliedAtTheTimeItWasMade() {
        let received = t0.addingTimeInterval(300)
        #expect(WatchTiming.effectiveTime(issuedAt: t0, receivedAt: received) == t0)
        // A watch clock that runs ahead can't put a tap in the future.
        #expect(WatchTiming.effectiveTime(issuedAt: received.addingTimeInterval(90), receivedAt: received) == received)
    }
}
