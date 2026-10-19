import SwiftUI
import TimeCardCore

// Small pieces the Team tab's screens share. Every tap target is glove-sized (54 pt).

/// A segmented choice with glove-sized segments: the selected one is fir green.
struct GloveSegmented<Value: Hashable>: View {
    var options: [(value: Value, title: String, identifier: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // Every segment the same size, even at the largest text sizes.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(selected ? Palette.firInk : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.fir)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(option.identifier)
            }
        }
        .padding(4)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A big selectable card: a title, a line of detail, and a check when chosen.
struct ChoiceTile: View {
    var title: String
    var detail: String?
    var systemImage: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? Palette.firText : Palette.muted)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Palette.fir : Palette.line)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight, alignment: .leading)
            .background(selected ? Palette.firSoft : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Palette.fir : Palette.line, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A whole number with big minus and plus buttons on either side, for sizes like rows and trees.
struct GloveNumberField: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var identifier: String
    var focus: FocusState<String?>.Binding

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                stepButton("minus", label: "One fewer", disabled: value <= range.lowerBound) { set(value - 1) }
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.tcStat)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                    .focused(focus, equals: identifier)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(identifier)
                    .onChange(of: text) { _, new in
                        let digits = String(new.filter(\.isASCII).filter(\.isNumber).prefix(4))
                        if digits != new { text = digits }
                        value = Int(digits) ?? 0
                    }
                stepButton("plus", label: "One more", disabled: value >= range.upperBound) { set(value + 1) }
            }
        }
        .id(identifier)
        .onAppear { text = value > 0 ? String(value) : "" }
        .onChange(of: value) { _, new in
            if Int(text) != new { text = new > 0 ? String(new) : "" }
        }
    }

    private func set(_ new: Int) {
        value = min(max(new, range.lowerBound), range.upperBound)
        text = String(value)
    }

    private func stepButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .frame(width: GloveButtonStyle.minHeight + 6, height: GloveButtonStyle.minHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel("\(label): \(title)")
        .buttonRepeatBehavior(.enabled)
    }
}

/// A labeled text field in the glove style.
struct LabeledGloveField: View {
    var title: String
    var prompt: String
    @Binding var text: String
    var identifier: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            TextField(prompt, text: $text)
                .textFieldStyle(.glove)
                .accessibilityIdentifier(identifier)
            if let footnote {
                Text(footnote).font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A round badge with a person's initials.
struct Avatar: View {
    var name: String
    var size: CGFloat = 44
    var dimmed = false

    var body: some View {
        Text(initials)
            .font(.custom(Typeface.headingBold, size: size * 0.4, relativeTo: .headline))
            .foregroundStyle(dimmed ? Palette.muted : Palette.firText)
            .frame(width: size, height: size)
            .background(dimmed ? Palette.stripe : Palette.firSoft, in: Circle())
            .overlay(Circle().strokeBorder((dimmed ? Palette.line : Palette.fir).opacity(0.3), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = [words.first?.first, words.count > 1 ? words.last?.first : nil].compactMap { $0 }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

/// A number with its label, for the stat rows.
struct TeamStat: View {
    var label: String
    var value: String
    var unit: String?
    var accessibilityValue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).numberStyle(.stat).foregroundStyle(Palette.ink)
                if let unit {
                    Text(unit).font(.subheadline).foregroundStyle(Palette.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue ?? [value, unit].compactMap { $0 }.joined(separator: " "))
    }
}

/// Stats side by side, or one above the other at the largest text sizes.
struct TeamStatRow<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) { content }
        } else {
            HStack(alignment: .top, spacing: 16) { content }
        }
    }
}

/// The hairline between rows in a card.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

/// A calm note in sap gold: warnings that aren't errors.
struct NoticeBox<Content: View>: View {
    var systemImage: String = "exclamationmark.circle"
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.sapInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Palette.sapSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.sap.opacity(0.45), lineWidth: 1))
    }
}

/// The text of a crew row's status: "Working since 7:02 AM", "On lunch since 11:45 AM".
enum CrewStatusText {
    /// The day is added when it began before today: "Working since Sun, Oct 18 at 11:52 PM".
    static func line(_ status: CrewRow.Status, calendar: FarmCalendar, now: Date = Date()) -> String? {
        func since(_ date: Date) -> String {
            calendar.isSameDay(date, now) ? Fmt.time(date, calendar) : "\(Fmt.day(date, calendar)) at \(Fmt.time(date, calendar))"
        }
        switch status {
        case .working(let start): return "Working since \(since(start))"
        case .onBreak(let kind, let start): return "On \(kind == .lunch ? "lunch" : "a break") since \(since(start))"
        case .off: return nil
        }
    }

    static func tone(_ status: CrewRow.Status) -> StatusPill.Tone {
        switch status {
        case .working: .working
        case .onBreak: .onBreak
        case .off: .off
        }
    }
}

extension View {
    /// The Team tab's page width and padding.
    func teamPage() -> some View {
        padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
    }
}
