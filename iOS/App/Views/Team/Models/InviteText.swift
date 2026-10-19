import Foundation
import TimeCardCore

/// Words for invite and reset codes: grouped to read aloud, spelled for VoiceOver, and the
/// message that goes with a share.
enum InviteText {
    enum Status: Equatable {
        case open, used, expired
    }

    /// "K7Q4-M2XP-9R" in its three groups.
    static func groups(_ code: String) -> [String] {
        code.split(separator: "-").map(String.init)
    }

    /// One character at a time, a pause between groups: "K, 7, Q, 4. M, 2, X, P. 9, R."
    static func spelled(_ code: String) -> String {
        groups(code).map { $0.map(String.init).joined(separator: ", ") + "." }.joined(separator: " ")
    }

    static func inviteShare(code: String, farmName: String, expiresAt: Date, calendar: FarmCalendar) -> String {
        "You’re invited to \(farmName) on Time Card. Open the app, tap “Join with an invite code” and enter \(code). "
            + "It works once, until \(Fmt.day(expiresAt, calendar))."
    }

    static func resetShare(code: String, expiresAt: Date, calendar: FarmCalendar) -> String {
        "Your Time Card reset code is \(code). On the sign-in screen, tap “I have a reset code”. "
            + "It works once, until \(Fmt.day(expiresAt, calendar)) at \(Fmt.time(expiresAt, calendar))."
    }

    static func status(_ invite: InviteInfo, now: Date) -> Status {
        if invite.usedAt != nil { return .used }
        return invite.expiresAt > now ? .open : .expired
    }

    /// "Works until Tue, Oct 27", "Used Thu, Oct 15", "Expired Sat, Oct 17".
    static func statusLine(_ invite: InviteInfo, now: Date, calendar: FarmCalendar) -> String {
        switch status(invite, now: now) {
        case .open: "Works until \(Fmt.day(invite.expiresAt, calendar))"
        case .used: "Used \(Fmt.day(invite.usedAt ?? now, calendar))"
        case .expired: "Expired \(Fmt.day(invite.expiresAt, calendar))"
        }
    }
}
