import Foundation

/// An in-memory stand-in for the server, used by tests and by UI-test runs of the app.
///
/// It keeps the server's promises that matter to the app: every stored record gets a
/// rising sequence number, pulls page through them, a repeated mutation id gets its
/// first answer, the first mark on a tree wins, and a person can have one open shift.
/// The account and admin routes follow docs/api.md with the server's own sentences:
/// sessions per device, single-use invite and reset codes, the last-admin rule, and a
/// CSV export like the server's. Tests can script failures and add their own rejection rules.
///
/// It plays one phone talking to the server: whoever signed in last is the caller.
public actor StubAPIClient: APIClient {
    private struct Stored {
        var seq: Int64
        var record: SyncRecord
    }

    private struct Account {
        var password: String
        var me: MeResponse
    }

    private struct Invite {
        /// As the list shows it: no code.
        var info: InviteInfo
        var farmId: UUID
        /// The farm to join, for invites added before the farm's record is stored.
        var farm: Farm?
        /// Normalized, as `normalizeCode` makes it.
        var code: String
    }

    private struct SignInSession {
        var userId: UUID
        var info: SessionInfo
    }

    private struct ResetCode {
        var code: String
        var expiresAt: Date
    }

    static let signInAgain = "Please sign in again."
    static let inviteLifetime: TimeInterval = 7 * 24 * 3600
    static let resetCodeLifetime: TimeInterval = 24 * 3600

    private var seq: Int64 = 0
    private var farms: [UUID: [EntityKey: Stored]] = [:]
    private var answered: [UUID: MutationResult] = [:]
    private var scripted: [APIError] = []
    private var losesNextPushAnswer = false
    private var accounts: [String: Account] = [:]
    private var invites: [Invite] = []
    private var resetCodes: [String: ResetCode] = [:]
    private var lockouts: [String: TimeInterval] = [:]
    private var signedIn: MeResponse?
    private var sessionList: [SignInSession] = []
    private var currentSession: UUID?
    private var clock: @Sendable () -> Date = { Date() }
    private var rejector: (@Sendable (Mutation) -> MutationResult?)?
    /// How long each pull takes (tests of a slow network).
    private var pullDelay: Duration?

    /// Calls made, for tests to inspect.
    public private(set) var pushes: [PushRequest] = []
    public private(set) var pulls: [(since: Int64, limit: Int)] = []
    public private(set) var logouts = 0

    public init() {}

    /// What a stub can start with, so it's ready without any `await` (the app's UI-test mode).
    public struct Seed: Sendable {
        public var farmId: UUID
        public var records: [SyncRecord]
        public var accounts: [Credentials]
        public var signedIn: MeResponse?
        /// Other devices signed in as `signedIn`. This phone's session is added for you
        /// unless one here is marked current.
        public var sessions: [SessionInfo]
        /// Invites on `farmId`. One without a `code` gets a made-up one.
        public var invites: [InviteInfo]

        public struct Credentials: Sendable {
            public var email: String
            public var password: String
            public var me: MeResponse

            public init(email: String, password: String, me: MeResponse) {
                self.email = email
                self.password = password
                self.me = me
            }
        }

        public init(farmId: UUID, records: [SyncRecord], accounts: [Credentials] = [], signedIn: MeResponse? = nil,
                    sessions: [SessionInfo] = [], invites: [InviteInfo] = []) {
            self.farmId = farmId
            self.records = records
            self.accounts = accounts
            self.signedIn = signedIn
            self.sessions = sessions
            self.invites = invites
        }
    }

    public init(seed: Seed) {
        var records: [EntityKey: Stored] = [:]
        var seq: Int64 = 0
        for record in seed.records {
            seq += 1
            records[EntityKey(record.kind, record.entityId)] = Stored(seq: seq, record: record)
        }
        self.seq = seq
        self.farms = [seed.farmId: records]
        self.accounts = Dictionary(seed.accounts.map { (Self.normalize($0.email), Account(password: $0.password, me: $0.me)) }) { $1 }
        self.invites = seed.invites.map { info in
            var listed = info
            listed.code = nil
            return Invite(info: listed, farmId: seed.farmId, farm: nil, code: Self.normalizeCode(info.code ?? Self.humanCode()))
        }
        self.signedIn = seed.signedIn
        if let me = seed.signedIn {
            let now = Date().roundedToMillisecond
            var sessions = seed.sessions.map { SignInSession(userId: me.user.id, info: $0) }
            if let current = sessions.first(where: \.info.isCurrent) {
                self.currentSession = current.info.id
            } else {
                let current = SessionInfo(id: UUID(), deviceName: Self.thisPhone, createdAt: now, lastUsedAt: now, isCurrent: true)
                sessions.append(SignInSession(userId: me.user.id, info: current))
                self.currentSession = current.id
            }
            self.sessionList = sessions
        }
    }

    /// The device name for sessions the stub starts on its own (seeded or `signIn(as:)`).
    static let thisPhone = "This iPhone"

    // MARK: Setting up

    /// Stores records as if other devices had pushed them.
    public func seed(farmId: UUID, _ records: [SyncRecord]) {
        for record in records { store(record, farmId: farmId) }
    }

    public func addMember(_ member: Member) {
        store(.member(member), farmId: member.farmId)
    }

    public func addAccount(email: String, password: String, me: MeResponse) {
        accounts[Self.normalize(email)] = Account(password: password, me: me)
    }

    public func addInvite(code: String, farm: Farm, role: Role = .worker, expired: Bool = false) {
        let now = now()
        let expiresAt = expired ? now.addingTimeInterval(-60) : now.addingTimeInterval(Self.inviteLifetime)
        let info = InviteInfo(id: UUID(), role: role, note: "", createdAt: now, expiresAt: expiresAt)
        invites.append(Invite(info: info, farmId: farm.id, farm: farm, code: Self.normalizeCode(code)))
    }

    public func addResetCode(_ code: String, email: String) {
        resetCodes[Self.normalize(email)] = ResetCode(code: Self.normalizeCode(code), expiresAt: now().addingTimeInterval(Self.resetCodeLifetime))
    }

    /// The time the stub stamps on what it makes (sessions, invites, removals). Defaults to now.
    public func setClock(_ now: @escaping @Sendable () -> Date) {
        clock = now
    }

    public func lockOut(email: String, for seconds: TimeInterval) {
        lockouts[Self.normalize(email)] = seconds
    }

    /// Acts as if this person is already signed in (UI-test runs start here).
    public func signIn(as me: MeResponse) {
        signedIn = me
        if sessionList.first(where: { $0.info.id == currentSession })?.userId != me.user.id {
            currentSession = startSession(userId: me.user.id, deviceName: Self.thisPhone)
        }
    }

    /// The next call throws `error` instead of answering.
    public func failNext(_ error: APIError) {
        scripted.append(error)
    }

    /// The next push is kept but its answer is lost, as when a request times out late.
    public func loseNextPushAnswer() {
        losesNextPushAnswer = true
    }

    /// Makes every pull wait this long before answering (nil: answer at once).
    public func setPullDelay(_ delay: Duration?) {
        pullDelay = delay
    }

    /// A rule run before the built-in ones; return a result to answer a mutation yourself.
    public func setRejector(_ rule: (@Sendable (Mutation) -> MutationResult?)?) {
        rejector = rule
    }

    public func record(kind: RecordKind, id: UUID) -> SyncRecord? {
        for records in farms.values {
            if let stored = records[EntityKey(kind, id)] { return stored.record }
        }
        return nil
    }

    public func records(farmId: UUID) -> [SyncRecord] {
        (farms[farmId] ?? [:]).values.sorted { $0.seq < $1.seq }.map(\.record)
    }

    // MARK: APIClient

    public func login(_ request: LoginRequest) async throws -> AuthResponse {
        try takeScripted()
        let email = Self.normalize(request.email)
        if let wait = lockouts[email] {
            throw APIError.rateLimited(reason: "Too many tries. Try again in \(Int((wait / 60).rounded(.up))) minutes.", retryAfter: wait)
        }
        guard let account = accounts[email], account.password == request.password else {
            throw APIError.unauthorized(reason: "That email and password don’t match.")
        }
        guard account.me.memberships.contains(where: { (member($0.userId, farmId: $0.farmId) ?? $0).removedAt == nil }) else {
            throw APIError.client(status: 403, reason: "You’re no longer on any farm. Ask an admin for a new invite.")
        }
        return signIn(account.me, deviceName: request.deviceName)
    }

    public func register(_ request: RegisterRequest) async throws -> AuthResponse {
        try takeScripted()
        let code = Self.normalizeCode(request.inviteCode)
        guard let index = invites.firstIndex(where: { $0.code == code }) else {
            throw APIError.client(status: 400, reason: "That invite code isn’t valid. Ask your admin for a new one.")
        }
        let invite = invites[index]
        guard invite.info.usedAt == nil else {
            throw APIError.client(status: 400, reason: "That invite code was already used. Ask your admin for a new one.")
        }
        let now = now()
        guard invite.info.expiresAt > now else {
            throw APIError.client(status: 400, reason: "That invite code has expired. Ask your admin for a new one.")
        }
        guard let farm = farmRecord(invite.farmId) ?? invite.farm else {
            throw APIError.client(status: 400, reason: "That invite code isn’t valid. Ask your admin for a new one.")
        }
        let email = Self.normalize(request.email)
        guard accounts[email] == nil else {
            throw APIError.client(status: 409, reason: "There’s already an account for that email. Sign in instead.")
        }
        let user = UserProfile(id: UUID(), email: email, displayName: request.displayName)
        let member = Member(userId: user.id, farmId: farm.id, displayName: user.displayName, email: email, role: invite.info.role, updatedAt: now)
        store(.member(member), farmId: farm.id)
        let me = MeResponse(user: user, farms: [farm], memberships: [member])
        accounts[email] = Account(password: request.password, me: me)
        invites[index].info.usedAt = now
        return signIn(me, deviceName: request.deviceName)
    }

    public func resetPassword(_ request: ResetPasswordRequest) async throws -> AuthResponse {
        try takeScripted()
        let email = Self.normalize(request.email)
        guard let code = resetCodes[email], code.code == Self.normalizeCode(request.resetCode), code.expiresAt > now(),
              var account = accounts[email] else {
            throw APIError.client(status: 400, reason: "That reset code isn’t right or has expired. Ask your admin for a new one.")
        }
        account.password = request.newPassword
        accounts[email] = account
        resetCodes[email] = nil
        // A reset ends every other session.
        sessionList.removeAll { $0.userId == account.me.user.id }
        return signIn(account.me, deviceName: request.deviceName)
    }

    public func logout() async throws {
        try takeScripted()
        logouts += 1
        sessionList.removeAll { $0.info.id == currentSession }
        signedIn = nil
        currentSession = nil
    }

    public func me() async throws -> MeResponse {
        try takeScripted()
        return try caller()
    }

    public func push(farmId: UUID, _ request: PushRequest) async throws -> PushResponse {
        try takeScripted()
        pushes.append(request)
        let results = request.mutations.map { apply($0, farmId: farmId) }
        if losesNextPushAnswer {
            losesNextPushAnswer = false
            throw APIError.offline
        }
        return PushResponse(results: results)
    }

    public func pull(farmId: UUID, since: Int64, limit: Int) async throws -> PullResponse {
        try takeScripted()
        pulls.append((since, limit))
        if let pullDelay { try await Task.sleep(for: pullDelay) }
        // Like the server: workers see their own shifts only, and other people's email and
        // rate come back blank. (A pull with nobody signed in, in engine tests, sees everything.)
        let viewer = signedIn == nil ? nil : try? member(on: farmId)
        let newer = (farms[farmId] ?? [:]).values.filter { $0.seq > since }.sorted { $0.seq < $1.seq }
        let page = newer.prefix(limit)
        let visible = page.compactMap { stored -> Change? in
            guard let viewer else { return Change(seq: stored.seq, record: stored.record) }
            guard Self.canSee(stored.record, viewer: viewer) else { return nil }
            return Change(seq: stored.seq, record: Self.redact(stored.record, for: viewer))
        }
        return PullResponse(changes: visible, cursor: page.last?.seq ?? max(since, 0), hasMore: newer.count > page.count)
    }

    /// The server's `Visibility.canSee`: admins see everything, workers their own shifts.
    static func canSee(_ record: SyncRecord, viewer: Member) -> Bool {
        if viewer.role == .admin { return true }
        if case .shift(let shift) = record { return shift.userId == viewer.userId }
        return true
    }

    /// The server's `Visibility.redact`: a worker gets other people's email and rate blank.
    static func redact(_ record: SyncRecord, for viewer: Member) -> SyncRecord {
        guard viewer.role != .admin, case .member(var member) = record, member.userId != viewer.userId else { return record }
        member.email = ""
        member.rateCents = 0
        return .member(member)
    }

    // MARK: Your account

    public func updateMe(_ request: UpdateMeRequest) async throws -> MeResponse {
        try takeScripted()
        var me = try caller()
        let name = try request.displayName.map(Self.validName)
        var newPassword: String?
        if let new = request.newPassword {
            guard let current = request.currentPassword, !current.isEmpty else {
                throw APIError.client(status: 400, reason: "Enter your current password to change it.")
            }
            guard let email = accountEmail(for: me.user.id), accounts[email]?.password == current else {
                throw APIError.client(status: 403, reason: "Your current password isn’t right.")
            }
            newPassword = try Self.validPassword(new)
        }

        let now = now()
        if let name, name != me.user.displayName {
            me.user.displayName = name
            // The name reaches every farm the person is on, as member changes that sync.
            for var member in activeMemberships(of: me.user.id) where member.displayName != name {
                member.displayName = name
                member.updatedAt = now
                store(.member(member), farmId: member.farmId)
            }
            me.memberships = me.memberships.map { listed in
                if let stored = member(listed.userId, farmId: listed.farmId) { return stored }
                var renamed = listed
                renamed.displayName = name
                return renamed
            }
        }
        if let email = accountEmail(for: me.user.id) {
            accounts[email]?.me = me
            if let newPassword {
                accounts[email]?.password = newPassword
                // Every other device signs in again.
                sessionList.removeAll { $0.userId == me.user.id && $0.info.id != currentSession }
            }
        }
        signedIn = me
        return me
    }

    public func deleteAccount(_ request: DeleteAccountRequest) async throws {
        try takeScripted()
        let me = try caller()
        guard let email = accountEmail(for: me.user.id), accounts[email]?.password == request.password else {
            throw APIError.client(status: 403, reason: "That password isn’t right.")
        }
        let memberships = activeMemberships(of: me.user.id)
        for membership in memberships where membership.role == .admin {
            let others = members(farmId: membership.farmId).filter { $0.userId != me.user.id && $0.removedAt == nil }
            if !others.isEmpty && !others.contains(where: { $0.role == .admin }) {
                let farmName = farmRecord(membership.farmId)?.name ?? me.farms.first { $0.id == membership.farmId }?.name ?? "your farm"
                throw APIError.client(status: 409, reason: "You’re the only admin of \(farmName). Make someone else an admin first.")
            }
        }
        // Shifts stay with the farm: the membership keeps the name but not the email.
        let now = now()
        for var member in memberships {
            member.removedAt = now
            member.email = ""
            member.updatedAt = now
            store(.member(member), farmId: member.farmId)
        }
        accounts[email] = nil
        resetCodes[email] = nil
        sessionList.removeAll { $0.userId == me.user.id }
        signedIn = nil
        currentSession = nil
    }

    public func sessions() async throws -> [SessionInfo] {
        try takeScripted()
        let me = try caller()
        return sessionList
            .filter { $0.userId == me.user.id }
            .map { session in
                var info = session.info
                info.isCurrent = info.id == currentSession
                return info
            }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    public func revokeSession(id: UUID) async throws {
        try takeScripted()
        let me = try caller()
        guard let index = sessionList.firstIndex(where: { $0.info.id == id && $0.userId == me.user.id }) else {
            throw APIError.client(status: 404, reason: "That session isn’t signed in anymore.")
        }
        sessionList.remove(at: index)
        if id == currentSession {
            signedIn = nil
            currentSession = nil
        }
    }

    // MARK: Admin

    public func invites(farmId: UUID) async throws -> [InviteInfo] {
        try takeScripted()
        _ = try admin(on: farmId)
        return invites.filter { $0.farmId == farmId }.map(\.info).sorted { $0.createdAt > $1.createdAt }
    }

    public func createInvite(farmId: UUID, _ request: CreateInviteRequest) async throws -> InviteInfo {
        try takeScripted()
        _ = try admin(on: farmId)
        let now = now()
        let code = Self.humanCode()
        let info = InviteInfo(id: UUID(), role: request.role, note: Limits.clampName(request.note), createdAt: now,
                              expiresAt: now.addingTimeInterval(Self.inviteLifetime))
        invites.append(Invite(info: info, farmId: farmId, farm: nil, code: Self.normalizeCode(code)))
        var answer = info
        answer.code = code
        return answer
    }

    public func revokeInvite(farmId: UUID, id: UUID) async throws {
        try takeScripted()
        _ = try admin(on: farmId)
        guard let index = invites.firstIndex(where: { $0.info.id == id && $0.farmId == farmId }) else {
            throw APIError.client(status: 404, reason: "That invite is already gone.")
        }
        invites.remove(at: index)
    }

    public func resetCode(farmId: UUID, userId: UUID) async throws -> ResetCodeResponse {
        try takeScripted()
        _ = try admin(on: farmId)
        guard let member = self.member(userId, farmId: farmId), member.removedAt == nil, let email = accountEmail(for: userId) else {
            throw APIError.client(status: 404, reason: "That person isn’t on this farm.")
        }
        let code = Self.humanCode()
        let expiresAt = now().addingTimeInterval(Self.resetCodeLifetime)
        resetCodes[email] = ResetCode(code: Self.normalizeCode(code), expiresAt: expiresAt)
        return ResetCodeResponse(code: code, expiresAt: expiresAt)
    }

    public func removeMember(farmId: UUID, userId: UUID) async throws {
        try takeScripted()
        _ = try admin(on: farmId)
        guard var member = self.member(userId, farmId: farmId) else {
            throw APIError.client(status: 404, reason: "That person isn’t on this farm.")
        }
        guard member.removedAt == nil else { return }
        if member.role == .admin, !members(farmId: farmId).contains(where: { $0.userId != userId && $0.role == .admin && $0.removedAt == nil }) {
            throw APIError.client(status: 409, reason: "A farm needs at least one admin. Make someone else an admin first.")
        }
        let now = now()
        member.removedAt = now
        member.updatedAt = max(now, member.updatedAt.addingTimeInterval(0.001))
        store(.member(member), farmId: farmId)

        // Their `/me` no longer lists the farm.
        func dropping(_ me: MeResponse) -> MeResponse {
            guard me.user.id == userId else { return me }
            var me = me
            me.memberships.removeAll { $0.farmId == farmId }
            me.farms.removeAll { $0.id == farmId }
            return me
        }
        if let email = accountEmail(for: userId), let account = accounts[email] {
            accounts[email]?.me = dropping(account.me)
        }
        signedIn = signedIn.map(dropping)
    }

    // MARK: Export

    /// The server's CSV: shifts clocking in within `[from, to)`, by start then name,
    /// with dates and times in the farm's time zone.
    public func exportCSV(farmId: UUID, from: Date? = nil, to: Date? = nil, userId: UUID? = nil) async throws -> Data {
        try takeScripted()
        let caller = try member(on: farmId)
        var userId = userId
        if caller.role != .admin {
            if let userId, userId != caller.userId {
                throw APIError.client(status: 403, reason: "You can only export your own hours.")
            }
            userId = caller.userId
        }
        guard let farm = farmRecord(farmId) else { throw APIError.client(status: 404, reason: "That farm doesn’t exist.") }

        let now = now()
        let names = Dictionary(members(farmId: farmId).map { ($0.userId, $0.displayName) }) { first, _ in first }
        let calendar = FarmCalendar(farm: farm)
        let rows = (farms[farmId] ?? [:]).values
            .compactMap { stored -> Shift? in
                guard case .shift(let shift) = stored.record else { return nil }
                return shift
            }
            .filter { shift in
                shift.deletedAt == nil && (userId == nil || shift.userId == userId)
                    && (from.map { shift.start >= $0 } ?? true) && (to.map { shift.start < $0 } ?? true)
            }
            .map { (shift: $0, name: names[$0.userId] ?? "Unknown") }
            .sorted { ($0.shift.start, $0.name) < ($1.shift.start, $1.name) }

        var csv = Self.csvRow(["Name", "Date", "In", "Out", "Breaks", "Hours", "Notes"])
        for (shift, name) in rows {
            let day = calendar.dayKey(shift.start)
            csv += Self.csvRow([
                name,
                "\(day.year)-\(Self.pad2(day.month))-\(Self.pad2(day.day))",
                Fmt.time(shift.start, calendar),
                shift.end.map { Fmt.time($0, calendar) } ?? "",
                String(Int((shift.breakTime(at: now) / 60).rounded())),
                Fmt.decimalHours(shift.workedTime(at: now)),
                shift.notes,
            ])
        }
        return Data(csv.utf8)
    }

    // MARK: Rules

    private func apply(_ mutation: Mutation, farmId: UUID) -> MutationResult {
        if let earlier = answered[mutation.id] { return earlier }
        let result = judge(mutation, farmId: farmId) ?? .applied(mutation.id, seq: store(mutation.record, farmId: farmId))
        answered[mutation.id] = result
        return result
    }

    private func judge(_ mutation: Mutation, farmId: UUID) -> MutationResult? {
        if let rejector, let result = rejector(mutation) { return result }
        let records = farms[farmId] ?? [:]
        switch mutation.record {
        case .treeMark(let mark) where mark.isLive:
            let winner = records.values.lazy.compactMap { stored -> TreeMark? in
                guard case .treeMark(let other) = stored.record else { return nil }
                return other
            }.first { $0.isLive && $0.id != mark.id && $0.seasonId == mark.seasonId && $0.tree == mark.tree }
            if let winner {
                return .rejected(mutation.id, .treeTaken, takenMessage(winner, farmId: farmId), current: .treeMark(winner))
            }
        case .shift(let shift) where shift.isLive && shift.isOpen:
            let open = records.values.lazy.compactMap { stored -> Shift? in
                guard case .shift(let other) = stored.record else { return nil }
                return other
            }.first { $0.isLive && $0.isOpen && $0.userId == shift.userId && $0.id != shift.id }
            if let open {
                return .rejected(mutation.id, .openShiftExists, "You’re already clocked in on another shift.", current: .shift(open))
            }
        default:
            break
        }
        return nil
    }

    private func takenMessage(_ mark: TreeMark, farmId: UUID) -> String {
        let records = farms[farmId] ?? [:]
        var name = "someone else"
        if case .member(let member)? = records[EntityKey(.member, mark.userId)]?.record { name = member.displayName }
        var timeZone = TimeZone(identifier: "UTC")!
        if case .farm(let farm)? = records[EntityKey(.farm, farmId)]?.record { timeZone = farm.timeZone }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d"
        return "Row \(mark.row + 1), tree \(mark.position + 1) was shaped by \(name) on \(formatter.string(from: mark.markedAt))."
    }

    // MARK: Helpers

    @discardableResult
    private func store(_ record: SyncRecord, farmId: UUID) -> Int64 {
        seq += 1
        farms[farmId, default: [:]][EntityKey(record.kind, record.entityId)] = Stored(seq: seq, record: record)
        return seq
    }

    private func signIn(_ me: MeResponse, deviceName: String) -> AuthResponse {
        signedIn = me
        currentSession = startSession(userId: me.user.id, deviceName: deviceName)
        return AuthResponse(token: "stub-\(UUID().uuidString)", me: me)
    }

    private func startSession(userId: UUID, deviceName: String) -> UUID {
        let now = now()
        let name = Limits.clampName(deviceName)
        let info = SessionInfo(id: UUID(), deviceName: name.isEmpty ? "Unknown device" : name, createdAt: now, lastUsedAt: now, isCurrent: false)
        sessionList.append(SignInSession(userId: userId, info: info))
        return info.id
    }

    /// Who is calling. Like the server, use slides the session's last-used time (once a minute at most).
    private func caller() throws -> MeResponse {
        guard let signedIn else { throw APIError.unauthorized(reason: Self.signInAgain) }
        let now = now()
        if let index = sessionList.firstIndex(where: { $0.info.id == currentSession }),
           now.timeIntervalSince(sessionList[index].info.lastUsedAt) > 60 {
            sessionList[index].info.lastUsedAt = now
        }
        return signedIn
    }

    /// The caller's current membership of a farm, or the server's 403.
    private func member(on farmId: UUID) throws -> Member {
        let me = try caller()
        let listed = me.memberships.first { $0.farmId == farmId && $0.userId == me.user.id }
        guard let member = self.member(me.user.id, farmId: farmId) ?? listed, member.removedAt == nil else {
            throw APIError.client(status: 403, reason: "You’re not on this farm.")
        }
        return member
    }

    private func admin(on farmId: UUID) throws -> Member {
        let member = try self.member(on: farmId)
        guard member.role == .admin else { throw APIError.client(status: 403, reason: "Only an admin can do that.") }
        return member
    }

    private func member(_ userId: UUID, farmId: UUID) -> Member? {
        guard case .member(let member)? = farms[farmId]?[EntityKey(.member, userId)]?.record else { return nil }
        return member
    }

    private func members(farmId: UUID) -> [Member] {
        (farms[farmId] ?? [:]).values.compactMap { stored in
            guard case .member(let member) = stored.record else { return nil }
            return member
        }
    }

    private func activeMemberships(of userId: UUID) -> [Member] {
        farms.keys.compactMap { member(userId, farmId: $0) }.filter { $0.removedAt == nil }
    }

    private func farmRecord(_ farmId: UUID) -> Farm? {
        guard case .farm(let farm)? = farms[farmId]?[EntityKey(.farm, farmId)]?.record else { return nil }
        return farm
    }

    private func accountEmail(for userId: UUID) -> String? {
        accounts.first { $0.value.me.user.id == userId }?.key
    }

    private func now() -> Date {
        clock().roundedToMillisecond
    }

    private func takeScripted() throws {
        if !scripted.isEmpty { throw scripted.removeFirst() }
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Like the server: upper-case, letters and digits only, so `k7q4 m2xp 9r` matches `K7Q4-M2XP-9R`.
    static func normalizeCode(_ code: String) -> String {
        String(code.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    /// A code like the server's, `K7Q4-M2XP-9R`, without 0/O or 1/I/L.
    static func humanCode() -> String {
        let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
        let chars = (0..<10).map { _ in alphabet.randomElement()! }
        return String(chars[0..<4]) + "-" + String(chars[4..<8]) + "-" + String(chars[8..<10])
    }

    private static func validName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw APIError.client(status: 400, reason: "Please enter your name.") }
        guard name.count <= Limits.name else { throw APIError.client(status: 400, reason: "Names can be up to \(Limits.name) characters.") }
        return name
    }

    private static func validPassword(_ password: String) throws -> String {
        guard password.count >= 8 else { throw APIError.client(status: 400, reason: "Use at least 8 characters for your password.") }
        guard password.count <= 200 else { throw APIError.client(status: 400, reason: "That password is too long.") }
        return password
    }

    /// RFC 4180 like the server: quote fields with commas, quotes or line breaks, and
    /// defuse anything a spreadsheet would run as a formula.
    private static func csvRow(_ fields: [String]) -> String {
        fields.map { raw in
            var value = raw
            if let first = value.first, "=+-@\t\r".contains(first) { value = "'" + value }
            guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") + "\r\n"
    }

    private static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}
