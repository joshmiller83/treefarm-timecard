import SwiftUI

/// The paper time card on screen: the same card the PDF prints, white paper in both
/// appearances, with the fir band, a ledger table, totals over a double rule, and the
/// "Prepared" line. At large text sizes each shift stacks so nothing is cut off.
struct PaperCardView: View {
    var card: PaperTimeCard
    @Environment(\.dynamicTypeSize) private var typeSize

    @ScaledMetric(relativeTo: .footnote) private var timeWidth: CGFloat = 66
    @ScaledMetric(relativeTo: .footnote) private var treesWidth: CGFloat = 42
    @ScaledMetric(relativeTo: .footnote) private var hoursWidth: CGFloat = 46

    enum Ink {
        static let paper = Color(uiColor: .white)
        static let ink = Color(uiColor: ReportPDF.Ink.ink)
        static let muted = Color(uiColor: ReportPDF.Ink.muted)
        static let rule = Color(uiColor: ReportPDF.Ink.rule)
        static let fir = Color(uiColor: ReportPDF.Ink.fir)
        static let sap = Color(uiColor: ReportPDF.Ink.sap)
    }

    private var stacked: Bool { typeSize >= .xxLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            band
            VStack(alignment: .leading, spacing: 0) {
                if !stacked { columnHeader }
                if card.rows.isEmpty {
                    Text(PaperTimeCard.empty)
                        .font(.subheadline)
                        .foregroundStyle(Ink.muted)
                        .padding(.vertical, 18)
                    Rectangle().fill(Ink.ink).frame(height: 1)
                }
                ForEach(card.rows.indices, id: \.self) { i in
                    row(card.rows[i], last: i == card.rows.count - 1)
                }
                totals
                footer
            }
            .padding(.horizontal, 16)
        }
        .background(Ink.paper)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
        .shadow(color: Color(red: 20 / 255, green: 34 / 255, blue: 26 / 255).opacity(0.10), radius: 14, y: 8)
        .shadow(color: Color(red: 20 / 255, green: 34 / 255, blue: 26 / 255).opacity(0.06), radius: 2, y: 1)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paper-card")
    }

    // MARK: Band

    private var band: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 12)
                    farm
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                    farm
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    who
                    Spacer(minLength: 12)
                    range
                }
                VStack(alignment: .leading, spacing: 4) {
                    who
                    range
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.fir)
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text(PaperTimeCard.title)
            .font(.custom(Typeface.headingBold, size: 22, relativeTo: .title2))
            .tracking(1.4)
            .foregroundStyle(.white)
            .accessibilityLabel("Time card")
    }

    private var farm: some View {
        Text(card.farm)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
    }

    private var who: some View {
        Text(card.whoLine)
            .font(.custom(Typeface.numberMedium, size: 11.5, relativeTo: .caption))
            .foregroundStyle(.white.opacity(0.88))
    }

    private var range: some View {
        Text(card.range)
            .font(.custom(Typeface.numberMedium, size: 11.5, relativeTo: .caption))
            .foregroundStyle(.white.opacity(0.88))
            .accessibilityIdentifier("paper-range")
    }

    // MARK: Table

    private var columnHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                headerText("Date").frame(maxWidth: .infinity, alignment: .leading)
                headerText("In").frame(width: timeWidth, alignment: .leading)
                headerText("Out").frame(width: timeWidth, alignment: .leading)
                headerText("Trees").frame(width: treesWidth, alignment: .trailing)
                headerText("Hours").frame(width: hoursWidth, alignment: .trailing)
            }
            .padding(.top, 12)
            .padding(.bottom, 7)
            Rectangle().fill(Ink.ink).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private func headerText(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.custom(Typeface.numberMedium, size: 9.5, relativeTo: .caption2))
            .tracking(0.9)
            .foregroundStyle(Ink.muted)
            .lineLimit(1)
    }

    private var numberFont: Font { .custom(Typeface.numberMedium, size: 12.5, relativeTo: .footnote) }

    @ViewBuilder
    private func row(_ row: PaperTimeCard.Row, last: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if stacked {
                Text(row.date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.ink)
                Text("\(row.clockIn) – \(row.clockOut)\(row.nextDay ? " (+1 day)" : "")")
                    .font(numberFont)
                    .foregroundStyle(Ink.ink)
                Text("\(row.hours) h · \(row.trees == "–" ? "no" : row.trees) trees")
                    .font(numberFont)
                    .foregroundStyle(Ink.ink)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.date)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.clockIn)
                        .frame(width: timeWidth, alignment: .leading)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(row.clockOut)
                            .foregroundStyle(row.clockOut == "—" ? Ink.muted : Ink.ink)
                        if row.nextDay {
                            Text("+1")
                                .font(.system(size: 8, weight: .semibold))
                                .baselineOffset(5)
                                .foregroundStyle(Ink.muted)
                                .accessibilityLabel("next day")
                        }
                    }
                    .frame(width: timeWidth, alignment: .leading)
                    Text(row.trees)
                        .foregroundStyle(row.trees == "–" ? Ink.muted : Ink.ink)
                        .frame(width: treesWidth, alignment: .trailing)
                    Text(row.hours)
                        .fontWeight(.semibold)
                        .frame(width: hoursWidth, alignment: .trailing)
                }
                .font(numberFont)
                .foregroundStyle(Ink.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            ForEach(row.details, id: \.self) { detail in
                detailText(detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, stacked ? 0 : 2)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(last ? Ink.ink : Ink.rule).frame(height: last ? 1 : 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(row))
        .accessibilityIdentifier("paper-row")
    }

    private func detailText(_ detail: PaperTimeCard.Detail) -> some View {
        let label = detail.label.map { Text("\($0)  ").font(.caption.weight(.semibold)).foregroundStyle(Ink.ink) } ?? Text("")
        let body = Text(detail.text)
            .font(detail.kind == .open ? .caption.weight(.medium) : .caption)
            .foregroundStyle(detail.kind == .open ? Ink.sap : Ink.muted)
        return Text("\(label)\(body)")
    }

    private func spoken(_ row: PaperTimeCard.Row) -> String {
        var parts = ["\(row.date): in \(row.clockIn), out \(row.clockOut == "—" ? "still on the clock" : row.clockOut)\(row.nextDay ? " the next day" : "")",
                     "\(row.hours) hours", row.trees == "–" ? "no trees" : "\(row.trees) trees"]
        parts += row.details.map { [$0.label, $0.text].compactMap { $0 }.joined(separator: ": ") }
        return parts.joined(separator: ". ")
    }

    // MARK: Totals and footer

    private var totals: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    totalLabel
                    Spacer(minLength: 8)
                    totalSum
                }
                VStack(alignment: .leading, spacing: 4) {
                    totalLabel
                    totalSum
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
            .padding(.bottom, 9)
            VStack(spacing: 2.5) {
                Rectangle().fill(Ink.ink).frame(height: 1)
                Rectangle().fill(Ink.ink).frame(height: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total, \(card.days): \(card.totalHours) hours, \(card.totalTrees) trees")
        .accessibilityIdentifier("paper-totals")
    }

    private var totalLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Total").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.ink)
            Text(card.days).font(.caption).foregroundStyle(Ink.muted)
        }
    }

    private var totalSum: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(card.totalHours).font(.custom(Typeface.numberSemiBold, size: 15, relativeTo: .subheadline))
            Text("hours ·").font(.caption).foregroundStyle(Ink.muted)
            Text(card.totalTrees).font(.custom(Typeface.numberSemiBold, size: 15, relativeTo: .subheadline))
            Text("trees").font(.caption).foregroundStyle(Ink.muted)
        }
        .foregroundStyle(Ink.ink)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                footnote
                Spacer(minLength: 8)
                prepared
            }
            VStack(alignment: .leading, spacing: 3) {
                footnote
                prepared
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(Ink.muted)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var footnote: some View { Text(PaperTimeCard.footnote) }
    private var prepared: some View { Text(card.prepared).accessibilityIdentifier("paper-prepared") }
}
