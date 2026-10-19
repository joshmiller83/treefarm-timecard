import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Bootstrap, sign-up, sign-in")
struct AuthTests {
    @Test func bootstrapMakesTheFarmAndItsFirstAdmin() async throws {
        try await withTestApp { app, clock in
            let result = try await Bootstrap.run(app: app, email: "Josh@Example.com", name: "Josh", farmName: "Dull's Tree Farm", timeZoneId: "America/Indiana/Indianapolis")
            let store = RecordStore(db: app.db)
            let farm = try #require(try await store.farm(result.farmId))
            #expect(farm.name == "Dull's Tree Farm")
            #expect(farm.timeZoneId == "America/Indiana/Indianapolis")
            #expect(farm.activeSeasonId == result.seasonId)
            let season = try #require(try await store.season(result.seasonId, farm: farm.id))
            #expect(season.name == "2025") // the test clock sits in October 2025
            let member = try #require(try await store.member(result.userId, farm: farm.id))
            #expect(member.role == .admin)
            #expect(member.email == "josh@example.com")
            #expect(member.displayName == "Josh")
            let field = try #require(try await store.field(result.fieldId, farm: farm.id))
            #expect(field.name == "Field 1")
            #expect(Codes.normalize(result.resetCode).count == 10)
            #expect(result.resetExpiresAt == clock.now.addingTimeInterval(24 * 3600))
        }
    }

    @Test func bootstrapRefusesAnEmailThatExists() async throws {
        try await withTestApp { app, _ in
            _ = try await Bootstrap.run(app: app, email: "josh@example.com", name: "Josh", farmName: "A", timeZoneId: "UTC")
            await #expect(throws: (any Error).self) {
                _ = try await Bootstrap.run(app: app, email: "JOSH@example.com", name: "Josh", farmName: "B", timeZoneId: "UTC")
            }
        }
    }

    @Test func bootstrapRefusesABadTimeZone() async throws {
        try await withTestApp { app, _ in
            await #expect(throws: (any Error).self) {
                _ = try await Bootstrap.run(app: app, email: "josh@example.com", name: "Josh", farmName: "A", timeZoneId: "Mars/Olympus")
            }
        }
    }

    @Test func theBootstrapResetCodeSignsTheAdminInOnce() async throws {
        try await withTestApp { app, _ in
            let result = try await Bootstrap.run(app: app, email: "josh@example.com", name: "Josh", farmName: "A", timeZoneId: "UTC")
            let req = ResetPasswordRequest(email: "josh@example.com", resetCode: result.resetCode.lowercased(), newPassword: "a long password", deviceName: "iPhone")
            let res = try await app.client2.send(.POST, APIPath.resetPassword, json: req)
            #expect(res.status == .ok)
            let auth = try res.decode(AuthResponse.self)
            #expect(auth.me.user.email == "josh@example.com")
            #expect(auth.me.farms.map(\.id) == [result.farmId])
            #expect(auth.me.memberships.first?.role == .admin)

            let again = try await app.client2.send(.POST, APIPath.resetPassword, json: req)
            #expect(again.status == .badRequest)
            #expect(again.errorReason?.contains("reset code") == true)
        }
    }

    @Test func resetCodesExpireAfterADay() async throws {
        try await withTestApp { app, clock in
            let result = try await Bootstrap.run(app: app, email: "josh@example.com", name: "Josh", farmName: "A", timeZoneId: "UTC")
            clock.advance(24 * 3600 + 1)
            let res = try await app.client2.send(.POST, APIPath.resetPassword, json: ResetPasswordRequest(email: "josh@example.com", resetCode: result.resetCode, newPassword: "a long password", deviceName: "iPhone"))
            #expect(res.status == .badRequest)
        }
    }

    @Test func registerJoinsTheFarmWithTheInvitesRole() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let me = try await app.client2.send(.GET, APIPath.me, token: sam.token).decode(MeResponse.self)
            #expect(me.user.displayName == "Sam")
            #expect(me.memberships.count == 1)
            let m = try #require(me.memberships.first)
            #expect(m.role == .worker)
            #expect(m.rateCents == 0)
            #expect(m.jobTitle == "")
            #expect(m.farmId == farm.farmId)

            let boss = try await farm.join("Boss", role: .admin)
            let bossMe = try await app.client2.send(.GET, APIPath.me, token: boss.token).decode(MeResponse.self)
            #expect(bossMe.memberships.first?.role == .admin)
        }
    }

    @Test func invitesAreSingleUseAndExpireInAWeek() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let code = try await farm.inviteCode()
            let first = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: code, email: "a@example.com", password: "password one", displayName: "A", deviceName: "p"))
            #expect(first.status == .ok)
            let second = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: code, email: "b@example.com", password: "password two", displayName: "B", deviceName: "p"))
            #expect(second.status == .badRequest)
            #expect(second.errorReason?.contains("already used") == true)

            let later = try await farm.inviteCode()
            clock.advance(7 * 24 * 3600 + 1)
            let expired = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: later, email: "c@example.com", password: "password three", displayName: "C", deviceName: "p"))
            #expect(expired.status == .badRequest)
            #expect(expired.errorReason?.contains("expired") == true)

            let bogus = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: "AAAA-BBBB-CC", email: "d@example.com", password: "password four", displayName: "D", deviceName: "p"))
            #expect(bogus.status == .badRequest)
        }
    }

    @Test func registerChecksItsInput() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let code = try await farm.inviteCode()
            let short = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: code, email: "a@example.com", password: "short", displayName: "A", deviceName: "p"))
            #expect(short.status == .badRequest)
            #expect(short.errorReason?.contains("8 characters") == true)
            let badEmail = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: code, email: "not-an-email", password: "long enough", displayName: "A", deviceName: "p"))
            #expect(badEmail.status == .badRequest)
            let noName = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: code, email: "a@example.com", password: "long enough", displayName: "   ", deviceName: "p"))
            #expect(noName.status == .badRequest)
            // None of those used the invite up.
            let ok = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: code, email: "a@example.com", password: "long enough", displayName: "A", deviceName: "p"))
            #expect(ok.status == .ok)
        }
    }

    @Test func anExistingAccountJoinsASecondFarmWithItsPassword() async throws {
        try await withTestApp { app, _ in
            let farmA = try await FarmFixture.make(app)
            let farmB = try await FarmFixture.make(app, farmName: "Other Farm", adminEmail: "other@example.com")
            let sam = try await farmA.join("Sam")

            let wrong = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: try await farmB.inviteCode(), email: sam.email, password: "not sams password", displayName: "Sam", deviceName: "p"))
            #expect(wrong.status == .conflict)

            let right = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: try await farmB.inviteCode(), email: sam.email.uppercased(), password: sam.password, displayName: "Sam", deviceName: "p"))
            #expect(right.status == .ok)
            let me = try right.decode(AuthResponse.self).me
            #expect(Set(me.farms.map(\.id)) == [farmA.farmId, farmB.farmId])

            let again = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: try await farmB.inviteCode(), email: sam.email, password: sam.password, displayName: "Sam", deviceName: "p"))
            #expect(again.status == .conflict)
        }
    }

    @Test func loginWorksWithAnyCaseEmailAndRefusesWrongPasswords() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let ok = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: " SAM@example.com ", password: sam.password, deviceName: "iPad"))
            #expect(ok.status == .ok)
            let auth = try ok.decode(AuthResponse.self)
            #expect(auth.me.user.id == sam.userId)
            #expect(auth.token != sam.token)

            let wrong = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: sam.email, password: "nope nope", deviceName: "iPad"))
            #expect(wrong.status == .unauthorized)
            let nobody = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: "ghost@example.com", password: "nope nope", deviceName: "iPad"))
            #expect(nobody.status == .unauthorized)
            #expect(wrong.errorReason == nobody.errorReason)
        }
    }

    @Test func bootstrappedAdminsCannotSignInBeforeUsingTheirCode() async throws {
        try await withTestApp { app, _ in
            _ = try await Bootstrap.run(app: app, email: "josh@example.com", name: "Josh", farmName: "A", timeZoneId: "UTC")
            let res = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: "josh@example.com", password: "", deviceName: "iPad"))
            #expect(res.status == .unauthorized)
        }
    }

    @Test func logoutEndsOnlyThatSession() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let other = try await farm.login(sam)
            let out = try await app.client2.send(.POST, APIPath.logout, token: sam.token)
            #expect(out.status == .noContent)
            #expect(try await app.client2.send(.GET, APIPath.me, token: sam.token).status == .unauthorized)
            #expect(try await app.client2.send(.GET, APIPath.me, token: other).status == .ok)
        }
    }

    @Test func meNeedsAValidToken() async throws {
        try await withTestApp { app, _ in
            #expect(try await app.client2.send(.GET, APIPath.me).status == .unauthorized)
            let res = try await app.client2.send(.GET, APIPath.me, token: "garbage")
            #expect(res.status == .unauthorized)
            #expect(res.errorReason == "Please sign in again.")
        }
    }

    @Test func sessionsSlideForNinetyDaysOfUse() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            clock.advance(80 * 24 * 3600)
            #expect(try await app.client2.send(.GET, APIPath.me, token: sam.token).status == .ok)
            clock.advance(80 * 24 * 3600)
            #expect(try await app.client2.send(.GET, APIPath.me, token: sam.token).status == .ok)
            clock.advance(91 * 24 * 3600)
            #expect(try await app.client2.send(.GET, APIPath.me, token: sam.token).status == .unauthorized)
        }
    }
}
