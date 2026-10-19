import CoreGraphics
import Foundation
import Observation
import TimeCardCore

/// The line under the mode picker: a hint, what the last tap did, or why it did nothing.
struct MapMessage: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case hint, done, warning
    }

    /// A button that rides along with the message.
    enum Action: Equatable, Sendable {
        /// Fill mode: forget the first tree.
        case cancelFill
        /// A tree was shaped on another of my shifts: mark trees for that shift instead.
        case markFor(shiftId: UUID)

        var title: String {
            switch self {
            case .cancelFill: "Cancel"
            case .markFor: "Switch to that shift"
            }
        }
    }

    var text: String
    var tone: Tone
    var action: Action?

    init(_ text: String, tone: Tone, action: Action? = nil) {
        self.text = text
        self.tone = tone
        self.action = action
    }
}

/// Move the map so a block is in view (after a tap on the overview).
struct MapScrollRequest: Equatable, Sendable {
    var blockId: UUID
    var token: Int
}

/// The tree whose card is open.
struct OpenTree: Identifiable, Equatable, Sendable {
    var tree: TreeRef
    var id: String { "\(tree.blockId.uuidString)-\(tree.row)-\(tree.position)" }
}

/// One map edit, kept so Undo can take it back.
struct MapEdit: Sendable {
    var shiftId: UUID
    var change: MarkChange
}

/// The Trees tab's brain: which field and shift, what a tap does, the map's layout, undo,
/// and the tree card. Every rule and sentence comes from TreeFarmKit (`MarkOps`,
/// `MarkMessages`, `FieldLayout`); this only decides which one applies.
///
/// It never touches the store itself: marks and note edits go out through `save`
/// (the session), new notes through `perform` (FieldActions), so tests run with plain closures.
@MainActor
@Observable
final class TreeMapModel {
    // MARK: State the screen shows

    private(set) var data: TreeMapData?
    /// The field picked in the header; nil means "the one I'm working in", then the first.
    var chosenFieldId: UUID? {
        didSet { if chosenFieldId != oldValue { fieldChanged() } }
    }
    /// The field Siri and the lock screen are working in, used until a field is picked.
    var workingFieldId: UUID?
    /// The shift picked under "Marking trees for"; nil means the open shift, then the latest.
    var chosenShiftId: UUID? {
        didSet { if chosenShiftId != oldValue { shiftChanged() } }
    }
    var mode: MapMode = .one {
        didSet {
            guard mode != oldValue else { return }
            setAnchor(nil)
            message = nil
        }
    }
    private(set) var zoom: MapZoom = .m
    /// The last tree size used, so a tap on the overview goes back to it.
    private(set) var lastPreset: MapZoom = .m
    /// The map's visible width, for the "All" overview.
    var viewportWidth: CGFloat = 360

    private(set) var anchor: TreeRef?
    private(set) var message: MapMessage?
    private(set) var undoStack = UndoStack<MapEdit>()
    var openTree: OpenTree? {
        didSet { if openTree != oldValue { markDirty([oldValue?.tree.rowRef, openTree?.tree.rowRef]) } }
    }
    private(set) var scrollRequest: MapScrollRequest?
    /// Bumps whenever the map's drawing changes. The rows to redraw wait in `takeDirtyRows()`.
    private(set) var revision = 0
    /// Bumps after each change to the trees, for a haptic tap.
    private(set) var feedback = 0

    // MARK: Plumbing

    @ObservationIgnored private let save: ([SyncRecord]) throws -> Void
    @ObservationIgnored private let perform: (FieldCommand) -> FieldReply
    @ObservationIgnored private let now: () -> Date
    /// Called after the trees change, so the lock screen catches up.
    @ObservationIgnored var onTreesChanged: () -> Void = {}
    @ObservationIgnored private var pendingDirty: Set<RowRef>? = []
    @ObservationIgnored private var cachedLayout: (key: LayoutKey, layout: FieldLayout)?
    @ObservationIgnored private var scrollToken = 0

    static let saveFailed = "Couldn’t save that on this phone. Try again."

    init(save: @escaping ([SyncRecord]) throws -> Void,
         perform: @escaping (FieldCommand) -> FieldReply,
         now: @escaping () -> Date = Date.init,
         zoom: MapZoom = .m,
         mode: MapMode = .one) {
        self.save = save
        self.perform = perform
        self.now = now
        self.zoom = zoom
        self.lastPreset = zoom == .all ? .m : zoom
        self.mode = mode
    }

    // MARK: Keeping up with the store

    /// Takes in the session's latest snapshot. Cheap when nothing the map draws has changed.
    func update(snapshot: FarmSnapshot, farm: Farm?, me: Member?) {
        guard let farm, let me else {
            if data != nil { data = nil; markDirty(nil) }
            return
        }
        guard var current = data, current.me.userId == me.userId, current.farm.id == farm.id else {
            data = TreeMapData(snapshot: snapshot, farm: farm, me: me)
            undoStack = UndoStack()
            setAnchor(nil)
            markDirty(nil)
            return
        }
        let shiftBefore = markingShift?.id
        let dirty = current.update(snapshot: snapshot, farm: farm, me: me)
        data = current
        if markingShift?.id != shiftBefore {
            markDirty(nil)
        } else if dirty != [] {
            markDirty(dirty)
        }
        if let id = chosenShiftId, current.shift(id) == nil { chosenShiftId = nil }
        undoStack.removeAll { current.shift($0.shiftId) == nil }
    }

    /// The rows to redraw since the last call; nil means all of them.
    func takeDirtyRows() -> Set<RowRef>? {
        defer { pendingDirty = [] }
        return pendingDirty
    }

    // MARK: Field and shift

    var fields: [Field] { data?.fields ?? [] }

    var field: Field? {
        let fields = fields
        if let id = chosenFieldId, let f = fields.first(where: { $0.id == id }) { return f }
        if let id = workingFieldId, let f = fields.first(where: { $0.id == id }) { return f }
        return fields.first
    }

    /// The current field's live blocks in walk order.
    var blocks: [Block] {
        guard let data, let field else { return [] }
        return FieldWalker(blocks: data.blocks(in: field.id)).blocks
    }

    var myShifts: [Shift] { data?.myShifts ?? [] }
    var openShift: Shift? { data?.openShift }

    /// The shift new marks go on: the picked one, else the open one, else the latest.
    var markingShift: Shift? {
        guard let data else { return nil }
        if let id = chosenShiftId, let s = data.shift(id) { return s }
        return data.openShift ?? data.myShifts.first
    }

    /// Marking for a shift other than the one on the clock.
    var isMarkingEarlierShift: Bool {
        guard let marking = markingShift, let open = openShift else { return false }
        return marking.id != open.id
    }

    func treeCount(_ shift: Shift) -> Int {
        data?.treeCount(shift) ?? 0
    }

    /// "Today · 7:02 AM – now · 38 trees", "Sun, Oct 18 · 8:00 AM – 4:30 PM · 212 trees"
    func shiftTitle(_ shift: Shift) -> String {
        guard let cal = data?.calendar else { return "" }
        let day = cal.isSameDay(shift.start, now()) ? "Today" : Fmt.day(shift.start, cal)
        var text = "\(day) · \(Fmt.time(shift.start, cal)) – \(shift.end.map { Fmt.time($0, cal) } ?? "now")"
        let n = treeCount(shift)
        if n > 0 { text += " · \(Fmt.plural(n, "tree"))" }
        return text
    }

    func useOpenShift() {
        chosenShiftId = openShift?.id
    }

    /// Clocks in from the Trees tab (no shift yet), in the field on screen.
    func clockIn() {
        let reply = perform(.clockIn(fieldId: field?.id))
        message = MapMessage(reply.speech, tone: reply.succeeded ? .done : .warning)
        if reply.succeeded { chosenShiftId = nil }
    }

    // MARK: Zoom and layout

    func setZoom(_ zoom: MapZoom) {
        guard zoom != self.zoom else { return }
        self.zoom = zoom
        if zoom != .all { lastPreset = zoom }
        setAnchor(nil)
        if message?.tone == .hint { message = nil }
    }

    /// The map's geometry at the current zoom. Hit tests and drawing both use this one.
    var layout: FieldLayout {
        let blocks = blocks
        let width = zoom == .all ? viewportWidth.rounded() : 0
        let key = LayoutKey(field: field?.id, zoom: zoom, width: width, blocks: blocks)
        if let cachedLayout, cachedLayout.key == key { return cachedLayout.layout }
        let layout = FieldLayout(blocks: blocks, metrics: zoom.metrics(blocks: blocks, width: width))
        cachedLayout = (key, layout)
        return layout
    }

    /// Identifies a layout, so the map knows when to lay its tiles out again.
    struct LayoutKey: Equatable {
        var field: UUID?
        var zoom: MapZoom
        var width: CGFloat
        var blocks: [Block]
    }

    var layoutKey: LayoutKey {
        LayoutKey(field: field?.id, zoom: zoom, width: zoom == .all ? viewportWidth.rounded() : 0, blocks: blocks)
    }

    /// After a pinch: snaps to the nearest size. Returns the zoom it landed on.
    @discardableResult
    func pinchEnded(cellWidth: CGFloat) -> MapZoom {
        let overview = MapMetrics.overview(blocks: blocks, width: viewportWidth).cell.width
        let next = MapZoom.nearest(cellWidth: cellWidth, overviewWidth: overview)
        setZoom(next)
        return next
    }

    // MARK: Taps

    /// A tap at a point in map coordinates (the same space as `layout`).
    func tap(at point: CGPoint) {
        guard let hit = layout.hitTest(point) else { return }
        switch hit {
        case .block(let id): zoomInto(id)
        case .row(let row): tapRow(row)
        case .tree(let tree): tapTree(tree)
        }
    }

    /// A long press: opens the tree's card in any mode.
    func longPress(at point: CGPoint) {
        guard case .tree(let tree)? = layout.hitTest(point) else { return }
        openTree = OpenTree(tree: tree)
    }

    func zoomInto(_ blockId: UUID) {
        guard let block = data?.block(blockId) else { return }
        setZoom(lastPreset)
        scrollToken += 1
        scrollRequest = MapScrollRequest(blockId: blockId, token: scrollToken)
        message = MapMessage("Showing \(block.displayName). Tap All to see the whole field again.", tone: .hint)
    }

    func tapRow(_ row: RowRef) {
        guard let block = data?.block(row.blockId) else { return }
        if mode == .notes {
            message = MapMessage(MapMode.notes.hint, tone: .hint)
            return
        }
        setAnchor(nil)
        guard let ctx = markContext() else { return }
        let change = MarkOps.rowTap(row, block: block, mode: mode.tapMode, ctx: ctx, index: data!.index)
        let text = MarkMessages.rowTap(change, row: row, block: block, mode: mode.tapMode)
        switch commit(change, shiftId: ctx.shiftId) {
        case .saved: message = MapMessage(text, tone: .done)
        case .nothing: message = MapMessage(text, tone: .warning)
        case .failed: break
        }
    }

    func tapTree(_ tree: TreeRef) {
        guard let data, let block = data.block(tree.blockId) else { return }
        switch mode {
        case .notes:
            openTree = OpenTree(tree: tree)
        case .fill:
            fill(to: tree, block: block)
        case .one, .erase:
            toggle(tree, erase: mode == .erase)
        }
    }

    /// One tree on or off for the marking shift. With `erase`, a free tree stays free.
    func toggle(_ tree: TreeRef, erase: Bool = false) {
        guard let data, let block = data.block(tree.blockId) else { return }
        setAnchor(nil)
        guard let ctx = markContext() else { return }
        let held = data.index.mark(at: tree)
        let change: MarkChange = erase ? MarkOps.unmark([tree], ctx: ctx, index: data.index)
                                       : MarkOps.toggle(tree, ctx: ctx, index: data.index)
        let shapedOn = held.flatMap { $0.shiftId == ctx.shiftId ? nil : Fmt.monthDay($0.markedAt, data.calendar) }
        let text = MarkMessages.tap(change, tree: tree, block: block, shapedOn: shapedOn)
        switch commit(change, shiftId: ctx.shiftId) {
        case .saved:
            message = MapMessage(text, tone: .done)
        case .nothing:
            // Shaped on another of my shifts: offer to mark for that one instead.
            let action = held.flatMap { mark in
                mark.shiftId != ctx.shiftId && data.shift(mark.shiftId) != nil ? MapMessage.Action.markFor(shiftId: mark.shiftId) : nil
            }
            message = MapMessage(text, tone: .warning, action: action)
        case .failed:
            break
        }
    }

    private func fill(to tree: TreeRef, block: Block) {
        guard let anchor else {
            guard markContext() != nil else { return }
            setAnchor(tree)
            message = MapMessage("Start: \(block.label(tree)). Now tap the last tree.", tone: .hint, action: .cancelFill)
            return
        }
        setAnchor(nil)
        guard anchor.blockId == tree.blockId else {
            message = MapMessage(MarkMessages.fillOneBlock, tone: .warning)
            return
        }
        guard let data, let ctx = markContext() else { return }
        let change = MarkOps.fillBetween(anchor, tree, block: block, ctx: ctx, index: data.index)
        let text = MarkMessages.fill(change, from: anchor, to: tree)
        switch commit(change, shiftId: ctx.shiftId) {
        case .saved: message = MapMessage(text, tone: .done)
        case .nothing: message = MapMessage(text, tone: .warning)
        case .failed: break
        }
    }

    func perform(_ action: MapMessage.Action) {
        switch action {
        case .cancelFill:
            setAnchor(nil)
            message = nil
        case .markFor(let shiftId):
            chosenShiftId = shiftId
            message = nil
        }
    }

    // MARK: Typed numbers

    /// Row and tree numbers as people count them (from 1). Missing "to" numbers mean the
    /// same row and the whole row. Returns true when something changed.
    @discardableResult
    func typeRange(blockId: UUID, fromRow: Int, toRow: Int?, fromTree: Int?, toTree: Int?, add: Bool) -> Bool {
        guard let data, let block = data.block(blockId) else { return false }
        var rows = (fromRow - 1, (toRow ?? fromRow) - 1)
        var trees = ((fromTree ?? 1) - 1, (toTree ?? block.treesPerRow) - 1)
        if rows.1 < rows.0 { rows = (rows.1, rows.0) }
        if trees.1 < trees.0 { trees = (trees.1, trees.0) }
        let rowRange = rows.0...rows.1
        let treeRange = trees.0...trees.1
        if let problem = MarkMessages.checkRange(block: block, rows: rowRange, positions: treeRange) {
            message = MapMessage(problem, tone: .warning)
            return false
        }
        setAnchor(nil)
        guard let ctx = markContext() else { return false }
        let change = MarkOps.range(block: block, rows: rowRange, positions: treeRange, add: add, ctx: ctx, index: data.index)
        let text = MarkMessages.range(change, block: block, rows: rowRange, add: add)
        switch commit(change, shiftId: ctx.shiftId) {
        case .saved:
            message = MapMessage(text, tone: .done)
            return true
        case .nothing:
            message = MapMessage(text, tone: .warning)
            return false
        case .failed:
            return false
        }
    }

    // MARK: Undo

    var canUndo: Bool { !undoStack.isEmpty }

    func undo() {
        setAnchor(nil)
        while let edit = undoStack.pop() {
            guard data?.shift(edit.shiftId) != nil else { continue }
            let inverse = edit.change.inverse(now: now().roundedToMillisecond)
            let records = (inverse.added + inverse.removed).map(SyncRecord.treeMark)
            guard apply(records) else { undoStack.push(edit); return }
            message = MapMessage(MarkMessages.undid, tone: .done)
            return
        }
        message = MapMessage(Speech.nothingToUndo, tone: .warning)
    }

    // MARK: Saving

    /// What marking needs: a shift to put the trees on and an active season. Says what's missing.
    private func markContext() -> MarkContext? {
        guard let data, let shift = markingShift else {
            message = MapMessage(MarkMessages.needShift, tone: .warning)
            return nil
        }
        guard let season = data.season else {
            message = MapMessage(Speech.noSeason, tone: .warning)
            return nil
        }
        return MarkContext(shiftId: shift.id, userId: data.me.userId, seasonId: season.id, now: now().roundedToMillisecond)
    }

    private enum CommitResult { case saved, nothing, failed }

    /// Saves an edit and remembers it for Undo.
    private func commit(_ change: MarkChange, shiftId: UUID) -> CommitResult {
        guard !change.isEmpty else { return .nothing }
        let records = (change.added + change.removed).map(SyncRecord.treeMark)
        guard apply(records) else { return .failed }
        undoStack.push(MapEdit(shiftId: shiftId, change: change))
        return .saved
    }

    /// Saves records and shows them on the map right away.
    private func apply(_ records: [SyncRecord]) -> Bool {
        do {
            try save(records)
        } catch {
            message = MapMessage(Self.saveFailed, tone: .warning)
            return false
        }
        if var current = data {
            let rows = current.apply(records)
            data = current
            markDirty(rows)
        }
        feedback += 1
        onTreesChanged()
        return true
    }

    // MARK: For the details extension

    func show(_ message: MapMessage?) {
        self.message = message
    }

    func currentTime() -> Date {
        now().roundedToMillisecond
    }

    func performCommand(_ command: FieldCommand) -> FieldReply {
        perform(command)
    }

    func saveRecords(_ records: [SyncRecord]) -> Bool {
        apply(records)
    }

    // MARK: Drawing bookkeeping

    private func setAnchor(_ tree: TreeRef?) {
        guard tree != anchor else { return }
        let old = anchor
        anchor = tree
        markDirty([old?.rowRef, tree?.rowRef])
    }

    private func markDirty(_ rows: [RowRef?]) {
        markDirty(Set(rows.compactMap { $0 }))
    }

    private func markDirty(_ rows: Set<RowRef>?) {
        if let rows {
            guard !rows.isEmpty else { return }
            pendingDirty?.formUnion(rows)
        } else {
            pendingDirty = nil
        }
        revision += 1
    }

    private func fieldChanged() {
        setAnchor(nil)
        message = nil
        markDirty(nil)
    }

    private func shiftChanged() {
        setAnchor(nil)
        markDirty(nil)
    }
}
