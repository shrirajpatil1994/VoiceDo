import Testing
import Foundation
@testable import VoiceDoShared

// MARK: - WidgetSnapshot Tests

@Suite("WidgetSnapshot Codable")
struct WidgetSnapshotTests {

    @Test("Full snapshot encodes and decodes")
    func fullRoundTrip() throws {
        let reminder = WidgetReminderPreview(
            id: UUID(),
            title: "Call Sarah",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            taskTypeRawValue: "call"
        )
        let original = WidgetSnapshot(
            incompleteTodoCount: 5,
            nextReminder: reminder,
            lastUpdated: Date(timeIntervalSince1970: 1_699_900_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        #expect(decoded == original)
        #expect(decoded.incompleteTodoCount == 5)
        #expect(decoded.nextReminder?.title == "Call Sarah")
        #expect(decoded.nextReminder?.taskTypeRawValue == "call")
    }

    @Test("Empty snapshot round-trips")
    func emptyRoundTrip() throws {
        let data = try JSONEncoder().encode(WidgetSnapshot.empty)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        #expect(decoded.incompleteTodoCount == 0)
        #expect(decoded.nextReminder == nil)
    }

    @Test("Snapshot with no reminder")
    func noReminder() throws {
        let original = WidgetSnapshot(incompleteTodoCount: 3, nextReminder: nil, lastUpdated: Date())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        #expect(decoded.nextReminder == nil)
        #expect(decoded.incompleteTodoCount == 3)
    }
}

// MARK: - AssociatedTaskType Tests

@Suite("AssociatedTaskType")
struct AssociatedTaskTypeTests {

    @Test("Raw value round-trips for all cases")
    func rawValueRoundTrips() throws {
        for type in AssociatedTaskType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(AssociatedTaskType.self, from: data)
            #expect(decoded == type, "Round-trip failed for: \(type)")
        }
    }

    @Test("Known raw values decode correctly")
    func knownRawValues() {
        #expect(AssociatedTaskType(rawValue: "message") == .message)
        #expect(AssociatedTaskType(rawValue: "purchase") == .purchase)
        #expect(AssociatedTaskType(rawValue: "deadline") == .deadline)
        #expect(AssociatedTaskType(rawValue: "call") == .call)
        #expect(AssociatedTaskType(rawValue: "other") == .other)
        #expect(AssociatedTaskType(rawValue: "unknown_value") == nil)
    }

    @Test("Display names are non-empty")
    func displayNamesNonEmpty() {
        for type in AssociatedTaskType.allCases {
            #expect(!type.displayName.isEmpty, "Empty displayName for: \(type)")
            #expect(!type.systemImageName.isEmpty, "Empty systemImageName for: \(type)")
        }
    }
}

// MARK: - ParsedIntent Tests

@Suite("ParsedIntent")
struct ParsedIntentTests {

    @Test("Todo is always ready to save")
    func todoReadyToSave() {
        let intent = ParsedIntent(type: .todo, confidence: 0.9, title: "Buy milk")
        #expect(intent.isReadyToSave)
    }

    @Test("Reminder with date is ready to save")
    func reminderWithDateReady() {
        let intent = ParsedIntent(
            type: .reminder,
            confidence: 0.85,
            title: "Call doctor",
            detectedDueDate: Date().addingTimeInterval(3600)
        )
        #expect(intent.isReadyToSave)
    }

    @Test("Reminder without date is not ready to save")
    func reminderWithoutDateNotReady() {
        let intent = ParsedIntent(type: .reminder, confidence: 0.7, title: "Call doctor")
        #expect(!intent.isReadyToSave)
    }

    @Test("Ambiguous is never ready to save")
    func ambiguousNotReady() {
        let intent = ParsedIntent(type: .ambiguous, confidence: 0.4, title: "Something")
        #expect(!intent.isReadyToSave)
    }
}

// MARK: - AppConstants Tests

@Suite("AppConstants")
struct AppConstantsTests {

    @Test("All string constants are non-empty")
    func nonEmptyStrings() {
        #expect(!AppConstants.appGroupID.isEmpty)
        #expect(!AppConstants.urlScheme.isEmpty)
        #expect(!AppConstants.keychainService.isEmpty)
        #expect(!AppConstants.keychainAccount.isEmpty)
        #expect(!AppConstants.widgetKind.isEmpty)
        #expect(!AppConstants.widgetSnapshotKey.isEmpty)
        #expect(!AppConstants.claudeModel.isEmpty)
        #expect(!AppConstants.claudeAPIEndpoint.isEmpty)
        #expect(!AppConstants.sqliteFilename.isEmpty)
        #expect(!AppConstants.logSubsystem.isEmpty)
    }

    @Test("App Group ID has correct prefix")
    func appGroupIDPrefix() {
        #expect(
            AppConstants.appGroupID.hasPrefix("group."),
            "App Group ID must start with 'group.' — got: \(AppConstants.appGroupID)"
        )
    }

    @Test("Claude endpoint uses HTTPS")
    func claudeEndpointHTTPS() {
        #expect(
            AppConstants.claudeAPIEndpoint.hasPrefix("https://"),
            "Claude API endpoint must use HTTPS — got: \(AppConstants.claudeAPIEndpoint)"
        )
    }

    @Test("Numeric constants are in valid ranges")
    func numericRanges() {
        #expect(AppConstants.claudeTimeoutSeconds > 0)
        #expect(AppConstants.offlineConfidenceThreshold > 0)
        #expect(AppConstants.offlineConfidenceThreshold <= 1.0)
        #expect(AppConstants.maxRecordingSeconds > 0)
    }
}

// MARK: - MessageDraft platformDisplayName Logic Test

@Suite("MessageDraft platform display names")
struct MessageDraftPlatformTests {

    // Tests the display name mapping logic independently of SwiftData.
    // (SwiftData @Model classes cannot be instantiated without a model container.)
    @Test("Platform hints map to correct display names", arguments: [
        ("email", "Email"),
        ("EMAIL", "Email"),
        ("whatsapp", "WhatsApp"),
        ("slack", "Slack"),
        ("sms", "SMS"),
        ("text", "SMS"),
        ("imessage", "iMessage"),
        ("imsg", "iMessage"),
        ("telegram", "Message")
    ])
    func platformDisplayNames(hint: String, expected: String) {
        #expect(platformDisplayName(for: hint) == expected)
    }

    @Test("nil platform hint returns generic label")
    func nilHintReturnsGeneric() {
        #expect(platformDisplayName(for: nil) == "Message")
    }

    // Mirrors MessageDraft.platformDisplayName for independent testing.
    private func platformDisplayName(for hint: String?) -> String {
        switch hint?.lowercased() {
        case "email": return "Email"
        case "whatsapp": return "WhatsApp"
        case "slack": return "Slack"
        case "sms", "text": return "SMS"
        case "imessage", "imsg": return "iMessage"
        default: return "Message"
        }
    }
}
