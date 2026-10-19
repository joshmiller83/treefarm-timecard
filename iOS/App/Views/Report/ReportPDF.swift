import UIKit

/// Prints a `PaperTimeCard` as a US Letter PDF, as many pages as it needs.
///
/// Page one opens with the fir band (TIME CARD, who, the dates and the farm); later pages
/// repeat a slim header and the column titles. A shift never splits across pages. The
/// totals, the double rule, "Breaks are listed, not counted." and the Prepared line end
/// the card, and every page is numbered. Pay is never printed.
enum ReportPDF {
    /// US Letter in points.
    static let pageSize = CGSize(width: 612, height: 792)

    static func render(_ card: PaperTimeCard) -> Data {
        let layout = Layout(card: card)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: card.fileName,
            kCGPDFContextAuthor as String: card.worker,
            kCGPDFContextCreator as String: "Time Card",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            for (index, page) in layout.pages.enumerated() {
                context.beginPage()
                layout.draw(page: page, number: index + 1, of: layout.pages.count)
            }
        }
    }

    // MARK: Styles

    enum Ink {
        static let ink = UIColor(red: 0x1B / 255, green: 0x1F / 255, blue: 0x1C / 255, alpha: 1)
        static let muted = UIColor(red: 0x55 / 255, green: 0x6A / 255, blue: 0x5C / 255, alpha: 1)
        static let rule = UIColor(red: 0xDD / 255, green: 0xE4 / 255, blue: 0xDD / 255, alpha: 1)
        static let fir = UIColor(red: 0x1D / 255, green: 0x5B / 255, blue: 0x3A / 255, alpha: 1)
        static let sap = UIColor(red: 0xB5 / 255, green: 0x7A / 255, blue: 0x12 / 255, alpha: 1)
        static let onFir = UIColor.white
        static let onFirSoft = UIColor(white: 1, alpha: 0.86)
    }

    enum Face {
        static func heading(_ size: CGFloat) -> UIFont {
            UIFont(name: "ZillaSlab-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
        }

        static func number(_ size: CGFloat, semibold: Bool = false) -> UIFont {
            UIFont(name: semibold ? "IBMPlexMono-SemiBold" : "IBMPlexMono-Medium", size: size)
                ?? .monospacedDigitSystemFont(ofSize: size, weight: semibold ? .semibold : .medium)
        }

        static func body(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
            .systemFont(ofSize: size, weight: weight)
        }
    }

    // MARK: Layout

    /// Where everything goes, measured once so pages can be numbered "of N".
    struct Layout {
        let card: PaperTimeCard
        static let margin: CGFloat = 40
        static let bandHeight: CGFloat = 84
        static let bandGap: CGFloat = 10
        static let slimHeaderHeight: CGFloat = 34
        static let columnHeaderHeight: CGFloat = 26
        static let rowLineHeight: CGFloat = 24
        static let footerHeight: CGFloat = 28
        static let totalsHeight: CGFloat = 70
        static let emptyHeight: CGFloat = 44
        /// Where the In column starts; details under a row start there too.
        static let inOffset: CGFloat = 118
        static var detailWidth: CGFloat { pageSize.width - margin * 2 - inOffset }

        var margin: CGFloat { Self.margin }
        var bandHeight: CGFloat { Self.bandHeight }
        var slimHeaderHeight: CGFloat { Self.slimHeaderHeight }
        var columnHeaderHeight: CGFloat { Self.columnHeaderHeight }
        var rowLineHeight: CGFloat { Self.rowLineHeight }
        var width: CGFloat { pageSize.width - margin * 2 }
        var left: CGFloat { margin }
        var right: CGFloat { pageSize.width - margin }
        /// Column edges: Date, In, Out from the left, then Trees and Hours right-aligned.
        var inX: CGFloat { left + Self.inOffset }
        var outX: CGFloat { left + 214 }
        var treesRight: CGFloat { right - 104 }
        var hoursRight: CGFloat { right }
        var detailWidth: CGFloat { Self.detailWidth }

        struct Page {
            var rows: [Int]
            var hasTotals: Bool
        }

        let pages: [Page]
        let rowHeights: [CGFloat]

        init(card: PaperTimeCard) {
            self.card = card
            let heights = card.rows.map { Self.rowHeight($0) }
            rowHeights = heights

            let bottom = pageSize.height - Self.margin - Self.footerHeight
            let firstTop = Self.margin + Self.bandHeight + Self.bandGap + Self.columnHeaderHeight
            let laterTop = Self.margin + Self.slimHeaderHeight + Self.columnHeaderHeight
            var pages: [Page] = []
            var current = Page(rows: [], hasTotals: false)
            var y = firstTop + (card.rows.isEmpty ? Self.emptyHeight : 0)
            for (i, h) in heights.enumerated() {
                if y + h > bottom && !current.rows.isEmpty {
                    pages.append(current)
                    current = Page(rows: [], hasTotals: false)
                    y = laterTop
                }
                current.rows.append(i)
                y += h
            }
            // The totals stay whole: when they don't fit, they start the next page.
            if y + Self.totalsHeight > bottom {
                pages.append(current)
                current = Page(rows: [], hasTotals: true)
            } else {
                current.hasTotals = true
            }
            pages.append(current)
            self.pages = pages
        }

        static func rowHeight(_ row: PaperTimeCard.Row) -> CGFloat {
            var h = rowLineHeight
            for detail in row.details {
                h += detailHeight(detail) + detailGap
            }
            return h + (row.details.isEmpty ? 0 : 6)
        }

        static let detailGap: CGFloat = 2

        static func detailHeight(_ detail: PaperTimeCard.Detail) -> CGFloat {
            detailText(detail).boundingRect(with: CGSize(width: detailWidth, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height.rounded(.up)
        }

        /// "Breaks  Lunch 30 min", with long notes wrapping under their text, not under the label.
        static func detailText(_ detail: PaperTimeCard.Detail) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 1.5
            let text = NSMutableAttributedString()
            if let label = detail.label {
                let labelText = NSAttributedString(string: label + "  ", attributes: [
                    .font: Face.body(9, .semibold), .foregroundColor: Ink.ink, .kern: 0.2,
                ])
                paragraph.headIndent = labelText.size().width
                text.append(labelText)
            }
            text.append(NSAttributedString(string: detail.text, attributes: [
                .font: detail.kind == .open ? Face.body(9.5, .medium) : Face.body(9.5),
                .foregroundColor: detail.kind == .open ? Ink.sap : Ink.muted,
            ]))
            text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
            return text
        }

        // MARK: Drawing

        func draw(page: Page, number: Int, of count: Int) {
            var y: CGFloat
            if number == 1 {
                drawBand()
                y = margin + bandHeight + Self.bandGap
            } else {
                drawSlimHeader()
                y = margin + slimHeaderHeight
            }
            if !page.rows.isEmpty || number == 1 {
                drawColumnHeader(at: y)
                y += columnHeaderHeight
            }
            if card.rows.isEmpty && number == 1 {
                text(PaperTimeCard.empty, font: Face.body(11), color: Ink.muted, x: left, baseline: y + 26)
                y += Self.emptyHeight
                line(at: y, color: Ink.ink, width: 0.75)
            }
            for (n, i) in page.rows.enumerated() {
                let isLast = i == card.rows.count - 1
                drawRow(card.rows[i], at: y, height: rowHeights[i], lastOnCard: isLast, lastOnPage: n == page.rows.count - 1)
                y += rowHeights[i]
            }
            if page.hasTotals {
                drawTotals(at: y)
            }
            drawFooter(number: number, of: count)
        }

        private func drawBand() {
            let band = CGRect(x: left, y: margin, width: width, height: bandHeight)
            Ink.fir.setFill()
            UIBezierPath(roundedRect: band, cornerRadius: 6).fill()

            let titleBaseline = band.minY + 41
            text(PaperTimeCard.title, font: Face.heading(27), color: Ink.onFir, x: band.minX + 22, baseline: titleBaseline, kern: 1.6)
            text(card.farm, font: Face.body(10.5, .semibold), color: Ink.onFir, rightAt: band.maxX - 22, baseline: titleBaseline)
            let lineBaseline = band.maxY - 16
            text(card.whoLine, font: Face.number(10.5), color: Ink.onFirSoft, x: band.minX + 22, baseline: lineBaseline)
            text(card.range, font: Face.number(10.5), color: Ink.onFirSoft, rightAt: band.maxX - 22, baseline: lineBaseline)
        }

        private func drawSlimHeader() {
            let baseline = margin + 13
            text(PaperTimeCard.title, font: Face.heading(13), color: Ink.fir, x: left, baseline: baseline, kern: 1.2)
            let title = NSAttributedString(string: PaperTimeCard.title, attributes: [.font: Face.heading(13), .kern: 1.2])
            text(card.whoLine, font: Face.body(9.5), color: Ink.muted, x: left + title.size().width + 12, baseline: baseline)
            text(card.range, font: Face.number(9.5), color: Ink.muted, rightAt: right, baseline: baseline)
        }

        private func drawColumnHeader(at y: CGFloat) {
            let font = Face.number(8)
            let baseline = y + 17
            text("DATE", font: font, color: Ink.muted, x: left, baseline: baseline, kern: 1)
            text("IN", font: font, color: Ink.muted, x: inX, baseline: baseline, kern: 1)
            text("OUT", font: font, color: Ink.muted, x: outX, baseline: baseline, kern: 1)
            text("TREES", font: font, color: Ink.muted, rightAt: treesRight, baseline: baseline, kern: 1)
            text("HOURS", font: font, color: Ink.muted, rightAt: hoursRight, baseline: baseline, kern: 1)
            line(at: y + columnHeaderHeight - 2, color: Ink.ink, width: 0.75)
        }

        private func drawRow(_ row: PaperTimeCard.Row, at y: CGFloat, height: CGFloat, lastOnCard: Bool, lastOnPage: Bool) {
            // Every cell of the row sits on one baseline, whatever its font.
            let baseline = y + 16.5
            let number = Face.number(10.5)
            text(row.date, font: Face.body(10.5, .semibold), color: Ink.ink, x: left, baseline: baseline)
            text(row.clockIn, font: number, color: Ink.ink, x: inX, baseline: baseline)
            let out = NSMutableAttributedString(string: row.clockOut, attributes: [.font: number, .foregroundColor: row.clockOut == "—" ? Ink.muted : Ink.ink])
            if row.nextDay {
                out.append(NSAttributedString(string: " +1 day", attributes: [.font: Face.body(8, .medium), .foregroundColor: Ink.muted]))
            }
            out.draw(at: CGPoint(x: outX, y: baseline - number.ascender))
            text(row.trees, font: number, color: row.trees == "–" ? Ink.muted : Ink.ink, rightAt: treesRight, baseline: baseline)
            text(row.hours, font: Face.number(10.5, semibold: true), color: Ink.ink, rightAt: hoursRight, baseline: baseline)

            var dy = y + rowLineHeight
            for detail in row.details {
                let height = Self.detailHeight(detail)
                Self.detailText(detail).draw(with: CGRect(x: inX, y: dy, width: detailWidth, height: height),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                dy += height + Self.detailGap
            }
            line(at: y + height, color: lastOnCard ? Ink.ink : Ink.rule, width: lastOnCard ? 0.75 : 0.5)
        }

        private func drawTotals(at y: CGFloat) {
            let top = y + 12
            let baseline = top + 15
            let big = Face.number(13, semibold: true)
            let total = NSMutableAttributedString(string: "Total", attributes: [.font: Face.body(11.5, .semibold), .foregroundColor: Ink.ink])
            total.append(NSAttributedString(string: "   " + card.days, attributes: [.font: Face.body(10), .foregroundColor: Ink.muted]))
            total.draw(at: CGPoint(x: left, y: baseline - Face.body(11.5, .semibold).ascender))

            let sum = NSMutableAttributedString()
            sum.append(NSAttributedString(string: card.totalHours, attributes: [.font: Face.number(13, semibold: true), .foregroundColor: Ink.ink]))
            sum.append(NSAttributedString(string: " hours  ·  ", attributes: [.font: Face.body(10.5), .foregroundColor: Ink.muted]))
            sum.append(NSAttributedString(string: card.totalTrees, attributes: [.font: Face.number(13, semibold: true), .foregroundColor: Ink.ink]))
            sum.append(NSAttributedString(string: " trees", attributes: [.font: Face.body(10.5), .foregroundColor: Ink.muted]))
            sum.draw(at: CGPoint(x: right - sum.size().width, y: baseline - big.ascender))

            // The double rule under the totals, as on a ledger.
            line(at: top + 24, color: Ink.ink, width: 0.75)
            line(at: top + 27.5, color: Ink.ink, width: 0.75)

            text(PaperTimeCard.footnote, font: Face.body(9.5), color: Ink.muted, x: left, baseline: top + 47)
            text(card.prepared, font: Face.body(9.5), color: Ink.muted, rightAt: right, baseline: top + 47)
        }

        private func drawFooter(number: Int, of count: Int) {
            let baseline = pageSize.height - margin
            line(at: baseline - 16, color: Ink.rule, width: 0.5)
            let who = [card.farm, card.worker].filter { !$0.isEmpty }.joined(separator: " · ")
            text(who, font: Face.body(8.5), color: Ink.muted, x: left, baseline: baseline)
            text("Page \(number) of \(count)", font: Face.number(8.5), color: Ink.muted, rightAt: right, baseline: baseline)
        }

        // MARK: Primitives

        /// Text whose baseline sits at `baseline`, so different fonts line up.
        private func text(_ string: String, font: UIFont, color: UIColor, x: CGFloat, baseline: CGFloat, kern: CGFloat = 0) {
            NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
                .draw(at: CGPoint(x: x, y: baseline - font.ascender))
        }

        /// The same, ending at `x` (the trailing letter-space doesn't count).
        private func text(_ string: String, font: UIFont, color: UIColor, rightAt x: CGFloat, baseline: CGFloat, kern: CGFloat = 0) {
            let s = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
            s.draw(at: CGPoint(x: x - s.size().width + kern, y: baseline - font.ascender))
        }

        private func line(at y: CGFloat, color: UIColor, width: CGFloat) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: left, y: y))
            path.addLine(to: CGPoint(x: right, y: y))
            path.lineWidth = width
            color.setStroke()
            path.stroke()
        }
    }
}
