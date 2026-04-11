import Foundation
import SwiftData

/// An AI-generated message draft attached to a reminder.
/// Covers any messaging platform: email, WhatsApp, Slack, SMS, etc.
/// In V1 there is no sending — the user copies the body manually.
@Model
final class MessageDraft {

    // MARK: - Stored Properties

    var id: UUID

    /// Informal recipient hint from dictation (e.g. "my landlord", "Sarah").
    /// Not a validated address — purely for display context.
    var recipientHint: String?

    /// Detected platform from dictation (e.g. "email", "whatsapp", "slack").
    /// `nil` if not detected.
    var platformHint: String?

    /// Optional subject line — relevant primarily for email.
    var subject: String?

    /// The AI-generated message body. This is the core output.
    var body: String

    /// The raw dictation context that was used to generate the body.
    var contextNotes: String

    /// When the draft was generated.
    var generatedAt: Date

    // MARK: - Init

    init(
        body: String,
        contextNotes: String,
        recipientHint: String? = nil,
        platformHint: String? = nil,
        subject: String? = nil
    ) {
        self.id = UUID()
        self.body = body
        self.contextNotes = contextNotes
        self.recipientHint = recipientHint
        self.platformHint = platformHint
        self.subject = subject
        self.generatedAt = Date()
    }

    // MARK: - Helpers

    /// A human-readable platform label for display in UI.
    var platformDisplayName: String {
        switch platformHint?.lowercased() {
        case "email": return "Email"
        case "whatsapp": return "WhatsApp"
        case "slack": return "Slack"
        case "sms", "text": return "SMS"
        case "imessage", "imsg": return "iMessage"
        default: return "Message"
        }
    }
}
