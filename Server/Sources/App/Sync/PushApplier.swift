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

    /// Every rejection carries the server's copy of the record when there is one the
    /// caller may see (redacted as a pull would be), so the device can take it.
    func apply(_ record: SyncRecord) async throws -> Outcome {
        let outcome = try await applyRecord(record)
        guard case .rejected(let reason, let message, nil) = outcome,
              let stored = try await store.find(record.kind, record.entityId, farm: farmId),
              Visibility.canSee(stored.record, caller: caller)
        else { return outcome }
        return .rejected(reason, message, Visibility.redact(stored.record, for: caller))
    }

    private func applyRecord(_ record: SyncRecord) async throws -> Outcome {
        guard let farm = try await store.farm(farmId) else {
            return .rejected(.notFound, "That farm doesn’t exist.")
        }
        switch record {
        case .shift(let shift): return try await applyShift(shift, farm: farm)
        case .treeMark(let mark): return try await applyMark(mark, farm: farm)
        case .farm(let incoming): return try await applyFarm(incoming)
        case .season(let season): return try await applySeason(season)
        case .field(let field): return try await applyField(field)
        case .block(let block): return try await applyBlock(block)
        case .treeNote(let note): return try await applyNote(note)
        case .member(let member): return try await applyMember(member)
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

    // MARK: Farm, seasons, fields, blocks (admins only)

    /// Trimmed, non-empty and within `Limits.name`, or a sentence saying what's wrong.
    func checkName(_ raw: String, _ thing: String) -> (String, String?) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return (name, "Give the \(thing) a name.") }
        if name.count > Limits.name { return (name, "Names can be up to \(Limits.name) characters.") }
        return (name, nil)
    }

    func applyFarm(_ incoming: Farm) async throws -> Outcome {
        guard incoming.id == farmId else { return .rejected(.forbidden, "That isn’t the farm you’re syncing.") }
        guard isAdmin else { return .rejected(.forbidden, "Only an admin can change the farm.") }
        var farm = incoming
        let (name, problem) = checkName(farm.name, "farm")
        if let problem { return .rejected(.invalid, problem) }
        farm.name = name
        guard FarmTime.isValidZone(farm.timeZoneId) else {
            return .rejected(.invalid, "\(farm.timeZoneId) isn’t a time zone.")
        }
        if let seasonId = farm.activeSeasonId, try await store.season(seasonId, farm: farmId) == nil {
            return .rejected(.invalid, "That season isn’t on this farm.")
        }
        let stored = try await store.find(.farm, farmId, farm: farmId)
        if let settled = try settle(.farm(farm), against: stored, noun: "farm") { return settled }
        return try await save(.farm(farm))
    }

    func applySeason(_ incoming: Season) async throws -> Outcome {
        guard incoming.farmId == farmId else { return .rejected(.forbidden, "That season belongs to another farm.") }
        guard isAdmin else { return .rejected(.forbidden, "Only an admin can change seasons.") }
        var season = incoming
        let (name, problem) = checkName(season.name, "season")
        if let problem { return .rejected(.invalid, problem) }
        season.name = name
        let stored = try await store.find(.season, season.id, farm: farmId)
        if let settled = try settle(.season(season), against: stored, noun: "season") { return settled }
        return try await save(.season(season))
    }

    func applyField(_ incoming: Field) async throws -> Outcome {
        guard incoming.farmId == farmId else { return .rejected(.forbidden, "That field belongs to another farm.") }
        guard isAdmin else { return .rejected(.forbidden, "Only an admin can change fields.") }
        var field = incoming
        let (name, problem) = checkName(field.name, "field")
        if let problem, field.deletedAt == nil { return .rejected(.invalid, problem) }
        field.name = name
        let stored = try await store.find(.field, field.id, farm: farmId)
        if let settled = try settle(.field(field), against: stored, noun: "field") { return settled }
        if field.deletedAt != nil, try await !liveBlocks(inField: field.id).isEmpty {
            return .rejected(.invalid, "Remove the blocks in \(field.name) first.")
        }
        return try await save(.field(field))
    }

    /// Refuses a resize, a move to another field or a removal that would strand
    /// live marks (from any season) or notes.
    func applyBlock(_ incoming: Block) async throws -> Outcome {
        guard isAdmin else { return .rejected(.forbidden, "Only an admin can change blocks.") }
        guard let field = try await store.field(incoming.fieldId, farm: farmId) else {
            return .rejected(.notFound, "That field isn’t on this farm.")
        }
        var block = incoming
        block.name = block.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if block.deletedAt == nil {
            guard field.deletedAt == nil else { return .rejected(.invalid, "That field was deleted.") }
            if let problem = BlockEdit.validate(name: block.name, rows: block.rowCount, treesPerRow: block.treesPerRow) {
                return .rejected(.invalid, problem)
            }
            guard (0...999).contains(block.gridRow), (0...999).contains(block.gridColumn) else {
                return .rejected(.invalid, "A block’s grid row and column go from 0 to 999.")
            }
        }
        let stored = try await store.find(.block, block.id, farm: farmId)
        if let settled = try settle(.block(block), against: stored, noun: "block") { return settled }

        if case .block(let old)? = stored?.record, old.deletedAt == nil {
            let marks = try await liveMarks(inBlock: old.id)
            let notes = try await liveNotes(inBlock: old.id)
            if block.deletedAt != nil {
                if let problem = BlockEdit.checkRemove(old, marks: marks, notes: notes) {
                    return .rejected(.blockInUse, problem)
                }
            } else {
                if block.fieldId != old.fieldId, !marks.isEmpty || !notes.isEmpty {
                    return .rejected(.blockInUse, "\(old.displayName) has shaped trees or notes, so it stays in its field. Erase them first.")
                }
                if block.rowCount < old.rowCount || block.treesPerRow < old.treesPerRow,
                   let problem = BlockEdit.checkResize(old, rows: block.rowCount, treesPerRow: block.treesPerRow, marks: marks, notes: notes) {
                    return .rejected(.blockInUse, problem)
                }
            }
        }
        return try await save(.block(block))
    }

    func liveBlocks(inField fieldId: UUID) async throws -> [Block] {
        try await store.all(.block, farm: farmId) { $0.filter(\.$deletedAt == nil) }.compactMap {
            if case .block(let b) = $0.record, b.fieldId == fieldId { return b }
            return nil
        }
    }

    func liveMarks(inBlock blockId: UUID) async throws -> [TreeMark] {
        try await store.all(.treeMark, farm: farmId) { $0.filter(\.$blockId == blockId).filter(\.$deletedAt == nil) }.compactMap {
            if case .treeMark(let m) = $0.record { return m }
            return nil
        }
    }

    func liveNotes(inBlock blockId: UUID) async throws -> [TreeNote] {
        try await store.all(.treeNote, farm: farmId) { $0.filter(\.$blockId == blockId).filter(\.$deletedAt == nil) }.compactMap {
            if case .treeNote(let n) = $0.record { return n }
            return nil
        }
    }

    // MARK: Members

    static let maxRateCents = 1_000_000

    /// Workers change their own name, job title and rate; admins anyone's role,
    /// rate and removal. Email is the account's and can't be pushed. A farm always
    /// keeps at least one current admin.
    func applyMember(_ incoming: Member) async throws -> Outcome {
        guard incoming.farmId == farmId else { return .rejected(.forbidden, "That person belongs to another farm.") }
        let stored = try await store.find(.member, incoming.userId, farm: farmId)
        guard case .member(let old)? = stored?.record else {
            return .rejected(.notFound, "That person isn’t on this farm.")
        }
        var member = incoming
        member.email = old.email
        if !isAdmin {
            guard member.userId == caller.userId else {
                return .rejected(.forbidden, "Only an admin can change other people.")
            }
            guard member.role == old.role, member.removedAt?.millis == old.removedAt?.millis else {
                return .rejected(.forbidden, "Only an admin can change roles or remove people.")
            }
        }
        let (name, problem) = checkName(member.displayName, "person")
        if let problem { return .rejected(.invalid, problem == "Give the person a name." ? "Please enter a name." : problem) }
        member.displayName = name
        member.jobTitle = member.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard member.jobTitle.count <= Limits.name else {
            return .rejected(.invalid, "Job titles can be up to \(Limits.name) characters.")
        }
        guard (0...Self.maxRateCents).contains(member.rateCents) else {
            return .rejected(.invalid, "The pay rate has to be between $0 and $10,000 an hour.")
        }
        if old.removedAt != nil, member.removedAt == nil, try await UserModel.find(member.userId, on: db) == nil {
            return .rejected(.invalid, "That person deleted their account. Send them a new invite.")
        }
        if let settled = try settle(.member(member), against: stored, noun: "person") { return settled }

        let wasAdmin = old.role == .admin && old.removedAt == nil
        let staysAdmin = member.role == .admin && member.removedAt == nil
        if wasAdmin && !staysAdmin {
            let others = try await store.members(farm: farmId).filter { $0.userId != member.userId && $0.role == .admin && $0.removedAt == nil }
            if others.isEmpty {
                return .rejected(.invalid, "A farm needs at least one admin. Make someone else an admin first.")
            }
        }

        let outcome = try await save(.member(member))
        if old.removedAt == nil, member.removedAt != nil,
           try await store.activeMemberships(of: member.userId).isEmpty {
            // Removed from their last farm: sign them out everywhere.
            try await Accounts.revokeSessions(of: member.userId, on: db, now: now)
        }
        return outcome
    }

    // MARK: Tree notes

    /// Anyone writes notes, in their own name. The author edits or deletes their
    /// own; admins any. Who wrote it and when stay as the server first stored them.
    func applyNote(_ incoming: TreeNote) async throws -> Outcome {
        guard incoming.farmId == farmId else { return .rejected(.forbidden, "That note belongs to another farm.") }
        var note = incoming
        note.body = Limits.clampNotes(note.body)
        let stored = try await store.find(.treeNote, note.id, farm: farmId)
        if case .treeNote(let old)? = stored?.record {
            guard isAdmin || old.authorId == caller.userId else {
                return .rejected(.forbidden, "Only the person who wrote a note or an admin can change it.")
            }
            guard old.tree == note.tree else { return .rejected(.invalid, "A note can’t move to another tree.") }
            note.authorId = old.authorId
            note.authorName = old.authorName
            note.createdAt = old.createdAt
        } else {
            guard note.authorId == caller.userId else { return .rejected(.forbidden, "Notes are written in your own name.") }
            note.authorName = caller.displayName
        }
        guard let block = try await store.block(note.blockId, farm: farmId) else {
            return .rejected(.notFound, "That block isn’t on this farm.")
        }
        if note.isLive, block.deletedAt != nil || !block.contains(note.tree) {
            return .rejected(.invalid, "That tree isn’t in \(block.displayName).")
        }
        if let settled = try settle(.treeNote(note), against: stored, noun: "note") { return settled }
        return try await save(.treeNote(note))
    }

    // MARK: Tree marks

    /// First commit wins: a live mark claims its tree for the season, and a second
    /// mark on that tree is refused as `treeTaken` with the winner in `current`.
    func applyMark(_ incoming: TreeMark, farm: Farm) async throws -> Outcome {
        let stored = try await store.find(.treeMark, incoming.id, farm: farmId)
        if case .treeMark(let old)? = stored?.record {
            guard isAdmin || old.userId == caller.userId else {
                return .rejected(.forbidden, "You can only change marks on your own shifts.")
            }
            guard old.seasonId == incoming.seasonId, old.tree == incoming.tree else {
                return .rejected(.invalid, "A mark can’t move to another tree.")
            }
        }
        guard let season = try await store.season(incoming.seasonId, farm: farmId) else {
            return .rejected(.notFound, "That season isn’t on this farm.")
        }
        guard let block = try await store.block(incoming.blockId, farm: farmId) else {
            return .rejected(.notFound, "That block isn’t on this farm.")
        }
        guard let shift = try await store.shift(incoming.shiftId, farm: farmId) else {
            return .rejected(.notFound, "That shift isn’t on this farm.")
        }
        guard isAdmin || shift.userId == caller.userId else {
            return .rejected(.forbidden, "You can only mark trees on your own shifts.")
        }
        guard incoming.userId == shift.userId else {
            return .rejected(.invalid, "A mark belongs to the person whose shift it’s on.")
        }
        if let settled = try settle(.treeMark(incoming), against: stored, noun: "tree mark") { return settled }

        if incoming.isLive {
            guard farm.activeSeasonId == season.id else {
                return .rejected(.invalid, "Trees are marked on the current season, not \(season.name).")
            }
            guard block.deletedAt == nil, block.contains(incoming.tree) else {
                return .rejected(.invalid, "That tree isn’t in \(block.displayName). Rows go from 1 to \(block.rowCount) and trees from 1 to \(block.treesPerRow).")
            }
            guard shift.isLive else {
                return .rejected(.invalid, "That shift was deleted.")
            }
            if let holder = try await TreeClaims.claim(incoming, farm: farmId, on: db) {
                return try await taken(incoming.tree, block: block, by: holder.markId, farm: farm)
            }
        } else {
            try await TreeClaims.release(markId: incoming.id, on: db)
        }
        return try await save(.treeMark(incoming))
    }

    /// "Row 12, tree 4 in Block 2 was shaped by Sam on Oct 16."
    func taken(_ tree: TreeRef, block: Block, by markId: UUID, farm: Farm) async throws -> Outcome {
        let place = "Row \(tree.row + 1), tree \(tree.position + 1) in \(block.displayName)"
        guard let winner = try await store.mark(markId, farm: farmId) else {
            return .rejected(.treeTaken, "\(place) was already shaped.")
        }
        let who = winner.userId == caller.userId ? "you" : try await name(of: winner.userId)
        let day = Fmt.monthDay(winner.markedAt, FarmCalendar(farm: farm))
        return .rejected(.treeTaken, "\(place) was shaped by \(who) on \(day).", .treeMark(winner))
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
