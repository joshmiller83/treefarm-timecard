import SwiftUI
import TreeFarmKit
import WatchKit

/// The left page (docs/watch.md 3.5): Lunch and Break (or Back to work), Undo, the rain Lock,
/// and Clock out, which always asks first and is never the primary action. No Double Tap here.
struct ControlsScreen: View {
    let model: WatchShiftModel
    let state: WatchState
    let act: (FieldCommand, WatchSource) -> Void

    @Environment(\.scenePhase) private var scenePhase
    private let metrics = ButtonMetrics.current

    var body: some View {
        GeometryReader { geometry in
            controls(fit: Fit(available: geometry.size.height, metrics: metrics))
        }
        .watchToast(model.toast, alignment: .top)
    }

    /// The glove sizes, scaled down together only as far as the screen needs (the 40 mm
    /// watch is a few points short), never below 48 pt.
    struct Fit {
        static let spacing: CGFloat = 6
        let grid: CGFloat
        let clockOut: CGFloat

        init(available: CGFloat, metrics: ButtonMetrics) {
            let needed = 2 * metrics.grid + metrics.clockOut + 2 * Self.spacing
            let k = available > 0 ? min(1, (available - 2 * Self.spacing) / (needed - 2 * Self.spacing)) : 1
            grid = max(48, (metrics.grid * k).rounded(.down))
            clockOut = max(48, (metrics.clockOut * k).rounded(.down))
        }
    }

    private func controls(fit: Fit) -> some View {
        let onBreak = state.snapshot.map { $0.phase != .working } ?? false
        return VStack(spacing: Fit.spacing) {
            if onBreak {
                Button {
                    act(.endBreak, .button)
                } label: {
                    GloveLabel(steps: WatchDisplay.primaryLabelSteps(.backToWork), glyph: WatchDisplay.Glyph.backToWork,
                               font: metrics.primaryFont)
                }
                .buttonStyle(GloveButtonStyle(tone: .fir, height: fit.grid))
                .accessibilityIdentifier("backToWork")
            } else {
                HStack(spacing: 6) {
                    gridButton(WatchDisplay.lunch, glyph: WatchDisplay.Glyph.lunch, tone: .sap, id: "lunch", height: fit.grid) {
                        act(.startBreak(.lunch, reason: ""), .button)
                    }
                    gridButton(WatchDisplay.takeBreak, glyph: WatchDisplay.Glyph.takeBreak, tone: .sap, id: "break", height: fit.grid) {
                        act(.startBreak(.break, reason: ""), .button)
                    }
                }
            }

            HStack(spacing: 6) {
                gridButton(WatchDisplay.undo, glyph: WatchDisplay.Glyph.undo, tone: .quiet, id: "undo", height: fit.grid) {
                    Task { _ = await model.undo() }
                }
                .disabled(!canUndo)
                if lockAvailable {
                    gridButton(WatchDisplay.lock, glyph: WatchDisplay.Glyph.lock, tone: .quiet, id: "lock", height: fit.grid) {
                        WKInterfaceDevice.current().enableWaterLock()
                    }
                }
            }

            Button {
                act(.clockOut, .button)
            } label: {
                GloveLabel(steps: [WatchDisplay.clockOut], glyph: WatchDisplay.Glyph.clockOut, font: metrics.primaryFont)
            }
            .buttonStyle(GloveButtonStyle(tone: .rust, height: fit.clockOut))
            .accessibilityIdentifier("clockOut")
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var canUndo: Bool {
        model.waitingCount > 0 || state.canUndo || state.snapshot?.canUndo == true
    }

    private var lockAvailable: Bool {
        WaterLockGate.isAvailable(rating: WKInterfaceDevice.current().waterResistanceRating,
                                  sessionActive: WatchShiftModel.sessionExists(ShiftWorkout.shared.live),
                                  foreground: scenePhase == .active)
    }

    private func gridButton(_ title: String, glyph: String, tone: GloveButtonStyle.Tone, id: String, height: CGFloat,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: glyph)
                    .font(.system(.title3).weight(.bold))
                Text(title)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(GloveButtonStyle(tone: tone, height: height, cornerRadius: 18))
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}
