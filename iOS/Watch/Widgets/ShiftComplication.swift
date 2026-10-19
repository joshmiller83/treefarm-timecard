import RelevanceKit
import SwiftUI
import TreeFarmKit
import WidgetKit

/// The shift on the wrist: the watch face complications and the Smart Stack widget.
///
/// Its only data is what the watch app writes to the App Group (`WatchStateFile`): the
/// **displayed** state, with taps that still wait for the phone already applied, and the
/// waiting count. The extension never touches WCSession. The timeline is one entry that never
/// expires: every timer and ring ticks by itself, and the app reloads it when
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
    let state: WatchState?
    /// Taps waiting for the phone (not in flight).
    let waitingCount: Int
    /// A watch clock-out waits for the phone: "Clock-out waiting for iPhone".
    let clockOutWaiting: Bool
    let date: Date

    init(state: WatchState?, waitingCount: Int, date: Date, clockOutWaiting: Bool = false) {
        self.state = state
        self.waitingCount = waitingCount
        self.clockOutWaiting = clockOutWaiting
        self.date = date
    }

    init(_ contents: WatchStateFile.Contents, date: Date) {
        self.init(state: contents.displayed, waitingCount: contents.waitingCount, date: date, clockOutWaiting: contents.clockOutWaiting)
    }

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
        return ShiftComplicationEntry(state: state, waitingCount: 0, date: now)
    }
}

struct ShiftComplicationProvider: TimelineProvider {
    /// Where the watch app leaves its displayed state (tests and previews pass their own).
    var read: @Sendable () -> WatchStateFile.Contents = { WatchStateFile.read() }

    func placeholder(in context: Context) -> ShiftComplicationEntry {
        .sample(at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ShiftComplicationEntry) -> Void) {
        completion(context.isPreview ? .sample(at: Date()) : ShiftComplicationEntry(read(), date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ShiftComplicationEntry>) -> Void) {
        completion(Timeline(entries: [ShiftComplicationEntry(read(), date: Date())], policy: .never))
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
