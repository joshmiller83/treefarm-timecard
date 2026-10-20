import RelevanceKit
import SwiftUI
import TreeFarmKit
import WidgetKit

/// The shift on the wrist: the watch face complications and the Smart Stack widget.
///
/// Its only data is what the watch app writes to the App Group (`WatchStateFile`): the
/// **displayed** state, with taps that still wait for the phone already applied, and the
/// waiting count. The extension never touches WCSession. The timeline never expires: every
/// timer and ring ticks by itself, off the clock a second entry turns "6.5 h today" back to
/// "IN" at the farm's midnight (`ComplicationDay`), and the app reloads it when
/// `ComplicationReload.needsReload` says something shown changed. Tapping it opens the app,
/// the glove-friendly way back in.
struct ShiftComplication: Widget {
    static let kind = ComplicationReload.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ShiftComplicationProvider()) { entry in
            ShiftComplicationView(entry: entry)
        }
        .configurationDisplayName(WatchDisplay.appName)
        .description("Your shift at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

struct ShiftComplicationEntry: TimelineEntry {
    /// What the watch app last wrote.
    let contents: WatchStateFile.Contents
    let date: Date

    /// What it shows at this entry's moment.
    var face: ComplicationFace { ComplicationFace(contents, at: date) }

    /// What the face editor and the widget gallery show: a shift under way.
    static func sample(at now: Date) -> ShiftComplicationEntry {
        let block = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let rows = (14...16).map { RowChip(blockId: block, row: $0 - 1, title: "Row \($0)", blockName: "Block 2") }
        let worked: TimeInterval = 3 * 3600 + 41 * 60 + 7
        let snapshot = LiveSnapshot(phase: .working, timerStart: now.addingTimeInterval(-worked), workedSoFar: worked,
                                    workedLabel: "worked today", breakStart: nil, breakReason: "", fieldName: "North",
                                    nextRows: rows, shiftTrees: 38, fieldShaped: 120, fieldTotal: 400, lastAction: nil, canUndo: false)
        let state = WatchState(signedIn: true, farmName: "", fieldName: "North", snapshot: snapshot, nextRows: rows,
                               todayWorked: worked, todayTrees: 38, canUndo: false, recordWorkouts: true, updatedAt: now,
                               shiftStart: now.addingTimeInterval(-worked))
        return ShiftComplicationEntry(contents: WatchStateFile.Contents(displayed: state), date: now)
    }
}

struct ShiftComplicationProvider: TimelineProvider {
    /// Where the watch app leaves its displayed state (tests and previews pass their own).
    var read: @Sendable () -> WatchStateFile.Contents = { WatchStateFile.read() }

    func placeholder(in context: Context) -> ShiftComplicationEntry {
        .sample(at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ShiftComplicationEntry) -> Void) {
        completion(context.isPreview ? .sample(at: Date()) : ShiftComplicationEntry(contents: read(), date: Date()))
    }

    /// Now, and the farm's midnight when hours today are showing; never expires, so the
    /// midnight entry spends no reload.
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ShiftComplicationEntry>) -> Void) {
        let contents = read()
        let dates = ComplicationDay.entryDates(for: contents.displayed, now: Date())
        completion(Timeline(entries: dates.map { ShiftComplicationEntry(contents: contents, date: $0) }, policy: .never))
    }

    /// The Smart Stack raises the widget all shift long, and around the usual clock-in time.
    func relevance() async -> WidgetRelevance<Void> {
        let windows = ComplicationRelevance.windows(for: read().displayed, now: Date())
        return WidgetRelevance(windows.map { WidgetRelevanceAttribute(context: Self.context($0)) })
    }

    static func context(_ window: ComplicationRelevance.Window) -> RelevantContext {
        if #available(watchOS 26.0, *) {
            return .date(interval: window.interval, kind: window.kind == .shift ? .default : .scheduled)
        }
        return .date(from: window.interval.start, to: window.interval.end)
    }
}
