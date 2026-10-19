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
                    .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight - 6)
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
        .frame(minHeight: GloveButtonStyle.minHeight)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: model.mode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What a tap does")
    }
}

/// What the last tap did (or a hint), its follow-up button, and Undo.
struct MessageBar: View {
    @Bindable var model: TreeMapModel

    private var message: MapMessage {
        if let message = model.message { return message }
        if model.zoom == .all { return MapMessage("This is the whole field. Tap a block to zoom in and mark trees.", tone: .hint) }
        return MapMessage(model.mode.hint, tone: .hint)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
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
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("trees-message")
            }
            if let action = message.action {
                Button(action.title) { model.perform(action) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.firText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: GloveButtonStyle.minHeight)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                    .accessibilityIdentifier("trees-message-action")
            }
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
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
        .frame(minHeight: GloveButtonStyle.minHeight)
        .animation(.easeOut(duration: 0.15), value: message)
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

/// All / XS / S / M / L, floating over the bottom of the map.
struct ZoomBar: View {
    @Bindable var model: TreeMapModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MapZoom.allCases) { zoom in
                let selected = model.zoom == zoom
                Button {
                    model.setZoom(zoom)
                } label: {
                    Text(zoom.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selected ? Palette.firText : Palette.ink)
                        .frame(width: 50, height: GloveButtonStyle.minHeight)
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
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
                .frame(width: GloveButtonStyle.minHeight + 6, height: GloveButtonStyle.minHeight + 6)
                .background(Palette.surface.opacity(0.94), in: Circle())
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
