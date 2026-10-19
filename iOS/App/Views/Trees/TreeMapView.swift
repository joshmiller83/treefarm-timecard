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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    func makeUIView(context: Context) -> TreeMapScrollView {
        let view = TreeMapScrollView()
        view.onTap = { [weak model] point in model?.tap(at: point) }
        view.onLongPress = { [weak model] point in model?.longPress(at: point) }
        view.onPinchEnd = { [weak model] width in model?.pinchEnded(cellWidth: width) }
        view.onSettled = { [weak model] blockId in model?.mapSettled(on: blockId) }
        view.rowValue = { [weak model] row in model?.rowSummary(row)?.value ?? "" }
        return view
    }

    func updateUIView(_ view: TreeMapScrollView, context: Context) {
        // Reading these here is what makes SwiftUI call back when they change.
        let revision = model.revision
        let key = model.layoutKey
        let request = model.scrollRequest
        let look = MapLook(dark: colorScheme == .dark, highContrast: contrast == .increased)
        var scene = MapScene(
            layout: model.layout,
            index: model.data?.index ?? MarkIndex(marks: []),
            markingShiftId: model.markingShift?.id,
            noteTrees: Set(model.data?.notesByTree.keys.map { $0 } ?? []),
            anchor: model.anchor,
            focus: model.openTree?.tree)
        scene.pips = differentiateWithoutColor
        view.fieldName = model.field?.name ?? ""
        view.apply(scene: scene, layoutKey: key, revision: revision, dirty: model.takeDirtyRows(),
                   look: look, scrollTo: request)
    }
}

/// Light or dark, and whether Increase Contrast is on: what the map's colors depend on.
struct MapLook: Equatable {
    var dark: Bool
    var highContrast: Bool

    var traits: UITraitCollection { MapPalette.traits(dark: dark, highContrast: highContrast) }
}

/// Lets the map's tap through only when the map is still. A touch that stops a flick just
/// stops it, as on the web map, instead of also marking whatever tree it landed on.
private final class TapGate: NSObject, UIGestureRecognizerDelegate {
    weak var map: TreeMapScrollView?

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(map?.isGliding ?? false)
    }
}

/// One square of the map. Drawn to an image off the main thread, then shown, so scrolling at
/// 120 Hz never waits on drawing; the old picture stays up until the new one is ready.
final class MapTileView: UIView {
    /// One serial queue for every tile: drawing keeps up with the screen, never with the touch.
    static let queue = DispatchQueue(label: "TimeCard.map-tiles", qos: .userInitiated)
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.contentsGravity = .resize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws the tile with `painter` at `scale` and shows it when done (a newer request wins).
    func render(_ painter: MapPainter, scale: CGFloat) {
        generation += 1
        let mine = generation
        let frame = self.frame
        guard frame.width > 0, frame.height > 0 else { return }
        Self.queue.async { [weak self] in
            let image = MapTileView.draw(painter, frame: frame, scale: scale)
            DispatchQueue.main.async {
                guard let self, self.generation == mine else { return }
                self.layer.contents = image
            }
        }
    }

    nonisolated static func draw(_ painter: MapPainter, frame: CGRect, scale: CGFloat) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
            let ctx = context.cgContext
            ctx.translateBy(x: -frame.minX, y: -frame.minY)
            painter.draw(frame, in: ctx)
        }.cgImage
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
    /// The map came to rest with this block in the middle.
    var onSettled: (UUID?) -> Void = { _ in }
    var rowValue: (RowRef) -> String = { _ in "" }
    var fieldName = ""

    private(set) var painter = MapPainter(scene: .empty, palette: MapPalette(traits: .current))
    private let content = MapContentView()
    private var tiles: [TileKey: MapTileView] = [:]
    /// The whole map, small, shown while a pinch zooms out a long way: dozens of full-size
    /// tiles would be drawn for one gesture. Real tiles come back when the gesture settles.
    private let overview = UIImageView()
    private var overviewKey: (layout: TreeMapModel.LayoutKey, revision: Int, look: MapLook?)?
    static let overviewBelowScale: CGFloat = 0.6
    /// Kept alive here: accessibility holds elements weakly.
    private var rowElementCache: [RowRef: MapRowElement] = [:]
    private var layoutKey: TreeMapModel.LayoutKey?
    private var revision = -1
    private var look: MapLook?
    private var lastScroll: MapScrollRequest?
    private var pendingScroll: MapScrollRequest?
    private let tapGate = TapGate()
    /// When the map last moved on its own after a flick.
    private var lastGlide: CFTimeInterval = 0
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
        overview.isHidden = true
        overview.contentMode = .scaleToFill
        overview.isUserInteractionEnabled = false
        content.addSubview(overview)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        longPress.minimumPressDuration = 0.45
        addGestureRecognizer(longPress)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.require(toFail: longPress)
        tapGate.map = self
        tap.delegate = tapGate
        addGestureRecognizer(tap)

        accessibilityIdentifier = "tree-map"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: New content

    func apply(scene: MapScene, layoutKey: TreeMapModel.LayoutKey, revision: Int, dirty: Set<RowRef>?,
               look: MapLook, scrollTo request: MapScrollRequest?) {
        let relayout = layoutKey != self.layoutKey
        let restyle = look != self.look || scene.pips != painter.scene.pips
        let sameField = layoutKey.field == self.layoutKey?.field
        // A new size keeps the same trees in the middle; anything else keeps the scroll position.
        if relayout && sameField && layoutKey.zoom != self.layoutKey?.zoom && focusBeforeRelayout == nil {
            focusBeforeRelayout = visibleFocus()
        }
        painter.scene = scene
        if look != self.look {
            self.look = look
            painter.palette = MapPalette(traits: look.traits)
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
            // Before the first layout there's no size to place the row in; wait for it.
            if bounds.isEmpty { pendingScroll = request } else { scroll(to: request) }
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
        overview.isHidden = true
        overview.image = nil
        overviewKey = nil
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
        let scale = tileScale
        guard let dirty else {
            tiles.values.forEach { $0.render(painter, scale: scale) }
            return
        }
        let bands = dirty.compactMap { painter.scene.band(of: $0) }
        for tile in tiles.values where bands.contains(where: { $0.intersects(tile.frame) }) {
            tile.render(painter, scale: scale)
        }
    }

    private var tileScale: CGFloat { max(1, traitCollection.displayScale) }

    // MARK: Tiles

    override func layoutSubviews() {
        super.layoutSubviews()
        if let pending = pendingScroll, !bounds.isEmpty {
            pendingScroll = nil
            scroll(to: pending)
        }
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
        // Pinching out a long way: the small whole-map picture stands in, and no new full-size
        // tiles are drawn until the gesture settles on a size.
        let zoomedOut = (isZooming || isZoomBouncing) && zoomScale < Self.overviewBelowScale
        showOverview(zoomedOut)
        if zoomedOut { return }
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
            content.addSubview(tile)
            tiles[key] = tile
            tile.render(painter, scale: tileScale)
        }
    }

    private func showOverview(_ show: Bool) {
        guard show else {
            if !overview.isHidden { overview.isHidden = true }
            return
        }
        let size = painter.scene.layout.size
        overview.frame = CGRect(origin: .zero, size: size)
        content.sendSubviewToBack(overview)
        overview.isHidden = false
        guard let layoutKey, overviewKey?.layout != layoutKey || overviewKey?.revision != revision || overviewKey?.look != look else { return }
        overviewKey = (layoutKey, revision, look)
        // Small enough to draw quickly; it's only seen shrinking under the fingers.
        let scale = min(1, 1600 / max(size.width, size.height, 1))
        let painter = self.painter
        let frame = CGRect(origin: .zero, size: size)
        MapTileView.queue.async { [weak self] in
            let image = MapTileView.draw(painter, frame: frame, scale: scale)
            DispatchQueue.main.async {
                guard let self, self.overviewKey?.layout == layoutKey, let image else { return }
                self.overview.image = UIImage(cgImage: image)
            }
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

    /// Still moving after a flick, or stopped by a touch a moment ago.
    var isGliding: Bool {
        isDecelerating || CACurrentMediaTime() - lastGlide < 0.08
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isDecelerating { lastGlide = CACurrentMediaTime() }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { reportSettled() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        reportSettled()
    }

    /// Typed numbers go to the block the map came to rest on.
    private func reportSettled() {
        guard !painter.scene.layout.metrics.isOverview else { return }
        onSettled(visibleFocus()?.blockId)
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

    /// The block's top-left corner, or, when a row is named that wouldn't be in view from there,
    /// that row a third of the way down (clear of the zoom bar at the bottom).
    private func scroll(to request: MapScrollRequest) {
        let layout = painter.scene.layout
        guard let f = layout.frame(of: request.blockId) else { return }
        var target = CGPoint(x: f.frame.minX - 4, y: f.frame.minY - 4)
        if let row = request.row, let rect = layout.rowHeaderRect(RowRef(blockId: request.blockId, row: row)) {
            let clear: CGFloat = 96
            if rect.maxY > target.y + bounds.height - clear { target.y = rect.midY - bounds.height / 3 }
            if rect.maxX > target.x + bounds.width - 16 { target.x = rect.midX - bounds.width / 2 }
        }
        setContentOffset(clampedOffset(target), animated: false)
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
