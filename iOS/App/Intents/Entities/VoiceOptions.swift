import AppIntents
import Foundation
import TimeCardCore

// Fixed choices Siri can hear inside a phrase. Their titles and synonyms are the words of
// the phrase itself ("Take lunch", "How many trees"), so one App Shortcut can carry several
// natural ways to say a command. Words to be matched against speech use a straight
// apostrophe ("What's"), the way Siri writes down what it hears.

/// Lunch, or another break.
enum BreakOption: String, AppEnum {
    case lunch
    case rest

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Break" }

    static var caseDisplayRepresentations: [BreakOption: DisplayRepresentation] {
        [
            .lunch: DisplayRepresentation(title: "lunch", synonyms: ["my lunch", "lunch break", "a lunch break", "a lunch"]),
            .rest: DisplayRepresentation(title: "a break", synonyms: ["break", "my break", "a short break", "a rest"]),
        ]
    }

    var kind: BreakKind {
        switch self {
        case .lunch: .lunch
        case .rest: .break
        }
    }

    init(_ kind: BreakKind) {
        self = kind == .lunch ? .lunch : .rest
    }
}

/// The status questions. Each title is the question as people ask it.
extension StatusTopic: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Question" }

    static var caseDisplayRepresentations: [StatusTopic: DisplayRepresentation] {
        [
            .summary: DisplayRepresentation(title: "How am I doing", synonyms: ["Status", "My status", "How's my day going", "Give me an update"]),
            .hours: DisplayRepresentation(title: "How long have I worked", synonyms: ["How many hours have I worked", "How many hours", "My hours", "How long have I been working", "Hours today"]),
            .trees: DisplayRepresentation(title: "How many trees", synonyms: ["How many trees have I done", "How many trees today", "How many trees have I shaped", "My trees", "Tree count"]),
            .whereAmI: DisplayRepresentation(title: "What row am I on", synonyms: ["Where am I", "Which row am I on", "What's my row", "What row is next", "What's next"]),
            .pace: DisplayRepresentation(title: "What's my pace", synonyms: ["How fast am I going", "My pace", "Trees per hour", "What's my speed"]),
            .pay: DisplayRepresentation(title: "How much have I made", synonyms: ["How much did I make", "What have I earned", "My pay", "How much money have I made", "What's my pay"]),
        ]
    }
}

/// A flag on a tree note.
enum FlagOption: String, AppEnum {
    case noFlag = "none"
    case attention
    case dead
    case replant

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Flag" }

    static var caseDisplayRepresentations: [FlagOption: DisplayRepresentation] {
        [
            .noFlag: DisplayRepresentation(title: "No flag", synonyms: ["none", "no", "nothing", "no thanks", "skip"]),
            .attention: DisplayRepresentation(title: "Needs attention", synonyms: ["attention", "needs a look", "check it", "look at it"]),
            .dead: DisplayRepresentation(title: "Dead", synonyms: ["it's dead", "dead tree"]),
            .replant: DisplayRepresentation(title: "Replant", synonyms: ["needs replanting", "replace it"]),
        ]
    }

    var flag: NoteFlag {
        switch self {
        case .noFlag: .none
        case .attention: .attention
        case .dead: .dead
        case .replant: .replant
        }
    }
}

/// The less frequent things Siri can do, which share one App Shortcut (an app gets ten).
enum FieldTask: String, AppEnum {
    case addNote
    case noteTree
    case markTrees
    case fixStart

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Task" }

    static var caseDisplayRepresentations: [FieldTask: DisplayRepresentation] {
        [
            .addNote: DisplayRepresentation(title: "Add a note", synonyms: ["Make a note", "Take a note", "Add a shift note", "Note this"]),
            .noteTree: DisplayRepresentation(title: "Note a tree", synonyms: ["Add a tree note", "Flag a tree", "Make a note on a tree", "Tag a tree"]),
            .markTrees: DisplayRepresentation(title: "Mark trees", synonyms: ["Mark some trees", "Mark part of a row", "Mark a few trees"]),
            .fixStart: DisplayRepresentation(title: "Fix my start time", synonyms: ["Change my start time", "I started earlier", "Change when I started"]),
        ]
    }
}
