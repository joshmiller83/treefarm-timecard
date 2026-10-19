import SwiftUI
import TimeCardCore

/// A small picture of a field's strips of blocks, drawn with the map's own geometry
/// (`FieldLayout` in its fit-to-width overview). Shaped trees this season show in fir
/// green; the block being edited or added shows in sap gold, a new one dashed. A tap on a
/// block reports it, so the preview doubles as a way to pick one.
struct MiniMapView: View {
    var blocks: [Block]
    var shaped: [TreeRef] = []
    var highlight: UUID?
    var highlightIsNew = false
    var maxHeight: CGFloat = 170
    var accessibilityText: String
    var onTapBlock: ((UUID) -> Void)?

    @State private var width: CGFloat = 0

    private var live: [Block] { blocks.filter { $0.deletedAt == nil } }

    var body: some View {
        Group {
            if live.isEmpty {
                empty
            } else {
                map
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var empty: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .frame(height: 72)
            .overlay {
                Text("No blocks yet").font(.subheadline).foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var map: some View {
        let geometry = Geometry(blocks: live, width: width, maxHeight: maxHeight)
        Canvas { context, _ in
            draw(geometry, in: &context)
        }
        .frame(height: geometry.height)
        .modifier(BlockTap(geometry: geometry, onTapBlock: onTapBlock))
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("mini-map")
    }

    private func draw(_ g: Geometry, in context: inout GraphicsContext) {
        guard let layout = g.layout else { return }
        var cells = Path()
        for tree in shaped {
            if let rect = layout.cellRect(tree) { cells.addRect(g.toView(rect)) }
        }
        for frame in layout.frames where frame.block.id != highlight {
            let outline = Path(roundedRect: g.toView(frame.outline), cornerRadius: 3)
            context.fill(outline, with: .color(Palette.treeEmpty))
        }
        context.fill(cells, with: .color(Palette.fir))
        for frame in layout.frames {
            let selected = frame.block.id == highlight
            let rect = g.toView(frame.outline)
            let outline = Path(roundedRect: rect, cornerRadius: 3)
            if selected {
                context.fill(outline, with: .color(Palette.sapSoft))
                context.stroke(outline, with: .color(Palette.sap),
                               style: StrokeStyle(lineWidth: 2.5, dash: highlightIsNew ? [5, 3] : []))
            } else {
                context.stroke(outline, with: .color(Palette.blockLine), lineWidth: 1)
            }
        }
        // Names last, on a small tag in the middle of each block, so shaped trees never hide them.
        for frame in layout.frames {
            let rect = g.toView(frame.outline)
            let size = min(13, rect.width * 0.42, rect.height * 0.42)
            guard size >= 7 else { continue }
            let selected = frame.block.id == highlight
            let text = context.resolve(Text(frame.block.name)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(selected ? Palette.sapInk : Palette.ink))
            let measured = text.measure(in: CGSize(width: rect.width, height: rect.height))
            guard measured.width <= rect.width - 4 else { continue }
            let tag = CGRect(x: rect.midX - measured.width / 2 - 4, y: rect.midY - measured.height / 2 - 1,
                             width: measured.width + 8, height: measured.height + 2)
            context.fill(Path(roundedRect: tag, cornerRadius: min(5, tag.height / 2)), with: .color(Palette.surface.opacity(0.85)))
            context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }

    /// Picks a block on tap, only when someone listens: otherwise taps go to what's around
    /// the map (a field card is a link).
    private struct BlockTap: ViewModifier {
        var geometry: Geometry
        var onTapBlock: ((UUID) -> Void)?

        func body(content: Content) -> some View {
            if let onTapBlock {
                content
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard case .block(let id)? = geometry.layout?.hitTest(geometry.toMap(location)) else { return }
                        onTapBlock(id)
                    }
            } else {
                content
            }
        }
    }

    /// Fits the overview into the width, then scales it down if it's taller than `maxHeight`.
    private struct Geometry {
        var layout: FieldLayout?
        var scale: CGFloat = 1
        var dx: CGFloat = 0
        var height: CGFloat = 72

        init(blocks: [Block], width: CGFloat, maxHeight: CGFloat) {
            guard width > 0 else { return }
            let layout = FieldLayout(blocks: blocks, metrics: .overview(blocks: blocks, width: width))
            guard layout.size.height > 0, layout.size.width > 0 else { return }
            self.layout = layout
            scale = min(1, maxHeight / layout.size.height, width / layout.size.width)
            dx = max(0, (width - layout.size.width * scale) / 2)
            height = layout.size.height * scale
        }

        func toView(_ r: CGRect) -> CGRect {
            CGRect(x: dx + r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
        }

        func toMap(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - dx) / scale, y: p.y / scale)
        }
    }
}

extension MiniMapView {
    /// "North Field: 4 blocks in 2 rows."
    static func describe(fieldName: String, blocks: [Block]) -> String {
        let live = blocks.filter { $0.deletedAt == nil }
        guard !live.isEmpty else { return "\(fieldName): no blocks yet." }
        let strips = Set(live.map(\.gridRow)).count
        return "\(fieldName): \(Fmt.plural(live.count, "block")) in \(Fmt.plural(strips, "row"))."
    }
}
