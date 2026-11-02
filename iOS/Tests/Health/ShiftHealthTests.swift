import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// A shift's Health card (docs/health.md 4): what it says from Health's numbers.
@MainActor
@Suite("Shift Health card")
struct ShiftHealthTests {
    let full = ShiftHealth(steps: 8120.4, distanceMeters: 5472, flights: 12, activeKcal: 1120.5, avgHeartRate: 103.6, maxHeartRate: 151)

    @Test func everyNumberHealthHasInTheCardsOrder() {
        let stats = ShiftHealthWording.stats(full, miles: true)
        #expect(stats.map(\.label) == ["Steps", "Distance", "Flights climbed", "Active calories", "Heart rate"])
        #expect(stats.map(\.value) == ["8,120", "3.4 mi", "12", "1,121 kcal", "avg 104 · max 151"])
        #expect(ShiftHealthWording.stats(full, miles: false)[1].value == "5.5 km")
    }

    @Test func voiceOverHearsTheNumbersInWords() {
        let spoken = ShiftHealthWording.stats(full, miles: true).map(\.spoken)
        #expect(spoken == ["8,120 steps", "3.4 miles", "12 flights", "1,121 calories", "Average heart rate 104, maximum 151"])
    }

    @Test func whatHealthDoesntHaveIsLeftOut() {
        let some = ShiftHealth(steps: 1, maxHeartRate: 140)
        #expect(ShiftHealthWording.stats(some).map(\.value) == ["1", "max 140"])
        #expect(ShiftHealthWording.stats(some).first?.spoken == "1 step")
        #expect(ShiftHealthWording.stats(ShiftHealth()).isEmpty)
        #expect(ShiftHealth().isEmpty && !some.isEmpty)
    }

    @Test func theWatchsWorkoutAddsItsActiveTime() {
        let t0 = Date(timeIntervalSince1970: 1_792_400_000)
        let summary = WorkoutSummary(shiftId: UUID(), start: t0, end: t0.addingTimeInterval(29_520), activeDuration: 27_660)
        #expect(ShiftHealthWording.workoutLine(summary) == "Tree care workout · 7:41 active")
        #expect(ShiftHealthWording.workoutLine(nil) == nil)
    }

    @Test func itPromisesTheNumbersStayOnThePhone() {
        #expect(ShiftHealthWording.footnote.contains("never sent to the farm"))
        #expect(ShiftHealthWording.permissionBody.contains("never sent to the farm"))
        #expect(ShiftHealthWording.footnote.contains("lunch and breaks are left out"))
    }

    @Test func theDemoReaderNeverPromptsAndScalesWithTheTimeWorked() async {
        let reader = DemoShiftHealthReader()
        #expect(await reader.needsPermission() == false)
        let t0 = Date(timeIntervalSince1970: 1_792_400_000)
        let health = await reader.read([DateInterval(start: t0, duration: 3600), DateInterval(start: t0.addingTimeInterval(5400), duration: 1800)])
        #expect(health.steps.map { Int($0.rounded()) } == 90 * 18)
        #expect(await reader.read([]).isEmpty)
    }

    @Test func testHostsGetTheDemoReader() throws {
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true))
        #expect(model.health is DemoShiftHealthReader)
    }
}
