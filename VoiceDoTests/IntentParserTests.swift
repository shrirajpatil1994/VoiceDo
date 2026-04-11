@testable import VoiceDo
import VoiceDoShared
import XCTest

/// Module 3 — OfflineIntentParser tests.
/// Requires 40+ transcript cases covering all intent types, task types, edge cases.
final class IntentParserTests: XCTestCase {

    private let parser = OfflineIntentParser()

    // MARK: - Todo: No Keywords

    func testSimpleTodo() {
        let intent = parser.parse(transcript: "Buy milk and eggs")
        XCTAssertEqual(intent.type, .todo)
        XCTAssertEqual(intent.detectedTaskType, .purchase)
        XCTAssertFalse(intent.title.isEmpty)
    }

    func testTodoWithNoKeywords() {
        let intent = parser.parse(transcript: "Finish the quarterly report")
        XCTAssertEqual(intent.type, .todo)
        XCTAssertNil(intent.detectedTaskType)
        XCTAssertFalse(intent.title.isEmpty)
    }

    func testTodoReadBook() {
        let intent = parser.parse(transcript: "Read the new design book")
        XCTAssertEqual(intent.type, .todo)
        XCTAssertNil(intent.detectedDueDate)
    }

    func testTodoOrganizeDesk() {
        let intent = parser.parse(transcript: "Organise my desk and sort the cables")
        XCTAssertEqual(intent.type, .todo)
        XCTAssertNil(intent.detectedTaskType)
    }

    func testTodoUpdateCV() {
        let intent = parser.parse(transcript: "Update my CV with the new projects")
        XCTAssertEqual(intent.type, .todo)
        XCTAssertNil(intent.detectedDueDate)
    }

    // MARK: - Filler Prefix Stripping

    func testTodoFillersStrippedDontForget() {
        let intent = parser.parse(transcript: "Don't forget to pick up dry cleaning")
        XCTAssertFalse(intent.title.lowercased().hasPrefix("don't forget"))
    }

    func testTodoFillersStrippedRemindMe() {
        let intent = parser.parse(transcript: "Remind me to send the invoice")
        XCTAssertFalse(intent.title.lowercased().hasPrefix("remind me"))
    }

    func testTodoFillersStrippedINeedTo() {
        let intent = parser.parse(transcript: "I need to review the pull request")
        XCTAssertFalse(intent.title.lowercased().hasPrefix("i need to"))
        XCTAssertFalse(intent.title.isEmpty)
    }

    func testTodoFillersStrippedPleaseCapitalized() {
        let intent = parser.parse(transcript: "Please call back the agency")
        XCTAssertFalse(intent.title.lowercased().hasPrefix("please"))
    }

    func testTodoFillersStrippedMakeSureTo() {
        let intent = parser.parse(transcript: "Make sure to back up the laptop")
        XCTAssertFalse(intent.title.lowercased().hasPrefix("make sure"))
    }

    // MARK: - Reminder: Date Detection

    func testReminderWithTomorrow() {
        let intent = parser.parse(transcript: "Remind me to call the dentist tomorrow")
        XCTAssertEqual(intent.type, .reminder)
        XCTAssertNotNil(intent.detectedDueDate)
        guard let dueDate = intent.detectedDueDate else { return }
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else {
            XCTFail("Could not compute tomorrow's date")
            return
        }
        XCTAssertTrue(Calendar.current.isDate(dueDate, inSameDayAs: tomorrow))
    }

    func testReminderWithInHours() {
        let intent = parser.parse(transcript: "Remind me in 3 hours to check the oven")
        XCTAssertEqual(intent.type, .reminder)
        XCTAssertNotNil(intent.detectedDueDate)
        guard let dueDate = intent.detectedDueDate else { return }
        // Rounded to nearest 30 min, so allow up to 30 min deviation from exact 3h
        let diff = abs(dueDate.timeIntervalSince(Date().addingTimeInterval(3 * 3600)))
        XCTAssertLessThan(diff, 30 * 60, "Date should be within 30 min of 3 hours from now")
    }

    func testReminderInTwoDays() {
        let intent = parser.parse(transcript: "Follow up with client in 2 days")
        XCTAssertEqual(intent.type, .reminder)
        XCTAssertNotNil(intent.detectedDueDate)
    }

    func testReminderEndOfWeek() {
        let intent = parser.parse(transcript: "Submit the proposal by end of week")
        XCTAssertEqual(intent.type, .reminder)
        XCTAssertNotNil(intent.detectedDueDate)
    }

    func testReminderNextWeek() {
        let intent = parser.parse(transcript: "Schedule performance review for next week")
        XCTAssertEqual(intent.type, .reminder)
        XCTAssertNotNil(intent.detectedDueDate)
    }

    func testReminderTonight() {
        let intent = parser.parse(transcript: "Remember to take medication tonight")
        XCTAssertEqual(intent.type, .reminder)
        XCTAssertNotNil(intent.detectedDueDate)
        guard let dueDate = intent.detectedDueDate else { return }
        let hour = Calendar.current.component(.hour, from: dueDate)
        // "Tonight" maps to 8pm (20:00) — accept 19 or 20 to be robust across locales
        XCTAssertTrue(hour >= 19 && hour <= 20, "Expected evening hour, got \(hour)")
    }

    func testReminderThisMorning() {
        let intent = parser.parse(transcript: "Send the brief this morning")
        XCTAssertEqual(intent.type, .reminder)
        XCTAssertNotNil(intent.detectedDueDate)
    }

    func testReminderSignalWordWithoutDate() {
        let intent = parser.parse(transcript: "Remind me to send the invoice")
        XCTAssertEqual(intent.type, .reminder)
        XCTAssertNil(intent.detectedDueDate)
        XCTAssertFalse(intent.isReadyToSave)
    }

    func testReminderDontForgetSignal() {
        let intent = parser.parse(transcript: "Don't forget the dentist appointment")
        XCTAssertEqual(intent.type, .reminder)
    }

    func testReminderIsReadyToSaveWithDate() {
        let intent = parser.parse(transcript: "Call bank tomorrow")
        XCTAssertTrue(intent.isReadyToSave)
    }

    func testTodoIsAlwaysReadyToSave() {
        let intent = parser.parse(transcript: "Tidy the garage")
        XCTAssertTrue(intent.isReadyToSave)
    }

    // MARK: - Task Type: Message

    func testEmailTask() {
        let intent = parser.parse(transcript: "Email my landlord about the heating issue")
        XCTAssertEqual(intent.detectedTaskType, .message)
        XCTAssertEqual(intent.platformHint, "email")
    }

    func testWhatsAppTask() {
        let intent = parser.parse(transcript: "WhatsApp Sarah about the meeting tomorrow")
        XCTAssertEqual(intent.detectedTaskType, .message)
        XCTAssertEqual(intent.platformHint, "whatsapp")
        XCTAssertEqual(intent.type, .reminder)
    }

    func testSlackTask() {
        let intent = parser.parse(transcript: "Slack the design team about the new mockups")
        XCTAssertEqual(intent.detectedTaskType, .message)
        XCTAssertEqual(intent.platformHint, "slack")
    }

    func testDraftMessage() {
        let intent = parser.parse(transcript: "Draft a message to the supplier about delays")
        XCTAssertEqual(intent.detectedTaskType, .message)
    }

    func testWriteToContact() {
        let intent = parser.parse(transcript: "Write to the HR team about my leave request")
        XCTAssertEqual(intent.detectedTaskType, .message)
    }

    // MARK: - Task Type: Purchase

    func testPurchaseTask() {
        let intent = parser.parse(transcript: "Order birthday cake for Friday")
        XCTAssertEqual(intent.detectedTaskType, .purchase)
        XCTAssertEqual(intent.type, .reminder)
    }

    func testBuyGroceries() {
        let intent = parser.parse(transcript: "Buy groceries on the way home")
        XCTAssertEqual(intent.detectedTaskType, .purchase)
    }

    func testPickUpDryCleaning() {
        let intent = parser.parse(transcript: "Pick up dry cleaning before 6pm")
        XCTAssertEqual(intent.detectedTaskType, .purchase)
    }

    func testGrabCoffee() {
        let intent = parser.parse(transcript: "Grab coffee beans from the shop")
        XCTAssertEqual(intent.detectedTaskType, .purchase)
    }

    // MARK: - Task Type: Call

    func testCallTask() {
        let intent = parser.parse(transcript: "Call the insurance company before noon tomorrow")
        XCTAssertEqual(intent.detectedTaskType, .call)
        XCTAssertEqual(intent.type, .reminder)
    }

    func testPhoneDoctor() {
        let intent = parser.parse(transcript: "Phone the doctor to book an appointment")
        XCTAssertEqual(intent.detectedTaskType, .call)
    }

    func testRingOffice() {
        let intent = parser.parse(transcript: "Ring the office to confirm the meeting")
        XCTAssertEqual(intent.detectedTaskType, .call)
    }

    // MARK: - Task Type: Deadline

    func testDeadlineTask() {
        let intent = parser.parse(transcript: "Submit tax return deadline April 15th")
        XCTAssertEqual(intent.detectedTaskType, .deadline)
        XCTAssertEqual(intent.type, .reminder)
    }

    func testDueByDate() {
        let intent = parser.parse(transcript: "Report due by Friday end of day")
        XCTAssertEqual(intent.detectedTaskType, .deadline)
    }

    func testHandInAssignment() {
        let intent = parser.parse(transcript: "Hand in the project proposal tomorrow")
        XCTAssertEqual(intent.detectedTaskType, .deadline)
    }

    // MARK: - Recipient Hint Extraction

    func testRecipientHintEmail() {
        let intent = parser.parse(transcript: "Email John about the project status")
        XCTAssertNotNil(intent.recipientHint)
        XCTAssertTrue(intent.recipientHint?.lowercased().contains("john") == true)
    }

    func testRecipientHintMyLandlord() {
        let intent = parser.parse(transcript: "Email my landlord about the broken heating")
        XCTAssertNotNil(intent.recipientHint)
    }

    func testRecipientHintCallSarah() {
        let intent = parser.parse(transcript: "Call Sarah at 3pm tomorrow")
        XCTAssertNotNil(intent.recipientHint)
        XCTAssertTrue(intent.recipientHint?.lowercased().contains("sarah") == true)
    }

    // MARK: - Platform Hint Detection

    func testPlatformHintEmail() {
        let intent = parser.parse(transcript: "Email the team the agenda")
        XCTAssertEqual(intent.platformHint, "email")
    }

    func testPlatformHintWhatsApp() {
        let intent = parser.parse(transcript: "Send a WhatsApp to Mum")
        XCTAssertEqual(intent.platformHint, "whatsapp")
    }

    func testPlatformHintSlack() {
        let intent = parser.parse(transcript: "Slack James the onboarding doc")
        XCTAssertEqual(intent.platformHint, "slack")
    }

    // MARK: - Confidence Scores

    func testHighConfidenceReminderWithDate() {
        let intent = parser.parse(transcript: "Call Sarah tomorrow at 3pm")
        XCTAssertGreaterThan(intent.confidence, 0.7)
    }

    func testLowerConfidenceForAmbiguous() {
        let intent = parser.parse(transcript: "Something")
        XCTAssertLessThan(intent.confidence, AppConstants.offlineConfidenceThreshold)
    }

    func testConfidenceBoostFromTaskType() {
        let withTask = parser.parse(transcript: "Email the team about the update")
        let withoutTask = parser.parse(transcript: "Think about the update")
        XCTAssertGreaterThan(withTask.confidence, withoutTask.confidence)
    }

    func testConfidenceBelowOnePointZero() {
        let intent = parser.parse(transcript: "Email Sarah about the contract due by Friday at 5pm")
        XCTAssertLessThanOrEqual(intent.confidence, 1.0)
    }

    // MARK: - Title Quality

    func testTitleIsCapitalized() {
        let intent = parser.parse(transcript: "buy more coffee")
        XCTAssertEqual(intent.title.first?.isUppercase, true)
    }

    func testTitleNotEmpty() {
        let intent = parser.parse(transcript: "Do something useful today")
        XCTAssertFalse(intent.title.isEmpty)
    }

    func testTitleDoesNotStartWithFillerPrefix() {
        let intent = parser.parse(transcript: "Remember to water the plants")
        XCTAssertFalse(intent.title.lowercased().hasPrefix("remember to"))
    }

    // MARK: - Edge Cases

    func testEmptyTranscriptThrows() async throws {
        let service = IntentParserService()
        do {
            _ = try await service.parse(transcript: "")
            XCTFail("Expected ParseError.emptyTranscript")
        } catch ParseError.emptyTranscript {
            // expected
        }
    }

    func testWhitespaceOnlyThrows() async throws {
        let service = IntentParserService()
        do {
            _ = try await service.parse(transcript: "   ")
            XCTFail("Expected ParseError.emptyTranscript")
        } catch ParseError.emptyTranscript {
            // expected
        }
    }

    func testLongTranscriptDoesNotCrash() {
        let longText = String(repeating: "Buy something important and ", count: 50)
        let intent = parser.parse(transcript: longText)
        XCTAssertFalse(intent.title.isEmpty)
    }

    func testPunctuationHandled() {
        let intent = parser.parse(transcript: "Call Mom... tomorrow!!")
        XCTAssertFalse(intent.title.isEmpty)
        XCTAssertEqual(intent.detectedTaskType, .call)
    }

    func testSingleWordTranscript() {
        let intent = parser.parse(transcript: "Exercise")
        XCTAssertEqual(intent.type, .todo)
        XCTAssertFalse(intent.title.isEmpty)
    }

    func testAllCapsTitleHandled() {
        let intent = parser.parse(transcript: "BUY MILK")
        XCTAssertFalse(intent.title.isEmpty)
        XCTAssertEqual(intent.detectedTaskType, .purchase)
    }

    func testTranscriptWithNumbersHandled() {
        let intent = parser.parse(transcript: "Call back on 0207 123 4567 tomorrow")
        XCTAssertEqual(intent.detectedTaskType, .call)
        XCTAssertEqual(intent.type, .reminder)
    }

    func testMessageContextExtracted() {
        let intent = parser.parse(
            transcript: "Email my manager about the budget issue with the Q3 report"
        )
        XCTAssertNotNil(intent.messageContextNotes)
    }

    func testParseErrorDescriptionsNonNil() {
        let errors: [ParseError] = [
            .emptyTranscript,
            .claudeAPIError(.missingAPIKey),
            .claudeResponseMalformed("bad json")
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}
