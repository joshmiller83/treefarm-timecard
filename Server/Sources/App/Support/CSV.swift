import Foundation

/// RFC 4180 CSV: fields with commas, quotes or line breaks are quoted, quotes are
/// doubled, rows end in CRLF. A field that starts like a formula gets a leading
/// apostrophe so a spreadsheet shows it instead of running it.
enum CSV {
    static func field(_ raw: String) -> String {
        var value = raw
        if let first = value.first, "=+-@\t\r".contains(first) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + "\r\n"
    }
}
