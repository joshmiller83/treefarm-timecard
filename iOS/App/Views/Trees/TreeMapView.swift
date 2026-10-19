import SwiftUI
import TimeCardCore
import UIKit

/// The field map: a scroll view that pans both ways and pinches between the zoom sizes.
/// It draws in tiles and only keeps the tiles on screen, so 8,540 trees scroll as smoothly
/// as 80. Taps and long presses go to the model as map points; the model hit-tests them
/// with `FieldLayout`, so what's drawn and what's tapped can't disagree.
struct TreeMapView: UIViewRepresentable {
    var model: TreeMapModel
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> TreeMapScrollView {
        let view = TreeMapScrollView()
        view.onTap = { [weak model] point in model?.tap(at: point) }
        view.onLongPress = { [weak model] point in model?.longPress(at: point) }
        view.onPinchEnd = { [weak model] width in model?.pinchEnded(cellWidth: width) }
        view.rowValue = { [weak model] row in model?.rowSummary(row)?.value ?? "" }
        return view
    }

    func updateUIView(_ view: TreeMapScrollView, context: Context) {
        // Reading these here is what makes SwiftUI call back when they change.
        let revision = model.revision
        let key = model.layoutKey
        let request = model.scrollRequest
        let scheme = colorScheme
        let scene = MapScene(
            layout: model.layout,
            index: model.data?.index ?? MarkIndex(marks: []),
            markingShiftId: model.markingShift?.id,
            noteTrees: Set(model.data?.notesByTree.keys.map { $0 } ?? []),
            anchor: model.anchor,
            focus: model.openTree?.tree)
        view.fieldName = model.field?.name ?? ""
        view.apply(scene: scene, layoutKey: key, revision: revision, dirty: model.takeDirtyRows(),
                   style: scheme == .dark ? .dark : .light, scrollTo: request)
    }
}

/// One square of the map, drawn on demand.
final class MapTileView: UIView {
    weak var map: TreeMapScrollView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let map else { return }
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        map.painter.draw(rect.offsetBy(dx: frame.minX, dy: frame.minY), in: ctx)
    }
}

/// Holds the tiles at map coordinates, and the row numbers for VoiceOver, Voice Control and UI tests.
final class MapContentView: UIView {
    weak var map: TreeMapScrollView?

    override var accessibilityElements: [Any]? {
        get { map?.rowElements() ?? [] }
        set {}
    }
}

/// A row number on the map, as an accessibility element: "Block 1, row 5". Activating it
/// taps the number, like a finger would.
final class MapRowElement: UIAccessibilityElement {
    var activate: () -> Void = {}
    var value: () -> String = { "" }

    override var accessibilityValue: String? {
        get { value() }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        activate()
        return true
    }
}

final class TreeMapScrollView: UIScrollView, UIScrollViewDelegate {
    static let tileSide: CGFloat = 256
    static let padding: CGFloat = 14

    var onTap: (CGPoint) -> Void = { _ in }
    var onLongPress: (CGPoint) -> Void = { _ in }
    /// Returns the zoom the model settled on.
    var onPinchEnd: (CGFloat) -> MapZoom? = { _ in nil }
    var rowValue: (RowRef) -> String = { _ in "" }
    var fieldName = ""

    private(set) var painter = MapPainter(scene: .empty, palette: MapPalette(traits: .current))
    private let content = MapContentView()
    private var tiles: [TileKey: MapTileView] = [:]
    /// Kept alive here: accessibility holds elements weakly.
    private var rowElementCache: [RowRef: MapRowElement] = [:]
    private var layoutKey: TreeMapModel.LayoutKey?
    private var revision = -1
    private var style: UIUserInterfaceStyle = .unspecified
    private var lastScroll: MapScrollRequest?
    /// Where the visible middle was before a zoom, so the same trees stay under the eyes.
    private var focusBeforeRelayout: (blockId: UUID, x: CGFloat, y: CGFloat)?

    private struct TileKey: Hashable {
        var column: Int
        var row: Int
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        showsHorizontalScrollIndicator = true
        showsVerticalScrollIndicator = true
        alwaysBounceVertical = false
        bouncesZoom = true
        decelerationRate = .normal
        contentInsetAdjustmentBehavior = .never
        contentInset = UIEdgeInsets(top: Self.padding, left: Self.padding, bottom: Self.padding + 70, right: Self.padding)
        minimumZoomScale = 0.2
        maximumZoomScale = 3
        content.map = self
        content.isAccessibilityElement = false
        addSubview(content)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        longPress.minimumPressDuration = 0.45
        addGestureRecognizer(longPress)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.require(toFail: longPress)
        addGestureRecognizer(tap)

        accessibilityIdentifier = "tree-map"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: New content

    func apply(scene: MapScene, layoutKey: TreeMapModel.LayoutKey, revision: Int, dirty: Set<RowRef>?,
               style: UIUserInterfaceStyle, scrollTo request: MapScrollRequest?) {
        let relayout = layoutKey != self.layoutKey
        let restyle = style != self.style
        let sameField = layoutKey.field == self.layoutKey?.field
        // A new size keeps the same trees in the middle; anything else keeps the scroll position.
        if relayout && sameField && layoutKey.zoom != self.layoutKey?.zoom && focusBeforeRelayout == nil {
            focusBeforeRelayout = visibleFocus()
        }
        painter.scene = scene
        if restyle {
            self.style = style
            painter.palette = MapPalette(traits: UITraitCollection(userInterfaceStyle: style))
        }

        if relayout {
            self.layoutKey = layoutKey
            relayoutContent(keepFocus: sameField)
        } else if restyle || revision != self.revision {
            redraw(dirty: restyle ? nil : dirty)
        }
        self.revision = revision

        if let request, request != lastScroll {
            lastScroll = request
            scroll(toBlock: request.blockId)
        }
    }

    private func relayoutContent(keepFocus: Bool) {
        let size = painter.scene.layout.size
        if zoomScale != 1 { zoomScale = 1 }
        content.transform = .identity
        content.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        tiles.values.forEach { $0.removeFromSuperview() }
        tiles.removeAll()
        rowElementCache.removeAll()
        if keepFocus, let focus = focusBeforeRelayout, let f = painter.scene.layout.frame(of: focus.blockId) {
            let point = CGPoint(x: f.grid.minX + focus.x * f.grid.width, y: f.grid.minY + focus.y * f.grid.height)
            contentOffset = clampedOffset(CGPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2))
        } else if !keepFocus {
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        } else {
            contentOffset = clampedOffset(contentOffset)
        }
        focusBeforeRelayout = nil
        setNeedsLayout()
        layoutIfNeeded()
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    private func redraw(dirty: Set<RowRef>?) {
        guard let dirty else {
            tiles.values.forEach { $0.setNeedsDisplay() }
            return
        }
        let bands = dirty.compactMap { painter.scene.band(of: $0) }
        for tile in tiles.values {
            for band in bands where band.intersects(tile.frame) {
                tile.setNeedsDisplay(band.intersection(tile.frame).offsetBy(dx: -tile.frame.minX, dy: -tile.frame.minY))
            }
        }
    }

    // MARK: Tiles

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTiles()
    }

    private func updateTiles() {
        let size = painter.scene.layout.size
        guard size.width > 0, size.height > 0 else {
            tiles.values.forEach { $0.removeFromSuperview() }
            tiles.removeAll()
            return
        }
        let side = Self.tileSide
        // Visible part of the map, in map points, plus a margin so a flick finds tiles ready.
        let visible = convert(bounds, to: content).insetBy(dx: -side / 2, dy: -side / 2)
            .intersection(CGRect(origin: .zero, size: size))
        guard !visible.isNull, !visible.isEmpty else { return }
        let columns = Int((visible.minX / side).rounded(.down))...Int(((visible.maxX - 0.01) / side).rounded(.down))
        let rows = Int((visible.minY / side).rounded(.down))...Int(((visible.maxY - 0.01) / side).rounded(.down))
        var wanted = Set<TileKey>()
        for column in columns {
            for row in rows { wanted.insert(TileKey(column: column, row: row)) }
        }
        for (key, tile) in tiles where !wanted.contains(key) {
            tile.removeFromSuperview()
            tiles[key] = nil
        }
        for key in wanted where tiles[key] == nil {
            let frame = CGRect(x: CGFloat(key.column) * side, y: CGFloat(key.row) * side, width: side, height: side)
                .intersection(CGRect(origin: .zero, size: size))
            let tile = MapTileView(frame: frame)
            tile.map = self
            tile.contentScaleFactor = max(1, traitCollection.displayScale)
            content.addSubview(tile)
            tiles[key] = tile
        }
    }

    // MARK: Gestures

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onTap(gesture.location(in: content))
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onLongPress(gesture.location(in: content))
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        content
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        focusBeforeRelayout = nil
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Remember the trees in the middle at the old size, then let the model pick a size.
        let focus = visibleFocus()
        let cell = painter.scene.layout.metrics.cell.width * scale
        let before = layoutKey?.zoom
        let after = onPinchEnd(cell)
        if after == nil || after == before {
            setZoomScale(1, animated: true)
        } else {
            focusBeforeRelayout = focus
        }
    }

    // MARK: Positions

    /// The block under the middle of the screen, and where in its trees (0...1 across and down).
    private func visibleFocus() -> (blockId: UUID, x: CGFloat, y: CGFloat)? {
        let mid = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: content)
        let frames = painter.scene.layout.frames
        guard !frames.isEmpty else { return nil }
        let f = frames.first { $0.frame.contains(mid) } ?? frames.min { distance($0.frame, mid) < distance($1.frame, mid) }!
        guard f.grid.width > 0, f.grid.height > 0 else { return nil }
        return (f.block.id, min(1, max(0, (mid.x - f.grid.minX) / f.grid.width)), min(1, max(0, (mid.y - f.grid.minY) / f.grid.height)))
    }

    private func distance(_ rect: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private func scroll(toBlock id: UUID) {
        guard let f = painter.scene.layout.frame(of: id) else { return }
        setContentOffset(clampedOffset(CGPoint(x: f.frame.minX - 4, y: f.frame.minY - 4)), animated: false)
    }

    private func clampedOffset(_ p: CGPoint) -> CGPoint {
        let maxX = max(-contentInset.left, contentSize.width + contentInset.right - bounds.width)
        let maxY = max(-contentInset.top, contentSize.height + contentInset.bottom - bounds.height)
        return CGPoint(x: min(max(p.x, -contentInset.left), maxX), y: min(max(p.y, -contentInset.top), maxY))
    }

    // MARK: Accessibility

    /// The row numbers on screen, so Voice Control can "tap Block 1, row 5" and tests can find them.
    func rowElements() -> [Any] {
        let layout = painter.scene.layout
        guard !layout.metrics.isOverview else { return [] }
        let visible = convert(bounds, to: content)
        var elements: [Any] = []
        for f in layout.frames where f.frame.intersects(visible) {
            for row in 0..<max(0, f.block.rowCount) {
                let ref = RowRef(blockId: f.block.id, row: row)
                guard let rect = layout.rowHeaderRect(ref), rect.intersects(visible) else { continue }
                let element = rowElementCache[ref] ?? makeRowElement(ref, block: f.block, rect: rect)
                rowElementCache[ref] = element
                elements.append(element)
            }
        }
        return elements
    }

    private func makeRowElement(_ ref: RowRef, block: Block, rect: CGRect) -> MapRowElement {
        let element = MapRowElement(accessibilityContainer: content)
        element.accessibilityFrameInContainerSpace = rect
        element.accessibilityLabel = block.label(row: ref.row)
        element.accessibilityTraits = .button
        element.accessibilityHint = "Marks or clears the whole row."
        element.accessibilityIdentifier = "map-row-\(block.name)-\(ref.row + 1)"
        let center = CGPoint(x: rect.midX, y: rect.midY)
        element.activate = { [weak self] in self?.onTap(center) }
        element.value = { [weak self] in self?.rowValue(ref) ?? "" }
        return element
    }

    override var accessibilityElements: [Any]? {
        get { [content] }
        set {}
    }
}
