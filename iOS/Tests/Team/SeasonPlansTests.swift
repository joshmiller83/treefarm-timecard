import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Team: seasons")
struct SeasonPlansTests {
    @Test func suggestsTheNextYear() {
        let f = TeamFixture()
        // The active season is "2026", so next is 2027.
        #expect(SeasonPlans.suggestedName(seasons: [f.season], active: f.season, now: f.now, calendar: f.calendar) == "2027")
        // A season with another name: this year, unless it's taken.
        let spring = Season(farmId: f.farm.id, name: "Spring", startedAt: f.at(1, 0))
        #expect(SeasonPlans.suggestedName(seasons: [spring], active: spring, now: f.now, calendar: f.calendar) == "2026")
        let taken = Season(farmId: f.farm.id, name: "2026", startedAt: f.at(2, 0))
        #expect(SeasonPlans.suggestedName(seasons: [spring, taken], active: spring, now: f.now, calendar: f.calendar) == "2027")
    }

    @Test func startingASeasonMakesTheSeasonAndPointsTheFarmAtIt() {
        let f = TeamFixture()
        let edit = SeasonPlans.start(name: " 2027 ", farm: f.farm, now: f.now)
        guard edit.records.count == 2, case .season(let season) = edit.records[0], case .farm(let farm) = edit.records[1] else {
            Issue.record("expected a season and the farm, got \(edit)")
            return
        }
        #expect(season.name == "2027")
        #expect(season.farmId == f.farm.id)
        #expect(season.startedAt == f.now.roundedToMillisecond)
        #expect(farm.activeSeasonId == season.id)
        #expect(farm.name == f.farm.name)
        #expect(farm.updatedAt == f.now.roundedToMillisecond)
        #expect(SeasonPlans.start(name: "", farm: f.farm, now: f.now).problem == "Give the season a name.")
    }

    @Test func countsShapedTreesPerSeasonAndFieldProgress() {
        var f = TeamFixture()
        let block = f.addBlock("1", row: 0, column: 0, rows: 10, trees: 10)
        let shift = f.addShift(f.sam, from: f.at(20, 7), to: f.at(20, 15))
        let old = Season(farmId: f.farm.id, name: "2025", startedAt: f.at(1, 0).addingTimeInterval(-365 * 86400))
        f.snapshot.seasons[old.id] = old
        f.mark(block, row: 0, position: 0, shift: shift)
        f.mark(block, row: 0, position: 1, shift: shift)
        f.mark(block, row: 0, position: 2, shift: shift, season: old)

        let rows = SeasonPlans.rows(f.snapshot)
        #expect(rows.map(\.season.name) == ["2026", "2025"])
        #expect(rows.map(\.shaped) == [2, 1])
        #expect(rows.map(\.isActive) == [true, false])

        let progress = SeasonPlans.progress(f.snapshot)
        #expect(progress.count == 1)
        #expect(progress.first?.shaped == 2)
        #expect(progress.first?.total == 100)
    }
}

@Suite("Team: invite and reset codes")
struct InviteTextTests {
    @Test func splitsAndSpellsACode() {
        #expect(InviteText.groups("K7Q4-M2XP-9R") == ["K7Q4", "M2XP", "9R"])
        #expect(InviteText.spelled("K7Q4-M2XP-9R") == "K, 7, Q, 4. M, 2, X, P. 9, R.")
    }

    @Test func sharesPlainInstructions() {
        let f = TeamFixture()
        let expires = f.at(28, 12)
        #expect(InviteText.inviteShare(code: "K7Q4-M2XP-9R", farmName: "Test Tree Farm", expiresAt: expires, calendar: f.calendar)
            == "You’re invited to Test Tree Farm on Time Card. Open the app, tap “Join with an invite code” and enter K7Q4-M2XP-9R. It works once, until Wed, Oct 28.")
        #expect(InviteText.resetShare(code: "ABCD-EFGH-JK", expiresAt: f.at(22, 9, 5), calendar: f.calendar)
            == "Your Time Card reset code is ABCD-EFGH-JK. On the sign-in screen, tap “I have a reset code”. It works once, until Thu, Oct 22 at 9:05 AM.")
    }

    @Test func saysWhereEachInviteStands() {
        let f = TeamFixture()
        let open = InviteInfo(id: UUID(), role: .worker, note: "", createdAt: f.at(20, 9), expiresAt: f.at(27, 9))
        let used = InviteInfo(id: UUID(), role: .admin, note: "", createdAt: f.at(14, 9), expiresAt: f.at(21, 9), usedAt: f.at(15, 8))
        let expired = InviteInfo(id: UUID(), role: .worker, note: "", createdAt: f.at(10, 9), expiresAt: f.at(17, 9))
        #expect(InviteText.status(open, now: f.now) == .open)
        #expect(InviteText.status(used, now: f.now) == .used)
        #expect(InviteText.status(expired, now: f.now) == .expired)
        #expect(InviteText.statusLine(open, now: f.now, calendar: f.calendar) == "Works until Tue, Oct 27")
        #expect(InviteText.statusLine(used, now: f.now, calendar: f.calendar) == "Used Thu, Oct 15")
        #expect(InviteText.statusLine(expired, now: f.now, calendar: f.calendar) == "Expired Sat, Oct 17")
    }

    @Test func saysWhatAConnectionIsNeededFor() {
        #expect(TeamErrors.message(APIError.offline, needs: "Making an invite")
            == "You’re offline. Making an invite needs a connection, so try again when you have signal.")
        #expect(TeamErrors.message(APIError.client(status: 404, reason: "That invite is already gone."), needs: "x") == "That invite is already gone.")
    }
}
