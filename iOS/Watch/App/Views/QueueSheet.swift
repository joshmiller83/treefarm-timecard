import SwiftUI
import TreeFarmKit

/// The taps waiting for the phone, with their times, and those it refused in the last hour
/// (docs/watch.md 3.7). They count at the time they were tapped once the phone is back.
struct QueueSheet: View {
    let model: WatchShiftModel

    var body: some View {
        let state = model.displayed
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !model.queue.isEmpty {
                    Text(WatchDisplay.waitingLine(count: model.waitingCount))
                        .font(.system(.headline, design: .rounded))
                    ForEach(model.queue) { request in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: WatchDisplay.queueGlyph)
                                .font(.system(.caption2).weight(.bold))
                                .foregroundStyle(WatchPalette.sap)
                            Text(WatchDisplay.queueItemLine(request, state: state))
                                .font(.system(.footnote, design: .rounded).weight(.medium))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("queuedTap")
                    }
                    Text(WatchDisplay.queueFootnote)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if model.dropped > 0 {
                    Text(WatchDisplay.droppedLine(model.dropped))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(WatchPalette.sap)
                }
                if !model.refused.isEmpty {
                    Divider()
                    ForEach(model.refused) { tap in
                        Text(WatchDisplay.refusedItemLine(tap.request, speech: tap.speech, state: state))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(WatchPalette.rustBright)
                    }
                }
                Label(WatchDisplay.phoneLine(model.reach, waiting: model.waitingCount),
                      systemImage: model.reach == .reachable ? WatchDisplay.Glyph.phone : WatchDisplay.Glyph.phoneAway)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("queueSheet")
    }
}
