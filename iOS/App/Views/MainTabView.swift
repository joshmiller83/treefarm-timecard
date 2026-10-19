import SwiftUI
import TimeCardCore

enum AppTab: String, Hashable {
    case clock, trees, log, report, team

    /// UI-test runs can open on a tab with `-UITestTab trees`.
    static var launchTab: AppTab {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-UITestTab"), i + 1 < args.count else { return .clock }
        return AppTab(rawValue: args[i + 1]) ?? .clock
    }
}

/// The signed-in app: Clock, Trees, Log, Report and, for admins, Team.
/// Settings opens from the gear on the Clock tab, so the tab bar never overflows into More.
struct MainTabView: View {
    @Environment(TimeCardSession.self) private var session
    @State private var tab: AppTab = .launchTab

    var body: some View {
        TabView(selection: $tab) {
            ClockView()
                .tabItem { Label("Clock", systemImage: "clock") }
                .tag(AppTab.clock)
            TreesView()
                .tabItem { Label("Trees", systemImage: "tree") }
                .tag(AppTab.trees)
            LogView()
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.log)
            ReportView()
                .tabItem { Label("Report", systemImage: "doc.text") }
                .tag(AppTab.report)
            if session.isAdmin {
                TeamView()
                    .tabItem { Label("Team", systemImage: "person.2") }
                    .tag(AppTab.team)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Banners()
        }
    }
}

/// Session and sync messages that sit above every tab.
private struct Banners: View {
    @Environment(TimeCardSession.self) private var session
    @State private var signingIn = false

    var body: some View {
        VStack(spacing: 8) {
            if case .expired = session.auth {
                Banner(tone: .onBreak, systemImage: "person.crop.circle.badge.exclamationmark",
                       text: "Your sign-in ended. Your changes are safe on this phone.",
                       actionTitle: "Sign in") { signingIn = true }
                    .accessibilityIdentifier("expired-banner")
            }
            if let notice = session.latestNotice {
                Banner(tone: .alert, systemImage: "exclamationmark.bubble", text: notice.message,
                       actionTitle: "OK") { session.dismissNotice() }
                    .accessibilityIdentifier("sync-notice")
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(12))
                        if session.latestNotice?.id == notice.id { session.dismissNotice() }
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.2), value: session.latestNotice)
        .sheet(isPresented: $signingIn) {
            SignInView(reauthenticating: true) { signingIn = false }
                .presentationDragIndicator(.visible)
        }
    }
}

struct Banner: View {
    var tone: StatusPill.Tone
    var systemImage: String
    var text: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tone.dot)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tone.ink)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tone.dot.opacity(0.45), lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
