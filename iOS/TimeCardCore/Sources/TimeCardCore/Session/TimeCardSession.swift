import Foundation
import Observation

/// The app's brain outside the UI: who is signed in, which farm is open, that farm's
/// records, and how syncing is going. SwiftUI reads it directly (it's `@Observable`);
/// the app's `AppModel` adds the platform glue (background tasks, network, scenes).
///
/// Everything that changes farm data goes through `save(_:)`, so later layers (field
/// actions, Siri intents, Live Activity buttons) share one path into the store and sync.
@MainActor
@Observable
public final class TimeCardSession {
    public private(set) var auth: AuthState
    public private(set) var snapshot: FarmSnapshot
    public private(set) var syncStatus = SyncStatus()
    /// The last change the server turned down, until dismissed.
    public private(set) var latestNotice: SyncNotice?
    /// True from the moment the person's role is seen to change until the farm has been
    /// pulled again under it. Until then other people's records may be the redacted copies
    /// a worker gets (no email, rate 0), so member edits wait.
    public private(set) var isCatchingUpOnRole = false
    private var chosenFarm: Farm?
    private var chosenMembership: Member?

    @ObservationIgnored public let store: LocalStore
    @ObservationIgnored private let api: any APIClient
    @ObservationIgnored private let authService: AuthService
    @ObservationIgnored private let engineConfiguration: SyncEngine.Configuration
    @ObservationIgnored public private(set) var engine: SyncEngine?
    @ObservationIgnored private var storeListener: Task<Void, Never>?
    @ObservationIgnored private var engineListeners: [Task<Void, Never>] = []
    /// The role last checked against the one the farm was pulled under.
    @ObservationIgnored private var checkedRole: (farmId: UUID, role: Role)?
    @ObservationIgnored private var roleCatchUp: Task<Void, Never>?
    /// The launch's fresh `/me`, which runs after `start()` returns. Tests wait for it.
    @ObservationIgnored public private(set) var launchRefresh: Task<Void, Never>?
    /// Called on the main actor for every rejection (for spoken or banner feedback).
    @ObservationIgnored public var onNotice: (@MainActor (SyncNotice) -> Void)?

    public nonisolated static let farmKey = "session.farmId"

    public init(store: LocalStore, api: any APIClient, tokens: any TokenStore, deviceName: String,
                engineConfiguration: SyncEngine.Configuration = SyncEngine.Configuration()) {
        self.store = store
        self.api = api
        self.engineConfiguration = engineConfiguration
        let initial = AuthService.initialState(tokens: tokens, cache: store)
        self.authService = AuthService(api: api, tokens: tokens, cache: store, deviceName: deviceName, initialState: initial)
        self.auth = initial
        self.snapshot = store.snapshot
        // The farm is known from the cached `/me` straight away, so a signed-in launch never
        // looks like "no farm" while the store opens.
        if let me = initial.me, let chosen = Self.chooseFarm(in: me, preferred: Self.preferredFarm(in: store)) {
            chosenFarm = chosen.farm
            chosenMembership = chosen.member
        }
        listenToStore()
    }

    private nonisolated static func preferredFarm(in store: LocalStore) -> UUID? {
        (try? store.value(forKey: farmKey)).flatMap { UUID(uuidString: String(decoding: $0, as: UTF8.self)) }
    }

    // MARK: What the UI reads

    /// The open farm: the synced record when there is one, else the copy from `/me`.
    public var farm: Farm? {
        guard let chosenFarm else { return nil }
        return snapshot.farmId == chosenFarm.id ? (snapshot.farm ?? chosenFarm) : chosenFarm
    }

    /// The signed-in person's place on the open farm.
    public var membership: Member? {
        guard let chosenMembership else { return nil }
        return snapshot.members[chosenMembership.userId] ?? chosenMembership
    }

    public var isAdmin: Bool { membership?.role == .admin }

    /// False until the farm's records are loaded (or it's settled there's no farm to load).
    /// The app shows a plain launch surface until then, never "No farm yet".
    public private(set) var hasOpened = false
    public var me: MeResponse? { auth.me }

    // MARK: Lifecycle

    /// Opens the store for whoever was signed in last and starts syncing. Works offline.
    public func start() async {
        listenToStore()
        auth = await authService.state
        guard let me = auth.me else {
            hasOpened = true
            return
        }
        await open(me: me)
        if case .signedIn = auth {
            await engine?.requestSync(.launch)
            launchRefresh = Task { try? await self.refreshMe() }
        } else {
            await engine?.markSignedOut()
        }
    }

    /// Stops syncing and listening (tests, or before replacing the session).
    public func stop() async {
        storeListener?.cancel()
        storeListener = nil
        await closeEngine()
    }

    // MARK: Signing in and out

    /// Signs in. `expecting` is the person whose sign-in ended (signing in again): if
    /// someone else signs in while that person's changes still wait to sync, the sign-in is
    /// taken back before anything is wiped, and the error says whose work is waiting.
    public func signIn(email: String, password: String, expecting expected: UUID? = nil) async throws {
        let previous = auth.me
        let me = try await authService.login(email: email, password: password)
        if let expected, let previous, previous.user.id == expected, me.user.id != expected,
           ((try? store.pendingCount()) ?? 0) > 0 {
            await authService.restoreExpired(previous)
            auth = await authService.state
            throw AuthError.invalid(Self.othersWorkWaiting(previous))
        }
        await adopt(me, previousUser: previous?.user.id)
    }

    /// "Josh’s changes on this phone haven’t synced yet. Sign in as josh@example.com to send them first."
    nonisolated static func othersWorkWaiting(_ me: MeResponse) -> String {
        "\(me.user.displayName)’s changes on this phone haven’t synced yet. Sign in as \(me.user.email) to send them first."
    }

    public func join(inviteCode: String, email: String, password: String, displayName: String) async throws {
        let previous = auth.me?.user.id
        await adopt(try await authService.register(inviteCode: inviteCode, email: email, password: password, displayName: displayName),
                    previousUser: previous)
    }

    public func resetPassword(email: String, code: String, newPassword: String) async throws {
        let previous = auth.me?.user.id
        await adopt(try await authService.reset(email: email, code: code, newPassword: newPassword), previousUser: previous)
    }

    /// How a sign-out went.
    public enum SignOutResult: Equatable, Sendable {
        case signedOut
        /// Nothing was forgotten: this many changes still couldn't reach the server.
        case unsynced(Int)
    }

    /// Signs out on the server if possible and forgets this phone's copy of the farm.
    /// Changes still waiting are sent first (for up to `syncLimit`); if some still can't be
    /// sent, nothing is forgotten unless `discardingUnsynced`, and the result says how many.
    @discardableResult
    public func signOut(discardingUnsynced: Bool = false, syncLimit: Duration = .seconds(10)) async -> SignOutResult {
        if ((try? store.pendingCount()) ?? 0) > 0, let engine {
            _ = await Self.within(syncLimit) { await engine.syncNow() }
        }
        let left = (try? store.pendingCount()) ?? 0
        if left > 0 && !discardingUnsynced { return .unsynced(left) }
        await closeEngine()
        await authService.logout()
        forgetFarmData()
        return .signedOut
    }

    /// The body's answer, or nil when it takes longer than `limit` (it carries on in the background).
    private static func within<T: Sendable>(_ limit: Duration, _ body: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Asks the server for the person's farms again (on launch and foreground).
    public func refreshMe() async throws {
        do {
            let me = try await authService.refreshMe()
            auth = .signedIn(me)
            await open(me: me)
        } catch {
            auth = await authService.state
            throw error
        }
    }

    /// Switches to another farm the person belongs to and remembers the choice.
    public func selectFarm(_ farmId: UUID) async {
        try? store.setValue(Data(farmId.uuidString.utf8), forKey: Self.farmKey)
        guard let me = auth.me else { return }
        await open(me: me)
        await engine?.requestSync(.manual)
    }

    // MARK: Data

    /// Saves records made on this phone; they sync shortly after.
    public func save(_ records: [SyncRecord]) throws {
        try store.save(records)
        snapshot = store.snapshot
    }

    /// Asks for a sync pass (foreground, network back, pull to refresh).
    public func requestSync(_ trigger: SyncTrigger) async {
        await engine?.requestSync(trigger)
    }

    /// Runs a pass now and waits for it (background refresh, tests).
    @discardableResult
    public func syncNow() async -> SyncOutcome {
        guard let engine else { return .signedOut }
        return await engine.syncNow()
    }

    /// Runs a pass now and waits for it, but no longer than `limit` (it carries on after).
    /// Nil when it took longer.
    @discardableResult
    public func syncNow(within limit: Duration) async -> SyncOutcome? {
        guard let engine else { return .signedOut }
        return await Self.within(limit) { await engine.syncNow() }
    }

    public func dismissNotice() {
        latestNotice = nil
    }

    // MARK: Your account

    /// Changes the person's name or password (`UpdateMeRequest`). The answer becomes the
    /// cached `/me`, and a sync brings down the renamed crew records before this returns.
    public func updateMe(_ request: UpdateMeRequest) async throws {
        let me = try await expiring { try await self.authService.updateMe(request) }
        auth = .signedIn(me)
        await open(me: me)
        _ = await engine?.syncNow()
    }

    /// Deletes the person's login. Hours still on this phone are sent first (best effort),
    /// since shifts stay with the farm; then the phone forgets the person and the farm.
    public func deleteAccount(password: String) async throws {
        if !password.isEmpty { _ = await engine?.syncNow() }
        try await expiring { try await self.authService.deleteAccount(password: password) }
        await closeEngine()
        forgetFarmData()
    }

    /// The devices signed in to this account, most recently used first. The one marked
    /// `isCurrent` is this phone; sign out with `signOut()` rather than revoking it.
    public func listSessions() async throws -> [SessionInfo] {
        try await expiring { try await self.api.sessions() }
    }

    /// Signs another device out.
    public func revokeSession(_ id: UUID) async throws {
        try await expiring { try await self.api.revokeSession(id: id) }
    }

    // MARK: Running the farm (admins)

    /// The open farm's invites, newest first, without codes.
    public func listInvites() async throws -> [InviteInfo] {
        let farmId = try openFarmId()
        return try await expiring { try await self.api.invites(farmId: farmId) }
    }

    /// A single-use invite to the open farm, good for 7 days. Its `code` is shown only now.
    public func createInvite(role: Role, note: String = "") async throws -> InviteInfo {
        let farmId = try openFarmId()
        return try await expiring { try await self.api.createInvite(farmId: farmId, CreateInviteRequest(role: role, note: note)) }
    }

    public func revokeInvite(_ id: UUID) async throws {
        let farmId = try openFarmId()
        try await expiring { try await self.api.revokeInvite(farmId: farmId, id: id) }
    }

    /// A single-use password-reset code for someone on the open farm, good for 24 hours.
    public func resetCode(for userId: UUID) async throws -> ResetCodeResponse {
        let farmId = try openFarmId()
        return try await expiring { try await self.api.resetCode(farmId: farmId, userId: userId) }
    }

    /// Takes someone off the open farm (their hours stay). A sync brings the change down
    /// before this returns, so the crew list shows it.
    public func removeMember(_ userId: UUID) async throws {
        let farmId = try openFarmId()
        try await expiring { try await self.api.removeMember(farmId: farmId, userId: userId) }
        _ = await engine?.syncNow()
    }

    /// The open farm's shifts that clock in within `[from, to)`, as the server's CSV.
    /// Workers get their own; admins one person's (`userId`) or everyone's.
    public func exportCSV(from: Date? = nil, to: Date? = nil, userId: UUID? = nil) async throws -> Data {
        let farmId = try openFarmId()
        return try await expiring { try await self.api.exportCSV(farmId: farmId, from: from, to: to, userId: userId) }
    }

    // MARK: Choosing a farm

    /// The farm to open: the remembered one if the person is still on it, else the first
    /// farm (in the server's order) where their membership is current.
    public nonisolated static func chooseFarm(in me: MeResponse, preferred: UUID?) -> (farm: Farm, member: Member)? {
        let current = me.farms.compactMap { farm -> (Farm, Member)? in
            guard let member = me.memberships.first(where: { $0.farmId == farm.id && $0.userId == me.user.id && $0.removedAt == nil }) else {
                return nil
            }
            return (farm, member)
        }
        return current.first { $0.0.id == preferred } ?? current.first
    }

    // MARK: Plumbing

    /// Runs a server call; a 401 means the sign-in ended, so the person is asked to sign in
    /// again and syncing waits, as when the sync engine hears it.
    private func expiring<T>(_ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch APIError.unauthorized(let reason) {
            await authService.markExpired()
            auth = await authService.state
            await engine?.markSignedOut()
            throw APIError.unauthorized(reason: reason)
        }
    }

    private func openFarmId() throws -> UUID {
        guard let farmId = farm?.id else { throw APIError.client(status: 403, reason: "You’re not on this farm.") }
        return farmId
    }

    /// Forgets the person's farm data on this phone (after signing out or deleting the account).
    private func forgetFarmData() {
        try? store.wipe()
        auth = .signedOut
        chosenFarm = nil
        chosenMembership = nil
        snapshot = store.snapshot
        syncStatus = SyncStatus()
        latestNotice = nil
    }

    private func adopt(_ me: MeResponse, previousUser: UUID?) async {
        if let previousUser, previousUser != me.user.id {
            // Someone else on this phone: their farm data and unsynced work aren't ours.
            await closeEngine()
            try? store.wipe(keeping: [AuthService.meKey])
            chosenFarm = nil
            chosenMembership = nil
        }
        auth = .signedIn(me)
        await open(me: me)
        await engine?.resume()
        await engine?.requestSync(.manual)
    }

    private func open(me: MeResponse) async {
        defer { hasOpened = true }
        guard let chosen = Self.chooseFarm(in: me, preferred: Self.preferredFarm(in: store)) else {
            await closeEngine()
            chosenFarm = nil
            chosenMembership = nil
            return
        }
        let farm = chosen.farm
        chosenFarm = farm
        chosenMembership = chosen.member
        reconcileRole()
        guard engine?.farmId != farm.id else { return }

        await closeEngine()
        // Decoding a season of marks takes a while: off the main thread, behind the launch surface.
        let store = self.store
        await Task.detached(priority: .userInitiated) { try? store.activate(farmId: farm.id) }.value
        // Another open (a farm switch, a fresh `/me`) may have run meanwhile; the latest one wins.
        guard chosenFarm?.id == farm.id, engine == nil else { return }
        snapshot = store.snapshot
        let engine = SyncEngine(store: store, api: api, farmId: farm.id, configuration: engineConfiguration)
        self.engine = engine
        await engine.start()
        checkedRole = nil
        reconcileRole()
        let statuses = await engine.statusUpdates()
        let notices = await engine.notices()
        engineListeners = [
            Task { [weak self] in
                for await status in statuses {
                    await self?.syncStatusChanged(status)
                }
            },
            Task { [weak self] in
                for await notice in notices {
                    self?.latestNotice = notice
                    self?.onNotice?(notice)
                }
            },
        ]
    }

    private func syncStatusChanged(_ status: SyncStatus) async {
        syncStatus = status
        // A pass that ended after the restart (which happens before `roleCatchUp` ends) pulled from 0.
        if isCatchingUpOnRole, roleCatchUp == nil, status.phase == .idle { isCatchingUpOnRole = false }
        if status.phase == .signedOut, case .signedIn = auth {
            await authService.markExpired()
            auth = await authService.state
        }
    }

    private func closeEngine() async {
        roleCatchUp?.cancel()
        roleCatchUp = nil
        isCatchingUpOnRole = false
        checkedRole = nil
        engineListeners.forEach { $0.cancel() }
        engineListeners = []
        // A pass on its way finishes (or stops) before anything is wiped or switched.
        await engine?.stopAndWait()
        engine = nil
    }

    private func listenToStore() {
        guard storeListener == nil else { return }
        let events = store.events()
        storeListener = Task { [weak self] in
            for await _ in events {
                guard let self else { return }
                self.snapshot = self.store.snapshot
                self.reconcileRole()
            }
        }
    }

    /// The server filters pulls by role, so when the person's own role changes (seen in a
    /// pulled member record or a fresh `/me`) the farm is pulled again from the start: a
    /// promoted worker gets everyone's hours and real rates, and a demoted admin's phone
    /// forgets other people's shifts.
    private func reconcileRole() {
        guard let engine, let me = membership, me.farmId == engine.farmId else { return }
        if let checked = checkedRole, checked.farmId == engine.farmId, checked.role == me.role { return }
        checkedRole = (engine.farmId, me.role)
        let farmId = engine.farmId
        let pulledAs = try? store.pulledAs(farmId: farmId)
        guard pulledAs != me.role else { return }
        try? store.setPulledAs(me.role, farmId: farmId)
        // Never checked before: only a farm already pulled (under a role we can't know) needs redoing.
        if pulledAs == nil, ((try? store.cursor(farmId: farmId)) ?? 0) == 0 { return }
        let owner = me.role == .admin ? nil : me.userId
        isCatchingUpOnRole = true
        roleCatchUp?.cancel()
        roleCatchUp = Task { [weak self] in
            let outcome = await engine.pullEverythingAgain(keepingOnlyShiftsOf: owner)
            guard let self, !Task.isCancelled else { return }
            self.roleCatchUp = nil
            if case .synced = outcome { self.isCatchingUpOnRole = false }
        }
    }
}
