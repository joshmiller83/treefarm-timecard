import Foundation
import Testing
import TreeFarmKit
@testable import TimeCardWatch

/// What the workout's screens say: the shift summary (docs/watch.md 3.9), the Today page's
/// workout line and banners (3.6, 2.2, 2.5), and the glove sizes (3.1).
@Suite("Workout screens")
struct WorkoutScreensTests {
    let start = Date(timeIntervalSince1970: 1_792_400_000)

    var closed: ClosedShift {
        ClosedShift(shiftId: UUID(), start: start, end: start.addingTimeInterval(8 * 3600 + 720),
                    worked: 8 * 3600 + 12 * 60, trees: 412)
    }

    var summary: WorkoutSummary {
        WorkoutSummary(shiftId: closed.shiftId, start: start, end: closed.end, activeDuration: 7 * 3600 + 41 * 60,
                       activeKcal: 1_120, avgHeartRate: 104.4, maxHeartRate: 151)
    }

    // MARK: Sizes

    @Test func everyWatchGetsItsGloveSizes() {
        let sizes: [(CGSize, WorkoutSize)] = [
            (CGSize(width: 162, height: 197), .small),   // 40 mm
            (CGSize(width: 176, height: 215), .small),   // 41 mm
            (CGSize(width: 187, height: 223), .small),   // 42 mm
            (CGSize(width: 184, height: 224), .medium),  // 44 mm
            (CGSize(width: 198, height: 242), .medium),  // 45 mm
            (CGSize(width: 208, height: 248), .medium),  // 46 mm
            (CGSize(width: 205, height: 251), .large),   // 49 mm Ultra 2
            (CGSize(width: 211, height: 257), .large),   // 49 mm Ultra 3
        ]
        for (screen, size) in sizes { #expect(WorkoutSize(screen: screen) == size, "\(screen)") }
        #expect([WorkoutSize.small, .medium, .large].map(\.primaryHeight) == [60, 64, 68])
        #expect([WorkoutSize.small, .medium, .large].map(\.secondaryHeight) == [48, 52, 54])
    }

    // MARK: The summary

    @Test func theSummaryShowsWorkedTimeTreesHeartAndEnergyButNeverPay() {
        let content = WorkoutSummaryContent(closed: closed, summary: summary, waitingForPhone: false)
        #expect(content.title == "Shift done")
        #expect(content.worked == "8:12")
        #expect(content.detail == "worked · 412 trees")
        #expect(content.heart == "avg 104 · max 151")
        #expect(content.energy == "1,120 kcal · 7:41 act.")
        #expect(content.workedAccessibility == "Worked 8 hours 12 minutes")
        let everything = [content.title, content.worked, content.detail, content.heart, content.energy].compactMap { $0 }.joined()
        #expect(!everything.contains("$"))
    }

    @Test func theSummaryReadsItsNumbersInWords() {
        // The heart and the flame are hidden from VoiceOver, so the numbers say what they are.
        let content = WorkoutSummaryContent(closed: closed, summary: summary, waitingForPhone: false)
        #expect(content.heartAccessibility == "Average heart rate 104, maximum 151")
        #expect(content.energyAccessibility == "1,120 calories, 7 hours 41 minutes active")

        var partial = summary
        partial.avgHeartRate = nil
        partial.activeKcal = nil
        partial.activeDuration += 50
        let less = WorkoutSummaryContent(closed: closed, summary: partial, waitingForPhone: false)
        #expect(less.heartAccessibility == "Maximum heart rate 151")
        // The minutes the screen shows ("7:41 act."), not rounded up.
        #expect(less.energyAccessibility == "7 hours 41 minutes active")
        #expect(WorkoutSummaryContent(closed: closed, summary: nil, waitingForPhone: false).heartAccessibility == nil)
    }

    @Test func whileTheClockOutWaitsTheTreesAreTheWatchsOwnCount() {
        let content = WorkoutSummaryContent(closed: closed, summary: summary, waitingForPhone: true)
        #expect(content.detail == "412 trees · waiting for iPhone")
    }

    @Test func withoutAWorkoutTheSummaryIsJustTheShift() {
        let content = WorkoutSummaryContent(closed: closed, summary: nil, waitingForPhone: false)
        #expect(content.worked == "8:12" && content.heart == nil && content.energy == nil)
    }

    @Test func withoutHeartRateTheEnergyLineStaysAlone() {
        var noHeart = summary
        noHeart.avgHeartRate = nil
        noHeart.maxHeartRate = nil
        noHeart.activeKcal = nil
        let content = WorkoutSummaryContent(closed: closed, summary: noHeart, waitingForPhone: false)
        #expect(content.heart == nil)
        #expect(content.energy == "7:41 act.")
    }

    // MARK: The workout line and banners

    @Test func theTodayPageSaysWhatTheWorkoutIsDoing() {
        func status(_ recording: WorkoutLive.Recording) -> WorkoutStatus? {
            WorkoutStatus(WorkoutLive(recording: recording))
        }
        #expect(status(.recording)?.text == "Recording shift workout")
        #expect(status(.paused)?.text == "Workout paused")
        #expect(status(.waitingForClockOut)?.text == "Clock-out waiting for iPhone")
        #expect(status(.stoppedUnexpectedly)?.text == "Recording stopped")
        #expect(status(.stoppedUnexpectedly)?.offersRecordAgain == true)
        #expect(status(.notAuthorized)?.text == "Workouts off · Allow Time Card in the Health app on your iPhone.")
        #expect(status(.off)?.text == "Action button needs workouts on.")
        #expect(status(.idle) == nil)
        #expect(status(.recording)?.offersRecordAgain == false)
    }

    @Test func theHeartLineIsLiveFromTheWorkout() {
        #expect(WorkoutStatus.heartLine(WorkoutLive(heartRate: 103.6, kcal: 612.2, recording: .recording)) == "104 bpm · 612 kcal")
        #expect(WorkoutStatus.heartLine(WorkoutLive(recording: .recording)) == nil)
    }

    @Test func theHeartLineReadsInWords() {
        #expect(WorkoutStatus.heartLineAccessibility(WorkoutLive(heartRate: 103.6, kcal: 612.2, recording: .recording))
                == "Heart rate 104, 612 calories")
        #expect(WorkoutStatus.heartLineAccessibility(WorkoutLive(heartRate: 98, recording: .recording)) == "Heart rate 98")
        #expect(WorkoutStatus.heartLineAccessibility(WorkoutLive(kcal: 1, recording: .recording)) == "1 calorie")
        #expect(WorkoutStatus.heartLineAccessibility(WorkoutLive(recording: .recording)) == nil)
    }

    // MARK: The first-launch card

    @Test func theCardAsksForHealthThenForTheReminder() {
        #expect(HealthOnboardingStep.health.title == "Record shifts as workouts")
        #expect(HealthOnboardingStep.health.body == "You earn the calorie equivalent of a brisk walk anytime sensor readings are unavailable.")
        #expect(HealthOnboardingStep.health.button == "Allow Health")
        #expect(HealthOnboardingStep.reminder.body == "Remind me if a clock-out gets stuck.")
    }
}
