import Foundation
import Testing
import TimeCardCore
import TreeFarmKitTestSupport
@testable import TimeCard

@MainActor
@Suite("App model")
struct AppModelTests {
    @Test func launchArgumentsPickTheMode() {
        #expect(LaunchMode.current(arguments: ["TimeCard"], environment: [:]) == .live)
        #expect(LaunchMode.current(arguments: ["TimeCard", "-UITestInMemory"], environment: [:]) == .uiTest(signedIn: true))
        #expect(LaunchMode.current(arguments: ["TimeCard", "-UITestInMemory", "-UITestSignedOut"], environment: [:]) == .uiTest(signedIn: false))
        #expect(LaunchMode.current(arguments: ["TimeCard"], environment: ["UITEST_IN_MEMORY": "1"]) == .uiTest(signedIn: true))
    }

    @Test func theRealWatchLinkIsForLiveLaunchesAndPairedSimulatorRuns() {
        #expect(LaunchMode.usesRealWatch(.live, arguments: ["TimeCard"], isTestHost: false))
        #expect(!LaunchMode.usesRealWatch(.live, arguments: ["TimeCard"], isTestHost: true))
        #expect(!LaunchMode.usesRealWatch(.uiTest(signedIn: true), arguments: ["TimeCard", "-UITestInMemory"], isTestHost: false))
        // The paired-simulator integration (docs/watch.md 7.4): the demo farm and a real watch link.
        #expect(LaunchMode.usesRealWatch(.uiTest(signedIn: true), arguments: ["TimeCard", "-UITestInMemory", "-UITestWatchLink"],
                                         isTestHost: false))
        #expect(!LaunchMode.usesRealWatch(.uiTest(signedIn: true), arguments: ["TimeCard", "-UITestInMemory", "-UITestWatchLink"],
                                          isTestHost: true))
    }

    @Test func uiTestModeOpensSignedInOnTheDemoFarm() async throws {
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true))
        #expect(model.session.auth.me?.user.email == DemoFarm.email)
        await model.start()
        #expect(model.session.farm?.name == "Pine Hollow Tree Farm")
        #expect(model.session.isAdmin)
        _ = await model.session.syncNow()
        #expect(model.snapshot.fields.count == 2)
        #expect(model.session.syncStatus.summary == "All changes saved")
    }

    @Test func uiTestModeCanStartAtSignIn() async throws {
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: false))
        await model.start()
        #expect(model.session.auth == .signedOut)
        try await model.session.signIn(email: DemoFarm.email, password: DemoFarm.password)
        #expect(model.session.farm != nil)
    }

    @Test func saveIsTheSeamForEveryWriter() async throws {
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true))
        await model.start()
        let me = try #require(model.session.me)
        let farm = try #require(model.session.farm)
        let shift = Shift(userId: me.user.id, farmId: farm.id, start: Date(), rateCents: 2000)
        try model.save([.shift(shift)])
        #expect(model.snapshot.shifts[shift.id] == shift)
        #expect(try model.session.store.pendingCount() >= 1)
    }

    @Test func concurrentStartCallersAllSeeALoadedSession() async {
        // The window, an intent and a watch request can all start the app at once; none of them
        // may run on a session that is still loading (and say "Open Time Card to sign in.").
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true))
        let callers = (0..<4).map { _ in
            Task { @MainActor in
                await model.start()
                return model.session.hasOpened && model.session.farm != nil && model.actions.state() != nil
            }
        }
        var loaded: [Bool] = []
        for caller in callers { loaded.append(await caller.value) }
        #expect(loaded == [true, true, true, true])
    }

    @Test func theWatchLinkIsActivatedWhenTheModelIsMade() {
        // Not in a view: a watch message can launch the app in the background with no scene.
        let fake = FakeWatchTransport()
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true), watchTransport: fake)
        #expect(fake.activations == 1)
        #expect(model.watch != nil)
    }

    @Test func testModesNeverTouchTheRealWatchConnectivity() {
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true))
        #expect(model.watch != nil)
        #expect(LaunchMode.isTestHost)
    }

    @Test func storageErrorsStopTheApp() async {
        let session = TimeCardSession(store: try! LocalStore.inMemory(), api: StubAPIClient(), tokens: InMemoryTokenStore(), deviceName: "t")
        let model = AppModel(session: session, mode: .live, storageError: "Broken")
        await model.start()
        #expect(model.storageError == "Broken")
    }

    // MARK: Switching servers

    private func signedInStore() throws -> (LocalStore, InMemoryTokenStore, UserDefaults) {
        let store = try LocalStore.inMemory()
        try store.setValue(Data("me".utf8), forKey: AuthService.meKey)
        let defaults = try #require(UserDefaults(suiteName: "ServerSwitch-\(UUID().uuidString)"))
        return (store, InMemoryTokenStore(token: "old-token"), defaults)
    }

    @Test func theSameServerKeepsTheSignIn() throws {
        let (store, tokens, defaults) = try signedInStore()
        // Signed in before the setting existed: that was the standard server.
        let switched = try AppEnvironment.adoptServer(TimeCardCore.defaultServerURL, store: store, tokens: tokens, defaults: defaults)
        #expect(!switched)
        #expect(try tokens.read() == "old-token")
        #expect(try store.value(forKey: AuthService.meKey) != nil)
        #expect(defaults.string(forKey: ServerAddress.signedInServerKey) == TimeCardCore.defaultServerURL.absoluteString)
    }

    @Test func aNewServerForgetsTheOldSignInBeforeAnyRequest() throws {
        let (store, tokens, defaults) = try signedInStore()
        let other = try ServerAddress.parse("https://tc.example.com").get()
        let switched = try AppEnvironment.adoptServer(other, store: store, tokens: tokens, defaults: defaults)
        #expect(switched)
        #expect(try tokens.read() == nil)
        #expect(try store.value(forKey: AuthService.meKey) == nil)
        #expect(defaults.string(forKey: ServerAddress.signedInServerKey) == other.absoluteString)
        // The next launch on that server keeps the sign-in made there.
        try tokens.save("new-token")
        #expect(try !AppEnvironment.adoptServer(other, store: store, tokens: tokens, defaults: defaults))
        #expect(try tokens.read() == "new-token")
    }

    @Test func settingsOffersTheSwitchNowThatTheAppMakesIt() {
        #expect(ServerAddress.isEditable)
    }

    // MARK: Opening again after the first unlock

    private func sealedModel(_ error: String = "Sealed") -> AppModel {
        let session = TimeCardSession(store: try! LocalStore.inMemory(), api: StubAPIClient(), tokens: InMemoryTokenStore(), deviceName: "t")
        return AppModel(session: session, mode: .live, storageError: error)
    }

    @Test func aSealedModelIsMadeAgain() {
        let opened = AppEnvironment.makeModel(mode: .uiTest(signedIn: true))
        #expect(AppModel.reopening(sealedModel(), make: { opened }) === opened)
    }

    @Test func aModelThatOpenedIsKept() {
        var made = 0
        let opened = AppEnvironment.makeModel(mode: .uiTest(signedIn: true))
        #expect(AppModel.reopening(opened, make: { made += 1; return opened }) == nil)
        #expect(made == 0)
    }

    @Test func theSharedModelStaysWhileItsDatabaseIsOpen() {
        let shared = AppModel.shared
        guard shared.storageError == nil else { return }
        var made = 0
        #expect(AppModel.reopenIfSealed(make: { made += 1; return self.sealedModel() }) === shared)
        #expect(made == 0)
        #expect(AppModel.shared === shared)
    }
}

