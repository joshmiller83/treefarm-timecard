import SwiftUI
import TreeFarmKit
import WidgetKit

// The four accessory families (docs/watch.md 4.3), built for a glance on a wrist raise: the
// timer and the next row are the biggest things, the phase has a glyph and a word as well as a
// color, and nothing needs a tap but opening the app. Timers and glyphs are `.widgetAccentable()`,
// so a tinted face colors them and leaves the words plain. Every timer has a set width, one
// line and room to shrink, since Always On may write "3:41" as "3 hr".

/// Picks the family's layout.
struct ShiftComplicationView: View {
    var entry: ShiftComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let face = ComplicationFace(entry)
        Group {
            switch family {
            case .accessoryCircular: CircularComplication(face: face)
            case .accessoryCorner: CornerComplication(face: face)
            case .accessoryInline: InlineComplication(face: face)
            default: RectangularComplication(face: face)
            }
        }
        .containerBackground(for: .widget) {
            ComplicationStyle.background(face.tone)
        }
    }
}

// MARK: - Circular

/// Working: a ring filling over an eight-hour day around the leaf and the next row. On a break:
/// the ring stops, and the break's own timer sits under the cup. Off the clock: hours today, or
/// "IN" as the invitation to clock in.
struct CircularComplication: View {
    var face: ComplicationFace

    var body: some View {
        ZStack {
            ring
            VStack(spacing: 1) {
                Image(systemName: face.glyph)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ComplicationStyle.tint(face.tone))
                    .widgetAccentable()
                centre
            }
            // Clear of the ring's stroke on the smallest (40 mm) face.
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var ring: some View {
        switch face.tone {
        case .working:
            if let start = face.timerStart {
                ProgressView(timerInterval: start...start.addingTimeInterval(ComplicationFace.ringDay), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(ComplicationStyle.firRing)
                .widgetAccentable()
            }
        case .onBreak:
            ProgressView(value: face.frozenRing)
                .progressViewStyle(.circular)
                .tint(ComplicationStyle.sap)
                .widgetAccentable()
        case .offClock, .none:
            AccessoryWidgetBackground()
        }
    }

    @ViewBuilder
    private var centre: some View {
        switch face.tone {
        case .working:
            if let row = face.rowNumber {
                Text(row)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .trimmedLineBox(19)
            } else if let glyph = face.noRowGlyph {
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .bold))
            }
        case .onBreak:
            if let start = face.breakStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: false)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .trimmedLineBox(13)
            }
        case .offClock:
            Text(face.hoursMark)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .trimmedLineBox(16)
        case .none:
            Text(WatchDisplay.noDataMark)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .trimmedLineBox(16)
        }
    }
}

// MARK: - Rectangular (also the Smart Stack widget)

/// Three lines: where you are, the big timer (or "Clock in"), and what's next. While taps wait
/// for the phone, line 3 says so instead. The sizes step down to fit the face: roomy on 49 mm
/// and in the Smart Stack, tighter on 44–46 mm, compact on 40–42 mm (150 × 47 pt).
struct RectangularComplication: View {
    var face: ComplicationFace

    var body: some View {
        ViewThatFits(in: .vertical) {
            RectangularLines(face: face, metrics: .roomy)
            RectangularLines(face: face, metrics: .regular)
            RectangularLines(face: face, metrics: .compact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Point sizes for the three lines. Complications keep the face's sizes, so these are fixed.
struct RectangularMetrics: Hashable {
    var title: CGFloat
    var big: CGFloat
    var detail: CGFloat

    /// 49 mm (184 × 59 pt) and the Smart Stack.
    static let roomy = RectangularMetrics(title: 15, big: 25, detail: 13.5)
    /// 44–46 mm (about 162–178 × 54–56 pt).
    static let regular = RectangularMetrics(title: 14, big: 22.5, detail: 12.5)
    /// 40–42 mm (150 × 47 pt).
    static let compact = RectangularMetrics(title: 12.5, big: 19.5, detail: 11.5)
}

struct RectangularLines: View {
    var face: ComplicationFace
    var metrics: RectangularMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: face.glyph)
                    .foregroundStyle(ComplicationStyle.tint(face.tone))
                    .widgetAccentable()
                ViewThatFits(in: .horizontal) {
                    Text(face.title)
                    Text(face.shortTitle)
                }
            }
            .font(.system(size: metrics.title, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            big
                .foregroundStyle(ComplicationStyle.tint(face.tone))
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .trimmedLineBox(metrics.big)

            if let detail = face.detail {
                HStack(spacing: 3) {
                    if face.detailIsWaiting {
                        Image(systemName: WatchDisplay.queueGlyph)
                            .foregroundStyle(ComplicationStyle.sap)
                    }
                    Text(detail)
                }
                .font(.system(size: metrics.detail, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var big: some View {
        switch face.tone {
        case .working:
            if let start = face.timerStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(ComplicationStyle.timer(size: metrics.big))
            }
        case .onBreak:
            if let start = face.breakStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(ComplicationStyle.timer(size: metrics.big))
            }
        case .offClock:
            Text(WatchDisplay.clockIn)
                .font(.system(size: metrics.big, weight: .semibold, design: .rounded))
        case .none:
            Text(WatchDisplay.openOnPhone)
                .font(.system(size: metrics.big * 0.8, weight: .semibold, design: .rounded))
        }
    }
}

// MARK: - Corner

/// The phase glyph in the corner, with the curved label beside it: "3:41:07 R14" working,
/// "Lunch 12:40" on a break, "6.5 h today" off the clock.
struct CornerComplication: View {
    var face: ComplicationFace

    var body: some View {
        Image(systemName: face.glyph)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(ComplicationStyle.tint(face.tone))
            .widgetAccentable()
            .widgetCurvesContent()
            .widgetLabel {
                label
                    .foregroundStyle(ComplicationStyle.tint(face.tone))
            }
            .accessibilityElement(children: .combine)
    }

    var label: Text {
        switch face.tone {
        case .working:
            guard let start = face.timerStart else { return Text(WatchDisplay.phaseTitle(.working)) }
            let timer = Text(timerInterval: start...Date.distantFuture, countsDown: false)
            return face.cornerRow.map { timer + Text(" \($0)") } ?? timer
        case .onBreak:
            guard let start = face.breakStart else { return Text(face.breakWord) }
            return Text("\(face.breakWord) ") + Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: false)
        case .offClock:
            return Text(face.hoursLine)
        case .none:
            return Text(WatchDisplay.appName)
        }
    }
}

// MARK: - Inline

/// One line over the time: "🍃 3:41:07 · Row 14", "☕ Lunch 12:40 · 3:41 worked", "🍃 6.5 h today".
struct InlineComplication: View {
    var face: ComplicationFace

    var body: some View {
        switch face.tone {
        case .none:
            Text(WatchDisplay.appName)
        default:
            Label {
                line
            } icon: {
                Image(systemName: face.glyph)
            }
        }
    }

    private var line: Text {
        switch face.tone {
        case .working:
            guard let start = face.timerStart else { return Text(face.inlineDetail) }
            return Text(timerInterval: start...Date.distantFuture, countsDown: false) + Text(" · \(face.inlineDetail)")
        case .onBreak:
            guard let start = face.breakStart else { return Text(face.inlineDetail) }
            return Text("\(face.breakWord) ") + Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: false)
                + Text(" · \(face.inlineDetail)")
        case .offClock, .none:
            return Text(face.inlineDetail)
        }
    }
}
