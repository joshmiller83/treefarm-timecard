import Foundation
import NIOPosix
import Vapor

/// Bcrypt on the thread pool, at the configured cost (12 in production, 4 in tests).
struct PasswordService: Sendable {
    let cost: Int
    let threadPool: NIOThreadPool

    func hash(_ password: String) async throws -> String {
        let cost = self.cost
        return try await threadPool.runIfActive { try Bcrypt.hash(password, cost: cost) }
    }

    func verify(_ password: String, hash: String) async throws -> Bool {
        try await threadPool.runIfActive { (try? Bcrypt.verify(password, created: hash)) ?? false }
    }

    /// Spends the same time as a real check, so a missing account can't be told
    /// apart from a wrong password by timing.
    func verifyNothing(_ password: String) async {
        _ = try? await verify(password, hash: Self.dummyHash)
    }

    /// A password nobody knows, for accounts that must sign in with a reset code first.
    func unusableHash() async throws -> String {
        try await hash(Codes.token())
    }

    private static let dummyHash = "$2b$04$C6UzMDM.H6dfI/f/IKxGhuJ5bdD7wq1A8Fz3W8BeUCmmYd/i9WMzG"
}

extension Application {
    var hasher: PasswordService { PasswordService(cost: config.bcryptCost, threadPool: threadPool) }
}

extension Request {
    var hasher: PasswordService { application.hasher }
}
