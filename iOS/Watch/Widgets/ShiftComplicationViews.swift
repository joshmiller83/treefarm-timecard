import SwiftUI
import TreeFarmKit
import WidgetKit

// The complication for each accessory family (docs/watch.md 4.3). The family views and their
// colors are in Watch/Shared (ComplicationFamilyViews.swift, ComplicationStyle.swift), so the
// watch tests can render them.

/// Picks the family's layout.
struct ShiftComplicationView: View {
    var entry: ShiftComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let face = entry.face
        Group {
            switch family {
            case .accessoryCircular: CircularComplication(face: face)
            case .accessoryCorner: CornerComplication(face: face)
            case .accessoryInline: InlineComplication(face: face)
            default: RectangularComplication(face: face)
            }
        }
        .containerBackground(for: .widget) {
            ComplicationStyle.background(face.tone)
        }
    }
}
