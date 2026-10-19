import SwiftUI
import TimeCardCore

enum AuthRoute: Hashable {
    case join
    case reset
}

/// Sign in, with ways to join a farm or use a reset code.
struct SignInFlow: View {
    var body: some View {
        NavigationStack {
            SignInView()
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .join: JoinView()
                    case .reset: ResetPasswordView()
                    }
                }
        }
    }
}

struct SignInView: View {
    @Environment(TimeCardSession.self) private var session

    /// For signing in again after a session ends: the email is known and there's no join link.
    var reauthenticating = false
    var onSignedIn: () -> Void = {}

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                AuthHeader(title: reauthenticating ? "Sign in again" : "Time Card",
                           subtitle: reauthenticating
                               ? "Your sign-in ended. Your work is safe on this phone and syncs once you're back in."
                               : "Clock in, mark your rows, and keep the crew's map in step.")

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .accessibilityIdentifier("sign-in-email")
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit { Task { await signIn() } }
                        .accessibilityIdentifier("sign-in-password")
                }
                .textFieldStyle(.glove)

                VStack(spacing: 12) {
                    if let error { ErrorMessage(text: error) }
                    Button {
                        Task { await signIn() }
                    } label: {
                        BusyLabel(title: "Sign in", busy: busy)
                    }
                    .buttonStyle(.glovePrimary)
                    .disabled(busy)
                    .accessibilityIdentifier("sign-in-button")
                }

                if !reauthenticating {
                    VStack(spacing: 12) {
                        OrDivider()
                        NavigationLink(value: AuthRoute.join) {
                            Label("Join with an invite code", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.gloveSecondary)
                        NavigationLink(value: AuthRoute.reset) {
                            Text("I have a reset code")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Palette.firText)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if email.isEmpty, let known = session.me?.user.email { email = known }
        }
    }

    private func signIn() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.signIn(email: email, password: password)
            password = ""
            onSignedIn()
        } catch {
            self.error = signInMessage(for: error)
        }
    }
}

/// The leaf mark, a Zilla Slab title and one line under it.
struct AuthHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.firInk)
                .frame(width: 68, height: 68)
                .background(Palette.fir, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text(title).headingStyle(.tcLargeTitle)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A button title that becomes a spinner while waiting on the server.
struct BusyLabel: View {
    var title: String
    var busy: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(busy ? 0 : 1)
            if busy { ProgressView().tint(Palette.firInk) }
        }
        .accessibilityLabel(busy ? "\(title), working" : title)
    }
}

struct OrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Palette.line).frame(height: 1)
            Text("or").font(.footnote).foregroundStyle(Palette.muted)
            Rectangle().fill(Palette.line).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}
