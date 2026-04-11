import Foundation

// MARK: - ParsedIntent

/// The structured output of `IntentParserService`.
/// Intermediate value — never persisted to SwiftData directly.
/// Consumed by `VoiceCaptureViewModel` to create `TodoItem` or `ReminderItem`.
public struct ParsedIntent: Sendable, Equatable {

    // MARK: - IntentType

    public enum IntentType: String, Sendable, Equatable {
        /// A task with no specific due date.
        case todo
        /// A time-bound reminder.
        case reminder
        /// Parser could not confidently determine the type.
        case ambiguous
    }

    // MARK: - Properties

    public var type: IntentType

    /// Confidence score from the parser. 0.0 – 1.0.
    public var confidence: Double

    /// Concise action title extracted from the transcript.
    public var title: String

    /// Supporting context notes beyond the title.
    public var notes: String?

    /// Parsed due date. `nil` if no date was detected.
    public var detectedDueDate: Date?

    /// Category of the secondary action, if detected.
    public var detectedTaskType: AssociatedTaskType?

    /// Organizational list category, auto-detected from dictation.
    public var detectedCategory: TaskCategory

    /// Workspace context, auto-detected from dictation.
    public var detectedWorkspace: Workspace

    /// Informal recipient hint (e.g. "my landlord", "Sarah").
    public var recipientHint: String?

    /// Detected messaging platform hint (e.g. "email", "whatsapp").
    public var platformHint: String?

    /// Raw context for message drafting.
    public var messageContextNotes: String?

    /// An optional subject line for message drafts (primarily email).
    public var messageSubject: String?

    /// A Claude-generated message body, if available.
    public var generatedMessageBody: String?

    /// Set when Claude was called but message body generation failed.
    /// Displayed as an error in the message body section of the result view.
    public var messageBodyError: String?

    // MARK: - Init

    public init(
        type: IntentType,
        confidence: Double,
        title: String,
        notes: String? = nil,
        detectedDueDate: Date? = nil,
        detectedTaskType: AssociatedTaskType? = nil,
        detectedCategory: TaskCategory = .task,
        detectedWorkspace: Workspace = .personal,
        recipientHint: String? = nil,
        platformHint: String? = nil,
        messageContextNotes: String? = nil,
        messageSubject: String? = nil,
        generatedMessageBody: String? = nil,
        messageBodyError: String? = nil
    ) {
        self.type = type
        self.confidence = confidence
        self.title = title
        self.notes = notes
        self.detectedDueDate = detectedDueDate
        self.detectedTaskType = detectedTaskType
        self.detectedCategory = detectedCategory
        self.detectedWorkspace = detectedWorkspace
        self.recipientHint = recipientHint
        self.platformHint = platformHint
        self.messageContextNotes = messageContextNotes
        self.messageSubject = messageSubject
        self.generatedMessageBody = generatedMessageBody
        self.messageBodyError = messageBodyError
    }

    // MARK: - Static Factories

    /// A blank intent used when the user taps "+" to create an item manually.
    public static var blank: ParsedIntent {
        ParsedIntent(type: .todo, confidence: 1.0, title: "")
    }

    // MARK: - Helpers

    public var isReadyToSave: Bool {
        switch type {
        case .todo: return true
        case .reminder: return detectedDueDate != nil
        case .ambiguous: return false
        }
    }
}
