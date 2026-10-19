import Foundation
import TimeCardCore

/// What an admin's edit comes to: nothing to save, a sentence saying what to fix, or the
/// records to save. Every editor on the Team tab answers with one of these, so the views
/// only show the problem or hand the records to `TimeCardSession.save(_:)`.
enum TeamEdit: Equatable {
    case unchanged
    case problem(String)
    case save([SyncRecord])
}

@MainActor
enum TeamSave {
    /// Saves the edit's records (they sync shortly after). Returns the sentence to show
    /// when the edit has a problem, nil when it saved or there was nothing to save.
    @discardableResult
    static func apply(_ edit: TeamEdit, in session: TimeCardSession) throws -> String? {
        switch edit {
        case .unchanged: return nil
        case .problem(let text): return text
        case .save(let records):
            try session.save(records)
            return nil
        }
    }
}

/// Sentences for calls that need the server (invites, reset codes, removing someone).
/// They can't wait in the outbox like edits do, so "offline" has to say so plainly.
enum TeamErrors {
    static func message(_ error: Error, needs what: String) -> String {
        if let api = error as? APIError {
            if api == .offline { return "You’re offline. \(what) needs a connection, so try again when you have signal." }
            return api.userMessage
        }
        return error.localizedDescription
    }

    /// Names: trimmed, not empty, at most `Limits.name`. The server's words.
    static func nameProblem(_ raw: String, thing: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give the \(thing) a name." }
        if name.count > Limits.name { return "Names can be up to \(Limits.name) characters." }
        return nil
    }
}

extension Role {
    /// What the app calls each role: "Admin" or "Crew".
    var teamLabel: String { self == .admin ? "Admin" : "Crew" }

    /// One line on what the role can do.
    var teamSummary: String {
        switch self {
        case .admin: "Sees everyone’s hours, runs reports, invites people and sets up fields."
        case .worker: "Clocks in, shapes trees and sees their own hours and pay."
        }
    }
}

extension Member {
    /// "Sam" for "Sam Ortiz": how the Team tab's buttons and questions name someone.
    var teamFirstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
}
