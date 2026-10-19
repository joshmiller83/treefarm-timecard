import ConsoleKit
import Foundation
import Vapor
@testable import App

/// Collects what a command prints.
final class CapturingConsole: Console, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var userInfo: [AnySendableHashable: any Sendable] = [:]
    var size: (width: Int, height: Int) { (120, 40) }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    func input(isSecure: Bool) -> String { "y" }

    func output(_ text: ConsoleText, newLine: Bool) {
        lock.lock(); defer { lock.unlock() }
        lines.append(text.description)
    }

    func clear(_ type: ConsoleClear) {}

    func report(error: String, newLine: Bool) {
        lock.lock(); defer { lock.unlock() }
        lines.append("ERROR: " + error)
    }
}

/// Runs `Run <args>` against the app and returns what it printed.
func runCommand(_ app: Application, _ args: [String]) async throws -> String {
    let console = CapturingConsole()
    var context = CommandContext(console: console, input: CommandInput(arguments: ["Run"] + args))
    context.application = app
    let group = AsyncCommands(commands: app.asyncCommands.commands, enableAutocomplete: false).group()
    try await console.run(group, with: context)
    return console.text
}

/// The first `XXXX-XXXX-XX` code in a command's output.
func findCode(in output: String) -> String? {
    let words = output.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    return words.first { word in word.count == 12 && word.filter { $0 == "-" }.count == 2 }
}
