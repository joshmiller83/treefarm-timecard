import Foundation
import Testing
import TreeFarmKit
import TreeFarmKitTestSupport
@testable import TimeCardWatch

/// The file the watch app shares with its complications.
@Suite("Watch state file")
struct WatchStateFileTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "WatchStateFileTests-\(UUID().uuidString)")

    @Test func nothingWrittenReadsEmpty() {
        #expect(WatchStateFile.read(from: directory) == .empty)
    }

    @Test func whatIsWrittenIsRead() {
        let state = WatchState.signedOut(epoch: UUID(), revision: 4, now: Date(timeIntervalSince1970: 1_792_400_000))
        let contents = WatchStateFile.Contents(displayed: state, waitingCount: 2, clockOutWaiting: true)
        WatchStateFile.write(contents, to: directory)
        #expect(WatchStateFile.read(from: directory) == contents)
    }

    @Test func anUnreadableFileReadsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: WatchStateFile.fileName))
        #expect(WatchStateFile.read(from: directory) == .empty)
    }

    @Test func theTestSupportLibraryLinks() {
        #expect(InMemoryOutboxStore().load() == nil)
    }
}
