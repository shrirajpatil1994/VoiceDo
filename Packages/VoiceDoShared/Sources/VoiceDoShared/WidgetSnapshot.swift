import Foundation

// MARK: - WidgetSnapshot

/// Lightweight, Codable snapshot of app state for the widget extension.
/// Written to App Group UserDefaults by the main app after every data change.
/// Read by the widget extension's TimelineProvider — never opens SwiftData directly.
public struct WidgetSnapshot: Codable, Sendable, Equatable {

    public var incompleteTodoCount: Int
    public var nextReminder: WidgetReminderPreview?
    public var lastUpdated: Date

    public init(
        incompleteTodoCount: Int = 0,
        nextReminder: WidgetReminderPreview? = nil,
        lastUpdated: Date = Date()
    ) {
        self.incompleteTodoCount = incompleteTodoCount
        self.nextReminder = nextReminder
        self.lastUpdated = lastUpdated
    }

    /// An empty snapshot for first-launch / missing data scenarios.
    public static let empty = WidgetSnapshot(
        incompleteTodoCount: 0,
        nextReminder: nil,
        lastUpdated: .distantPast
    )
}

// MARK: - WidgetReminderPreview

/// A minimal preview of a reminder for widget display.
/// Contains only what is needed for the widget — no sensitive details.
public struct WidgetReminderPreview: Codable, Sendable, Equatable {

    public var id: UUID
    public var title: String
    public var dueDate: Date
    /// Raw value of `AssociatedTaskType` — the widget doesn't import SwiftData models.
    public var taskTypeRawValue: String?

    public init(
        id: UUID,
        title: String,
        dueDate: Date,
        taskTypeRawValue: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.taskTypeRawValue = taskTypeRawValue
    }
}
