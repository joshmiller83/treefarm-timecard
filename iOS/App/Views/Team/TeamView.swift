import SwiftUI
import TimeCardCore

/// The Team tab (admins only): the crew with this week's hours and their invites, the
/// fields and blocks editor, and seasons. Edits save through the session and sync; invites,
/// reset codes and removing someone go to the server directly.
struct TeamView: View {
    enum Section: String, Hashable, CaseIterable {
        case crew, fields, season
    }

    enum Route: Hashable {
        case member(UUID)
        case memberReport(UUID)
        case field(UUID)
    }

    @Environment(AppModel.self) private var model
    @Environment(TimeCardSession.self) private var session
    @State private var section: Section = TeamScenario.section ?? .crew
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GloveSegmented(options: [
                        (.crew, "Crew", "team-section-crew"),
                        (.fields, "Fields", "team-section-fields"),
                        (.season, "Season", "team-section-season"),
                    ], selection: $section)
                    switch section {
                    case .crew: CrewSection()
                    case .fields: FieldsSection()
                    case .season: SeasonSection()
                    }
                }
                .teamPage()
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Team")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .member(let id): MemberDetailView(userId: id)
                case .memberReport(let id): MemberReportView(userId: id)
                case .field(let id): FieldEditorView(fieldId: id)
                }
            }
            .refreshable { await session.requestSync(.manual) }
        }
        .task {
            guard model.mode != .live else { return }
            await TeamScenario.applyIfRequested(session)
        }
    }
}

#Preview {
    let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true))
    TeamView()
        .environment(model)
        .environment(model.session)
        .task { await model.start() }
}
