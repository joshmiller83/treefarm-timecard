import Foundation
import Testing
@testable import TreeFarmKit

@Suite("StableID")
struct StableIDTests {
    let farm = UUID(uuidString: "FA000000-0000-0000-0000-000000000001")!

    @Test func matchesTheStandardNameBasedUUID() {
        // RFC 4122 version 5; the value Python's uuid.uuid5(NAMESPACE_DNS, "python.org") gives.
        let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        #expect(StableID.uuid(dns, "python.org") == UUID(uuidString: "886313e1-3b8a-5372-9b90-0c9aee199e5d"))
    }

    @Test(arguments: [
        ("block:b1", "30bcddfd-20c1-51ef-8fdd-ac816bfad84e"),
        (String(repeating: "x", count: 200), "97c45a04-aae6-5cc8-9ec7-f4f6db99b9f6"),
        ("Dull’s Tree Farm 🌲", "2a28f0ba-b2e4-59a6-9fb8-3f8e0f0bac0f"),
        ("", "c3234898-42df-510f-aa13-315eba3beafc"),
    ])
    func knownValues(name: String, expected: String) {
        #expect(StableID.uuid(farm, name) == UUID(uuidString: expected))
    }

    @Test func sameInputSameId() {
        #expect(StableID.uuid(farm, "shift:s1") == StableID.uuid(farm, "shift:s1"))
        #expect(StableID.uuid(farm, "shift:s1") != StableID.uuid(farm, "shift:s2"))
        #expect(StableID.uuid(farm, "shift:s1") != StableID.uuid(UUID(), "shift:s1"))
    }

    @Test func isVersionFiveWithTheRFCVariant() {
        let id = StableID.uuid(farm, "mark:1").uuid
        #expect(id.6 >> 4 == 5)
        #expect(id.8 >> 6 == 0b10)
    }
}
