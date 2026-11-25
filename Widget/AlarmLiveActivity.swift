import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct AlarmingWidgets: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        OpenAlarmingControl()
        AlarmLiveActivity()
    }
}

struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RingMetadata>.self) { context in
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Details(metadata: context.attributes.metadata)
                    Spacer()
                    Remaining(state: context.state).font(.title.weight(.semibold))
                    EndButton(context: context)
                }
                Progress(state: context.state)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(LinearGradient(
                colors: [Color(white: 0.05), Color(red: 0.08, green: 0.07, blue: 0.16), Color(red: 0.08, green: 0.15, blue: 0.38)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Details(metadata: context.attributes.metadata) }
                DynamicIslandExpandedRegion(.trailing) {
                    Remaining(state: context.state).font(.title2.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Progress(state: context.state)
                        EndButton(context: context)
                    }
                }
            } compactLeading: {
                Image(systemName: "zzz").foregroundStyle(Color.accentBright)
            } compactTrailing: {
                Remaining(state: context.state).frame(maxWidth: 48).foregroundStyle(Color.accentBright)
            } minimal: {
                Image(systemName: "zzz").foregroundStyle(Color.accentBright)
            }
            .keylineTint(.accentBright)
        }
    }
}

private struct Details: View {
    let metadata: RingMetadata?

    private var left: String {
        switch metadata?.snoozesLeft {
        case nil: "Snoozing"
        case 0: "Last ring next"
        case 1: "1 snooze left"
        case let count?: "\(count) snoozes left"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metadata?.label ?? "Alarm").font(.headline).lineLimit(1)
            Text(left).font(.subheadline)
        }
    }
}

private struct Remaining: View {
    let state: AlarmPresentationState

    var body: some View {
        if case .countdown(let countdown) = state.mode {
            Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct Progress: View {
    let state: AlarmPresentationState

    var body: some View {
        if case .countdown(let countdown) = state.mode {
            ProgressView(timerInterval: countdown.startDate...countdown.fireDate, countsDown: false) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
                .tint(LinearGradient(colors: [.accentFill, .accentBright], startPoint: .leading, endPoint: .trailing))
        }
    }
}

private struct EndButton: View {
    let context: ActivityViewContext<AlarmAttributes<RingMetadata>>

    var body: some View {
        if let alarmID = context.attributes.metadata?.alarmID {
            Button("End", intent: StopIntent(ringID: context.state.alarmID.uuidString, alarmID: alarmID.uuidString))
                .buttonStyle(.borderedProminent)
                .tint(.accentFill)
                .foregroundStyle(.white)
        }
    }
}
