import Foundation
import NIOHTTP1
import Testing
import TreeFarmKit
import Vapor
import VaporTesting
@testable import App

/// A response with its body still raw, plus helpers to decode it with the shared JSON settings.
struct TestResponse {
    let status: HTTPResponseStatus
    let headers: HTTPHeaders
    let body: ByteBuffer

    var text: String { String(buffer: body) }

    func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try JSONCoding.decoder().decode(T.self, from: Data(buffer: body))
    }

    var errorReason: String? { (try? decode(APIErrorBody.self))?.reason }
}

/// Sends requests to the in-memory app the way the iPhone app would.
struct TestClient {
    let app: Application
    /// Send over a real socket on 127.0.0.1 instead of calling the responder directly.
    var live = false

    func send(
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil,
        headers: HTTPHeaders = [:],
        rawBody: ByteBuffer? = nil
    ) async throws -> TestResponse {
        var headers = headers
        if let token { headers.bearerAuthorization = BearerAuthorization(token: token) }
        let tester = try live ? app.testing(method: .running(hostname: "127.0.0.1", port: 0)) : app.testing()
        let res = try await tester.sendRequest(method, path, headers: headers, body: rawBody)
        return TestResponse(status: res.status, headers: res.headers, body: res.body)
    }

    func send<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil,
        headers: HTTPHeaders = [:],
        json: Body
    ) async throws -> TestResponse {
        var headers = headers
        headers.contentType = .json
        let data = try JSONCoding.encoder().encode(json)
        return try await send(method, path, token: token, headers: headers, rawBody: ByteBuffer(data: data))
    }
}

extension Application {
    var client2: TestClient { TestClient(app: self) }
    var liveClient: TestClient { TestClient(app: self, live: true) }
}
