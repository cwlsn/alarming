import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct SpikeWidgets: WidgetBundle {
    var body: some Widget { SpikeWidget() }
}

struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<SpikeMetadata>.self) { context in
            HStack {
                Text("Snoozes left: \(context.attributes.metadata?.snoozesLeft ?? 0)")
                Spacer()
                Remaining(state: context.state).font(.title2.monospacedDigit())
                Button("End", intent: StopIntent(alarmID: context.state.alarmID.uuidString))
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Remaining(state: context.state) }
            } compactLeading: {
                Image(systemName: "zzz")
            } compactTrailing: {
                Remaining(state: context.state).frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "zzz")
            }
        }
    }
}

struct Remaining: View {
    let state: AlarmPresentationState
    var body: some View {
        if case .countdown(let countdown) = state.mode {
            Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true)
        }
    }
}
