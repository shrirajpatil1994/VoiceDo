import Foundation
import os.log
import VoiceDoShared
import WidgetKit

// MARK: - WidgetReloadService

/// Writes the `WidgetSnapshot` to the App Group UserDefaults and triggers
/// a WidgetKit timeline reload. Call after every data mutation.
final class WidgetReloadService: Sendable {

    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "WidgetReload")

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupID)
    }

    // MARK: - Update

    /// Build and write a new snapshot, then reload all widget timelines.
    func update(todos: [TodoItem], reminders: [ReminderItem]) {
        let snapshot = buildSnapshot(todos: todos, reminders: reminders)
        write(snapshot: snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.widgetKind)
        let nextTitle = snapshot.nextReminder?.title ?? "none"
        logger.info("Widget snapshot updated: \(snapshot.incompleteTodoCount) todos, nextReminder=\(nextTitle)")
    }

    // MARK: - Private

    private func buildSnapshot(todos: [TodoItem], reminders: [ReminderItem]) -> WidgetSnapshot {
        let incompleteTodos = todos.filter { !$0.isCompleted }
        let upcoming = reminders
            .filter { !$0.isCompleted && $0.dueDate >= Date() }
            .sorted { $0.dueDate < $1.dueDate }
            .first

        let preview: WidgetReminderPreview? = upcoming.map { reminder in
            WidgetReminderPreview(
                id: reminder.id,
                title: reminder.title,
                dueDate: reminder.dueDate,
                taskTypeRawValue: reminder.associatedTask?.taskType.rawValue
            )
        }

        return WidgetSnapshot(
            incompleteTodoCount: incompleteTodos.count,
            nextReminder: preview,
            lastUpdated: Date()
        )
    }

    private func write(snapshot: WidgetSnapshot) {
        guard let defaults else {
            logger.error("Could not access App Group UserDefaults (\(AppConstants.appGroupID))")
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            logger.error("Failed to encode WidgetSnapshot")
            return
        }
        defaults.set(data, forKey: AppConstants.widgetSnapshotKey)
    }
}

// AppGroupDataReader lives in VoiceDoShared so both app + widget targets can use it.
