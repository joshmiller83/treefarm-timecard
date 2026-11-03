import SwiftUI
import TreeFarmKit

/// The field log's page (docs/gis.md 10), right of Now while a log is written: what you're
/// doing, for how long, and the buttons that say so. Shaping starts on a row and ends with
/// Stop row or the row's mark; Prep and Rest cover the rest of the time on the clock. Lunch
/// and Break stay on Controls (they pause the workout). No Double Tap here.
struct ActivityScreen: View {
    let state: WatchState
    let labels: FieldLabels

    private let metrics = ButtonMetrics.current

    var body: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(FieldActivityCopy.title(labels.activity, row: labels.row))
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(timerInterval: labels.since...Date.distantFuture, countsDown: false)
                    .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(labels.activity == .shaping ? Color.white : WatchPalette.sap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            FieldRowButton(state: state, labels: labels, height: metrics.secondary)

            HStack(spacing: 6) {
                choice(.prep, glyph: "shippingbox.fill", id: "prep")
                choice(.rest, glyph: "cup.and.saucer.fill", id: "rest")
            }
        }
        .padding(.horizontal, 2)
    }

    private func choice(_ activity: FieldActivity, glyph: String, id: String) -> some View {
        let current = labels.activity == activity
        return Button {
            labels.choose(activity)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: current ? "checkmark" : glyph)
                    .font(.system(.title3).weight(.bold))
                Text(FieldActivityCopy.name(activity))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
            }
        }
        .buttonStyle(GloveButtonStyle(tone: current ? .quiet : .sap, height: metrics.secondary + 8, cornerRadius: 18))
        .disabled(current)
        .accessibilityLabel(FieldActivityCopy.name(activity))
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// Start row (the next row, as Now shows it) or, while shaping, Stop row. On Now and on the
/// field log's page.
struct FieldRowButton: View {
    let state: WatchState
    let labels: FieldLabels
    let height: CGFloat
    var chip: RowChip?

    var body: some View {
        if labels.activity == .shaping {
            Button {
                labels.choose(.prep)
            } label: {
                GloveLabel(steps: [FieldActivityCopy.stop(labels.row), FieldActivityCopy.stopShort], glyph: "stop.fill",
                           font: .system(.headline, design: .rounded))
            }
            .buttonStyle(GloveButtonStyle(tone: .quiet, height: height))
            .accessibilityIdentifier("stopRow")
        } else if let next = chip ?? WatchDisplay.chips(state).first {
            Button {
                labels.startRow(next)
            } label: {
                GloveLabel(steps: [FieldActivityCopy.start(next), FieldActivityCopy.startShort], glyph: "play.fill",
                           font: .system(.headline, design: .rounded))
            }
            .buttonStyle(GloveButtonStyle(tone: .sap, height: height))
            .accessibilityIdentifier("startRow")
        }
    }
}

/// The field log page's words.
enum FieldActivityCopy {
    static let startShort = "Start row"
    static let stopShort = "Stop row"

    static func name(_ activity: FieldActivity) -> String {
        switch activity {
        case .shaping: "Shaping"
        case .prep: "Prep"
        case .rest: "Rest"
        }
    }

    /// "Shaping row 50", "Prep", "Rest".
    static func title(_ activity: FieldActivity, row: RowChip?) -> String {
        guard activity == .shaping, let row else { return name(activity) }
        return "Shaping \(row.title.lowercased())"
    }

    /// "Start row 50"
    static func start(_ chip: RowChip) -> String { "Start \(chip.title.lowercased())" }

    /// "Stop row 50"
    static func stop(_ chip: RowChip?) -> String {
        chip.map { "Stop \($0.title.lowercased())" } ?? stopShort
    }
}
