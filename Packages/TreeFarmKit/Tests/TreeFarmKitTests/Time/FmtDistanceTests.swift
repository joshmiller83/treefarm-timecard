import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Distance")
struct FmtDistanceTests {
    @Test func milesAndKilometersToATenth() {
        #expect(Fmt.distance(meters: 5472, miles: true) == "3.4 mi")
        #expect(Fmt.distance(meters: 5472, miles: false) == "5.5 km")
        #expect(Fmt.distance(meters: 0, miles: true) == "0.0 mi")
        #expect(Fmt.distance(meters: 1_609_344, miles: true) == "1,000.0 mi")
        #expect(Fmt.distance(meters: -3, miles: false) == "0.0 km")
        #expect(Fmt.distance(meters: .nan, miles: false) == "0.0 km")
    }

    @Test func spokenDistance() {
        #expect(Fmt.spokenDistance(meters: 5472, miles: true) == "3.4 miles")
        #expect(Fmt.spokenDistance(meters: 1609.344, miles: true) == "1 mile")
        #expect(Fmt.spokenDistance(meters: 3000, miles: false) == "3 kilometers")
        #expect(Fmt.spokenDistance(meters: 400, miles: false) == "0.4 kilometers")
    }
}
