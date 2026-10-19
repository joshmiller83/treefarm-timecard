import Foundation
import Testing
import TimeCardCore
import TreeFarmKitTestSupport
@testable import TimeCard

/// The iPhone's side of the watch link (docs/watch.md 1.3), against a scripted
/// WatchConnectivity and a recording workout launcher: every request is answered exactly once
/// after the app has started, publishing is coalesced and only reaches a paired watch with the
/// app installed, a phone clock-in starts the watch's workout after the context, and
/// complication pushes go out only on phase changes the watch can't hear about otherwise.
@MainActor
@Suite("Phone watch bridge", .serialized)
struct PhoneWatchBridgeTests {
    // MARK: Fakes and helpers

    /// Records each launch, with the state the watch's context held at that moment.
    final class FakeLauncher: WatchWorkoutLauncher, @unchecked Sendable {
        private let lock = NSLock()
        private var _launches: [WatchState?] = []
        var transport: FakeWatchTransport?
        var result: WatchLaunchResult = .started

        var launches: [WatchState?] { lock.withLock { _launches } }

        func startShiftWorkout(timeout: Duration) async -> WatchLaunchResult {
            let context = transport?.contextStates.last
            lock.withLock { _launches.append(context) }
            return result
        }
    }

    @MainActor struct Harness {
        let model: AppModel
        let fake: FakeWatchTransport
        let launcher: FakeLauncher

        var bridge: PhoneWatchBridge { model.watch }
        var userId: UUID { model.session.me!.user.id }
    }

    func harness(_ fake: FakeWatchTransport = FakeWatchTransport(), start: Bool = true,
                 recordWorkouts: Bool = true) async -> Harness {
        let demo = DemoFarm.makeServer(signedIn: true)
        let store = try! LocalStore.inMemory()
        try? store.setValue(try? JSONCoding.encoder().encode(demo.me), forKey: AuthService.meKey)
        WatchSettings.save(WatchSettings(recordWorkouts: recordWorkouts), to: store, userId: demo.me.user.id)
        let session = TimeCardSession(store: store, api: demo.server, tokens: InMemoryTokenStore(token: "t"), deviceName: "Test iPhone")
        let launcher = FakeLauncher()
        launcher.transport = fake
        let model = AppModel(session: session, mode: .uiTest(signedIn: true), watchTransport: fake, watchLauncher: launcher)
        model.watch.coalesce = .milliseconds(40)
        let h = Harness(model: model, fake: fake, launcher: launcher)
        if start {
            await model.start()
            await quiet(h)
        }
        return h
    }

    /// Lets the start's publishes (and the session changes they follow) finish.
    func quiet(_ h: Harness) async {
        var seen = -1
        while seen != h.fake.contexts.count {
            seen = h.fake.contexts.count
            await h.bridge.settled()
            try? await Task.sleep(for: .milliseconds(80))
            await h.bridge.settled()
        }
    }

    /// Waits (briefly) for something the bridge's event loop does.
    func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func request(_ command: FieldCommand, userId: UUID?, shiftId: UUID? = nil, id: UUID = UUID()) -> Data {
        FakeWatchTransport.envelope(.request(WatchRequest(id: id, body: .command(command), issuedAt: Date(), userId: userId, shiftId: shiftId)))
    }

    func reply(_ data: Data?) -> WatchReply? {
        guard let data, case .reply(let reply)? = try? WatchEnvelope.decode(data).message else { return nil }
        return reply
    }

    func states(_ datas: [Data]) -> [WatchState] {
        datas.compactMap { if case .state(let s)? = try? WatchEnvelope.decode($0).message { s } else { nil } }
    }

    // MARK: Activation and status

    @Test func theBridgeActivatesAndReportsTheWatch() async {
        let h = await harness(start: false)
        #expect(h.fake.activations == 1)
        await eventually { h.bridge.status == .inReach }
        #expect(h.bridge.status == .inReach)
        h.fake.setReachable(false)
        await eventually { h.bridge.status == .outOfReach }
        #expect(h.bridge.status == .outOfReach)
        h.fake.setWatch(paired: true, installed: false, complicationEnabled: false)
        await eventually { h.bridge.status == .appNotInstalled }
        #expect(h.bridge.status == .appNotInstalled)
        h.fake.setWatch(paired: false, installed: false, complicationEnabled: false)
        await eventually { h.bridge.status == .noWatch }
        #expect(h.bridge.status == .noWatch)
    }

    // MARK: Publishing

    @Test func publishingIsCoalescedAndEveryStateComesFromTheDesk() async {
        let h = await harness()
        let before = h.fake.contexts.count
        #expect(before >= 1, "the start publishes")
        for reason in [PublishReason.fieldAction, .sync, .sceneActive, .fieldAction, .sync] { h.bridge.publish(reason: reason) }
        await h.bridge.settled()
        #expect(h.fake.contexts.count == before + 1)
        let published = states(h.fake.contexts)
        let last = try! #require(published.last)
        // The next state the desk makes follows straight on: one counter.
        #expect(h.bridge.desk.makeState().revision == last.revision + 1)
        #expect(Set(published.map(\.epoch)).count == 1)
        #expect(zip(published, published.dropFirst()).allSatisfy { $1.revision > $0.revision })
    }

    @Test func aReachableWatchAlsoGetsTheStateAsAMessage() async {
        let h = await harness()
        #expect(states(h.fake.posted).last == states(h.fake.contexts).last)
    }

    @Test func nothingIsPublishedWithoutAPairedWatch() async {
        let h = await harness(FakeWatchTransport(paired: false, installed: false))
        h.bridge.publish(reason: .fieldAction)
        await h.bridge.settled()
        #expect(h.fake.contexts.isEmpty)
        #expect(h.fake.posted.isEmpty)
    }

    @Test func nothingIsPublishedWhenTheWatchAppIsntInstalled() async {
        let h = await harness(FakeWatchTransport(paired: true, installed: false))
        h.bridge.publish(reason: .fieldAction)
        await h.bridge.settled()
        #expect(h.fake.contexts.isEmpty)
    }

    @Test func nothingIsPublishedBeforeTheAppHasStarted() async {
        let h = await harness(start: false)
        await eventually { h.bridge.status == .inReach }
        h.bridge.publish(reason: .activation)
        await h.bridge.settled()
        // A state from a session that hasn't loaded would say "signed out" and stop the workout.
        #expect(h.fake.contexts.isEmpty)
    }

    @Test func aFieldActionOnThePhonePublishes() async {
        let h = await harness()
        let before = h.fake.contexts.count
        #expect(h.model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await quiet(h)
        #expect(h.fake.contexts.count > before)
        #expect(states(h.fake.contexts).last?.isClockedIn == true)
    }

    @Test func turningRecordingOffPublishesTheNewSetting() async {
        let h = await harness()
        #expect(states(h.fake.contexts).last?.recordWorkouts == true)
        WatchSettings.save(WatchSettings(recordWorkouts: false), to: h.model.session.store, userId: h.userId)
        h.bridge.publish(reason: .settingsChanged)
        await h.bridge.settled()
        #expect(states(h.fake.contexts).last?.recordWorkouts == false)
    }

    // MARK: Starting the watch's workout

    @Test func aPhoneClockInStartsTheWatchWorkoutAfterTheContext() async {
        let h = await harness()
        #expect(h.model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await h.bridge.settled()
        #expect(h.launcher.launches.count == 1)
        // The watch reads the shift from the context, so it went first.
        let seen = h.launcher.launches.first ?? nil
        #expect(seen?.isClockedIn == true)
        #expect(seen?.shiftId == h.model.session.snapshot.openShift(for: h.userId)?.id)
    }

    @Test func noWorkoutLaunchWithRecordingOff() async {
        let h = await harness(recordWorkouts: false)
        #expect(h.model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await h.bridge.settled()
        #expect(h.launcher.launches.isEmpty)
        #expect(states(h.fake.contexts).last?.isClockedIn == true)
    }

    @Test func noWorkoutLaunchForAWatchClockIn() async {
        let h = await harness()
        let minted = UUID()
        let answer = reply(await h.fake.deliverMessage(request(.clockIn(fieldId: nil), userId: h.userId, shiftId: minted)))
        #expect(answer?.succeeded == true)
        await h.bridge.settled()
        #expect(h.launcher.launches.isEmpty)
        #expect(states(h.fake.contexts).last?.shiftId == minted)
    }

    @Test func noWorkoutLaunchForOtherChanges() async {
        let h = await harness()
        #expect(h.model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await h.bridge.settled()
        #expect(h.model.actions.perform(.startBreak(.lunch, reason: "")).succeeded)
        await h.bridge.settled()
        #expect(h.model.actions.perform(.endBreak).succeeded)
        await h.bridge.settled()
        #expect(h.launcher.launches.count == 1)
    }

    @Test func noWorkoutLaunchWithoutTheWatchApp() async {
        let h = await harness(FakeWatchTransport(paired: true, installed: false))
        #expect(h.model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await h.bridge.settled()
        #expect(h.launcher.launches.isEmpty)
    }

    // MARK: Complication pushes

    @Test func aPhaseChangeOutOfReachPushesTheComplicationWhileBudgetLasts() async throws {
        let fake = FakeWatchTransport(reachable: false, complicationEnabled: true, complicationTransfers: 1)
        let h = await harness(fake)
        #expect(fake.complicationTransfers.isEmpty, "starting changes no phase the watch knew")
        #expect(h.model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await h.bridge.settled()
        #expect(fake.complicationTransfers.count == 1)
        let pushed = try #require(states(fake.complicationTransfers).first)
        #expect(WatchDisplay.phase(pushed) == .working)
        // A row is no phase change.
        let next = try #require(states(fake.contexts).last?.nextRows.first)
        #expect(h.model.actions.perform(.markRow(next.rowRef)).succeeded)
        await h.bridge.settled()
        #expect(fake.complicationTransfers.count == 1)
        // Lunch is, but today's budget is spent: the context alone carries it.
        #expect(h.model.actions.perform(.startBreak(.lunch, reason: "")).succeeded)
        await h.bridge.settled()
        #expect(fake.complicationTransfers.count == 1)
        #expect(states(fake.contexts).last.map(WatchDisplay.phase) == .lunch)
    }

    @Test func noComplicationPushWhileTheWatchIsInReach() async {
        let fake = FakeWatchTransport(reachable: true, complicationEnabled: true)
        let h = await harness(fake)
        #expect(h.model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await h.bridge.settled()
        #expect(fake.complicationTransfers.isEmpty)
    }

    @Test func noComplicationPushWithoutTheComplicationOnAFace() async {
        let fake = FakeWatchTransport(reachable: false, complicationEnabled: false)
        let h = await harness(fake)
        #expect(h.model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await h.bridge.settled()
        #expect(fake.complicationTransfers.isEmpty)
    }

    // MARK: Requests

    @Test func everyRequestIsAnsweredExactlyOnce() async {
        let h = await harness()
        let messages = [
            request(.clockIn(fieldId: nil), userId: h.userId, shiftId: UUID()),
            Data("not an envelope".utf8),
            request(.startBreak(.lunch, reason: ""), userId: UUID(), shiftId: UUID()),
            FakeWatchTransport.envelope(.request(WatchRequest(body: .refresh, issuedAt: Date(), userId: h.userId))),
        ]
        var replies: [WatchReply?] = []
        for message in messages { replies.append(reply(await h.fake.deliverMessage(message))) }
        #expect(h.fake.repliesSent.count == messages.count)
        #expect(replies.allSatisfy { $0 != nil })
        #expect(replies.allSatisfy { $0?.state != nil })
        #expect(replies[1]?.requestId == WatchReply.unreadableId)
    }

    @Test func aRequestThatWakesTheAppWaitsForItToStart() async {
        let h = await harness(start: false)
        let answer = reply(await h.fake.deliverMessage(request(.clockIn(fieldId: nil), userId: h.userId, shiftId: UUID())))
        // Never a false "Open Time Card to sign in." from a session still loading.
        #expect(answer?.succeeded == true, "\(answer?.speech ?? "no reply")")
        #expect(h.model.session.hasOpened)
    }

    @Test func aSealedPhoneKeepsTheTapQueuedAndSendsNoState() async {
        let fake = FakeWatchTransport()
        let session = TimeCardSession(store: try! LocalStore.inMemory(), api: StubAPIClient(), tokens: InMemoryTokenStore(), deviceName: "t")
        let model = AppModel(session: session, mode: .uiTest(signedIn: true), storageError: "Sealed",
                             watchTransport: fake, watchLauncher: FakeLauncher())
        let tap = WatchRequest(body: .command(.clockIn(fieldId: nil)), issuedAt: Date(), userId: UUID(), shiftId: UUID())
        let answer = reply(await fake.deliverMessage(FakeWatchTransport.envelope(.request(tap))))
        #expect(answer?.keepQueued == true)
        #expect(answer?.requestId == tap.id)
        #expect(answer?.speech == Speech.unlockOnce)
        // A signed-out state from a phone that can't read its data would end the watch's workout.
        #expect(answer?.state == nil)
        model.watch.publish(reason: .sceneActive)
        await model.watch.settled()
        #expect(fake.contexts.isEmpty)
    }

    @Test func aPostedWorkoutSummaryIsKeptOnThePhone() async throws {
        let h = await harness()
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let summary = WorkoutSummary(shiftId: UUID(), start: start, end: start.addingTimeInterval(3600), activeDuration: 3500, activeKcal: 300)
        h.fake.deliverPost(FakeWatchTransport.envelope(.workoutSummary(summary)))
        let id = try #require(summary.shiftId)
        await eventually { h.bridge.desk.summary(for: id) != nil }
        #expect(h.bridge.desk.summary(for: id) == summary)
    }

    // MARK: The decisions

    @Test func aComplicationPushNeedsAPhaseChangeTheWatchCantHear() {
        #expect(WatchComplicationPusher.shouldPush(before: .offClock, after: .working, reachable: false, complicationEnabled: true))
        #expect(!WatchComplicationPusher.shouldPush(before: .working, after: .working, reachable: false, complicationEnabled: true))
        #expect(!WatchComplicationPusher.shouldPush(before: .offClock, after: .working, reachable: true, complicationEnabled: true))
        #expect(!WatchComplicationPusher.shouldPush(before: .offClock, after: .working, reachable: false, complicationEnabled: false))
        #expect(!WatchComplicationPusher.shouldPush(before: nil, after: .working, reachable: false, complicationEnabled: true))
    }

    @Test func aWorkoutLaunchNeedsAPhoneClockInWithRecordingOn() {
        let snapshot = LiveSnapshot(phase: .working, timerStart: Date(), workedSoFar: 0, workedLabel: "worked today", breakStart: nil,
                                    breakReason: "", fieldName: "North", nextRows: [], shiftTrees: 0, fieldShaped: 0, fieldTotal: 0,
                                    lastAction: nil, canUndo: false)
        var working = WatchState(signedIn: true, farmName: "F", fieldName: "North", snapshot: snapshot, nextRows: [], todayWorked: 0,
                                 todayTrees: 0, canUndo: false, recordWorkouts: true, updatedAt: Date(), shiftId: UUID())
        #expect(WatchComplicationPusher.shouldLaunchWorkout(before: .offClock, state: working, openedByWatch: false, watchAppInstalled: true))
        #expect(WatchComplicationPusher.shouldLaunchWorkout(before: .signedOut, state: working, openedByWatch: false, watchAppInstalled: true))
        #expect(!WatchComplicationPusher.shouldLaunchWorkout(before: .working, state: working, openedByWatch: false, watchAppInstalled: true))
        #expect(!WatchComplicationPusher.shouldLaunchWorkout(before: nil, state: working, openedByWatch: false, watchAppInstalled: true))
        #expect(!WatchComplicationPusher.shouldLaunchWorkout(before: .offClock, state: working, openedByWatch: true, watchAppInstalled: true))
        #expect(!WatchComplicationPusher.shouldLaunchWorkout(before: .offClock, state: working, openedByWatch: false, watchAppInstalled: false))
        working.recordWorkouts = false
        #expect(!WatchComplicationPusher.shouldLaunchWorkout(before: .offClock, state: working, openedByWatch: false, watchAppInstalled: true))
    }

    // MARK: Settings wording

    @Test func theSettingsStatusLineNamesTheWatch() {
        #expect(WatchSettingsWording.status(.inReach) == "Time Card on your watch · in reach")
        #expect(WatchSettingsWording.status(.outOfReach) == "Time Card on your watch · out of reach")
        #expect(WatchSettingsWording.status(.appNotInstalled) == "Time Card on your watch · not installed: install it from the Watch app")
        #expect(WatchSettingsWording.status(.noWatch) == "No Apple Watch paired")
    }

    @Test func theFootnoteAddsTheActionButtonWhenRecordingIsOff() {
        let on = WatchSettingsWording.footnote(recordWorkouts: true)
        #expect(on == "Workouts keep Time Card on your watch all shift and log heart rate and calories in Health. They never go to the farm.")
        #expect(WatchSettingsWording.footnote(recordWorkouts: false) == on + " The Action button needs workouts on.")
    }

    @Test func theSectionShowsOnlyWithAPairedWatch() {
        #expect(!WatchSettingsWording.isShown(.noWatch))
        #expect(WatchSettingsWording.isShown(.appNotInstalled))
        #expect(WatchSettingsWording.isShown(.inReach))
        #expect(WatchSettingsWording.isShown(.outOfReach))
    }
}
