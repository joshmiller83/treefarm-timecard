import SwiftUI

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

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    if let tag {
                        Text(tag)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.sapInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Palette.sapSoft, in: Capsule())
                    }
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Two or three big choices side by side (Lunch | Break, This week | Last week | …).
struct GloveSegmented<Value: Hashable>: View {
    var options: [(value: Value, title: String)]
    @Binding var selection: Value
    var identifier: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let selected = option.value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(selected ? Palette.firText : Palette.ink)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
                        .background(selected ? Palette.firSoft : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.fir.opacity(0.35), lineWidth: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("\(identifier)-\(option.title)")
            }
        }
        .padding(4)
        .background(Palette.stripe, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                    number
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
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
