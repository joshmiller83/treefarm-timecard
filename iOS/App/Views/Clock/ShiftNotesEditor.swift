import Foundation
import Observation
import TimeCardCore

/// Shift notes that save themselves a moment after you stop typing. What you type is kept
/// exactly (no trimming mid-sentence); only the length is held to `Limits.notes`.
/// Notes added another way (Siri: "Add a note in Time Card") show up unless you're mid-edit.
@MainActor
@Observable
final class ShiftNotesEditor {
    enum Status: Equatable {
        /// Nothing written yet.
        case idle
        case saving
        case saved
        case failed
    }

    var text = ""
    private(set) var status: Status = .idle
    /// Writes the notes onto that shift (the view saves through the session).
    @ObservationIgnored var save: ((UUID, String) throws -> Void)?

    @ObservationIgnored private(set) var shiftId: UUID?
    @ObservationIgnored private var lastSaved = ""
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let debounce: Duration

    init(debounce: Duration = .milliseconds(800)) {
        self.debounce = debounce
    }

    /// Shows a shift's notes. The same shift's newer notes replace the text only when
    /// nothing typed here is waiting to save.
    func load(shiftId: UUID?, notes: String) {
        if shiftId != self.shiftId {
            flush()
            self.shiftId = shiftId
            text = notes
            lastSaved = notes
            status = notes.isEmpty ? .idle : .saved
            return
        }
        guard pending == nil, notes != lastSaved else { return }
        if text == lastSaved { text = notes }
        lastSaved = notes
    }

    /// Call after every keystroke.
    func edited() {
        if text.count > Limits.notes { text = String(text.prefix(Limits.notes)) }
        pending?.cancel()
        guard text != lastSaved else {
            pending = nil
            if status == .saving { status = text.isEmpty ? .idle : .saved }
            return
        }
        status = .saving
        let delay = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Saves now (before a clock action, or when the card goes away).
    func flush() {
        pending?.cancel()
        pending = nil
        guard let shiftId, text != lastSaved else { return }
        do {
            try save?(shiftId, text)
            lastSaved = text
            status = .saved
        } catch {
            status = .failed
        }
    }

    /// The shift with these notes, stamped now; nil when nothing changed.
    static func updated(_ shift: Shift, notes: String, now: Date) -> Shift? {
        let kept = String(notes.prefix(Limits.notes))
        guard kept != shift.notes else { return nil }
        var s = shift
        s.notes = kept
        s.updatedAt = now.roundedToMillisecond
        return s
    }
}

/// A short message after a tap: what Siri would have said.
struct ClockToast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var succeeded: Bool

    /// Long enough to read, short enough not to linger: 3 to 7 seconds.
    var duration: Duration {
        let seconds = min(7, max(3, 1.5 + Double(text.count) * 0.045))
        return .milliseconds(Int(seconds * 1000))
    }
}
