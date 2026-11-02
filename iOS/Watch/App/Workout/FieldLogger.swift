import CoreLocation
import CoreMotion
import Foundation
import TreeFarmKit

/// The phase 0 field log (docs/gis.md 10): while a Tree care workout runs with the field log on,
/// one line a second of what the watch senses. The fixes are the route's own (one GPS), the
/// heart rate is the workout's, and the wrist motion comes from the batched accelerometer that
/// workout apps get, reduced on the spot by `MotionFeatures`.
///
/// The file stays on the watch for `keepDays` and goes to the phone when the workout ends.
@MainActor
final class FieldLogger {
    static var directory: URL { URL.applicationSupportDirectory.appending(path: "FieldLogs") }
    static let keepDays = 7

    private var writer: FieldLogWriter?
    private var fixes: [FieldLogFix] = []
    private let motion = MotionBuffer()
    private var tick: Task<Void, Never>?
    private var motionTask: Task<Void, Never>?
    private var heartRate: @MainActor () -> Double? = { nil }
    private var phase: @MainActor () -> String = { WorkoutLocal.Phase.running.rawValue }

    var isRunning: Bool { writer != nil }

    /// Opens a new log. `heartRate` and `phase` are read once a second.
    func start(shiftId: UUID?, at date: Date, timeZone: String, heartRate: @escaping @MainActor () -> Double?,
               phase: @escaping @MainActor () -> String) {
        guard writer == nil else { return }
        Self.prune()
        let file = Self.directory.appending(path: FieldLog.fileName(startedAt: date, id: UUID()))
        let header = FieldLogHeader(startedAt: date, shiftId: shiftId, device: Self.hardwareModel, timeZone: timeZone)
        guard let writer = try? FieldLogWriter(file: file, header: header) else { return }
        self.writer = writer
        self.heartRate = heartRate
        self.phase = phase
        fixes = []
        _ = motion.take()
        motionTask = Self.readMotion(into: motion)
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.writeSecond()
            }
        }
    }

    /// Fixes as CoreLocation gave them (the route recorder passes every one on).
    func add(_ locations: [CLLocation]) {
        guard writer != nil else { return }
        fixes += locations.map {
            FieldLogFix(t: $0.timestamp, lat: $0.coordinate.latitude, lon: $0.coordinate.longitude, hAcc: $0.horizontalAccuracy,
                        alt: $0.verticalAccuracy >= 0 ? $0.altitude : nil, vAcc: $0.verticalAccuracy >= 0 ? $0.verticalAccuracy : nil,
                        speed: $0.speed >= 0 ? $0.speed : nil, course: $0.course >= 0 ? $0.course : nil)
        }
    }

    /// Writes the last second, closes the file and returns it for the phone.
    func finish() -> URL? {
        guard let writer else { return nil }
        writeSecond()
        stop()
        try? writer.close()
        self.writer = nil
        return writer.file
    }

    /// A workout that was discarded (under two minutes) leaves no log.
    func discard() {
        guard let file = finish() else { return }
        try? FileManager.default.removeItem(at: file)
    }

    private func writeSecond() {
        guard let writer else { return }
        let second = FieldLogSecond(t: Date(), phase: phase(), fixes: fixes, heartRate: heartRate(),
                                    motion: MotionFeatures.second(motion.take()))
        fixes = []
        try? writer.append(second)
    }

    private func stop() {
        tick?.cancel()
        tick = nil
        motionTask?.cancel()
        motionTask = nil
    }

    /// The batched accelerometer, read off the main actor; each batch (about a second) goes into
    /// the buffer as plain samples. It needs the running workout session, and asks for Motion &
    /// Fitness the first time. Denied or unsupported, the log just has no motion.
    private nonisolated static func readMotion(into buffer: MotionBuffer) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            guard CMBatchedSensorManager.isAccelerometerSupported else { return }
            let manager = CMBatchedSensorManager()
            do {
                for try await batch in manager.accelerometerUpdates() {
                    if Task.isCancelled { break }
                    buffer.add(batch.map {
                        MotionSample(t: $0.timestamp, x: $0.acceleration.x, y: $0.acceleration.y, z: $0.acceleration.z)
                    })
                }
            } catch {}
            manager.stopAccelerometerUpdates()
        }
    }

    /// Logs older than `keepDays` go; the phone has its own copy.
    private static func prune() {
        let fm = FileManager.default
        let limit = Date().addingTimeInterval(-Double(keepDays) * 86_400)
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for file in files {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            if created < limit { try? fm.removeItem(at: file) }
        }
    }

    /// "Watch7,5".
    private static var hardwareModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

/// Samples handed from the motion task to the main actor, a second at a time.
final class MotionBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [MotionSample] = []

    func add(_ new: [MotionSample]) {
        lock.withLock { samples += new }
    }

    func take() -> [MotionSample] {
        lock.withLock {
            defer { samples = [] }
            return samples
        }
    }
}
