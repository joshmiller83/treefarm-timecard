import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// Makes the first admin and their farm: a season named for the current year (in
/// the farm's time zone) set active, an admin membership and a "Field 1". The
/// account gets an unusable password; the admin signs in with the reset code.
enum Bootstrap {
    struct Result: Sendable {
        let userId: UUID
        let farmId: UUID
        let seasonId: UUID
        let fieldId: UUID
        let resetCode: String
        let resetExpiresAt: Date
    }

    enum Failure: Error, CustomStringConvertible {
        case emailExists(String)
        case badTimeZone(String)
        case badInput(String)

        var description: String {
            switch self {
            case .emailExists(let e): "An account for \(e) already exists."
            case .badTimeZone(let tz): "\(tz) isn’t a time zone. Use an IANA name like America/Indiana/Indianapolis."
            case .badInput(let s): s
            }
        }
    }

    static func run(app: Application, email rawEmail: String, name rawName: String, farmName rawFarm: String, timeZoneId: String) async throws -> Result {
        let now = app.now
        let email: String
        let name: String
        let farmName: String
        do {
            email = try Accounts.validEmail(rawEmail)
            name = try Accounts.validName(rawName)
            farmName = try Accounts.validName(rawFarm)
        } catch let abort as any AbortError {
            throw Failure.badInput(abort.reason)
        }
        guard FarmTime.isValidZone(timeZoneId) else { throw Failure.badTimeZone(timeZoneId) }
        if try await UserModel.query(on: app.db).filter(\.$email == email).first() != nil {
            throw Failure.emailExists(email)
        }
        let passwordHash = try await app.hasher.unusableHash()

        return try await app.db.transaction { db in
            let user = UserModel(email: email, displayName: name, passwordHash: passwordHash, createdAt: now)
            try await user.create(on: db)
            let userId = user.id!

            var farm = Farm(name: farmName, timeZoneId: timeZoneId, weekStart: .monday, updatedAt: now)
            let season = Season(farmId: farm.id, name: FarmTime.yearName(now, timeZoneId: timeZoneId), startedAt: now, updatedAt: now)
            farm.activeSeasonId = season.id
            let member = Member(userId: userId, farmId: farm.id, displayName: name, email: email, role: .admin, updatedAt: now)
            let field = Field(farmId: farm.id, name: "Field 1", sortOrder: 0, updatedAt: now)

            let store = RecordStore(db: db)
            try await store.save(.farm(farm), farm: farm.id)
            try await store.save(.season(season), farm: farm.id)
            try await store.save(.member(member), farm: farm.id)
            try await store.save(.field(field), farm: farm.id)

            let reset = try await ResetCodes.issue(for: userId, on: db, now: now)
            return Result(userId: userId, farmId: farm.id, seasonId: season.id, fieldId: field.id, resetCode: reset.code, resetExpiresAt: reset.expiresAt)
        }
    }
}
