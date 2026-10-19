import SwiftUI
import TimeCardCore

/// The small card Siri shows under a status answer ("How many trees in Time Card?"): where
/// the day stands at a glance, with the number that was asked about in front.
struct DaySnippetView: View {
    let card: DayCard?

    var body: some View {
        if let card {
            DaySnippetCard(card: card)
        }
    }
}

/// One number on the card: "6:40" over "worked today".
struct SnippetStat: Equatable, Identifiable {
    var value: String
    var label: String
    /// What VoiceOver reads: "6 hours 40 minutes worked today".
    var spoken: String
    /// The number the question was about.
    var focus: Bool

    var id: String { label }

    /// The three numbers for a topic, the asked-about one first.
    static func stats(for card: DayCard) -> [SnippetStat] {
        let span = card.span.words
        let worked = SnippetStat(value: Fmt.hm(card.worked), label: "worked \(span)",
                                 spoken: "\(Fmt.spokenDuration(card.worked)) worked \(span)", focus: false)
        let week = SnippetStat(value: Fmt.hm(card.workedWeek), label: "this week",
                               spoken: "\(Fmt.spokenDuration(card.workedWeek)) this week", focus: false)
        let trees = SnippetStat(value: Fmt.count(card.trees), label: (card.trees == 1 ? "tree " : "trees ") + span,
                                spoken: "\(Fmt.plural(card.trees, "tree")) \(span)", focus: false)
        let rate = SnippetStat(value: Speech.rate(card.treesPerHour), label: "trees an hour",
                               spoken: "\(Speech.rate(card.treesPerHour)) trees an hour \(span)", focus: false)
        let season = SnippetStat(value: Speech.rate(card.seasonTreesPerHour), label: "season pace",
                                 spoken: "season pace \(Speech.rate(card.seasonTreesPerHour)) an hour", focus: false)
        func focused(_ s: SnippetStat) -> SnippetStat {
            var s = s
            s.focus = true
            return s
        }
        switch card.topic {
        case .hours: return [focused(worked), week, trees]
        case .trees: return [focused(trees), rate, worked]
        case .pace: return [focused(rate), season, trees]
        case .pay:
            guard let pay = card.pay else { return [] }
            return [SnippetStat(value: Fmt.usd(cents: pay.todayCents), label: "today", spoken: "\(Fmt.usd(cents: pay.todayCents)) today", focus: true),
                    SnippetStat(value: Fmt.usd(cents: pay.weekCents), label: "this week", spoken: "\(Fmt.usd(cents: pay.weekCents)) this week", focus: true)]
        case .summary, .whereAmI: return [worked, trees, rate]
        }
    }
}

struct DaySnippetCard: View {
    let card: DayCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if card.topic == .whereAmI {
                whereBlock
                StatRow(stats: SnippetStat.stats(for: card), compact: true)
            } else if card.topic == .pay && card.pay == nil {
                payHidden
            } else {
                StatRow(stats: SnippetStat.stats(for: card), compact: false)
                if card.topic != .pay { rowLine }
            }
            if card.fieldTotal > 0 && card.topic != .pay { progress }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Parts

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                pill
                Spacer(minLength: 8)
                fieldTitle
            }
            VStack(alignment: .leading, spacing: 8) {
                pill
                fieldTitle
            }
        }
    }

    private var pill: some View {
        StatusPill(text: phaseText, tone: phaseTone).fixedSize()
    }

    @ViewBuilder private var fieldTitle: some View {
        if !card.fieldName.isEmpty {
            Text(card.fieldName)
                .font(.tcHeadline)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
        }
    }

    private var phaseText: String {
        switch card.phase {
        case .working: "Working"
        case .lunch: "On lunch"
        case .onBreak: "On a break"
        case .off: "Off the clock"
        }
    }

    private var phaseTone: StatusPill.Tone {
        switch card.phase {
        case .working: .working
        case .lunch, .onBreak: .onBreak
        case .off: .off
        }
    }

    /// "Row 6, Block 1", large, with the next rows under it.
    private var whereBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let here = card.here {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        bigRow(here)
                        blockName(here)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        bigRow(here)
                        blockName(here)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("You’re on \(here.block), row \(here.row)")
                if !card.next.isEmpty { nextChips }
            } else {
                allShaped
            }
        }
    }

    /// "Row 6" set as a heading: it names a place, like a sign at the end of the row.
    private func bigRow(_ here: DayCard.Spot) -> some View {
        Text("Row \(here.row)")
            .font(.custom(Typeface.headingBold, size: 40, relativeTo: .largeTitle))
            .foregroundStyle(Palette.firText)
            .fixedSize()
    }

    private func blockName(_ here: DayCard.Spot) -> some View {
        Text(here.block)
            .font(.tcTitle2)
            .foregroundStyle(Palette.muted)
            .fixedSize()
    }

    /// The row you're on, under the numbers: "→ Row 15  Block 2   next 16 · 17".
    @ViewBuilder private var rowLine: some View {
        if let here = card.here {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    hereLabel(here)
                    Spacer(minLength: 8)
                    nextLabel(here)
                }
                VStack(alignment: .leading, spacing: 4) {
                    hereLabel(here)
                    nextLabel(here)
                }
            }
        } else if card.fieldTotal > 0 {
            allShaped
        }
    }

    private func hereLabel(_ here: DayCard.Spot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.forward.circle.fill")
                .foregroundStyle(Palette.fir)
                .accessibilityHidden(true)
            Text("Row \(here.row)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            Text(here.block)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You’re on \(here.block), row \(here.row)")
    }

    @ViewBuilder private func nextLabel(_ here: DayCard.Spot) -> some View {
        if !card.next.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("next").font(.caption).foregroundStyle(Palette.muted)
                Text(card.next.map { $0.block == here.block ? String($0.row) : "\($0.block), \($0.row)" }.joined(separator: ", "))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
    }

    private var nextChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                nextTitle
                ForEach(card.next, id: \.self, content: chip)
            }
            VStack(alignment: .leading, spacing: 6) {
                nextTitle
                ForEach(card.next, id: \.self, content: chip)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var nextTitle: some View {
        Text("NEXT")
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.muted)
    }

    private func chip(_ spot: DayCard.Spot) -> some View {
        Text(spot.block == card.here?.block ? "Row \(spot.row)" : "\(spot.block), row \(spot.row)")
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Palette.firText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.firSoft, in: Capsule())
            .fixedSize()
    }

    private var allShaped: some View {
        Label("Every row is shaped", systemImage: "checkmark.seal.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.firText)
    }

    private var payHidden: some View {
        Label {
            Text("Pay stays hidden while the phone is locked.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(.callout)
        .foregroundStyle(Palette.muted)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.line)
                    Capsule().fill(Palette.fir)
                        .frame(width: max(card.fieldShaped > 0 ? 6 : 0, geo.size.width * card.fieldProgress))
                }
            }
            .frame(height: 6)
            Text("\(Fmt.count(card.fieldShaped)) of \(Fmt.count(card.fieldTotal)) trees shaped")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Fmt.count(card.fieldShaped)) of \(Fmt.count(card.fieldTotal)) trees in \(card.fieldName) shaped")
    }
}

/// Three numbers across, or stacked when the text is large.
private struct StatRow: View {
    let stats: [SnippetStat]
    let compact: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ForEach(stats) { stat in
                    StatView(stat: stat, compact: compact, stacked: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(stats) { stat in
                    StatView(stat: stat, compact: compact, stacked: true)
                }
            }
        }
    }
}

private struct StatView: View {
    let stat: SnippetStat
    let compact: Bool
    let stacked: Bool

    var body: some View {
        let value = Text(stat.value)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(stat.focus ? Palette.firText : Palette.ink)
            .lineLimit(1)
        let label = Text(stat.label)
            .font(.caption)
            .foregroundStyle(Palette.muted)
        Group {
            if stacked {
                HStack(alignment: .firstTextBaseline, spacing: 8) { value; label }
            } else {
                VStack(alignment: .leading, spacing: 2) { value; label }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.spoken)
    }

    private var font: Font {
        if compact { return .tcNumber }
        return stat.focus ? .custom(Typeface.numberSemiBold, size: 34, relativeTo: .title) : .tcStat
    }
}

#Preview("Status cards") {
    let card = DayCard(topic: .trees, phase: .working, fieldName: "North Field", worked: 6 * 3600 + 40 * 60,
                       workedWeek: 31 * 3600 + 12 * 60, trees: 212, treesPerHour: 33.8, seasonTreesPerHour: 29.4,
                       here: .init(block: "Block 2", row: 15), next: [.init(block: "Block 2", row: 16), .init(block: "Block 2", row: 17)],
                       fieldShaped: 1204, fieldTotal: 8540, pay: nil, payHidden: false)
    ScrollView {
        VStack(spacing: 16) {
            ForEach([StatusTopic.trees, .hours, .whereAmI, .pace], id: \.self) { topic in
                DaySnippetView(card: card.with(topic: topic)).card(padding: 0)
            }
        }
        .padding()
    }
    .screenBackground()
}
