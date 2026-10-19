import SwiftUI
import TimeCardCore

/// A quiet stand-in for a tab that's still being built.
struct PlaceholderScreen<Extra: View>: View {
    var title: String
    var systemImage: String
    var headline: String
    var detail: String
    @ViewBuilder var extra: Extra

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    extra
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: systemImage)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Palette.firText)
                            .frame(width: 56, height: 56)
                            .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                        Text(headline).headingStyle(.tcTitle2)
                        Text(detail)
                            .font(.body)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Coming soon")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.sapInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Palette.sapSoft, in: Capsule())
                    }
                    .card(padding: 20)
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationTitle(title)
        }
    }
}

extension PlaceholderScreen where Extra == EmptyView {
    init(title: String, systemImage: String, headline: String, detail: String) {
        self.init(title: title, systemImage: systemImage, headline: headline, detail: detail) { EmptyView() }
    }
}
