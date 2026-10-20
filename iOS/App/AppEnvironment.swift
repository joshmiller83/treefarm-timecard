import Foundation
import TimeCardCore
import UIKit

/// How this launch gets its data.
enum LaunchMode: Equatable {
    /// The real database in the App Group and the real server.
    case live
    /// UI tests: an in-memory store and the stub server holding the demo farm, so
    /// tests run offline. `signedIn` starts as the demo admin; otherwise at sign-in.
    case uiTest(signedIn: Bool)

    static let inMemoryArgument = "-UITestInMemory"

    /// True when this process hosts unit tests (XCTest loads them into the app). Such a run
    /// never asks for permissions: an alert left behind breaks the next UI test.
    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
    static let signedOutArgument = "-UITestSignedOut"
    /// With `-UITestInMemory`: the demo farm, but the real WatchConnectivity link and HealthKit
    /// launcher, for the paired-simulator integration (docs/watch.md 7.4).
    static let watchLinkArgument = "-UITestWatchLink"

    /// The real watch link: a live launch, or a UI-test launch that asks for it. Never in a
    /// process hosting unit tests.
    static func usesRealWatch(_ mode: LaunchMode, arguments: [String] = ProcessInfo.processInfo.arguments,
                              isTestHost: Bool = LaunchMode.isTestHost) -> Bool {
        guard !isTestHost else { return false }
        return mode == .live || arguments.contains(watchLinkArgument)
    }

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments,
                        environment: [String: String] = ProcessInfo.processInfo.environment) -> LaunchMode {
        guard arguments.contains(inMemoryArgument) || environment["UITEST_IN_MEMORY"] == "1" else { return .live }
        return .uiTest(signedIn: !arguments.contains(signedOutArgument))
    }
}

/// Builds the app's object graph for a launch mode.
@MainActor
enum AppEnvironment {
    /// `watchTransport` replaces the watch link's transport (tests use a `FakeWatchTransport`).
    static func makeModel(mode: LaunchMode = .current(), watchTransport: (any WatchTransport)? = nil) -> AppModel {
        switch mode {
        case .live:
            return makeLive()
        case .uiTest(let signedIn):
            let demo = DemoFarm.makeServer(signedIn: signedIn)
            // An in-memory database can't fail to open.
            let store = try! LocalStore.inMemory()
            let tokens = InMemoryTokenStore(token: signedIn ? "ui-test-token" : nil)
            if signedIn, let me = try? JSONCoding.encoder().encode(demo.me) {
                try? store.setValue(me, forKey: AuthService.meKey)
            }
            let session = TimeCardSession(store: store, api: demo.server, tokens: tokens, deviceName: "UI Test iPhone")
            return AppModel(session: session, mode: mode, watchTransport: watchTransport)
        }
    }

    private static func makeLive() -> AppModel {
        let server = serverURL
        serverInUse = server
        let tokens = KeychainTokenStore(service: Bundle.main.bundleIdentifier ?? "timecard")
        let api = URLSessionAPIClient(baseURL: server, tokens: tokens)
        let appGroup = Bundle.main.object(forInfoDictionaryKey: "TimeCardAppGroup") as? String
        do {
            let store = try LocalStore.onDisk(directory: AppDatabase.directory(appGroup: appGroup))
            // Before the session reads its token: a sign-in from another server stays there.
            try adoptServer(server, store: store, tokens: tokens)
            return AppModel(session: TimeCardSession(store: store, api: api, tokens: tokens, deviceName: UIDevice.current.name), mode: .live)
        } catch {
            // Don't quietly run on a throwaway database: say so and stop there.
            let store = try! LocalStore.inMemory()
            let session = TimeCardSession(store: store, api: api, tokens: tokens, deviceName: UIDevice.current.name)
            return AppModel(session: session, mode: .live,
                            storageError: "Time Card couldn’t open its data on this phone (\(error.localizedDescription)). Restart the phone and try again.")
        }
    }

    /// The server the next launch talks to: `TIMECARD_SERVER_URL` in the scheme's environment
    /// for development, then the address saved in Settings, then the standard server.
    static var serverURL: URL {
        ServerAddress.resolve()
    }

    /// The server this launch talks to. A new address saved in Settings is used from the next
    /// launch, after `adoptServer` has signed out of the old one.
    private(set) static var serverInUse: URL = ServerAddress.resolve()

    /// Makes `server` the one this phone's sign-in belongs to. When the token and the farm
    /// records on this phone came from another server, forgets them first (as signing out
    /// does), so the old token never goes to the new host and the old farm never syncs there.
    /// Returns true when it signed out.
    @discardableResult
    static func adoptServer(_ server: URL, store: LocalStore, tokens: TokenStore, defaults: UserDefaults = .standard) throws -> Bool {
        let signedOut = ServerAddress.mustSignOut(signedInServer: defaults.string(forKey: ServerAddress.signedInServerKey), using: server)
        if signedOut {
            try tokens.clear()
            try store.wipe()
        }
        defaults.set(server.absoluteString, forKey: ServerAddress.signedInServerKey)
        return signedOut
    }
}
