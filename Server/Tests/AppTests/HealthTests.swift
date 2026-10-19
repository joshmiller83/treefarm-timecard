import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Health and errors")
struct HealthTests {
    @Test func healthAnswersOK() async throws {
        try await withTestApp { app, _ in
            let res = try await app.client2.send(.GET, APIPath.health)
            #expect(res.status == .ok)
            let body = try res.decode(HealthResponse.self)
            #expect(body.status == "ok")
            #expect(!body.version.isEmpty)
        }
    }

    @Test func theRootRedirectsToTheWebsite() async throws {
        try await withTestApp { app, _ in
            let res = try await app.client2.send(.GET, "/")
            #expect(res.status == .found)
            #expect(res.headers.first(name: .location) == "https://treefarm.joshnliz.com")
        }
    }

    @Test func unknownRoutesAnswerWithAJSONError() async throws {
        try await withTestApp { app, _ in
            let res = try await app.client2.send(.GET, "/v1/nope")
            #expect(res.status == .notFound)
            let body = try res.decode(APIErrorBody.self)
            #expect(body.error)
            #expect(!body.reason.isEmpty)
        }
    }

    @Test func unexpectedErrorsDoNotLeakDetails() async throws {
        try await withTestApp { app, _ in
            app.get("boom") { _ -> String in
                struct Secret: Error { let detail = "stack trace and secrets" }
                throw Secret()
            }
            let res = try await app.client2.send(.GET, "/boom")
            #expect(res.status == .internalServerError)
            #expect(!res.text.contains("secrets"))
            #expect(!res.text.contains("Secret"))
            #expect(res.errorReason == "Something went wrong on the server. Please try again.")
        }
    }

    @Test func oversizedBodiesAreRefused() async throws {
        try await withTestApp { app, _ in
            app.post("echo") { req -> String in "\(req.body.data?.readableBytes ?? 0)" }
            let big = ByteBuffer(repeating: UInt8(ascii: "a"), count: 3 * 1024 * 1024)
            let res = try await app.liveClient.send(.POST, "/echo", rawBody: big)
            #expect(res.status == .payloadTooLarge)
            #expect(res.errorReason != nil)
        }
    }

    @Test func configReadsTheEnvironment() {
        let config = AppConfig.fromEnvironment([
            "TIMECARD_HOST": "0.0.0.0",
            "TIMECARD_PORT": "9000",
            "TIMECARD_DB": "/tmp/x.sqlite",
            "TIMECARD_BACKUP_DIR": "/tmp/backups",
            "TIMECARD_BCRYPT_COST": "10",
        ])
        #expect(config.host == "0.0.0.0")
        #expect(config.port == 9000)
        #expect(config.database == .file("/tmp/x.sqlite"))
        #expect(config.backupDirectory == "/tmp/backups")
        #expect(config.bcryptCost == 10)

        let defaults = AppConfig.fromEnvironment([:])
        #expect(defaults.host == "127.0.0.1")
        #expect(defaults.port == 8790)
        #expect(defaults.database == .file("./data/timecard.sqlite"))
        #expect(defaults.backupDirectory == "./data/backups")
        #expect(defaults.bcryptCost == 12)
    }
}
