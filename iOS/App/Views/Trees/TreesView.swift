import SwiftUI
import TimeCardCore

/// The Trees tab: the field map. Pick a field and the shift you're marking for, choose what a
/// tap does, then tap trees or row numbers. Long-press a tree (or use Notes) for its card.
struct TreesView: View {
    @Environment(TimeCardSession.self) private var session
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var model = TreesView.makeModel()
    /// Nil follows VoiceOver: the list when it's on, the map when it's off.
    @State private var listChoice: Bool?
    @State private var typing = false
    @State private var addingShift = false
    @State private var chromeHeight: CGFloat = 0

    static let zoomKey = "trees.zoom"

    private var showsList: Bool { listChoice ?? voiceOver }

    var body: some View {
        NavigationStack {
            content
                .screenBackground()
                .toolbar(.hidden, for: .navigationBar)
                .navigationTitle("Trees")
        }
        .onChange(of: session.snapshot, initial: true) { refresh() }
        .onChange(of: session.membership) { refresh() }
        .onChange(of: model.zoom) { _, zoom in
            if AppModel.shared.mode == .live { UserDefaults.standard.set(zoom.rawValue, forKey: Self.zoomKey) }
        }
        .onChange(of: model.message) { _, message in
            if let message, message.tone != .hint { AccessibilityNotification.Announcement(message.text).post() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.feedback)
        .sheet(item: $model.openTree) { open in
            TreeCardView(model: model, tree: open.tree)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $typing) {
            TypeNumbersSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $addingShift) {
            ShiftEditorView(shiftId: nil)
        }
        .task {
            // Siri and the lock screen remember where you're working; open there until a field is picked.
            model.workingFieldId = AppModel.shared.actions.state()?.position?.fieldId
            await TreesDemoSeed.runIfRequested(model: AppModel.shared)
        }
    }

    // MARK: Screens

    @ViewBuilder private var content: some View {
        if model.data == nil {
            ContentUnavailableView {
                Label("Loading the farm", systemImage: "tree")
            } description: {
                Text("The field map shows up as soon as this phone has the farm.")
            }
        } else if model.fields.isEmpty {
            emptyFarm(title: "No fields yet",
                      detail: model.data?.isAdmin == true
                        ? "Add a field and its blocks in the Team tab, then mark trees here."
                        : "Ask an admin to set up your field. It shows up here when they do.")
        } else if model.blocks.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                FieldHeader(model: model, showsList: showsList) { listChoice = !showsList }
                emptyFarm(title: "\(model.field?.name ?? "This field") has no blocks yet",
                          detail: model.data?.isAdmin == true
                            ? "Add blocks of rows in the Team tab, beside or below each other the way they stand in the field."
                            : "Ask an admin to add this field’s blocks.")
                Spacer()
            }
            .padding(16)
        } else {
            map
        }
    }

    private var map: some View {
        GeometryReader { proxy in
            let mapHeight = max(320, proxy.size.height - chromeHeight - 12)
            ScrollView(.vertical) {
                VStack(spacing: 12) {
                    chrome
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight = $0 }
                    if showsList {
                        TreeRowsList(model: model)
                            .frame(height: mapHeight)
                            .background(Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                            .padding(.horizontal, 16)
                    } else {
                        mapCard.frame(height: mapHeight)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldHeader(model: model, showsList: showsList) { listChoice = !showsList }
            MarkingForBar(model: model, clockIn: { model.clockIn() }, addShift: { addingShift = true })
            ModePicker(model: model)
            MessageBar(model: model)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var mapCard: some View {
        VStack(spacing: 0) {
            MapLegend()
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            Divider().overlay(Palette.line)
            ZStack(alignment: .bottom) {
                TreeMapView(model: model)
                    .accessibilityIdentifier("tree-map")
                HStack(alignment: .bottom) {
                    ZoomBar(model: model)
                    Spacer(minLength: 8)
                    MapRoundButton(systemImage: "textformat.123", label: "Type row and tree numbers") { typing = true }
                        .accessibilityIdentifier("type-numbers")
                }
                .padding(10)
            }
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            model.viewportWidth = max(120, width - 32 - 2 * TreeMapScrollView.padding)
        }
    }

    private func emptyFarm(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.firText)
                .frame(width: 56, height: 56)
                .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(title).headingStyle(.tcTitle2)
            Text(detail)
                .font(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 20)
        .padding(.horizontal, model.fields.isEmpty ? 16 : 0)
    }

    // MARK: Model

    private func refresh() {
        model.update(snapshot: session.snapshot, farm: session.farm, me: session.membership)
    }

    @MainActor
    static func makeModel() -> TreeMapModel {
        let app = AppModel.shared
        let zoom = app.mode == .live ? MapZoom(rawValue: UserDefaults.standard.string(forKey: zoomKey) ?? "") ?? .m
                                     : TreesDemoSeed.zoom() ?? .m
        let model = TreeMapModel(save: { try app.session.save($0) },
                                 perform: { app.actions.perform($0) },
                                 zoom: zoom)
        model.onTreesChanged = { app.actions.publishLiveSnapshot() }
        return model
    }
}
