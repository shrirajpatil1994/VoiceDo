import SwiftData
import SwiftUI
import VoiceDoShared

struct ReminderListView: View {

    let persistence: PersistenceService
    let notificationService: NotificationService

    @Query(sort: \ReminderItem.dueDate)
    private var reminders: [ReminderItem]

    @State private var showCompleted = false
    @State private var alertError: VoiceDoError?

    private var filtered: [ReminderItem] {
        showCompleted ? reminders : reminders.filter { !$0.isCompleted }
    }

    private var grouped: [(TaskCategory, [ReminderItem])] {
        let dict = Dictionary(grouping: filtered) { $0.category }
        return TaskCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        ZStack {
            Color.vdBackground.ignoresSafeArea()

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.vdMuted)
                    Text("No reminders")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.vdInk)
                    Text("Capture a voice note with a date or time to create a reminder.")
                        .font(.subheadline)
                        .foregroundStyle(Color.vdMuted)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(grouped, id: \.0) { category, items in
                            categorySection(category: category, items: items)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCompleted.toggle()
                } label: {
                    Text(showCompleted ? "Hide done" : "Show done")
                        .font(.subheadline)
                        .foregroundStyle(Color.vdInk)
                }
            }
        }
        .alert(error: $alertError)
    }

    // MARK: - Category Section

    @ViewBuilder
    private func categorySection(category: TaskCategory, items: [ReminderItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: category.systemImageName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.vdMuted)
                Text(category.displayName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.vdMuted)
                    .kerning(0.8)
            }

            VStack(spacing: 0) {
                ForEach(items) { reminder in
                    NavigationLink(
                        value: NavigationDestination.reminderCard(id: reminder.id)
                    ) {
                        ReminderRow(reminder: reminder)
                    }
                    .buttonStyle(.plain)

                    if reminder.id != items.last?.id {
                        Divider()
                            .padding(.leading, 54)
                            .foregroundStyle(Color.vdBorder)
                    }
                }
            }
            .vdCard()
        }
    }

    // MARK: - Actions

    private func delete(_ reminder: ReminderItem) {
        notificationService.cancelReminder(identifier: reminder.notificationIdentifier)
        do {
            try persistence.deleteReminder(reminder)
        } catch {
            alertError = .persistence(error)
        }
    }
}
