import Fluent
import Foundation
import TreeFarmKit

/// What happened to one pushed record.
enum Outcome: Equatable {
    case applied(Int64)
    case rejected(RejectReason, String, SyncRecord? = nil)

    func result(_ mutationId: UUID) -> MutationResult {
        switch self {
        case .applied(let seq): .applied(mutationId, seq: seq)
        case .rejected(let reason, let message, let current): .rejected(mutationId, reason, message, current: current)
        }
    }
}

/// Applies one pushed record inside its own transaction: checks who may change
/// it, keeps the newer copy, enforces the farm's rules, and stores it at the next seq.
///
/// Conflict rule for every kind: if the server already has an identical copy (or
/// both are deleted) the push is answered `applied` with the stored seq. Otherwise
/// an incoming copy whose `updatedAt` isn't newer than the stored one is refused
/// as `invalid` with the stored copy in `current`, so the device can take it.
struct PushApplier {
    let db: any Database
    let farmId: UUID
    let caller: Member
    let now: Date

    var store: RecordStore { RecordStore(db: db) }
    var isAdmin: Bool { caller.role == .admin }

    func apply(_ record: SyncRecord) async throws -> Outcome {
        guard let farm = try await store.farm(farmId) else {
            return .rejected(.notFound, "That farm doesn’t exist.")
        }
        switch record {
        case .shift(let shift): return try await applyShift(shift, farm: farm)
        default: return .rejected(.invalid, "That kind of record can’t be pushed yet.")
        }
    }

    // MARK: Shared steps

    /// Settles repeats and stale copies. Nil means the incoming copy should be written.
    func settle(_ incoming: SyncRecord, against stored: StoredRecord?, noun: String) throws -> Outcome? {
        guard let stored else { return nil }
        if try ServerJSON.string(incoming) == stored.model.json { return .applied(stored.seq) }
        if incoming.deletedAt != nil && stored.record.deletedAt != nil { return .applied(stored.seq) }
        if incoming.updatedAt.millis <= stored.record.updatedAt.millis {
            return .rejected(.invalid, "A newer copy of this \(noun) is on the server.", Visibility.redact(stored.record, for: caller))
        }
        return nil
    }

    func save(_ record: SyncRecord) async throws -> Outcome {
        .applied(try await store.save(record, farm: farmId))
    }

    func name(of userId: UUID) async throws -> String {
        if userId == caller.userId { return caller.displayName }
        return try await store.member(userId, farm: farmId)?.displayName ?? "Someone"
    }

    // MARK: Shifts

    func applyShift(_ incoming: Shift, farm: Farm) async throws -> Outcome {
        guard incoming.farmId == farmId else {
            return .rejected(.forbidden, "That shift belongs to another farm.")
        }
        guard isAdmin || incoming.userId == caller.userId else {
            return .rejected(.forbidden, "You can only change your own shifts.")
        }
        let stored = try await store.find(.shift, incoming.id, farm: farmId)
        if case .shift(let old)? = stored?.record {
            guard isAdmin || old.userId == caller.userId else {
                return .rejected(.forbidden, "You can only change your own shifts.")
            }
            guard old.userId == incoming.userId else {
                return .rejected(.invalid, "A shift can’t move to another person.")
            }
        } else if try await store.member(incoming.userId, farm: farmId) == nil {
            return .rejected(.notFound, "That person isn’t on this farm.")
        }

        let shift = ShiftRules.normalized(incoming)
        if let settled = try settle(.shift(shift), against: stored, noun: "shift") { return settled }

        if shift.isLive {
            guard shift.rateCents >= 0 else { return .rejected(.invalid, "The pay rate can’t be negative.") }
            let calendar = FarmCalendar(farm: farm)
            let others = try await otherShifts(of: shift)
            if shift.isOpen, let open = others.first(where: { $0.isOpen && $0.isLive }) {
                let who = shift.userId == caller.userId ? "You’re" : "\(try await name(of: shift.userId)) is"
                return .rejected(.openShiftExists,
                                 "\(who) already clocked in (since \(Fmt.day(open.start, calendar)) at \(Fmt.time(open.start, calendar))).",
                                 .shift(open))
            }
            if let problem = ShiftRules.validate(shift, others: others, now: now, calendar: calendar, skew: Limits.clockSkew) {
                return .rejected(.invalid, problem.message)
            }
        }

        let outcome = try await save(.shift(shift))
        if !shift.isLive { try await removeMarks(onShift: shift.id) }
        return outcome
    }

    /// The same person's other live shifts that could overlap this one, plus any open one.
    func otherShifts(of shift: Shift) async throws -> [Shift] {
        let from = shift.start.addingTimeInterval(-(Limits.maxShift + 3600))
        let to = (shift.end ?? now).addingTimeInterval(Limits.clockSkew + 3600)
        return try await store.all(.shift, farm: farmId) { q in
            q.filter(\.$ownerUserId == shift.userId)
                .filter(\.$deletedAt == nil)
                .filter(\.$entityId != shift.id)
                .group(.or) { or in
                    or.filter(\.$endsAt == nil)
                    or.group(.and) { $0.filter(\.$startsAt >= from).filter(\.$startsAt <= to) }
                }
        }
        .compactMap { if case .shift(let s) = $0.record { return s }; return nil }
    }

    /// A deleted shift takes its tree marks with it, so the trees are free again.
    func removeMarks(onShift shiftId: UUID) async throws {
        let claims = try await TreeClaimModel.query(on: db).filter(\.$farmId == farmId).filter(\.$shiftId == shiftId).all()
        for claim in claims {
            if var mark = try await store.mark(claim.markId, farm: farmId) {
                mark.deletedAt = now
                mark.updatedAt = now
                try await store.save(.treeMark(mark), farm: farmId)
            }
            try await claim.delete(on: db)
        }
    }
}
