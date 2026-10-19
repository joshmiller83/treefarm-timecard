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
    private var chosenFarm: Farm?
    private var chosenMembership: Member?

    @ObservationIgnored public let store: LocalStore
    @ObservationIgnored private let api: any APIClient
    @ObservationIgnored private let authService: AuthService
    @ObservationIgnored private let engineConfiguration: SyncEngine.Configuration
    @ObservationIgnored public private(set) var engine: SyncEngine?
    @ObservationIgnored private var storeListener: Task<Void, Never>?
    @ObservationIgnored private var engineListeners: [Task<Void, Never>] = []
    /// Called on the main actor for every rejection (for spoken or banner feedback).
    @ObservationIgnored public var onNotice: (@MainActor (SyncNotice) -> Void)?

    public static let farmKey = "session.farmId"

    public init(store: LocalStore, api: any APIClient, tokens: any TokenStore, deviceName: String,
                engineConfiguration: SyncEngine.Configuration = SyncEngine.Configuration()) {
        self.store = store
        self.api = api
        self.engineConfiguration = engineConfiguration
        self.authService = AuthService(api: api, tokens: tokens, cache: store, deviceName: deviceName)
        self.auth = AuthService.initialState(tokens: tokens, cache: store)
        self.snapshot = store.snapshot
        listenToStore()
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
    public var me: MeResponse? { auth.me }

    // MARK: Lifecycle

    /// Opens the store for whoever was signed in last and starts syncing. Works offline.
    public func start() async {
        listenToStore()
        auth = await authService.state
        guard let me = auth.me else { return }
        await open(me: me)
        if case .signedIn = auth {
            await engine?.requestSync(.launch)
            Task { try? await self.refreshMe() }
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

    public func signIn(email: String, password: String) async throws {
        let previous = auth.me?.user.id
        await adopt(try await authService.login(email: email, password: password), previousUser: previous)
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

    /// Signs out on the server if possible and forgets this phone's copy of the farm.
    public func signOut() async {
        await closeEngine()
        await authService.logout()
        try? store.wipe()
        auth = .signedOut
        chosenFarm = nil
        chosenMembership = nil
        snapshot = store.snapshot
        syncStatus = SyncStatus()
        latestNotice = nil
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

    public func dismissNotice() {
        latestNotice = nil
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
        let preferred = (try? store.value(forKey: Self.farmKey)).flatMap { UUID(uuidString: String(decoding: $0, as: UTF8.self)) }
        guard let chosen = Self.chooseFarm(in: me, preferred: preferred) else {
            await closeEngine()
            chosenFarm = nil
            chosenMembership = nil
            return
        }
        let farm = chosen.farm
        chosenFarm = farm
        chosenMembership = chosen.member
        guard engine?.farmId != farm.id else { return }

        await closeEngine()
        try? store.activate(farmId: farm.id)
        snapshot = store.snapshot
        let engine = SyncEngine(store: store, api: api, farmId: farm.id, configuration: engineConfiguration)
        self.engine = engine
        await engine.start()
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
        if status.phase == .signedOut, case .signedIn = auth {
            await authService.markExpired()
            auth = await authService.state
        }
    }

    private func closeEngine() async {
        engineListeners.forEach { $0.cancel() }
        engineListeners = []
        await engine?.stop()
        engine = nil
    }

    private func listenToStore() {
        guard storeListener == nil else { return }
        let events = store.events()
        storeListener = Task { [weak self] in
            for await _ in events {
                guard let self else { return }
                self.snapshot = self.store.snapshot
            }
        }
    }
}
