import Foundation
import Vapor

/// A command's failure, printed as a plain sentence.
struct CommandFailure: Error, CustomStringConvertible, LocalizedError {
    let description: String
    var errorDescription: String? { description }

    init(_ description: String) { self.description = description }
}

/// `Run import-artifact --farm <id> --email <user> --file <export.json>`
struct ImportArtifactCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "farm", help: "The farm's id (bootstrap prints it).")
        var farm: String?
        @Option(name: "email", help: "The person whose time card this is. They must be on the farm.")
        var email: String?
        @Option(name: "file", help: "The JSON exported from the web artifact.")
        var file: String?

        init() {}
    }

    var help: String { "Imports a time card exported from the original web artifact. Safe to run again." }

    func run(using context: CommandContext, signature: Signature) async throws {
        guard let farmText = signature.farm, let farmId = UUID(uuidString: farmText),
              let email = signature.email, let file = signature.file
        else { throw CommandFailure("Usage: Run import-artifact --farm <farm id> --email <email> --file <export.json>") }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: file))
        } catch {
            throw CommandFailure("Couldn’t read \(file).")
        }
        do {
            let summary = try await ArtifactImporter.run(app: context.application, farmId: farmId, email: email, data: data)
            summary.lines.forEach { context.console.print($0) }
        } catch let failure as ArtifactImporter.Failure {
            throw CommandFailure(failure.description)
        }
    }
}
