import Foundation
import SwiftUI
import Testing
import TimeCardCore
@testable import TimeCard

/// The Live Activity's `.small` layout: the card Apple Watch shows in its Smart Stack (and
/// CarPlay). One control only, picked by the phase, and only system fonts (docs/watch.md 4.4).
/// Renders land in iOS/build/LiveActivityRenders as small-*.png.
@MainActor
@Suite("Live Activity small layout")
struct LiveActivitySmallTests {
    typealias F = LiveFixtures

    /// The farm's day, so "Since 12:01" reads the same wherever the tests run.
    static let calendar = FarmCalendar(timeZone: TimeZone(identifier: "America/Indiana/Indianapolis")!, weekStart: .monday)

    // MARK: The one control

    @Test func workingTheControlMarksTheRowItShows() {
        let snapshot = F.working()
        let d = LiveActivitySmallDisplay(snapshot, calendar: Self.calendar)
        #expect(d.control == .markRow(F.chip(13)))
        #expect(d.controlLabels == ["Row 13 done", "Row 13", "13"])
        #expect(d.controlGlyph == "checkmark")
        #expect(d.controlAccessibilityLabel == "Mark row 13 in block 2 shaped")
        #expect(d.message == nil)
        // The words and glyph above it.
        #expect(!d.isOnBreak)
        #expect(d.glyph == "leaf.fill")
        #expect(d.titles == ["Working · Block 2", "Block 2"])
        #expect(d.detail == "Next Row 13 · 212 trees")
        #expect(d.timerStart == snapshot.timerStart)
        #expect(d.timerCharacters == LiveActivityDisplay(snapshot).timerCharacters)
    }

    @Test func theRowButtonRunsTheLockScreensMarkRowIntent() throws {
        let d = LiveActivitySmallDisplay(F.working(rows: [F.chip(1, block: F.block3, name: "Block 3")]), calendar: Self.calendar)
        let intent = try #require(d.markRowIntent)
        #expect(intent.blockId == F.block3.uuidString)
        #expect(intent.row == 0)
        #expect(d.controlAccessibilityLabel == "Mark row 1 in block 3 shaped")
        #expect(LiveActivitySmallDisplay(F.onBreak(), calendar: Self.calendar).markRowIntent == nil)
    }

    @Test func onLunchTheControlIsBackToWork() {
        let snapshot = F.onBreak(.lunch)
        let d = LiveActivitySmallDisplay(snapshot, calendar: Self.calendar)
        #expect(d.control == .backToWork)
        #expect(d.controlLabels == ["Back to work", "Back"])
        #expect(d.controlGlyph == "play.fill")
        #expect(d.controlAccessibilityLabel == "Back to work")
        #expect(d.isOnBreak)
        #expect(d.glyph == "cup.and.saucer.fill")
        #expect(d.titles == ["Lunch · 4:12 worked", "Lunch"])
        #expect(d.detail == "Since \(Fmt.spokenTime(snapshot.breakStart!, Self.calendar))")
        // The timer counts the lunch, not the day.
        #expect(d.timerStart == snapshot.breakStart)
    }

    @Test func onABreakTheControlIsBackToWorkToo() {
        let d = LiveActivitySmallDisplay(F.onBreak(.onBreak, reason: "Parts run", minutes: 3), calendar: Self.calendar)
        #expect(d.control == .backToWork)
        #expect(d.glyph == "pause.fill")
        #expect(d.titles == ["Break · 4:12 worked", "Break"])
    }

    @Test func aShapedFieldOffersNoButtonAndSaysWhy() {
        let d = LiveActivitySmallDisplay(F.working(rows: [], shaped: 8_540, total: 8_540), calendar: Self.calendar)
        #expect(d.control == .none)
        #expect(d.controlLabels.isEmpty)
        #expect(d.markRowIntent == nil)
        // The lock screen's words.
        #expect(d.message == "Every row in North Field is shaped.")
        #expect(d.titles == ["Working"])
        #expect(d.detail == "212 trees")
    }

    // MARK: Going stale

    @Test func staleLineTwoAsksToOpenTimeCardLikeTheLockScreen() {
        // iOS marks the activity stale 10 minutes before it ends it at 8 hours.
        let d = LiveActivitySmallDisplay(F.working(), isStale: true, calendar: Self.calendar)
        #expect(d.detail == "Open Time Card")
        #expect(d.detailGlyph == "arrow.clockwise")
        #expect(d.detailAccessibilityLabel == "Open Time Card to keep this timer")
        // The row can still be marked meanwhile.
        #expect(d.control == .markRow(F.chip(13)))
        #expect(d.titles == ["Working · Block 2", "Block 2"])
        // On a break too.
        let lunch = LiveActivitySmallDisplay(F.onBreak(.lunch), isStale: true, calendar: Self.calendar)
        #expect(lunch.detail == "Open Time Card")
        #expect(lunch.control == .backToWork)
    }

    @Test func freshLineTwoIsJustWords() {
        let d = LiveActivitySmallDisplay(F.working(), calendar: Self.calendar)
        #expect(d.detailGlyph == nil)
        #expect(d.detailAccessibilityLabel == nil)
    }

    // MARK: VoiceOver

    @Test func theHeaderIsHeardWholeEvenWhenItsWordsDontFit() {
        // On a 40 mm card the title can give way to the timer; VoiceOver still hears it.
        #expect(LiveActivitySmallDisplay(F.working(), calendar: Self.calendar).headerAccessibilityLabel == "Working · Block 2")
        #expect(LiveActivitySmallDisplay(F.onBreak(.lunch), calendar: Self.calendar).headerAccessibilityLabel == "Lunch · 4:12 worked")
        #expect(LiveActivitySmallDisplay(F.working(rows: [], shaped: 8_540, total: 8_540), calendar: Self.calendar)
            .headerAccessibilityLabel == "Working")
    }

    // MARK: Fonts

    @Test func itUsesOnlySystemFonts() {
        // A custom font is reported to break Text(timerInterval:) on the watch. Only the
        // small family is checked here; the compact island views are the lock screen's.
        #expect(LiveActivitySmallView.fonts.timer == LiveActivitySmallView.SystemFont(.title3, design: .rounded, monospacedDigits: true))
        for font in LiveActivitySmallView.fonts.all.map(\.font) {
            for size in stride(from: 8.0, through: 48, by: 0.5) {
                #expect(font != LiveFonts.number(size))
            }
        }
        #expect(LiveActivitySmallView.fonts.timer.font == Font.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
    }

    // MARK: Fit

    /// The Smart Stack card on each watch: 40 mm is the smallest to design for.
    static let cards: [(name: String, size: CGSize)] = [
        ("40mm", CGSize(width: 152, height: 69.5)),
        ("42mm", CGSize(width: 176, height: 72.5)),
        ("46mm", CGSize(width: 194, height: 80.5)),
        ("ultra2", CGSize(width: 191, height: 81.5)),
        ("ultra3", CGSize(width: 198, height: 81.5)),
    ]

    static var phases: [(name: String, snapshot: LiveSnapshot)] {
        let now = Date()
        return [
            ("working", F.working(now: now)),
            ("working-long", F.working(rows: [F.chip(118, name: "North Slope 12")], trees: 1_204, worked: 10 * 3600 + 5 * 60,
                                       field: "Big Hollow Christmas Trees", label: "worked this shift", now: now)),
            ("field-done", F.working(rows: [], shaped: 8_540, total: 8_540, now: now)),
            ("lunch", F.onBreak(.lunch, now: now)),
            ("break-long", F.onBreak(.onBreak, minutes: 75, now: now)),
        ]
    }

    /// At the standard text size every line fits on every watch; at any size the card at least
    /// keeps the header and the button (the view drops line 2 first).
    @Test(arguments: [DynamicTypeSize.large, LiveActivitySmallView.largestText, .accessibility5])
    func everyPhaseFitsEveryCard(textSize: DynamicTypeSize) throws {
        for (name, snapshot) in Self.phases {
            for isStale in [false, true] {
                let display = LiveActivitySmallDisplay(snapshot, isStale: isStale)
                let colors = LiveColors.dark(onBreak: display.isOnBreak)
                let label = isStale ? "\(name) (stale)" : name
                for card in Self.cards {
                    func size(showsDetail: Bool) -> CGSize {
                        LiveActivityRenderTests.size(of: SmallCard(display: display, colors: colors, showsDetail: showsDetail)
                            .frame(width: card.size.width)
                            .environment(\.dynamicTypeSize, textSize))
                    }
                    let tightest = size(showsDetail: false)
                    #expect(tightest.height <= card.size.height.rounded(.up), "\(label) on \(card.name) is \(tightest.height) pt tall at \(textSize)")
                    #expect(tightest.width == card.size.width.rounded(.up), "\(label) on \(card.name) is \(tightest.width) pt wide")
                    if textSize == .large {
                        let full = size(showsDetail: true)
                        #expect(full.height <= card.size.height.rounded(.up), "\(label) with line 2 on \(card.name) is \(full.height) pt tall")
                    }
                }
            }
        }
    }

    @Test func theButtonIsAGloveSizedTarget() {
        // At least 36 pt tall, full width, and it takes any room the card has to spare.
        #expect(LiveActivitySmallView.buttonHeight >= 36)
        for snapshot in [F.working(), F.onBreak(.lunch)] {
            let button = LiveActivityRenderTests.size(of: SmallControl(display: LiveActivitySmallDisplay(snapshot), colors: .dark(onBreak: false))
                .frame(width: 152))
            #expect(button.height >= LiveActivitySmallView.buttonHeight)
            #expect(button.width == 152)
        }
    }

    @Test func rendersForAPersonToLookAt() throws {
        for (name, snapshot) in Self.phases {
            for card in Self.cards where card.name == "40mm" || card.name == "ultra2" {
                try LiveActivityRenderTests.save(SmallCardBackdrop(snapshot: snapshot, size: card.size), "small-\(name)-\(card.name)")
            }
        }
        try LiveActivityRenderTests.save(SmallCardBackdrop(snapshot: F.working(now: Date()), size: Self.cards[0].size)
            .environment(\.dynamicTypeSize, LiveActivitySmallView.largestText), "small-working-40mm-largest")
        for card in Self.cards where card.name == "40mm" || card.name == "ultra2" {
            try LiveActivityRenderTests.save(SmallCardBackdrop(snapshot: F.working(now: Date()), size: card.size, isStale: true),
                                             "small-working-stale-\(card.name)")
        }
    }
}

/// The card on black, about as the Smart Stack shows it.
private struct SmallCardBackdrop: View {
    var snapshot: LiveSnapshot
    var size: CGSize
    var isStale = false

    var body: some View {
        LiveActivitySmallView(state: snapshot, isStale: isStale)
            .frame(width: size.width, height: size.height)
            .background(LiveColors.dark(onBreak: snapshot.phase != .working).background,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(10)
            .background(.black)
            .environment(\.colorScheme, .dark)
    }
}
