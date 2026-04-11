import Foundation
import SwiftData
import VoiceDoShared

/// A time-based reminder created from voice dictation.
@Model
final class ReminderItem {

    var id: UUID
    var title: String
    var notes: String?
    var dueDate: Date
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var category: TaskCategory = TaskCategory.task
    var workspace: Workspace = Workspace.personal
    var notificationIdentifier: String
    var sourceTranscript: String
    var wasAIRefined: Bool

    @Relationship(deleteRule: .cascade)
    var associatedTask: AssociatedTask?

    @Relationship(deleteRule: .cascade)
    var messageDraft: MessageDraft?

    init(
        title: String,
        dueDate: Date,
        sourceTranscript: String,
        notes: String? = nil,
        category: TaskCategory = .task,
        workspace: Workspace = .personal,
        wasAIRefined: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.dueDate = dueDate
        self.sourceTranscript = sourceTranscript
        self.notes = notes
        self.category = category
        self.workspace = workspace
        self.isCompleted = false
        self.createdAt = Date()
        self.completedAt = nil
        self.notificationIdentifier = UUID().uuidString
        self.wasAIRefined = wasAIRefined
    }

    var isOverdue: Bool {
        !isCompleted && dueDate < Date()
    }

    func markCompleted() {
        isCompleted = true
        completedAt = Date()
    }

    func markIncomplete() {
        isCompleted = false
        completedAt = nil
    }
}
