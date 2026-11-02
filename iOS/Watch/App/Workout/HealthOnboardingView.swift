import SwiftUI
import TreeFarmKit

/// The card's questions (docs/watch.md 2.4, docs/health.md 2 and 3).
enum HealthOnboardingStep: Equatable, Sendable {
    /// "Record Tree care workouts", with Apple's wording for how Other counts calories.
    case health
    /// Shown while the system asks about notifications: "Remind me if a clock-out gets stuck."
    case reminder
    /// Once, after an update that reads more from Health: steps and distance.
    case healthMore
    /// Record route is on and location was never asked: "Record your route".
    case location

    var title: String { self == .location ? WatchDisplay.routeTitle : WatchDisplay.healthTitle }

    var body: String {
        switch self {
        case .health: WatchDisplay.caloriesNote
        case .reminder: WatchDisplay.notificationsAsk
        case .healthMore: WatchDisplay.healthMoreNote
        case .location: WatchDisplay.routeNote
        }
    }

    var button: String { self == .location ? WatchDisplay.allowLocation : WatchDisplay.allowHealth }

    /// The button's glyph: a heart for Health, a location arrow for the route.
    var buttonGlyph: String { self == .location ? WatchDisplay.Glyph.location : WatchDisplay.Glyph.heart }

    /// A heart for Health; for the reminder, the phone out of reach that leaves a clock-out stuck.
    var glyph: String {
        switch self {
        case .health, .healthMore: WatchDisplay.Glyph.heart
        case .reminder: WatchDisplay.Glyph.phoneAway
        case .location: WatchDisplay.Glyph.location
        }
    }
}

/// The full-screen card the watch shows on its first launch while recording is on and Health
/// was never asked, once after an update that reads more, and once Record route needs location
/// (`ShiftWorkout.needsHealthOnboarding`).
struct HealthOnboardingView: View {
    var workout: ShiftWorkout = .shared

    var body: some View {
        let step = workout.onboardingStep ?? .health
        HealthOnboardingCard(step: step) {
            Task {
                if step == .location {
                    await workout.allowLocation()
                } else {
                    await workout.allowHealth()
                }
            }
        }
    }
}

/// The card itself: one glyph, the question, and Allow Health (Double Tap).
struct HealthOnboardingCard: View {
    let step: HealthOnboardingStep
    let onAllow: () -> Void

    @Environment(\.workoutSizeOverride) private var sizeOverride
    @Environment(\.dynamicTypeSize) private var typeSize
    private var size: WorkoutSize { sizeOverride ?? .current }

    /// How the calorie (or reminder) note is set.
    private enum Note { case full, shrinking, hidden }

    var body: some View {
        VStack(spacing: 8) {
            // Never a scroll view: it would take Double Tap from Allow Health. Last resort: at
            // the standard text sizes the note may shrink a little (the 40 mm watch); at the
            // accessibility sizes it never shrinks below what the person chose, it goes instead
            // (VoiceOver still reads it).
            ViewThatFits(in: .vertical) {
                message(showGlyph: true, note: .full)
                message(showGlyph: false, note: .full)
                message(showGlyph: false, note: typeSize.isAccessibilitySize ? .hidden : .shrinking)
            }
            .frame(maxHeight: .infinity)

            Button(action: onAllow) {
                Label(step.button, systemImage: step.buttonGlyph)
            }
            .buttonStyle(WorkoutButtonStyle(fill: WorkoutPalette.fir, height: size.primaryHeight))
            .handGestureShortcut(.primaryAction)
            .disabled(step == .reminder)
            .accessibilityIdentifier("onboarding.allowHealth")
        }
        .animation(.easeInOut(duration: 1), value: step)
    }

    private func message(showGlyph: Bool, note: Note) -> some View {
        VStack(spacing: 4) {
            if showGlyph {
                Image(systemName: step.glyph)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(step == .reminder ? WorkoutPalette.sapText : step == .location ? WorkoutPalette.firText : WorkoutPalette.heart)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
            }
            Text(step.title)
                .font(.headline)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
            if note != .hidden {
                Text(step.body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(note == .shrinking ? 0.7 : 1)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: note == .full)
        .accessibilityElement(children: .combine)
        .accessibilityHint(note == .hidden ? step.body : "")
    }
}
