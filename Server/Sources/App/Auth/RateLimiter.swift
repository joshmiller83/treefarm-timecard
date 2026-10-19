import Foundation
import NIOCore
import Vapor

/// In-memory limits for the sign-in routes: a window of attempts per client
/// address, and a lock on an email after repeated wrong passwords or reset codes.
/// State resets when the server restarts, which is fine for a farm-sized crew.
actor RateLimiter {
    struct Rules: Sendable {
        var ipAttempts: Int
        var ipWindow: TimeInterval
        var emailFailures: Int
        var lockout: TimeInterval
    }

    let rules: Rules
    private var hits: [String: [Date]] = [:]
    private var failures: [String: [Date]] = [:]
    private var lockedUntil: [String: Date] = [:]
    private var calls = 0

    init(rules: Rules) {
        self.rules = rules
    }

    /// Counts an attempt from `ip`. Returns how long to wait when it's over the limit.
    func hit(ip: String, now: Date) -> TimeInterval? {
        sweep(now: now)
        var list = hits[ip, default: []].filter { now.timeIntervalSince($0) < rules.ipWindow }
        if list.count >= rules.ipAttempts, let oldest = list.first {
            hits[ip] = list
            return max(1, rules.ipWindow - now.timeIntervalSince(oldest))
        }
        list.append(now)
        hits[ip] = list
        return nil
    }

    func lockRemaining(email: String, now: Date) -> TimeInterval? {
        guard let until = lockedUntil[email] else { return nil }
        if until <= now {
            lockedUntil[email] = nil
            return nil
        }
        return until.timeIntervalSince(now)
    }

    func recordFailure(email: String, now: Date) {
        var list = failures[email, default: []].filter { now.timeIntervalSince($0) < rules.lockout }
        list.append(now)
        if list.count >= rules.emailFailures {
            lockedUntil[email] = now.addingTimeInterval(rules.lockout)
            list = []
        }
        failures[email] = list
    }

    func recordSuccess(email: String) {
        failures[email] = nil
    }

    /// Drops stale entries now and then so the maps don't grow forever.
    private func sweep(now: Date) {
        calls += 1
        guard calls % 500 == 0 else { return }
        hits = hits.filter { $0.value.contains { now.timeIntervalSince($0) < rules.ipWindow } }
        failures = failures.filter { $0.value.contains { now.timeIntervalSince($0) < rules.lockout } }
        lockedUntil = lockedUntil.filter { $0.value > now }
    }

    static func tooMany(_ wait: TimeInterval) -> Abort {
        let seconds = Int(wait.rounded(.up))
        let minutes = max(1, Int((wait / 60).rounded(.up)))
        return Abort(.tooManyRequests, headers: ["Retry-After": String(seconds)],
                     reason: "Too many tries. Try again in \(minutes) minute\(minutes == 1 ? "" : "s").")
    }
}

/// The address a request really came from. Behind the Cloudflare Tunnel every
/// connection comes from cloudflared on this machine, so `CF-Connecting-IP` is
/// believed only when the peer is localhost; anyone else could forge it.
enum ClientIP {
    static func resolve(peer: SocketAddress?, headers: HTTPHeaders) -> String {
        guard let ip = peer?.ipAddress else { return "unknown" }
        if ip == "127.0.0.1" || ip == "::1",
           let forwarded = headers.first(name: "CF-Connecting-IP")?.trimmingCharacters(in: .whitespaces),
           !forwarded.isEmpty {
            return forwarded
        }
        return ip
    }
}

extension Request {
    var clientIP: String { ClientIP.resolve(peer: remoteAddress, headers: headers) }
}

extension Application {
    private struct LimiterKey: StorageKey { typealias Value = RateLimiter }

    var rateLimiter: RateLimiter {
        get { storage[LimiterKey.self]! }
        set { storage[LimiterKey.self] = newValue }
    }
}

/// Applies the per-address limit to the sign-in, sign-up and reset routes.
struct AuthRateLimitMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let wait = await req.application.rateLimiter.hit(ip: req.clientIP, now: req.now) {
            throw RateLimiter.tooMany(wait)
        }
        return try await next.respond(to: req)
    }
}
