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
                .accessibilityInputLabels([mode.title, mode.spokenTitle])
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityShowsLargeContentViewer { Label(mode.title, systemImage: mode.systemImage) }
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
    /// The rows are a list: the hint talks about rows, not trees.
    var showsList = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// What the last tap did, or a hint. The mode's hint goes once a tree has been marked here.
    private var message: MapMessage? {
        if let message = model.message { return message }
        if model.zoom == .all && !showsList { return MapMessage("This is the whole field. Tap a block to zoom in and mark trees.", tone: .hint) }
        if model.hasMarked { return nil }
        return MapMessage(showsList ? model.mode.listHint : model.mode.hint, tone: .hint)
    }

    var body: some View {
        // At the largest sizes a follow-up button goes under the words with Undo, so the words
        // keep the width. Otherwise Undo sits beside them.
        Group {
            if typeSize.isAccessibilitySize && message?.action != nil {
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

    /// One view whatever the message (or none), so a change never swaps the layout mid-animation.
    private var text: some View {
        let shown = message
        let tone = shown?.tone ?? .hint
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon(tone) ?? "circle")
                .font(.footnote.weight(.bold))
                .foregroundStyle(tone == .warning ? Palette.sap : Palette.fir)
                .opacity(icon(tone) == nil ? 0 : 1)
                .frame(width: icon(tone) == nil ? 0 : nil)
                .accessibilityHidden(true)
            Text(shown?.text ?? "")
                .font(.subheadline)
                .foregroundStyle(tone == .hint ? Palette.muted : Palette.ink)
                // A hint never pushes the map off the screen; what a tap did is always shown whole.
                .lineLimit(tone == .hint ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(shown == nil)
                .accessibilityIdentifier(shown == nil ? "" : "trees-message")
        }
        // What a tap did follows the person's text size all the way; a hint stops growing.
        .dynamicTypeSize(...(tone == .hint ? DynamicTypeSize.accessibility1 : .accessibility5))
    }

    @ViewBuilder private var actionButton: some View {
        if let action = message?.action {
            Button(action.title) { model.perform(action) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.firText)
                .padding(.horizontal, 12)
                .frame(minWidth: GloveButtonStyle.minHeight, minHeight: GloveButtonStyle.minHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityShowsLargeContentViewer { Text(action.title) }
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
        .accessibilityShowsLargeContentViewer { Label("Undo", systemImage: "arrow.uturn.backward") }
        .accessibilityIdentifier("trees-undo")
    }

    private func icon(_ tone: MapMessage.Tone) -> String? {
        switch tone {
        case .hint: nil
        case .done: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        }
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
                .accessibilityInputLabels([zoom.title, "Map size \(zoom.title)", zoom.spokenTitle])
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityShowsLargeContentViewer { Text(zoom.spokenTitle) }
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
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: systemImage) }
    }
}
