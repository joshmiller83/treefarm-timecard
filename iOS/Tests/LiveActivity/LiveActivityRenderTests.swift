import SwiftUI
import Testing
import TimeCardCore
import UIKit
@testable import TimeCard

/// Renders the lock screen and the Dynamic Island for each phase, in light and dark, and
/// checks they fit Apple's limits. The pictures land in iOS/build/LiveActivityRenders
/// (git-ignored) for a person to look at.
@MainActor
@Suite("Live Activity renders")
struct LiveActivityRenderTests {
    typealias F = LiveFixtures

    /// iOS cuts a lock-screen Live Activity off past this height.
    static let maxLockScreenHeight: CGFloat = 160
    /// The lock-screen card on an iPhone 17, and on the narrowest current iPhones.
    static let widths: [CGFloat] = [370, 343]

    /// Made with the real time, since the timers count from it as they draw.
    static var phases: [(name: String, snapshot: LiveSnapshot)] {
        let now = Date()
        return [
            ("working", F.working(now: now)),
            ("working-marked", F.working(lastAction: "Row 14 marked", canUndo: true, now: now)),
            ("working-next-block", F.working(rows: [F.chip(20), F.chip(1, block: F.block3, name: "Block 3"), F.chip(2, block: F.block3, name: "Block 3")],
                                             lastAction: "Row 19 marked", canUndo: true, now: now)),
            ("working-long-names", F.working(rows: [F.chip(118, name: "North Slope 12"), F.chip(119, name: "North Slope 12"), F.chip(120, name: "North Slope 12")],
                                             trees: 1_204, lastAction: "Marked trees 1 to 6", canUndo: true, worked: 10 * 3600 + 5 * 60,
                                             field: "Big Hollow Christmas Trees", label: "worked this shift", now: now)),
            ("field-done", F.working(rows: [], shaped: 8_540, total: 8_540, lastAction: "Row 61 marked", canUndo: true, now: now)),
            ("first-minutes", F.working(trees: 0, lastAction: "Clocked in", worked: 4 * 60 + 12, now: now)),
            ("lunch", F.onBreak(.lunch, now: now)),
            ("break-reason", F.onBreak(.onBreak, reason: "Parts run", minutes: 3, lastAction: "Break started", now: now)),
            ("break-no-undo", F.onBreak(.onBreak, minutes: 75, lastAction: "Undid row 14", canUndo: true, now: now)),
            ("working-refused", F.working(rows: [F.chip(15), F.chip(16), F.chip(17)], lastAction: "Row 14 was shaped by Sam Ortiz on Oct 16.",
                                          canUndo: true, now: now)),
            ("working-undone", F.working(lastAction: "Undid row 14", canUndo: true, now: now)),
            ("long-day", F.working(lastAction: "Row 14 marked", canUndo: true, worked: 9 * 3600 + 58 * 60, now: now)),
        ]
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func lockScreenFitsAndRenders(scheme: ColorScheme) throws {
        for (name, snapshot) in Self.phases {
            for width in Self.widths {
                let card = LiveLockScreenView(display: LiveActivityDisplay(snapshot))
                    .frame(width: width)
                    .environment(\.colorScheme, scheme)
                let size = Self.size(of: card)
                #expect(size.height <= Self.maxLockScreenHeight, "\(name) at \(width) pt is \(size.height) pt tall")
            }
            try Self.save(LockScreenBackdrop(snapshot: snapshot, scheme: scheme), "lock-\(name)-\(scheme == .dark ? "dark" : "light")")
            if scheme == .light {
                try Self.save(LockScreenBackdrop(snapshot: snapshot, scheme: scheme, width: 343), "narrow-\(name)")
            }
        }
    }

    @Test(arguments: [DynamicTypeSize.xxLarge, .accessibility5])
    func lockScreenFitsAtTheLargestTextItShows(size textSize: DynamicTypeSize) throws {
        // Text grows up to `largestText`; bigger settings stop there.
        for (name, snapshot) in Self.phases {
            for width in Self.widths {
                for scheme in [ColorScheme.light, .dark] {
                    let card = LiveLockScreenView(display: LiveActivityDisplay(snapshot))
                        .frame(width: width)
                        .environment(\.colorScheme, scheme)
                        .environment(\.dynamicTypeSize, textSize)
                    let size = Self.size(of: card)
                    #expect(size.height <= Self.maxLockScreenHeight, "\(name) at \(width) pt is \(size.height) pt tall at \(textSize)")
                }
            }
            if textSize == .xxLarge {
                try Self.save(LockScreenBackdrop(snapshot: snapshot, scheme: .light).environment(\.dynamicTypeSize, textSize), "xxl-\(name)")
                try Self.save(LockScreenBackdrop(snapshot: snapshot, scheme: .dark, width: 343).environment(\.dynamicTypeSize, textSize),
                              "xxl-narrow-\(name)-dark")
            }
        }
    }

    @Test func textGrowsWithThePersonsTextSize() throws {
        #expect(LiveLockScreenView.largestText >= .xxLarge)
        let snapshot = F.working(lastAction: "Row 14 marked", canUndo: true, now: Date())
        func png(_ size: DynamicTypeSize) -> Data? {
            let renderer = ImageRenderer(content: LiveLockScreenView(display: LiveActivityDisplay(snapshot), isStale: false)
                .frame(width: 370).environment(\.dynamicTypeSize, size))
            renderer.scale = 1
            return renderer.uiImage?.pngData()
        }
        let standard = try #require(png(.large))
        #expect(try #require(png(.xxLarge)) != standard)
        #expect(png(.small) != standard)
    }

    @Test func theBlockStaysInTheHeaderOnTheNarrowestCard() {
        // The header gives up the last action's words before the block's name: the shortest
        // line that keeps the block fits beside the pill on a 343 pt card. A long block name
        // at the largest text may shrink to 80% (the header's last resort), never vanish.
        let room: CGFloat = 343 - 28
        for (name, snapshot) in Self.phases {
            let display = LiveActivityDisplay(snapshot)
            var nameless = display
            nameless.blockTitle = ""
            nameless.place = ""
            for textSize in [DynamicTypeSize.large, LiveLockScreenView.largestText] {
                for scheme in [ColorScheme.light, .dark] {
                    let colors = LiveColors.lockScreen(scheme, onBreak: display.isOnBreak)
                    func width(_ d: LiveActivityDisplay, _ trailing: LiveHeaderLine.Trailing) -> CGFloat {
                        Self.size(of: HStack(spacing: 8) {
                            LiveStatusPill(title: d.statusTitle, colors: colors).fixedSize()
                            LiveHeaderLine(display: d, isStale: false, colors: colors, place: .short, trailing: trailing)
                        }
                        .fixedSize()
                        .environment(\.dynamicTypeSize, textSize)).width
                    }
                    if name == "working-long-names" && textSize > .large {
                        // The last resort: just [Undo], and the name at 80% or more.
                        let full = width(display, .minimal), withoutName = width(nameless, .minimal)
                        let smallest = withoutName + 0.8 * (full - withoutName)
                        #expect(smallest <= room, "\(name) needs \(smallest) pt at \(textSize)")
                    } else {
                        let full = width(display, .short)
                        #expect(full <= room, "\(name) needs \(full) pt at \(textSize)")
                    }
                }
            }
        }
    }

    @Test func undoIsAGloveSizedTarget() {
        let colors = LiveColors.light(onBreak: false)
        // Working: the whole "✓ Row 14 marked  Undo" is one button.
        let confirmation = Self.size(of: LiveLastAction(last: .init(text: "Row 14 marked", canUndo: true), colors: colors).fixedSize())
        #expect(confirmation.width >= 150)
        #expect(confirmation.height >= LiveHeader.height)
        // Short, on a tight header: still wider than it is tall.
        let short = Self.size(of: LiveLastAction(last: .init(text: "Row 14 marked", canUndo: true), colors: colors, showsText: false).fixedSize())
        #expect(short.width >= 80)
        // On a break, Undo is a full-height button beside Back to work.
        let row = LiveButtonRow(display: LiveActivityDisplay(F.onBreak(.onBreak, lastAction: "Break started", canUndo: true)), colors: colors)
            .frame(width: 342)
        #expect(Self.size(of: row).height == LiveLockScreenView.buttonHeight)
    }

    /// After a row tap the lock screen's Undo is a fifth tile beside the rows and Break, about
    /// 64 × 54 pt, not a 26 pt capsule right above them.
    @Test func lockScreenUndoIsATileInTheButtonRow() {
        let colors = LiveColors.light(onBreak: false)
        let display = LiveActivityDisplay(F.working(lastAction: "Row 14 marked", canUndo: true, now: Date()))
        let row = LiveButtonRow(display: display, colors: colors, undoInRow: true).frame(width: 342)
        #expect(Self.size(of: row).height == LiveLockScreenView.buttonHeight)
        let tile = (342 - 4 * 6) / 5.0
        #expect(tile >= 60, "five tiles of about 64 pt")
        // The header shows the confirmation as words only: one Undo, the big one.
        let header = Self.size(of: LiveLastAction(last: .init(text: "Row 14 marked", canUndo: true), colors: colors, offersUndo: false).fixedSize())
        #expect(header.width < 150)
    }

    @Test func staleActivitySaysToOpenTheApp() throws {
        try Self.save(LockScreenBackdrop(snapshot: F.working(lastAction: "Row 14 marked", canUndo: true, now: Date()), scheme: .dark, isStale: true), "lock-stale-dark")
        try Self.save(LockScreenBackdrop(snapshot: F.working(lastAction: "Row 14 marked", canUndo: true, now: Date()), scheme: .light, isStale: true, width: 343),
                      "narrow-stale")
    }

    @Test func dynamicIslandRenders() throws {
        let now = Date()
        for (name, snapshot) in [("working", F.working(lastAction: "Row 14 marked", canUndo: true, now: now)),
                                 ("first-minutes", F.working(trees: 0, worked: 4 * 60 + 12, now: now)),
                                 ("lunch", F.onBreak(.lunch, now: now)),
                                 ("break-reason", F.onBreak(.onBreak, reason: "Parts run", minutes: 3, lastAction: "Break started", now: now)),
                                 ("refused", F.working(lastAction: "Row 14 was shaped by Sam Ortiz on Oct 16.", canUndo: true, now: now))] {
            let display = LiveActivityDisplay(snapshot)
            for textSize in [DynamicTypeSize.large, .accessibility5] {
                let expanded = Self.size(of: ExpandedIsland(display: display).environment(\.dynamicTypeSize, textSize))
                #expect(expanded.height <= ExpandedIsland.maxHeight, "\(name) expanded is \(expanded.height) pt tall")
                #expect(expanded.width == ExpandedIsland.width)
            }
            try Self.save(IslandBackdrop(display: display, now: now), "island-\(name)")
        }
        try Self.save(IslandBackdrop(display: LiveActivityDisplay(F.working(lastAction: "Row 14 marked", canUndo: true, now: now)), now: now)
            .environment(\.dynamicTypeSize, .accessibility5), "island-working-ax5")
    }

    // MARK: Rendering

    static func size(of view: some View) -> CGSize {
        let renderer = ImageRenderer(content: view.fixedSize(horizontal: false, vertical: true))
        renderer.scale = 1
        return renderer.uiImage?.size ?? .zero
    }

    static var outputFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/LiveActivityRenders")
    }

    static func save(_ view: some View, _ name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try #require(renderer.uiImage, "\(name) didn't render")
        let data = try #require(image.pngData())
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        try data.write(to: outputFolder.appendingPathComponent("\(name).png"))
    }
}

/// The card on a lock-screen-ish wallpaper, about as iOS shows it.
private struct LockScreenBackdrop: View {
    var snapshot: LiveSnapshot
    var scheme: ColorScheme
    var isStale = false
    var width: CGFloat = 370

    var body: some View {
        let colors = LiveColors.lockScreen(scheme, onBreak: snapshot.phase != .working)
        LiveLockScreenView(display: LiveActivityDisplay(snapshot), isStale: isStale)
            .frame(width: width)
            .background(colors.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .top) {
                // Apple's 160 pt line, to see how much room is left.
                Rectangle().fill(.red.opacity(0.5)).frame(height: 1).offset(y: 160)
            }
            .padding(16)
            .background(
                LinearGradient(colors: scheme == .dark ? [Color(white: 0.05), Color(red: 0.1, green: 0.14, blue: 0.22)]
                                                       : [Color(red: 0.62, green: 0.74, blue: 0.86), Color(red: 0.86, green: 0.8, blue: 0.7)],
                               startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, scheme)
    }
}

/// The expanded island at its real size on an iPhone 17: 371 pt wide, at most 160 pt tall.
/// Leading and trailing sit either side of the camera, the bottom below.
private struct ExpandedIsland: View {
    static let width: CGFloat = 371
    static let maxHeight: CGFloat = 160
    var display: LiveActivityDisplay

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                LiveIslandLeading(display: display)
                Spacer(minLength: 120) // the camera
                LiveIslandTrailing(display: display)
            }
            .frame(height: 52)
            LiveIslandBottom(display: display)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// Expanded, compact and minimal islands on black, roughly at their real sizes.
private struct IslandBackdrop: View {
    var display: LiveActivityDisplay
    var now: Date

    var body: some View {
        VStack(spacing: 18) {
            ExpandedIsland(display: display)
                .overlay(alignment: .top) {
                    // The 160 pt limit.
                    Rectangle().fill(.red.opacity(0.6)).frame(height: 1).offset(y: ExpandedIsland.maxHeight)
                }
                .frame(height: ExpandedIsland.maxHeight, alignment: .top)

            HStack(spacing: 20) {
                // Compact: leading, the camera, trailing.
                HStack(spacing: 0) {
                    LiveIslandCompactLeading(display: display)
                    Spacer(minLength: 120)
                    LiveIslandCompactTrailing(display: display)
                }
                .padding(.horizontal, 14)
                .frame(height: 37)
                .background(.black, in: Capsule())
                // Minimal, drawn still for the picture.
                LiveIslandMinimal(display: display, still: now)
                    .frame(width: 37, height: 37)
                    .background(.black, in: Circle())
            }
        }
        .padding(20)
        .background(Color(white: 0.92))
        .environment(\.colorScheme, .dark)
    }
}
