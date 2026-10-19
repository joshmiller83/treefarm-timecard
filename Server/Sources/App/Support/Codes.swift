import Crypto
import Foundation

/// Secrets the server hands out. Only their SHA-256 hashes are stored.
enum Codes {
    /// No 0/O, 1/I/L, so a code read aloud or off a scrap of paper survives.
    static let alphabet: [Character] = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    /// A 10-character invite or reset code grouped like `K7Q4-M2XP-9R` (about 49 bits).
    static func humanCode() -> String {
        var rng = SystemRandomNumberGenerator()
        let chars = (0..<10).map { _ in alphabet.randomElement(using: &rng)! }
        return String(chars[0..<4]) + "-" + String(chars[4..<8]) + "-" + String(chars[8..<10])
    }

    /// Upper-cases and drops everything but letters and digits, so `k7q4 m2xp 9r` matches.
    static func normalize(_ code: String) -> String {
        String(code.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    static func codeHash(_ code: String) -> String { sha256Hex(normalize(code)) }

    /// A bearer token: 32 random bytes, base64url without padding.
    static func token() -> String {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256Hex(_ s: String) -> String {
        let digits = Array("0123456789abcdef")
        return String(SHA256.hash(data: Data(s.utf8)).flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] })
    }
}
