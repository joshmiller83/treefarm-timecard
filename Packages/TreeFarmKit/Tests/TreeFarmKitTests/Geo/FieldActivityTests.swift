import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Field activity")
struct FieldActivityTests {
    let t0 = Date(timeIntervalSince1970: 1_792_400_000)
    let block = UUID(uuidString: "269A195F-F734-5615-AC9F-7332FC6AAC9F")!

    func chip(_ row: Int) -> RowChip {
        RowChip(blockId: block, row: row, title: "Row \(row + 1)", blockName: "Block 6")
    }

    func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    @Test func aLogStartsInPrep() {
        var tracker = FieldActivityTracker(at: t0)
        let event = tracker.begin(at: at(5))
        #expect(event == FieldActivityEvent(t: at(5), activity: .prep, by: .start))
        #expect(tracker.activity == .prep)
        #expect(tracker.since == at(5))
    }

    @Test func startRowShapesThatRowAndSaysWhichOne() {
        var tracker = FieldActivityTracker(at: t0)
        let event = tracker.startRow(chip(49), at: at(60))
        #expect(event == FieldActivityEvent(t: at(60), activity: .shaping, by: .button, blockId: block, blockName: "Block 6", row: 49))
        #expect(tracker.activity == .shaping)
        #expect(tracker.row == chip(49))
        // The same row again changes nothing; another row moves to it.
        #expect(tracker.startRow(chip(49), at: at(70)) == nil)
        #expect(tracker.startRow(chip(50), at: at(80))?.row == 50)
    }

    @Test func stopRowIsPrepAndRestIsItsOwn() {
        var tracker = FieldActivityTracker(at: t0)
        _ = tracker.startRow(chip(49), at: at(60))
        #expect(tracker.choose(.prep, at: at(300)) == FieldActivityEvent(t: at(300), activity: .prep, by: .button))
        #expect(tracker.row == nil)
        #expect(tracker.choose(.prep, at: at(310)) == nil)
        #expect(tracker.choose(.rest, at: at(320))?.activity == .rest)
        // Shaping only starts on a row.
        #expect(tracker.choose(.shaping, at: at(330)) == nil)
        #expect(tracker.activity == .rest)
    }

    @Test func aMarkWhileShapingEndsTheRow() {
        var tracker = FieldActivityTracker(at: t0)
        #expect(tracker.observe(shiftTrees: 20, at: at(1)) == nil)
        _ = tracker.startRow(chip(49), at: at(60))
        #expect(tracker.observe(shiftTrees: 20, at: at(120)) == nil)
        #expect(tracker.observe(shiftTrees: 30, at: at(300)) == FieldActivityEvent(t: at(300), activity: .prep, by: .mark))
        #expect(tracker.activity == .prep)
    }

    @Test func aMarkOutsideShapingChangesNothing() {
        var tracker = FieldActivityTracker(at: t0)
        _ = tracker.observe(shiftTrees: 20, at: at(1))
        _ = tracker.choose(.rest, at: at(2))
        #expect(tracker.observe(shiftTrees: 30, at: at(3)) == nil)
        #expect(tracker.activity == .rest)
        // Undo (fewer trees) and the first sight of a shift never end a row.
        _ = tracker.startRow(chip(49), at: at(4))
        #expect(tracker.observe(shiftTrees: 20, at: at(5)) == nil)
        #expect(tracker.observe(shiftTrees: nil, at: at(6)) == nil)
        #expect(tracker.observe(shiftTrees: 10, at: at(7)) == nil)
        #expect(tracker.activity == .shaping)
    }

    @Test func secondsCarryTheActivityAndOmitItWhenAbsent() throws {
        let event = FieldActivityEvent(t: at(1), activity: .shaping, by: .button, blockId: block, blockName: "Block 6", row: 49)
        let second = FieldLogSecond(t: at(1), phase: "running", activity: .shaping, events: [event])
        let data = try JSONCoding.encoder().encode(FieldLogLine(second: second))
        #expect(try JSONCoding.decoder().decode(FieldLogLine.self, from: data).second == second)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""activity":"shaping""#))
        #expect(json.contains(#""by":"button""#))

        let plain = try JSONCoding.encoder().encode(FieldLogLine(second: FieldLogSecond(t: at(2), phase: "running")))
        #expect(!String(decoding: plain, as: UTF8.self).contains("activity"))
        #expect(!String(decoding: plain, as: UTF8.self).contains("events"))
    }

    @Test func aVersion1SecondStillReads() throws {
        let line = Data(#"{"second":{"fixes":[],"phase":"running","t":1793713391161}}"#.utf8)
        let second = try #require(FieldLogReader.read(line).seconds.first)
        #expect(second.activity == nil)
        #expect(second.events == nil)
    }
}
