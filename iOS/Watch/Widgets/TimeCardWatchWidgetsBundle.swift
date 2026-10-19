import SwiftUI
import TreeFarmKit
import WidgetKit

// STUB: slice c replaces
//
// The watch complications (docs/watch.md 4.3): one StaticConfiguration, kind
// "timecard.watch.shift", all four accessory families, a single entry with policy `.never`,
// read from `WatchStateFile` (never WCSession). Words and glyphs come from `WatchDisplay`.

@main
struct TimeCardWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShiftComplication()
    }
}

struct ShiftComplicationEntry: TimelineEntry {
    let state: WatchState?
    let waitingCount: Int
    let date: Date

    init(state: WatchState?, waitingCount: Int, date: Date) {
        self.state = state
        self.waitingCount = waitingCount
        self.date = date
    }
}

struct ShiftComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShiftComplicationEntry {
        ShiftComplicationEntry(state: nil, waitingCount: 0, date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ShiftComplicationEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftComplicationEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> ShiftComplicationEntry {
        let contents = WatchStateFile.read()
        return ShiftComplicationEntry(state: contents.displayed, waitingCount: contents.waitingCount, date: Date())
    }
}

struct ShiftComplication: Widget {
    static let kind = "timecard.watch.shift"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ShiftComplicationProvider()) { entry in
            let phase = WatchDisplay.phase(entry.state)
            Image(systemName: WatchDisplay.phaseGlyph(phase))
                .widgetAccentable()
                .containerBackground(for: .widget) {}
        }
        .configurationDisplayName(WatchDisplay.appName)
        .description("Your shift at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
