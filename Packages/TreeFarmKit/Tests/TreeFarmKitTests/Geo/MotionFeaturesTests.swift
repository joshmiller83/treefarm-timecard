import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Motion features")
struct MotionFeaturesTests {
    /// One second at `hz`, gravity on z plus `wave(t)` added to the magnitude.
    func second(hz: Int = 100, _ wave: (Double) -> Double) -> [MotionSample] {
        (0..<hz).map { i in
            let t = Double(i) / Double(hz)
            return MotionSample(t: 50 + t, x: 0, y: 0, z: 1 + wave(t))
        }
    }

    @Test func aStillWristHasNoEnergyAndNoStrokes() throws {
        let motion = try #require(MotionFeatures.second(second { _ in 0 }))
        #expect(motion.samples == 100)
        #expect(motion.energy == 0)
        #expect(motion.peaks == 0)
        #expect(motion.magnitude == Array(repeating: 1, count: 25))
    }

    @Test func threeSharpSwingsAreThreeStrokes() throws {
        // Spikes of 1.2 g at 0.2, 0.5 and 0.8 s.
        let motion = try #require(MotionFeatures.second(second { t in
            [0.2, 0.5, 0.8].contains { abs(t - $0) < 0.001 } ? 1.2 : 0
        }))
        #expect(motion.peaks == 3)
        #expect(motion.energy > 0.15)
    }

    @Test func peaksCloserThanTheGapCountOnce() throws {
        let motion = try #require(MotionFeatures.second(second { t in
            [0.40, 0.45].contains { abs(t - $0) < 0.001 } ? 1.0 : 0
        }))
        #expect(motion.peaks == 1)
    }

    @Test func aGentleSwayIsNotAStroke() throws {
        // A slow 1 Hz sway of ±0.2 g: energy, but below the stroke threshold.
        let motion = try #require(MotionFeatures.second(second { t in 0.2 * sin(2 * .pi * t) }))
        #expect(motion.peaks == 0)
        #expect(motion.energy > 0.1 && motion.energy < 0.2)
    }

    @Test func theMagnitudeIsAveragedIntoTwentyFiveSlicesEvenFromAShortBatch() throws {
        let motion = try #require(MotionFeatures.second(second(hz: 10) { t in t < 0.5 ? 0 : 1 }))
        #expect(motion.magnitude.count == 25)
        #expect(motion.magnitude.first == 1)
        #expect(motion.magnitude.last == 2)
        #expect(MotionFeatures.second([]) == nil)
    }
}
