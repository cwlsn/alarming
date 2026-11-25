import AlarmingCore
import SwiftUI
import WidgetKit

struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: NextAlarmKind.name, provider: NextAlarmProvider()) { NextAlarmView(entry: $0) }
            .configurationDisplayName("Next Alarm")
            .description("When your next alarm rings.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    let next: UpcomingAlarms.Next?
}

struct NextAlarmProvider: TimelineProvider {
    private static let sample = UpcomingAlarms(
        publishedAt: .now, alarms: [AlarmDefinition(hour: 6, minute: 30, days: RepeatDays.everyDay, label: "Work")])

    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(date: .now, next: Self.sample.next(after: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        let upcoming = context.isPreview ? Self.sample : UpcomingAlarmsFile.shared?.load()
        completion(NextAlarmEntry(date: .now, next: upcoming?.next(after: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let now = Date.now
        let upcoming = UpcomingAlarmsFile.shared?.load()
        let dates = [now] + (upcoming?.changes(after: now, limit: 20) ?? [])
        let entries = dates.map { NextAlarmEntry(date: $0, next: upcoming?.next(after: $0)) }
        // With nothing left to ring, only the app can change what is shown.
        completion(Timeline(entries: entries, policy: entries.last?.next == nil ? .never : .atEnd))
    }
}

struct NextAlarmView: View {
    let entry: NextAlarmEntry
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 40

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            // iOS draws this as one line of text beside the date.
            Label(inlineText, image: "CatClock")
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            rectangular
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .containerBackground(.clear, for: .widget)
        default:
            content
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .containerBackground(for: .widget) {
                    SkyGradient(minute: TimeText.minuteOfDay(entry.next?.date ?? entry.date))
                }
        }
    }

    private var inlineText: String {
        guard let next = entry.next else { return "No alarms on" }
        let days = daysUntil(next.date)
        let time = TimeText.string(next.date)
        return days == 0 ? time : "\(next.date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    @ViewBuilder private var rectangular: some View {
        if let next = entry.next {
            VStack(alignment: .leading, spacing: 0) {
                Label(dayName(next.date), image: "CatClock").font(.caption.weight(.semibold))
                Text(TimeText.display(next.date, size: 24)).widgetAccentable()
                Text(next.alarm.displayLabel).font(.caption)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Label("No alarms on", image: "CatClock").font(.headline).widgetAccentable()
                Text("Tap to set one").font(.caption)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private var content: some View {
        if let next = entry.next {
            VStack(alignment: .leading, spacing: 0) {
                Label(dayName(next.date), image: "CatClock")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(TimeText.display(next.date, size: min(timeSize, 52)))
                    .tracking(-0.8)
                    .widgetAccentable()
                Text(next.alarm.displayLabel).font(.subheadline)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Image("CatClock").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
                Spacer(minLength: 4)
                Text("No alarms on").font(.headline)
                Text("Tap to set one").font(.subheadline)
            }
            .minimumScaleFactor(0.6)
        }
    }

    private func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date), to: calendar.startOfDay(for: date)).day ?? 0
    }

    private func dayName(_ date: Date) -> String {
        switch daysUntil(date) {
        case 0: "Today"
        case 1: "Tomorrow"
        default: date.formatted(.dateTime.weekday(.wide))
        }
    }
}
