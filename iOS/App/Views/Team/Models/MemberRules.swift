import Foundation
import TimeCardCore

/// The member form as typed: role, job title and the hourly rate in dollars.
struct MemberDraft: Equatable {
    var role: Role
    var jobTitle: String
    var rateText: String

    init(_ member: Member) {
        role = member.role
        jobTitle = member.jobTitle
        rateText = member.rateCents == 0 ? "" : MemberRules.rateText(member.rateCents)
    }
}

/// Roles and rates, with the server's rules and words, checked on the phone first so an
/// admin hears "no" right away instead of from a sync rejection later.
enum MemberRules {
    static let lastAdmin = "A farm needs at least one admin. Make someone else an admin first."
    static let maxRateCents = 1_000_000
    static let rateRange = "The pay rate has to be between $0 and $10,000 an hour."
    static let rateFormat = "Enter the pay rate in dollars, like 18.50."
    static let jobTooLong = "Job titles can be up to \(Limits.name) characters."
    static let removeYourself = "You can’t remove yourself. To leave the farm, delete your account in Settings."

    /// The edit as a member record, or what to fix. Refuses to leave the farm without a
    /// current admin. Email is the account's and never changes here.
    static func save(_ draft: MemberDraft, for member: Member, members: [Member], now: Date) -> TeamEdit {
        guard let cents = parseRate(draft.rateText) else { return .problem(rateFormat) }
        guard (0...maxRateCents).contains(cents) else { return .problem(rateRange) }
        let job = draft.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard job.count <= Limits.name else { return .problem(jobTooLong) }
        if member.role == .admin, draft.role != .admin, isOnlyAdmin(member, members: members) {
            return .problem(lastAdmin)
        }
        guard draft.role != member.role || job != member.jobTitle || cents != member.rateCents else { return .unchanged }
        var saved = member
        saved.role = draft.role
        saved.jobTitle = job
        saved.rateCents = cents
        saved.updatedAt = max(now.roundedToMillisecond, member.updatedAt.addingTimeInterval(0.001))
        return .save([.member(saved)])
    }

    /// True when `member` is the farm's only current admin.
    static func isOnlyAdmin(_ member: Member, members: [Member]) -> Bool {
        member.role == .admin && member.removedAt == nil
            && !members.contains { $0.userId != member.userId && $0.role == .admin && $0.removedAt == nil }
    }

    /// The signed-in admin is about to make themself crew (they lose the Team tab).
    static func losesOwnAdmin(_ draft: MemberDraft, for member: Member, me: UUID?) -> Bool {
        member.userId == me && member.role == .admin && draft.role != .admin
    }

    /// Why `member` can't be taken off the farm, or nil when they can.
    static func removeProblem(_ member: Member, members: [Member], me: UUID?) -> String? {
        if member.removedAt != nil { return "\(member.displayName) is already off the farm." }
        if member.userId == me { return removeYourself }
        if isOnlyAdmin(member, members: members) { return lastAdmin }
        return nil
    }

    // MARK: Rates

    /// Dollars as typed ("$18.50", "18.5", "1,000", ".75") in cents. Empty is $0.
    /// Nil for anything else, including negatives and fractions of a cent.
    static func parseRate(_ text: String) -> Int? {
        let cleaned = text.filter { !$0.isWhitespace && $0 != "$" && $0 != "," }
        if cleaned.isEmpty { return 0 }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        let whole = parts[0], fraction = parts.count == 2 ? parts[1] : ""
        guard !(whole.isEmpty && fraction.isEmpty), fraction.count <= 2, whole.count <= 7 else { return nil }
        let dollars = Int(whole) ?? 0
        let cents = Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        return dollars * 100 + cents
    }

    /// Cents as the rate field shows them: "18.50", "1,234.56".
    static func rateText(_ cents: Int) -> String {
        String(Fmt.usd(cents: cents).dropFirst())
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
