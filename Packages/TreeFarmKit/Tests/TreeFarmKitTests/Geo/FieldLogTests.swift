import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Field log")
struct FieldLogTests {
    let t0 = Date(timeIntervalSince1970: 1_792_400_000)
    let directory = FileManager.default.temporaryDirectory.appending(path: "FieldLogTests-\(UUID().uuidString)")

    var header: FieldLogHeader {
        FieldLogHeader(startedAt: t0, shiftId: UUID(uuidString: "6F36AC4A-2482-43AB-93EB-D015C1503B1B"), device: "Watch7,5",
                       timeZone: "America/Indiana/Indianapolis", motionHz: 200, wrist: "left")
    }

    func second(_ i: Int, phase: String = "running") -> FieldLogSecond {
        FieldLogSecond(t: t0.addingTimeInterval(Double(i)), phase: phase,
                       fixes: [FieldLogFix(t: t0.addingTimeInterval(Double(i) - 0.5), lat: 40.1667, lon: -86.5016, hAcc: 3.2,
                                           alt: 262, vAcc: 4, speed: 0.6, course: 181)],
                       heartRate: 104, motion: FieldLogMotion(samples: 200, energy: 0.21, peaks: 2, turn: -6.1, magnitude: Array(repeating: 1, count: 25)))
    }

    @Test func aLogReadsBackLineForLine() throws {
        let file = directory.appending(path: FieldLog.fileName(startedAt: t0, id: UUID()))
        let writer = try FieldLogWriter(file: file, header: header, flushEvery: 3)
        for i in 1...7 { try writer.append(second(i)) }
        try writer.append(second(8, phase: "paused"))
        try writer.close()

        let log = FieldLogReader.read(try Data(contentsOf: file))
        #expect(log.header == header)
        #expect(log.seconds == (1...7).map { second($0) } + [second(8, phase: "paused")])
    }

    @Test func secondsWrittenBeforeACrashAreThereUpToTheLastFlush() throws {
        let file = directory.appending(path: "crash.jsonl")
        let writer = try FieldLogWriter(file: file, header: header, flushEvery: 3)
        for i in 1...4 { try writer.append(second(i)) }
        // No close: the fourth second is still waiting.
        let log = FieldLogReader.read(try Data(contentsOf: file))
        #expect(log.header != nil)
        #expect(log.seconds.count == 3)
    }

    @Test func aTornLastLineIsSkipped() throws {
        var data = try JSONCoding.encoder().encode(FieldLogLine(header: header))
        data.append(0x0A)
        data.append(try JSONCoding.encoder().encode(FieldLogLine(second: second(1))))
        data.append(0x0A)
        data.append(Data(#"{"second":{"t":17924"#.utf8))
        let log = FieldLogReader.read(data)
        #expect(log.seconds == [second(1)])
    }

    @Test func fileNamesSortByStartInUTC() {
        let id = UUID(uuidString: "6F36AC4A-2482-43AB-93EB-D015C1503B1B")!
        // 1_792_400_000 is 2026-10-19 08:53:20 UTC.
        #expect(FieldLog.fileName(startedAt: t0, id: id) == "2026-10-19T0853Z-6F36AC4A.jsonl")
        #expect(FieldLog.transferMetadata == ["kind": "fieldLog"])
    }
}
