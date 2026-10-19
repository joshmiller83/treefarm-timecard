import Foundation
import TreeFarmKit

/// The logic behind every watch intent, Siri and the Action button alike (docs/watch.md 4.1
/// and 4.2). Each intent is a thin shell over one of these and says what it returns.
///
/// - In reach, the phone decides and its sentence is said.
/// - With the phone away, a command waits on the watch and Siri says so ("Saved on your
///   watch…"), unless the cached state shows it's bound to fail (`WatchPrecheck`, including
///   "Open Time Card on your iPhone once." with no state at all): then the refusal is said and
///   nothing is queued.
/// - A row is always the chip the watch shows (`markRow`, never `markNextRow`); with no chip,
///   the no-chip line is said and nothing is queued.
@MainActor
enum WatchVoice {
    /// What to say for what became of a command.
    static func speech(_ outcome: WatchOutcome) -> String {
        switch outcome {
        case .done(let reply), .refused(let reply): reply.speech
        case .queued: WatchDisplay.savedForSiri
        case .notSent(let text): text
        }
    }

    /// The refusal for a command the phone can't hear about and the cache shows will fail.
    static func refusal(_ command: FieldCommand, _ model: any WatchIntentModel) -> String? {
        guard model.reach != .reachable || model.displayed == nil else { return nil }
        return WatchPrecheck.refusal(for: command, state: model.displayed)
    }

    /// Runs a command: refused from the cache, or handed to the model.
    static func run(_ command: FieldCommand, _ model: any WatchIntentModel, source: WatchSource) async -> String {
        if let refusal = refusal(command, model) { return refusal }
        return speech(await model.perform(command, source: source))
    }

    static func clockIn(_ model: any WatchIntentModel, source: WatchSource) async -> String {
        await run(.clockIn(fieldId: nil), model, source: source)
    }

    /// Asks the clock-out question the watch's own way (`WatchConfirm`, the same as Siri on
    /// the phone), so it asks with the phone away too.
    static func clockOut(_ model: any WatchIntentModel, confirm: (String) async -> Bool) async -> String {
        if let refusal = refusal(.clockOut, model) { return refusal }
        if let question = model.confirmation(for: .clockOut), !(await confirm(question)) { return Speech.stillClockedIn }
        return speech(await model.perform(.clockOut, source: .siri))
    }

    /// Marks the first chip the watch shows.
    static func nextRow(_ model: any WatchIntentModel, source: WatchSource) async -> String {
        guard let state = model.displayed else { return WatchDisplay.neverConnected }
        guard state.signedIn else { return WatchDisplay.signedOut }
        if let refusal = refusal(.markNextRow, model) { return refusal }
        guard let chip = state.nextRows.first else { return WatchDisplay.noChipLine(state) }
        return speech(await model.perform(.markRow(chip.rowRef), source: source))
    }

    /// Marks a row by number, asking which when none was said, and first when it's far away.
    static func markRow(_ row: RowRef?, _ model: any WatchIntentModel,
                        askRow: () async throws -> RowRef, confirm: (String) async -> Bool) async -> String {
        guard let state = model.displayed else { return WatchDisplay.neverConnected }
        guard state.signedIn else { return WatchDisplay.signedOut }
        if let refusal = refusal(.markNextRow, model) { return refusal }
        let target: RowRef
        if let row {
            target = row
        } else {
            guard let asked = try? await askRow() else { return Speech.nothingMarked }
            target = asked
        }
        let command = FieldCommand.markRow(target)
        if let question = model.confirmation(for: command), !(await confirm(question)) { return Speech.nothingMarked }
        return speech(await model.perform(command, source: .siri))
    }

    /// Lunch if there's been none today, else a break: the Action button's pause.
    static func pause(_ model: any WatchIntentModel, source: WatchSource) async -> String {
        guard let state = model.displayed else { return WatchDisplay.neverConnected }
        return await run(.startBreak(state.hadLunchToday ? .break : .lunch, reason: ""), model, source: source)
    }

    static func undo(_ model: any WatchIntentModel) async -> String {
        speech(await model.undo())
    }

    /// Hours, trees, pace and the next row in one answer: the phone's when it answers, else
    /// the watch's cache "as of" when the phone last said.
    static func status(_ model: any WatchIntentModel, now: Date) async -> String {
        if model.reach == .reachable {
            let hours = await model.ask(.hours)
            if WatchVoiceText.isAnswer(hours) {
                let trees = await model.ask(.trees)
                if WatchVoiceText.isAnswer(trees) { return "\(hours) \(trees)" }
            }
        }
        return WatchVoiceText.cachedStatus(model.displayed, now: now)
    }

    /// A shift note, dictated.
    static func addNote(_ text: String?, _ model: any WatchIntentModel, askText: () async throws -> String) async -> String {
        if let refusal = refusal(.addShiftNote(""), model) { return refusal }
        let said: String
        if let text {
            said = text
        } else {
            guard let asked = try? await askText() else { return Speech.nothingNoted }
            said = asked
        }
        let note = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return Speech.emptyNote }
        return speech(await model.perform(.addShiftNote(note), source: .siri))
    }

    /// The Action button's first press: clock in (the workout starts through reconcile), or
    /// with a shift already on the clock, only start or attach its workout.
    static func startShift(_ model: any WatchIntentModel, attachWorkout: () -> Void) async -> String {
        if model.displayed?.isClockedIn == true {
            attachWorkout()
            return WatchDisplay.recordingYourShift
        }
        return await clockIn(model, source: .actionButton)
    }
}
