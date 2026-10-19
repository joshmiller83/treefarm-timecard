import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Server commands")
struct CommandTests {
    @Test func bootstrapPrintsTheFarmAndAResetCode() async throws {
        try await withTestApp { app, _ in
            let out = try await runCommand(app, ["bootstrap", "--email", "josh@example.com", "--name", "Josh", "--farm", "Dull's Tree Farm", "--tz", "America/Indiana/Indianapolis"])
            #expect(out.contains("Dull's Tree Farm"))
            let farm = try #require(try await RecordModel.query(on: app.db).filter(\.$kind == "farm").first())
            #expect(out.contains(farm.entityId.uuidString))
            let code = try #require(findCode(in: out))
            let res = try await app.client2.send(.POST, APIPath.resetPassword, json: ResetPasswordRequest(email: "josh@example.com", resetCode: code, newPassword: "long enough", deviceName: "iPhone"))
            #expect(res.status == .ok)

            await #expect(throws: (any Error).self) {
                _ = try await runCommand(app, ["bootstrap", "--email", "josh@example.com", "--name", "Josh", "--farm", "Again", "--tz", "UTC"])
            }
            await #expect(throws: (any Error).self) {
                _ = try await runCommand(app, ["bootstrap", "--email", "x@example.com"])
            }
        }
    }

    @Test func resetCodeLetsAnAccountSignInAgain() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let out = try await runCommand(app, ["reset-code", "--email", "  \(farm.admin.email.uppercased()) "])
            #expect(out.contains("I have a reset code"))
            let code = try #require(findCode(in: out))
            let res = try await app.client2.send(.POST, APIPath.resetPassword, json: ResetPasswordRequest(email: farm.admin.email, resetCode: code, newPassword: "a brand new one", deviceName: "iPhone"))
            #expect(res.status == .ok)

            await #expect(throws: (any Error).self) {
                _ = try await runCommand(app, ["reset-code", "--email", "nobody@example.com"])
            }
            await #expect(throws: (any Error).self) {
                _ = try await runCommand(app, ["reset-code"])
            }
        }
    }

    @Test func invitePrintsAWorkingCode() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let out = try await runCommand(app, ["invite", "--farm", farm.farmId.uuidString, "--role", "admin"])
            let code = try #require(findCode(in: out))
            let res = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: code, email: "boss@example.com", password: "long enough", displayName: "Boss", deviceName: "p"))
            #expect(res.status == .ok)
            #expect(try res.decode(AuthResponse.self).me.memberships.first?.role == .admin)

            await #expect(throws: (any Error).self) {
                _ = try await runCommand(app, ["invite", "--farm", UUID().uuidString, "--role", "worker"])
            }
            await #expect(throws: (any Error).self) {
                _ = try await runCommand(app, ["invite", "--farm", farm.farmId.uuidString, "--role", "boss"])
            }
        }
    }

    @Test func importArtifactRunsFromAFile() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("export.json")
            try SampleExport.json(start: clock.now.addingTimeInterval(-3 * 86400)).write(to: file)
            let out = try await runCommand(app, ["import-artifact", "--farm", farm.farmId.uuidString, "--email", farm.admin.email, "--file", file.path])
            #expect(out.contains("Shifts: 2 added"))
            #expect(out.contains("Note:"))
            await #expect(throws: (any Error).self) {
                _ = try await runCommand(app, ["import-artifact", "--farm", farm.farmId.uuidString, "--email", farm.admin.email, "--file", dir.appendingPathComponent("missing.json").path])
            }
        }
    }
}
