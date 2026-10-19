import Foundation
import NIOCore
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Rate limits")
struct RateLimitTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func eachAddressGetsAWindowOfAttempts() async {
        let limiter = RateLimiter(rules: .init(ipAttempts: 3, ipWindow: 60, emailFailures: 5, lockout: 900))
        for _ in 0..<3 { #expect(await limiter.hit(ip: "1.1.1.1", now: t0) == nil) }
        let wait = await limiter.hit(ip: "1.1.1.1", now: t0.addingTimeInterval(10))
        #expect(wait == 50)
        #expect(await limiter.hit(ip: "2.2.2.2", now: t0) == nil)
        #expect(await limiter.hit(ip: "1.1.1.1", now: t0.addingTimeInterval(61)) == nil)
    }

    @Test func repeatedFailuresLockAnEmail() async {
        let limiter = RateLimiter(rules: .init(ipAttempts: 100, ipWindow: 60, emailFailures: 3, lockout: 900))
        for _ in 0..<2 { await limiter.recordFailure(email: "a@b.com", now: t0) }
        #expect(await limiter.lockRemaining(email: "a@b.com", now: t0) == nil)
        await limiter.recordFailure(email: "a@b.com", now: t0)
        #expect(await limiter.lockRemaining(email: "a@b.com", now: t0.addingTimeInterval(100)) == 800)
        #expect(await limiter.lockRemaining(email: "a@b.com", now: t0.addingTimeInterval(901)) == nil)
    }

    @Test func successClearsFailures() async {
        let limiter = RateLimiter(rules: .init(ipAttempts: 100, ipWindow: 60, emailFailures: 3, lockout: 900))
        for _ in 0..<2 { await limiter.recordFailure(email: "a@b.com", now: t0) }
        await limiter.recordSuccess(email: "a@b.com")
        await limiter.recordFailure(email: "a@b.com", now: t0)
        #expect(await limiter.lockRemaining(email: "a@b.com", now: t0) == nil)
    }

    @Test func cloudflaresHeaderIsTrustedOnlyFromLocalhost() throws {
        let headers: HTTPHeaders = ["CF-Connecting-IP": "203.0.113.9"]
        let local = try SocketAddress(ipAddress: "127.0.0.1", port: 5000)
        let local6 = try SocketAddress(ipAddress: "::1", port: 5000)
        let remote = try SocketAddress(ipAddress: "198.51.100.4", port: 5000)
        #expect(ClientIP.resolve(peer: local, headers: headers) == "203.0.113.9")
        #expect(ClientIP.resolve(peer: local6, headers: headers) == "203.0.113.9")
        #expect(ClientIP.resolve(peer: remote, headers: headers) == "198.51.100.4")
        #expect(ClientIP.resolve(peer: local, headers: [:]) == "127.0.0.1")
        #expect(ClientIP.resolve(peer: nil, headers: headers) == "unknown")
    }

    @Test func fiveWrongPasswordsLockTheAccountForFifteenMinutes() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            for _ in 0..<5 {
                let res = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: sam.email, password: "wrong wrong", deviceName: "x"))
                #expect(res.status == .unauthorized)
            }
            let locked = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: sam.email, password: sam.password, deviceName: "x"))
            #expect(locked.status == .tooManyRequests)
            #expect(locked.headers.first(name: "Retry-After") == "900")
            #expect(locked.errorReason?.contains("15 minutes") == true)

            clock.advance(15 * 60 + 1)
            let ok = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: sam.email, password: sam.password, deviceName: "x"))
            #expect(ok.status == .ok)
        }
    }

    @Test func wrongResetCodesCountTowardTheLock() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            for _ in 0..<5 {
                let res = try await app.client2.send(.POST, APIPath.resetPassword, json: ResetPasswordRequest(email: farm.admin.email, resetCode: "AAAA-AAAA-AA", newPassword: "whatever long", deviceName: "x"))
                #expect(res.status == .badRequest)
            }
            let locked = try await app.client2.send(.POST, APIPath.resetPassword, json: ResetPasswordRequest(email: farm.admin.email, resetCode: "AAAA-AAAA-AA", newPassword: "whatever long", deviceName: "x"))
            #expect(locked.status == .tooManyRequests)
        }
    }

    @Test func eachAddressIsLimitedAcrossSignInRoutes() async throws {
        try await withTestApp(adjust: { $0.ipAttempts = 4 }) { app, _ in
            for i in 0..<4 {
                let res = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: "u\(i)@example.com", password: "whatever", deviceName: "x"))
                #expect(res.status == .unauthorized)
            }
            let res = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: "x", email: "z@example.com", password: "whatever long", displayName: "Z", deviceName: "x"))
            #expect(res.status == .tooManyRequests)
            #expect(res.headers.first(name: "Retry-After") != nil)
        }
    }

    @Test func behindTheTunnelEachRealAddressHasItsOwnLimit() async throws {
        try await withTestApp(adjust: { $0.ipAttempts = 2 }) { app, _ in
            func attempt(from ip: String) async throws -> HTTPStatus {
                try await app.liveClient.send(.POST, APIPath.login, headers: ["CF-Connecting-IP": ip], json: LoginRequest(email: "x@example.com", password: "whatever", deviceName: "x")).status
            }
            var results: [HTTPStatus] = []
            for ip in ["203.0.113.1", "203.0.113.1", "203.0.113.1", "203.0.113.2"] {
                results.append(try await attempt(from: ip))
            }
            #expect(results == [.unauthorized, .unauthorized, .tooManyRequests, .unauthorized])
        }
    }
}
