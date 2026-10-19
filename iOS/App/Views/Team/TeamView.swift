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
    @State private var invites: InvitesModel?

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
                    case .crew: CrewSection(invites: invites)
                    case .fields: FieldsSection { path.append(.field($0)) }
                    case .season: SeasonSection()
                    }
                }
                .teamPage()
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Team")
            // Coming back to the tab, or back from someone's page, picks up invites used meanwhile.
            .onAppear { refreshInvites() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .member(let id): MemberDetailView(userId: id)
                case .memberReport(let id): MemberReportView(userId: id)
                case .field(let id): FieldEditorView(fieldId: id)
                }
            }
            .refreshable {
                // Waits for the pass, so the spinner stays until the farm is fresh.
                _ = await session.syncNow()
                if section == .crew { await invites?.load() }
            }
        }
        .task {
            if invites == nil {
                invites = InvitesModel(session: session)
                await invites?.load()
            }
            guard model.mode != .live else { return }
            await TeamScenario.applyIfRequested(session)
        }
        .onChange(of: section) { _, new in
            if new == .crew { refreshInvites() }
        }
    }

    private func refreshInvites() {
        guard let invites, section == .crew else { return }
        Task { await invites.refreshIfStale() }
    }
}

extension TimeCardSession {
    /// The farm's records haven't come from the server yet (`TeamLoading`).
    var teamIsWaitingForFarm: Bool {
        TeamScenario.forceWaiting || TeamLoading.isWaitingForFarm(snapshot: snapshot, farm: farm, syncStatus: syncStatus)
    }
}

/// "Getting the farm from the server…" with a spinner, in place of a list that would
/// otherwise look empty before the first pull.
struct TeamWaitingCard: View {
    @Environment(TimeCardSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProgressView().tint(Palette.firText)
                Text("Getting the farm from the server…").font(.tcHeadline).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(TeamLoading.detail(session.syncStatus))
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("team-waiting")
    }
}

#Preview {
    let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true))
    TeamView()
        .environment(model)
        .environment(model.session)
        .task { await model.start() }
}
