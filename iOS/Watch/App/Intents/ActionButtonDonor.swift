import Foundation
import TreeFarmKit

// STUB: slice d replaces
//
// Donates the Ultra Action button's next action on every phase change (docs/watch.md 4.2):
// `MarkNextRowIntent` while working, `ResumeWorkIntent` on a break, nothing without a session.
@MainActor
final class ActionButtonDonor {
    static let shared = ActionButtonDonor()

    func update(_ displayed: WatchState?) {}
}
