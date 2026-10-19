import Foundation
import UIKit

/// What the phone itself is like right now, as far as Siri's answers care.
///
/// **How the app knows the phone is locked.** iOS seals files protected `.complete` shortly
/// after a phone with a passcode locks, and opens them again on unlock; it reports this as
/// `UIApplication.isProtectedDataAvailable`. That is the same thing that decides whether
/// someone could pick up the phone and read it, so a phone whose protected data is
/// unavailable is treated as locked. (A phone with no passcode never seals its files, and
/// counts as unlocked: there's no lock to keep anyone out.)
///
/// The limit: for up to about 10 seconds after the phone locks, or the Require Passcode
/// delay when that's longer (Settings › Face ID & Passcode), the files aren't sealed yet and
/// the phone still counts as unlocked. "How much have I made" asked right after pocketing
/// the phone in that window says the pay even with "Say pay out loud when locked" off.
///
/// The time card's own database uses the looser `completeUntilFirstUserAuthentication` class
/// so Siri can work while the phone is locked in a pocket; before the first unlock after a
/// restart even that is sealed, which is when `AppModel.storageError` is set and protected
/// data is unavailable. After that unlock, `VoiceCommands.blocker()` opens it again.
struct DeviceConditions: Equatable, Sendable {
    var protectedDataAvailable: Bool

    /// Locked with a passcode (or not yet unlocked since a restart).
    var isLocked: Bool { !protectedDataAvailable }

    @MainActor
    static func current() -> DeviceConditions {
        DeviceConditions(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
    }
}
