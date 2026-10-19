import Fluent
import Foundation
import TreeFarmKit
import Vapor

/// `Run bootstrap --email <e> --name <n> --farm <farm name> --tz <IANA zone>`
struct BootstrapCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "email", help: "The first admin's email.")
        var email: String?
        @Option(name: "name", help: "Their name as the crew will see it.")
        var name: String?
        @Option(name: "farm", help: "The farm's name.")
        var farm: String?
        @Option(name: "tz", help: "The farm's time zone, e.g. America/Indiana/Indianapolis.")
        var tz: String?

        init() {}
    }

    var help: String { "Makes the first admin and their farm, and prints a one-time code to sign in with." }

    func run(using context: CommandContext, signature: Signature) async throws {
        guard let email = signature.email, let name = signature.name, let farm = signature.farm, let tz = signature.tz else {
            throw CommandFailure("Usage: Run bootstrap --email <email> --name <name> --farm <farm name> --tz <time zone>")
        }
        let app = context.application
        let result: Bootstrap.Result
        do {
            result = try await Bootstrap.run(app: app, email: email, name: name, farmName: farm, timeZoneId: tz)
        } catch let failure as Bootstrap.Failure {
            throw CommandFailure(failure.description)
        }
        let calendar = FarmCalendar(timeZone: FarmTime.zone(tz), weekStart: .monday)
        context.console.print("Made \(farm) (farm id \(result.farmId.uuidString)).")
        context.console.print("\(name) <\(Accounts.normalizeEmail(email))> is its admin. Season and \"Field 1\" are ready.")
        context.console.print("In the app, choose \"I have a reset code\" and enter this code:")
        context.console.print("    \(result.resetCode)")
        context.console.print("It works once, until \(Fmt.day(result.resetExpiresAt, calendar)) at \(Fmt.time(result.resetExpiresAt, calendar)).")
    }
}

/// `Run reset-code --email <e>`: a fresh one-time sign-in code for an existing account,
/// for when the bootstrap code expired or an admin is locked out with no other admin to ask.
struct ResetCodeCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "email", help: "The account's email.")
        var email: String?

        init() {}
    }

    var help: String { "Prints a one-time code that sets a new password for an existing account." }

    func run(using context: CommandContext, signature: Signature) async throws {
        guard let raw = signature.email else { throw CommandFailure("Usage: Run reset-code --email <email>") }
        let app = context.application
        let email = Accounts.normalizeEmail(raw)
        guard let user = try await UserModel.query(on: app.db).filter(\.$email == email).first(), let userId = user.id else {
            throw CommandFailure("There's no account for \(email).")
        }
        let reset = try await ResetCodes.issue(for: userId, on: app.db, now: Date())
        context.console.print("In the app, choose \"I have a reset code\" and enter this code for \(email):")
        context.console.print("    \(reset.code)")
        context.console.print("It works once, for 24 hours. Any earlier unused code no longer works.")
    }
}

/// `Run invite --farm <id> --role worker|admin [--note <who it's for>]`
struct InviteCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "farm", help: "The farm's id.")
        var farm: String?
        @Option(name: "role", help: "worker or admin.")
        var role: String?
        @Option(name: "note", help: "Who it's for, to remember by.")
        var note: String?

        init() {}
    }

    var help: String { "Prints a single-use invite code that works for 7 days." }

    func run(using context: CommandContext, signature: Signature) async throws {
        guard let farmText = signature.farm, let farmId = UUID(uuidString: farmText),
              let roleText = signature.role, let role = Role(rawValue: roleText.lowercased())
        else { throw CommandFailure("Usage: Run invite --farm <farm id> --role worker|admin") }
        let app = context.application
        guard let farm = try await RecordStore(db: app.db).farm(farmId) else {
            throw CommandFailure("There’s no farm with that id.")
        }
        let created = try await Invites.create(on: app.db, farmId: farmId, role: role, note: signature.note ?? "", createdBy: nil, now: app.now)
        context.console.print("Invite code for \(farm.name) (\(role.rawValue)):")
        context.console.print("    \(created.code)")
        context.console.print("It works once, for 7 days.")
    }
}

/// `Run backup`
struct BackupCommand: AsyncCommand {
    struct Signature: CommandSignature {
        init() {}
    }

    var help: String { "Writes a VACUUM INTO copy to the backups folder and keeps the newest 30." }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let url = try await Backups.run(app: app)
        try await Maintenance.prune(db: app.db, now: app.now)
        context.console.print("Backed up to \(url.path). Keeping the newest \(app.config.backupsKept).")
    }
}
