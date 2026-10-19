import SwiftUI
import TimeCardCore

/// The field's name (a menu when there are more fields), how much of it is shaped, and how
/// long the rest might take at your pace.
struct FieldHeader: View {
    @Bindable var model: TreeMapModel
    var showsList: Bool
    var toggleList: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                fieldTitle
                Spacer(minLength: 4)
                Button(action: toggleList) {
                    Image(systemName: showsList ? "map" : "list.bullet")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.firText)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(width: GloveButtonStyle.minHeight, height: GloveButtonStyle.minHeight)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsList ? "Show the map" : "Show rows as a list")
                .accessibilityIdentifier("trees-list-toggle")
            }
            if let progress = model.progress {
                ProgressLine(progress: progress)
            }
        }
    }

    @ViewBuilder private var fieldTitle: some View {
        let name = model.field?.name ?? "Trees"
        if model.fields.count > 1 {
            Menu {
                Picker("Field", selection: Binding(get: { model.field?.id }, set: { model.chosenFieldId = $0 })) {
                    ForEach(model.fields) { field in
                        Text(field.name).tag(Optional(field.id))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.tcTitle)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Palette.firText)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .frame(minHeight: GloveButtonStyle.minHeight)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Field: \(name)")
            .accessibilityHint("Picks another field.")
            .accessibilityIdentifier("trees-field-picker")
        } else {
            Text(name)
                .font(.tcTitle)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minHeight: GloveButtonStyle.minHeight)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// A fir bar with "7% · 72 of 960", then the time left at your pace.
private struct ProgressLine: View {
    var progress: FieldProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.firSoft)
                        Capsule().fill(Palette.fir)
                            .frame(width: progress.shaped > 0 ? max(8, proxy.size.width * progress.fraction) : 0)
                    }
                }
                .frame(height: 8)
                Text("\(progress.percent)% · \(Fmt.count(progress.shaped)) of \(Fmt.count(progress.total))")
                    .font(.tcNumberSmall.weight(.semibold))
                    .foregroundStyle(Palette.firText)
                    .fixedSize()
            }
            Text(progress.timeLeft ?? (progress.shaped < progress.total ? "\(Fmt.plural(progress.total - progress.shaped, "tree")) to go." : progress.summary))
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Field progress")
        .accessibilityValue("\(progress.percent) percent. " + [progress.summary, progress.timeLeft].compactMap { $0 }.joined(separator: " "))
        .accessibilityIdentifier("field-progress")
    }
}

/// What the dots mean.
struct MapLegend: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var pips

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow { notYet; earlier }
                GridRow { thisShift; note }
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.muted)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: rings are not shaped yet, green dots were shaped earlier, gold dots on this shift, and a red corner means the tree has notes.")
    }

    @ViewBuilder private var items: some View {
        notYet
        earlier
        thisShift
        note
    }

    private var notYet: some View { item("Not yet") { Circle().strokeBorder(Color.mapTreeEmpty, lineWidth: 1.6) } }
    private var earlier: some View { item("Earlier") { Circle().fill(Palette.fir) } }
    private var thisShift: some View {
        item("This shift") {
            ZStack {
                Circle().fill(Palette.sap)
                if pips { Circle().fill(Palette.surface).padding(3.5) }
            }
        }
    }
    private var note: some View { item("Note") { NoteCorner().fill(Palette.rust).padding(1) } }

    private func item<S: View>(_ title: String, @ViewBuilder swatch: () -> S) -> some View {
        HStack(spacing: 5) {
            swatch().frame(width: 11, height: 11)
            Text(title).lineLimit(1).fixedSize()
        }
    }
}

/// The note marker's shape: the top-right corner of a cell.
struct NoteCorner: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// "Marking trees for": which shift new marks go on, with a note when it isn't the one on
/// the clock, or when the one on the clock was left open from an earlier day.
struct MarkingForBar: View {
    @Bindable var model: TreeMapModel
    var clockIn: () -> Void
    var addShift: () -> Void
    /// Opens the shift editor on this shift ("Fix the times").
    var fixShift: (UUID) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Gold when trees go somewhere other than today's shift on the clock.
    private var highlighted: Bool { model.isMarkingEarlierShift || model.isMarkingStaleShift }

    var body: some View {
        if let shift = model.markingShift {
            VStack(alignment: .leading, spacing: 8) {
                picker(shift)
                if model.isMarkingEarlierShift {
                    note("This is an earlier shift, not the one you’re clocked in on.",
                         button: model.openShiftIsToday ? "Switch to today’s shift" : "Switch to the shift you’re on",
                         id: "use-open-shift") {
                        model.useOpenShift()
                    }
                } else if let stale = model.staleShiftNote {
                    note("\(stale) \(Speech.fixTheTimes)", button: "Fix the times", id: "trees-fix-times", icon: "exclamationmark.triangle.fill") {
                        fixShift(shift.id)
                    }
                    .accessibilityIdentifier("trees-stale-shift")
                } else if model.openShift == nil {
                    note("You’re not clocked in, so trees you mark go on this shift.", button: nil, id: nil) {}
                }
            }
        } else {
            noShift
        }
    }

    private func picker(_ shift: Shift) -> some View {
        Menu {
            Picker("Marking trees for", selection: Binding(get: { model.markingShift?.id }, set: { model.pickShift($0) })) {
                ForEach(model.pickerShifts) { s in
                    Text(model.shiftTitle(s)).tag(Optional(s.id))
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("MARKING TREES FOR")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .lineLimit(1)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .foregroundStyle(highlighted ? Palette.sapInk : Palette.muted)
                    Text(model.shiftTitle(shift))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.firText)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight, alignment: .leading)
            .background(highlighted ? Palette.sapSoft : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(highlighted ? Palette.sap : Palette.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityLabel("Marking trees for")
        .accessibilityValue(model.shiftTitle(shift))
        .accessibilityHint("Picks the shift new marks go on.")
        .accessibilityIdentifier("marking-for")
    }

    private func note(_ text: String, button: String?, id: String?, icon: String? = nil, action: @escaping () -> Void) -> some View {
        // Side by side when there's room; the button drops below the words at the largest sizes.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                  : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(Palette.sap)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .foregroundStyle(Palette.sapInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let button {
                Button(button, action: action)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.sapInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .frame(minWidth: GloveButtonStyle.minHeight, minHeight: GloveButtonStyle.minHeight)
                    .background(Palette.sapSoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.sap, lineWidth: 1))
                    .contentShape(Capsule())
                    .accessibilityIdentifier(id ?? "")
            }
        }
        .padding(.horizontal, 4)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
    }

    private var noShift: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.firText)
                    .frame(width: 40, height: 40)
                    .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clock in to mark trees").headingStyle(.tcHeadline)
                    Text("Trees are saved with a shift. Clock in, or add a shift you already worked.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button("Clock in", action: clockIn)
                    .buttonStyle(.glovePrimary)
                    .accessibilityIdentifier("trees-clock-in")
                Button("Add a shift", action: addShift)
                    .buttonStyle(.gloveSecondary)
            }
        }
        .card(padding: 14)
    }
}
