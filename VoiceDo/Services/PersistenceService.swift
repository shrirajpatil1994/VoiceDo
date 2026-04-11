import Foundation
import os.log
import SwiftData
import VoiceDoShared

// MARK: - PersistenceService

/// Factory and CRUD interface for the SwiftData model container.
/// The container is stored in the App Group directory so the widget can read it.
@MainActor
final class PersistenceService {

    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "Persistence")
    let container: ModelContainer

    // MARK: - Init

    init(inMemory: Bool = false) throws {
        let schema = Schema([
            TodoItem.self,
            ReminderItem.self,
            AssociatedTask.self,
            MessageDraft.self
        ])

        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            guard let groupURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) else {
                throw PersistenceError.appGroupUnavailable
            }
            let storeURL = groupURL.appendingPathComponent(AppConstants.sqliteFilename)
            config = ModelConfiguration(schema: schema, url: storeURL)
            logger.info("SwiftData store: \(storeURL.path)")
        }

        container = try ModelContainer(for: schema, configurations: [config])
        logger.info("SwiftData container initialized (inMemory: \(inMemory))")
    }

    // MARK: - Context

    var context: ModelContext { container.mainContext }

    // MARK: - Todo CRUD

    func saveTodo(_ todo: TodoItem) throws {
        context.insert(todo)
        try context.save()
        logger.info("Saved TodoItem: \(todo.id)")
    }

    func fetchIncompleteTodos() throws -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchAllTodos() throws -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func deleteTodo(_ todo: TodoItem) throws {
        context.delete(todo)
        try context.save()
    }

    // MARK: - Reminder CRUD

    func saveReminder(_ reminder: ReminderItem) throws {
        // Explicitly insert relationship objects — SwiftData may not auto-insert
        // models set on a parent before context.insert() is called.
        if let task = reminder.associatedTask {
            context.insert(task)
        }
        if let draft = reminder.messageDraft {
            context.insert(draft)
        }
        context.insert(reminder)
        try context.save()
        logger.info("Saved ReminderItem: \(reminder.id)")
    }

    func fetchUpcomingReminders() throws -> [ReminderItem] {
        let now = Date()
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { !$0.isCompleted && $0.dueDate >= now },
            sortBy: [SortDescriptor(\.dueDate)]
        )
        return try context.fetch(descriptor)
    }

    func fetchAllReminders() throws -> [ReminderItem] {
        let descriptor = FetchDescriptor<ReminderItem>(
            sortBy: [SortDescriptor(\.dueDate)]
        )
        return try context.fetch(descriptor)
    }

    func fetchReminder(by id: UUID) throws -> ReminderItem? {
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func deleteReminder(_ reminder: ReminderItem) throws {
        context.delete(reminder)
        try context.save()
    }

    // MARK: - Mark Complete

    func markTodoComplete(_ todo: TodoItem) throws {
        todo.markCompleted()
        try context.save()
    }

    func markReminderComplete(_ reminder: ReminderItem) throws {
        reminder.markCompleted()
        try context.save()
    }
}

// MARK: - PersistenceError

enum PersistenceError: Error, LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Could not access the App Group container. Check entitlements."
        }
    }
}
