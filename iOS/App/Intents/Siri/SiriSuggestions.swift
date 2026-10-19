import Foundation
import Observation
import TimeCardCore

/// Keeps the rows, blocks and fields Siri knows by name in step with the farm, so "Mark row 14
/// in Time Card" always covers the rows ahead of you.
///
/// iOS reads them (each entity query's `suggestedEntities`) only when the app says they changed
/// (`updateAppShortcutParameters`). Once it follows the app's model, this says so whenever they
/// may have: the session opening at launch, signing in or out, switching farms, a sync bringing
/// rows other people marked, and any field action from anywhere (Siri, the lock screen, the
/// app's own buttons), since it rides on `FieldActions.onLiveSnapshot`. Bursts settle into one
/// update, and an update is only sent when what Siri can name really changed.
@MainActor
final class SiriSuggestions {
    static let shared = SiriSuggestions()

    /// Tells iOS to read the suggestions again. Tests count the calls.
    var update: @MainActor () -> Void
    /// How long to wait after a change for more of them (a sync applies many records).
    var settle: Duration

    private weak var followed: AppModel?
    private var lastNames: Names?
    private var pending: Task<Void, Never>?

    init(settle: Duration = .seconds(1), update: @escaping @MainActor () -> Void = { TimeCardShortcuts.updateAppShortcutParameters() }) {
        self.settle = settle
        self.update = update
    }

    /// What Siri can name right now: the suggested rows, blocks and fields, by id.
    struct Names: Equatable {
        var rows: [String] = []
        var blocks: [String] = []
        var fields: [String] = []

        init(_ state: FieldState?) {
            guard let state else { return }
            rows = VoiceCatalog.suggestedRows(state).map(\.id)
            blocks = VoiceCatalog.suggestedBlocks(state).map(\.id)
            fields = VoiceCatalog.fields(state).map(\.id)
        }
    }

    /// Follows `model` from now on (another model replaces the one followed before), and
    /// tells iOS what it can name now.
    func follow(_ model: AppModel) {
        guard followed !== model else { return }
        followed = model
        lastNames = nil
        let previous = model.actions.onLiveSnapshot
        model.actions.onLiveSnapshot = { [weak self, weak model] snapshot in
            previous?(snapshot)
            guard let self, let model, self.followed === model else { return }
            self.changed()
        }
        watch(model)
        changed()
    }

    /// What Siri can name may have changed: tell iOS once things settle, if it did.
    func changed() {
        pending?.cancel()
        let settle = settle
        pending = Task { [weak self] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.send(always: false)
        }
    }

    /// Tells iOS right away. An intent calls this before it returns, since iOS may suspend the
    /// app as soon as it does.
    func refreshNow() {
        pending?.cancel()
        pending = nil
        send(always: true)
    }

    /// Waits for a pending update to go out (tests).
    func settled() async {
        await pending?.value
    }

    private func send(always: Bool) {
        let names = followed.map { Names($0.actions.state()) }
        if !always, let names, names == lastNames { return }
        lastNames = names
        update()
    }

    /// Reads what the suggestions are built from (the farm, who's signed in, its records), and
    /// hears about the next change to any of it.
    private func watch(_ model: AppModel) {
        withObservationTracking {
            _ = model.actions.state()
        } onChange: { [weak self, weak model] in
            Task { @MainActor in
                guard let self, let model, self.followed === model else { return }
                self.watch(model)
                self.changed()
            }
        }
    }
}
