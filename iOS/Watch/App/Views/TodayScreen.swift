import SwiftUI
import TreeFarmKit

/// The right page (docs/watch.md 3.6), the only one that scrolls: today's work, the field, the
/// workout, and the phone. Never pay: bystanders can see a wrist.
struct TodayScreen: View {
    let model: WatchShiftModel
    let state: WatchState
    let showQueue: () -> Void

    var body: some View {
        let live = ShiftWorkout.shared.live
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WatchDisplay.todayLine(worked: worked, trees: state.todayTrees))
                        .font(.system(.headline, design: .rounded))
                        .monospacedDigit()
                    if let pace = WatchDisplay.paceLine(state.pacePerHour) {
                        Text(pace)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                if let snapshot = state.snapshot, let progress = WatchDisplay.fieldProgress(snapshot) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(progress.line)
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                        ProgressView(value: progress.fraction)
                            .tint(WatchPalette.firBright)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let heart = WatchDisplay.heartLine(bpm: live.heartRate, kcal: live.kcal) {
                    Label(heart, systemImage: WatchDisplay.Glyph.heart)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(WatchPalette.rustBright)
                }

                recording(live)

                Divider()

                Label(WatchDisplay.phoneLine(model.reach, waiting: model.waitingCount),
                      systemImage: model.reach == .reachable ? WatchDisplay.Glyph.phone : WatchDisplay.Glyph.phoneAway)
                    .font(.system(.footnote, design: .rounded))

                if let oldest = model.queue.first {
                    Button(action: showQueue) {
                        Label(WatchDisplay.waitingSince(count: model.waitingCount, oldest: oldest.issuedAt, state: state),
                              systemImage: "list.bullet")
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(GloveButtonStyle(tone: .quiet, height: 48, cornerRadius: 14))
                    .accessibilityIdentifier("openQueue")
                }

                ForEach(model.refused) { tap in
                    Text(WatchDisplay.refusedItemLine(tap.request, speech: tap.speech, state: state))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(WatchPalette.rustBright)
                }

                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    Label(WatchDisplay.lowPower, systemImage: "battery.25")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(WatchPalette.sap)
                }

                if let demo = model.demo {
                    DemoControls(demo: demo)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .navigationTitle(WatchCopy.today)
    }

    /// Worked today, live while working.
    private var worked: TimeInterval {
        guard let snapshot = state.snapshot, snapshot.phase == .working else { return state.todayWorked }
        return max(snapshot.workedSoFar, Date().timeIntervalSince(snapshot.timerStart))
    }

    @ViewBuilder
    private func recording(_ live: WorkoutLive) -> some View {
        switch live.recording {
        case .recording, .paused:
            Label(WatchDisplay.recording, systemImage: WatchDisplay.Glyph.recording)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(WatchPalette.firBright)
        case .notAuthorized:
            Text(WatchDisplay.workoutsOff)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        case .off:
            Text(WatchDisplay.actionButtonNeedsWorkouts)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        case .stoppedUnexpectedly:
            VStack(alignment: .leading, spacing: 6) {
                Banner(text: WatchDisplay.recordingStopped, glyph: "exclamationmark.triangle.fill", tint: WatchPalette.rustBright)
                Button {
                    ShiftWorkout.shared.recordAgain()
                } label: {
                    GloveLabel(steps: [WatchDisplay.recordAgain], glyph: WatchDisplay.Glyph.recording,
                               font: .system(.headline, design: .rounded))
                }
                .buttonStyle(GloveButtonStyle(tone: .fir, height: ButtonMetrics.current.secondary))
            }
        case .waitingForClockOut:
            Banner(text: WatchDisplay.clockOutWaiting)
        case .idle:
            EmptyView()
        }
    }
}

/// The scripted phone's controls, shown only with `-watchDemo`.
struct DemoControls: View {
    let demo: DemoWatchTransport
    @State private var away = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Demo phone")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Button(away ? "Bring phone back" : "Take phone away") {
                away.toggle()
                demo.setReachable(!away)
            }
            .accessibilityIdentifier("demoPhoneReach")
            Button("Phone sends its state") {
                demo.pushState()
            }
            .accessibilityIdentifier("demoPushState")
        }
        .onAppear { away = !demo.isReachable }
    }
}
