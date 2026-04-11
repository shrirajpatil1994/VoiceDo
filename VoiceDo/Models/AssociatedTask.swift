import Foundation
import SwiftData
import VoiceDoShared

/// A secondary action that is attached to a reminder.
/// For example: "send a message", "buy something", "make a call".
@Model
final class AssociatedTask {

    // MARK: - Stored Properties

    var id: UUID
    /// Stored as a raw string for SwiftData compatibility; bridged to `AssociatedTaskType`.
    private var taskTypeRawValue: String
    var taskDescription: String
    var isCompleted: Bool
    var createdAt: Date

    // MARK: - Computed

    var taskType: AssociatedTaskType {
        get { AssociatedTaskType(rawValue: taskTypeRawValue) ?? .other }
        set { taskTypeRawValue = newValue.rawValue }
    }

    // MARK: - Init

    init(taskType: AssociatedTaskType, taskDescription: String) {
        self.id = UUID()
        self.taskTypeRawValue = taskType.rawValue
        self.taskDescription = taskDescription
        self.isCompleted = false
        self.createdAt = Date()
    }
}
