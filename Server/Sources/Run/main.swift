import App
import Foundation
import Logging
import Vapor

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)

// One event loop means one SQLite connection; see `configure`.
let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let app = try await Application.make(env, .shared(eventLoopGroup))

var config = AppConfig.fromEnvironment(ProcessInfo.processInfo.environment)
config.scheduleBackups = AppConfig.isServeCommand(env.arguments)

do {
    try await configure(app, config: config)
    try await app.execute()
} catch {
    app.logger.report(error: error)
    try? await app.asyncShutdown()
    try? await eventLoopGroup.shutdownGracefully()
    exit(1)
}
try await app.asyncShutdown()
try await eventLoopGroup.shutdownGracefully()
