import Foundation

/// Numbers as Siri writes down what someone said: "14", "fourteen", "row twenty two",
/// "the third". Used to read row, tree and block numbers out of a spoken answer, and to give
/// entities spoken-word synonyms ("block three").
enum SpokenNumber {
    /// The first number in the text, or nil.
    static func parse(_ text: String) -> Int? {
        numbers(in: text).first
    }

    /// Every number in the text, in order: "row 14 in block 2" gives [14, 2].
    static func numbers(in text: String) -> [Int] {
        segments(text).compactMap { if case .number(let n) = $0 { n } else { nil } }
    }

    /// The text in lowercase words with every spoken number as digits: "Block Three, row
    /// twenty-two" gives "block 3 row 22". For comparing what was said with names.
    static func digitized(_ text: String) -> String {
        segments(text).map { segment in
            switch segment {
            case .number(let n): String(n)
            case .word(let w): w
            }
        }.joined(separator: " ")
    }

    enum Segment: Equatable {
        case number(Int)
        case word(String)
    }

    static func segments(_ text: String) -> [Segment] {
        let tokens = tokenize(text)
        var reader = Reader()
        for (i, token) in tokens.enumerated() {
            if let n = digits(token) {
                reader.flush()
                reader.out.append(.number(n))
            } else if token == "a", tokens.indices.contains(i + 1), tokens[i + 1] == "hundred" {
                reader.add(1, kind: .unit)
            } else if token == "and", reader.last == .hundred {
                continue
            } else if let word = Word(token) {
                reader.add(word.value, kind: word.kind)
                if word.ordinal { reader.flush() }
            } else if let n = soundAlikes[token], tokens.count == 1 || (i > 0 && keywords.contains(tokens[i - 1])) {
                reader.flush()
                reader.out.append(.number(n))
            } else {
                reader.flush()
                reader.out.append(.word(token))
            }
        }
        reader.flush()
        return reader.out
    }

    /// "three", "forty-two", "two hundred fifteen" (0 through 999; larger numbers as digits).
    static func words(_ n: Int) -> String {
        guard (0..<1000).contains(n) else { return String(n) }
        if n < 20 { return units[n] }
        if n < 100 { return tens[n / 10] + (n % 10 == 0 ? "" : "-" + units[n % 10]) }
        let rest = n % 100
        return units[n / 100] + " hundred" + (rest == 0 ? "" : " " + words(rest))
    }

    // MARK: Reading

    private enum Kind { case none, unit, teen, ten, hundred }

    private struct Reader {
        var out: [Segment] = []
        var value: Int?
        var last: Kind = .none

        mutating func add(_ n: Int, kind: Kind) {
            switch kind {
            case .hundred:
                guard let v = value, last == .unit else { flush(); out.append(.word("hundred")); return }
                value = v * 100
            case .unit:
                if last == .ten || last == .hundred { value = (value ?? 0) + n } else { flush(); value = n }
            case .teen, .ten:
                if last == .hundred { value = (value ?? 0) + n } else { flush(); value = n }
            case .none:
                return
            }
            last = kind
        }

        mutating func flush() {
            if let value { out.append(.number(value)) }
            value = nil
            last = .none
        }
    }

    private struct Word {
        var value: Int
        var kind: Kind
        var ordinal: Bool

        init?(_ token: String) {
            if token == "hundred" { (value, kind, ordinal) = (100, .hundred, false); return }
            if let i = units.firstIndex(of: token) {
                (value, kind, ordinal) = (i, i < 10 ? .unit : .teen, false)
                if i == 0 { kind = .teen }
                return
            }
            if let i = tens.firstIndex(of: token), i >= 2 { (value, kind, ordinal) = (i * 10, .ten, false); return }
            if let i = ordinalUnits.firstIndex(of: token) {
                (value, kind, ordinal) = (i, i < 10 ? .unit : .teen, true)
                return
            }
            if let i = ordinalTens.firstIndex(of: token), i >= 2 { (value, kind, ordinal) = (i * 10, .ten, true); return }
            return nil
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// "14", or "14th", "21st", "2nd", "3rd".
    private static func digits(_ token: String) -> Int? {
        var t = Substring(token)
        for suffix in ["st", "nd", "rd", "th"] where t.hasSuffix(suffix) && t.count > suffix.count {
            t = t.dropLast(suffix.count)
            break
        }
        guard !t.isEmpty, t.allSatisfy(\.isASCII), t.allSatisfy(\.isNumber) else { return nil }
        return Int(t)
    }

    private static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    private static let ordinalUnits = ["zeroth", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
                                       "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth"]
    private static let ordinalTens = ["", "", "twentieth", "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth", "ninetieth"]

    /// Words that sound like a number, trusted only alone or right after "row", "tree"…
    private static let soundAlikes = ["for": 4, "fore": 4, "to": 2, "too": 2, "won": 1, "ate": 8]
    private static let keywords: Set<String> = ["row", "rows", "tree", "trees", "block", "number"]
}
