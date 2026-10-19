import Foundation
import Observation
import TimeCardCore

/// Whether the farm's records are still on their way from the server. Every farm starts
/// with a season and "Field 1", so before the first pull an empty list doesn't mean there
/// are none: the Team tab waits instead of offering to start a season or add a field, which
/// would move the whole crew to a new season or make a second "Field 1".
enum TeamLoading {
    static func isWaitingForFarm(snapshot: FarmSnapshot, farm: Farm?, syncStatus: SyncStatus) -> Bool {
        guard let farm else { return true }
        if let season = farm.activeSeasonId, snapshot.seasons[season] == nil { return true }
        return snapshot.fields.isEmpty && snapshot.seasons.isEmpty && syncStatus.lastSyncedAt == nil
    }

    /// The line under "Getting the farm from the server…".
    static func detail(_ status: SyncStatus) -> String {
        switch status.phase {
        case .offline: "You’re offline. The farm’s fields and seasons show up once you have signal."
        case .failed: "The server didn’t answer. Pull down to try again."
        default: "The farm’s fields and seasons show up in a moment."
        }
    }
}

/// The farm's invites, through the session's admin calls. The list never holds a code:
/// the server shows each code once, in the answer to making it.
@MainActor
@Observable
final class InvitesModel {
    private(set) var invites: [InviteInfo] = []
    private(set) var loaded = false
    private(set) var loading = false
    /// Why the list couldn't load.
    private(set) var listError: String?
    private(set) var working = false
    /// Why the last make or revoke failed.
    var error: String?
    /// When the list last came from the server.
    private(set) var loadedAt: Date?

    @ObservationIgnored private let session: TimeCardSession

    /// How old the list can get before coming back to the Crew section reloads it.
    nonisolated static let maxAge: TimeInterval = 30

    init(session: TimeCardSession) {
        self.session = session
    }

    nonisolated static func isStale(loadedAt: Date?, now: Date) -> Bool {
        guard let loadedAt else { return true }
        return now.timeIntervalSince(loadedAt) > maxAge
    }

    /// Reloads when the list is over half a minute old, so a used invite doesn't linger as open.
    func refreshIfStale(now: Date = Date()) async {
        guard Self.isStale(loadedAt: loadedAt, now: now) else { return }
        await load()
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            invites = try await session.listInvites()
            loaded = true
            loadedAt = Date()
            listError = nil
        } catch {
            listError = TeamErrors.message(error, needs: "The invite list")
        }
    }

    /// A new invite with its code, or nil (see `error`).
    func create(role: Role, note: String) async -> InviteInfo? {
        working = true
        defer { working = false }
        do {
            let made = try await session.createInvite(role: role, note: Limits.clampName(note))
            var listed = made
            listed.code = nil
            invites.removeAll { $0.id == made.id }
            invites.insert(listed, at: 0)
            error = nil
            return made
        } catch {
            self.error = TeamErrors.message(error, needs: "Making an invite")
            return nil
        }
    }

    @discardableResult
    func revoke(_ invite: InviteInfo) async -> Bool {
        working = true
        defer { working = false }
        do {
            try await session.revokeInvite(invite.id)
            invites.removeAll { $0.id == invite.id }
            error = nil
            return true
        } catch APIError.client(404, _) {
            // Already gone: the list catches up.
            invites.removeAll { $0.id == invite.id }
            return true
        } catch {
            self.error = TeamErrors.message(error, needs: "Revoking an invite")
            return false
        }
    }
}

/// Server calls about one person: a password reset code, or taking them off the farm.
@MainActor
@Observable
final class MemberActionsModel {
    private(set) var working = false
    var error: String?

    @ObservationIgnored private let session: TimeCardSession

    init(session: TimeCardSession) {
        self.session = session
    }

    func resetCode(for member: Member) async -> ResetCodeResponse? {
        working = true
        defer { working = false }
        do {
            let code = try await session.resetCode(for: member.userId)
            error = nil
            return code
        } catch {
            self.error = TeamErrors.message(error, needs: "A reset code")
            return nil
        }
    }

    /// Takes the person off the farm (their hours stay). Refused here first for yourself
    /// and for the last admin, so the server never has to say no.
    func remove(_ member: Member) async -> Bool {
        if let problem = MemberRules.removeProblem(member, members: Array(session.snapshot.members.values), me: session.me?.user.id) {
            error = problem
            return false
        }
        working = true
        defer { working = false }
        do {
            try await session.removeMember(member.userId)
            error = nil
            return true
        } catch {
            self.error = TeamErrors.message(error, needs: "Removing someone")
            return false
        }
    }
}
