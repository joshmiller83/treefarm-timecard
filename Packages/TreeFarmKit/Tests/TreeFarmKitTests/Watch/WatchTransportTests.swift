import Foundation
import Testing
@testable import TreeFarmKit
import TreeFarmKitTestSupport

/// The transport seam and the fake every watch test drives it with.
@Suite("Watch transport")
struct WatchTransportTests {
    let t0 = Date(timeIntervalSince1970: 1_792_400_000)

    func request(_ command: FieldCommand = .clockOut) -> WatchRequest {
        WatchRequest(body: .command(command), issuedAt: t0)
    }

    func replyEnvelope(for request: WatchRequest, _ speech: String = "Done.") -> Data {
        FakeWatchTransport.envelope(.reply(WatchReply(requestId: request.id, speech: speech, succeeded: true)))
    }

    @Test func aScriptedReplyAnswersTheSend() async throws {
        let fake = FakeWatchTransport()
        let r = request()
        fake.enqueue(.reply(replyEnvelope(for: r)))
        let message = FakeWatchTransport.envelope(.request(r))
        let answer = try await fake.send(message, timeout: .seconds(1))
        guard case .reply(let reply) = try WatchEnvelope.decode(answer).message else { Issue.record("not a reply"); return }
        #expect(reply.requestId == r.id)
        #expect(fake.sentRequests == [r])
    }

    @Test func aScriptedOtherSideSeesTheRequest() async throws {
        let fake = FakeWatchTransport()
        fake.defaultAnswer = .respond { data in
            guard case .request(let r)? = try? WatchEnvelope.decode(data).message else { return Data() }
            return FakeWatchTransport.envelope(.reply(WatchReply(requestId: r.id, speech: "Saw \(r.id)", succeeded: true)))
        }
        let r = request()
        let answer = try await fake.send(FakeWatchTransport.envelope(.request(r)), timeout: .seconds(1))
        guard case .reply(let reply) = try WatchEnvelope.decode(answer).message else { Issue.record("not a reply"); return }
        #expect(reply.speech == "Saw \(r.id)")
    }

    @Test func anUnreachableSideRefusesTheSend() async {
        let fake = FakeWatchTransport(reachable: false)
        await #expect(throws: WatchTransportError.notReachable) {
            try await fake.send(FakeWatchTransport.envelope(.request(request())), timeout: .seconds(1))
        }
        await #expect(throws: WatchTransportError.notReachable) {
            try await fake.post(Data())
        }
        #expect(fake.sent.count == 1)
    }

    @Test func aLostReplyTimesOut() async {
        let fake = FakeWatchTransport()
        fake.enqueue(.lost)
        await #expect(throws: WatchTransportError.timedOut) {
            try await fake.send(Data(), timeout: .milliseconds(30))
        }
    }

    @Test func aReplyAfterTheTimeoutIsIgnored() async throws {
        let fake = FakeWatchTransport()
        let r = request()
        fake.enqueue(.after(.milliseconds(120), .reply(replyEnvelope(for: r))))
        await #expect(throws: WatchTransportError.timedOut) {
            try await fake.send(FakeWatchTransport.envelope(.request(r)), timeout: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(250))
        #expect(fake.lateReplies == 1)
    }

    @Test func errorsComeBackAsTheyAre() async {
        let fake = FakeWatchTransport()
        fake.enqueue(.fail(.failed("Bluetooth")))
        await #expect(throws: WatchTransportError.failed("Bluetooth")) {
            try await fake.send(Data(), timeout: .seconds(1))
        }
    }

    @Test func reachabilityChangesAreEvents() async {
        let fake = FakeWatchTransport(reachable: false)
        fake.activate()
        fake.setReachable(true)
        fake.setNeedsUnlock(true)
        fake.finish()
        var seen: [String] = []
        for await event in fake.events {
            switch event {
            case .activated(let paired, let installed, _): seen.append("activated \(paired) \(installed)")
            case .reachabilityChanged(let r): seen.append("reach \(r)")
            case .needsUnlock(let n): seen.append("unlock \(n)")
            default: seen.append("other")
            }
        }
        #expect(seen == ["activated true true", "reach false", "reach true", "unlock true"])
        #expect(fake.isReachable)
        #expect(fake.activations == 1)
    }

    @Test func aDeliveredMessageIsAnsweredThroughItsSink() async {
        let fake = FakeWatchTransport()
        let reader = Task {
            for await event in fake.events {
                if case .received(let data, let sink?) = event { sink.send(data + Data("!".utf8)) }
            }
        }
        let reply = await fake.deliverMessage(Data("hi".utf8))
        #expect(reply == Data("hi!".utf8))
        #expect(fake.repliesSent.count == 1)
        fake.finish()
        await reader.value
    }

    @Test func drainedWaitsForEveryContextAndUserInfoToBeHandled() async throws {
        let fake = FakeWatchTransport()
        fake.deliverContext(Data("a".utf8))
        fake.deliverUserInfo(Data("b".utf8))
        #expect(fake.unhandledEvents == 2)
        var dones: [WatchEventDone] = []
        var iterator = fake.events.makeAsyncIterator()
        for _ in 0..<2 {
            switch await iterator.next() {
            case .contextReceived(_, let done)?, .userInfoReceived(_, let done)?: dones.append(done)
            default: Issue.record("unexpected event")
            }
        }
        let waiter = Task { await fake.drained(); return true }
        try await Task.sleep(for: .milliseconds(30))
        dones[0]()
        dones[0]() // twice counts once
        #expect(fake.unhandledEvents == 1)
        dones[1]()
        #expect(await waiter.value)
        #expect(fake.unhandledEvents == 0)
        await fake.drained()
    }

    @Test func complicationTransfersNeedTheComplicationAndABudget() {
        let off = FakeWatchTransport(complicationEnabled: false)
        #expect(!off.transferComplicationState(Data()))
        let on = FakeWatchTransport(complicationEnabled: true, complicationTransfers: 1)
        #expect(on.transferComplicationState(Data("1".utf8)))
        #expect(!on.transferComplicationState(Data("2".utf8)))
        #expect(on.complicationTransfers == [Data("1".utf8)])
    }

    @Test func publishedContextsAreRecorded() throws {
        let fake = FakeWatchTransport()
        let state = WatchState.signedOut(epoch: UUID(), revision: 3, now: t0)
        try fake.publishContext(FakeWatchTransport.envelope(.state(state)))
        #expect(fake.contextStates == [state])
    }

    @Test func theDisconnectedTransportHasNobodyOnTheOtherEnd() async {
        let none = DisconnectedWatchTransport()
        #expect(!none.isReachable && !none.hasContentPending)
        #expect(!none.transferComplicationState(Data()))
        await #expect(throws: WatchTransportError.notReachable) { try await none.send(Data(), timeout: .seconds(1)) }
        await #expect(throws: WatchTransportError.notReachable) { try await none.post(Data()) }
        #expect(throws: Never.self) { try none.publishContext(Data()) }
        none.activate()
        var iterator = none.events.makeAsyncIterator()
        if case .activated(let paired, let installed, _)? = await iterator.next() {
            #expect(!paired && !installed)
        } else {
            Issue.record("no activation")
        }
        await none.drained()
    }

    @Test func theInMemoryStoreKeepsTheOutbox() {
        let store = InMemoryOutboxStore()
        #expect(store.load() == nil)
        var outbox = WatchOutbox()
        outbox.add(request(.endBreak))
        store.save(outbox)
        #expect(store.load() == outbox)
        #expect(store.saves == 1)
    }
}
