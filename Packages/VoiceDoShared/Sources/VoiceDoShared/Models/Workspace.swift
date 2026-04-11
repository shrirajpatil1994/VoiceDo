import Foundation

// MARK: - Workspace

/// High-level workspace / context for todos and reminders.
/// Detected automatically from voice dictation; editable by user.
public enum Workspace: String, Codable, CaseIterable, Sendable {
    case personal
    case work
    case home

    public var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .work: return "Work"
        case .home: return "Home"
        }
    }

    public var systemImageName: String {
        switch self {
        case .personal: return "person"
        case .work: return "briefcase"
        case .home: return "house"
        }
    }
}
