import Foundation
import TreeFarmKit
import Vapor

/// The server writes dates as whole milliseconds since 1970, which is what
/// `JSONCoding` reads, but rounding first means a record that goes out and comes
/// back encodes to exactly the same bytes. Stored records rely on that to spot
/// repeats.
enum ServerJSON {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.millis)
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder { JSONCoding.decoder() }

    static func string<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder().encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try decoder().decode(T.self, from: Data(string.utf8))
    }
}

extension Date {
    /// Whole milliseconds since 1970, the precision records sync at.
    var millis: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }

    init(millis: Int64) {
        self.init(timeIntervalSince1970: Double(millis) / 1000)
    }
}

extension Request {
    /// Decodes the body with the shared JSON settings, answering 400 with a plain sentence when it can't.
    func decodeJSON<T: Decodable>(_ type: T.Type) throws -> T {
        guard let buffer = body.data, buffer.readableBytes > 0 else {
            throw Abort(.badRequest, reason: "The request needs a JSON body.")
        }
        do {
            return try ServerJSON.decoder().decode(T.self, from: Data(buffer: buffer))
        } catch let error as DecodingError {
            throw Abort(.badRequest, reason: "The request body wasn’t understood (\(error.shortDescription)).")
        }
    }
}

extension DecodingError {
    var shortDescription: String {
        func path(_ ctx: Context) -> String {
            let p = ctx.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
            return p.isEmpty ? "body" : p
        }
        switch self {
        case .keyNotFound(let key, let ctx):
            let p = path(ctx)
            return "missing \(p == "body" ? key.stringValue : "\(p).\(key.stringValue)")"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "wrong type at \(path(ctx))"
        case .dataCorrupted(let ctx):
            return "bad value at \(path(ctx))"
        @unknown default:
            return "unreadable"
        }
    }
}

extension Response {
    /// A JSON answer written with the server's encoder.
    static func json<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok) throws -> Response {
        var headers = HTTPHeaders()
        headers.contentType = .json
        return Response(status: status, headers: headers, body: .init(data: try ServerJSON.encoder().encode(value)))
    }
}
