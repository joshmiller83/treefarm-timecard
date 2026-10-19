import SwiftUI
import UIKit

/// A tall row that shows a value and opens a picker under itself when tapped, like the
/// Calendar app's time rows, sized for gloves.
struct PickerRow<Picker: View>: View {
    var title: String
    var value: String
    /// A small tag after the value, such as "Next day".
    var tag: String? = nil
    /// Times read in Plex Mono; dates in the body font.
    var monospaced = true
    var isExpanded: Bool
    var identifier: String
    var toggle: () -> Void
    @ViewBuilder var picker: Picker
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                Group {
                    if typeSize.isAccessibilitySize {
                        // The title over the value, so "9:15 AM" keeps the whole width.
                        VStack(alignment: .leading, spacing: 6) {
                            titleText
                            HStack(spacing: 10) {
                                valueBox
                                tagText
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    } else {
                        HStack(spacing: 10) {
                            titleText
                            Spacer(minLength: 8)
                            tagText
                            valueBox
                        }
                    }
                }
                .frame(minHeight: GloveButtonStyle.minHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue([value, tag].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint(isExpanded ? "Closes the picker" : "Opens a picker")
            .accessibilityIdentifier(identifier)

            if isExpanded {
                picker
                    .frame(maxWidth: .infinity)
                    .transition(.slide(from: .top, reduceMotion: UIAccessibility.isReduceMotionEnabled))
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.body)
            .foregroundStyle(Palette.ink)
    }

    @ViewBuilder
    private var tagText: some View {
        if let tag {
            Text(tag)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.sapInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.sapSoft, in: Capsule())
        }
    }

    private var valueBox: some View {
        Group {
            if monospaced {
                Text(value).numberStyle(.body)
            } else {
                Text(value).font(.body.weight(.medium))
            }
        }
        .foregroundStyle(isExpanded ? Palette.firText : Palette.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isExpanded ? Palette.firSoft : Palette.stripe, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isExpanded ? Palette.fir.opacity(0.35) : Palette.line, lineWidth: 1))
    }
}

extension String {
    /// "Oct 12 – Oct 18, 2026" with no-break spaces inside each date, so a long line wraps
    /// after the dash and never inside a date ("Oct" / "18").
    var wrappingOnlyAtDash: String {
        components(separatedBy: " – ")
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: "\u{00A0}– ")
    }
}

/// A short, calm message that floats above the tab bar for a few seconds.
struct Toast: View {
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.fir)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("log-toast")
    }
}

extension View {
    /// Shows `message` as a toast, clears it after a few seconds, and reads it to VoiceOver.
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                Toast(text: text)
                    .padding(.bottom, 12)
                    .transition(.slide(from: .bottom, reduceMotion: UIAccessibility.isReduceMotionEnabled))
                    .task(id: text) {
                        AccessibilityNotification.Announcement(text).post()
                        try? await Task.sleep(for: .seconds(3.5))
                        withAnimation(.easeInOut(duration: 0.25)) { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: message.wrappedValue)
    }
}

/// Totals side by side at one size: all in a row when they fit at full size, else two by two,
/// and one per line at the largest text sizes. Never each column shrunk on its own, which made
/// "$735.67" look smaller than "38.25" beside it.
struct StatRow: View {
    struct Stat: Identifiable {
        var label: String
        var value: String
        var identifier: String?
        var id: String { identifier ?? label }
    }

    var stats: [Stat]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) { columns(stats) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { columns(stats) }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { i in
                        GridRow {
                            columns(Array(stats[i..<min(i + 2, stats.count)]))
                        }
                    }
                }
            }
        }
    }

    private func columns(_ items: [Stat]) -> some View {
        ForEach(items) { stat in
            StatColumn(label: stat.label, value: stat.value, identifier: stat.identifier)
        }
    }
}

/// A labeled number for totals: "HOURS  38.25".
/// At the largest text sizes it becomes a row (label left, number right) inside an
/// `AdaptiveStack`, so numbers are never squeezed or cut.
struct StatColumn: View {
    var label: String
    var value: String
    var identifier: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline) {
                    caption
                    Spacer(minLength: 8)
                    number
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    caption
                    // Whole, at full size: `StatRow` makes room instead.
                    number
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "stat-\(label.lowercased())")
    }

    private var caption: some View {
        Text(label.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.muted)
    }

    private var number: some View {
        Text(value)
            .numberStyle(.stat)
            .foregroundStyle(Palette.ink)
    }
}

/// Side by side, or stacked at the accessibility text sizes where side by side would
/// break words ("Tree s").
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 10
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}
