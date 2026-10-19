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

    @Test func lockScreenStaysWithinTheLimitAtTheLargestTextSize() throws {
        for (name, snapshot) in Self.phases {
            let card = LiveLockScreenView(display: LiveActivityDisplay(snapshot))
                .frame(width: 343)
                .environment(\.dynamicTypeSize, .accessibility5)
            let size = Self.size(of: card)
            #expect(size.height <= Self.maxLockScreenHeight, "\(name) is \(size.height) pt tall at AX5")
        }
        try Self.save(LockScreenBackdrop(snapshot: F.working(lastAction: "Row 14 marked", canUndo: true, now: Date()), scheme: .light)
            .environment(\.dynamicTypeSize, .accessibility5), "lock-working-marked-ax5")
    }

    @Test func staleActivitySaysToOpenTheApp() throws {
        try Self.save(LockScreenBackdrop(snapshot: F.working(lastAction: "Row 14 marked", canUndo: true, now: Date()), scheme: .dark, isStale: true), "lock-stale-dark")
    }

    @Test func dynamicIslandRenders() throws {
        let now = Date()
        for (name, snapshot) in [("working", F.working(lastAction: "Row 14 marked", canUndo: true, now: now)),
                                 ("first-minutes", F.working(trees: 0, worked: 4 * 60 + 12, now: now)),
                                 ("lunch", F.onBreak(.lunch, now: now)),
                                 ("break-reason", F.onBreak(.onBreak, reason: "Parts run", minutes: 3, lastAction: "Break started", now: now))] {
            let display = LiveActivityDisplay(snapshot)
            try Self.save(IslandBackdrop(display: display), "island-\(name)")
        }
        try Self.save(IslandBackdrop(display: LiveActivityDisplay(F.working(lastAction: "Row 14 marked", canUndo: true, now: now)))
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

/// Expanded, compact and minimal islands on black, roughly at their real sizes.
private struct IslandBackdrop: View {
    var display: LiveActivityDisplay

    var body: some View {
        VStack(spacing: 18) {
            // Expanded: leading and trailing beside the camera, bottom below.
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    LiveIslandLeading(display: display)
                    Spacer(minLength: 90)
                    LiveIslandTrailing(display: display)
                }
                .frame(height: 52)
                LiveIslandBottom(display: display)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(width: 371)
            .background(.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))

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
                // Minimal.
                LiveIslandMinimal(display: display)
                    .frame(width: 37, height: 37)
                    .background(.black, in: Circle())
            }
        }
        .padding(20)
        .background(Color(white: 0.92))
        .environment(\.colorScheme, .dark)
    }
}
