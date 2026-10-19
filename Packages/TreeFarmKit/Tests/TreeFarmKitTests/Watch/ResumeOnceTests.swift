import Foundation
import Testing
@testable import TreeFarmKit

@Suite("ResumeOnce")
struct ResumeOnceTests {
    struct Boom: Error, Equatable {}

    @Test func aReplyThenATimeoutGivesTheReply() async throws {
        let value: Int = try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            once.resume(returning: 14)
            once.resume(throwing: WatchTransportError.timedOut)
        }
        #expect(value == 14)
    }

    @Test func aReplyAfterTheTimeoutDoesntCrashAndIsIgnored() async {
        await #expect(throws: WatchTransportError.timedOut) {
            let _: Int = try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce(continuation)
                once.resume(throwing: WatchTransportError.timedOut)
                // Resuming a continuation twice is a fatal error; this one must do nothing.
                once.resume(returning: 15)
            }
        }
    }

    @Test func anErrorThenAReplyGivesTheError() async {
        await #expect(throws: Boom()) {
            let _: Int = try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce(continuation)
                once.resume(throwing: Boom())
                once.resume(returning: 16)
                once.resume(throwing: WatchTransportError.timedOut)
            }
        }
    }

    @Test func manyRacersResumeExactlyOnce() async {
        // Whoever wins, the continuation is resumed once (twice would crash the test run).
        for _ in 0..<50 {
            do {
                let value: Int = try await withCheckedThrowingContinuation { continuation in
                    let once = ResumeOnce(continuation)
                    DispatchQueue.concurrentPerform(iterations: 8) { i in
                        if i.isMultiple(of: 2) { once.resume(returning: i) } else { once.resume(throwing: Boom()) }
                    }
                    #expect(once.isResumed)
                }
                #expect(value.isMultiple(of: 2))
            } catch {
                #expect(error is Boom)
            }
        }
    }

    @Test func aTimedSendThatIsAnsweredLateTimesOut() async {
        // The shape every transport's `send` uses: the reply handler, its error handler and a
        // timeout task all race to resume, and the first one wins.
        await #expect(throws: WatchTransportError.timedOut) {
            let _: Data = try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce(continuation)
                Task {
                    try? await Task.sleep(for: .milliseconds(20))
                    once.resume(throwing: WatchTransportError.timedOut)
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    once.resume(returning: Data("late".utf8))
                }
            }
        }
        // Let the late reply arrive: it must not resume anything.
        try? await Task.sleep(for: .milliseconds(250))
    }
}
