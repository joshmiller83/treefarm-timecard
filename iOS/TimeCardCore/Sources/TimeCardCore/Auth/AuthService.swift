import Foundation

/// Somewhere small to keep a value between launches. `LocalStore` is one.
public protocol KeyValueStore: Sendable {
    func value(forKey key: String) throws -> Data?
    func setValue(_ value: Data?, forKey key: String) throws
}

extension LocalStore: KeyValueStore {}

/// Who is using the app.
public enum AuthState: Equatable, Sendable {
    case signedOut
    case signedIn(MeResponse)
    /// The server refused the token (expired or revoked). The person and their unsynced
    /// work stay on the phone; they sign in again to carry on.
    case expired(MeResponse)

    public var me: MeResponse? {
        switch self {
        case .signedOut: nil
        case .signedIn(let me), .expired(let me): me
        }
    }
}

/// A problem with what was typed, caught before asking the server.
public enum AuthError: Error, Equatable, Sendable {
    case invalid(String)

    public var userMessage: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

/// Signs people in, up (with an invite code) and out, and remembers the last `/me`
/// answer so the app opens straight to work with no network.
public actor AuthService {
    public static let meKey = "auth.me"

    private let api: any APIClient
    private let tokens: any TokenStore
    private let cache: any KeyValueStore
    private let deviceName: String

    public private(set) var state: AuthState

    /// `initialState` saves reading the Keychain and the cached `/me` twice at launch when the
    /// caller already has it.
    public init(api: any APIClient, tokens: any TokenStore, cache: any KeyValueStore, deviceName: String, initialState: AuthState? = nil) {
        self.api = api
        self.tokens = tokens
        self.cache = cache
        self.deviceName = deviceName

        state = initialState ?? Self.initialState(tokens: tokens, cache: cache)
    }

    /// What launch looks like before any network: the cached person, signed in if a token is
    /// still on the phone.
    public static func initialState(tokens: any TokenStore, cache: any KeyValueStore) -> AuthState {
        let cached = (try? cache.value(forKey: meKey)).flatMap { try? JSONCoding.decoder().decode(MeResponse.self, from: $0) }
        let token = (try? tokens.read()) ?? nil
        switch (cached, token) {
        case (let me?, _?): return .signedIn(me)
        case (let me?, nil): return .expired(me)
        case (nil, _): return .signedOut
        }
    }

    // MARK: Signing in

    @discardableResult
    public func login(email: String, password: String) async throws -> MeResponse {
        let email = try Self.checkEmail(email)
        guard !password.isEmpty else { throw AuthError.invalid("Enter your password.") }
        do {
            return try adopt(await api.login(LoginRequest(email: email, password: password, deviceName: deviceName)))
        } catch APIError.unauthorized(let reason) {
            throw APIError.unauthorized(reason: reason.isEmpty ? "That email and password don't match." : reason)
        }
    }

    /// Joins a farm with an invite code from an admin.
    @discardableResult
    public func register(inviteCode: String, email: String, password: String, displayName: String) async throws -> MeResponse {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw AuthError.invalid("Enter the invite code from your admin.") }
        let name = Limits.clampName(displayName)
        guard !name.isEmpty else { throw AuthError.invalid("Enter your name as the crew knows it.") }
        let email = try Self.checkEmail(email)
        guard !password.isEmpty else { throw AuthError.invalid("Choose a password.") }
        return try adopt(await api.register(RegisterRequest(inviteCode: code, email: email, password: password, displayName: name, deviceName: deviceName)))
    }

    /// Sets a new password with a reset code an admin made.
    @discardableResult
    public func reset(email: String, code: String, newPassword: String) async throws -> MeResponse {
        let email = try Self.checkEmail(email)
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw AuthError.invalid("Enter the reset code from your admin.") }
        guard !newPassword.isEmpty else { throw AuthError.invalid("Choose a new password.") }
        return try adopt(await api.resetPassword(ResetPasswordRequest(email: email, resetCode: code, newPassword: newPassword, deviceName: deviceName)))
    }

    // MARK: Staying signed in

    /// Asks the server who we are and caches the answer. A 401 marks the session expired.
    @discardableResult
    public func refreshMe() async throws -> MeResponse {
        do {
            let me = try await api.me()
            try cacheMe(me)
            state = .signedIn(me)
            return me
        } catch let error as APIError {
            if case .unauthorized = error { markExpired() }
            throw error
        }
    }

    // MARK: Your account

    /// Changes the person's name or password and caches the new `/me`. A password
    /// change keeps this phone signed in; the server signs out every other device.
    @discardableResult
    public func updateMe(_ request: UpdateMeRequest) async throws -> MeResponse {
        do {
            let me = try await api.updateMe(request)
            try cacheMe(me)
            state = .signedIn(me)
            return me
        } catch let error as APIError {
            if case .unauthorized = error { markExpired() }
            throw error
        }
    }

    /// Deletes the login on the server, then forgets it here. Shifts stay with the farm.
    public func deleteAccount(password: String) async throws {
        guard !password.isEmpty else { throw AuthError.invalid("Enter your password.") }
        do {
            try await api.deleteAccount(DeleteAccountRequest(password: password))
        } catch let error as APIError {
            if case .unauthorized = error { markExpired() }
            throw error
        }
        forget()
    }

    /// The sync engine got a 401: keep the person, ask them to sign in again.
    public func markExpired() {
        if case .signedIn(let me) = state { state = .expired(me) }
    }

    /// Ends the session on the server if it can, and forgets it here either way.
    public func logout() async {
        try? await api.logout()
        forget()
    }

    /// Takes back a sign-in that can't be used (someone else signing in over unsynced work):
    /// signs that token out on the server and goes back to `me`'s ended sign-in.
    public func restoreExpired(_ me: MeResponse) async {
        try? await api.logout()
        try? tokens.clear()
        if let data = try? JSONCoding.encoder().encode(me) { try? cache.setValue(data, forKey: Self.meKey) }
        state = .expired(me)
    }

    /// Drops the token and the cached person without asking the server.
    private func forget() {
        try? tokens.clear()
        try? cache.setValue(nil, forKey: Self.meKey)
        state = .signedOut
    }

    // MARK: Helpers

    private func adopt(_ answer: AuthResponse) throws -> MeResponse {
        try tokens.save(answer.token)
        try cacheMe(answer.me)
        state = .signedIn(answer.me)
        return answer.me
    }

    private func cacheMe(_ me: MeResponse) throws {
        try cache.setValue(try JSONCoding.encoder().encode(me), forKey: Self.meKey)
    }

    private static func checkEmail(_ email: String) throws -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AuthError.invalid("Enter your email address.") }
        guard trimmed.contains("@"), !trimmed.hasPrefix("@"), !trimmed.hasSuffix("@") else {
            throw AuthError.invalid("That doesn't look like an email address.")
        }
        return trimmed
    }
}

/// A sentence for any error the sign-in screens might see.
public func userMessage(for error: any Error) -> String {
    switch error {
    case let error as APIError: error.userMessage
    case let error as AuthError: error.userMessage
    default: "Something went wrong: \(error.localizedDescription)"
    }
}

/// Like `userMessage(for:)`, worded for the sign-in, join and reset screens.
public func signInMessage(for error: any Error) -> String {
    if case APIError.offline = error { return "You're offline. Connect to the internet to sign in." }
    return userMessage(for: error)
}
