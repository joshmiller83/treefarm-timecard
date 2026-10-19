import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Watch inbox")
struct WatchInboxTests {
    let t0 = Date(timeIntervalSince1970: 1_792_400_000)

    func reply(_ id: UUID = UUID(), _ speech: String = "Row 14 marked, 4 trees. Next is row 15.") -> WatchReply {
        WatchReply(requestId: id, speech: speech, succeeded: true, lastAction: "Row 14 marked",
                   state: .signedOut(epoch: UUID(), revision: 4, now: t0), appliedAt: t0)
    }

    @Test func aRetriedRequestFindsItsFirstReplyWithoutState() {
        var inbox = WatchInbox()
        let id = UUID()
        #expect(inbox.reply(for: id) == nil)
        inbox.record(reply(id), at: t0)
        let saved = inbox.reply(for: id)
        #expect(saved?.speech == "Row 14 marked, 4 trees. Next is row 15.")
        #expect(saved?.lastAction == "Row 14 marked")
        #expect(saved?.appliedAt == t0)
        #expect(saved?.state == nil)
        #expect(inbox.count == 1)
    }

    @Test func recordingTheSameRequestAgainKeepsOneEntry() {
        var inbox = WatchInbox()
        let id = UUID()
        inbox.record(reply(id, "First."), at: t0)
        inbox.record(reply(id, "Second."), at: t0.addingTimeInterval(1))
        #expect(inbox.count == 1)
        #expect(inbox.reply(for: id)?.speech == "Second.")
    }

    @Test func itKeepsTheLast500() {
        var inbox = WatchInbox()
        let ids = (0..<501).map { _ in UUID() }
        for (i, id) in ids.enumerated() { inbox.record(reply(id), at: t0.addingTimeInterval(Double(i))) }
        #expect(inbox.count == 500)
        #expect(inbox.reply(for: ids[0]) == nil)
        #expect(inbox.reply(for: ids[1]) != nil)
        #expect(inbox.reply(for: ids[500]) != nil)
    }

    @Test func itForgetsRepliesOlderThanAWeek() {
        var inbox = WatchInbox(limit: 500, maxAge: 7 * 86_400)
        let old = UUID(), recent = UUID()
        inbox.record(reply(old), at: t0)
        inbox.record(reply(recent), at: t0.addingTimeInterval(6 * 86_400))
        inbox.record(reply(), at: t0.addingTimeInterval(7 * 86_400 + 1))
        #expect(inbox.reply(for: old) == nil)
        #expect(inbox.reply(for: recent) != nil)
    }

    @Test func recentIdsAreTheNewestLast() {
        var inbox = WatchInbox()
        let ids = (0..<5).map { _ in UUID() }
        for (i, id) in ids.enumerated() { inbox.record(reply(id), at: t0.addingTimeInterval(Double(i))) }
        #expect(inbox.recentIds(3) == Array(ids.suffix(3)))
        #expect(inbox.recentIds(50) == ids)
        #expect(inbox.recentIds(0).isEmpty)
    }

    @Test func anUnreadableReplyIsNeverKept() {
        var inbox = WatchInbox()
        inbox.record(.unreadable("Update Time Card on your iPhone."), at: t0)
        #expect(inbox.count == 0)
        #expect(inbox.reply(for: WatchReply.unreadableId) == nil)
    }

    @Test func aMintedShiftIdFollowsItsAlias() {
        var inbox = WatchInbox()
        let minted = UUID(), open = UUID(), other = UUID()
        #expect(inbox.resolve(shiftId: nil) == nil)
        #expect(inbox.resolve(shiftId: other) == other)
        inbox.alias(minted, to: open, at: t0)
        #expect(inbox.resolve(shiftId: minted) == open)
        #expect(inbox.shiftAliases == [minted: open])
        // A clock-in refused while that alias's shift was open aliases on through it.
        let second = UUID()
        inbox.alias(second, to: minted, at: t0)
        #expect(inbox.resolve(shiftId: second) == open)
    }

    @Test func aliasesThatLoopStillResolve() {
        var inbox = WatchInbox()
        let a = UUID(), b = UUID()
        inbox.alias(a, to: b, at: t0)
        inbox.alias(b, to: a, at: t0)
        let resolved = inbox.resolve(shiftId: a)
        #expect(resolved == a || resolved == b)
    }

    @Test func aliasesAreForgottenAfterAWeekToo() {
        var inbox = WatchInbox()
        let minted = UUID(), open = UUID()
        inbox.alias(minted, to: open, at: t0)
        inbox.record(reply(), at: t0.addingTimeInterval(8 * 86_400))
        #expect(inbox.resolve(shiftId: minted) == minted)
    }

    @Test func theInboxSurvivesARestartOfThePhoneApp() throws {
        var inbox = WatchInbox(limit: 20, maxAge: 3600)
        let id = UUID()
        inbox.record(reply(id), at: t0)
        inbox.alias(UUID(), to: UUID(), at: t0)
        let back = try JSONCoding.decoder().decode(WatchInbox.self, from: JSONCoding.encoder().encode(inbox))
        #expect(back == inbox)
        #expect(back.reply(for: id)?.state == nil)
        #expect(back.limit == 20 && back.maxAge == 3600)
    }

    @Test func fiveHundredEntriesStaySmall() throws {
        var inbox = WatchInbox()
        for i in 0..<500 { inbox.record(reply(), at: t0.addingTimeInterval(Double(i))) }
        let size = try JSONCoding.encoder().encode(inbox).count
        #expect(size < 200_000)
    }
}
