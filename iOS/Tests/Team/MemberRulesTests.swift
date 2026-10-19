import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Team: roles and rates")
struct MemberRulesTests {
    @Test func readsRatesTheWayPeopleTypeThem() {
        #expect(MemberRules.parseRate("18.50") == 1850)
        #expect(MemberRules.parseRate("$18.5") == 1850)
        #expect(MemberRules.parseRate(" 18 ") == 1800)
        #expect(MemberRules.parseRate("1,000") == 100_000)
        #expect(MemberRules.parseRate(".75") == 75)
        #expect(MemberRules.parseRate("") == 0)
        #expect(MemberRules.parseRate("abc") == nil)
        #expect(MemberRules.parseRate("18.505") == nil)
        #expect(MemberRules.parseRate("-5") == nil)
        #expect(MemberRules.rateText(1850) == "18.50")
        #expect(MemberRules.rateText(0) == "0.00")
        #expect(MemberRules.rateText(123_456) == "1,234.56")
    }

    @Test func savesRoleJobAndRateAsAMemberRecord() {
        let f = TeamFixture()
        let members = [f.alex, f.sam, f.jo]
        var draft = MemberDraft(f.sam)
        draft.role = .admin
        draft.jobTitle = "  Lead trimmer "
        draft.rateText = "19.25"
        let edit = MemberRules.save(draft, for: f.sam, members: members, now: f.now)
        guard case .save(let records) = edit, case .member(let saved)? = records.first else {
            Issue.record("expected a save, got \(edit)")
            return
        }
        #expect(records.count == 1)
        #expect(saved.role == .admin)
        #expect(saved.jobTitle == "Lead trimmer")
        #expect(saved.rateCents == 1925)
        #expect(saved.updatedAt == f.now.roundedToMillisecond)
        #expect(saved.email == f.sam.email)
    }

    @Test func nothingChangedSavesNothing() {
        let f = TeamFixture()
        let members = [f.alex, f.sam, f.jo]
        var draft = MemberDraft(f.sam)
        draft.rateText = "$16.50"
        #expect(MemberRules.save(draft, for: f.sam, members: members, now: f.now) == .unchanged)
    }

    @Test func refusesToDemoteTheLastAdmin() {
        let f = TeamFixture()
        let members = [f.alex, f.sam, f.jo]
        var draft = MemberDraft(f.alex)
        draft.role = .worker
        #expect(MemberRules.save(draft, for: f.alex, members: members, now: f.now)
            == .problem("A farm needs at least one admin. Make someone else an admin first."))
        #expect(MemberRules.isOnlyAdmin(f.alex, members: members))
    }

    @Test func aRemovedAdminDoesNotCountAsAnotherAdmin() {
        var f = TeamFixture()
        f.jo.role = .admin
        var draft = MemberDraft(f.alex)
        draft.role = .worker
        #expect(MemberRules.save(draft, for: f.alex, members: [f.alex, f.sam, f.jo], now: f.now).problem == MemberRules.lastAdmin)
    }

    @Test func anAdminCanStepDownWhenAnotherAdminRemains() {
        var f = TeamFixture()
        f.sam.role = .admin
        var draft = MemberDraft(f.alex)
        draft.role = .worker
        let edit = MemberRules.save(draft, for: f.alex, members: [f.alex, f.sam, f.jo], now: f.now)
        #expect(edit.records.count == 1)
        #expect(MemberRules.losesOwnAdmin(draft, for: f.alex, me: f.alex.userId))
        #expect(!MemberRules.losesOwnAdmin(draft, for: f.alex, me: f.sam.userId))
    }

    @Test func checksRateAndJobTitleWithTheServersWords() {
        let f = TeamFixture()
        let members = [f.alex, f.sam, f.jo]
        var draft = MemberDraft(f.sam)
        draft.rateText = "10000.01"
        #expect(MemberRules.save(draft, for: f.sam, members: members, now: f.now).problem == "The pay rate has to be between $0 and $10,000 an hour.")
        draft.rateText = "twelve"
        #expect(MemberRules.save(draft, for: f.sam, members: members, now: f.now).problem == "Enter the pay rate in dollars, like 18.50.")
        draft.rateText = "12"
        draft.jobTitle = String(repeating: "x", count: Limits.name + 1)
        #expect(MemberRules.save(draft, for: f.sam, members: members, now: f.now).problem == "Job titles can be up to 80 characters.")
    }

    @Test func removalGuards() {
        let f = TeamFixture()
        let members = [f.alex, f.sam, f.jo]
        #expect(MemberRules.removeProblem(f.alex, members: members, me: f.sam.userId) == MemberRules.lastAdmin)
        #expect(MemberRules.removeProblem(f.sam, members: members, me: f.alex.userId) == nil)
        #expect(MemberRules.removeProblem(f.alex, members: members, me: f.alex.userId) == "You can’t remove yourself. To leave the farm, delete your account in Settings.")
        #expect(MemberRules.removeProblem(f.jo, members: members, me: f.alex.userId) == "Jo Banks is already off the farm.")
    }
}
