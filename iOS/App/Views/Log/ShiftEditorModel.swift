import Foundation
import Observation
import TimeCardCore

/// The shift editor's state and its two writes, save and delete. Every check is
/// `ShiftRules.validate`, against the same person's other shifts, so the editor accepts
/// exactly what the server will. Writes go through `TimeCardSession.save`.
///
/// The shift can change while the editor is open (a break from the lock screen, a Siri
/// clock-out or note, a sync). Saving puts the person's edits on top of the shift as it's
/// stored then, so only what they changed is written.
@MainActor
@Observable
final class ShiftEditorModel {
    enum Stage: Equatable {
        case editing
        /// "Delete this shift?" is showing.
        case confirmingDelete
    }

    let calendar: FarmCalendar
    var draft: ShiftDraft
    /// The draft as it opened (or as the stored shift stood at the last save), to tell what
    /// the person changed.
    private(set) var initialDraft: ShiftDraft
    /// Set once the person tries to save; from then on problems show as they edit.
    private(set) var triedToSave = false
    private(set) var stage: Stage = .editing

    @ObservationIgnored private let session: TimeCardSession
    @ObservationIgnored private let now: () -> Date

    /// Nil when there's no farm open, or `shiftId` isn't on this phone.
    init?(session: TimeCardSession, shiftId: UUID?, now: @escaping () -> Date = Date.init) {
        guard let farm = session.farm, let me = session.membership else { return nil }
        let calendar = FarmCalendar(farm: farm)
        self.calendar = calendar
        self.session = session
        self.now = now
        let loaded: ShiftDraft
        if let shiftId {
            guard let shift = session.snapshot.shifts[shiftId], shift.isLive else { return nil }
            loaded = ShiftDraft(shift: shift, calendar: calendar)
        } else {
            loaded = ShiftDraft.newShift(userId: me.userId, farmId: farm.id, rateCents: me.rateCents,
                                         mine: Array(session.snapshot.shifts.values), now: now(), calendar: calendar)
        }
        draft = loaded
        initialDraft = loaded
        recountTrees()
    }

    var isNew: Bool { draft.isNew }

    /// "Editing Sam Ortiz’s shift." when an admin opens someone else's; nil for your own.
    var ownerLine: String? {
        guard draft.userId != session.membership?.userId else { return nil }
        let name = session.snapshot.members[draft.userId]?.displayName ?? "someone else"
        return "Editing \(name)’s shift."
    }
    /// The shift was open when the editor opened, so it may stay open.
    var canStayOpen: Bool { draft.original?.isOpen == true }

    // MARK: Reading

    /// The first rule the draft breaks right now, if any.
    var problem: ShiftRuleError? {
        let at = now()
        return ShiftRules.validate(draft.shift(calendar: calendar, now: at), others: others, now: at, calendar: calendar)
    }

    /// The message under the form: a storage failure, or a rule problem once a save was tried.
    var visibleProblem: String? {
        saveError ?? (triedToSave ? problem?.message : nil)
    }

    /// "8.50 hrs worked · 30 min of breaks"
    var totalsLine: String {
        let t = draft.totals(calendar: calendar, now: now())
        let worked = Fmt.decimalHours(t.worked) + " hrs worked"
        return t.breaks > 0 ? worked + " · " + Fmt.minutesText(t.breaks) + " of breaks" : worked
    }

    /// Trees the shift holds (saved shifts only), counted when the editor opened and again
    /// before deleting, so the question matches what goes.
    private(set) var trees = 0
    /// "Block 1: rows 1–12", or "".
    private(set) var treeSummary = ""

    private func recountTrees() {
        guard !isNew else { return }
        let held = ShiftTrees(snapshot: session.snapshot)
        trees = held.count(draft.id)
        treeSummary = held.summary(draft.id)
    }

    var deleteQuestion: String { ShiftMessages.deleteQuestion(trees: trees, isOpen: draft.original?.isOpen == true) }
    var deleteButton: String { ShiftMessages.deleteButton(trees: trees) }

    /// The same person's other shifts, which the rules check for overlaps.
    private var others: [Shift] {
        session.snapshot.shifts.values.filter { $0.userId == draft.userId && $0.id != draft.id }
    }

    // MARK: Editing

    func addBreak() {
        draft.breaks.append(draft.suggestedBreak(calendar: calendar, now: now()))
    }

    func removeBreak(_ id: UUID) {
        draft.breaks.removeAll { $0.id == id }
    }

    /// Clocked out, or still on the clock (only for a shift that was open).
    func setStillOnTheClock(_ open: Bool) {
        if open {
            draft.end = nil
        } else if draft.end == nil {
            let end = WallClock(now(), calendar).unpinned
            draft.end = end
            // A running break ends when the shift does, on the same day.
            var breakEnd = end
            breakEnd.dayOffset = draft.dayOffset(of: end)
            for i in draft.breaks.indices where draft.breaks[i].end == nil {
                draft.breaks[i].end = breakEnd
            }
        }
    }

    // MARK: Writing

    /// Saves when the rules allow it. Returns the sentence to show, or nil when there's a
    /// problem (then `visibleProblem` says what).
    @discardableResult
    func save() -> String? {
        triedToSave = true
        saveError = nil
        if !isNew {
            // Deleted on another device while this was open: don't bring it back.
            guard let stored = session.snapshot.shifts[draft.id], stored.isLive else {
                saveError = ShiftMessages.missing
                return nil
            }
            if stored != initialDraft.original {
                // Changed elsewhere while this was open: keep those changes under the person's.
                let current = ShiftDraft(shift: stored, calendar: calendar)
                let merged = ShiftDraft.rebase(draft, base: initialDraft, onto: current)
                draft = merged.draft
                initialDraft = current
                recountTrees()
                if merged.conflict {
                    saveError = ShiftMessages.changedElsewhere
                    return nil
                }
            }
        }
        let at = now()
        let shift = draft.shift(calendar: calendar, now: at)
        if ShiftRules.validate(shift, others: others, now: at, calendar: calendar) != nil { return nil }
        // Nothing the person changed: nothing to write (and no new `updatedAt` to win a sync).
        if !isNew && draft == initialDraft { return ShiftMessages.unchanged }
        do {
            try session.save([.shift(ShiftRules.normalized(shift))])
        } catch {
            saveError = Speech.saveFailed
            return nil
        }
        return isNew ? ShiftMessages.added : ShiftMessages.saved
    }

    /// A storage failure, shown like a rule problem.
    private(set) var saveError: String?

    func askToDelete() {
        recountTrees()
        stage = .confirmingDelete
    }

    func cancelDelete() {
        stage = .editing
    }

    /// Deletes the shift and every tree mark on it. Returns the sentence to show.
    @discardableResult
    func delete() -> String? {
        guard !isNew else { return nil }
        guard let stored = session.snapshot.shifts[draft.id], stored.isLive else {
            stage = .editing
            saveError = ShiftMessages.missing
            return nil
        }
        recountTrees()
        let at = now().roundedToMillisecond
        let trees = self.trees
        var shift = stored
        shift.deletedAt = at
        shift.updatedAt = at
        let marks = ShiftTrees.marksToDelete(onShift: stored.id, in: session.snapshot).map { mark -> SyncRecord in
            var m = mark
            m.deletedAt = at
            m.updatedAt = at
            return .treeMark(m)
        }
        do {
            try session.save([.shift(shift)] + marks)
        } catch {
            stage = .editing
            saveError = "Couldn’t delete that on this phone. Try again."
            return nil
        }
        return ShiftMessages.deleted(trees: trees)
    }
}
