import Fluent
import FluentSQLiteDriver
import Foundation
import Vapor

/// Sets up the database, middleware and routes.
///
/// One rule holds the sync design together: the server talks to SQLite over a
/// single connection. FluentSQLiteDriver opens one connection per event loop and
/// the server runs one event loop (see `Run/main.swift` and the tests), so every
/// transaction runs alone. That keeps `seq` numbers in commit order, which is what
/// makes `since`-based pulls safe.
public func configure(_ app: Application, config: AppConfig) async throws {
    app.config = config

    app.http.server.configuration.hostname = config.host
    app.http.server.configuration.port = config.port
    app.routes.defaultMaxBodySize = "2mb"

    switch config.database {
    case .memory:
        app.databases.use(.sqlite(.memory), as: .sqlite)
    case .file(let path):
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        app.databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    app.rateLimiter = RateLimiter(rules: .init(ipAttempts: config.ipAttempts, ipWindow: config.ipWindow,
                                               emailFailures: config.emailFailures, lockout: config.lockout))
    app.dummyPasswordHash = try await app.hasher.hash(Codes.token())

    app.migrations.add(CreateSchema())
    try await app.autoMigrate()

    app.middleware = Middlewares()
    app.middleware.use(RouteLoggingMiddleware(logLevel: .info))
    app.middleware.use(APIErrorMiddleware())

    app.asyncCommands.use(ImportArtifactCommand(), as: "import-artifact")

    try routes(app)
}

func routes(_ app: Application) throws {
    try app.register(collection: HealthController())
    try app.register(collection: AuthController())
    try app.register(collection: MeController())
    try app.register(collection: AdminController())
}
