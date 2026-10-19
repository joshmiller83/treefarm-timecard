import Foundation
import Testing
import TimeCardCore
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

    @Test func storageErrorsStopTheApp() async {
        let session = TimeCardSession(store: try! LocalStore.inMemory(), api: StubAPIClient(), tokens: InMemoryTokenStore(), deviceName: "t")
        let model = AppModel(session: session, mode: .live, storageError: "Broken")
        await model.start()
        #expect(model.storageError == "Broken")
    }
}
