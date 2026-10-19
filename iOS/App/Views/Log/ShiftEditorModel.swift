import Foundation
import Observation
import TimeCardCore

/// The shift editor's state and its two writes, save and delete. Every check is
/// `ShiftRules.validate`, against the same person's other shifts, so the editor accepts
/// exactly what the server will. Writes go through `TimeCardSession.save`.
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
    /// The draft as it opened, to tell whether anything changed.
    let initialDraft: ShiftDraft
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
    }

    var isNew: Bool { draft.isNew }
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

    /// Trees the shift holds (saved shifts only).
    var trees: Int {
        guard !isNew else { return 0 }
        return ShiftTrees(snapshot: session.snapshot).count(draft.id)
    }

    var treeSummary: String {
        guard !isNew else { return "" }
        return ShiftTrees(snapshot: session.snapshot).summary(draft.id)
    }

    var deleteQuestion: String { LogWording.deleteQuestion(trees: trees, isOpen: draft.original?.isOpen == true) }
    var deleteButton: String { LogWording.deleteButton(trees: trees) }

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
            draft.end = WallClock(now(), calendar).unpinned
            // A running break ends when the shift does.
            for i in draft.breaks.indices where draft.breaks[i].end == nil {
                draft.breaks[i].end = draft.end
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
        let at = now()
        let shift = draft.shift(calendar: calendar, now: at)
        if ShiftRules.validate(shift, others: others, now: at, calendar: calendar) != nil { return nil }
        do {
            try session.save([.shift(ShiftRules.normalized(shift))])
        } catch {
            saveError = "Couldn’t save that on this phone. Try again."
            return nil
        }
        return isNew ? LogWording.added : LogWording.saved
    }

    /// A storage failure, shown like a rule problem.
    private(set) var saveError: String?

    func askToDelete() {
        stage = .confirmingDelete
    }

    func cancelDelete() {
        stage = .editing
    }

    /// Deletes the shift and every tree mark on it. Returns the sentence to show.
    @discardableResult
    func delete() -> String? {
        guard let original = draft.original else { return nil }
        let at = now().roundedToMillisecond
        let trees = self.trees
        var shift = original
        shift.deletedAt = at
        shift.updatedAt = at
        let marks = ShiftTrees.marksToDelete(onShift: original.id, in: session.snapshot).map { mark -> SyncRecord in
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
        return LogWording.deleted(trees: trees)
    }
}
