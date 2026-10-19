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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Field progress")
        .accessibilityValue("\(progress.percent) percent. " + [progress.summary, progress.timeLeft].compactMap { $0 }.joined(separator: " "))
        .accessibilityIdentifier("field-progress")
    }
}

/// What the dots mean.
struct MapLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item("Not yet") { Circle().strokeBorder(Palette.treeEmpty, lineWidth: 1.5) }
            item("Earlier") { Circle().fill(Palette.fir) }
            item("This shift") { Circle().fill(Palette.sap) }
            item("Note") { NoteCorner().fill(Palette.rust).padding(1) }
        }
        .font(.caption)
        .foregroundStyle(Palette.muted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: rings are not shaped yet, green dots were shaped earlier, gold dots on this shift, and a red corner means the tree has notes.")
    }

    private func item<S: View>(_ title: String, @ViewBuilder swatch: () -> S) -> some View {
        HStack(spacing: 5) {
            swatch().frame(width: 11, height: 11)
            Text(title).lineLimit(1)
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

/// "Marking trees for": which shift new marks go on, with a note when it isn't the one on the clock.
struct MarkingForBar: View {
    @Bindable var model: TreeMapModel
    var clockIn: () -> Void
    var addShift: () -> Void

    var body: some View {
        if let shift = model.markingShift {
            VStack(alignment: .leading, spacing: 8) {
                picker(shift)
                if model.isMarkingEarlierShift {
                    note("This is an earlier shift, not the one you’re clocked in on.", button: "Switch to today’s shift") {
                        model.useOpenShift()
                    }
                } else if model.openShift == nil {
                    note("You’re not clocked in, so trees you mark go on this shift.", button: nil) {}
                }
            }
        } else {
            noShift
        }
    }

    private func picker(_ shift: Shift) -> some View {
        Menu {
            Picker("Marking trees for", selection: Binding(get: { model.markingShift?.id }, set: { model.chosenShiftId = $0 })) {
                ForEach(model.myShifts.prefix(60)) { s in
                    Text(model.shiftTitle(s)).tag(Optional(s.id))
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("MARKING TREES FOR")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(model.isMarkingEarlierShift ? Palette.sapInk : Palette.muted)
                    Text(model.shiftTitle(shift))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.firText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight, alignment: .leading)
            .background(model.isMarkingEarlierShift ? Palette.sapSoft : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(model.isMarkingEarlierShift ? Palette.sap : Palette.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel("Marking trees for")
        .accessibilityValue(model.shiftTitle(shift))
        .accessibilityIdentifier("marking-for")
    }

    private func note(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.sapInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let button {
                Button(button, action: action)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.sapInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: GloveButtonStyle.minHeight)
                    .background(Palette.sapSoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.sap, lineWidth: 1))
                    .accessibilityIdentifier("use-open-shift")
            }
        }
        .padding(.horizontal, 4)
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
