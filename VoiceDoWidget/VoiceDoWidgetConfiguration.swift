import AppIntents
import WidgetKit

// MARK: - WorkspaceOption

enum WorkspaceOption: String, AppEnum {
    case all
    case personal
    case work
    case home

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Workspace"
    static var caseDisplayRepresentations: [WorkspaceOption: DisplayRepresentation] = [
        .all:      "All",
        .personal: "Personal",
        .work:     "Work",
        .home:     "Home"
    ]

    var displayName: String {
        switch self {
        case .all:      return "All"
        case .personal: return "Personal"
        case .work:     return "Work"
        case .home:     return "Home"
        }
    }
}

// MARK: - Widget Configuration Intent

struct VoiceDoWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "VoiceDo Widget"
    static var description = IntentDescription("Choose which workspace to display.")

    @Parameter(title: "Workspace", default: .all)
    var workspace: WorkspaceOption
}
