import SwiftUI
import TimeCardCore

/// The Report tab. (Stand-in until its slice lands.)
struct ReportView: View {
    var body: some View {
        PlaceholderScreen(title: "Report", systemImage: "doc.text",
                          headline: "A paper time card",
                          detail: "Pick a week or any dates and print a clean time card as a PDF, or share a CSV.")
    }
}
