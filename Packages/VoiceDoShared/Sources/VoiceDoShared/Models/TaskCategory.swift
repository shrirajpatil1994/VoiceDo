import Foundation

// MARK: - TaskCategory

/// Organizational category for todos and reminders.
/// Detected automatically from voice dictation; editable by user.
public enum TaskCategory: String, Codable, CaseIterable, Sendable {
    case grocery
    case task
    case deadline
    case call
    case message
    case other

    public var displayName: String {
        switch self {
        case .grocery: return "Groceries"
        case .task: return "Tasks"
        case .deadline: return "Deadlines"
        case .call: return "Calls"
        case .message: return "Messages"
        case .other: return "Other"
        }
    }

    public var systemImageName: String {
        switch self {
        case .grocery: return "cart"
        case .task: return "checklist"
        case .deadline: return "calendar.badge.exclamationmark"
        case .call: return "phone"
        case .message: return "envelope"
        case .other: return "tray"
        }
    }
}
