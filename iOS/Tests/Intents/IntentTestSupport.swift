import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// The demo farm the UI tests use (Pine Hollow): North Field has blocks 1–4, 20 rows of
/// 12 trees each, and Sam already shaped rows 1–4 of block 1. Creek Field has one block of
/// 30 rows × 8. The signed-in person is Alex Rivera, an admin paid $20 an hour.
@MainActor
enum Demo {
    static func model(signedIn: Bool = true) async -> AppModel {
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: signedIn))
        await model.start()
        if signedIn { _ = await model.session.syncNow() }
        return model
    }

    /// Siri's side of the app for that model, on an unlocked phone unless `locked`.
    static func voice(_ model: AppModel, locked: Bool = false) -> VoiceCommands {
        var voice = VoiceCommands(model: model, device: DeviceConditions(protectedDataAvailable: !locked))
        voice.onChange = {}
        return voice
    }

    static func state(_ model: AppModel) throws -> FieldState {
        try #require(model.actions.state())
    }

    static func field(_ model: AppModel, _ name: String) throws -> Field {
        try #require(model.snapshot.fields.values.first { $0.name == name })
    }

    /// A block of North Field by name ("1"…"4"), or of another field.
    static func block(_ model: AppModel, _ name: String, in fieldName: String = "North Field") throws -> Block {
        let field = try field(model, fieldName)
        return try #require(model.snapshot.blocks.values.first { $0.fieldId == field.id && $0.name == name })
    }

    /// Row `number` (counting from 1) of a North Field block.
    static func row(_ model: AppModel, _ number: Int, block name: String = "1") throws -> RowRef {
        RowRef(blockId: try block(model, name).id, row: number - 1)
    }

    static func openShift(_ model: AppModel) -> Shift? {
        guard let me = model.session.membership else { return nil }
        return model.snapshot.openShift(for: me.userId)
    }

    static func spoken(_ date: Date?, _ model: AppModel) -> String {
        guard let date, let farm = model.session.farm else { return "?" }
        return Fmt.spokenTime(date, FarmCalendar(farm: farm))
    }

    static func marks(_ model: AppModel, row: RowRef) -> Int {
        model.snapshot.marks.values.filter { $0.isLive && $0.blockId == row.blockId && $0.row == row.row }.count
    }
}

/// Answers a confirmation the way the test says, and remembers what was asked.
final class Answerer: @unchecked Sendable {
    private let lock = NSLock()
    private var _questions: [String] = []
    let answer: Bool

    init(_ answer: Bool) {
        self.answer = answer
    }

    var questions: [String] {
        lock.withLock { _questions }
    }

    var confirm: VoiceCommands.Confirm {
        { question in
            self.lock.withLock { self._questions.append(question) }
            return self.answer
        }
    }
}

/// Gives a spoken answer to a question, and remembers what was asked.
final class Speaker: @unchecked Sendable {
    private let lock = NSLock()
    private var _questions: [String] = []
    let reply: String?

    init(_ reply: String?) {
        self.reply = reply
    }

    var questions: [String] {
        lock.withLock { _questions }
    }

    var ask: VoiceCommands.Ask {
        { question in
            self.lock.withLock { self._questions.append(question) }
            return self.reply
        }
    }
}
