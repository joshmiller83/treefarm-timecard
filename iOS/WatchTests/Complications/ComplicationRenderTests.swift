import Foundation
import ImageIO
import SwiftUI
import Testing
import TreeFarmKit
import UniformTypeIdentifiers
@testable import TimeCardWatch

/// Renders each complication family in each phase at the smallest and largest watch sizes
/// (docs/watch.md 4.3 and 7.3), as PNGs to read and judge. Full color on black, as on a
/// full-color face; the corner's curved label and a tinted face only draw on a real face.
/// They go to `$COMPLICATION_SNAPSHOTS` (pass `TEST_RUNNER_COMPLICATION_SNAPSHOTS=<dir>` to
/// xcodebuild), else to the test host's temporary folder.
@MainActor
@Suite("Complication renders", .serialized)
struct ComplicationRenderTests {
    typealias Contents = WatchStateFile.Contents

    struct Watch {
        let name: String
        let circular: CGFloat
        let rectangular: CGSize
        let inlineWidth: CGFloat
    }

    /// The accessory slots, in points.
    static let watches = [
        Watch(name: "40mm", circular: 42, rectangular: CGSize(width: 150, height: 47), inlineWidth: 140),
        Watch(name: "49mm", circular: 50, rectangular: CGSize(width: 184, height: 59), inlineWidth: 170),
    ]

    let now = Date()

    // MARK: States, relative to now so the timers read like a shift

    func chips(_ rows: ClosedRange<Int>) -> [RowChip] {
        let block = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        return rows.map { RowChip(blockId: block, row: $0 - 1, title: "Row \($0)", blockName: "Block 2", openTrees: 10) }
    }

    func state(_ phase: LiveSnapshot.Phase?, todayWorked: TimeInterval = 0, signedIn: Bool = true) -> WatchState {
        let worked: TimeInterval = 3 * 3600 + 41 * 60 + 7
        let snapshot = phase.map { phase in
            LiveSnapshot(phase: phase, timerStart: now.addingTimeInterval(-worked), workedSoFar: worked, workedLabel: "worked today",
                         breakStart: phase == .working ? nil : now.addingTimeInterval(-(12 * 60 + 40)), breakReason: "",
                         fieldName: "North", nextRows: Array(chips(14...16)), shiftTrees: 38, fieldShaped: 120, fieldTotal: 400,
                         lastAction: nil, canUndo: false)
        }
        return WatchState(signedIn: signedIn, farmName: "Dull’s Tree Farm", fieldName: "North", snapshot: snapshot,
                          nextRows: chips(14...30), todayWorked: phase == nil ? todayWorked : worked, todayTrees: 212,
                          canUndo: false, recordWorkouts: true, updatedAt: now, shiftId: phase == nil ? nil : UUID(),
                          shiftStart: phase == nil ? nil : now.addingTimeInterval(-worked),
                          farmTimeZone: TimeZone.current.identifier)
    }

    var phases: [(String, Contents)] {
        [
            ("working", Contents(displayed: state(.working))),
            ("lunch", Contents(displayed: state(.lunch))),
            ("break", Contents(displayed: state(.onBreak))),
            ("off-clock-in", Contents(displayed: state(nil))),
            ("off-clock-hours", Contents(displayed: state(nil, todayWorked: 6.5 * 3600))),
            ("taps-waiting", Contents(displayed: state(.working), waitingCount: 2)),
            ("clock-out-waiting", Contents(displayed: state(nil, todayWorked: 3.7 * 3600), waitingCount: 1, clockOutWaiting: true)),
            ("signed-out", Contents(displayed: state(nil, signedIn: false))),
            ("no-data", Contents(displayed: nil)),
        ]
    }

    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["COMPLICATION_SNAPSHOTS"] { return URL(fileURLWithPath: path) }
        return FileManager.default.temporaryDirectory.appending(path: "ComplicationSnapshots")
    }

    // MARK: Renders

    @Test func everyFamilyInEveryPhase() throws {
        for watch in Self.watches {
            for (name, contents) in phases {
                let face = ComplicationFace(contents, at: now)
                try shoot("circular-\(name)-\(watch.name)", CGSize(width: watch.circular, height: watch.circular)) {
                    CircularComplication(face: face)
                }
                try shoot("rectangular-\(name)-\(watch.name)", watch.rectangular) {
                    RectangularComplication(face: face)
                }
                try shoot("inline-\(name)-\(watch.name)", CGSize(width: watch.inlineWidth, height: 20)) {
                    InlineComplication(face: face).font(.system(size: 13, weight: .medium)).lineLimit(1)
                }
                try shoot("corner-\(name)-\(watch.name)", CGSize(width: 32, height: 32)) {
                    CornerComplication(face: face)
                }
            }
        }
    }

    /// The rectangular family is also the Smart Stack widget, on its phase-tinted card.
    @Test func theSmartStackCard() throws {
        for (name, contents) in phases {
            let face = ComplicationFace(contents, at: now)
            try shoot("smart-stack-\(name)", CGSize(width: 184, height: 72)) {
                RectangularComplication(face: face)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ComplicationStyle.background(face.tone), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func shoot(_ name: String, _ size: CGSize, @ViewBuilder _ content: () -> some View) throws {
        let view = content()
            .frame(width: size.width, height: size.height)
            .background(.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(size)
        let image = try #require(renderer.cgImage, "\(name) didn't render")
        #expect(image.width == Int(size.width * 3) && image.height == Int(size.height * 3))

        let directory = Self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
