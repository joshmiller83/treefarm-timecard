import SwiftUI
import TimeCardCore

/// Set a new password with a reset code from an admin (there's no email service).
struct ResetPasswordView: View {
    @Environment(TimeCardSession.self) private var session

    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AuthHeader(title: "Reset your password", subtitle: "Ask an admin for a reset code. It works once, for a day.")

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("reset-email")
                    TextField("Reset code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.tcNumber)
                        .accessibilityIdentifier("reset-code")
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("reset-password")
                }
                .textFieldStyle(.glove)

                VStack(spacing: 12) {
                    if let error { ErrorMessage(text: error) }
                    Button {
                        Task { await reset() }
                    } label: {
                        BusyLabel(title: "Set password and sign in", busy: busy)
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
        .navigationTitle("Reset code")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reset() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.resetPassword(email: email, code: code, newPassword: newPassword)
        } catch {
            self.error = signInMessage(for: error)
        }
    }
}
