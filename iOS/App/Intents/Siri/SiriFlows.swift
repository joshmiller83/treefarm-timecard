import Foundation
import TimeCardCore

/// The voice commands that take more than one breath, shared by their own intents and by
/// the "notes and fixes" App Shortcut. Each checks what would stop it first (not clocked in,
/// signed out, phone not yet unlocked), so nobody answers three questions only to hear
/// "You're not clocked in", and then asks only for what wasn't already said.
enum SiriFlows {
    typealias Asker<Value> = @Sendable () async throws -> Value

    /// "Mark row 14", or "Mark a row" → "Which row?"
    static func markRow(_ row: RowEntity?, askRow: Asker<RowEntity>, confirm: @escaping VoiceCommands.Confirm) async throws -> VoiceReply {
        if let stop = await check(.marking) { return .failed(stop) }
        let target = try await value(row, or: askRow)
        return await IntentRunner.voice { await $0.markRow(target.rowRef, confirm: confirm) }
    }

    /// "Mark trees" → "Which row?" → "First tree?" → "Last tree?". Each answer is checked as
    /// soon as it's given: a row outside its block or a tree past the end of the row is said
    /// right away, and a row far away or in another block is confirmed before the trees are
    /// asked, in case Siri misheard it.
    static func markTrees(row: RowEntity?, first: Int?, last: Int?,
                          askRow: Asker<RowEntity>, askFirst: Asker<Int>, askLast: Asker<Int>,
                          confirm: @escaping VoiceCommands.Confirm) async throws -> VoiceReply {
        if let stop = await check(.marking) { return .failed(stop) }
        let target = try await value(row, or: askRow).rowRef
        if let out = await IntentRunner.voice({ $0.problem(row: target) }) { return .failed(out) }
        guard await IntentRunner.voice({ await $0.checked(target, confirm: confirm) }) else { return .failed(VoiceText.nothingMarked) }
        let from = try await value(first, or: askFirst)
        if let out = await IntentRunner.voice({ $0.problem(tree: from, in: target) }) { return .failed(out) }
        let to = try await value(last, or: askLast)
        return await IntentRunner.voice { await $0.markTrees(row: target, first: from, last: to, confirm: nil) }
    }

    /// "I'm in block 3", or "Move to another block" → "Which block?"
    static func moveTo(_ block: BlockEntity?, row: Int?, askBlock: Asker<BlockEntity>) async throws -> VoiceReply {
        if let stop = await check(.signedIn) { return .failed(stop) }
        let target = try await value(block, or: askBlock)
        return await IntentRunner.voice { await $0.moveTo(block: target.blockId, row: row) }
    }

    /// "Add a note" → "What's the note?"
    static func addNote(_ text: String?, askText: Asker<String>) async throws -> VoiceReply {
        if let stop = await check(.shiftNote) { return .failed(stop) }
        let note = try await value(given(text), or: askText)
        return await IntentRunner.voice { await $0.addNote(note) }
    }

    /// "Note a tree" → "Which tree?" → "What's the note?" → "Any flag?" The row is the one
    /// you're on unless one was named, so usually only the tree number is needed. A named row
    /// outside its block, or a tree past the end of the row, is said before the next question;
    /// a named row far away or in another block is confirmed first, in case Siri misheard it.
    static func noteTree(row: RowEntity?, tree: Int?, note: String?, flag: FlagOption?,
                         askRow: Asker<RowEntity>, askTree: Asker<Int>, askNote: Asker<String>, askFlag: Asker<FlagOption>,
                         confirm: @escaping VoiceCommands.Confirm) async throws -> VoiceReply {
        if let stop = await check(.signedIn) { return .failed(stop) }
        let here = await IntentRunner.voice { $0.currentRow() }
        let target: RowRef
        var spoken = true
        if let row { target = row.rowRef } else if let here { target = here; spoken = false } else { target = try await askRow().rowRef }
        if let out = await IntentRunner.voice({ $0.problem(row: target) }) { return .failed(out) }
        if spoken, !(await IntentRunner.voice({ await $0.checked(target, confirm: confirm) })) { return .failed(VoiceText.nothingNoted) }
        let number = try await value(tree, or: askTree)
        // A tree past the end of the row is said now, before the note is dictated.
        if let out = await IntentRunner.voice({ $0.problem(tree: number, in: target) }) { return .failed(out) }
        let body = try await value(given(note), or: askNote)
        let chosen = try await value(flag, or: askFlag)
        return await IntentRunner.voice { await $0.noteTree(row: target, tree: number, body: body, flag: chosen.flag, confirm: nil) }
    }

    /// "Fix my start time" → "What time did you start?"
    static func fixStart(_ time: Date?, askTime: Asker<Date>) async throws -> VoiceReply {
        if let stop = await check(.openShift) { return .failed(stop) }
        let spoken = try await value(time, or: askTime)
        return await IntentRunner.voice { await $0.changeStart(to: spoken) }
    }

    // MARK: -

    private static func check(_ need: VoiceCommands.Need) async -> String? {
        await IntentRunner.voice { await $0.problem(before: need) }
    }

    private static func value<Value>(_ value: Value?, or ask: Asker<Value>) async throws -> Value {
        if let value { return value }
        return try await ask()
    }

    /// Text that was really said, or nil to ask for it.
    private static func given(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
