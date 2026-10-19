import Foundation
import Testing
import TreeFarmKit
import TreeFarmKitTestSupport
@testable import TimeCardWatch

/// The watch's model: the confirmed state from the phone, the taps on their way, the displayed
/// state the screen and complications read, and what each tap's answer plays and says
/// (docs/watch.md 1.4, 3.10, 3.11).
@MainActor
@Suite("Watch shift model", .serialized)
struct WatchShiftModelTests {
    typealias F = WatchFixture

    let directory = FileManager.default.temporaryDirectory.appending(path: "WatchShiftModelTests-\(UUID().uuidString)")
    let recorder = WatchModelRecorder()
    let clock = TestClock(WatchFixture.at(10, 0))

    func makeModel(_ transport: FakeWatchTransport, store: InMemoryOutboxStore = InMemoryOutboxStore(),
                   replyTimeout: Duration = .seconds(2), directory: URL? = nil,
                   sessionActive: Bool = false) -> WatchShiftModel {
        let recorder = recorder
        let clock = clock
        let model = WatchShiftModel(transport: transport, store: store, directory: directory ?? self.directory,
                                    replyTimeout: replyTimeout, now: { clock.now },
                                    haptics: { recorder.haptics.append($0) },
                                    reloadComplications: { recorder.reloads += 1 },
                                    sessionActive: { sessionActive })
        model.addObserver { recorder.changes.append($0) }
        return model
    }

    /// A model that has heard `state` from a phone that answers with `phone`.
    func connected(_ state: WatchState, reachable: Bool = true) async -> (WatchShiftModel, FakeWatchTransport, WatchTestPhone) {
        let phone = WatchTestPhone(state)
        let fake = FakeWatchTransport(reachable: reachable)
        fake.defaultAnswer = .respond { phone.answer($0) }
        let model = makeModel(fake)
        // The context WatchConnectivity replays at activation, already waiting.
        fake.deliverContext(F.envelope(state))
        model.activate()
        await fake.drained()
        return (model, fake, phone)
    }

    // MARK: Taps and their answers

    @Test func aTapShowsAtOnceThenTheReplySettlesItWithSuccess() async {
        let (model, _, phone) = await connected(F.working())

        let outcome = await model.perform(.markRow(F.row(14)), source: .button)

        guard case .done(let reply) = outcome else { Issue.record("expected done, got \(outcome)"); return }
        #expect(reply.lastAction == "Row 14 marked")
        #expect(model.displayed?.nextRows.first?.title == "Row 15")
        #expect(model.confirmed?.revision == 6)
        #expect(model.toast == WatchToast(text: "Row 14 marked", kind: .success))
        #expect(recorder.haptics == [.confirmed])
        #expect(model.waitingCount == 0)
        #expect(phone.commands.map(\.command) == [.markRow(F.row(14))])
    }

    @Test func theScreenMovesBeforeThePhoneAnswers() async {
        let (model, fake, _) = await connected(F.working())
        fake.defaultAnswer = .after(.milliseconds(300), fake.defaultAnswer!)

        let task = Task { await model.perform(.markRow(F.row(14)), source: .doubleTap) }
        #expect(await eventually { model.displayed?.nextRows.first?.title == "Row 15" })
        #expect(model.isSending)
        #expect(model.waitingCount == 0, "a tap in flight never flashes the badge")
        _ = await task.value
        #expect(!model.isSending)
    }

    @Test func aRefusalShowsThePhonesSentenceAndTheScreenFollowsItsState() async {
        let (model, _, phone) = await connected(F.working())
        phone.refuseNext("Row 14 was shaped by Sam on Oct 16. Next open row is 15.")

        let outcome = await model.perform(.markRow(F.row(14)), source: .button)

        guard case .refused(let reply) = outcome else { Issue.record("expected refused, got \(outcome)"); return }
        #expect(reply.speech.hasPrefix("Row 14 was shaped"))
        #expect(model.toast == WatchToast(text: "Row 14 was shaped by Sam on Oct 16. Next open row is 15.", kind: .refusal))
        #expect(model.toast?.duration == 4)
        #expect(recorder.haptics == [.refused])
        #expect(model.displayed?.nextRows.first?.title == "Row 14", "the phone's state, without the refused tap")
    }

    @Test func outOfReachTheTapIsQueuedWithItsTimeAndShift() async {
        let (model, fake, _) = await connected(F.working(), reachable: false)
        clock.advance(31)

        let outcome = await model.perform(.markRow(F.row(14)), source: .button)

        #expect(outcome == .queued("Saved on watch · 1 waiting"))
        #expect(model.toast == WatchToast(text: "Saved on watch · 1 waiting", kind: .saved))
        #expect(model.toast?.duration == 2.5)
        #expect(recorder.haptics == [.queued])
        #expect(model.waitingCount == 1)
        #expect(model.queue.first?.issuedAt == F.at(10, 0, 31))
        #expect(model.queue.first?.shiftId == F.shift)
        #expect(model.queue.first?.userId == F.user)
        #expect(model.displayed?.nextRows.first?.title == "Row 15")
        #expect(fake.sent.isEmpty)
    }

    @Test func aTapQueuedWhileThePhoneNeedsUnlockingSaysSo() async {
        let (model, fake, _) = await connected(F.working(), reachable: false)
        fake.setNeedsUnlock(true)
        #expect(await eventually { model.reach == .needsUnlock })

        let outcome = await model.perform(.markRow(F.row(14)), source: .button)

        #expect(outcome == .queued(WatchDisplay.unlockPhone))
        #expect(model.toast == WatchToast(text: WatchDisplay.unlockPhone, kind: .saved))
        #expect(model.waitingCount == 1)
    }

    @Test func siriHearsTheLongerSavedLine() async {
        let (model, _, _) = await connected(F.working(), reachable: false)
        let outcome = await model.perform(.startBreak(.lunch, reason: ""), source: .siri)
        #expect(outcome == .queued(WatchDisplay.savedForSiri))
    }

    @Test func outOfReachABoundToFailTapIsRefusedAndNotQueued() async {
        let (model, _, _) = await connected(F.offClock(), reachable: false)

        let outcome = await model.perform(.clockOut, source: .button)

        #expect(outcome == .notSent(Speech.notClockedIn))
        #expect(model.waitingCount == 0)
        #expect(recorder.haptics == [.refused])
    }

    @Test func withNoStateEveryCommandIsRefused() async {
        let fake = FakeWatchTransport()
        let model = makeModel(fake)
        model.activate()

        let outcome = await model.perform(.clockIn(fieldId: nil), source: .button)

        #expect(outcome == .notSent(WatchDisplay.neverConnected))
        #expect(fake.sentRequests.compactMap(\.command).isEmpty)
    }

    @Test func aClockInMintsTheShiftIdAndLaterTapsCarryIt() async {
        let (model, _, phone) = await connected(F.offClock())

        _ = await model.perform(.clockIn(fieldId: nil), source: .button)
        _ = await model.perform(.markRow(F.row(14)), source: .button)

        let clockIn = phone.commands[0]
        #expect(clockIn.shiftId != nil)
        #expect(clockIn.userId == F.user)
        #expect(phone.commands[1].shiftId == clockIn.shiftId)
        #expect(model.displayed?.shiftId == clockIn.shiftId)
        #expect(recorder.haptics == [.started, .confirmed])
    }

    @Test func eachKindOfTapHasItsOwnHaptic() async {
        let (model, _, _) = await connected(F.working())
        _ = await model.perform(.startBreak(.lunch, reason: ""), source: .button)
        _ = await model.perform(.endBreak, source: .button)
        _ = await model.perform(.clockOut, source: .button)
        #expect(recorder.haptics == [.breakStarted, .backToWork, .stopped])
    }

    @Test func nextRowSendsTheChipShownNeverMarkNextRow() async {
        let (model, _, phone) = await connected(F.working())
        _ = await model.perform(.markNextRow, source: .actionButton)
        _ = await model.perform(.markNextRow, source: .actionButton)
        #expect(phone.commands.map(\.command) == [.markRow(F.row(14)), .markRow(F.row(15))])
    }

    @Test func twoQuickTapsMarkTwoRows() async {
        let (model, fake, phone) = await connected(F.working())
        fake.defaultAnswer = .after(.milliseconds(100), fake.defaultAnswer!)
        let primary = { WatchDisplay.command(for: WatchDisplay.primary(model.displayed))! }

        let firstTap = primary()
        async let first = model.perform(firstTap, source: .doubleTap)
        _ = await eventually { model.displayed?.nextRows.first?.title == "Row 15" }
        let secondTap = primary()
        async let second = model.perform(secondTap, source: .doubleTap)
        _ = await (first, second)

        #expect(phone.commands.map(\.command) == [.markRow(F.row(14)), .markRow(F.row(15))])
        #expect(model.displayed?.nextRows.first?.title == "Row 16")
    }

    // MARK: No chip

    @Test func noChipQueuesNothingAndSaysFieldDone() async {
        let (model, fake, _) = await connected(F.working(rows: nil, shaped: 400, total: 400))
        let outcome = await model.perform(.markNextRow, source: .doubleTap)
        #expect(outcome == .notSent("Every row in North is shaped."))
        #expect(fake.sentRequests.compactMap(\.command).isEmpty)
        #expect(model.waitingCount == 0)
    }

    @Test func noChipQueuesNothingAndSaysOutOfKnownRows() async {
        let (model, fake, _) = await connected(F.working(rows: nil), reachable: false)
        let outcome = await model.perform(.markNextRow, source: .actionButton)
        #expect(outcome == .notSent(WatchDisplay.outOfKnownRows))
        #expect(fake.sent.isEmpty)
        #expect(model.waitingCount == 0)
    }

    // MARK: States from the phone

    @Test func aNewStateWithTwoQueuedMarksStillShowsRow16() async {
        let (model, fake, phone) = await connected(F.working(), reachable: false)
        _ = await model.perform(.markRow(F.row(14)), source: .button)
        _ = await model.perform(.markRow(F.row(15)), source: .button)

        // Siri on the phone added a note meanwhile: a newer state without the taps.
        let pushed = phone.change { $0.todayTrees = 40 }
        fake.deliverContext(F.envelope(pushed))
        #expect(await eventually { model.confirmed?.revision == pushed.revision })

        #expect(model.displayed?.nextRows.first?.title == "Row 16")
        #expect(model.displayed?.todayTrees == 40)
        #expect(model.waitingCount == 2)
    }

    @Test func appliedIdsArentAppliedTwice() async {
        let (model, fake, _) = await connected(F.working(), reachable: false)
        _ = await model.perform(.markRow(F.row(14)), source: .button)
        let queued = model.queue[0]

        // The phone applied it (the reply was lost) and lists it: row 14 is gone from its rows.
        var after = WatchOptimism.apply(.markRow(F.row(14)), shiftId: F.shift, to: F.working(), at: F.at(10, 0))
        after.revision = 9
        after.appliedRequestIds = [queued.id]
        fake.deliverContext(F.envelope(after))
        #expect(await eventually { model.confirmed?.revision == 9 })

        #expect(model.displayed?.nextRows.first?.title == "Row 15", "not row 16")
        #expect(await eventually { model.waitingCount == 0 }, "the state cleared it from the outbox")
    }

    @Test func aNewEpochWithALowerRevisionIsAccepted() async {
        let (model, fake, _) = await connected(F.working(revision: 40))
        fake.deliverContext(F.envelope(F.offClock(revision: 2, epoch: UUID())))
        #expect(await eventually { model.confirmed?.revision == 2 })
        #expect(WatchDisplay.phase(model.displayed) == .offClock)
    }

    @Test func anOlderRevisionInTheSameEpochIsIgnored() async {
        let (model, fake, _) = await connected(F.working(revision: 40))
        fake.deliverContext(F.envelope(F.offClock(revision: 39)))
        await fake.drained()
        #expect(model.confirmed?.revision == 40)
        fake.deliverContext(F.envelope(F.working(revision: 41)))
        #expect(await eventually { model.confirmed?.revision == 41 })
        #expect(WatchDisplay.phase(model.displayed) == .working)
    }

    @Test func aStatePushedAsAMessageIsAcceptedToo() async {
        let (model, fake, _) = await connected(F.working(revision: 5))
        fake.deliverPost(F.envelope(F.onLunch(revision: 6)))
        #expect(await eventually { model.confirmed?.revision == 6 })
        #expect(WatchDisplay.phase(model.displayed) == .lunch)
    }

    @Test func aUserInfoEventIsHandledLikeAContextAndDrainedWaitsForIt() async {
        let (model, fake, _) = await connected(F.working(revision: 5))
        fake.deliverUserInfo(F.envelope(F.onLunch(revision: 7)))

        await fake.drained()

        #expect(model.confirmed?.revision == 7)
        #expect(WatchStateFile.read(from: directory).displayed?.revision == 7)
        #expect(fake.unhandledEvents == 0)
    }

    // MARK: Complications

    @Test func theStateFileGetsTheDisplayedStateAndReloadsOnlyWhenItChanged() async {
        let (model, fake, _) = await connected(F.working(), reachable: false)
        #expect(WatchStateFile.read(from: directory) == WatchStateFile.Contents(displayed: model.displayed))
        let reloads = recorder.reloads
        #expect(reloads >= 1)

        _ = await model.perform(.markRow(F.row(14)), source: .button)

        let file = WatchStateFile.read(from: directory)
        #expect(file.displayed?.nextRows.first?.title == "Row 15", "displayed, not the raw phone state")
        #expect(file.waitingCount == 1)
        #expect(recorder.reloads > reloads)
        let after = recorder.reloads

        // The same state again: nothing to write, nothing to reload.
        fake.deliverContext(F.envelope(F.working()))
        await fake.drained()
        #expect(recorder.reloads == after)
    }

    @Test func aWaitingClockOutIsInTheStateFile() async {
        let (model, _, _) = await connected(F.working(), reachable: false)
        _ = await model.perform(.clockOut, source: .button)
        #expect(model.clockOutWaiting)
        #expect(WatchStateFile.read(from: directory).clockOutWaiting)
    }

    // MARK: Undo

    @Test func undoTakesBackTheLastQueuedTapFirst() async {
        let (model, fake, _) = await connected(F.working(), reachable: false)
        _ = await model.perform(.markRow(F.row(14)), source: .button)
        _ = await model.perform(.markRow(F.row(15)), source: .button)

        let outcome = await model.undo()

        guard case .done(let reply) = outcome else { Issue.record("expected done, got \(outcome)"); return }
        #expect(reply.speech == "Took back row 15. It wasn’t sent yet.")
        #expect(model.waitingCount == 1)
        #expect(model.displayed?.nextRows.first?.title == "Row 15")
        #expect(fake.sent.isEmpty)
    }

    @Test func undoWithNothingQueuedGoesToThePhone() async {
        let (model, _, phone) = await connected(F.working())
        _ = await model.perform(.markRow(F.row(14)), source: .button)

        let outcome = await model.undo()

        guard case .done = outcome else { Issue.record("expected done, got \(outcome)"); return }
        #expect(phone.commands.last?.command == .undo)
        #expect(model.waitingCount == 0)
    }

    @Test func undoWithNothingQueuedAndThePhoneAwayNeedsThePhone() async {
        let (model, _, _) = await connected(F.working(), reachable: false)
        #expect(await model.undo() == .notSent(WatchDisplay.undoNeedsPhone))
    }

    @Test func undoClockInIsOfferedForTwoMinutesAfterAWatchClockIn() async {
        let (model, _, phone) = await connected(F.offClock())
        _ = await model.perform(.clockIn(fieldId: nil), source: .doubleTap)
        let minted = phone.commands[0].shiftId

        #expect(model.canUndoClockIn)
        clock.advance(119)
        #expect(model.canUndoClockIn)

        let outcome = await model.undoClockIn()

        guard case .done = outcome else { Issue.record("expected done, got \(outcome)"); return }
        #expect(phone.commands.last?.command == .cancelShift(minted!))
        #expect(WatchDisplay.phase(model.displayed) == .offClock)
        #expect(!model.canUndoClockIn)
    }

    @Test func undoClockInIsGoneAfterTwoMinutes() async {
        let (model, _, _) = await connected(F.offClock())
        _ = await model.perform(.clockIn(fieldId: nil), source: .doubleTap)
        clock.advance(121)
        #expect(!model.canUndoClockIn)
    }

    @Test func undoClockInIsNeverOfferedForAPhoneShift() async {
        let (model, _, _) = await connected(F.working())
        #expect(!model.canUndoClockIn)
    }

    @Test func undoClockInWorksWhileQueued() async {
        let (model, _, _) = await connected(F.offClock(), reachable: false)
        _ = await model.perform(.clockIn(fieldId: nil), source: .button)
        #expect(model.canUndoClockIn)

        let outcome = await model.undoClockIn()

        #expect(outcome == .queued("Saved on watch · 2 waiting"))
        #expect(WatchDisplay.phase(model.displayed) == .offClock)
    }

    // MARK: The phone's answers to queued taps

    @Test func aQueuedTapRefusedLaterIsListedForAnHour() async {
        let (model, fake, phone) = await connected(F.working(), reachable: false)
        _ = await model.perform(.startBreak(.lunch, reason: ""), source: .button)
        phone.refuseNext("You’re already on lunch since 10:34.")

        fake.setReachable(true)
        #expect(await eventually { model.waitingCount == 0 && !model.refused.isEmpty })

        #expect(model.refused.first?.speech == "You’re already on lunch since 10:34.")
        #expect(model.toast?.kind == .refusal)
        clock.advance(3601)
        #expect(model.refused.isEmpty)
    }

    @Test func aRefusedWatchClockInIsRememberedForTheWorkout() async {
        let (model, _, phone) = await connected(F.offClock())
        phone.refuseNext("You’re already clocked in since 7:00.")
        _ = await model.perform(.clockIn(fieldId: nil), source: .button)
        let minted = phone.commands[0].shiftId!
        #expect(model.refusedClockIns == [minted])
        #expect(recorder.changes.last?.workout.refusedClockIns == [minted])
    }

    @Test func observersHearAPendingClockInBeforeAnyReply() async {
        let (model, fake, _) = await connected(F.offClock())
        fake.defaultAnswer = .after(.milliseconds(300), fake.defaultAnswer!)
        let task = Task { await model.perform(.clockIn(fieldId: nil), source: .button) }

        #expect(await eventually {
            recorder.changes.last.map { change in (change.workout.outbox + change.workout.inFlight).contains { $0.command == .clockIn(fieldId: nil) } } ?? false
        })
        #expect(recorder.changes.last?.displayed?.isClockedIn == true)
        _ = await task.value
    }

    @Test func reachabilityComingBackFlushesTheOutbox() async {
        let (model, fake, phone) = await connected(F.working(), reachable: false)
        _ = await model.perform(.markRow(F.row(14)), source: .button)
        _ = await model.perform(.markRow(F.row(15)), source: .button)
        #expect(model.reach == .outOfReach)

        fake.setReachable(true)

        #expect(await eventually { model.waitingCount == 0 })
        #expect(phone.commands.map(\.command) == [.markRow(F.row(14)), .markRow(F.row(15))])
        #expect(model.reach == .reachable)
        #expect(model.displayed?.nextRows.first?.title == "Row 16")
    }

    @Test func aSlowReplySaysWaitingForPhoneThenQueues() async {
        let phone = WatchTestPhone(F.working())
        let fake = FakeWatchTransport()
        fake.defaultAnswer = .respond { phone.answer($0) }
        let model = makeModel(fake, replyTimeout: .milliseconds(400))
        model.slowAfter = .milliseconds(100)
        model.activate()
        fake.deliverContext(F.envelope(F.working()))
        _ = await eventually { model.confirmed != nil }
        fake.enqueue(.lost)

        let task = Task { await model.perform(.markRow(F.row(14)), source: .button) }
        #expect(await eventually { model.isSlow })
        #expect(await task.value == .queued("Saved on watch · 1 waiting"))
        #expect(!model.isSlow)
    }

    // MARK: Reach

    @Test func reachFollowsTheTransport() async {
        let fake = FakeWatchTransport(reachable: false)
        let model = makeModel(fake)
        model.activate()
        #expect(await eventually { model.reach == .neverConnected })
        fake.deliverContext(F.envelope(F.working()))
        #expect(await eventually { model.reach == .outOfReach })
        fake.setReachable(true)
        #expect(await eventually { model.reach == .reachable })
        fake.setNeedsUnlock(true)
        #expect(await eventually { model.reach == .needsUnlock })
        fake.setNeedsUnlock(false)
        #expect(await eventually { model.reach == .reachable })
    }

    @Test func aQuestionIsAnsweredByThePhone() async {
        let (model, _, _) = await connected(F.working())
        #expect(await model.ask(.trees) == "You’ve shaped 38 trees today.")
    }

    @Test func aQuestionWithThePhoneAwayNeedsThePhone() async {
        let (model, _, _) = await connected(F.working(), reachable: false)
        #expect(await model.ask(.trees) == WatchDisplay.askNeedsPhone)
    }

    @Test func confirmationAsksBeforeClockOutAndFarRows() async {
        let (model, _, _) = await connected(F.working())
        #expect(model.confirmation(for: .clockOut)?.hasSuffix("Clock out?") == true)
        #expect(model.confirmation(for: .markRow(F.row(40))) == "Row 40 in block 2? That’s 26 rows ahead.")
        #expect(model.confirmation(for: .markRow(F.row(15))) == nil)
    }

    // MARK: Persistence

    @Test func theConfirmedStateSurvivesARelaunch() async {
        let (model, _, _) = await connected(F.working(revision: 12))
        _ = model
        let again = makeModel(FakeWatchTransport(reachable: false))
        #expect(again.confirmed?.revision == 12)
        #expect(again.reach == .outOfReach)
    }

    @Test func theShiftSummaryShowsOnceAfterAWatchClockOut() async {
        let (model, _, _) = await connected(F.working())
        #expect(model.summary == nil)
        _ = await model.perform(.clockOut, source: .button)
        #expect(model.summary?.shiftId == F.shift)
        model.dismissSummary()
        #expect(model.summary == nil)
    }
}
