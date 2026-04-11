import Foundation

/// The category of secondary action attached to a reminder.
/// Defined in the shared package so the widget can reference it via `WidgetReminderPreview.taskTypeRawValue`.
public enum AssociatedTaskType: String, Codable, CaseIterable, Sendable {
    /// Drafting a message — email, WhatsApp, Slack, or any platform.
    case message
    /// Buying or ordering something.
    case purchase
    /// A hard deadline with no specific action beyond awareness.
    case deadline
    /// Placing a phone or video call.
    case call
    /// Any other action type not covered above.
    case other

    public var displayName: String {
        switch self {
        case .message: return "Message"
        case .purchase: return "Purchase"
        case .deadline: return "Deadline"
        case .call: return "Call"
        case .other: return "Task"
        }
    }

    public var systemImageName: String {
        switch self {
        case .message: return "envelope"
        case .purchase: return "cart"
        case .deadline: return "calendar.badge.exclamationmark"
        case .call: return "phone"
        case .other: return "checkmark.circle"
        }
    }
}
