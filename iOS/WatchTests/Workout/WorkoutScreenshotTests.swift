import Foundation
import ImageIO
import SwiftUI
import Testing
import TreeFarmKit
import UniformTypeIdentifiers
@testable import TimeCardWatch

/// Renders the workout's screens on every watch size (docs/watch.md 7.3), at the default text
/// size, at accessibility XL and in Always On, as PNGs to read and judge. They go to
/// `$WORKOUT_SNAPSHOTS` (pass `TEST_RUNNER_WORKOUT_SNAPSHOTS=<dir>` to xcodebuild), else to the
/// test host's temporary folder.
@MainActor
@Suite("Workout screenshots", .serialized)
struct WorkoutScreenshotTests {
    struct Screen {
        let name: String
        let size: CGSize
        let workout: WorkoutSize
    }

    static let screens = [
        Screen(name: "40mm", size: CGSize(width: 162, height: 197), workout: .small),
        Screen(name: "42mm", size: CGSize(width: 187, height: 223), workout: .small),
        Screen(name: "46mm", size: CGSize(width: 208, height: 248), workout: .medium),
        Screen(name: "49mm", size: CGSize(width: 205, height: 251), workout: .large),
    ]

    let start = Date(timeIntervalSince1970: 1_792_400_000)

    var closed: ClosedShift {
        ClosedShift(shiftId: UUID(), start: start, end: start.addingTimeInterval(8 * 3600 + 720), worked: 8 * 3600 + 12 * 60, trees: 412)
    }

    var summary: WorkoutSummary {
        WorkoutSummary(shiftId: closed.shiftId, start: start, end: closed.end, activeDuration: 7 * 3600 + 41 * 60,
                       activeKcal: 1_120, avgHeartRate: 104, maxHeartRate: 151)
    }

    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["WORKOUT_SNAPSHOTS"] { return URL(fileURLWithPath: path) }
        return FileManager.default.temporaryDirectory.appending(path: "WorkoutSnapshots")
    }

    @Test func theShiftSummary() throws {
        for screen in Self.screens {
            try shoot("summary", screen) {
                WorkoutSummaryView(closed: closed, summary: summary, waitingForPhone: false) {}
            }
        }
        let small = Self.screens[0]
        try shoot("summary-waiting", small) {
            WorkoutSummaryView(closed: closed, summary: summary, waitingForPhone: true) {}
        }
        try shoot("summary-ax", small, type: .accessibility3) {
            WorkoutSummaryView(closed: closed, summary: summary, waitingForPhone: false) {}
        }
        try shoot("summary-ax", Self.screens[3], type: .accessibility3) {
            WorkoutSummaryView(closed: closed, summary: summary, waitingForPhone: false) {}
        }
        try shoot("summary-aod", Self.screens[2], dimmed: true) {
            WorkoutSummaryView(closed: closed, summary: summary, waitingForPhone: false) {}
        }
    }

    @Test func theHealthCard() throws {
        for screen in Self.screens {
            try shoot("onboarding", screen) { HealthOnboardingCard(step: .health) {} }
        }
        try shoot("onboarding-reminder", Self.screens[2]) { HealthOnboardingCard(step: .reminder) {} }
        try shoot("onboarding-ax", Self.screens[0], type: .accessibility3) { HealthOnboardingCard(step: .health) {} }
    }

    @Test func theBannersAndTheTodayLines() throws {
        let recording = WorkoutLive(heartRate: 104, kcal: 612, recording: .recording)
        for screen in Self.screens {
            try shoot("banners", screen) {
                VStack(alignment: .leading, spacing: 8) {
                    ClockOutWaitingBanner()
                    WorkoutStatusLine(live: recording)
                    WorkoutHeartLine(live: recording)
                    Spacer(minLength: 0)
                }
            }
            try shoot("recording-stopped", screen) {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    RecordingStoppedBanner {}
                }
            }
        }
        try shoot("today-lines", Self.screens[2]) {
            VStack(alignment: .leading, spacing: 10) {
                WorkoutStatusLine(live: WorkoutLive(recording: .notAuthorized))
                WorkoutStatusLine(live: WorkoutLive(recording: .off))
                WorkoutStatusLine(live: WorkoutLive(recording: .paused))
                Spacer(minLength: 0)
            }
        }
        try shoot("banners-aod", Self.screens[3], dimmed: true) {
            VStack(spacing: 8) {
                ClockOutWaitingBanner()
                Spacer(minLength: 0)
                RecordingStoppedBanner {}
            }
        }
    }

    // MARK: Rendering

    private func shoot(_ name: String, _ screen: Screen, dimmed: Bool = false, type: DynamicTypeSize = .large,
                       @ViewBuilder _ content: () -> some View) throws {
        let view = WatchFace(size: screen.size) { content() }
            .workoutSize(screen.workout)
            .environment(\.isLuminanceReduced, dimmed)
            .environment(\.dynamicTypeSize, type)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(screen.size)
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(screen.size.width * 2) && image.height == Int(screen.size.height * 2))

        let directory = Self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name)-\(screen.name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

/// A watch screen around the content: black, the time at the top right, the system's margins.
private struct WatchFace<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Spacer()
                Text("10:42").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(height: 22)
            .padding(.horizontal, 14)
            content
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 4)
        .frame(width: size.width, height: size.height)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: size.width * 0.2, style: .continuous))
    }
}
