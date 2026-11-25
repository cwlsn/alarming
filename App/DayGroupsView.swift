import AlarmingCore
import Observation
import SwiftUI

/// The person's own day groups, kept between launches.
@MainActor @Observable
final class DayGroupStore {
    static let shared = DayGroupStore()
    private let preferences = DayGroupPreferences(store: Services.preferences)

    /// May hold unfinished groups while they are being edited.
    var editing: [DayGroup] { didSet { preferences.save(editing) } }
    var groups: [DayGroup] { DayGroup.normalized(editing) }

    private init() { editing = preferences.load() }

    func tidy() { editing = groups }
}

/// Every group is edited in place, so there is no second screen.
struct DayGroupsView: View {
    @Bindable var store = DayGroupStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($store.editing) { $group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.days.isEmpty ? "New group" : group.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(group.days.isEmpty ? Color.quiet : Color.primary)
                                .accessibilityHidden(true)
                            DayRow(days: $group.days)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("day-group")
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { remove(group) }
                        }
                    }
                    Button("Add group", systemImage: "plus") {
                        withAnimation(.smooth) { store.editing.append(DayGroup(days: [])) }
                    }
                } footer: {
                    Text("Swipe left on a group to delete it. Empty and repeated groups are not kept.")
                }
            }
            .navigationTitle("Day groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.buttonStyle(.glassProminent).tint(.accentFill)
                }
            }
        }
        .onDisappear { store.tidy() }
    }

    private func remove(_ group: DayGroup) {
        withAnimation(.smooth) { store.editing.removeAll { $0.id == group.id } }
    }
}

/// Seven day buttons.
struct DayRow: View {
    @Binding var days: Set<Locale.Weekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RepeatDays.inWeekOrder(), id: \.day) { item in
                let selected = days.contains(item.day)
                Button { days.formSymmetricDifference([item.day]) } label: {
                    Text(item.letter)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.quiet)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.chip)
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentFill)
                                .scaleEffect(selected ? 1 : 0.5)
                                .opacity(selected ? 1 : 0)
                        }
                        .contentShape(.rect)
                }
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .buttonStyle(SpringyButtonStyle())
        .animation(.spring(duration: 0.35, bounce: 0.35), value: days)
        .sensoryFeedback(.selection, trigger: days)
    }
}
