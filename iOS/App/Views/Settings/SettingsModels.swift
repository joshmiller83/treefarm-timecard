import Foundation
import TimeCardCore

/// Hourly pay as people type it: "18.50", "$18.5", "18". Empty means no rate yet.
enum RateText {
    static let maxCents = 99_999

    /// Cents, or nil when it isn't a pay amount (negative, three decimals, over $999.99).
    static func parse(_ text: String) -> Int? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("$") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return 0 }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let whole = parts[0].isEmpty ? 0 : Int(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard let whole, fraction.count <= 2, !(parts[0].isEmpty && fraction.isEmpty) else { return nil }
        let cents = whole * 100 + (Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0)
        return cents <= maxCents ? cents : nil
    }

    /// "18.50", or empty for no rate.
    static func format(_ cents: Int) -> String {
        guard cents > 0 else { return "" }
        return "\(cents / 100).\(cents % 100 < 10 ? "0" : "")\(cents % 100)"
    }
}

/// Your name, job and hourly pay on this farm: your own Member record, which you may change
/// (the server lets a worker edit just these three fields of their own).
struct ProfileForm: Equatable {
    var name: String
    var job: String
    var rate: String

    init(member: Member) {
        name = member.displayName
        job = member.jobTitle
        rate = RateText.format(member.rateCents)
    }

    /// What to fix before saving, or nil.
    var problem: String? {
        if Limits.clampName(name).isEmpty { return "Add your name. It goes on your time card." }
        guard RateText.parse(rate) != nil else {
            let plain = rate.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
            if let value = Double(plain), value >= 1000 { return "Hourly pay goes up to $999.99." }
            return "Enter your hourly pay like 18.50."
        }
        return nil
    }

    func isChanged(from member: Member) -> Bool {
        guard let cents = RateText.parse(rate) else { return true }
        return Limits.clampName(name) != member.displayName || Limits.clampName(job) != member.jobTitle || cents != member.rateCents
    }

    /// The records to save: the member, and the shift you're on when the rate changed (it
    /// should pay at the new rate; finished shifts keep theirs). Empty when there's nothing
    /// to save or something to fix.
    func records(for member: Member, openShift: Shift?, now: Date) -> [SyncRecord] {
        guard problem == nil, isChanged(from: member), let cents = RateText.parse(rate) else { return [] }
        let stamp = now.roundedToMillisecond
        var updated = member
        updated.displayName = Limits.clampName(name)
        updated.jobTitle = Limits.clampName(job)
        updated.rateCents = cents
        updated.updatedAt = stamp
        var records: [SyncRecord] = [.member(updated)]
        if cents != member.rateCents, var shift = openShift, shift.rateCents != cents {
            shift.rateCents = cents
            shift.updatedAt = stamp
            records.append(.shift(shift))
        }
        return records
    }
}

/// The server address under Settings > Advanced. Saved on this phone (it outlives signing
/// out) and read when the app starts.
enum ServerAddress {
    static let defaultsKey = "server.url"

    struct Problem: Error, Equatable {
        var message: String
    }

    /// Adds https:// when it's missing and drops a trailing slash. Plain http is allowed only
    /// for this Mac (localhost or a .local name), for running the server during development.
    static func parse(_ input: String) -> Result<URL, Problem> {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(Problem(message: "Enter the server’s web address.")) }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.contains(" "), let url = URL(string: text), let scheme = url.scheme?.lowercased() else {
            return .failure(Problem(message: "That doesn’t look like a web address."))
        }
        guard scheme == "https" || scheme == "http" else { return .failure(Problem(message: "Use an https:// address.")) }
        guard let host = url.host?.lowercased(), !host.isEmpty, url.query == nil, url.fragment == nil else {
            return .failure(Problem(message: "That doesn’t look like a web address."))
        }
        if scheme == "http" && !(host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")) {
            return .failure(Problem(message: "Use an https:// address. Plain http only works for this Mac (localhost or a .local name)."))
        }
        return .success(url)
    }

    static func saved(in defaults: UserDefaults = .standard) -> URL? {
        guard let text = defaults.string(forKey: defaultsKey), case .success(let url) = parse(text),
              text.contains("://") else { return nil }
        return url
    }

    /// Nil goes back to the standard server.
    static func save(_ url: URL?, in defaults: UserDefaults = .standard) {
        if let url {
            defaults.set(url.absoluteString, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
    }
}

/// Things to say to Siri, shown in Settings. Each names the app, as Siri requires.
enum SiriPhrases {
    struct Example: Hashable {
        var phrase: String
        var does: String
    }

    static let examples: [Example] = [
        Example(phrase: "Clock in with Time Card", does: "Starts your shift and the lock-screen timer"),
        Example(phrase: "Next row in Time Card", does: "Marks your next row shaped"),
        Example(phrase: "Mark row 14 in Time Card", does: "Marks that row in the block you’re in"),
        Example(phrase: "Take lunch with Time Card", does: "Starts lunch; say “Take a break” for other breaks"),
        Example(phrase: "Back to work with Time Card", does: "Ends the break"),
        Example(phrase: "Undo in Time Card", does: "Takes back the last row, break or move"),
        Example(phrase: "I’m in block 3 in Time Card", does: "Moves where your next rows start"),
        Example(phrase: "Add a note in Time Card", does: "Adds what you say to today’s notes"),
        Example(phrase: "How many trees in Time Card?", does: "Trees today, your pace, and your row"),
        Example(phrase: "I started at 7:30 in Time Card", does: "Fixes your start time"),
        Example(phrase: "Clock out with Time Card", does: "Asks first, then ends your shift"),
    ]
}
