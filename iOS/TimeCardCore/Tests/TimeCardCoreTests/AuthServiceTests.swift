import Foundation
import Testing
@testable import TimeCardCore

@Suite("Auth service")
struct AuthServiceTests {
    let f = Fixtures()
    let tokens = InMemoryTokenStore()

    var me: MeResponse {
        MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [f.member])
    }

    func makeService(stub: StubAPIClient? = nil, cache: LocalStore? = nil) async throws -> (AuthService, StubAPIClient, LocalStore) {
        let stub = stub ?? StubAPIClient()
        await stub.addAccount(email: "josh@example.com", password: "right horse", me: me)
        let cache = try cache ?? LocalStore.inMemory()
        return (AuthService(api: stub, tokens: tokens, cache: cache, deviceName: "Test iPhone"), stub, cache)
    }

    @Test func startsSignedOut() async throws {
        let (auth, _, _) = try await makeService()
        #expect(await auth.state == .signedOut)
    }

    @Test func signsInAndRemembersWhoForNextLaunch() async throws {
        let (auth, stub, cache) = try await makeService()
        let answer = try await auth.login(email: " josh@example.com ", password: "right horse")
        #expect(answer == me)
        #expect(await auth.state == .signedIn(me))
        #expect(try tokens.read()?.hasPrefix("stub-") == true)

        // Next launch, with no network: still signed in from the cache.
        let relaunched = AuthService(api: stub, tokens: tokens, cache: cache, deviceName: "Test iPhone")
        #expect(await relaunched.state == .signedIn(me))
    }

    @Test func aWrongPasswordSaysSo() async throws {
        let (auth, _, _) = try await makeService()
        await #expect(throws: APIError.unauthorized(reason: "That email and password don't match.")) {
            _ = try await auth.login(email: "josh@example.com", password: "wrong")
        }
        #expect(await auth.state == .signedOut)
        #expect(try tokens.read() == nil)
    }

    @Test func aBlank401AtLoginStillReadsAsAWrongPassword() async throws {
        let stub = StubAPIClient()
        await stub.failNext(.unauthorized(reason: ""))
        let (auth, _, _) = try await makeService(stub: stub)
        await #expect(throws: APIError.unauthorized(reason: "That email and password don't match.")) {
            _ = try await auth.login(email: "josh@example.com", password: "right horse")
        }
    }

    @Test func checksTheFormBeforeAsking() async throws {
        let (auth, _, _) = try await makeService()
        await #expect(throws: AuthError.invalid("Enter your email address.")) {
            _ = try await auth.login(email: "  ", password: "x")
        }
        await #expect(throws: AuthError.invalid("Enter your password.")) {
            _ = try await auth.login(email: "josh@example.com", password: "")
        }
        await #expect(throws: AuthError.invalid("Enter the invite code from your admin.")) {
            _ = try await auth.register(inviteCode: " ", email: "a@b.co", password: "pw", displayName: "A")
        }
        await #expect(throws: AuthError.invalid("Enter your name as the crew knows it.")) {
            _ = try await auth.register(inviteCode: "ABC", email: "a@b.co", password: "pw", displayName: " ")
        }
        await #expect(throws: AuthError.invalid("Enter the reset code from your admin.")) {
            _ = try await auth.reset(email: "a@b.co", code: "", newPassword: "pw")
        }
    }

    @Test func lockoutsCarryTheWait() async throws {
        let (auth, stub, _) = try await makeService()
        await stub.lockOut(email: "josh@example.com", for: 900)
        await #expect(throws: APIError.rateLimited(reason: "Too many tries. Try again in 15 minutes.", retryAfter: 900)) {
            _ = try await auth.login(email: "josh@example.com", password: "right horse")
        }
    }

    @Test func joinsWithAnInviteCode() async throws {
        let (auth, stub, _) = try await makeService()
        await stub.addInvite(code: "TREE-1234", farm: f.farm)
        let joined = try await auth.register(inviteCode: "tree-1234", email: "sam@example.com", password: "pines", displayName: "Sam")
        #expect(joined.user.displayName == "Sam")
        #expect(joined.memberships.first?.role == .worker)
        #expect(await auth.state == .signedIn(joined))
    }

    @Test func anExpiredInviteSaysSo() async throws {
        let (auth, stub, _) = try await makeService()
        await stub.addInvite(code: "OLD", farm: f.farm, expired: true)
        await #expect(throws: APIError.client(status: 410, reason: "That invite code has expired. Ask your admin for a new one.")) {
            _ = try await auth.register(inviteCode: "OLD", email: "sam@example.com", password: "pines", displayName: "Sam")
        }
    }

    @Test func resetsAPasswordWithACode() async throws {
        let (auth, stub, _) = try await makeService()
        await stub.addResetCode("481516", email: "josh@example.com")
        let answer = try await auth.reset(email: "josh@example.com", code: "481516", newPassword: "new horse")
        #expect(answer == me)
        #expect(await auth.state == .signedIn(me))
        _ = try await auth.login(email: "josh@example.com", password: "new horse")
    }

    @Test func refreshKeepsTheCacheCurrent() async throws {
        let (auth, stub, cache) = try await makeService()
        _ = try await auth.login(email: "josh@example.com", password: "right horse")
        var renamed = me
        renamed.user.displayName = "Joshua"
        await stub.signIn(as: renamed)
        #expect(try await auth.refreshMe() == renamed)
        let relaunched = AuthService(api: stub, tokens: tokens, cache: cache, deviceName: "d")
        #expect(await relaunched.state == .signedIn(renamed))
    }

    @Test func anExpiredTokenKeepsWhoYouWere() async throws {
        let (auth, stub, _) = try await makeService()
        _ = try await auth.login(email: "josh@example.com", password: "right horse")
        await stub.failNext(.unauthorized(reason: "Your session ended."))
        await #expect(throws: APIError.unauthorized(reason: "Your session ended.")) {
            _ = try await auth.refreshMe()
        }
        #expect(await auth.state == .expired(me))
    }

    @Test func offlineRefreshChangesNothing() async throws {
        let (auth, stub, _) = try await makeService()
        _ = try await auth.login(email: "josh@example.com", password: "right horse")
        await stub.failNext(.offline)
        await #expect(throws: APIError.offline) { _ = try await auth.refreshMe() }
        #expect(await auth.state == .signedIn(me))
    }

    @Test func theSyncEngineCanReportAnExpiredToken() async throws {
        let (auth, _, _) = try await makeService()
        await auth.markExpired()
        #expect(await auth.state == .signedOut)
        _ = try await auth.login(email: "josh@example.com", password: "right horse")
        await auth.markExpired()
        #expect(await auth.state == .expired(me))
    }

    @Test func signOutForgetsTheTokenEvenOffline() async throws {
        let (auth, stub, cache) = try await makeService()
        _ = try await auth.login(email: "josh@example.com", password: "right horse")
        await stub.failNext(.offline)
        await auth.logout()
        #expect(await auth.state == .signedOut)
        #expect(try tokens.read() == nil)
        #expect(try cache.value(forKey: AuthService.meKey) == nil)
    }

    @Test func aCachedPersonWithoutATokenMustSignInAgain() async throws {
        let (auth, stub, cache) = try await makeService()
        _ = try await auth.login(email: "josh@example.com", password: "right horse")
        try tokens.clear()
        let relaunched = AuthService(api: stub, tokens: tokens, cache: cache, deviceName: "d")
        #expect(await relaunched.state == .expired(me))
        _ = auth
    }
}
