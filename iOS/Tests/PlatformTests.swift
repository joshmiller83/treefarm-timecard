import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// Things only a real iOS runtime can check: the Keychain and file protection.
@Suite("Platform")
struct PlatformTests {
    @Test func keychainKeepsTheToken() throws {
        let store = KeychainTokenStore(service: "TimeCardTests.\(UUID().uuidString)")
        defer { try? store.clear() }
        #expect(try store.read() == nil)
        try store.save("first")
        #expect(try store.read() == "first")
        try store.save("second")
        #expect(try store.read() == "second")
        try store.clear()
        #expect(try store.read() == nil)
        try store.clear()
    }

    @Test func theDatabaseIsReadableAfterFirstUnlock() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("db-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try AppDatabase.open(directory: dir)
        for file in AppDatabase.protectedFiles(for: dir.appendingPathComponent(AppDatabase.fileName)) {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let protection = attributes[.protectionKey] as? FileProtectionType {
                #expect(protection == .completeUntilFirstUserAuthentication, "\(file.lastPathComponent)")
            }
        }
    }

    @Test func theAppGroupIsConfigured() {
        let group = Bundle.main.object(forInfoDictionaryKey: "TimeCardAppGroup") as? String
        #expect(group?.hasPrefix("group.") == true)
        #expect(group?.hasSuffix(".timecard") == true)
    }

    @Test func backgroundRefreshIsPermitted() {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        #expect(permitted.contains(AppModel.backgroundRefreshID))
    }

    @Test func siriKnowsTheOtherNames() {
        let names = (Bundle.main.object(forInfoDictionaryKey: "INAlternativeAppNames") as? [[String: String]] ?? []).compactMap { $0["INAlternativeAppName"] }
        #expect(names == ["Tree Card", "Tree Farm"])
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Time Card")
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true)
    }
}
