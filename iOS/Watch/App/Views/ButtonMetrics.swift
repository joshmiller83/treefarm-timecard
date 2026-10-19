import SwiftUI
import WatchKit

/// Glove-sized button heights by watch size (docs/watch.md 3.1), all well above the 44 pt
/// default:
///
/// |                 | 40 / 41 / 42 mm | 44 / 45 / 46 mm | 49 mm |
/// |-----------------|-----------------|-----------------|-------|
/// | Primary         | 60              | 64              | 68    |
/// | Controls grid   | 56              | 60              | 62    |
/// | Clock out       | 52              | 56              | 58    |
/// | Undo, Record    | 48              | 52              | 54    |
struct ButtonMetrics: Equatable, Sendable {
    enum Size: Sendable { case small, medium, large }

    let size: Size

    /// Sized by the screen's height in points: 40 mm 197, 41 mm 215, 42 mm 223 are small;
    /// 44 mm 224, 45 mm 242, 46 mm 248 are medium; the 49 mm Ultras (251, 257) are large.
    init(screenHeight: CGFloat) {
        size = screenHeight >= 250 ? .large : screenHeight >= 224 ? .medium : .small
    }

    static var current: ButtonMetrics {
        ButtonMetrics(screenHeight: WKInterfaceDevice.current().screenBounds.height)
    }

    var primary: CGFloat { pick(60, 64, 68) }
    var grid: CGFloat { pick(56, 60, 62) }
    var clockOut: CGFloat { pick(52, 56, 58) }
    var secondary: CGFloat { pick(48, 52, 54) }

    /// The primary button's words: a little smaller on the smallest watches, so "Back to work"
    /// and "Row 14 done" keep their words.
    var primaryFont: Font {
        isSmall ? .system(.headline, design: .rounded).weight(.bold) : .system(.title3, design: .rounded).weight(.semibold)
    }

    /// The big timer's size before Dynamic Type scales it.
    var timer: CGFloat { pick(32, 38, 42) }

    var isSmall: Bool { size == .small }
    var isLarge: Bool { size == .large }

    private func pick(_ small: CGFloat, _ medium: CGFloat, _ large: CGFloat) -> CGFloat {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }
}
