import Foundation
import TreeFarmKit
import Vapor

/// Turns every error into `APIErrorBody`. Errors the server meant to raise
/// (`AbortError`) keep their status and sentence; anything else becomes a plain
/// 500 so stack traces and internals never reach the client.
struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            return Self.response(for: error, request: request)
        }
    }

    static func response(for error: any Error, request: Request) -> Response {
        let status: HTTPResponseStatus
        let reason: String
        var headers = HTTPHeaders()

        switch error {
        case let abort as any AbortError where abort.status.code < 500:
            status = abort.status
            reason = abort.reason
            headers = abort.headers
        case let abort as any AbortError:
            status = abort.status
            reason = "Something went wrong on the server. Please try again."
            request.logger.report(error: abort)
        default:
            status = .internalServerError
            reason = "Something went wrong on the server. Please try again."
            request.logger.error("Unhandled error: \(String(reflecting: error))")
        }

        headers.contentType = .json
        let body = (try? ServerJSON.encoder().encode(APIErrorBody(reason: reason))) ?? Data()
        return Response(status: status, headers: headers, body: .init(data: body))
    }
}
