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

    // MARK: Turning (a full circle around each tree)

    /// One second at `hz` turning at `degreesPerSecond`, from device motion with the watch flat
    /// (gravity straight down the watch's -z).
    func turning(_ degreesPerSecond: Double, hz: Int = 200, start: Double = 0) -> [MotionSample] {
        let rate = degreesPerSecond * .pi / 180
        return (0..<hz).map { i in
            // Counterclockwise seen from above is a positive rotation about the up axis (+z here).
            MotionSample(t: start + Double(i) / Double(hz), gravity: (0, 0, -1), user: (0, 0, 0), rotation: (0, 0, rate))
        }
    }

    @Test func circlingATreeInAMinuteTurnsSixDegreesASecond() throws {
        let ccw = try #require(MotionFeatures.second(turning(6)))
        #expect(ccw.turn == 6)
        let cw = try #require(MotionFeatures.second(turning(-6)))
        #expect(cw.turn == -6)
        // Device motion's total acceleration is gravity plus the user's: 1 g at rest.
        #expect(ccw.magnitude.allSatisfy { $0 == 1 } && ccw.energy == 0)
    }

    @Test func sixtySecondsOfCirclingAddUpToOneFullTurn() throws {
        let total = try (0..<60).reduce(0.0) { sum, s in
            sum + (try #require(MotionFeatures.second(turning(6, start: Double(s)))).turn ?? 0)
        }
        #expect(abs(total - 360) < 0.5)
    }

    @Test func theTurnIsAboutTheVerticalWhicheverWayTheWristIsHeld() throws {
        // The watch on its side (gravity along -x): a rotation about its x axis is the vertical one.
        let rate = 6 * Double.pi / 180
        let samples = (0..<200).map { i in
            MotionSample(t: Double(i) / 200, gravity: (-1, 0, 0), user: (0, 0, 0), rotation: (rate, 0, 0))
        }
        #expect(try #require(MotionFeatures.second(samples)).turn == 6)
        // Twisting the wrist about a level axis isn't a turn.
        let twist = (0..<200).map { i in
            MotionSample(t: Double(i) / 200, gravity: (-1, 0, 0), user: (0, 0, 0), rotation: (0, rate, 0))
        }
        #expect(try #require(MotionFeatures.second(twist)).turn == 0)
    }

    @Test func noGyroscopeNoTurn() throws {
        #expect(try #require(MotionFeatures.second(second { _ in 0 })).turn == nil)
    }

    @Test func theMagnitudeIsAveragedIntoTwentyFiveSlicesEvenFromAShortBatch() throws {
        let motion = try #require(MotionFeatures.second(second(hz: 10) { t in t < 0.5 ? 0 : 1 }))
        #expect(motion.magnitude.count == 25)
        #expect(motion.magnitude.first == 1)
        #expect(motion.magnitude.last == 2)
        #expect(MotionFeatures.second([]) == nil)
    }
}
