import Foundation

// The phase 0 field log (docs/gis.md 10): what the watch senses each second of a Tree care
// workout, written while the person has the field log on, so the matching engine can be built
// and tuned against real shifts. It stays on the person's own devices: the watch writes it, the
// phone keeps it, and the person shares it to their Mac. Never to the farm.
//
// One file per workout, JSON Lines: a header line, then one line per second.
//
//     {"header":{"version":1,"startedAt":…,"shiftId":"…","device":"Watch7,5","timeZone":"…"}}
//     {"second":{"t":…,"phase":"running","fixes":[…],"heartRate":104,"motion":{…},"activity":"shaping"}}
//
// Version 2 added the activity the person tapped (`FieldActivity`) and its changes.

public enum FieldLog {
    public static let version = 2
    public static let fileExtension = "jsonl"
    /// The transfer's metadata says what the file is: `["kind": "fieldLog"]`.
    public static let metadataKey = "kind"
    public static let metadataValue = "fieldLog"
    public static var transferMetadata: [String: String] { [metadataKey: metadataValue] }

    /// "2026-11-02T1202Z-6F36AC4A.jsonl" (UTC): sortable by start, unique per workout.
    public static func fileName(startedAt: Date, id: UUID) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HHmm"
        return "\(f.string(from: startedAt))Z-\(id.uuidString.prefix(8)).\(fileExtension)"
    }
}

public struct FieldLogHeader: Codable, Hashable, Sendable {
    public var version: Int
    public var startedAt: Date
    /// The shift the workout records, when known at the start.
    public var shiftId: UUID?
    /// The watch model, "Watch7,5".
    public var device: String
    public var timeZone: String
    /// Device motion samples a second, when it runs.
    public var motionHz: Int?
    /// The wrist the watch is on ("left" or "right"), and so whether it's the hand with the shears.
    public var wrist: String?

    public init(version: Int = FieldLog.version, startedAt: Date, shiftId: UUID?, device: String, timeZone: String,
                motionHz: Int? = nil, wrist: String? = nil) {
        self.version = version
        self.startedAt = startedAt
        self.shiftId = shiftId
        self.device = device
        self.timeZone = timeZone
        self.motionHz = motionHz
        self.wrist = wrist
    }
}

/// One GPS fix as CoreLocation gave it, before any filtering: the analysis decides what to keep.
public struct FieldLogFix: Codable, Hashable, Sendable {
    public var t: Date
    public var lat: Double
    public var lon: Double
    /// Horizontal uncertainty in meters (negative: invalid).
    public var hAcc: Double
    public var alt: Double?
    public var vAcc: Double?
    /// Meters a second; nil when CoreLocation had none.
    public var speed: Double?
    /// Degrees from north; nil when CoreLocation had none.
    public var course: Double?

    public init(t: Date, lat: Double, lon: Double, hAcc: Double, alt: Double? = nil, vAcc: Double? = nil,
                speed: Double? = nil, course: Double? = nil) {
        self.t = t
        self.lat = lat
        self.lon = lon
        self.hAcc = hAcc
        self.alt = alt
        self.vAcc = vAcc
        self.speed = speed
        self.course = course
    }
}

/// One second of wrist motion, reduced on the watch (`MotionFeatures`). No raw samples are kept
/// beyond the 25-a-second magnitude.
public struct FieldLogMotion: Codable, Hashable, Sendable {
    /// Accelerometer samples that went into this second.
    public var samples: Int
    /// Root mean square of the magnitude around its mean, in g: how hard the wrist moved.
    public var energy: Double
    /// Sharp peaks above `MotionFeatures.peakThreshold`, at least `MotionFeatures.peakGap` apart:
    /// a first guess at strokes of the shears.
    public var peaks: Int
    /// Degrees the watch turned about the vertical this second, counterclockwise seen from above
    /// (negative: clockwise). A tree circled in a minute is about ±6 a second. Nil without a
    /// gyroscope.
    public var turn: Double?
    /// The acceleration's magnitude in g, averaged into 25 equal slices of the second, rounded to
    /// thousandths. Enough to try other stroke detectors later without collecting again.
    public var magnitude: [Double]

    public init(samples: Int, energy: Double, peaks: Int, turn: Double? = nil, magnitude: [Double]) {
        self.samples = samples
        self.energy = energy
        self.peaks = peaks
        self.turn = turn
        self.magnitude = magnitude
    }
}

public struct FieldLogSecond: Codable, Hashable, Sendable {
    /// The end of the second.
    public var t: Date
    /// The workout session: "running", "paused" (lunch or a break) or "stopped".
    public var phase: String
    /// Every fix that arrived during the second, oldest first (none while paused: GPS is off).
    public var fixes: [FieldLogFix]
    /// The latest heart rate, in beats a minute.
    public var heartRate: Double?
    public var motion: FieldLogMotion?
    /// What the person said they were doing this second (version 2).
    public var activity: FieldActivity?
    /// The changes of activity during the second, oldest first; nil when none.
    public var events: [FieldActivityEvent]?

    public init(t: Date, phase: String, fixes: [FieldLogFix] = [], heartRate: Double? = nil, motion: FieldLogMotion? = nil,
                activity: FieldActivity? = nil, events: [FieldActivityEvent]? = nil) {
        self.t = t
        self.phase = phase
        self.fixes = fixes
        self.heartRate = heartRate
        self.motion = motion
        self.activity = activity
        self.events = events
    }
}

/// One line of the file: a header or a second.
public struct FieldLogLine: Codable, Hashable, Sendable {
    public var header: FieldLogHeader?
    public var second: FieldLogSecond?

    public init(header: FieldLogHeader) {
        self.header = header
    }

    public init(second: FieldLogSecond) {
        self.second = second
    }
}

/// Appends lines to one log file, a few seconds at a time, so a crash loses little and the
/// watch doesn't write every second.
public final class FieldLogWriter {
    public let file: URL
    private let handle: FileHandle
    private var pending = Data()
    private let flushEvery: Int
    private var waiting = 0

    /// Creates the file (and its folder) and writes the header.
    public init(file: URL, header: FieldLogHeader, flushEvery: Int = 10) throws {
        self.file = file
        self.flushEvery = flushEvery
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        handle = try FileHandle(forWritingTo: file)
        try add(FieldLogLine(header: header))
        try flush()
    }

    public func append(_ second: FieldLogSecond) throws {
        try add(FieldLogLine(second: second))
        waiting += 1
        if waiting >= flushEvery { try flush() }
    }

    public func flush() throws {
        guard !pending.isEmpty else { return }
        try handle.write(contentsOf: pending)
        pending.removeAll(keepingCapacity: true)
        waiting = 0
    }

    /// Writes what's left and closes the file.
    public func close() throws {
        try flush()
        try handle.close()
    }

    private func add(_ line: FieldLogLine) throws {
        pending.append(try JSONCoding.encoder().encode(line))
        pending.append(0x0A)
    }
}

/// Reads a log back: the analysis on the Mac, and the tests.
public enum FieldLogReader {
    public struct Log: Equatable, Sendable {
        public var header: FieldLogHeader?
        public var seconds: [FieldLogSecond]
    }

    /// Lines that don't parse (a crash mid-write) are skipped.
    public static func read(_ data: Data) -> Log {
        var log = Log(header: nil, seconds: [])
        let decoder = JSONCoding.decoder()
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            guard let parsed = try? decoder.decode(FieldLogLine.self, from: Data(line)) else { continue }
            if let header = parsed.header { log.header = header }
            if let second = parsed.second { log.seconds.append(second) }
        }
        return log
    }
}
