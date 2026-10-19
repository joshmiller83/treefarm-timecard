import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Hourly pay text")
struct RateTextTests {
    @Test func readsWhatPeopleType() {
        #expect(RateText.parse("18.50") == 1850)
        #expect(RateText.parse("$18.5") == 1850)
        #expect(RateText.parse(" 18 ") == 1800)
        #expect(RateText.parse("18.") == 1800)
        #expect(RateText.parse(".75") == 75)
        #expect(RateText.parse("") == 0)
        #expect(RateText.parse("999.99") == 99999)
    }

    @Test func refusesWhatIsntPay() {
        #expect(RateText.parse("abc") == nil)
        #expect(RateText.parse("-5") == nil)
        #expect(RateText.parse("18.505") == nil)
        #expect(RateText.parse("1000") == nil)
        #expect(RateText.parse("1.2.3") == nil)
    }

    @Test func showsCentsOrNothing() {
        #expect(RateText.format(1850) == "18.50")
        #expect(RateText.format(2000) == "20.00")
        #expect(RateText.format(5) == "0.05")
        #expect(RateText.format(0) == "")
    }
}

@Suite("Your name, job and rate")
struct ProfileFormTests {
    let f = ClockFixture()
    var now: Date { f.today(9, 0).addingTimeInterval(0.000_4) }

    @Test func startsFromTheMembership() {
        let form = ProfileForm(member: f.me)
        #expect(form.name == "Josh")
        #expect(form.job == "Trimmer")
        #expect(form.rate == "18.00")
        #expect(form.problem == nil)
        #expect(!form.isChanged(from: f.me))
        #expect(form.records(for: f.me, openShift: nil, now: now).isEmpty)
    }

    @Test func savesTheMemberRecordTrimmedAndStamped() throws {
        var form = ProfileForm(member: f.me)
        form.name = "  Josh Miller "
        form.job = "Tree trimming"
        let records = form.records(for: f.me, openShift: nil, now: now)
        #expect(records.count == 1)
        guard case .member(let m)? = records.first else { Issue.record("no member"); return }
        #expect(m.displayName == "Josh Miller")
        #expect(m.jobTitle == "Tree trimming")
        #expect(m.rateCents == 1800)
        #expect(m.userId == f.userId)
        #expect(m.updatedAt == now.roundedToMillisecond)
    }

    @Test func aNewRateCountsFromTheShiftYoureOnButNotEarlierOnes() throws {
        let open = f.shift(f.today(7, 0))
        var form = ProfileForm(member: f.me)
        form.rate = "19.25"
        let records = form.records(for: f.me, openShift: open, now: now)
        #expect(records.count == 2)
        guard case .member(let m)? = records.first, case .shift(let s)? = records.last else { Issue.record("wrong records"); return }
        #expect(m.rateCents == 1925)
        #expect(s.id == open.id)
        #expect(s.rateCents == 1925)
        #expect(s.updatedAt == now.roundedToMillisecond)

        form = ProfileForm(member: f.me)
        form.job = "Lead"
        #expect(form.records(for: f.me, openShift: open, now: now).count == 1)
    }

    @Test func saysWhatToFix() {
        var form = ProfileForm(member: f.me)
        form.name = "   "
        #expect(form.problem == "Add your name. It goes on your time card.")
        form.name = "Josh"
        form.rate = "eighteen"
        #expect(form.problem == "Enter your hourly pay like 18.50.")
        form.rate = "2000"
        #expect(form.problem == "Hourly pay goes up to $999.99.")
        #expect(form.records(for: f.me, openShift: nil, now: now).isEmpty)
    }

    @Test func aChangeFromElsewhereShowsWhenYouHaventTouchedTheForm() throws {
        let form = ProfileForm(member: f.me)
        var raised = f.me
        raised.rateCents = 1950
        let fresh = try #require(form.refreshed(from: f.me, to: raised, editing: false))
        #expect(fresh.rate == "19.50")
        // Comparing with the new record would have kept the old $18.00 on screen, ready to save back.
        #expect(form.isChanged(from: raised))
    }

    @Test func yourEditsStayWhenAChangeArrives() {
        var form = ProfileForm(member: f.me)
        var raised = f.me
        raised.rateCents = 1950
        #expect(form.refreshed(from: f.me, to: raised, editing: true) == nil)
        form.job = "Lead"
        #expect(form.refreshed(from: f.me, to: raised, editing: false) == nil)
    }

    @Test func longEntriesAreHeldToTheLimit() throws {
        var form = ProfileForm(member: f.me)
        form.name = String(repeating: "n", count: 120)
        guard case .member(let m)? = form.records(for: f.me, openShift: nil, now: now).first else { Issue.record("no member"); return }
        #expect(m.displayName.count == Limits.name)
    }
}

@Suite("Server address")
struct ServerAddressTests {
    @Test func addsHttpsAndTidiesUp() throws {
        #expect(try ServerAddress.parse("timecard.example.com").get().absoluteString == "https://timecard.example.com")
        #expect(try ServerAddress.parse(" https://timecard.example.com/ ").get().absoluteString == "https://timecard.example.com")
        #expect(try ServerAddress.parse("https://example.com:8443/tc").get().absoluteString == "https://example.com:8443/tc")
    }

    @Test func plainHttpOnlyForThisMac() throws {
        #expect(try ServerAddress.parse("http://localhost:8790").get().absoluteString == "http://localhost:8790")
        #expect(try ServerAddress.parse("http://127.0.0.1:8790").get().absoluteString == "http://127.0.0.1:8790")
        #expect(try ServerAddress.parse("http://imac.local:8790").get().absoluteString == "http://imac.local:8790")
        #expect(ServerAddress.parse("http://timecard.example.com").failure == "Use an https:// address. Plain http only works for this Mac (localhost or a .local name).")
    }

    @Test func refusesNonsense() {
        #expect(ServerAddress.parse("").failure == "Enter the server’s web address.")
        #expect(ServerAddress.parse("ftp://example.com").failure == "Use an https:// address.")
        #expect(ServerAddress.parse("https://").failure == "That doesn’t look like a web address.")
        #expect(ServerAddress.parse("not a url").failure == "That doesn’t look like a web address.")
    }

    @Test func savedChoiceIsRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "ServerAddressTests-\(UUID().uuidString)"))
        #expect(ServerAddress.saved(in: defaults) == nil)
        let url = try ServerAddress.parse("https://tc.example.com").get()
        ServerAddress.save(url, in: defaults)
        #expect(ServerAddress.saved(in: defaults) == url)
        ServerAddress.save(nil, in: defaults)
        #expect(ServerAddress.saved(in: defaults) == nil)
        defaults.set("garbage", forKey: ServerAddress.defaultsKey)
        #expect(ServerAddress.saved(in: defaults) == nil)
    }
}

@Suite("Which server to use")
struct ServerChoiceTests {
    func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "ServerChoiceTests-\(UUID().uuidString)"))
    }

    @Test func theSchemeThenThisPhoneThenTheStandardServer() throws {
        let d = try defaults()
        #expect(ServerAddress.resolve(environment: [:], defaults: d) == TimeCardCore.defaultServerURL)
        let saved = try ServerAddress.parse("https://tc.example.com").get()
        ServerAddress.save(saved, in: d)
        #expect(ServerAddress.resolve(environment: [:], defaults: d) == saved)
        let dev = ServerAddress.resolve(environment: ["TIMECARD_SERVER_URL": "http://localhost:8790"], defaults: d)
        #expect(dev.absoluteString == "http://localhost:8790")
    }

    @Test func aNewServerMeansSigningOutFirst() throws {
        let standard = TimeCardCore.defaultServerURL
        let other = try ServerAddress.parse("https://tc.example.com").get()
        // Signed in before this setting existed: that was the standard server.
        #expect(!ServerAddress.mustSignOut(signedInServer: nil, using: standard))
        #expect(ServerAddress.mustSignOut(signedInServer: nil, using: other))
        #expect(!ServerAddress.mustSignOut(signedInServer: "https://TC.example.com/", using: other))
        #expect(ServerAddress.mustSignOut(signedInServer: other.absoluteString, using: standard))
        #expect(ServerAddress.mustSignOut(signedInServer: "https://tc.example.com:8443", using: other))
    }

    /// Settings offers a new server only once the app really switches to it.
    @MainActor @Test func theSwitchIsOfferedOnlyWhenTheAppMakesIt() throws {
        guard ServerAddress.isEditable else { return }
        let before = UserDefaults.standard.string(forKey: ServerAddress.defaultsKey)
        defer { UserDefaults.standard.set(before, forKey: ServerAddress.defaultsKey) }
        ServerAddress.save(try ServerAddress.parse("https://tc.example.com").get())
        #expect(AppEnvironment.serverURL.absoluteString == "https://tc.example.com")
    }
}

@Suite("Siri phrases")
struct SiriPhraseTests {
    @Test func startTimeExampleIsOneSiriKnows() {
        // A shortcut phrase can't carry a spoken time; Siri asks for it.
        #expect(SiriPhrases.examples.contains { $0.phrase == "Fix my start time in Time Card" })
        #expect(!SiriPhrases.examples.contains { $0.phrase.contains("7:30") })
    }

    @Test func everyPhraseNamesTheApp() {
        #expect(SiriPhrases.examples.count >= 8)
        for example in SiriPhrases.examples {
            #expect(example.phrase.contains("Time Card"), "\(example.phrase)")
            #expect(!example.does.isEmpty)
        }
    }
}

extension Result where Failure == ServerAddress.Problem {
    var failure: String? {
        if case .failure(let problem) = self { return problem.message }
        return nil
    }
}
