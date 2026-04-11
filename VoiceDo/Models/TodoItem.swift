import Foundation
import SwiftData
import VoiceDoShared

/// A single to-do item created from voice dictation or manually.
@Model
final class TodoItem {

    var id: UUID
    var title: String
    var notes: String?
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var category: TaskCategory = TaskCategory.task
    var workspace: Workspace = Workspace.personal
    var sourceTranscript: String
    var wasAIRefined: Bool

    @Relationship(deleteRule: .nullify)
    var reminder: ReminderItem?

    init(
        title: String,
        notes: String? = nil,
        category: TaskCategory = .task,
        workspace: Workspace = .personal,
        sourceTranscript: String,
        wasAIRefined: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.category = category
        self.workspace = workspace
        self.isCompleted = false
        self.createdAt = Date()
        self.completedAt = nil
        self.sourceTranscript = sourceTranscript
        self.wasAIRefined = wasAIRefined
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
