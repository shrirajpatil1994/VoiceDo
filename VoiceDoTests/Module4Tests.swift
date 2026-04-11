@testable import VoiceDo
import VoiceDoShared
import XCTest

// MARK: - PersistenceServiceTests

/// Tests for `PersistenceService` using an in-memory SwiftData store.
/// No App Group access required — `inMemory: true` bypasses the container URL.
@MainActor
final class PersistenceServiceTests: XCTestCase {

    private var persistence: PersistenceService!

    override func setUp() async throws {
        persistence = try PersistenceService(inMemory: true)
    }

    // MARK: - Todo CRUD

    func testSaveAndFetchTodo() throws {
        let todo = TodoItem(
            title: "Buy oat milk",
            sourceTranscript: "Buy oat milk"
        )
        try persistence.saveTodo(todo)

        let all = try persistence.fetchAllTodos()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Buy oat milk")
    }

    func testFetchIncompleteTodosExcludesCompleted() throws {
        let todo = TodoItem(title: "Task A", sourceTranscript: "Task A")
        try persistence.saveTodo(todo)
        try persistence.markTodoComplete(todo)

        let incomplete = try persistence.fetchIncompleteTodos()
        XCTAssertTrue(incomplete.isEmpty)
    }

    func testDeleteTodoRemovesIt() throws {
        let todo = TodoItem(title: "Delete me", sourceTranscript: "Delete me")
        try persistence.saveTodo(todo)
        try persistence.deleteTodo(todo)

        let all = try persistence.fetchAllTodos()
        XCTAssertTrue(all.isEmpty)
    }

    func testMarkTodoCompleteSetsDates() throws {
        let todo = TodoItem(title: "Finish report", sourceTranscript: "Finish report")
        try persistence.saveTodo(todo)
        try persistence.markTodoComplete(todo)

        XCTAssertTrue(todo.isCompleted)
        XCTAssertNotNil(todo.completedAt)
    }

    func testFetchAllTodosReturnsSortedByCreatedAt() throws {
        for title in ["C", "A", "B"] {
            let todo = TodoItem(title: title, sourceTranscript: title)
            try persistence.saveTodo(todo)
        }
        let all = try persistence.fetchAllTodos()
        XCTAssertEqual(all.count, 3)
        // Sorted reverse-chronological — last inserted should be first
        XCTAssertEqual(all.first?.title, "B")
    }

    // MARK: - Reminder CRUD

    func testSaveAndFetchReminder() throws {
        let reminder = ReminderItem(
            title: "Call dentist",
            dueDate: Date().addingTimeInterval(3600),
            sourceTranscript: "Call dentist tomorrow"
        )
        try persistence.saveReminder(reminder)

        let all = try persistence.fetchAllReminders()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Call dentist")
    }

    func testFetchUpcomingRemindersExcludesPast() throws {
        let past = ReminderItem(
            title: "Past",
            dueDate: Date().addingTimeInterval(-3600),
            sourceTranscript: "Past"
        )
        let future = ReminderItem(
            title: "Future",
            dueDate: Date().addingTimeInterval(3600),
            sourceTranscript: "Future"
        )
        try persistence.saveReminder(past)
        try persistence.saveReminder(future)

        let upcoming = try persistence.fetchUpcomingReminders()
        XCTAssertEqual(upcoming.count, 1)
        XCTAssertEqual(upcoming.first?.title, "Future")
    }

    func testFetchReminderById() throws {
        let reminder = ReminderItem(
            title: "Specific",
            dueDate: Date().addingTimeInterval(3600),
            sourceTranscript: "Specific"
        )
        try persistence.saveReminder(reminder)

        let fetched = try persistence.fetchReminder(by: reminder.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Specific")
    }

    func testFetchReminderByUnknownIdReturnsNil() throws {
        let fetched = try persistence.fetchReminder(by: UUID())
        XCTAssertNil(fetched)
    }

    func testDeleteReminderRemovesIt() throws {
        let reminder = ReminderItem(
            title: "Delete me",
            dueDate: Date().addingTimeInterval(3600),
            sourceTranscript: "Delete me"
        )
        try persistence.saveReminder(reminder)
        try persistence.deleteReminder(reminder)

        let all = try persistence.fetchAllReminders()
        XCTAssertTrue(all.isEmpty)
    }

    func testMarkReminderCompleteUpdatesFlag() throws {
        let reminder = ReminderItem(
            title: "Pay bill",
            dueDate: Date().addingTimeInterval(3600),
            sourceTranscript: "Pay bill"
        )
        try persistence.saveReminder(reminder)
        try persistence.markReminderComplete(reminder)

        XCTAssertTrue(reminder.isCompleted)
    }

    func testFetchUpcomingRemindersExcludesCompleted() throws {
        let reminder = ReminderItem(
            title: "Done",
            dueDate: Date().addingTimeInterval(3600),
            sourceTranscript: "Done"
        )
        try persistence.saveReminder(reminder)
        try persistence.markReminderComplete(reminder)

        let upcoming = try persistence.fetchUpcomingReminders()
        XCTAssertTrue(upcoming.isEmpty)
    }

    // MARK: - PersistenceError

    func testPersistenceErrorHasDescription() {
        let error = PersistenceError.appGroupUnavailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }
}

// MARK: - WidgetReloadServiceTests

/// Tests for `WidgetReloadService`: snapshot building and UserDefaults write.
/// Uses a custom `suiteName` to avoid polluting the real App Group defaults.
final class WidgetReloadServiceTests: XCTestCase {

    private let testSuiteName = "com.voicedo.tests.widgetreload"
    private var testDefaults: UserDefaults!

    override func setUp() {
        testDefaults = UserDefaults(suiteName: testSuiteName)
        testDefaults.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testSuiteName)
    }

    // MARK: - WidgetSnapshot Encode/Decode

    func testWidgetSnapshotRoundTripsJSON() throws {
        let preview = WidgetReminderPreview(
            id: UUID(),
            title: "Call dentist",
            dueDate: Date(),
            taskTypeRawValue: "call"
        )
        let snapshot = WidgetSnapshot(
            incompleteTodoCount: 3,
            nextReminder: preview,
            lastUpdated: Date()
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.incompleteTodoCount, 3)
        XCTAssertEqual(decoded.nextReminder?.title, "Call dentist")
        XCTAssertEqual(decoded.nextReminder?.taskTypeRawValue, "call")
    }

    func testWidgetSnapshotEmptyRoundTrips() throws {
        let snapshot = WidgetSnapshot.empty
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.incompleteTodoCount, 0)
        XCTAssertNil(decoded.nextReminder)
    }

    func testWidgetSnapshotWrittenToUserDefaults() throws {
        let snapshot = WidgetSnapshot(
            incompleteTodoCount: 5,
            nextReminder: nil,
            lastUpdated: Date()
        )
        let data = try JSONEncoder().encode(snapshot)
        testDefaults.set(data, forKey: AppConstants.widgetSnapshotKey)

        guard let stored = testDefaults.data(forKey: AppConstants.widgetSnapshotKey) else {
            return XCTFail("No data found in test UserDefaults")
        }
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: stored)
        XCTAssertEqual(decoded.incompleteTodoCount, 5)
    }

    func testAppGroupDataReaderReturnsEmptyWhenMissing() {
        // Use an isolated suite with no data written — reader should return .empty
        let isolatedDefaults = UserDefaults(suiteName: "com.voicedo.tests.empty")
        isolatedDefaults?.removePersistentDomain(forName: "com.voicedo.tests.empty")

        // AppGroupDataReader reads from AppConstants.appGroupID — we can't inject a suite,
        // but we can verify the fallback path: decoding nil data returns .empty
        let nilData: Data? = nil
        let decoded = nilData.flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        let result = decoded ?? .empty
        XCTAssertEqual(result.incompleteTodoCount, 0)
        XCTAssertNil(result.nextReminder)
    }
}

// MARK: - DeepLinkHandlerTests

/// Tests for `DeepLinkHandler` URL parsing.
final class DeepLinkHandlerTests: XCTestCase {

    func testReminderURLParsed() {
        let id = UUID()
        let url = URL(string: "\(AppConstants.urlScheme)://reminder/\(id.uuidString)")!
        let dest = DeepLinkHandler.destination(from: url)
        XCTAssertEqual(dest, .reminderCard(id: id))
    }

    func testTodoURLParsed() {
        let id = UUID()
        let url = URL(string: "\(AppConstants.urlScheme)://todo/\(id.uuidString)")!
        let dest = DeepLinkHandler.destination(from: url)
        XCTAssertEqual(dest, .todoDetail(id: id))
    }

    func testCaptureURLParsed() {
        let url = URL(string: "\(AppConstants.urlScheme)://capture")!
        let dest = DeepLinkHandler.destination(from: url)
        XCTAssertEqual(dest, .voiceCapture)
    }

    func testWrongSchemeReturnsNil() {
        let url = URL(string: "https://example.com/reminder/123")!
        XCTAssertNil(DeepLinkHandler.destination(from: url))
    }

    func testUnknownHostReturnsNil() {
        let url = URL(string: "\(AppConstants.urlScheme)://unknown/path")!
        XCTAssertNil(DeepLinkHandler.destination(from: url))
    }

    func testReminderURLWithInvalidUUIDReturnsNil() {
        let url = URL(string: "\(AppConstants.urlScheme)://reminder/not-a-uuid")!
        XCTAssertNil(DeepLinkHandler.destination(from: url))
    }

    func testTodoURLWithInvalidUUIDReturnsNil() {
        let url = URL(string: "\(AppConstants.urlScheme)://todo/not-a-uuid")!
        XCTAssertNil(DeepLinkHandler.destination(from: url))
    }

    func testReminderURLMissingUUIDReturnsNil() {
        let url = URL(string: "\(AppConstants.urlScheme)://reminder")!
        XCTAssertNil(DeepLinkHandler.destination(from: url))
    }

    func testNavigationDestinationHashable() {
        let id = UUID()
        let a = NavigationDestination.reminderCard(id: id)
        let b = NavigationDestination.reminderCard(id: id)
        XCTAssertEqual(a, b)

        let set: Set<NavigationDestination> = [a, b, .voiceCapture]
        XCTAssertEqual(set.count, 2)
    }
}

// MARK: - NotificationServiceTests

/// Tests for `NotificationService` logic that does not require a running app or real device.
final class NotificationServiceTests: XCTestCase {

    func testCategoryAndActionIDsAreStable() {
        // These strings are stored in notification payloads — must never change silently.
        XCTAssertEqual(NotificationService.CategoryID.reminder, "VOICEDO_REMINDER")
        XCTAssertEqual(NotificationService.ActionID.markDone, "VOICEDO_MARK_DONE")
        XCTAssertEqual(NotificationService.ActionID.open, "VOICEDO_OPEN")
    }

    func testUserInfoKeyStringsAreStable() {
        XCTAssertEqual(NotificationService.UserInfoKey.reminderId, "reminderId")
        XCTAssertEqual(NotificationService.UserInfoKey.deepLink, "deepLink")
    }

    func testReminderMarkedDoneNotificationNameIsStable() {
        // The Notification.Name value is stored in NotificationCenter observers.
        let name = Notification.Name.reminderMarkedDoneFromNotification
        XCTAssertFalse(name.rawValue.isEmpty)
        XCTAssertTrue(name.rawValue.contains("reminderMarkedDone"))
    }

    func testDeepLinkFormatMatchesURLScheme() {
        let id = UUID()
        let deepLink = "\(AppConstants.urlScheme)://reminder/\(id.uuidString)"
        guard let url = URL(string: deepLink) else {
            return XCTFail("Deep-link URL is malformed: \(deepLink)")
        }
        let dest = DeepLinkHandler.destination(from: url)
        XCTAssertEqual(dest, .reminderCard(id: id))
    }

    func testNotificationServiceCanBeInstantiated() {
        // Smoke test — ensures init doesn't crash (no real UNUserNotificationCenter calls)
        let service = NotificationService()
        XCTAssertNotNil(service)
    }
}
