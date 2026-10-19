import SwiftUI
import TimeCardCore

/// Join a farm with the invite code an admin made.
struct JoinView: View {
    @Environment(TimeCardSession.self) private var session

    @State private var inviteCode = ""
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AuthHeader(title: "Join your farm", subtitle: "Your admin gives you an invite code. It works once and lasts a week.")

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.tcNumber)
                        .accessibilityLabel("Invite code")
                        .accessibilityIdentifier("join-code")
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .accessibilityLabel("Your name")
                        .accessibilityIdentifier("join-name")
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Email")
                        .accessibilityIdentifier("join-email")
                    SecureField("Choose a password", text: $password)
                        .textContentType(.newPassword)
                        .accessibilityLabel("Choose a password")
                        .accessibilityIdentifier("join-password")
                }
                .textFieldStyle(.glove)

                VStack(spacing: 12) {
                    if let error { ErrorMessage(text: error) }
                    Button {
                        Task { await join() }
                    } label: {
                        BusyLabel(title: "Join the farm", busy: busy)
                    }
                    .buttonStyle(.glovePrimary)
                    .disabled(busy)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Join")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func join() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.join(inviteCode: inviteCode, email: email, password: password, displayName: name)
        } catch {
            self.error = signInMessage(for: error)
        }
    }
}
