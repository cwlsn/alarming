import AlarmingCore
import SwiftUI

/// Every property on one screen. Closing an existing alarm saves it, so there is no Save button to find.
struct AlarmEditorView: View {
    let model: AlarmModel
    let isNew: Bool
    let onSave: () -> Void
    let onError: (String) -> Void
    @State private var draft: AlarmDefinition
    @State private var original: AlarmDefinition
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDeleted = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    init(model: AlarmModel, alarm: AlarmDefinition, isNew: Bool,
         onSave: @escaping () -> Void, onError: @escaping (String) -> Void) {
        self.model = model
        self.isNew = isNew
        self.onSave = onSave
        self.onError = onError
        var draft = alarm
        // Shown as a placeholder so there is nothing to clear before typing.
        if draft.label == AlarmDefinition.defaultLabel { draft.label = "" }
        _draft = State(initialValue: draft)
        _original = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    wheel
                    VStack(spacing: 26) {
                        DayPicker(days: $draft.days, isOneTime: $draft.isOneTime)
                        Divider()
                        TonePicker(tone: $draft.tone)
                        Divider()
                        if draft.isOneTime {
                            Label("Rings once without snooze, then disappears when you stop it.", image: "Poof")
                                .font(.subheadline)
                                .foregroundStyle(Color.quiet)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        } else {
                            SnoozeSettingsView(policy: $draft.snooze, start: draft.nextOccurrence(after: .now) ?? .now)
                                .transition(.opacity)
                        }
                        if !isNew {
                            Divider()
                            Button("Delete alarm", role: .destructive, action: delete)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.canvas.ignoresSafeArea())
            .safeAreaBar(edge: .bottom) { if isNew { addBar } }
            .animation(.smooth(duration: 0.3), value: draft.isOneTime)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .disabled(isSaving)
            .alert("Alarm not saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: { Text(errorMessage ?? "") }
        }
        .onDisappear { saveChanges() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { saveChanges() }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !isNew, draft != original {
                Button("Revert", systemImage: "arrow.uturn.backward") { withAnimation(.smooth) { draft = original } }
            }
        }
        ToolbarItem(placement: .principal) {
            TextField(AlarmDefinition.defaultLabel, text: $draft.label)
                .font(.headline)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .frame(minWidth: 120, minHeight: 44)
                .accessibilityLabel("Label")
        }
        ToolbarItem(placement: .confirmationAction) {
            Group {
                if isNew {
                    Button("Add", systemImage: "checkmark", action: add)
                        .accessibilityIdentifier("add-top")
                } else {
                    Button("Done") { dismiss() }
                }
            }
            .buttonStyle(.glassProminent)
            .tint(.accentFill)
        }
    }

    /// Within reach of a thumb, where the header buttons are not.
    private var addBar: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button { dismiss() } label: {
                Text("Cancel").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("cancel-bottom")
            Button(action: add) {
                Text("Add").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentFill)
            .accessibilityIdentifier("add-bottom")
        }
        .font(.headline)
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 8)
        // Content fades out above the buttons rather than showing through their glass.
        .background {
            LinearGradient(stops: [.init(color: Color.canvas.opacity(0), location: 0), .init(color: Color.canvas, location: 0.4)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var wheel: some View {
        VStack(spacing: 0) {
            DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 170)
                .clipped()
            TimelineView(.everyMinute) { context in
                let now = max(context.date, .now)
                let text = TimeText.ringsIn(draft.nextOccurrence(after: now) ?? now, now: now)
                Text(text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.quiet)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: text)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background {
            LivingSky(minute: draft.hour * 60 + draft.minute)
                .opacity(0.30)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .padding(.top, -160)
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                // A fixed winter day, so no clock change can hide a time.
                Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: draft.hour, minute: draft.minute)) ?? .now
            },
            set: {
                draft.hour = Calendar.current.component(.hour, from: $0)
                draft.minute = Calendar.current.component(.minute, from: $0)
            })
    }

    private func add() {
        isSaving = true
        draft.isEnabled = true
        Task {
            do {
                try await model.save(draft)
                Services.newAlarms.remember(draft)
                onSave()
                dismiss()
            } catch {
                errorMessage = ErrorText.message(for: error)
                isSaving = false
            }
        }
    }

    private func delete() {
        isSaving = true
        Task {
            do {
                try await model.delete(draft.id)
                isDeleted = true
                dismiss()
            } catch {
                errorMessage = ErrorText.message(for: error)
                isSaving = false
            }
        }
    }

    /// Saved once on the way out rather than on every touch, because saving ends a snooze in progress.
    private func saveChanges() {
        guard !isNew, !isDeleted, draft != original, let current = model.alarms.first(where: { $0.id == draft.id }) else { return }
        var changed = draft
        // Choosing a new time turns the alarm on. Anything else leaves it as it is now, which may
        // have changed while this screen was open.
        let movesRing = (draft.hour, draft.minute) != (original.hour, original.minute) || draft.days != original.days
        changed.isEnabled = movesRing || current.isEnabled
        let before = original
        original = draft
        Task {
            do {
                try await model.save(changed)
                Services.newAlarms.remember(changed)
                onSave()
            } catch {
                original = before
                onError(ErrorText.message(for: error))
            }
        }
    }
}

private struct DayPicker: View {
    @Binding var days: Set<Locale.Weekday>
    @Binding var isOneTime: Bool
    @State private var editsGroups = false

    private let presets: [(String, Set<Locale.Weekday>)] = [
        ("Daily", RepeatDays.everyDay), ("Weekdays", RepeatDays.weekdays), ("Weekends", RepeatDays.weekends),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DayRow(days: $days)
            ChipScroll {
                Button { isOneTime.toggle() } label: {
                    Chip(isSelected: isOneTime) {
                        Image("Poof").accessibilityHidden(true)
                        Text(AlarmDefinition.oneTimeName)
                    }
                }
                .accessibilityAddTraits(isOneTime ? .isSelected : [])
                ForEach(presets, id: \.0) { chip($0, $1) }
                ForEach(DayGroupStore.shared.groups) { group in
                    chip(group.title, group.days).accessibilityLabel(RepeatDays.summary(group.days))
                }
                Button { editsGroups = true } label: {
                    Chip(isSelected: false) { Image(systemName: "slider.horizontal.3") }
                }
                .accessibilityLabel("Edit day groups")
            }
            .buttonStyle(SpringyButtonStyle())
        }
        .animation(.spring(duration: 0.35, bounce: 0.35), value: days)
        .animation(.spring(duration: 0.35, bounce: 0.35), value: isOneTime)
        .sheet(isPresented: $editsGroups) { DayGroupsView().withoutAnimationsWhenUITesting() }
    }

    /// Tapping the active choice clears it.
    private func chip(_ name: String, _ value: Set<Locale.Weekday>) -> some View {
        let selected = days == value
        return Button { days = selected ? [] : value } label: { Chip(isSelected: selected) { Text(name) } }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of chips that runs to the screen edges.
struct ChipScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal) { HStack(spacing: 8) { content } }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
    }
}

struct Chip<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.accentText : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(isSelected ? Color.accentFill.opacity(0.16) : Color.chip, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentFill.opacity(0.6) : Color.hairline, lineWidth: 1)
            }
            .contentShape(.rect)
    }
}
