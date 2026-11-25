import AlarmingCore
import SwiftUI

struct AlarmListView: View {
    let model: AlarmModel
    @State private var editing: AlarmDefinition?
    @State private var errorMessage: String?
    @State private var savedCount = 0
    @Namespace private var zoom
    private static let addSource = "add"

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = max(context.date, .now)
            Group {
                if model.alarms.isEmpty && !model.permissionDenied && !model.storageFailed {
                    EmptyAlarms(minute: TimeText.minuteOfDay(now))
                } else {
                    list(now: now)
                }
            }
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(addSource: Self.addSource, zoom: zoom, create: create) { editing = blank() }
        }
        .animation(.smooth(duration: 0.35), value: model.alarms)
        .sheet(item: $editing) { alarm in
            let isNew = !model.alarms.contains { $0.id == alarm.id }
            AlarmEditorView(model: model, alarm: alarm, isNew: isNew) { savedCount += 1 } onError: { errorMessage = $0 }
                .navigationTransition(.zoom(sourceID: isNew ? AnyHashable(Self.addSource) : AnyHashable(alarm.id), in: zoom))
        }
        .alert("Alarm not changed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "") }
        .sensoryFeedback(.success, trigger: savedCount)
    }

    private func list(now: Date) -> some View {
        let next = model.alarms.filter(\.isEnabled)
            .compactMap { alarm in alarm.nextOccurrence(after: now).map { (alarm.id, $0) } }
            .min { $0.1 < $1.1 }
        return List {
            if model.permissionDenied { permissionBanner }
            if model.storageFailed {
                Label("Your alarms could not be read. Alarms already set will still ring.", systemImage: "exclamationmark.triangle.fill")
                    .listRowBackground(Color.clear)
            }
            if !model.alarms.isEmpty { header(next?.1, now: now) }
            ForEach(model.alarms) { alarm in
                AlarmRow(alarm: alarm, now: now, isOn: binding(for: alarm)) { editing = alarm }
                    .matchedTransitionSource(id: alarm.id, in: zoom)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparatorTint(.hairline)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .listRowBackground(RowGlow(alarm: alarm, isNext: alarm.id == next?.0))
                    .swipeActions { deleteButton(alarm) }
                    .contextMenu {
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(alarm) }
                        deleteButton(alarm)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func header(_ next: Date?, now: Date) -> some View {
        let text = next.map { TimeText.ringsIn($0, now: now) } ?? "No alarms on"
        return Text(text)
            .font(.title2.weight(.semibold))
            .tracking(-0.4)
            .contentTransition(.numericText())
            .animation(.snappy, value: text)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparatorTint(.hairline)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .listRowBackground(Color.clear)
    }

    private func deleteButton(_ alarm: AlarmDefinition) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) { run { try await model.delete(alarm.id) } }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Alarms are turned off", systemImage: "bell.slash.fill").font(.headline)
            Text("Allow Alarming to set alarms in Settings, or nothing will ring.").foregroundStyle(Color.quiet)
            Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                .buttonStyle(.plain)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentText)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func blank() -> AlarmDefinition {
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return Services.newAlarms.apply(to: AlarmDefinition(hour: now.hour ?? 7, minute: now.minute ?? 0))
    }

    private func create(_ entry: QuickEntry.Result) async -> Bool {
        let alarm = Services.newAlarms.apply(to: AlarmDefinition(hour: entry.hour, minute: entry.minute, days: entry.days, label: entry.label))
        do {
            try await model.save(alarm)
            savedCount += 1
            return true
        } catch {
            errorMessage = ErrorText.message(for: error)
            return false
        }
    }

    private func duplicate(_ alarm: AlarmDefinition) {
        run {
            try await model.save(AlarmDefinition(
                hour: alarm.hour, minute: alarm.minute, days: alarm.days, label: alarm.label,
                tone: alarm.tone, snooze: alarm.snooze, isEnabled: alarm.isEnabled))
        }
    }

    private func binding(for alarm: AlarmDefinition) -> Binding<Bool> {
        Binding(
            get: { model.alarms.first { $0.id == alarm.id }?.isEnabled ?? false },
            set: { enabled in run { try await model.setEnabled(enabled, id: alarm.id) } })
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { errorMessage = ErrorText.message(for: error) }
        }
    }
}

/// Type a whole alarm in one line, or open the wheel.
private struct QuickEntryBar: View {
    let addSource: String
    let zoom: Namespace.ID
    let create: (QuickEntry.Result) async -> Bool
    let openWheel: () -> Void
    @State private var text = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    private var entry: QuickEntry.Result? {
        QuickEntry.parse(text, now: .now, uses24Hour: TimeText.uses24Hour)
    }

    var body: some View {
        let entry = entry
        VStack(spacing: 8) {
            if !text.isEmpty {
                preview(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                TextField("7:30 weekdays gym", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                    .accessibilityLabel("Quick add")
                    .padding(.horizontal, 18)
                    .frame(minHeight: 50)
                    .glassEffect(.regular.interactive(), in: .capsule)
                Button {
                    if entry == nil { openWheel() } else { submit() }
                } label: {
                    Image(systemName: entry == nil ? "plus" : "arrow.up")
                        .font(.system(size: 19, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(SpringyButtonStyle())
                .glassEffect(.regular.tint(.accentFill).interactive(), in: .circle)
                .matchedTransitionSource(id: addSource, in: zoom)
                .accessibilityLabel(entry == nil ? "Add alarm" : "Create alarm")
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: entry)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: text.isEmpty)
    }

    @ViewBuilder private func preview(_ entry: QuickEntry.Result?) -> some View {
        if let entry {
            let alarm = AlarmDefinition(hour: entry.hour, minute: entry.minute, days: entry.days, label: entry.label)
            let next = alarm.nextOccurrence(after: .now) ?? .now
            VStack(alignment: .leading, spacing: 2) {
                Text("\(TimeText.string(next)) · \(alarm.displayLabel) · \(RepeatDays.summary(alarm.days))")
                    .font(.subheadline.weight(.semibold))
                Text(TimeText.ringsIn(next, now: .now)).font(.footnote).foregroundStyle(Color.quiet)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("quick-preview")
        } else {
            Text("Add a time, like 7:30 or in 20m").font(.subheadline).foregroundStyle(Color.quiet)
        }
    }

    private func submit() {
        guard let entry, !isSaving else { return }
        isSaving = true
        Task {
            if await create(entry) {
                text = ""
                focused = false
            }
            isSaving = false
        }
    }
}

private struct EmptyAlarms: View {
    let minute: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Group {
                if colorScheme == .dark {
                    LivingSky(minute: minute).opacity(0.6)
                } else {
                    // Night colors look gray on white, so light mode keeps a soft morning.
                    LinearGradient(colors: [.dusk.opacity(0.22), .accentFill.opacity(0.12), .cyan.opacity(0.16)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            }
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
            .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 8) {
                    ClockMark()
                    Text("No alarms yet").font(.title2.weight(.semibold)).tracking(-0.4)
                    Text("Type a time below, or tap + for the wheel.").foregroundStyle(Color.quiet)
                }
                .multilineTextAlignment(.center)
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.center, for: .alignment)
        }
    }
}

/// A trace of the alarm's sky, spreading from the switch when it turns on.
private struct RowGlow: View {
    let alarm: AlarmDefinition
    let isNext: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let diameter = 2.2 * hypot(proxy.size.width, proxy.size.height)
            SkyGradient(minute: alarm.hour * 60 + alarm.minute)
                .opacity(isNext ? 0.16 : 0.06)
                .mask {
                    Circle()
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(alarm.isEnabled || reduceMotion ? 1 : 0.001)
                        .position(x: proxy.size.width - 50, y: proxy.size.height / 2)
                }
                .opacity(alarm.isEnabled || !reduceMotion ? 1 : 0)
        }
        .background(Color.canvas)
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.55), value: alarm.isEnabled)
        .animation(.smooth, value: isNext)
    }
}

private struct AlarmRow: View {
    let alarm: AlarmDefinition
    let now: Date
    @Binding var isOn: Bool
    let edit: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var timeSize = 28

    private var next: Date { alarm.nextOccurrence(after: now) ?? now }
    private var wake: Date? { alarm.snooze.isEnabled ? alarm.snooze.projectedWake(from: next) : nil }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: edit) {
                HStack(spacing: 14) {
                    Capsule()
                        .fill(isOn ? AnyShapeStyle(bar) : AnyShapeStyle(Color.hairline))
                        .frame(width: 3)
                        .frame(maxHeight: 50)
                        .accessibilityHidden(true)
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(TimeText.display(next, size: min(timeSize, 60)))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .contentTransition(.numericText())
                                .foregroundStyle(isOn ? Color.primary : Color.quiet)
                            Text("\(alarm.displayLabel) · \(RepeatDays.summary(alarm.days))")
                                .font(.footnote)
                                .foregroundStyle(Color.quiet)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if alarm.snooze.isEnabled { snooze }
                    }
                }
                .padding(.vertical, 24)
                .contentShape(.rect)
            }
            .buttonStyle(SpringyButtonStyle(scale: 0.98))
            .accessibilityValue(alarm.snooze.summary)
            .accessibilityHint("Edits this alarm")
            .accessibilityIdentifier("alarm-row")
            Toggle("\(alarm.displayLabel) on", isOn: $isOn).labelsHidden().tint(.accentFill)
        }
        .animation(.smooth(duration: 0.35), value: isOn)
        .animation(.spring(duration: 0.5, bounce: 0.25), value: alarm)
        .sensoryFeedback(trigger: isOn) { _, on in on ? .impact(flexibility: .soft) : .impact(weight: .light) }
    }

    private var bar: LinearGradient {
        let sky = SkyPalette(minuteOfDay: alarm.hour * 60 + alarm.minute)
        return LinearGradient(colors: [Color(sky.middle), Color(sky.horizon)].map { $0.mix(with: .white, by: 0.3) }, startPoint: .top, endPoint: .bottom)
    }

    private var snooze: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 8) {
            Text(wake.map { "Up by \(TimeText.string($0))" } ?? "No limit")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(isOn && wake != nil ? Color.accentText : Color.quiet)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            SnoozeLadder(intervals: alarm.snooze.intervals, height: 4,
                         style: isOn ? nil : AnyShapeStyle(Color.secondary.opacity(0.4)))
                .frame(width: 84)
        }
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
    }
}

enum ErrorText {
    static func message(for error: any Error) -> String {
        switch error {
        case AlarmModelError.permissionDenied: "Allow Alarming to set alarms in Settings, then try again."
        case AlarmModelError.storageUnavailable: "Your saved alarms could not be read. Unlock your iPhone and try again."
        default: isLimit(error)
            ? "iOS has reached its limit for alarms. Turn one off and try again."
            : "iOS could not set this alarm. Please try again."
        }
    }
}

import AlarmKit

private func isLimit(_ error: any Error) -> Bool {
    error as? AlarmManager.AlarmError == .maximumLimitReached
}
