import Foundation
import Testing
@testable import App

@Suite("Codes and tokens")
struct CodesTests {
    @Test func humanCodesAreGroupedFromAnUnambiguousAlphabet() {
        for _ in 0..<200 {
            let code = Codes.humanCode()
            #expect(code.count == 12)
            let parts = code.split(separator: "-")
            #expect(parts.map(\.count) == [4, 4, 2])
            for ch in code where ch != "-" {
                #expect(Codes.alphabet.contains(ch))
            }
            #expect(!code.contains { "01OIL".contains($0) })
        }
    }

    @Test func codesCompareIgnoringCaseDashesAndSpaces() {
        let code = "K7Q4-M2XP-9R"
        #expect(Codes.codeHash(code) == Codes.codeHash("k7q4m2xp9r"))
        #expect(Codes.codeHash(code) == Codes.codeHash(" k7q4 - m2xp - 9r "))
        #expect(Codes.codeHash(code) != Codes.codeHash("K7Q4-M2XP-9S"))
    }

    @Test func tokensAre32RandomBytesInBase64URL() {
        let a = Codes.token()
        let b = Codes.token()
        #expect(a != b)
        #expect(a.count == 43)
        #expect(!a.contains("+") && !a.contains("/") && !a.contains("="))
    }

    @Test func hashesAreSHA256Hex() {
        #expect(Codes.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
