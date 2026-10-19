import SwiftUI
import TimeCardCore

/// One / Fill / Erase / Notes as four big segments.
struct ModePicker: View {
    @Bindable var model: TreeMapModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MapMode.allCases) { mode in
                let selected = model.mode == mode
                Button {
                    model.mode = mode
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(height: 20)
                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Palette.firInk : Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
                    .background(selected ? Palette.fir : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.spokenTitle)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("mode-\(mode.rawValue)")
            }
        }
        .padding(3)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(.selection, trigger: model.mode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What a tap does")
    }
}

/// What the last tap did (or a hint), its follow-up button, and Undo.
struct MessageBar: View {
    @Bindable var model: TreeMapModel
    @Environment(\.dynamicTypeSize) private var typeSize

    private var message: MapMessage {
        if let message = model.message { return message }
        if model.zoom == .all { return MapMessage("This is the whole field. Tap a block to zoom in and mark trees.", tone: .hint) }
        return MapMessage(model.mode.hint, tone: .hint)
    }

    var body: some View {
        // At the largest sizes the buttons go under the words, so the words keep the width.
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    text
                    HStack(spacing: 10) {
                        actionButton
                        Spacer(minLength: 0)
                        undoButton
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    text
                    actionButton
                    undoButton
                }
                .frame(minHeight: GloveButtonStyle.minHeight)
            }
        }
        .animation(.easeOut(duration: 0.15), value: message)
    }

    private var text: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.tone == .hint ? Palette.muted : Palette.ink)
                // A hint never pushes the map off the screen; what a tap did is always shown whole.
                .lineLimit(message.tone == .hint ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("trees-message")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder private var actionButton: some View {
        if let action = message.action {
            Button(action.title) { model.perform(action) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.firText)
                .padding(.horizontal, 12)
                .frame(minWidth: GloveButtonStyle.minHeight, minHeight: GloveButtonStyle.minHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityIdentifier("trees-message-action")
        }
    }

    private var undoButton: some View {
        Button {
            model.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: GloveButtonStyle.minHeight, height: GloveButtonStyle.minHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canUndo)
        .opacity(model.canUndo ? 1 : 0.4)
        .accessibilityLabel("Undo")
        .accessibilityIdentifier("trees-undo")
    }

    private var icon: String? {
        switch message.tone {
        case .hint: nil
        case .done: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        message.tone == .warning ? Palette.sap : Palette.fir
    }
}

/// All / XS / S / M / L, floating over the bottom of the map. Each size is a 54-point
/// square; on a phone too narrow for that they slim down rather than spill over.
struct ZoomBar: View {
    @Bindable var model: TreeMapModel

    static let wide: CGFloat = GloveButtonStyle.minHeight
    static let narrow: CGFloat = 46

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(width: Self.wide)
            bar(width: Self.narrow)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func bar(width: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(MapZoom.allCases) { zoom in
                let selected = model.zoom == zoom
                Button {
                    model.setZoom(zoom)
                } label: {
                    Text(zoom.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selected ? Palette.firText : Palette.ink)
                        .frame(width: width, height: GloveButtonStyle.minHeight)
                        .background(selected ? Palette.firSoft : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Map size: \(zoom.spokenTitle)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("zoom-\(zoom.rawValue)")
            }
        }
        .padding(3)
        .background(Palette.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .fixedSize()
    }
}

/// A round floating button over the map.
struct MapRoundButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.firText)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: GloveButtonStyle.minHeight, height: GloveButtonStyle.minHeight)
                .background(Palette.surface.opacity(0.94), in: Circle())
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
