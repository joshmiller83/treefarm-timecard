import Foundation

/// An in-memory stand-in for the server, used by tests and by UI-test runs of the app.
///
/// It keeps the server's promises that matter to the app: every stored record gets a
/// rising sequence number, pulls page through them, a repeated mutation id gets its
/// first answer, the first mark on a tree wins, and a person can have one open shift.
/// Tests can script failures and add their own rejection rules.
public actor StubAPIClient: APIClient {
    private struct Stored {
        var seq: Int64
        var record: SyncRecord
    }

    private struct Account {
        var password: String
        var me: MeResponse
    }

    private var seq: Int64 = 0
    private var farms: [UUID: [EntityKey: Stored]] = [:]
    private var answered: [UUID: MutationResult] = [:]
    private var scripted: [APIError] = []
    private var losesNextPushAnswer = false
    private var accounts: [String: Account] = [:]
    private var invites: [String: (expired: Bool, farm: Farm, role: Role)] = [:]
    private var resetCodes: [String: String] = [:]
    private var lockouts: [String: TimeInterval] = [:]
    private var signedIn: MeResponse?
    private var rejector: (@Sendable (Mutation) -> MutationResult?)?

    /// Calls made, for tests to inspect.
    public private(set) var pushes: [PushRequest] = []
    public private(set) var pulls: [(since: Int64, limit: Int)] = []
    public private(set) var logouts = 0

    public init() {}

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
        invites[code.uppercased()] = (expired, farm, role)
    }

    public func addResetCode(_ code: String, email: String) {
        resetCodes[Self.normalize(email)] = code
    }

    public func lockOut(email: String, for seconds: TimeInterval) {
        lockouts[Self.normalize(email)] = seconds
    }

    /// Acts as if this person is already signed in (UI-test runs start here).
    public func signIn(as me: MeResponse) {
        signedIn = me
    }

    /// The next call throws `error` instead of answering.
    public func failNext(_ error: APIError) {
        scripted.append(error)
    }

    /// The next push is kept but its answer is lost, as when a request times out late.
    public func loseNextPushAnswer() {
        losesNextPushAnswer = true
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
            throw APIError.unauthorized(reason: "That email and password don't match.")
        }
        return signIn(account.me)
    }

    public func register(_ request: RegisterRequest) async throws -> AuthResponse {
        try takeScripted()
        guard let invite = invites[request.inviteCode.trimmingCharacters(in: .whitespaces).uppercased()] else {
            throw APIError.client(status: 404, reason: "That invite code isn't right. Check it with your admin.")
        }
        guard !invite.expired else {
            throw APIError.client(status: 410, reason: "That invite code has expired. Ask your admin for a new one.")
        }
        let email = Self.normalize(request.email)
        guard accounts[email] == nil else {
            throw APIError.client(status: 409, reason: "There's already an account for that email. Sign in instead.")
        }
        let user = UserProfile(id: UUID(), email: email, displayName: request.displayName)
        let member = Member(userId: user.id, farmId: invite.farm.id, displayName: user.displayName, email: email, role: invite.role)
        store(.member(member), farmId: invite.farm.id)
        let me = MeResponse(user: user, farms: [invite.farm], memberships: [member])
        accounts[email] = Account(password: request.password, me: me)
        invites[request.inviteCode.uppercased()] = nil
        return signIn(me)
    }

    public func resetPassword(_ request: ResetPasswordRequest) async throws -> AuthResponse {
        try takeScripted()
        let email = Self.normalize(request.email)
        guard let code = resetCodes[email], code == request.resetCode.trimmingCharacters(in: .whitespaces), var account = accounts[email] else {
            throw APIError.client(status: 400, reason: "That reset code isn't right or has expired. Ask your admin for a new one.")
        }
        account.password = request.newPassword
        accounts[email] = account
        resetCodes[email] = nil
        return signIn(account.me)
    }

    public func logout() async throws {
        try takeScripted()
        logouts += 1
        signedIn = nil
    }

    public func me() async throws -> MeResponse {
        try takeScripted()
        guard let signedIn else { throw APIError.unauthorized(reason: "Sign in again.") }
        return signedIn
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
        let newer = (farms[farmId] ?? [:]).values.filter { $0.seq > since }.sorted { $0.seq < $1.seq }
        let page = newer.prefix(limit)
        return PullResponse(changes: page.map { Change(seq: $0.seq, record: $0.record) },
                            cursor: page.last?.seq ?? max(since, 0), hasMore: newer.count > page.count)
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
                return .rejected(mutation.id, .openShiftExists, "You're already clocked in on another shift.", current: .shift(open))
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

    private func signIn(_ me: MeResponse) -> AuthResponse {
        signedIn = me
        return AuthResponse(token: "stub-\(UUID().uuidString)", me: me)
    }

    private func takeScripted() throws {
        if !scripted.isEmpty { throw scripted.removeFirst() }
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
