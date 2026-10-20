import Foundation
import HealthKit
import Testing
import TreeFarmKit
@testable import TimeCardWatch

/// What the workout keeps on disk (the session's record, for recovery, and the last summary)
/// and what it writes into Health.
@Suite("Workout store and metadata")
struct WorkoutStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "WorkoutStoreTests-\(UUID().uuidString)")
    let start = Date(timeIntervalSince1970: 1_792_400_000)

    @Test func nothingSavedReadsAsNoSession() {
        let store = WorkoutStore(directory: directory)
        #expect(store.local() == WorkoutLocal())
        #expect(store.summaries() == WorkoutStore.Summaries())
    }

    @Test func theSessionsRecordSurvivesARelaunch() {
        let local = WorkoutLocal().started(at: start, shiftId: UUID(), origin: .watchTap, syncIdentifier: UUID())
            .stopped(at: start.addingTimeInterval(3600))
        WorkoutStore(directory: directory).save(local)
        #expect(WorkoutStore(directory: directory).local() == local)
    }

    @Test func theSummarySlotHoldsOne() {
        let store = WorkoutStore(directory: directory)
        let first = WorkoutSummary(shiftId: UUID(), start: start, end: start.addingTimeInterval(3600), activeDuration: 3500)
        let second = WorkoutSummary(shiftId: UUID(), start: start, end: start.addingTimeInterval(7200), activeDuration: 7000)
        store.save(WorkoutStore.Summaries(last: first, dismissed: false, pending: first))
        store.save(WorkoutStore.Summaries(last: second, dismissed: true, pending: second))
        #expect(store.summaries() == WorkoutStore.Summaries(last: second, dismissed: true, pending: second))
    }

    @Test func anUnreadableFileReadsAsNothing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: directory.appending(path: WorkoutStore.localFile))
        #expect(WorkoutStore(directory: directory).local() == WorkoutLocal())
    }

    @Test func theWorkoutCarriesItsShiftBrandAndSyncIdentity() {
        let shift = UUID(), sync = UUID()
        let local = WorkoutLocal().started(at: start, shiftId: shift, origin: .phoneLaunch, syncIdentifier: sync)
        let metadata = WorkoutMetadata.make(local: local, timeZone: "America/Indiana/Indianapolis")
        #expect(metadata[HKMetadataKeyWorkoutBrandName] as? String == "Time Card shift")
        #expect(metadata[WorkoutMetadata.shiftIdKey] as? String == shift.uuidString)
        #expect(metadata[HKMetadataKeySyncIdentifier] as? String == sync.uuidString)
        #expect(metadata[HKMetadataKeySyncVersion] as? Int == 1)
        #expect(metadata[HKMetadataKeyTimeZone] as? String == "America/Indiana/Indianapolis")
        #expect(metadata[HKMetadataKeyIndoorWorkout] as? Bool == false)
        #expect(metadata.count == 6)
    }

    @Test func anUntaggedWorkoutHasNoShiftId() {
        let local = WorkoutLocal().started(at: start, shiftId: nil, origin: .phoneLaunch, syncIdentifier: UUID())
        let metadata = WorkoutMetadata.make(local: local, timeZone: "UTC")
        #expect(metadata[WorkoutMetadata.shiftIdKey] == nil)
        #expect(metadata.count == 5)
    }

    @Test func theSessionIsAnOutdoorOtherWorkout() {
        let configuration = WorkoutMetadata.configuration()
        #expect(configuration.activityType == .other)
        #expect(configuration.locationType == .outdoor)
    }
}
