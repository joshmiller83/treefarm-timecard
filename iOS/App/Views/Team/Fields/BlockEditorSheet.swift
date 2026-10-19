import SwiftUI
import TimeCardCore

/// Adds a block "to the right of" another or "in a new row below", or changes one: its
/// name, rows, trees per row and which way the rows run. The map at the top shows the
/// result as you go. Every rule and sentence comes from TreeFarmKit's `BlockEdit`.
struct BlockEditorSheet: View {
    var fieldId: UUID
    var target: BlockEditorTarget

    @Environment(TimeCardSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BlockDraft(name: "", rows: BlockPlans.defaultRows, treesPerRow: BlockPlans.defaultTrees, direction: .across)
    @State private var placementID = ""
    @State private var sizeTouched = false
    @State private var attempted = false
    @State private var sheetProblem: String?
    @State private var confirmingRemove = false
    @State private var loaded = false
    @State private var saved = 0
    @State private var refused = 0
    @FocusState private var focus: String?

    private var editing: Block? {
        if case .edit(let block) = target { return session.snapshot.blocks[block.id] ?? block }
        return nil
    }

    private var fieldBlocks: [Block] {
        session.snapshot.blocks.values.filter { $0.fieldId == fieldId }
    }

    private var choices: [PlacementChoice] { BlockPlans.choices(fieldBlocks) }

    private var placement: BlockEdit.Placement {
        choices.first { $0.id == placementID }?.placement ?? BlockPlans.defaultPlacement(fieldBlocks)
    }

    private var marks: [TreeMark] { Array(session.snapshot.marks.values) }
    private var notes: [TreeNote] { Array(session.snapshot.notes.values) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    LabeledGloveField(title: "Block name", prompt: BlockPlans.nextName(fieldBlocks), text: $draft.name,
                                      identifier: "block-name", footnote: "A number reads “Block 3”; anything else reads as typed.")
                        .focused($focus, equals: "name")
                    // Above the sizes, so it stays in sight over the number pad while you type.
                    if let problem = shownProblem {
                        ErrorMessage(text: problem)
                    }
                    sizeFields
                    directionChoice
                    if editing == nil { placementPicker }
                    if attempted, let problem = shownProblem {
                        // Again by the button, so a refused save is never silent. VoiceOver
                        // reads the copy above and hears it announced, so it skips this one.
                        ErrorMessage(text: problem)
                            .accessibilityHidden(true)
                    }
                    if editing == nil, let sheetProblem {
                        ErrorMessage(text: sheetProblem)
                    }
                    Button(editing == nil ? "Add block" : "Save block", action: save)
                        .buttonStyle(.glovePrimary)
                        .accessibilityIdentifier("block-save")
                    if editing != nil { removeArea }
                }
                .teamPage()
            }
            .onChange(of: shownProblem) { _, new in
                TeamAnnounce.say(new)
                // A message appearing above the sizes pushes them down: keep the one being typed in sight.
                guard let focus, focus != "name" else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(focus, anchor: UnitPoint(x: 0.5, y: 0.85)) }
            }
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(editing.map { "Edit \($0.displayName)" } ?? "New Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .sensoryFeedback(.warning, trigger: refused)
            // A refused save or removal is said out loud, even when the sentence was already showing.
            .onChange(of: refused) { TeamAnnounce.say(sheetProblem ?? shownProblem) }
            .onAppear(perform: load)
            .onChange(of: placementID) { followNeighbor() }
        }
    }

    // MARK: Parts

    private var preview: some View {
        let shown = BlockPlans.preview(blocks: fieldBlocks, draft: draft, editing: editing, placement: editing == nil ? placement : nil)
        let season = session.snapshot.farm?.activeSeasonId
        let ids = Set(shown.blocks.map(\.id))
        let shaped = session.snapshot.marks.values.filter { $0.seasonId == season && ids.contains($0.blockId) }.map(\.tree)
        return VStack(alignment: .leading, spacing: 10) {
            MiniMapView(blocks: shown.blocks, shaped: shaped, highlight: shown.highlight, highlightIsNew: editing == nil,
                        maxHeight: 200, accessibilityText: previewDescription(shown.blocks)) { id in
                guard editing == nil, id != BlockPlans.previewID,
                      let choice = choices.first(where: { $0.placement == .rightOf(id) }) else { return }
                placementID = choice.id
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.sapSoft)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.sap, lineWidth: 1.5))
                    .frame(width: 14, height: 10)
                    .accessibilityHidden(true)
                Text(editing == nil ? "Where the new block goes. Tap a block to put it to the right of that one." : "This block, at the size you set.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    @ViewBuilder
    private var sizeFields: some View {
        GloveNumberField(title: "Rows in block", value: sizeBinding(\.rows), range: Limits.blockRows, identifier: "block-rows", focus: $focus)
        GloveNumberField(title: "Trees per row", value: sizeBinding(\.treesPerRow), range: Limits.treesPerRow, identifier: "block-trees", focus: $focus)
    }

    private var directionChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rows run").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            ChoiceTile(title: "Across", detail: "Each row is a line; row numbers down the left.", systemImage: "line.3.horizontal",
                       selected: draft.direction == .across) { setDirection(.across) }
                .accessibilityIdentifier("block-across")
            ChoiceTile(title: "Down", detail: "Each row is a column; row numbers across the top.", systemImage: "line.3.horizontal",
                       iconRotation: .degrees(90), selected: draft.direction == .down) { setDirection(.down) }
                .accessibilityIdentifier("block-down")
        }
    }

    private var placementPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where it goes").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            Menu {
                Picker("Where it goes", selection: $placementID) {
                    ForEach(choices) { Text($0.label).tag($0.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: placementIcon).font(.title3.weight(.semibold)).foregroundStyle(Palette.firText)
                    Text(choices.first { $0.id == placementID }?.label ?? "")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: GloveButtonStyle.minHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityIdentifier("block-placement")
            if case .rightOf = placement {
                Text("Blocks after it in that row move over one to make room.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private var removeArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(role: .destructive) {
                guard let block = editing else { return }
                if let problem = BlockPlans.remove(block, marks: marks, notes: notes, now: Date()).problemText {
                    sheetProblem = problem
                    refused += 1
                } else {
                    confirmingRemove = true
                }
            } label: {
                Label("Remove block", systemImage: "trash")
            }
            .buttonStyle(.gloveDestructive)
            .accessibilityIdentifier("block-remove")
            .confirmationDialog("Remove \(editing?.displayName ?? "this block")?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove block", role: .destructive, action: remove)
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("It has no shaped trees or notes. The blocks around it stay where they are.")
            }
            if let sheetProblem { ErrorMessage(text: sheetProblem) }
        }
        .padding(.top, 8)
    }

    // MARK: State

    /// What to fix: a resize that would strand trees shows right away; the rest after a save try.
    private var shownProblem: String? {
        if let block = editing,
           let stranded = BlockEdit.checkResize(block, rows: max(draft.rows, 1), treesPerRow: max(draft.treesPerRow, 1), marks: marks, notes: notes) {
            return stranded
        }
        guard attempted else { return nil }
        return BlockEdit.validate(name: draft.name, rows: draft.rows, treesPerRow: draft.treesPerRow)
    }

    private var placementIcon: String {
        switch placement {
        case .rightOf: "arrow.right.square"
        case .newRowBelow: "arrow.down.square"
        case .first: "square.dashed"
        }
    }

    private func sizeBinding(_ path: WritableKeyPath<BlockDraft, Int>) -> Binding<Int> {
        Binding(get: { draft[keyPath: path] }, set: { value in
            if draft[keyPath: path] != value { sizeTouched = true }
            draft[keyPath: path] = value
        })
    }

    private func setDirection(_ direction: RowDirection) {
        sizeTouched = true
        draft.direction = direction
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let block = editing {
            draft = BlockDraft(block: block)
        } else {
            let start = BlockPlans.defaultPlacement(fieldBlocks)
            placementID = choices.first { $0.placement == start }?.id ?? ""
            draft = BlockPlans.newDraft(blocks: fieldBlocks, placement: start)
        }
    }

    /// A new block takes its neighbor's size until you set one yourself.
    private func followNeighbor() {
        guard editing == nil, !sizeTouched else { return }
        let suggested = BlockPlans.newDraft(blocks: fieldBlocks, placement: placement)
        draft.rows = suggested.rows
        draft.treesPerRow = suggested.treesPerRow
        draft.direction = suggested.direction
    }

    private func save() {
        focus = nil
        attempted = true
        let problem = if let block = editing {
            commit(BlockPlans.update(block, with: draft, marks: marks, notes: notes, now: Date()))
        } else {
            commit(BlockPlans.add(draft, placement: placement, fieldId: fieldId, blocks: fieldBlocks, now: Date()))
        }
        // Rule problems are already on screen (`shownProblem`); anything else shows here.
        sheetProblem = problem == shownProblem ? nil : problem
    }

    private func remove() {
        guard let block = editing else { return }
        sheetProblem = commit(BlockPlans.remove(block, marks: marks, notes: notes, now: Date()))
    }

    /// Saves and closes, or returns the sentence saying why not.
    private func commit(_ edit: TeamEdit) -> String? {
        do {
            if let problem = try TeamSave.apply(edit, in: session) {
                refused += 1
                return problem
            }
            saved += 1
            dismiss()
            return nil
        } catch {
            refused += 1
            return error.localizedDescription
        }
    }

    private func previewDescription(_ blocks: [Block]) -> String {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        let what = name.isEmpty ? "The block" : Block(fieldId: fieldId, name: name, gridRow: 0, gridColumn: 0, rowCount: 1, treesPerRow: 1).displayName
        if editing != nil { return "\(what), \(Fmt.plural(draft.rows, "row")) of \(Fmt.plural(draft.treesPerRow, "tree"))." }
        let spot = choices.first { $0.id == placementID }?.label.lowercased() ?? ""
        return "\(what) goes \(spot), \(Fmt.plural(draft.rows, "row")) of \(Fmt.plural(draft.treesPerRow, "tree"))."
    }
}

private extension TeamEdit {
    var problemText: String? {
        if case .problem(let text) = self { return text }
        return nil
    }
}
