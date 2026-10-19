import TreeFarmKit
import Vapor

public enum ServerInfo {
    public static let version = "0.2.0"
    /// Where a browser pointed at the API host is sent.
    public static let website = "https://treefarm.joshnliz.com"
}

struct HealthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get { _ in
            Response(status: .found, headers: [HTTPHeaders.Name.location.description: ServerInfo.website])
        }
        routes.get("health") { _ in
            try Response.json(HealthResponse(status: "ok", version: ServerInfo.version))
        }
    }
}
