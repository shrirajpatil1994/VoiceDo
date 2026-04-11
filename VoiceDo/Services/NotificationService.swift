import Foundation
import os.log
import UIKit
@preconcurrency import UserNotifications
import VoiceDoShared

// MARK: - NotificationService

/// Schedules and manages `UNUserNotificationCenter` requests for reminders.
/// Call `registerCategories()` once at app launch.
final class NotificationService: NSObject, Sendable {

    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "Notifications")
    private let center = UNUserNotificationCenter.current()

    // MARK: - Notification Category / Action IDs

    enum CategoryID {
        static let reminder = "VOICEDO_REMINDER"
    }

    enum ActionID {
        static let markDone = "VOICEDO_MARK_DONE"
        static let open = "VOICEDO_OPEN"
    }

    enum UserInfoKey {
        static let reminderId = "reminderId"
        static let deepLink = "deepLink"
    }

    // MARK: - Setup

    /// Register notification categories and actions.
    /// Call once from `VoiceDoApp.init()` or `AppDelegate.didFinishLaunching`.
    func registerCategories() {
        let markDoneAction = UNNotificationAction(
            identifier: ActionID.markDone,
            title: "Mark Done",
            options: []
        )
        let openAction = UNNotificationAction(
            identifier: ActionID.open,
            title: "Open",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: CategoryID.reminder,
            actions: [markDoneAction, openAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
        center.delegate = self
        logger.info("Notification categories registered")
    }

    // MARK: - Permission

    func requestPermission() async throws -> Bool {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { return true }

        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        logger.info("Notification permission: \(granted)")
        return granted
    }

    // MARK: - Schedule

    func scheduleReminder(_ reminder: ReminderItem) async throws {
        guard reminder.dueDate > Date() else {
            logger.warning("Skipping notification for past-due reminder: \(reminder.id)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.categoryIdentifier = CategoryID.reminder
        content.sound = .default

        // Subtitle: show associated task type if present
        if let task = reminder.associatedTask {
            content.subtitle = task.taskType.displayName
        }

        // Body: notes + message draft preview (if present)
        var bodyParts: [String] = []
        if let notes = reminder.notes, !notes.isEmpty {
            bodyParts.append(notes)
        }
        if let draft = reminder.messageDraft, !draft.body.isEmpty {
            let preview = draft.body.prefix(120)
            bodyParts.append("Draft: \(preview)")
        }
        content.body = bodyParts.isEmpty ? "Tap to view details." : bodyParts.joined(separator: "\n")
        content.badge = 1

        // Deep-link payload
        let deepLink = "\(AppConstants.urlScheme)://reminder/\(reminder.id.uuidString)"
        content.userInfo = [
            UserInfoKey.reminderId: reminder.id.uuidString,
            UserInfoKey.deepLink: deepLink
        ]

        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerComponents,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: reminder.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
        logger.info("Scheduled notification \(reminder.notificationIdentifier) for \(reminder.dueDate)")
    }

    // MARK: - Cancel

    func cancelReminder(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        logger.info("Cancelled notification: \(identifier)")
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        logger.info("All notifications cancelled")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Show notifications even when app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle notification action responses.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case ActionID.markDone:
            if let idString = userInfo[UserInfoKey.reminderId] as? String,
               let reminderId = UUID(uuidString: idString) {
                // Post notification for the app to handle — avoids coupling to PersistenceService
                NotificationCenter.default.post(
                    name: .reminderMarkedDoneFromNotification,
                    object: nil,
                    userInfo: ["reminderId": reminderId]
                )
            }

        case ActionID.open, UNNotificationDefaultActionIdentifier:
            if let deepLink = userInfo[UserInfoKey.deepLink] as? String,
               let url = URL(string: deepLink) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }

        default:
            break
        }

        completionHandler()
    }
}

// MARK: - Notification.Name Extension

extension Notification.Name {
    static let reminderMarkedDoneFromNotification = Notification.Name(
        "com.voicedo.reminderMarkedDoneFromNotification"
    )
}
