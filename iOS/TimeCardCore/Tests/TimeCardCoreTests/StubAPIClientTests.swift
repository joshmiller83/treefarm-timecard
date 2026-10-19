import Foundation
import Testing
@testable import TimeCardCore

@Suite("Stub server")
struct StubAPIClientTests {
    let f = Fixtures()

    func makeStub() async -> StubAPIClient {
        let stub = StubAPIClient()
        await stub.seed(farmId: f.farmId, f.layout)
        return stub
    }

    @Test func pushedRecordsComeBackOnPullInPages() async throws {
        let stub = await makeStub()
        let marks = (0..<5).map { f.mark(row: 0, position: $0) }
        let push = PushRequest(mutations: marks.map { Mutation(record: .treeMark($0)) })
        let answer = try await stub.push(farmId: f.farmId, push)
        #expect(answer.results.map(\.status) == Array(repeating: .applied, count: 5))

        let page1 = try await stub.pull(farmId: f.farmId, since: 0, limit: 6)
        #expect(page1.changes.count == 6)
        #expect(page1.hasMore)
        let page2 = try await stub.pull(farmId: f.farmId, since: page1.cursor, limit: 6)
        #expect(page2.changes.count == 4)
        #expect(!page2.hasMore)
        #expect(Set(page2.changes.map(\.record)).isSuperset(of: Set(marks.suffix(4).map(SyncRecord.treeMark))))
    }

    @Test func aRepeatedMutationGetsItsFirstAnswer() async throws {
        let stub = await makeStub()
        let mutation = Mutation(record: .shift(f.shift()))
        let first = try await stub.push(farmId: f.farmId, PushRequest(mutations: [mutation]))
        let again = try await stub.push(farmId: f.farmId, PushRequest(mutations: [mutation]))
        #expect(first == again)
        let all = try await stub.pull(farmId: f.farmId, since: 0, limit: 100)
        #expect(all.changes.filter { $0.record.kind == .shift }.count == 1)
    }

    @Test func theFirstMarkOnATreeWins() async throws {
        let stub = await makeStub()
        await stub.addMember(Member(userId: f.otherUserId, farmId: f.farmId, displayName: "Sam", email: "sam@example.com", role: .worker,
                                    updatedAt: Fixtures.t0))
        let sams = f.mark(row: 11, position: 3, userId: f.otherUserId, shiftId: UUID(), at: Date(timeIntervalSince1970: 1_760_630_400))
        _ = try await stub.push(farmId: f.farmId, PushRequest(mutations: [Mutation(record: .treeMark(sams))]))
        let mine = Mutation(record: .treeMark(f.mark(row: 11, position: 3)))
        let answer = try await stub.push(farmId: f.farmId, PushRequest(mutations: [mine]))
        #expect(answer.results == [.rejected(mine.id, .treeTaken, "Row 12, tree 4 was shaped by Sam on Oct 16.", current: .treeMark(sams))])
    }

    @Test func scriptedFailures() async throws {
        let stub = await makeStub()
        await stub.failNext(.offline)
        await #expect(throws: APIError.offline) { _ = try await stub.pull(farmId: f.farmId, since: 0, limit: 10) }
        _ = try await stub.pull(farmId: f.farmId, since: 0, limit: 10)

        // The server keeps the push but the answer never arrives.
        await stub.loseNextPushAnswer()
        let mutation = Mutation(record: .shift(f.shift()))
        await #expect(throws: APIError.offline) { _ = try await stub.push(farmId: f.farmId, PushRequest(mutations: [mutation])) }
        #expect(await stub.record(kind: .shift, id: f.shiftId) == .shift(f.shift()))
    }

    @Test func signsInKnownPeople() async throws {
        let stub = await makeStub()
        let me = MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [f.member])
        await stub.addAccount(email: "josh@example.com", password: "right", me: me)
        let auth = try await stub.login(LoginRequest(email: "Josh@Example.com ", password: "right", deviceName: "d"))
        #expect(auth.me == me)
        #expect(!auth.token.isEmpty)
        await #expect(throws: APIError.unauthorized(reason: "That email and password don't match.")) {
            _ = try await stub.login(LoginRequest(email: "josh@example.com", password: "wrong", deviceName: "d"))
        }
    }
}
