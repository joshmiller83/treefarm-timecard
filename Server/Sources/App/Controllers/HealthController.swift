import TreeFarmKit
import Vapor

public enum ServerInfo {
    public static let version = "0.2.0"
}

struct HealthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("health") { _ in
            try Response.json(HealthResponse(status: "ok", version: ServerInfo.version))
        }
    }
}
