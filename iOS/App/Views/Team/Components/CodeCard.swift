import SwiftUI
import TimeCardCore
import UIKit

/// An invite or reset code, big and in groups so it reads aloud easily ("K7Q4, M2XP, 9R").
/// The codes never use 0/O or 1/I/L, so there's nothing to mix up. VoiceOver spells it.
struct CodeDisplay: View {
    var code: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { groups }
            VStack(spacing: 10) { groups }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code: \(InviteText.spelled(code))")
        .accessibilityIdentifier("code-display")
    }

    private var groups: some View {
        ForEach(Array(InviteText.groups(code).enumerated()), id: \.offset) { _, group in
            Text(group)
                .font(.custom(Typeface.numberSemiBold, size: 32, relativeTo: .largeTitle))
                .tracking(3)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        }
    }
}

/// A just-made code with how long it works, a share button and a copy button. The server
/// keeps only a hash, so this is the one time anyone sees it; the card says so.
struct CodeCard: View {
    var title: String
    var code: String
    var expiry: String
    var shareText: String
    var shareTitle: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(title)
                Text(expiry).font(.subheadline).foregroundStyle(Palette.muted)
            }
            CodeDisplay(code: code)
                .padding(.vertical, 4)
            NoticeBox(systemImage: "eye") {
                Text("This is the only time the code is shown. Share it or write it down now.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ShareLink(item: shareText, subject: Text(shareTitle)) {
                Label("Share the code", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glovePrimary)
            .accessibilityIdentifier("code-share")
            Button {
                UIPasteboard.general.string = code
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy the code", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.gloveSecondary)
            .accessibilityIdentifier("code-copy")
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
        .card(padding: 18)
    }
}
