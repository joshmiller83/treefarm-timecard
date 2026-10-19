import Foundation
import Testing
@testable import TimeCard

/// Checks the App Intents metadata Xcode builds into the app (Metadata.appintents), which
/// is exactly what iOS reads to teach Siri the phrases.
@Suite("App Shortcut phrases")
struct ShortcutPhraseTests {
    let metadata: [String: Any]

    init() throws {
        let url = try #require(Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents"),
                               "the app has no App Intents metadata")
        metadata = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    var shortcuts: [[String: Any]] {
        metadata["autoShortcuts"] as? [[String: Any]] ?? []
    }

    /// Every phrase of every App Shortcut, by intent.
    var phrases: [(intent: String, phrase: String)] {
        shortcuts.flatMap { shortcut -> [(String, String)] in
            let intent = shortcut["actionIdentifier"] as? String ?? "?"
            let templates = shortcut["phraseTemplates"] as? [[String: Any]] ?? []
            return templates.compactMap { $0["key"] as? String }.map { (intent, $0) }
        }
    }

    var actions: [String: [String: Any]] {
        metadata["actions"] as? [String: [String: Any]] ?? [:]
    }

    @Test func everyPhraseNamesTheApp() {
        #expect(phrases.count >= 60)
        for (intent, phrase) in phrases {
            #expect(phrase.contains("${applicationName}"), "\(intent): “\(phrase)” must say the app's name")
        }
    }

    @Test func noMoreThanTenAppShortcuts() {
        #expect(shortcuts.count == 10, "iOS allows an app ten App Shortcuts")
    }

    @Test func eachPhraseHasAtMostOneParameterAndIsUnique() {
        for (intent, phrase) in phrases {
            let parameters = phrase.components(separatedBy: "${").count - 2
            #expect(parameters <= 1, "\(intent): “\(phrase)”")
        }
        let all = phrases.map { $0.phrase.lowercased() }
        #expect(Set(all).count == all.count, "a phrase is used twice")
    }

    /// The commands from the plan's Siri table, said the way the voice script says them.
    @Test func everyCommandHasItsPhrase() {
        let expected: [(String, String)] = [
            ("ClockInIntent", "Clock in with ${applicationName}"),
            ("ClockInIntent", "Punch in with ${applicationName}"),
            ("ClockInIntent", "Start work with ${applicationName}"),
            ("ClockInIntent", "Start my shift in ${applicationName}"),
            ("ClockInIntent", "Clock in at ${field} with ${applicationName}"),
            ("ClockOutIntent", "Clock out with ${applicationName}"),
            ("TakeBreakIntent", "Take ${kind} with ${applicationName}"),
            ("BackToWorkIntent", "Back to work with ${applicationName}"),
            ("NextRowIntent", "Next row in ${applicationName}"),
            ("NextRowIntent", "Row done in ${applicationName}"),
            ("MarkRowByNumberIntent", "Mark ${row} in ${applicationName}"),
            ("MarkRowByNumberIntent", "Mark a row in ${applicationName}"),
            ("MoveToBlockIntent", "I'm in ${block} in ${applicationName}"),
            ("UndoIntent", "Undo in ${applicationName}"),
            ("AskTimeCardIntent", "${topic} in ${applicationName}"),
            ("FieldTaskIntent", "${task} in ${applicationName}"),
        ]
        for (intent, phrase) in expected {
            #expect(phrases.contains { $0.intent == intent && $0.phrase == phrase }, "missing “\(phrase)”")
        }
    }

    /// Field actions run with the phone locked in a pocket, and never open the app.
    @Test func everyIntentRunsLockedWithoutOpeningTheApp() {
        #expect(actions.count == 20)
        for (name, action) in actions {
            #expect(action["openAppWhenRun"] as? Bool == false, "\(name) opens the app")
            // 0 is IntentAuthenticationPolicy.alwaysAllowed, set explicitly.
            #expect(action["authenticationPolicy"] as? Int == 0, "\(name) needs the phone unlocked")
            #expect(action["isAuthPolExplicit"] as? Bool == true, "\(name)")
        }
    }

    /// The lock-screen buttons aren't offered in Shortcuts; Siri's commands are.
    @Test func onlyTheVoiceCommandsShowInShortcuts() {
        let buttons: Set = ["MarkRowIntent", "StartBreakButtonIntent", "BackToWorkButtonIntent", "UndoButtonIntent", "NextRowButtonIntent", "ClockInButtonIntent"]
        for (name, action) in actions {
            #expect(action["isDiscoverable"] as? Bool == !buttons.contains(name), "\(name)")
        }
    }

    /// Words in phrases are matched against what Siri heard, which uses a straight apostrophe.
    @Test func spokenWordsUseStraightApostrophes() {
        for (intent, phrase) in phrases {
            #expect(!phrase.contains("’"), "\(intent): “\(phrase)”")
        }
        for option in StatusTopic.allCases.map({ StatusTopic.caseDisplayRepresentations[$0] }) {
            let words = [option?.title].compactMap { $0 }.map { String(localized: $0) } + (option?.synonyms ?? []).map { String(localized: $0) }
            for word in words {
                #expect(!word.contains("’"), "\(word)")
            }
        }
    }
}
