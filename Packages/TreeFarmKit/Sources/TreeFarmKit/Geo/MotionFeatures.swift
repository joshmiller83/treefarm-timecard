import Foundation

/// One motion sample: the total acceleration in g, and how fast the watch turns about the
/// vertical (radians a second, counterclockwise seen from above), with its time in seconds (any
/// clock, as long as it's one).
public struct MotionSample: Hashable, Sendable {
    public var t: TimeInterval
    public var x: Double
    public var y: Double
    public var z: Double
    /// Nil when the source has no gyroscope.
    public var turnRate: Double?

    public init(t: TimeInterval, x: Double, y: Double, z: Double, turnRate: Double? = nil) {
        self.t = t
        self.x = x
        self.y = y
        self.z = z
        self.turnRate = turnRate
    }

    /// From device motion: gravity and the user's acceleration (both in g) add up to the total,
    /// and the rotation rate (radians a second, device frame) projected on gravity is the turn
    /// about the vertical. Gravity points down, and a positive rotation about a downward axis is
    /// clockwise seen from above, hence the minus.
    public init(t: TimeInterval, gravity: (x: Double, y: Double, z: Double), user: (x: Double, y: Double, z: Double),
                rotation: (x: Double, y: Double, z: Double)) {
        let g = (gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z).squareRoot()
        let turn = g > 0 ? -(rotation.x * gravity.x + rotation.y * gravity.y + rotation.z * gravity.z) / g : nil
        self.init(t: t, x: gravity.x + user.x, y: gravity.y + user.y, z: gravity.z + user.z, turnRate: turn)
    }

    public var magnitude: Double { (x * x + y * y + z * z).squareRoot() }
}

/// Reduces a second of wrist motion to a few numbers on the watch (docs/gis.md 5), so the field
/// log keeps no raw samples. The turn is the clearest sign of shaping: Josh walks a full circle
/// around each tree, so the watch turns about 360° a tree, on either wrist. The stroke count is a
/// first guess to be tuned on real shifts; the 25-a-second magnitude is kept so other detectors
/// can be tried on the same data.
public enum MotionFeatures {
    /// A peak this far above the second's mean (g) counts.
    public static let peakThreshold = 0.35
    /// Peaks closer than this (seconds) are one stroke.
    public static let peakGap = 0.15
    public static let slices = 25

    /// `samples` from one second, oldest first. Nil when there are none.
    public static func second(_ samples: [MotionSample]) -> FieldLogMotion? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let m = samples.map(\.magnitude)
        let mean = m.reduce(0, +) / Double(m.count)
        let energy = (m.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(m.count)).squareRoot()

        var peaks = 0
        var lastPeak = -Double.infinity
        if m.count >= 3 {
            for i in 1..<(m.count - 1) where m[i] - mean >= peakThreshold && m[i] >= m[i - 1] && m[i] > m[i + 1] {
                if samples[i].t - lastPeak >= peakGap {
                    peaks += 1
                    lastPeak = samples[i].t
                }
            }
        }

        // Equal slices of the time the samples span (one second when the batch is whole).
        let span = max(last.t - first.t, 1e-9)
        var sums = [Double](repeating: 0, count: slices)
        var counts = [Int](repeating: 0, count: slices)
        for (sample, value) in zip(samples, m) {
            let i = min(slices - 1, Int((sample.t - first.t) / span * Double(slices)))
            sums[i] += value
            counts[i] += 1
        }
        var magnitude: [Double] = []
        var previous = mean
        for i in 0..<slices {
            // An empty slice (a short batch) repeats the one before.
            let value = counts[i] > 0 ? sums[i] / Double(counts[i]) : previous
            magnitude.append((value * 1000).rounded() / 1000)
            previous = value
        }
        // The turn: each sample's rate over the time to the next (the last one uses the average
        // spacing), in degrees.
        var turn: Double?
        if samples.contains(where: { $0.turnRate != nil }) {
            let step = samples.count > 1 ? span / Double(samples.count - 1) : 0
            var radians = 0.0
            for (i, sample) in samples.enumerated() {
                let dt = i + 1 < samples.count ? samples[i + 1].t - sample.t : step
                radians += (sample.turnRate ?? 0) * dt
            }
            turn = (radians * 180 / .pi * 10).rounded() / 10
        }
        return FieldLogMotion(samples: samples.count, energy: (energy * 10_000).rounded() / 10_000, peaks: peaks,
                              turn: turn, magnitude: magnitude)
    }
}
