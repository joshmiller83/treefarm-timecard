import Foundation
import SwiftUI
import Testing
import TimeCardCore
import UIKit
@testable import TimeCard

/// The card under Siri's status answers: its numbers, and how it draws in light, dark and
/// at large text sizes. Set SNIPPET_DIR (TEST_RUNNER_SNIPPET_DIR for xcodebuild) to save
/// the drawings as PNGs for a look.
@MainActor
@Suite("Status card")
struct DaySnippetTests {
    static let sample = DayCard(
        topic: .trees, phase: .working, fieldName: "North Field", workedToday: 6 * 3600 + 40 * 60, workedWeek: 31 * 3600 + 12 * 60,
        treesToday: 212, treesPerHour: 31.8, seasonTreesPerHour: 29.4, here: .init(block: "Block 2", row: 15),
        next: [.init(block: "Block 2", row: 16), .init(block: "Block 2", row: 17)], fieldShaped: 1204, fieldTotal: 8540,
        pay: nil, payHidden: false)

    @Test func theAskedNumberComesFirst() {
        let trees = SnippetStat.stats(for: Self.sample)
        #expect(trees.map(\.value) == ["212", "32", "6:40"])
        #expect(trees.map(\.focus) == [true, false, false])
        #expect(trees[0].spoken == "212 trees today")

        let hours = SnippetStat.stats(for: Self.sample.with(topic: .hours))
        #expect(hours.map(\.value) == ["6:40", "31:12", "212"])
        #expect(hours[0].spoken == "6 hours 40 minutes worked today")

        let pace = SnippetStat.stats(for: Self.sample.with(topic: .pace))
        #expect(pace.map(\.label) == ["trees an hour", "season pace", "trees today"])
        #expect(pace.map(\.value) == ["32", "29", "212"])
    }

    @Test func payShowsOnlyWhenItMay() {
        var card = Self.sample.with(topic: .pay)
        #expect(SnippetStat.stats(for: card).isEmpty)
        card.pay = .init(todayCents: 9450, weekCents: 41_000)
        #expect(SnippetStat.stats(for: card).map(\.value) == ["$94.50", "$410.00"])
    }

    @Test func theCardIsBuiltFromTheFarm() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        #expect(await voice.status(.trees).card?.phase == .off)
        _ = await voice.clockIn(field: nil)
        _ = await voice.nextRow()
        let card = try #require(await voice.status(.trees).card)
        #expect(card.phase == .working)
        #expect(card.fieldName == "North Field")
        #expect(card.treesToday == 12)
        #expect(card.here == .init(block: "Block 1", row: 6))
        #expect(card.next == [.init(block: "Block 1", row: 7), .init(block: "Block 1", row: 8)])
        #expect(card.fieldShaped == 60)
        #expect(card.fieldTotal == 4 * 20 * 12)
        _ = await voice.takeBreak(.lunch, reason: nil, askReason: Speaker(nil).ask)
        #expect(await voice.status(.hours).card?.phase == .lunch)
    }

    @Test(arguments: [StatusTopic.summary, .hours, .trees, .whereAmI, .pace, .pay])
    func itDrawsInEveryLook(_ topic: StatusTopic) throws {
        var card = Self.sample.with(topic: topic)
        if topic == .pay { card.payHidden = true }
        let looks: [(String, ColorScheme, DynamicTypeSize)] = [("light", .light, .large), ("dark", .dark, .large), ("large-type", .light, .accessibility3)]
        for (name, scheme, size) in looks {
            let image = try #require(render(card, scheme: scheme, size: size), "\(topic) \(name)")
            #expect(image.size.width == 370)
            #expect(image.size.height > 100 && image.size.height < (size.isAccessibilitySize ? 900 : 330), "\(topic) \(name): \(image.size.height)")
            save(image, "\(topic.rawValue)-\(name)")
        }
        if topic == .pay {
            card.payHidden = false
            card.pay = .init(todayCents: 9450, weekCents: 41_000)
            save(try #require(render(card, scheme: .light, size: .large)), "pay-shown-light")
        }
    }

    private func render(_ card: DayCard, scheme: ColorScheme, size: DynamicTypeSize) -> UIImage? {
        let view = DaySnippetView(card: card)
            .frame(width: 370)
            .background(scheme == .dark ? Color(white: 0.11) : Color(white: 0.97))
            .environment(\.colorScheme, scheme)
            .dynamicTypeSize(size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    private func save(_ image: UIImage, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNIPPET_DIR"], let data = image.pngData() else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
