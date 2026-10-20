import Foundation
import Testing
import TreeFarmKit
import WatchKit
@testable import TimeCardWatch

/// The small pieces around the model: the outbox file, the rain lock gate, haptics, the pages
/// and the glove-sized buttons.
@Suite("Watch model parts")
struct WatchModelPartsTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "WatchModelPartsTests-\(UUID().uuidString)")

    // MARK: FileOutboxStore

    @Test func anOutboxFileRoundTrips() {
        let store = FileOutboxStore(url: directory.appending(path: "outbox.json"))
        #expect(store.load() == nil)

        var outbox = WatchOutbox()
        outbox.add(WatchRequest(body: .command(.clockOut), issuedAt: Date(timeIntervalSince1970: 1_792_400_000), shiftId: UUID()))
        store.save(outbox)

        #expect(store.load() == outbox)
        #expect(FileOutboxStore(url: directory.appending(path: "outbox.json")).load() == outbox)
    }

    @Test func anUnreadableOutboxFileLoadsNothing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "outbox.json")
        try Data("{".utf8).write(to: url)
        #expect(FileOutboxStore(url: url).load() == nil)
    }

    // MARK: WaterLockGate

    @Test func theRainLockShowsOnWaterResistantWatchesDuringASessionInTheForeground() {
        #expect(WaterLockGate.isAvailable(rating: .wr50, sessionActive: true, foreground: true))
        #expect(WaterLockGate.isAvailable(rating: .wr100, sessionActive: true, foreground: true))
        #expect(!WaterLockGate.isAvailable(rating: .ipx7, sessionActive: true, foreground: true))
        #expect(!WaterLockGate.isAvailable(rating: .wr50, sessionActive: false, foreground: true))
        #expect(!WaterLockGate.isAvailable(rating: .wr100, sessionActive: true, foreground: false))
    }

    // MARK: Haptics

    @Test func eachEventHasItsMeaning() {
        #expect(WatchHaptics.type(for: .started) == .start)
        #expect(WatchHaptics.type(for: .stopped) == .stop)
        #expect(WatchHaptics.type(for: .confirmed) == .success)
        #expect(WatchHaptics.type(for: .refused) == .failure)
        #expect(WatchHaptics.type(for: .queued) == .retry)
        #expect(WatchHaptics.type(for: .breakStarted) == .directionDown)
        #expect(WatchHaptics.type(for: .backToWork) == .directionUp)
    }

    @Test func hapticsCloserThan100msArentStacked() {
        var throttle = HapticThrottle()
        let t = Date(timeIntervalSince1970: 1_792_400_000)
        let first = throttle.shouldPlay(at: t)
        let tooSoon = throttle.shouldPlay(at: t.addingTimeInterval(0.05))
        let later = throttle.shouldPlay(at: t.addingTimeInterval(0.2))
        #expect(first && !tooSoon && later)
    }

    // MARK: Toasts

    @Test func toastsStayLongEnoughToRead() {
        #expect(WatchToast(text: "Row 14 marked", kind: .success).duration == 2.5)
        #expect(WatchToast(text: "Saved on watch · 1 waiting", kind: .saved).duration == 2.5)
        #expect(WatchToast(text: "Row 14 is already marked.", kind: .refusal).duration == 4)
    }

    // MARK: Pages

    @Test func aWristRaiseAfter30sLandsOnNow() {
        let t = Date(timeIntervalSince1970: 1_792_400_000)
        var pages = PageMemory(selection: .today)
        pages.wentAway(at: t)
        pages.cameBack(at: t.addingTimeInterval(31))
        #expect(pages.selection == .now)
    }

    @Test func aQuickGlanceAwayKeepsThePage() {
        let t = Date(timeIntervalSince1970: 1_792_400_000)
        var pages = PageMemory(selection: .controls)
        pages.wentAway(at: t)
        pages.cameBack(at: t.addingTimeInterval(10))
        #expect(pages.selection == .controls)
    }

    @Test func onlyNowTakesTheDoubleTap() {
        #expect(PageMemory(selection: .now).primaryActionEnabled(dialogShown: false))
        #expect(!PageMemory(selection: .now).primaryActionEnabled(dialogShown: true))
        #expect(!PageMemory(selection: .controls).primaryActionEnabled(dialogShown: false))
        #expect(!PageMemory(selection: .today).primaryActionEnabled(dialogShown: false))
    }

    // MARK: Button sizes (docs/watch.md 3.1)

    @Test func buttonsGrowWithTheWatch() {
        let small = ButtonMetrics(screenHeight: 197)    // 40 mm
        let series42 = ButtonMetrics(screenHeight: 223) // 42 mm
        let medium = ButtonMetrics(screenHeight: 248)   // 46 mm
        let ultra2 = ButtonMetrics(screenHeight: 251)   // 49 mm Ultra 2
        let ultra3 = ButtonMetrics(screenHeight: 257)   // 49 mm Ultra 3

        #expect([small.primary, small.grid, small.clockOut, small.secondary] == [60, 56, 52, 48])
        #expect(series42.primary == 60)
        #expect([medium.primary, medium.grid, medium.clockOut, medium.secondary] == [64, 60, 56, 52])
        #expect([ultra2.primary, ultra2.grid, ultra2.clockOut, ultra2.secondary] == [68, 62, 58, 54])
        #expect(ultra3.primary == 68)
        #expect(ButtonMetrics(screenHeight: 224).primary == 64, "44 mm")
    }
}
