import Foundation

/// One rule for changing someone's hourly rate, used by Settings (your own) and the Team tab
/// (an admin setting anyone's): the member record takes the new rate, the shift they're on
/// switches to it too, and finished shifts keep the rate they began with.
public enum RateChange {
    /// The note under every rate field.
    public static let footnote = "A new rate counts from the shift you’re on. Finished shifts keep the rate they began with."

    /// "The pay rate has to be between $0 and $10,000 an hour."
    public static let outOfRange = "The pay rate has to be between $0 and \(Fmt.usd(cents: Limits.maxRateCents).replacingOccurrences(of: ".00", with: "")) an hour."

    /// The records to save: `member` as edited (its new rate set here), and the person's open
    /// shift repriced when the rate changed. `now` stamps both, after what they replace.
    public static func records(member edited: Member, from old: Member, openShift: Shift?, now: Date) -> [SyncRecord] {
        var member = edited
        member.updatedAt = RecordMetadata.stamp(now, after: old.updatedAt)
        var records: [SyncRecord] = [.member(member)]
        if edited.rateCents != old.rateCents, var shift = openShift, shift.isLive, shift.isOpen,
           shift.userId == edited.userId, shift.rateCents != edited.rateCents {
            let previous = shift.updatedAt
            shift.rateCents = edited.rateCents
            shift.updatedAt = RecordMetadata.stamp(now, after: previous)
            records.append(.shift(shift))
        }
        return records
    }
}
