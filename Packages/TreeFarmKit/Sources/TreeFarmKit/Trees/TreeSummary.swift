import Foundation

/// Short text for what a shift shaped, as the log and the report show it.
public enum TreeSummary {
    /// 0-based positions in, 1-based text out: "1–4, 7, 9–10". Past four parts it ends ", …".
    public static func ranges(_ positions: [Int]) -> String {
        let sorted = Set(positions).sorted()
        guard var low = sorted.first else { return "" }
        var parts: [String] = []
        var high = low
        func flush() { parts.append(low == high ? "\(low + 1)" : "\(low + 1)–\(high + 1)") }
        for n in sorted.dropFirst() {
            if n == high + 1 { high = n; continue }
            flush()
            low = n
            high = n
        }
        flush()
        return parts.count > 4 ? parts.prefix(4).joined(separator: ", ") + ", …" : parts.joined(separator: ", ")
    }

    /// One shift's marks: "Block 1: rows 1–12, row 13 (trees 1–4) · Block 2: row 1".
    /// Blocks in walk order; deleted marks, deleted blocks and trees outside a block are left out.
    public static func text(marks: [TreeMark], blocks: [Block]) -> String {
        var byBlock: [UUID: [Int: Set<Int>]] = [:]
        for mark in marks where mark.isLive {
            byBlock[mark.blockId, default: [:]][mark.row, default: []].insert(mark.position)
        }
        let parts = FieldWalker(blocks: blocks).blocks.compactMap { block -> String? in
            guard let rows = byBlock[block.id] else { return nil }
            let segments = segments(rows, block: block)
            guard !segments.isEmpty else { return nil }
            let list = segments.count > 6 ? segments.prefix(6).joined(separator: ", ") + " and more" : segments.joined(separator: ", ")
            return "\(block.displayName): \(list)"
        }
        return parts.joined(separator: " · ")
    }

    /// Full rows run together ("rows 1–12"); a part row lists its trees ("row 13 (trees 1–4)").
    private static func segments(_ rows: [Int: Set<Int>], block: Block) -> [String] {
        var segments: [String] = []
        var run: ClosedRange<Int>?
        func flush() {
            if let r = run { segments.append(r.count == 1 ? "row \(r.lowerBound + 1)" : "rows \(r.lowerBound + 1)–\(r.upperBound + 1)") }
            run = nil
        }
        for row in rows.keys.sorted() where (0..<block.rowCount).contains(row) {
            let trees = rows[row]!.filter { (0..<block.treesPerRow).contains($0) }
            if trees.isEmpty { continue }
            if trees.count == block.treesPerRow {
                if let r = run, r.upperBound == row - 1 { run = r.lowerBound...row } else { flush(); run = row...row }
            } else {
                flush()
                segments.append("row \(row + 1) (tree\(trees.count == 1 ? "" : "s") \(ranges(Array(trees))))")
            }
        }
        flush()
        return segments
    }
}
