import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// Sign-in, sign-up with an invite, password reset with an admin's code, sign-out.
struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("v1", "auth")
        auth.post("login", use: login)
        auth.post("register", use: register)
        auth.post("reset", use: reset)
        auth.grouped(BearerAuth()).post("logout", use: logout)
    }

    func login(req: Request) async throws -> Response {
        let body = try req.decodeJSON(LoginRequest.self)
        let email = Accounts.normalizeEmail(body.email)
        let now = req.now

        guard let user = try await UserModel.query(on: req.db).filter(\.$email == email).first() else {
            await req.hasher.verifyNothing(body.password)
            throw Abort(.unauthorized, reason: "That email and password don't match.")
        }
        guard try await req.hasher.verify(body.password, hash: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "That email and password don't match.")
        }
        let memberships = try await RecordStore(db: req.db).activeMemberships(of: user.id!)
        guard !memberships.isEmpty else {
            throw Abort(.forbidden, reason: "You're no longer on any farm. Ask an admin for a new invite.")
        }
        let token = try await Accounts.startSession(userId: user.id!, deviceName: body.deviceName, on: req.db, now: now)
        return try .json(try await Accounts.authResponse(user, token: token, on: req.db))
    }

    func register(req: Request) async throws -> Response {
        let body = try req.decodeJSON(RegisterRequest.self)
        let now = req.now
        let email = try Accounts.validEmail(body.email)
        let password = try Accounts.validPassword(body.password)
        let name = try Accounts.validName(body.displayName)
        _ = try await Invites.usable(body.inviteCode, on: req.db, now: now)

        // Someone who already has an account joins with its password.
        let existing = try await UserModel.query(on: req.db).filter(\.$email == email).first()
        let newHash: String?
        if let existing {
            guard try await req.hasher.verify(password, hash: existing.passwordHash) else {
                throw Abort(.conflict, reason: "There's already an account for that email. Use its password to join, or sign in.")
            }
            newHash = nil
        } else {
            newHash = try await req.hasher.hash(password)
        }

        let (user, token) = try await req.db.transaction { db -> (UserModel, String) in
            // Checked again inside the transaction so two sign-ups can't share a code.
            let invite = try await Invites.usable(body.inviteCode, on: db, now: now)
            let user: UserModel
            if let existing {
                user = existing
            } else {
                user = UserModel(email: email, displayName: name, passwordHash: newHash!, createdAt: now)
                try await user.create(on: db)
            }
            let store = RecordStore(db: db)
            let role = Role(rawValue: invite.role) ?? .worker
            if var member = try await store.member(user.id!, farm: invite.farmId) {
                guard member.removedAt != nil else {
                    throw Abort(.conflict, reason: "You're already on this farm. Sign in instead.")
                }
                member.removedAt = nil
                member.role = role
                member.email = email
                member.updatedAt = now
                try await store.save(.member(member), farm: invite.farmId)
            } else {
                let member = Member(userId: user.id!, farmId: invite.farmId, displayName: existing?.displayName ?? name,
                                    email: email, role: role, jobTitle: "", rateCents: 0, updatedAt: now)
                try await store.save(.member(member), farm: invite.farmId)
            }
            invite.usedAt = now
            invite.usedBy = user.id
            try await invite.save(on: db)
            let token = try await Accounts.startSession(userId: user.id!, deviceName: body.deviceName, on: db, now: now)
            return (user, token)
        }
        return try .json(try await Accounts.authResponse(user, token: token, on: req.db))
    }

    func reset(req: Request) async throws -> Response {
        let body = try req.decodeJSON(ResetPasswordRequest.self)
        let email = Accounts.normalizeEmail(body.email)
        let now = req.now
        let badCode = Abort(.badRequest, reason: "That reset code isn't right or has expired. Ask your admin for a new one.")

        guard let user = try await UserModel.query(on: req.db).filter(\.$email == email).first(),
              try await ResetCodes.usable(body.resetCode, for: user.id!, on: req.db, now: now) != nil
        else { throw badCode }
        let password = try Accounts.validPassword(body.newPassword)
        let hash = try await req.hasher.hash(password)

        let token = try await req.db.transaction { db -> String in
            guard let code = try await ResetCodes.usable(body.resetCode, for: user.id!, on: db, now: now) else { throw badCode }
            code.usedAt = now
            try await code.save(on: db)
            user.passwordHash = hash
            try await user.save(on: db)
            try await Accounts.revokeSessions(of: user.id!, on: db, now: now)
            return try await Accounts.startSession(userId: user.id!, deviceName: body.deviceName, on: db, now: now)
        }
        return try .json(try await Accounts.authResponse(user, token: token, on: req.db))
    }

    func logout(req: Request) async throws -> HTTPStatus {
        let ctx = try req.requireAuth()
        ctx.session.revokedAt = req.now
        try await ctx.session.save(on: req.db)
        return .noContent
    }
}
