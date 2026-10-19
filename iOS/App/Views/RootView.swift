import SwiftUI
import TimeCardCore

/// Picks the screen for who's signed in: the sign-in flow, the main tabs, or a
/// message when there's no farm (or no database) to show.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(TimeCardSession.self) private var session

    var body: some View {
        Group {
            if let error = model.storageError {
                MessageScreen(systemImage: "externaldrive.badge.exclamationmark", title: "Can't open your time card", message: error)
            } else {
                switch session.auth {
                case .signedOut:
                    SignInFlow()
                case .signedIn, .expired:
                    if session.farm == nil {
                        NoFarmView()
                    } else {
                        MainTabView()
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.auth)
    }
}

/// A calm full-screen message with an optional action.
struct MessageScreen<Actions: View>: View {
    var systemImage: String
    var title: String
    var message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Palette.firText)
                .frame(width: 88, height: 88)
                .background(Palette.firSoft, in: Circle())
                .accessibilityHidden(true)
            Text(title).headingStyle(.tcTitle).multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

extension MessageScreen where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// Signed in, but not a current member of any farm (removed, or the farm is gone).
struct NoFarmView: View {
    @Environment(TimeCardSession.self) private var session

    var body: some View {
        MessageScreen(systemImage: "person.crop.circle.badge.questionmark", title: "No farm yet",
                      message: "You're signed in as \(session.me?.user.email ?? "you"), but you're not on a farm's crew. Ask your admin for an invite code.") {
            Button("Sign out") { Task { await session.signOut() } }
                .buttonStyle(.gloveSecondary)
                .padding(.top, 8)
        }
    }
}
