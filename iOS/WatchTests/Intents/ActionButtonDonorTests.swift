import Foundation
import Observation
import Testing
import TreeFarmKit
@testable import TimeCardWatch

/// The Ultra's Action button (docs/watch.md 4.2): the first press clocks in and records; while
/// working the next press marks the shown row, on a break it resumes work; Action + side pauses
/// for lunch, then a break; the button never clocks out.
@MainActor
@Suite("Action button")
struct ActionButtonDonorTests {
    typealias F = IntentFixtures

    final class RecordingDonations: ActionButtonDonating {
        var donations: [ActionButtonNext] = []
        func donate(_ next: ActionButtonNext) { donations.append(next) }
    }

    /// The workout's recording status, as `ShiftWorkout.shared.live.recording` reports it.
    @MainActor @Observable final class FakeRecording {
        var status: WorkoutLive.Recording
        init(_ status: WorkoutLive.Recording) { self.status = status }
    }

    func donor(_ status: WorkoutLive.Recording = .recording) -> (ActionButtonDonor, RecordingDonations) {
        donor(FakeRecording(status))
    }

    func donor(_ recording: FakeRecording) -> (ActionButtonDonor, RecordingDonations) {
        let recorded = RecordingDonations()
        let donor = ActionButtonDonor(donating: recorded, recording: { recording.status })
        return (donor, recorded)
    }

    /// Waits (briefly) for the donor to hear about a change.
    func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Donations

    @Test func workingDonatesMarkNextRow() {
        let (donor, recorded) = donor()
        donor.update(F.working())
        #expect(recorded.donations == [.markNextRow])
    }

    @Test func aBreakDonatesResumeWork() {
        let (donor, recorded) = donor()
        donor.update(F.onLunch())
        #expect(recorded.donations == [.resumeWork])
        let (other, recordedBreak) = self.donor()
        other.update(F.onBreak())
        #expect(recordedBreak.donations == [.resumeWork])
    }

    @Test func everyPhaseChangeDonatesAgainAndNothingElseDoes() {
        let (donor, recorded) = donor()
        donor.update(F.working())
        donor.update(F.working(chips: F.chips(from: 14, count: 39)))  // a row: same phase
        donor.update(F.onLunch())
        donor.update(F.onLunch())
        donor.update(F.working())
        #expect(recorded.donations == [.markNextRow, .resumeWork, .markNextRow])
    }

    @Test func offTheClockOrWithNoStateDonatesNothing() {
        let (donor, recorded) = donor()
        donor.update(nil)
        donor.update(F.signedOut)
        donor.update(F.offClock())
        #expect(recorded.donations.isEmpty)
    }

    @Test func recordingOffDonatesNothing() {
        let (donor, recorded) = donor()
        var off = F.working()
        off.recordWorkouts = false
        donor.update(off)
        #expect(recorded.donations.isEmpty)
        // Turned back on mid-shift: donated then.
        donor.update(F.working())
        #expect(recorded.donations == [.markNextRow])
    }

    @Test func healthDeniedDonatesNothing() {
        let (donor, recorded) = donor(.notAuthorized)
        donor.update(F.working())
        donor.update(F.onLunch())
        #expect(recorded.donations.isEmpty)
    }

    @Test func aWorkoutThatStartsAfterThePhaseChangeDonatesAgain() async {
        // The state says working before the session is running; a donation then may not count.
        let recording = FakeRecording(.idle)
        let (donor, recorded) = donor(recording)
        donor.update(F.working())
        #expect(recorded.donations == [.markNextRow])
        recording.status = .recording
        await eventually { recorded.donations.count == 2 }
        #expect(recorded.donations == [.markNextRow, .markNextRow])
        // A row is no change, and neither is a pause on lunch (the phase change donated it).
        donor.update(F.working(chips: F.chips(from: 14, count: 39)))
        donor.update(F.onLunch())
        recording.status = .paused
        try? await Task.sleep(for: .milliseconds(50))
        #expect(recorded.donations == [.markNextRow, .markNextRow, .resumeWork])
    }

    @Test func healthDeniedLaterStopsDonating() async {
        let recording = FakeRecording(.recording)
        let (donor, recorded) = donor(recording)
        donor.update(F.working())
        recording.status = .notAuthorized
        try? await Task.sleep(for: .milliseconds(50))
        donor.update(F.onLunch())
        #expect(recorded.donations == [.markNextRow])
    }

    // MARK: Presses

    @Test func theFirstPressClocksInFromTheActionButton() async {
        let model = FakeIntentModel(F.offClock())
        var attached = 0
        let said = await StartShiftWorkoutIntent(style: .treeShift).speak(model: model, sessionPossible: true) { attached += 1 }
        #expect(model.performed == [.clockIn(fieldId: nil)])
        #expect(model.sources == [.actionButton])
        #expect(attached == 0)
        #expect(said == F.phoneSays(.clockIn(fieldId: nil)))
    }

    @Test func theFirstPressOnTheClockOnlyStartsTheWorkout() async {
        let model = FakeIntentModel(F.working())
        var attached = 0
        let said = await StartShiftWorkoutIntent(style: .treeShift).speak(model: model, sessionPossible: true) { attached += 1 }
        #expect(model.performed.isEmpty)
        #expect(attached == 1)
        #expect(said == "Recording your shift.")
    }

    @Test func aPressOnTheClockWithRecordingOffSaysTheButtonNeedsWorkouts() async {
        var state = F.working()
        state.recordWorkouts = false
        let model = FakeIntentModel(state)
        var attached = 0
        let said = await StartShiftWorkoutIntent(style: .treeShift).speak(model: model, sessionPossible: true) { attached += 1 }
        // Nothing records, so it never says it does.
        #expect(said == "Action button needs workouts on.")
        #expect(attached == 0)
        #expect(model.performed.isEmpty)
    }

    @Test func aPressOnTheClockWithHealthDeniedSaysTheButtonNeedsWorkouts() async {
        let model = FakeIntentModel(F.onLunch())
        var attached = 0
        let said = await StartShiftWorkoutIntent(style: .treeShift).speak(model: model, sessionPossible: false) { attached += 1 }
        #expect(said == WatchDisplay.actionButtonNeedsWorkouts)
        #expect(attached == 0)
        #expect(model.performed.isEmpty)
    }

    @Test func theFirstPressWithHealthDeniedStillClocksIn() async {
        let model = FakeIntentModel(F.offClock())
        var attached = 0
        let said = await StartShiftWorkoutIntent(style: .treeShift).speak(model: model, sessionPossible: false) { attached += 1 }
        #expect(model.performed == [.clockIn(fieldId: nil)])
        #expect(attached == 0)
        #expect(said == F.phoneSays(.clockIn(fieldId: nil)))
    }

    @Test func theFirstPressWithRecordingOffStillClocksIn() async {
        var state = F.offClock()
        state.recordWorkouts = false
        let model = FakeIntentModel(state, reach: .outOfReach)
        let said = await StartShiftWorkoutIntent(style: .treeShift).speak(model: model, sessionPossible: true) {}
        #expect(model.performed == [.clockIn(fieldId: nil)])
        #expect(said == WatchDisplay.savedForSiri)
    }

    @Test func theFirstPressWithNoStateSaysWhy() async {
        let model = FakeIntentModel(nil, reach: .outOfReach)
        #expect(await StartShiftWorkoutIntent(style: .treeShift).speak(model: model, sessionPossible: true) {} == WatchDisplay.neverConnected)
        #expect(model.performed.isEmpty)
    }

    @Test func laterPressesMarkTheShownRow() async {
        let model = FakeIntentModel(F.working())
        _ = await MarkNextRowIntent().speak(model: model)
        #expect(model.performed == [.markRow(RowRef(blockId: F.blockId, row: 13))])
        #expect(model.sources == [.actionButton])
    }

    @Test func aPressWithNoRowSaysTheNoChipLine() async {
        let model = FakeIntentModel(F.fieldDone())
        #expect(await MarkNextRowIntent().speak(model: model) == "Every row in North is shaped.")
        #expect(model.performed.isEmpty)
    }

    @Test func aPressOnABreakResumesWork() async {
        let model = FakeIntentModel(F.onLunch())
        _ = await ResumeWorkIntent().speak(model: model)
        #expect(model.performed == [.endBreak])
    }

    @Test func actionPlusSidePausesForLunchThenABreak() async {
        let first = FakeIntentModel(F.working())
        first.displayed?.hadLunchToday = false
        _ = await PauseShiftIntent().speak(model: first)
        #expect(first.performed == [.startBreak(.lunch, reason: "")])
        let second = FakeIntentModel(F.working())
        second.displayed?.hadLunchToday = true
        _ = await PauseShiftIntent().speak(model: second)
        #expect(second.performed == [.startBreak(.break, reason: "")])
    }

    @Test func actionPlusSideWhilePausedResumes() async {
        let model = FakeIntentModel(F.onBreak())
        _ = await ResumeShiftIntent().speak(model: model)
        #expect(model.performed == [.endBreak])
        #expect(model.sources == [.actionButton])
    }

    @Test func theButtonNeverClocksOut() async {
        let model = FakeIntentModel(F.working())
        _ = await StartShiftWorkoutIntent(style: .treeShift).speak(model: model, sessionPossible: true) {}
        _ = await MarkNextRowIntent().speak(model: model)
        _ = await PauseShiftIntent().speak(model: model)
        _ = await ResumeShiftIntent().speak(model: model)
        _ = await ResumeWorkIntent().speak(model: model)
        #expect(!model.performed.contains(.clockOut))
    }

    @Test func theWorkoutIsATreeShift() {
        #expect(StartShiftWorkoutIntent.suggestedWorkouts.map(\.workoutStyle) == [.treeShift])
        #expect(ShiftWorkoutStyle.allCases == [.treeShift])
    }
}
